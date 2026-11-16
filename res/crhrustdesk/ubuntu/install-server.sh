#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run with sudo' >&2; exit 1; }
staging="$(cd -- "$(dirname -- "$0")/.." && pwd)"
if [[ -e /opt/crhrustdesk ]]; then
    [[ ${1:-} == --resume-incomplete && ! -e /etc/systemd/system/crhrustdesk-api.service && ! -e /etc/crhrustdesk/jwt.env ]] || {
        echo 'Existing install: refusing to overwrite' >&2; exit 1;
    }
    cmp /opt/crhrustdesk/api/apimain "$staging/build/rustdesk-api/apimain"
fi
[[ -s /etc/crhrustdesk/ldap.env ]]
[[ -s "$staging/ubuntu/api.yaml" ]] || { echo 'Create private api.yaml from api.example.yaml and configure the AD identity first' >&2; exit 1; }
grep -qx API_BUILD_OK "$staging/build/api-build.log"
(cd "$staging/build/rustdesk-api" && sha256sum --check ../api-build.sha256)
id crhrustdesk &>/dev/null || useradd --system --home-dir /var/lib/crhrustdesk --shell /usr/sbin/nologin crhrustdesk
install -d -o root -g root -m 755 /opt/crhrustdesk/{bin,api,account-server}
install -d -o root -g crhrustdesk -m 750 /etc/crhrustdesk
install -d -o crhrustdesk -g crhrustdesk -m 700 /var/lib/crhrustdesk /var/lib/crhrustdesk/{api,log,transport,transport/x86_64,caddy}
install -o root -g root -m 755 "$staging/build/rustdesk-api/apimain" /opt/crhrustdesk/api/apimain
for asset in conf docs resources; do
    install -d -m 755 "/opt/crhrustdesk/api/$asset"
    cp -a "$staging/build/api-release/release/$asset/." "/opt/crhrustdesk/api/$asset/"
done
chown -R root:root /opt/crhrustdesk/api
chmod -R go-w /opt/crhrustdesk/api
install -o root -g root -m 644 "$staging/ubuntu/admin-hello.md" /opt/crhrustdesk/api/conf/admin/hello.html
[[ $(readlink /opt/crhrustdesk/api/data || true) == /var/lib/crhrustdesk/api ]] || ln -s /var/lib/crhrustdesk/api /opt/crhrustdesk/api/data
for name in hbbs hbbr; do
    install -o root -g root -m 755 "$staging/build/transport/amd64/$name" "/opt/crhrustdesk/bin/$name"
done
install -o root -g root -m 755 "$staging/build/caddy/caddy" /opt/crhrustdesk/bin/caddy
cp -a "$staging/account-server/." /opt/crhrustdesk/account-server/
chown -R root:root /opt/crhrustdesk/account-server
chmod -R go-w /opt/crhrustdesk/account-server
python3 -m venv /opt/crhrustdesk/permit-python
/opt/crhrustdesk/permit-python/bin/pip --disable-pip-version-check install -r /opt/crhrustdesk/account-server/requirements.txt
/opt/crhrustdesk/permit-python/bin/python - <<'PY'
import base64, json, os, pwd, secrets
from pathlib import Path
from nacl.signing import SigningKey
os.umask(0o077)
env = Path('/etc/crhrustdesk/jwt.env')
if not env.exists():
    env.write_text('RUSTDESK_API_JWT_KEY=' + secrets.token_hex(64) + '\n')
root = Path('/var/lib/crhrustdesk')
key_file = root / 'permit.key'
if not key_file.exists():
    key_file.write_bytes(bytes(SigningKey.generate()))
key = SigningKey(key_file.read_bytes())
(root / 'permit-public-key.txt').write_text(base64.b64encode(bytes(key.verify_key)).decode() + '\n')
policy = root / 'unattended-users.json'
if not policy.exists():
    policy.write_text(json.dumps({'allow_admin': True, 'users': {}}, indent=2) + '\n')
account = pwd.getpwnam('crhrustdesk')
for path in (key_file, root / 'permit-public-key.txt', policy):
    os.chown(path, account.pw_uid, account.pw_gid)
PY
install -d -o root -g root -m 755 /opt/crhrustdesk/downloads
for asset in index.html style.css app.js; do
    install -o root -g root -m 644 "$staging/ubuntu/downloads/$asset" "/opt/crhrustdesk/downloads/$asset"
done
for name in api.yaml Caddyfile; do
    install -o root -g root -m 644 "$staging/ubuntu/$name" "/etc/crhrustdesk/$name"
done
for unit in "$staging"/ubuntu/crhrustdesk-*.service; do
    install -o root -g root -m 644 "$unit" /etc/systemd/system/
done
systemctl daemon-reload
echo 'INSTALL_OK: services remain stopped; bootstrap admin before starting proxy'
