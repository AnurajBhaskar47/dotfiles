local M = {}

function M.path(source)
  local cfg = require("focc.config").values
  return vim.fs.joinpath(
    vim.fs.dirname(source),
    cfg.tests_relative_dir,
    vim.fs.basename(source) .. cfg.tests_file_suffix
  )
end

local function read(path)
  local file = io.open(path, "rb")
  if not file then
    if vim.uv.fs_stat(path) then
      error("FOCC: cannot read " .. path)
    end
    return nil
  end
  local data = file:read("*a")
  file:close()
  return data
end
M.read = read

function M.validate(tests)
  assert(type(tests) == "table" and vim.islist(tests), "FOCC: tests must be a JSON array")
  for index, test in ipairs(tests) do
    assert(type(test) == "table" and type(test.test) == "string", "FOCC: invalid input in test " .. index)
    for _, key in ipairs({ "correct_answers", "uncorrect_answers" }) do
      if test[key] ~= nil then
        assert(type(test[key]) == "table" and vim.islist(test[key]), "FOCC: invalid " .. key .. " in test " .. index)
        for _, answer in ipairs(test[key]) do
          assert(type(answer) == "string", "FOCC: answers must be strings")
        end
      end
    end
  end
end

function M.load(source)
  local path = M.path(source)
  local raw = read(path)
  local tests = {}
  if raw then
    assert(raw:match("^%s*%["), "FOCC: tests must be a JSON array: " .. path)
    local ok, decoded = pcall(vim.json.decode, raw)
    assert(ok, "FOCC: invalid test JSON: " .. path)
    tests = decoded
  end
  M.validate(tests)
  return { source = source, path = path, tests = tests, original = raw }
end

function M.save(store)
  M.validate(store.tests)
  assert(read(store.path) == store.original, "FOCC: tests changed outside Neovim. Reload before saving.")
  vim.fn.mkdir(vim.fs.dirname(store.path), "p")
  -- Encode the outer array explicitly, including the empty-array case.
  local entries = {}
  for _, test in ipairs(store.tests) do
    local copy = vim.deepcopy(test)
    local encoded = vim.json.encode(copy)
    entries[#entries + 1] = "  " .. encoded
  end
  local data = "[\n" .. table.concat(entries, ",\n") .. "\n]\n"
  local temp = store.path .. ".nvim-" .. vim.uv.os_getpid() .. "-" .. vim.uv.hrtime()
  local fd, err = vim.uv.fs_open(temp, "wx", 384)
  assert(fd, err)
  local written, write_err = vim.uv.fs_write(fd, data, 0)
  vim.uv.fs_fsync(fd)
  vim.uv.fs_close(fd)
  if not written or written ~= #data then
    vim.uv.fs_unlink(temp)
    error(write_err or "FOCC: incomplete test-file write")
  end
  if read(store.path) ~= store.original then
    vim.uv.fs_unlink(temp)
    error("FOCC: tests changed during save. Reload before saving.")
  end
  local ok, rename_err = vim.uv.fs_rename(temp, store.path)
  if not ok then
    vim.uv.fs_unlink(temp)
    error(rename_err)
  end
  store.original = data
end

function M.answer(test, output)
  output = vim.trim(output)
  for _, answer in ipairs(test.correct_answers or {}) do
    if output == answer then
      return "accepted"
    end
  end
  for _, answer in ipairs(test.uncorrect_answers or {}) do
    if output == answer then
      return "rejected"
    end
  end
  if #(test.correct_answers or {}) > 0 then
    return "rejected"
  end
  return "unknown"
end

function M.mark(test, output, correct)
  local value = vim.trim(output)
  local yes = correct and "correct_answers" or "uncorrect_answers"
  local no = correct and "uncorrect_answers" or "correct_answers"
  test[no] = vim.tbl_filter(function(answer)
    return answer ~= value
  end, test[no] or {})
  test[yes] = test[yes] or {}
  if not vim.tbl_contains(test[yes], value) then
    table.insert(test[yes], value)
  end
end

return M
