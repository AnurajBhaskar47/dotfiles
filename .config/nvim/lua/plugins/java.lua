local java8 = "/Library/Java/JavaVirtualMachines/temurin-8.jdk/Contents/Home"
local java21 = "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"

return {
  {
    "mfussenegger/nvim-jdtls",
    opts = function(_, opts)
      -- JDTLS itself always runs on Java 21, regardless of your shell's JAVA_HOME.
      table.insert(opts.cmd, 2, "--java-executable=" .. java21 .. "/bin/java")

      -- Select the fallback project runtime when launching Neovim.
      local project_java = vim.env.JDTLS_PROJECT_JAVA or "21"
      assert(project_java == "8" or project_java == "21", "JDTLS_PROJECT_JAVA must be 8 or 21")

      opts.settings.java.configuration = {
        runtimes = {
          { name = "JavaSE-1.8", path = java8, default = project_java == "8" },
          { name = "JavaSE-21", path = java21, default = project_java == "21" },
        },
      }
    end,
  },
}
