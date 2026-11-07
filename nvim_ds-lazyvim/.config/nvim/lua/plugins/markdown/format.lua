-- conform.nvim 的 markdown 格式化链（LazyVim lang.markdown extra 同款）
--
-- 保存 markdown 时依次执行，前一个失败不影响后一个：
--   1. prettier            统一 markdown 风格（已随系统安装）
--   2. markdownlint-cli2   只修能自动修的规范问题；仅当 buffer 里已有
--                          markdownlint 诊断时才跑（LazyVim 同款条件）
--   3. markdown-toc        刷新 <!-- toc --> 处的目录；仅当有该标记时才跑
-- 2、3 所需的可执行文件不存在时会自动跳过，不会报错。
--
-- 本模块只「扩展」已有的 lua/plugins/conform.lua：
-- 用 optional = true，只有那个文件声明了 conform 时才合并这里的设置，
-- 避免为了 markdown 把一个格式化框架强塞给配置。
local features = require("core.markdown_features")

-- 保存 markdown 时的格式化链（顺序即执行顺序）
local markdown_formatters = { "prettier", "markdownlint-cli2", "markdown-toc" }

--- 只在 buffer 里已存在 markdownlint 诊断时才跑（LazyVim 同款逻辑）
local function has_markdownlint_diagnostic(_, ctx)
  local diag = vim.tbl_filter(function(d)
    return d.source == "markdownlint" or d.source == "markdownlint-cli2"
  end, vim.diagnostic.get(ctx.buf))
  return #diag > 0
end

--- 只有存在 <!-- toc --> 标记时才跑（LazyVim 同款逻辑）
local function has_toc_marker(_, ctx)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false)) do
    if line:find("<!%-%- toc %-%->") then
      return true
    end
  end
  return false
end

return {
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      if not features.format then
        return
      end

      opts.formatters = opts.formatters or {}
      opts.formatters["markdown-toc"] = {
        condition = function(_, ctx)
          if vim.fn.executable("markdown-toc") == 0 then
            return false
          end
          return has_toc_marker(_, ctx)
        end,
      }
      opts.formatters["markdownlint-cli2"] = {
        condition = function(_, ctx)
          if vim.fn.executable("markdownlint-cli2") == 0 then
            return false
          end
          return has_markdownlint_diagnostic(_, ctx)
        end,
      }

      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.markdown = markdown_formatters
    end,
  },
}
