-- sparkle.overlay: an animated sparkle.canvas in a floating terminal window.
--
--   local ov = overlay.open({ row=, col=, width=, height=, anchor=, zindex=, fps= }, function(c, t, dt, ov)
--     ... draw into canvas c ...
--     return t < 1.5          -- false/nil closes the overlay
--   end)
--   ov:move({ row = 3 })      -- any nvim_win_set_config keys
--   ov:close()
--
-- Overlays never take focus. They stop animating while Neovim is unfocused.

local C = require("sparkle.canvas")
local api, uv = vim.api, vim.uv or vim.loop
local floor, min = math.floor, math.min

local M = {}

local Overlay = {}
Overlay.__index = Overlay

local live = {} -- [ov] = true

local function now() return uv.hrtime() / 1e9 end

-- nvim_open_win / nvim_win_set_config that tolerate keys an older Neovim does not know
-- (e.g. `_cmdline_offset` is 0.12+, `hide` is 0.10+): drop the offending key and retry.
local function compat(fn, ...)
  local args = { ... }
  local cfg = vim.deepcopy(args[#args])
  args[#args] = cfg
  for _ = 1, 8 do
    local ok, res = pcall(fn, unpack(args))
    if ok then return res end
    local key = tostring(res):match("[Ii]nvalid key:? '?([%w_]+)'?")
    if not key or cfg[key] == nil then error(res, 0) end
    cfg[key] = nil
  end
  error("sparkle: could not configure window", 0)
end
function M.open_win(buf, enter, cfg) return compat(api.nvim_open_win, buf, enter, cfg) end
function M.win_set_config(win, cfg) return compat(api.nvim_win_set_config, win, cfg) end

local function open_term(buf)
  -- nvim_open_term fires TermOpen; user autocmds (startinsert, keymaps on buffer 0, ...) must not run
  local ei = vim.o.eventignore
  vim.o.eventignore = "all"
  local ok, chan = pcall(api.nvim_open_term, buf, { on_input = function() end })
  vim.o.eventignore = ei
  return ok and chan or nil
end

function M.open(cfg, draw)
  local width, height = math.max(1, cfg.width), math.max(1, cfg.height)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local wcfg = {
    relative = cfg.relative or "editor",
    row = cfg.row or 0,
    col = cfg.col or 0,
    width = width,
    height = height,
    anchor = cfg.anchor,
    zindex = cfg.zindex or 60,
    style = "minimal",
    focusable = false,
    noautocmd = true,
    border = "none",
    hide = cfg.hide,
  }
  local ok, win = pcall(M.open_win, buf, false, wcfg)
  if not ok then
    pcall(api.nvim_buf_delete, buf, { force = true })
    return nil
  end
  vim.wo[win].winblend = cfg.blend or 0
  vim.wo[win].winhighlight = "Normal:SparkleOverlay,NormalFloat:SparkleOverlay"
  local chan = open_term(buf)
  if not chan then
    pcall(api.nvim_win_close, win, true)
    return nil
  end
  vim.bo[buf].scrollback = 1

  local ov = setmetatable({
    buf = buf, win = win, chan = chan, draw = draw,
    canvas = C.new(width, height),
    t0 = now(), fps = cfg.fps or 30, repaint = 3,
    redraw = cfg.redraw, -- force a screen flush every frame (needed while in cmdline mode)
    data = cfg.data or {},
  }, Overlay)
  live[ov] = true
  ov:start()
  return ov
end

function Overlay:valid()
  return self.win and api.nvim_win_is_valid(self.win) and api.nvim_buf_is_valid(self.buf)
end

function Overlay:frame()
  if not self:valid() then return self:close() end
  local t = now()
  local dt = min(0.1, t - (self.last or t))
  self.last = t
  local c = self.canvas
  local w, h = api.nvim_win_get_width(self.win), api.nvim_win_get_height(self.win)
  if c.cols ~= w or c.rows ~= h then
    c:resize(w, h)
    self.repaint = 3
  end
  local ok, keep = pcall(self.draw, c, t - self.t0, dt, self)
  if not ok then
    vim.schedule(function() vim.notify("sparkle overlay: " .. tostring(keep), vim.log.levels.DEBUG) end)
    keep = false
  end
  if not keep then return self:close() end
  if self.repaint > 0 then
    self.repaint = self.repaint - 1
    c:invalidate_ansi()
  end
  local data = c:render_ansi()
  if data then pcall(api.nvim_chan_send, self.chan, data) end
  if self.redraw then self.redraw(self) end
end

function Overlay:start()
  if self.timer or self.closed then return end
  self.timer = uv.new_timer()
  self.last = nil
  self.timer:start(0, floor(1000 / self.fps), vim.schedule_wrap(function()
    if not self.closed then self:frame() end
  end))
end

function Overlay:stop()
  if self.timer then
    self.timer:stop()
    self.timer:close()
    self.timer = nil
  end
end

function Overlay:move(cfg)
  if not self:valid() then return end
  pcall(M.win_set_config, self.win, cfg)
end

function Overlay:set_blend(b)
  if self:valid() then vim.wo[self.win].winblend = math.max(0, math.min(100, floor(b))) end
end

function Overlay:close()
  if self.closed then return end
  self.closed = true
  self:stop()
  live[self] = nil
  local win, buf, chan = self.win, self.buf, self.chan
  vim.schedule(function()
    pcall(vim.fn.chanclose, chan)
    pcall(api.nvim_win_close, win, true)
    pcall(api.nvim_buf_delete, buf, { force = true })
  end)
  if self.on_close then pcall(self.on_close, self) end
end

-- pause everything while the terminal is unfocused
local grp = api.nvim_create_augroup("SparkleOverlay", { clear = true })
api.nvim_create_autocmd("FocusLost", { group = grp, callback = function()
  for ov in pairs(live) do ov:stop() end
end })
api.nvim_create_autocmd("FocusGained", { group = grp, callback = function()
  for ov in pairs(live) do ov:start() end
end })
api.nvim_create_autocmd("VimLeavePre", { group = grp, callback = function()
  for ov in pairs(live) do ov:stop() end
end })

function M.close_all()
  for ov in pairs(live) do ov:close() end
end

---------------------------------------------------------------- shared look
M.pal = {
  navy = C.hex(0x0a0f24),
  panel = C.hex(0x0c1230),
  border = C.hex(0x2f78b8),
  cyan = C.hex(0x46e0ff),
  magenta = C.hex(0xff4fd8),
  purple = C.hex(0x9a5cff),
  gold = C.hex(0xffd34d),
  green = C.hex(0x5cffa8),
  red = C.hex(0xff5470),
  white = C.hex(0xf4f7ff),
  text = C.hex(0xc8d4f4),
  dim = C.hex(0x6a7499),
  faint = C.hex(0x3a4366),
}

local function hash(i, s)
  local v = math.sin(i * 127.1 + s * 311.7) * 43758.5453
  return v - floor(v)
end
M.hash = hash

-- Dark panel with a twinkling star dust background.
function M.backdrop(c, t, base, density)
  local pal = M.pal
  base = base or pal.panel
  local pw, ph = c.pw, c.ph
  for y = 0, ph - 1 do
    local k = 1 - 0.25 * (y / math.max(1, ph - 1))
    for x = 0, pw - 1 do
      local i = y * pw + x + 1
      c.R[i], c.G[i], c.B[i] = base[1] * k, base[2] * k, base[3] * k
    end
  end
  local n = floor(pw * ph * (density or 0.03))
  for i = 1, n do
    local x, y = floor(hash(i, 1) * pw), floor(hash(i, 2) * ph)
    local tw = 0.5 + 0.5 * math.sin(t * (2 + 3 * hash(i, 3)) + hash(i, 4) * 6.28)
    c:padd(x, y, C.hex(0x8ea0e0), 0.25 + 0.45 * tw * tw)
  end
end

-- Rounded text-glyph frame whose colour cycles around the border (a running light).
function M.frame(c, t, a, b, opts)
  opts = opts or {}
  local cols, rows = c.cols, c.rows
  local per = 2 * (cols + rows)
  local speed = opts.speed or 0.6
  local function col_at(i)
    local u = ((i / per) - t * speed) % 1
    local k = 0.5 + 0.5 * math.cos(u * 6.283)
    local cc = C.lerp(a, b, k)
    local head = math.max(0, 1 - math.abs(u - 0.5) * 14)
    return C.add(cc, M.pal.white, head * 0.8)
  end
  local i = 0
  local function put(x, y, ch)
    c:put(x, y, ch, col_at(i), { bold = true })
    i = i + 1
  end
  put(0, 0, "╭")
  for x = 1, cols - 2 do put(x, 0, "─") end
  put(cols - 1, 0, "╮")
  for y = 1, rows - 2 do put(cols - 1, y, "│") end
  put(cols - 1, rows - 1, "╯")
  for x = cols - 2, 1, -1 do put(x, rows - 1, "─") end
  put(0, rows - 1, "╰")
  for y = rows - 2, 1, -1 do put(0, y, "│") end
end

-- A little 4-point star made of pixels.
function M.twinkle(c, x, y, k, col)
  col = col or M.pal.white
  if k <= 0 then return end
  c:glow(x, y, 2.5, col, k * 0.8)
  for i = 1, 2 do
    local a = k * (1 - i / 3)
    c:padd(x + i, y, col, a); c:padd(x - i, y, col, a)
    c:padd(x, y + i, col, a); c:padd(x, y - i, col, a)
  end
end

-- particles: list of {x,y,vx,vy,life,age,col}
function M.burst(list, x, y, n, cols, speed)
  speed = speed or 1
  for _ = 1, n do
    local a = math.random() * 6.283
    local sp = (6 + math.random() * 18) * speed
    list[#list + 1] = {
      x = x, y = y, vx = math.cos(a) * sp, vy = math.sin(a) * sp * 0.6,
      life = 0.35 + math.random() * 0.45, age = 0, col = cols[math.random(#cols)],
    }
  end
end

function M.particles(c, list, dt)
  local j = 0
  for i = 1, #list do
    local p = list[i]
    p.age = p.age + dt
    if p.age < p.life then
      p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
      p.vx, p.vy = p.vx * 0.9, p.vy * 0.9 + 12 * dt
      local k = 1 - p.age / p.life
      c:padd(p.x, p.y, p.col, k)
      c:glow(p.x, p.y, 1.6, p.col, 0.35 * k)
      j = j + 1
      list[j] = p
    end
  end
  for i = #list, j + 1, -1 do list[i] = nil end
end

api.nvim_set_hl(0, "SparkleOverlay", { default = true, bg = "#0c1230", fg = "#c8d4f4" })

return M
