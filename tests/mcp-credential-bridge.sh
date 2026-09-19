#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
configure=$repo_root/scripts/configure-mcp-credentials.sh
mongodb_launcher=$repo_root/dot_local/bin/executable_mongodb-mcp-readonly
paul_launcher=$repo_root/dot_local/bin/executable_paul-mcp
mongodb_service=$repo_root/dot_local/bin/executable_mongodb-mcp-service
paul_service=$repo_root/dot_local/bin/executable_paul-mcp-service

tmp_root=$(mktemp -d)
trap 'rm -rf -- "$tmp_root"' EXIT
failure_count=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failure_count=$((failure_count + 1))
}
assert_contains() { grep -Fq -- "$2" "$1" || fail "$3"; }
assert_not_contains() { ! grep -Fq -- "$2" "$1" || fail "$3"; }

[ -x "$configure" ] || fail 'credential provisioning helper exists and is executable'
[ -x "$mongodb_launcher" ] || fail 'MongoDB bridge launcher exists and is executable'
[ -x "$paul_launcher" ] || fail 'PAUL bridge launcher exists and is executable'
[ -x "$mongodb_service" ] || fail 'MongoDB service command exists and is executable'
[ -x "$paul_service" ] || fail 'PAUL service command exists and is executable'

for launcher in "$mongodb_launcher" "$paul_launcher"; do
    assert_contains "$launcher" 'systemd-run --user --pipe --wait' 'launcher uses the user systemd stdio bridge'
    assert_not_contains "$launcher" 'op run' 'normal launcher does not invoke 1Password'
done
assert_contains "$mongodb_launcher" 'LoadCredentialEncrypted=mongodb-mcp-connection-string:$HOME/.config/credstore.encrypted/mongodb-mcp-connection-string' 'MongoDB bridge loads the encrypted connection credential'
assert_contains "$paul_launcher" 'LoadCredentialEncrypted=paul-mcp-email:$HOME/.config/credstore.encrypted/paul-mcp-email' 'PAUL bridge loads the encrypted email credential'
assert_contains "$paul_launcher" 'LoadCredentialEncrypted=paul-mcp-password:$HOME/.config/credstore.encrypted/paul-mcp-password' 'PAUL bridge loads the encrypted password credential'
assert_contains "$mongodb_service" 'MDB_MCP_READ_ONLY=true' 'MongoDB service preserves read-only environment defense'
assert_contains "$mongodb_service" '--readOnly' 'MongoDB service preserves read-only command defense'
assert_contains "$paul_service" 'PAUL_URL=https://iventas.cc/iventas-coach' 'PAUL service preserves its URL'

bin_dir=$tmp_root/bin
home_dir=$tmp_root/home
mkdir -p "$bin_dir" "$home_dir/.config/mongodb-mcp" "$home_dir/.config/paul-mcp"
printf '%s\n' 'MDB_MCP_CONNECTION_STRING=op://reference' >"$home_dir/.config/mongodb-mcp/1password.env"
printf '%s\n' 'PAUL_EMAIL=op://reference' 'PAUL_PASSWORD=op://reference' >"$home_dir/.config/paul-mcp/1password.env"
cat >"$bin_dir/op" <<'STUB'
#!/bin/sh
[ "$1" = inject ] || exit 64
[ "$2" = --in-file ] || exit 64
[ "$4" = --out-file ] || exit 64
sed 's#op://reference#provisioned-value#g' "$3" >"$5"
STUB
cat >"$bin_dir/systemd-creds" <<'STUB'
#!/bin/sh
[ "$1" = encrypt ] && [ "$2" = --user ] || exit 64
name=${3#--name=}
[ "$4" = - ] || exit 64
printf '%s\n' "credential=$name" >"$5"
cat >>"$5"
STUB
cat >"$bin_dir/systemctl" <<'STUB'
#!/bin/sh
exit 0
STUB
chmod +x "$bin_dir/op" "$bin_dir/systemd-creds" "$bin_dir/systemctl"

PATH="$bin_dir:$PATH" HOME="$home_dir" XDG_RUNTIME_DIR="$tmp_root" "$configure" >/dev/null 2>&1 || fail 'provisioning succeeds with existing reference files'
assert_contains "$home_dir/.config/credstore.encrypted/mongodb-mcp-connection-string" 'credential=mongodb-mcp-connection-string' 'MongoDB credential is encrypted with its fixed name'
assert_contains "$home_dir/.config/credstore.encrypted/paul-mcp-email" 'credential=paul-mcp-email' 'PAUL email credential is encrypted with its fixed name'
assert_contains "$home_dir/.config/credstore.encrypted/paul-mcp-password" 'credential=paul-mcp-password' 'PAUL password credential is encrypted with its fixed name'

# dotenv-style quoted references (as written by 1Password templates) must not
# leak their surrounding quotes into the encrypted credential values.
printf '%s\n' 'MDB_MCP_CONNECTION_STRING="op://reference"' >"$home_dir/.config/mongodb-mcp/1password.env"
printf '%s\n' 'PAUL_EMAIL="op://reference"' "PAUL_PASSWORD='op://reference'" >"$home_dir/.config/paul-mcp/1password.env"
PATH="$bin_dir:$PATH" HOME="$home_dir" XDG_RUNTIME_DIR="$tmp_root" "$configure" >/dev/null 2>&1 || fail 'provisioning succeeds with quoted reference files'
for credential_name in mongodb-mcp-connection-string paul-mcp-email paul-mcp-password; do
    grep -Fxq -- 'provisioned-value' "$home_dir/.config/credstore.encrypted/$credential_name" || fail "quoted reference for $credential_name is stored without surrounding quotes"
done

# Exercise a normal launcher with a systemd-run stand-in.  An op stand-in would
# leave a marker if the launcher tried to invoke 1Password at runtime.
mkdir -p "$home_dir/.local/bin" "$tmp_root/runtime-credentials"
cp "$mongodb_service" "$home_dir/.local/bin/mongodb-mcp-service"
cp "$paul_service" "$home_dir/.local/bin/paul-mcp-service"
printf '%s\n' 'runtime-mongodb-value' >"$tmp_root/runtime-credentials/mongodb-mcp-connection-string"
printf '%s\n' 'runtime-paul-email' >"$tmp_root/runtime-credentials/paul-mcp-email"
printf '%s\n' 'runtime-paul-password' >"$tmp_root/runtime-credentials/paul-mcp-password"
cat >"$bin_dir/systemd-run" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>'$tmp_root/systemd-run.log'
for argument in "\$@"; do service=\$argument; done
CREDENTIALS_DIRECTORY='$tmp_root/runtime-credentials' exec "\$service"
STUB
cat >"$bin_dir/npx" <<STUB
#!/bin/sh
printf '%s|%s|%s|%s\n' "\$*" "\${MDB_MCP_READ_ONLY-}" "\${PAUL_EMAIL-}" "\${PAUL_URL-}" >>'$tmp_root/npx.log'
STUB
cat >"$bin_dir/op" <<STUB
#!/bin/sh
: >'$tmp_root/op-invoked'
exit 99
STUB
chmod +x "$bin_dir/systemd-run" "$bin_dir/npx" "$bin_dir/op"
PATH="$bin_dir:$PATH" HOME="$home_dir" "$mongodb_launcher" || fail 'MongoDB launcher executes through the systemd bridge'
PATH="$bin_dir:$PATH" HOME="$home_dir" "$paul_launcher" || fail 'PAUL launcher executes through the systemd bridge'
[ ! -e "$tmp_root/op-invoked" ] || fail 'normal launcher execution does not invoke op'
assert_contains "$tmp_root/systemd-run.log" 'LoadCredentialEncrypted=mongodb-mcp-connection-string:' 'MongoDB launcher passes its encrypted credential to systemd'
assert_contains "$tmp_root/systemd-run.log" 'LoadCredentialEncrypted=paul-mcp-password:' 'PAUL launcher passes encrypted credentials to systemd'
assert_contains "$tmp_root/npx.log" 'mongodb-mcp-server@latest --readOnly|true' 'MongoDB runtime retains both read-only defenses'
assert_contains "$tmp_root/npx.log" 'github:iVentas-Plus/iventas-paul||runtime-paul-email|https://iventas.cc/iventas-coach' 'PAUL runtime supplies required environment'

[ "$failure_count" -eq 0 ] || exit 1
printf 'All MCP credential bridge tests passed.\n'
