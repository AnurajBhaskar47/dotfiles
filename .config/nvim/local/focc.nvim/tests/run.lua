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
  assert(vim.bo.filetype == "json" and vim.fn.exists(":FoccSave") == 2)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '{"test":"3\\n","correct_answers":["6"],"extra":null}' })
  vim.cmd("FoccSave")
  local loaded = store.load(path)
  assert(loaded.tests[1].test == "3\n" and loaded.tests[1].extra == vim.NIL)
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
    listeners = { after = { event_terminated = {}, event_exited = {}, event_initialized = {} } },
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
  assert(store.read(input) == "12\n" and value.stdio[2] == vim.NIL)
  local result = invoke({ value.program }, { input = store.read(input) })
  assert(result.stdout == "24")
  dap.listeners.after.event_exited["focc-" .. path]()
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
