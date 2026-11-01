local M = {}

M.defaults = {
  tests_relative_dir = "",
  tests_file_suffix = ":tests",
  save_before_run = true,
  allow_shell = false,
  run_timeout_ms = 5000,
  compile_timeout_ms = 30000,
  output_limit = 1024 * 1024,
  run_args = {},
  panel_width = 0.42,
  close_sidebar = false,
  lint_enabled = false,
  lint_delay_ms = 700,
  lint_error_region_scope = "DiagnosticError",
  lint_warning_region_scope = "DiagnosticWarn",
  cpp_complete_enabled = true,
  cpp_complete_settings = {
    classes = {
      int = { template_size = 0 },
      char = { template_size = 0 },
      string = { template_size = 0 },
      pair = { template_size = 2 },
      vector = { template_size = 1 },
      bool = { template_size = 0 },
      ll = { template_size = 0 },
      double = { template_size = 0 },
      set = { template_size = 1, bind = "S" },
      map = { template_size = 2 },
    },
    dont_expand = { "pii" },
  },
  algorithms_base = false,
  numeric_highlights = false,
  stress_time_limit_seconds = 2,
  stress_iterations = 0,
  companion = {
    port = 12345,
    extension = "cpp",
    template = "",
    max_request_bytes = 2 * 1024 * 1024,
  },
  run_settings = {
    {
      name = "C++",
      extensions = { "cpp" },
      compile_cmd = { "g++", "{source_file}", "-std=gnu++17", "-o", "{file_name}" },
      run_cmd = { "./{file_name}", "{args}" },
      lint_compile_cmd = { "g++", "-std=gnu++17", "-fsyntax-only", "{source_file}", "-I", "{source_file_dir}" },
    },
    { name = "Python", extensions = { "py" }, compile_cmd = false, run_cmd = { "python", "{source_file}", "{args}" } },
    {
      name = "Java",
      extensions = { "java" },
      compile_cmd = { "javac", "-J-Dfile.encoding=utf8", "-d", "{source_file_dir}", "{source_file}" },
      run_cmd = { "java", "-classpath", "{source_file_dir}", "{file_name}", "{args}" },
    },
  },
  debug = {
    adapter = "",
    compile_cmd = false,
    program = "{source_file_dir}/{file_name}-debug",
    input_file = "input.txt",
    stop_on_entry = true,
  },
}

local placeholders = { file = true, source_file = true, source_file_dir = true, file_name = true, args = true }

local function command(cmd, allow_shell)
  if cmd == nil or cmd == false then
    return
  end
  assert(type(cmd) == "table" or type(cmd) == "string", "command must be an argument array or string")
  if type(cmd) == "string" then
    assert(allow_shell, "string commands require allow_shell = true")
  else
    assert(vim.islist(cmd) and #cmd > 0, "command array must not be empty")
  end
  for _, arg in ipairs(type(cmd) == "table" and cmd or { cmd }) do
    assert(type(arg) == "string", "command arguments must be strings")
    local rest = arg:gsub("{([%w_]+)}", function(key)
      assert(placeholders[key], "unknown placeholder: " .. key)
      return ""
    end)
    assert(not rest:find("[{}]"), "invalid command template: " .. arg)
    if type(cmd) == "table" and arg:find("{args}", 1, true) then
      assert(arg == "{args}", "{args} must be a separate array argument")
    end
  end
end

function M.setup(opts)
  opts = opts or {}
  for key in pairs(opts) do
    assert(M.defaults[key] ~= nil, "unknown focc option: " .. key)
  end
  local cfg = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
  -- Lists replace defaults. They must not merge by numeric index.
  if opts.run_settings then
    cfg.run_settings = vim.deepcopy(opts.run_settings)
  end
  assert(type(cfg.tests_relative_dir) == "string", "tests_relative_dir must be a string")
  assert(type(cfg.tests_file_suffix) == "string" and cfg.tests_file_suffix ~= "", "tests_file_suffix must not be empty")
  assert(not cfg.tests_file_suffix:find("[/\\]"), "tests_file_suffix must not contain a path separator")
  for _, key in ipairs({
    "run_timeout_ms",
    "compile_timeout_ms",
    "output_limit",
    "lint_delay_ms",
    "stress_time_limit_seconds",
  }) do
    assert(type(cfg[key]) == "number" and cfg[key] > 0, key .. " must be positive")
  end
  assert(
    type(cfg.panel_width) == "number" and cfg.panel_width > 0 and cfg.panel_width < 1,
    "panel_width must be between 0 and 1"
  )
  for _, key in ipairs({
    "save_before_run",
    "allow_shell",
    "close_sidebar",
    "lint_enabled",
    "cpp_complete_enabled",
    "numeric_highlights",
  }) do
    assert(type(cfg[key]) == "boolean", key .. " must be a boolean")
  end
  assert(vim.islist(cfg.run_args), "run_args must be an array")
  for _, arg in ipairs(cfg.run_args) do
    assert(type(arg) == "string", "run_args must contain strings")
  end
  assert(
    type(cfg.stress_iterations) == "number" and cfg.stress_iterations >= 0 and cfg.stress_iterations % 1 == 0,
    "stress_iterations must be a nonnegative integer"
  )
  assert(vim.islist(cfg.run_settings) and #cfg.run_settings > 0, "run_settings must be a nonempty array")
  local extensions = {}
  for _, lang in ipairs(cfg.run_settings) do
    assert(type(lang.name) == "string" and vim.islist(lang.extensions), "language requires name and extensions")
    for key in pairs(lang) do
      assert(
        vim.tbl_contains({ "name", "extensions", "compile_cmd", "run_cmd", "lint_compile_cmd" }, key),
        "unknown language option: " .. key
      )
    end
    assert(#lang.extensions > 0 and lang.run_cmd, "language requires extensions and run_cmd")
    for _, ext in ipairs(lang.extensions) do
      assert(type(ext) == "string" and not extensions[ext], "invalid or duplicate extension: " .. tostring(ext))
      extensions[ext] = true
    end
    for _, key in ipairs({ "compile_cmd", "run_cmd", "lint_compile_cmd" }) do
      command(lang[key], cfg.allow_shell)
    end
  end
  local binds = {}
  for name, class in pairs(cfg.cpp_complete_settings.classes) do
    assert(
      type(name) == "string"
        and type(class.template_size) == "number"
        and class.template_size >= 0
        and class.template_size % 1 == 0,
      "invalid completion class: " .. name
    )
    assert(not class.bind or #class.bind == 1, "completion bind must have one character")
    local bind = class.bind or name:sub(1, 1)
    assert(not binds[bind], "duplicate completion bind: " .. bind)
    binds[bind] = true
  end
  assert(
    cfg.algorithms_base == false or type(cfg.algorithms_base) == "string",
    "algorithms_base must be false or a directory"
  )
  assert(type(cfg.debug) == "table" and type(cfg.debug.adapter) == "string", "debug.adapter must be a string")
  command(cfg.debug.compile_cmd, cfg.allow_shell)
  assert(type(cfg.debug.program) == "string" and cfg.debug.program ~= "", "debug.program must not be empty")
  command({ cfg.debug.program }, false)
  assert(not cfg.debug.program:find("{args}", 1, true), "debug.program cannot use {args}")
  assert(type(cfg.debug.input_file) == "string" and cfg.debug.input_file ~= "", "debug.input_file must not be empty")
  assert(type(cfg.debug.stop_on_entry) == "boolean", "debug.stop_on_entry must be a boolean")
  assert(
    type(cfg.companion.port) == "number"
      and cfg.companion.port % 1 == 0
      and cfg.companion.port > 0
      and cfg.companion.port < 65536,
    "companion.port must be a valid TCP port"
  )
  assert(
    type(cfg.companion.extension) == "string" and cfg.companion.extension:match("^%w+$"),
    "invalid companion.extension"
  )
  assert(extensions[cfg.companion.extension], "companion.extension must match a configured language")
  assert(type(cfg.companion.template) == "string", "companion.template must be source text")
  assert(
    type(cfg.companion.max_request_bytes) == "number" and cfg.companion.max_request_bytes > 0,
    "companion.max_request_bytes must be positive"
  )
  if cfg.allow_shell then
    vim.notify(
      "FOCC: shell commands execute trusted configuration. Do not load untrusted commands.",
      vim.log.levels.WARN
    )
  end
  M.values = cfg
  return cfg
end

function M.language(source)
  local ext = vim.fn.fnamemodify(source, ":e")
  for _, lang in ipairs(M.values.run_settings) do
    if vim.tbl_contains(lang.extensions, ext) then
      return lang
    end
  end
  error("FOCC: unsupported extension: " .. ext)
end

return M
