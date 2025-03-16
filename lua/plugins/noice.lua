return {
  "folke/noice.nvim",
  event = "VeryLazy",
  config = true,
  dependencies = {
    -- if you lazy-load any plugin below, make sure to add proper `module="..."` entries
    "MunifTanjim/nui.nvim",
    -- OPTIONAL:
    "rcarriga/nvim-notify",
  }
}
