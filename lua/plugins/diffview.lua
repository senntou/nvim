return {
  "sindrets/diffview.nvim",
  opts = {
    enhanced_diff_hl = false,
    keymaps = {
      disable_default = true,
    },
  },

  config = function(opts)
    require("diffview").setup(opts)
    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = "diffview://*",
      callback = function()
        vim.keymap.set("n", "q", ":DiffviewClose<CR>", { buffer = true })
      end,
    })
  end,

  keys = {
    {
      "<leader>df",
      function()
        local lib = require("diffview.lib")
        local view = lib.get_current_view()
        if view then
          -- Current tabpage is a Diffview; close it
          vim.cmd.DiffviewClose()
        else
          -- No open Diffview exists: open a new one
          vim.cmd.DiffviewOpen()
        end
      end,
      desc = "toggle Diffview"
    },
    {
      "q",
      "<cmd>DiffviewClose<cr>",
      desc = "Close Diffview",
    }
  },

}
