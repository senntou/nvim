-- transparent keymap
vim.keymap.set('n', '<leader>t', function() vim.cmd(':TransparentToggle') end, { desc = 'Toggle transparency' })
