-- 文字コード
vim.o.encoding = "utf-8"
vim.o.fileencoding = "utf-8"

if vim.fn.has("mac") == 1 then
  vim.g.mapleader = "_"
end

-- clipboard
vim.o.clipboard = "unnamedplus"

-- 行番号
vim.o.number = true
vim.o.shiftwidth = 2
vim.o.tabstop = 2
vim.o.softtabstop = 2

-- インデント
vim.o.expandtab = true
vim.o.smartindent = true

-- cppファイルのコメントアウト
vim.cmd [[ autocmd FileType cpp setlocal commentstring=//\ %s ]]
-- phpファイルのコメントアウト
vim.cmd [[ autocmd FileType php setlocal commentstring=//\ %s ]]

-- xで削除した文字をクリップボードに保存しない
vim.api.nvim_set_keymap("n", "x", '"_x', { noremap = true, silent = true })
