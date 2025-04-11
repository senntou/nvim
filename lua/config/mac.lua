vim.keymap.set('n', 'zh', Prev_buffer, { desc = 'Previous buffer' })
vim.keymap.set('n', 'zl', Next_buffer, { desc = 'Next buffer' })
vim.keymap.set('n', 'zd', ':lua Bdelete()<CR>', { desc = 'Delete buffer' })
vim.api.nvim_set_keymap('n', 'zt', '<cmd>lua toggle_terminal()<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('i', 'zt', '<cmd>lua toggle_terminal()<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('t', 'zt', '<cmd>lua toggle_terminal()<CR>', { noremap = true, silent = true })

vim.keymap.set('n', '<C-_><C-j>', Prev_buffer, { desc = 'Previous buffer' })
vim.keymap.set('n', '<C-_><C-h>', Prev_buffer, { desc = 'Previous buffer' })
vim.keymap.set('n', '<C-_><C-k>', Next_buffer, { desc = 'Next buffer' })
vim.keymap.set('n', '<C-_><C-l>', Next_buffer, { desc = 'Next buffer' })

vim.keymap.set('n', '<C-_><C-d>', ':lua Bdelete()<CR>', { desc = 'Delete buffer' })
