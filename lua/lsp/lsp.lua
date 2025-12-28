vim.lsp.enable('clangd')
vim.lsp.enable('ts_ls')
vim.lsp.enable('eslint')
vim.lsp.enable('pyright')
vim.lsp.enable('ruff')
vim.lsp.enable('cssls')
-- vim.lsp.enable('phpactor')
vim.lsp.enable('intelephense')
vim.lsp.enable('lua_ls')

-- auto format
-- save時にvim.lsp.buf.format()を実行
-- vim.api.nvim_create_autocmd("BufWritePre", {
--   pattern = "*",
--   callback = function()
--     vim.lsp.buf.format()
--   end
-- })
