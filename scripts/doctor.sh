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
        fail "chezmoi doctor reported problems"
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
