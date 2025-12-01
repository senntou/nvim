return {
  'rmagatti/auto-session',
  lazy = false,
  enabled = false,

  ---enables autocomplete for opts
  ---@module "auto-session"
  ---@type AutoSession.Config
  opts = {
    suppressed_dirs = { '~/', '~/Projects', '~/Downloads', '/' },
    bypass_save_filetypes = { 'alpha' }
  },

  config = function(opts)
    require('auto-session').setup(opts)
    vim.o.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,localoptions"
  end
}
