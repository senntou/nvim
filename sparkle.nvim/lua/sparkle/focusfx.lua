-- sparkle.focusfx: the window (pane) that receives the focus lights up in the mode colour for a
-- moment and fades back, e.g. when jumping between NvimTree and a file with <C-w>.
--
-- Two layers:
--   * the whole pane is tinted and fades back: the window-local 'winhighlight' (Normal /
--     EndOfBuffer) is swapped for a few frames, also on sparkle.stars' filler float that covers
--     the rows below the end of the buffer
--   * a glint runs down the pane from top to bottom: per screen row line highlights (whole width,
--     text or not) from a decoration provider
local api, uv = vim.api, vim.uv or vim.loop
local style = require("sparkle.style")
local floor, max, min = math.floor, math.max, math.min

local M = {}

M.config = {
  duration = 0.4, -- seconds for the tint to fade
  wave_duration = 0.42, -- seconds for the glint to run from the top to the bottom
  wave_half = 3, -- half height of the glint in rows
  fps = 50,
  strength = { 0.12, 0.2, 0.28 }, -- peak tint per flashiness level
  wave = { 0.22, 0.32, 0.45 }, -- glint strength per flashiness level
}

local FL = 8 -- fade steps
local active = false
local flashes = {} -- [win] = { t0, k, winhl (original), normal, eob, tint }
local timer
local from_float = false -- the focus came back from a float (picker, notification, ...)
local ns = api.nvim_create_namespace("SparkleFocusFx")
local wave -- { win, t0, height } the glint (one pane at a time)
local WL = 8 -- glint brightness steps

local function now() return uv.hrtime() / 1e9 end
local function rgb(h) return { floor(h / 65536) % 256, floor(h / 256) % 256, h % 256 } end
local function pack(c)
  local q = function(v) return max(0, min(255, floor(v + 0.5))) end
  return q(c[1]) * 65536 + q(c[2]) * 256 + q(c[3])
end
local function mix(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end

local function mode_color()
  local sl = package.loaded["sparkle.statusline"]
  local cols = sl and sl.mode_colors or {}
  return rgb(tonumber((cols.normal or "#46e0ff"):sub(2), 16))
end

local function hl_of(name)
  local ok, hl = pcall(api.nvim_get_hl, 0, { name = name, link = false })
  hl = ok and hl or {}
  hl.default = nil
  return hl
end

-- the group a window really uses for `name` (its 'winhighlight' mapping, or the global one)
local function mapped(win, name)
  return (vim.wo[win].winhighlight or ""):match("%f[%w]" .. name .. ":([%w_]+)") or name
end

local function with_map(whl, name, group)
  local pat = "%f[%w]" .. name .. ":[%w_]+"
  if whl:find(pat) then return (whl:gsub(pat, name .. ":" .. group)) end
  return whl == "" and (name .. ":" .. group) or (whl .. "," .. name .. ":" .. group)
end

local function set_whl(win, s)
  pcall(api.nvim_set_option_value, "winhighlight", s, { win = win, scope = "local" })
end

-- the base definitions are read once when the flash starts: while it runs, reading "Normal" in
-- that window would return the tinted group
local function base(win)
  local normal, eob = hl_of(mapped(win, "Normal")), hl_of(mapped(win, "EndOfBuffer"))
  local bg = normal.bg or hl_of("Normal").bg
  bg = bg and rgb(bg) or (vim.o.background == "light" and rgb(0xf4f0d9) or rgb(0x1e2326))
  return normal, eob, bg
end

local function tinted(f, kind, k)
  local name = ("SparkleFocus%s%d_%d"):format(kind, k, f.id)
  local def = vim.deepcopy(kind == "N" and f.normal or f.eob)
  local own = def.bg and rgb(def.bg) or f.bg
  local s = M.config.strength[style.level] or M.config.strength[2]
  def.bg = pack(mix(own, f.tint, s * k / FL))
  api.nvim_set_hl(0, name, def)
  return name
end

-- sparkle.stars' filler floats sitting on top of `win` (below the end of its buffer)
local function fillers(win)
  local out = {}
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local c = api.nvim_win_get_config(w)
    if c.relative == "win" and c.win == win and c.zindex == 1 and c.focusable == false then out[#out + 1] = w end
  end
  return out
end

-- 'winhighlight' without any mapping to our tinted groups
local function clean(whl)
  local out = {}
  for _, item in ipairs(vim.split(whl or "", ",", { plain = true, trimempty = true })) do
    if not item:find(":SparkleFocus", 1, true) then out[#out + 1] = item end
  end
  return table.concat(out, ",")
end

-- what a filler float of a window with 'winhighlight' `whl` normally uses (sparkle.stars builds it
-- from the window's Normal mapping)
local function filler_whl(whl)
  local nh = whl:match("%f[%w]Normal:([%w_]+)") or "Normal"
  return ("Normal:%s,NormalFloat:%s,EndOfBuffer:%s"):format(nh, nh, nh)
end

local function finish(win)
  local f = flashes[win]
  flashes[win] = nil
  if not f or not api.nvim_win_is_valid(win) then return end
  set_whl(win, f.winhl)
  -- every filler on it now, including ones sparkle.stars (re)created during the flash: those
  -- copied the tinted mapping from the window and would otherwise keep it
  for _, w in ipairs(fillers(win)) do set_whl(w, filler_whl(f.winhl)) end
end

local function tick()
  local t = now()
  for win, f in pairs(flashes) do
    if not api.nvim_win_is_valid(win) then
      flashes[win] = nil
    else
      local p = (t - f.t0) / M.config.duration
      local k = floor((1 - p) * (1 - p) * FL + 0.5) -- ease out
      if p >= 1 or k <= 0 then
        finish(win)
      elseif k ~= f.k then
        f.k = k
        local n, e = tinted(f, "N", k), tinted(f, "E", k)
        set_whl(win, with_map(with_map(f.winhl, "Normal", n), "EndOfBuffer", e))
        local fw = ("Normal:%s,NormalFloat:%s,EndOfBuffer:%s"):format(n, n, n)
        for _, w in ipairs(fillers(win)) do set_whl(w, fw) end
      end
    end
  end
  if wave then
    if not api.nvim_win_is_valid(wave.win) or t - wave.t0 > M.config.wave_duration then
      local w = wave.win
      wave = nil
      if api.nvim_win_is_valid(w) then pcall(api.nvim__redraw, { win = w, valid = false }) end
    elseif not style.in_cmdline() then
      pcall(api.nvim__redraw, { win = wave.win, valid = false })
      for _, w in ipairs(fillers(wave.win)) do pcall(api.nvim__redraw, { win = w, valid = false }) end
    end
  end
  if next(flashes) == nil and not wave and timer then timer:stop() end
end

---------------------------------------------------------------- glint
local function define_wave(f)
  local s = M.config.wave[style.level] or M.config.wave[2]
  local white = { 255, 255, 255 }
  for k = 1, WL do
    local t = k / WL
    -- towards white in the core: a glint rather than a coloured bar
    local col = mix(f.tint, white, max(0, t - 0.55) * 1.4)
    api.nvim_set_hl(0, "SparkleFocusWave" .. k, { bg = pack(mix(f.bg, col, s * t)) })
  end
end

-- glint level for a screen row of the pane
local function wave_level(srow)
  local p = (now() - wave.t0) / M.config.wave_duration
  p = 1 - (1 - p) * (1 - p) * 0.6 - 0.4 * (1 - p) -- quick start, slightly eased
  local h = M.config.wave_half
  local c = -h + p * (wave.height + 2 * h)
  return floor(max(0, 1 - math.abs(srow - c) / h) * WL + 0.5)
end

local view = {} -- [win] = { rows = { [buffer row] = screen row } }

local function on_win(_, win, _buf, top, bot)
  if not wave then return false end
  if win == wave.win then
    -- screen row of each buffer row (wrapped lines and folds taken into account)
    local rows, y = {}, 0
    for r = top, bot do
      rows[r] = y
      local ok, th = pcall(api.nvim_win_text_height, win, { start_row = r, end_row = r })
      y = y + ((ok and th.all) or 1)
    end
    view[win] = { rows = rows }
    return true
  end
  local c = api.nvim_win_get_config(win)
  if c.relative == "win" and c.win == wave.win and c.zindex == 1 then
    view[win] = { offset = c.row or 0 }
    return true
  end
  return false
end

local function on_line(_, win, buf, row)
  local v = view[win]
  if not v or not wave then return end
  local srow = v.rows and v.rows[row] or (v.offset and (v.offset + row))
  if not srow then return end
  local k = wave_level(srow)
  if k <= 0 then return end
  -- (an ephemeral line_hl_group is ignored; a whole-line range with hl_eol does the same)
  api.nvim_buf_set_extmark(buf, ns, row, 0, {
    end_row = row + 1, end_col = 0, hl_group = "SparkleFocusWave" .. min(WL, k), hl_eol = true,
    ephemeral = true, priority = 300,
  })
end

local next_id = 0
function M.flash(win)
  if not active or style.in_cmdline() then return end
  if not api.nvim_win_is_valid(win) or api.nvim_win_get_config(win).relative ~= "" then return end
  if vim.wo[win].diff then return end
  finish(win)
  -- never take a tinted mapping for the original (whatever left it there)
  local whl = vim.wo[win].winhighlight or ""
  if whl:find(":SparkleFocus", 1, true) then set_whl(win, clean(whl)) end
  next_id = next_id % 4 + 1 -- a few sets of groups are enough (one per window flashing at once)
  local normal, eob, bg = base(win)
  local f = { id = next_id, t0 = now(), winhl = vim.wo[win].winhighlight or "",
    normal = normal, eob = eob, bg = bg, tint = mode_color() }
  flashes[win] = f
  define_wave(f)
  wave = { win = win, t0 = now(), height = api.nvim_win_get_height(win) }
  if not timer then timer = uv.new_timer() end
  if not timer:is_active() then timer:start(0, floor(1000 / M.config.fps), vim.schedule_wrap(tick)) end
end

function M.set_active(on)
  active = on
  if not on then
    if timer then timer:stop() end
    for w in pairs(flashes) do finish(w) end
    wave = nil
  end
end

function M.setup()
  active = true
  api.nvim_set_decoration_provider(ns, { on_win = on_win, on_line = on_line })
  local grp = api.nvim_create_augroup("SparkleFocusFx", { clear = true })
  api.nvim_create_autocmd("WinLeave", { group = grp, callback = function()
    from_float = api.nvim_win_get_config(0).relative ~= ""
  end })
  api.nvim_create_autocmd("WinEnter", { group = grp, callback = function()
    local win = api.nvim_get_current_win()
    -- coming back from Telescope, a notification, ... is not a move between panes
    if from_float then from_float = false; return end
    vim.schedule(function()
      if api.nvim_get_current_win() == win then M.flash(win) end
    end)
  end })
  api.nvim_create_autocmd("WinClosed", { group = grp, callback = function(ev)
    local w = tonumber(ev.match)
    if w then flashes[w] = nil end
  end })
end

return M
