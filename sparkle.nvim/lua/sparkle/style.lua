-- sparkle.style: "sparkle" (animated, neon palette) or "calm" (colorscheme colours, no animation).
-- The choice is remembered in stdpath("state")/sparkle.json.
local M = {}

M.current = "sparkle"

local function state_file()
  return vim.fn.stdpath("state") .. "/sparkle.json"
end

function M.load(default)
  M.current = default or "sparkle"
  local f = io.open(state_file(), "r")
  if f then
    local ok, data = pcall(vim.json.decode, f:read("*a"))
    f:close()
    if ok and type(data) == "table" and (data.style == "sparkle" or data.style == "calm") then
      M.current = data.style
    end
  end
  return M.current
end

function M.save()
  vim.fn.mkdir(vim.fn.stdpath("state"), "p")
  local f = io.open(state_file(), "w")
  if not f then return end
  f:write(vim.json.encode({ style = M.current }))
  f:close()
end

function M.calm() return M.current == "calm" end

return M
