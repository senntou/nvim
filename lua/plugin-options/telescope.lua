-- telescope keymaps
local builtin = require('telescope.builtin')
vim.keymap.set('n', '<C-f>', builtin.live_grep, { desc = 'Telescope live grep' })
