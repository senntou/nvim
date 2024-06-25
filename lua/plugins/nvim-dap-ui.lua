return {
    "rcarriga/nvim-dap-ui",
    dependencies = {"mfussenegger/nvim-dap", "nvim-neotest/nvim-nio"},
    config = function()
        require('dapui').setup({
            -- UIのレイアウトを変更
            layouts = {
              {
                id = 1,
                elements = {
                  -- { id = 'repl', size = 0.15 },
                  -- { id = 'stacks', size = 0.2 },
                  { id = 'watches', size = 0.5 },
                  { id = 'scopes',  size = 0.5 },
                  -- { id = 'breakpoints', size = 0.1 }
                },
                size = 0.4,
                position = 'right'
              },
              {
                id = 2,
                elements = { 'console' },
                size = 0.25,
                position = 'bottom'
              }
          }
        })
    end
}
