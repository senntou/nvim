return {
  "almo7aya/openingh.nvim",
  lazy = true,
  keys = {
    { "gh", "<cmd>:OpenInGHFileLines<CR>",      mode = "n", desc = "Open Line in GitHub" },
    { "gh", "<cmd>:'<,'>OpenInGHFileLines<CR>", mode = "v", desc = "Open Line in GitHub" },
  },
}
