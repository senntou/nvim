return {
    "senntou/gridjump.nvim",
    -- dir = "/local/home/wkanegae/workspace/gridjump",
    config = function()
        require("gridjump").setup({
            index_rows = { 1, 11, 21, 31},
            index_cols = { 1, 21, 41, 61},
            index_style = {
                highlight = { fg = "#00ffff", bold = true },
                dim       = { fg = "#555555" },
            },
            index_chars = 'qazwsxedcrfvtgbyhnujmik,ol.p;/',
            row_stride = 1,
            col_stride = 2,
            fill_stride_gaps = true,

            free_jump = true,
        })
    end,

    keys = {
        { "<leader>g", "<cmd>GridJump<cr>", desc = "Grid Jump" },
    },
}
