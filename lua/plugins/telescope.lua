return {
  'nvim-telescope/telescope.nvim',
  lazy = true,
  tag = '0.1.8',
  dependencies = { 'nvim-lua/plenary.nvim' },
  -- .gitディレクトリは除外する
  opts = {
    defaults = {
      file_ignore_patterns = { '%.git' },
    },
  },

  -- キーマップ
  keys = {
    -- 隠しファイルも含め、ファイル検索をして表示する
    {
      "<C-p>",
      function()
        require('telescope.builtin').find_files({
          hidden = true,
        })
      end,
    },
    -- gitのブランチを表示する
    {
      "<C-\\><C-b>",
      function()
        require('telescope.builtin').git_branches()
      end,
    },
    {
      "<C-_><C-b>",
      function()
        require('telescope.builtin').git_branches()
      end,
    },
    -- gitのステータスを表示する
    {
      "<C-G>",
      function()
        require('telescope.builtin').git_status()
      end,
    },
    -- 文字列検索をして表示する
    {
      "<C-o>",
      function()
        require('telescope.builtin').live_grep()
      end,
    },
  }
}
