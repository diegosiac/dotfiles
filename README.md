# Dotfiles

Personal dotfiles for an Arch Linux, terminal-first, Hyprland-based environment.

This repository is intentionally being rebuilt from zero. Configuration will be added incrementally as each tool and workflow is selected.

## Principles

- Arch Linux first.
- Terminal-first workflow.
- Hyprland as the desktop direction.
- Public repository: no plaintext secrets.
- Secrets must be handled through 1Password or generated locally.

## Fresh install flow

This is the happy path for a new Arch machine. Apply it in a VM first when changing the flow.

### One-command bootstrap

Run the interactive bootstrap. It asks before installing packages, applying dotfiles, applying immediate desktop theme defaults, switching the login shell to `zsh`, initializing runtimes, installing the AI stack, and enabling `greetd`.

Run it as your regular user with sudo access, not as `root`.

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/diegosiac/dotfiles/main/bootstrap.sh)
```

The root `bootstrap.sh` only ensures minimal prerequisites, initializes or updates the chezmoi source, and delegates to the repo-local `scripts/bootstrap-arch.sh`. Machine mutation stays in the bootstrap scripts; chezmoi owns dotfiles. Runtime and AI setup stay as interactive bootstrap phases because they depend on installed packages, network state, and user auth/session choices.

### Manual fallback

Use this auditable flow when debugging the bootstrap or when you want to run each step yourself.

Install the bootstrap tools first if the fresh image does not have them yet. Run the flow as your regular user with sudo access:

```sh
sudo pacman -Syu --needed git chezmoi curl sudo
```

Clone the dotfiles source without applying it yet. Package-dependent chezmoi scripts, such as the Tmux plugin installer, need the package manifests to be installed first.

```sh
chezmoi init https://github.com/diegosiac/dotfiles.git
cd ~/.local/share/chezmoi
```

Install the official package sets:

```sh
sudo pacman -Syu --needed - < packages/arch/base.txt
sudo pacman -S --needed - < packages/arch/desktop.txt
```

Install `paru` if the machine does not have an AUR helper yet:

```sh
scripts/install-paru.sh
```

Install AUR packages:

```sh
paru -S --needed - < packages/arch/aur.txt
```

Apply the dotfiles after the required packages are available:

```sh
chezmoi apply
```

Optionally apply the desktop dark theme defaults when the bootstrap asks, or rerun `chezmoi apply` after the desktop packages are available. Change the login shell to `zsh` before relying on the terminal-first session defaults.

Initialize project runtimes and AI tooling:

```sh
fnm install --lts
fnm default lts-latest
corepack enable
corepack prepare pnpm@latest --activate
scripts/install-gentle-ai-engram.sh
```

If `corepack` is not visible immediately after `fnm` installs Node.js, load the runtime environment in the current shell and retry the Corepack commands:

```sh
eval "$(fnm env --shell bash)"
```

Optionally configure the login manager only after dotfiles apply cleanly and the desktop has been tested from a TTY:

```sh
sudo scripts/configure-greetd.sh
sudo systemctl enable --now greetd
```

Quick validation:

```sh
scripts/doctor.sh
Hyprland
pgrep -a quickshell
node --version
pnpm --version
engram --version
gentle-ai --help
chezmoi doctor
```

`scripts/configure-greetd.sh` also wires GNOME Keyring into `/etc/pam.d/greetd` for Secret Service/libsecret unlock. To run the optional fake-secret keyring smoke test, use `DOTFILES_DOCTOR_KEYRING_SMOKE=1 scripts/doctor.sh`; it stores, looks up, and clears only a temporary test value.

Optional AI setup and secret validation require your authenticated user session:

```sh
engram setup opencode
engram setup pi
gentle-ai
secrets-load
test -n "$ENGRAM_CLOUD_TOKEN" && test -n "$ENGRAM_CLOUD_SERVER" && echo "Engram Cloud settings loaded"
```

### Herdr phone app

The official Herdr app ([iOS](https://apps.apple.com/app/id6828898364), [Android](https://play.google.com/store/apps/details?id=dev.herdr.app)) drives agents that run under **herdr-core** (`hc`), not the Herdr TUI. It connects over plain SSH with no relay, so this machine only needs herdr-core and a reachable SSH server on the tailnet. See [herdr.dev/mobile](https://herdr.dev/mobile/) and [herdr.dev/core](https://herdr.dev/core/).

The optional `Herdr mobile` bootstrap phase:

- downloads `https://releases.herdr.dev/core/install.sh`, verifies its repository-pinned SHA-256 (`herdr_core_installer_sha256` in `scripts/bootstrap-arch.sh`), and runs it. The installer is user-local (`~/.local/bin/herdr-core`, plus an `hc` symlink when no other `hc` exists) and checks the release tarball digest itself. Any upstream installer change fails closed until the new script is reviewed and the pin is updated consciously;
- skips the install when herdr-core already exists; update it with `herdr-core update`;
- enables Tailscale SSH with `sudo tailscale set --ssh`, so the phone authenticates with its Tailscale identity instead of an SSH key.

Tailscale SSH answers port 22 on the tailnet address and ignores `authorized_keys` and `sshd_config` there. With UFW allowing inbound traffic only on `tailscale0`, OpenSSH is no longer the tailnet entry point. Access is governed by the `ssh` rules of the tailnet policy. The default policy uses `check` mode, which periodically asks for browser re-authentication. To skip it for your own devices, set this rule in the Tailscale admin console:

```json
"ssh": [{
  "action": "accept",
  "src": ["autogroup:member"],
  "dst": ["autogroup:self"],
  "users": ["autogroup:nonroot"]
}]
```

Roll back with `sudo tailscale set --ssh=false`.

Diagnostics:

```sh
scripts/doctor.sh
herdr-core server status
tailscale debug prefs | jq .RunSSH
```

Tailscale state, the tailnet policy, phone settings, and herdr-core runtime state are local and MUST NOT enter Git.

### Controlled UFW activation

UFW covers IPv4 and IPv6 with a default-deny incoming and default-allow outgoing policy. All inbound traffic is allowed only on `tailscale0`; UDP 41641 and SSH or Zen ports are not opened globally.

Perform activation only with independent console or recovery access available, Tailscale connected, and the current remote session kept open. Install UFW and verify that IPv6 support is enabled before continuing:

```sh
sudo pacman -S --needed ufw
grep -qx 'IPV6=yes' /etc/default/ufw
```

If the IPv6 check fails, set `IPV6=yes` in `/etc/default/ufw` before configuring or enabling UFW. Configure the approved policy, then inspect the pending rule set before activation:

```sh
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow in on tailscale0
sudo ufw show added
```

Confirm that the only inbound allowance is on `tailscale0`, then enable UFW and its Arch systemd service for boot persistence:

```sh
sudo ufw enable
sudo systemctl enable ufw.service
sudo ufw status verbose
```

Before closing the original session, use a separate client to establish and validate a NEW SSH session through Tailscale, replacing `user@tailscale-host` with the tailnet destination:

```sh
ssh user@tailscale-host
```

If the connection fails, keep the original session open and disable UFW from the independent recovery console:

```sh
sudo ufw disable
```

Docker-published ports can bypass UFW. Review every published port before using it; do not add `DOCKER-USER` mitigation until Docker actually publishes a port and the required exposure is known.

### VM desktop validation

After changing Hyprland, Quickshell, package manifests, or startup scripts, validate the desktop in a disposable VM before trusting the host install.

Apply the latest dotfiles and restart Quickshell:

```sh
cd ~/.local/share/chezmoi
chezmoi update && chezmoi apply
pkill quickshell
quickshell > /tmp/quickshell.log 2>&1 &
```

Check the desktop behavior:

- [ ] The top bar appears on login.
- [ ] Clicking the right status island opens and closes the control center.
- [ ] Volume slider and mute change the actual PipeWire sink.
- [ ] Brightness controls only appear when the VM exposes a real backlight.
- [ ] Network opens `nm-connection-editor`.
- [ ] Lock works through `hyprlock` or `loginctl`.
- [ ] Logout exits the Hyprland session.
- [ ] Reboot and shutdown require a second confirmation click.

Inspect the Quickshell log:

```sh
less /tmp/quickshell.log
```

Quickshell warnings about deprecated properties should be fixed. VM graphics warnings like `libEGL warning: failed to create dri2 screen` are usually harmless if the panel renders and behaves correctly.

### Screen sharing smoke tests

Run these from a real Hyprland session after installing the desktop package set and applying dotfiles:

- WebRTC: open `https://mozilla.github.io/webrtc-landing/gum_test.html`, choose screen capture, and confirm the portal picker appears and shares a window or monitor.
- OBS: add a `Screen Capture (PipeWire)` source and confirm the portal picker appears and the captured preview updates.

If either picker does not appear, run `scripts/doctor.sh` and review the `Screen Sharing and Portals` warnings first.

## Terminal multiplexer

Herdr is the default terminal multiplexer. It is agent-oriented: workspaces, tabs and panes with a sidebar reporting per-agent state. Tmux and Zellij stay installed and can be selected per shell session.

| Goal                        | Command                           |
| --------------------------- | --------------------------------- |
| Use the default multiplexer | `zsh`                             |
| Start with Tmux instead     | `TERMINAL_MULTIPLEXER=tmux zsh`   |
| Start with Zellij instead   | `TERMINAL_MULTIPLEXER=zellij zsh` |
| Start without a multiplexer | `TERMINAL_MULTIPLEXER=none zsh`   |

The shell skips auto-start when `HERDR_ENV`, `TMUX` or `ZELLIJ` is already set, so nested sessions are avoided by default. Auto-start does not `exec`, so a multiplexer that fails to launch leaves a usable Zsh session.

Herdr agent integrations are not installed automatically. Enable the ones you need with `herdr integration install <agent>` (for example `claude`, `codex`, `opencode`); without the hook the sidebar cannot report agent state.

Prefix keys currently overlap: the vendored Herdr config uses `ctrl+a`, which is also the Tmux prefix in `dot_tmux.conf`. Running Tmux inside a Herdr pane means Herdr consumes the prefix first.

## Runtime managers

Project JavaScript runtimes are managed with `fnm`. JavaScript package commands should use `pnpm`.

After installing the base packages on a new machine, initialize Node.js with:

```sh
fnm install --lts
fnm default lts-latest
corepack enable
corepack prepare pnpm@latest --activate
```

The shell aliases `npm` to `pnpm` and `npx` to `pnpm dlx`.

Some Arch-packaged developer tools may pull the system `nodejs` package as a runtime dependency. That is acceptable for packaged CLIs, but project-level Node.js versions should still come from `fnm`.

Python uses the system `python` package plus `uv` for Python tooling and virtual environments. Avoid global `pip install`; use `uv` or project-local virtual environments instead.

`inshellisense` is intentionally not installed through AUR because it is shell UX sugar, not required tooling. If we use it later, prefer the user-managed Node.js runtime instead.

## AI stack

The AI coding stack uses terminal-first agents plus shared persistent memory.

Core repositories:

- Gentle-AI: `https://github.com/Gentleman-Programming/gentle-ai`
- Engram: `https://github.com/Gentleman-Programming/engram`

Gentle-AI and Engram are installed as user-level Go binaries:

```sh
scripts/install-gentle-ai-engram.sh
```

After installation, configure the local user integrations as needed:

```sh
engram setup opencode
engram setup pi
gentle-ai
```

Generated agent config, MCP config, tokens, and Engram memory state stay outside this public repository.

Secrets used by the AI stack are loaded from 1Password on demand:

```sh
secrets-load
```

1Password manages these Engram Cloud values:

- `ENGRAM_CLOUD_TOKEN`
- `ENGRAM_CLOUD_SERVER`

For background autosync, run the helper that writes encrypted systemd user credentials for `engram.service` and only enables the service after both credentials exist:

```sh
scripts/configure-engram-cloud.sh
```

MongoDB and PAUL MCP launchers use a transient user-systemd service so stdio is preserved while systemd decrypts machine-bound credentials. Provision them once after authenticating 1Password; normal MCP startup does not run `op`:

```sh
scripts/configure-mcp-credentials.sh
```

The helper reads the existing local 1Password reference files, writes only encrypted blobs under `~/.config/credstore.encrypted`, and keeps those reference files for rollback. It preserves MongoDB's `MDB_MCP_READ_ONLY=true` and `--readOnly` controls; database-level least-privilege permissions remain a separate requirement.

Clear the Engram Cloud values from the current shell with:

```sh
secrets-clear
```

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

If `paru` is not installed yet, build it locally from AUR source:

```sh
scripts/install-paru.sh
```

This builds `paru` from source, so Rust/Cargo must be installed first through `packages/arch/base.txt`.

## Foundation policy

| Area | Policy |
| ---- | ------ |
| DNS | Use NetworkManager defaults. Do not hardcode public DNS or mutate `/etc/resolv.conf`. |
| Firewall | UFW covers IPv4 and IPv6, denies incoming traffic by default, allows outgoing traffic, and permits inbound traffic only on `tailscale0`. Activate it only through the controlled runbook above. |
| Power | AMD desktop needs no power daemon. Intel laptop uses `power-profiles-daemon`. Avoid governor, kernel flag, and tuning cargo cult. |
| AUR | Optional, interactive, and a reviewed trust boundary. `paru` is built locally from AUR source if needed; AUR is not required for base boot. |

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

| Tool | Source path | Local path |
| --- | --- | --- |
| Zellij | `GentlemanZellij/zellij` | `dot_config/zellij` |
| Tmux | `GentlemanTmux/tmux.conf` | `dot_tmux.conf` |
| Neovim | `GentlemanNvim/nvim` | `dot_config/nvim` |
| Herdr | `herdr/config.toml` | `dot_config/herdr/config.toml` |

Tmux plugins are installed through TPM by the chezmoi script `run_once_after_20-install-tmux-plugins.sh`.
