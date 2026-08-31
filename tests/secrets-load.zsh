#!/usr/bin/env zsh
setopt NO_UNSET PIPE_FAIL

repo_root="${0:A:h:h}"
loader="$repo_root/dot_local/bin/executable_secrets-load"
tmp_root="$(mktemp -d)"
stub_bin="$tmp_root/bin"
empty_bin="$tmp_root/empty-bin"
fake_token="sentinel-token-value"
stale_token="stale-token-value"
failures=0

cleanup() { rm -rf -- "$tmp_root"; }
trap cleanup EXIT
mkdir -p "$stub_bin" "$empty_bin"

cat >"$stub_bin/op" <<'STUB'
#!/bin/sh
if [ "$1" != read ] || [ "$2" != 'op://Secrets/Engram Cloud/password' ]; then
    exit 64
fi
case "$OP_MODE" in
    fail)
        printf '%s\n' "$OP_TEST_VALUE"
        printf '%s\n' "$OP_TEST_VALUE" >&2
        exit 23
        ;;
    empty) exit 0 ;;
    success) printf '%s\n' "$OP_TEST_VALUE" ;;
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
    /usr/bin/env -i \
        PATH="$case_path" LOADER="$loader" OP_MODE="$mode" \
        OP_TEST_VALUE="$fake_token" EXPECTED_TOKEN="$fake_token" STALE_TOKEN="$stale_token" \
        /usr/bin/zsh -dfc '
            export ENGRAM_CLOUD_TOKEN="$STALE_TOKEN"
            source "$LOADER"
            source_status=$?
            [[ "${ENGRAM_CLOUD_TOKEN-}" == "$EXPECTED_TOKEN" ]] && matches=1 || matches=0
            exported=0
            (( ${+parameters[ENGRAM_CLOUD_TOKEN]} )) && [[ ${(t)ENGRAM_CLOUD_TOKEN} == *export* ]] && exported=1
            leaks=0
            for name in _secrets_load_token _secrets_load_status; do
                (( ${+parameters[$name]} || ${+functions[$name]} )) && leaks=1
            done
            print -rl -- "status=$source_status" "set=${+parameters[ENGRAM_CLOUD_TOKEN]}" \
                "matches=$matches" "exported=$exported" "leaks=$leaks"
        ' >"$output_file" 2>&1
    CASE_OUTPUT="$(<"$output_file")"
    assert_absent "$fake_token" "$CASE_OUTPUT" "$mode does not print the loaded token"
    assert_absent "$stale_token" "$CASE_OUTPUT" "$mode does not print the stale token"
}

run_case missing "$empty_bin"
assert_equals $'secrets-load: 1Password CLI not found\nstatus=1\nset=0\nmatches=0\nexported=0\nleaks=0' "$CASE_OUTPUT" "missing op fails closed"

run_case fail "$stub_bin"
assert_equals $'secrets-load: unable to read ENGRAM_CLOUD_TOKEN\nstatus=23\nset=0\nmatches=0\nexported=0\nleaks=0' "$CASE_OUTPUT" "op read failure propagates and fails closed"

run_case empty "$stub_bin"
assert_equals $'secrets-load: ENGRAM_CLOUD_TOKEN was empty\nstatus=1\nset=0\nmatches=0\nexported=0\nleaks=0' "$CASE_OUTPUT" "empty op output fails closed"

run_case success "$stub_bin"
assert_equals $'Loaded secrets: ENGRAM_CLOUD_TOKEN\nstatus=0\nset=1\nmatches=1\nexported=1\nleaks=0' "$CASE_OUTPUT" "non-empty op output is exported"

(( failures == 0 )) || { print -u2 -r -- "$failures secrets-load tests failed."; exit 1; }
print -r -- "All secrets-load tests passed."
