local M = {}
local runner = require("focc.runner")
local store = require("focc.store")
local ui = require("focc.ui")

local function source()
  local path = vim.b.focc_source or vim.api.nvim_buf_get_name(0)
  assert(path ~= "" and not path:match("^%w+://"), "FOCC: open a source file first")
  path = vim.fn.fnamemodify(path, ":p")
  require("focc.config").language(path)
  return path
end

local function save_source(path)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.bo[buf].modified and require("focc.config").values.save_before_run then
    vim.api.nvim_buf_call(buf, function()
      vim.cmd.write()
    end)
  end
end

local function data_for(path)
  local session = runner.sessions[path]
  if not session then
    session = { source = path, store = store.load(path), results = {}, status = "ready" }
    runner.sessions[path] = session
  end
  return session
end

local function choose(session, index, callback)
  if index then
    assert(session.store.tests[index], "FOCC: invalid test number")
    callback(index)
    return
  end
  local choices = {}
  for i in ipairs(session.store.tests) do
    choices[#choices + 1] = i
  end
  assert(#choices > 0, "FOCC: no tests")
  vim.ui.select(choices, { prompt = "FOCC test" }, function(i)
    if i then
      local ok, err = pcall(callback, i)
      if not ok then
        vim.notify(tostring(err), vim.log.levels.ERROR)
      end
    end
  end)
end

function M.action(action, index)
  local ok, err = pcall(function()
    if action == "receive" then
      require("focc.companion").start(index)
      return
    end
    if action == "stop_receive" then
      require("focc.companion").stop()
      return
    end
    local path = source()
    if action == "run_all" or action == "interactive" then
      save_source(path)
      runner.run(path, nil, ui.show, action == "interactive")
      return
    end
    if action == "stress" then
      save_source(path)
      require("focc.stress").start(path)
      return
    end
    if action == "stop_stress" then
      require("focc.stress").stop()
      return
    end
    if action == "snippets" then
      require("focc.aids").pick_snippet()
      return
    end
    if action == "lint" then
      require("focc.aids").lint(vim.fn.bufnr(path))
      return
    end
    if vim.tbl_contains({ "debug", "debug_input_file", "debug_no_input" }, action) then
      save_source(path)
      require("focc.debug").start(path, index, action)
      return
    end
    local session = data_for(path)
    if
      vim.tbl_contains(
        { "add", "edit", "delete", "clear", "move_up", "move_down", "reload", "accept", "reject", "save_interactive" },
        action
      )
    then
      assert(
        not vim.tbl_contains({ "running", "compiling", "interactive" }, session.status),
        "FOCC: stop the current process before editing tests"
      )
    end
    local function refresh()
      ui.show(session)
    end
    if action == "show" then
      refresh()
    elseif action == "stop" then
      runner.stop(session)
      session.status = "cancelled"
      refresh()
    elseif action == "reload" then
      assert(not session.task or session.status ~= "running", "FOCC: stop the run before reloading")
      session.store, session.results = store.load(path), {}
      refresh()
    elseif action == "add" then
      ui.edit(path, session.store, nil, refresh)
    elseif action == "send" then
      assert(session.status == "interactive", "FOCC: no interactive process")
      vim.ui.input({ prompt = "Input line: " }, function(value)
        if value ~= nil and session.status == "interactive" then
          session.input = session.input .. value .. "\n"
          session.task:send(value .. "\n")
          refresh()
        end
      end)
    elseif action == "eof" then
      assert(session.status == "interactive", "FOCC: no interactive process")
      session.task:eof()
    elseif action == "save_interactive" then
      assert(session.input ~= nil, "FOCC: no captured interactive input")
      local test = { test = session.input }
      local candidate = vim.deepcopy(session.store)
      table.insert(candidate.tests, test)
      store.save(candidate)
      session.store = candidate
      refresh()
    elseif action == "clear" then
      vim.ui.select(
        { "Cancel", "Clear all tests" },
        { prompt = "Delete all tests for " .. vim.fs.basename(path) .. "?" },
        function(value)
          if value == "Clear all tests" then
            local saved, failure = pcall(function()
              local candidate = vim.deepcopy(session.store)
              candidate.tests = {}
              store.save(candidate)
              session.store = candidate
              session.results = {}
              refresh()
            end)
            if not saved then
              vim.notify(tostring(failure), vim.log.levels.ERROR)
            end
          end
        end
      )
    else
      choose(session, index, function(i)
        if action == "run" then
          save_source(path)
          runner.run(path, i, ui.show)
        elseif action == "edit" then
          ui.edit(path, session.store, i, refresh)
        else
          local candidate = vim.deepcopy(session.store)
          if action == "delete" then
            table.remove(candidate.tests, i)
          elseif action == "accept" or action == "reject" then
            assert(session.results[i], "FOCC: run this test first")
            store.mark(candidate.tests[i], session.results[i].stdout, action == "accept")
          elseif action == "move_up" or action == "move_down" then
            local j = i + (action == "move_up" and -1 or 1)
            if not candidate.tests[j] then
              return
            end
            candidate.tests[i], candidate.tests[j] = candidate.tests[j], candidate.tests[i]
          else
            error("FOCC: unknown action " .. action)
          end
          store.save(candidate)
          session.store = candidate
          if action == "accept" or action == "reject" then
            session.results[i].answer = store.answer(candidate.tests[i], session.results[i].stdout)
          else
            session.results = {}
          end
          refresh()
        end
      end)
    end
  end)
  if not ok then
    vim.notify(tostring(err), vim.log.levels.ERROR)
  end
end

function M.setup(opts)
  require("focc.config").setup(opts)
  require("focc.aids").setup()
  local actions = {
    "run_all",
    "run",
    "show",
    "reload",
    "add",
    "edit",
    "delete",
    "clear",
    "accept",
    "reject",
    "move_up",
    "move_down",
    "stop",
    "interactive",
    "send",
    "eof",
    "save_interactive",
    "stress",
    "stop_stress",
    "snippets",
    "lint",
    "debug",
    "debug_input_file",
    "debug_no_input",
    "receive",
    "stop_receive",
  }
  vim.api.nvim_create_user_command("Focc", function(command)
    local action = command.fargs[1] or "run_all"
    M.action(action, action == "receive" and command.args:match("^receive%s+(.+)$") or tonumber(command.fargs[2]))
  end, {
    nargs = "*",
    complete = function(prefix)
      return vim.tbl_filter(function(item)
        return vim.startswith(item, prefix)
      end, actions)
    end,
    desc = "FastOlympicCoding commands",
  })
  local group = vim.api.nvim_create_augroup("FoccLifecycle", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for _, session in pairs(runner.sessions) do
        runner.stop(session)
      end
      require("focc.stress").stop()
      require("focc.debug").cleanup()
      require("focc.companion").stop()
    end,
  })
end

return M
