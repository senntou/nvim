return {
    'nvim-telescope/telescope.nvim', tag = '0.1.8',
    dependencies = { 'nvim-lua/plenary.nvim' },
    -- .gitディレクトリは除外する
    opts = {
      defaults = {
        file_ignore_patterns = { '%.git' },
      },
    },
    
    -- キーマップ
    -- 隠しファイルも表示する
    keys = {
      {
        "<C-p>",
        function()
          require('telescope.builtin').find_files({
            hidden = true,
          })
        end,
      }
    }
}
