return {
  "nvimtools/none-ls.nvim",
  event = "VeryLazy",
  config = function()
    local null_ls = require("null-ls")
    local builtins = require("null-ls.builtins")
    local sources = {
      builtins.diagnostics.phpstan,
      builtins.formatting.prettier,
      builtins.formatting.black,
    }
    null_ls.setup {
      sources = sources,
    }
  end,
  dependencies = { "neovim/nvim-lspconfig" },
}
