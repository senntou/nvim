# 環境構築の手順

- LSPを使った静的解析
    - masonでLSPをインストール
    - plugin-options/lspconfig.luaに追記
- フォーマッタ
    - こちらもplugin-options/lspconfig.luaに追記
- 補完
    - nvim-cmpを使って補完を追加
    - plugin-options/cmp.luaに追記

# ディレクトリ構成

- `init.lua`
  - 最初に実行されるluaファイル
- `colors/`
  - colorschemeファイルを保存する
- `lua/`
  - init.luaを除くluaファイルが格納される   

# 導入しているプラグイン

### lazy.nvim
lazy.nvim is a modern plugin manager for Neovim.

### auto-pairs
https://github.com/jiangmiao/auto-pairs
括弧などのペア記号を補完する

### bufferline.nvim
https://github.com/akinsho/bufferline.nvim
タブバーを追加するためのプラグイン

### nvim-cmp & cmp-nvim-lsp
https://github.com/hrsh7th/nvim-cmp
補完を追加するためのプラグイン

### copilot.vim
https://github.com/github/copilot.vim
GitHub Copilot for Neovim

### gitsigns.nvim
https://github.com/lewis6991/gitsigns.nvim
gitの変更を表示するためのプラグイン

### mason.nvim
https://github.com/williamboman/mason.nvim
LSPサーバーなどの外部ツールをインストールするためのプラグイン

### mason-lspconfig.nvim
https://github.com/williamboman/mason-lspconfig.nvim
lspconfigからmasonでインストールしたlspを自動で起動できるなど

### neoscroll.nvim
https://github.com/karb94/neoscroll.nvim
Neovim上でのスクロールをスムーズにする

### nerdtree
https://github.com/preservim/nerdtree
VSCodeのようなファイルエクスプローラーをサイドバーに表示する

### nvim-lspconfig
https://github.com/neovim/nvim-lspconfig
nvimのlspをラップして、configの設定を簡単にするプラグイン

### nvim-treesitter
https://github.com/nvim-treesitter/nvim-treesitter
コードを色分けするのに必要

### telescope.nvim
https://github.com/nvim-telescope/telescope.nvim
Neovimで文字列検索、ファイル検索をするためのプラグイン

### transparent.nvim
https://github.com/xiyaowong/transparent.nvim
背景を透過させるためのプラグイン



