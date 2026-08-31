local function fail(message)
  io.stderr:write("FAIL: Node.js harness: " .. message .. "\n")
  vim.cmd("cquit 1")
end

local function assert_true(value, message)
  if not value then
    fail(message)
  end
end

local module_path = assert(vim.env.NODEJS_MODULE, "NODEJS_MODULE is required")
local install_path = assert(vim.env.NODEJS_ACTIVE_INSTALL, "NODEJS_ACTIVE_INSTALL is required")
local scenario = assert(vim.env.NODEJS_SCENARIO, "NODEJS_SCENARIO is required")
local bin = install_path .. "/bin"
local host = bin .. "/neovim-node-host"
local notifications = {}

vim.notify = function(message)
  notifications[#notifications + 1] = message
end

local nodejs = dofile(module_path)
assert_true(nodejs.setup({ silent = true }), "setup did not select the active global Mise Node.js runtime")
assert_true(nodejs.setup({ silent = true }), "repeated setup failed")

local path_entries = vim.split(vim.env.PATH or "", ":", { plain = true, trimempty = true })
local bin_count = 0
for _, entry in ipairs(path_entries) do
  if entry == bin then
    bin_count = bin_count + 1
  end
end

assert_true(path_entries[1] == bin, "global Mise bin was not prepended to PATH")
assert_true(bin_count == 1, "global Mise bin was duplicated in PATH")
assert_true(vim.g.npm_host_prog == nil, "unrecognized npm provider setting was assigned")

if scenario == "provider-present" then
  assert_true(vim.g.node_host_prog == host, "node_host_prog does not point to neovim-node-host")
  assert_true(vim.g.node_host_prog ~= bin .. "/node", "node_host_prog points to the Node.js runtime")
elseif scenario == "provider-missing" then
  assert_true(vim.g.node_host_prog == nil, "node_host_prog was set without an executable provider host")
  local guidance_found = false
  for _, message in ipairs(notifications) do
    if message:find("npm install --global neovim", 1, true) then
      guidance_found = true
      break
    end
  end
  assert_true(guidance_found, "missing provider guidance was not reported")
else
  fail("unknown scenario")
end

vim.cmd("qa")
