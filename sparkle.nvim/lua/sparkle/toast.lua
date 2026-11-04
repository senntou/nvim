-- sparkle.toast: a little "SAVED!" pop-up (bottom right) whenever a buffer is written.
local overlay = require("sparkle.overlay")
local C = require("sparkle.canvas")
local font = require("sparkle.font")
local api = vim.api
local floor, max, min, abs, sin = math.floor, math.max, math.min, math.abs, math.sin
local pal = overlay.pal

local M = {}

M.config = {
  duration = 1.6,
  word = "SAVED!",
}

local active = true
local cur -- the visible toast (one at a time)
local pending = {} -- buffers written in the current tick (:wa)

local function ease_out_back(t)
  t = C.clamp(t, 0, 1)
  local c1 = 1.70158
  local u = t - 1
  return 1 + (c1 + 1) * u * u * u + c1 * u * u
end

local G_WHITE, G_CYAN, G_BLUE, G_PINK = C.hex(0xffffff), C.hex(0x7ff3ff), C.hex(0x5a7cff), C.hex(0xd85cff)

local function logo_color(fy)
  if fy < 0.35 then return C.lerp(G_WHITE, G_CYAN, fy / 0.35) end
  if fy < 0.65 then return C.lerp(G_CYAN, G_BLUE, (fy - 0.35) / 0.3) end
  return C.lerp(G_BLUE, G_PINK, (fy - 0.65) / 0.35)
end

local function human(n)
  if n < 1024 then return n .. "B" end
  if n < 1024 * 1024 then return string.format("%.1fKB", n / 1024) end
  return string.format("%.1fMB", n / 1024 / 1024)
end

local function info_for(bufs)
  if #bufs > 1 then return string.format("✔ %d FILES WRITTEN", #bufs) end
  local b = bufs[1]
  local name = vim.fn.fnamemodify(api.nvim_buf_get_name(b), ":t")
  if name == "" then name = "[No Name]" end
  local lines = api.nvim_buf_line_count(b)
  local size = vim.fn.getfsize(api.nvim_buf_get_name(b))
  local s = string.format("✔ %s  %dL", name, lines)
  if size and size >= 0 then s = s .. "  " .. human(size) end
  return s
end

local function show(bufs)
  if cur then cur:close() end
  local info = C.truncate(info_for(bufs), 46)
  local L = font.mask(M.config.word, 1, 6)
  local width = max(L.w + 6, C.width(info) + 4)
  local height = 7
  local parts = {}
  local burst_done = false
  local D = M.config.duration
  local row = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)
  cur = overlay.open({
    anchor = "SE", row = row, col = vim.o.columns - 1, width = width, height = height, zindex = 70, fps = 30,
  }, function(c, t, dt, ov)
    overlay.backdrop(c, t, pal.panel, 0.04)
    c:clear_text()
    -- sweeping shine + popping letters
    local lx = floor((c.pw - L.w) / 2)
    local ly = 2
    local sweep = (t - 0.35) * 70 - 10
    for x = 0, L.w - 1 do
      local letter = floor(x / L.adv)
      local lt = C.clamp((t - 0.05 * letter) / 0.35, 0, 1)
      if lt > 0 then
        local yoff = floor((1 - ease_out_back(lt)) * 6 + 0.5)
        for y = 0, L.h - 1 do
          if L.at(x, y) then
            local col = logo_color(y / (L.h - 1))
            if not L.at(x, y - 1) then col = C.add(col, G_WHITE, 0.35) end
            local d = abs(x + (L.h - y) * 0.7 - sweep)
            if d < 3 then col = C.lerp(col, G_WHITE, (1 - d / 3) * 0.9) end
            c:pblend(lx + x + 1, ly + y + yoff + 1, C.hex(0x05020c), 0.8)
            c:pset(lx + x, ly + y + yoff, col)
          end
        end
      end
    end
    if t > 0.3 and not burst_done then
      burst_done = true
      overlay.burst(parts, lx + L.w / 2, ly + 3, 28, { pal.cyan, pal.magenta, pal.gold, pal.white }, 1.4)
    end
    -- twinkles at the corners of the word
    local tw = max(0, sin((t - 0.6) * 5))
    if t > 0.6 then
      overlay.twinkle(c, lx + L.w + 1, ly - 0.5, tw)
      overlay.twinkle(c, lx - 2, ly + L.h, max(0, sin((t - 0.8) * 5)), pal.cyan)
    end
    overlay.particles(c, parts, dt)
    overlay.frame(c, t, pal.cyan, pal.magenta, { speed = 0.9 })
    local ia = C.clamp((t - 0.25) / 0.3, 0, 1)
    c:put_gradient(2, 5, info, C.scale(pal.gold, ia), C.scale(pal.text, ia))
    -- fade out
    if t > D - 0.4 then ov:set_blend((t - (D - 0.4)) / 0.4 * 100) end
    return t < D
  end)
  if cur then
    local me = cur
    me.on_close = function() if cur == me then cur = nil end end
  end
end

function M.saved(buf)
  if not active then return end
  if vim.bo[buf].buftype ~= "" then return end
  pending[#pending + 1] = buf
  if #pending > 1 then return end
  vim.schedule(function()
    local bufs = pending
    pending = {}
    if #api.nvim_list_uis() > 0 then show(bufs) end
  end)
end

function M.set_active(on)
  active = on
  if not on and cur then cur:close() end
end

function M.setup()
  local grp = api.nvim_create_augroup("SparkleToast", { clear = true })
  api.nvim_create_autocmd("BufWritePost", {
    group = grp,
    callback = function(ev) M.saved(ev.buf) end,
  })
end

return M
