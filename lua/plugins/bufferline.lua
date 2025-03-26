return {
  'akinsho/bufferline.nvim',
  opts = {
    options = {

      numbers = 'bufer_id',
      diagnostics = 'nvim_lsp',

      custom_filter = function(buf_number)
        if vim.bo[buf_number].buftype == 'terminal' then
          return false;
        end
        return true;
      end,

      offsets = {
        {
          filetype = "NvimTree",
          text = "Nvim Tree",
          text_align = "center",
          separator = true
        }
      },

    }
  },
  version = "*",
  dependencies = 'nvim-tree/nvim-web-devicons'
}
