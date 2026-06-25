local home = os.getenv("HOME")

return {
  {
    "mfussenegger/nvim-jdtls",
    ft = { "java" },
    config = function()
      local workspace_folder = home .. ".cache/jdtls/workspace/" .. vim.fn.fnamemodify(vim.fn.getcwd(), ":p:h:t")

      local nvlsp = require "nvchad.configs.lspconfig"

      -- Safely extract the exact launcher jar name matching wildcards
      local launcher_jar = vim.fn.split(vim.fn.glob(home .. "/.local/share/nvim/mason/packages/jdtls/plugins/org.eclipse.equinox.launcher_*.jar"), "\n")[1]

      local lombok_jar = home .. "/.local/share/nvim/mason/packages/jdtls/lombok.jar"

      local config = {
        -- 1. Boot the server using java-21-openjdk
        cmd = {
          "/usr/lib/jvm/java-21-openjdk/bin/java",
          "-javaagent:" .. lombok_jar,
          "-Declipse.application=org.eclipse.jdt.ls.core.id1",
          "-Dosgi.bundles.defaultStartLevel=4",
          "-Declipse.product=org.eclipse.jdt.ls.core.product",
          "-Dlog.level=ALL",
          "-Xmx1G",
          "--add-modules=ALL-SYSTEM",
          "--add-opens", "java.base/java.lang=ALL-UNNAMED",
          "--add-opens", "java.base/java.util=ALL-UNNAMED",

          "-jar", launcher_jar,
          "-configuration", home .. "/.local/share/nvim/mason/packages/jdtls/config_linux",
          "-data", workspace_folder
        },

        root_dir = require("jdtls.setup").find_root({ ".git", "pom.xml" }),
        -- 2. Compile, check syntax, and run compilations matching Java 8 specs
        settings = {
          java = {
            configuration = {
              runtimes = {
                {
                  name = "JavaSE-21",
                  path = "/usr/lib/jvm/java-21-openjdk",
                  default = true,
                },
              },
            },
          },
        },

        -- Keep Nvtext UI attachments intact
        on_attach = nvlsp.on_attach,
        on_init = nvlsp.on_init,
        capabilities = nvlsp.capabilities,
      }

      -- Run JDTLS setup on java files
      require("jdtls").start_or_attach(config)
    end,
  }
}

