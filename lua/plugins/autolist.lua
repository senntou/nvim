return {
    "gaoDean/autolist.nvim",
    ft = {
        "markdown",
        "text",
    },
    config = function()
        require("autolist").setup()

        vim.keymap.set("i", "<tab>", "<cmd>AutolistTab<cr>")
        -- AutolistShiftTab は内部で <c-d> をリマップ有効で feedkeys するため、
        -- insert の C-d を <Del> に割り当てているこの設定では壊れる。
        -- <c-d> を noremap で送って自前でインデントを下げる
        vim.keymap.set("i", "<s-tab>", function()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-d>", true, false, true), "n", false)
            vim.schedule(function() vim.cmd("AutolistRecalculate") end)
        end)
        -- vim.keymap.set("i", "<c-t>", "<c-t><cmd>AutolistRecalculate<cr>") -- an example of using <c-t> to indent
        vim.keymap.set("i", "<CR>", "<CR><cmd>AutolistNewBullet<cr>")
        vim.keymap.set("n", "o", "o<cmd>AutolistNewBullet<cr>")
        vim.keymap.set("n", "O", "O<cmd>AutolistNewBulletBefore<cr>")
        vim.keymap.set("n", "<space>", "<cmd>AutolistToggleCheckbox<CR>")

        -- cycle list types with dot-repeat
        vim.keymap.set("n", "<leader>cn", require("autolist").cycle_next_dr, { expr = true })
        vim.keymap.set("n", "<leader>cp", require("autolist").cycle_prev_dr, { expr = true })

        -- if you don't want dot-repeat
        -- vim.keymap.set("n", "<leader>cn", "<cmd>AutolistCycleNext<cr>")
        -- vim.keymap.set("n", "<leader>cp", "<cmd>AutolistCycleNext<cr>")

        -- functions to recalculate list on edit
        vim.keymap.set("n", ">>", ">><cmd>AutolistRecalculate<cr>")
        vim.keymap.set("n", "<<", "<<<cmd>AutolistRecalculate<cr>")
        vim.keymap.set("n", "dd", "dd<cmd>AutolistRecalculate<cr>")
        vim.keymap.set("v", "d", "d<cmd>AutolistRecalculate<cr>")
    end,
}

