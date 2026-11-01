local M = {}
local process = require("focc.process")

function M.find(source, suffix)
  local name = vim.fn.fnamemodify(source, ":t:r") .. suffix
  local found
  for _, lang in ipairs(require("focc.config").values.run_settings) do
    for _, ext in ipairs(lang.extensions) do
      local path = vim.fs.joinpath(vim.fs.dirname(source), name .. "." .. ext)
      if vim.uv.fs_stat(path) then
        assert(not found, "FOCC: conflicting stress sources for " .. name)
        found = path
      end
    end
  end
  assert(found, "FOCC: missing " .. name)
  return found
end

function M.stop()
  if M.session then
    M.session.stopped = true
    if M.session.task then
      M.session.task:cancel()
    end
  end
end

function M.start(source)
  local cfg = require("focc.config").values
  local paths = { M.find(source, "__Generator"), M.find(source, "__Good"), source }
  M.stop()
  local session = { iteration = 0, stopped = false }
  M.session = session
  local buf = vim.api.nvim_create_buf(false, true)
  session.buf = buf
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "focc"
  vim.b[buf].focc_source = source
  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.keymap.set("n", "x", M.stop, { buffer = buf })
  local function log(message)
    if not vim.api.nvim_buf_is_valid(buf) then
      M.stop()
      return
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(message, "\n", { plain = true }))
    vim.bo[buf].modifiable = false
  end
  local function invoke(path, template, input, timeout, callback)
    session.task = process.start(process.command(template, path), {
      input = input,
      cwd = vim.fs.dirname(path),
      timeout_ms = timeout,
    }, function(result)
      if session.stopped or M.session ~= session then
        log("Stress stopped")
        return
      end
      if result.code ~= 0 or result.reason then
        log(
          string.format(
            "Stress failed: %s\nSeed: %s\n%s\nInput:\n%s\nStdout:\n%s\nStderr:\n%s",
            path,
            session.seed or "compile",
            result.reason or ("exit " .. result.code),
            input or "",
            result.stdout,
            result.stderr
          )
        )
        session.stopped = true
        return
      end
      callback(result.stdout)
    end)
  end
  local function iteration()
    if session.stopped then
      return
    end
    if cfg.stress_iterations > 0 and session.iteration >= cfg.stress_iterations then
      log("Stress passed " .. session.iteration .. " tests")
      return
    end
    session.iteration = session.iteration + 1
    session.seed = tostring(math.random(0, 1000000000))
    log("Stress test " .. session.iteration .. " | seed " .. session.seed .. " | x:stop")
    invoke(
      paths[1],
      require("focc.config").language(paths[1]).run_cmd,
      session.seed,
      cfg.stress_time_limit_seconds * 1000,
      function(input)
        invoke(
          paths[2],
          require("focc.config").language(paths[2]).run_cmd,
          input,
          cfg.stress_time_limit_seconds * 1000,
          function(good)
            invoke(
              paths[3],
              require("focc.config").language(paths[3]).run_cmd,
              input,
              cfg.stress_time_limit_seconds * 1000,
              function(bad)
                if vim.trim(good) ~= vim.trim(bad) then
                  session.stopped = true
                  session.failure =
                    { test = input, correct_answers = { vim.trim(good) }, uncorrect_answers = { vim.trim(bad) } }
                  log(
                    "Different output | seed "
                      .. session.seed
                      .. "\nInput:\n"
                      .. input
                      .. "\nReference:\n"
                      .. good
                      .. "\nCandidate:\n"
                      .. bad
                  )
                else
                  vim.schedule(iteration)
                end
              end
            )
          end
        )
      end
    )
  end
  local function compile(i)
    if not paths[i] then
      iteration()
      return
    end
    local path = paths[i]
    local cmd = require("focc.config").language(path).compile_cmd
    if not cmd then
      compile(i + 1)
      return
    end
    log("Compiling " .. path)
    invoke(path, cmd, nil, cfg.compile_timeout_ms, function()
      compile(i + 1)
    end)
  end
  compile(1)
  return session
end

return M
