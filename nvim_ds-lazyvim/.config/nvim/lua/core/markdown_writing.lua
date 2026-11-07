-- Markdown 写作增强（纯设置，不依赖任何插件）
--
-- 由 init.lua 的 FileType markdown 自动命令调用，对每个 markdown buffer 生效。
-- 开关在 core/markdown_features.lua，按键在 keymap/markdown.lua。
local M = {}

--- 切换当前窗口的拼写检查（按键 <leader>us）
--- @return boolean enabled 切换后的状态
function M.toggle_spell()
  local features = require("core.markdown_features")
  local enabled = not vim.wo.spell
  vim.wo.spell = enabled
  if enabled then
    vim.opt_local.spelllang = features.spelllang
    -- 中文句子没有「句首大写」的概念，留着 spellcapcheck 会一直误报
    vim.opt_local.spellcapcheck = ""
  end
  return enabled
end

function M.setup()
  local features = require("core.markdown_features")
  if not features.writing then
    return
  end

  -- ── 软换行 ──
  -- options.lua 已按 *.md / *.txt 开了 wrap，这里按 filetype 再兜一层，
  -- 覆盖没有扩展名的 README，以及 .markdown / .mdown 之类的写法。
  vim.opt_local.wrap = true -- 长段落按窗口宽度折行（只影响显示，不写入文件）
  vim.opt_local.linebreak = true -- 只在空格/标点处折行，不在单词中间断开
  vim.opt_local.breakindent = true -- 折行后的续行保持缩进

  -- 保持 textwidth = 0：不往文件里写硬换行，一个段落始终是一整行。
  -- 想改成「按 80 列硬折行」（Git 风格 Markdown 的常见做法），启用下面两行：
  --   vim.opt_local.textwidth = 80
  --   vim.opt_local.formatoptions:add("t")
  -- 注意硬折行与 conform 里的 prettier 会互相打架，同时用建议去掉 prettier。
  vim.opt_local.textwidth = 0

  -- ── 拼写检查 ──
  if features.spell then
    vim.wo.spell = true
    vim.opt_local.spelllang = features.spelllang
    vim.opt_local.spellcapcheck = ""
  end
end

return M
