-- sparkle.tree: nvim-tree in sparkle colours, plus a few effects.
--
--   * transparent.nvim: while it is on, the tree background is cleared too (colorschemes such as
--     everforest give NvimTreeNormal its own background, which transparent.nvim leaves alone)
--   * sparkle style: neon palette (folders, git status, indent guides, ...) on the dark navy panel
--     (or no background when transparent), the cursor line breathes in the colour of the mode,
--     a light sweep runs over the entry you open, and the star field is drawn in the tree as well
--   * calm style: the colorscheme's own nvim-tree colours (only the transparency is applied)
--
-- nvim-tree defines its groups with `:hi def`, so whatever is set here wins over its defaults.
local api, uv = vim.api, vim.uv or vim.loop
local style = require("sparkle.style")
local floor, max, abs, sin = math.floor, math.max, math.abs, math.sin

local M = {}

M.config = {
  fps = 10, -- cursor line breathing
  sweep_fps = 40,
  sweep_speed = 70, -- characters per second
  idle_after = 30,
  stars = true, -- let sparkle.stars draw in the tree
}

-- per flashiness level: cursor line breathing amount (0 = static), sweep strength
M.levels = {
  { breath = 0, sweep = 0.35 },
  { breath = 0.16, sweep = 0.5 },
  { breath = 0.28, sweep = 0.65 },
}
local function L() return M.levels[style.level] or M.levels[2] end

local P = {
  bg = "#0a0f24",
  cursor = "#1a2250",
  text = "#c8d4f4",
  dim = "#6a7499",
  faint = "#2a3358",
  white = "#ffffff",
  cyan = "#46e0ff",
  cyan2 = "#9ff0ff",
  pink = "#ff4fd8",
  purple = "#9a5cff",
  lilac = "#c9b6ff",
  yellow = "#ffd34d",
  green = "#5cffa8",
  red = "#ff5470",
  orange = "#ff9f5c",
  rose = "#ffb8ec",
}

-- groups whose background follows the panel / transparency
local BG_GROUPS = { "NvimTreeNormal", "NvimTreeNormalNC", "NvimTreeEndOfBuffer", "NvimTreeSignColumn",
  "NvimTreeLineNr" }

local function sparkle_groups(bg)
  local G = {
    NvimTreeNormal = { fg = P.text, bg = bg },
    NvimTreeNormalNC = { fg = P.text, bg = bg },
    NvimTreeEndOfBuffer = { fg = bg or P.bg, bg = bg },
    NvimTreeSignColumn = { bg = bg },
    NvimTreeLineNr = { fg = P.faint, bg = bg },
    NvimTreeCursorLine = { bg = P.cursor },
    NvimTreeCursorLineNr = { fg = P.cyan, bg = P.cursor, bold = true },

    NvimTreeRootFolder = { fg = P.pink, bold = true },
    NvimTreeFolderName = { fg = P.cyan },
    NvimTreeOpenedFolderName = { fg = P.cyan2, bold = true },
    NvimTreeEmptyFolderName = { fg = P.dim },
    NvimTreeSymlinkFolderName = { fg = P.lilac },
    NvimTreeFolderIcon = { fg = P.purple },
    NvimTreeOpenedFolderIcon = { fg = P.lilac },
    NvimTreeClosedFolderIcon = { fg = P.purple },
    NvimTreeFolderArrowOpen = { fg = P.cyan },
    NvimTreeFolderArrowClosed = { fg = P.dim },
    NvimTreeIndentMarker = { fg = P.faint },

    NvimTreeOpenedHL = { fg = P.white, bold = true },
    NvimTreeSpecialFile = { fg = P.yellow, bold = true },
    NvimTreeExecFile = { fg = P.green },
    NvimTreeImageFile = { fg = P.rose },
    NvimTreeSymlink = { fg = P.lilac, underline = true },
    NvimTreeModifiedIcon = { fg = P.pink },
    NvimTreeBookmarkIcon = { fg = P.yellow },
    NvimTreeBookmarkHL = { fg = P.yellow, italic = true },
    NvimTreeCopiedHL = { fg = P.green, italic = true },
    NvimTreeCutHL = { fg = P.red, italic = true },
    NvimTreeHiddenIcon = { fg = P.dim },
    NvimTreeHiddenDisplay = { fg = P.faint, italic = true },
    NvimTreeWindowPicker = { fg = P.bg, bg = P.pink, bold = true },
    NvimTreeLiveFilterPrefix = { fg = P.pink, bold = true },
    NvimTreeLiveFilterValue = { fg = P.white, bold = true },

    NvimTreeGitDirtyIcon = { fg = P.yellow },
    NvimTreeGitNewIcon = { fg = P.green },
    NvimTreeGitStagedIcon = { fg = P.cyan },
    NvimTreeGitDeletedIcon = { fg = P.red },
    NvimTreeGitRenamedIcon = { fg = P.lilac },
    NvimTreeGitMergeIcon = { fg = P.orange },
    NvimTreeGitIgnoredIcon = { fg = P.faint },
    NvimTreeGitFileIgnoredHL = { fg = P.dim },
    NvimTreeGitFolderIgnoredHL = { fg = P.dim },

    NvimTreeDiagnosticErrorIcon = { fg = P.red },
    NvimTreeDiagnosticWarnIcon = { fg = P.yellow },
    NvimTreeDiagnosticInfoIcon = { fg = P.cyan },
    NvimTreeDiagnosticHintIcon = { fg = P.lilac },
  }
  return G
end

local calm = false
local orig = {} -- [group] = definition from the colorscheme (restored in calm style)
local touched = {} -- groups this module has set
local cursor_base -- cursor line colour without the breathing
local last_breath
local timer, sweep_timer
local last_input = 0
local ns = api.nvim_create_namespace("SparkleTree")
local sweep -- { buf, row, chars = { {s, e}, ... }, t0 }
local leave -- { buf, row, t } when the cursor just left a tree window

local function now() return uv.hrtime() / 1e9 end
local function transparent() return vim.g.transparent_enabled == true end

local function rgb(h)
  local n = type(h) == "number" and h or tonumber(h:sub(2), 16)
  return { floor(n / 65536) % 256, floor(n / 256) % 256, n % 256 }
end
local function hex(c) return string.format("#%02x%02x%02x", floor(c[1] + 0.5), floor(c[2] + 0.5), floor(c[3] + 0.5)) end
local function mix(a, b, t)
  local x, y = rgb(a), rgb(b)
  return hex({ x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t, x[3] + (y[3] - x[3]) * t })
end

local function mode_color()
  local sl = package.loaded["sparkle.statusline"]
  local cols = sl and sl.mode_colors or { normal = P.cyan }
  local m = api.nvim_get_mode().mode:sub(1, 1)
  local key = (m == "i" and "insert") or ((m == "v" or m == "V" or m == "\22") and "visual")
    or (m == "R" and "replace") or (m == "c" and "command") or (m == "t" and "terminal") or "normal"
  return cols[key] or cols.normal
end

---------------------------------------------------------------- highlights
-- remember the colorscheme's definitions (right after :colorscheme, before anything is applied)
local function capture()
  orig = {}
  local names = vim.tbl_keys(sparkle_groups(nil))
  for _, g in ipairs(names) do
    local ok, hl = pcall(api.nvim_get_hl, 0, { name = g, link = true })
    if ok and hl and not vim.tbl_isempty(hl) then orig[g] = hl end
  end
end

local function set(g, def)
  touched[g] = true
  api.nvim_set_hl(0, g, def)
end

local function apply()
  if calm then
    -- back to the colorscheme (and nvim-tree's own defaults for what it does not define)
    for g in pairs(touched) do api.nvim_set_hl(0, g, orig[g] or {}) end
    touched = {}
    local ok, app = pcall(require, "nvim-tree.appearance")
    if ok and package.loaded["nvim-tree"] then pcall(app.highlight) end
    if transparent() then
      for _, g in ipairs(BG_GROUPS) do
        local ok2, hl = pcall(api.nvim_get_hl, 0, { name = g, link = false })
        if ok2 and hl and hl.bg then
          hl.bg = nil
          set(g, hl)
        end
      end
    end
    cursor_base = nil
    return
  end
  for g, def in pairs(sparkle_groups(not transparent() and P.bg or nil)) do set(g, def) end
  cursor_base = P.cursor
  last_breath = nil
end

---------------------------------------------------------------- tree windows
local function is_tree(buf) return api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "NvimTree" end

local function tree_focused() return is_tree(api.nvim_get_current_buf()) end

---------------------------------------------------------------- cursor line breathing
local function breathe(force)
  if calm or not cursor_base then return end
  if not force and style.in_cmdline() then return end
  local amt = L().breath
  local col = cursor_base
  if amt > 0 and tree_focused() then
    local b = 0.5 + 0.5 * sin(now() * 6.283 / 3.2)
    col = mix(cursor_base, mode_color(), amt * (0.35 + 0.65 * b))
  end
  local key = col .. mode_color()
  if key == last_breath then return end
  last_breath = key
  set("NvimTreeCursorLine", { bg = col })
  set("NvimTreeCursorLineNr", { fg = mode_color(), bg = col, bold = true })
end

local function stop() if timer then timer:stop() end end

local function tick()
  if calm or not tree_focused() or now() - last_input > M.config.idle_after or L().breath <= 0 then
    stop()
    breathe(true) -- settle on the resting colour
    return
  end
  breathe()
end

local function start()
  if calm or L().breath <= 0 or not tree_focused() then return end
  if not timer then timer = uv.new_timer() end
  if timer:is_active() then return end
  timer:start(0, floor(1000 / M.config.fps), vim.schedule_wrap(tick))
end

---------------------------------------------------------------- open sweep
local SW = 8
local function define_sweep()
  for k = 0, SW - 1 do
    local s = k / (SW - 1)
    api.nvim_set_hl(0, "SparkleTreeSweep" .. k, {
      bg = mix(cursor_base or P.cursor, P.cyan, s * L().sweep), fg = mix(P.text, P.white, s), bold = k > 0,
    })
  end
end

local function sweep_stop()
  if sweep_timer then sweep_timer:stop() end
  if sweep and api.nvim_buf_is_valid(sweep.buf) then api.nvim_buf_clear_namespace(sweep.buf, ns, 0, -1) end
  sweep = nil
end

local function sweep_tick()
  if not sweep or not api.nvim_buf_is_valid(sweep.buf) then return sweep_stop() end
  local u = (now() - sweep.t0) * M.config.sweep_speed - 3
  local n = #sweep.chars
  if u > n + 4 then return sweep_stop() end
  api.nvim_buf_clear_namespace(sweep.buf, ns, 0, -1)
  for i, c in ipairs(sweep.chars) do
    local lv = max(0, 1 - abs(i - u) / 3.5)
    local k = floor(lv * (SW - 1) + 0.5)
    if k > 0 then
      pcall(api.nvim_buf_set_extmark, sweep.buf, ns, sweep.row, c[1],
        { end_col = c[2], hl_group = "SparkleTreeSweep" .. k, priority = 250 })
    end
  end
end

local function sweep_start(buf, row)
  if calm then return end
  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  if not line or line == "" then return end
  -- byte range of every character after the leading indent
  local chars, i = {}, line:find("%S") or 1
  local len = #line
  while i <= len do
    local n = vim.str_utf_end(line, i) + 1
    chars[#chars + 1] = { i - 1, i - 1 + n }
    i = i + n
  end
  if #chars == 0 then return end
  sweep_stop()
  define_sweep()
  sweep = { buf = buf, row = row, chars = chars, t0 = now() }
  if not sweep_timer then sweep_timer = uv.new_timer() end
  sweep_timer:start(0, floor(1000 / M.config.sweep_fps), vim.schedule_wrap(sweep_tick))
end

---------------------------------------------------------------- style
function M.set_calm(c)
  calm = c
  apply()
  if calm then
    stop()
    sweep_stop()
  else
    breathe(true)
    start()
  end
end

local function stars_in(buf)
  if M.config.stars then vim.b[buf].sparkle_stars = true end
end

function M.setup()
  capture()
  apply()
  last_input = now()

  local grp = api.nvim_create_augroup("SparkleTree", { clear = true })
  api.nvim_create_autocmd("ColorScheme", { group = grp, callback = function()
    touched = {}
    capture()
    -- :colorscheme cleared nvim-tree's default links; let it put them back first
    local ok, app = pcall(require, "nvim-tree.appearance")
    if ok and package.loaded["nvim-tree"] then pcall(app.highlight) end
    apply()
    breathe(true)
  end })
  -- transparent.nvim reruns :colorscheme on toggle; this also covers a plain :TransparentEnable
  api.nvim_create_autocmd("User", { group = grp, pattern = "TransparentClear", callback = function()
    vim.schedule(apply)
  end })
  api.nvim_create_autocmd("User", { group = grp, pattern = "SparkleLevel", callback = function()
    breathe(true)
    start()
  end })
  api.nvim_create_autocmd("FileType", { group = grp, pattern = "NvimTree", callback = function(ev)
    stars_in(ev.buf)
  end })
  api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, { group = grp, callback = function(ev)
    if is_tree(ev.buf) then
      stars_in(ev.buf)
      last_input = now()
      start()
      return
    end
    breathe(true)
  end })
  -- a file was opened from the tree: light up the entry it was opened from
  api.nvim_create_autocmd("BufWinEnter", { group = grp, callback = function(ev)
    if leave and now() - leave.t < 0.3 and not is_tree(ev.buf) and vim.bo[ev.buf].buflisted then
      local l = leave
      leave = nil
      vim.schedule(function() if api.nvim_buf_is_valid(l.buf) then sweep_start(l.buf, l.row) end end)
    end
  end })
  api.nvim_create_autocmd("WinLeave", { group = grp, callback = function(ev)
    if is_tree(ev.buf) then
      leave = { buf = ev.buf, row = api.nvim_win_get_cursor(0)[1] - 1, t = now() }
    end
  end })
  api.nvim_create_autocmd("ModeChanged", { group = grp, callback = function()
    if tree_focused() then vim.schedule(function() breathe(true) end) end
  end })
  api.nvim_create_autocmd("FocusLost", { group = grp, callback = stop })
  api.nvim_create_autocmd("FocusGained", { group = grp, callback = function() last_input = now(); start() end })
  vim.on_key(function()
    last_input = now()
    if timer and not timer:is_active() and not calm then vim.schedule(start) end
  end, api.nvim_create_namespace("SparkleTreeKeys"))
end

return M
