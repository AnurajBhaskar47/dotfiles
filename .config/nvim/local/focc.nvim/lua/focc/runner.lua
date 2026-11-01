local M = { sessions = {} }
local process = require("focc.process")
local store = require("focc.store")

function M.stop(session)
  if session then
    session.stopped = true
    if session.task then
      session.task:cancel()
    end
  end
end

function M.run(source, index, update, interactive)
  local cfg = require("focc.config").values
  local lang = require("focc.config").language(source)
  local data = store.load(source)
  if index then
    assert(data.tests[index], "FOCC: test number does not exist")
  end
  M.stop(M.sessions[source])
  local session = { source = source, store = data, results = {}, status = "compiling", update = update }
  M.sessions[source] = session
  local function notify()
    if update then
      update(session)
    end
  end
  local function next_test(i)
    if session.stopped then
      session.status = "cancelled"
      notify()
      return
    end
    if not data.tests[i] or (index and i ~= index) then
      session.status = "finished"
      notify()
      return
    end
    session.status = "running"
    session.current = i
    session.task = process.start(process.command(lang.run_cmd, source), {
      cwd = vim.fs.dirname(source),
      input = data.tests[i].test,
    }, function(result)
      if M.sessions[source] ~= session then
        return
      end
      result.answer = store.answer(data.tests[i], result.stdout)
      session.results[i] = result
      notify()
      if result.reason == "cancelled" then
        session.status = "cancelled"
        notify()
      else
        next_test(i + 1)
      end
    end)
    notify()
  end
  local function execute()
    if session.stopped then
      session.status = "cancelled"
      notify()
      return
    end
    if interactive then
      session.status = "interactive"
      session.input = ""
      session.task = process.start(process.command(lang.run_cmd, source), {
        cwd = vim.fs.dirname(source),
        interactive = true,
        on_output = function(task)
          session.live = task
          notify()
        end,
      }, function(result)
        if M.sessions[source] ~= session then
          return
        end
        session.live = result
        session.status = result.reason or "finished"
        session.interactive_result = result
        notify()
      end)
      notify()
    else
      next_test(index or 1)
    end
  end
  local compile = process.command(lang.compile_cmd, source)
  if compile then
    session.task = process.start(
      compile,
      { cwd = vim.fs.dirname(source), timeout_ms = cfg.compile_timeout_ms },
      function(result)
        if M.sessions[source] ~= session then
          return
        end
        session.compile = result
        if result.code ~= 0 or result.reason then
          session.status = result.reason or "compile error"
          notify()
        else
          execute()
        end
      end
    )
  else
    execute()
  end
  notify()
  return session
end

return M
