#!/usr/bin/env bash
set -euo pipefail

credstore_dir=${HOME:?HOME is required}/.config/credstore.encrypted
mongodb_reference=${HOME}/.config/mongodb-mcp/1password.env
paul_reference=${HOME}/.config/paul-mcp/1password.env

fail() {
  printf 'configure-mcp-credentials: %s\n' "$1" >&2
  exit 1
}
require_command() { command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"; }

require_command op
require_command systemd-creds
require_command install
require_command mktemp
[ -r "$mongodb_reference" ] || fail "MongoDB 1Password reference file is not readable: $mongodb_reference"
[ -r "$paul_reference" ] || fail "PAUL 1Password reference file is not readable: $paul_reference"

umask 077
install -d -m 700 -- "$credstore_dir"
tmp_dir=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/mcp-credentials.XXXXXX") || fail 'failed to create temporary directory'
trap 'rm -rf -- "$tmp_dir"' EXIT HUP INT TERM

inject_references() {
  local source=$1 destination=$2
  op inject --in-file "$source" --out-file "$destination" || fail '1Password credential injection failed'
}
extract_credential() {
  local source=$1 variable_name=$2 destination=$3
  # Values may be written dotenv-style with matching surrounding quotes; strip them.
  awk -v name="$variable_name" '
    index($0, name "=") == 1 {
      value = substr($0, length(name) + 2)
      if (length(value) >= 2) {
        first = substr(value, 1, 1); last = substr(value, length(value), 1)
        if ((first == "\"" || first == "\047") && first == last) value = substr(value, 2, length(value) - 2)
      }
      print value; found = 1; exit
    }
    END { exit !found }' "$source" >"$destination" || fail "required credential is missing: $variable_name"
  [ -s "$destination" ] || fail "required credential is empty: $variable_name"
}
encrypt_credential() {
  local name=$1 plaintext=$2
  systemd-creds encrypt --user --name="$name" - "$tmp_dir/$name.cred" <"$plaintext" || fail "failed to encrypt credential: $name"
  chmod 600 -- "$tmp_dir/$name.cred"
}

inject_references "$mongodb_reference" "$tmp_dir/mongodb.env"
inject_references "$paul_reference" "$tmp_dir/paul.env"
extract_credential "$tmp_dir/mongodb.env" MDB_MCP_CONNECTION_STRING "$tmp_dir/mongodb-connection-string"
extract_credential "$tmp_dir/paul.env" PAUL_EMAIL "$tmp_dir/paul-email"
extract_credential "$tmp_dir/paul.env" PAUL_PASSWORD "$tmp_dir/paul-password"
encrypt_credential mongodb-mcp-connection-string "$tmp_dir/mongodb-connection-string"
encrypt_credential paul-mcp-email "$tmp_dir/paul-email"
encrypt_credential paul-mcp-password "$tmp_dir/paul-password"

credential_names=(mongodb-mcp-connection-string paul-mcp-email paul-mcp-password)
restore_credentials() {
  local name
  for name in "${credential_names[@]}"; do
    if [ -e "$tmp_dir/$name.previous" ]; then
      mv -f -- "$tmp_dir/$name.previous" "$credstore_dir/$name"
    else
      rm -f -- "$credstore_dir/$name"
    fi
  done
}

for name in "${credential_names[@]}"; do
  destination=$credstore_dir/$name
  if [ -e "$destination" ] && ! mv -- "$destination" "$tmp_dir/$name.previous"; then
    for restore_name in "${credential_names[@]}"; do
      [ ! -e "$tmp_dir/$restore_name.previous" ] || mv -f -- "$tmp_dir/$restore_name.previous" "$credstore_dir/$restore_name"
    done
    fail 'failed to back up an existing encrypted credential'
  fi
done
for name in "${credential_names[@]}"; do
  if ! mv -- "$tmp_dir/$name.cred" "$credstore_dir/$name"; then
    restore_credentials || fail 'failed to commit encrypted credentials and rollback failed'
    fail 'failed to commit encrypted credentials; original credentials were restored'
  fi
done

printf 'MongoDB and PAUL encrypted user credentials are configured.\n'
