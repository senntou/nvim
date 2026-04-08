return {
  "gaoDean/autolist.nvim",
  ft = { "markdown" },
  config = function()
    require("autolist").setup()
    vim.keymap.set("i", "<CR>", "<CR><cmd>AutolistNewBullet<cr>")
  end,
}
