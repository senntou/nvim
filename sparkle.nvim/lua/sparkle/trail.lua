-- sparkle.trail: sparks when typing and a comet trail when the cursor jumps.
--
-- Particles live in window screen coordinates and are drawn as ephemeral overlay extmarks with
-- hl_mode=combine, so the editor stays fully visible: over blank cells a particle shows a spark
-- glyph, over text it just lights the character up in its colour for a moment.
local api, uv = vim.api, vim.uv or vim.loop
local style = require("sparkle.style")
local in_cmdline = style.in_cmdline
local floor, max, min, abs, sqrt = math.floor, math.max, math.min, math.abs, math.sqrt
local random = math.random

local M = {}

M.config = {
  typing = true, -- sparks on every inserted character
  delete = true, -- deleted characters crumble and fall (insert mode <BS>, <Del>, <C-w>, <C-u>)
  move = true, -- comet trail on cursor jumps
  min_jump = { rows = 2, cols = 6 }, -- smaller moves only leave a single fading dot
  small_moves = true, -- the single fading dot for hjkl-sized moves
  fps = 40,
  max_particles = 220,
  exclude_ft = { "NvimTree", "sparkle", "lazy", "mason", "TelescopePrompt", "TelescopeResults", "alpha",
    "neo-tree", "qf", "DiffviewFiles", "NeogitStatus", "gitgraph" },
}

local ns = api.nvim_create_namespace("SparkleTrail")
local enabled = true
local excluded = {}
local parts = {} -- { x, y, vx, vy, age, life, col, glyph(optional fixed), gw(glyph width), light(bool: only light text) }
local win -- window the particles belong to
local timer
local view -- { top, leftcol, width, rowmap = {[buf row] = screen y}, buf }
local last -- { win, x, y } last cursor screen position
local cells_cache = {}

local NCOL, NLVL = 5, 6
local PALETTE = { 0x46e0ff, 0xff4fd8, 0xffd34d, 0x9a5cff, 0xf4f7ff }
local GLYPHS -- by remaining life, brightest first

---------------------------------------------------------------- colours
local function rgb(h) return { floor(h / 65536) % 256, floor(h / 256) % 256, h % 256 } end
local function mix(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end
local function pack(c)
  local q = function(v) return max(0, min(255, floor(v + 0.5))) end
  return q(c[1]) * 65536 + q(c[2]) * 256 + q(c[3])
end

local function define_groups()
  local ok, hl = pcall(api.nvim_get_hl, 0, { name = "Normal", link = false })
  local bg = (ok and hl and hl.bg) and rgb(hl.bg) or (vim.o.background == "light" and rgb(0xf4f0d9) or rgb(0x1e2326))
  for c = 1, NCOL do
    local col = rgb(PALETTE[c])
    for l = 1, NLVL do
      local k = l / NLVL -- 1 = full brightness
      local fg = mix(bg, mix(col, rgb(0xffffff), max(0, k - 0.75) * 1.6), 0.25 + 0.75 * k)
      api.nvim_set_hl(0, ("SparkleSpark%d_%d"):format(c, l), { fg = pack(fg), bold = l >= NLVL - 1 })
    end
  end
end

local function pick_glyphs()
  local want = vim.o.ambiwidth == "double" and { "*", "+", "+", "." } or { "✦", "✧", "⋆", "·" }
  for i, g in ipairs(want) do
    if vim.fn.strdisplaywidth(g) ~= 1 then want[i] = ({ "*", "+", "+", "." })[i] end
  end
  return want
end

---------------------------------------------------------------- geometry
local function eligible(w)
  if not enabled or not w or not api.nvim_win_is_valid(w) then return false end
  local b = api.nvim_win_get_buf(w)
  if vim.b[b].sparkle_trail == false then return false end
  if excluded[vim.bo[b].filetype] or api.nvim_win_get_config(w).relative ~= "" then return false end
  local bt = vim.bo[b].buftype
  return bt == "" or bt == "acwrite"
end

-- cursor position in window text-area coordinates (0-based)
local function cursor_xy()
  local info = vim.fn.getwininfo(api.nvim_get_current_win())[1]
  return vim.fn.wincol() - 1 - info.textoff, vim.fn.winline() - 1
end

local function compute_view()
  if not api.nvim_win_is_valid(win) then return nil end
  local info = vim.fn.getwininfo(win)[1]
  local v = { top = info.topline - 1, leftcol = info.leftcol or 0, width = info.width - info.textoff,
    buf = info.bufnr, rowmap = {} }
  for lnum = info.topline, info.botline do
    local p = vim.fn.screenpos(win, lnum, 1)
    if p.row > 0 then v.rowmap[lnum - 1] = p.row - info.winrow end
  end
  return v
end

-- display cells of a buffer line: [abs display col] = char, " " for blanks/tabs; the trailing cells of a
-- wide char (CJK etc.) hold the number of its first cell, and c.wide[first cell] = its width
local function line_cells(buf, row)
  local key = buf .. ":" .. row
  local c = cells_cache[key]
  if c then return c end
  c = { wide = {} }
  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local ts = vim.bo[buf].tabstop
  local col = 0
  for ch in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if ch == "\t" then
      local w = ts - (col % ts)
      for i = 0, w - 1 do c[col + i] = " " end
      col = col + w
    else
      local w = ch:byte() < 128 and 1 or vim.fn.strdisplaywidth(ch)
      c[col] = ch
      if w > 1 then
        c.wide[col] = w
        for i = 1, w - 1 do c[col + i] = col end
      end
      col = col + max(1, w)
    end
  end
  cells_cache[key] = c
  return c
end

---------------------------------------------------------------- drawing
local function on_win(_, w, buf)
  return view ~= nil and w == win and buf == view.buf and #parts > 0
end

local function on_line(_, w, buf, row)
  local v = view
  local y = v and v.rowmap[row]
  if not y then return end
  local cells
  local placed = {}
  for i = #parts, 1, -1 do -- newest first: they win the cell
    local p = parts[i]
    if floor(p.y + 0.5) == y then
      local x = floor(p.x + 0.5)
      if x >= 0 and x < v.width and not placed[x] then
        cells = cells or line_cells(buf, row)
        local ax = x + v.leftcol
        local ch = cells[ax]
        if type(ch) == "number" then -- inside a wide char: light up the whole char from its first cell
          ax = ch
          ch = cells[ax]
          x = ax - v.leftcol
        end
        if x >= 0 and not placed[x] then
          local k = 1 - p.age / p.life
          local glyph, gw
          if ch ~= nil and ch ~= " " then
            glyph, gw = ch, cells.wide[ax] or 1 -- light up the text underneath
          elseif not p.light then
            glyph, gw = p.glyph, p.gw or 1
            -- a wide glyph (crumbling CJK char) needs a free cell on its right too
            local nx = cells[ax + 1]
            if not glyph or (gw > 1 and (x + 1 >= v.width or placed[x + 1] or (nx ~= nil and nx ~= " "))) then
              glyph, gw = GLYPHS[min(#GLYPHS, 1 + floor((1 - k) * #GLYPHS))], 1
            end
          end
          if glyph then
            for d = 0, gw - 1 do placed[x + d] = true end
            local lvl = max(1, min(NLVL, floor(k * NLVL + 0.999)))
            api.nvim_buf_set_extmark(buf, ns, row, 0, {
              virt_text = { { glyph, ("SparkleSpark%d_%d"):format(p.col, lvl) } },
              virt_text_win_col = x, hl_mode = "combine", ephemeral = true, priority = 300,
            })
          end
        end
      end
    end
  end
end

---------------------------------------------------------------- simulation
local function stop()
  if timer then timer:stop() end
end

local function redraw(w)
  if w and api.nvim_win_is_valid(w) then pcall(api.nvim__redraw, { win = w, valid = false, flush = true }) end
end

local prev_t
local function tick()
  if in_cmdline() then -- drop the effect, one last redraw before typing starts
    parts, view = {}, nil
    stop()
    redraw(win)
    return
  end
  local t = uv.hrtime() / 1e9
  local dt = min(0.05, t - (prev_t or t))
  prev_t = t
  local j = 0
  for i = 1, #parts do
    local p = parts[i]
    p.age = p.age + dt
    if p.age < p.life then
      p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
      local drag = 1 - min(1, (p.drag or 3.5) * dt)
      p.vx, p.vy = p.vx * drag, p.vy * drag + (p.grav or 0) * dt
      j = j + 1
      parts[j] = p
    end
  end
  for i = #parts, j + 1, -1 do parts[i] = nil end
  cells_cache = {}
  if #parts == 0 then
    view = nil
    stop()
    redraw(win) -- clear the last frame
    return
  end
  view = compute_view()
  redraw(win)
end

local function start()
  if not timer then timer = uv.new_timer() end
  if timer:is_active() then return end
  prev_t = nil
  timer:start(0, floor(1000 / M.config.fps), vim.schedule_wrap(tick))
end

local function add(p)
  if #parts >= M.config.max_particles then table.remove(parts, 1) end
  p.age = p.age or 0
  parts[#parts + 1] = p
end

local function claim(w)
  if win ~= w then
    local old = win
    parts, win, view = {}, w, nil
    if old then redraw(old) end
  end
end

---------------------------------------------------------------- effects
function M.sparks(x, y, n, opts)
  opts = opts or {}
  local w = api.nvim_get_current_win()
  if not eligible(w) then return end
  claim(w)
  -- the typed character itself flashes
  if opts.flash ~= false then add({ x = x, y = y, vx = 0, vy = 0, life = 0.28, col = 5, light = true }) end
  local c = opts.col or random(1, NCOL - 1)
  for _ = 1, n do
    local a = random() * 6.283
    local sp = 8 + random() * 16
    add({
      x = x, y = y, vx = math.cos(a) * sp, vy = math.sin(a) * sp * 0.45 - 2.5,
      life = 0.25 + random() * 0.3, col = random() < 0.7 and c or random(1, NCOL), grav = 9, drag = 4,
    })
  end
  start()
end

function M.trail(x0, y0, x1, y1)
  local w = api.nvim_get_current_win()
  if not eligible(w) then return end
  claim(w)
  local dx, dy = x1 - x0, y1 - y0
  local dist = sqrt(dx * dx + (dy * 2) ^ 2) -- cells are ~2x taller than wide
  local n = min(70, max(2, floor(dist * 0.9)))
  local c = random(1, NCOL - 1)
  for i = 0, n - 1 do
    local u = i / max(1, n - 1) -- 0 = start (oldest), 1 = end (newest)
    add({
      x = x0 + dx * u + (random() - 0.5) * 0.6, y = y0 + dy * u,
      vx = (random() - 0.5) * 2.5, vy = (random() - 0.5) * 1.2,
      life = 0.12 + 0.45 * u + random() * 0.08, col = (i % 5 == 0) and 5 or c, drag = 2,
    })
  end
  -- a little burst where it lands
  for _ = 1, 6 do
    local a = random() * 6.283
    add({ x = x1, y = y1, vx = math.cos(a) * 10, vy = math.sin(a) * 4, life = 0.3 + random() * 0.2,
      col = random(1, NCOL), drag = 5, light = false })
  end
  start()
end

-- deleted text crumbles: each character hops up and falls away, with a little dust
function M.crumble(x, y, text)
  local w = api.nvim_get_current_win()
  if not eligible(w) then return end
  claim(w)
  local lv = style.level or 2
  local col, n = 0, 0
  for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local cw = ch == "\t" and 1 or max(1, vim.fn.strdisplaywidth(ch))
    if n < 24 and ch:match("%S") and ch ~= "\u{3000}" and cw <= 2 then
      n = n + 1
      add({
        x = x + col, y = y, vx = (random() - 0.5) * 6, vy = -(4 + random() * 4),
        life = 0.45 + random() * 0.3, col = random() < 0.6 and 2 or 4, glyph = ch, gw = cw, grav = 28, drag = 1.2,
      })
    end
    col = col + cw
  end
  -- dust where the text was
  for _ = 1, min(18, 2 + lv * 2 + floor(col / 2)) do
    local a = random() * 6.283
    local sp = 4 + random() * 8
    add({
      x = x + random() * max(1, col) - 0.5, y = y, vx = math.cos(a) * sp, vy = math.sin(a) * sp * 0.4,
      life = 0.2 + random() * 0.25, col = random() < 0.5 and 4 or 5, glyph = GLYPHS[#GLYPHS], drag = 4,
    })
  end
  start()
end

function M.dot(x, y)
  local w = api.nvim_get_current_win()
  if not eligible(w) then return end
  claim(w)
  add({ x = x, y = y, vx = 0, vy = 0, life = 0.3, col = 1 + (floor(uv.hrtime() / 1e8) % (NCOL - 1)),
    glyph = GLYPHS[#GLYPHS] })
  start()
end

function M.set_active(on) M.toggle(on) end

function M.toggle(on)
  if on == nil then on = not enabled end
  enabled = on
  if not on then
    parts = {}
    stop()
    redraw(win)
  end
end

function M.setup()
  excluded = {}
  for _, ft in ipairs(M.config.exclude_ft) do excluded[ft] = true end
  GLYPHS = pick_glyphs()
  define_groups()
  api.nvim_set_decoration_provider(ns, { on_win = on_win, on_line = on_line })

  local grp = api.nvim_create_augroup("SparkleTrail", { clear = true })
  api.nvim_create_autocmd("ColorScheme", { group = grp, callback = define_groups })
  api.nvim_create_autocmd("OptionSet", { group = grp, pattern = "ambiwidth", callback = function()
    GLYPHS = pick_glyphs()
  end })

  if M.config.typing then
    api.nvim_create_autocmd("InsertCharPre", { group = grp, callback = function()
      if not eligible(api.nvim_get_current_win()) then return end
      vim.schedule(function()
        if api.nvim_get_mode().mode:sub(1, 1) ~= "i" and api.nvim_get_mode().mode:sub(1, 1) ~= "R" then return end
        local x, y = cursor_xy()
        M.sparks(x - 1, y, 4 + random(0, 3))
        last = nil
      end)
    end })
  end

  if M.config.delete then
    -- remember the cursor line; a shorter line on the same row after TextChangedI = deletion
    local snap
    local function take()
      local w = api.nvim_get_current_win()
      if not eligible(w) then snap = nil return end
      local row = api.nvim_win_get_cursor(w)[1] - 1
      snap = { buf = api.nvim_get_current_buf(), row = row,
        line = api.nvim_buf_get_lines(0, row, row + 1, false)[1] or "" }
    end
    api.nvim_create_autocmd("InsertEnter", { group = grp, callback = take })
    -- only when the row changes: on the same row TextChangedI keeps the snapshot current
    -- (CursorMovedI may fire before TextChangedI and must not swallow the old line)
    api.nvim_create_autocmd("CursorMovedI", { group = grp, callback = function()
      local row = api.nvim_win_get_cursor(0)[1] - 1
      if not snap or snap.buf ~= api.nvim_get_current_buf() or snap.row ~= row then take() end
    end })
    api.nvim_create_autocmd("TextChangedI", { group = grp, callback = function()
      local old = snap
      take()
      local new = snap
      if not old or not new or old.buf ~= new.buf or old.row ~= new.row then return end
      if vim.fn.pumvisible() == 1 or #new.line >= #old.line then return end
      -- deleted span = what is left after stripping the common prefix and suffix
      local a, b = old.line, new.line
      local p = 0
      while p < #b and a:byte(p + 1) == b:byte(p + 1) do p = p + 1 end
      local q = 0
      while q < #b - p and a:byte(#a - q) == b:byte(#b - q) do q = q + 1 end
      -- keep the span on utf-8 character boundaries
      while p > 0 and (a:byte(p + 1) or 0) >= 0x80 and (a:byte(p + 1) or 0) < 0xc0 do p = p - 1 end
      local gone = a:sub(p + 1, #a - q)
      if gone == "" then return end
      -- screen x of the span start, relative to the cursor (works with wrap and leftcol)
      local cx, y = cursor_xy()
      local ccol = api.nvim_win_get_cursor(0)[2]
      local x = cx + vim.fn.strdisplaywidth(b:sub(1, p)) - vim.fn.strdisplaywidth(b:sub(1, ccol))
      M.crumble(x, y, gone)
      last = nil
    end })
  end

  if M.config.move then
    local function remember()
      local w = api.nvim_get_current_win()
      if not eligible(w) then last = nil return end
      local x, y = cursor_xy()
      last = { win = w, x = x, y = y }
    end
    api.nvim_create_autocmd({ "BufEnter", "WinEnter", "InsertLeave" }, { group = grp, callback = function()
      vim.schedule(remember)
    end })
    api.nvim_create_autocmd("CursorMoved", { group = grp, callback = function()
      local w = api.nvim_get_current_win()
      if not eligible(w) then last = nil return end
      local x, y = cursor_xy()
      local l = last
      last = { win = w, x = x, y = y }
      if not l or l.win ~= w then return end
      local dx, dy = abs(x - l.x), abs(y - l.y)
      if dx == 0 and dy == 0 then return end
      if dy >= M.config.min_jump.rows or dx >= M.config.min_jump.cols then
        M.trail(l.x, l.y, x, y)
      elseif M.config.small_moves then
        M.dot(l.x, l.y)
      end
    end })
  end

  api.nvim_create_autocmd("FocusLost", { group = grp, callback = function()
    parts = {}
  end })
  api.nvim_create_user_command("SparkleTrail", function(o)
    M.toggle(o.args == "" and nil or o.args == "on")
  end, { nargs = "?", complete = function() return { "on", "off" } end, desc = "Toggle sparkle cursor/typing effects" })
end

return M
