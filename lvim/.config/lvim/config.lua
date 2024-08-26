-- Read the docs: https://www.lunarvim.org/docs/configuration
-- Example configs: https://github.com/LunarVim/starter.lvim
-- Video Tutorials: https://www.youtube.com/watch?v=sFA9kX-Ud_c&list=PLhoH5vyxr6QqGu0i7tt_XoVK9v-KvZ3m6
-- Forum: https://www.reddit.com/r/lunarvim/
-- Discord: https://discord.com/invite/Xb9B4Ny


-- Formatting
lvim.format_on_save.enabled = true
lvim.format_on_save.pattern = { "*.lua", "*.py", "*.cpp", "*.rs" }
-- lvim.transparent_window = true

vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.g.nvim_markdown_preview_theme = 'solarized-dark'

-- Vim_settings
vim.opt.relativenumber = true
vim.keymap.set("i", "jj", "<Esc>")
vim.keymap.set("i", "<C-BS>", "<C-w>")

-- Lvim_keybindings
lvim.keys.insert_mode["<S-Tab>"] = "<C-d>"
-- lvim.keys.normal_mode["o"] = "o<esc>"
-- lvim.keys.normal_mode["O"] = "O<esc>"
lvim.keys.normal_mode["Y"] = "Vy"
lvim.keys.normal_mode["<Esc>"] = ":nohl<cr>"
lvim.keys.normal_mode["<C-m>"] = ":MarkdownPreview<cr>"
lvim.keys.normal_mode["<A-n>"] = ":RunCode<cr>:startinsert <cr>" -- Code-Runner
lvim.keys.normal_mode["<C-a>"] = "ggVG"
lvim.keys.normal_mode["<C-s>"] = ":SessionSearch<CR>"            --Session search

lvim.builtin.terminal.execs = {
    { nil, "<C-`>", "Horizontal Terminal", "horizontal", 0.3 },
    { nil, "<C-.>", "Vertical Terminal",   "vertical",   0.4 },
    { nil, "<M-3>", "Float Terminal",      "float",      nil },
}

-- Leader-keybindings
lvim.builtin.which_key.mappings["bt"] = { ":Telescope current_buffer_fuzzy_find<cr>", "Current buffer fuzzy find" }
lvim.builtin.which_key.mappings["R"] = { ":RunCode<cr>:startinsert <cr>", "Run code" }
lvim.builtin.which_key.mappings["rF"] = { ":RunFile tab<CR>", "Run Files" }
lvim.builtin.which_key.mappings["rf"] = { ":RunFile<CR>", "Run File" }
lvim.builtin.which_key.mappings["rp"] = { ":RunProject<CR>", "Run Project" }
lvim.builtin.which_key.mappings["rc"] = { ":RunClose<CR>", "Run Close" }
-- lvim.builtin.which_key.mappings["crf"] = { ":CRFiletype<CR>", "CR Filetype" }
-- lvim.builtin.which_key.mappings["crp"] = { ":CRProjects<CR>", "CR Projects" }

-- Plugins
lvim.plugins = {
    -- Cmake-tools␍
    {
        "Civitasv/cmake-tools.nvim"
    },
    -- CodeRunner␍
    {
        "CRAG666/code_runner.nvim",
        config = true,
        dependencies = { "nvim-lua/plenary.nvim" },
    },

    -- Render-Markdown
    {
        'MeanderingProgrammer/render-markdown.nvim',
        opts = {},
        dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.nvim' }, -- if you use the mini.nvim suite
        -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.icons' }, -- if you use standalone mini plugins
        -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
    },
    {
        'rmagatti/auto-session',
        lazy = false,
        dependencies = {
            'nvim-telescope/telescope.nvim', -- Only needed if you want to use session lens
        },
        keys = {
            -- Will use Telescope if installed or a vim.ui.select picker otherwise
            { '<leader>wr', '<cmd>SessionSearch<CR>',         desc = 'Session search' },
            { '<leader>ws', '<cmd>SessionSave<CR>',           desc = 'Save session' },
            { '<leader>wa', '<cmd>SessionToggleAutoSave<CR>', desc = 'Toggle autosave' },
        },

        ---enables autocomplete for opts
        ---@module "auto-session"
        ---@type AutoSession.Config
        opts = {
            suppressed_dirs = { '~/', '~/Projects', '~/Downloads', '/' },
            -- log_level = 'debug',
        }
    },
    {
        "simrat39/rust-tools.nvim",
        ft = "rust",
        dependencies = "neovim/nvim-lspconfig",
        -- opts = function ()
        --   return require "custom.configs.rust-tools"␍
        -- end,
    },
    { "mfussenegger/nvim-dap-python" },
    { "nvim-neotest/nvim-nio" },
    { "nvim-neotest/neotest" },
    { "nvim-neotest/neotest-python" },

}


-- Debug Adapter Protocol
lvim.builtin.dap.active = true

-- Python
local mason_path = vim.fn.glob(vim.fn.stdpath "data" .. "/mason/")
pcall(function()
    require("dap-python").setup(mason_path .. "packages/debugpy/venv/bin/python")
end)

require("neotest").setup({
    adapters = {
        require("neotest-python")({
            dap = {
                justMyCode = false,
                console = "integratedTerminal",
            },
            args = { "--log-level", "DEBUG", "--quiet" },
            runner = "pytest",
        })
    }
})

-- DAP Keybindings
lvim.builtin.which_key.mappings["dm"] = { "<cmd>lua require('neotest').run.run()<cr>",
    "Test Method" }
lvim.builtin.which_key.mappings["dM"] = { "<cmd>lua require('neotest').run.run({strategy = 'dap'})<cr>",
    "Test Method DAP" }
lvim.builtin.which_key.mappings["df"] = {
    "<cmd>lua require('neotest').run.run({vim.fn.expand('%')})<cr>", "Test Class" }
lvim.builtin.which_key.mappings["dF"] = {
    "<cmd>lua require('neotest').run.run({vim.fn.expand('%'), strategy = 'dap'})<cr>", "Test Class DAP" }
lvim.builtin.which_key.mappings["dS"] = { "<cmd>lua require('neotest').summary.toggle()<cr>", "Test Summary" }
