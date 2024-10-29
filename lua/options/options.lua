vim.o.encoding = "utf-8"
vim.o.fileencoding = "utf-8"
vim.o.clipboard = "unnamedplus"
vim.o.shiftwidth = 2
vim.o.tabstop = 2
vim.o.softtabstop = 2
vim.o.expandtab = true
vim.o.smartindent = true
vim.o.number = true


vim.cmd[[ autocmd FileType cpp setlocal commentstring=//\ %s ]]
vim.cmd[[
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif
]]

