vim.cmd([[
    inoremap <silent><expr> <TAB>
    \ coc#pum#visible() ? coc#_select_confirm() :
    \ coc#expandableOrJumpable() ?
    \ "\<C-r>=coc#rpc#request('doKeymap', ['snippets-expand-jump',''])\<CR>" :
    \ CheckBackspace() ? "\<TAB>" :
    \ coc#refresh()

    noremap <C-n> :NERDTreeToggle<CR>
    noremap <C-e> :NERDTreeFind<CR>

    function! CheckBackspace() abort
    let col = col('.') - 1
    return !col || getline('.')[col - 1]  =~# '\s'
    endfunction
]])

local builtin = require('telescope.builtin')
vim.keymap.set('n', '<C-p>', builtin.find_files, { desc = 'Telescope find files' })
vim.keymap.set('n', '<C-f>', builtin.live_grep, { desc = 'Telescope live grep' })

vim.keymap.set('n', '<leader>t', function() vim.cmd(':TransparentToggle') end, { desc = 'Toggle transparency' })

-- :bnext and :bprev
vim.keymap.set('n', '<C-\\><C-j>', function() vim.cmd(':bprev') end, { desc = 'Previous buffer' })
vim.keymap.set('n', '<C-\\><C-k>', function() vim.cmd(':bnext') end, { desc = 'Next buffer' })
