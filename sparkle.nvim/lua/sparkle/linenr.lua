-- sparkle.linenr: line numbers in a slowly flowing cyan → purple → magenta gradient
-- (top to bottom of each window). The cursor line keeps CursorLineNr (see sparkle.glow).
--
-- Each visible line gets an extmark with number_hl_group = SparkleNr<i> (i = position in the
-- window); the flow is done by re-colouring those groups, so marks only change on scroll/edit.
local api, uv = vim.api, vim.uv or vim.loop
local in_cmdline = require("sparkle.style").in_cmdline
local floor, max, min, sin = math.floor, math.max, math.min, math.sin

local M = {}

M.config = {
  stops = { 0x46e0ff, 0x5a7cff, 0x9a5cff, 0xff4fd8, 0x9a5cff, 0x5a7cff }, -- cyclic gradient
  strength = 0.62, -- 0 = background colour, 1 = full gradient colour
  span = 0.55, -- how much of the cycle one window height covers
  speed = 0.05, -- cycles per second
  fps = 10,
  idle_after = 30,
  exclude_ft = { "NvimTree", "sparkle", "lazy", "mason", "TelescopePrompt", "TelescopeResults", "alpha" },
}

local ns = api.nvim_create_namespace("SparkleLineNr")
local N = 24
local timer
local last_input = uv.hrtime() / 1e9
local enabled = true
local excluded = {}
local marked = {} -- [buf] = true when this module has marks in it

local function rgb(h) return { floor(h / 65536) % 256, floor(h / 256) % 256, h % 256 } end
local function mix(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end
local function pack(c)
  local q = function(v) return max(0, min(255, floor(v / 4 + 0.5) * 4)) end
  return q(c[1]) * 65536 + q(c[2]) * 256 + q(c[3])
end

local bg
local function bg_color()
  local ok, hl = pcall(api.nvim_get_hl, 0, { name = "Normal", link = false })
  if ok and hl and hl.bg then return rgb(hl.bg) end
  return vim.o.background == "light" and rgb(0xf4f0d9) or rgb(0x1e2326)
end

local function gradient(u)
  local s = M.config.stops
  u = (u % 1) * #s
  local i = floor(u)
  local a, b = rgb(s[i + 1]), rgb(s[(i + 1) % #s + 1])
  local f = u - i
  f = f * f * (3 - 2 * f)
  return mix(a, b, f)
end

local applied = {}
local function paint(t)
  bg = bg or bg_color()
  local k = M.config.strength
  for i = 1, N do
    local u = (i - 1) / (N - 1) * M.config.span - t * M.config.speed
    local shimmer = 0.06 * sin(t * 1.3 + i * 0.45)
    local fg = pack(mix(bg, gradient(u), k + shimmer))
    if applied[i] ~= fg then
      applied[i] = fg
      api.nvim_set_hl(0, "SparkleNr" .. i, { fg = fg })
    end
  end
end

---------------------------------------------------------------- marks
local function eligible(win)
  if not enabled or api.nvim_win_get_config(win).relative ~= "" then return false end
  if not (vim.wo[win].number or vim.wo[win].relativenumber) then return false end
  local buf = api.nvim_win_get_buf(win)
  if vim.b[buf].sparkle_linenr == false or excluded[vim.bo[buf].filetype] then return false end
  return vim.bo[buf].buftype ~= "terminal"
end

local function mark_win(win)
  local buf = api.nvim_win_get_buf(win)
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  marked[buf] = true
  local info = vim.fn.getwininfo(win)[1]
  if not info then return end
  local top, bot, h = info.topline, info.botline, max(2, info.height)
  local cur = api.nvim_win_get_cursor(win)[1]
  local folds = vim.wo[win].foldenable
  local y = 0
  local lnum = top
  local last = api.nvim_buf_line_count(buf)
  while lnum <= bot and lnum <= last do
    -- count a closed fold as one screen line
    local fe = folds and api.nvim_win_call(win, function() return vim.fn.foldclosedend(lnum) end) or -1
    if lnum ~= cur then
      local i = min(N, 1 + floor(y / (h - 1) * (N - 1) + 0.5))
      pcall(api.nvim_buf_set_extmark, buf, ns, lnum - 1, 0, { number_hl_group = "SparkleNr" .. i, priority = 5 })
    end
    y = y + 1
    lnum = (fe > 0 and fe or lnum) + 1
  end
end

local pending = false
local function refresh()
  if pending then return end
  pending = true
  vim.schedule(function()
    pending = false
    if in_cmdline() then return end -- redone on CmdlineLeave
    for buf in pairs(marked) do
      if api.nvim_buf_is_valid(buf) then api.nvim_buf_clear_namespace(buf, ns, 0, -1) end
    end
    marked = {}
    if not enabled then return end
    local curwin = api.nvim_get_current_win()
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
      if w ~= curwin and eligible(w) then mark_win(w) end
    end
    if eligible(curwin) then mark_win(curwin) end -- the focused window wins a shared buffer
  end)
end

---------------------------------------------------------------- loop
local function stop() if timer then timer:stop() end end

local function tick()
  local t = uv.hrtime() / 1e9
  if t - last_input > M.config.idle_after then return stop() end
  if in_cmdline() then return end
  paint(t)
end

local function start()
  if not enabled then return end
  if not timer then timer = uv.new_timer() end
  if timer:is_active() then return end
  timer:start(0, floor(1000 / M.config.fps), vim.schedule_wrap(tick))
end

function M.set_active(on) M.toggle(on) end

function M.toggle(on)
  if on == nil then on = not enabled end
  enabled = on
  if on then start() else stop() end
  refresh()
end

function M.setup()
  excluded = {}
  for _, ft in ipairs(M.config.exclude_ft) do excluded[ft] = true end
  local grp = api.nvim_create_augroup("SparkleLineNr", { clear = true })
  local last_line = {}
  api.nvim_create_autocmd({ "WinScrolled", "WinResized", "VimResized", "BufWinEnter", "WinEnter", "WinNew",
    "TextChanged", "InsertLeave", "TabEnter" }, { group = grp, callback = refresh })
  api.nvim_create_autocmd("OptionSet", { group = grp, pattern = { "number", "relativenumber" }, callback = refresh })
  api.nvim_create_autocmd("CmdlineLeave", { group = grp, callback = refresh })
  -- the cursor line is left to CursorLineNr: only re-mark when the cursor changes line
  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChangedI" }, { group = grp, callback = function(ev)
    local w = api.nvim_get_current_win()
    local l = api.nvim_win_get_cursor(w)[1] .. ":" .. api.nvim_buf_line_count(ev.buf)
    if last_line[w] ~= l then
      last_line[w] = l
      refresh()
    end
  end })
  api.nvim_create_autocmd("ColorScheme", { group = grp, callback = function()
    bg, applied = nil, {}
    paint(uv.hrtime() / 1e9)
  end })
  api.nvim_create_autocmd("FocusLost", { group = grp, callback = stop })
  api.nvim_create_autocmd("FocusGained", { group = grp, callback = function()
    last_input = uv.hrtime() / 1e9
    start()
  end })
  vim.on_key(function()
    last_input = uv.hrtime() / 1e9
    if timer and not timer:is_active() and enabled then vim.schedule(start) end
  end, api.nvim_create_namespace("SparkleLineNrKeys"))
  api.nvim_create_user_command("SparkleLineNr", function(o)
    M.toggle(o.args == "" and nil or o.args == "on")
  end, { nargs = "?", complete = function() return { "on", "off" } end, desc = "Toggle the line number gradient" })

  paint(uv.hrtime() / 1e9)
  start()
  refresh()
end

return M
