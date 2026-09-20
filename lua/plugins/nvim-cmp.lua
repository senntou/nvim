return {
  "hrsh7th/nvim-cmp",
  config = function()
    local lspkind = require("lspkind")
    local cmp = require("cmp")
    local types = require('cmp.types')
    vim.opt.completeopt = { "menu", "menuone", "noselect" }

    -- insert モードの Emacs キーバインド用のヘルパー
    -- cmp が奪っているキーを、補完メニューが出ている時だけ cmp の操作に使う
    local function feed(key)
      local keys = vim.api.nvim_replace_termcodes(key, true, false, true)
      return function()
        -- "i" フラグ必須: typeahead の先頭に入れないと cmp のハンドラ内では無視される
        vim.api.nvim_feedkeys(keys, "in", false)
      end
    end

    -- メニューが出ていれば action、出ていなければ key を素のまま送る
    local function cmp_or(action, key)
      local fallback = feed(key)
      return cmp.mapping(function()
        if cmp.visible() then
          action()
        else
          fallback()
        end
      end, { "i" })
    end

    cmp.setup({
      mapping = cmp.mapping.preset.insert({
        ["<Tab>"] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.

        -- Emacs キーバインド（C-n/C-p/C-e は補完メニューが出ている時のみ従来の挙動）
        ["<C-n>"] = cmp_or(function()
          cmp.select_next_item({ behavior = types.cmp.SelectBehavior.Insert })
        end, "<Down>"),
        ["<C-p>"] = cmp_or(function()
          cmp.select_prev_item({ behavior = types.cmp.SelectBehavior.Insert })
        end, "<Up>"),
        ["<C-e>"] = cmp_or(function()
          cmp.abort()
        end, "<End>"),
        -- C-f/C-b はドキュメントのスクロール（scroll_docs）を捨ててカーソル移動に統一
        ["<C-f>"] = cmp.mapping(feed("<Right>"), { "i" }),
        ["<C-b>"] = cmp.mapping(feed("<Left>"), { "i" }),
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
