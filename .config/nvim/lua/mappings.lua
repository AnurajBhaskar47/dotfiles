require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

-- map("n", ";", ":", { desc = "CMD enter command mode" })
-- map("i", "jk", "<ESC>")

map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")

-- Tmux sessionizer shortcut
map("n", "<C-f>", "<cmd>silent !tmux neww tmux-sessionizer<CR>")

-- Git blame decoration
map("n", "<leader>gb", "<cmd>BlameToggle<CR>", { desc = "Git blame toggle decoration" })

-- Telescope Symbol Search (LSP)
map("n", "<leader>fs", "<cmd>Telescope lsp_document_symbols<CR>", { desc = "Telescope document symbols" })
map("n", "<leader>fS", "<cmd>Telescope lsp_dynamic_workspace_symbols<CR>", { desc = "Telescope workspace symbols" })
