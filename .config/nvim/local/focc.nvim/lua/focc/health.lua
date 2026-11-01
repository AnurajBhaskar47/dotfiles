local M = {}
function M.check()
  vim.health.start("FastOlympicCoding")
  local cfg = require("focc.config").values
  if not cfg then
    vim.health.error("FOCC setup did not run")
    return
  end
  vim.health.ok("Native Lua configuration loaded; Sublime settings are not read")
  for _, lang in ipairs(cfg.run_settings) do
    for _, field in ipairs({ "compile_cmd", "run_cmd" }) do
      local cmd = lang[field]
      if type(cmd) == "table" then
        if cmd[1]:match("^{") or cmd[1]:match("^%./") then
          vim.health.info(lang.name .. " " .. field .. ": generated executable")
        elseif vim.fn.executable(cmd[1]) == 1 then
          vim.health.ok(cmd[1] .. " is available")
        else
          vim.health.warn(cmd[1] .. " is missing")
        end
      end
    end
  end
  if vim.fn.executable("setsid") == 1 then
    vim.health.ok("Process-group cancellation is available")
  else
    vim.health.warn("setsid is missing; cancellation cannot reliably terminate child processes")
  end
  local companion = require("focc.companion")
  vim.health.info("Competitive Companion port: " .. cfg.companion.port .. " (loopback only)")
  if companion.server then
    vim.health.ok("Receiver active: " .. companion.root)
  else
    vim.health.info("Start imports with :Focc receive [directory]")
  end
  vim.health.info("Codeforces submission is not implemented")
  vim.health.info(
    "Debugging requires a user-configured nvim-dap adapter; test stdin requires codelldb-compatible stdio"
  )
end
return M
