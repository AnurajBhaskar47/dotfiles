-- Live crash checks: nvim --headless -u NONE -l tests/crash.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/nvim-dap")
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/nvim-dap-ui")
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/nvim-nio")
local dap = require("dap")
dap.set_log_level("TRACE")
local ui_opened = 0
local dapui = require("dapui")
dapui.setup({})
local open = dapui.open
dapui.open = function(opts)
  ui_opened = ui_opened + 1
  open(opts)
end
local adapter = vim.fn.stdpath("data") .. "/mason/bin/codelldb"
assert(vim.fn.executable(adapter) == 1, "Install CodeLLDB through Mason first")
dap.adapters.codelldb = {
  type = "server",
  port = "${port}",
  executable = { command = adapter, args = { "--port", "${port}" } },
}
local spec = dofile("../../lua/plugins/focc.lua")
spec[1].opts.debug.stop_on_entry = false
require("focc.config").setup(spec[1].opts)
local debugger = require("focc.debug")
local store = require("focc.store")
local root = "/tmp/opencode/focc-crash-" .. vim.uv.os_getpid()
vim.fn.mkdir(root, "p")
local source = root .. "/main.cpp"
local code = [[#include <cstdlib>
#include <iostream>
void crash(int value, int mode) {
  if (mode == 11) {
    volatile int *ptr = nullptr;
    *ptr = value;
  } else {
    std::abort();
  }
}
int main() {
  int input = 0, mode = 0;
  std::cin >> input >> mode;
  crash(input, mode);
  return 0;
}
]]
local file = assert(io.open(source, "wb"))
file:write(code)
file:close()
local data = store.load(source)
data.tests = { { test = "42 11\n" }, { test = "73 6\n" } }
store.save(data)
local original = store.read(data.path)
vim.cmd.edit(source)
local stopped
dap.listeners.after.event_stopped.crash_integration = function(_, body)
  stopped = body
end
local function wait(predicate, label)
  assert(vim.wait(30000, predicate, 10), "Timed out: " .. label)
end
local function request(session, command, args)
  local done, response, error
  session:request(command, args, function(err, body)
    error, response, done = err, body, true
  end)
  wait(function()
    return done
  end, command)
  assert(not error, vim.inspect(error))
  return response
end
local function panel(filetype)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == filetype then
      return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    end
  end
  return ""
end
local ok, err = pcall(function()
  for index, expected in ipairs({ { "SIGSEGV", "42" }, { "SIGABRT", "73" } }) do
    stopped = nil
    debugger.start(source, index)
    wait(function()
      return stopped ~= nil
    end, expected[1] .. " stop")
    local session = assert(dap.session())
    wait(function()
      return session.current_frame ~= nil
    end, "current frame")
    local crash = require("focc.crash")
    wait(function()
      return crash.stops[source] and crash.stops[source].source_frame ~= nil
    end, "FOCC source frame")
    assert(crash.stops[source].signal == expected[1])
    assert(session.current_frame.id == crash.stops[source].source_frame.id)
    assert(crash.stops[source].source_frame.line == (index == 1 and 6 or 8))
    assert(ui_opened == index, "FOCC must open the DAP UI on each crash: " .. ui_opened .. " opens, expected " .. index)
    wait(function()
      return panel("dapui_stacks"):find("crash", 1, true) ~= nil
    end, "visible stack frames")
    local input = session.config.stdio[1]
    assert(store.read(input) == data.tests[index].test)
    local exception = request(session, "exceptionInfo", { threadId = stopped.threadId })
    assert(vim.inspect(exception):find(expected[1], 1, true), vim.inspect(exception))
    local trace = request(session, "stackTrace", { threadId = stopped.threadId })
    local crash_frame, caller_frame
    for _, frame in ipairs(trace.stackFrames) do
      if frame.source and frame.source.path == source then
        if frame.name:find("crash", 1, true) then
          crash_frame = frame
        end
        if frame.name == "main" then
          caller_frame = frame
        end
      end
    end
    assert(crash_frame and caller_frame, "Expected crash and caller source frames")
    session:_frame_set(crash_frame)
    assert(
      request(session, "evaluate", { expression = "value", frameId = crash_frame.id, context = "watch" }).result
        == expected[2]
    )
    local scopes = request(session, "scopes", { frameId = crash_frame.id })
    local found_value = false
    for _, scope in ipairs(scopes.scopes) do
      for _, variable in
        ipairs(request(session, "variables", { variablesReference = scope.variablesReference }).variables)
      do
        if variable.name == "value" and variable.value == expected[2] then
          found_value = true
        end
      end
    end
    assert(found_value, "Expected the crash frame's value in the variables response")
    wait(function()
      local text = panel("dapui_scopes")
      return text:find("value", 1, true) and text:find(expected[2], 1, true)
    end, "crash variables in Scopes")
    session:_frame_set(caller_frame)
    assert(
      request(session, "evaluate", { expression = "input", frameId = caller_frame.id, context = "watch" }).result
        == expected[2]
    )
    assert(session.current_frame.id == caller_frame.id)
    wait(function()
      local text = panel("dapui_scopes")
      return text:find("input", 1, true) and text:find(expected[2], 1, true)
    end, "caller variables in Scopes")
    assert(dap.session() == session and vim.uv.fs_stat(input), "Crash inspection must retain session and stdin")
    assert(store.read(data.path) == original)
    dap.terminate()
    wait(function()
      return not dap.session() and not vim.uv.fs_stat(input)
    end, "termination and input cleanup")
    assert(crash.stops[source] == nil, "Termination must remove crash listeners/state")
    dapui.close({})
    print("PASS " .. expected[1] .. ": source frames, variables, frame selection, retained stdin, termination cleanup")
  end
end)
if not ok then
  if dap.session() then
    dap.terminate()
    vim.wait(10000, function()
      return not dap.session()
    end, 10)
  end
  debugger.cleanup()
  io.stderr:write(tostring(err) .. "\n")
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
