local M = { clients = {}, batches = {} }
local uv = vim.uv
local store = require("focc.store")

local function slug(text)
  return (text:gsub("[^%w_-]", "_"):gsub("_+", "_"):sub(1, 100))
end

local function problem_path(payload)
  local host, route = payload.url:match("^https?://([^/]+)(/[^?#]*)")
  host = host and host:lower():gsub("^www%.", "")
  local contest, problem
  if host == "codeforces.com" then
    contest, problem = route:match("^/contest/(%d+)/problem/([%w]+)/*$")
    if not contest then
      contest, problem = route:match("^/problemset/problem/(%d+)/([%w]+)/*$")
    end
    if not contest then
      contest, problem = route:match("^/gym/(%d+)/problem/([%w]+)/*$")
    end
    assert(contest, "FOCC: unsupported Codeforces problem URL")
  elseif host == "atcoder.jp" then
    local task
    contest, task = route:match("^/contests/([%w_-]+)/tasks/([%w_-]+)/*$")
    assert(contest, "FOCC: unsupported AtCoder problem URL")
    -- Older and shared tasks can have numeric or unrelated task slugs.
    -- Prefer a standard letter suffix, then the displayed task label.
    problem = task:match("_([a-zA-Z])$") or payload.name:match("^([%w]+)%s*%-") or task
    if #problem == 1 then
      problem = problem:upper()
    end
  elseif host == "codechef.com" then
    local kind
    contest, kind, problem = route:match("^/([%w_-]+)/([%w-]+)/([%w_-]+)/*$")
    if not contest then
      kind, problem = route:match("^/([%w-]+)/([%w_-]+)/*$")
    end
    assert(
      problem and (kind == "problems" or kind == "problems-old" or kind == "submit"),
      "FOCC: unsupported CodeChef problem URL"
    )
    if not contest then
      -- Companion can supply the original contest code for practice URLs.
      -- Do not mistake display titles or syllabus names for contest IDs.
      local category = type(payload.group) == "string" and payload.group:match("^CodeChef%s*%-%s*(.-)%s*$")
      contest = category and category:match("^[A-Z0-9_-]+$") and category or "Practice"
    end
    if contest:upper() == "PRACTICE" then
      contest = "Practice"
    end
  else
    contest = slug(type(payload.group) == "string" and payload.group or "Problems")
    problem = slug(payload.name)
  end
  assert(contest ~= "" and problem ~= "", "FOCC: invalid problem path")
  return contest, problem
end

local function directory(path)
  -- Do not follow symlinks in generated paths (including .focc).
  local current = "/"
  for part in path:gmatch("[^/]+") do
    assert(part ~= "..", "FOCC: invalid import path")
    current = vim.fs.joinpath(current, part)
    local stat = uv.fs_lstat(current)
    if stat then
      assert(stat.type == "directory", "FOCC: import directory is not a regular directory: " .. current)
    else
      assert(uv.fs_mkdir(current, 493))
    end
  end
end

local function create(path, content)
  local stat = uv.fs_lstat(path)
  if stat then
    assert(stat.type == "file", "FOCC: refusing non-file import target: " .. path)
    return false
  end
  local fd, err = uv.fs_open(path, "wx", 420)
  assert(fd, err)
  local count, write_err = uv.fs_write(fd, content, 0)
  uv.fs_close(fd)
  assert(count == #content, write_err or "FOCC: incomplete import write")
  return true
end

function M.import(payload, root)
  local cfg = require("focc.config").values
  assert(
    type(payload) == "table" and type(payload.name) == "string" and payload.name ~= "",
    "FOCC: missing problem name"
  )
  assert(type(payload.url) == "string" and #payload.url <= 4096, "FOCC: missing problem URL")
  assert(type(payload.tests) == "table" and vim.islist(payload.tests), "FOCC: samples must be an array")
  local samples = {}
  for _, sample in ipairs(payload.tests) do
    assert(
      type(sample) == "table" and type(sample.input) == "string" and type(sample.output) == "string",
      "FOCC: invalid sample"
    )
    samples[#samples + 1] =
      { test = sample.input, correct_answers = { vim.trim(sample.output) }, uncorrect_answers = {} }
  end
  local batch = payload.batch
  if batch then
    assert(
      type(batch) == "table"
        and type(batch.id) == "string"
        and #batch.id <= 128
        and type(batch.size) == "number"
        and batch.size % 1 == 0
        and batch.size > 0
        and batch.size <= 1000,
      "FOCC: invalid batch"
    )
  end
  local contest, problem = problem_path(payload)
  local dest = vim.fs.joinpath(root, contest)
  local source = vim.fs.joinpath(dest, problem .. "." .. cfg.companion.extension)
  local active = require("focc.runner").sessions[source]
  assert(
    not active or not vim.tbl_contains({ "running", "compiling", "interactive" }, active.status),
    "FOCC: stop the active test run before importing"
  )
  directory(dest)
  directory(vim.fs.dirname(store.path(source)))
  local test_stat = uv.fs_lstat(store.path(source))
  assert(not test_stat or test_stat.type == "file", "FOCC: refusing non-file test target")
  local data = store.load(source)
  local added = 0
  for _, sample in ipairs(samples) do
    local duplicate = false
    for _, existing in ipairs(data.tests) do
      if
        existing.test == sample.test and vim.tbl_contains(existing.correct_answers or {}, sample.correct_answers[1])
      then
        duplicate = true
        break
      end
    end
    if not duplicate then
      data.tests[#data.tests + 1] = sample
      added = added + 1
    end
  end
  create(source, cfg.companion.template)
  if added > 0 or data.original == nil then
    store.save(data)
  end
  -- Metadata is separate from the Sublime-compatible tests; do not overwrite it.
  create(store.path(source) .. ":problem.json", vim.json.encode({
    name = payload.name,
    url = payload.url,
    group = payload.group,
    timeLimit = payload.timeLimit,
    memoryLimit = payload.memoryLimit,
    interactive = payload.interactive,
    batch = payload.batch,
  }) .. "\n")
  if active then
    active.store, active.results, active.status = data, {}, "ready"
    require("focc.ui").render(active)
  end
  return { source = source, added = added, batch = batch, url = payload.url }
end

function M.stop()
  if M.server then
    M.server:close()
    M.server = nil
  end
  for client, close in pairs(M.clients) do
    close()
  end
  M.clients, M.batches = {}, {}
end

function M.start(root)
  assert(not M.server, "FOCC: receiver already running; use :Focc stop_receive first")
  root = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(root or vim.fn.getcwd()), ":p"))
  directory(root)
  local cfg = require("focc.config").values.companion
  local server = uv.new_tcp()
  local bound, bind_err = server:bind("127.0.0.1", cfg.port)
  if not bound then
    server:close()
    error("FOCC: cannot bind port " .. cfg.port .. ": " .. tostring(bind_err))
  end
  local listening, listen_err = server:listen(16, function(err)
    if err then
      return
    end
    local client = uv.new_tcp()
    if not server:accept(client) then
      client:close()
      return
    end
    local count = 0
    for _ in pairs(M.clients) do
      count = count + 1
    end
    if count >= 16 then
      client:close()
      return
    end
    local timer = uv.new_timer()
    local closed, handled = false, false
    local function close()
      if closed then
        return
      end
      closed = true
      M.clients[client] = nil
      timer:stop()
      timer:close()
      client:read_stop()
      client:close()
    end
    M.clients[client] = close
    timer:start(10000, 0, close)
    local function reply(status, body)
      if closed then
        return
      end
      client:read_stop()
      client:write(
        "HTTP/1.1 "
          .. status
          .. "\r\nContent-Type: text/plain\r\nConnection: close\r\nContent-Length: "
          .. #body
          .. "\r\n\r\n"
          .. body,
        close
      )
    end
    local buffer, header_end, length = "", nil, nil
    client:read_start(function(read_err, chunk)
      if read_err or not chunk then
        close()
        return
      end
      if handled then
        return
      end
      buffer = buffer .. chunk
      if #buffer > cfg.max_request_bytes + 8192 then
        handled = true
        reply("413 Payload Too Large", "Request too large")
        return
      end
      if not header_end then
        header_end = buffer:find("\r\n\r\n", 1, true)
        if not header_end then
          if #buffer > 8192 then
            handled = true
            reply("431 Request Header Fields Too Large", "Headers too large")
          end
          return
        end
        if header_end > 8192 then
          handled = true
          reply("431 Request Header Fields Too Large", "Headers too large")
          return
        end
        local header = buffer:sub(1, header_end - 1)
        if not header:match("^POST / HTTP/1%.[01]\r\n") then
          handled = true
          reply("405 Method Not Allowed", "Use POST /")
          return
        end
        local lengths = {}
        for line in header:gmatch("[^\r\n]+") do
          local key, value = line:match("^([^:]+):%s*(.-)%s*$")
          if key and key:lower() == "transfer-encoding" then
            handled = true
            reply("400 Bad Request", "Chunked requests unsupported")
            return
          end
          if key and key:lower() == "content-length" then
            lengths[#lengths + 1] = value
          end
        end
        if #lengths ~= 1 or not lengths[1]:match("^%d+$") then
          handled = true
          reply("400 Bad Request", "One Content-Length required")
          return
        end
        length = tonumber(lengths[1])
        if length > cfg.max_request_bytes then
          handled = true
          reply("413 Payload Too Large", "Request too large")
          return
        end
      end
      if #buffer < header_end + 3 + length then
        return
      end
      handled = true
      client:read_stop()
      local body = buffer:sub(header_end + 4, header_end + 3 + length)
      vim.schedule(function()
        if closed then
          return
        end
        local success, result = pcall(function()
          return M.import(vim.json.decode(body), root)
        end)
        if not success then
          reply("400 Bad Request", "Import failed")
          vim.notify(tostring(result), vim.log.levels.ERROR)
          return
        end
        reply("200 OK", "Imported")
        local progress = ""
        if result.batch then
          local id = result.batch.id
          if not M.batches[id] then
            local total = 0
            for _ in pairs(M.batches) do
              total = total + 1
            end
            if total >= 128 then
              M.batches = {}
            end
            M.batches[id] = {}
          end
          M.batches[id][result.url] = true
          local received = 0
          for _ in pairs(M.batches[id]) do
            received = received + 1
          end
          progress = string.format(" | batch %d/%d", received, result.batch.size)
        end
        vim.notify(string.format("FOCC: %s | %d new samples%s", result.source, result.added, progress))
      end)
    end)
  end)
  if not listening then
    server:close()
    error(tostring(listen_err))
  end
  M.server, M.root = server, root
  vim.notify(
    "FOCC: listening on 127.0.0.1:" .. cfg.port .. " → " .. root .. ". Click Competitive Companion's plus button."
  )
end

return M
