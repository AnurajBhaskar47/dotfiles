-- Optional integration test: run from the plugin directory with
-- nvim --headless -u NONE -l tests/debug.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/nvim-dap")
local dap = require("dap")
dap.set_log_level("TRACE")
local adapter = vim.fn.stdpath("data") .. "/mason/bin/codelldb"
assert(vim.fn.executable(adapter) == 1, "Install codelldb through Mason first")
dap.adapters.codelldb = {
  type = "server",
  port = "${port}",
  executable = { command = adapter, args = { "--port", "${port}" } },
}
local spec = dofile("../../lua/plugins/focc.lua")
require("focc.config").setup(spec[1].opts)
local root = "/tmp/opencode/focc-dap-" .. vim.uv.os_getpid()
vim.fn.mkdir(root, "p")
local source = root .. "/main.cpp"
local file = assert(io.open(source, "wb"))
file:write(
  "#include <iostream>\nint main() {\n  int x = 0;\n  std::cin >> x;\n  x *= 2;\n  std::cout << x;\n  return 0;\n}\n"
)
file:close()
local store = require("focc.store")
local data = store.load(source)
data.tests = { { test = "12\n", correct_answers = { "24" } } }
store.save(data)
local original = store.read(data.path)
vim.cmd.edit(source)
vim.api.nvim_win_set_cursor(0, { 5, 0 })
dap.toggle_breakpoint()
local stops, output = 0, ""
local done = false
dap.listeners.after.event_output.integration = function(_, body)
  if body.category == "stdout" then
    output = output .. body.output
  end
end
dap.listeners.after.event_stopped.integration = function()
  stops = stops + 1
end
dap.listeners.after.event_terminated.integration = function()
  done = true
end
local function wait(predicate, label)
  assert(vim.wait(30000, predicate, 10), "Debugger timed out: " .. (label or "event") .. "; see :DapShowLog")
end
local ok, err = pcall(function()
  require("focc.debug").start(source, 1)
  wait(function()
    return stops >= 1
  end)
  local session = assert(dap.session())
  wait(function()
    return session.stopped_thread_id ~= nil and session.current_frame ~= nil
  end, "entry frame")
  local input = session.config.stdio[1]
  assert(store.read(input) == "12\n")
  dap.continue()
  wait(function()
    return stops >= 2
  end, "breakpoint")
  wait(function()
    return session.current_frame and session.current_frame.line == 5
  end)
  assert(session.current_frame.line == 5, "Expected breakpoint on line 5")
  dap.step_over()
  wait(function()
    return stops >= 3
  end)
  wait(function()
    return session.current_frame and session.current_frame.line == 6
  end)
  local evaluated
  session:request(
    "evaluate",
    { expression = "x", frameId = session.current_frame.id, context = "watch" },
    function(eval_err, body)
      assert(not eval_err, vim.inspect(eval_err))
      evaluated = body.result
    end
  )
  wait(function()
    return evaluated ~= nil
  end, "variable evaluation")
  assert(evaluated == "24", "Expected x = 24 after stepping")
  dap.continue()
  wait(function()
    return done
  end)
  wait(function()
    return not vim.uv.fs_stat(input)
  end)
  assert(output:find("24", 1, true), "Expected output from stored test input")
  assert(store.read(data.path) == original, "Debugging modified the shared test file")
end)
if not ok then
  if dap.session() then
    dap.terminate()
  end
  require("focc.debug").cleanup()
  io.stderr:write(tostring(err) .. "\n")
  vim.cmd("cquit 1")
end
print("PASS CodeLLDB: stored test stdin, stop on entry, breakpoint, step over, variable inspection, and cleanup")
vim.cmd("qa!")
