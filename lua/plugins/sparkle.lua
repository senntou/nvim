-- sparkle.nvim: local plugin living in this config repo (sparkle.nvim/)
--   :SparkleToggle               sparkle <-> calm (colorscheme colours, no animation; remembered)
--   :SparkleStyle {sparkle|calm}
--   :SparkleLevel {1|2|3}        flashiness of the star field (remembered)
return {
  dir = vim.fn.stdpath("config") .. "/sparkle.nvim",
  name = "sparkle.nvim",
  main = "sparkle",
  lazy = false,
  priority = 900,
  keys = {
    { "<leader>s", "<cmd>SparkleToggle<cr>", desc = "sparkle: toggle sparkle / calm" },
    { "<leader>S", function()
      local sp = require("sparkle")
      sp.set_level(require("sparkle.style").level % 3 + 1)
      vim.notify("sparkle level: " .. require("sparkle.style").level)
    end, desc = "sparkle: cycle flashiness 1 -> 2 -> 3" },
  },
  opts = {
    style = "sparkle", -- initial style when nothing has been saved yet
    level = 2, -- initial flashiness (1..3) when nothing has been saved yet
    features = {
      -- dashboard = true, notify = true, cmdline = true, statusline = true,
      -- toast = true, warp = true, glow = true, stars = true, trail = true, linenr = true,
    },
  },
}
