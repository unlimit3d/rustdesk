"""Loopback-only session permits; publish through the existing HTTPS proxy."""

import argparse
import base64
import json
import re
import sqlite3
import time
import urllib.error
import urllib.request
from contextlib import closing
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from nacl.signing import SigningKey
import management
import inventory


class AuthorizationError(Exception):
    pass


class PermitService:
    def __init__(self, root, api_url):
        self.root = Path(root)
        self.api_url = api_url.rstrip('/')
        self.key = SigningKey((self.root / 'permit.key').read_bytes())

    def current_user(self, bearer):
        if not bearer.startswith('Bearer ') or len(bearer) > 8192:
            raise AuthorizationError('Login required')
        req = urllib.request.Request(self.api_url + '/api/user/info',
                                     headers={'Authorization': bearer})
        try:
            with urllib.request.urlopen(req, timeout=5) as response:
                user = json.loads(response.read(16384))
        except (urllib.error.URLError, ValueError) as error:
            raise AuthorizationError('Account verification failed') from error
        if not user.get('name') or user.get('status') != 1:
            raise AuthorizationError('Account is disabled or invalid')
        return user

    def registered_key(self, device_id):
        if not isinstance(device_id, str) or not re.fullmatch(r'[0-9]{6,20}', device_id):
            raise AuthorizationError('Invalid device ID')
        db = self.root / 'transport/x86_64/db_v2.sqlite3'
        with closing(sqlite3.connect(db.as_uri() + '?mode=ro', uri=True, timeout=2)) as conn:
            row = conn.execute('SELECT pk FROM peer WHERE id = ?', (device_id,)).fetchone()
        if row is None or len(row[0]) != 32:
            raise AuthorizationError('Device is not registered')
        return base64.b64encode(row[0]).decode('ascii')

    def handle(self, route, bearer, body):
        if route == '/crhrustdesk/inventory':
            return inventory.report(self, bearer, body)
        user = self.current_user(bearer)
        target = body.get('target', '')
        public_key = self.registered_key(target)
        if route == '/crhrustdesk/identity':
            return {'id': target, 'public_key': public_key}
        if route != '/crhrustdesk/permit':
            raise AuthorizationError('Unknown endpoint')
        scope = body.get('scope', 'desktop')
        if scope not in ('desktop', 'file_transfer'):
            raise AuthorizationError('Unsupported session scope')
        nonce = body.get('nonce', '')
        controller = body.get('controller', '')
        if not isinstance(nonce, str) or not re.fullmatch(r'[0-9a-f]{64}', nonce):
            raise AuthorizationError('Invalid connection nonce')
        if not isinstance(controller, str) or not re.fullmatch(r'[0-9]{6,20}', controller):
            raise AuthorizationError('Invalid controller ID')
        policy = json.loads((self.root / 'unattended-users.json').read_text(encoding='utf-8-sig'))
        grants = policy.get('users', {}).get(user['name'], [])
        admin_granted = policy.get('allow_admin') is True and user.get('is_admin') is True
        if not admin_granted and target not in grants and '*' not in grants:
            raise AuthorizationError('This account requires local approval')
        payload = json.dumps({
            'domain': 'crhrustdesk-desktop-v1', 'name': user['name'],
            'target': target, 'controller': controller, 'nonce': nonce,
            'target_public_key': public_key,
            'scope': scope, 'expires': int(time.time()) + 60,
        }, separators=(',', ':')).encode('utf-8')
        return {'permit': base64.b64encode(self.key.sign(payload)).decode('ascii')}


def serve(root, api_url, port, management_origin=None):
    service = PermitService(root, api_url)

    class Handler(BaseHTTPRequestHandler):
        def local_management_request(self):
            hosts = ('127.0.0.1:' + str(self.server.server_port),
                     'localhost:' + str(self.server.server_port))
            origin = self.headers.get('Origin')
            return self.headers.get('Host') in hosts and (
                origin is None or origin in tuple('http://' + host for host in hosts)
                or (management_origin is not None and origin == management_origin))

        def do_GET(self):
            if not self.local_management_request():
                self.send_error(403)
                return
            assets = {'/_admin/': ('index.html', 'text/html; charset=utf-8'),
                      '/_admin/app.js': ('app.js', 'text/javascript; charset=utf-8'),
                      '/_permissions/': ('index.html', 'text/html; charset=utf-8'),
                      '/_permissions/app.js': ('app.js', 'text/javascript; charset=utf-8')}
            item = assets.get(self.path)
            if item is None:
                self.send_error(404)
                return
            raw = (Path(__file__).parent / 'management' / item[0]).read_bytes()
            self.send_response(200)
            self.send_header('Content-Type', item[1])
            self.send_header('Content-Length', str(len(raw)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Frame-Options', 'DENY')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'")
            self.end_headers()
            self.wfile.write(raw)

        def do_POST(self):
            try:
                if self.path.startswith('/crhrustdesk/admin/') and not self.local_management_request():
                    self.reply(403, {'error': 'Use the loopback management console'})
                    return
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= 16384:
                    self.send_error(413)
                    return
                body = json.loads(self.rfile.read(length))
                if not isinstance(body, dict):
                    raise ValueError('Expected object')
                if self.path.startswith('/crhrustdesk/admin/'):
                    result = management.handle(service, self.path, self.headers.get('Authorization', ''), body)
                else:
                    result = service.handle(self.path, self.headers.get('Authorization', ''), body)
                self.reply(200, result)
            except AuthorizationError as error:
                self.reply(403, {'error': str(error)})
            except PermissionError as error:
                self.reply(403, {'error': str(error)})
            except (ValueError, TypeError):
                self.reply(400, {'error': 'Invalid request'})
            except (OSError, sqlite3.Error):
                self.reply(503, {'error': 'Authorization service unavailable'})

        def reply(self, status, data):
            raw = json.dumps(data).encode('utf-8')
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def log_message(self, format, *args):
            # Never record request headers, bearer tokens or permits.
            print('%s %s' % (self.log_date_time_string(), format % args), flush=True)

    server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    server.daemon_threads = True
    server.serve_forever()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', required=True)
    parser.add_argument('--api-url', default='http://127.0.0.1:21114')
    parser.add_argument('--port', type=int, default=21120)
    parser.add_argument('--management-origin', choices=['https://172.16.1.83:21120'])
    parser.add_argument('--initialize', action='store_true')
    args = parser.parse_args()
    if args.initialize:
        root = Path(args.root)
        root.mkdir(parents=True, exist_ok=True)
        key_file = root / 'permit.key'
        if not key_file.exists():
            with key_file.open('xb') as file:
                file.write(SigningKey.generate().encode())
        key = SigningKey(key_file.read_bytes())
        (root / 'permit-public-key.txt').write_text(
            base64.b64encode(key.verify_key.encode()).decode('ascii'), encoding='ascii')
        policy_file = root / 'unattended-users.json'
        if not policy_file.exists():
            policy_file.write_text(json.dumps({'allow_admin': True, 'users': {}}, indent=2),
                                   encoding='utf-8')
    else:
        serve(args.root, args.api_url, args.port, args.management_origin)
