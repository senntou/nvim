return {
  "RRethy/vim-illuminate",
  config = function()
    require("illuminate").configure({
      filetypes_denylist = {
        "help",
        "lazy",
        "mason",
        "netrw",
        "NvimTree",
        "TelescopePrompt",
      },
      under_cursor = true,
    })
  end,
}
