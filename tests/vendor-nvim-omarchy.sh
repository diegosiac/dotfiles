#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tree="${1:-$repo_root/dot_config/nvim}"
patch_file="$repo_root/vendor/gentleman-dots/nvim-omarchy.patch"
preimages_file="$repo_root/vendor/gentleman-dots/nvim-omarchy.preimages"
contract_file="$repo_root/vendor/omarchy-nvim/contract.snapshot"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local needle="$1"
  local relative_path="$2"
  grep -Fq -- "$needle" "$tree/$relative_path" || fail "$relative_path does not contain the required contract text"
}

assert_source_link() {
  local relative_path="$1"
  local expected_target="$2"
  local path="$tree/$relative_path"

  [[ -f "$path" && ! -L "$path" ]] || fail "Chezmoi symlink source must be a regular file: $relative_path"
  [[ "$(<"$path")" == "$expected_target" ]] || fail "incorrect Chezmoi symlink target: $relative_path"
}

verify_contract() {
  local kind expected path extra actual
  local records=0
  declare -A seen_contract=()
  local -a required_contract=(
    "version:/usr/share/omarchy/version"
    "sha256:/usr/share/omarchy/version"
    "sha256:/usr/share/omarchy-nvim/config/lazy-lock.json"
    "sha256:/usr/share/omarchy-nvim/config/lua/plugins/all-themes.lua"
    "sha256:/usr/share/omarchy-nvim/config/lua/plugins/omarchy-theme-hotreload.lua"
    "sha256:/usr/share/omarchy-nvim/config/plugin/after/transparency.lua"
    "sha256:/usr/share/omarchy-nvim/config/lua/config/remote_clipboard.lua"
  )
  local record

  while IFS=$'\t' read -r kind expected path extra; do
    [[ -z "$kind" || "$kind" == \#* ]] && continue
    [[ -z "${extra:-}" ]] || fail "invalid Omarchy contract record: $kind"
    [[ -n "$expected" && -n "$path" ]] || fail "incomplete Omarchy contract record: $kind"
    record="$kind:$path"
    [[ -z "${seen_contract[$record]+x}" ]] || fail "duplicate Omarchy contract record: $record"

    case "$kind" in
      version)
        [[ -f "$path" ]] || fail "Omarchy version file is missing: $path"
        [[ "$(<"$path")" == "$expected" ]] || fail "Omarchy version drift: $path"
        ;;
      sha256)
        [[ -f "$path" ]] || fail "Omarchy contract path is missing: $path"
        actual="$(sha256sum "$path")"
        [[ "${actual%% *}" == "$expected" ]] || fail "Omarchy contract drift: $path"
        ;;
      *)
        fail "unknown Omarchy contract record type: $kind"
        ;;
    esac
    seen_contract["$record"]=1
    records=$((records + 1))
  done < "$contract_file"

  ((records == ${#required_contract[@]})) || fail "Omarchy contract snapshot has an unexpected record count"
  for record in "${required_contract[@]}"; do
    [[ -n "${seen_contract[$record]+x}" ]] || fail "Omarchy contract snapshot is missing: $record"
  done
}

verify_manifest_coverage() {
  local kind expected path extra patch_path
  local records=0
  declare -A manifest_paths=()
  local -a patch_paths=()
  local -a added_paths=()

  while IFS=$'\t' read -r kind expected path extra; do
    [[ -z "$kind" || "$kind" == \#* ]] && continue
    [[ -z "${extra:-}" ]] || fail "invalid preimage record: $kind"
    [[ "$kind" == "sha256" || "$kind" == "absent" ]] || fail "unknown preimage record type: $kind"
    [[ -n "$expected" && -n "$path" ]] || fail "incomplete preimage record: $kind"
    [[ -z "${manifest_paths[$path]+x}" ]] || fail "duplicate preimage path: $path"
    manifest_paths["$path"]="$kind"
    records=$((records + 1))
  done < "$preimages_file"

  mapfile -t patch_paths < <(
    awk '/^diff --git a\// { path=$4; sub(/^b\//, "", path); print path }' "$patch_file"
  )
  mapfile -t added_paths < <(
    awk '
      /^diff --git a\// { path=$4; sub(/^b\//, "", path) }
      /^--- \/dev\/null$/ { print path }
    ' "$patch_file"
  )

  ((${#patch_paths[@]} > 0)) || fail "adapter patch contains no file changes"
  ((${#patch_paths[@]} == records)) || fail "preimage manifest does not exactly cover adapter paths"
  for patch_path in "${patch_paths[@]}"; do
    [[ -n "${manifest_paths[$patch_path]+x}" ]] || fail "adapter path has no preimage record: $patch_path"
  done
  for patch_path in "${added_paths[@]}"; do
    [[ "${manifest_paths[$patch_path]}" == "absent" ]] || fail "added adapter path lacks an absence preimage: $patch_path"
  done
}

verify_locks() {
  if ! python3 - "$tree/lazy-lock.json" "/usr/share/omarchy-nvim/config/lazy-lock.json" <<'PY'
import json
import sys

adapted_path, installed_path = sys.argv[1:]
try:
    with open(adapted_path, encoding="utf-8") as handle:
        locks = json.load(handle)
    with open(installed_path, encoding="utf-8") as handle:
        installed = json.load(handle)
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)

required = (
    "aether", "ashen.nvim", "bamboo.nvim", "catppuccin", "ethereal.nvim",
    "everforest-nvim", "flexoki-neovim", "gruvbox.nvim", "hackerman.nvim",
    "kanagawa.nvim", "lumon.nvim", "matteblack.nvim", "miasma.nvim",
    "monokai-pro.nvim", "nightfox.nvim", "retro-82.nvim", "rose-pine",
    "tokyonight.nvim", "vantablack.nvim", "white.nvim",
)

for name in required:
    if name not in installed:
        raise SystemExit(f"FAIL: installed Omarchy lock is missing {name}")
    if locks.get(name) != installed[name]:
        raise SystemExit(f"FAIL: adapted Omarchy theme lock differs for {name}")

for removed in ("gentleman-kanagawa-blur", "oldworld.nvim"):
    if removed in locks:
        raise SystemExit(f"FAIL: obsolete Gentleman theme lock remains: {removed}")
PY
  then
    fail "Omarchy theme lock verification failed"
  fi
}

verify_lua_and_json() {
  local path
  local -a lua_files=()
  local -a json_files=()

  shopt -s globstar nullglob
  lua_files=("$tree"/**/*.lua)
  json_files=("$tree"/*.json)

  for path in "${lua_files[@]}"; do
    [[ "$(basename -- "$path")" == symlink_* ]] && continue
    luac -p "$path" 2>/dev/null || fail "Lua compile check failed: ${path#"$tree/"}"
  done

  if ! python3 - "${json_files[@]}" <<'PY'
import json
import sys

for path in sys.argv[1:]:
    try:
        with open(path, encoding="utf-8") as handle:
            json.load(handle)
    except (OSError, json.JSONDecodeError):
        raise SystemExit(1)
PY
  then
    fail "JSON parse check failed"
  fi
}

[[ -d "$tree" ]] || fail "adapted Neovim tree is missing"
for required in "$patch_file" "$preimages_file" "$contract_file"; do
  [[ -f "$required" ]] || fail "required adapter artifact is missing"
done

verify_contract
verify_manifest_coverage

assert_source_link "lua/plugins/symlink_theme.lua" "../../../../.local/state/omarchy/current/theme/neovim.lua"
assert_source_link "lua/plugins/symlink_all-themes.lua" "/usr/share/omarchy-nvim/config/lua/plugins/all-themes.lua"
assert_source_link "lua/plugins/symlink_omarchy-theme-hotreload.lua" "/usr/share/omarchy-nvim/config/lua/plugins/omarchy-theme-hotreload.lua"
assert_source_link "plugin/after/symlink_transparency.lua" "/usr/share/omarchy-nvim/config/plugin/after/transparency.lua"
assert_source_link "lua/config/symlink_remote_clipboard.lua" "/usr/share/omarchy-nvim/config/lua/config/remote_clipboard.lua"

[[ ! -e "$tree/lua/plugins/colorscheme.lua" ]] || fail "Gentleman colorscheme ownership remains"
assert_contains 'theme = "auto"' "lua/plugins/ui.lua"
assert_contains 'build = "make"' "lua/plugins/avante.lua"
assert_contains '{ "mise", "ls", "--global", "--installed", "--json", "node" }' "lua/config/nodejs.lua"
assert_contains 'entry.active == true' "lua/config/nodejs.lua"
assert_contains 'entry.install_path' "lua/config/nodejs.lua"
assert_contains 'prepend_path_once(bin)' "lua/config/nodejs.lua"
assert_contains 'bin .. "/neovim-node-host"' "lua/config/nodejs.lua"
assert_contains 'mise use --global node@lts' "lua/config/nodejs.lua"
assert_contains '"/usr/bin/node", "/usr/local/bin/node"' "lua/config/nodejs.lua"
assert_contains '<cmd>Obsidian quick_switch<CR>' "lua/config/keymaps.lua"

if grep -Eq 'npm_host_prog|mise", "which", "node|node_host_prog = (node|state\.node)' "$tree/lua/config/nodejs.lua"; then
  fail "Node.js provider configuration uses an invalid API or resolver"
fi

clipboard_calls="$(grep -RhoF --include='*.lua' -- 'require("config.remote_clipboard").setup()' "$tree" 2>/dev/null | wc -l || true)"
[[ "$clipboard_calls" == "1" ]] || fail "expected exactly one remote clipboard setup call, found $clipboard_calls"

forbidden_pattern='(^|[^[:alnum:]_])(Nix(OS|pkgs|fmt)?|Darwin|macOS|Homebrew|brew|WSL|win32|win64|win32yank|PowerShell|Volta|NVM|Zellij)([^[:alnum:]_]|$)|/opt/homebrew|\.volta/|\.nvm/|has\([^)]*(win32|win64|wsl)|Build\.ps1|Windows users|use_absolute_path'
if grep -ERqi --include='*.lua' -- "$forbidden_pattern" "$tree"; then
  fail "forbidden platform/runtime-manager or Zellij reference remains"
fi

verify_locks
verify_lua_and_json
if ! bash "$repo_root/tests/nvim-nodejs.sh" "$tree/lua/config/nodejs.lua" >/dev/null 2>&1; then
  fail "global Mise Node.js provider harness failed"
fi

printf 'PASS: global Mise Node.js provider harnesses\n'
printf 'PASS: Omarchy Neovim adapter contract\n'
