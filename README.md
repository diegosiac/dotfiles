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

### Reproducible Moshi access

The repository reproduces Moshi prerequisites and the setup procedure, but not machine identity or credentials. `packages/arch/base.txt` installs `openssh` and `mosh`; `scripts/configure-moshi.sh` configures the local machine interactively. Run it only from a regular user account with sudo access and KEEP THE CURRENT SESSION OPEN while testing new logins. The script never runs `tailscale up`.

SSH key material originates in 1Password. Before setup, use a hidden prompt to provide a secret reference that resolves ONLY to the Ed25519 public-key field; the script does not assume any vault, item, or field name:

```bash
read -rsp '1Password public-key reference: ' MOSHI_SSH_PUBLIC_KEY_REF && printf '\n'
export MOSHI_SSH_PUBLIC_KEY_REF
scripts/configure-moshi.sh
unset MOSHI_SSH_PUBLIC_KEY_REF
```

The script requires `op`, retrieves only that public key, rejects multiline, private-key, malformed, and non-Ed25519 values, and authorizes the key idempotently by fingerprint. It never reads, stores, or prints the matching private key. Moshi has no documented first-class 1Password integration: keep the private key in 1Password and manually import it into the Moshi mobile app from a file or the clipboard when creating the connection, following [Moshi connections and authentication](https://getmoshi.app/docs/connections). Do not automate or print the private key.

Tailscale must already be authenticated and online. The script reads structured Tailscale status and preferences but never runs `tailscale up` or prints identity fields. Migration depends on the actual `RunSSH` preference:

- **`RunSSH=false`:** Tailscale SSH is already off. The script hardens OpenSSH on port 22 only, requires the operator to confirm a successful new login, and continues. It does not create port 2222 or call `tailscale set --ssh=false`.
- **`RunSSH=true`:** Tailscale SSH stays active while hardened OpenSSH is prepared on ports 22 and 2222. The operator must explicitly confirm a new port-2222 login before the script disables only Tailscale SSH. The operator must then explicitly confirm a new port-22 login before the temporary port 2222 is removed. Success is never inferred.

OpenSSH is configured with generated host keys, root login disabled, public-key-only authentication, password and keyboard-interactive authentication disabled, and the current user allowlisted. OpenSSH uses the first obtained value for most directives, so the repository owns `/etc/ssh/sshd_config.d/00-moshi.conf`; it refuses to replace an unowned file there, leaves all unowned configuration untouched, and removes only marker-owned legacy `10-moshi.conf` or `90-moshi.conf` files. Every managed replacement is backed up and checked with both `sshd -t` and effective `sshd -T` policy before sshd is started or reloaded. Existing sessions are not closed. If a test fails, keep the current session open, use the reported rollback backup (or remove the newly generated `00-moshi.conf` on a first install), run `sudo sshd -t`, and reload sshd. During the `RunSSH=true` migration, port 2222 remains available until port 22 is explicitly confirmed; Tailscale SSH can be restored with `sudo tailscale set --ssh=true` if needed.

The setup command shown in the 1Password flow downloads the official `https://getmoshi.app/install.sh` installer and verifies its exact repository-pinned SHA-256 before execution. That pin is an explicit trust boundary, not a signature: any upstream installer change fails closed and requires consciously reviewing the new script before updating the digest. The reviewed installer retains its upstream checksum behavior for versioned CDN assets.

Leaving `MOSHI_HOOK_VERSION` unset is the default and installs the latest release. For a reproducible pin, pass an explicit release:

```sh
MOSHI_HOOK_VERSION=vX.Y.Z scripts/configure-moshi.sh
```

Never use the literal value `latest`; upstream would interpret it as `vlatest`. Routine reruns preserve an existing pairing and still install exactly the `pi`, `claude`, `codex`, `opencode`, and `grok` hooks plus the moshi-hook systemd user service. Pairing input is hidden so the token does not enter shell history. Replace pairing credentials only through the explicit `scripts/configure-moshi.sh --rotate-pairing` action. Setup optionally enables user lingering after explaining that it keeps user services available beyond an interactive login.

Official references: [install](https://getmoshi.app/docs/install), [hooks](https://getmoshi.app/docs/hooks), [Tailscale](https://getmoshi.app/docs/tailscale), [Tailscale guide](https://getmoshi.app/guides/tailscale), [connections](https://getmoshi.app/docs/connections), and [security and sync](https://getmoshi.app/docs/security-sync).

Safe diagnostics are read-only and sanitize Tailscale and Moshi output to booleans and hook states instead of IDs, names, paths, or secrets:

```sh
scripts/configure-moshi.sh --check
scripts/doctor.sh
sudo sshd -t
systemctl is-active sshd.service tailscaled.service
moshi-hook probe --json | jq '{installed, running}'
moshi-hook status --json | jq '{paired, hooks: [.hooks[] | select(.target == "pi" or .target == "claude" or .target == "codex" or .target == "opencode" or .target == "grok") | {target, status}]}'
```

Run the deterministic installer trust-boundary, SSH/Tailscale migration, and rollback contract tests without root, network, or host changes:

```sh
bash tests/configure-moshi.sh
```

The following are generated local state and MUST NOT enter Git: `authorized_keys`, OpenSSH host keys, moshi-hook pairing state, the generated user service, generated agent hook files, Tailscale state, linger state, phone settings, logs, tokens, host IDs, secrets, license keys, machine names, and machine addresses. The script and manifests are the reproducible boundary; operator confirmations and generated state remain local.

### Controlled UFW activation

UFW covers IPv4 and IPv6 with a default-deny incoming and default-allow outgoing policy. All inbound traffic is allowed only on `tailscale0`; UDP 41641 and SSH, Mosh, Moshi, or Zen ports are not opened globally.

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

Before closing the original session, use a separate client to establish and validate NEW SSH and Mosh sessions through Tailscale, replacing `user@tailscale-host` with the tailnet destination:

```sh
ssh user@tailscale-host
mosh user@tailscale-host
```

If either connection fails, keep the original session open and disable UFW from the independent recovery console:

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
