#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]] || [[ ! -f /etc/arch-release ]]; then
    echo "This script only supports Arch Linux."
    exit 1
fi

missing=()
for command in greetd tuigreet start-hyprland; do
    if ! command -v "$command" >/dev/null 2>&1; then
        missing+=("$command")
    fi
done

if (( ${#missing[@]} > 0 )); then
    echo "Missing required command(s): ${missing[*]}"
    echo "Install desktop packages first:"
    echo "  sudo pacman -S --needed - < packages/arch/desktop.txt"
    exit 1
fi

sudo install -d -m 0755 /etc/greetd

if [[ -f /etc/greetd/config.toml ]]; then
    sudo cp /etc/greetd/config.toml "/etc/greetd/config.toml.bak.$(date +%Y%m%d-%H%M%S)"
fi

sudo tee /etc/greetd/config.toml >/dev/null <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --cmd start-hyprland"
user = "greeter"
EOF

echo "greetd configured for tuigreet + start-hyprland."
echo "Enable it manually when ready:"
echo "  sudo systemctl enable --now greetd.service"
echo "Recovery if needed:"
echo "  sudo systemctl disable --now greetd.service"
