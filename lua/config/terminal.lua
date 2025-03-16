--terminal
function toggle_terminal()
  local bufnr = vim.fn.bufnr('%')  -- 現在のバッファ番号を取得
  local term_bufnr = nil

  -- 既に開いているターミナルを探す
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buftype == 'terminal' then
      term_bufnr = buf
      break
    end
  end

  if term_bufnr then
    -- もしターミナルがウィンドウとして開いていたら閉じる
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == term_bufnr then
        vim.api.nvim_win_hide(win)
        return
      end
    end
    -- ターミナルが開いてないなら、下半分に表示
    vim.cmd("belowright split")
    vim.cmd("buffer " .. term_bufnr)
    vim.cmd("startinsert") -- ターミナルに入ったら挿入モードにする
  else
    -- ターミナルがない場合、新しく作成して下半分に開く
    vim.cmd("belowright split")
    vim.cmd("terminal")
    vim.cmd("startinsert") -- ターミナルに入ったら挿入モードにする
  end
end

-- キーマッピングを設定（<C-Space> でトグル）
-- windows terminal環境では、この設定でC-@にマッピングされる
-- 他の環境では未検証
vim.api.nvim_set_keymap('n', '<C-Space>', '<cmd>lua toggle_terminal()<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('i', '<C-Space>', '<cmd>lua toggle_terminal()<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('t', '<C-Space>', '<cmd>lua toggle_terminal()<CR>', { noremap = true, silent = true })


