-- C言語関連のLSPについての設定
-- compile_commandsや.gitが無いプロジェクトでは動かない
require'lspconfig'.clangd.setup {
  cmd = { "clangd", "--background-index" },
  filetypes = { "c", "cpp", "objc", "objcpp" },
  root_dir = require'lspconfig'.util.root_pattern("compile_commands.json", "compile_flags.txt", ".git"),
  init_options = {
    clangdFileStatus = true
  }
}
