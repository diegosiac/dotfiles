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

| Goal                        | Command                         |
| --------------------------- | ------------------------------- |
| Use the default multiplexer | `zsh`                           |
| Start with tmux instead     | `TERMINAL_MULTIPLEXER=tmux zsh` |
| Start without a multiplexer | `TERMINAL_MULTIPLEXER=none zsh` |

The shell skips auto-start when already inside tmux or zellij, so nested sessions are avoided by default.

## Runtime managers

Node.js is managed with `fnm`, not with the system `nodejs` package. JavaScript package commands should use `pnpm`.

After installing the base packages on a new machine, initialize Node.js with:

```sh
fnm install --lts
fnm default lts-latest
corepack enable
corepack prepare pnpm@latest --activate
```

The shell aliases `npm` to `pnpm` and `npx` to `pnpm dlx`.

Python uses the system `python` package plus `uv` for Python tooling and virtual environments. Avoid global `pip install`; use `uv` or project-local virtual environments instead.

## Arch packages

Official repository packages are listed in:

```sh
packages/arch/base.txt
```

Install them with:

```sh
sudo pacman -S --needed - < packages/arch/base.txt
```

AUR packages are listed separately so `pacman` installs do not fail:

```sh
packages/arch/aur.txt
```

Install them with an AUR helper, for example:

```sh
paru -S --needed - < packages/arch/aur.txt
```

If `paru` is not installed yet, install the binary AUR package manually:

```sh
scripts/install-paru.sh
```

This builds `paru` from source, so Rust/Cargo must be installed first through `packages/arch/base.txt`.

## JavaScript package security

Global npm-compatible package installs disable lifecycle scripts by default through `~/.npmrc`:

```ini
ignore-scripts=true
```

This reduces supply-chain risk from malicious `preinstall`, `install`, or `postinstall` scripts in npm packages. If a trusted package genuinely needs lifecycle scripts, allow them explicitly for that install:

```sh
pnpm install --ignore-scripts=false
```

Reference: [npm ignore scripts best practices as security mitigation for malicious packages](https://www.nodejs-security.com/blog/npm-ignore-scripts-best-practices-as-security-mitigation-for-malicious-packages).

## Vendored configurations

Some tool configurations are copied from external dotfile repositories as reviewed snapshots.

Current external source:

- `https://github.com/Gentleman-Programming/Gentleman.Dots`

These configurations are not auto-updated during bootstrap or `chezmoi apply`. Updates must be pulled manually with the scripts under `vendor/gentleman-dots/`, reviewed with `git diff`, tested in the VM, and then committed.

Vendored configs currently planned or used:

| Tool   | Source path               | Local path          |
| ------ | ------------------------- | ------------------- |
| Zellij | `GentlemanZellij/zellij`  | `dot_config/zellij` |
| Tmux   | `GentlemanTmux/tmux.conf` | `dot_tmux.conf`     |
| Neovim | `GentlemanNvim/nvim`      | `dot_config/nvim`   |

Tmux plugins are installed through TPM by the chezmoi script `run_once_after_20-install-tmux-plugins.sh`.
