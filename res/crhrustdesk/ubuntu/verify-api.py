"""Check production auth without printing credentials or tokens."""

import json
import argparse
import os
import urllib.error
import urllib.request
from pathlib import Path


def request(port, path, body=None, bearer=None):
    headers = {'Content-Type': 'application/json'}
    if bearer:
        headers['Authorization'] = 'Bearer ' + bearer
    req = urllib.request.Request('http://127.0.0.1:' + str(port) + path,
        data=None if body is None else json.dumps(body).encode(), headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            return response.status, json.loads(response.read(1024 * 1024))
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read(16384))


def login(name, password):
    status, body = request(21114, '/api/login', {
        'username': name, 'password': password, 'type': 'account',
        'id': 'crhrustdesk-deployment-check', 'uuid': 'crhrustdesk-deployment-check'})
    if status != 200 or not body.get('access_token'):
        raise RuntimeError('Login failed for ' + name + ' (HTTP ' + str(status) + ')')
    return body['access_token']


def main(ad_user):
    if os.geteuid() != 0:
        raise SystemExit('Run as root')
    password = Path('/etc/crhrustdesk/admin-initial-password').read_text().strip()
    admin = login('admin', password)
    status, info = request(21114, '/api/user/info', bearer=admin)
    assert status == 200 and info['is_admin'] is True and info['name'] == 'admin'
    print('PASS: local recovery admin login')
    lines = Path('/etc/crhrustdesk/ldap.env').read_text().splitlines()
    value = next(line.split('=', 1)[1] for line in lines
                 if line.startswith('RUSTDESK_API_LDAP_BIND_PASSWORD='))
    ad_token = login(ad_user, json.loads(value))
    status, info = request(21114, '/api/user/info', bearer=ad_token)
    assert status == 200 and info['name'] == ad_user and info['is_admin'] is False
    print('PASS: real AD login and token account validation; no admin privilege')
    status, result = request(21120, '/crhrustdesk/admin/users', {'search': ''}, admin)
    assert status == 200 and isinstance(result.get('users'), list)
    print('PASS: administrator can read Management')
    status, _ = request(21120, '/crhrustdesk/admin/users', {'search': ''}, ad_token)
    assert status == 403
    print('PASS: ordinary AD account denied Management access')
    status, _ = request(21114, '/api/user/info', bearer='fabricated.invalid.token')
    assert status == 401
    status, _ = request(21120, '/crhrustdesk/permit', {'target': '123456'})
    assert status == 403
    print('PASS: forged token and anonymous permit requests denied')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--ad-user', required=True)
    args = parser.parse_args()
    try:
        main(args.ad_user)
    except Exception as error:
        raise SystemExit('API verification failed: ' + type(error).__name__) from None
