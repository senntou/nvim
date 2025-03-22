return {
  "nvimtools/none-ls.nvim",
  config = function()
    local null_ls = require("null-ls")
    local builtins = require("null-ls.builtins")
    local sources = {
      builtins.diagnostics.phpstan
    }
    null_ls.setup {
      sources = sources
    }
  end,
  dependencies = { "neovim/nvim-lspconfig" },
}
