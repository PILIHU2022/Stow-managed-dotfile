-- trouble.nvim —— 把「诊断 / 符号 / 引用 / quickfix」整理成可操作的面板
--
-- 和你现有配置的关系：
--   lspsaga 的 <leader>sd 是"一次性弹窗看诊断"，trouble 是一块可切换的列表面板：
--   能常驻、能在里面跳转/预览、能一次看完整个项目的报错。两者互补，不冲突。
--
-- 版本：trouble v3 用 `:Trouble <mode> toggle` 这类命令，下面用就是这个形式。
-- 要求 Neovim >= 0.9.2（本机 0.12.5），图标复用已装的 mini.icons / nvim-web-devicons。
return {
  {
    "folke/trouble.nvim",
    -- 只有执行 :Trouble 或按下面的键才加载
    cmd = { "Trouble" },
    opts = {
      -- LazyVim 同款：LSP 列表（引用 / 定义 / 实现）默认开在右侧
      modes = {
        lsp = {
          win = { position = "right" },
        },
      },
    },
    keys = {
      {
        "<leader>xx",
        "<cmd>Trouble diagnostics toggle<cr>",
        desc = "诊断列表（全部）",
      },
      {
        "<leader>xX",
        "<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
        desc = "诊断列表（仅当前 buffer）",
      },
      {
        "<leader>cs",
        "<cmd>Trouble symbols toggle<cr>",
        desc = "符号大纲",
      },
      {
        "<leader>cS",
        "<cmd>Trouble lsp toggle<cr>",
        desc = "引用 / 定义 / 实现",
      },
      {
        "<leader>xL",
        "<cmd>Trouble loclist toggle<cr>",
        desc = "Location List",
      },
      {
        "<leader>xQ",
        "<cmd>Trouble qflist toggle<cr>",
        desc = "Quickfix List",
      },
      -- LazyVim 同款：给内置的 [q / ]q 加一层"Trouble 感知"。
      -- Trouble 面板开着时在面板里跳，否则原样退回 :cprev / :cnext，
      -- 所以内置的 quickfix 跳转行为不会丢失。
      {
        "[q",
        function()
          if require("trouble").is_open() then
            require("trouble").prev({ skip_groups = true, jump = true })
          else
            local ok, err = pcall(vim.cmd.cprev)
            if not ok then
              vim.notify(err, vim.log.levels.ERROR)
            end
          end
        end,
        desc = "上一个 Trouble / Quickfix 条目",
      },
      {
        "]q",
        function()
          if require("trouble").is_open() then
            require("trouble").next({ skip_groups = true, jump = true })
          else
            local ok, err = pcall(vim.cmd.cnext)
            if not ok then
              vim.notify(err, vim.log.levels.ERROR)
            end
          end
        end,
        desc = "下一个 Trouble / Quickfix 条目",
      },
    },
  },
}
