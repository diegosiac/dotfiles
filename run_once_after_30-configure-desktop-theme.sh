#!/usr/bin/env bash
set -euo pipefail

if ! command -v gsettings >/dev/null 2>&1; then
    echo "Skipping desktop theme defaults: gsettings is not installed."
    exit 0
fi

set_gsetting() {
    local schema="$1"
    local key="$2"
    local value="$3"

    if ! gsettings set "$schema" "$key" "$value"; then
        echo "Skipping gsettings default: $schema $key" >&2
    fi
}

set_gsetting org.gnome.desktop.interface gtk-theme 'WhiteSur-Dark'
set_gsetting org.gnome.desktop.interface icon-theme 'WhiteSur'
set_gsetting org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Ice'
set_gsetting org.gnome.desktop.interface cursor-size 24
set_gsetting org.gnome.desktop.interface font-name 'Inter 11'
set_gsetting org.gnome.desktop.interface color-scheme 'prefer-dark'
