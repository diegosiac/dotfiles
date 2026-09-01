#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
plugin_spec="${1:-$repo_root/dot_config/nvim/lua/plugins/gemini.lua}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/nvim-gemini-test.XXXXXX")"
trap 'rm -rf -- "$fixture"' EXIT

mkdir -p -- \
  "$fixture/home" \
  "$fixture/plugin" \
  "$fixture/xdg/config" \
  "$fixture/xdg/data" \
  "$fixture/xdg/state" \
  "$fixture/xdg/cache"

cat > "$fixture/plugin/gemini.vim" <<'VIM'
" Bootstrap the gemini-cli plugin
if !exists('g:gemini_loaded')
  lua require('gemini').setup()
  let g:gemini_loaded = 1
endif
VIM

cat > "$fixture/harness.lua" <<'LUA'
local spec_path = assert(vim.env.GEMINI_PLUGIN_SPEC)
local runtime_path = assert(vim.env.GEMINI_RUNTIME_FILE)
local scenario = assert(vim.env.GEMINI_SCENARIO)
local executable_result = scenario == "absent" and 0 or 1
local source_runtime = scenario ~= "present-fallback"
local executable_calls = 0
local module_loads = 0
local setup_calls = 0
local input_calls = 0

vim.fn.executable = function(name)
  assert(name == "gemini", "unexpected executable lookup: " .. tostring(name))
  executable_calls = executable_calls + 1
  return executable_result
end

package.loaded.gemini = nil
package.preload.gemini = function()
  module_loads = module_loads + 1
  return {
    setup = function()
      setup_calls = setup_calls + 1
      if executable_result ~= 1 then
        input_calls = input_calls + 1
      end
    end,
  }
end

vim.g.gemini_loaded = nil
local spec = dofile(spec_path)
assert(type(spec) == "table", "Gemini plugin spec did not return a table")
assert(spec[1] == "jonroosevelt/gemini-cli.nvim", "Gemini plugin identity changed")
assert(type(spec.init) == "function", "Gemini plugin init is missing")
assert(type(spec.config) == "function", "Gemini plugin config is missing")

spec.init()
if source_runtime then
  vim.cmd.source(runtime_path)
end
spec.config()

assert(executable_calls == 2, "Gemini init and config should each check the executable")
assert(input_calls == 0, "Gemini installation input path was reached")
assert(vim.g.gemini_loaded == 1, "Gemini bootstrap sentinel was not set")
if scenario == "absent" then
  assert(module_loads == 0, "Gemini module loaded while the CLI was absent")
  assert(setup_calls == 0, "Gemini setup ran while the CLI was absent")
else
  assert(module_loads == 1, "Gemini module should load exactly once when the CLI exists")
  assert(setup_calls == 1, "Gemini setup should run exactly once when the CLI exists")
end
LUA

run_scenario() {
  local scenario="$1"

  HOME="$fixture/home" \
  XDG_CONFIG_HOME="$fixture/xdg/config" \
  XDG_DATA_HOME="$fixture/xdg/data" \
  XDG_STATE_HOME="$fixture/xdg/state" \
  XDG_CACHE_HOME="$fixture/xdg/cache" \
  GEMINI_PLUGIN_SPEC="$plugin_spec" \
  GEMINI_RUNTIME_FILE="$fixture/plugin/gemini.vim" \
  GEMINI_SCENARIO="$scenario" \
    nvim --headless --clean -u NONE -i NONE --noplugin -l "$fixture/harness.lua"
}

run_scenario absent
run_scenario present-runtime
run_scenario present-fallback

printf 'PASS: Gemini runtime bootstrap is noninteractive and setup runs at most once\n'
