-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

local function set_win_separator()
  vim.api.nvim_set_hl(0, "WinSeparator", { fg = "#7aa2f7" })
end

vim.api.nvim_create_autocmd("ColorScheme", {
  pattern = "*",
  callback = set_win_separator,
})

-- LazyVim can load this file before directly loading TokyoNight (without a
-- ColorScheme event). Apply after startup so the theme cannot overwrite it.
vim.schedule(set_win_separator)

