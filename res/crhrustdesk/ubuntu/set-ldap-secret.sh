#!/usr/bin/env bash
set -euo pipefail
if [[ ${EUID} -ne 0 ]]; then
    exec sudo bash "$0"
fi
umask 077
if [[ -e /etc/crhrustdesk/ldap.env ]]; then
    printf '%s\n' 'ldap.env already exists. Its password was left unchanged.'
    exit 1
fi
if [[ ! -d /etc/crhrustdesk ]]; then
    install -d -m 0700 /etc/crhrustdesk
fi
read -r -s -p 'AD bind password for the account in private api.yaml: ' crh_ldap_password </dev/tty
printf '\n'
if [[ -z ${crh_ldap_password} ]]; then
    printf '%s\n' 'Empty AD password was not saved.' >&2
    exit 1
fi
CRH_LDAP_PASSWORD="${crh_ldap_password}" python3 -B - <<'PY'
import json
import os
from pathlib import Path
path = Path('/etc/crhrustdesk/ldap.env')
with path.open('x', encoding='utf-8') as output:
    output.write('RUSTDESK_API_LDAP_BIND_PASSWORD=' +
                 json.dumps(os.environ['CRH_LDAP_PASSWORD'], ensure_ascii=False) + '\n')
os.chmod(path, 0o600)
PY
unset crh_ldap_password
printf '%s\n' 'Saved the AD bind password in /etc/crhrustdesk/ldap.env (root only). No service was started.'
