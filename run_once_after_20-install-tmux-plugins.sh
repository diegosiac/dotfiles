#!/usr/bin/env bash
set -euo pipefail

if ! command -v git >/dev/null 2>&1; then
    echo "Skipping Tmux plugin install: git is not installed."
    exit 0
fi

if ! command -v tmux >/dev/null 2>&1; then
    echo "Skipping Tmux plugin install: tmux is not installed."
    exit 0
fi

tpm_dir="$HOME/.tmux/plugins/tpm"

if [[ ! -d "$tpm_dir/.git" ]]; then
    mkdir -p "$(dirname "$tpm_dir")"
    git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
fi

"$tpm_dir/bin/install_plugins"
