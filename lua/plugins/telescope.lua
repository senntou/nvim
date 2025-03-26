return {
  'nvim-telescope/telescope.nvim',
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
    -- gitのステータスを表示する
    {
      "<C-G>",
      function()
        require('telescope.builtin').git_status()
      end,
    },
  }
}
