"""Install public, signed update files; signing keys stay off the server."""

import base64
import fcntl
import hashlib
import json
import os
import shutil
import sys
from pathlib import Path


def install(source):
    if os.geteuid() != 0:
        raise SystemExit('Run with sudo')
    source = Path(source).resolve(strict=True)
    envelope_path = source / 'latest.json'
    if envelope_path.is_symlink() or envelope_path.stat().st_size > 32768:
        raise SystemExit('Invalid update envelope file')
    envelope_bytes = envelope_path.read_bytes()
    envelope = json.loads(envelope_bytes)
    payload = json.loads(base64.b64decode(envelope['payload'], validate=True))
    signature = base64.b64decode(envelope['signature'], validate=True)
    revision = payload['revision']
    if type(revision) is not int or revision <= 0 or payload['product'] != 'CrhRustDesk' or payload['platform'] != 'windows-x64' or len(signature) < 384:
        raise SystemExit('Invalid update release metadata')
    expected_url = f'https://172.16.1.83:8443/crhrustdesk/updates/releases/{revision}/CrhRustDesk-Setup.exe'
    if payload['url'] != expected_url or not 0 < payload['size'] <= 536870912:
        raise SystemExit('Invalid update URL or size')
    setup = source / 'releases' / str(revision) / 'CrhRustDesk-Setup.exe'
    if setup.is_symlink() or setup.resolve(strict=True).parent != (source / 'releases' / str(revision)).resolve(strict=True):
        raise SystemExit('Invalid installer source')
    root = Path('/var/lib/crhrustdesk/updates')
    root.mkdir(mode=0o755, exist_ok=True)
    publish_lock = (root / '.publish.lock').open('a')
    fcntl.flock(publish_lock, fcntl.LOCK_EX)
    latest = root / 'latest.json'
    if latest.exists():
        previous = json.loads(base64.b64decode(json.loads(latest.read_bytes())['payload']))
        if revision <= previous['revision']:
            raise SystemExit('Publish a revision greater than the current release')
    destination = root / 'releases' / str(revision)
    if destination.exists():
        raise SystemExit('Revision directory already exists; use a new revision')
    destination.mkdir(mode=0o755, parents=True)
    staged = destination / 'CrhRustDesk-Setup.exe.part'
    digest = hashlib.sha256()
    total = 0
    with setup.open('rb') as input_file, staged.open('xb') as output_file:
        while chunk := input_file.read(65536):
            total += len(chunk)
            if total > payload['size']:
                raise SystemExit('Installer exceeds declared size')
            digest.update(chunk)
            output_file.write(chunk)
    if total != payload['size'] or digest.hexdigest() != payload['sha256']:
        raise SystemExit('Installer size or hash mismatch; latest release was left unchanged')
    staged.chmod(0o644)
    staged.rename(destination / 'CrhRustDesk-Setup.exe')
    new_latest = root / 'latest.json.new'
    with new_latest.open('wb') as output_file:
        output_file.write(envelope_bytes)
        output_file.flush()
        os.fsync(output_file.fileno())
    new_latest.chmod(0o644)
    os.replace(new_latest, latest)
    publish_lock.close()
    print(f'Published revision {revision}. Clients verify the RSA signature before installation.')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: sudo python3 -B install-update-release.py PUBLIC_RELEASE_DIRECTORY')
    install(sys.argv[1])
