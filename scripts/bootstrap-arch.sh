#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bold="$(tput bold 2>/dev/null || true)"
reset="$(tput sgr0 2>/dev/null || true)"
red="$(tput setaf 1 2>/dev/null || true)"
green="$(tput setaf 2 2>/dev/null || true)"
yellow="$(tput setaf 3 2>/dev/null || true)"
blue="$(tput setaf 4 2>/dev/null || true)"

section() {
    printf '\n%s%s==> %s%s\n' "$bold" "$blue" "$1" "$reset"
}

ok() {
    printf '%s✓%s %s\n' "$green" "$reset" "$1"
}

warn() {
    printf '%s[WARN]%s %s\n' "$yellow" "$reset" "$1"
}

fail() {
    printf '%s[ERROR]%s %s\n' "$red" "$reset" "$1" >&2
    exit 1
}

confirm() {
    local prompt="$1"
    local answer

    printf '%s [y/N] ' "$prompt"
    read -r answer
    [[ "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" || "$answer" == "YES" ]]
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

install_pacman_packages() {
    sudo pacman -Syu --needed - < <(grep -hEv '^[[:space:]]*(#|$)' "$repo_root/packages/arch/base.txt" "$repo_root/packages/arch/desktop.txt")
}

install_pacman_manifest() {
    local manifest="$1"
    local packages=()

    mapfile -t packages < <(grep -hEv '^[[:space:]]*(#|$)' "$manifest")

    if (( ${#packages[@]} == 0 )); then
        warn "No installable packages found in $manifest."
        return 0
    fi

    sudo pacman -S --needed -- "${packages[@]}"
}

install_aur_packages() {
    if ! command -v paru >/dev/null 2>&1; then
        section "paru"
        warn "paru is not installed. The repo-local installer will build it from AUR."
        bash "$repo_root/scripts/install-paru.sh"
    else
        ok "paru is already installed: $(command -v paru)"
    fi

    paru -S --needed - < <(grep -hEv '^[[:space:]]*(#|$)' "$repo_root/packages/arch/aur.txt")
}

enable_basic_desktop_service() {
    local unit="$1"

    if ! command -v systemctl >/dev/null 2>&1; then
        warn "systemctl is unavailable. Skipping $unit."
        return 0
    fi

    if ! systemctl list-unit-files "$unit" >/dev/null 2>&1; then
        warn "$unit is unavailable. Install the matching package first, then enable it manually if needed."
        return 0
    fi

    if sudo systemctl enable --now "$unit"; then
        ok "$unit enabled and started."
    else
        warn "Could not enable/start $unit. Continuing bootstrap; run 'sudo systemctl enable --now $unit' later if needed."
    fi
}

enable_basic_desktop_services() {
    enable_basic_desktop_service NetworkManager.service
    enable_basic_desktop_service bluetooth.service
}

load_fnm_env() {
    command -v fnm >/dev/null 2>&1 || return 1
    eval "$(fnm env --shell bash)"
}

initialize_node_runtime() {
    if ! command -v fnm >/dev/null 2>&1; then
        warn "fnm is missing. Install packages/arch/base.txt first, then rerun this phase manually."
        return 0
    fi

    load_fnm_env || warn "Could not load fnm shell environment. Continuing with current PATH."

    fnm install --lts
    fnm default lts-latest

    load_fnm_env || warn "Could not reload fnm shell environment after setting the default Node.js version."

    if ! command -v corepack >/dev/null 2>&1; then
        warn "corepack is missing after Node.js initialization. Restart your shell or run 'eval \"\$(fnm env --shell bash)\"', then retry."
        return 0
    fi

    corepack enable
    corepack prepare pnpm@latest --activate
}

install_ai_stack() {
    if ! command -v go >/dev/null 2>&1; then
        warn "go is missing. Install packages/arch/base.txt first, then rerun scripts/install-gentle-ai-engram.sh."
        return 0
    fi

    bash "$repo_root/scripts/install-gentle-ai-engram.sh"
}

apply_desktop_dark_theme_defaults() {
    if ! command -v gsettings >/dev/null 2>&1; then
        warn "gsettings is unavailable. Skipping immediate desktop theme defaults."
        return 0
    fi

    set_gsetting() {
        local schema="$1"
        local key="$2"
        local value="$3"

        if ! gsettings set "$schema" "$key" "$value"; then
            warn "Could not set gsettings key: $schema $key"
        fi
    }

    set_gsetting org.gnome.desktop.interface gtk-theme 'WhiteSur-Dark'
    set_gsetting org.gnome.desktop.interface icon-theme 'WhiteSur'
    set_gsetting org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Ice'
    set_gsetting org.gnome.desktop.interface cursor-size 24
    set_gsetting org.gnome.desktop.interface font-name 'Inter 11'
    set_gsetting org.gnome.desktop.interface color-scheme 'prefer-dark'
}

configure_default_shell() {
    local zsh_path=""
    local passwd_entry=""
    local login_shell=""

    if [[ -x /usr/bin/zsh ]]; then
        zsh_path="/usr/bin/zsh"
    elif zsh_path="$(command -v zsh 2>/dev/null)"; then
        :
    else
        warn "zsh is not installed or not on PATH. Install packages first, then rerun this phase."
        return 0
    fi

    passwd_entry="$(getent passwd "$USER" || true)"
    login_shell="${passwd_entry##*:}"

    if [[ "${SHELL:-}" == */zsh || "$login_shell" == */zsh ]]; then
        warn "Your current or configured login shell is already zsh. Continuing anyway if you choose to refresh it."
    fi

    if ! grep -Fxq "$zsh_path" /etc/shells; then
        warn "$zsh_path is not listed in /etc/shells. Adding it with sudo."
        if ! printf '%s\n' "$zsh_path" | sudo tee -a /etc/shells >/dev/null; then
            warn "Could not add $zsh_path to /etc/shells. Skipping login shell change."
            return 0
        fi
    fi

    if chsh -s "$zsh_path" "$USER"; then
        ok "Default login shell set to $zsh_path. Log out and back in for it to take effect."
    else
        warn "Could not change the default login shell. Continuing bootstrap; run 'chsh -s $zsh_path $USER' later if needed."
    fi
}

printf '\n%s%sSiac Dotfiles Bootstrap%s\n' "$bold" "$blue" "$reset"
printf '%sInteractive Arch Linux bootstrap for Diego Siac dotfiles.%s\n' "$yellow" "$reset"

section "Preflight"
[[ "$(uname -s)" == "Linux" ]] && [[ -f /etc/arch-release ]] || fail "This bootstrap only supports Arch Linux."
ok "Arch Linux detected."

if (( EUID == 0 )); then
    fail "Do not run this bootstrap as root. Log in as your regular user with sudo access and rerun it."
fi

ok "Running as regular user: $USER"

require_command sudo
require_command pacman
require_command chezmoi
sudo -v
ok "sudo access confirmed."

cd "$repo_root"

chezmoi_apply_succeeded=false

section "Official packages"
if confirm "Install/update official Arch packages from packages/arch/base.txt and packages/arch/desktop.txt?"; then
    install_pacman_packages
    ok "Official packages installed."
else
    warn "Skipped official package installation. Chezmoi scripts may fail if required commands are missing."
fi

section "Hardware packages"
if confirm "Install common hardware foundation packages from packages/arch/hardware-common.txt?"; then
    install_pacman_manifest "$repo_root/packages/arch/hardware-common.txt"
    ok "Common hardware packages installed."
else
    warn "Skipped common hardware packages. GPU, firmware, audio, and diagnostics tooling may be incomplete."
fi

if confirm "Install AMD desktop hardware packages from packages/arch/hardware-amd-desktop.txt? Choose this only on the 7800X3D desktop."; then
    install_pacman_manifest "$repo_root/packages/arch/hardware-amd-desktop.txt"
    ok "AMD desktop hardware packages installed."
else
    warn "Skipped AMD desktop hardware packages."
fi

if confirm "Install Intel laptop hardware packages from packages/arch/hardware-intel-laptop.txt? Choose this only on the Intel laptop."; then
    install_pacman_manifest "$repo_root/packages/arch/hardware-intel-laptop.txt"
    ok "Intel laptop hardware packages installed."
else
    warn "Skipped Intel laptop hardware packages."
fi

warn "NVIDIA offload packages are intentionally not installed automatically. Review packages/arch/hardware-nvidia-optional.txt before changing this."

section "AUR packages"
if confirm "Install AUR packages from packages/arch/aur.txt with paru?"; then
    install_aur_packages
    ok "AUR packages installed."
else
    warn "Skipped AUR package installation."
fi

section "Basic services"
if confirm "Enable and start NetworkManager and Bluetooth services now?"; then
    enable_basic_desktop_services
    ok "Basic services phase finished."
else
    warn "Skipped NetworkManager and Bluetooth service enablement."
fi

section "Dotfiles"
if confirm "Apply dotfiles now with chezmoi apply?"; then
    if chezmoi apply; then
        chezmoi_apply_succeeded=true
        ok "Dotfiles applied."
    else
        warn "chezmoi apply failed. Continuing bootstrap, but greetd will be skipped because Hyprland dotfiles may be missing."
    fi
else
    warn "Skipped chezmoi apply. Run 'chezmoi apply' later from any shell."
fi

section "Desktop theme"
if confirm "Apply desktop dark theme defaults now with gsettings?"; then
    apply_desktop_dark_theme_defaults
    ok "Desktop theme default phase finished."
else
    warn "Skipped immediate desktop theme defaults. Chezmoi-managed GTK and xsettingsd files are still installed when dotfiles are applied."
fi

section "Shell"
if confirm "Change the default login shell to zsh?"; then
    configure_default_shell
else
    warn "Skipped login shell change. Your login shell may remain bash until you run chsh manually."
fi

section "Runtimes"
if confirm "Initialize Node.js runtime with fnm and activate pnpm through Corepack?"; then
    initialize_node_runtime
    ok "Runtime phase finished."
else
    warn "Skipped Node.js runtime initialization. Run 'fnm install --lts' and Corepack setup later."
fi

section "AI stack"
if confirm "Install Gentle-AI and Engram user binaries with Go?"; then
    install_ai_stack
    ok "AI stack install phase finished."
else
    warn "Skipped AI stack installation. Run 'scripts/install-gentle-ai-engram.sh' later."
fi

section "greetd"
if [[ "$chezmoi_apply_succeeded" != true ]]; then
    warn "Skipping greetd. It requires a successful chezmoi apply in this bootstrap run so Hyprland and terminal config exist before login manager startup."
elif confirm "Configure and enable greetd now? This can change your login flow immediately."; then
    sudo "$repo_root/scripts/configure-greetd.sh"
    sudo systemctl enable --now greetd
    ok "greetd configured and enabled."
else
    warn "Skipped greetd configuration."
fi

section "Validation"
cat <<'EOF'
Run these checks after the bootstrap finishes:

  Hyprland
  pgrep -a quickshell
  systemctl status greetd
  node --version
  pnpm --version
  engram --version
  gentle-ai --help
  chezmoi doctor
  gsettings get org.gnome.desktop.interface color-scheme
  gsettings get org.gnome.desktop.interface gtk-theme
  gsettings get org.gnome.desktop.interface cursor-theme

Optional AI setup after you have an authenticated shell/session:

  engram setup opencode
  engram setup pi
  gentle-ai
  secrets-load
  test -n "$ENGRAM_CLOUD_TOKEN" && echo "Engram Cloud token loaded"

If greetd blocks login, switch to another TTY and run:

  sudo systemctl disable --now greetd
EOF

ok "Bootstrap finished."
