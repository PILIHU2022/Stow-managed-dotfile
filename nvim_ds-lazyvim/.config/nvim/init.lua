require("lazy_setup")
require("core.options")
require("core.keymap")

-- Markdown 写作相关入口
--   插件：lua/plugins/markdown/   开关：lua/core/markdown_features.lua
--   设置：lua/core/markdown_writing.lua   按键：lua/keymap/markdown.lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    require("core.markdown_writing").setup() -- 软换行 / formatoptions / 拼写
    require("keymap.markdown").setup() -- buffer 内按键
  end,
})
