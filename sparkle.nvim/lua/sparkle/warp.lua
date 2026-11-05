-- sparkle.warp: a short hyperspace jump when quitting Neovim.
local overlay = require("sparkle.overlay")
local C = require("sparkle.canvas")
local font = require("sparkle.font")
local api = vim.api
local floor, max, min, sin, cos, sqrt = math.floor, math.max, math.min, math.sin, math.cos, math.sqrt
local pal = overlay.pal

local M = {}

local active = true

M.config = {
  duration = 0.55, -- seconds (Neovim waits for this before exiting)
  stars = 260,
  word = "SEE YOU!", -- farewell word; false (or "") for the jump only
}

local function scene(stars, L)
  local D = M.config.duration
  return function(c, t)
    local pw, ph = c.pw, c.ph
    local cx, cy = pw / 2, ph / 2
    local p = min(1, t / D)
    -- background darkens in, nebula tint pulses
    local bgk = min(1, t / 0.12)
    local top, bot = C.hex(0x03040c), C.hex(0x10062a)
    for y = 0, ph - 1 do
      local base = C.scale(C.lerp(top, bot, y / max(1, ph - 1)), bgk)
      for x = 0, pw - 1 do
        local i = y * pw + x + 1
        c.R[i], c.G[i], c.B[i] = base[1], base[2], base[3]
      end
    end
    c:clear_text()
    c:glow(cx, cy, min(pw, ph * 2) * 0.35, C.hex(0x3a1a80), 0.5 * p)
    -- radial streaks: speed ramps up
    local speed = 0.2 + 3.5 * p * p
    for _, s in ipairs(stars) do
      local z = (s.z - t * speed) % 1
      local r0 = 1 / max(0.04, z) * s.r
      local r1 = 1 / max(0.04, z + 0.05 * (0.2 + p * 3)) * s.r
      local dx, dy = cos(s.a), sin(s.a) * 0.5
      local col = C.lerp(s.col, pal.white, 1 - z)
      local k = min(1, (1 - z) * 1.6) * bgk
      local steps = max(1, floor(r0 - r1))
      for j = 0, min(steps, 40) do
        local r = r1 + (r0 - r1) * j / steps
        c:padd(cx + dx * r, cy + dy * r, col, k * (j / steps))
      end
    end
    -- the farewell word zooms past
    if L then
      local lx, ly = floor((pw - L.w) / 2), floor((ph - L.h) / 2)
      local a = C.clamp(t / 0.15, 0, 1) * (1 - C.clamp((t - D * 0.7) / (D * 0.3), 0, 1))
      for x = 0, L.w - 1 do
        for y = 0, L.h - 1 do
          if L.at(x, y) then
            local col = C.lerp(pal.cyan, pal.magenta, x / L.w)
            if not L.at(x, y - 1) then col = C.add(col, pal.white, 0.4) end
            c:pblend(lx + x, ly + y, col, a)
          end
        end
      end
    end
    -- final white flash
    if p > 0.8 then
      c:fill_rect(0, 0, pw, ph, pal.white, (p - 0.8) / 0.2 * 0.9)
    end
    return true
  end
end

function M.play()
  if not active or M.played or #api.nvim_list_uis() == 0 or vim.v.dying > 0 then return end
  M.played = true
  local stars = {}
  local cols = { pal.cyan, pal.magenta, pal.purple, pal.white, C.hex(0x8ea0e0) }
  for i = 1, M.config.stars do
    stars[i] = {
      a = math.random() * 6.283, z = math.random(),
      r = 2 + math.random() * 6, col = cols[math.random(#cols)],
    }
  end
  local W, H = vim.o.columns, vim.o.lines
  local sc = (W >= 120 and H >= 30) and 2 or 1
  local word = M.config.word
  local L = (type(word) == "string" and word ~= "") and font.mask(word, sc, 6 * sc) or nil
  if L and L.w > W - 4 then L = nil end
  -- Terminal buffers stop refreshing once Neovim is exiting, so this one is drawn into a plain
  -- buffer with highlight extmarks instead of going through sparkle.overlay.
  local buf = api.nvim_create_buf(false, true)
  local ok, win = pcall(api.nvim_open_win, buf, false, {
    relative = "editor", row = 0, col = 0, width = W, height = H, zindex = 300,
    style = "minimal", focusable = false, noautocmd = true, border = "none",
  })
  if not ok then return end
  vim.wo[win].winhighlight = "Normal:SparkleOverlay"
  vim.wo[win].wrap = false
  local ns = api.nvim_create_namespace("sparkle.warp")
  local canvas = C.new(W, H)
  local draw = scene(stars, L)
  local t0 = (vim.uv or vim.loop).hrtime()
  local D = M.config.duration * 1e9
  while true do
    local el = (vim.uv or vim.loop).hrtime() - t0
    if el >= D then break end
    draw(canvas, el / 1e9)
    canvas:render_buf(buf, ns)
    vim.cmd("redraw")
    vim.wait(12)
  end
  pcall(api.nvim_win_close, win, true)
  pcall(api.nvim_buf_delete, buf, { force = true })
end

function M.set_active(on) active = on end

function M.setup()
  api.nvim_create_autocmd("VimLeavePre", {
    group = api.nvim_create_augroup("SparkleWarp", { clear = true }),
    callback = function() pcall(M.play) end,
  })
end

return M
