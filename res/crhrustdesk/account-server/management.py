"""Local administrator UI for username-to-device grants."""

import json
import os
import re
import threading
import urllib.error
import urllib.parse
import urllib.request

_policy_writer = threading.Lock()


def api_call(service, path, body=None, token=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['api-token'] = token
    request = urllib.request.Request(service.api_url + path,
        data=None if body is None else json.dumps(body).encode('utf-8'), headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return json.loads(response.read(1024 * 1024))
    except urllib.error.HTTPError as error:
        raise PermissionError('Account service rejected the request') from error


def handle(service, route, bearer, body):
    if route == '/crhrustdesk/admin/login':
        login = api_call(service, '/api/login', {
            'username': body.get('username', ''), 'password': body.get('password', ''),
            'type': 'account', 'id': 'crhrustdesk-management', 'uuid': 'crhrustdesk-management',
        })
        token = login.get('access_token', '')
        user = service.current_user('Bearer ' + token)
        if user.get('is_admin') is not True:
            raise PermissionError('Administrator account required')
        return {'access_token': token, 'name': user['name']}

    user = service.current_user(bearer)
    if user.get('is_admin') is not True:
        raise PermissionError('Administrator account required')
    policy_file = service.root / 'unattended-users.json'
    if route == '/crhrustdesk/admin/users':
        query = str(body.get('search', ''))[:128]
        params = urllib.parse.urlencode({'page': 1, 'page_size': 100, 'username': query})
        result = api_call(service, '/api/admin/user/list?' + params, token=bearer[7:])
        if result.get('code') != 0:
            raise PermissionError('Cannot read the account list')
        policy = json.loads(policy_file.read_text(encoding='utf-8-sig'))
        accounts = [{
            'username': item['username'], 'nickname': item.get('nickname', ''),
            'is_admin': item.get('is_admin') is True,
            'devices': policy.get('users', {}).get(item['username'], []),
        } for item in result.get('data', {}).get('list', [])]
        return {'users': accounts, 'allow_admin': policy.get('allow_admin') is True}

    if route != '/crhrustdesk/admin/grant':
        raise ValueError('Unknown management endpoint')
    username = body.get('username', '')
    if not isinstance(username, str) or not username.strip() or len(username) > 128 or any(ord(c) < 32 for c in username):
        raise ValueError('Enter a valid AD or local username')
    username = username.strip()
    devices = body.get('devices', [])
    if not isinstance(devices, list) or len(devices) > 1000:
        raise ValueError('Invalid device list')
    for device in devices:
        if not isinstance(device, str) or not re.fullmatch(r'\*|[0-9]{6,20}', device):
            raise ValueError('Use device IDs or select all devices')
    with _policy_writer:
        policy = json.loads(policy_file.read_text(encoding='utf-8-sig'))
        if devices:
            policy.setdefault('users', {})[username] = sorted(set(devices))
        else:
            policy.setdefault('users', {}).pop(username, None)
        temporary = policy_file.with_suffix('.json.new')
        temporary.write_text(json.dumps(policy, ensure_ascii=False, indent=2), encoding='utf-8')
        os.replace(temporary, policy_file)
    return {'username': username, 'devices': devices, 'saved': True}
