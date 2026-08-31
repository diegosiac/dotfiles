#!/usr/bin/env bash
# Bootstrap functions are sourced without executing the interactive entry point.
# shellcheck disable=SC1090,SC2329
set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source <(sed '/^printf .*Siac Dotfiles Bootstrap/,$d' "$repo_root/scripts/bootstrap-arch.sh")

failures=0
tests_run=0

report_failure() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local context="$3"

    if [[ "$actual" != "$expected" ]]; then
        printf 'Expected trace:\n%s\nActual trace:\n%s\n' "$expected" "$actual" >&2
        report_failure "$context"
    fi
}

test_basic_services_include_weekly_trim() {
    local trace=""
    local expected=""

    trace="$(
        enable_system_service() { printf '%s\n' "$1"; }
        ok() { :; }

        enable_basic_services
    )"

    expected=$'NetworkManager.service\nbluetooth.service\ntailscaled.service\nsystemd-timesyncd.service\npaccache.timer\nfstrim.timer'
    assert_equals "$expected" "$trace" "basic services include weekly filesystem trim"
}

test_unavailable_trim_timer_is_skipped() {
    local trace=""
    local expected=""

    trace="$(
        systemctl() { return 1; }
        sudo() { printf 'sudo:%s\n' "$*"; }
        warn() { printf 'warn:%s\n' "$1"; }

        enable_system_service fstrim.timer
    )"

    expected="warn:fstrim.timer is unavailable. Install the matching package first, then enable it manually if needed."
    assert_equals "$expected" "$trace" "unavailable fstrim timer is skipped without sudo"
}

test_node_runtime_uses_mise_with_bash_activation() {
    local trace=""
    local expected=""

    trace="$(
        mise() {
            if [[ "$1" == "activate" ]]; then
                printf '%s\n' "printf 'mise:activate %s\\n' '$2'"
            else
                printf 'mise:%s\n' "$*"
            fi
        }
        corepack() { printf 'corepack:%s\n' "$*"; }

        initialize_node_runtime
    )"

    expected=$'mise:activate bash\nmise:use --global node@lts\nmise:activate bash\ncorepack:enable\ncorepack:prepare pnpm@latest --activate'
    assert_equals "$expected" "$trace" "Node.js runtime uses mise with native Bash activation"
}

run_test() {
    local name="$1"
    local test_function="$2"
    local failures_before="$failures"

    tests_run=$((tests_run + 1))
    "$test_function"
    if [[ "$failures" -eq "$failures_before" ]]; then
        printf 'PASS: %s\n' "$name"
    fi
}

run_test "basic services include weekly TRIM" test_basic_services_include_weekly_trim
run_test "unavailable TRIM timer is skipped" test_unavailable_trim_timer_is_skipped
run_test "Node.js runtime uses mise with Bash activation" test_node_runtime_uses_mise_with_bash_activation

if ((failures > 0)); then
    printf '%s of %s Arch bootstrap behavior tests failed.\n' "$failures" "$tests_run" >&2
    exit 1
fi

printf 'All %s Arch bootstrap behavior tests passed.\n' "$tests_run"
