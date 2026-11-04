-- sparkle.nvim: local plugin living in this config repo (sparkle.nvim/)
--   :SparkleToggle               sparkle <-> calm (colorscheme colours, no animation; remembered)
--   :SparkleStyle {sparkle|calm}
return {
  dir = vim.fn.stdpath("config") .. "/sparkle.nvim",
  name = "sparkle.nvim",
  main = "sparkle",
  lazy = false,
  priority = 900,
  keys = {
    { "<leader>s", "<cmd>SparkleToggle<cr>", desc = "sparkle: toggle sparkle / calm" },
  },
  opts = {
    style = "sparkle", -- initial style when nothing has been saved yet
    features = {
      -- dashboard = true, notify = true, cmdline = true, statusline = true,
      -- toast = true, warp = true, glow = true, stars = true, trail = true, linenr = true,
    },
  },
}
