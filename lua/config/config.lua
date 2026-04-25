-- 文字コード
vim.o.encoding = "utf-8"
vim.o.fileencoding = "utf-8"

-- clipboard
vim.o.clipboard = "unnamedplus"

vim.o.autoindent = true

-- 行番号
vim.o.number = true
vim.o.shiftwidth = 2
vim.o.tabstop = 2
vim.o.softtabstop = 2

-- インデント
vim.o.expandtab = true
vim.o.smartindent = true

-- cppファイルのコメントアウト
-- luaで書き直す
vim.api.nvim_create_autocmd("FileType", {
  pattern = "cpp",
  callback = function()
    vim.bo.commentstring = "// %s"
  end,
})
-- phpファイルのコメントアウト
vim.api.nvim_create_autocmd("FileType", {
  pattern = "php",
  callback = function()
    vim.bo.commentstring = "// %s"
  end,
})


-- xで削除した文字をクリップボードに保存しない
vim.api.nvim_set_keymap("n", "x", '"_x', { noremap = true, silent = true })
