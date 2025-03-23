-- 現在のバッファがNERDTreeの場合、別のウィンドウ移動する
function leave_nerdtree()
  if vim.fn.winnr('$') > 1 and vim.fn.bufname('%'):match('NERD_tree_tab_%d+') then -- NERDTreeのバッファかつウィンドウが2つ以上ある場合
    nerd_winnr = vim.fn.winnr()                                                    -- NERDTreeのウィンドウ番号を取得
    next_winnr = nerd_winnr % 2 + 1
    buf = vim.api.nvim_list_wins()[next_winnr]                                     -- 一番上のウィンドウに移動
    vim.api.nvim_set_current_win(buf)
  end
end

--terminal
function toggle_terminal()
  local bufnr = vim.fn.bufnr('%') -- 現在のバッファ番号を取得
  local term_bufnr = nil          -- ターミナルのバッファ番号

  -- 既に開いているターミナルを探す
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buftype == 'terminal' then
      term_bufnr = buf
      break
    end
  end

  if term_bufnr then -- 既にターミナルが起動されている（バッファが存在する）場合
    -- もしターミナルがウィンドウとして開いていたら閉じる
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == term_bufnr then
        vim.api.nvim_win_hide(win)
        return
      end
    end
    -- ターミナルが開いてないなら、下半分に表示
    leave_nerdtree()
    vim.cmd("belowright split")
    vim.cmd("buffer " .. term_bufnr)
    vim.cmd("startinsert") -- ターミナルに入ったら挿入モードにする
  else                     -- ターミナルが起動されていない（バッファが存在しない）場合
    leave_nerdtree()
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
vim.api.nvim_set_keymap('n', '<C-\\><C-t>', '<cmd>lua toggle_terminal()<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('i', '<C-\\><C-t>', '<cmd>lua toggle_terminal()<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('t', '<C-\\><C-t>', '<cmd>lua toggle_terminal()<CR>', { noremap = true, silent = true })
