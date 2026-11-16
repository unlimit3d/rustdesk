"""Scan index blobs before commit, or all commit candidates without exposing secrets."""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath


def git(*args):
    return subprocess.check_output(['git', *args], stderr=subprocess.DEVNULL)


def forbidden_path(name):
    path = PurePosixPath(name.lower())
    base = path.name
    return (
        path.parts[0] in ('target', 'build', '.private', 'dev-server', 'update-signing')
        or path.as_posix() == 'res/crhrustdesk/ubuntu/api.yaml'
        or base in ('id_rsa', 'id_ed25519', 'permit.key', 'server-public-key.txt',
                    'permit-public-key.txt', 'update-public-key.xml', 'update-private-key.xml')
        or base.endswith(('.credential.xml', '.key', '.pem', '.pfx', '.p12', '.crt', '.cer', '.jks', '.keystore', '.env'))
        or (base.startswith('.env') and base != '.env.example')
    )


def scan(worktree=False, executable=None):
    root = Path(git('rev-parse', '--show-toplevel').decode().strip())
    if worktree:
        names = git('ls-files', '-z', '--cached', '--others', '--exclude-standard')
    else:
        names = git('diff', '--cached', '--name-only', '-z', '--diff-filter=ACMR')
    names = sorted(set(name for name in names.decode('utf-8').split('\0') if name))
    if not names:
        print('Secret check: no staged files')
        return 0
    if not executable:
        configured = subprocess.run(['git', 'config', '--get', 'crhrustdesk.gitleaksPath'], capture_output=True, text=True)
        executable = configured.stdout.strip() or shutil.which('gitleaks')
    if not executable or not Path(executable).is_file():
        print('Secret check blocked: configure a verified Gitleaks executable; see COMMIT-SAFETY-TH.md')
        return 2
    policy = json.loads((Path(__file__).parent / 'secret-scan-baseline.json').read_text())
    reviewed = {(item['path'], item['rule'], item['sha256']) for item in policy['findings']}
    findings = []
    local_policy = subprocess.run(['git', 'config', '--get', 'crhrustdesk.privateDenylist'], capture_output=True, text=True).stdout.strip()
    denied = json.loads(Path(local_policy).read_text()) if local_policy else {'identities': [], 'secrets': []}
    header = re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----')
    xml_key = re.compile(rb'<RSAKeyValue>[\s\S]{0,12000}<D>[^<]{64,}</D>')
    credential = re.compile(rb'<Objs\b[\s\S]{0,10000}(?:System\.Management\.Automation\.PSCredential|System\.Security\.SecureString)')
    with tempfile.TemporaryDirectory(prefix='crhrustdesk-secret-check-') as folder:
        snapshot = Path(folder)
        blobs = {}
        for name in names:
            path = root / name
            if worktree:
                if path.is_symlink():
                    data = os.readlink(path).encode('utf-8')
                elif path.is_file():
                    data = path.read_bytes()
                else:
                    continue
            else:
                mode = git('ls-files', '-s', '--', name).split(b' ', 1)[0]
                if mode == b'160000':
                    continue
                data = git('show', ':' + name)
            if forbidden_path(name):
                findings.append((name, 'credential/key/private-runtime filename'))
            decoded = data.decode('utf-16').encode('utf-8') if data.startswith((b'\xff\xfe', b'\xfe\xff')) else data
            if header.search(decoded) or xml_key.search(decoded) or credential.search(decoded):
                findings.append((name, 'private-key or serialized credential material'))
            identities = re.findall(rb'\b[A-Za-z][A-Za-z0-9_.-]{1,127}\b', decoded)
            tokens = re.findall(rb'[A-Za-z0-9_@+/.!$-]{6,}', decoded)
            if any(hashlib.sha256(token.lower()).hexdigest() in denied['identities'] for token in identities):
                findings.append((name, 'private deployment account identifier'))
            if any(hashlib.sha256(token).hexdigest() in denied['secrets'] for token in tokens):
                findings.append((name, 'private deployment credential or key'))
            relative = PurePosixPath(name)
            if relative.is_absolute() or '..' in relative.parts:
                raise ValueError('Unsafe Git path')
            destination = snapshot / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(decoded)
            blobs[name] = decoded
        report = snapshot / 'report.json'
        empty_ignore = snapshot / '.empty-gitleaks-ignore'
        empty_ignore.write_bytes(b'')
        result = subprocess.run([executable, 'dir', '.', '--no-banner', '--redact=100',
            '--ignore-gitleaks-allow', '--gitleaks-ignore-path', str(empty_ignore),
            '--config', str(Path(__file__).parent / 'gitleaks.toml'), '--max-archive-depth', '2',
            '--log-level', 'error', '--report-format', 'json', '--report-path', str(report)],
            cwd=snapshot, capture_output=True)
        if result.returncode not in (0, 1):
            print('Secret check blocked: Gitleaks failed; scanner output withheld')
            return 2
        ignored = 0
        for item in json.loads(report.read_text()) if report.exists() else []:
            name = item['File'].replace('\\', '/')
            if name.startswith('./'):
                name = name[2:]
            if name not in blobs:
                findings.append((name, item['RuleID']))
                continue
            span = b'\n'.join(blobs[name].splitlines()[item['StartLine'] - 1:item['EndLine']])
            fingerprint = (name, item['RuleID'], hashlib.sha256(span).hexdigest())
            if fingerprint in reviewed:
                ignored += 1
            else:
                findings.append((name, f"{item['RuleID']} at line {item['StartLine']}"))
    for path, reason in findings:
        print(f'BLOCKED: {path}: {reason}')
    print(f'Secret check: {len(blobs)} files, {len(findings)} findings, {ignored} exact reviewed examples')
    return 1 if findings else 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--staged', action='store_true')
    modes.add_argument('--worktree', action='store_true')
    parser.add_argument('--gitleaks')
    args = parser.parse_args()
    try:
        sys.exit(scan(args.worktree, args.gitleaks))
    except Exception as error:
        print('Secret check blocked: ' + type(error).__name__ + '; no secret values printed')
        sys.exit(2)
