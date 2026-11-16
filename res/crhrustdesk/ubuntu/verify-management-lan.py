"""Verify HTTPS Management authorization without printing its password or token."""

import json
import ssl
import urllib.error
import urllib.request
from pathlib import Path


def main():
    base = 'https://172.16.1.83:21120'
    context = ssl.create_default_context(
        cafile='/var/lib/crhrustdesk/caddy/pki/authorities/local/root.crt')

    def post(action, body, token='', origin=base):
        request = urllib.request.Request(base + '/crhrustdesk/admin/' + action,
            data=json.dumps(body).encode(), headers={
                'Content-Type': 'application/json', 'Origin': origin,
                'Authorization': 'Bearer ' + token})
        try:
            with urllib.request.urlopen(request, context=context, timeout=10) as response:
                return response.status, json.loads(response.read(1024 * 1024))
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read(16384))

    password = Path('/etc/crhrustdesk/admin-initial-password').read_text().strip()
    status, data = post('login', {'username': 'admin', 'password': password})
    assert status == 200 and data.get('access_token'), 'Admin login failed; check whether the initial password changed'
    token = data['access_token']
    status, data = post('users', {'search': ''}, token)
    assert status == 200 and isinstance(data.get('users'), list)
    print('PASS: HTTPS admin login and account-list access with the configured Origin')
    status, _ = post('users', {'search': ''}, token, 'https://untrusted.invalid')
    assert status == 403
    print('PASS: untrusted Origin rejected even with a valid administrator token')
    status, _ = post('users', {'search': ''})
    assert status == 403
    print('PASS: anonymous access rejected')

    request = urllib.request.Request(base + '/api/admin/login',
        data=json.dumps({'username': 'admin', 'password': password, 'platform': 'verification'}).encode(),
        headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, context=context, timeout=10) as response:
        login = json.loads(response.read(16384))
    assert login.get('code') == 0 and login['data'].get('token'), 'Full admin login failed or requires captcha'
    admin_token = login['data']['token']
    for route in ('/user/current', '/user/list?page=1&pageSize=2',
                  '/login_log/list?page=1&pageSize=2'):
        request = urllib.request.Request(base + '/api/admin' + route,
            headers={'api-token': admin_token})
        with urllib.request.urlopen(request, context=context, timeout=10) as response:
            data = json.loads(response.read(1024 * 1024))
        assert data.get('code') == 0, route
    print('PASS: full Admin login, current user, user-management list and login logs')
    request = urllib.request.Request(base + '/api/admin/user/changeCurPwd', data=b'{}',
        headers={'api-token': admin_token, 'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, context=context, timeout=10) as response:
        data = json.loads(response.read(16384))
    assert data.get('code') == 101
    print('PASS: change-password endpoint validates required fields; no password changed')
    request = urllib.request.Request(base + '/api/admin/user/list?page=1&pageSize=2')
    with urllib.request.urlopen(request, context=context, timeout=10) as response:
        data = json.loads(response.read(16384))
    assert data.get('code') == 403
    print('PASS: full Admin user list requires authentication')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        raise SystemExit('Management HTTPS verification failed: ' + type(error).__name__) from None
