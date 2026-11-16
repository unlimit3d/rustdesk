import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import management


class ManagementTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.policy = self.root / 'unattended-users.json'
        self.policy.write_text(json.dumps({'allow_admin': True, 'users': {'test_operator': ['*']}}))
        self.service = SimpleNamespace(root=self.root, current_user=lambda _: {
            'name': 'admin', 'is_admin': True, 'status': 1,
        })

    def test_user_without_admin_role_cannot_change_grants(self):
        self.service.current_user = lambda _: {'name': 'somchai', 'is_admin': False, 'status': 1}
        with self.assertRaises(PermissionError):
            management.handle(self.service, '/crhrustdesk/admin/grant', 'Bearer test',
                              {'username': 'somchai', 'devices': ['*']})

    def test_admin_can_grant_specific_devices_and_revoke_username(self):
        body = {'username': 'somchai', 'devices': ['262799361']}
        result = management.handle(self.service, '/crhrustdesk/admin/grant', 'Bearer test', body)
        self.assertEqual(result['devices'], ['262799361'])
        self.assertEqual(json.loads(self.policy.read_text())['users']['somchai'], ['262799361'])
        body['devices'] = []
        management.handle(self.service, '/crhrustdesk/admin/grant', 'Bearer test', body)
        self.assertNotIn('somchai', json.loads(self.policy.read_text())['users'])
        self.assertEqual(json.loads(self.policy.read_text())['users']['test_operator'], ['*'])

    def test_invalid_device_permissions_are_rejected(self):
        with self.assertRaises(ValueError):
            management.handle(self.service, '/crhrustdesk/admin/grant', 'Bearer test',
                              {'username': 'somchai', 'devices': ['172.29.0.52']})


if __name__ == '__main__':
    unittest.main()
