-- sparkle.stars: a faint, twinkling star field in the empty space of normal editor windows
-- (blank lines and the area right of the text), plus the occasional shooting star.
--
-- Stars are ephemeral overlay extmarks drawn by a decoration provider, so they never touch the
-- buffer, never hide text and cost nothing for lines that are off screen. Twinkling is done by
-- re-colouring a handful of highlight groups, not by moving marks.
local api, uv = vim.api, vim.uv or vim.loop
local style = require("sparkle.style")
local in_cmdline = style.in_cmdline
local floor, max, min, sin = math.floor, math.max, math.min, math.sin

local M = {}

-- per flashiness level (sparkle.style.level / :SparkleLevel)
--   density       chance of a star in each empty cell
--   dim, bright   star colour = mix(bg, tint, dim + bright * twinkle^2)
--   speed         twinkle speed multiplier
--   meteor_every  seconds between shooting stars (random in range)
--   glyphs        relative weights of the star glyphs (dot .. big star)
M.levels = {
  { density = 0.016, dim = 0.12, bright = 0.55, speed = 1.0, meteor_every = { 10, 25 }, glyphs = { 62, 14, 6, 5, 2, 3 } },
  { density = 0.026, dim = 0.22, bright = 0.65, speed = 1.2, meteor_every = { 6, 15 }, glyphs = { 50, 16, 10, 8, 5, 4 } },
  { density = 0.040, dim = 0.35, bright = 0.65, speed = 1.5, meteor_every = { 3, 8 }, glyphs = { 38, 16, 14, 12, 10, 5 } },
}

local function L() return M.levels[style.level] or M.levels[2] end

M.config = {
  margin = 4, -- cells kept clear right of the text
  fps = 8,
  idle_after = 30, -- seconds without input before twinkling pauses
  meteors = true, -- occasional shooting star
  exclude_ft = { "NvimTree", "sparkle", "lazy", "mason", "TelescopePrompt", "TelescopeResults", "alpha",
    "neo-tree", "Outline", "trouble", "qf", "DiffviewFiles", "NeogitStatus", "gitgraph" },
}

local ns = api.nvim_create_namespace("SparkleStars")
local NG = 6 -- twinkle groups
local timer
local last_input = uv.hrtime() / 1e9
local enabled = true
local glyphs -- { {glyph, weight}, ... } filtered to single-width glyphs
local cache, cache_w = {}, -1 -- [row] = { {col, glyph, group}, ... } for the current text width
local cache_n = 0
local meteor -- { win, t0, x0, y0, len, speed }
local next_meteor

---------------------------------------------------------------- helpers
local function now() return uv.hrtime() / 1e9 end

local function hash(a, b)
  local h = bit.bxor(bit.tobit(a * 374761393), bit.tobit(b * 668265263 + 1013904223))
  h = bit.bxor(h, bit.rshift(h, 13))
  h = bit.tobit(bit.band(h, 0xffff) * 1274126177 + bit.rshift(h, 16) * 2246822519)
  h = bit.bxor(h, bit.rshift(h, 16))
  return bit.band(h, 0xffffff) / 0x1000000
end

local function rgb(h) return { floor(h / 65536) % 256, floor(h / 256) % 256, h % 256 } end
local function mix(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end
local function pack(c)
  local q = function(v) return max(0, min(255, floor(v + 0.5))) end
  return q(c[1]) * 65536 + q(c[2]) * 256 + q(c[3])
end

local function bg_color()
  local ok, hl = pcall(api.nvim_get_hl, 0, { name = "Normal", link = false })
  if ok and hl and hl.bg then return rgb(hl.bg) end
  return vim.o.background == "light" and rgb(0xf4f0d9) or rgb(0x1e2326)
end

local function pick_glyphs()
  local w = L().glyphs
  local want = vim.o.ambiwidth == "double"
    and { { ".", w[1] + w[2] }, { "+", w[3] + w[6] }, { "*", w[4] + w[5] } }
    or { { "·", w[1] }, { "⋅", w[2] }, { "✧", w[3] }, { "⋆", w[4] }, { "✦", w[5] }, { "+", w[6] } }
  local out, total = {}, 0
  for _, g in ipairs(want) do
    if vim.fn.strdisplaywidth(g[1]) == 1 then
      total = total + g[2]
      out[#out + 1] = { g[1], total }
    end
  end
  for _, g in ipairs(out) do g[2] = g[2] / total end
  return out
end

local function glyph_for(u)
  for _, g in ipairs(glyphs) do
    if u <= g[2] then return g[1] end
  end
  return glyphs[#glyphs][1]
end

local function stars_for(row, width)
  if width ~= cache_w or cache_n > 4000 then cache, cache_w, cache_n = {}, width, 0 end
  local s = cache[row]
  if s then return s end
  s = {}
  local d = L().density
  for c = 0, width - 1 do
    if hash(row, c) < d then
      s[#s + 1] = { c, glyph_for(hash(c, row + 7919)), "SparkleStar" .. (floor(hash(row + 31, c + 17) * NG) + 1) }
    end
  end
  cache[row], cache_n = s, cache_n + 1
  return s
end

local excluded = {}
local function eligible(win, buf)
  if not enabled or vim.b[buf].sparkle_stars == false then return false end
  if vim.bo[buf].buftype ~= "" or excluded[vim.bo[buf].filetype] then return false end
  if api.nvim_win_get_config(win).relative ~= "" then return false end
  if vim.wo[win].diff then return false end
  return true
end

---------------------------------------------------------------- colours
local TINTS = { 0xf4f7ff, 0x9ff0ff, 0xc9b6ff, 0xffe6a0, 0xffb8ec, 0xb8ffd9 }
local bg
local function paint(t)
  bg = bg or bg_color()
  local lv = L()
  for i = 1, NG do
    local tint = rgb(TINTS[i])
    local tw = 0.5 + 0.5 * sin(t * lv.speed * (0.9 + 0.37 * i) + i * 1.7)
    local k = min(1, lv.dim + lv.bright * tw * tw)
    api.nvim_set_hl(0, "SparkleStar" .. i, { fg = pack(mix(bg, tint, k)), default = false })
  end
  api.nvim_set_hl(0, "SparkleMeteorHead", { fg = pack(mix(bg, rgb(0xffffff), 0.95)), bold = true })
  api.nvim_set_hl(0, "SparkleMeteor1", { fg = pack(mix(bg, rgb(0x9ff0ff), 0.75)) })
  api.nvim_set_hl(0, "SparkleMeteor2", { fg = pack(mix(bg, rgb(0x7aa8ff), 0.5)) })
  api.nvim_set_hl(0, "SparkleMeteor3", { fg = pack(mix(bg, rgb(0x9a5cff), 0.3)) })
end

---------------------------------------------------------------- shooting stars
local function schedule_meteor()
  local r = L().meteor_every
  next_meteor = now() + r[1] + math.random() * (r[2] - r[1])
end

local function spawn_meteor()
  local win = api.nvim_get_current_win()
  local buf = api.nvim_win_get_buf(win)
  if not eligible(win, buf) then return end
  local info = vim.fn.getwininfo(win)[1]
  local w, h = info.width - info.textoff, info.height
  if w < 30 or h < 6 then return end
  meteor = {
    win = win, t0 = now(),
    x0 = w * (0.45 + 0.5 * math.random()), y0 = h * 0.35 * math.random(),
    speed = 55 + 25 * math.random(), len = 9,
    life = 0.9,
  }
end

-- cells of the meteor at time t: { [screen_row] = { {col, group, glyph}, ... } }
local function meteor_cells(m, t)
  local cells = {}
  local age = t - m.t0
  local hx = m.x0 - age * m.speed
  local hy = m.y0 + age * m.speed * 0.35
  for i = 0, m.len - 1 do
    local x, y = floor(hx + i + 0.5), floor(hy - i * 0.35 + 0.5)
    local grp = i == 0 and "SparkleMeteorHead" or ("SparkleMeteor" .. min(3, 1 + floor(i / 3)))
    local g = i == 0 and "✦" or (i < 4 and "━" or "─")
    if vim.fn.strdisplaywidth(g) ~= 1 then g = i == 0 and "*" or "-" end
    cells[y] = cells[y] or {}
    table.insert(cells[y], { x, grp, g })
  end
  return cells
end

---------------------------------------------------------------- drawing
local view = {} -- per redraw: [win] = { top, leftcol, width, wrap, meteor }

local function on_win(_, win, buf, top)
  if not eligible(win, buf) then return false end
  local info = vim.fn.getwininfo(win)[1]
  if not info then return false end
  local v = {
    top = top,
    leftcol = info.leftcol or 0,
    width = info.width - info.textoff,
    wrap = vim.wo[win].wrap,
  }
  if meteor and meteor.win == win then v.meteor = meteor_cells(meteor, now()) end
  view[win] = v
  return true
end

local function on_line(_, win, buf, row)
  local v = view[win]
  if not v or v.width <= 0 then return end
  -- end of the text on screen (tabs, wide chars and inline virtual text included)
  local endcol = vim.fn.virtcol({ row + 1, "$" }, false, win) - 1
  -- lines carrying end-of-line virtual text (diagnostics, blame, ...) keep their right side
  local vt = api.nvim_buf_get_extmarks(buf, -1, { row, 0 }, { row, -1 }, { details = true, type = "virt_text" })
  for _, m in ipairs(vt) do
    local p = m[4].virt_text_pos
    if p == "eol" or p == "right_align" or p == "eol_right_align" then return end
    if p == "inline" then
      for _, chunk in ipairs(m[4].virt_text or {}) do endcol = endcol + vim.fn.strdisplaywidth(chunk[1]) end
    end
  end
  if v.wrap and endcol > v.width then return end
  local from = max(0, endcol - v.leftcol + M.config.margin)
  if from >= v.width then return end

  local mc = v.meteor and v.meteor[row - v.top]
  local taken
  if mc then
    taken = {}
    for _, c in ipairs(mc) do
      if c[1] >= from and c[1] < v.width then
        taken[c[1]] = true
        api.nvim_buf_set_extmark(buf, ns, row, 0, {
          virt_text = { { c[3], c[2] } }, virt_text_win_col = c[1], hl_mode = "combine", ephemeral = true, priority = 2,
        })
      end
    end
  end

  -- stars are pinned to the buffer line and the absolute display column (so they scroll with the text)
  for _, s in ipairs(stars_for(row, v.width + v.leftcol)) do
    local col = s[1] - v.leftcol
    if col >= from and col < v.width and not (taken and taken[col]) then
      api.nvim_buf_set_extmark(buf, ns, row, 0, {
        virt_text = { { s[2], s[3] } }, virt_text_win_col = col, hl_mode = "combine", ephemeral = true, priority = 1,
      })
    end
  end
end

---------------------------------------------------------------- loop
local function stop()
  if timer then timer:stop() end
end

local function redraw_meteor_win()
  if meteor and api.nvim_win_is_valid(meteor.win) then
    pcall(api.nvim__redraw, { win = meteor.win, valid = false, flush = true })
  end
end

local function tick()
  if in_cmdline() then return end
  local t = now()
  if meteor and t - meteor.t0 > meteor.life then
    local w = meteor.win
    meteor = nil
    if api.nvim_win_is_valid(w) then pcall(api.nvim__redraw, { win = w, valid = false }) end
    timer:set_repeat(floor(1000 / M.config.fps))
  end
  if t - last_input > M.config.idle_after and not meteor then return stop() end
  if M.config.meteors and not meteor and next_meteor and t > next_meteor then
    schedule_meteor()
    if api.nvim_get_mode().mode:sub(1, 1) == "n" then
      spawn_meteor()
      if meteor then timer:set_repeat(33) end
    end
  end
  paint(t)
  redraw_meteor_win()
end

local function start()
  if not enabled then return end
  if not timer then timer = uv.new_timer() end
  if timer:is_active() then return end
  timer:start(0, floor(1000 / (meteor and 30 or M.config.fps)), vim.schedule_wrap(tick))
end

function M.set_active(on) M.toggle(on) end

function M.toggle(on)
  if on == nil then on = not enabled end
  enabled = on
  if not on then stop() else start() end
  pcall(api.nvim__redraw, { valid = false, flush = true })
end

function M.setup()
  excluded = {}
  for _, ft in ipairs(M.config.exclude_ft) do excluded[ft] = true end
  glyphs = pick_glyphs()
  schedule_meteor()
  api.nvim_set_decoration_provider(ns, { on_win = on_win, on_line = on_line })

  local grp = api.nvim_create_augroup("SparkleStars", { clear = true })
  api.nvim_create_autocmd("ColorScheme", { group = grp, callback = function()
    bg = nil
    paint(now())
  end })
  api.nvim_create_autocmd("OptionSet", { group = grp, pattern = "ambiwidth", callback = function()
    glyphs, cache, cache_w = pick_glyphs(), {}, -1
  end })
  api.nvim_create_autocmd("User", { group = grp, pattern = "SparkleLevel", callback = function()
    glyphs, cache, cache_w = pick_glyphs(), {}, -1
    schedule_meteor()
    paint(now())
    pcall(api.nvim__redraw, { valid = false, flush = true })
  end })
  api.nvim_create_autocmd("FocusLost", { group = grp, callback = stop })
  api.nvim_create_autocmd("FocusGained", { group = grp, callback = function()
    last_input = now()
    start()
  end })
  vim.on_key(function()
    last_input = now()
    if timer and not timer:is_active() and enabled then vim.schedule(start) end
  end, api.nvim_create_namespace("SparkleStarsKeys"))
  api.nvim_create_user_command("SparkleStars", function(o)
    M.toggle(o.args == "" and nil or o.args == "on")
  end, { nargs = "?", complete = function() return { "on", "off" } end, desc = "Toggle the sparkle star field" })

  paint(now())
  start()
end

return M
