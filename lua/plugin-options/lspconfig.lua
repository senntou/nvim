-- 補完を有効にするためのオプション
local capabilities = require('cmp_nvim_lsp').default_capabilities()

-- C言語関連のLSPについての設定
-- compile_commandsや.gitが無いプロジェクトでは動かない
require 'lspconfig'.clangd.setup {
  cmd = { "clangd", "--background-index" },
  filetypes = { "c", "cpp", "objc", "objcpp" },
  root_dir = require 'lspconfig'.util.root_pattern("compile_commands.json", "compile_flags.txt", ".git"),
  init_options = {
    clangdFileStatus = true
  },
  capabilities = capabilities
}

-- typescript
require "lspconfig".ts_ls.setup {
  cmd = { "typescript-language-server", "--stdio" },
  filetypes = { "javascript", "javascriptreact", "javascript.jsx", "typescript", "typescriptreact", "typescript.tsx" },
  root_dir = require 'lspconfig'.util.root_pattern("package.json", "tsconfig.json", ".git"),
  capabilities = capabilities
}
require "lspconfig".eslint.setup {
  cmd = { "eslint_d", "--stdio" },
  filetypes = { "javascript", "javascriptreact", "javascript.jsx", "typescript", "typescriptreact", "typescript.tsx" },
  root_dir = require 'lspconfig'.util.root_pattern("package.json", ".git"),
  capabilities = capabilities
}

-- css
require "lspconfig".cssls.setup {
  cmd = { "vscode-css-language-server", "--stdio" },
  filetypes = { "css", "scss", "less" },
  root_dir = require 'lspconfig'.util.root_pattern("package.json", ".git"),
  capabilities = capabilities
}

-- php phpactor
require "lspconfig".phpactor.setup {
  cmd = { "phpactor", "language-server" },
  filetypes = { "php" },
  root_dir = require 'lspconfig'.util.root_pattern("composer.json", ".git"),
  capabilities = capabilities
}

-- auto format
-- save時にvim.lsp.buf.format()を実行
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*",
  callback = function()
    vim.lsp.buf.format()
  end
})

-- lua
require 'lspconfig'.lua_ls.setup({
  on_init = function(client)
    if client.workspace_folders then
      local path = client.workspace_folders[1].name
      if path ~= vim.fn.stdpath('config') and (vim.loop.fs_stat(path .. '/.luarc.json') or vim.loop.fs_stat(path .. '/.luarc.jsonc')) then
        return
      end
    end

    client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua, {
      runtime = {
        version = 'LuaJIT'
      },
      workspace = {
        checkThirdParty = false,
        library = {
          vim.env.VIMRUNTIME
        }
      }
    })
  end,
  settings = {
    Lua = {}
  }
})
