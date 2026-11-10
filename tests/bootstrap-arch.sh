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

test_herdr_mobile_installs_core_and_enables_tailscale_ssh() {
    local trace=""
    local expected=""

    trace="$(
        herdr_core_installed() { return 1; }
        install_herdr_core() { printf 'install_herdr_core\n'; }
        sudo() { printf 'sudo:%s\n' "$*"; }
        ok() { printf 'ok:%s\n' "$1"; }
        warn() { printf 'warn:%s\n' "$1"; }

        configure_herdr_mobile
    )"

    expected=$'install_herdr_core\nok:herdr-core installed for the Herdr phone app.\nsudo:tailscale set --ssh\nok:Tailscale SSH enabled; the Herdr phone app connects through the tailnet.'
    assert_equals "$expected" "$trace" "herdr mobile installs herdr-core and enables Tailscale SSH"
}

test_herdr_mobile_keeps_existing_core() {
    local trace=""
    local expected=""

    trace="$(
        herdr_core_installed() { return 0; }
        install_herdr_core() { printf 'install_herdr_core\n'; }
        sudo() { printf 'sudo:%s\n' "$*"; }
        ok() { printf 'ok:%s\n' "$1"; }
        warn() { printf 'warn:%s\n' "$1"; }

        configure_herdr_mobile
    )"

    expected=$'ok:herdr-core is already installed; update it with \'herdr-core update\'.\nsudo:tailscale set --ssh\nok:Tailscale SSH enabled; the Herdr phone app connects through the tailnet.'
    assert_equals "$expected" "$trace" "herdr mobile keeps an existing herdr-core"
}

test_herdr_core_installer_digest_mismatch_is_not_run() {
    local trace=""
    local expected=""

    trace="$(
        curl() {
            local output=""
            while (($#)); do
                if [[ "$1" == "-o" ]]; then
                    output="$2"
                    shift
                fi
                shift
            done
            printf 'tampered installer\n' >"$output"
        }
        sh() { printf 'sh:%s\n' "$*"; }
        warn() { printf 'warn:%s\n' "$1"; }

        install_herdr_core
        printf 'status:%s\n' "$?"
    )"

    expected=$'warn:The herdr-core installer digest changed. Review https://releases.herdr.dev/core/install.sh and consciously update herdr_core_installer_sha256.\nstatus:1'
    assert_equals "$expected" "$trace" "herdr-core installer with an unexpected digest is not run"
}

test_herdr_core_download_failure_is_reported() {
    local trace=""
    local expected=""
    local scratch=""

    scratch="$(mktemp -d)"
    trace="$(
        export TMPDIR="$scratch"
        curl() { return 22; }
        sh() { printf 'sh:%s\n' "$*"; }
        warn() { printf 'warn:%s\n' "$1"; }

        install_herdr_core
        printf 'status:%s\n' "$?"
        printf 'leftovers:%s\n' "$(find "$scratch" -type f | wc -l)"
    )"
    rm -rf -- "$scratch"

    expected=$'warn:Could not download the herdr-core installer from https://releases.herdr.dev/core/install.sh.\nstatus:1\nleftovers:0'
    assert_equals "$expected" "$trace" "herdr-core download failure is reported and cleaned up"
}

test_herdr_core_pinned_installer_runs_and_is_removed() {
    local trace=""
    local expected=""
    local scratch=""

    scratch="$(mktemp -d)"
    trace="$(
        export TMPDIR="$scratch"
        herdr_core_installer_sha256="$(printf 'reviewed installer\n' | sha256sum | cut -d' ' -f1)"
        curl() {
            local output=""
            while (($#)); do
                if [[ "$1" == "-o" ]]; then
                    output="$2"
                    shift
                fi
                shift
            done
            printf 'reviewed installer\n' >"$output"
        }
        sh() { printf 'sh:%s\n' "$(cat "$1")"; return 7; }
        warn() { printf 'warn:%s\n' "$1"; }

        install_herdr_core
        printf 'status:%s\n' "$?"
        printf 'leftovers:%s\n' "$(find "$scratch" -type f | wc -l)"
    )"
    rm -rf -- "$scratch"

    expected=$'sh:reviewed installer\nstatus:7\nleftovers:0'
    assert_equals "$expected" "$trace" "pinned herdr-core installer runs, propagates its status, and is removed"
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
run_test "Herdr mobile installs herdr-core and enables Tailscale SSH" test_herdr_mobile_installs_core_and_enables_tailscale_ssh
run_test "Herdr mobile keeps an existing herdr-core" test_herdr_mobile_keeps_existing_core
run_test "herdr-core installer digest mismatch is not run" test_herdr_core_installer_digest_mismatch_is_not_run
run_test "herdr-core download failure is reported" test_herdr_core_download_failure_is_reported
run_test "pinned herdr-core installer runs and is removed" test_herdr_core_pinned_installer_runs_and_is_removed

if ((failures > 0)); then
    printf '%s of %s Arch bootstrap behavior tests failed.\n' "$failures" "$tests_run" >&2
    exit 1
fi

printf 'All %s Arch bootstrap behavior tests passed.\n' "$tests_run"
