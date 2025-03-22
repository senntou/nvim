-- NERDTree keymaps
vim.cmd([[
    noremap <C-n> :NERDTreeToggle<CR>
    noremap <C-e> :NERDTreeFind<CR>
]])

-- NERDTreeが他のバッファにリプレイスされるのを防ぐ
vim.cmd([[
autocmd BufEnter * if winnr() == winnr('h') && bufname('#') =~ 'NERD_tree_tab_\d\+' && bufname('%') !~ 'NERD_tree_tab_\d\+' && winnr('$') > 1 |
    \ echo("test") | let buf=bufnr() | buffer# | execute "normal! \<C-W>w" | execute 'buffer'.buf | endif
]])

-- NERDTreeが最後のウィンドウになったら閉じる
vim.cmd[[ autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif ]]
