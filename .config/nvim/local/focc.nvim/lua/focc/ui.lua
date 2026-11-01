local M = { views = {} }
local ns = vim.api.nvim_create_namespace("focc-ui")

local function highlights()
  vim.api.nvim_set_hl(0, "FoccAccepted", { fg = "#98c379" })
end
highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("focc-ui-highlights", { clear = true }),
  callback = highlights,
})

local function visible(view)
  return view.win and vim.api.nvim_win_is_valid(view.win) and vim.api.nvim_win_get_buf(view.win) == view.buf
end

local function text(lines, title, value)
  lines[#lines + 1] = "  " .. title
  for _, line in ipairs(vim.split(value or "", "\n", { plain = true })) do
    lines[#lines + 1] = "    " .. line
  end
end

local function status(session, index)
  local result = session.results[index]
  if result then
    return result.reason or (result.code ~= 0 and "runtime error" or result.answer)
  end
  return session.status == "running" and session.current == index and "running" or "not run"
end

local function failure(label)
  return vim.tbl_contains({ "rejected", "runtime error", "timeout", "output limit" }, label)
end

function M.navigate(view, direction, failures_only)
  if not visible(view) then
    return
  end
  local selected = M.index(view) or (direction > 0 and 0 or (#view.headers + 1))
  for step = 1, #view.headers do
    local index = selected + direction * step
    local header = view.headers[index]
    if header and (not failures_only or failure(header.status)) then
      vim.api.nvim_win_set_cursor(view.win, { header.row, 0 })
      return
    end
  end
end

function M.show(session)
  local view = M.views[session.source]
  if not view or not vim.api.nvim_buf_is_valid(view.buf) then
    view = { buf = vim.api.nvim_create_buf(false, true), headers = {}, folded = {} }
    M.views[session.source] = view
    vim.api.nvim_buf_set_name(view.buf, "focc://results/" .. session.source)
    vim.bo[view.buf].filetype = "focc"
    vim.bo[view.buf].bufhidden = "hide"
    vim.bo[view.buf].swapfile = false
    vim.b[view.buf].focc_source = session.source
    local function bind(key, action)
      vim.keymap.set("n", key, function()
        require("focc").action(action, M.index(view))
      end, { buffer = view.buf, silent = true })
    end
    bind("r", "run")
    bind("R", "run_all")
    bind("a", "add")
    bind("e", "edit")
    bind("d", "delete")
    bind("y", "accept")
    bind("n", "reject")
    bind("J", "move_down")
    bind("K", "move_up")
    bind("x", "stop")
    bind("I", "interactive")
    bind("s", "send")
    bind("E", "eof")
    bind("S", "save_interactive")
    bind("D", "debug")
    for key, move in pairs({
      ["]t"] = { 1, false },
      ["[t"] = { -1, false },
      ["]f"] = { 1, true },
      ["[f"] = { -1, true },
    }) do
      vim.keymap.set("n", key, function()
        M.navigate(view, move[1], move[2])
      end, { buffer = view.buf, desc = "Navigate FOCC tests" })
    end
    vim.keymap.set("n", "?", function()
      view.help = not view.help
      M.render(view.session)
    end, { buffer = view.buf, desc = "Toggle FOCC help" })
    vim.keymap.set("n", "v", function()
      view.show_rejected = not view.show_rejected
      M.render(view.session)
    end, { buffer = view.buf, desc = "Toggle recorded rejected answers" })
    vim.keymap.set("n", "P", function()
      view.collapse_passed = not view.collapse_passed
      M.render(view.session)
    end, { buffer = view.buf, desc = "Toggle folding accepted tests" })
    vim.keymap.set("n", "<Tab>", function()
      local index = M.index(view)
      if index then
        local folded = view.folded[index]
        if folded == nil then
          folded = view.collapse_passed and status(view.session, index) == "accepted"
        end
        view.folded[index] = not folded
        M.render(view.session)
      end
    end, { buffer = view.buf })
    vim.keymap.set("n", "q", function()
      vim.cmd.close()
    end, { buffer = view.buf })
  end
  if not visible(view) then
    if require("focc.config").values.close_sidebar then
      local ok, command = pcall(require, "neo-tree.command")
      if ok then
        command.execute({ action = "close" })
      end
    end
    vim.cmd("botright vsplit")
    view.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(view.win, view.buf)
    vim.api.nvim_win_set_width(
      view.win,
      math.max(30, math.floor(vim.o.columns * require("focc.config").values.panel_width))
    )
    vim.wo[view.win].number = false
    vim.wo[view.win].relativenumber = false
    vim.wo[view.win].wrap = true
    vim.wo[view.win].signcolumn = "no"
    vim.wo[view.win].foldcolumn = "0"
  end
  M.render(session)
end

function M.index(view)
  if not visible(view) then
    return
  end
  local row = vim.api.nvim_win_get_cursor(view.win)[1]
  local selected
  for _, header in ipairs(view.headers) do
    if header.row <= row and row <= header.last_row then
      selected = header.index
    end
  end
  return selected
end

function M.render(session)
  local view = M.views[session.source]
  if not view or not vim.api.nvim_buf_is_valid(view.buf) then
    return
  end
  -- Save logical test/offset anchors before replacing the buffer. Earlier tests
  -- can grow while this test is selected, so absolute line numbers are unstable.
  local saved
  local function anchor(row)
    for _, header in ipairs(view.headers) do
      if row >= header.row and row <= header.last_row then
        return { index = header.index, offset = row - header.row }
      end
    end
    return { row = row }
  end
  if visible(view) then
    saved = vim.api.nvim_win_call(view.win, vim.fn.winsaveview)
    saved.cursor_anchor, saved.top_anchor = anchor(saved.lnum), anchor(saved.topline)
  end
  view.session = session
  local counts = {}
  for index in ipairs(session.store.tests) do
    local label = status(session, index)
    local category = failure(label) and label ~= "rejected" and "errors" or label
    counts[category] = (counts[category] or 0) + 1
  end
  local summary = {}
  for _, label in ipairs({ "accepted", "rejected", "errors", "unknown", "running", "cancelled", "not run" }) do
    if counts[label] then
      summary[#summary + 1] = counts[label] .. " " .. label
    end
  end
  local lines = {
    "FOCC · " .. vim.fs.basename(session.source) .. " · " .. session.status,
    #summary > 0 and table.concat(summary, " · ") or "No tests · a: add a test",
    "",
  }
  local badges = {}
  view.headers = {}
  if session.compile and (session.compile.code ~= 0 or session.compile.reason) then
    lines[#lines + 1] = "Compiler diagnostics"
    if session.compile.stdout and session.compile.stdout ~= "" then
      text(lines, "Stdout", session.compile.stdout)
    end
    if session.compile.stderr and session.compile.stderr ~= "" then
      text(lines, "Stderr", session.compile.stderr)
    end
    lines[#lines + 1] = ""
  end
  for index, test in ipairs(session.store.tests) do
    local result = session.results[index]
    local label = status(session, index)
    local folded = view.folded[index]
    if folded == nil then
      folded = view.collapse_passed and label == "accepted"
    end
    local prefix = string.format("%s Test %d  ", folded and "▸" or "▾", index)
    local badge = "[" .. label:upper() .. "]"
    local timing = result and string.format("  %.1f ms", result.time_ms) or ""
    if result and result.code ~= 0 then
      timing = timing .. string.format("  exit %d", result.code)
    end
    lines[#lines + 1] = prefix .. badge .. timing
    local header = { row = #lines, index = index, status = label }
    view.headers[#view.headers + 1] = header
    badges[#badges + 1] = { row = #lines, start_col = #prefix, end_col = #prefix + #badge, status = label }
    if not folded then
      text(lines, "Input", test.test)
      for i, answer in ipairs(test.correct_answers or {}) do
        text(lines, #(test.correct_answers or {}) == 1 and "Expected" or "Expected (alternative " .. i .. ")", answer)
      end
      if #(test.correct_answers or {}) == 0 then
        lines[#lines + 1] = "  Expected · not set"
      end
      if view.show_rejected then
        for i, answer in ipairs(test.uncorrect_answers or {}) do
          text(lines, "Recorded rejected answer " .. i, answer)
        end
      end
      if result then
        text(lines, "Actual", result.stdout)
        if result.stderr and result.stderr ~= "" then
          text(lines, "Stderr", result.stderr)
        end
      end
    end
    lines[#lines + 1] = ""
    header.last_row = #lines
  end
  if session.input ~= nil then
    lines[#lines + 1] = "Interactive | s:send E:EOF S:save captured input"
    text(lines, "Input", session.input)
    text(lines, "Actual", session.live and session.live.stdout)
    if session.live and session.live.stderr and session.live.stderr ~= "" then
      text(lines, "Stderr", session.live.stderr)
    end
  end
  lines[#lines + 1] = "r: run · R: all · Tab: fold · ?: help · q: hide"
  if view.help then
    vim.list_extend(lines, {
      "a: add · e: edit · d: delete · y/n: accept/reject output",
      "]t/[t: next/previous test · ]f/[f: next/previous failure",
      "J/K: reorder · P: fold accepted · v: recorded rejected answers",
      "D: debug selected test · x: stop",
      "I: interactive · s: send · E: EOF · S: save captured input",
    })
  end
  vim.bo[view.buf].modifiable = true
  vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
  vim.bo[view.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(view.buf, ns, 0, -1)
  for _, header in ipairs(badges) do
    local hl = header.status == "accepted" and "FoccAccepted"
      or (failure(header.status) and "DiagnosticError" or "DiagnosticInfo")
    vim.api.nvim_buf_set_extmark(
      view.buf,
      ns,
      header.row - 1,
      header.start_col,
      { end_col = header.end_col, hl_group = hl }
    )
  end
  if saved then
    local function resolve(value)
      local header = value.index and view.headers[value.index]
      return header and math.min(header.row + value.offset, header.last_row) or math.min(value.row or #lines, #lines)
    end
    saved.lnum, saved.topline = resolve(saved.cursor_anchor), resolve(saved.top_anchor)
    saved.cursor_anchor, saved.top_anchor = nil, nil
    saved.col = math.min(saved.col, #lines[saved.lnum])
    vim.api.nvim_win_call(view.win, function()
      vim.fn.winrestview(saved)
    end)
  end
end

function M.edit(source, data, index, done)
  local test = index and data.tests[index] or { test = "" }
  assert(test, "FOCC: test number does not exist")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "json"
  vim.b[buf].focc_source = source
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(vim.json.encode(test), "\n"))
  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_buf_set_name(buf, "focc://edit/" .. buf)
  local function save()
    local ok, err = pcall(function()
      local replacement = vim.json.decode(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
      require("focc.store").validate({ replacement })
      local updated = vim.deepcopy(data.tests)
      if index then
        updated[index] = replacement
      else
        updated[#updated + 1] = replacement
      end
      local candidate = { source = data.source, path = data.path, original = data.original, tests = updated }
      require("focc.store").save(candidate)
      data.tests, data.original = candidate.tests, candidate.original
      vim.api.nvim_buf_delete(buf, { force = true })
      done()
    end)
    if not ok then
      vim.notify(tostring(err), vim.log.levels.ERROR)
    end
  end
  vim.keymap.set({ "n", "i" }, "<C-s>", save, { buffer = buf, desc = "Save FOCC test" })
  vim.api.nvim_buf_create_user_command(buf, "FoccSave", save, {})
  vim.notify("Edit test JSON. Use Ctrl-S or :FoccSave to save. :q! cancels.")
end

return M
