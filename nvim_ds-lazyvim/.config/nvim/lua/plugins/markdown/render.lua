-- render-markdown.nvim —— LazyVim「Markdown 写作」extra 的核心插件
--
-- 它不修改文件内容，只用 treesitter + extmark/conceal 把 markdown「渲染」出来：
--   # 标题      -> 放大/加粗的标题（本配置保持 LazyVim 原样：不加图标、不加侧边符号）
--   - 列表      -> 更清晰的列表符号
--   > 引用      -> 左侧竖线
--   ``` 代码块  -> 带语言名的块边框（conceal 掉围栏）
--   | 表格      -> 对齐后的表格
-- 光标所在的那一行永远显示原文，所以可以正常编辑。
--
-- 不用手动设 conceallevel：插件渲染时自己把窗口的 conceallevel 设为 3，
-- 退出渲染时恢复成你的全局值（本配置是 0），两者不冲突。
--
-- 解析器：markdown / markdown_inline。Neovim 0.12 已内置这两个 parser，
-- 且 ftplugin/markdown.lua 会自动 vim.treesitter.start()，开箱即用。
local features = require("core.markdown_features")

return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    -- 与 LazyVim 相同的文件类型列表
    ft = { "markdown", "norg", "rmd", "org" },
    cond = features.render,
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      -- 代码块语言图标；不装也能用（图标会退化）。mini.icons 同样被支持。
      "nvim-tree/nvim-web-devicons",
    },
    -- 下面三项与 LazyVim 完全一致
    opts = {
      code = { sign = false, width = "block", right_pad = 1 },
      heading = { sign = false, icons = {} },
      checkbox = { enabled = false },
      -- 本配置可选的额外调整，需要时取消注释：
      -- 觉得和 markdown-table-mode 一起动表格太吵，就关掉表格渲染
      -- pipe_table = { enabled = false },
      -- 想渲染 - [ ] 复选框（LazyVim 默认关闭）
      -- checkbox = { enabled = true },
      -- 想更贴近 LazyVim 官方观感，可以直接用官方预设（会覆盖上面的 opts）
      -- preset = "lazy",
    },
    keys = {
      {
        "<leader>um",
        function()
          require("render-markdown").toggle()
        end,
        ft = "markdown",
        desc = "Markdown: 行内渲染开关",
      },
    },
  },
}
