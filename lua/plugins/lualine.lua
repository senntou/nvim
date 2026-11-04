return {
    'nvim-lualine/lualine.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons', 'sparkle.nvim' },
    -- sparkle.statusline supplies the whole config (plain lualine defaults when that feature is off)
    opts = function()
      return require('sparkle.statusline').lualine_opts()
    end,
}
