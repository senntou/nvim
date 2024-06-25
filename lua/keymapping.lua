vim.cmd([[
    inoremap <silent><expr> <TAB>
    \ coc#pum#visible() ? coc#_select_confirm() :
    \ coc#expandableOrJumpable() ?
    \ "\<C-r>=coc#rpc#request('doKeymap', ['snippets-expand-jump',''])\<CR>" :
    \ CheckBackspace() ? "\<TAB>" :
    \ coc#refresh()

    noremap <C-n> :NERDTreeToggle<CR>

    function! CheckBackspace() abort
    let col = col('.') - 1
    return !col || getline('.')[col - 1]  =~# '\s'
    endfunction

    let g:coc_snippet_next = '<tab>'
]])

vim.keymap.set('n', '<C-F5>', function()
    compile_without_g_cpp()
    require('dapui').open(2)
    require('dap').continue() 
end)
vim.keymap.set('n', '<S-F5>', function() require('dap').terminate() end)
vim.keymap.set('n', '<F5>', function() 
    compile_current_cpp()
    require('dapui').open()
    require('dap').continue() 
end )
vim.keymap.set('n', '<F6>', function() require('dap').continue() end)
vim.keymap.set('n', '<F10>', function() require('dap').step_over() end)
vim.keymap.set('n', '<F11>', function() require('dap').step_into() end)
vim.keymap.set('n', '<F12>', function() require('dap').step_out() end)
vim.keymap.set('n', '<F9>', function() require('dap').toggle_breakpoint() end)
vim.keymap.set('n', '<leader>c', function() compile_without_g_cpp() end)
vim.api.nvim_set_keymap('n', '<leader>g', ':lua require("dapui").close()<CR>', {})
vim.api.nvim_set_keymap('n', '<leader>j', ':lua require("dapui").toggle(1)<CR>', {})
-- vim.keymap.set('n', '<Leader>B', function() require('dap').set_breakpoint() end)
-- vim.keymap.set('n', '<Leader>lp', function() require('dap').set_breakpoint(nil, nil, vim.fn.input('Log point message: ')) end)
-- vim.keymap.set('n', '<Leader>dr', function() require('dap').repl.open() end)
-- vim.keymap.set('n', '<Leader>dl', function() require('dap').run_last() end)
-- vim.keymap.set({'n', 'v'}, '<Leader>dh', function()
--   require('dap.ui.widgets').hover()
-- end)
-- vim.keymap.set({'n', 'v'}, '<Leader>dp', function()
--   require('dap.ui.widgets').preview()
-- end)
-- vim.keymap.set('n', '<Leader>df', function()
--   local widgets = require('dap.ui.widgets')
--   widgets.centered_float(widgets.frames)
-- end)
-- vim.keymap.set('n', '<Leader>ds', function()
--   local widgets = require('dap.ui.widgets')
--   widgets.centered_float(widgets.scopes)
-- end)
