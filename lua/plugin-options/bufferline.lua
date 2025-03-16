vim.opt.termguicolors = true
require('bufferline').setup({
  options = {
    custom_filter = function(buf_number)
      if vim.bo[buf_number].buftype == 'terminal' then
        return false;
      end
      return true;
    end
  }
})
