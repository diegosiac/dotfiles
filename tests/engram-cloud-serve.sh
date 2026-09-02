#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
wrapper=$repo_root/dot_local/bin/executable_engram-cloud-serve
tmp_root=$(mktemp -d)
failure_count=0

cleanup() { rm -rf -- "$tmp_root"; }
trap cleanup EXIT

fail() {
        printf 'FAIL: %s\n' "$1" >&2
        failure_count=$((failure_count + 1))
}

assert_equals() {
        expected=$1
        actual=$2
        context=$3
        [ "$actual" = "$expected" ] || {
                printf 'Expected: %s\nActual:   %s\n' "$expected" "$actual" >&2
                fail "$context"
        }
}

assert_absent() {
        needle=$1
        haystack=$2
        context=$3
        case $haystack in
        *"$needle"*) fail "$context" ;;
        esac
}

run_case() {
        mode=$1
        home_dir=$tmp_root/home-$mode
        credentials_dir=$tmp_root/credentials-$mode
        output_file=$tmp_root/$mode.out
        env_file=$tmp_root/$mode.env
        token='sentinel-token-value'
        server='https://engram-cloud.example.test'

        mkdir -p "$home_dir/.local/bin" "$credentials_dir"
        cat >"$home_dir/.local/bin/engram" <<STUB
#!/bin/sh
[ "\$1" = serve ] || exit 64
printf 'token=%s\nserver=%s\nautosync=%s\n' "\$ENGRAM_CLOUD_TOKEN" "\$ENGRAM_CLOUD_SERVER" "\${ENGRAM_CLOUD_AUTOSYNC-}" >'$env_file'
exit 0
STUB
        chmod +x "$home_dir/.local/bin/engram"

        case $mode in
        success)
                printf '%s\n' "$token" >"$credentials_dir/engram-cloud-token"
                printf '%s\n' "$server" >"$credentials_dir/engram-cloud-server"
                CREDENTIALS_DIRECTORY=$credentials_dir HOME=$home_dir ENGRAM_CLOUD_AUTOSYNC=1 sh "$wrapper" >"$output_file" 2>&1
                status=$?
                ;;
        empty-token)
                : >"$credentials_dir/engram-cloud-token"
                printf '%s\n' "$server" >"$credentials_dir/engram-cloud-server"
                set +e
                CREDENTIALS_DIRECTORY=$credentials_dir HOME=$home_dir sh "$wrapper" >"$output_file" 2>&1
                status=$?
                set -e
                ;;
        empty-server)
                printf '%s\n' "$token" >"$credentials_dir/engram-cloud-token"
                : >"$credentials_dir/engram-cloud-server"
                set +e
                CREDENTIALS_DIRECTORY=$credentials_dir HOME=$home_dir sh "$wrapper" >"$output_file" 2>&1
                status=$?
                set -e
                ;;
        missing-token)
                printf '%s\n' "$server" >"$credentials_dir/engram-cloud-server"
                set +e
                CREDENTIALS_DIRECTORY=$credentials_dir HOME=$home_dir sh "$wrapper" >"$output_file" 2>&1
                status=$?
                set -e
                ;;
        missing-server)
                printf '%s\n' "$token" >"$credentials_dir/engram-cloud-token"
                set +e
                CREDENTIALS_DIRECTORY=$credentials_dir HOME=$home_dir sh "$wrapper" >"$output_file" 2>&1
                status=$?
                set -e
                ;;
        unreadable-token)
                printf '%s\n' "$token" >"$credentials_dir/engram-cloud-token"
                printf '%s\n' "$server" >"$credentials_dir/engram-cloud-server"
                chmod 000 "$credentials_dir/engram-cloud-token"
                set +e
                CREDENTIALS_DIRECTORY=$credentials_dir HOME=$home_dir sh "$wrapper" >"$output_file" 2>&1
                status=$?
                set -e
                ;;
        unreadable-server)
                printf '%s\n' "$token" >"$credentials_dir/engram-cloud-token"
                printf '%s\n' "$server" >"$credentials_dir/engram-cloud-server"
                chmod 000 "$credentials_dir/engram-cloud-server"
                set +e
                CREDENTIALS_DIRECTORY=$credentials_dir HOME=$home_dir sh "$wrapper" >"$output_file" 2>&1
                status=$?
                set -e
                ;;
        missing-directory)
                set +e
                HOME=$home_dir sh "$wrapper" >"$output_file" 2>&1
                status=$?
                set -e
                ;;
        *) exit 65 ;;
        esac

        output=$(cat "$output_file")
        assert_absent "$token" "$output" "$mode does not print token"
        assert_absent "$server" "$output" "$mode does not print server"
}

expected_success='token=sentinel-token-value
server=https://engram-cloud.example.test
autosync=1'

run_case success
assert_equals 0 "$status" "success exits with engram status"
assert_equals "$expected_success" "$(cat "$env_file")" "success exports cloud token, server, and preserves autosync"

for mode in missing-directory missing-token missing-server unreadable-token unreadable-server empty-token empty-server; do
        run_case "$mode"
        [ "$status" -ne 0 ] || fail "$mode fails closed"
        [ ! -e "$env_file" ] || fail "$mode does not exec engram"
done

[ "$failure_count" -eq 0 ] || {
        printf '%s engram-cloud-serve tests failed.\n' "$failure_count" >&2
        exit 1
}
printf 'All engram-cloud-serve tests passed.\n'
