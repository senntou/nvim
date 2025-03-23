require 'cmp'.setup {
  sources = {
    { name = 'nvim_lsp' }
  }
}

-- The nvim-cmp almost supports LSP's capabilities so You should advertise it to LSP servers..
local capabilities = require('cmp_nvim_lsp').default_capabilities()

-- clangdのLSPを用いた補完を有効にする
require('lspconfig').clangd.setup {
  capabilities = capabilities,
  ... -- other lspconfig configs
}


require('lspconfig').phpactor.setup {
  capabilities = capabilities,
  ... -- other lspconfig configs
}
