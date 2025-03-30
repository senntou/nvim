return {
  "neovim/nvim-lspconfig",
  init = function()
    vim.diagnostic.config({
      virtual_text = {
        prefix = "●"
      },
      signs = true,
      underline = true,
    })
  end,
}
