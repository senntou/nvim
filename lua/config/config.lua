-- 文字コード
vim.o.encoding = "utf-8"
vim.o.fileencoding = "utf-8"

-- clipboard
vim.o.clipboard = "unnamedplus"

vim.o.autoindent = true

-- 行番号
vim.o.number = true
vim.o.shiftwidth = 2
vim.o.tabstop = 2
vim.o.softtabstop = 2

-- インデント
vim.o.expandtab = true
vim.o.smartindent = true

-- cppファイルのコメントアウト
vim.cmd [[ autocmd FileType cpp setlocal commentstring=//\ %s ]]
-- phpファイルのコメントアウト
vim.cmd [[ autocmd FileType php setlocal commentstring=//\ %s ]]

-- xで削除した文字をクリップボードに保存しない
vim.api.nvim_set_keymap("n", "x", '"_x', { noremap = true, silent = true })

-- 不要な標準プラグインを無効化
vim.g.did_install_default_menus  = 1
vim.g.did_install_syntax_menu    = 1
vim.g.did_indent_on              = 1
vim.g.did_load_ftplugin          = 1
vim.g.loaded_2html_plugin        = 1
vim.g.loaded_gzip                = 1
vim.g.loaded_man                 = 1
vim.g.loaded_matchit             = 1
vim.g.loaded_matchparen          = 1
vim.g.loaded_netrwPlugin         = 1
vim.g.loaded_remote_plugins      = 1
vim.g.loaded_shada_plugin        = 1
vim.g.loaded_spellfile_plugin    = 1
vim.g.loaded_tarPlugin           = 1
vim.g.loaded_tutor_mode_plugin   = 1
vim.g.loaded_zipPlugin           = 1
vim.g.skip_loading_mswin         = 1

