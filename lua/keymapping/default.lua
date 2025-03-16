-- 各プラグインのキーマップやターミナルのキーマップは、コンフィグファイルに記載してください
-- ここに記載するのは、Vimのデフォルトのキーマップの設定です



-- :bnext and :bprev
vim.keymap.set('n', '<C-\\><C-j>', function() vim.cmd(':bprev') end, { desc = 'Previous buffer' })
vim.keymap.set('n', '<C-\\><C-h>', function() vim.cmd(':bprev') end, { desc = 'Previous buffer' })
vim.keymap.set('n', '<C-\\><C-k>', function() vim.cmd(':bnext') end, { desc = 'Next buffer' })
vim.keymap.set('n', '<C-\\><C-l>', function() vim.cmd(':bnext') end, { desc = 'Next buffer' })

-- ctrl + hjkl
vim.keymap.set('i', '<C-j>', '<Down>', { noremap = true })
vim.keymap.set('i', '<C-k>', '<Up>', { noremap = true })
vim.keymap.set('i', '<C-h>', '<Left>', { noremap = true })
vim.keymap.set('i', '<C-l>', '<Right>', { noremap = true })

-- split
vim.keymap.set('n', '<C-w><C-l>', '<C-w>v', { noremap = true })
