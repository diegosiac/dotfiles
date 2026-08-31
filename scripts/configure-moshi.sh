#!/usr/bin/env bash
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	set -euo pipefail
fi

bold="$(tput bold 2>/dev/null || true)"
reset="$(tput sgr0 2>/dev/null || true)"
red="$(tput setaf 1 2>/dev/null || true)"
green="$(tput setaf 2 2>/dev/null || true)"
yellow="$(tput setaf 3 2>/dev/null || true)"
blue="$(tput setaf 4 2>/dev/null || true)"

temp_files=()
removed_legacy_sshd_dropins=()
easy_pair_confirmed=false
managed_sshd_dropin="/etc/ssh/sshd_config.d/00-moshi.conf"
managed_sshd_marker="# Managed by dotfiles scripts/configure-moshi.sh"
moshi_hook_installer_url="https://getmoshi.app/install.sh"
# Trust boundary: review upstream installer changes before consciously updating this digest.
moshi_hook_installer_sha256="95f05fe8d4525bef32c557eede09ecd0e4414f8d0eba8c3a65a866a409134432"

cleanup() {
	local file
	for file in "${temp_files[@]}"; do
		[[ -e "$file" ]] || continue
		if command -v shred >/dev/null 2>&1; then
			shred -u -- "$file" 2>/dev/null || rm -f -- "$file"
		else
			rm -f -- "$file"
		fi
	done
}
section() {
	printf '\n%s%s==> %s%s\n' "$bold" "$blue" "$1" "$reset"
}

ok() {
	printf '%s✓%s %s\n' "$green" "$reset" "$1"
}

warn() {
	printf '%s[WARN]%s %s\n' "$yellow" "$reset" "$1"
}

fail() {
	printf '%s[ERROR]%s %s\n' "$red" "$reset" "$1" >&2
	exit 1
}

confirm() {
	local prompt="$1"
	local answer=""

	printf '%s [y/N] ' "$prompt"
	read -r answer
	[[ "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" || "$answer" == "YES" ]]
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

new_temp_file() {
	temp_file_result="$(mktemp)"
	chmod 0600 "$temp_file_result"
	temp_files+=("$temp_file_result")
}

effective_sshd_policy_matches() {
	local effective_config="$1"
	local ports="${2:-}"
	local expected_ports=""
	local actual_ports=""

	awk -v user="$USER" '
		tolower($1) == "permitrootlogin" && NF == 2 && $2 == "no" { permit_root_login = 1 }
		tolower($1) == "pubkeyauthentication" && NF == 2 && $2 == "yes" { pubkey_authentication = 1 }
		tolower($1) == "passwordauthentication" && NF == 2 && $2 == "no" { password_authentication = 1 }
		tolower($1) == "kbdinteractiveauthentication" && NF == 2 && $2 == "no" { keyboard_authentication = 1 }
		tolower($1) == "authenticationmethods" && NF == 2 && $2 == "publickey" { authentication_methods = 1 }
		tolower($1) == "allowusers" {
			for (i = 2; i <= NF; i++) {
				if ($i == user) allowed_user = 1
			}
		}
		END {
			exit !(permit_root_login && pubkey_authentication && password_authentication && keyboard_authentication && authentication_methods && allowed_user)
		}
	' <<<"$effective_config" || return 1

	if [[ -n "$ports" ]]; then
		expected_ports="$(tr ' ' '\n' <<<"$ports" | sort -nu | paste -sd ' ' -)"
		actual_ports="$(awk 'tolower($1) == "port" && NF == 2 { print $2 }' <<<"$effective_config" | sort -nu | paste -sd ' ' -)"
		[[ "$actual_ports" == "$expected_ports" ]] || return 1
	fi
}

read_tailscale_state() {
	systemctl is-active --quiet tailscaled.service || fail "tailscaled.service is not active. Start the service, authenticate through your approved Tailscale flow, then rerun this script."

	if ! tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running" and (.Self.Online == true)' >/dev/null; then
		fail "Tailscale is not authenticated and online. This script never runs 'tailscale up'; authenticate separately, confirm connectivity, then rerun it."
	fi

	run_ssh="$(tailscale debug prefs 2>/dev/null | jq -er 'if (.RunSSH | type) == "boolean" then (.RunSSH | tostring) else error("missing RunSSH") end')" || fail "Could not read boolean RunSSH from structured Tailscale preferences. Refusing to guess."
	ok "Tailscale is authenticated and online; structured RunSSH preference was read without displaying identity data."
}

check_mode() {
	local effective_sshd_config=""
	local sanitized_status=""
	local run_ssh_value="unknown"
	local sshd_host=""

	section "Moshi workflow diagnostics (read-only)"
	for command_name in ssh sshd ssh-keygen mosh tailscale jq curl systemctl; do
		if command -v "$command_name" >/dev/null 2>&1; then
			ok "$command_name is available."
		else
			warn "$command_name is unavailable."
		fi
	done

	if systemctl is-active --quiet tailscaled.service 2>/dev/null; then
		ok "tailscaled.service is active."
	else
		warn "tailscaled.service is not active."
	fi

	if command -v tailscale >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
		if tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running" and (.Self.Online == true)' >/dev/null; then
			ok "Tailscale backend is running and this node is online."
		else
			warn "Tailscale is not both running and online."
		fi

		run_ssh_value="$(tailscale debug prefs 2>/dev/null | jq -r 'if (.RunSSH | type) == "boolean" then (.RunSSH | tostring) else "unknown" end' 2>/dev/null || printf 'unknown')"
		if [[ "$run_ssh_value" == "true" || "$run_ssh_value" == "false" ]]; then
			ok "Tailscale RunSSH: $run_ssh_value."
		else
			warn "Tailscale structured preferences are unavailable."
		fi
	fi

	if command -v sshd >/dev/null 2>&1; then
		if sudo -n sshd -t >/dev/null 2>&1; then
			ok "sshd configuration syntax is valid."
			sshd_host="$(uname -n 2>/dev/null || printf localhost)"
			if effective_sshd_config="$(sudo -n sshd -T -C "user=$USER,host=$sshd_host,addr=127.0.0.1" 2>/dev/null)"; then
				if effective_sshd_policy_matches "$effective_sshd_config"; then
					ok "Effective sshd configuration enforces the Moshi hardening policy."
				else
					warn "Effective sshd configuration does not enforce the complete Moshi hardening policy."
				fi
			else
				warn "Could not inspect effective sshd configuration non-interactively."
			fi
		else
			warn "Could not validate sshd non-interactively; run 'sudo sshd -t' and inspect 'sudo sshd -T'."
		fi
	fi

	if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet sshd.service 2>/dev/null; then
		ok "sshd.service is active."
	else
		warn "sshd.service is not active."
	fi

	if command -v moshi-hook >/dev/null 2>&1; then
		ok "moshi-hook is installed."
		sanitized_status="$(moshi-hook status --json 2>/dev/null | jq -c '{paired: (.paired == true), hooks: [.hooks[]? | select(.target == "pi" or .target == "claude" or .target == "codex" or .target == "opencode" or .target == "grok") | {target, status}]}' 2>/dev/null || true)"
		if [[ -n "$sanitized_status" ]]; then
			if [[ "$(jq -r '.paired' <<<"$sanitized_status")" == "true" ]]; then
				ok "moshi-hook reports agent-hook paired state."
			else
				warn "moshi-hook is not paired for agent hooks."
			fi
			jq -r '.hooks[] | "hook " + .target + ": " + .status' <<<"$sanitized_status"
		else
			warn "moshi-hook structured status is unavailable."
		fi

		if moshi-hook probe --json 2>/dev/null | jq -e '.installed == true and .running == true' >/dev/null; then
			ok "moshi-hook daemon is installed and running."
		else
			warn "moshi-hook daemon probe did not report installed and running."
		fi
	else
		warn "moshi-hook is not installed."
	fi

	if loginctl show-user "$USER" -p Linger --value 2>/dev/null | grep -qx yes; then
		ok "User lingering is enabled."
	else
		warn "User lingering is disabled; the user service may stop after logout."
	fi
}

validate_moshi_hook_version() {
	if [[ "${MOSHI_HOOK_VERSION:-}" == "latest" ]]; then
		fail "Do not set MOSHI_HOOK_VERSION=latest; upstream would interpret it as vlatest. Leave it unset for the latest release, or set an explicit value such as vX.Y.Z."
	fi
	if [[ -n "${MOSHI_HOOK_VERSION:-}" && ! "${MOSHI_HOOK_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		fail "MOSHI_HOOK_VERSION must be unset or an explicit vX.Y.Z release."
	fi
}

verify_moshi_hook_installer() {
	local actual_sha256=""
	local checksum_output=""
	local installer="$1"

	if command -v sha256sum >/dev/null 2>&1; then
		checksum_output="$(sha256sum -- "$installer")" || fail "Could not calculate the Moshi installer SHA-256. Refusing to execute it."
	elif command -v shasum >/dev/null 2>&1; then
		checksum_output="$(shasum -a 256 -- "$installer")" || fail "Could not calculate the Moshi installer SHA-256. Refusing to execute it."
	else
		fail "Neither sha256sum nor shasum is available. Refusing to execute an unverified Moshi installer."
	fi

	actual_sha256="${checksum_output%%[[:space:]]*}"
	[[ "$actual_sha256" == "$moshi_hook_installer_sha256" ]] || fail "Moshi installer SHA-256 mismatch. Refusing to execute it; review the upstream change before updating the pinned digest."
}

install_moshi_hook() {
	local installer=""

	new_temp_file
	installer="$temp_file_result"
	curl --proto '=https' --tlsv1.2 -fsSL "$moshi_hook_installer_url" -o "$installer" || fail "Could not download the Moshi installer over verified HTTPS. Refusing to continue."
	verify_moshi_hook_installer "$installer"
	if [[ -n "${MOSHI_HOOK_VERSION:-}" ]]; then
		MOSHI_HOOK_VERSION="$MOSHI_HOOK_VERSION" bash "$installer"
	else
		env -u MOSHI_HOOK_VERSION bash "$installer"
	fi
	hash -r
	require_command moshi-hook
	ok "moshi-hook installed after verifying the pinned installer SHA-256; upstream asset checksum behavior was preserved."
}

confirm_easy_pair() {
	section "Moshi Easy Pair confirmation"
	warn "Easy Pair starts a new host authorization. On reruns, continue only when you intentionally want to authorize a mobile-generated key."
	warn "The QR code displayed by Easy Pair is a temporary access token. Treat it as a secret: do not share, record, or capture it."
	printf '%s\n' "The private key is generated on the mobile device. Only its public key is sent to this host and installed in authorized_keys."

	if confirm "Authorize a Moshi mobile device with Easy Pair after OpenSSH is validated?"; then
		easy_pair_confirmed=true
		return 0
	fi

	warn "Easy Pair declined. No installer, OpenSSH, Tailscale, or host-credential changes were made."
	return 1
}

setup_easy_pair() {
	[[ "$easy_pair_confirmed" == true ]] || fail "Easy Pair was not explicitly confirmed. Refusing to create or replace host authorization state."

	section "Moshi Easy Pair host authorization"
	warn "The next command displays the temporary-access QR. Scan it only with the intended Moshi mobile device."
	if ! moshi-hook host setup; then
		fail "Moshi Easy Pair host setup failed. Keep this session open and inspect authorized_keys before retrying; during a Tailscale SSH migration, port 2222 remains available for recovery."
	fi
	ok "Easy Pair authorized the mobile-generated public key. The private key remained on the mobile device."
}

sshd_dropin_is_owned() {
	local config_file="$1"
	local first_line=""

	first_line="$(sudo awk 'NR == 1 { print; exit }' "$config_file" 2>/dev/null || true)"
	[[ "$first_line" == "$managed_sshd_marker" ]]
}

restore_managed_sshd_dropin() {
	local backup_file="$1"
	local was_present="$2"

	if [[ -n "$backup_file" ]]; then
		sudo cp -p "$backup_file" "$managed_sshd_dropin"
	elif [[ "$was_present" == false ]]; then
		sudo rm -f -- "$managed_sshd_dropin"
	fi
}

remove_owned_legacy_sshd_dropins() {
	local timestamp="$1"
	local legacy_backup=""
	local legacy_file=""
	removed_legacy_sshd_dropins=()

	for legacy_file in \
		/etc/ssh/sshd_config.d/10-moshi.conf \
		/etc/ssh/sshd_config.d/90-moshi.conf; do
		[[ "$legacy_file" == "$managed_sshd_dropin" ]] && continue
		sudo test -f "$legacy_file" || continue
		if sshd_dropin_is_owned "$legacy_file"; then
			legacy_backup="$legacy_file.bak.$timestamp"
			sudo cp -p "$legacy_file" "$legacy_backup" || return 1
			sudo rm -- "$legacy_file" || return 1
			removed_legacy_sshd_dropins+=("$legacy_file|$legacy_backup")
			warn "Migrated repository-owned legacy drop-in $legacy_file; backup: $legacy_backup"
		else
			warn "Leaving unowned SSH configuration unchanged: $legacy_file"
		fi
	done
}

restore_owned_legacy_sshd_dropins() {
	local entry=""
	local legacy_backup=""
	local legacy_file=""

	for entry in "${removed_legacy_sshd_dropins[@]}"; do
		legacy_file="${entry%%|*}"
		legacy_backup="${entry#*|}"
		sudo cp -p "$legacy_backup" "$legacy_file"
	done
}

rollback_sshd_dropins() {
	local backup_file="$1"
	local managed_dropin_was_present="$2"

	restore_managed_sshd_dropin "$backup_file" "$managed_dropin_was_present"
	restore_owned_legacy_sshd_dropins
}

write_sshd_dropin() {
	local ports="$1"
	local backup_file=""
	local config_changed=true
	local config_temp=""
	local effective_config=""
	local managed_dropin_was_present=false
	local sshd_host=""
	local timestamp=""
	local port=""

	new_temp_file
	config_temp="$temp_file_result"
	{
		printf '%s\n' "$managed_sshd_marker"
		for port in $ports; do
			printf 'Port %s\n' "$port"
		done
		printf 'PermitRootLogin no\n'
		printf 'PubkeyAuthentication yes\n'
		printf 'PasswordAuthentication no\n'
		printf 'KbdInteractiveAuthentication no\n'
		printf 'AuthenticationMethods publickey\n'
		printf 'AllowUsers %s\n' "$USER"
	} >"$config_temp"

	sudo install -d -m 0755 /etc/ssh/sshd_config.d
	if sudo test -f "$managed_sshd_dropin" && ! sshd_dropin_is_owned "$managed_sshd_dropin"; then
		fail "Refusing to replace unowned SSH configuration at $managed_sshd_dropin. Move or reconcile it manually, then retry."
	fi
	if sudo test -f "$managed_sshd_dropin"; then
		managed_dropin_was_present=true
	fi

	timestamp="$(date +%Y%m%d-%H%M%S-%N)"
	if sudo test -f "$managed_sshd_dropin" && sudo cmp -s "$config_temp" "$managed_sshd_dropin"; then
		config_changed=false
		ok "OpenSSH hardening drop-in already has the requested ports."
	elif sudo test -f "$managed_sshd_dropin"; then
		backup_file="$managed_sshd_dropin.bak.$timestamp"
		sudo cp -p "$managed_sshd_dropin" "$backup_file"
		warn "Rollback backup: $backup_file"
	else
		warn "Rollback for this first install: remove $managed_sshd_dropin, run 'sudo sshd -t', then reload sshd."
	fi

	if [[ "$config_changed" == true ]]; then
		sudo install -m 0644 -o root -g root "$config_temp" "$managed_sshd_dropin"
	fi
	sudo ssh-keygen -A
	if ! sudo sshd -t; then
		restore_managed_sshd_dropin "$backup_file" "$managed_dropin_was_present"
		fail "sshd syntax validation failed; the managed drop-in was rolled back. Existing sessions were not closed."
	fi

	if ! remove_owned_legacy_sshd_dropins "$timestamp"; then
		rollback_sshd_dropins "$backup_file" "$managed_dropin_was_present"
		fail "Could not migrate repository-owned legacy SSH configuration; completed changes were rolled back. Existing sessions were not closed."
	fi
	if ! sudo sshd -t; then
		rollback_sshd_dropins "$backup_file" "$managed_dropin_was_present"
		fail "sshd validation failed after legacy migration; managed and legacy drop-ins were rolled back. Existing sessions were not closed."
	fi

	sshd_host="$(uname -n 2>/dev/null || printf localhost)"
	if ! effective_config="$(sudo sshd -T -C "user=$USER,host=$sshd_host,addr=127.0.0.1")"; then
		rollback_sshd_dropins "$backup_file" "$managed_dropin_was_present"
		fail "Could not inspect effective sshd configuration; managed and legacy drop-ins were rolled back. Existing sessions were not closed."
	fi
	if ! effective_sshd_policy_matches "$effective_config" "$ports"; then
		rollback_sshd_dropins "$backup_file" "$managed_dropin_was_present"
		fail "Effective sshd configuration does not match the requested ports and hardening policy; managed and legacy drop-ins were rolled back. Resolve earlier or additive unowned directives before retrying."
	fi

	sudo systemctl enable sshd.service
	if [[ "$config_changed" == false && ${#removed_legacy_sshd_dropins[@]} -eq 0 ]] && systemctl is-active --quiet sshd.service; then
		ok "Effective OpenSSH configuration already matches the requested state."
	elif systemctl is-active --quiet sshd.service; then
		sudo systemctl reload sshd.service
	else
		sudo systemctl start sshd.service
	fi
	ok "Validated and applied hardened OpenSSH ports: $ports. Existing sessions remain open."
}

pair_and_install_hooks() {
	local paired=""

	section "Moshi agent pairing and hooks"
	paired="$(moshi-hook status --json 2>/dev/null | jq -er 'if (.paired | type) == "boolean" then (.paired | tostring) else error("missing paired state") end')" || fail "Could not read Moshi paired state. Refusing to replace pairing credentials implicitly."
	if [[ "$paired" == "true" ]]; then
		ok "Existing Moshi agent-hook pairing preserved. Use --rotate-pairing only when intentionally replacing pairing credentials."
	else
		pair_moshi_hook
	fi

	moshi-hook install --target pi,claude,codex,opencode,grok
	moshi-hook service install
	ok "Installed exactly the pi, claude, codex, opencode, and grok hooks and the user service."

	cat <<'EOF'
User lingering keeps systemd user services running after logout and allows them
to start at boot without an interactive login. It is optional and changes
per-user systemd lifecycle behavior.
EOF
	if confirm "Enable lingering for the current user?"; then
		sudo loginctl enable-linger "$USER"
		ok "User lingering enabled."
	else
		warn "Lingering remains unchanged."
	fi
}

pair_moshi_hook() {
	local pairing_token=""

	printf 'Paste the Moshi pairing token (input is hidden and is not stored in shell history): '
	IFS= read -rs pairing_token
	printf '\n'
	[[ -n "$pairing_token" ]] || fail "A pairing token is required."
	moshi-hook pair --token "$pairing_token"
	unset pairing_token
}

rotate_pairing() {
	((EUID != 0)) || fail "Run this action as a regular user, not as root."
	require_command moshi-hook
	section "Explicit Moshi pairing rotation"
	warn "This replaces the existing hook pairing credentials and requires updating the matching Moshi app pairing."
	confirm "Rotate Moshi hook pairing credentials now?" || fail "Pairing rotation cancelled; existing credentials were not changed."
	pair_moshi_hook
	ok "Moshi hook pairing credentials rotated explicitly."
}

orchestrate_ssh_migration() {
	local run_ssh_value="$1"

	if [[ "$run_ssh_value" == "false" ]]; then
		section "OpenSSH setup (Tailscale SSH is already disabled)"
		write_sshd_dropin "22"
		setup_easy_pair
		warn "Keep this session open. Test a NEW port-22 SSH/Moshi login from another client."
		confirm "Did the new port-22 login succeed?" || fail "Port-22 success was not confirmed. Tailscale SSH was not changed; use the rollback guidance above before retrying."
		return
	fi

	section "OpenSSH migration while Tailscale SSH remains active"
	write_sshd_dropin "22 2222"
	warn "Easy Pair cannot run while Tailscale SSH intercepts port 22. Use an existing OpenSSH credential for the port-2222 safety test before Tailscale SSH is disabled."
	warn "Tailscale SSH remains active. Keep this session open and test OpenSSH through port 2222 from Moshi or another client."
	confirm "Did a new OpenSSH login on port 2222 succeed?" || fail "Port-2222 success was not confirmed. Tailscale SSH remains active and port 2222 remains available for diagnosis."

	warn "The next step disables ONLY Tailscale SSH. It does not run 'tailscale down' or change tailnet connectivity."
	confirm "Disable Tailscale SSH now?" || fail "Tailscale SSH remains active; no further migration changes were made."
	sudo tailscale set --ssh=false
	ok "Tailscale SSH disabled."

	setup_easy_pair
	warn "Keep this session open. Test a NEW port-22 OpenSSH/Moshi login before port 2222 is removed."
	confirm "Did a new port-22 login succeed after disabling Tailscale SSH?" || fail "Port-22 success was not confirmed. Port 2222 remains configured; re-enable Tailscale SSH with 'sudo tailscale set --ssh=true' if rollback is needed."
	write_sshd_dropin "22"
	ok "Temporary port 2222 removed after explicit port-22 confirmation."
}

preflight_moshi() {
	section "Preflight"
	read_tailscale_state
	confirm_easy_pair || fail "Easy Pair was cancelled before any setup changes were made."
}

configure_moshi() {
	install_moshi_hook
	orchestrate_ssh_migration "$run_ssh"
	pair_and_install_hooks
	section "Sanitized verification"
	check_mode

	cat <<'EOF'
Setup finished. Easy Pair authorization, host keys, Moshi pairing/service/hook
state, Tailscale state, linger state, logs, IDs, and phone settings are local
machine state and must never be copied into this repository.
EOF
}

validate_host_environment() {
	[[ "$(uname -s)" == "Linux" && -f /etc/arch-release ]] || fail "This setup supports Arch Linux only."
	((EUID != 0)) || fail "Run this script as a regular user with sudo access, not as root."
}

main() {
	local command_name=""

	trap cleanup EXIT HUP INT TERM
	if [[ "${1:-}" == "--check" ]]; then
		check_mode
		return
	elif [[ "${1:-}" == "--rotate-pairing" ]]; then
		rotate_pairing
		return
	elif (($# > 0)); then
		fail "Usage: $0 [--check|--rotate-pairing]"
	fi

	validate_host_environment

	for command_name in sudo curl jq ssh sshd ssh-keygen systemctl tailscale mosh; do
		require_command "$command_name"
	done
	validate_moshi_hook_version
	preflight_moshi
	sudo -v
	configure_moshi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
