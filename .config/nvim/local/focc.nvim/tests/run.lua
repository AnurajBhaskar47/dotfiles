-- Run from this plugin directory: nvim --headless -u NONE -l tests/run.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
local config = require("focc.config")
local store = require("focc.store")
local process = require("focc.process")
local runner = require("focc.runner")
local aids = require("focc.aids")
local root = "/tmp/opencode/focc-tests-" .. vim.uv.os_getpid() .. "-" .. vim.uv.hrtime()
vim.fn.mkdir(root, "p")
local passed = 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if not ok then
    io.stderr:write("FAIL " .. name .. "\n" .. tostring(err) .. "\n")
    vim.cmd("cquit 1")
  end
  passed = passed + 1
  print("PASS " .. name)
end
local function write(path, value)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local file = assert(io.open(path, "wb"))
  file:write(value)
  file:close()
end
local function rejected(fn)
  assert(not pcall(fn), "expected failure")
end
local function wait(fn)
  assert(vim.wait(45000, fn, 10), "async task did not finish")
end
local function invoke(cmd, opts)
  local result
  local task = process.start(cmd, opts, function(value)
    result = value
  end)
  wait(function()
    return result ~= nil
  end)
  return result, task
end
local function form_row(buf, index)
  local form = require("focc.editor").forms[buf]
  local ns = vim.api.nvim_get_namespaces()["focc-editor"]
  return vim.api.nvim_buf_get_extmark_by_id(buf, ns, form.fields[index].mark, {})[1]
end
local function form_set(buf, index, lines)
  local form = require("focc.editor").forms[buf]
  local last = form.fields[index + 1] and form_row(buf, index + 1) or vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, form_row(buf, index) + 1, last, false, lines)
end

config.setup({ tests_relative_dir = ".focc" })
test("configuration validation", function()
  rejected(function()
    config.setup({ misspelled_option = true })
  end)
  rejected(function()
    config.setup({ run_settings = { { name = "X", extensions = { "x" }, run_cmd = "echo hello" } } })
  end)
  rejected(function()
    config.setup({ run_settings = { { name = "X", extensions = { "x" }, run_cmd = { "{bad}" } } } })
  end)
  rejected(function()
    config.setup({ output_limit = -1 })
  end)
end)

local source = vim.fs.joinpath(root, "spaces here", "task.cpp")
test("path includes full source filename", function()
  assert(store.path(source) == vim.fs.joinpath(root, "spaces here", ".focc", "task.cpp:tests"))
end)
test("missing file and atomic JSON round trip", function()
  local data = store.load(source)
  data.tests = {
    {
      test = "1\n",
      correct_answers = { "2" },
      uncorrect_answers = {},
      extra = { null = vim.NIL, dict = vim.empty_dict(), array = {} },
    },
  }
  store.save(data)
  local loaded = store.load(source)
  assert(loaded.tests[1].extra.null == vim.NIL)
  assert(store.read(data.path):find('"uncorrect_answers":%[%]'))
  assert(store.read(data.path):find('"dict":{}'))
  loaded.tests = {}
  store.save(loaded)
  assert(store.read(data.path):match("^%["))
  assert(#store.load(source).tests == 0)
end)
test("external changes prevent save", function()
  local data = store.load(source)
  write(data.path, '[{"test":"external"}]')
  rejected(function()
    store.save(data)
  end)
  assert(store.load(source).tests[1].test == "external")
end)
test("malformed tests are not overwritten", function()
  write(store.path(source), "{broken")
  rejected(function()
    store.load(source)
  end)
  assert(store.read(store.path(source)) == "{broken")
  write(store.path(source), '[{"test":4}]')
  rejected(function()
    store.load(source)
  end)
end)
test("all existing CP fixtures round trip in copies", function()
  local paths = vim.fn.glob("/home/aj47/Projects/Protocol99/CP/*/.focc/*:tests", false, true)
  assert(#paths == 8, "expected eight existing fixtures")
  for index, path in ipairs(paths) do
    local raw = store.read(path)
    local copy = vim.fs.joinpath(root, "fixture" .. index, (vim.fs.basename(path):gsub(":tests$", "")))
    write(store.path(copy), raw)
    local data = store.load(copy)
    local original = vim.deepcopy(data.tests)
    store.save(data)
    assert(vim.deep_equal(store.load(copy).tests, original), path)
    assert(store.read(path) == raw, "original fixture changed")
  end
end)
test("answer verdicts and explicit mark transitions", function()
  local data = { test = "x", correct_answers = { "a" }, uncorrect_answers = { "b", "a" } }
  assert(store.answer(data, " a\n") == "accepted")
  assert(store.answer(data, "b") == "rejected")
  local original = vim.deepcopy(data)
  assert(store.answer(data, "other") == "rejected")
  assert(vim.deep_equal(data, original), "judging must not record mismatched output")
  assert(store.answer({ test = "x", correct_answers = { "a", "other" } }, "other\n") == "accepted")
  assert(store.answer({ test = "x" }, "other") == "unknown")
  assert(store.answer({ test = "x", correct_answers = {}, uncorrect_answers = { "b" } }, "other") == "unknown")
  assert(store.answer({ test = "x", uncorrect_answers = { "b" } }, "b") == "rejected")
  assert(store.answer({ test = "x", correct_answers = { "" } }, "\n") == "accepted")
  assert(store.answer({ test = "x", correct_answers = { "" } }, "other") == "rejected")
  store.mark(data, "b\n", true)
  assert(store.answer(data, "b") == "accepted")
  store.mark(data, "b", false)
  assert(store.answer(data, "b") == "rejected")
end)
test("argument templates preserve spaces and expand args", function()
  local cmd = process.command({ "clang++", "{source_file}", "-o", "{file_name}", "{args}" }, source, { "a b", "c" })
  assert(cmd[2] == source and cmd[4] == "task" and cmd[5] == "a b")
end)
test("completion definitions", function()
  assert(aids.expand("vi") == "vector<int>")
  assert(aids.expand("vpii") == "vector<pii>")
  assert(aids.expand("mSivl") == "map<set<int>, vector<ll>>")
  assert(not aids.expand("invalid"))
end)
test("Blink shorthand provider", function()
  vim.bo.filetype = "cpp"
  local result
  require("focc.blink").new():get_completions({ line = "vi", cursor = { 1, 2 } }, function(value)
    result = value
  end)
  assert(result.items[1].insertText == "vector<int>")
  assert(result.items[1].textEdit.range.start.character == 0)
  vim.bo.filetype = ""
end)
test("diagnostic parsing", function()
  local items = aids.parse_diagnostics(source .. ":3:4: error: bad type\n" .. source .. ":5:2: warning: unused", source)
  assert(#items == 2 and items[1].lnum == 2 and items[1].col == 3)
  assert(items[2].severity == vim.diagnostic.severity.WARN)
end)
test("process stdin stdout and stderr", function()
  local result = invoke(
    { "python", "-c", "import sys; print(sys.stdin.read().upper()); print('err',file=sys.stderr)" },
    { input = "hello" }
  )
  assert(result.code == 0 and result.stdout == "HELLO\n" and result.stderr == "err\n")
end)
test("timeout", function()
  local result = invoke({ "python", "-c", "import time; time.sleep(10)" }, { timeout_ms = 80 })
  assert(result.reason == "timeout")
end)
test("cancellation", function()
  local result
  local task = process.start({ "python", "-c", "import time; time.sleep(10)" }, {}, function(value)
    result = value
  end)
  vim.defer_fn(function()
    task:cancel()
  end, 80)
  wait(function()
    return result ~= nil
  end)
  assert(result.reason == "cancelled")
end)
test("output limit", function()
  config.setup({ tests_relative_dir = ".focc", output_limit = 128 })
  local result = invoke(
    { "python", "-c", "import sys,time; sys.stdout.write('x'*10000); sys.stdout.flush(); time.sleep(1)" },
    {}
  )
  assert(result.reason == "output limit" and #result.stdout <= 128)
  config.setup({ tests_relative_dir = ".focc" })
end)
test("interactive input and EOF", function()
  local result
  local task = process.start(
    { "python", "-c", "import sys; print(sys.stdin.read())" },
    { interactive = true },
    function(value)
      result = value
    end
  )
  task:send("hello\n")
  task:eof()
  wait(function()
    return result ~= nil
  end)
  assert(result.code == 0 and result.stdout == "hello\n\n")
end)

local function language_test(ext, code)
  local path = vim.fs.joinpath(root, "language " .. ext, ext == "java" and "Main.java" or ("main." .. ext))
  write(path, code)
  local data = store.load(path)
  data.tests = { { test = "4\n", correct_answers = { "8" } }, { test = "7\n", correct_answers = { "14" } } }
  store.save(data)
  local session = runner.run(path)
  wait(function()
    return session.status == "finished" or session.status == "compile error"
  end)
  assert(session.status == "finished", session.compile and session.compile.stderr)
  assert(session.results[1].answer == "accepted" and session.results[2].answer == "accepted")
end
test("C++ compile and run with spaces", function()
  language_test("cpp", "#include <iostream>\nint main(){int x; std::cin>>x; std::cout<<x*2;}\n")
end)
test("Python run", function()
  language_test("py", "print(int(input())*2)\n")
end)
test("user clang++ C++26 configuration", function()
  local spec = dofile("../../lua/plugins/focc.lua")
  config.setup(spec[1].opts)
  language_test("cpp", "#include <iostream>\nint main(){int x; std::cin>>x; std::cout<<x*2;}\n")
  config.setup({ tests_relative_dir = ".focc" })
end)
test("compile failure does not execute tests", function()
  local path = vim.fs.joinpath(root, "compile-error", "main.cpp")
  write(path, "this is not valid C++;\n")
  local data = store.load(path)
  data.tests = { { test = "1" } }
  store.save(data)
  local session = runner.run(path)
  wait(function()
    return session.status == "compile error"
  end)
  assert(next(session.results) == nil and session.compile.code ~= 0)
end)
test("Java compile and run", function()
  if vim.fn.executable("javac") == 1 then
    language_test(
      "java",
      "import java.util.*; public class Main { public static void main(String[] a){System.out.println(new Scanner(System.in).nextInt()*2);} }"
    )
  else
    print("SKIP Java: javac is missing")
  end
end)
test("stress detects different output", function()
  local path = vim.fs.joinpath(root, "stress", "main.py")
  write(path, 'print("bad")\n')
  write(path:gsub("main.py$", "main__Good.py"), 'print("good")\n')
  write(path:gsub("main.py$", "main__Generator.py"), 'print("1")\n')
  local session = require("focc.stress").start(path)
  wait(function()
    return session.failure ~= nil
  end)
  assert(session.failure.correct_answers[1] == "good")
end)
test("UI and editing command registration", function()
  require("focc").setup({ tests_relative_dir = ".focc" })
  assert(vim.fn.exists(":Focc") == 2)
  local path = vim.fs.joinpath(root, "ui", "main.py")
  write(path, 'print("ok")')
  local data = store.load(path)
  local session = { source = path, store = data, results = {}, status = "ready" }
  require("focc.ui").show(session)
  assert(vim.bo.filetype == "focc")
  require("focc.ui").edit(path, data, nil, function() end)
  assert(vim.bo.filetype == "focc-edit" and vim.fn.exists(":FoccSave") == 2)
  local buf = vim.api.nvim_get_current_buf()
  form_set(buf, 1, { "3", "" })
  form_set(buf, 2, { "6" })
  vim.cmd("FoccSave")
  local loaded = store.load(path)
  assert(loaded.tests[1].test == "3\n" and loaded.tests[1].correct_answers[1] == "6")
end)
test("multiline form preserves exact strings, alternatives, and unknown metadata", function()
  local path = root .. "/form/roundtrip.cpp"
  local data = store.load(path)
  local values = { "  1 2\n3\n\n", "answer\n", "", "── Input ──\n\\n\t雪", "bad\noutput\n" }
  data.tests = {
    {
      test = values[1],
      correct_answers = { values[2], values[3], values[4] },
      uncorrect_answers = { values[5] },
      extra = { null = vim.NIL, note = "preserve" },
    },
  }
  store.save(data)
  local ui = require("focc.ui")
  local original = vim.deepcopy(data.tests[1])
  local completed = 0
  local buf = ui.edit(path, data, 1, function()
    completed = completed + 1
  end)
  assert(vim.api.nvim_buf_get_name(buf):match("^focc://edit/"))
  local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  assert(content:find(values[1], 1, true) and content:find(values[4], 1, true))
  vim.cmd("FoccSave")
  assert(completed == 1 and vim.deep_equal(store.load(path).tests[1], original))
  assert(require("focc.editor").forms[buf] == nil)
  buf = ui.edit(path, data, 1, function()
    completed = completed + 1
  end)
  form_set(buf, 1, { "new input", "second line", "" })
  form_set(buf, 2, { "first output", "second output", "" })
  form_set(buf, 5, { "different wrong output" })
  vim.cmd("FoccSave")
  local updated = store.load(path).tests[1]
  assert(updated.test == "new input\nsecond line\n")
  assert(updated.correct_answers[1] == "first output\nsecond output")
  assert(updated.correct_answers[2] == "" and updated.correct_answers[3] == values[4])
  assert(updated.uncorrect_answers[1] == "different wrong output")
  assert(vim.deep_equal(updated.extra, original.extra))
  assert(store.answer(updated, "first output\nsecond output\n") == "accepted")
end)
test("form answer controls and save shortcuts", function()
  local ui = require("focc.ui")
  local path = root .. "/form/controls.cpp"
  local data = store.load(path)
  local buf = ui.edit(path, data, nil, function() end)
  assert(vim.fn.exists(":FoccAnswerAdd") == 2 and vim.fn.exists(":FoccAnswerDelete") == 2)
  local function key(lhs)
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if mapping.lhs == lhs then
        mapping.callback()
        return
      end
    end
    error("missing form key: " .. lhs)
  end
  key("<Tab>")
  assert(vim.api.nvim_win_get_cursor(0)[1] == form_row(buf, 2) + 2)
  key("<S-Tab>")
  assert(vim.api.nvim_win_get_cursor(0)[1] == form_row(buf, 1) + 2)
  form_set(buf, 3, {})
  key("<S-Tab>")
  assert(
    vim.api.nvim_win_get_cursor(0)[1] == form_row(buf, 3) + 2,
    "Navigation must restore an editable line in an empty field"
  )
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, "i")) do
    assert(mapping.lhs ~= "<Tab>", "Insert-mode Tab must remain literal")
  end
  vim.cmd("FoccAnswerAdd correct")
  assert(#require("focc.editor").forms[buf].fields == 3)
  -- This explicitly adds an empty correct answer. A untouched placeholder does not.
  vim.cmd("FoccAnswerAdd correct")
  assert(#require("focc.editor").forms[buf].fields == 4)
  form_set(buf, 3, { "alternative", "two lines" })
  vim.cmd("FoccAnswerAdd incorrect")
  form_set(buf, 4, { "wrong", "output" })
  local mappings = vim.api.nvim_buf_get_keymap(buf, "n")
  for _, mapping in ipairs(mappings) do
    if mapping.lhs == "<C-S>" or mapping.lhs == "<C-s>" then
      mapping.callback()
      break
    end
  end
  assert(not vim.api.nvim_buf_is_valid(buf), "Ctrl-S must save and close the form")
  local test = store.load(path).tests[1]
  assert(test.test == "" and vim.deep_equal(test.correct_answers, { "", "alternative\ntwo lines" }))
  assert(vim.deep_equal(test.uncorrect_answers, { "wrong\noutput" }))
  buf = ui.edit(path, data, 1, function() end)
  vim.api.nvim_win_set_cursor(0, { form_row(buf, 2) + 2, 0 })
  vim.cmd("FoccAnswerDelete")
  vim.api.nvim_win_set_cursor(0, { form_row(buf, 2) + 2, 0 })
  vim.cmd("FoccAnswerDelete")
  vim.cmd("FoccSave")
  assert(#store.load(path).tests[1].correct_answers == 0)
  local fresh = store.load(root .. "/form/blank.cpp")
  ui.edit(fresh.source, fresh, nil, function() end)
  vim.cmd("FoccSave")
  assert(
    store.load(fresh.source).tests[1].correct_answers == nil,
    "Blank optional fields must not create accepted answers"
  )
end)
test("form cancellation, external changes, and damaged headings prevent data loss", function()
  local ui = require("focc.ui")
  local path = root .. "/form/safety.cpp"
  local data = store.load(path)
  data.tests = { { test = "original", correct_answers = { "answer" } } }
  store.save(data)
  rejected(function()
    ui.edit(path, data, 99, function() end)
  end)
  local original = store.read(data.path)
  local buf = ui.edit(path, data, 1, function()
    error("Must not save")
  end)
  form_set(buf, 1, { "cancelled edit" })
  vim.cmd("q!")
  assert(store.read(data.path) == original and require("focc.editor").forms[buf] == nil)
  buf = ui.edit(path, data, 1, function()
    error("Must not save")
  end)
  local row = form_row(buf, 2)
  vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { "damaged heading" })
  pcall(vim.cmd, "FoccSave")
  assert(vim.api.nvim_buf_is_valid(buf) and store.read(data.path) == original)
  vim.api.nvim_buf_delete(buf, { force = true })
  buf = ui.edit(path, data, 1, function()
    error("Must not save")
  end)
  row = form_row(buf, 2)
  vim.api.nvim_buf_set_lines(buf, row, row + 1, false, {})
  pcall(vim.cmd, "FoccSave")
  assert(vim.api.nvim_buf_is_valid(buf) and store.read(data.path) == original)
  vim.api.nvim_buf_delete(buf, { force = true })
  buf = ui.edit(path, data, 1, function()
    error("Must not save")
  end)
  write(data.path, '[{"test":"external"}]')
  form_set(buf, 1, { "local" })
  pcall(vim.cmd, "FoccSave")
  assert(vim.api.nvim_buf_is_valid(buf) and store.load(path).tests[1].test == "external")
  vim.api.nvim_buf_delete(buf, { force = true })
end)
test("results panel summary, navigation, folding, and viewport anchors", function()
  local ui = require("focc.ui")
  local path = vim.fs.joinpath(root, "ui", "summary.py")
  local data = {
    tests = {
      { test = "1", correct_answers = { "2" }, uncorrect_answers = { "secret rejected output" } },
      { test = "2", correct_answers = { "4" } },
      { test = "3" },
      { test = "4", correct_answers = { "8" } },
      { test = "5" },
    },
  }
  local session = {
    source = path,
    store = data,
    status = "finished",
    results = {
      { stdout = "2", stderr = "", code = 0, time_ms = 1, answer = "accepted" },
      { stdout = "5", stderr = "", code = 0, time_ms = 2, answer = "rejected" },
      { stdout = "?", stderr = "", code = 0, time_ms = 3, answer = "unknown" },
      { stdout = "", stderr = "exception", code = 1, time_ms = 4, answer = "rejected" },
    },
  }
  ui.show(session)
  local view = ui.views[path]
  local function content()
    return table.concat(vim.api.nvim_buf_get_lines(view.buf, 0, -1, false), "\n")
  end
  local output = content()
  assert(output:find("1 accepted · 1 rejected · 1 errors · 1 unknown · 1 not run", 1, true))
  assert(output:find("[REJECTED]", 1, true) and output:find("  Expected\n    4\n  Actual\n    5", 1, true))
  assert(not output:find("secret rejected output", 1, true))
  local _, stderr_count = output:gsub("  Stderr", "")
  assert(stderr_count == 1, "empty stderr sections must be hidden")
  assert(view.headers[4].status == "runtime error")
  local marks =
    vim.api.nvim_buf_get_extmarks(view.buf, vim.api.nvim_get_namespaces()["focc-ui"], 0, -1, { details = true })
  assert(#marks == 5 and not marks[1][4].line_hl_group and marks[1][4].hl_group == "FoccAccepted")
  assert(vim.api.nvim_get_hl(0, { name = "FoccAccepted" }).fg == 0x98c379)
  vim.api.nvim_set_hl(0, "FoccAccepted", { fg = "#ffffff" })
  vim.api.nvim_exec_autocmds("ColorScheme", {})
  assert(vim.api.nvim_get_hl(0, { name = "FoccAccepted" }).fg == 0x98c379)
  vim.api.nvim_win_set_cursor(view.win, { view.headers[1].row, 0 })
  ui.navigate(view, 1, true)
  assert(ui.index(view) == 2)
  ui.navigate(view, 1, true)
  assert(ui.index(view) == 4)
  ui.navigate(view, -1, false)
  assert(ui.index(view) == 3)
  local function key(lhs)
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(view.buf, "n")) do
      if mapping.lhs == lhs then
        mapping.callback()
        return
      end
    end
    error("missing UI key: " .. lhs)
  end
  key("?")
  assert(content():find("D: debug selected test", 1, true))
  key("v")
  assert(content():find("secret rejected output", 1, true))
  key("P")
  assert(view.headers[1].last_row - view.headers[1].row == 1)
  vim.api.nvim_win_set_cursor(view.win, { view.headers[1].row, 0 })
  key("<Tab>")
  assert(view.headers[1].last_row - view.headers[1].row > 1, "Tab must override automatic passing folds")
  -- Anchor both cursor and viewport inside test 2, then expand test 1.
  vim.api.nvim_win_set_cursor(view.win, { view.headers[2].row + 2, 1 })
  vim.api.nvim_win_call(view.win, function()
    vim.fn.winrestview({ topline = view.headers[2].row })
  end)
  local before = vim.api.nvim_win_call(view.win, vim.fn.winsaveview)
  local old_header = view.headers[2].row
  data.tests[1].test = string.rep("long input\n", 20)
  ui.render(session)
  local after = vim.api.nvim_win_call(view.win, vim.fn.winsaveview)
  assert(after.lnum - view.headers[2].row == before.lnum - old_header)
  assert(after.topline - view.headers[2].row == before.topline - old_header)
  assert(after.col == before.col and ui.index(view) == 2)
  vim.api.nvim_win_set_cursor(view.win, { vim.api.nvim_buf_line_count(view.buf), 0 })
  assert(ui.index(view) == nil, "help/footer must not select the last test")
  ui.navigate(view, -1, false)
  assert(ui.index(view) == 5)
  -- An editor can reuse the panel's window. Background updates must not move it.
  local other = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(other, 0, -1, false, { "one", "two", "three" })
  vim.api.nvim_win_set_buf(view.win, other)
  vim.api.nvim_win_set_cursor(view.win, { 2, 1 })
  ui.render(session)
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(view.win), { 2, 1 }))
  assert(ui.index(view) == nil)
  ui.navigate(view, 1, false)
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(view.win), { 2, 1 }))
  ui.show(session)
  assert(vim.api.nvim_win_get_buf(view.win) == view.buf)
end)
test("runner rejects wrong answers without changing stored tests", function()
  local path = vim.fs.joinpath(root, "wrong-answer", "main.py")
  write(path, 'print("wrong")\n')
  local data = store.load(path)
  data.tests = { { test = "", correct_answers = { "right" }, uncorrect_answers = {} } }
  store.save(data)
  local original = store.read(data.path)
  local session = runner.run(path)
  wait(function()
    return session.status == "finished"
  end)
  assert(session.results[1].answer == "rejected")
  assert(store.read(data.path) == original)
end)
test("snippet insertion and cursor properties", function()
  local path = vim.fs.joinpath(root, "snippets", "example.cpp")
  write(path, "abc\ndef")
  write(path .. ":properties", '{"move_cursor":4}')
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  aids.snippet(path)
  assert(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[2] == "def")
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 0 }))
end)
test("live compiler lint on unsaved buffer", function()
  config.setup({ tests_relative_dir = ".focc", lint_enabled = true })
  local buf = vim.api.nvim_create_buf(false, true)
  local path = vim.fs.joinpath(root, "lint", "main.cpp")
  write(path, "int main() { return 0; }")
  vim.api.nvim_buf_set_name(buf, path)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "int main() { BAD_TOKEN; }" })
  aids.lint(buf)
  local ns = vim.api.nvim_get_namespaces()["focc-lint"]
  wait(function()
    return #vim.diagnostic.get(buf, { namespace = ns }) > 0
  end)
  assert(store.read(path) == "int main() { return 0; }")
  config.setup({ tests_relative_dir = ".focc" })
end)
test("debug launch modes build separate executables and preserve tests", function()
  local spec = dofile("../../lua/plugins/focc.lua")
  config.setup(spec[1].opts)
  local previous = package.loaded.dap
  local launched
  local dap = {
    adapters = { codelldb = {} },
    listeners = {
      before = { event_stopped = {} },
      after = {
        event_terminated = {},
        event_exited = {},
        event_initialized = {},
        event_stopped = {},
        stackTrace = {},
        event_continued = {},
      },
    },
    defaults = { codelldb = { auto_continue_if_many_stopped = true } },
    repl = { append = function() end },
    session = function()
      return nil
    end,
    run = function(value)
      launched = value
    end,
  }
  package.loaded.dap = dap
  local path = vim.fs.joinpath(root, "debug space", "main.cpp")
  write(path, "#include <iostream>\nint main(){int x; std::cin>>x; std::cout<<x*2;}\n")
  local data = store.load(path)
  data.tests = { { test = "12\n", correct_answers = { "24" } } }
  store.save(data)
  local original = store.read(data.path)
  local debugger = require("focc.debug")
  local function launch(mode, index)
    launched = nil
    debugger.start(path, index, mode)
    wait(function()
      return launched ~= nil
    end)
    assert(launched.program == vim.fs.joinpath(vim.fs.dirname(path), "main-debug"))
    assert(launched.stopOnEntry and launched.type == "codelldb")
    return launched
  end
  local value = launch("debug", 1)
  local input = value.stdio[1]
  dap.listeners.after.event_initialized["focc-" .. path]({ on_close = {} })
  assert(dap.defaults.codelldb.auto_continue_if_many_stopped == false)
  assert(store.read(input) == "12\n" and value.stdio[2] == vim.NIL)
  local result = invoke({ value.program }, { input = store.read(input) })
  assert(result.stdout == "24")
  dap.listeners.after.event_exited["focc-" .. path]()
  assert(dap.defaults.codelldb.auto_continue_if_many_stopped == true)
  assert(dap.listeners.before.event_stopped["focc-" .. path] == nil)
  assert(not vim.uv.fs_stat(input))
  write(vim.fs.joinpath(vim.fs.dirname(path), "input.txt"), "9\n")
  value = launch("debug_input_file")
  assert(store.read(value.stdio[1]) == "9\n")
  dap.listeners.after.event_terminated["focc-" .. path]()
  assert(store.read(value.stdio[1]) == "9\n")
  value = launch("debug_no_input")
  assert(value.stdio == nil and value.terminal == "integrated")
  dap.listeners.after.event_terminated["focc-" .. path]()
  rejected(function()
    debugger.start(path, 2)
  end)
  assert(store.read(data.path) == original)
  package.loaded.dap = previous
  config.setup({ tests_relative_dir = ".focc" })
end)
test("crash listeners preserve stops and select source frames", function()
  local previous_ui = package.loaded.dapui
  local opened, message, selected = 0, "", nil
  package.loaded.dapui = {
    open = function()
      opened = opened + 1
    end,
  }
  local dap = {
    listeners = {
      before = { event_stopped = {} },
      after = { event_stopped = {}, stackTrace = {}, event_continued = {} },
    },
    repl = {
      append = function(text)
        message = message .. text
      end,
    },
  }
  local source = root .. "/crash-listeners/main.cpp"
  local session = {
    _frame_set = function(_, frame)
      selected = frame
    end,
  }
  local crash = require("focc.crash")
  local cleanup = crash.attach(dap, source, "test-crash")
  local function stopped(reason, description)
    dap.listeners.before.event_stopped["test-crash"](
      session,
      { reason = reason, description = description, threadId = 1 }
    )
    dap.listeners.after.event_stopped["test-crash"](session)
  end
  stopped("breakpoint", nil)
  assert(opened == 0 and crash.stops[source] == nil)
  stopped("exception", "signal SIGSTOP")
  assert(opened == 0 and crash.stops[source] == nil)
  stopped("exception", "signal SIGABRT")
  dap.listeners.after.event_stopped["test-crash"](session)
  assert(opened == 1 and crash.stops[source].signal == "SIGABRT")
  assert(message:find("Execution remains stopped", 1, true))
  local frames = {
    { id = 10, line = 1, name = "abort", source = { path = "/lib/abort.c" } },
    { id = 11, line = 8, name = "crash", source = { path = source } },
  }
  dap.listeners.after.stackTrace["test-crash"](session, nil, { stackFrames = frames }, { threadId = 1 })
  assert(selected == frames[2] and #crash.stops[source].frames == 2)
  assert(crash.stops[source].source_frame == frames[2])
  dap.listeners.after.event_continued["test-crash"](session)
  assert(crash.stops[source] == nil)
  stopped("exception", "signal SIGSEGV")
  dap.listeners.after.stackTrace["test-crash"](session, nil, { stackFrames = { frames[1] } }, { threadId = 1 })
  assert(crash.stops[source].source_frame == nil, "A missing source frame must not prevent crash inspection")
  cleanup()
  assert(crash.stops[source] == nil and dap.listeners.after.stackTrace["test-crash"] == nil)
  package.loaded.dapui = previous_ui
end)
test("normal crash results display signals without starting a debugger", function()
  config.setup({ tests_relative_dir = ".focc" })
  local path = root .. "/signals/main.py"
  write(
    path,
    [[import os, resource
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
signal = int(input())
if signal:
    os.kill(os.getpid(), signal)
print('ok')
]]
  )
  local data = store.load(path)
  data.tests = { { test = "11\n" }, { test = "6\n" }, { test = "0\n", correct_answers = { "ok" } } }
  store.save(data)
  local original = store.read(data.path)
  local session = runner.run(path)
  wait(function()
    return session.status == "finished"
  end)
  assert(session.results[1].signal == vim.uv.constants.SIGSEGV)
  assert(session.results[2].signal == vim.uv.constants.SIGABRT)
  assert(session.results[3].answer == "accepted", "Normal run_all must continue after a crash")
  local signals = require("focc.signals")
  assert(signals.name(0) == nil and signals.name(nil) == nil)
  assert(signals.name(9999) == "signal 9999")
  local ui = require("focc.ui")
  ui.show(session)
  local view = ui.views[path]
  local output = table.concat(vim.api.nvim_buf_get_lines(view.buf, 0, -1, false), "\n")
  assert(output:find("[RUNTIME ERROR]  SIGSEGV", 1, true))
  assert(output:find("[RUNTIME ERROR]  SIGABRT", 1, true))
  session.results[1].reason = "timeout"
  ui.render(session)
  assert(view.headers[1].status == "timeout", "Timeouts must not be relabeled as crashes")
  assert(store.read(data.path) == original)
end)
test("Companion imports preserve solutions and custom tests", function()
  config.setup({ tests_relative_dir = ".focc" })
  local companion = require("focc.companion")
  local payload = {
    name = "A. Example",
    group = "Codeforces - Contest",
    url = "https://codeforces.com/contest/1234/problem/A",
    tests = { { input = "2\n", output = "4\n" } },
    batch = { id = "batch-1", size = 2 },
  }
  local result = companion.import(payload, root .. "/companion")
  assert(result.source == root .. "/companion/1234/A.cpp" and result.added == 1)
  local data = store.load(result.source)
  assert(data.tests[1].test == "2\n" and data.tests[1].correct_answers[1] == "4")
  write(result.source, "// my solution\n")
  data.tests[#data.tests + 1] = { test = "custom", extra = "keep" }
  store.save(data)
  assert(companion.import(payload, root .. "/companion").added == 0)
  assert(store.read(result.source) == "// my solution\n" and #store.load(result.source).tests == 2)
  assert(store.load(result.source).tests[2].extra == "keep")
  payload.url = "https://codeforces.com/problemset/problem/1234/B"
  assert(companion.import(payload, root .. "/companion").source:match("/B.cpp$"))
  payload.tests = { { input = 123, output = "4" } }
  rejected(function()
    companion.import(payload, root .. "/companion")
  end)
  local linkroot = root .. "/companion-link"
  assert(vim.uv.fs_symlink(root .. "/companion", linkroot))
  rejected(function()
    companion.import({ name = "X", url = "https://codeforces.com/contest/1/problem/A", tests = {} }, linkroot)
  end)
end)
test("Companion judge paths are stable for individual and contest downloads", function()
  config.setup({ tests_relative_dir = ".focc" })
  local companion = require("focc.companion")
  local destination = root .. "/judge-paths"
  local cases = {
    { "https://codeforces.com/contest/1234/problem/A", "1234/A.cpp" },
    { "https://www.codeforces.com/problemset/problem/1234/A?locale=en", "1234/A.cpp" },
    { "https://codeforces.com/gym/100001/problem/A1/", "100001/A1.cpp" },
    { "https://atcoder.jp/contests/abc400/tasks/abc400_a?lang=en", "abc400/A.cpp", "A - ABC400 Party" },
    { "https://atcoder.jp/contests/arc100/tasks/arc100_f/", "arc100/F.cpp", "F - Example" },
    { "https://atcoder.jp/contests/abc042/tasks/arc058_a", "abc042/A.cpp", "A - Shared task" },
    { "https://atcoder.jp/contests/abc001/tasks/abc001_1", "abc001/A.cpp", "A - Older task" },
    { "https://atcoder.jp/contests/dp/tasks/dp_a", "dp/A.cpp", "A - Frog 1" },
    { "https://atcoder.jp/contests/example/tasks/unusual_task", "example/Ex.cpp", "Ex - Extra" },
    { "https://atcoder.jp/contests/example/tasks/unusual_task2", "example/unusual_task2.cpp" },
    { "https://www.codechef.com/START123D/problems/PROBCODE", "START123D/PROBCODE.cpp" },
    { "https://codechef.com/START123D/submit/PROBCODE?tab=statement", "START123D/PROBCODE.cpp" },
    { "https://www.codechef.com/START123D/problems-old/PROBCODE/", "START123D/PROBCODE.cpp" },
    { "https://www.codechef.com/problems/PROBCODE", "START123D/PROBCODE.cpp", "Example", "CodeChef - START123D" },
    { "https://www.codechef.com/submit/PROBCODE", "START123D/PROBCODE.cpp", "Example", "CodeChef - START123D" },
    { "https://www.codechef.com/problems/FLOW001", "Practice/FLOW001.cpp", "Example", "CodeChef - Practice" },
    { "https://www.codechef.com/problems-old/FLOW001", "Practice/FLOW001.cpp" },
    { "https://www.codechef.com/PRACTICE/problems/FLOW001", "Practice/FLOW001.cpp" },
    { "https://www.codechef.com/problems/FLOW002", "Practice/FLOW002.cpp", "Example", "CodeChef - Learn C++" },
    { "https://other.example/problems/1", "Other_Group/Example.cpp", "Example", "Other Group" },
  }
  for _, case in ipairs(cases) do
    local payload = {
      url = case[1],
      name = case[3] or "Example",
      group = case[4],
      tests = { { input = "8\n", output = "16\n" } },
    }
    local single = companion.import(payload, destination)
    assert(single.source == destination .. "/" .. case[2], single.source)
    assert(
      store.path(single.source)
        == vim.fs.joinpath(vim.fs.dirname(single.source), ".focc", vim.fs.basename(single.source) .. ":tests")
    )
    payload.batch = { id = "judge-contest", size = 5 }
    local batch = companion.import(payload, destination)
    assert(batch.source == single.source and batch.added == 0)
    local tests = store.load(single.source).tests
    assert(#tests == 1 and tests[1].test == "8\n" and tests[1].correct_answers[1] == "16")
  end
  for _, url in ipairs({
    "https://codeforces.com/contest/1/problem/../A",
    "https://atcoder.jp/contests/../tasks/task_a",
    "https://atcoder.jp/contests/abc400/editorial",
    "https://www.codechef.com/../problems/FLOW001",
    "https://www.codechef.com/START123D/editorial/FLOW001",
  }) do
    rejected(function()
      companion.import({ url = url, name = "Example", tests = {} }, destination)
    end)
  end
  assert(not vim.uv.fs_stat(destination .. "/Codeforces"))
  assert(not vim.uv.fs_stat(destination .. "/AtCoder"))
  assert(not vim.uv.fs_stat(destination .. "/CodeChef"))
end)
test("single-test reruns preserve other results and full runs reset them", function()
  config.setup({ tests_relative_dir = ".focc" })
  local path = root .. "/single-rerun/main.py"
  write(path, "import sys\nvalue = input()\nif value == 'crash': sys.exit(1)\nprint(value)\n")
  local data = store.load(path)
  data.tests = {
    { test = "ok\n", correct_answers = { "ok" } },
    { test = "wrong\n", correct_answers = { "expected" } },
    { test = "crash\n" },
    { test = "untested\n", correct_answers = { "untested" } },
  }
  store.save(data)
  local session = runner.run(path)
  wait(function()
    return session.status == "finished"
  end)
  assert(session.results[1].answer == "accepted" and session.results[2].answer == "rejected")
  assert(session.results[3].code == 1)
  session.results[4] = nil
  local previous = session
  local ui = require("focc.ui")
  ui.show(session)
  session = runner.run(path, 2, function(value)
    ui.render(value)
  end)
  assert(session.results[2] == nil, "The selected test must clear its old verdict during execution")
  assert(session.results[1] == previous.results[1] and session.results[3] == previous.results[3])
  assert(session.results[4] == nil)
  wait(function()
    return session.status == "finished"
  end)
  assert(session.results[2] ~= previous.results[2] and session.results[2].answer == "rejected")
  assert(session.results[1] == previous.results[1] and session.results[3] == previous.results[3])
  local headers = ui.views[path].headers
  assert(headers[1].status == "accepted" and headers[2].status == "rejected")
  assert(headers[3].status == "runtime error" and headers[4].status == "not run")
  previous = session
  session = runner.run(path, 4)
  wait(function()
    return session.status == "finished"
  end)
  assert(session.results[4].answer == "accepted")
  for i = 1, 3 do
    assert(session.results[i] == previous.results[i])
  end
  session = runner.run(path)
  assert(next(session.results) == nil, "A full run must reset all old results")
  wait(function()
    return session.status == "finished"
  end)
  -- Externally edited tests must not inherit stale verdicts by index.
  data.tests[1].test = "changed\n"
  store.save(data)
  session = runner.run(path, 2)
  assert(session.results[1] == nil and session.results[3] ~= nil)
  wait(function()
    return session.status == "finished"
  end)
end)
test("Companion current-source imports preserve code and append shared tests", function()
  config.setup({ tests_relative_dir = ".focc" })
  local companion = require("focc.companion")
  local source = root .. "/current-source/problem.py"
  write(source, "# existing solution\n")
  local data = store.load(source)
  data.tests = { { test = "custom", extra = "preserve" } }
  store.save(data)
  local active = { source = source, store = data, status = "ready", results = { { stdout = "old" } } }
  runner.sessions[source] = active
  local payload = {
    name = "A - Example",
    url = "https://atcoder.jp/contests/abc400/tasks/abc400_a",
    tests = { { input = "3\n", output = "6\n" } },
    batch = { id = "single", size = 1 },
  }
  local result = companion.import(payload, nil, source)
  assert(result.source == source and result.added == 1)
  assert(store.read(source) == "# existing solution\n")
  assert(store.path(source) == root .. "/current-source/.focc/problem.py:tests")
  local tests = store.load(source).tests
  assert(#tests == 2 and tests[1].extra == "preserve" and tests[2].correct_answers[1] == "6")
  assert(active.status == "ready" and #active.results == 0 and #active.store.tests == 2)
  assert(companion.import(payload, nil, source).added == 0)
  assert(not vim.uv.fs_stat(root .. "/current-source/abc400"))
  active.status = "running"
  rejected(function()
    companion.import(payload, nil, source)
  end)
  active.status = "ready"
  payload.batch.size = 2
  local original = store.read(store.path(source))
  rejected(function()
    companion.import(payload, nil, source)
  end)
  assert(store.read(store.path(source)) == original)
  payload.batch = nil
  local unsaved = root .. "/current-source/unsaved.cpp"
  assert(companion.import(payload, nil, unsaved).source == unsaved)
  assert(not vim.uv.fs_stat(unsaved) and #store.load(unsaved).tests == 1)
  local linked = root .. "/current-source/linked.cpp"
  assert(vim.uv.fs_symlink(source, linked))
  rejected(function()
    companion.import(payload, nil, linked)
  end)
  assert(not vim.uv.fs_stat(store.path(linked)))
end)
test("Companion receiver follows active buffers for each HTTP import", function()
  local probe = vim.uv.new_tcp()
  assert(probe:bind("127.0.0.1", 0))
  local port = probe:getsockname().port
  probe:close()
  config.setup({ tests_relative_dir = ".focc", companion = { port = port } })
  local companion = require("focc.companion")
  local source = root .. "/pinned-source/problem.cpp"
  write(source, "// on disk\n")
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, source)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "// unsaved edits" })
  vim.api.nvim_set_current_buf(buf)
  vim.cmd("Focc receive")
  assert(companion.current_buffer and companion.root == nil)
  local other = vim.api.nvim_create_buf(true, false)
  local other_source = root .. "/pinned-source/other.cpp"
  vim.api.nvim_buf_set_name(other, other_source)
  local function send_samples(expected)
    local result = invoke({
      "python",
      "-c",
      [[
import socket, json, sys
def send(problem):
    body = json.dumps(problem).encode()
    with socket.create_connection(('127.0.0.1', int(sys.argv[1])), timeout=5) as sock:
        sock.sendall(b'POST / HTTP/1.1\r\nContent-Length: ' + str(len(body)).encode() + b'\r\n\r\n' + body)
        response = b''
        while True:
            part = sock.recv(8192)
            if not part: break
            response += part
        return response.split(b'\r\n')[0]
problem = {'name': 'A. Example', 'url': 'https://codeforces.com/contest/987654/problem/A',
           'tests': [{'input': '2\n', 'output': '4\n'}], 'batch': {'id': 'single', 'size': 1}}
assert sys.argv[2].encode() in send(problem)
if sys.argv[2] == '400': sys.exit(0)
assert b'200' in send(problem)
problem['tests'] = [{'input': '7\n', 'output': '14\n'}]
assert b'200' in send(problem)
problem['batch']['size'] = 2
assert b'400' in send(problem)
]],
      tostring(port),
      expected or "200",
    }, { timeout_ms = 15000 })
    assert(result.code == 0, result.stderr)
  end
  send_samples()
  assert(#store.load(source).tests == 2)
  vim.api.nvim_set_current_buf(other)
  send_samples()
  assert(#store.load(other_source).tests == 2)
  assert(not vim.uv.fs_stat(other_source), "Import must not save an unsaved source")
  local panel = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(panel, "focc://results/receiver")
  vim.b[panel].focc_source = source
  vim.api.nvim_set_current_buf(panel)
  send_samples()
  assert(#store.load(source).tests == 2, "FOCC panels must resolve their associated source")
  vim.api.nvim_buf_delete(panel, { force = true })
  local invalid = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(invalid)
  send_samples("400")
  vim.api.nvim_buf_set_name(invalid, root .. "/pinned-source/unsupported.txt")
  send_samples("400")
  assert(not vim.uv.fs_stat(store.path(root .. "/pinned-source/unsupported.txt")))
  assert(#store.load(source).tests == 2 and #store.load(other_source).tests == 2)
  vim.api.nvim_set_current_buf(buf)
  send_samples()
  vim.cmd("Focc stop_receive")
  assert(companion.current_buffer == nil and companion.root == nil)
  assert(#store.load(source).tests == 2)
  assert(store.read(source) == "// on disk\n" and vim.bo[buf].modified)
  assert(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == "// unsaved edits")
  assert(not vim.uv.fs_stat(other_source) and vim.uv.fs_stat(store.path(other_source)))
  assert(not vim.uv.fs_stat(root .. "/pinned-source/987654"))
  vim.api.nvim_buf_delete(buf, { force = true })
  vim.api.nvim_buf_delete(other, { force = true })
  vim.api.nvim_buf_delete(invalid, { force = true })
  config.setup({ tests_relative_dir = ".focc" })
end)
test("Companion current-file mode resolves FOCC buffers and rejects unnamed sources", function()
  local probe = vim.uv.new_tcp()
  assert(probe:bind("127.0.0.1", 0))
  local port = probe:getsockname().port
  probe:close()
  config.setup({ tests_relative_dir = ".focc", companion = { port = port } })
  local companion = require("focc.companion")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  rejected(function()
    companion.start()
  end)
  assert(not companion.server)
  vim.api.nvim_buf_set_name(buf, root .. "/unsupported.txt")
  rejected(function()
    companion.start()
  end)
  assert(not companion.server)
  vim.api.nvim_buf_set_name(buf, "focc://results/test")
  vim.b[buf].focc_source = root .. "/associated.cpp"
  companion.start()
  assert(companion.current_buffer and companion.root == nil)
  companion.stop()
  assert(not vim.uv.fs_stat(root .. "/associated.cpp"))
  vim.api.nvim_buf_delete(buf, { force = true })
  config.setup({ tests_relative_dir = ".focc" })
end)
test("Companion HTTP listener handles split POSTs and rejects bad requests", function()
  local probe = vim.uv.new_tcp()
  assert(probe:bind("127.0.0.1", 0))
  local port = probe:getsockname().port
  probe:close()
  config.setup({ tests_relative_dir = ".focc", companion = { port = port, max_request_bytes = 4096 } })
  local companion = require("focc.companion")
  companion.start(root .. "/http-import")
  local result = invoke({
    "python",
    "-c",
    [[
import socket, json, sys, time
port = int(sys.argv[1])
def send(request, split=False):
    with socket.create_connection(('127.0.0.1', port), timeout=5) as sock:
        if split:
            sock.sendall(request[:20]); time.sleep(.02); sock.sendall(request[20:])
        else: sock.sendall(request)
        response = b''
        while True:
            chunk = sock.recv(8192)
            if not chunk: break
            response += chunk
        return response.split(b'\r\n')[0]
problem = {'name':'A. HTTP', 'url':'https://codeforces.com/contest/99/problem/A', 'tests':[{'input':'7\n','output':'14\n'}], 'batch':{'id':'http-contest','size':2}}
body = json.dumps(problem).encode()
request = b'POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: ' + str(len(body)).encode() + b'\r\n\r\n' + body
assert b'200' in send(request, True)
assert b'200' in send(request)
problem['name'] = 'B. HTTP'
problem['url'] = 'https://codeforces.com/contest/99/problem/B'
body = json.dumps(problem).encode()
assert b'200' in send(b'POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: ' + str(len(body)).encode() + b'\r\n\r\n' + body)
for url in ['https://atcoder.jp/contests/abc400/tasks/abc400_a', 'https://www.codechef.com/START123D/problems/PROBCODE']:
    problem['url'] = url
    problem['batch'] = {'id': url, 'size': 1}
    body = json.dumps(problem).encode()
    assert b'200' in send(b'POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: ' + str(len(body)).encode() + b'\r\n\r\n' + body, True)
assert b'405' in send(b'GET / HTTP/1.1\r\nHost: localhost\r\n\r\n')
assert b'413' in send(b'POST / HTTP/1.1\r\nContent-Length: 99999\r\n\r\n')
assert b'400' in send(b'POST / HTTP/1.1\r\nContent-Length: 1\r\n\r\nx')
assert b'400' in send(b'POST / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 1\r\n\r\nx')
print('ok')
]],
    tostring(port),
  }, { timeout_ms = 15000 })
  companion.stop()
  assert(result.code == 0, result.stderr)
  assert(#store.load(root .. "/http-import/99/A.cpp").tests == 1)
  assert(#store.load(root .. "/http-import/99/B.cpp").tests == 1)
  assert(#store.load(root .. "/http-import/abc400/A.cpp").tests == 1)
  assert(#store.load(root .. "/http-import/START123D/PROBCODE.cpp").tests == 1)
  config.setup({ tests_relative_dir = ".focc" })
end)
print(string.format("%d tests passed. Temporary files: %s", passed, root))
vim.cmd("qa!")
