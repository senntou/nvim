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
