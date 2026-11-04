-- sparkle: SHOOTIE-flavoured eye candy for Neovim.
--
--   require("sparkle").setup({
--     style = "sparkle",                    -- or "calm"; only used until :SparkleStyle saves a choice
--     level = 2,                            -- flashiness 1..3; only used until :SparkleLevel saves one
--     dashboard = { ... },                  -- sparkle.dashboard config
--     features = { toast = false, ... },    -- turn individual features off (read at startup)
--   })
--
-- Two styles, switched at runtime with :SparkleToggle / :SparkleStyle {sparkle|calm} (remembered):
--   sparkle  neon palette, everything animated
--   calm     the UI parts (dashboard, cmdline, notify, statusline) stay, drawn statically in the
--            colours of the current colorscheme; the purely decorative effects are switched off.
--
-- Set vim.g.sparkle_disable = true (e.g. over a slow ssh link) to keep everything off.
local style = require("sparkle.style")

local M = {}

M.features = {
  dashboard = true, -- start screen
  notify = true, -- vim.notify replacement
  cmdline = true, -- centred command line
  statusline = true, -- lualine config (needs the lualine spec to use sparkle.statusline)
  toast = true, -- "SAVED!" pop-up on :w                       (decoration)
  warp = true, -- hyperspace jump on quit                       (decoration)
  glow = true, -- breathing borders / cursor line number        (decoration)
  stars = true, -- twinkling stars in the empty space            (decoration)
  trail = true, -- sparks while typing, comet trail on jumps     (decoration)
  linenr = true, -- flowing gradient line numbers                (decoration)
  searchfx = true, -- search matches keep shimmering after <CR>  (decoration)
}

-- UI parts: always set up, told about the style via set_calm(calm)
local UI = { "dashboard", "notify", "cmdline", "statusline" }
-- decorations: only set up while the sparkle style is on, switched with set_active(on)
local DECOR = { "toast", "warp", "glow", "stars", "trail", "linenr", "searchfx" }

local loaded = {} -- [name] = true once its setup() ran
local opts_ = {}

local function try(name, fn)
  local ok, err = pcall(fn)
  if not ok then vim.notify("sparkle." .. name .. ": " .. tostring(err), vim.log.levels.WARN) end
  return ok
end

local function setup_dashboard()
  local dash = require("sparkle.dashboard")
  dash.config = vim.tbl_extend("force", dash.config, opts_.dashboard or {})

  vim.api.nvim_create_user_command("Sparkle", function() dash.open() end, { desc = "Open the sparkle dashboard" })

  local grp = vim.api.nvim_create_augroup("SparkleStartup", { clear = true })
  vim.api.nvim_create_autocmd("StdinReadPre", {
    group = grp,
    callback = function() vim.g.sparkle_stdin = true end,
  })
  vim.api.nvim_create_autocmd("VimEnter", {
    group = grp,
    nested = true,
    callback = function()
      if vim.fn.argc() > 0 or vim.g.sparkle_stdin or #vim.api.nvim_list_uis() == 0 then return end
      -- a session (auto-session) was restored, possibly only partly: leave its layout alone
      if vim.v.this_session ~= "" then return end
      local normal = 0
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_config(w).relative == "" then normal = normal + 1 end
      end
      if normal > 1 then return end
      local buf = vim.api.nvim_get_current_buf()
      if vim.api.nvim_buf_get_name(buf) ~= "" or vim.bo[buf].modified then return end
      if vim.api.nvim_buf_line_count(buf) > 1 or vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] ~= "" then return end
      dash.open()
    end,
  })
end

local function ensure(name)
  if loaded[name] then return true end
  local ok = try(name, function()
    if name == "dashboard" then setup_dashboard() else require("sparkle." .. name).setup() end
  end)
  loaded[name] = ok
  return ok
end

-- (re)apply the current style to every enabled feature
local function apply()
  local calm = style.calm()
  for _, name in ipairs(UI) do
    if M.features[name] and ensure(name) then
      local mod = require("sparkle." .. name)
      if mod.set_calm then try(name, function() mod.set_calm(calm) end) end
    end
  end
  for _, name in ipairs(DECOR) do
    if M.features[name] then
      if not calm then
        if ensure(name) then try(name, function() require("sparkle." .. name).set_active(true) end) end
      elseif loaded[name] then
        try(name, function() require("sparkle." .. name).set_active(false) end)
      end
    end
  end
end

function M.calm() return style.calm() end

function M.set_style(s)
  if s ~= "sparkle" and s ~= "calm" then
    vim.notify("sparkle: unknown style '" .. tostring(s) .. "' (sparkle|calm)", vim.log.levels.WARN)
    return
  end
  style.current = s
  style.save()
  apply()
  vim.api.nvim_exec_autocmds("User", { pattern = "SparkleStyle", data = { style = s } })
end

-- flashiness of the sparkle style (1..3). Modules read style.level and react to User SparkleLevel.
function M.set_level(n)
  n = tonumber(n)
  if not n or n < 1 or n > style.LEVEL_MAX then
    vim.notify("sparkle: level must be 1.." .. style.LEVEL_MAX, vim.log.levels.WARN)
    return
  end
  style.level = math.floor(n)
  style.save()
  vim.api.nvim_exec_autocmds("User", { pattern = "SparkleLevel", data = { level = style.level } })
end

function M.toggle()
  M.set_style(style.calm() and "sparkle" or "calm")
end

function M.setup(opts)
  opts_ = opts or {}
  if vim.g.sparkle_disable then
    M.features = vim.tbl_map(function() return false end, M.features)
    return
  end
  M.features = vim.tbl_extend("force", M.features, opts_.features or {})
  style.load(opts_.style, opts_.level)

  vim.api.nvim_create_user_command("SparkleToggle", M.toggle, { desc = "sparkle: switch sparkle <-> calm style" })
  vim.api.nvim_create_user_command("SparkleStyle", function(o)
    if o.args == "" then
      print("sparkle style: " .. style.current)
    else
      M.set_style(o.args)
    end
  end, { nargs = "?", complete = function() return { "sparkle", "calm" } end, desc = "sparkle: set the style" })

  vim.api.nvim_create_user_command("SparkleLevel", function(o)
    if o.args == "" then
      print("sparkle level: " .. style.level)
    else
      M.set_level(o.args)
    end
  end, { nargs = "?", complete = function() return { "1", "2", "3" } end, desc = "sparkle: set the flashiness (1..3)" })

  apply()
end

return M
