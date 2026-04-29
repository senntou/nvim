return {
  {
    "nvimtools/hydra.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    config = function()
      local Hydra = require("hydra")

      Hydra({
        name = "Window",
        mode = "n",
        body = "<leader>w",
        hint = [[
Window
-------
_h_ ←   _j_ ↓   _k_ ↑   _l_ →
_H_ shrink   _L_ expand
_K_ taller   _J_ shorter

_s_ split   _v_ vsplit
_b_ next buffer

_d_ close   _q_ quit
               ]],
        config = {
          color = "pink",
          hint = {
            type = "window",
            position = "top-right",
            float_opts = {
              border = "rounded",
            },
          },
          on_enter = function()
            vim.o.timeoutlen = 0
          end,
          on_exit = function()
            vim.o.timeoutlen = 300
          end,
        },
        heads = {
          -- 移動
          { "h", "<C-w>h" },
          { "j", "<C-w>j" },
          { "k", "<C-w>k" },
          { "l", "<C-w>l" },

          -- リサイズ
          { "H", "<C-w><" },
          { "L", "<C-w>>" },
          { "K", "<C-w>+" },
          { "J", "<C-w>-" },

          -- 分割
          { "s", "<C-w>s" },
          { "v", "<C-w>v", { nowait = true } },

          -- 右に新しいバッファ表示
          { "b", "<C-w>v | bnext" },

          -- 終了
          { "d", "<C-w>q" },
          { "q", "", { exit = true } },
        }
      })
    end,
  }
}
