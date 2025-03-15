require("config")

vim.cmd[[let g:python3_host_prog = 'C:\Users\watar\AppData\Local\Programs\Python\Python312\python.exe']]

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins")
require("colorscheme")
require("keymapping.default")
require("commands")
require("plugin-options.bufferline")
require("plugin-options.nerdtree")
require("plugin-options.telescope")
require("plugin-options.transparent")
require("plugin-options.treesitter")
require("plugin-options.lspconfig")


-- local vimrcを読み込む設定
local function load_local_vimrc()
  local local_vimrc = vim.fn.getcwd() .. "/.vimrc"
  if vim.fn.filereadable(local_vimrc) == 1 then
    vim.cmd('source ' .. local_vimrc)
  end
end

-- Neovimが起動するたびにlocal vimrcを読み込む
load_local_vimrc()
