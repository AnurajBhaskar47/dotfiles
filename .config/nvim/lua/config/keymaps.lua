-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local function multicursors_clear_all()
  local mc_ns = vim.api.nvim_create_namespace("nvim.multicursor")
  vim.api.nvim_buf_clear_namespace(0, mc_ns, 0, -1)
end

vim.keymap.set("n", "<leader>qm", multicursors_clear_all, { desc = "Clear all multicursors" })
vim.keymap.set("n", "<C-x>", function()
  vim.cmd("botright 15new")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].bufhidden = "wipe"
  local job = vim.fn.jobstart({ vim.fn.expand("~/.local/scripts/rex-sessionizer") }, {
    term = true,
    on_exit = function(_, code)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        if code == 0 then
          if vim.api.nvim_get_current_buf() == buf then
            vim.cmd("stopinsert")
          end
          vim.api.nvim_buf_delete(buf, { force = true })
        else
          vim.notify("Rex sessionizer failed (exit " .. code .. "). See terminal output.", vim.log.levels.ERROR)
        end
      end)
    end,
  })
  if job <= 0 then
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.notify("Could not start Rex sessionizer", vim.log.levels.ERROR)
    return
  end
  vim.cmd("startinsert")
end, { desc = "Run Rex sessionizer" })
