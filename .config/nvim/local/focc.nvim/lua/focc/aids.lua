local M = {}
local lint_ns = vim.api.nvim_create_namespace("focc-lint")
local number_ns = vim.api.nvim_create_namespace("focc-numbers")
local style_ns = vim.api.nvim_create_namespace("focc-lint-styles")
local pending, jobs = {}, {}

function M.expand(prefix)
  local cfg = require("focc.config").values
  if not cfg.cpp_complete_enabled then
    return
  end
  local classes = {}
  for name, class in pairs(cfg.cpp_complete_settings.classes) do
    local bind = class.bind or name:sub(1, 1)
    if classes[bind] then
      return nil
    end
    classes[bind] = { name = name, size = class.template_size }
  end
  local function parse(index)
    local class = classes[prefix:sub(index, index)]
    if not class then
      return nil, index
    end
    local start, children = index, {}
    index = index + 1
    for _ = 1, class.size do
      local child
      child, index = parse(index)
      if not child then
        return nil, index
      end
      children[#children + 1] = child
    end
    local token = prefix:sub(start, index - 1)
    if vim.tbl_contains(cfg.cpp_complete_settings.dont_expand, token) then
      return token, index
    end
    return class.name .. (#children > 0 and ("<" .. table.concat(children, ", ") .. ">") or ""), index
  end
  local result, index = parse(1)
  if index ~= #prefix + 1 then
    return nil
  end
  return result
end

function M.complete(findstart, base)
  if findstart == 1 then
    local cursor = vim.api.nvim_win_get_cursor(0)
    local before = vim.api.nvim_get_current_line():sub(1, cursor[2])
    return #before - #(before:match("[%w_]+$") or "")
  end
  local expanded = M.expand(base)
  return expanded and expanded ~= base and { { word = expanded, menu = "FOCC" } } or {}
end

function M.parse_diagnostics(output, source)
  local diagnostics = {}
  for line in output:gmatch("[^\n]+") do
    local path, row, col, kind, message = line:match("^(.-):(%d+):(%d+):%s*([%w ]+):%s*(.*)$")
    if path == source then
      diagnostics[#diagnostics + 1] = {
        lnum = tonumber(row) - 1,
        col = tonumber(col) - 1,
        message = message,
        source = "FOCC",
        severity = kind:find("warning") and vim.diagnostic.severity.WARN or vim.diagnostic.severity.ERROR,
      }
    end
  end
  return diagnostics
end

function M.lint(buf)
  local cfg = require("focc.config").values
  if not cfg.lint_enabled or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local source = vim.api.nvim_buf_get_name(buf)
  local ok, lang = pcall(require("focc.config").language, source)
  if not ok or lang.name ~= "C++" or not lang.lint_compile_cmd then
    return
  end
  if jobs[buf] then
    jobs[buf]:cancel()
  end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local tmp = vim.fn.tempname() .. ".cpp"
  local file = assert(io.open(tmp, "wb"))
  file:write(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") .. "\n")
  file:close()
  local cmd = require("focc.process").command(lang.lint_compile_cmd, source)
  for i, arg in ipairs(cmd) do
    if arg == source then
      cmd[i] = tmp
    end
    if cfg.allow_shell and i == #cmd then
      cmd[i] = arg:gsub(vim.pesc(source), function()
        return tmp
      end)
    end
  end
  jobs[buf] = require("focc.process").start(
    cmd,
    { cwd = vim.fs.dirname(source), timeout_ms = cfg.compile_timeout_ms },
    function(result)
      vim.uv.fs_unlink(tmp)
      if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_changedtick(buf) == tick and not result.reason then
        local diagnostics = M.parse_diagnostics(result.stderr .. "\n" .. result.stdout, tmp)
        vim.diagnostic.set(lint_ns, buf, diagnostics)
        vim.api.nvim_buf_clear_namespace(buf, style_ns, 0, -1)
        for _, item in ipairs(diagnostics) do
          local line = vim.api.nvim_buf_get_lines(buf, item.lnum, item.lnum + 1, false)[1]
          if line and item.col < #line then
            local span = line:sub(item.col + 1):match("^%w+") or line:sub(item.col + 1, item.col + 1)
            vim.api.nvim_buf_set_extmark(buf, style_ns, item.lnum, item.col, {
              end_col = item.col + #span,
              hl_group = item.severity == vim.diagnostic.severity.WARN and cfg.lint_warning_region_scope
                or cfg.lint_error_region_scope,
            })
          end
        end
      end
    end
  )
end

function M.numbers(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, number_ns, 0, -1)
  if not require("focc.config").values.numeric_highlights then
    return
  end
  -- Only syntax captures are marked. Strings and comments must remain unchanged.
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not ok or not parser then
    return
  end
  local trees = parser:parse()
  local query = vim.treesitter.query.get(parser:lang(), "highlights")
  if not query or not trees[1] then
    return
  end
  for id, node in query:iter_captures(trees[1]:root(), buf) do
    if query.captures[id]:match("^number") then
      local raw = vim.treesitter.get_node_text(node, buf)
      local digits = raw:match("^%d+") or ""
      local row, col = node:range()
      for offset = #digits - 3, 1, -3 do
        vim.api.nvim_buf_set_extmark(
          buf,
          number_ns,
          row,
          col + offset - 1,
          { end_col = col + offset, hl_group = "FoccDigitGroup" }
        )
      end
    end
  end
end

function M.snippet(path)
  local file = assert(io.open(path, "rb"), "FOCC: cannot read snippet")
  local value = file:read("*a")
  file:close()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  vim.api.nvim_buf_set_text(0, row, col, row, col, vim.split(value, "\n", { plain = true }))
  local properties = require("focc.store").read(path .. ":properties")
  if properties then
    local prop = vim.json.decode(properties)
    local function position(offset)
      assert(type(offset) == "number" and offset >= 0 and offset <= #value, "FOCC: invalid snippet offset")
      local prefix = value:sub(1, offset)
      local parts = vim.split(prefix, "\n", { plain = true })
      return row + #parts, (#parts == 1 and col or 0) + #parts[#parts]
    end
    for _, range in ipairs(prop.fold or {}) do
      local first = position(range[1])
      local last = position(range[2])
      if last > first then
        vim.wo.foldmethod = "manual"
        vim.cmd(first .. "," .. last .. "fold")
      end
    end
    if prop.move_cursor then
      local r, c = position(prop.move_cursor)
      vim.api.nvim_win_set_cursor(0, { r, c })
    end
  end
end

function M.pick_snippet()
  local base = require("focc.config").values.algorithms_base
  assert(base, "FOCC: configure algorithms_base first")
  local files = vim.fn.globpath(vim.fn.expand(base), "**/*.cpp", false, true)
  vim.ui.select(files, {
    prompt = "FOCC algorithm",
    format_item = function(path)
      return vim.fs.basename(path)
    end,
  }, function(path)
    if path then
      local ok, err = pcall(M.snippet, path)
      if not ok then
        vim.notify(tostring(err), vim.log.levels.ERROR)
      end
    end
  end)
end

function M.setup()
  local cfg = require("focc.config").values
  vim.api.nvim_set_hl(0, "FoccDigitGroup", { underline = true, default = true })
  vim.diagnostic.config({ virtual_text = true, signs = true, underline = false }, lint_ns)
  local group = vim.api.nvim_create_augroup("FoccAids", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function(event)
      local buf = event.buf
      if not vim.tbl_contains({ "cpp", "python" }, vim.bo[buf].filetype) then
        return
      end
      pending[buf] = (pending[buf] or 0) + 1
      local token = pending[buf]
      vim.defer_fn(function()
        if pending[buf] == token and vim.api.nvim_buf_is_valid(buf) then
          M.lint(buf)
          M.numbers(buf)
        end
      end, cfg.lint_delay_ms)
      if vim.bo[buf].filetype == "cpp" and cfg.cpp_complete_enabled and vim.bo[buf].completefunc == "" then
        vim.bo[buf].completefunc = "v:lua.require'focc.aids'.complete"
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(event)
      pending[event.buf] = nil
      if jobs[event.buf] then
        jobs[event.buf]:cancel()
        jobs[event.buf] = nil
      end
    end,
  })
end

return M
