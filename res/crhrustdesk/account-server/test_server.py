"""Run against the real dev account API using tokens supplied in the environment."""

import base64
import json
import os
import sqlite3
import tempfile
import unittest
from contextlib import closing
from pathlib import Path

from nacl.signing import SigningKey
from server import AuthorizationError, PermitService


class AccountAccessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'permit.key').write_bytes(SigningKey.generate().encode())
        db = self.root / 'transport/x86_64/db_v2.sqlite3'
        db.parent.mkdir(parents=True)
        with closing(sqlite3.connect(db)) as conn:
            conn.execute('CREATE TABLE peer (id TEXT, pk BLOB)')
            conn.execute('INSERT INTO peer VALUES (?, ?)', ('123456789', bytes([42]) * 32))
            conn.commit()
        self.policy = {'allow_admin': True, 'users': {'test_operator': ['123456789']}}
        self.write_policy()
        self.service = PermitService(self.root, 'http://127.0.0.1:21114')
        self.body = {'target': '123456789', 'controller': '987654321', 'nonce': 'ab' * 32}

    def write_policy(self):
        (self.root / 'unattended-users.json').write_text(json.dumps(self.policy), encoding='utf-8')

    def token(self, role):
        return 'Bearer ' + os.environ['CRH_TEST_' + role + '_TOKEN']

    def test_live_allowed_user_gets_scoped_signed_permit(self):
        for role, name in [('USER', 'test_operator')]:
            result = self.service.handle('/crhrustdesk/permit', self.token(role), self.body)
            payload = self.service.key.verify_key.verify(base64.b64decode(result['permit']))
            permit = json.loads(payload)
            self.assertEqual((permit['name'], permit['target'], permit['nonce'], permit['scope']),
                             (name, self.body['target'], self.body['nonce'], 'desktop'))
            self.assertEqual(base64.b64decode(permit['target_public_key']), bytes([42]) * 32)

    def test_policy_removal_takes_effect_without_client_rebuild(self):
        self.policy['users'] = {}
        self.write_policy()
        with self.assertRaises(AuthorizationError):
            self.service.handle('/crhrustdesk/permit', self.token('USER'), self.body)
        self.service.current_user = lambda _: {'name': 'admin', 'is_admin': False, 'status': 1}
        with self.assertRaises(AuthorizationError):
            self.service.handle('/crhrustdesk/permit', 'test', self.body)
        self.service.current_user = lambda _: {'name': 'administrator', 'is_admin': True, 'status': 1}
        self.assertIn('permit', self.service.handle('/crhrustdesk/permit', 'test', self.body))

    def test_no_token_and_forged_token_are_denied(self):
        for token in ['', 'Bearer fabricated.invalid.token']:
            with self.assertRaises(AuthorizationError):
                self.service.handle('/crhrustdesk/permit', token, self.body)

    def test_file_transfer_permit_is_scoped_and_requires_a_grant(self):
        self.service.current_user = lambda _: {'name': 'test_operator', 'is_admin': False, 'status': 1}
        body = dict(self.body, scope='file_transfer')
        result = self.service.handle('/crhrustdesk/permit', 'Bearer test', body)
        payload = self.service.key.verify_key.verify(base64.b64decode(result['permit']))
        self.assertEqual(json.loads(payload)['scope'], 'file_transfer')
        with self.assertRaises(AuthorizationError):
            self.service.handle('/crhrustdesk/permit', 'Bearer test', dict(body, scope='terminal'))
        self.policy['users'] = {}
        self.write_policy()
        with self.assertRaises(AuthorizationError):
            self.service.handle('/crhrustdesk/permit', 'Bearer test', body)


if __name__ == '__main__':
    unittest.main()
