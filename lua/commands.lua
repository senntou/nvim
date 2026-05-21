-- 自作のコマンドはここに追加していく

-- helpを全画面で開く
vim.cmd([[command! -nargs=1 -complete=help H help <args> | only]])

-- バッファ名を表示する
vim.cmd([[command! Bufname echo bufname('%')]])


-- バッファを移動する関数
function NextBuffer()
  vim.cmd(':bnext')
  -- terminal がある場合は、terminal の次のバッファに移動する
  if vim.bo.buftype == 'terminal' then
    vim.cmd(':bnext')
  end
end

function PrevBuffer()
  vim.cmd(':bprev')
  -- terminal がある場合は、terminal の次のバッファに移動する
  if vim.bo.buftype == 'terminal' then
    vim.cmd(':bprev')
  end
end

-- バッファを閉じる
-- バッファを閉じた後は、一つ前のバッファに移動する
function Bdelete()
  local buf_list = vim.fn.getbufinfo({ buflisted = 1 })
  local current_bufnr = vim.fn.bufnr('%')

  local current_idx = 0
  for idx, buf in ipairs(buf_list) do
    if buf.bufnr == current_bufnr then
      current_idx = idx
      break
    end
  end

  local next_idx = (current_idx + #buf_list - 2) % #buf_list + 1
  while vim.api.nvim_get_option_value('buftype', { buf = buf_list[next_idx].bufnr }) == 'terminal' do
    next_idx = (next_idx + #buf_list - 2) % #buf_list + 1
  end

  local next_bufnr = buf_list[next_idx].bufnr
  if vim.fn.buflisted(next_bufnr) ~= 0 and next_bufnr ~= current_bufnr then
    vim.cmd('buffer ' .. next_bufnr)
    vim.cmd('bdelete ' .. current_bufnr)
    return
  end

  vim.cmd('Alpha')
  vim.cmd('bdelete' .. current_bufnr)
end

-- ビジュアル選択とクリップボードをdiff比較する
vim.keymap.set("v", "<leader>cf", function()
  -- 選択範囲をレジスタzにヤンク
  vim.cmd('noau normal! "zy')
  local selection = vim.fn.getreg("z")
  local selection_lines = vim.split(selection, "\n")
  if selection_lines[#selection_lines] == "" then
    table.remove(selection_lines)
  end

  -- クリップボード（+レジスタ）を取得
  local clipboard = vim.fn.getreg("+")
  local clipboard_lines = vim.split(clipboard, "\n")
  if clipboard_lines[#clipboard_lines] == "" then
    table.remove(clipboard_lines)
  end

  -- 新しいタブで左右にscratchバッファを開く
  vim.cmd("tabnew")

  local left_buf = vim.api.nvim_get_current_buf()
  vim.bo[left_buf].buftype = "nofile"
  vim.bo[left_buf].bufhidden = "wipe"
  vim.bo[left_buf].swapfile = false
  pcall(vim.api.nvim_buf_set_name, left_buf, "Clipboard")
  vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, clipboard_lines)
  vim.cmd("diffthis")

  vim.cmd("vsplit")
  local right_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, right_buf)
  vim.bo[right_buf].buftype = "nofile"
  vim.bo[right_buf].bufhidden = "wipe"
  vim.bo[right_buf].swapfile = false
  pcall(vim.api.nvim_buf_set_name, right_buf, "Selection")
  vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, selection_lines)
  vim.cmd("diffthis")

  local close = function() vim.cmd("tabclose") end
  vim.keymap.set("n", "q", close, { buffer = left_buf, nowait = true })
  vim.keymap.set("n", "q", close, { buffer = right_buf, nowait = true })
end, { desc = "Diff selection vs clipboard" })
