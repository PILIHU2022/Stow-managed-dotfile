-- markdown-preview.nvim —— 浏览器实时预览（LazyVim lang.markdown extra 同款）
--
-- 按键：
--   <leader>cp   LazyVim 键位，由 lazy.nvim 懒加载（定义在本文件）
--   <C-k> <C-m>  本配置原有的键位，在 keymap/markdown.lua 里，仅 markdown buffer 生效
-- 命令：
--   :MarkdownPreview / :MarkdownPreviewStop / :MarkdownPreviewToggle
local features = require("core.markdown_features")

return {
  {
    "iamcco/markdown-preview.nvim",
    -- 命令或按键触发时才下载并加载
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    cond = features.preview,
    -- LazyVim 的安装方式：调用插件自带脚本下载预编译好的二进制，不需要 yarn/node。
    -- 若网络受限导致下载失败，换回原来的 yarn 方式即可：
    --   build = "cd app && yarn install",
    build = function()
      require("lazy").load({ plugins = { "markdown-preview.nvim" } })
      vim.fn["mkdp#util#install"]()
    end,
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
    end,
    keys = {
      {
        "<leader>cp",
        "<cmd>MarkdownPreviewToggle<cr>",
        ft = "markdown",
        desc = "Markdown: 浏览器预览",
      },
    },
    -- LazyVim 同款：加载后补触发一次 FileType，让 mkdp 正确接管当前 buffer
    config = function()
      vim.cmd([[do FileType]])
    end,
  },
}
