local M = { forms = {} }
local ns = vim.api.nvim_create_namespace("focc-editor")
local store = require("focc.store")

local function position(form, field)
  local mark = vim.api.nvim_buf_get_extmark_by_id(form.buf, ns, field.mark, { details = true })
  assert(#mark > 0 and not mark[3].invalid, "FOCC: a field heading was deleted. Undo that change before saving.")
  local row = mark[1]
  assert(
    vim.api.nvim_buf_get_lines(form.buf, row, row + 1, false)[1] == field.heading,
    "FOCC: keep field headings unchanged. Use :FoccAnswerAdd or :FoccAnswerDelete to change answer fields."
  )
  return row
end

local function read(form)
  local rows = {}
  for i, field in ipairs(form.fields) do
    rows[i] = position(form, field)
    assert(
      (i == 1 and rows[i] == 0) or (i > 1 and rows[i] > rows[i - 1]),
      "FOCC: field headings moved. Undo that change before saving."
    )
  end
  for i, field in ipairs(form.fields) do
    field.value = table.concat(
      vim.api.nvim_buf_get_lines(form.buf, rows[i] + 1, rows[i + 1] or vim.api.nvim_buf_line_count(form.buf), false),
      "\n"
    )
  end
end

local function render(form, selected)
  local lines, counts = {}, { correct_answers = 0, uncorrect_answers = 0 }
  for _, field in ipairs(form.fields) do
    if field.key == "test" then
      field.heading = "── Input ──"
    else
      counts[field.key] = counts[field.key] + 1
      local name = field.key == "correct_answers" and "Correct answer" or "Incorrect answer"
      field.heading =
        string.format("── %s %d%s ──", name, counts[field.key], field.keep_empty and "" or " (optional)")
    end
    field.row = #lines
    lines[#lines + 1] = field.heading
    vim.list_extend(lines, vim.split(field.value, "\n", { plain = true }))
  end
  vim.api.nvim_buf_set_lines(form.buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(form.buf, ns, 0, -1)
  for i, field in ipairs(form.fields) do
    field.mark = vim.api.nvim_buf_set_extmark(form.buf, ns, field.row, 0, {
      end_row = field.row + 1,
      end_col = 0,
      hl_group = "Title",
      hl_eol = true,
      right_gravity = true,
      end_right_gravity = false,
      invalidate = true,
      undo_restore = true,
      virt_lines = i == 1 and {
        { { "FOCC · " .. (form.index and "Edit test " .. form.index or "Add test"), "Title" } },
        { { "Ctrl-S / :FoccSave save · :q! cancel · Tab / Shift-Tab navigate", "Comment" } },
        { { ":FoccAnswerAdd correct|incorrect · :FoccAnswerDelete", "Comment" } },
      } or nil,
      virt_lines_above = true,
    })
  end
  if selected then
    vim.api.nvim_win_set_cursor(0, { selected.row + 2, 0 })
  end
end

local function replacement(form)
  read(form)
  local result = vim.deepcopy(form.original)
  local answers = { correct_answers = {}, uncorrect_answers = {} }
  for _, field in ipairs(form.fields) do
    if field.key == "test" then
      result.test = field.value
    elseif field.keep_empty or field.value ~= "" then
      -- Existing strings round-trip unchanged. New or edited answers use the
      -- same outer-whitespace normalization as captured program output.
      local value = field.value == field.original_value and field.value or vim.trim(field.value)
      table.insert(answers[field.key], value)
    end
  end
  for key, values in pairs(answers) do
    if form.original[key] ~= nil or #values > 0 then
      result[key] = values
    else
      result[key] = nil
    end
  end
  return result
end

local function current(form)
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  for i = #form.fields, 1, -1 do
    if row >= position(form, form.fields[i]) then
      return i
    end
  end
  return 1
end

local function focus(form, i)
  local row = position(form, form.fields[i])
  local last = form.fields[i + 1] and position(form, form.fields[i + 1]) or vim.api.nvim_buf_line_count(form.buf)
  if last == row + 1 then
    vim.api.nvim_buf_set_lines(form.buf, row + 1, row + 1, false, { "" })
  end
  vim.api.nvim_win_set_cursor(0, { row + 2, 0 })
end

local function protected(callback)
  return function(...)
    local ok, err = pcall(callback, ...)
    if not ok then
      vim.notify(tostring(err), vim.log.levels.ERROR)
    end
  end
end

function M.open(source, data, index, done)
  local original = { test = "" }
  if index then
    original = data.tests[index]
  end
  assert(original, "FOCC: test number does not exist")
  local buf = vim.api.nvim_create_buf(false, true)
  local form = {
    buf = buf,
    index = index,
    original = vim.deepcopy(original),
    fields = {
      { key = "test", value = original.test, keep_empty = true },
    },
  }
  M.forms[buf] = form
  for _, key in ipairs({ "correct_answers", "uncorrect_answers" }) do
    for _, value in ipairs(original[key] or {}) do
      form.fields[#form.fields + 1] = { key = key, value = value, original_value = value, keep_empty = true }
    end
    if #(original[key] or {}) == 0 then
      form.fields[#form.fields + 1] = { key = key, value = "", keep_empty = false }
    end
  end
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "focc-edit"
  vim.bo[buf].swapfile = false
  vim.b[buf].focc_source = source
  vim.api.nvim_buf_set_name(buf, "focc://edit/" .. buf)
  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.wo.number, vim.wo.relativenumber, vim.wo.signcolumn = false, false, "no"
  vim.wo.wrap = false
  render(form, form.fields[1])
  vim.bo[buf].modified = false
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      M.forms[buf] = nil
    end,
  })
  local function save()
    local value = replacement(form)
    store.validate({ value })
    local updated = vim.deepcopy(data.tests)
    if index then
      updated[index] = value
    else
      updated[#updated + 1] = value
    end
    local candidate = { source = data.source, path = data.path, original = data.original, tests = updated }
    store.save(candidate)
    data.tests, data.original = candidate.tests, candidate.original
    vim.api.nvim_buf_delete(buf, { force = true })
    done()
  end
  vim.keymap.set({ "n", "i" }, "<C-s>", protected(save), { buffer = buf, desc = "Save FOCC test" })
  vim.api.nvim_buf_create_user_command(buf, "FoccSave", protected(save), {})
  for key, direction in pairs({ ["<Tab>"] = 1, ["<S-Tab>"] = -1 }) do
    vim.keymap.set(
      "n",
      key,
      protected(function()
        local i = ((current(form) - 1 + direction) % #form.fields) + 1
        focus(form, i)
      end),
      { buffer = buf, desc = "Navigate FOCC fields" }
    )
  end
  vim.api.nvim_buf_create_user_command(
    buf,
    "FoccAnswerAdd",
    protected(function(command)
      local key = ({ correct = "correct_answers", incorrect = "uncorrect_answers" })[command.args]
      assert(key, "FOCC: use :FoccAnswerAdd correct or :FoccAnswerAdd incorrect")
      read(form)
      local selected
      for i, field in ipairs(form.fields) do
        if field.key == key then
          selected = i
          if not field.keep_empty and field.value == "" then
            field.keep_empty = true
            render(form, field)
            return
          end
        end
      end
      local field = { key = key, value = "", keep_empty = true }
      table.insert(form.fields, selected + 1, field)
      render(form, field)
    end),
    {
      nargs = 1,
      complete = function()
        return { "correct", "incorrect" }
      end,
    }
  )
  vim.api.nvim_buf_create_user_command(
    buf,
    "FoccAnswerDelete",
    protected(function()
      read(form)
      local i = current(form)
      local field = form.fields[i]
      assert(field.key ~= "test", "FOCC: the Input field cannot be deleted")
      table.remove(form.fields, i)
      local count = 0
      for _, other in ipairs(form.fields) do
        if other.key == field.key then
          count = count + 1
        end
      end
      if count == 0 then
        table.insert(form.fields, i, { key = field.key, value = "", keep_empty = false })
      end
      render(form, form.fields[math.min(i, #form.fields)])
    end),
    {}
  )
  vim.notify("Enter multiline text below each heading. Ctrl-S or :FoccSave saves. :q! cancels.")
  return buf
end

return M
