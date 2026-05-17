# Dotfiles

Personal dotfiles for an Arch Linux, terminal-first, Hyprland-based environment.

This repository is intentionally being rebuilt from zero. Configuration will be added incrementally as each tool and workflow is selected.

## Principles

- Arch Linux first.
- Terminal-first workflow.
- Hyprland as the desktop direction.
- Public repository: no plaintext secrets.
- Secrets must be handled through 1Password or generated locally.

## Terminal multiplexer

Zellij is the default terminal multiplexer. Tmux is also installed and can be selected per shell session.

| Goal | Command |
| --- | --- |
| Use the default multiplexer | `zsh` |
| Start with tmux instead | `TERMINAL_MULTIPLEXER=tmux zsh` |
| Start without a multiplexer | `TERMINAL_MULTIPLEXER=none zsh` |

The shell skips auto-start when already inside tmux or zellij, so nested sessions are avoided by default.

## Vendored configurations

Some tool configurations are copied from external dotfile repositories as reviewed snapshots.

Current external source:

- `https://github.com/Gentleman-Programming/Gentleman.Dots`

These configurations are not auto-updated during bootstrap or `chezmoi apply`. Updates must be pulled manually with the scripts under `vendor/gentleman-dots/`, reviewed with `git diff`, tested in the VM, and then committed.

Vendored configs currently planned or used:

| Tool | Source path | Local path |
| --- | --- | --- |
| Zellij | `GentlemanZellij/zellij` | `dot_config/zellij` |
| Tmux | `GentlemanTmux/tmux.conf` | `dot_tmux.conf` |
| Neovim | `GentlemanNvim/nvim` | pending |

Tmux plugins are installed through TPM by the chezmoi script `run_once_after_20-install-tmux-plugins.sh`.
