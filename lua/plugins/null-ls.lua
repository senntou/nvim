return {
  "nvimtools/none-ls.nvim",
  event = "VeryLazy",
  config = function()
    local null_ls = require("null-ls")
    local builtins = require("null-ls.builtins")
    local sources = {
      builtins.formatting.prettier,
      builtins.formatting.black,
      null_ls.builtins.formatting.pg_format,
      -- null_ls.builtins.formatting.phpcsfixer.with {
      --   method = null_ls.methods.FORMATTING,
      --   command = "/Users/wataru.kanegae/workspace/prtimes-dev-docker/web/prtimes-source/dev_php_tools/vendor/bin/php-cs-fixer",
      --   args = {
      --     "fix",
      --     "--config=php_dev_tools/.php-cs-fixer.dist.php",
      --     "$FILENAME",
      --   },
      -- },
      null_ls.builtins.diagnostics.phpcs.with {
        method = null_ls.methods.DIAGNOSTICS_ON_SAVE,
        args = {
          -- "--standard=PSR12",
          -- "--standard=phpcs.xml",
          "--report=json",
          "-q",
          "-s",
          "--runtime-set",
          "ignore_warnings_on_exit",
          "1",
          "--runtime-set",
          "ignore_errors_on_exit",
          "1",
          "--stdin-path=$FILENAME",
          "--basepath=",
        },
      },
      builtins.diagnostics.phpstan.with {
        method = null_ls.methods.DIAGNOSTICS_ON_SAVE,
        to_temp_file = false,
        args = {
          "analyze",
          "--error-format",
          "json",
          "--memory-limit=8G",
          "--no-progress",
          "$FILENAME",
        },
      },
    }
    null_ls.setup {
      sources = sources,
    }
  end,
  dependencies = { "neovim/nvim-lspconfig" },
}
