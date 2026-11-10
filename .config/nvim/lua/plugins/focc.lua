return {
  {
    name = "focc.nvim",
    dir = vim.fn.stdpath("config") .. "/local/focc.nvim",
    main = "focc",
    cmd = "Focc",
    ft = { "cpp", "python", "java" },
    opts = {
      tests_relative_dir = ".focc",
      tests_file_suffix = ":tests",
      run_settings = {
        {
          name = "C++",
          extensions = { "cpp" },
          compile_cmd = { "clang++", "{source_file}", "-std=c++26", "-o", "{file_name}" },
          run_cmd = { "./{file_name}", "{args}" },
          lint_compile_cmd = { "clang++", "-std=c++23", "-fsyntax-only", "{source_file}", "-I", "{source_file_dir}" },
        },
        {
          name = "Python",
          extensions = { "py" },
          compile_cmd = false,
          run_cmd = { "python3", "{source_file}", "{args}" },
        },
        {
          name = "Java",
          extensions = { "java" },
          compile_cmd = { "javac", "-J-Dfile.encoding=utf8", "-d", "{source_file_dir}", "{source_file}" },
          run_cmd = { "java", "-classpath", "{source_file_dir}", "{file_name}", "{args}" },
        },
      },
      -- Opt in to compiler linting if you do not use clangd diagnostics.
      lint_enabled = false,
      cpp_complete_enabled = true,
      numeric_highlights = false,
      close_sidebar = false,
      companion = { port = 12345 },
      debug = {
        adapter = "codelldb",
        compile_cmd = { "clang++", "-std=c++26", "-g", "-O0", "{source_file}", "-o", "{file_name}-debug" },
        stop_on_entry = true,
      },
    },
  },
  {
    "saghen/blink.cmp",
    optional = true,
    opts = function(_, opts)
      opts.sources = opts.sources or {}
      opts.sources.providers = opts.sources.providers or {}
      opts.sources.providers.focc = { name = "FOCC", module = "focc.blink", score_offset = 20 }
      opts.sources.per_filetype = opts.sources.per_filetype or {}
      local cpp = opts.sources.per_filetype.cpp
      if type(cpp) == "function" then
        local previous = cpp
        opts.sources.per_filetype.cpp = function()
          local sources = previous()
          if not vim.tbl_contains(sources, "focc") then
            sources[#sources + 1] = "focc"
          end
          return sources
        end
      else
        cpp = cpp or { inherit_defaults = true }
        if not vim.tbl_contains(cpp, "focc") then
          cpp[#cpp + 1] = "focc"
        end
        opts.sources.per_filetype.cpp = cpp
      end
    end,
  },
}
