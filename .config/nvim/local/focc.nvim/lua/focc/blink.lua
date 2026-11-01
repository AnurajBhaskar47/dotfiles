local M = {}
function M.new()
  return setmetatable({}, { __index = M })
end
function M:enabled()
  local cfg = require("focc.config").values
  return cfg ~= nil and cfg.cpp_complete_enabled and vim.bo.filetype == "cpp"
end
function M:get_completions(context, callback)
  local items = {}
  if self:enabled() then
    local prefix = context.line:sub(1, context.cursor[2]):match("[%w_]+$") or ""
    local expanded = require("focc.aids").expand(prefix)
    if expanded and expanded ~= prefix then
      items[1] = {
        label = expanded,
        filterText = prefix,
        insertText = expanded,
        detail = "FOCC: " .. prefix,
        kind = vim.lsp.protocol.CompletionItemKind.Class,
        textEdit = {
          newText = expanded,
          range = {
            start = { line = context.cursor[1] - 1, character = context.cursor[2] - #prefix },
            ["end"] = { line = context.cursor[1] - 1, character = context.cursor[2] },
          },
        },
      }
    end
  end
  callback({ is_incomplete_forward = true, is_incomplete_backward = true, items = items })
end
return M
