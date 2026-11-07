-- markdown-table-mode.nvim —— 表格自动补齐与对齐
-- （这是本配置原有的插件，随 markdown 模块一起搬进来，逻辑未改）
--
-- 输入 | 时自动补出整行，并在离开插入模式时把列对齐。
-- 与 render-markdown 的表格渲染可以共存；如果觉得两边都在动表格太吵，
-- 就在 lua/plugins/markdown/render.lua 里打开 pipe_table = { enabled = false }。
local features = require("core.markdown_features")

return {
  {
    "Kicamon/markdown-table-mode.nvim",
    -- 仅在打开 Markdown 文件时加载
    ft = "markdown",
    cond = features.table,
    config = function()
      require("markdown-table-mode").setup({
        filetype = { "*.md" },
        options = {
          insert = true, -- 输入 "|" 时触发
          insert_leave = true, -- 离开插入模式时触发
          alig_style = "center", -- 对齐方式: default, left, center, right
        },
      })
    end,
  },
}
