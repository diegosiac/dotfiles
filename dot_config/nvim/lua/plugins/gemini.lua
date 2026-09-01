return {
  "jonroosevelt/gemini-cli.nvim",
  init = function()
    if vim.fn.executable("gemini") ~= 1 then
      vim.g.gemini_loaded = 1
    end
  end,
  config = function()
    if vim.fn.executable("gemini") ~= 1 then
      return
    end

    if vim.g.gemini_loaded == 1 then
      return
    end

    require("gemini").setup()
    vim.g.gemini_loaded = 1
  end,
}
