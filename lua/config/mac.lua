vim.keymap.set('n', 'zh', PrevBuffer, { desc = 'Previous buffer' })
vim.keymap.set('n', 'zl', NextBuffer, { desc = 'Next buffer' })
vim.keymap.set('n', 'zd', ':lua Bdelete()<CR>', { desc = 'Delete buffer' })
vim.api.nvim_set_keymap('n', 'zt', '<cmd>lua toggle_terminal()<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('i', 'zt', '<cmd>lua toggle_terminal()<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('t', 'zt', '<cmd>lua toggle_terminal()<CR>', { noremap = true, silent = true })

vim.keymap.set('n', '<C-_><C-j>', PrevBuffer, { desc = 'Previous buffer' })
vim.keymap.set('n', '<C-_><C-h>', PrevBuffer, { desc = 'Previous buffer' })
vim.keymap.set('n', '<C-_><C-k>', NextBuffer, { desc = 'Next buffer' })
vim.keymap.set('n', '<C-_><C-l>', NextBuffer, { desc = 'Next buffer' })

vim.keymap.set('n', '<C-_><C-d>', ':lua Bdelete()<CR>', { desc = 'Delete buffer' })
