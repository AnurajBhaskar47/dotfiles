local base_dir = vim.env.LUNARVIM_BASE_DIR
    or (function()
        local init_path = debug.getinfo(1, "S").source
        return init_path:sub(2):match("(.*[/\\])"):sub(1, -2)
    end)()

if not vim.tbl_contains(vim.opt.rtp:get(), base_dir) then
    vim.opt.rtp:prepend(base_dir)
end

require("lvim.bootstrap"):init(base_dir)

require("lvim.config"):load()

local plugins = require "lvim.plugins"

require("lvim.plugin-loader").load { plugins, lvim.plugins }

require("lvim.core.theme").setup()

local Log = require "lvim.core.log"
Log:debug "Starting LunarVim"

local commands = require "lvim.core.commands"
commands.load(commands.defaults)

-- Code-Runner setup
require('code_runner').setup({
    -- term = {
    --     --  Position to open the terminal, this option is ignored if mode ~= term
    --     position = "bot",
    --     -- window size, this option is ignored if mode == tab
    --     size = 12,
    -- },
    filetype = {
        java = {
            "cd $dir &&",
            "javac $fileName &&",
            "java $fileNameWithoutExt &&",
            "rm $dir/$fileNameWithoutExt.class"
        },
        python = "python3 -u",
        cpp =
        "cd $dir && g++ $fileName -o $fileNameWithoutExt && $dir/$fileNameWithoutExt && rm $dir/$fileNameWithoutExt",
        typescript = "deno run",
        rust = {
            "cd $dir &&",
            "rustc $fileName &&",
            "$dir/$fileNameWithoutExt"
        },
        c =
        "cd $dir && gcc $fileName -o $fileNameWithoutExt && $dir/$fileNameWithoutExt && rm $dir/$fileNameWithoutExt",
        --  c = function(...)
        --    c_base = {
        --      "cd $dir &&",
        --      "gcc $fileName -o",
        --      "$fileNameWithoutExt",
        --    }
        --    local c_exec = {
        --      "&& $fileNameWithoutExt &&",
        --      "rm $fileNameWithoutExt",
        --    }
        --   vim.ui.input({ prompt = "Add more args:" }, function(input)
        --     c_base[4] = input
        --     vim.print(vim.tbl_extend("force", c_base, c_exec))
        --     require("code_runner.commands").run_from_fn(vim.list_extend(c_base, c_exec))
        --   end)
        -- end,
    },
})
