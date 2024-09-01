local dap = require('dap')

-- アイコン設定
vim.fn.sign_define('DapBreakpoint', { text='●', texthl='DapBreakpointTextHl' })
vim.fn.sign_define('DapStopped', { text='➜', texthl='DapStoppedTextHl' })

dap.adapters.codelldb = {
  type = 'server',
  port = "${port}",
  executable = {
    -- CHANGE THIS to your path!
    command = vim.fn.stdpath('data') .. '/mason/packages/codelldb/extension/adapter/codelldb',
    args = {"--port", "${port}"},
    -- On windows you may have to uncomment this:
    -- detached = false,
  }
}

dap.configurations.cpp = {
  {
    name = "codelldb",
    type = "codelldb",
    request = "launch",
    program = function()
      -- return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
      local filename = vim.fn.getcwd() .. '/a'
      return filename
    end,
    cwd = '${workspaceFolder}',
    stdio = "input.txt",
    stopOnEntry = false,
  },
}
dap.configurations.rust = dap.configurations.cpp

local function remove_repl()
    local buffers = vim.api.nvim_list_bufs()
    for _, buf in ipairs(buffers) do
        local name = vim.api.nvim_buf_get_name(buf)
        if string.match(name, "%[dap%-repl%-.+") then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end
end
dap.listeners.before.event_terminated.dapui_config = function()
    remove_repl()
end
