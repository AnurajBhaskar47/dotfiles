vim.keymap.set("x", "y", function()
  vim.cmd('normal! "zy')

  local result = vim.fn.system(
    { "/usr/bin/pbcopy" },
    vim.fn.getreg("z")
  )

  if vim.v.shell_error ~= 0 then
    vim.notify(result, vim.log.levels.ERROR)
    return
  end

  vim.cmd("qa!")
end, { silent = true })

vim.keymap.set("n", "q", "<Cmd>qa!<CR>", { silent = true })

