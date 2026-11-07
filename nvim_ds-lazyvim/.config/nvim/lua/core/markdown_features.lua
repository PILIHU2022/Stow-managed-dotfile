-- Markdown 写作模块总开关
--
-- 这里集中控制 lua/plugins/markdown/ 下每个子模块的启停：
--   false -> 对应插件完全不加载（不下载、不注册按键、不报错）
-- 想彻底删掉某个模块，直接删 lua/plugins/markdown/ 下对应的 .lua 文件也可以。
--
-- 生效时机：启动 nvim 时读取，改完重启即可。
return {
  -- ── 插件类 ──

  -- MeanderingProgrammer/render-markdown.nvim（LazyVim lang.markdown 的核心）
  -- 编辑时就把 markdown 渲染出来：标题、列表符号、引用竖线、代码块边框、表格对齐。
  -- 光标所在行始终显示原文，所以不影响编辑。
  render = true,

  -- iamcco/markdown-preview.nvim
  -- 浏览器实时预览，支持滚动同步。按键 <leader>cp / <C-k> / <C-m>。
  preview = true,

  -- stevearc/conform.nvim 的 markdown 扩展（本模块只做扩展，不引入新插件）
  -- 保存时依次执行：prettier -> markdownlint-cli2 --fix -> markdown-toc
  -- 后两个命令不存在时自动跳过，不会报错。
  -- 关掉它也不影响原有的 prettier 格式化（那条在 lua/plugins/conform.lua 里）。
  format = true,

  -- mfussenegger/nvim-lint + markdownlint-cli2
  -- 写作规范检查，需要系统里有 markdownlint-cli2 命令，没有则静默跳过。
  lint = true,

  -- Kicamon/markdown-table-mode.nvim
  -- 输入 | 时自动补齐表格、自动对齐。
  table = true,

  -- ── 设置类 ──

  -- 纯设置型写作增强（软换行、折行缩进、formatoptions 等）
  -- 见 lua/core/markdown_writing.lua
  writing = true,

  -- 打开 markdown 时自动开启拼写检查。
  -- 默认 false：本机 Neovim runtime 只带 en 词表、没有 cjk 词表，
  -- 一开启所有中文词都会被标成拼写错误。需要时用 <leader>us 手动开关。
  spell = false,

  -- 拼写检查语言（只在 spell / <leader>us 打开时生效）。
  -- 只有 en 词表时保持 { "en" }；
  -- 另装了 cjk 词表后可改成 { "en", "cjk" }（只写 "cjk" 会连英文都不检查）。
  spelllang = { "en" },
}
