return {
  'nvim-telescope/telescope.nvim',
  lazy = true,
  tag = '0.1.8',
  dependencies = { 'nvim-lua/plenary.nvim' },
  -- .gitディレクトリは除外する
  opts = {
    -- path_display: ~
    --     Determines how file paths are displayed.
    --
    --     path_display can be set to an array with a combination of:
    --     - "hidden"    hide file names
    --     - "tail"      only display the file name, and not the path
    --     - "absolute"  display absolute paths
    --     - "smart"     remove as much from the path as possible to only show
    --                   the difference between the displayed paths.
    --                   Warning: The nature of the algorithm might have a negative
    --                   performance impact!
    --     - "shorten"   only display the first character of each directory in
    --                   the path
    --     - "truncate"  truncates the start of the path when the whole path will
    --                   not fit. To increase the gap between the path and the edge,
    --                   set truncate to number `truncate = 3`
    defaults = {
      file_ignore_patterns = { '%.git' },
      path_display = { 'smart' },
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
