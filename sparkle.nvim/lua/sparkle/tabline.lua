-- sparkle.tabline: the buffer list at the top of the screen (replaces bufferline.nvim).
--
--   * listed, non-terminal buffers in :bnext order (the same set NextBuffer/PrevBuffer cycle through)
--   * the current buffer gets a mode-coloured accent bar and a light sweep when you switch to it
--   * ● for unsaved changes, error / warning counts from vim.diagnostic
--   * same file names are told apart by their parent directories
--   * a "Files" title above NvimTree, tab page numbers on the right when there is more than one
--   * left click switches, middle click closes; too many buffers scroll so the current one stays visible
--   * sparkle style: faint twinkling stars in the empty part of the bar (level 2+)
--   * calm style: drawn statically in the TabLine / TabLineSel / TabLineFill colours of the colorscheme
--
-- require("sparkle.tabline").go(n) jumps to the n-th buffer of the bar.
local api, uv = vim.api, vim.uv or vim.loop
local style = require("sparkle.style")
local floor, max, min, abs, sin = math.floor, math.max, math.min, math.abs, math.sin

local M = {}

M.config = {
  numbers = true, -- ordinal in front of each name (matches go(n) / <leader>1..9)
  max_name = 24, -- display cells before a name is shortened with …
  min_width = 16, -- tabs are padded to at least this many cells (status marks sit at the right end)
  gap = 1, -- cells of bar background between two tabs
  fps = 20,
  sweep_speed = 30, -- characters per second
  idle_after = 30, -- stop animating after this many seconds without input
  offset_ft = { NvimTree = "Files", ["neo-tree"] = "Files" },
}

-- per flashiness level: seconds between idle sweeps (nil = only when switching), star density
M.levels = {
  { sweep_every = nil, stars = 0 },
  { sweep_every = 8, stars = 0.06 },
  { sweep_every = 4, stars = 0.12 },
}
local function L() return M.levels[style.level] or M.levels[2] end

local P = {
  fill = "#080c1e",
  tab = "#111838",
  sel = "#1c2654",
  text = "#c8d4f4",
  dim = "#6a7499",
  faint = "#3a4366",
  white = "#ffffff",
  mod = "#ff4fd8",
  err = "#ff5470",
  warn = "#ffd34d",
  title = "#46e0ff",
  star = "#a8c8ff",
}

local MODES = { "normal", "insert", "visual", "replace", "command", "terminal" }
local SWEEP = 8 -- sweep brightness steps
local STAR = 6 -- star brightness steps

local calm = false
local last_buf -- the buffer shown as current while focus is in NvimTree, a float, ...
local sweep_t0 = -100
local timer
local last_input = 0
local icon_hl = {} -- [devicons group .. sel] = our group with the tab background

---------------------------------------------------------------- colours
local function now() return uv.hrtime() / 1e9 end

local function rgb(h)
  local n = type(h) == "number" and h or tonumber(h:sub(2), 16)
  return { floor(n / 65536) % 256, floor(n / 256) % 256, n % 256 }
end
local function hex(c) return string.format("#%02x%02x%02x", floor(c[1] + 0.5), floor(c[2] + 0.5), floor(c[3] + 0.5)) end
local function mix(a, b, t)
  local x, y = rgb(a), rgb(b)
  return hex({ x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t, x[3] + (y[3] - x[3]) * t })
end

local function get(name, key)
  local ok, hl = pcall(api.nvim_get_hl, 0, { name = name, link = false })
  if not ok or not hl then return nil end
  local v = hl[key]
  if hl.reverse then v = (key == "fg") and hl.bg or hl.fg end
  return v and string.format("#%06x", v) or nil
end

local function mode_colors()
  local sl = package.loaded["sparkle.statusline"]
  return sl and sl.mode_colors or {
    normal = "#46e0ff", insert = "#ff4fd8", visual = "#ffd34d",
    replace = "#ff5470", command = "#5cffa8", terminal = "#9a5cff",
  }
end

-- the palette in use: sparkle neon, or taken from the colorscheme (calm)
local function palette()
  if not calm then return P end
  -- TabLineSel is often reverse video or a loud colour: derive quiet shades from the
  -- bar background and the normal text colour instead
  local t = require("sparkle.theme").colors().hex
  local fill = get("TabLineFill", "bg") or get("StatusLineNC", "bg") or t.bg
  return {
    fill = fill,
    tab = mix(fill, t.fg, 0.06),
    sel = mix(fill, t.fg, 0.15),
    text = mix(t.fg, fill, 0.2),
    sel_fg = t.fg,
    dim = mix(t.fg, fill, 0.45),
    faint = mix(t.fg, fill, 0.65),
    white = t.fg,
    mod = t.special,
    err = get("DiagnosticError", "fg") or t.accent2,
    warn = get("DiagnosticWarn", "fg") or t.title,
    title = t.title,
    star = t.dim,
    accent = t.accent,
  }
end

local function define_hl()
  icon_hl = {}
  local p = palette()
  local tab = p.tab or p.fill
  local sel_fg = p.sel_fg or p.white
  local set = function(name, def) api.nvim_set_hl(0, "SparkleTab" .. name, def) end
  set("Fill", { bg = p.fill, fg = p.faint })
  set("", { bg = tab, fg = p.dim })
  set("Visible", { bg = tab, fg = p.text })
  set("Sel", { bg = p.sel, fg = sel_fg, bold = true })
  set("Num", { bg = tab, fg = p.faint })
  set("NumSel", { bg = p.sel, fg = p.dim })
  set("Mod", { bg = tab, fg = p.mod, bold = true })
  set("ModSel", { bg = p.sel, fg = p.mod, bold = true })
  set("Err", { bg = tab, fg = p.err })
  set("ErrSel", { bg = p.sel, fg = p.err })
  set("Warn", { bg = tab, fg = p.warn })
  set("WarnSel", { bg = p.sel, fg = p.warn })
  set("Div", { bg = tab, fg = p.faint })
  set("More", { bg = p.fill, fg = p.dim, bold = true })
  set("Title", { bg = p.fill, fg = p.title, bold = true })
  set("Page", { bg = tab, fg = p.dim })
  set("PageSel", { bg = p.sel, fg = calm and sel_fg or p.title, bold = true })
  local mc = mode_colors()
  for _, m in ipairs(MODES) do
    local col = calm and p.accent or mc[m]
    set("Accent_" .. m, { bg = p.sel, fg = col })
    for k = 0, SWEEP - 1 do
      local s = calm and 0 or k / (SWEEP - 1)
      set(("Sweep_%s_%d"):format(m, k), { bg = mix(p.sel, col, s * 0.35), fg = mix(sel_fg, P.white, s * 0.7), bold = true })
    end
  end
  for k = 0, STAR - 1 do
    set("Star" .. k, { bg = p.fill, fg = mix(p.fill, p.star, 0.15 + 0.85 * k / (STAR - 1)) })
  end
end

local function icon_group(group, sel)
  local key = (group or "") .. (sel and "S" or "")
  local g = icon_hl[key]
  if g then return g end
  g = "SparkleTabIcon_" .. (group or "none") .. (sel and "_sel" or "")
  local p = palette()
  api.nvim_set_hl(0, g, { bg = sel and p.sel or (p.tab or p.fill), fg = group and get(group, "fg") or p.dim })
  icon_hl[key] = g
  return g
end

---------------------------------------------------------------- buffers
local function mode_key()
  local c = api.nvim_get_mode().mode:sub(1, 1)
  if c == "i" then return "insert" end
  if c == "v" or c == "V" or c == "\22" or c == "s" or c == "S" or c == "\19" then return "visual" end
  if c == "R" then return "replace" end
  if c == "c" then return "command" end
  if c == "t" then return "terminal" end
  return "normal"
end

local function eligible(b)
  return api.nvim_buf_is_valid(b) and vim.bo[b].buflisted and vim.bo[b].buftype ~= "terminal"
end

function M.list()
  local out = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    if eligible(b) then out[#out + 1] = b end
  end
  return out
end

local function current_buf()
  local b = api.nvim_get_current_buf()
  if eligible(b) then return b end
  if last_buf and eligible(last_buf) then return last_buf end
end

-- short unique names: basename, then as many parent directories as it takes
local function names(bufs)
  local parts, res, depth = {}, {}, {}
  for _, b in ipairs(bufs) do
    local full = api.nvim_buf_get_name(b)
    if full == "" then
      res[b] = "[No Name]"
    else
      parts[b] = vim.split(vim.fn.fnamemodify(full, ":~:."), "/", { plain = true, trimempty = true })
      depth[b] = 1
    end
  end
  local function label(b)
    local p, d = parts[b], depth[b]
    return table.concat(p, "/", max(1, #p - d + 1), #p)
  end
  for _ = 1, 8 do
    local seen, clash = {}, false
    for b in pairs(parts) do
      local l = label(b)
      seen[l] = seen[l] or {}
      table.insert(seen[l], b)
    end
    for _, group in pairs(seen) do
      if #group > 1 then
        for _, b in ipairs(group) do
          if depth[b] < #parts[b] then depth[b] = depth[b] + 1; clash = true end
        end
      end
    end
    if not clash then break end
  end
  for b in pairs(parts) do res[b] = label(b) end
  return res
end

local function shorten(s, n)
  if vim.fn.strdisplaywidth(s) <= n then return s end
  local chars = vim.fn.strchars(s)
  -- keep the end (the file name itself), drop from the front
  for i = 1, chars do
    local t = "…" .. vim.fn.strcharpart(s, i)
    if vim.fn.strdisplaywidth(t) <= n then return t end
  end
  return s
end

local function icon(b, name)
  local ok, dev = pcall(require, "nvim-web-devicons")
  if not ok then return nil end
  local fname = vim.fn.fnamemodify(api.nvim_buf_get_name(b), ":t")
  local ext = vim.fn.fnamemodify(fname, ":e")
  local ic, grp = dev.get_icon(fname ~= "" and fname or name, ext, { default = true })
  if not ic then
    ic, grp = dev.get_icon_by_filetype(vim.bo[b].filetype, { default = true })
  end
  return ic, grp
end

---------------------------------------------------------------- rendering
local function esc(s) return (s:gsub("%%", "%%%%")) end
local function width(s) return api.nvim_strwidth(s) end

-- one tab as a list of { hl, text } chunks plus its width
local function build_item(b, idx, name, is_cur, visible, t)
  local chunks, w = {}, 0
  local function add(hl, text)
    chunks[#chunks + 1] = { hl, text }
    w = w + width(text)
  end
  local mk = mode_key()
  local base = is_cur and "SparkleTabSel" or (visible and "SparkleTabVisible" or "SparkleTab")
  if is_cur then add("SparkleTabAccent_" .. mk, "▌") else add("SparkleTab", " ") end
  if M.config.numbers and idx <= 9 then
    add(is_cur and "SparkleTabNumSel" or "SparkleTabNum", tostring(idx) .. " ")
  end
  local ic, grp = icon(b, name)
  if ic then add(icon_group(grp, is_cur), ic .. " ") end
  name = shorten(name, M.config.max_name)
  -- the light sweep over the current name
  local u = (t - sweep_t0) * M.config.sweep_speed - 2
  local n = vim.fn.strchars(name)
  if is_cur and not calm and u < n + 3 then
    for i = 0, n - 1 do
      local lv = max(0, 1 - abs(i - u) / 2.5)
      add(("SparkleTabSweep_%s_%d"):format(mk, floor(lv * (SWEEP - 1) + 0.5)), vim.fn.strcharpart(name, i, 1))
    end
  else
    add(base, name)
  end
  -- status marks, kept at the right end of the tab
  local sfx = is_cur and "Sel" or ""
  local status, sw = {}, 0
  local function mark(hl, text)
    status[#status + 1] = { hl, text }
    sw = sw + width(text)
  end
  local ok, cnt = pcall(vim.diagnostic.count, b)
  if ok and cnt then
    local E, W = cnt[vim.diagnostic.severity.ERROR], cnt[vim.diagnostic.severity.WARN]
    if E and E > 0 then mark("SparkleTabErr" .. sfx, " " .. E) end
    if W and W > 0 then mark("SparkleTabWarn" .. sfx, " " .. W) end
  end
  if vim.bo[b].modified then mark("SparkleTabMod" .. sfx, " ●") end
  local pad = max(1, M.config.min_width - w - sw - 1)
  add(base, (" "):rep(pad))
  for _, c in ipairs(status) do add(c[1], c[2]) end
  add(base, " ")
  if M.config.gap > 0 then add("SparkleTabFill", (" "):rep(M.config.gap)) end
  return { buf = b, chunks = chunks, w = w }
end

-- NvimTree (or similar) at the left edge: its width, title
local function offset()
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local title = M.config.offset_ft[vim.bo[api.nvim_win_get_buf(w)].filetype]
    if title and api.nvim_win_get_config(w).relative == "" and api.nvim_win_get_position(w)[2] == 0 then
      return api.nvim_win_get_width(w), title
    end
  end
end

local function hash(a)
  local h = bit.tobit(a * 374761393 + 668265263)
  h = bit.bxor(h, bit.rshift(h, 13))
  h = bit.tobit(bit.band(h, 0xffff) * 1274126177 + bit.rshift(h, 16) * 2246822519)
  h = bit.bxor(h, bit.rshift(h, 16))
  return bit.band(h, 0xffffff) / 0x1000000
end

-- the empty part of the bar: blanks, or twinkling stars (sparkle style, level 2+)
local function fill(out, col, n, t)
  if n <= 0 then return end
  local density = calm and 0 or L().stars
  if density <= 0 then
    out[#out + 1] = "%#SparkleTabFill#" .. (" "):rep(n)
    return
  end
  local cur
  for x = col, col + n - 1 do
    local h = hash(x)
    local hl, ch = "SparkleTabFill", " "
    if h < density then
      local tw = 0.5 + 0.5 * sin(t * (1.2 + 2.5 * hash(x + 7919)) + h * 97)
      hl = "SparkleTabStar" .. floor(tw * tw * (STAR - 1) + 0.5)
      ch = hash(x + 104729) < 0.25 and "✦" or (hash(x + 15485863) < 0.5 and "⋆" or "·")
    end
    if hl ~= cur then
      out[#out + 1] = "%#" .. hl .. "#"
      cur = hl
    end
    out[#out + 1] = ch
  end
end

function M.render()
  local t = now()
  local cols = vim.o.columns
  local out = {}
  local used = 0

  -- left offset above a file tree
  local ow, title = offset()
  if ow then
    local label = " ✦ " .. title .. " "
    if calm then label = " " .. title .. " " end
    local lw = width(label)
    if lw > ow then label, lw = "", 0 end
    local left = floor((ow - lw) / 2)
    out[#out + 1] = "%#SparkleTabFill#" .. (" "):rep(left) .. "%#SparkleTabTitle#" .. label
      .. "%#SparkleTabFill#" .. (" "):rep(ow - lw - left) .. "%#WinSeparator#│"
    used = ow + 1
  end

  -- tab pages on the right
  local right, rw = {}, 0
  local tabs = api.nvim_list_tabpages()
  if #tabs > 1 then
    local curtab = api.nvim_get_current_tabpage()
    right[#right + 1] = "%#SparkleTabFill# "
    rw = 1
    for i, tp in ipairs(tabs) do
      local lbl = " " .. i .. " "
      right[#right + 1] = ("%%%dT%%#%s#%s%%T"):format(i, tp == curtab and "SparkleTabPageSel" or "SparkleTabPage", lbl)
      rw = rw + width(lbl)
    end
  end

  -- buffers
  local bufs = M.list()
  local cur = current_buf()
  local nm = names(bufs)
  local shown = {}
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do shown[api.nvim_win_get_buf(w)] = true end
  local items, cur_i = {}, nil
  for i, b in ipairs(bufs) do
    items[i] = build_item(b, i, nm[b], b == cur, shown[b], t)
    if b == cur then cur_i = i end
  end

  local avail = cols - used - rw
  local total = 0
  for _, it in ipairs(items) do total = total + it.w end
  local first, last = 1, #items
  local more_l, more_r = "", ""
  if total > avail and #items > 0 then
    -- grow a window of tabs around the current one until it no longer fits
    local c = cur_i or 1
    first, last = c, c
    local function marks(f, l)
      local ml = f > 1 and (" ‹" .. (f - 1) .. " ") or ""
      local mr = l < #items and (" " .. (#items - l) .. "› ") or ""
      return ml, mr
    end
    local sum = items[c].w
    local grew = true
    while grew do
      grew = false
      for _, dir in ipairs({ 1, -1 }) do
        local f, l = first, last
        if dir == 1 and l < #items then l = l + 1 elseif dir == -1 and f > 1 then f = f - 1 else goto continue end
        do
          local s = sum + items[dir == 1 and l or f].w
          local ml, mr = marks(f, l)
          if s + width(ml) + width(mr) <= avail then
            first, last, sum, grew = f, l, s, true
          end
        end
        ::continue::
      end
    end
    more_l, more_r = marks(first, last)
  end

  if more_l ~= "" then
    out[#out + 1] = "%#SparkleTabMore#" .. more_l
    used = used + width(more_l)
  end
  for i = first, last do
    local it = items[i]
    if it then
      out[#out + 1] = ("%%%d@v:lua.SparkleTablineClick@"):format(it.buf)
      for _, ch in ipairs(it.chunks) do
        out[#out + 1] = "%#" .. ch[1] .. "#" .. esc(ch[2])
      end
      out[#out + 1] = "%T"
      used = used + it.w
    end
  end
  local mrw = width(more_r)
  fill(out, used, cols - used - mrw - rw, t)
  if more_r ~= "" then out[#out + 1] = "%#SparkleTabMore#" .. more_r end
  for _, s in ipairs(right) do out[#out + 1] = s end
  return table.concat(out)
end

---------------------------------------------------------------- actions
-- switch to buffer b without putting it into a file-tree / special window
local function show(b)
  local win = api.nvim_get_current_win()
  if not eligible(api.nvim_win_get_buf(win)) or api.nvim_win_get_config(win).relative ~= "" then
    local target
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
      if api.nvim_win_get_config(w).relative == "" then
        local wb = api.nvim_win_get_buf(w)
        if wb == last_buf then target = w break end
        if not target and (eligible(wb) or vim.bo[wb].filetype == "sparkle") then target = w end
      end
    end
    if target then api.nvim_set_current_win(target) end
  end
  vim.cmd("buffer " .. b)
end

function M.go(n)
  local b = M.list()[n]
  if b then show(b) end
end

function M.close(b)
  if b == api.nvim_get_current_buf() and type(_G.Bdelete) == "function" then
    _G.Bdelete()
  elseif vim.bo[b].modified then
    vim.notify("sparkle: " .. vim.fn.bufname(b) .. " has unsaved changes", vim.log.levels.WARN)
  else
    pcall(vim.cmd, "bdelete " .. b)
  end
end

function _G.SparkleTablineClick(b, _clicks, button, _mods)
  if not api.nvim_buf_is_valid(b) then return end
  if button == "m" then
    M.close(b)
  elseif button == "l" then
    show(b)
  end
end

---------------------------------------------------------------- animation
local function redraw()
  if style.in_cmdline() then return end
  pcall(vim.cmd.redrawtabline)
end

local function stop()
  if timer then timer:stop() end
end

local frame = 0
local function tick()
  local t = now()
  if calm or t - last_input > M.config.idle_after then return stop() end
  local lv = L()
  if lv.sweep_every and t - sweep_t0 > lv.sweep_every then sweep_t0 = t end
  frame = frame + 1
  local sweeping = (t - sweep_t0) * M.config.sweep_speed < M.config.max_name + 8
  -- stars only need a few frames a second
  if sweeping or (lv.stars > 0 and frame % 4 == 0) then redraw() end
  if not sweeping and lv.stars <= 0 and not lv.sweep_every then stop() end
end

local function start()
  if calm then return end
  if not timer then timer = uv.new_timer() end
  if timer:is_active() then return end
  timer:start(0, floor(1000 / M.config.fps), vim.schedule_wrap(tick))
end

local function sweep()
  sweep_t0 = now()
  last_input = now()
  start()
end

function M.set_calm(c)
  calm = c
  define_hl()
  if calm then stop() else sweep() end
  redraw()
end

function M.setup()
  define_hl()
  vim.o.showtabline = 2
  vim.o.tabline = "%!v:lua.require'sparkle.tabline'.render()"
  last_input = now()

  local grp = api.nvim_create_augroup("SparkleTabline", { clear = true })
  local au = function(ev, fn) api.nvim_create_autocmd(ev, { group = grp, callback = fn }) end
  au("ColorScheme", function() vim.schedule(function() define_hl(); redraw() end) end)
  au("BufEnter", function(ev)
    if eligible(ev.buf) then
      if ev.buf ~= last_buf then sweep() end
      last_buf = ev.buf
    end
  end)
  au({ "BufAdd", "BufDelete", "BufWipeout", "BufModifiedSet", "BufFilePost", "DiagnosticChanged",
    "WinResized", "TabEnter", "TabClosed", "ModeChanged" }, function() vim.schedule(redraw) end)
  au("User", function(ev)
    if ev.match == "SparkleLevel" then sweep() end
  end)
  au("FocusLost", stop)
  au("FocusGained", function() last_input = now(); start() end)
  vim.on_key(function()
    last_input = now()
    if timer and not timer:is_active() and not calm then vim.schedule(start) end
  end, api.nvim_create_namespace("SparkleTablineKeys"))
  start()
end

return M
