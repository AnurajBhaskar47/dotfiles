local rex_cli = "/Applications/Rex Beta.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"

rex.action{
  name = "copy_mode",
  title = "Copy Mode (Scrollback in nvim)",
  run = function(ctx)
    assert(ctx.session_id and ctx.block_id, "Run Copy Mode from a terminal pane")

    local target, err = rex.session.describe_block{
      block_id = ctx.block_id,
    }
    assert(target, err)

    local script = [[
      set -eu
      f=$(/usr/bin/mktemp -t rex-scrollback)
      trap '/bin/rm -f "$f"' EXIT

      "$3" capture -s "$1" -b "$2" --trim --unwrap > "$f"

      /opt/homebrew/bin/nvim -u NONE -i NONE -n -R + \
        -c 'lua dofile(vim.env.HOME .. "/.config/rex/copy-mode.lua")' \
        "$f"
    ]]

    local layer, layer_err = rex.session.new_layer{
      window_id = assert(target.block.window_id, "Pane must belong to a tab"),
      bounds = { 0, 0, 1, 1 },
      focus = true,
      layout = rex.layout.block{
        flavor = "com.superlogical.terminal.shell",
        options = {
          shell = "none",
          command = {
            "/bin/sh", "-c", script, "rex-copy-mode",
            ctx.session_id, ctx.block_id, rex_cli,
          },
        },
      },
    }
    assert(layer, layer_err)
    return layer
  end,
}

rex.bind("ctrl+q>[", "copy_mode")

