-- sparkle.canvas: half-block pixel canvas rendered as ANSI escapes (for a terminal buffer).
--
-- 1 cell = 2 vertical pixels using "▀" (fg = top pixel, bg = bottom pixel), 24-bit colour.
-- A text layer sits on top (one single-width glyph per cell); its background defaults to
-- the average of the two pixels underneath so text looks like it is printed on the image.
-- Ported from the SHOOTIE renderer (gfx/canvas.cpp).

local floor, max, min, abs, sqrt = math.floor, math.max, math.min, math.abs, math.sqrt

local M = {}

local HALF = "▀"
local LOWER = "▄"
local DEF = -2 -- "default background" (SGR 49): the window's Normal background shows through
local Q = 4 -- colour quantisation step (tiny colour drifts do not cause redraws)

---------------------------------------------------------------- colour helpers
function M.hex(h)
  return { floor(h / 65536) % 256, floor(h / 256) % 256, h % 256 }
end

function M.lerp(a, b, t)
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

function M.scale(a, k)
  return { a[1] * k, a[2] * k, a[3] * k }
end

function M.add(a, b, k)
  k = k or 1
  return { min(255, a[1] + b[1] * k), min(255, a[2] + b[2] * k), min(255, a[3] + b[3] * k) }
end

function M.hsv(h, s, v)
  h = (h % 1) * 6
  local i = floor(h)
  local f = h - i
  local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
  local r, g, b
  if i == 0 then r, g, b = v, t, p
  elseif i == 1 then r, g, b = q, v, p
  elseif i == 2 then r, g, b = p, v, t
  elseif i == 3 then r, g, b = p, q, v
  elseif i == 4 then r, g, b = t, p, v
  else r, g, b = v, p, q end
  return { r * 255, g * 255, b * 255 }
end

function M.clamp(x, a, b)
  return x < a and a or (x > b and b or x)
end

---------------------------------------------------------------- canvas
local Canvas = {}
Canvas.__index = Canvas

function M.new(cols, rows)
  local c = setmetatable({}, Canvas)
  c:resize(cols, rows)
  return c
end

function Canvas:resize(cols, rows)
  self.cols, self.rows = cols, rows
  self.pw, self.ph = cols, rows * 2
  local n = cols * rows * 2
  local R, G, B = {}, {}, {}
  for i = 1, n do
    R[i], G[i], B[i] = 0, 0, 0
  end
  self.R, self.G, self.B = R, G, B
  if self.T then self.T = {} end
  self.text = {}
  self.af = nil
end

-- Transparent mode: pixels nothing was drawn on since clear_pixels() are not painted at all, so the
-- window's own background (e.g. Normal, or the terminal's when that has no bg) shows instead.
-- `base` is the colour blending starts from (should be close to that background).
function Canvas:clear_pixels(base)
  local R, G, B = self.R, self.G, self.B
  local r, g, b = base[1], base[2], base[3]
  for i = 1, #R do
    R[i], G[i], B[i] = r, g, b
  end
  self.T = {}
end

function Canvas:clear_text()
  self.text = {}
end

-- Copy a whole pixel layer (arrays of the same size) into the canvas.
function Canvas:blit(R, G, B)
  local r, g, b = self.R, self.G, self.B
  for i = 1, #R do
    r[i], g[i], b[i] = R[i], G[i], B[i]
  end
end

function Canvas:pset(x, y, c)
  x, y = floor(x), floor(y)
  if x < 0 or y < 0 or x >= self.pw or y >= self.ph then return end
  local i = y * self.pw + x + 1
  self.R[i], self.G[i], self.B[i] = c[1], c[2], c[3]
  if self.T then self.T[i] = true end
end

function Canvas:pget(x, y)
  x, y = floor(x), floor(y)
  if x < 0 or y < 0 or x >= self.pw or y >= self.ph then return { 0, 0, 0 } end
  local i = y * self.pw + x + 1
  return { self.R[i], self.G[i], self.B[i] }
end

function Canvas:pblend(x, y, c, a)
  x, y = floor(x), floor(y)
  if x < 0 or y < 0 or x >= self.pw or y >= self.ph then return end
  local i = y * self.pw + x + 1
  local R, G, B = self.R, self.G, self.B
  if self.T then
    if a < 0.03 then return end
    self.T[i] = true
  end
  R[i] = R[i] + (c[1] - R[i]) * a
  G[i] = G[i] + (c[2] - G[i]) * a
  B[i] = B[i] + (c[3] - B[i]) * a
end

-- additive, saturating
function Canvas:padd(x, y, c, k)
  x, y = floor(x), floor(y)
  if x < 0 or y < 0 or x >= self.pw or y >= self.ph then return end
  k = k or 1
  local i = y * self.pw + x + 1
  local R, G, B = self.R, self.G, self.B
  if self.T then
    if k * max(c[1], c[2], c[3]) < 8 then return end -- too faint to be worth an opaque cell
    self.T[i] = true
  end
  R[i] = min(255, R[i] + c[1] * k)
  G[i] = min(255, G[i] + c[2] * k)
  B[i] = min(255, B[i] + c[3] * k)
end

function Canvas:fill_rect(x, y, w, h, c, a)
  a = a or 1
  for yy = y, y + h - 1 do
    for xx = x, x + w - 1 do
      self:pblend(xx, yy, c, a)
    end
  end
end

-- Multiply everything inside a rect (k < 1 darkens).
function Canvas:dim_rect(x, y, w, h, k)
  local R, G, B, pw = self.R, self.G, self.B, self.pw
  for yy = max(0, y), min(self.ph - 1, y + h - 1) do
    for xx = max(0, x), min(pw - 1, x + w - 1) do
      local i = yy * pw + xx + 1
      R[i], G[i], B[i] = R[i] * k, G[i] * k, B[i] * k
    end
  end
end

-- Additive radial glow with smooth falloff.
function Canvas:glow(cx, cy, radius, c, intensity)
  intensity = intensity or 1
  if intensity <= 0 or radius <= 0 then return end
  local x0, x1 = floor(cx - radius), floor(cx + radius)
  local y0, y1 = floor(cy - radius), floor(cy + radius)
  for y = y0, y1 do
    for x = x0, x1 do
      local dx, dy = x + 0.5 - cx, y + 0.5 - cy
      local d = sqrt(dx * dx + dy * dy) / radius
      if d < 1 then
        local k = (1 - d)
        self:padd(x, y, c, k * k * intensity)
      end
    end
  end
end

---------------------------------------------------------------- text layer
-- Display width of one code point (cached; ASCII is always 1).
local wcache = {}
local function cwidth(ch)
  if #ch == 1 then return 1 end
  local w = wcache[ch]
  if not w then
    w = vim.api.nvim_strwidth(ch)
    if w < 1 then w = 1 end
    wcache[ch] = w
  end
  return w
end
M.cwidth = cwidth

-- Put a UTF-8 string at (col,row). Wide (CJK) characters take two cells.
-- opts: bg = {r,g,b} | nil, bold = bool
function Canvas:put(col, row, s, fg, opts)
  if row < 0 or row >= self.rows then return end
  opts = opts or {}
  local x = col
  local base = row * self.cols
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local w = cwidth(ch)
    if x >= 0 and x + w <= self.cols then
      local text, i = self.text, base + x + 1
      -- overwriting half of an existing wide character: blank its other half
      local old = text[i]
      if old and old.cont and x > 0 then
        local lead = text[i - 1]
        if lead then text[i - 1] = { ch = " ", fg = lead.fg or fg, bg = lead.bg, w = 1 } end
      end
      local nxt = text[i + w]
      if nxt and nxt.cont and x + w < self.cols then text[i + w] = nil end
      text[i] = { ch = ch, fg = fg, bg = opts.bg, bold = opts.bold, w = w }
      if w == 2 then text[i + 1] = { cont = true } end
    end
    x = x + w
  end
end

function M.width(s)
  local n = 0
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + cwidth(ch) end
  return n
end

-- Truncate a string to at most `w` display cells (appends "…" when cut).
function M.truncate(s, w)
  if M.width(s) <= w then return s end
  local out, n = {}, 0
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local cw = cwidth(ch)
    if n + cw > w - 1 then break end
    out[#out + 1], n = ch, n + cw
  end
  return table.concat(out) .. "…"
end

-- Wrap a string into lines of at most `w` display cells.
function M.wrap(s, w)
  local lines = {}
  for para in (s .. "\n"):gmatch("(.-)\n") do
    para = para:gsub("\t", "  ")
    if para == "" then
      lines[#lines + 1] = ""
    else
      local cur, n = {}, 0
      for ch in para:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local cw = cwidth(ch)
        if n + cw > w then
          lines[#lines + 1] = table.concat(cur)
          cur, n = {}, 0
        end
        cur[#cur + 1], n = ch, n + cw
      end
      lines[#lines + 1] = table.concat(cur)
    end
  end
  return lines
end

-- centred on a column
function Canvas:putc(ccol, row, s, fg, opts)
  self:put(ccol - floor(M.width(s) / 2), row, s, fg, opts)
end

-- per-character gradient a -> b
function Canvas:put_gradient(col, row, s, a, b, opts)
  local n = M.width(s)
  local x = col
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    self:put(x, row, ch, M.lerp(a, b, n > 1 and (x - col) / (n - 1) or 0), opts)
    x = x + cwidth(ch)
  end
end

---------------------------------------------------------------- output
local function q(v)
  v = floor(v / Q + 0.5) * Q
  return v > 255 and 255 or (v < 0 and 0 or v)
end

---------------------------------------------------------------- ANSI output (terminal buffer)
-- Diff against the previous frame and emit only the cells that changed, as 24-bit SGR escapes.
-- Feed the result to a terminal buffer (nvim_open_term + nvim_chan_send).
function Canvas:render_ansi()
  local R, G, B, pw, cols, text = self.R, self.G, self.B, self.pw, self.cols, self.text
  local T = self.T
  local n = cols * self.rows
  local pf, pb, pc = self.af, self.ab, self.ac
  local full = not pf or #pf ~= n
  if full then pf, pb, pc = {}, {}, {} end
  local out, no = {}, 0
  local cur_f, cur_b, cur_bold = -1, -1, nil
  local cx, cy = -1, -1
  local fmt = string.format
  if full then
    no = 1
    out[1] = "\27[?25l\27[0m\27[2J"
  end
  local dirty_rows = 0
  -- Rows holding wide (CJK) characters, now or in the previous frame, are always re-sent whole:
  -- overwriting half of a wide character makes the terminal erase all of it, which a per-cell
  -- diff cannot track.
  local wide_now, wide_prev = {}, self.awide or {}
  for idx, cell in pairs(text) do
    if cell.cont then wide_now[floor((idx - 1) / cols)] = true end
  end
  self.awide = wide_now
  for row = 0, self.rows - 1 do
    local top0, bot0 = (2 * row) * pw + 1, (2 * row + 1) * pw + 1
    local row_dirty = false
    local row_full = full or wide_now[row] or wide_prev[row]
    for col = 0, cols - 1 do
      local ti, bi = top0 + col, bot0 + col
      local idx = row * cols + col + 1
      local cell = text[idx]
      local ch, f, b, bold
      if cell and cell.cont then
        -- right half of a wide character: drawn together with its left half
        ch, bold, f, b = "", false, pf[idx - 1] or 0, pb[idx - 1] or 0
      elseif cell then
        ch, bold = cell.ch, cell.bold or false
        local fc, bc = cell.fg, cell.bg
        f = q(fc[1]) * 65536 + q(fc[2]) * 256 + q(fc[3])
        if bc then
          b = q(bc[1]) * 65536 + q(bc[2]) * 256 + q(bc[3])
        elseif T and not T[ti] and not T[bi] then
          b = DEF
        else
          b = q((R[ti] + R[bi]) * 0.5) * 65536 + q((G[ti] + G[bi]) * 0.5) * 256 + q((B[ti] + B[bi]) * 0.5)
        end
      elseif T and not (T[ti] and T[bi]) then
        bold, b = false, DEF
        if T[ti] then
          ch, f = HALF, q(R[ti]) * 65536 + q(G[ti]) * 256 + q(B[ti])
        elseif T[bi] then
          ch, f = LOWER, q(R[bi]) * 65536 + q(G[bi]) * 256 + q(B[bi])
        else
          ch, f = " ", 0
        end
      else
        ch, bold = HALF, false
        f = q(R[ti]) * 65536 + q(G[ti]) * 256 + q(B[ti])
        b = q(R[bi]) * 65536 + q(G[bi]) * 256 + q(B[bi])
      end
      local c = bold and ch .. "\1" or ch
      local dirty_cell = row_full or pf[idx] ~= f or pb[idx] ~= b or pc[idx] ~= c
      if dirty_cell then
        pf[idx], pb[idx], pc[idx] = f, b, c
        row_dirty = true
      end
      if ch ~= "" and (row_full or dirty_cell) then
        if cy ~= row or cx ~= col then
          no = no + 1
          out[no] = fmt("\27[%d;%dH", row + 1, col + 1)
        end
        if bold ~= cur_bold then
          no = no + 1
          out[no] = bold and "\27[1m" or "\27[22m"
          cur_bold = bold
        end
        if f ~= cur_f then
          no = no + 1
          out[no] = fmt("\27[38;2;%d;%d;%dm", floor(f / 65536), floor(f / 256) % 256, f % 256)
          cur_f = f
        end
        if b ~= cur_b then
          no = no + 1
          out[no] = b == DEF and "\27[49m"
            or fmt("\27[48;2;%d;%d;%dm", floor(b / 65536), floor(b / 256) % 256, b % 256)
          cur_b = b
        end
        no = no + 1
        out[no] = ch
        cx, cy = col + (cell and cell.w or 1), row
      end
    end
    if row_dirty then dirty_rows = dirty_rows + 1 end
  end
  self.dirty_rows = dirty_rows
  self.af, self.ab, self.ac = pf, pb, pc
  if no == 0 then return nil end
  return table.concat(out)
end

---------------------------------------------------------------- highlight output (normal buffer)
-- Fallback renderer for when terminal buffers do not refresh (e.g. while Neovim is exiting):
-- writes the picture into an ordinary buffer, one extmark per run of equally coloured cells.
local hl_cache = {}
local HQ = 8
local function hq(v)
  v = floor(v / HQ + 0.5) * HQ
  return v > 255 and 255 or (v < 0 and 0 or v)
end
local function hl_for(f, b, bold)
  local key = f * 16777216 + b + (bold and 0.5 or 0)
  local name = hl_cache[key]
  if not name then
    name = string.format("SparkleC%06x%06x%s", f, b, bold and "b" or "")
    vim.api.nvim_set_hl(0, name, { fg = f, bg = b, bold = bold or nil })
    hl_cache[key] = name
  end
  return name
end

function Canvas:render_buf(buf, ns)
  local R, G, B, pw, cols, text = self.R, self.G, self.B, self.pw, self.cols, self.text
  local lines, marks = {}, {}
  for row = 0, self.rows - 1 do
    local top0, bot0 = (2 * row) * pw + 1, (2 * row + 1) * pw + 1
    local parts, byte = {}, 0
    local run_hl, run_start = nil, 0
    for col = 0, cols - 1 do
      local ti, bi = top0 + col, bot0 + col
      local cell = text[row * cols + col + 1]
      if not (cell and cell.cont) then
        local ch, f, b, bold
        if cell then
          ch, bold = cell.ch, cell.bold
          f = hq(cell.fg[1]) * 65536 + hq(cell.fg[2]) * 256 + hq(cell.fg[3])
          local bc = cell.bg
          if bc then
            b = hq(bc[1]) * 65536 + hq(bc[2]) * 256 + hq(bc[3])
          else
            b = hq((R[ti] + R[bi]) * 0.5) * 65536 + hq((G[ti] + G[bi]) * 0.5) * 256 + hq((B[ti] + B[bi]) * 0.5)
          end
        else
          ch = HALF
          f = hq(R[ti]) * 65536 + hq(G[ti]) * 256 + hq(B[ti])
          b = hq(R[bi]) * 65536 + hq(G[bi]) * 256 + hq(B[bi])
        end
        local hl = hl_for(f, b, bold)
        if hl ~= run_hl then
          if run_hl then marks[#marks + 1] = { row, run_start, byte, run_hl } end
          run_hl, run_start = hl, byte
        end
        parts[#parts + 1] = ch
        byte = byte + #ch
      end
    end
    if run_hl then marks[#marks + 1] = { row, run_start, byte, run_hl } end
    lines[row + 1] = table.concat(parts)
  end
  local api = vim.api
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for _, m in ipairs(marks) do
    api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
end

function Canvas:invalidate_ansi()
  self.af = nil
end

return M
