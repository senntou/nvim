-- 文字コード
vim.o.encoding = "utf-8"
vim.o.fileencoding = "utf-8"

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
vim.cmd[[ autocmd FileType cpp setlocal commentstring=//\ %s ]]

-- NERDTreeが最後のウィンドウになったら閉じる
vim.cmd[[
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif
]]

