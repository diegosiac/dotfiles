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

configure_greetd_pam() {
    local pam_file="/etc/pam.d/greetd"
    local timestamp=""
    local temp_file=""

    timestamp="$(date +%Y%m%d-%H%M%S)"

    if [[ -f "$pam_file" ]]; then
        sudo cp "$pam_file" "$pam_file.bak.$timestamp"
        temp_file="$(mktemp)"

        sudo awk '
            BEGIN {
                auth_keyring = "auth optional pam_gnome_keyring.so"
                session_keyring = "session optional pam_gnome_keyring.so auto_start"
            }
            $1 == "auth" && $2 == "optional" && $3 == "pam_gnome_keyring.so" { has_auth = 1 }
            $1 == "session" && $2 == "optional" && $3 == "pam_gnome_keyring.so" && $0 ~ /auto_start/ { has_session = 1 }
            $1 == "auth" { last_auth = NR }
            $1 == "session" { last_session = NR }
            { lines[NR] = $0 }
            END {
                for (i = 1; i <= NR; i++) {
                    print lines[i]
                    if (!has_auth && i == last_auth) {
                        print auth_keyring
                    }
                    if (!has_session && i == last_session) {
                        print session_keyring
                    }
                }
                if (!has_auth && !last_auth) {
                    print auth_keyring
                }
                if (!has_session && !last_session) {
                    print session_keyring
                }
            }
        ' "$pam_file" >"$temp_file"

        sudo install -m 0644 -o root -g root "$temp_file" "$pam_file"
        rm -f "$temp_file"
    else
        sudo tee "$pam_file" >/dev/null <<'EOF'
#%PAM-1.0

auth required pam_securetty.so
auth requisite pam_nologin.so
auth include system-local-login
auth optional pam_gnome_keyring.so
account include system-local-login
session include system-local-login
session optional pam_gnome_keyring.so auto_start
EOF
        sudo chmod 0644 "$pam_file"
    fi
}

configure_greetd_pam

echo "greetd configured for tuigreet + start-hyprland."
echo "greetd PAM configured for GNOME Keyring unlock/start; previous files were backed up when present."
echo "Enable it manually when ready:"
echo "  sudo systemctl enable --now greetd.service"
echo "Recovery if needed:"
echo "  sudo systemctl disable --now greetd.service"
