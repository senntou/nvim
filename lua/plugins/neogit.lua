return {
  "NeogitOrg/neogit",
  config       = true,
  dependencies = {
    "nvim-lua/plenary.nvim",         -- required
    "sindrets/diffview.nvim",        -- optional - Diff integration
    "nvim-telescope/telescope.nvim", -- optional
  },
  -- キーマップ
  keys         = {
    {
      "<leader>ng",
      function()
        require("neogit").open()
      end,
    }
  },
}
