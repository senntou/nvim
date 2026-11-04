-- sparkle.cmdline: the command line, re-drawn as a floating panel in the middle of the screen.
--
-- Uses vim.ui_attach({ext_cmdline}) (modelled on Neovim 0.12's builtin vim._core.ui2): the text
-- lives in a normal floating window (so the real cursor, CJK input and syntax colouring just
-- work), sitting on top of an animated sparkle.canvas frame.
-- Messages are left alone (they still appear at the bottom).
-- calm style: no canvas frame; the text window gets a plain rounded border in the colorscheme's colours.
local overlay = require("sparkle.overlay")
local C = require("sparkle.canvas")
local api, fn = vim.api, vim.fn
local floor, max, min, sin = math.floor, math.max, math.min, math.sin
local pal = overlay.pal

local M = {}

M.config = {
  width = 64, -- minimum text width
  max_width = 0.8, -- fraction of the screen
  row = 0.30, -- vertical position (fraction of the screen)
  fps = 24,
}

local ns = api.nvim_create_namespace("sparkle.cmdline")
local calm = false
local S = {
  buf = -1, win = -1, ov = nil,
  level = 0, firstc = "", prompt = "", text = "", pos = 0, indent = 0,
  block = {}, -- previous lines of a cmdline block (:function ... etc.)
  prefix_len = 0, row = 0, -- cursor anchor
  redrawing = false,
  shown_at = 0,
}

local kinds = {
  [":"] = { label = "COMMAND", icon = "❯ ", a = pal.cyan, b = pal.purple },
  ["/"] = { label = "SEARCH ↓", icon = "/ ", a = pal.gold, b = pal.magenta },
  ["?"] = { label = "SEARCH ↑", icon = "? ", a = pal.gold, b = pal.magenta },
  ["="] = { label = "EXPRESSION", icon = "= ", a = pal.green, b = pal.cyan },
  [">"] = { label = "DEBUG", icon = "> ", a = pal.red, b = pal.gold },
  [""] = { label = "INPUT", icon = "", a = pal.magenta, b = pal.cyan },
}
local function kind()
  return kinds[S.firstc] or { label = "INPUT", icon = S.firstc ~= "" and (S.firstc .. " ") or "", a = pal.magenta, b = pal.cyan }
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
  overlay.backdrop(c, t, pal.panel, 0.05)
  -- inner area matches the text window background exactly
  c:fill_rect(1, 2, c.pw - 2, c.ph - 4, pal.panel, 1)
  c:clear_text()
  overlay.frame(c, t, k.a, k.b, { speed = 0.45 })
  local title = " ✦ " .. k.label .. (S.level > 1 and ("  LV" .. S.level) or "") .. " "
  c:put_gradient(3, 0, title, C.add(k.a, pal.white, 0.35), k.b, { bold = true })
  -- intro flash: a bright line sweeps across the frame once when the cmdline opens
  local age = t - S.shown_at
  if age < 0.35 then
    local x = age / 0.35 * (c.pw + 8) - 4
    for y = 0, c.ph - 1 do
      c:padd(x, y, pal.white, 0.6)
      c:padd(x - 1, y, k.a, 0.4)
    end
  end
  -- twinkles that hop between the corners
  local slot = floor(t / 0.9)
  local u = (t / 0.9) % 1
  local corners = { { 0, 0 }, { c.pw - 1, 0 }, { c.pw - 1, c.ph - 1 }, { 0, c.ph - 1 } }
  local cn = corners[slot % 4 + 1]
  overlay.twinkle(c, cn[1], cn[2], sin(u * math.pi) * 0.9, slot % 2 == 0 and k.a or pal.white)
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
    wo.winhighlight = (calm and "Normal:NormalFloat,FloatBorder:FloatBorder,FloatTitle:FloatTitle"
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
    S.ov = overlay.open(vim.tbl_extend("force", frame_cfg, { zindex = 240, fps = M.config.fps }), draw_frame)
    if S.ov then S.ov.redraw = flush_screen end
  else
    S.ov:move(frame_cfg)
    S.ov:start()
  end
end

local function hide_windows()
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

---------------------------------------------------------------- ui events
local H = {}

function H.cmdline_show(content, pos, firstc, prompt, indent, level, _hl_id)
  local text = {}
  for _, chunk in ipairs(content) do text[#text + 1] = chunk[2] end
  if S.level == 0 then S.shown_at = S.ov and S.ov.t0 and ((vim.uv or vim.loop).hrtime() / 1e9 - S.ov.t0) or 0 end
  S.text, S.pos, S.firstc, S.prompt, S.indent, S.level = table.concat(text), pos, firstc, prompt, indent, level
  render()
  place_cursor()
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
  api.nvim_set_hl(0, "SparkleCmdline", { default = true, bg = "#0c1230", fg = "#e6ecff" })
  api.nvim_set_hl(0, "SparkleCmdlineIcon", { default = true, fg = "#46e0ff", bold = true })
  api.nvim_set_hl(0, "SparkleCmdlinePrompt", { default = true, fg = "#ffd34d", bold = true })
end

function M.enable()
  if M.enabled or #api.nvim_list_uis() == 0 then return end
  M.enabled = true
  define_hl()
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
  vim.ui_detach(ns)
  hide_windows()
end

function M.set_calm(c)
  if c == calm then return end
  calm = c
  -- recreate both windows in the new style next time the cmdline opens
  if api.nvim_win_is_valid(S.win) then pcall(api.nvim_win_close, S.win, true) end
  if S.ov then
    S.ov:close()
    S.ov = nil
  end
end

function M.setup()
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
