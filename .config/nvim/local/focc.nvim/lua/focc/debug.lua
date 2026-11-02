local M = { pending = {}, inputs = {} }
local process = require("focc.process")

function M.cleanup()
  for _, task in pairs(M.pending) do
    task:cancel()
  end
  for input in pairs(M.inputs) do
    vim.uv.fs_unlink(input)
  end
  M.inputs = {}
end

function M.start(source, index, mode)
  mode = mode or "debug"
  local cfg = require("focc.config").values
  local ok, dap = pcall(require, "dap")
  assert(ok, "FOCC: enable LazyVim DAP Core before debugging")
  assert(cfg.debug.adapter ~= "" and dap.adapters[cfg.debug.adapter], "FOCC: configure debug.adapter in nvim-dap")
  assert(require("focc.config").language(source).name == "C++", "FOCC: debugging currently supports C++")
  assert(cfg.debug.compile_cmd, "FOCC: configure debug.compile_cmd with debug symbols")
  assert(not M.pending[source], "FOCC: a debug build is already running for this source")
  assert(not dap.session(), "FOCC: finish the current debug session before launching another")
  local function launch(test)
    local input, temporary
    if test then
      input = vim.fn.tempname()
      local file = assert(io.open(input, "wb"))
      local written, err = file:write(test.test)
      file:close()
      if not written then
        vim.uv.fs_unlink(input)
        error(err)
      end
      temporary = true
      M.inputs[input] = true
    elseif mode == "debug_input_file" then
      input = vim.fn.expand(cfg.debug.input_file)
      if not vim.startswith(input, "/") then
        input = vim.fs.joinpath(vim.fs.dirname(source), input)
      end
      local file = assert(io.open(input, "rb"), "FOCC: cannot read debug input: " .. input)
      file:close()
    end
    local key = "focc-" .. source
    local detach_crash, defaults, previous_auto_continue
    local function cleanup()
      if detach_crash then
        detach_crash()
        detach_crash = nil
      end
      if defaults then
        if defaults.auto_continue_if_many_stopped == false then
          defaults.auto_continue_if_many_stopped = previous_auto_continue
        end
        defaults = nil
      end
      if temporary then
        vim.uv.fs_unlink(input)
        M.inputs[input] = nil
      end
      dap.listeners.after.event_terminated[key] = nil
      dap.listeners.after.event_exited[key] = nil
      dap.listeners.after.event_initialized[key] = nil
    end
    M.pending[source] = process.start(process.command(cfg.debug.compile_cmd, source), {
      cwd = vim.fs.dirname(source),
      timeout_ms = cfg.compile_timeout_ms,
    }, function(result)
      M.pending[source] = nil
      if result.code ~= 0 or result.reason then
        cleanup()
        vim.notify(
          "FOCC debug build failed: " .. (result.reason or "compiler error") .. "\n" .. result.stderr .. result.stdout,
          vim.log.levels.ERROR
        )
        return
      end
      if dap.session() then
        cleanup()
        vim.notify("FOCC: another debug session started during compilation", vim.log.levels.ERROR)
        return
      end
      local program = process.command({ cfg.debug.program }, source)[1]
      if not vim.startswith(program, "/") then
        program = vim.fs.joinpath(vim.fs.dirname(source), program)
      end
      if vim.fn.executable(program) ~= 1 then
        cleanup()
        vim.notify("FOCC: debug build did not produce " .. program, vim.log.levels.ERROR)
        return
      end
      dap.listeners.after.event_terminated[key] = cleanup
      dap.listeners.after.event_exited[key] = cleanup
      dap.listeners.after.event_initialized[key] = function(session)
        -- Also clean up on disconnect or adapter failure after initialization.
        session.on_close[key] = cleanup
        -- nvim-dap must not automatically resume another stopped thread during
        -- this FOCC session. Restore the adapter default when the session closes.
        if not defaults then
          defaults = dap.defaults[cfg.debug.adapter]
          previous_auto_continue = rawget(defaults, "auto_continue_if_many_stopped")
          defaults.auto_continue_if_many_stopped = false
        end
      end
      detach_crash = require("focc.crash").attach(dap, source, key)
      local launched, err = pcall(dap.run, {
        name = "FOCC " .. vim.fs.basename(source),
        type = cfg.debug.adapter,
        request = "launch",
        program = program,
        cwd = vim.fs.dirname(source),
        args = cfg.run_args,
        stopOnEntry = cfg.debug.stop_on_entry,
        -- Explicit JSON nulls retain stdout/stderr defaults in the three-slot array.
        stdio = input and { input, vim.NIL, vim.NIL } or nil,
        preRunCommands = input and { 'settings set target.input-path "' .. input:gsub('([\\"])', "\\%1") .. '"' }
          or nil,
        terminal = input and "console" or "integrated",
      })
      if not launched then
        cleanup()
        vim.notify(tostring(err), vim.log.levels.ERROR)
      end
    end)
  end
  if mode ~= "debug" then
    launch()
    return
  end
  local data = require("focc.store").load(source)
  assert(#data.tests > 0, "FOCC: no stored tests; add one or use debug_input_file/debug_no_input")
  if index then
    assert(data.tests[index], "FOCC: invalid debug test")
    launch(data.tests[index])
  else
    local choices = {}
    for i in ipairs(data.tests) do
      choices[#choices + 1] = i
    end
    vim.ui.select(choices, { prompt = "FOCC: debug stored test" }, function(i)
      if not i then
        return
      end
      local selected, err = pcall(function()
        assert(not M.pending[source] and not dap.session(), "FOCC: debugger is already busy")
        launch(data.tests[i])
      end)
      if not selected then
        vim.notify(tostring(err), vim.log.levels.ERROR)
      end
    end)
  end
end

return M
