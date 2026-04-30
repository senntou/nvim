return {
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    dependencies = {
      { "nvim-lua/plenary.nvim", branch = "master" },
    },
    build = "make tiktoken",
    opts = {
      -- See Configuration section for options
    },
    keys = {
      {
        "<leader>cc",
        function()
          require("CopilotChat").open({
            window = {
              layout = 'float',
              width = 80, -- Fixed width in columns
              height = 20, -- Fixed height in rows
              border = 'rounded', -- 'single', 'double', 'rounded', 'solid'
              title = '🤖 AI Assistant',
              zindex = 100, -- Ensure window stays on top
            },
          
            headers = {
              user = '👤 You',
              assistant = '🤖 Copilot',
              tool = '🔧 Tool',
            },
          
            separator = '━━',
            auto_fold = true, -- Automatically folds non-assistant messages
          })
        end,
        desc = "Open Copilot Chat",
      },
    },
  },
}
