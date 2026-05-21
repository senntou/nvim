return {
  "sindrets/diffview.nvim",
  opts = {
    enhanced_diff_hl = false,
    keymaps = {
      disable_default = true,
      view = {
        { "n", "L", false },
      },
      diff1 = {
        { "n", "L", false },
      },
      diff2 = {
        { "n", "L", false },
      },
      diff3 = {
        { "n", "L", false },
      },
      diff4 = {
        { "n", "L", false },
      },
      file_panel = {
        { "n", "L", false },
      },
      file_history_panel = {
        { "n", "L", false },
      },
    },
  },

  config = function(_, opts)
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
  },
}
