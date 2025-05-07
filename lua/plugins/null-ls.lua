return {
  "nvimtools/none-ls.nvim",
  event = "VeryLazy",
  config = function()
    local null_ls = require("null-ls")
    local builtins = require("null-ls.builtins")
    local sources = {
      builtins.formatting.prettier,
      builtins.formatting.black,
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
