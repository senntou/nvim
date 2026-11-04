-- sparkle.theme: colours taken from the current colorscheme (used by the calm style).
-- Every entry is an {r, g, b} table (sparkle.canvas colour) and a "#rrggbb" string in .hex.
local api = vim.api
local floor = math.floor

local M = {}

local cache

local function attr(groups, key)
  for _, g in ipairs(groups) do
    local ok, hl = pcall(api.nvim_get_hl, 0, { name = g, link = false })
    if ok and hl then
      local v = hl[key]
      if hl.reverse then v = (key == "fg") and hl.bg or hl.fg end
      if v then return v end
    end
  end
end

local function rgb(n) return { floor(n / 65536) % 256, floor(n / 256) % 256, n % 256 } end

function M.colors()
  if cache then return cache end
  local dark = vim.o.background ~= "light"
  local bg = attr({ "Normal" }, "bg") or (dark and 0x1e2326 or 0xf4f0d9)
  local fg = attr({ "Normal" }, "fg") or (dark and 0xd3c6aa or 0x5c6a72)
  local c = {
    bg = bg,
    fg = fg,
    float_bg = attr({ "NormalFloat", "Pmenu" }, "bg") or bg,
    dim = attr({ "Comment", "NonText" }, "fg") or fg,
    accent = attr({ "Function", "Identifier" }, "fg") or fg,
    accent2 = attr({ "Keyword", "Statement" }, "fg") or fg,
    title = attr({ "Title", "Function" }, "fg") or fg,
    special = attr({ "Special", "Constant" }, "fg") or fg,
    border = attr({ "FloatBorder", "WinSeparator", "Comment" }, "fg") or fg,
    sel_bg = attr({ "CursorLine", "Visual", "PmenuSel" }, "bg") or bg,
  }
  cache = { hex = {} }
  for k, v in pairs(c) do
    cache[k] = rgb(v)
    cache.hex[k] = string.format("#%06x", v)
  end
  return cache
end

api.nvim_create_autocmd("ColorScheme", {
  group = api.nvim_create_augroup("SparkleTheme", { clear = true }),
  callback = function() cache = nil end,
})

return M
