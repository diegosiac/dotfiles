#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source_nvim="$repo_root/dot_config/nvim"
real_config="$HOME/.config/chezmoi/chezmoi.toml"
real_state_db="$HOME/.config/chezmoi/chezmoistate.boltdb"
live_nvim="$HOME/.config/nvim"
default_source="$HOME/.local/share/chezmoi"
runtime_theme="$HOME/.local/state/omarchy/current/theme/neovim.lua"
sandbox=""

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

fingerprint_path() {
  python3 - "$1" <<'PY'
from hashlib import sha256
from pathlib import Path
import os
import stat
import sys

root = Path(sys.argv[1])
digest = sha256()
if not os.path.lexists(root):
    digest.update(b"absent\0")
else:
    paths = [root]
    if root.is_dir() and not root.is_symlink():
        paths.extend(sorted(root.rglob("*"), key=lambda path: path.relative_to(root).as_posix()))
    for path in paths:
        relative = b"." if path == root else path.relative_to(root).as_posix().encode()
        metadata = path.lstat()
        digest.update(relative + b"\0")
        digest.update(f"{metadata.st_mode}:{metadata.st_size}:{metadata.st_mtime_ns}".encode() + b"\0")
        if stat.S_ISLNK(metadata.st_mode):
            digest.update(os.readlink(path).encode() + b"\0")
        elif stat.S_ISREG(metadata.st_mode):
            with path.open("rb") as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    digest.update(chunk)
print(digest.hexdigest())
PY
}

state_before="$(fingerprint_path "$real_state_db")"
live_before="$(fingerprint_path "$live_nvim")"
default_source_before="$(fingerprint_path "$default_source")"

cleanup() {
  local status=$?
  local state_after live_after default_source_after
  trap - EXIT
  set +e

  state_after="$(fingerprint_path "$real_state_db")"
  [[ $? -eq 0 ]] || status=1
  live_after="$(fingerprint_path "$live_nvim")"
  [[ $? -eq 0 ]] || status=1
  default_source_after="$(fingerprint_path "$default_source")"
  [[ $? -eq 0 ]] || status=1

  if [[ "$state_after" != "$state_before" ]]; then
    printf 'FAIL: real Chezmoi persistent state changed\n' >&2
    status=1
  fi
  if [[ "$live_after" != "$live_before" ]]; then
    printf 'FAIL: live Neovim configuration changed\n' >&2
    status=1
  fi
  if [[ "$default_source_after" != "$default_source_before" ]]; then
    printf 'FAIL: default Chezmoi source changed\n' >&2
    status=1
  fi

  [[ -z "$sandbox" ]] || rm -rf -- "$sandbox"
  exit "$status"
}
trap cleanup EXIT

for command in chezmoi find luac python3 sort; do
  command -v "$command" >/dev/null 2>&1 || fail "required command is unavailable: $command"
done
[[ -d /tmp/opencode ]] || fail "/tmp/opencode is unavailable"
[[ -d "$source_nvim" && ! -L "$source_nvim" ]] || fail "Neovim source is missing or unsafe"
[[ -f "$real_config" && ! -L "$real_config" ]] || fail "Chezmoi config is missing or unsafe"
[[ -f "$runtime_theme" ]] || fail "current Omarchy runtime theme is missing"

sandbox="$(mktemp -d /tmp/opencode/nvim-materialization.XXXXXX)"
destination="$sandbox/destination"
cache="$sandbox/cache"
persistent_state="$sandbox/state/chezmoistate.boltdb"
mkdir -p -- \
  "$destination/.local/state/omarchy/current/theme" \
  "$cache" \
  "$(dirname -- "$persistent_state")"
cp -- "$runtime_theme" "$destination/.local/state/omarchy/current/theme/neovim.lua"

mapfile -d '' -t absolute_source_leaves < <(find "$source_nvim" -type f -print0 | sort -z)
((${#absolute_source_leaves[@]} > 0)) || fail "Neovim source leaf enumeration was empty"

managed_source_leaves=()
for path in "${absolute_source_leaves[@]}"; do
  [[ "$path" == "$repo_root/"* ]] || fail "managed source leaf escaped the worktree"
  managed_source_leaves+=("$path")
done
((${#managed_source_leaves[@]} > 0)) || fail "Neovim managed source array was empty"

if ! chezmoi \
  --source "$repo_root" \
  --destination "$destination" \
  --config "$real_config" \
  --persistent-state "$persistent_state" \
  --cache "$cache" \
  --no-tty \
  --refresh-externals=never \
  apply --parent-dirs --source-path "${managed_source_leaves[@]}" \
  > "$sandbox/chezmoi.stdout" 2> "$sandbox/chezmoi.stderr"; then
  fail "isolated Neovim materialization failed"
fi

materialized_nvim="$destination/.config/nvim"
[[ -d "$materialized_nvim" && ! -L "$materialized_nvim" ]] \
  || fail "materialized Neovim directory is missing or unsafe"
[[ -f "$materialized_nvim/.neoconf.json" && ! -L "$materialized_nvim/.neoconf.json" ]] \
  || fail "materialized .neoconf.json is missing or unsafe"

declare -A expected_symlinks=(
  ["lua/config/remote_clipboard.lua"]="/usr/share/omarchy-nvim/config/lua/config/remote_clipboard.lua"
  ["lua/plugins/all-themes.lua"]="/usr/share/omarchy-nvim/config/lua/plugins/all-themes.lua"
  ["lua/plugins/omarchy-theme-hotreload.lua"]="/usr/share/omarchy-nvim/config/lua/plugins/omarchy-theme-hotreload.lua"
  ["lua/plugins/theme.lua"]="../../../../.local/state/omarchy/current/theme/neovim.lua"
  ["plugin/after/transparency.lua"]="/usr/share/omarchy-nvim/config/plugin/after/transparency.lua"
)

mapfile -d '' -t materialized_symlinks < <(find "$materialized_nvim" -type l -print0 | sort -z)
[[ ${#materialized_symlinks[@]} -eq ${#expected_symlinks[@]} ]] \
  || fail "materialized Neovim symlink count was not exactly five"
for path in "${materialized_symlinks[@]}"; do
  relative="${path#"$materialized_nvim/"}"
  [[ -n "${expected_symlinks[$relative]+x}" ]] || fail "unexpected materialized Neovim symlink: $relative"
  [[ "$(readlink -- "$path")" == "${expected_symlinks[$relative]}" ]] \
    || fail "incorrect materialized Neovim symlink target: $relative"
done
for relative in "${!expected_symlinks[@]}"; do
  [[ -L "$materialized_nvim/$relative" ]] || fail "expected materialized Neovim symlink is missing: $relative"
done
[[ -e "$materialized_nvim/lua/plugins/theme.lua" ]] \
  || fail "temporary runtime theme did not satisfy the materialized theme symlink"

mapfile -d '' -t materialized_leaves < <(
  find "$materialized_nvim" \( -type f -o -type l \) -print0 | sort -z
)
[[ ${#materialized_leaves[@]} -eq ${#managed_source_leaves[@]} ]] \
  || fail "materialized Neovim leaf count differs from managed source leaves"

mapfile -d '' -t destination_leaves < <(
  find "$destination" \( -type f -o -type l \) -print0 | sort -z
)
for path in "${destination_leaves[@]}"; do
  relative="${path#"$destination/"}"
  case "$relative" in
    .config/nvim/* | .local/state/omarchy/current/theme/neovim.lua) ;;
    *) fail "unrelated target was materialized: $relative" ;;
  esac
done

mapfile -d '' -t lua_files < <(
  find "$materialized_nvim" \( -type f -o -type l \) -name '*.lua' -print0 | sort -z
)
((${#lua_files[@]} > 0)) || fail "materialized Lua enumeration was empty"
for path in "${lua_files[@]}"; do
  luac -p "$path" 2> "$sandbox/luac.stderr" \
    || fail "materialized Lua compile failed: ${path#"$materialized_nvim/"}"
done

mapfile -d '' -t json_files < <(find "$materialized_nvim" -type f -name '*.json' -print0 | sort -z)
((${#json_files[@]} > 0)) || fail "materialized JSON enumeration was empty"
if ! python3 - "${json_files[@]}" <<'PY'
import json
import sys

for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as handle:
        json.load(handle)
PY
then
  fail "materialized JSON parse failed"
fi

[[ "$(fingerprint_path "$real_state_db")" == "$state_before" ]] \
  || fail "real Chezmoi persistent state changed"
[[ "$(fingerprint_path "$live_nvim")" == "$live_before" ]] \
  || fail "live Neovim configuration changed"
[[ "$(fingerprint_path "$default_source")" == "$default_source_before" ]] \
  || fail "default Chezmoi source changed"

printf 'PASS: isolated Neovim materializes every managed source leaf\n'
printf 'PASS: materialized Neovim JSON, Lua, and five symlink contracts are valid\n'
printf 'PASS: live Neovim, Chezmoi state, and default source remain unchanged\n'
