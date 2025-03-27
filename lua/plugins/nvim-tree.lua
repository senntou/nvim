return {
  "nvim-tree/nvim-tree.lua",
  config = function()
    require('nvim-tree').setup({
      disable_netrw = true,
      hijack_cursor = true,
    })

    function NvimTreeToggleOrFindFile()
      local api = require('nvim-tree.api')
      if api.tree.is_visible() then
        api.tree.close()
      else
        vim.cmd('NvimTreeFindFile')
      end
    end

    vim.api.nvim_set_keymap("n", "<C-n>", '<cmd>:lua NvimTreeToggleOrFindFile()<CR>', { noremap = true, silent = true })
  end
}
