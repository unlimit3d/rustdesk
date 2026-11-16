import os
from pathlib import Path
import secrets
import string
import subprocess
import sys
import tempfile
import unittest


class GitSecretChecks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='crh-secret-test-')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.scanner = Path(__file__).resolve().parents[1] / 'Check-GitSecrets.py'
        self.tool = os.environ['CRH_GITLEAKS']
        self.git('init', '-q')

    def git(self, *args):
        subprocess.run(['git', *args], cwd=self.root, check=True, capture_output=True)

    def check(self):
        return subprocess.run([sys.executable, str(self.scanner), '--staged', '--gitleaks', self.tool],
                              cwd=self.root, capture_output=True).returncode

    def test_clean_staged_file_passes(self):
        (self.root / 'readme.txt').write_text('No credentials here.\n')
        self.git('add', 'readme.txt')
        self.assertEqual(self.check(), 0)

    def test_staged_secret_is_blocked_even_when_worktree_is_clean(self):
        value = 'gh' + 'p_' + ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(36))
        (self.root / 'example.txt').write_text('access_token=' + value)
        self.git('add', 'example.txt')
        (self.root / 'example.txt').write_text('Unstaged cleanup does not fix the index.\n')
        self.assertEqual(self.check(), 1)

    def test_credential_filename_is_blocked_even_when_empty(self):
        (self.root / 'sample.credential.xml').write_text('')
        self.git('add', 'sample.credential.xml')
        self.assertEqual(self.check(), 1)


if __name__ == '__main__':
    unittest.main()
