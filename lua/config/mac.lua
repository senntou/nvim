vim.keymap.set('n', '<C-_><C-j>', PrevBuffer, { desc = 'Previous buffer' })
vim.keymap.set('n', '<C-_><C-h>', PrevBuffer, { desc = 'Previous buffer' })
vim.keymap.set('n', '<C-_><C-k>', NextBuffer, { desc = 'Next buffer' })
vim.keymap.set('n', '<C-_><C-l>', NextBuffer, { desc = 'Next buffer' })

vim.keymap.set('n', '<C-_><C-d>', ':lua Bdelete()<CR>', { desc = 'Delete buffer' })
