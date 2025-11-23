-- 各プラグインのキーマップやターミナルのキーマップは、コンフィグファイルに記載してください
-- ここに記載するのは、Vimのデフォルトのキーマップの設定です


-- バッファの移動
vim.keymap.set('n', '<C-\\><C-j>', PrevBuffer, { desc = 'Previous buffer' })
vim.keymap.set('n', '<C-\\><C-h>', PrevBuffer, { desc = 'Previous buffer' })
vim.keymap.set('n', '<C-\\><C-k>', NextBuffer, { desc = 'Next buffer' })
vim.keymap.set('n', '<C-\\><C-l>', NextBuffer, { desc = 'Next buffer' })
vim.keymap.set('n', 'zh', PrevBuffer, { desc = 'Previous buffer' })
vim.keymap.set('n', 'zl', NextBuffer, { desc = 'Next buffer' })
vim.keymap.set('n', 'zd', ':lua Bdelete()<CR>', { desc = 'Delete buffer' })

-- バッファの削除
vim.keymap.set('n', '<C-\\><C-d>', ':lua Bdelete()<CR>', { desc = 'Delete buffer' })
vim.keymap.set('n', '<leader>bd', ':lua Bdelete()<CR>', { desc = 'Delete buffer' })

-- command line での補完を上下キーで選択する
vim.keymap.set('c', '<Down>', '<C-n>', { noremap = true })
vim.keymap.set('c', '<Up>', '<C-p>', { noremap = true })

-- split
vim.keymap.set('n', '<C-w><C-l>', '<C-w>v', { noremap = true })

-- ファイルパスをコピーする
vim.keymap.set('n', '<leader>y', ':let @+ = expand("%:.")<CR>', {noremap = true, desc = 'Copy file path to clipboard'})

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
vim.api.nvim_set_keymap('n', 'q', '<C-w>', { noremap = true, silent = false })
vim.api.nvim_set_keymap('n', 'Q', '<C-w>', { noremap = true, silent = false })
vim.api.nvim_set_keymap('n', '@', '<Nop>', { noremap = true, silent = false })

-- 次の単語検索
vim.keymap.set("n", "*", "*``", { noremap = true, silent = true })

-- resize window
vim.api.nvim_set_keymap('n', '<C-Up>', '<cmd>vertical resize +4<CR>',
  { noremap = true, silent = true, desc = 'Resize left' })
vim.api.nvim_set_keymap('n', '<C-Down>', '<cmd>vertical resize -4<CR>',
  { noremap = true, silent = true, desc = 'Resize right' })

-- Neovimを終了する
vim.api.nvim_set_keymap('n', '<leader>q', '<cmd>:qa<CR>', { noremap = true, silent = true, desc = 'Quit Neovim' })


-- terminal でのEscキーの挙動を変更
-- vim.keymap.set('t', '<Esc>', '<C-\\><C-n>', { noremap = true })
