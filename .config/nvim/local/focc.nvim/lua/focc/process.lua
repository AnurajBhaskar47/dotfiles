local M = {}

function M.command(template, source, args)
  if not template or template == false then
    return nil
  end
  local values = {
    file = vim.fs.basename(source),
    source_file = source,
    source_file_dir = vim.fs.dirname(source),
    file_name = vim.fn.fnamemodify(source, ":t:r"),
  }
  args = args or require("focc.config").values.run_args
  if type(template) == "string" then
    assert(require("focc.config").values.allow_shell, "FOCC: shell commands are disabled")
    local quoted = {}
    for _, arg in ipairs(args) do
      quoted[#quoted + 1] = vim.fn.shellescape(arg)
    end
    -- String templates retain the original user-supplied quoting convention.
    local text = template:gsub("{([%w_]+)}", function(key)
      return key == "args" and table.concat(quoted, " ") or assert(values[key], "unknown placeholder " .. key)
    end)
    return { vim.o.shell, "-c", text }
  end
  local cmd = {}
  for _, arg in ipairs(template) do
    if arg == "{args}" then
      vim.list_extend(cmd, args)
    else
      cmd[#cmd + 1] = arg:gsub("{([%w_]+)}", function(key)
        return assert(values[key], "unknown placeholder " .. key)
      end)
    end
  end
  return cmd
end

function M.start(cmd, opts, callback)
  opts = opts or {}
  local cfg = require("focc.config").values
  local task = { cancelled = false, stdout = "", stderr = "", bytes = 0 }
  local started = vim.uv.hrtime()
  local finished = false
  local function stop(reason)
    if finished then
      return
    end
    task.reason = reason
    if task.pid and vim.fn.has("unix") == 1 and task.group then
      local killed = vim.uv.kill(-task.pid, 9)
      if not killed and task.job then
        task.job:kill(9)
      end
    elseif task.job then
      task.job:kill(9)
    end
  end
  function task:cancel()
    self.cancelled = true
    stop("cancelled")
  end
  function task:send(text)
    if not finished then
      self.job:write(text)
    end
  end
  function task:eof()
    if not finished then
      self.job:write(nil)
    end
  end
  local function receive(stream, err, data)
    if err then
      task.stderr = task.stderr .. tostring(err)
    end
    if not data then
      return
    end
    local room = math.max(0, cfg.output_limit - task.bytes)
    task[stream] = task[stream] .. data:sub(1, room)
    task.bytes = task.bytes + #data
    if task.bytes > cfg.output_limit then
      stop("output limit")
    end
    if opts.on_output then
      vim.schedule(function()
        if not finished then
          opts.on_output(task)
        end
      end)
    end
  end
  local launch = vim.deepcopy(cmd)
  -- A private process group lets cancellation terminate shell children as well.
  if vim.fn.has("unix") == 1 and vim.fn.executable("setsid") == 1 then
    table.insert(launch, 1, "--")
    table.insert(launch, 1, "setsid")
    task.group = true
  end
  local ok, job = pcall(vim.system, launch, {
    cwd = opts.cwd,
    text = true,
    stdin = opts.interactive and true or opts.input,
    stdout = function(err, data)
      receive("stdout", err, data)
    end,
    stderr = function(err, data)
      receive("stderr", err, data)
    end,
  }, function(result)
    finished = true
    if task.timer then
      task.timer:stop()
      task.timer:close()
    end
    task.code, task.signal = result.code, result.signal
    task.time_ms = (vim.uv.hrtime() - started) / 1e6
    vim.schedule(function()
      callback(task)
    end)
  end)
  if not ok then
    task.code, task.stderr, task.time_ms = -1, tostring(job), 0
    finished = true
    vim.schedule(function()
      callback(task)
    end)
    return task
  end
  task.job, task.pid = job, job.pid
  task.timer = vim.uv.new_timer()
  task.timer:start(opts.timeout_ms or cfg.run_timeout_ms, 0, function()
    stop("timeout")
  end)
  return task
end

return M
