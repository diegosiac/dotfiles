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
