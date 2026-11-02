local M = {}

function M.name(number)
  if not number or number == 0 then
    return nil
  end
  -- Resolve against this host's libuv constants, not Linux-only signal numbers.
  for _, name in ipairs({
    "SIGSEGV",
    "SIGABRT",
    "SIGBUS",
    "SIGFPE",
    "SIGILL",
    "SIGTRAP",
    "SIGKILL",
    "SIGTERM",
    "SIGINT",
    "SIGQUIT",
    "SIGPIPE",
    "SIGALRM",
    "SIGHUP",
    "SIGXCPU",
    "SIGXFSZ",
    "SIGSYS",
    "SIGSTOP",
    "SIGCONT",
    "SIGUSR1",
    "SIGUSR2",
  }) do
    if vim.uv.constants[name] == number then
      return name
    end
  end
  return "signal " .. tostring(number)
end

return M
