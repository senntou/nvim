-- 日本語文章でのWORD移動(W,E,B)とaW/iWを文節単位にする
-- w/e/b もカーソル周りが日本語のときだけ文節単位、英語などでは元の動作にする

-- 日本語(かな・漢字・全角記号)かどうか
local function is_ja(c)
  if c == nil or c == "" then return false end
  local n = vim.fn.char2nr(c)
  return (n >= 0x3000 and n <= 0x30FF)  -- 全角記号・ひらがな・カタカナ
    or (n >= 0x3400 and n <= 0x4DBF)    -- CJK拡張A
    or (n >= 0x4E00 and n <= 0x9FFF)    -- CJK統合漢字
    or (n >= 0xFF00 and n <= 0xFFEF)    -- 全角英数・半角カナ
end

-- カーソル位置から dir 方向(1:後ろ, -1:前)に見て最初の空白以外の文字。
-- include_cur なら現在の文字から調べる
local function nonblank_char(dir, include_cur)
  local chars = vim.fn.split(vim.fn.getline("."), [[\zs]])
  local idx = vim.fn.charcol(".") -- 1-based の文字位置
  local i = include_cur and idx or idx + dir
  while i >= 1 and i <= #chars do
    local c = chars[i]
    if not c:match("^%s$") and c ~= "　" then return c end
    i = i + dir
  end
  return nil
end

local function pick(key)
  local c
  if key == "w" then
    c = nonblank_char(1, true)
  elseif key == "e" then
    c = nonblank_char(1, false)
  else -- b
    c = nonblank_char(-1, false)
  end
  if not is_ja(c) then return "<Plug>(jasegment-native-" .. key .. ")" end
  local mode = vim.fn.mode(true)
  local suffix = mode:find("o") and "O" or (mode:match("^[vV\22]") and "V" or "N")
  return "<Plug>JaSegmentMove" .. suffix .. key:upper()
end

local keys = {
  { "W", mode = { "n", "o", "x" } },
  { "E", mode = { "n", "o", "x" } },
  { "B", mode = { "n", "o", "x" } },
  { "aW", mode = { "o", "x" } },
  { "iW", mode = { "o", "x" } },
}
for _, k in ipairs({ "w", "e", "b" }) do
  table.insert(keys, {
    k,
    function() return pick(k) end,
    mode = { "n", "o", "x" },
    expr = true,
    remap = true,
    desc = "jasegment: 日本語なら文節単位の " .. k,
  })
end

return {
  "deton/jasegment.vim",
  keys = keys,
  cmd = { "JaSegmentSplit" },
  init = function()
    -- 英語などのときに使う素の w/e/b
    for _, k in ipairs({ "w", "e", "b" }) do
      vim.keymap.set({ "n", "o", "x" }, "<Plug>(jasegment-native-" .. k .. ")", k)
    end
  end,
}
