return {
  "hrsh7th/nvim-cmp",
  config = function()
    local lspkind = require("lspkind")
    local cmp = require("cmp")
    local types = require('cmp.types')
    vim.opt.completeopt = { "menu", "menuone", "noselect" }
    cmp.setup({
      mapping = cmp.mapping.preset.insert({
        ["<Tab>"] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
      }),
      sources = cmp.config.sources({
        { name = "copilot" },
        { name = "nvim_lsp" },
        { name = "nvim_lua" },
        -- { name = "luasnip" }, -- For luasnip users.
      }, {
        { name = "buffer" },
        { name = "path" },
      }),

      formatting = {
        format = lspkind.cmp_format({
          mode = 'symbol_text',
          menu = ({
            buffer = "[Buffer]",
            nvim_lsp = "[LSP]",
            copilot = "[Copilot]",
            nvim_lua = "[Lua]",
            latex_symbols = "[Latex]",
          }),
        }),
      },
    })
  end
}
