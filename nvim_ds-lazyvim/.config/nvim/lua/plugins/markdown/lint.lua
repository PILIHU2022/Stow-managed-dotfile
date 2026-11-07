-- nvim-lint + markdownlint-cli2 —— markdown 写作规范检查
-- （LazyVim lang.markdown extra 用的是同一套）
--
-- 触发时机：保存后、离开插入模式。不放在 TextChanged 里，避免写一半就满屏报错。
-- 前置条件：系统里有 markdownlint-cli2 命令；没有时本模块静默跳过，不会报错。
--   安装方式（任选其一）：
--     npm i -g markdownlint-cli2
--     或加装 mason.nvim，见 doc/markdown-writing.md
-- 规则配置：在项目里放 .markdownlint.yaml / .markdownlint.json 即可，
--           不需要改 nvim 配置；没有配置文件时用 markdownlint 默认规则。
local features = require("core.markdown_features")

return {
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPre", "BufNewFile" },
    cond = features.lint,
    config = function()
      local lint = require("lint")

      lint.linters_by_ft = lint.linters_by_ft or {}
      lint.linters_by_ft.markdown = { "markdownlint-cli2" }

      -- 保存后 / 离开插入模式时检查（不放在 TextChanged，避免写一半满屏报错）
      local group = vim.api.nvim_create_augroup("UserMdLint", { clear = true })
      vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave" }, {
        group = group,
        callback = function()
          -- 命令没装就直接跳过：否则 nvim-lint 每次保存都会报一次错
          if vim.fn.executable("markdownlint-cli2") == 0 then
            return
          end
          lint.try_lint()
        end,
      })
    end,
  },
}
