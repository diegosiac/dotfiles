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

section "Desktop Files"
if [[ -f "$HOME/.config/hypr/hyprland.conf" ]]; then
    ok "Hyprland config exists at $HOME/.config/hypr/hyprland.conf"
else
    fail "Missing Hyprland config: $HOME/.config/hypr/hyprland.conf"
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
    quickshell \
    greetd \
    tuigreet \
    dbus-update-activation-environment \
    gsettings \
    ghostty \
    wezterm \
    alacritty \
    fnm \
    node \
    pnpm
do
    check_command "$command_name"
done

section "Node"
if node_path="$(command -v node 2>/dev/null)"; then
    ok "node path: $node_path"
    if [[ "$node_path" == *fnm* ]]; then
        ok "node appears to come from fnm"
    else
        warn "node does not appear to come from fnm: $node_path"
    fi
else
    warn "node is unavailable; skipping fnm path check"
fi

section "Theme"
if command -v gsettings >/dev/null 2>&1; then
    print_gsetting org.gnome.desktop.interface color-scheme
    print_gsetting org.gnome.desktop.interface gtk-theme
    print_gsetting org.gnome.desktop.interface cursor-theme
else
    warn "gsettings is unavailable; skipping theme checks"
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

if check_optional_runtime_command wpctl; then
    if wpctl status >/dev/null 2>&1; then
        ok "wpctl status can read PipeWire/WirePlumber state"
    else
        warn "wpctl status could not read PipeWire/WirePlumber state"
    fi
fi

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

section "Summary"
printf 'Warnings: %s\n' "$warn_count"
printf 'Failures: %s\n' "$fail_count"

if (( fail_count > 0 )); then
    exit 1
fi

exit 0
