#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]] || [[ ! -f /etc/arch-release ]]; then
    echo "This installer only supports Arch Linux."
    exit 1
fi

if command -v paru >/dev/null 2>&1; then
    echo "paru is already installed: $(command -v paru)"
    exit 0
fi

missing=()
for command in git makepkg; do
    if ! command -v "$command" >/dev/null 2>&1; then
        missing+=("$command")
    fi
done

if (( ${#missing[@]} > 0 )); then
    echo "Missing required command(s): ${missing[*]}"
    echo "Install base dependencies first:"
    echo "  sudo pacman -S --needed - < packages/arch/base.txt"
    exit 1
fi

work_dir="${TMPDIR:-/tmp}/paru-bin"
rm -rf "$work_dir"
git clone https://aur.archlinux.org/paru-bin.git "$work_dir"

cd "$work_dir"
makepkg -si

echo "paru installed successfully."
