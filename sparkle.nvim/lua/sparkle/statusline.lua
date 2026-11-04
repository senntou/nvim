-- sparkle.statusline: lualine theme + a shimmering mode badge + a gradient progress bar.
--
-- lua/plugins/lualine.lua uses `opts = function() return require("sparkle.statusline").lualine_opts() end`.
-- calm style: lualine's "auto" theme (follows the colorscheme), a static badge and a plain progress bar.
local api, uv = vim.api, vim.uv or vim.loop
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local M = {}

M.config = {
  sweep_every = 4.5, -- seconds between idle shimmers
  sweep_speed = 28, -- characters per second
  fps = 20,
  idle_after = 30, -- stop animating after this many seconds without input
}

local P = {
  navy = "#0a0f24",
  panel = "#0c1230",
  b = "#1a2250",
  text = "#c8d4f4",
  dim = "#6a7499",
  faint = "#3a4366",
  white = "#ffffff",
}

M.mode_colors = {
  normal = "#46e0ff",
  insert = "#ff4fd8",
  visual = "#ffd34d",
  replace = "#ff5470",
  command = "#5cffa8",
  terminal = "#9a5cff",
}

local LEVELS = 8
local calm = false

local function rgb(h)
  local n = tonumber(h:sub(2), 16)
  return { floor(n / 65536) % 256, floor(n / 256) % 256, n % 256 }
end
local function to_hex(c)
  return string.format("#%02x%02x%02x", floor(c[1] + 0.5), floor(c[2] + 0.5), floor(c[3] + 0.5))
end
local function mix(a, b, t)
  local x, y = rgb(a), rgb(b)
  return to_hex({ x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t, x[3] + (y[3] - x[3]) * t })
end

---------------------------------------------------------------- theme
function M.theme()
  local t = {}
  for name, col in pairs(M.mode_colors) do
    t[name] = {
      a = { bg = col, fg = P.navy, gui = "bold" },
      b = { bg = P.b, fg = col },
      c = { bg = P.panel, fg = P.text },
    }
  end
  t.inactive = {
    a = { bg = P.panel, fg = P.dim, gui = "bold" },
    b = { bg = P.panel, fg = P.dim },
    c = { bg = P.panel, fg = P.faint },
  }
  return t
end

---------------------------------------------------------------- highlights
local function define_hl()
  for name, col in pairs(M.mode_colors) do
    for k = 0, LEVELS - 1 do
      local s = k / (LEVELS - 1)
      api.nvim_set_hl(0, ("SparkleMode_%s_%d"):format(name, k), {
        bg = mix(col, P.white, s * 0.8), fg = mix(P.navy, "#3a1060", s), bold = true,
      })
    end
    api.nvim_set_hl(0, ("SparkleModeStar_%s"):format(name), { bg = col, fg = P.white, bold = true })
  end
  for k = 0, 9 do
    api.nvim_set_hl(0, ("SparkleProg%d"):format(k), { bg = P.b, fg = mix("#46e0ff", "#ff4fd8", k / 9) })
  end
  api.nvim_set_hl(0, "SparkleProgHead", { bg = P.b, fg = P.white, bold = true })
  api.nvim_set_hl(0, "SparkleProgEmpty", { bg = P.b, fg = P.faint })
end

---------------------------------------------------------------- mode badge
local function mode_key()
  local m = api.nvim_get_mode().mode
  local c = m:sub(1, 1)
  if c == "i" then return "insert" end
  if c == "v" or c == "V" or c == "\22" or c == "s" or c == "S" or c == "\19" then return "visual" end
  if c == "R" then return "replace" end
  if c == "c" then return "command" end
  if c == "t" then return "terminal" end
  return "normal"
end

local sweep_t0 = -100
local stars = { "✦", "✧", "⋆", "✧" }

local function now() return uv.hrtime() / 1e9 end

function M.mode()
  local ok, lm = pcall(require, "lualine.utils.mode")
  local name = ok and lm.get_mode() or mode_key():upper()
  if calm then return "✦ " .. name .. " ✦" end
  local key = mode_key()
  local t = now()
  local text = name
  local n = vim.fn.strchars(text)
  local u = (t - sweep_t0) * M.config.sweep_speed - 3
  local star = stars[floor(t * 2.5) % #stars + 1]
  local star_hl = "%#SparkleModeStar_" .. key .. "#"
  local out = { star_hl, star, " " }
  for i = 0, n - 1 do
    local ch = vim.fn.strcharpart(text, i, 1)
    local lv = max(0, 1 - abs(i - u) / 2.5)
    local k = floor(lv * (LEVELS - 1) + 0.5)
    out[#out + 1] = ("%%#SparkleMode_%s_%d#%s"):format(key, k, ch)
  end
  out[#out + 1] = star_hl
  out[#out + 1] = " " .. star
  return table.concat(out)
end

---------------------------------------------------------------- progress bar
function M.progress()
  local cur, total = api.nvim_win_get_cursor(0)[1], api.nvim_buf_line_count(0)
  local W = 10
  local pos = total <= 1 and 0 or floor((cur - 1) / (total - 1) * (W - 1) + 0.5)
  if calm then -- section colours only
    return ("━"):rep(pos) .. "◆" .. ("─"):rep(W - 1 - pos)
  end
  local out = {}
  for i = 0, W - 1 do
    if i < pos then
      out[#out + 1] = ("%%#SparkleProg%d#━"):format(floor(i / (W - 1) * 9))
    elseif i == pos then
      out[#out + 1] = "%#SparkleProgHead#◆"
    else
      out[#out + 1] = "%#SparkleProgEmpty#─"
    end
  end
  return table.concat(out)
end

---------------------------------------------------------------- animation driver
local timer, last_str, last_input = nil, nil, now()

local function refresh()
  local lualine = package.loaded["lualine"]
  if lualine then pcall(lualine.refresh, { scope = "window", place = { "statusline" }, trigger = "timer" }) end
end

local function tick()
  if not package.loaded["lualine"] or now() - last_input > M.config.idle_after then
    if timer then timer:stop() end
    return
  end
  if now() - sweep_t0 > M.config.sweep_every then sweep_t0 = now() end
  local s = M.mode()
  if s ~= last_str then
    last_str = s
    refresh()
  end
end

local function start()
  if calm then return end
  if not timer then timer = uv.new_timer() end
  if timer:is_active() then return end
  timer:start(0, floor(1000 / M.config.fps), vim.schedule_wrap(tick))
end

function M.lualine_opts()
  local sp = package.loaded["sparkle"]
  if not (sp and sp.features.statusline) then return {} end -- feature off: plain lualine
  define_hl()
  return {
    options = {
      theme = calm and "auto" or M.theme(),
      component_separators = { left = "", right = "" },
      section_separators = { left = "", right = "" },
    },
    sections = {
      lualine_a = { { M.mode, padding = 1 } },
      lualine_b = { "branch", "diff", "diagnostics" },
      lualine_c = { { "filename", path = 1 } },
      lualine_x = { "encoding", "fileformat", "filetype" },
      lualine_y = { { M.progress, padding = 1 }, "progress" },
      lualine_z = { "location" },
    },
  }
end

function M.set_calm(c)
  calm = c
  if calm then
    if timer then timer:stop() end
  else
    last_input = now()
    start()
  end
  local lualine = package.loaded["lualine"]
  if lualine then pcall(lualine.setup, M.lualine_opts()) end
end

function M.setup()
  define_hl()
  local grp = api.nvim_create_augroup("SparkleStatusline", { clear = true })
  api.nvim_create_autocmd("ColorScheme", { group = grp, callback = define_hl })
  api.nvim_create_autocmd("ModeChanged", { group = grp, callback = function()
    sweep_t0 = now()
    last_input = now()
    start()
  end })
  api.nvim_create_autocmd("FocusLost", { group = grp, callback = function() if timer then timer:stop() end end })
  api.nvim_create_autocmd("FocusGained", { group = grp, callback = function() last_input = now(); start() end })
  vim.on_key(function()
    last_input = now()
    if timer and not timer:is_active() then vim.schedule(start) end
  end, api.nvim_create_namespace("SparkleStatuslineKeys"))
  start()
end

return M
