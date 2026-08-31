-- Resolve Neovim's Node.js runtime and provider from the global Mise configuration.

local M = {}

local state = {
  source = "unconfigured",
  node = nil,
  npm = nil,
  provider = nil,
  mise_bin = nil,
  detail = nil,
}

local function run(command, options)
  options = vim.tbl_extend("force", { text = true }, options or {})
  local result = vim.system(command, options):wait()
  return result.code, vim.trim(result.stdout or ""), vim.trim(result.stderr or "")
end

local function prepend_path_once(directory)
  local updated = { directory }
  for _, entry in ipairs(vim.split(vim.env.PATH or "", ":", { plain = true, trimempty = true })) do
    if entry ~= directory then
      updated[#updated + 1] = entry
    end
  end
  vim.env.PATH = table.concat(updated, ":")
end

local function global_mise_install()
  if vim.fn.executable("mise") ~= 1 then
    return nil, "Mise is not executable"
  end

  local home = vim.env.HOME or vim.uv.os_homedir()
  local code, stdout, stderr = run(
    { "mise", "ls", "--global", "--installed", "--json", "node" },
    { cwd = home }
  )
  if code ~= 0 then
    return nil, stderr ~= "" and stderr or "Mise could not list the global Node.js runtime"
  end

  local ok, entries = pcall(vim.json.decode, stdout)
  if not ok or type(entries) ~= "table" then
    return nil, "Mise returned invalid JSON for the global Node.js runtime"
  end

  local selected = nil
  for _, entry in ipairs(entries) do
    if
      entry.active == true
      and entry.installed == true
      and type(entry.install_path) == "string"
      and entry.install_path ~= ""
    then
      if selected then
        return nil, "Mise reported multiple active global Node.js runtimes"
      end
      selected = entry.install_path
    end
  end

  if not selected then
    return nil, "Mise has no active installed global Node.js runtime"
  end

  return selected, nil
end

local function select_node()
  local install_path, mise_detail = global_mise_install()
  if install_path then
    local bin = install_path .. "/bin"
    local node = bin .. "/node"
    if vim.fn.executable(node) == 1 then
      prepend_path_once(bin)
      return node, bin, "Mise global", nil
    end
    mise_detail = "The active global Mise Node.js runtime has no executable bin/node"
  end

  for _, node in ipairs({ "/usr/bin/node", "/usr/local/bin/node" }) do
    if vim.fn.executable(node) == 1 then
      return node, vim.fn.fnamemodify(node, ":h"), "Linux system fallback", mise_detail
    end
  end

  return nil, nil, "unavailable", mise_detail
end

local function executable_or_nil(path)
  return path and vim.fn.executable(path) == 1 and path or nil
end

local function node_version(node)
  local code, stdout = run({ node, "--version" })
  if code ~= 0 then
    return nil
  end
  return stdout:gsub("^v", ""):match("(%d+%.%d+%.%d+)")
end

local function provider_guidance(bin)
  return "Neovim's Node.js provider is unavailable because "
    .. bin
    .. "/neovim-node-host is not executable. Install it under the global Mise Node.js runtime with:\n"
    .. "  mise use --global node@lts\n"
    .. "  npm install --global neovim"
end

local function setup_nodejs()
  vim.g.node_host_prog = nil
  state = {
    source = "unconfigured",
    node = nil,
    npm = nil,
    provider = nil,
    mise_bin = nil,
    detail = nil,
  }

  local node, bin, source, detail = select_node()
  state.source = source
  state.detail = detail
  if not node then
    vim.notify(
      "Node.js was not found. Install the global Mise runtime with:\n  mise use --global node@lts",
      vim.log.levels.ERROR
    )
    return false, nil
  end

  state.node = node
  state.npm = executable_or_nil(bin .. "/npm")
  state.mise_bin = source == "Mise global" and bin or nil
  state.provider = executable_or_nil(bin .. "/neovim-node-host")
  if state.provider then
    vim.g.node_host_prog = state.provider
  else
    vim.notify(provider_guidance(bin), vim.log.levels.WARN)
  end

  local version = node_version(node)
  if not version then
    vim.notify("Could not read the Node.js version from the selected runtime.", vim.log.levels.ERROR)
    return false, nil
  end

  local major = tonumber(version:match("^(%d+)"))
  if major and major < 18 then
    vim.notify(
      "Node.js v"
        .. version
        .. " is too old. Neovim requires v18+ (v22+ recommended).\n\nUpgrade with:\n  mise use --global node@lts",
      vim.log.levels.WARN
    )
  elseif vim.g.debug_nodejs or vim.env.DEBUG_NODEJS then
    print("Node.js runtime: " .. node .. " (v" .. version .. ")")
    print("Source: " .. source)
  end

  return true, version
end

local function check_node_version(version)
  local major = version and tonumber(version:match("^(%d+)"))
  if major and major >= 18 and major < 22 and vim.g.debug_nodejs then
    vim.notify("Node.js v" .. version .. " works, but v22+ is recommended.", vim.log.levels.INFO)
  end
end

function M.setup(opts)
  opts = opts or {}
  local success, version = setup_nodejs()
  if success and not opts.silent then
    check_node_version(version)
  end
  return success
end

function M.info()
  print("Node.js runtime: " .. (state.node or "Not configured"))
  print("Source: " .. state.source)
  print("npm: " .. (state.npm or "Not found adjacent to the selected Node.js runtime"))
  print("Neovim Node.js host: " .. (state.provider or "Not installed"))
  if state.mise_bin then
    print("Global Mise bin: " .. state.mise_bin)
  end
  if state.detail then
    print("Mise detail: " .. state.detail)
  end
  if not state.node then
    print("Guidance: mise use --global node@lts")
  elseif not state.provider then
    print("Provider guidance: npm install --global neovim")
  end

  if vim.g.debug_nodejs then
    print("Mise executable: " .. (vim.fn.exepath("mise") ~= "" and vim.fn.exepath("mise") or "Not found"))
    print("HOME: " .. (vim.env.HOME or "Not set"))
    print("PATH: " .. (vim.env.PATH or "Not set"))
  end
end

vim.api.nvim_create_user_command("NodeRefresh", function()
  M.setup({ silent = false })
  M.info()
end, { desc = "Refresh global Mise Node.js configuration" })

vim.api.nvim_create_user_command("NodeInfo", function()
  M.info()
end, { desc = "Show global Mise Node.js configuration" })

vim.api.nvim_create_user_command("NodeDebug", function()
  vim.g.debug_nodejs = true
  print("=== Global Mise Node.js Debug Mode ===")
  M.setup({ silent = false })
  M.info()
  print("=== End Debug Info ===")
  vim.g.debug_nodejs = false
end, { desc = "Debug global Mise Node.js resolution" })

return M
