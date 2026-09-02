#!/usr/bin/env zsh
setopt NO_UNSET PIPE_FAIL

repo_root="${0:A:h:h}"
loader="$repo_root/dot_local/bin/executable_secrets-load"
tmp_root="$(mktemp -d)"
stub_bin="$tmp_root/bin"
empty_bin="$tmp_root/empty-bin"
fake_token="sentinel-token-value"
fake_server=$'engram-cloud.example.test\r'
expected_server="https://engram-cloud.example.test"
stale_token="stale-token-value"
stale_server="https://stale-engram-cloud.example.test"
failures=0

cleanup() { rm -rf -- "$tmp_root"; }
trap cleanup EXIT
mkdir -p "$stub_bin" "$empty_bin"

cat >"$stub_bin/op" <<'STUB'
#!/bin/sh
if [ "$1" != item ] || [ "$2" != get ] || [ "$3" != engram-cloud ] || [ "$4" != --field ] || [ "$6" != --reveal ]; then
    exit 64
fi
case "$5" in
    password) value="$OP_TEST_TOKEN"; name=token ;;
    server) value="$OP_TEST_SERVER"; name=server ;;
    *) exit 64 ;;
esac
case "$OP_MODE" in
    fail-token)
        if [ "$name" = token ]; then
            printf '%s\n' "$value"
            printf '%s\n' "$value" >&2
            exit 23
        fi
        printf '%s\n' "$value"
        ;;
    fail-server)
        if [ "$name" = server ]; then
            printf '%s\n' "$value"
            printf '%s\n' "$value" >&2
            exit 24
        fi
        printf '%s\n' "$value"
        ;;
    empty-token)
        [ "$name" = token ] || printf '%s\n' "$value"
        ;;
    empty-server)
        [ "$name" = server ] || printf '%s\n' "$value"
        ;;
    success) printf '%s\n' "$value" ;;
    *) exit 65 ;;
esac
STUB
chmod +x "$stub_bin/op"

report_failure() { print -u2 -r -- "FAIL: $1"; failures=$((failures + 1)); }

assert_equals() {
    local expected="$1" actual="$2" context="$3"
    if [[ "$actual" != "$expected" ]]; then
        print -u2 -r -- "Expected: $expected" "Actual:   $actual"
        report_failure "$context"
    fi
}

assert_absent() {
    local needle="$1" output="$2" context="$3"
    [[ "$output" != *"$needle"* ]] || report_failure "$context"
}

run_case() {
    local mode="$1" case_path="$2"
    local output_file="$tmp_root/$mode.out"
    # shellcheck disable=SC2016
    /usr/bin/env -i \
        PATH="$case_path" LOADER="$loader" OP_MODE="$mode" \
        OP_TEST_TOKEN="$fake_token" OP_TEST_SERVER="$fake_server" \
        EXPECTED_TOKEN="$fake_token" EXPECTED_SERVER="$expected_server" \
        STALE_TOKEN="$stale_token" STALE_SERVER="$stale_server" \
        /usr/bin/zsh -dfc '
            export ENGRAM_CLOUD_TOKEN="$STALE_TOKEN"
            export ENGRAM_CLOUD_SERVER="$STALE_SERVER"
            source "$LOADER"
            source_status=$?
            [[ "${ENGRAM_CLOUD_TOKEN-}" == "$EXPECTED_TOKEN" ]] && token_matches=1 || token_matches=0
            [[ "${ENGRAM_CLOUD_SERVER-}" == "$EXPECTED_SERVER" ]] && server_matches=1 || server_matches=0
            token_exported=0
            server_exported=0
            (( ${+parameters[ENGRAM_CLOUD_TOKEN]} )) && [[ ${(t)ENGRAM_CLOUD_TOKEN} == *export* ]] && token_exported=1
            (( ${+parameters[ENGRAM_CLOUD_SERVER]} )) && [[ ${(t)ENGRAM_CLOUD_SERVER} == *export* ]] && server_exported=1
            leaks=0
            for name in _secrets_load_token _secrets_load_server _secrets_load_status; do
                (( ${+parameters[$name]} || ${+functions[$name]} )) && leaks=1
            done
            print -rl -- "status=$source_status" \
                "token_set=${+parameters[ENGRAM_CLOUD_TOKEN]}" "server_set=${+parameters[ENGRAM_CLOUD_SERVER]}" \
                "token_matches=$token_matches" "server_matches=$server_matches" \
                "token_exported=$token_exported" "server_exported=$server_exported" "leaks=$leaks"
        ' >"$output_file" 2>&1
    CASE_OUTPUT="$(<"$output_file")"
    assert_absent "$fake_token" "$CASE_OUTPUT" "$mode does not print the loaded token"
    assert_absent "$fake_server" "$CASE_OUTPUT" "$mode does not print the loaded bare server"
    assert_absent "$expected_server" "$CASE_OUTPUT" "$mode does not print the normalized server"
    assert_absent "$stale_token" "$CASE_OUTPUT" "$mode does not print the stale token"
    assert_absent "$stale_server" "$CASE_OUTPUT" "$mode does not print the stale server"
}

run_case missing "$empty_bin"
assert_equals $'secrets-load: 1Password CLI not found\nstatus=1\ntoken_set=0\nserver_set=0\ntoken_matches=0\nserver_matches=0\ntoken_exported=0\nserver_exported=0\nleaks=0' "$CASE_OUTPUT" "missing op fails closed"

run_case fail-token "$stub_bin"
assert_equals $'secrets-load: unable to read ENGRAM_CLOUD_TOKEN\nstatus=23\ntoken_set=0\nserver_set=0\ntoken_matches=0\nserver_matches=0\ntoken_exported=0\nserver_exported=0\nleaks=0' "$CASE_OUTPUT" "token 1Password read failure propagates and fails closed"

run_case fail-server "$stub_bin"
assert_equals $'secrets-load: unable to read ENGRAM_CLOUD_SERVER\nstatus=24\ntoken_set=0\nserver_set=0\ntoken_matches=0\nserver_matches=0\ntoken_exported=0\nserver_exported=0\nleaks=0' "$CASE_OUTPUT" "server 1Password read failure propagates and fails closed"

run_case empty-token "$stub_bin"
assert_equals $'secrets-load: ENGRAM_CLOUD_TOKEN was empty\nstatus=1\ntoken_set=0\nserver_set=0\ntoken_matches=0\nserver_matches=0\ntoken_exported=0\nserver_exported=0\nleaks=0' "$CASE_OUTPUT" "empty token 1Password output fails closed"

run_case empty-server "$stub_bin"
assert_equals $'secrets-load: ENGRAM_CLOUD_SERVER was empty\nstatus=1\ntoken_set=0\nserver_set=0\ntoken_matches=0\nserver_matches=0\ntoken_exported=0\nserver_exported=0\nleaks=0' "$CASE_OUTPUT" "empty server op output fails closed"

run_case success "$stub_bin"
assert_equals $'Loaded secrets: ENGRAM_CLOUD_TOKEN ENGRAM_CLOUD_SERVER\nstatus=0\ntoken_set=1\nserver_set=1\ntoken_matches=1\nserver_matches=1\ntoken_exported=1\nserver_exported=1\nleaks=0' "$CASE_OUTPUT" "bare server op output is normalized and exported"

(( failures == 0 )) || { print -u2 -r -- "$failures secrets-load tests failed."; exit 1; }
print -r -- "All secrets-load tests passed."
