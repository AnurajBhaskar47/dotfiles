local M = { stops = {} }

-- These listeners inspect a live stopped process. They never repeat a test,
-- continue execution, terminate the process, or write shared test files.
function M.attach(dap, source, key)
  local stop
  dap.listeners.before.event_stopped[key] = function(session, body)
    stop = nil
    M.stops[source] = nil
    local signal = (body.description or body.text or ""):match("SIG[%u%d]+")
    -- CodeLLDB can report its initial loader stop as SIGSTOP, not a crash.
    if body.reason ~= "exception" or signal == "SIGSTOP" then
      return
    end
    stop = {
      session = session,
      thread_id = body.threadId,
      reason = body.reason,
      description = body.description or body.text or body.reason,
      signal = signal,
    }
    M.stops[source] = stop
  end
  dap.listeners.after.event_stopped[key] = function(session)
    if not stop or stop.session ~= session or stop.announced then
      return
    end
    stop.announced = true
    local ok, ui = pcall(require, "dapui")
    if ok then
      ui.open({})
    end
    local message = "FOCC: Debugger stopped: "
      .. stop.description
      .. ". Select a stack frame to inspect variables. Execution remains stopped."
    vim.notify(message, vim.log.levels.ERROR)
    dap.repl.append(message .. "\n")
  end
  dap.listeners.after.stackTrace[key] = function(session, err, body, request)
    if
      not stop
      or stop.session ~= session
      or stop.located
      or err
      or not body
      or not request
      or request.threadId ~= stop.thread_id
    then
      return
    end
    stop.located = true
    stop.frames = body.stackFrames or {}
    for _, frame in ipairs(stop.frames) do
      if
        frame.source
        and frame.source.path
        and frame.line
        and frame.line > 0
        and vim.fs.normalize(frame.source.path) == vim.fs.normalize(source)
      then
        stop.source_frame = frame
        -- The failing instruction can be in libc (for example, abort()).
        -- Select the nearest frame in this source, without hiding libc frames.
        session:_frame_set(frame)
        dap.repl.append(string.format("FOCC: Source frame: %s:%d (%s)\n", source, frame.line, frame.name))
        break
      end
    end
  end
  dap.listeners.after.event_continued[key] = function(session)
    if stop and stop.session == session then
      stop = nil
      M.stops[source] = nil
    end
  end
  return function()
    stop = nil
    M.stops[source] = nil
    dap.listeners.before.event_stopped[key] = nil
    dap.listeners.after.event_stopped[key] = nil
    dap.listeners.after.stackTrace[key] = nil
    dap.listeners.after.event_continued[key] = nil
  end
end

return M
