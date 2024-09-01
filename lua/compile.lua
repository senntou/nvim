function compile_unmodified_current_cpp()
    local filename = vim.fn.expand('%:p')
    if(vim.bo.modified) then
        vim.cmd('w')
        vim.cmd('!g++ -g ' .. filename)
    end
end
function compile_current_cpp()
    local filename = vim.fn.expand('%:p')
    vim.cmd('w')
    vim.cmd('!g++ -g ' .. filename)
end
function compile_without_g_cpp()
    local filename = vim.fn.expand('%:p')
    vim.cmd('w | !g++ -O2 ' .. filename)
    -- vim.cmd('!g++ ' .. filename)
end
-- function compile_without_g_cpp()
--   local filename = vim.fn.expand('%:p')
--   vim.cmd('split | term g++ -g ' .. filename) 
--   vim.cmd('autocmd TermClose * bd!')
-- end
