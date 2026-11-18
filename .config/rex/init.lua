rex.bind("ctrl+q>h", "pane.focus.left")
rex.bind("ctrl+q>j", "pane.focus.down")
rex.bind("ctrl+q>k", "pane.focus.up")
rex.bind("ctrl+q>l", "pane.focus.right")

rex.mode("resize", { exclusive = true })
rex.bind("cmd+r", "client.mode.enter", { name = "resize" })

rex.bind("resize/h",  "pane.resize", { direction = "left" })
rex.bind("resize/j",  "pane.resize", { direction = "down" })
rex.bind("resize/k",    "pane.resize", { direction = "up" })
rex.bind("resize/l", "pane.resize", { direction = "right" })
rex.bind("resize/=", "pane.balance")
