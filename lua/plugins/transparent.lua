return {
  "xiyaowong/transparent.nvim",
  init = function()
    vim.keymap.set('n', '<leader>t', function() vim.cmd(':TransparentToggle') end, { desc = 'Toggle transparency' })
  end,
  opts = {
    groups = { -- table: default groups
      'Normal', 'NormalNC', 'Comment', 'Constant', 'Special', 'Identifier',
      'Statement', 'PreProc', 'Type', 'Underlined', 'Todo', 'String', 'Function',
      'Conditional', 'Repeat', 'Operator', 'Structure', 'LineNr', 'NonText',
      'SignColumn', 'CursorLine', 'CursorLineNr', 'StatusLine', 'StatusLineNC',
      'EndOfBuffer',
    },
    extra_groups = {}, -- table: additional groups that should be cleared
    exclude_groups = {
      'StatusLine', 'StatusLineNC',
    }, -- table: groups you don't want to clear
  }
}
