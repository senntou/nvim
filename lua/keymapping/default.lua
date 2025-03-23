-- 各プラグインのキーマップやターミナルのキーマップは、コンフィグファイルに記載してください
-- ここに記載するのは、Vimのデフォルトのキーマップの設定です

-- バッファを移動する関数
function next_buffer()
  vim.cmd(':bnext')
  -- terminal がある場合は、terminal の次のバッファに移動する
  if vim.bo.buftype == 'terminal' then
    vim.cmd(':bnext')
  end
end

function prev_buffer()
  vim.cmd(':bprev')
  -- terminal がある場合は、terminal の次のバッファに移動する
  if vim.bo.buftype == 'terminal' then
    vim.cmd(':bprev')
  end
end

-- バッファの移動
vim.keymap.set('n', '<C-\\><C-j>', prev_buffer, { desc = 'Previous buffer' })
vim.keymap.set('n', '<C-\\><C-h>', prev_buffer, { desc = 'Previous buffer' })
vim.keymap.set('n', '<C-\\><C-k>', next_buffer, { desc = 'Next buffer' })
vim.keymap.set('n', '<C-\\><C-l>', next_buffer, { desc = 'Next buffer' })

-- バッファの削除
vim.keymap.set('n', '<C-\\><C-d>', ':bd<CR>', { desc = 'Delete buffer' })

-- ctrl + hjkl
vim.keymap.set('i', '<C-j>', '<Down>', { noremap = true })
vim.keymap.set('i', '<C-k>', '<Up>', { noremap = true })
vim.keymap.set('i', '<C-h>', '<Left>', { noremap = true })
vim.keymap.set('i', '<C-l>', '<Right>', { noremap = true })

-- command line での補完を上下キーで選択する
vim.keymap.set('c', '<Down>', '<C-n>', { noremap = true })
vim.keymap.set('c', '<Up>', '<C-p>', { noremap = true })

-- split
vim.keymap.set('n', '<C-w><C-l>', '<C-w>v', { noremap = true })

-- 定義ジャンプ
vim.api.nvim_create_autocmd("LspAttach", {
  desc = "Attach key mappings for LSP functionalities",
  callback = function()
    vim.keymap.set('n', 'gd', '<cmd>:lua vim.lsp.buf.definition()<CR>')
    vim.keymap.set('n', 'gr', '<cmd>:lua vim.lsp.buf.references()<CR>')
    -- more mappings ...
  end
})

-- terminal でのEscキーの挙動を変更
-- vim.keymap.set('t', '<Esc>', '<C-\\><C-n>', { noremap = true })
