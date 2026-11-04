return {
  'rmagatti/auto-session',
  lazy = false,

  ---enables autocomplete for opts
  ---@module "auto-session"
  ---@type AutoSession.Config
  opts = {
    suppressed_dirs = { '~/', '~/Projects', '~/Downloads', '/' },
    bypass_save_filetypes = { 'sparkle' },
    -- the sparkle dashboard is a terminal buffer: a session that contains it cannot be restored
    -- (E474: buftype=terminal). Swap it for an empty buffer before saving (the window is kept),
    -- and bring it back in that empty window after restoring.
    pre_save_cmds = {
      function() pcall(function() require('sparkle.dashboard').detach() end) end,
    },
    post_restore_cmds = {
      function()
        if vim.g.sparkle_disable then return end
        vim.schedule(function() pcall(function() require('sparkle.dashboard').open_in_empty() end) end)
      end,
    },
  },

  config = function(_, opts)
    require('auto-session').setup(opts)
    vim.o.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,localoptions"
  end
}
