-- sparkle.cmdline: the command line, re-drawn as a floating panel in the middle of the screen.
--
-- Uses vim.ui_attach({ext_cmdline}) (modelled on Neovim 0.12's builtin vim._core.ui2): the text
-- lives in a normal floating window (so the real cursor, CJK input and syntax colouring just
-- work), sitting on top of an animated sparkle.canvas frame.
-- Messages are left alone (they still appear at the bottom).
-- The box is transparent (the editor's Normal background shows through); typing makes the
-- input text itself light up (a pop on the new character and a ripple running along the line),
-- and while searching, the matches in the window flash their background whenever the pattern changes.
-- calm style: no canvas frame; the text window gets a plain rounded border in the colorscheme's colours.
local overlay = require("sparkle.overlay")
local C = require("sparkle.canvas")
local theme = require("sparkle.theme")
local api, fn = vim.api, vim.fn
local floor, max, min = math.floor, math.max, math.min
local pal = overlay.pal

local M = {}

M.config = {
  width = 64, -- minimum text width
  max_width = 0.8, -- fraction of the screen
  row = 0.30, -- vertical position (fraction of the screen)
  fps = 24,
  effects = true, -- input text lights up while typing
  search_effects = true, -- search matches shimmer (background) and burst when the pattern changes
  max_search_flashes = 40,
}

local ns = api.nvim_create_namespace("sparkle.cmdline")
local calm = false
local S = {
  buf = -1, win = -1, ov = nil,
  level = 0, firstc = "", prompt = "", text = "", pos = 0, indent = 0,
  block = {}, -- previous lines of a cmdline block (:function ... etc.)
  prefix_len = 0, row = 0, -- cursor anchor
  redrawing = false,
}

local kinds = {
  [":"] = { label = "COMMAND", icon = "❯ ", a = pal.cyan, b = pal.purple, an = "cyan", bn = "purple" },
  ["/"] = { label = "SEARCH ↓", icon = "/ ", a = pal.gold, b = pal.magenta, an = "gold", bn = "magenta" },
  ["?"] = { label = "SEARCH ↑", icon = "? ", a = pal.gold, b = pal.magenta, an = "gold", bn = "magenta" },
  ["="] = { label = "EXPRESSION", icon = "= ", a = pal.green, b = pal.cyan, an = "green", bn = "cyan" },
  [">"] = { label = "DEBUG", icon = "> ", a = pal.red, b = pal.gold, an = "red", bn = "gold" },
  [""] = { label = "INPUT", icon = "", a = pal.magenta, b = pal.cyan, an = "magenta", bn = "cyan" },
}
local function kind()
  return kinds[S.firstc] or { label = "INPUT", icon = S.firstc ~= "" and (S.firstc .. " ") or "",
    a = pal.magenta, b = pal.cyan, an = "magenta", bn = "cyan" }
end

---------------------------------------------------------------- windows
local function geometry(text_h)
  local cols, lines = vim.o.columns, vim.o.lines
  local need = 0
  for _, l in ipairs(api.nvim_buf_get_lines(S.buf, 0, -1, false)) do need = max(need, fn.strdisplaywidth(l) + 2) end
  local maxw = max(10, min(floor(cols * M.config.max_width), cols - 6))
  local w = min(maxw, max(M.config.width, need))
  local h = max(1, min(text_h or 1, lines - 6))
  local row = max(0, min(floor(lines * M.config.row) - floor(h / 2), lines - h - 4))
  local col = max(0, floor((cols - (w + 4)) / 2))
  return { w = w, h = h, row = row, col = col }
end

local function valid_here(win)
  return win and api.nvim_win_is_valid(win) and api.nvim_win_get_tabpage(win) == api.nvim_get_current_tabpage()
end

local function draw_frame(c, t, dt, ov)
  local k = kind()
  c:clear_pixels(theme.colors().bg) -- transparent: only what is drawn below is painted
  c:clear_text()
  overlay.frame(c, t, k.a, k.b, { speed = 0.45 })
  local title = " ✦ " .. k.label .. (S.level > 1 and ("  LV" .. S.level) or "") .. " "
  c:put_gradient(3, 0, title, C.add(k.a, pal.white, 0.35), k.b, { bold = true })
  M.paint_fx()
  M.paint_search_fx()
  return true
end

local function flush_screen()
  if S.redrawing then return end
  S.redrawing = true
  if api.nvim__redraw then -- 0.10+
    pcall(api.nvim__redraw, { flush = true, cursor = true, win = valid_here(S.win) and S.win or nil })
  else
    pcall(vim.cmd, "redraw")
  end
  S.redrawing = false
end

local function ensure_buf()
  if not api.nvim_buf_is_valid(S.buf) then
    S.buf = api.nvim_create_buf(false, true)
    vim.bo[S.buf].bufhidden = "hide"
    pcall(api.nvim_buf_set_name, S.buf, "[SparkleCmdline]")
  end
end

local function calm_title()
  local k = kind()
  return " " .. k.label .. (S.level > 1 and ("  LV" .. S.level) or "") .. " "
end

local function ensure_windows(g)
  ensure_buf()
  local text_cfg = {
    relative = "editor", row = g.row + 1, col = g.col + 2, width = g.w, height = g.h,
    zindex = 241, style = "minimal", focusable = false, border = "none", hide = false,
    _cmdline_offset = S.prefix_len,
  }
  if calm then
    -- the border takes the place of the frame: same text position as the sparkle style
    text_cfg.row, text_cfg.col = g.row, g.col + 1
    text_cfg.border, text_cfg.title, text_cfg.title_pos = "rounded", calm_title(), "left"
  end
  if not valid_here(S.win) then
    if api.nvim_win_is_valid(S.win) then pcall(api.nvim_win_close, S.win, true) end
    text_cfg.noautocmd = true
    S.win = overlay.open_win(S.buf, false, text_cfg)
    local wo = vim.wo[S.win]
    wo.winhighlight = (calm and "Normal:Normal,NormalFloat:Normal,FloatBorder:FloatBorder,FloatTitle:FloatTitle"
      or "Normal:SparkleCmdline,NormalFloat:SparkleCmdline") .. ",Search:None,CurSearch:None,IncSearch:None"
    wo.wrap, wo.linebreak, wo.breakindent = true, false, false
    wo.showbreak, wo.list, wo.spell = "", false, false
    pcall(function() wo.eventignorewin = "all" end) -- 0.11+
  else
    overlay.win_set_config(S.win, text_cfg)
  end
  if calm then
    if S.ov then
      S.ov:close()
      S.ov = nil
    end
    return
  end
  local frame_cfg = { relative = "editor", row = g.row, col = g.col, width = g.w + 4, height = g.h + 2, hide = false }
  -- A terminal that is resized keeps its old rows until the next redraw and the picture would
  -- come out shifted: open a fresh frame whenever the size changes.
  local reuse = S.ov and not S.ov.closed and valid_here(S.ov.win)
    and api.nvim_win_get_width(S.ov.win) == frame_cfg.width and api.nvim_win_get_height(S.ov.win) == frame_cfg.height
  if not reuse then
    if S.ov then S.ov:close() end
    S.ov = overlay.open(vim.tbl_extend("force", frame_cfg, { zindex = 240, fps = M.config.fps, transparent = true }),
      draw_frame)
    if S.ov then S.ov.redraw = flush_screen end
  else
    S.ov:move(frame_cfg)
    S.ov:start()
  end
end

local function hide_windows()
  M.clear_fx()
  if api.nvim_win_is_valid(S.win) then
    if not pcall(overlay.win_set_config, S.win, { hide = true }) or not api.nvim_win_get_config(S.win).hide then
      pcall(api.nvim_win_close, S.win, true) -- Neovim < 0.10 cannot hide floats
    end
  end
  if S.ov and not S.ov.closed then
    S.ov:stop()
    S.ov:move({ hide = true })
    if not (S.ov:valid() and api.nvim_win_get_config(S.ov.win).hide) then
      S.ov:close() -- Neovim < 0.10 cannot hide floats
      S.ov = nil
    end
  end
end

---------------------------------------------------------------- rendering
local function highlight_vim(line, row, start)
  local ok, parser = pcall(vim.treesitter.get_string_parser, line, "vim")
  if not ok or not parser then return end
  pcall(function()
    parser:parse(true)
    parser:for_each_tree(function(tstree, tree)
      local query = tstree and vim.treesitter.query.get(tree:lang(), "highlights")
      if not query then return end
      for capture, node in query:iter_captures(tstree:root(), line) do
        local _, sc, _, ec = node:range()
        local name = query.captures[capture]
        if name:sub(1, 1) ~= "_" then
          api.nvim_buf_set_extmark(S.buf, ns, row, start + sc, {
            end_col = start + ec, hl_group = ("@%s.%s"):format(name, query.lang), priority = 100,
          })
        end
      end
    end)
  end)
end

local function render()
  local k = kind()
  local prompt_lines = vim.split(S.prompt, "\n", { plain = true })
  local head = k.icon .. fn.strtrans(prompt_lines[#prompt_lines]) .. (" "):rep(S.indent)
  S.prefix_len = #head
  local lines = {}
  for _, b in ipairs(S.block) do lines[#lines + 1] = "  " .. b end
  for i = 1, #prompt_lines - 1 do lines[#lines + 1] = fn.strtrans(prompt_lines[i]) end
  S.row = #lines
  lines[#lines + 1] = head .. fn.strtrans(S.text) .. " "
  ensure_buf()
  api.nvim_buf_set_lines(S.buf, 0, -1, false, lines)
  api.nvim_buf_clear_namespace(S.buf, ns, 0, -1)
  for i = 0, #S.block - 1 do
    api.nvim_buf_set_extmark(S.buf, ns, i, 0, { end_col = 2, hl_group = calm and "Special" or "SparkleCmdlineIcon" })
  end
  local icon_hl = calm and "Special" or "SparkleCmdlineIcon"
  if #k.icon > 0 then
    api.nvim_buf_set_extmark(S.buf, ns, S.row, 0, { end_col = #k.icon, hl_group = icon_hl })
  end
  if #head > #k.icon then
    api.nvim_buf_set_extmark(S.buf, ns, S.row, #k.icon,
      { end_col = #head, hl_group = calm and "Question" or "SparkleCmdlinePrompt" })
  end
  if S.firstc == ":" then highlight_vim(fn.strtrans(S.text), S.row, #head) end

  -- size: measure wrapped height with the final width
  local g = geometry(1)
  ensure_windows(g)
  local th
  if api.nvim_win_text_height then -- 0.10+
    th = api.nvim_win_text_height(S.win, {}).all
  else
    th = 0
    for _, l in ipairs(api.nvim_buf_get_lines(S.buf, 0, -1, false)) do
      th = th + math.max(1, math.ceil(fn.strdisplaywidth(l) / g.w))
    end
  end
  if th ~= g.h then
    g = geometry(th)
    ensure_windows(g)
  end
end

local function place_cursor()
  if not valid_here(S.win) then return end
  local col = S.prefix_len + #fn.strtrans(S.text:sub(1, S.pos))
  pcall(api.nvim_win_set_cursor, S.win, { S.row + 1, col })
end

---------------------------------------------------------------- input effects
-- Highlights on the input text inside the cmdline's own window: only that small float is redrawn,
-- the editor windows (and their 'incsearch' highlighting) are left alone.
local fxns = api.nvim_create_namespace("sparkle.cmdline.fx")
local FX_COLORS = { "cyan", "magenta", "gold", "green", "red", "purple" }
local FX_LVL = 6
local POP_LIFE, DEL_LIFE, WAVE_LIFE, WAVE_SPEED = 0.35, 0.25, 0.5, 30 -- seconds, chars/s
local pops = {} -- { i = char index (1-based) of the touched character, t0, del }
local painted = false
local function now() return (vim.uv or vim.loop).hrtime() / 1e9 end

-- groups are created up front: nvim_set_hl while typing would redraw every window
function M.define_fx_hl()
  local th = theme.colors()
  for _, name in ipairs(FX_COLORS) do
    for l = 1, FX_LVL do
      local k = l / FX_LVL
      local col = C.lerp(th.fg, C.add(pal[name], pal.white, max(0, k - 0.7) * 1.6), 0.2 + 0.8 * k)
      api.nvim_set_hl(0, ("SparkleCmdIn_%s_%d"):format(name, l), {
        fg = string.format("#%02x%02x%02x", min(255, floor(col[1])), min(255, floor(col[2])), min(255, floor(col[3]))),
        bold = l >= FX_LVL - 2,
      })
    end
  end
end

function M.clear_fx()
  M.clear_search_fx()
  pops, painted = {}, false
  if api.nvim_buf_is_valid(S.buf) then api.nvim_buf_clear_namespace(S.buf, fxns, 0, -1) end
end

-- a character was typed (or deleted) just before the cursor
function M.typed(insert)
  if calm or not M.config.effects then return end
  local i = fn.strchars(S.text:sub(1, S.pos))
  if i < 1 then return end
  if #pops > 12 then table.remove(pops, 1) end
  pops[#pops + 1] = { i = i, t0 = now(), del = not insert }
end

function M.paint_fx()
  if not api.nvim_buf_is_valid(S.buf) then return end
  if #pops == 0 and not painted then return end
  api.nvim_buf_clear_namespace(S.buf, fxns, 0, -1)
  painted = false
  if #pops == 0 then return end
  local t = now()
  local live = {}
  for _, p in ipairs(pops) do
    if t - p.t0 < WAVE_LIFE then live[#live + 1] = p end
  end
  pops = live
  if #pops == 0 then return end
  local k = kind()
  local disp = fn.strtrans(S.text)
  local i, byte = 0, S.prefix_len
  for ch in disp:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    i = i + 1
    local best, name = 0, nil
    for _, p in ipairs(pops) do
      local age = t - p.t0
      local d = math.abs(i - p.i)
      local v, n
      if d == 0 then -- the character itself pops
        v, n = 1 - age / (p.del and DEL_LIFE or POP_LIFE), p.del and k.bn or k.an
      elseif not p.del then -- a ripple running away from it along the line
        v, n = max(0, 1 - math.abs(d - age * WAVE_SPEED) / 1.6) * (1 - age / WAVE_LIFE) * 0.8, k.bn
      end
      if v and v > best then best, name = v, n end
    end
    if best > 0.08 then
      painted = true
      local lvl = max(1, min(FX_LVL, math.ceil(best * FX_LVL)))
      pcall(api.nvim_buf_set_extmark, S.buf, fxns, S.row, byte, {
        end_col = byte + #ch, hl_group = ("SparkleCmdIn_%s_%d"):format(name, lvl), priority = 200,
      })
    end
    byte = byte + #ch
  end
end

---------------------------------------------------------------- search match effects
-- While searching, every visible match carries a small float whose background shimmers (a slow
-- gold <-> magenta flow plus a white sheen sweeping across); each time the pattern changes the
-- matches burst: a bright flash, a halo one cell wider, rippling out from the current match.
-- Floats are composited on top of the window: the window itself is never redrawn, so the
-- 'incsearch' highlighting underneath survives and shows through the tint.
local matches = {} -- { row, col, width, delay, current }
local hit_t0 = -100
local pool = {} -- { win, buf, width, key, hl }
local sfx_ns = api.nvim_create_namespace("sparkle.cmdline.search")
local NHUE, NSHEEN = 12, 4
local BURST_LIFE, HALO_LIFE = 0.7, 0.35
local search_seq = 0

local function rgbhex(c)
  return string.format("#%02x%02x%02x", min(255, floor(c[1] + 0.5)), min(255, floor(c[2] + 0.5)), min(255, floor(c[3] + 0.5)))
end

-- created up front: nvim_set_hl while searching would redraw every window
function M.define_search_hl()
  local a, b = pal.gold, pal.magenta
  for h = 1, NHUE do
    local u = 0.5 - 0.5 * math.cos((h - 1) / NHUE * 2 * math.pi) -- cyclic a -> b -> a
    local base = C.lerp(a, b, u)
    for j = 0, NSHEEN - 1 do
      api.nvim_set_hl(0, ("SparkleSearchFx_%d_%d"):format(h, j), { bg = rgbhex(C.lerp(base, pal.white, j * 0.25)) })
    end
  end
  api.nvim_set_hl(0, "SparkleSearchHalo", { bg = rgbhex(C.lerp(theme.colors().bg, pal.gold, 0.5)) })
end

local function search_pattern()
  local t, sep = S.text, S.firstc
  local out, i = {}, 1
  while i <= #t do -- the pattern ends at an unescaped separator (an offset may follow)
    local c = t:sub(i, i)
    if c == "\\" then
      out[#out + 1] = t:sub(i, i + 1)
      i = i + 2
    elseif c == sep then
      break
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  local pat = table.concat(out)
  if pat == "" then return nil end
  if vim.o.ignorecase and vim.o.smartcase and not pat:find("\\[cC]") and pat:find("%u") then pat = "\\C" .. pat end
  return pat
end

local function find_matches()
  local pat = search_pattern()
  if not pat then return {} end
  local win = api.nvim_get_current_win()
  local info = fn.getwininfo(win)[1]
  if not info or api.nvim_win_get_config(win).relative ~= "" then return {} end
  local buf = api.nvim_win_get_buf(win)
  local left, right = info.wincol - 1 + info.textoff, info.wincol - 1 + info.width
  local cur = api.nvim_win_get_cursor(win)
  local cur_row = fn.screenpos(win, cur[1], cur[2] + 1).row
  local list = {}
  for lnum = info.topline, info.botline do
    if fn.foldclosed(lnum) == -1 then
      local line = api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
      local start = 0
      while #list < M.config.max_search_flashes do
        local ok, m = pcall(fn.matchstrpos, line, pat, start)
        if not ok or m[2] < 0 then break end
        local s, e = m[2], m[3]
        if e > s then
          local p = fn.screenpos(win, lnum, s + 1)
          if p.row > 0 then
            local w = min(fn.strdisplaywidth(line:sub(s + 1, e)), right - (p.col - 1))
            if w > 0 then
              list[#list + 1] = {
                row = p.row - 1, col = p.col - 1, width = w, left = left, right = right,
                current = lnum == cur[1] and s <= cur[2] and cur[2] < e,
                delay = math.abs(p.row - cur_row) * 0.025, -- ripple out from the current match
              }
            end
          end
          start = e
        else
          start = s + 1
        end
        if start > #line then break end
      end
    end
  end
  return list
end

local function hide_from(n)
  for i = n, #pool do
    local p = pool[i]
    if api.nvim_win_is_valid(p.win) and not p.hidden then
      pcall(overlay.win_set_config, p.win, { hide = true })
      p.hidden = true
    end
  end
end

function M.clear_search_fx()
  matches = {}
  hide_from(1)
end

-- the pattern changed: find the matches once incsearch has moved/scrolled the view, then burst
function M.search_changed()
  if calm or not M.config.search_effects then return end
  search_seq = search_seq + 1
  local seq = search_seq
  vim.schedule(function()
    if seq ~= search_seq or S.level == 0 or (S.firstc ~= "/" and S.firstc ~= "?") then return end
    local ok, list = pcall(find_matches)
    matches = ok and list or {}
    hit_t0 = now()
    if #matches == 0 then hide_from(1) end
  end)
end

local function place(i, row, col, width)
  local p = pool[i]
  local cfg = { relative = "editor", row = row, col = col, width = width, height = 1, hide = false }
  if p and api.nvim_win_is_valid(p.win) and api.nvim_win_get_tabpage(p.win) == api.nvim_get_current_tabpage() then
    if p.width ~= width then
      api.nvim_buf_set_lines(p.buf, 0, -1, false, { (" "):rep(width) })
      p.width, p.key = width, nil
    end
    if p.hidden or p.row ~= row or p.col ~= col or p.cfg_w ~= width then
      pcall(overlay.win_set_config, p.win, cfg)
      p.hidden, p.row, p.col, p.cfg_w = false, row, col, width
    end
    return p
  end
  if p and api.nvim_win_is_valid(p.win) then pcall(api.nvim_win_close, p.win, true) end
  local buf = (p and api.nvim_buf_is_valid(p.buf)) and p.buf or api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  api.nvim_buf_set_lines(buf, 0, -1, false, { (" "):rep(width) })
  cfg.zindex, cfg.style, cfg.focusable, cfg.noautocmd, cfg.border = 45, "minimal", false, true, "none"
  local ok, win = pcall(overlay.open_win, buf, false, cfg)
  if not ok then return nil end
  vim.wo[win].winblend = 100
  vim.wo[win].winhighlight = "Normal:SparkleSearchHalo"
  pcall(function() vim.wo[win].eventignorewin = "all" end)
  p = { win = win, buf = buf, width = width, row = row, col = col, cfg_w = width }
  pool[i] = p
  return p
end

function M.paint_search_fx()
  if #matches == 0 then return end
  if calm or S.level == 0 or (S.firstc ~= "/" and S.firstc ~= "?") then return M.clear_search_fx() end
  local t = now()
  for i, m in ipairs(matches) do
    local age = t - hit_t0 - m.delay
    local burst = (age >= 0 and age < BURST_LIFE) and (1 - age / BURST_LIFE) or 0
    burst = burst * burst
    -- tint strength 0..1: a gentle breathing glow, raised by the burst
    local base = 0.3 + 0.08 * math.sin(t * 3.1 + i * 0.9)
    local strength = max(base, (m.current and 0.85 or 0.7) * burst)
    local halo = age >= 0 and age < HALO_LIFE
    local col, width, pad_l = m.col, m.width, 0
    if halo then
      if col - 1 >= m.left then col, pad_l = col - 1, 1 end
      width = m.width + pad_l + ((m.col + m.width < m.right) and 1 or 0)
    end
    local p = place(i, m.row, col, width)
    if p then
      local blend = floor(100 - strength * 100 + 0.5)
      if p.blend ~= blend then
        vim.wo[p.win].winblend = blend
        p.blend = blend
      end
      -- per cell: flowing hue + a white sheen sweeping across now and then (+ white at the burst)
      local sweep = ((t * 0.55 + i * 0.37) % 1.6) * (m.width + 6) - 3
      local flash = (age >= 0 and age < 0.18) and (NSHEEN - 1) or 0
      local groups = {}
      for x = 0, width - 1 do
        local cx = x - pad_l
        if cx < 0 or cx >= m.width then
          groups[x + 1] = "SparkleSearchHalo"
        else
          local h = floor(((cx * 0.12 + i * 0.29 - t * 0.45) % 1) * NHUE) + 1
          local j = max(flash, floor(max(0, 1 - math.abs(cx - sweep) / 1.6) * (NSHEEN - 1) + 0.5))
          groups[x + 1] = ("SparkleSearchFx_%d_%d"):format(h, j)
        end
      end
      local key = table.concat(groups, ",")
      if p.key ~= key then
        p.key = key
        api.nvim_buf_clear_namespace(p.buf, sfx_ns, 0, -1)
        for x = 0, width - 1 do
          api.nvim_buf_set_extmark(p.buf, sfx_ns, 0, x, { end_col = x + 1, hl_group = groups[x + 1] })
        end
      end
    end
  end
  hide_from(#matches + 1)
end

---------------------------------------------------------------- ui events
local H = {}

function H.cmdline_show(content, pos, firstc, prompt, indent, level, _hl_id)
  local text = {}
  for _, chunk in ipairs(content) do text[#text + 1] = chunk[2] end
  local new = table.concat(text)
  local delta = S.level == level and (#new - #S.text) or 0
  S.text, S.pos, S.firstc, S.prompt, S.indent, S.level = new, pos, firstc, prompt, indent, level
  render()
  place_cursor()
  if delta ~= 0 then
    M.typed(delta > 0)
    if firstc == "/" or firstc == "?" then M.search_changed() end
  end
  M.paint_fx()
end

function H.cmdline_pos(pos, _level)
  S.pos = pos
  place_cursor()
end

function H.cmdline_special_char(c, shift, level)
  if level and level ~= S.level then return end
  -- show the pending character (e.g. after <C-v>/<C-r>) at the cursor
  local before, after = S.text:sub(1, S.pos), S.text:sub(S.pos + 1)
  if not shift then after = after:sub(2) end
  local saved = S.text
  S.text = before .. c .. after
  render()
  place_cursor()
  S.text = saved
end

function H.cmdline_hide(level, _abort)
  if (level and level > 1) or S.in_block then return end
  S.level, S.block = 0, {}
  hide_windows()
end

function H.cmdline_block_show(lines)
  S.block, S.in_block = {}, true
  for _, content in ipairs(lines) do
    local t = {}
    for _, chunk in ipairs(content) do t[#t + 1] = chunk[2] end
    S.block[#S.block + 1] = table.concat(t)
  end
end

function H.cmdline_block_append(line)
  local t = {}
  for _, chunk in ipairs(line) do t[#t + 1] = chunk[2] end
  S.block[#S.block + 1] = table.concat(t)
end

function H.cmdline_block_hide()
  S.block, S.in_block = {}, false
  H.cmdline_hide(1, true)
end

local function handle(event, ...)
  local ok, err = pcall(H[event], ...)
  if not ok then
    vim.schedule(function() vim.notify("sparkle.cmdline: " .. tostring(err), vim.log.levels.ERROR) end)
  end
  if event ~= "cmdline_hide" and event ~= "cmdline_block_hide" then
    flush_screen()
  end
end
local scheduled = vim.schedule_wrap(handle)

---------------------------------------------------------------- setup
local function define_hl()
  api.nvim_set_hl(0, "SparkleCmdline", { default = true, link = "Normal" }) -- see-through box
  M.define_fx_hl()
  M.define_search_hl()
  api.nvim_set_hl(0, "SparkleCmdlineIcon", { default = true, fg = "#46e0ff", bold = true })
  api.nvim_set_hl(0, "SparkleCmdlinePrompt", { default = true, fg = "#ffd34d", bold = true })
end

---------------------------------------------------------------- "pattern not found" guard
-- With ext_cmdline the executed search is echoed ("/foo") on its own message line, so a following
-- "E486: Pattern not found" makes two lines and stops at a hit-enter prompt. When the pattern has
-- no match anywhere in the buffer, abort the search instead and say so with vim.notify.

-- the pattern part of a "/pat/e;..." search command (nil when it can't be told apart safely)
local function search_part(line, delim)
  local i, n = 1, #line
  while i <= n do
    local c = line:sub(i, i)
    if c == "\\" then
      i = i + 2
    elseif c == "[" then
      return line:find(delim, i, true) == nil and line or nil -- a collection may hold the delimiter
    elseif c == delim then
      return line:sub(1, i - 1)
    else
      i = i + 1
    end
  end
  return line
end

-- true only when pat is a valid pattern with no match in the current buffer
local function no_match(pat)
  if pat == nil or pat == "" then return false end
  local ok, lnum = pcall(fn.search, pat, "nw")
  return ok and lnum == 0
end

local function not_found(pat)
  vim.schedule(function()
    vim.notify("Pattern not found: " .. pat, vim.log.levels.WARN, { title = "search" })
  end)
end

local function search_cr()
  local t = fn.getcmdtype()
  if t ~= "/" and t ~= "?" then return "<CR>" end
  local line = fn.getcmdline()
  local pat = search_part(line, t)
  if not no_match(pat) then return "<CR>" end
  fn.histadd("search", line) -- still recallable with <Up>
  not_found(pat)
  return "<C-c>"
end

local function search_next(key)
  return function()
    local pat = fn.getreg("/")
    if no_match(pat) then
      not_found(pat)
      return ""
    end
    return key -- a typed count is still pending and applies to this key
  end
end

local function map_guard()
  vim.keymap.set("c", "<CR>", search_cr, { expr = true, desc = "sparkle: search without E486 stop" })
  for _, k in ipairs({ "n", "N" }) do
    vim.keymap.set({ "n", "x", "o" }, k, search_next(k), { expr = true, desc = "sparkle: " .. k .. " without E486 stop" })
  end
end

local function unmap_guard()
  pcall(vim.keymap.del, "c", "<CR>")
  for _, k in ipairs({ "n", "N" }) do pcall(vim.keymap.del, { "n", "x", "o" }, k) end
end

function M.enable()
  if M.enabled or #api.nvim_list_uis() == 0 then return end
  M.enabled = true
  define_hl()
  map_guard()
  vim.ui_attach(ns, { ext_cmdline = true }, function(event, ...)
    if not H[event] then return end
    if vim.in_fast_event() then
      scheduled(event, ...)
    else
      handle(event, ...)
    end
    return true
  end)
end

function M.disable()
  if not M.enabled then return end
  M.enabled = false
  unmap_guard()
  vim.ui_detach(ns)
  hide_windows()
end

function M.set_calm(c)
  if c == calm then return end
  calm = c
  M.clear_fx()
  -- recreate both windows in the new style next time the cmdline opens
  if api.nvim_win_is_valid(S.win) then pcall(api.nvim_win_close, S.win, true) end
  if S.ov then
    S.ov:close()
    S.ov = nil
  end
end

function M.setup()
  define_hl()
  local grp = api.nvim_create_augroup("SparkleCmdline", { clear = true })
  api.nvim_create_autocmd("ColorScheme", { group = grp, callback = define_hl })
  api.nvim_create_autocmd("VimResized", { group = grp, callback = function()
    if S.level > 0 then render(); place_cursor(); flush_screen() end
  end })
  api.nvim_create_user_command("SparkleCmdline", function(o)
    if o.args == "off" then M.disable() else M.enable() end
  end, { nargs = "?", complete = function() return { "on", "off" } end, desc = "sparkle centred cmdline" })
  if vim.v.vim_did_enter == 1 then
    M.enable()
  else
    api.nvim_create_autocmd("VimEnter", { group = grp, once = true, callback = M.enable })
  end
end

return M
