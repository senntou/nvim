return {
    "tetsuya28/memo.nvim",
    dependencies = { "nvim-telescope/telescope.nvim" },
    config = function()
        local memo = require("memo")
        local save_dir = vim.fn.expand("$HOME/.nvim/memos")

        memo.setup({
            save_dir = save_dir,
            width = 100,
            height = 30,
        })

        -- 以降、Claude Code にたのんで、かなりプラグインを魔改造している
        vim.api.nvim_create_autocmd({ "BufEnter", "BufFilePost" }, {
            callback = function(ev)
                local name = vim.api.nvim_buf_get_name(ev.buf)
                if name:find(save_dir, 1, true) and name:match("%.md$") then
                    vim.keymap.set("n", "q", "<cmd>silent! write<cr><cmd>close<cr>", { buffer = ev.buf, nowait = true })
                    vim.api.nvim_win_set_option(0, "number", true)
                end
            end,
        })

        vim.api.nvim_create_autocmd("BufAdd", {
            pattern = save_dir .. "/*.md",
            callback = function(ev)
                vim.api.nvim_buf_set_option(ev.buf, "buflisted", false)
            end,
        })

        vim.api.nvim_create_user_command("MemoList", function()
            require("telescope.builtin").find_files({
                prompt_title = "Memos  [Enter] open  [C-r] rename  [C-d] delete",
                cwd = save_dir,
                attach_mappings = function(prompt_bufnr, map)
                    local actions = require("telescope.actions")
                    local action_state = require("telescope.actions.state")

                    actions.select_default:replace(function()
                        actions.close(prompt_bufnr)
                        local selection = action_state.get_selected_entry()
                        if selection then
                            memo.memo.open_with_filename(selection.path)
                        end
                    end)

                    map("i", "<C-r>", function()
                        local selection = action_state.get_selected_entry()
                        if not selection then return end
                        local old_path = selection.path
                        local old_name = vim.fn.fnamemodify(old_path, ":t:r")
                        local new_name = vim.fn.input("Rename: ", old_name)
                        if new_name == "" or new_name == old_name then return end
                        local new_path = save_dir .. "/" .. new_name .. ".md"
                        vim.fn.rename(old_path, new_path)
                        actions.close(prompt_bufnr)
                        vim.cmd("MemoList")
                    end)

                    map("i", "<C-a>", function()
                        local name = vim.fn.input("New memo: ")
                        if name == "" then return end
                        actions.close(prompt_bufnr)
                        memo.memo.open_with_filename(save_dir .. "/" .. name .. ".md")
                    end)

                    map("i", "<C-d>", function()
                        local selection = action_state.get_selected_entry()
                        if not selection then return end
                        local path = selection.path
                        local name = vim.fn.fnamemodify(path, ":t")
                        local ok = vim.fn.confirm("Delete " .. name .. "?", "&Yes\n&No", 2)
                        if ok ~= 1 then return end
                        vim.fn.delete(path)
                        actions.close(prompt_bufnr)
                        vim.cmd("MemoList")
                    end)

                    return true
                end,
            })
        end, { desc = "List memos with telescope" })

        vim.api.nvim_create_user_command("MemoLatest", function()
            local files = vim.fn.glob(save_dir .. "/*.md", false, true)
            if #files == 0 then
                vim.api.nvim_err_writeln("No memos found")
                return
            end
            table.sort(files, function(a, b)
                return vim.fn.getftime(a) > vim.fn.getftime(b)
            end)
            memo.memo.open_with_filename(files[1])
        end, { desc = "Open latest memo" })
    end,
    keys = {
        { "<leader>mm", "<cmd>MemoList<cr>", desc = "List memos" },
        { "<leader>ml", "<cmd>MemoLatest<cr>", desc = "Open latest memo" },
    },
}

