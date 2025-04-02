vim.keymap.set('n', 'zh', Prev_buffer, { desc = 'Previous buffer' })
vim.keymap.set('n', 'zl', Next_buffer, { desc = 'Next buffer' })
vim.keymap.set('n', 'zd', ':lua Bdelete()<CR>', { desc = 'Delete buffer' })
