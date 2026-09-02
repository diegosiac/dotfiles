#!/usr/bin/env bash
set -euo pipefail

item_name=engram-cloud
credstore_dir=${HOME:?HOME is required}/.config/credstore.encrypted
token_credential=engram-cloud-token
server_credential=engram-cloud-server

die() {
    printf 'configure-engram-cloud: %s\n' "$1" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

mv_bin=${MV_BIN:-mv}

require_command op
require_command systemd-creds
require_command systemctl
require_command mktemp
require_command "$mv_bin"

case $credstore_dir in
/*) ;;
*) die 'credential store path must be absolute' ;;
esac

umask 077
install -d -m 700 -- "$credstore_dir"

tmp_parent=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
tmp_dir=$(mktemp -d "${tmp_parent%/}/engram-cloud.XXXXXX") || die 'failed to create temporary directory'
cleanup() {
    rm -rf -- "$tmp_dir"
}
trap cleanup EXIT HUP INT TERM

prepare_credential() {
    local field_name=$1
    local credential_name=$2
    local plaintext_file=$tmp_dir/$credential_name.plain
    local encrypted_temp=$tmp_dir/$credential_name.cred
    local field_value

    op item get "$item_name" --field "$field_name" --reveal >"$plaintext_file" || die "failed to read required 1Password field: $field_name"
    [ -s "$plaintext_file" ] || die "required 1Password field is empty: $field_name"

    if [ "$field_name" = server ]; then
        field_value=$(cat -- "$plaintext_file")
        field_value=${field_value%$'\r'}
        [ -n "$field_value" ] || die "required 1Password field is empty: $field_name"
        case $field_value in
        *://*) ;;
        *) field_value=https://$field_value ;;
        esac
        printf '%s\n' "$field_value" >"$plaintext_file"
    fi

    systemd-creds encrypt --user --name="$credential_name" - "$encrypted_temp" <"$plaintext_file" || die "failed to encrypt systemd credential: $credential_name"
    [ -s "$encrypted_temp" ] || die "encrypted credential was not created: $credential_name"
}

backup_credential() {
    local credential_name=$1
    local encrypted_dest=$credstore_dir/$credential_name
    local encrypted_backup=$tmp_dir/$credential_name.backup
    local existed_var=$2

    printf -v "$existed_var" '%s' 0
    if [ -e "$encrypted_dest" ]; then
        "$mv_bin" -f -- "$encrypted_dest" "$encrypted_backup"
        printf -v "$existed_var" '%s' 1
    fi
}

restore_credential() {
    local credential_name=$1
    local existed=$2
    local encrypted_dest=$credstore_dir/$credential_name
    local encrypted_backup=$tmp_dir/$credential_name.backup

    if [ "$existed" -eq 1 ]; then
        "$mv_bin" -f -- "$encrypted_backup" "$encrypted_dest"
    else
        rm -f -- "$encrypted_dest"
    fi
}

restore_committed_credentials() {
    local restore_status=0

    restore_credential "$token_credential" "$token_credential_existed" || restore_status=1
    restore_credential "$server_credential" "$server_credential_existed" || restore_status=1
    return "$restore_status"
}

commit_credentials() {
    local token_credential_existed=0
    local server_credential_existed=0

    chmod 600 -- "$tmp_dir/$token_credential.cred" "$tmp_dir/$server_credential.cred"

    if ! backup_credential "$token_credential" token_credential_existed; then
        die 'failed to backup existing encrypted credentials'
    fi
    if ! backup_credential "$server_credential" server_credential_existed; then
        restore_credential "$token_credential" "$token_credential_existed" || true
        die 'failed to backup existing encrypted credentials'
    fi

    if ! "$mv_bin" -f -- "$tmp_dir/$token_credential.cred" "$credstore_dir/$token_credential"; then
        restore_committed_credentials || die 'failed to commit encrypted credentials and rollback failed'
        die 'failed to commit encrypted credentials; original credentials were restored'
    fi
    if ! "$mv_bin" -f -- "$tmp_dir/$server_credential.cred" "$credstore_dir/$server_credential"; then
        restore_committed_credentials || die 'failed to commit encrypted credentials and rollback failed'
        die 'failed to commit encrypted credentials; original credentials were restored'
    fi
}

prepare_credential password "$token_credential"
prepare_credential server "$server_credential"

commit_credentials

systemctl --user daemon-reload
systemctl --user enable --now engram.service

printf 'Engram Cloud encrypted user credentials are configured and engram.service is enabled.\n'
