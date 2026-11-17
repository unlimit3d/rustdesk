import base64
import json
import tempfile
import time
import unittest
from contextlib import closing
from pathlib import Path
from types import SimpleNamespace

from nacl.signing import SigningKey

import inventory
import management


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.key = SigningKey.generate()
        self.public_key = base64.b64encode(self.key.verify_key.encode()).decode('ascii')
        self.service = SimpleNamespace(root=self.root, registered_key=lambda _: self.public_key,
            current_user=lambda _: {'name': 'admin', 'is_admin': True, 'status': 1})
        self.payload = {'domain': 'crhrustdesk-inventory-v1', 'machine_id': 'ab' * 32,
            'id': '123456789', 'hostname': 'dev-pc', 'role': 'incoming',
            'version': '1.5.4', 'revision': 202611170001, 'reported_at': int(time.time())}

    def body(self, **changes):
        return {'public_key': self.public_key, 'report': base64.b64encode(
            self.key.sign(json.dumps(dict(self.payload, **changes)).encode())).decode('ascii')}

    def test_update_reuses_machine_and_replay_does_not_extend_online_status(self):
        inventory.report(self.service, '', self.body(reported_at=self.payload['reported_at'] - 2))
        inventory.report(self.service, '', self.body(id='987654321', revision=202611170002))
        with closing(inventory.connect(self.root)) as conn, conn:
            conn.execute('UPDATE installation SET last_seen = ?', (int(time.time()) - 181,))
        inventory.report(self.service, '', self.body())
        result = inventory.overview(self.root)
        self.assertEqual((result['total'], result['online'], result['incoming']), (1, 0, 1))
        self.assertEqual(result['devices'][0]['revision'], 202611170002)
        self.assertEqual(result['devices'][0]['id'], '987654321')

    def test_unsigned_unregistered_and_expired_devices_cannot_enroll(self):
        body = self.body()
        body['report'] = base64.b64encode(bytes(64) + b'{}').decode('ascii')
        with self.assertRaises(PermissionError):
            inventory.report(self.service, '', body)
        self.service.registered_key = lambda _: base64.b64encode(bytes(32)).decode('ascii')
        with self.assertRaises(PermissionError):
            inventory.report(self.service, '', self.body())
        with self.assertRaises(ValueError):
            inventory.report(self.service, '', self.body(reported_at=int(time.time()) - 121))
        self.assertEqual(inventory.overview(self.root)['total'], 0)

    def test_operator_enrolls_with_account_but_only_admin_can_read_inventory(self):
        self.service.current_user = lambda _: {'name': 'operator', 'is_admin': False, 'status': 1}
        inventory.report(self.service, 'Bearer test', self.body(role='outgoing'))
        with self.assertRaises(PermissionError):
            management.handle(self.service, '/crhrustdesk/admin/inventory', 'Bearer test', {})
        result = inventory.overview(self.root)
        self.assertEqual((result['total'], result['online'], result['outgoing']), (1, 1, 1))


if __name__ == '__main__':
    unittest.main()
