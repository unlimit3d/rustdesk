"""Set a private initial password on a fresh, stopped production API only."""

import crypt
import os
import secrets
import sqlite3
from pathlib import Path


def main():
    if os.geteuid() != 0:
        raise SystemExit('Run as root')
    secret = Path('/etc/crhrustdesk/admin-initial-password')
    if secret.exists():
        raise SystemExit('Admin password already provisioned; no changes made')
    db = Path('/var/lib/crhrustdesk/api/rustdeskapi.db')
    password = secrets.token_urlsafe(24)
    salt = crypt.mksalt(crypt.METHOD_BLOWFISH, rounds=1024)
    hashed = crypt.crypt(password, salt)
    if not hashed or not hashed.startswith(('$2a$', '$2b$', '$2y$')):
        raise SystemExit('bcrypt is unavailable')
    with sqlite3.connect(db.as_uri() + '?mode=rw', uri=True) as connection:
        users = connection.execute('SELECT id, username FROM users').fetchall()
        if users != [(1, 'admin')]:
            raise SystemExit('Refusing to reset credentials in a populated database')
        fd = os.open(secret, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as stream:
            stream.write(password + '\n')
        connection.execute('UPDATE users SET password=? WHERE id=1 AND username=?', (hashed, 'admin'))
    print('ADMIN_BOOTSTRAP_OK: password saved in root-only file; not displayed')


if __name__ == '__main__':
    main()
