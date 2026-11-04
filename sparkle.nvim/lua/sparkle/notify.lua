-- sparkle.notify: vim.notify replacement. Arcade-style panels stacked in the top right corner.
-- calm style: plain bordered floats in the colorscheme's colours, no animation.
local overlay = require("sparkle.overlay")
local C = require("sparkle.canvas")
local api = vim.api
local floor, max, min, sin = math.floor, math.max, math.min, math.sin
local pal = overlay.pal
local L = vim.log.levels

local M = {}

M.config = {
  max_width = 56,
  timeout = 4000, -- ms (errors stay twice as long)
  max_lines = 10,
  min_level = L.INFO, -- quieter levels only go to :SparkleMessages
}

M.history = {}

local styles = {
  [L.TRACE] = { name = "TRACE", icon = "·", a = pal.dim, b = pal.faint },
  [L.DEBUG] = { name = "DEBUG", icon = "⚙", a = pal.dim, b = pal.purple },
  [L.INFO] = { name = "INFO", icon = "✦", a = pal.cyan, b = pal.purple },
  [L.WARN] = { name = "WARN", icon = "▲", a = pal.gold, b = C.hex(0xff8a3d) },
  [L.ERROR] = { name = "ERROR", icon = "✖", a = pal.red, b = pal.magenta },
}

local stack = {} -- visible toasts, top first
local next_id = 0
local calm = false

local calm_hl = {
  [L.TRACE] = "Comment", [L.DEBUG] = "Comment", [L.INFO] = "DiagnosticInfo",
  [L.WARN] = "DiagnosticWarn", [L.ERROR] = "DiagnosticError",
}

local function layout()
  local row = (vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #api.nvim_list_tabpages() > 1)) and 1 or 0
  for _, n in ipairs(stack) do
    n.target_row = row
    if not n.row then n.row = row end
    row = row + n.height
  end
  if calm then
    for _, n in ipairs(stack) do
      n.row = n.target_row
      if n.ov then n.ov:move({ relative = "editor", row = n.target_row, col = vim.o.columns - 1 }) end
    end
  end
end

local function close(n)
  for i, m in ipairs(stack) do
    if m == n then
      table.remove(stack, i)
      break
    end
  end
  if n.ov then n.ov:close() end
  layout()
end

local function draw(n)
  return function(c, t, dt, ov)
    local st = n.style
    -- life: appear, stay, fade
    local age = ((vim.uv or vim.loop).hrtime() / 1e9) - n.born
    local life = n.timeout / 1000
    if n.dead or age > life + 0.4 then
      vim.schedule(function() close(n) end)
      return false
    end

    -- glide to the stacking position
    if n.row ~= n.target_row then
      local d = n.target_row - n.row
      n.row = math.abs(d) < 0.3 and n.target_row or n.row + d * min(1, dt * 14)
      ov:move({ row = floor(n.row + 0.5), relative = "editor", col = vim.o.columns - 1 })
    end

    overlay.backdrop(c, t, pal.panel, 0.025)
    -- tinted inner glow along the left edge
    for y = 0, c.ph - 1 do
      c:padd(1, y, st.a, 0.35)
      c:padd(2, y, st.a, 0.12)
    end
    c:clear_text()

    -- materialise: a bright scanline wipes in from the right
    local wipe = C.clamp(t / 0.28, 0, 1)
    local edge = floor((1 - wipe) * c.cols)

    overlay.frame(c, t, st.a, st.b, { speed = 0.5 })
    -- title chip on the top border
    local title = " " .. st.icon .. " " .. (n.title ~= "" and (st.name .. " · " .. n.title) or st.name) .. " "
    title = C.truncate(title, c.cols - 4)
    c:put_gradient(2, 0, title, C.add(st.a, pal.white, 0.3), st.b, { bold = true })
    -- message
    for i, line in ipairs(n.lines) do
      c:put(2, i, line, pal.text)
    end
    -- timer bar along the bottom border
    local left = C.clamp(1 - age / life, 0, 1)
    local bw = floor((c.cols - 4) * left + 0.5)
    for x = 2, 1 + bw do
      c:put(x, c.rows - 1, "━", C.lerp(st.a, st.b, (x - 2) / max(1, c.cols - 4)))
    end

    if n.parts then overlay.particles(c, n.parts, dt) end
    if wipe < 1 then
      for y = 0, c.rows - 1 do
        for x = 0, edge - 1 do
          c.text[y * c.cols + x + 1] = { ch = " ", fg = pal.panel, bg = { 0, 0, 0 }, w = 1 }
        end
      end
      c:fill_rect(edge, 0, 2, c.ph, pal.white, 0.9)
      c:glow(edge, c.ph / 2, c.ph, st.a, 0.6)
    elseif not n.parts then
      n.parts = {}
      overlay.burst(n.parts, c.pw - 3, 1, 14, { st.a, st.b, pal.white }, 0.9)
    end

    -- fade out
    if age > life then ov:set_blend((age - life) / 0.4 * 100) end
    -- calm down after the intro
    if t > 1.2 and ov.fps ~= 12 then
      ov.fps = 12
      if ov.timer then ov.timer:set_repeat(floor(1000 / 12)) end
    end
    return true
  end
end

-- a static float with the same small interface as a sparkle.overlay (move / close)
local function open_calm(n, width)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local lines = {}
  for i, l in ipairs(n.lines) do lines[i] = " " .. l end
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local hl = calm_hl[n.level] or "DiagnosticInfo"
  local st = n.style
  local title = " " .. st.icon .. " " .. (n.title ~= "" and (st.name .. " · " .. n.title) or st.name) .. " "
  local ok, win = pcall(overlay.open_win, buf, false, {
    relative = "editor", anchor = "NE", row = n.target_row, col = vim.o.columns - 1,
    width = max(1, width - 2), height = #lines, zindex = 150, style = "minimal", focusable = false,
    noautocmd = true, border = "rounded", title = C.truncate(title, max(1, width - 4)), title_pos = "left",
  })
  if not ok then
    pcall(api.nvim_buf_delete, buf, { force = true })
    return nil
  end
  vim.wo[win].winhighlight = ("Normal:NormalFloat,FloatBorder:%s,FloatTitle:%s"):format(hl, hl)
  vim.wo[win].wrap = false
  local o = { win = win }
  function o:move(cfg)
    if api.nvim_win_is_valid(self.win) then pcall(overlay.win_set_config, self.win, cfg) end
  end
  function o:close()
    if self.closed then return end
    self.closed = true
    vim.schedule(function()
      pcall(api.nvim_win_close, win, true)
      pcall(api.nvim_buf_delete, buf, { force = true })
    end)
  end
  vim.defer_fn(function() if not n.dead then n.dead = true; close(n) end end, n.timeout)
  return o
end

local function to_lines(msg, width)
  local lines = C.wrap(msg, width)
  while #lines > 1 and lines[#lines] == "" do lines[#lines] = nil end
  if #lines > M.config.max_lines then
    local n = #lines - M.config.max_lines + 1
    lines = vim.list_slice(lines, 1, M.config.max_lines - 1)
    lines[#lines + 1] = string.format("… (+%d lines, :SparkleMessages)", n)
  end
  return lines
end

local function show(msg, level, opts)
  if #api.nvim_list_uis() == 0 then return end
  local st = styles[level] or styles[L.INFO]
  local width = min(M.config.max_width, max(24, floor(vim.o.columns * 0.4)))
  local inner = width - 4
  local title = opts.title and tostring(opts.title) or ""
  local lines = to_lines(msg, inner)
  local need = 0
  for _, l in ipairs(lines) do need = max(need, C.width(l)) end
  width = max(min(width, need + 4), C.width(title) + #st.name + 12, 24)

  -- replace an existing notification (nvim-notify style `replace = id`)
  local rep = opts.replace
  if type(rep) == "table" then rep = rep.id end
  for _, m in ipairs(stack) do
    if rep and m.id == rep then
      m.dead = true
      close(m)
      break
    end
  end

  next_id = next_id + 1
  local timeout = opts.timeout
  if timeout == false then timeout = 24 * 3600 * 1000 end
  timeout = timeout or (level >= L.ERROR and M.config.timeout * 2 or M.config.timeout)
  lines = to_lines(msg, width - 4)
  local n = {
    id = next_id, style = st, title = title, lines = lines, level = level,
    height = #lines + 2, born = (vim.uv or vim.loop).hrtime() / 1e9, timeout = timeout,
  }
  table.insert(stack, n)
  layout()
  -- drop old ones that no longer fit
  while #stack > 1 and (stack[#stack].target_row + stack[#stack].height) > vim.o.lines - 3 do
    close(stack[1])
  end
  if calm then
    n.ov = open_calm(n, width)
  else
    n.ov = overlay.open({
      anchor = "NE", row = n.target_row, col = vim.o.columns - 1, width = width, height = n.height,
      zindex = 150, fps = 30,
    }, draw(n))
  end
  if not n.ov then close(n) end
  return { id = n.id }
end

function M.notify(msg, level, opts)
  msg = type(msg) == "string" and msg or vim.inspect(msg)
  level = level or L.INFO
  if type(level) == "string" then level = L[level:upper()] or L.INFO end
  opts = opts or {}
  table.insert(M.history, { time = os.time(), msg = msg, level = level, title = opts.title })
  if #M.history > 300 then table.remove(M.history, 1) end
  if level < M.config.min_level then return end
  if vim.in_fast_event() then
    vim.schedule(function() show(msg, level, opts) end)
    return
  end
  local ok, res = pcall(show, msg, level, opts)
  if ok then return res end
end

function M.dismiss()
  for i = #stack, 1, -1 do
    stack[i].dead = true
    close(stack[i])
  end
end

function M.open_history()
  local lines = {}
  for _, h in ipairs(M.history) do
    local st = styles[h.level] or styles[L.INFO]
    local head = string.format("%s %s %s%s", os.date("%H:%M:%S", h.time), st.icon, st.name,
      h.title and (" · " .. tostring(h.title)) or "")
    lines[#lines + 1] = head
    for l in (h.msg .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = "    " .. l end
  end
  vim.cmd("botright new")
  local buf = api.nvim_get_current_buf()
  vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = "nofile", "wipe", false
  api.nvim_buf_set_name(buf, "sparkle://messages")
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true })
  vim.cmd("normal! G")
end

function M.set_calm(c)
  if c == calm then return end
  calm = c
  M.dismiss() -- the visible ones were drawn in the other style
end

function M.setup()
  M.orig = M.orig or vim.notify
  vim.notify = M.notify
  api.nvim_create_user_command("SparkleMessages", M.open_history, { desc = "sparkle notification history" })
  api.nvim_create_user_command("SparkleDismiss", M.dismiss, { desc = "dismiss sparkle notifications" })
  api.nvim_create_autocmd("VimResized", {
    group = api.nvim_create_augroup("SparkleNotify", { clear = true }),
    callback = function()
      layout()
      for _, n in ipairs(stack) do
        if n.ov then n.ov:move({ relative = "editor", row = n.target_row, col = vim.o.columns - 1 }) end
      end
    end,
  })
end

return M
