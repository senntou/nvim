-- 自作のコマンドはここに追加していく

-- helpを全画面で開く
vim.cmd([[command! -nargs=1 -complete=help H help <args> | only]])

-- バッファ名を表示する
vim.cmd([[command! Bufname echo bufname('%')]])


-- ファイルを表示できる普通の窓か（NvimTree・ターミナル・フロートなどは除く）
local function is_file_win(win)
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.api.nvim_win_get_config(win).relative == ''
    and vim.bo[buf].buftype == '' and vim.bo[buf].buflisted
end

-- NvimTree などにフォーカスがあるときは、先にファイルの窓へフォーカスを移す
-- （そのまま :bnext するとツリーの窓がファイルで置き換わってしまう）
local function focus_file_win()
  local cur = vim.api.nvim_get_current_win()
  if is_file_win(cur) then return end
  -- 直前にいた窓 → 同じタブの最初のファイルの窓、の順に探す
  local prev = vim.fn.win_getid(vim.fn.winnr('#'))
  if prev ~= 0 and is_file_win(prev) then
    vim.api.nvim_set_current_win(prev)
    return
  end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_file_win(w) then
      vim.api.nvim_set_current_win(w)
      return
    end
  end
  -- ダッシュボードだけが開いている場合は、そこを置き換える
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'sparkle' then
      vim.api.nvim_set_current_win(w)
      return
    end
  end
  -- ファイルの窓が無い（ツリーだけ等）: 右側に窓を作ってそこで切り替える
  vim.cmd('botright vsplit')
end

-- バッファを移動する関数
function NextBuffer()
  focus_file_win()
  vim.cmd(':bnext')
  -- terminal がある場合は、terminal の次のバッファに移動する
  if vim.bo.buftype == 'terminal' then
    vim.cmd(':bnext')
  end
end

function PrevBuffer()
  focus_file_win()
  vim.cmd(':bprev')
  -- terminal がある場合は、terminal の次のバッファに移動する
  if vim.bo.buftype == 'terminal' then
    vim.cmd(':bprev')
  end
end

-- バッファを閉じる
-- バッファを閉じた後は、一つ前のバッファに移動する
function Bdelete()
  local current_bufnr = vim.fn.bufnr('%')
  -- NvimTree などのサイドバー（unlisted）上では何もしない（ツリーの窓にファイルが開いてしまうため）
  if vim.fn.buflisted(current_bufnr) == 0 and vim.bo.filetype ~= 'sparkle' then
    return
  end
  -- 移動先の候補: listed かつ terminal 以外、現在のバッファ以外
  local candidates = {}
  local current_idx = 0
  for _, buf in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    if buf.bufnr == current_bufnr then
      current_idx = #candidates + 1
    elseif vim.bo[buf.bufnr].buftype ~= 'terminal' then
      table.insert(candidates, buf.bufnr)
    end
  end

  if #candidates > 0 then
    -- 一つ前のバッファ（先頭なら末尾）へ
    local idx = current_idx - 1
    if idx < 1 then idx = #candidates end
    vim.cmd('buffer ' .. candidates[idx])
  else
    -- 他に開くバッファが無ければダッシュボードへ
    local ok = pcall(function() require('sparkle.dashboard').open() end)
    if not ok then vim.cmd('enew') end
  end

  if vim.api.nvim_buf_is_valid(current_bufnr) and vim.fn.buflisted(current_bufnr) == 1
    and vim.bo[current_bufnr].filetype ~= 'sparkle' then
    vim.cmd('bdelete ' .. current_bufnr)
  end
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
