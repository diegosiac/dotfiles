#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
script=$repo_root/scripts/configure-engram-cloud.sh
tmp_root=$(mktemp -d)
failure_count=0

cleanup() { rm -rf -- "$tmp_root"; }
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failure_count=$((failure_count + 1))
}

assert_file_contains() {
    local file=$1
    local needle=$2
    local context=$3
    grep -Fqx -- "$needle" "$file" || fail "$context"
}

assert_absent() {
    local needle=$1
    local haystack=$2
    local context=$3
    case $haystack in
    *"$needle"*) fail "$context" ;;
    esac
}

make_path() {
    local mode=$1
    local bin_dir=$tmp_root/bin-$mode
    mkdir -p "$bin_dir"

    cat >"$bin_dir/op" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = item ] && [ "$2" = get ] && [ "$3" = engram-cloud ] || exit 64
[ "$4" = --field ] || exit 64
[ "$6" = --reveal ] || exit 64
case "$5" in
    password) printf '%s\n' 'sentinel-token-value' ;;
    server) printf 'engram-cloud.example.test\r\n' ;;
    *) exit 65 ;;
esac
STUB

    cat >"$bin_dir/systemd-creds" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = encrypt ] && [ "$2" = --user ] || exit 64
case "$3" in --name=*) name=${3#--name=} ;; *) exit 64 ;; esac
[ "$4" = - ] || exit 64
dest=$5
secret=$(cat)
[ -n "$secret" ] || exit 66
printf 'name=%s\n' "$name" >"$dest"
printf 'encrypted=%s\n' "$secret" >>"$dest"
STUB

    cat >"$bin_dir/systemctl" <<STUB
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>'$tmp_root/systemctl-$mode.log'
STUB

    chmod +x "$bin_dir/op" "$bin_dir/systemd-creds" "$bin_dir/systemctl"
    printf '%s' "$bin_dir"
}

make_second_commit_move_fails() {
    local mode=$1
    local cred_dir=$2
    local mv_stub=$tmp_root/mv-$mode
    local real_mv
    real_mv=$(command -v mv)

    cat >"$mv_stub" <<STUB
#!/usr/bin/env bash
set -euo pipefail
src=
dest=
for arg in "\$@"; do
    src=\$dest
    dest=\$arg
done
server_src=0
case "\$src" in
    */engram-cloud-server.cred) server_src=1 ;;
esac
if [ "\$server_src" -eq 1 ] && [ "\$dest" = '$cred_dir/engram-cloud-server' ] && [ ! -e '$tmp_root/mv-$mode.failed' ]; then
    : >'$tmp_root/mv-$mode.failed'
    exit 73
fi
exec '$real_mv' "\$@"
STUB
    chmod +x "$mv_stub"
    printf '%s' "$mv_stub"
}

run_success() {
    local mode=success
    local home_dir=$tmp_root/home-$mode
    local output_file=$tmp_root/$mode.out
    mkdir -p "$home_dir"
    PATH="$(make_path "$mode"):$PATH" HOME=$home_dir XDG_RUNTIME_DIR=$tmp_root "$script" >"$output_file" 2>&1

    assert_file_contains "$home_dir/.config/credstore.encrypted/engram-cloud-token" 'name=engram-cloud-token' 'token credential uses systemd credential name'
    assert_file_contains "$home_dir/.config/credstore.encrypted/engram-cloud-server" 'name=engram-cloud-server' 'server credential uses systemd credential name'
    assert_file_contains "$home_dir/.config/credstore.encrypted/engram-cloud-server" 'encrypted=https://engram-cloud.example.test' 'bare server hostname is normalized before encryption'
    assert_file_contains "$tmp_root/systemctl-$mode.log" '--user daemon-reload' 'daemon reload runs after credentials'
    assert_file_contains "$tmp_root/systemctl-$mode.log" '--user enable --now engram.service' 'service enabled after credentials'
    output=$(cat "$output_file")
    assert_absent 'sentinel-token-value' "$output" 'success does not print token'
    assert_absent 'engram-cloud.example.test' "$output" 'success does not print bare server'
    assert_absent 'https://engram-cloud.example.test' "$output" 'success does not print normalized server'
}

run_empty_token_fails_closed() {
    local mode=empty-token
    local home_dir=$tmp_root/home-$mode
    local bin_dir
    local output_file=$tmp_root/$mode.out
    mkdir -p "$home_dir"
    bin_dir=$(make_path "$mode")
    cat >"$bin_dir/op" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[ "$5" = password ] && exit 0
printf '%s\n' 'https://engram-cloud.example.test'
STUB
    chmod +x "$bin_dir/op"

    set +e
    PATH="$bin_dir:$PATH" HOME=$home_dir XDG_RUNTIME_DIR=$tmp_root "$script" >"$output_file" 2>&1
    status=$?
    set -e

    [ "$status" -ne 0 ] || fail 'empty token fails'
    [ ! -e "$tmp_root/systemctl-$mode.log" ] || fail 'systemctl is not called on credential failure'
    output=$(cat "$output_file")
    assert_absent 'https://engram-cloud.example.test' "$output" 'failure does not print server'
}

run_server_encrypt_failure_preserves_existing_token() {
    local mode=server-encrypt-failure
    local home_dir=$tmp_root/home-$mode
    local cred_dir=$home_dir/.config/credstore.encrypted
    local bin_dir
    local output_file=$tmp_root/$mode.out
    mkdir -p "$cred_dir"
    printf '%s\n' 'old-token-credential' >"$cred_dir/engram-cloud-token"

    bin_dir=$(make_path "$mode")
    cat >"$bin_dir/systemd-creds" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = encrypt ] && [ "$2" = --user ] || exit 64
case "$3" in --name=*) name=${3#--name=} ;; *) exit 64 ;; esac
[ "$4" = - ] || exit 64
dest=$5
secret=$(cat)
[ -n "$secret" ] || exit 66
[ "$name" = engram-cloud-server ] && exit 67
printf 'name=%s\n' "$name" >"$dest"
printf 'encrypted=%s\n' "$secret" >>"$dest"
STUB
    chmod +x "$bin_dir/systemd-creds"

    set +e
    PATH="$bin_dir:$PATH" HOME=$home_dir XDG_RUNTIME_DIR=$tmp_root "$script" >"$output_file" 2>&1
    status=$?
    set -e

    [ "$status" -ne 0 ] || fail 'server encryption failure fails'
    assert_file_contains "$cred_dir/engram-cloud-token" 'old-token-credential' 'existing token credential is not overwritten before server encryption succeeds'
    [ ! -e "$tmp_root/systemctl-$mode.log" ] || fail 'systemctl is not called on server encryption failure'
    output=$(cat "$output_file")
    assert_absent 'sentinel-token-value' "$output" 'server encryption failure does not print token'
    assert_absent 'engram-cloud.example.test' "$output" 'server encryption failure does not print server'
    assert_absent 'https://engram-cloud.example.test' "$output" 'server encryption failure does not print normalized server'
}

run_second_commit_move_failure_restores_existing_pair() {
    local mode=second-commit-move-fails-existing
    local home_dir=$tmp_root/home-$mode
    local cred_dir=$home_dir/.config/credstore.encrypted
    local bin_dir
    local mv_stub
    local output_file=$tmp_root/$mode.out
    mkdir -p "$cred_dir"
    printf '%s\n' 'old-token-credential' >"$cred_dir/engram-cloud-token"
    printf '%s\n' 'old-server-credential' >"$cred_dir/engram-cloud-server"

    bin_dir=$(make_path "$mode")
    mv_stub=$(make_second_commit_move_fails "$mode" "$cred_dir")

    set +e
    PATH="$bin_dir:$PATH" MV_BIN=$mv_stub HOME=$home_dir XDG_RUNTIME_DIR=$tmp_root "$script" >"$output_file" 2>&1
    status=$?
    set -e

    [ "$status" -ne 0 ] || fail 'second commit move failure fails'
    assert_file_contains "$cred_dir/engram-cloud-token" 'old-token-credential' 'existing token credential is restored after second commit move failure'
    assert_file_contains "$cred_dir/engram-cloud-server" 'old-server-credential' 'existing server credential is restored after second commit move failure'
    [ ! -e "$tmp_root/systemctl-$mode.log" ] || fail 'systemctl is not called after second commit move failure'
    output=$(cat "$output_file")
    assert_absent 'sentinel-token-value' "$output" 'second commit move failure does not print token'
    assert_absent 'engram-cloud.example.test' "$output" 'second commit move failure does not print server'
    assert_absent 'https://engram-cloud.example.test' "$output" 'second commit move failure does not print normalized server'
}

run_second_commit_move_failure_removes_new_when_missing_pair() {
    local mode=second-commit-move-fails-missing
    local home_dir=$tmp_root/home-$mode
    local cred_dir=$home_dir/.config/credstore.encrypted
    local bin_dir
    local mv_stub
    local output_file=$tmp_root/$mode.out
    mkdir -p "$cred_dir"

    bin_dir=$(make_path "$mode")
    mv_stub=$(make_second_commit_move_fails "$mode" "$cred_dir")

    set +e
    PATH="$bin_dir:$PATH" MV_BIN=$mv_stub HOME=$home_dir XDG_RUNTIME_DIR=$tmp_root "$script" >"$output_file" 2>&1
    status=$?
    set -e

    [ "$status" -ne 0 ] || fail 'second commit move failure without existing credentials fails'
    [ ! -e "$cred_dir/engram-cloud-token" ] || fail 'new token credential is removed when no original existed'
    [ ! -e "$cred_dir/engram-cloud-server" ] || fail 'server credential remains absent when no original existed'
    [ ! -e "$tmp_root/systemctl-$mode.log" ] || fail 'systemctl is not called after second commit move failure without existing credentials'
    output=$(cat "$output_file")
    assert_absent 'sentinel-token-value' "$output" 'second commit move missing case does not print token'
    assert_absent 'engram-cloud.example.test' "$output" 'second commit move missing case does not print server'
    assert_absent 'https://engram-cloud.example.test' "$output" 'second commit move missing case does not print normalized server'
}

run_success
run_empty_token_fails_closed
run_server_encrypt_failure_preserves_existing_token
run_second_commit_move_failure_restores_existing_pair
run_second_commit_move_failure_removes_new_when_missing_pair

[ "$failure_count" -eq 0 ] || {
    printf '%s configure-engram-cloud tests failed.\n' "$failure_count" >&2
    exit 1
}
printf 'All configure-engram-cloud tests passed.\n'
