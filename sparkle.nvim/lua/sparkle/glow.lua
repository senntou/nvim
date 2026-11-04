-- sparkle.glow: window separators, float borders and the cursor line number slowly "breathe"
-- in the colour of the current mode.
local api, uv = vim.api, vim.uv or vim.loop
local in_cmdline = require("sparkle.style").in_cmdline
local floor, sin = math.floor, math.sin

local M = {}

M.config = {
  groups = { "WinSeparator", "FloatBorder", "CursorLineNr", "TelescopeBorder", "TelescopePromptBorder",
    "TelescopeResultsBorder", "TelescopePreviewBorder" },
  period = 3.2, -- seconds per breath
  fps = 6,
  idle_after = 30,
}

local base = {} -- original definitions (without fg), captured after each :colorscheme
local orig = {} -- the same, untouched (restored when glow is switched off)
local active = true
local applied = {}
local timer
local last_input = uv.hrtime() / 1e9

local function rgb(h)
  return { floor(h / 65536) % 256, floor(h / 256) % 256, h % 256 }
end
local function mix(a, b, t)
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end
local function pack(c)
  local q = function(v) return math.max(0, math.min(255, floor(v / 6 + 0.5) * 6)) end
  return q(c[1]) * 65536 + q(c[2]) * 256 + q(c[3])
end

local function capture()
  base, orig, applied = {}, {}, {}
  for _, g in ipairs(M.config.groups) do
    local ok, hl = pcall(api.nvim_get_hl, 0, { name = g, link = false })
    if ok and hl then
      orig[g] = vim.deepcopy(hl)
      hl.fg = nil
      hl.default = nil
      base[g] = hl
    end
  end
end

local function mode_color()
  local sl = package.loaded["sparkle.statusline"]
  local cols = sl and sl.mode_colors or { normal = "#46e0ff" }
  local m = api.nvim_get_mode().mode:sub(1, 1)
  local key = (m == "i" and "insert") or ((m == "v" or m == "V" or m == "\22") and "visual")
    or (m == "R" and "replace") or (m == "c" and "command") or (m == "t" and "terminal") or "normal"
  return rgb(tonumber((cols[key] or cols.normal):sub(2), 16))
end

local NAVY, PURPLE, WHITE = rgb(0x1a2250), rgb(0x9a5cff), rgb(0xffffff)

local function tick(force)
  if not active then return end
  if not force and in_cmdline() then return end
  local t = uv.hrtime() / 1e9
  if t - last_input > M.config.idle_after then
    if timer then timer:stop() end
    return
  end
  local mc = mode_color()
  local breath = 0.5 + 0.5 * sin(t * 6.283 / M.config.period)
  local drift = 0.5 + 0.5 * sin(t * 6.283 / (M.config.period * 2.7))
  local border = mix(mix(NAVY, mc, 0.45 + 0.5 * breath), PURPLE, 0.35 * drift)
  local nr = mix(mc, WHITE, 0.15 + 0.35 * breath)
  for g, hl in pairs(base) do
    local fg = pack(g == "CursorLineNr" and nr or border)
    if applied[g] ~= fg then
      applied[g] = fg
      local def = vim.deepcopy(hl)
      def.fg = fg
      if g == "CursorLineNr" then def.bold = true end
      api.nvim_set_hl(0, g, def)
    end
  end
end

local function start()
  if not active then return end
  if not timer then timer = uv.new_timer() end
  if timer:is_active() then return end
  timer:start(0, floor(1000 / M.config.fps), vim.schedule_wrap(tick))
end

function M.set_active(on)
  if on == active then return end
  active = on
  if on then
    capture()
    start()
  else
    if timer then timer:stop() end
    for g, hl in pairs(orig) do
      hl.default = nil
      pcall(api.nvim_set_hl, 0, g, hl)
    end
    applied = {}
  end
end

function M.setup()
  capture()
  local grp = api.nvim_create_augroup("SparkleGlow", { clear = true })
  api.nvim_create_autocmd("ColorScheme", { group = grp, callback = function()
    vim.schedule(function() capture(); tick(true) end)
  end })
  api.nvim_create_autocmd("ModeChanged", { group = grp, callback = function()
    vim.schedule(function() tick(true) end)
  end })
  api.nvim_create_autocmd("FocusLost", { group = grp, callback = function() if timer then timer:stop() end end })
  api.nvim_create_autocmd("FocusGained", { group = grp, callback = function()
    last_input = uv.hrtime() / 1e9
    start()
  end })
  vim.on_key(function()
    last_input = uv.hrtime() / 1e9
    if timer and not timer:is_active() then vim.schedule(start) end
  end, api.nvim_create_namespace("SparkleGlowKeys"))
  -- telescope defines its groups lazily: pick them up once it is loaded
  api.nvim_create_autocmd("User", { group = grp, pattern = "LazyLoad", callback = function(ev)
    if ev.data == "telescope.nvim" then vim.schedule(capture) end
  end })
  start()
end

return M
