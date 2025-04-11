-- 各プラグインのキーマップやターミナルのキーマップは、コンフィグファイルに記載してください
-- ここに記載するのは、Vimのデフォルトのキーマップの設定です

-- バッファを移動する関数
function Next_buffer()
  vim.cmd(':bnext')
  -- terminal がある場合は、terminal の次のバッファに移動する
  if vim.bo.buftype == 'terminal' then
    vim.cmd(':bnext')
  end
end

function Prev_buffer()
  vim.cmd(':bprev')
  -- terminal がある場合は、terminal の次のバッファに移動する
  if vim.bo.buftype == 'terminal' then
    vim.cmd(':bprev')
  end
end

-- バッファの移動
vim.keymap.set('n', '<C-\\><C-j>', Prev_buffer, { desc = 'Previous buffer' })
vim.keymap.set('n', '<C-\\><C-h>', Prev_buffer, { desc = 'Previous buffer' })
vim.keymap.set('n', '<C-\\><C-k>', Next_buffer, { desc = 'Next buffer' })
vim.keymap.set('n', '<C-\\><C-l>', Next_buffer, { desc = 'Next buffer' })

-- バッファの削除
vim.keymap.set('n', '<C-\\><C-d>', ':lua Bdelete()<CR>', { desc = 'Delete buffer' })
vim.keymap.set('n', '<leader>bd', ':lua Bdelete()<CR>', { desc = 'Delete buffer' })

-- command line での補完を上下キーで選択する
vim.keymap.set('c', '<Down>', '<C-n>', { noremap = true })
vim.keymap.set('c', '<Up>', '<C-p>', { noremap = true })

-- split
vim.keymap.set('n', '<C-w><C-l>', '<C-w>v', { noremap = true })

-- LSP関連のキーマップ
vim.api.nvim_create_autocmd("LspAttach", {
  desc = "Attach key mappings for LSP functionalities",
  callback = function()
    vim.keymap.set('n', 'gd', '<cmd>:lua vim.lsp.buf.definition()<CR>')
    vim.keymap.set('n', 'gr', '<cmd>:lua vim.lsp.buf.references()<CR>')
    vim.keymap.set('n', 'gn', '<cmd>:lua vim.lsp.buf.rename()<CR>')
    vim.keymap.set('n', 'ga', '<cmd>:lua vim.lsp.buf.code_action()<CR>')
    vim.api.nvim_set_keymap('n', 'gf', '<cmd>:lua vim.diagnostic.open_float()<CR>',
      { noremap = true, silent = true, desc = 'Open Float' })
    vim.api.nvim_set_keymap('n', '<leader>fm', '<cmd>:lua vim.lsp.buf.format()<CR>',
      { noremap = true, silent = true, desc = 'Format' })
    vim.keymap.set('n', 'gk', '<cmd>lua vim.diagnostic.goto_prev()<CR>')
    vim.keymap.set('n', 'gj', '<cmd>lua vim.diagnostic.goto_next()<CR>')
  end
})

-- qキーでマクロ設定の無効化
vim.api.nvim_set_keymap('n', 'q', ':echo "Macro is disabled"<CR>', { noremap = true, silent = false })
vim.api.nvim_set_keymap('n', 'Q', ':echo "Macro is disabled"<CR>', { noremap = true, silent = false })
vim.api.nvim_set_keymap('n', '@', '<Nop>', { noremap = true, silent = false })

-- Neovimを終了する
vim.api.nvim_set_keymap('n', '<leader>q', '<cmd>:qa<CR>', { noremap = true, silent = true, desc = 'Quit Neovim' })


-- terminal でのEscキーの挙動を変更
-- vim.keymap.set('t', '<Esc>', '<C-\\><C-n>', { noremap = true })
