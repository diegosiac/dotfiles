#!/usr/bin/env bash

warn_count=0
fail_count=0

if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    red="$(tput setaf 1 2>/dev/null || true)"
    green="$(tput setaf 2 2>/dev/null || true)"
    yellow="$(tput setaf 3 2>/dev/null || true)"
    blue="$(tput setaf 4 2>/dev/null || true)"
    bold="$(tput bold 2>/dev/null || true)"
    reset="$(tput sgr0 2>/dev/null || true)"
else
    red=""
    green=""
    yellow=""
    blue=""
    bold=""
    reset=""
fi

section() {
    printf '\n%s%s==> %s%s\n' "$bold" "$blue" "$1" "$reset"
}

ok() {
    printf '%sOK%s   %s\n' "$green" "$reset" "$1"
}

info() {
    printf '%sINFO%s %s\n' "$blue" "$reset" "$1"
}

warn() {
    warn_count=$((warn_count + 1))
    printf '%sWARN%s %s\n' "$yellow" "$reset" "$1"
}

fail() {
    fail_count=$((fail_count + 1))
    printf '%sFAIL%s %s\n' "$red" "$reset" "$1"
}

check_command() {
    local command_name="$1"
    local command_path=""

    if command_path="$(command -v "$command_name" 2>/dev/null)"; then
        ok "$command_name found at $command_path"
    else
        fail "Missing required command: $command_name"
    fi
}

check_optional_runtime_command() {
    local command_name="$1"
    local command_path=""

    if command_path="$(command -v "$command_name" 2>/dev/null)"; then
        ok "$command_name found at $command_path"
    else
        warn "$command_name is unavailable; skipping runtime diagnostic"
        return 1
    fi
}

print_gsetting() {
    local schema="$1"
    local key="$2"
    local value=""

    if value="$(gsettings get "$schema" "$key" 2>&1)"; then
        ok "$schema $key = $value"
    else
        warn "Could not read $schema $key: $value"
    fi
}

check_user_unit_status() {
    local unit="$1"
    local enabled_status=""
    local enabled_rc=0
    local active_status=""
    local active_rc=0

    enabled_status="$(systemctl --user is-enabled "$unit" 2>&1)"
    enabled_rc=$?
    active_status="$(systemctl --user is-active "$unit" 2>&1)"
    active_rc=$?

    if (( enabled_rc == 0 )); then
        ok "$unit user enabled status: $enabled_status"
    elif [[ "$enabled_status" == "disabled" ]]; then
        ok "$unit user enabled status: disabled (activation may happen through PAM, socket, or DBus)"
    else
        warn "$unit user enabled status: $enabled_status"
    fi

    if (( active_rc == 0 )); then
        ok "$unit user active status: $active_status"
    elif [[ "$active_status" == "inactive" ]]; then
        ok "$unit user active status: inactive (it may start on demand)"
    else
        warn "$unit user active status: $active_status"
    fi
}

check_system_unit_status() {
    local unit="$1"
    local enabled_status=""
    local enabled_rc=0
    local active_status=""
    local active_rc=0

    enabled_status="$(systemctl is-enabled "$unit" 2>&1)"
    enabled_rc=$?
    active_status="$(systemctl is-active "$unit" 2>&1)"
    active_rc=$?

    if (( enabled_rc == 0 )); then
        ok "$unit enabled status: $enabled_status"
    else
        warn "$unit enabled status: $enabled_status"
    fi

    if (( active_rc == 0 )); then
        ok "$unit active status: $active_status"
    else
        warn "$unit active status: $active_status"
    fi
}

check_dbus_name() {
    local name="$1"

    if command -v busctl >/dev/null 2>&1; then
        if busctl --user status "$name" >/dev/null 2>&1; then
            ok "DBus user name is available: $name"
        else
            warn "DBus user name is unavailable: $name"
        fi
    else
        warn "busctl is unavailable; skipping DBus user name check for $name"
    fi
}

check_systemd_user_env_var() {
    local env_output="$1"
    local var_name="$2"

    if grep -Eq "^${var_name}=" <<<"$env_output"; then
        ok "systemd user environment contains $var_name"
    else
        warn "systemd user environment is missing $var_name"
    fi
}

print_limited_lines() {
    local text="$1"
    local limit="$2"
    local line=""
    local count=0

    while IFS= read -r line; do
        count=$((count + 1))
        if (( count <= limit )); then
            printf '  %s\n' "$line"
        fi
    done <<<"$text"

    if (( count > limit )); then
        printf '  ... truncated %s more lines\n' "$((count - limit))"
    fi
}

check_failed_units() {
    local label="$1"
    shift
    local failed_output=""
    local failed_count=0

    if failed_output="$(systemctl "$@" --failed --no-pager 2>&1)"; then
        failed_count="$(grep -Ec '^[[:space:]●]*[^[:space:]]+[[:space:]]+loaded[[:space:]]+failed[[:space:]]+' <<<"$failed_output" || true)"
        if (( failed_count > 0 )); then
            warn "$label has failed units"
            print_limited_lines "$failed_output" 20
        else
            ok "$label has no failed units"
        fi
    else
        warn "Could not read $label failed units: $failed_output"
    fi
}

check_ssh_permissions() {
    local ssh_dir="$HOME/.ssh"
    local mode=""
    local basename=""

    if [[ ! -d "$ssh_dir" ]]; then
        ok "No $ssh_dir directory present"
        return
    fi

    mode="$(stat -c '%a' "$ssh_dir" 2>/dev/null || true)"
    if [[ -n "$mode" && $((8#$mode & 022)) -eq 0 ]]; then
        ok "$ssh_dir is not group/world writable"
    elif [[ -n "$mode" ]]; then
        warn "$ssh_dir is group/world writable (mode $mode)"
    else
        warn "Could not read permissions for $ssh_dir"
    fi

    while IFS= read -r -d '' key_file; do
        basename="${key_file##*/}"
        [[ "$basename" == *.pub || "$basename" == "known_hosts" || "$basename" == "authorized_keys" || "$basename" == "config" ]] && continue

        mode="$(stat -c '%a' "$key_file" 2>/dev/null || true)"
        if [[ -n "$mode" && $((8#$mode & 044)) -eq 0 ]]; then
            ok "$key_file is not group/world readable"
        elif [[ -n "$mode" ]]; then
            warn "$key_file is group/world readable (mode $mode)"
        else
            warn "Could not read permissions for $key_file"
        fi
    done < <(find "$ssh_dir" -maxdepth 1 -type f \( -name 'id_*' -o -name '*.pem' -o -name '*.key' \) -print0 2>/dev/null)
}

check_secret_patterns() {
    local pattern="-----BEGIN (RSA |DSA |EC |OPENSSH )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|gh[pousr]_[0-9A-Za-z]{36,}|xox[baprs]-[0-9A-Za-z-]{10,}|(api[_-]?key|token|secret)[[:space:]]*[:=][[:space:]]*[\"'][0-9A-Za-z_./+=-]{20,}"
    local matches=""
    local rc=0

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        warn "Not inside a git work tree; skipping tracked-file secret-pattern scan"
        return
    fi

    matches="$(git grep -nE -I "$pattern" -- 2>/dev/null)"
    rc=$?

    if (( rc == 0 )); then
        warn "Potential secret patterns found in tracked files"
        print_limited_lines "$matches" 20
    elif (( rc == 1 )); then
        ok "No obvious secret patterns found in tracked files"
    else
        warn "git grep secret-pattern scan failed"
    fi
}

section "System"
if [[ "$(uname -s 2>/dev/null)" == "Linux" && -f /etc/arch-release ]]; then
    ok "Arch Linux detected"
else
    fail "Arch Linux was not detected"
fi

if (( EUID == 0 )); then
    fail "Do not run this doctor as root"
else
    ok "Running as regular user: ${USER:-unknown}"
fi

section "Chezmoi"
if command -v chezmoi >/dev/null 2>&1; then
    if chezmoi doctor; then
        ok "chezmoi doctor passed"
    else
        warn "chezmoi doctor reported environment diagnostics; review output above"
    fi
else
    warn "chezmoi is not installed or not on PATH; skipping chezmoi doctor"
fi

section "Stock Omarchy Desktop"
if [[ -f "$HOME/.config/hypr/hyprland.lua" ]]; then
    ok "Stock Omarchy Hyprland config exists at $HOME/.config/hypr/hyprland.lua"
else
    fail "Missing stock Omarchy Hyprland config: $HOME/.config/hypr/hyprland.lua"
fi

section "Shell"
passwd_entry="$(getent passwd "${USER:-}" 2>/dev/null || true)"
login_shell="${passwd_entry##*:}"
if [[ -n "$passwd_entry" && "$login_shell" == */zsh ]]; then
    ok "Login shell is $login_shell"
elif [[ -n "$passwd_entry" ]]; then
    fail "Login shell is $login_shell, expected a path ending in zsh"
else
    fail "Could not read passwd entry for user ${USER:-unknown}"
fi

section "Commands"
for command_name in \
    Hyprland \
    hypridle \
    hyprlock \
    hyprctl \
    loginctl \
    systemd-inhibit \
    quickshell \
    greetd \
    tuigreet \
    dbus-update-activation-environment \
    gsettings \
    ghostty \
    wezterm \
    alacritty \
    mise \
    node \
    pnpm
do
    check_command "$command_name"
done

section "Idle, Lock, and Suspend"
if command -v pgrep >/dev/null 2>&1; then
    if pgrep -a hypridle >/dev/null 2>&1; then
        ok "hypridle process is running"
    else
        warn "hypridle process is not running"
    fi
else
    warn "pgrep is unavailable; skipping hypridle process check"
fi

if [[ -n "${XDG_SESSION_ID:-}" ]]; then
    if command -v loginctl >/dev/null 2>&1; then
        if loginctl show-session "$XDG_SESSION_ID" -p Type -p Active -p Remote -p LockedHint -p IdleHint; then
            ok "loginctl can read session $XDG_SESSION_ID lock/idle state"
        else
            warn "loginctl could not read session $XDG_SESSION_ID lock/idle state"
        fi
    else
        warn "loginctl is unavailable; skipping session lock/idle state check"
    fi
else
    warn "XDG_SESSION_ID is unset; skipping loginctl session lock/idle state check"
fi

if command -v systemd-inhibit >/dev/null 2>&1; then
    if systemd-inhibit --list >/dev/null 2>&1; then
        ok "systemd-inhibit can list active inhibitors"
    else
        warn "systemd-inhibit could not list active inhibitors"
    fi
else
    warn "systemd-inhibit is unavailable; skipping inhibitor check"
fi

section "Power Profiles"
if command -v powerprofilesctl >/dev/null 2>&1; then
    if powerprofiles_output="$(powerprofilesctl 2>&1)"; then
        ok "powerprofilesctl can read power profiles"
        print_limited_lines "$powerprofiles_output" 20
    else
        warn "powerprofilesctl is installed but could not read power profiles: $powerprofiles_output"
    fi

    if command -v systemctl >/dev/null 2>&1; then
        if powerprofiles_active="$(systemctl is-active power-profiles-daemon.service 2>&1)"; then
            ok "power-profiles-daemon.service active status: $powerprofiles_active"
        else
            warn "powerprofilesctl is installed but power-profiles-daemon.service is not active: $powerprofiles_active"
        fi
    else
        info "systemctl is unavailable; skipping power-profiles-daemon.service status"
    fi
else
    info "powerprofilesctl is unavailable; skipping power profile diagnostics"
fi

section "Node"
if node_path="$(command -v node 2>/dev/null)"; then
    ok "node path: $node_path"
    if [[ "$node_path" == *mise* ]]; then
        ok "node appears to come from mise"
    else
        warn "node does not appear to come from mise: $node_path"
    fi
else
    warn "node is unavailable; skipping mise path check"
fi

section "Theme"
if command -v gsettings >/dev/null 2>&1; then
    print_gsetting org.gnome.desktop.interface color-scheme
    print_gsetting org.gnome.desktop.interface gtk-theme
    print_gsetting org.gnome.desktop.interface cursor-theme
else
    warn "gsettings is unavailable; skipping theme checks"
fi

section "Notifications"
for command_name in \
    notify-send \
    swaync \
    swaync-client
do
    check_command "$command_name"
done

check_dbus_name org.freedesktop.Notifications

if command -v pgrep >/dev/null 2>&1; then
    if pgrep -a swaync >/dev/null 2>&1; then
        ok "swaync process is running"
    else
        warn "swaync process is not running"
    fi
else
    warn "pgrep is unavailable; skipping swaync process check"
fi

section "Audio, Bluetooth, and Network"
if command -v systemctl >/dev/null 2>&1; then
    check_system_unit_status NetworkManager.service
    check_system_unit_status bluetooth.service
else
    warn "systemctl is unavailable; skipping NetworkManager and Bluetooth service checks"
fi

if check_optional_runtime_command nmcli; then
    if nmcli general status >/dev/null 2>&1; then
        ok "nmcli general status can read NetworkManager state"
    else
        warn "nmcli general status could not read NetworkManager state"
    fi
fi

section "DNS"
if command -v nmcli >/dev/null 2>&1; then
    if nmcli_dns="$(nmcli general status 2>&1)"; then
        info "NetworkManager status:"
        print_limited_lines "$nmcli_dns" 6
    else
        info "NetworkManager status unavailable: $nmcli_dns"
    fi
else
    info "nmcli is unavailable; skipping NetworkManager DNS context"
fi

if [[ -L /etc/resolv.conf ]]; then
    resolv_target="$(readlink /etc/resolv.conf 2>/dev/null || true)"
    info "/etc/resolv.conf is a symlink to ${resolv_target:-unknown target}"
elif [[ -f /etc/resolv.conf ]]; then
    info "/etc/resolv.conf is a regular file"
else
    info "/etc/resolv.conf is missing or not a regular file/symlink"
fi

if command -v resolvectl >/dev/null 2>&1; then
    if resolvectl_status="$(resolvectl status 2>&1)"; then
        info "resolvectl status:"
        print_limited_lines "$resolvectl_status" 25
    else
        info "resolvectl status unavailable: $resolvectl_status"
    fi
else
    info "resolvectl is unavailable; skipping systemd-resolved DNS context"
fi

if check_optional_runtime_command bluetoothctl; then
    if bluetoothctl show >/dev/null 2>&1; then
        ok "bluetoothctl show can read controller state"
    else
        warn "bluetoothctl show could not read controller state"
    fi
fi

if check_optional_runtime_command wpctl; then
    if wpctl status >/dev/null 2>&1; then
        ok "wpctl status can read PipeWire/WirePlumber state"
    else
        warn "wpctl status could not read PipeWire/WirePlumber state"
    fi
fi

section "Screen Sharing and Portals"
if command -v systemctl >/dev/null 2>&1; then
    if systemd_user_env="$(systemctl --user show-environment 2>&1)"; then
        for env_var in \
            WAYLAND_DISPLAY \
            XDG_CURRENT_DESKTOP \
            XDG_SESSION_DESKTOP \
            XDG_SESSION_TYPE
        do
            check_systemd_user_env_var "$systemd_user_env" "$env_var"
        done

        if grep -Eq '^HYPRLAND_INSTANCE_SIGNATURE=' <<<"$systemd_user_env"; then
            ok "systemd user environment contains HYPRLAND_INSTANCE_SIGNATURE"
        else
            ok "systemd user environment does not contain optional HYPRLAND_INSTANCE_SIGNATURE"
        fi

        for unit in \
            pipewire.service \
            pipewire-pulse.service \
            wireplumber.service \
            xdg-desktop-portal.service \
            xdg-desktop-portal-hyprland.service
        do
            check_user_unit_status "$unit"
        done
    else
        warn "systemctl --user show-environment is unavailable; skipping portal environment and user unit checks: $systemd_user_env"
    fi
else
    warn "systemctl is unavailable; skipping portal environment and user unit checks"
fi

check_dbus_name org.freedesktop.portal.Desktop
check_dbus_name org.freedesktop.impl.portal.desktop.hyprland

if check_optional_runtime_command pactl; then
    if pactl info >/dev/null 2>&1; then
        ok "pactl info can read PulseAudio-compatible PipeWire state"
    else
        warn "pactl info could not read PulseAudio-compatible PipeWire state"
    fi
fi

if check_optional_runtime_command wayland-info; then
    if command -v timeout >/dev/null 2>&1; then
        if timeout 5s wayland-info >/dev/null 2>&1; then
            ok "wayland-info can query the compositor"
        else
            warn "wayland-info could not query the compositor"
        fi
    elif wayland-info >/dev/null 2>&1; then
        ok "wayland-info can query the compositor"
    else
        warn "wayland-info could not query the compositor"
    fi
fi

section "Keyring"
secret_service_available=0
if command -v secret-tool >/dev/null 2>&1; then
    ok "secret-tool found at $(command -v secret-tool)"
else
    warn "secret-tool is unavailable; install libsecret for Secret Service checks"
fi

if command -v busctl >/dev/null 2>&1; then
    if busctl --user status org.freedesktop.secrets >/dev/null 2>&1; then
        secret_service_available=1
        ok "DBus Secret Service name is available: org.freedesktop.secrets"
    else
        warn "DBus Secret Service name is unavailable or locked: org.freedesktop.secrets"
    fi
else
    warn "busctl is unavailable; skipping DBus Secret Service check"
fi

if command -v systemctl >/dev/null 2>&1; then
    if systemctl --user show-environment >/dev/null 2>&1; then
        check_user_unit_status gnome-keyring-daemon.service
        check_user_unit_status gnome-keyring-daemon.socket
    else
        warn "systemctl --user is unavailable for this session; skipping GNOME Keyring user unit checks"
    fi
else
    warn "systemctl is unavailable; skipping GNOME Keyring user unit checks"
fi

if (( secret_service_available == 1 )); then
    ok "Secret Service availability is the primary keyring signal"
fi

if command -v secret-tool >/dev/null 2>&1 && [[ "${DOTFILES_DOCTOR_KEYRING_SMOKE:-}" == "1" ]]; then
    smoke_id="smoke-test-$RANDOM-$(date +%s)"
    smoke_secret="dotfiles-doctor-$RANDOM-$(date +%s)"
    smoke_output="$(printf '%s' "$smoke_secret" | secret-tool store --label='dotfiles doctor temporary smoke test secret' dotfiles-doctor "$smoke_id" 2>&1)"
    smoke_store_rc=$?

    if (( smoke_store_rc == 0 )); then
        smoke_lookup="$(secret-tool lookup dotfiles-doctor "$smoke_id" 2>&1)"
        smoke_lookup_rc=$?
        smoke_clear_output="$(secret-tool clear dotfiles-doctor "$smoke_id" 2>&1)"
        smoke_clear_rc=$?

        if (( smoke_lookup_rc == 0 )) && [[ "$smoke_lookup" == "$smoke_secret" ]]; then
            ok "secret-tool temporary store/lookup smoke test passed"
        else
            warn "secret-tool temporary store/lookup smoke test failed: $smoke_lookup"
        fi

        if (( smoke_clear_rc == 0 )); then
            ok "secret-tool temporary smoke test secret cleared"
        else
            warn "secret-tool temporary smoke test clear failed: $smoke_clear_output"
        fi
    else
        warn "secret-tool temporary store smoke test skipped/failed; keyring may be locked or unavailable: $smoke_output"
    fi
elif command -v secret-tool >/dev/null 2>&1; then
    ok "Optional secret-tool temporary store/lookup/clear smoke test skipped; set DOTFILES_DOCTOR_KEYRING_SMOKE=1 to run it with a fake test secret"
fi

section "Services"
if command -v systemctl >/dev/null 2>&1; then
    enabled_status="$(systemctl is-enabled greetd.service 2>&1)"
    enabled_rc=$?
    active_status="$(systemctl is-active greetd.service 2>&1)"
    active_rc=$?

    if (( enabled_rc == 0 )); then
        ok "greetd.service enabled status: $enabled_status"
    else
        warn "greetd.service enabled status: $enabled_status"
    fi

    if (( active_rc == 0 )); then
        ok "greetd.service active status: $active_status"
    else
        warn "greetd.service active status: $active_status"
    fi
else
    warn "systemctl is unavailable; skipping greetd service checks"
fi

section "Moshi, OpenSSH, and Tailscale"
for command_name in ssh sshd ssh-keygen mosh; do
    if command -v "$command_name" >/dev/null 2>&1; then
        ok "$command_name is available"
    else
        fail "Missing Moshi access prerequisite: $command_name"
    fi
done

if command -v systemctl >/dev/null 2>&1; then
    check_system_unit_status tailscaled.service
    check_system_unit_status sshd.service
else
    warn "systemctl is unavailable; skipping tailscaled and sshd service checks"
fi

if command -v tailscale >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    if tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running" and (.Self.Online == true)' >/dev/null; then
        ok "Tailscale backend is running and this node is online"
    else
        warn "Tailscale is not both running and online"
    fi

    tailscale_run_ssh="$(tailscale debug prefs 2>/dev/null | jq -r 'if (.RunSSH | type) == "boolean" then (.RunSSH | tostring) else "unknown" end' 2>/dev/null || printf 'unknown')"
    if [[ "$tailscale_run_ssh" == "true" || "$tailscale_run_ssh" == "false" ]]; then
        ok "Tailscale RunSSH: $tailscale_run_ssh"
    else
        warn "Tailscale RunSSH could not be read from structured preferences"
    fi
else
    warn "tailscale or jq is unavailable; skipping sanitized Tailscale state checks"
fi

if command -v sshd >/dev/null 2>&1; then
    if sudo -n sshd -t >/dev/null 2>&1; then
        ok "sshd configuration syntax is valid"
        sshd_host="$(uname -n 2>/dev/null || printf localhost)"
        effective_sshd_config="$(sudo -n sshd -T -C "user=${USER:-unknown},host=$sshd_host,addr=127.0.0.1" 2>/dev/null || true)"
        if [[ -n "$effective_sshd_config" ]] \
            && awk -v user="${USER:-unknown}" '
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
            ' <<<"$effective_sshd_config"; then
            ok "Effective sshd configuration enforces the Moshi hardening policy"
        else
            warn "Effective sshd configuration could not be verified or does not enforce the complete Moshi hardening policy"
        fi
    else
        warn "Could not validate sshd non-interactively; run 'sudo sshd -t' and inspect 'sudo sshd -T'"
    fi
fi

if command -v moshi-hook >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    ok "moshi-hook is available"
    moshi_status="$(moshi-hook status --json 2>/dev/null | jq -c '{paired: (.paired == true), hooks: [.hooks[]? | select(.target == "pi" or .target == "claude" or .target == "codex" or .target == "opencode" or .target == "grok") | {target, status}]}' 2>/dev/null || true)"
    if [[ -n "$moshi_status" ]] && [[ "$(jq -r '.paired' <<<"$moshi_status" 2>/dev/null)" == "true" ]]; then
        ok "moshi-hook reports agent-hook paired state"
    else
        warn "moshi-hook does not report agent-hook paired state"
    fi

    for hook_target in pi claude codex opencode grok; do
        hook_status="$(jq -r --arg target "$hook_target" '[.hooks[]? | select(.target == $target) | .status] | first // "missing"' <<<"$moshi_status" 2>/dev/null || printf 'unknown')"
        if [[ "$hook_status" == "installed" || "$hook_status" == "ok" || "$hook_status" == "current" ]]; then
            ok "moshi-hook target $hook_target status: $hook_status"
        else
            warn "moshi-hook target $hook_target status: $hook_status"
        fi
    done
    unset moshi_status hook_status

    if moshi-hook probe --json 2>/dev/null | jq -e '.installed == true and .running == true' >/dev/null; then
        ok "moshi-hook daemon probe reports installed and running"
    else
        warn "moshi-hook daemon probe did not report installed and running"
    fi

    if command -v systemctl >/dev/null 2>&1; then
        check_user_unit_status moshi-hook.service
    fi
else
    warn "moshi-hook or jq is unavailable; skipping structured Moshi checks"
fi

if command -v herdr >/dev/null 2>&1; then
    ok "Herdr is available for Moshi terminal context detection"
else
    warn "Herdr is unavailable; Moshi can still use another supported terminal context"
fi

if command -v loginctl >/dev/null 2>&1; then
    linger_state="$(loginctl show-user "${USER:-}" -p Linger --value 2>/dev/null || true)"
    if [[ "$linger_state" == "yes" ]]; then
        ok "User lingering is enabled"
    else
        warn "User lingering is disabled; moshi-hook may stop after logout"
    fi
else
    warn "loginctl is unavailable; skipping linger check"
fi

section "Security"
firewall_command_found=0
if command -v ufw >/dev/null 2>&1; then
    firewall_command_found=1
    if ufw_status="$(ufw status 2>&1)" && grep -qi '^Status: active' <<<"$ufw_status"; then
        ok "ufw status is active"
    else
        warn "ufw is present but not active or status is unavailable"
    fi
fi

if command -v firewall-cmd >/dev/null 2>&1; then
    firewall_command_found=1
    if firewall_state="$(firewall-cmd --state 2>&1)" && [[ "$firewall_state" == "running" ]]; then
        ok "firewalld status is running"
    else
        warn "firewalld is present but not running or status is unavailable"
    fi
fi

if command -v nft >/dev/null 2>&1; then
    firewall_command_found=1
    if nft_output="$(nft list ruleset 2>&1)"; then
        if [[ -n "$nft_output" ]]; then
            ok "nft is present and can list a ruleset"
        else
            warn "nft is present but the ruleset appears empty"
        fi
    else
        warn "nft is present but ruleset status is unavailable"
    fi
fi

if (( firewall_command_found == 0 )); then
    ok "No firewall manager command found; not required by this doctor"
fi

if command -v ss >/dev/null 2>&1; then
    if ss_output="$(ss -tulpen 2>&1)"; then
        warn "Listening sockets from ss -tulpen (review exposed services)"
        print_limited_lines "$ss_output" 25
    else
        warn "ss -tulpen failed: $ss_output"
    fi
else
    warn "ss is unavailable; skipping listening socket check"
fi

if command -v systemctl >/dev/null 2>&1; then
    check_failed_units "system units"
    check_failed_units "user units" --user
else
    warn "systemctl is unavailable; skipping failed unit checks"
fi

check_ssh_permissions
check_secret_patterns

section "AUR"
if command -v paru >/dev/null 2>&1; then
    if paru_version="$(paru --version 2>&1)"; then
        ok "paru is available"
        print_limited_lines "$paru_version" 3
    else
        info "paru is present but version output is unavailable: $paru_version"
    fi
else
    info "paru is unavailable; AUR packages remain optional"
fi

if command -v pacman >/dev/null 2>&1; then
    foreign_packages="$(pacman -Qm 2>/dev/null || true)"
    if [[ -n "$foreign_packages" ]]; then
        foreign_count="$(grep -c '^' <<<"$foreign_packages")"
        info "Foreign packages installed: $foreign_count"
        print_limited_lines "$foreign_packages" 25
    else
        info "No foreign packages reported by pacman -Qm"
    fi
else
    info "pacman is unavailable; skipping foreign package list"
fi

section "Summary"
printf 'Warnings: %s\n' "$warn_count"
printf 'Failures: %s\n' "$fail_count"

if (( fail_count > 0 )); then
    exit 1
fi

exit 0
