-- sparkle.dashboard: SHOOTIE-style animated start screen for Neovim.
-- Nebula + parallax starfield, a shiny bevelled pixel logo that drops in, a ship flying past,
-- and an arcade menu with a glowing highlight bar.
-- calm style: the same layout drawn once in the colorscheme's colours (redrawn only on input/resize).

local C = require("sparkle.canvas")
local font = require("sparkle.font")
local hex, lerp, scale, add, hsv, clamp = C.hex, C.lerp, C.scale, C.add, C.hsv, C.clamp
local floor, max, min, abs, sin, sqrt = math.floor, math.max, math.min, math.abs, math.sin, math.sqrt
local api, uv = vim.api, vim.uv or vim.loop
local theme = require("sparkle.theme")

local M = {}

local calm = false

M.config = {
  title = "NEOVIM",
  subtitle = "HYPEREXTENSIBLE EDITOR",
  fps = 30,
  star_speed = 1.0, -- parallax scroll speed multiplier (lower = calmer + cheaper)
  idle_fps = 10, -- after `idle_after` seconds without input the animation slows down to save CPU
  idle_after = 15,
}

local S = nil -- live state (one dashboard at a time)

local pal = {
  navy = hex(0x0a0f24),
  panel = hex(0x0c1230),
  border = hex(0x2f78b8),
  cyan = hex(0x46e0ff),
  magenta = hex(0xff4fd8),
  purple = hex(0x9a5cff),
  gold = hex(0xffd34d),
  white = hex(0xf4f7ff),
  text = hex(0xc8d4f4),
  dim = hex(0x6a7499),
  faint = hex(0x3a4366),
}

---------------------------------------------------------------- menu
local function try(fn)
  return function()
    local ok, err = pcall(fn)
    if not ok then vim.notify("sparkle: " .. tostring(err), vim.log.levels.WARN) end
  end
end

local function telescope(picker, fallback)
  return try(function()
    local ok, b = pcall(require, "telescope.builtin")
    if ok then b[picker]() else vim.cmd(fallback) end
  end)
end

M.items = {
  { key = "f", label = "FIND FILE", run = telescope("find_files", "edit .") },
  { key = "r", label = "RECENT FILES", run = telescope("oldfiles", "browse oldfiles") },
  { key = "g", label = "LIVE GREP", run = telescope("live_grep", "") },
  { key = "n", label = "NEW FILE", run = try(function() vim.cmd("enew") end) },
  {
    key = "c",
    label = "CONFIG",
    run = try(function() vim.cmd("edit " .. vim.fn.fnameescape(vim.fn.stdpath("config") .. "/init.lua")) end),
  },
  { key = "l", label = "LAZY", run = try(function() vim.cmd("Lazy") end) },
  { key = "q", label = "QUIT", run = try(function() vim.cmd("qa") end) },
}

---------------------------------------------------------------- noise / nebula
local NW, NH = 512, 128

local function hash(ix, iy, seed)
  local s = sin(ix * 127.1 + iy * 311.7 + seed * 74.7) * 43758.5453
  return s - floor(s)
end

local function smooth(t) return t * t * (3 - 2 * t) end

local function noise_tex(seed)
  local tex = {}
  local octaves = { { 32, 0.55 }, { 16, 0.3 }, { 8, 0.15 } }
  for y = 0, NH - 1 do
    for x = 0, NW - 1 do
      local v = 0
      for _, o in ipairs(octaves) do
        local cs, w = o[1], o[2]
        local P = NW / cs
        local fx, fy = x / cs, y / cs
        local ix, iy = floor(fx), floor(fy)
        local tx, ty = smooth(fx - ix), smooth(fy - iy)
        local a = hash(ix % P, iy, seed + cs)
        local b = hash((ix + 1) % P, iy, seed + cs)
        local c = hash(ix % P, iy + 1, seed + cs)
        local d = hash((ix + 1) % P, iy + 1, seed + cs)
        v = v + w * ((a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * ty)
      end
      tex[y * NW + x] = v
    end
  end
  return tex
end

local NA, NB -- lazily built noise textures

local function build_background(pw, ph, nstep, mstep)
  NA = NA or noise_tex(1)
  NB = NB or noise_tex(7)
  local R, G, B = {}, {}, {}
  local top, bot = hex(0x03040c), hex(0x0a0618)
  local pA = lerp(hex(0x3c1866), hex(0x101e5a), 0.35)
  local pB = lerp(hex(0x0c3450), hex(0x4a1450), 0.35)
  for y = 0, ph - 1 do
    local base = lerp(top, bot, y / max(1, ph))
    local ty = floor((y * NH) / max(1, ph) / 2) + 20
    for x = 0, pw - 1 do
      local n = NA[(ty % NH) * NW + (floor(x * 0.8) + nstep) % NW]
      local m = NB[((ty + 40) % NH) * NW + (floor(x * 0.6) + mstep + 50) % NW]
      local neb = clamp((n - 0.4) / 0.55, 0, 1)
      neb = smooth(neb) * 0.9
      local i = y * pw + x + 1
      R[i] = min(255, base[1] + (pA[1] + (pB[1] - pA[1]) * m) * neb)
      G[i] = min(255, base[2] + (pA[2] + (pB[2] - pA[2]) * m) * neb)
      B[i] = min(255, base[3] + (pA[3] + (pB[3] - pA[3]) * m) * neb)
    end
  end
  return R, G, B
end

---------------------------------------------------------------- stars
local WRAP = 1024

local function make_layer(n, seed)
  local l = {}
  for i = 1, n do
    l[i] = {
      x = hash(i, 1, seed) * WRAP,
      y = hash(i, 2, seed),
      b = 0.35 + 0.65 * hash(i, 3, seed),
      freq = 1.5 + 3 * hash(i, 4, seed),
      phase = hash(i, 5, seed) * 6.283,
    }
  end
  return l
end

local STARS = { far = make_layer(220, 11), mid = make_layer(110, 23), near = make_layer(36, 37) }

local function star_layer(c, layer, H, scroll, t, tint, bright, streak)
  local W = c.pw
  for _, s in ipairs(layer) do
    local x = (s.x - scroll) % WRAP - 16
    if x < W + 16 then
      local ix, iy = floor(x), floor(s.y * H)
      local tw = 0.65 + 0.35 * floor(2 * sin(t * s.freq + s.phase) + 0.5) * 0.5
      local col = scale(tint, s.b * bright * tw)
      c:padd(ix, iy, col)
      if streak then
        for k = 1, streak do c:padd(ix + k, iy, col, 0.7 * (1 - k / (streak + 1))) end
      end
      if s.b > 0.93 and bright > 0.7 then
        local k = 0.35 * tw
        c:padd(ix - 1, iy, col, k); c:padd(ix + 1, iy, col, k)
        c:padd(ix, iy - 1, col, k); c:padd(ix, iy + 1, col, k)
      end
    end
  end
end

local function draw_stars(c, t)
  local h = c.ph
  local bands = max(1, floor((h + 59) / 60))
  for b = 0, bands - 1 do
    local bh = min(60, h - b * 60)
    if bh <= 0 then break end
    -- draw into a band by offsetting y
    local proxy = setmetatable({ pw = c.pw }, {
      __index = {
        padd = function(_, x, y, col, k) c:padd(x, y + b * 60, col, k) end,
      },
    })
    local v = t * M.config.star_speed
    star_layer(proxy, STARS.far, bh, v * 2.0 + b * 97, t, hex(0x8890c0), 0.6)
    star_layer(proxy, STARS.mid, bh, v * 6.0 + b * 211, t, hex(0xb8c8f0), 0.8)
    star_layer(proxy, STARS.near, bh, v * 16.0 + b * 331, t, hex(0xffffff), 1.0, 2)
  end
  -- occasional shooting star
  local cyc = t % 5.5
  if cyc < 0.9 then
    local n = floor(t / 5.5)
    local w = c.pw
    local sx, sy = (0.3 + 0.6 * hash(n, 61, 0)) * w, (0.05 + 0.3 * hash(n, 62, 0)) * h
    local p = cyc / 0.9
    local hx, hy = sx - p * w * 0.35, sy + p * w * 0.12
    for k = 0, 17 do
      c:padd(hx + k * 1.9, hy - k * 0.66, hex(0xd0e8ff), (1 - k / 18) * (1 - p))
    end
    c:glow(hx, hy, 2.5, hex(0x80c0ff), 0.8 * (1 - p))
  end
end

---------------------------------------------------------------- logo
local function ease_out_back(t)
  t = clamp(t, 0, 1)
  local c1 = 1.70158
  local c3 = c1 + 1
  local u = t - 1
  return 1 + c3 * u * u * u + c1 * u * u
end

local SHADOW1, SHADOW2 = hex(0x12041e), hex(0x0a0214)
local G_WHITE, G_CYAN, G_BLUE, G_PINK = hex(0xffffff), hex(0x7ff3ff), hex(0x5a7cff), hex(0xd85cff)

local function draw_logo(c, L, lx, ly, t)
  local intro = clamp(t / 1.2, 0, 1)
  c:glow(lx + L.w / 2, ly + L.h / 2, L.w * 0.45, hex(0x5020a0), 0.35 * intro)
  local sp = (t % 4) / 1.1
  local sweep_x = sp * (L.w + L.h + 30) - 15 - L.h
  local tq = floor(t)
  for pass = 0, 1 do
    for x = 0, L.w - 1 do
      local letter = min(L.n - 1, floor(x / L.adv))
      local lt = clamp((t - 0.08 * letter) / 0.7, 0, 1)
      if lt > 0 then
        local yoff = floor((1 - ease_out_back(lt)) * -(ly + L.h + 4) + 0.5)
        yoff = yoff + floor(sin(t * 2 + letter * 0.7) * 0.6 + 0.5)
        local drift = lerp(G_WHITE, hsv(0.55 + 0.25 * sin(tq * 0.5 + x * 0.03), 0.6, 1), 1)
        for y = 0, L.h - 1 do
          if L.at(x, y) then
            local px, py = lx + x, ly + y + yoff
            if pass == 0 then
              c:pblend(px + L.scale, py + L.scale, SHADOW1, 0.9)
              c:pblend(px + L.scale + 1, py + L.scale + 1, SHADOW2, 0.6)
            else
              local fy = y / max(1, L.h - 1)
              local col
              if fy < 0.35 then col = lerp(G_WHITE, G_CYAN, fy / 0.35)
              elseif fy < 0.65 then col = lerp(G_CYAN, G_BLUE, (fy - 0.35) / 0.3)
              else col = lerp(G_BLUE, G_PINK, (fy - 0.65) / 0.35) end
              col = lerp(col, drift, 0.18)
              if not L.at(x, y - 1) then col = add(col, G_WHITE, 0.35) end
              if not L.at(x, y + 1) then col = scale(col, 0.62) end
              local d = abs(x + (L.h - y) * 0.7 - sweep_x)
              if d < 3.5 then col = lerp(col, G_WHITE, (1 - d / 3.5) * 0.85) end
              c:pset(px, py, col)
            end
          end
        end
      end
    end
  end
  -- sparkle on the last letter once the sweep passes
  if sp > 0.85 and sp < 1.2 then
    local k = 1 - abs(sp - 1.0) / 0.2
    local sx, sy = lx + L.w - 2, ly + 1
    c:glow(sx, sy, 3, G_WHITE, k)
    for i = 1, 3 do
      local a = k * (1 - i / 4)
      c:padd(sx + i, sy, G_WHITE, a); c:padd(sx - i, sy, G_WHITE, a)
      c:padd(sx, sy + i, G_WHITE, a); c:padd(sx, sy - i, G_WHITE, a)
    end
  end
end

---------------------------------------------------------------- ship
local SHIP_PAL = {
  W = hex(0xFFFFFF), C = hex(0x5ADCFF), G = hex(0xA8F4FF), L = hex(0xC4D0E2),
  S = hex(0x7C8CA8), D = hex(0x434C66), B = hex(0x2C6CD8), R = hex(0xFF4A68),
}
local SHIP = {
  { "RSD......", ".DSLLC...", ".DSLBGGCW", ".DSLLC...", "RSD......" },
  { "DD.......", ".DSSC....", ".DSLBGGCW", ".DLLLC...", "RLSD....." },
  { "RLSD.....", ".DLLLC...", ".DSLBGGCW", ".DSSC....", "DD......." },
}

local function draw_ship(c, base_y, t)
  local period, fly = 7, 2.6
  local ct = (t + 4.5) % period
  if ct > fly then return end
  local p = ct / fly
  local x = -12 + p * (c.pw + 24)
  local y = base_y + 3 + sin(p * 6.283 * 1.5) * 2
  local vy = math.cos(p * 6.283 * 1.5)
  for k = 1, 10 do
    local a = 1 - k / 11
    c:padd(x - 4 - k * 2.2, floor(y + sin(p * 9 - k * 0.4) * 0.6 + 0.5),
      lerp(hex(0x40c8ff), hex(0xb040ff), k / 10), a * 0.8)
  end
  c:glow(x - 4, y, 2.5, hex(0x40c8ff), 0.6)
  local art = SHIP[vy > 0.5 and 3 or (vy < -0.5 and 2 or 1)]
  local ox, oy = floor(x - 4.5), floor(y - 2.5)
  for r = 1, #art do
    local row = art[r]
    for i = 1, #row do
      local col = SHIP_PAL[row:sub(i, i)]
      if col then c:pset(ox + i - 1, oy + r - 1, col) end
    end
  end
end

---------------------------------------------------------------- particles
local function burst(px, py, n, cols)
  for _ = 1, n do
    local a = math.random() * 6.283
    local sp = 8 + math.random() * 22
    table.insert(S.parts, {
      x = px, y = py, vx = math.cos(a) * sp, vy = math.sin(a) * sp * 0.6,
      life = 0.35 + math.random() * 0.35, age = 0,
      col = cols[math.random(#cols)],
    })
  end
end

local function draw_particles(c, dt)
  local keep = {}
  for _, p in ipairs(S.parts) do
    p.age = p.age + dt
    if p.age < p.life then
      p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
      p.vx, p.vy = p.vx * 0.92, p.vy * 0.92
      local k = 1 - p.age / p.life
      c:padd(p.x, p.y, p.col, k)
      c:glow(p.x, p.y, 1.8, p.col, 0.4 * k)
      keep[#keep + 1] = p
    end
  end
  S.parts = keep
end

---------------------------------------------------------------- UI widgets
local function panel(c, col, row, w, h, border, alpha)
  c:fill_rect(col, row * 2, w, h * 2, pal.panel, alpha)
  c:fill_rect(col + 1, row * 2 + 1, w - 2, 2, lerp(pal.panel, border, 0.25), alpha * 0.5)
  local hz = string.rep("─", w - 2)
  c:put(col, row, "╭" .. hz .. "╮", border)
  c:put(col, row + h - 1, "╰" .. hz .. "╯", border)
  for r = row + 1, row + h - 2 do
    c:put(col, r, "│", border)
    c:put(col + w - 1, r, "│", border)
  end
end

local function highlight_bar(c, col, pixel_y, w, t, a, b)
  local pulse = 0.55 + 0.2 * floor(sin(t * 5) * 3 + 0.5) / 3
  local y = floor(pixel_y + 0.5)
  for x = 0, w - 1 do
    local u = x / max(1, w - 1)
    local sheen = max(0, 1 - abs(u - (t * 0.5) % 1.6 + 0.3) * 6)
    local cc = add(lerp(a, b, u), pal.white, sheen * 0.25)
    local edge = min(1, min(x + 1, w - x) / 3)
    c:fill_rect(col + x, y, 1, 2, cc, pulse * edge)
  end
end

local function spaced(s)
  return (s:gsub(".", "%0 "):gsub(" $", ""))
end

local function info_line()
  local ok, lazy = pcall(require, "lazy")
  local v = vim.version()
  local s = string.format("NVIM V%d.%d.%d", v.major, v.minor, v.patch)
  if ok then
    local st = lazy.stats()
    s = s .. string.format("   PLUGINS %d/%d   %.1fMS", st.loaded, st.count, st.startuptime)
  end
  return s
end

---------------------------------------------------------------- calm scene
local function draw_calm(c)
  local th = theme.colors()
  local cols, rows, pw = c.cols, c.rows, c.pw
  c:fill_rect(0, 0, pw, c.ph, th.bg, 1)
  c:clear_text()

  local oy = max(0, floor((rows - 24) / 2))
  local cx = floor(cols / 2)

  -- logo: flat, two-tone from the colorscheme
  local title = M.config.title
  local sc, adv = 2, 12
  if adv * (#title - 1) + 10 > pw - 4 then adv = 11 end
  if adv * (#title - 1) + 10 > pw - 4 then sc, adv = 1, 6 end
  if not S.logo or S.logo.scale ~= sc or S.logo.adv ~= adv or S.logo_word ~= title then
    S.logo, S.logo_word = font.mask(title, sc, adv), title
  end
  local L = S.logo
  local lx, ly = floor((pw - L.w) / 2), (oy + 1) * 2 + 1
  for x = 0, L.w - 1 do
    for y = 0, L.h - 1 do
      if L.at(x, y) then
        local col = lerp(th.title, th.accent, y / max(1, L.h - 1))
        if not L.at(x, y + 1) then col = lerp(col, th.bg, 0.3) end
        c:pset(lx + x, ly + y, col)
      end
    end
  end

  local row = oy + 1 + floor((L.h + 1) / 2) + 1
  c:putc(cx, row, spaced(M.config.subtitle), th.accent2, { bold = true })
  row = row + 1
  c:putc(cx, row, S.info or "", th.dim)
  row = row + 2

  -- menu
  local items = M.items
  local mw, mh = 34, #items + 2
  local mx, my = cx - floor(mw / 2), row
  local hz = string.rep("─", mw - 2)
  c:put(mx, my, "╭" .. hz .. "╮", th.border)
  c:put(mx, my + mh - 1, "╰" .. hz .. "╯", th.border)
  for r = my + 1, my + mh - 2 do
    c:put(mx, r, "│", th.border)
    c:put(mx + mw - 1, r, "│", th.border)
  end
  S.cursor = S.sel
  c:fill_rect(mx + 2, (my + 1 + S.sel) * 2, mw - 4, 2, th.sel_bg, 1)
  for i, it in ipairs(items) do
    local sel = (i - 1) == S.sel
    local r = my + i
    if sel then
      c:put(mx + 3, r, "▶", th.accent, { bold = true })
      c:put(mx + mw - 4, r, "◀", th.accent, { bold = true })
    end
    c:put(mx + 7, r, it.key:upper(), sel and th.special or th.dim, { bold = true })
    c:put(mx + 10, r, it.label, sel and th.fg or th.dim, { bold = sel })
  end
  S.menu = { mx = mx, my = my, mw = mw }
  row = my + mh + 1

  local fr = rows - 1
  if fr > row then
    c:put(1, fr, "J/K SELECT  ENTER OK  Q QUIT", th.dim)
    local ver = "SPARKLE V0.1"
    c:put(cols - C.width(ver) - 1, fr, ver, th.dim)
  end
end

---------------------------------------------------------------- scene
local function draw(c, t, dt)
  if calm then return draw_calm(c) end
  local cols, rows, pw, ph = c.cols, c.rows, c.pw, c.ph

  -- background: nebula is cached and only re-rendered when its (whole-pixel) scroll step changes
  local nstep, mstep = floor(t * 0.25), floor(t * 0.15)
  local bk = pw .. "x" .. ph .. ":" .. nstep .. ":" .. mstep
  if S.bg_key ~= bk then
    S.bgR, S.bgG, S.bgB = build_background(pw, ph, nstep, mstep)
    S.bg_key = bk
  end
  c:blit(S.bgR, S.bgG, S.bgB)
  c:clear_text()
  draw_stars(c, t)

  local oy = max(0, floor((rows - 24) / 2))
  local cx = floor(cols / 2)

  -- logo
  local title = M.config.title
  local sc, adv = 2, 12
  if adv * (#title - 1) + 10 > pw - 4 then adv = 11 end
  if adv * (#title - 1) + 10 > pw - 4 then sc, adv = 1, 6 end
  if not S.logo or S.logo.scale ~= sc or S.logo.adv ~= adv or S.logo_word ~= title then
    S.logo, S.logo_word = font.mask(title, sc, adv), title
  end
  local L = S.logo
  local lx, ly = floor((pw - L.w) / 2), (oy + 1) * 2 + 1
  draw_logo(c, L, lx, ly, t)
  draw_ship(c, ly + floor(L.h / 2) - 3, t)

  local row = oy + 1 + floor((L.h + 1) / 2) + 1
  local sub = spaced(M.config.subtitle)
  local sub_a = clamp((t - 0.8) / 0.6, 0, 1)
  if sub_a > 0 then
    c:put_gradient(cx - floor(C.width(sub) / 2), row, sub, scale(pal.cyan, sub_a), scale(pal.magenta, sub_a),
      { bold = true })
  end
  row = row + 1
  c:putc(cx, row, S.info or "", pal.gold)
  row = row + 2

  -- menu
  local items = M.items
  local N = #items
  local mw, mh = 34, N + 2
  local mx, my = cx - floor(mw / 2), row
  panel(c, mx, my, mw, mh, pal.border, 0.78)
  S.cursor = S.cursor + (S.sel - S.cursor) * min(1, dt * 18)
  highlight_bar(c, mx + 2, (my + 1 + S.cursor) * 2, mw - 4, t, pal.magenta, pal.cyan)
  for i, it in ipairs(items) do
    local sel = (i - 1) == S.sel
    local r = my + i
    if sel then
      local bob = floor(sin(t * 7) * 0.8 + 0.2 + 0.5)
      c:put(mx + 3 + bob, r, "▶", pal.white, { bold = true })
      c:put(mx + mw - 4 - bob, r, "◀", pal.white, { bold = true })
    end
    c:put(mx + 7, r, it.key:upper(), sel and pal.gold or pal.faint, { bold = true })
    c:put(mx + 10, r, it.label, sel and pal.white or pal.dim, { bold = sel })
  end
  S.menu = { mx = mx, my = my, mw = mw }
  row = my + mh + 1
  if (t - S.blink_reset) % 1.1 < 0.7 then
    c:putc(cx, row, "- PRESS ENTER -", pal.gold, { bold = true })
  end

  draw_particles(c, dt)

  -- confirm flash
  if S.flash > 0 then
    local k = S.flash
    c:fill_rect(0, 0, pw, ph, pal.white, 0.35 * k)
    S.flash = max(0, S.flash - dt * 10)
  end

  -- footer
  local fr = rows - 1
  if fr > row then
    c:fill_rect(0, fr * 2, pw, 2, pal.navy, 0.85)
    c:put(1, fr, "J/K SELECT  ENTER OK  Q QUIT", pal.dim)
    local ver = "SPARKLE V0.1"
    c:put(cols - C.width(ver) - 1, fr, ver, pal.faint)
  end
end

---------------------------------------------------------------- frame loop
local function stop()
  if S and S.timer then
    S.timer:stop()
    S.timer:close()
    S.timer = nil
  end
end

local function find_win()
  if not S then return nil end
  if S.win and api.nvim_win_is_valid(S.win) and api.nvim_win_get_buf(S.win) == S.buf then return S.win end
  for _, w in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(w) == S.buf then
      S.win = w
      return w
    end
  end
end

local function frame()
  if not S or not api.nvim_buf_is_valid(S.buf) then return stop() end
  local win = find_win()
  if not win then return stop() end
  local cols, rows = api.nvim_win_get_width(win), api.nvim_win_get_height(win)
  if not S.canvas then
    S.canvas = C.new(cols, rows)
  elseif S.canvas.cols ~= cols or S.canvas.rows ~= rows then
    S.canvas:resize(cols, rows)
  end
  local now = uv.hrtime() / 1e9
  local t = now - S.t0
  local dt = clamp(now - (S.last or now), 0, 0.1)
  S.last = now
  if not S.info or floor(t) ~= S.info_t then
    S.info, S.info_t = info_line(), floor(t)
  end

  local want = (t - S.last_input > M.config.idle_after) and M.config.idle_fps or M.config.fps
  if want ~= S.fps and S.timer then
    S.fps = want
    S.timer:set_repeat(floor(1000 / want))
  end

  local prof = vim.g.sparkle_profile and {}
  local h0 = prof and uv.hrtime()
  draw(S.canvas, t, dt)
  local h1 = prof and uv.hrtime()

  -- size changed (or vterm not resized yet): repaint everything for a few frames
  if S.size ~= cols .. "x" .. rows then
    S.size, S.repaint = cols .. "x" .. rows, 3
  end
  if S.repaint > 0 then
    S.repaint = S.repaint - 1
    S.canvas:invalidate_ansi()
  end
  local data = S.canvas:render_ansi()
  local h2 = prof and uv.hrtime()
  if data then api.nvim_chan_send(S.chan, data) end
  if prof then
    local h3 = uv.hrtime()
    local P = S.prof or { n = 0, draw = 0, render = 0, flush = 0, bytes = 0 }
    P.n, P.draw, P.render, P.flush = P.n + 1, P.draw + (h1 - h0) / 1e6, P.render + (h2 - h1) / 1e6, P.flush + (h3 - h2) / 1e6
    P.bytes = P.bytes + (data and #data or 0)
    P.dirty = (P.dirty or 0) + S.canvas.dirty_rows
    S.prof = P
  end
end

function M.profile()
  local P = S and S.prof
  if not P or P.n == 0 then return nil end
  return string.format("frames %d  draw %.2fms  render %.2fms  send %.2fms  %.1fKB/frame  dirty rows %.1f/%d",
    P.n, P.draw / P.n, P.render / P.n, P.flush / P.n, P.bytes / P.n / 1024, (P.dirty or 0) / P.n, S.canvas.rows)
end

-- calm: no timer, just draw (a few times: a freshly opened/resized terminal may not have its
-- final size yet and would show the first picture shifted)
local function kick()
  for _, ms in ipairs({ 0, 50, 150 }) do
    vim.defer_fn(function()
      if S and not S.timer and find_win() then frame() end
    end, ms)
  end
end

local function start()
  if not S or S.timer then return end
  if calm then return kick() end
  S.last = nil
  S.timer = uv.new_timer()
  S.fps = M.config.fps
  S.last_input = uv.hrtime() / 1e9 - S.t0
  S.timer:start(0, floor(1000 / S.fps), vim.schedule_wrap(frame))
end

---------------------------------------------------------------- cursor hiding
local saved_guicursor
local function hide_cursor()
  if saved_guicursor then return end
  saved_guicursor = vim.o.guicursor
  api.nvim_set_hl(0, "SparkleHiddenCursor", { blend = 100, nocombine = true })
  vim.o.guicursor = "a:SparkleHiddenCursor/lCursor"
end
local function show_cursor()
  if not saved_guicursor then return end
  vim.o.guicursor = saved_guicursor
  saved_guicursor = nil
end

---------------------------------------------------------------- input
local function move(d)
  local N = #M.items
  S.sel = (S.sel + d) % N
  S.blink_reset = uv.hrtime() / 1e9 - S.t0
  S.last_input = S.blink_reset
  if calm then return frame() end
  if S.menu then
    burst(S.menu.mx + 4, (S.menu.my + 1 + S.sel) * 2 + 1, 10, { pal.cyan, pal.magenta, pal.white })
    burst(S.menu.mx + S.menu.mw - 4, (S.menu.my + 1 + S.sel) * 2 + 1, 10, { pal.cyan, pal.magenta, pal.white })
  end
end

local function activate(i)
  local it = M.items[i]
  if not it then return end
  S.sel = i - 1
  if calm then
    frame()
    vim.schedule(it.run)
    return
  end
  S.flash = 1
  S.last_input = uv.hrtime() / 1e9 - S.t0
  if S.menu then burst(S.menu.mx + floor(S.menu.mw / 2), (S.menu.my + i) * 2 + 1, 30, { pal.gold, pal.white, pal.cyan }) end
  vim.defer_fn(it.run, 120)
end

local function map(buf)
  local o = { buffer = buf, nowait = true, silent = true }
  -- (<C-n>/<C-p> are left alone: they are global maps for NvimTree / Telescope)
  for _, k in ipairs({ "j", "<Down>", "<Tab>" }) do vim.keymap.set("n", k, function() move(1) end, o) end
  for _, k in ipairs({ "k", "<Up>", "<S-Tab>" }) do vim.keymap.set("n", k, function() move(-1) end, o) end
  vim.keymap.set("n", "<CR>", function() activate(S.sel + 1) end, o)
  vim.keymap.set("n", "<Space>", function() activate(S.sel + 1) end, o)
  for i, it in ipairs(M.items) do
    vim.keymap.set("n", it.key, function() activate(i) end, o)
  end
  for _, k in ipairs({ "i", "a", "I", "A", "o", "O", "s", "S", "c", "C" }) do
    if not vim.tbl_contains(vim.tbl_map(function(x) return x.key end, M.items), k) then
      vim.keymap.set("n", k, "<Nop>", o)
    end
  end
  vim.keymap.set("n", "<LeftMouse>", function()
    local pos = vim.fn.getmousepos()
    if S.menu and pos.winid == S.win then
      local i = pos.line - 1 - S.menu.my
      if i >= 1 and i <= #M.items then activate(i) end
    end
  end, o)
end

---------------------------------------------------------------- sessions
-- The dashboard is a terminal buffer, which :mksession cannot restore (E474: buftype=terminal).
-- Before a session is saved, swap it out for an empty buffer (keeping the window) and wipe it.
function M.detach()
  if not S or not api.nvim_buf_is_valid(S.buf) then return end
  local buf, chan = S.buf, S.chan
  for _, w in ipairs(vim.fn.win_findbuf(buf)) do
    api.nvim_win_call(w, function() vim.cmd("enew") end)
  end
  pcall(vim.fn.chanclose, chan)
  pcall(api.nvim_buf_delete, buf, { force = true })
end

-- After a session restore: show the dashboard in the first empty editor window, if any.
function M.open_in_empty()
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local b = api.nvim_win_get_buf(w)
    if api.nvim_win_get_config(w).relative == "" and vim.bo[b].buftype == "" and vim.bo[b].filetype ~= "NvimTree"
      and api.nvim_buf_get_name(b) == "" and not vim.bo[b].modified and api.nvim_buf_line_count(b) == 1
      and api.nvim_buf_get_lines(b, 0, 1, false)[1] == "" then
      api.nvim_set_current_win(w)
      M.open()
      return true
    end
  end
  return false
end

function M.set_calm(c)
  if c == calm then return end
  calm = c
  if not S then return end
  stop()
  S.repaint = 3
  if find_win() then start() end
end

---------------------------------------------------------------- open
function M.open()
  local win = api.nvim_get_current_win()
  -- never take over a sidebar (NvimTree, quickfix, ...) or a float: use a normal editor window
  local function normal_win(w)
    local b = api.nvim_win_get_buf(w)
    if api.nvim_win_get_config(w).relative ~= "" then return false end
    return vim.bo[b].filetype == "sparkle" or (vim.bo[b].buftype == "" and vim.bo[b].filetype ~= "NvimTree")
  end
  if not normal_win(win) then
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
      if normal_win(w) then
        win = w
        break
      end
    end
    if win ~= api.nvim_get_current_win() then api.nvim_set_current_win(win) end
  end
  if S and api.nvim_buf_is_valid(S.buf) then
    api.nvim_set_current_buf(S.buf)
    return
  end
  local prev_buf = api.nvim_win_get_buf(win)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(win, buf)
  for k, v in pairs({
    number = false, relativenumber = false, cursorline = false, cursorcolumn = false,
    signcolumn = "no", foldcolumn = "0", colorcolumn = "", list = false, wrap = false,
    spell = false, statuscolumn = "", fillchars = "eob: ", sidescrolloff = 0, scrolloff = 0,
  }) do
    vim.wo[win][0][k] = v
  end
  -- The picture is drawn by streaming 24-bit ANSI escapes into a terminal buffer: no highlight
  -- groups are needed and only changed cells are sent (like SHOOTIE's own renderer).
  local chan = api.nvim_open_term(buf, { on_input = function() end })
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].scrollback = 1
  vim.bo[buf].filetype = "sparkle"

  -- drop the empty startup buffer this replaced
  if prev_buf ~= buf and api.nvim_buf_is_valid(prev_buf) and api.nvim_buf_get_name(prev_buf) == ""
    and not vim.bo[prev_buf].modified and vim.bo[prev_buf].buftype == ""
    and api.nvim_buf_line_count(prev_buf) == 1 and api.nvim_buf_get_lines(prev_buf, 0, 1, false)[1] == "" then
    pcall(api.nvim_buf_delete, prev_buf, {})
  end

  S = { buf = buf, win = win, chan = chan, t0 = uv.hrtime() / 1e9, sel = 0, cursor = 0, repaint = 0,
    parts = {}, flash = 0, blink_reset = 0, last_input = 0 }
  map(buf)

  local grp = api.nvim_create_augroup("SparkleDashboardBuf", { clear = true })
  -- Animate while the dashboard is visible in some window, even if focus is elsewhere
  -- (e.g. NvimTree). Pause only while a floating window (Telescope etc.) has focus, so
  -- pickers opened on top stay snappy, or while no window shows the dashboard.
  local function update()
    if not S or S.buf ~= buf or not api.nvim_buf_is_valid(buf) then return end
    if not find_win() then return stop() end
    local cur = api.nvim_get_current_win()
    if api.nvim_win_get_config(cur).relative ~= "" and api.nvim_win_get_buf(cur) ~= buf then
      return stop()
    end
    start()
  end
  api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "BufEnter", "WinClosed", "TabEnter" }, {
    group = grp, callback = function() vim.schedule(update) end,
  })
  -- the cursor is hidden only while the dashboard itself has focus
  api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, { group = grp, buffer = buf, callback = hide_cursor })
  api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, { group = grp, buffer = buf, callback = show_cursor })
  api.nvim_create_autocmd("BufWinLeave", { group = grp, buffer = buf, callback = show_cursor })
  -- terminal buffers ignore bufhidden=wipe while their channel is open: wipe it ourselves
  api.nvim_create_autocmd("BufHidden", { group = grp, buffer = buf, callback = function()
    vim.schedule(function()
      if api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) == 0 then
        pcall(vim.fn.chanclose, chan)
        pcall(api.nvim_buf_delete, buf, { force = true })
      end
    end)
  end })
  api.nvim_create_autocmd("BufWipeout", { group = grp, buffer = buf, callback = function()
    show_cursor(); stop(); S = nil
  end })
  api.nvim_create_autocmd("FocusLost", { group = grp, callback = stop })
  api.nvim_create_autocmd("FocusGained", { group = grp, callback = update })
  -- While paused (e.g. a float has focus and the layout changes underneath) the picture would
  -- stay at the old size: repaint a few frames so it is re-laid out once the terminal has resized.
  api.nvim_create_autocmd({ "WinResized", "VimResized", "ColorScheme" }, { group = grp, callback = function()
    if not S or S.timer or not find_win() then return end
    kick()
  end })

  hide_cursor()
  start()
end

return M
