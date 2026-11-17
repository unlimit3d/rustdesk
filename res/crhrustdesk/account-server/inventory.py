"""Signed installation reports, separate from session authorization and policy."""

import base64
import json
import re
import sqlite3
import time
from contextlib import closing

from nacl.exceptions import BadSignatureError
from nacl.signing import VerifyKey

ONLINE_SECONDS = 180


def connect(root):
    conn = sqlite3.connect(root / 'client-inventory.sqlite3', timeout=5)
    conn.row_factory = sqlite3.Row
    conn.execute('''CREATE TABLE IF NOT EXISTS installation (
        machine_id TEXT PRIMARY KEY, public_key TEXT NOT NULL,
        id TEXT NOT NULL, hostname TEXT NOT NULL, role TEXT NOT NULL,
        version TEXT NOT NULL, revision INTEGER NOT NULL,
        first_seen INTEGER NOT NULL, last_seen INTEGER NOT NULL,
        reported_at INTEGER NOT NULL)''')
    return conn


def report(service, bearer, body):
    try:
        public_key = base64.b64decode(body['public_key'], validate=True)
        signed = base64.b64decode(body['report'], validate=True)
        payload = json.loads(VerifyKey(public_key).verify(signed))
    except (KeyError, ValueError, TypeError, BadSignatureError) as error:
        raise PermissionError('Invalid device signature') from error
    if not isinstance(payload, dict) or payload.get('domain') != 'crhrustdesk-inventory-v1':
        raise ValueError('Invalid inventory report')
    machine_id = payload.get('machine_id')
    if not isinstance(machine_id, str) or not re.fullmatch('[0-9a-f]{64}', machine_id):
        raise ValueError('Invalid machine identity')
    device_id = payload.get('id')
    if not isinstance(device_id, str) or not re.fullmatch('[0-9]{6,20}', device_id):
        raise ValueError('Invalid device ID')
    for key in ('hostname', 'version'):
        value = payload.get(key)
        if not isinstance(value, str) or not 0 < len(value) <= 256 or any(ord(c) < 32 for c in value):
            raise ValueError('Invalid device metadata')
    if payload.get('role') not in ('incoming', 'outgoing'):
        raise ValueError('Invalid installation role')
    now = int(time.time())
    reported_at = payload.get('reported_at')
    revision = payload.get('revision')
    if type(reported_at) is not int or abs(now - reported_at) > 120:
        raise ValueError('Report expired; synchronize the device clock')
    if type(revision) is not int or not 0 < revision <= 9223372036854775807:
        raise ValueError('Invalid release revision')
    encoded_key = base64.b64encode(public_key).decode('ascii')
    with closing(connect(service.root)) as conn, conn:
        existing = conn.execute('SELECT public_key FROM installation WHERE machine_id = ?',
                                (machine_id,)).fetchone()
        if existing:
            if existing['public_key'] != encoded_key:
                raise PermissionError('Installation signing key changed; administrator review required')
        elif payload['role'] == 'incoming':
            if service.registered_key(device_id) != encoded_key:
                raise PermissionError('Device does not match its registered key')
        else:
            service.current_user(bearer)
        conn.execute('''INSERT INTO installation VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(machine_id) DO UPDATE SET
                id=excluded.id, hostname=excluded.hostname, role=excluded.role,
                version=excluded.version, revision=excluded.revision,
                last_seen=excluded.last_seen, reported_at=excluded.reported_at
            WHERE excluded.reported_at > installation.reported_at''',
            (machine_id, encoded_key, device_id, payload['hostname'], payload['role'],
             payload['version'], revision, now, now, reported_at))
    return {'registered': True}


def overview(root):
    now = int(time.time())
    with closing(connect(root)) as conn:
        rows = conn.execute('''SELECT machine_id, id, hostname, role, version, revision,
            first_seen, last_seen FROM installation ORDER BY last_seen DESC, machine_id''').fetchall()
    devices = [dict(row, online=now - row['last_seen'] <= ONLINE_SECONDS) for row in rows]
    return {'total': len(devices), 'online': sum(device['online'] for device in devices),
            'incoming': sum(device['role'] == 'incoming' for device in devices),
            'outgoing': sum(device['role'] == 'outgoing' for device in devices),
            'online_seconds': ONLINE_SECONDS, 'devices': devices}
