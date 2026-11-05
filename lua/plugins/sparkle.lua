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
  init = function()
    -- tabline: <leader>1..9 jumps to the n-th buffer shown at the top
    for i = 1, 9 do
      vim.keymap.set("n", "<leader>" .. i, function() require("sparkle.tabline").go(i) end,
        { desc = "Go to buffer " .. i })
    end
  end,
  opts = {
    style = "sparkle", -- initial style when nothing has been saved yet
    level = 2, -- initial flashiness (1..3) when nothing has been saved yet
    -- warp = { word = "BYE!" }, -- 終了演出の文字を変える（false で文字なし）
    features = {
      warp = false, -- 終了時のワープ演出 ("SEE YOU!") を出さず、すぐ終了する
      -- dashboard = true, notify = true, cmdline = true, statusline = true,
      -- toast = true, warp = true, glow = true, stars = true, trail = true, linenr = true,
    },
  },
}
