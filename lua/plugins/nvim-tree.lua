return {
  "nvim-tree/nvim-tree.lua",
  lazy = true,
  config = function()
    local function my_on_attach(bufnr)
      local api = require('nvim-tree.api')

      -- Default mappings
      api.config.mappings.default_on_attach(bufnr)
      vim.keymap.del('n', 'q', { buffer = bufnr }) -- Disable the default 'q' mapping
    end

    require('nvim-tree').setup({
      on_attach = my_on_attach,
      disable_netrw = true,
      hijack_cursor = true,
      filters = {
        git_ignored = false,
      }
    })

    function NvimTreeToggleOrFindFile()
      local api = require('nvim-tree.api')
      if api.tree.is_visible() then
        api.tree.close()
      else
        vim.cmd('NvimTreeFindFile')
      end
    end
  end,

  keys = {
    { "<C-n>", "<cmd>:lua NvimTreeToggleOrFindFile()<CR>", desc = "Toggle NvimTree" },
  }
}
