#!/usr/bin/env bash
set -euo pipefail

repo_url="https://github.com/diegosiac/dotfiles.git"
source_dir="${CHEZMOI_SOURCE_DIR:-$HOME/.local/share/chezmoi}"

if [[ "$(uname -s)" != "Linux" ]] || [[ ! -f /etc/arch-release ]]; then
    echo "Siac Dotfiles Bootstrap currently supports Arch Linux only."
    exit 1
fi

if (( EUID == 0 )); then
    cat >&2 <<'EOF'
Siac Dotfiles Bootstrap must run as your regular user, not as root.

Create or switch to your user first, make sure it has sudo access, then run
the bootstrap again from that user account.
EOF
    exit 1
fi

sudo_cmd=(sudo)

if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required when running as a regular user. Install sudo first or run from a root shell."
    exit 1
fi

missing=()
for command in git chezmoi curl sudo; do
    if ! command -v "$command" >/dev/null 2>&1; then
        missing+=("$command")
    fi
done

if (( ${#missing[@]} > 0 )); then
    echo "Installing minimal bootstrap prerequisite(s): ${missing[*]}"
    "${sudo_cmd[@]}" pacman -Syu --needed git chezmoi curl sudo
fi

if [[ -d "$source_dir/.git" ]]; then
    echo "Updating dotfiles source at $source_dir"
    git -C "$source_dir" pull --ff-only
else
    echo "Initializing dotfiles source at $source_dir"
    chezmoi init --source "$source_dir" "$repo_url"
fi

exec bash "$source_dir/scripts/bootstrap-arch.sh"
