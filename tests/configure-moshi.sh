#!/usr/bin/env bash
# Test doubles are invoked indirectly, and global overrides are subprocess-scoped.
# shellcheck disable=SC2030,SC2031,SC2329
set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# The runtime path is anchored above; configure-moshi.sh is linted separately.
# shellcheck disable=SC1091
source "$repo_root/scripts/configure-moshi.sh"

failures=0
tests_run=0
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT
expected_moshi_hook_installer_sha256="95f05fe8d4525bef32c557eede09ecd0e4414f8d0eba8c3a65a866a409134432"
installer_fixture="$temp_dir/installer-fixture.sh"
installer_fixture_sha256="0a5fb2d3a9e42d8cd0cd06a68ffdbc8cdd3e26ad2ec801c47867e457e7433e1a"
printf '#!/bin/sh\nexit 99\n' >"$installer_fixture"
mkdir "$temp_dir/no-sha-tools"

report_failure() {
	printf 'FAIL: %s\n' "$1" >&2
	failures=$((failures + 1))
}

assert_status() {
	local expected="$1"
	local actual="$2"
	local context="$3"

	if [[ "$actual" -ne "$expected" ]]; then
		report_failure "$context: expected status $expected, got $actual"
	fi
}

assert_equals() {
	local expected="$1"
	local actual="$2"
	local context="$3"

	if [[ "$actual" != "$expected" ]]; then
		report_failure "$context: expected '$expected', got '$actual'"
	fi
}

assert_file_equals() {
	local expected="$1"
	local file="$2"
	local context="$3"
	local actual=""

	actual="$(<"$file")"
	if [[ "$actual" != "$expected" ]]; then
		printf 'Expected trace:\n%s\nActual trace:\n%s\n' "$expected" "$actual" >&2
		report_failure "$context"
	fi
}

assert_contains() {
	local expected="$1"
	local file="$2"
	local context="$3"

	if ! grep -Fq -- "$expected" "$file"; then
		report_failure "$context: missing '$expected'"
	fi
}

assert_not_contains() {
	local unexpected="$1"
	local file="$2"
	local context="$3"

	if grep -Fq -- "$unexpected" "$file"; then
		report_failure "$context: unexpectedly found '$unexpected'"
	fi
}

run_effective_sshd_policy_match() {
	local effective_config="$1"
	local ports="$2"
	local user="$3"

	(
		USER="$user"
		effective_sshd_policy_matches "$effective_config" "$ports"
	)
}

test_effective_sshd_policy_accepts_lowercase_keys() {
	local effective_config=""
	local status=0

	effective_config=$'port 2222\npermitrootlogin no\npubkeyauthentication yes\npasswordauthentication no\nkbdinteractiveauthentication no\nallowusers moshi-user backup-user\nauthenticationmethods publickey\nport 22'
	run_effective_sshd_policy_match "$effective_config" "22 2222" "moshi-user" || status=$?
	assert_status 0 "$status" "legacy lowercase sshd -T policy with exact ports and allowed user"
}

test_effective_sshd_policy_accepts_capitalized_keys() {
	local effective_config=""
	local status=0

	effective_config=$'Port 2222\nPermitRootLogin no\nPubkeyAuthentication yes\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nAllowUsers moshi-user backup-user\nAuthenticationMethods publickey\nPort 22'
	run_effective_sshd_policy_match "$effective_config" "22 2222" "moshi-user" || status=$?
	assert_status 0 "$status" "OpenSSH 10.5 capitalized sshd -T policy with exact ports and allowed user"
}

test_effective_sshd_policy_rejects_incorrect_policy() {
	local effective_config=""
	local status=0

	effective_config=$'Port 2222\nPermitRootLogin no\nPubkeyAuthentication yes\nPasswordAuthentication yes\nKbdInteractiveAuthentication no\nAllowUsers moshi-user backup-user\nAuthenticationMethods publickey\nPort 22'
	run_effective_sshd_policy_match "$effective_config" "22 2222" "moshi-user" || status=$?
	assert_status 1 "$status" "capitalized policy still rejects password authentication"

	status=0
	effective_config="${effective_config/PasswordAuthentication yes/PasswordAuthentication no}"
	run_effective_sshd_policy_match "$effective_config" "22" "moshi-user" || status=$?
	assert_status 1 "$status" "capitalized policy still rejects a non-exact port set"

	status=0
	run_effective_sshd_policy_match "$effective_config" "22 2222" "missing-user" || status=$?
	assert_status 1 "$status" "capitalized policy still requires the current user in AllowUsers"
}

run_migration() {
	local run_ssh_value="$1"
	local trace_file="$2"
	local output_file="$3"
	shift 3

	: >"$trace_file"
	(
		confirm_results=("$@")
		confirm_index=0
		record() { printf '%s\n' "$1" >>"$trace_file"; }
		section() { :; }
		warn() { :; }
		ok() { :; }
		write_sshd_dropin() { record "ports:$1"; }
		setup_easy_pair() { record "easy-pair"; }
		confirm() {
			local result="${confirm_results[$confirm_index]:-1}"
			record "confirm:$1"
			confirm_index=$((confirm_index + 1))
			return "$result"
		}
		sudo() { record "sudo:$*"; }

		orchestrate_ssh_migration "$run_ssh_value"
	) >"$output_file" 2>&1
}

test_runssh_false() {
	local trace="$temp_dir/runssh-false.trace"
	local output="$temp_dir/runssh-false.output"
	local status=0

	run_migration false "$trace" "$output" 0 || status=$?
	assert_status 0 "$status" "RunSSH=false succeeds after port-22 confirmation"
	assert_file_equals $'ports:22\neasy-pair\nconfirm:Did the new port-22 login succeed?' "$trace" "RunSSH=false runs Easy Pair after validated port 22"
	assert_not_contains "2222" "$trace" "RunSSH=false never requests the fallback port"
	assert_not_contains "tailscale set" "$trace" "RunSSH=false never disables Tailscale SSH"
}

test_runssh_true_success() {
	local trace="$temp_dir/runssh-true-success.trace"
	local output="$temp_dir/runssh-true-success.output"
	local status=0
	local expected_trace=""

	run_migration true "$trace" "$output" 0 0 0 || status=$?
	expected_trace=$'ports:22 2222\nconfirm:Did a new OpenSSH login on port 2222 succeed?\nconfirm:Disable Tailscale SSH now?\nsudo:tailscale set --ssh=false\neasy-pair\nconfirm:Did a new port-22 login succeed after disabling Tailscale SSH?\nports:22'
	assert_status 0 "$status" "RunSSH=true successful migration"
	assert_file_equals "$expected_trace" "$trace" "RunSSH=true preserves the confirmation and port-removal order"
}

test_failed_2222_confirmation() {
	local trace="$temp_dir/failed-2222.trace"
	local output="$temp_dir/failed-2222.output"
	local status=0

	run_migration true "$trace" "$output" 1 || status=$?
	assert_status 1 "$status" "failed port-2222 confirmation stops migration"
	assert_file_equals $'ports:22 2222\nconfirm:Did a new OpenSSH login on port 2222 succeed?' "$trace" "failed port-2222 confirmation keeps the fallback request"
	assert_not_contains "tailscale set" "$trace" "failed port-2222 confirmation keeps Tailscale SSH active"
	assert_contains "Tailscale SSH remains active and port 2222 remains available" "$output" "failed port-2222 confirmation explains the safe state"
}

test_failed_port_22_confirmation() {
	local trace="$temp_dir/failed-port-22.trace"
	local output="$temp_dir/failed-port-22.output"
	local status=0
	local expected_trace=""

	run_migration true "$trace" "$output" 0 0 1 || status=$?
	expected_trace=$'ports:22 2222\nconfirm:Did a new OpenSSH login on port 2222 succeed?\nconfirm:Disable Tailscale SSH now?\nsudo:tailscale set --ssh=false\neasy-pair\nconfirm:Did a new port-22 login succeed after disabling Tailscale SSH?'
	assert_status 1 "$status" "failed port-22 confirmation stops fallback removal"
	assert_file_equals "$expected_trace" "$trace" "failed port-22 confirmation leaves port 2222 configured"
	assert_contains "sudo tailscale set --ssh=true" "$output" "failed port-22 confirmation exposes the recovery command"
}

test_rollback_sequence() {
	local trace="$temp_dir/rollback.trace"
	local status=0

	: >"$trace"
	(
		restore_managed_sshd_dropin() { printf 'managed:%s:%s\n' "$1" "$2" >>"$trace"; }
		restore_owned_legacy_sshd_dropins() { printf 'legacy\n' >>"$trace"; }
		rollback_sshd_dropins "/tmp/managed-backup" true
	) || status=$?
	assert_status 0 "$status" "rollback helper succeeds"
	assert_file_equals $'managed:/tmp/managed-backup:true\nlegacy' "$trace" "rollback restores managed configuration before owned legacy configuration"
}

run_easy_pair_gate() {
	local confirmation_result="$1"
	local trace_file="$2"
	local output_file="$3"

	: >"$trace_file"
	(
		easy_pair_confirmed=false
		record() { printf '%s\n' "$1" >>"$trace_file"; }
		section() { :; }
		warn() { printf 'WARN: %s\n' "$1"; }
		ok() { :; }
		confirm() {
			record "confirm:$1"
			return "$confirmation_result"
		}
		moshi-hook() { record "moshi-hook:$*"; }

		if confirm_easy_pair; then
			setup_easy_pair
		fi
	) >"$output_file" 2>&1
}

test_easy_pair_confirmation_accepts() {
	local trace="$temp_dir/easy-pair-accept.trace"
	local output="$temp_dir/easy-pair-accept.output"
	local status=0

	run_easy_pair_gate 0 "$trace" "$output" || status=$?
	assert_status 0 "$status" "accepted Easy Pair confirmation succeeds"
	assert_file_equals $'confirm:Authorize a Moshi mobile device with Easy Pair after OpenSSH is validated?\nmoshi-hook:host setup' "$trace" "accepted Easy Pair runs the official host setup command only after confirmation"
	assert_contains "temporary access token" "$output" "Easy Pair confirmation warns about the QR trust boundary"
}

run_main_easy_pair_flow() {
	local confirmation_result="$1"
	local trace_file="$2"
	local output_file="$3"

	: >"$trace_file"
	(
		easy_pair_confirmed=false
		record() { printf '%s\n' "$1" >>"$trace_file"; }
		cleanup() { :; }
		section() { :; }
		warn() { printf 'WARN: %s\n' "$1"; }
		ok() { :; }
		validate_host_environment() { :; }
		require_command() { :; }
		validate_moshi_hook_version() { :; }
		confirm() {
			record "confirm:$1"
			return "$confirmation_result"
		}
		read_tailscale_state() {
			record "read-tailscale"
			run_ssh=false
		}
		sudo() { record "sudo:$*"; }
		install_moshi_hook() { record "install-moshi-hook"; }
		orchestrate_ssh_migration() { record "ssh-migration:$1"; }
		pair_and_install_hooks() { record "agent-hooks"; }
		check_mode() { record "check-mode"; }

		main
	) >"$output_file" 2>&1
}

test_easy_pair_confirmation_precedes_sudo() {
	local trace="$temp_dir/easy-pair-main-accept.trace"
	local output="$temp_dir/easy-pair-main-accept.output"
	local status=0

	run_main_easy_pair_flow 0 "$trace" "$output" || status=$?
	assert_status 0 "$status" "accepted Easy Pair entrypoint flow succeeds with test doubles"
	assert_file_equals $'read-tailscale\nconfirm:Authorize a Moshi mobile device with Easy Pair after OpenSSH is validated?\nsudo:-v\ninstall-moshi-hook\nssh-migration:false\nagent-hooks\ncheck-mode' "$trace" "entrypoint confirms Easy Pair before sudo and all mutating setup operations"
}

test_easy_pair_confirmation_declines_safely() {
	local trace="$temp_dir/easy-pair-main-decline.trace"
	local output="$temp_dir/easy-pair-main-decline.output"
	local status=0

	run_main_easy_pair_flow 1 "$trace" "$output" || status=$?
	assert_status 1 "$status" "declined Easy Pair stops the setup workflow"
	assert_file_equals $'read-tailscale\nconfirm:Authorize a Moshi mobile device with Easy Pair after OpenSSH is validated?' "$trace" "declined Easy Pair stops before installer, SSH, or agent-hook mutation"
	assert_not_contains "sudo:" "$trace" "declined Easy Pair never refreshes sudo credential state"
	assert_not_contains "install-moshi-hook" "$trace" "declined Easy Pair never starts installer setup"
	assert_not_contains "ssh-migration" "$trace" "declined Easy Pair never starts SSH or Tailscale mutation"
	assert_not_contains "agent-hooks" "$trace" "declined Easy Pair never changes agent-hook state"
	assert_contains "No installer, OpenSSH, Tailscale, or host-credential changes were made" "$output" "declined Easy Pair explains the unchanged state"
}

run_installer_install() {
	local expected_sha256="$1"
	local trace_file="$2"
	local output_file="$3"

	: >"$trace_file"
	(
		moshi_hook_installer_sha256="$expected_sha256"
		MOSHI_HOOK_VERSION="v0.0.0"
		record() { printf '%s\n' "$1" >>"$trace_file"; }
		new_temp_file() { temp_file_result="$installer_fixture"; }
		curl() { record "curl"; }
		sha256sum() {
			record "sha256sum"
			command sha256sum "$@"
		}
		bash() { record "bash"; }
		require_command() { record "require:$1"; }
		ok() { :; }

		install_moshi_hook
	) >"$output_file" 2>&1
}

test_installer_digest_match_and_order() {
	local trace="$temp_dir/installer-match.trace"
	local output="$temp_dir/installer-match.output"
	local status=0

	assert_equals "$expected_moshi_hook_installer_sha256" "$moshi_hook_installer_sha256" "repository installer pin"
	run_installer_install "$installer_fixture_sha256" "$trace" "$output" || status=$?
	assert_status 0 "$status" "matching installer digest is accepted"
	assert_file_equals $'curl\nsha256sum\nbash\nrequire:moshi-hook' "$trace" "installer verification runs before Bash execution"
	assert_equals "$expected_moshi_hook_installer_sha256" "$moshi_hook_installer_sha256" "installer pin is restored after matching test"
}

test_installer_digest_mismatch() {
	local trace="$temp_dir/installer-mismatch.trace"
	local output="$temp_dir/installer-mismatch.output"
	local status=0

	run_installer_install "$expected_moshi_hook_installer_sha256" "$trace" "$output" || status=$?
	assert_status 1 "$status" "mismatched installer digest fails closed"
	assert_file_equals $'curl\nsha256sum' "$trace" "mismatched installer never reaches Bash execution"
	assert_contains "Moshi installer SHA-256 mismatch" "$output" "mismatch explains the trust-boundary failure"
	assert_equals "$expected_moshi_hook_installer_sha256" "$moshi_hook_installer_sha256" "installer pin is restored after mismatch test"
}

test_installer_without_sha_tools() {
	local output="$temp_dir/installer-no-sha.output"
	local status=0

	(PATH="$temp_dir/no-sha-tools" verify_moshi_hook_installer "$installer_fixture") >"$output" 2>&1 || status=$?
	assert_status 1 "$status" "missing SHA-256 tooling fails closed"
	assert_contains "Neither sha256sum nor shasum is available" "$output" "missing verifier explains the fail-closed result"
	assert_equals "$expected_moshi_hook_installer_sha256" "$moshi_hook_installer_sha256" "PATH and installer pin are restored after unavailable-tool test"
}

test_installer_download_failure() {
	local trace="$temp_dir/installer-download-failure.trace"
	local output="$temp_dir/installer-download-failure.output"
	local status=0

	: >"$trace"
	(
		record() { printf '%s\n' "$1" >>"$trace"; }
		new_temp_file() { temp_file_result="$installer_fixture"; }
		curl() {
			record "curl"
			return 22
		}
		sha256sum() { record "sha256sum"; }
		bash() { record "bash"; }

		install_moshi_hook
	) >"$output" 2>&1 || status=$?
	assert_status 1 "$status" "failed installer download fails closed"
	assert_file_equals 'curl' "$trace" "failed installer download never reaches verification or execution"
	assert_contains "Could not download the Moshi installer" "$output" "download failure explains the trust-boundary stop"
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

run_test "legacy lowercase effective sshd policy" test_effective_sshd_policy_accepts_lowercase_keys
run_test "OpenSSH 10.5 capitalized effective sshd policy" test_effective_sshd_policy_accepts_capitalized_keys
run_test "incorrect effective sshd policy rejection" test_effective_sshd_policy_rejects_incorrect_policy
run_test "RunSSH=false port contract" test_runssh_false
run_test "RunSSH=true migration order" test_runssh_true_success
run_test "port-2222 confirmation gate" test_failed_2222_confirmation
run_test "port-22 confirmation recovery" test_failed_port_22_confirmation
run_test "sshd rollback helper order" test_rollback_sequence
run_test "Easy Pair explicit confirmation" test_easy_pair_confirmation_accepts
run_test "Easy Pair confirmation precedes sudo" test_easy_pair_confirmation_precedes_sudo
run_test "Easy Pair safe decline" test_easy_pair_confirmation_declines_safely
run_test "installer digest match and execution order" test_installer_digest_match_and_order
run_test "installer digest mismatch" test_installer_digest_mismatch
run_test "installer verifier unavailable" test_installer_without_sha_tools
run_test "installer download failure" test_installer_download_failure

if ((failures > 0)); then
	printf '%s of %s Moshi behavior tests failed.\n' "$failures" "$tests_run" >&2
	exit 1
fi

printf 'All %s Moshi behavior tests passed.\n' "$tests_run"
