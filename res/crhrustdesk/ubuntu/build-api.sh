#!/usr/bin/env bash
set -euo pipefail
staging="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$staging/build/rustdesk-api"
python3 - <<'PY'
from pathlib import Path
for name in ('service/user.go', 'http/middleware/rustauth.go'):
    path = Path(name)
    path.write_text(path.read_text(), newline='\n')
PY
if ! grep -q 'Config.Ldap.Enable && !strings.EqualFold(username, "admin")' service/user.go; then
    patch --forward -p1 < "$staging/patches/rustdesk-api-ad-strict.patch"
fi
grep -q 'Config.Ldap.Enable && !strings.EqualFold(username, "admin")' service/user.go
grep -q 'GetUserInfoByUsernameLdap(user.Username)' http/middleware/rustauth.go
if grep -q 'Fallback to local database' service/user.go; then
    echo 'Refusing to build: LDAP password fallback is still present' >&2
    exit 1
fi
export GOMAXPROCS=2 GOMEMLIMIT=256MiB GOTOOLCHAIN=local
go_bin="$staging/build/sdk/go/bin/go"
"$go_bin" mod tidy
"$go_bin" build -p 1 -trimpath -ldflags '-s -w' -o apimain ./cmd/apimain.go
sha256sum apimain > ../api-build.sha256
echo API_BUILD_OK
