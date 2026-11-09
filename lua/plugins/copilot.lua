return {
  "zbirenbaum/copilot.lua",
  enabled = false,
  cmd = "Copilot",
  event = "InsertEnter",
  opts = {
      suggestion = {
        auto_trigger = true,
        keymap = {
          accept = "<tab>",
        },
      },
      panel = { enabled = false },
  }
}
