vim.keymap.set('n', '<C-_><C-j>', PrevBuffer, { desc = 'Previous buffer' })
vim.keymap.set('n', '<C-_><C-h>', PrevBuffer, { desc = 'Previous buffer' })
vim.keymap.set('n', '<C-_><C-k>', NextBuffer, { desc = 'Next buffer' })
vim.keymap.set('n', '<C-_><C-l>', NextBuffer, { desc = 'Next buffer' })

vim.keymap.set('n', '<C-_><C-d>', ':lua Bdelete()<CR>', { desc = 'Delete buffer' })

vim.api.nvim_set_keymap('n', '<leader>zt', '<cmd>lua toggle_terminal()<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('i', '<leader>zt', '<cmd>lua toggle_terminal()<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('t', '<leader>zt', '<cmd>lua toggle_terminal()<CR>', { noremap = true, silent = true })
