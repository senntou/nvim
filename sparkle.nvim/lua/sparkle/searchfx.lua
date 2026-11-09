-- sparkle.searchfx: search matches keep shimmering after the search is done.
--
-- While 'hlsearch' highlighting is on (v:hlsearch), the matches of @/ in the visible windows are
-- drawn by this module instead of the Search group: the background flows between gold and magenta,
-- breathes, and a white sheen sweeps across now and then. Finishing a search, or landing on a
-- match (n / N / * / #), makes that match burst, rippling out to the others.
--
-- The native Search/CurSearch highlight is masked per window (winhighlight) while this is on, and
-- handed back on :nohlsearch, when a new search is typed (sparkle.cmdline takes over there) or in
-- the calm style.
local api, fn, uv = vim.api, vim.fn, vim.uv or vim.loop
local floor, max, min, abs, sin, cos = math.floor, math.max, math.min, math.abs, math.sin, math.cos
local style = require("sparkle.style")

local M = {}

M.config = {
  fps = 15,
  idle_after = 20, -- seconds without input before the shimmer holds still
  burst_life = 0.7,
  exclude_ft = { "NvimTree", "sparkle", "lazy", "mason", "TelescopePrompt", "TelescopeResults", "qf" },
}

local ns = api.nvim_create_namespace("SparkleSearchFx")
local NHUE, NLVL, NSHEEN = 8, 6, 3
local MASK = "Search:None,CurSearch:None"

local active = true -- feature switched on (sparkle style)
local on = false -- currently drawing
local masked = {} -- [win] = true while this module masks its Search highlight
local excluded = {}
local timer
local last_input = uv.hrtime() / 1e9
local burst -- { win, row, col, t0 }
local rx, rx_key

local function now() return uv.hrtime() / 1e9 end

---------------------------------------------------------------- colours
local function rgb(h) return { floor(h / 65536) % 256, floor(h / 256) % 256, h % 256 } end
local function mix(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end
local function pack(c)
  local q = function(v) return max(0, min(255, floor(v + 0.5))) end
  return q(c[1]) * 65536 + q(c[2]) * 256 + q(c[3])
end

-- all groups up front: SparkleSearchBuf_<hue>_<strength>_<sheen>
function M.define_hl()
  local bg = require("sparkle.theme").colors().bg
  local gold, magenta, white = rgb(0xffd34d), rgb(0xff4fd8), rgb(0xffffff)
  for h = 1, NHUE do
    local u = 0.5 - 0.5 * cos((h - 1) / NHUE * 2 * math.pi) -- cyclic gold -> magenta -> gold
    local hue = mix(gold, magenta, u)
    for l = 1, NLVL do
      local k = 0.25 + 0.7 * (l - 1) / (NLVL - 1) -- how far the background goes from Normal to the hue
      for j = 0, NSHEEN - 1 do
        local col = mix(bg, mix(hue, white, j * 0.3), k)
        -- strong tints get dark text (like Search), faint ones keep the syntax colour
        api.nvim_set_hl(0, ("SparkleSearchBuf_%d_%d_%d"):format(h, l, j),
          { bg = pack(col), fg = k > 0.6 and pack(bg) or nil, bold = k > 0.8 or nil })
      end
    end
  end
end

---------------------------------------------------------------- pattern
local function regex()
  if fn.getreg("/") == "" then return nil end
  local pat = fn.getreg("/")
  local ic = vim.o.ignorecase and not (vim.o.smartcase and pat:find("%u"))
  local key = pat .. (ic and "\1c" or "\1C")
  if key ~= rx_key then
    rx_key = key
    local ok, r = pcall(vim.regex, (ic and "\\c" or "\\C") .. pat)
    rx = ok and r or nil
  end
  return rx
end

local function hl_active()
  return vim.o.hlsearch and vim.v.hlsearch == 1
end

---------------------------------------------------------------- windows
local function eligible(win)
  if not api.nvim_win_is_valid(win) or api.nvim_win_get_config(win).relative ~= "" then return false end
  local buf = api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == "" and not excluded[vim.bo[buf].filetype]
end

local function mask(win)
  if masked[win] then return end
  local cur = vim.wo[win].winhighlight
  vim.wo[win].winhighlight = cur == "" and MASK or (cur .. "," .. MASK)
  masked[win] = true
end

local function unmask(win)
  masked[win] = nil
  if not api.nvim_win_is_valid(win) then return end
  local cur = vim.wo[win].winhighlight
  local out = cur:gsub(",?" .. vim.pesc(MASK), "")
  vim.wo[win].winhighlight = out
end

local function mask_all()
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if eligible(w) then mask(w) elseif masked[w] then unmask(w) end
  end
end

---------------------------------------------------------------- drawing
local function cell_group(t, seed, cx, w, strength, flash)
  local h = floor(((cx * 0.12 + seed * 0.29 - t * 0.45) % 1) * NHUE) + 1
  local sweep = ((t * 0.55 + seed * 0.37) % 1.6) * (w + 6) - 3
  local j = max(flash, floor(max(0, 1 - abs(cx - sweep) / 1.6) * (NSHEEN - 1) + 0.5))
  local l = max(1, min(NLVL, floor((strength - 0.25) / 0.7 * (NLVL - 1) + 1.5)))
  return ("SparkleSearchBuf_%d_%d_%d"):format(h, l, j)
end

local frame = {} -- per redraw: { t, cur_row (of the burst window) }

local function on_win(_, win, buf, top)
  -- (no in_cmdline check: drawing is fine, only forcing redraws is not, and tick() holds off then)
  if not on or not masked[win] then return false end
  if not regex() then return false end
  frame.t = now()
  frame.top = top
  return true
end

local function on_line(_, win, buf, row)
  local r = rx
  if not r then return end
  local t = frame.t
  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  if line == "" then return end
  local start = 0
  for _ = 1, 60 do
    local s, e = r:match_line(buf, row, start)
    if not s then break end
    s, e = start + s, start + e
    if e <= s then -- empty match: step over one character
      start = s + 1
    else
      local seed = row * 7 + s
      local strength = 0.32 + 0.08 * sin(t * 3.1 + seed * 0.9)
      local flash = 0
      local b = burst
      if b and b.win == win then
        local is_cur = b.row == row and s <= b.col and b.col < e
        local age = t - b.t0 - (is_cur and 0 or abs(row - b.row) * 0.025)
        if age >= 0 and age < M.config.burst_life then
          local k = 1 - age / M.config.burst_life
          strength = max(strength, (is_cur and 0.95 or 0.65) * k * k)
          if age < 0.18 then flash = NSHEEN - 1 end
        end
      end
      local cx, w = 0, fn.strchars(line:sub(s + 1, e))
      local i = s
      while i < e do
        local n = #(line:sub(i + 1):match("^[%z\1-\127\194-\244][\128-\191]*") or "x")
        api.nvim_buf_set_extmark(buf, ns, row, i, {
          end_col = min(i + n, #line), hl_group = cell_group(t, seed, cx, w, strength, flash),
          ephemeral = true, priority = 4000,
        })
        i, cx = i + n, cx + 1
      end
      start = e
    end
    if start >= #line then break end
  end
end

---------------------------------------------------------------- loop
local function stop() if timer then timer:stop() end end

function M.deactivate()
  if not on and next(masked) == nil then return end
  on, burst = false, nil
  stop()
  for w in pairs(masked) do unmask(w) end
end

local function tick()
  if not on then return stop() end
  if style.in_cmdline() then return end
  if not hl_active() then return M.deactivate() end
  local t = now()
  if t - last_input > M.config.idle_after and not (burst and t - burst.t0 < 2) then return stop() end
  for w in pairs(masked) do
    if api.nvim_win_is_valid(w) then
      pcall(api.nvim__redraw, { win = w, valid = false })
    else
      masked[w] = nil
    end
  end
  pcall(api.nvim__redraw, { flush = true })
end

local function start()
  if not on then return end
  if not timer then timer = uv.new_timer() end
  if timer:is_active() then return end
  timer:start(0, floor(1000 / M.config.fps), vim.schedule_wrap(tick))
end

local function activate()
  if not active or not hl_active() or not regex() then return false end
  if not on then
    on = true
    mask_all()
  end
  last_input = now()
  start()
  return true
end

-- burst the match under the cursor (if any) in the current window
local function burst_here()
  local win = api.nvim_get_current_win()
  local r = regex()
  if not r or not masked[win] then return end
  local pos = api.nvim_win_get_cursor(win)
  burst = { win = win, row = pos[1] - 1, col = pos[2], t0 = now() }
end

---------------------------------------------------------------- setup
function M.set_active(v)
  active = v
  if not v then M.deactivate() end
end

function M.setup()
  excluded = {}
  for _, ft in ipairs(M.config.exclude_ft) do excluded[ft] = true end
  M.define_hl()
  api.nvim_set_decoration_provider(ns, { on_win = on_win, on_line = on_line })

  local grp = api.nvim_create_augroup("SparkleSearchFx", { clear = true })
  api.nvim_create_autocmd("ColorScheme", { group = grp, callback = function() vim.schedule(M.define_hl) end })
  -- typing a new search: hand the highlighting back (sparkle.cmdline draws that phase)
  -- (no autocmd pattern here: patterns are globs, and "?" would match ":" as well, so opening any
  -- command line switched the shimmer off)
  local function is_search(ev) return ev.match == "/" or ev.match == "?" end
  api.nvim_create_autocmd("CmdlineEnter", { group = grp, callback = function(ev)
    if is_search(ev) then M.deactivate() end
  end })
  api.nvim_create_autocmd("CmdlineLeave", { group = grp, callback = function(ev)
    if not is_search(ev) then return end
    local abort = vim.v.event.abort
    vim.schedule(function()
      -- an aborted search keeps the old pattern highlighted: shimmer again, without the burst
      if activate() and not abort then burst_here() end
    end)
  end })
  -- landing on a match (n, N, *, #, ...) makes it burst
  api.nvim_create_autocmd("CursorMoved", { group = grp, callback = function()
    if not active or not hl_active() then return end
    local r = regex()
    if not r then return end
    local pos = api.nvim_win_get_cursor(0)
    local s = r:match_line(0, pos[1] - 1, pos[2])
    if s == 0 and activate() then burst_here() end
  end })
  api.nvim_create_autocmd({ "WinEnter", "BufWinEnter", "WinNew", "TabEnter" }, { group = grp, callback = function()
    if on then vim.schedule(mask_all) end
  end })
  api.nvim_create_autocmd("WinClosed", { group = grp, callback = function(ev)
    masked[tonumber(ev.match)] = nil
  end })
  api.nvim_create_autocmd("FocusLost", { group = grp, callback = stop })
  api.nvim_create_autocmd("FocusGained", { group = grp, callback = function()
    last_input = now()
    start()
  end })
  vim.on_key(function()
    last_input = now()
    if on and timer and not timer:is_active() then vim.schedule(start) end
    -- :nohlsearch (or <C-l>) has no event: notice it on the next key
    if on then vim.schedule(function() if on and not hl_active() then M.deactivate() end end) end
  end, api.nvim_create_namespace("SparkleSearchFxKeys"))
end

return M
