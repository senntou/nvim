-- 日本語文章でのWORD移動(W,E,B)とaW/iWを文節単位にする
return {
  "deton/jasegment.vim",
  keys = {
    { "W", mode = { "n", "o", "x" } },
    { "E", mode = { "n", "o", "x" } },
    { "B", mode = { "n", "o", "x" } },
    { "aW", mode = { "o", "x" } },
    { "iW", mode = { "o", "x" } },
  },
  cmd = { "JaSegmentSplit" },
}
