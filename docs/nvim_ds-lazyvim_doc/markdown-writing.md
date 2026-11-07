# Markdown 写作模块

本目录（`~/.config/nvim/lua/plugins/markdown/`）整合了原配置里的 Markdown 插件，
并补齐了 LazyVim `lang.markdown` extra 提供的写作插件。

## 一、模块结构

| 文件 | 作用 | 来源 |
|:--|:--|:--|
| `lua/plugins/markdown/render.lua` | **render-markdown.nvim**：编辑时把标题/列表/引用/代码块/表格渲染出来（不改文件内容，光标行显示原文） | LazyVim `lang.markdown` 新增 |
| `lua/plugins/markdown/preview.lua` | **markdown-preview.nvim**：浏览器实时预览 | 原 `lua/plugins/markdown-preview.lua` 迁入，并改用 LazyVim 的安装方式 |
| `lua/plugins/markdown/format.lua` | **conform.nvim** 的 markdown 格式化链：`prettier` → `markdownlint-cli2 --fix` → `markdown-toc` | LazyVim `lang.markdown` 新增 |
| `lua/plugins/markdown/lint.lua` | **nvim-lint + markdownlint-cli2**：保存/离开插入模式时做规范检查 | LazyVim `lang.markdown` 新增 |
| `lua/plugins/markdown/table.lua` | **markdown-table-mode.nvim**：输入 `\|` 自动补齐并对齐表格 | 原 `lua/plugins/markdown-table-mode.lua` 迁入，逻辑未改 |

配套的非插件部分：

| 文件 | 作用 |
|:--|:--|
| `lua/core/markdown_features.lua` | **总开关**：每个子模块一个布尔值，`false` 就完全不加载 |
| `lua/core/markdown_writing.lua` | 纯设置型写作增强：软换行、折行缩进、`textwidth`、拼写检查 |
| `lua/keymap/markdown.lua` | markdown buffer 内按键（原有中文标点映射 + `<leader>us`） |
| `init.lua` | `FileType markdown` 时依次调用上面两个模块 |
| `lua/lazy_setup.lua` | `{ import = "plugins.markdown" }` |

> `lazy.nvim` 的 `import` **不会递归子目录**。所以 `lua/plugins/markdown/` 必须在
> `lazy_setup.lua` 里单独 import 一次，见文件里的注释。

## 二、怎么开关 / 增删

1. **临时关闭某个模块**：把 `lua/core/markdown_features.lua` 里对应项改成 `false`，重启 nvim。
   对应插件完全不加载，不会下载、不会注册按键、不会报错。
2. **永久移除某个模块**：删掉 `lua/plugins/markdown/` 下对应的 `.lua` 文件即可，其它模块不受影响。
3. **新增一个 markdown 插件**：在 `lua/plugins/markdown/` 下新建 `.lua`，返回一个 lazy spec 表，
   并在 `lua/core/markdown_features.lua` 里加一个开关。

## 三、按键

| 按键 | 模式 | 作用 |
|:--|:--|:--|
| `<leader>um` | n | 行内渲染开关（render-markdown），来自 LazyVim |
| `<leader>cp` | n | 浏览器预览开关，来自 LazyVim |
| `<leader>us` | n | 拼写检查开关（默认关闭，见下） |
| `<C-k>` / `<C-m>` | n | 浏览器预览开关（本配置原有键位） |
| `[[` / `]]` | n | 上一个 / 下一个标题（Neovim 0.12 `ftplugin/markdown.lua` 自带） |
| `gO` | n | 当前文档标题大纲（同上，自带） |
| `,1` … `,5` | i | 一至五级标题 |
| `,b` `,s` `,h` `,i` `,d` `,c` `,m` `,p` `,a` `,l` `,t` | i | 粗体 / 删除线 / 高亮 / 斜体 / 行内代码 / 代码块 / 列表 / 图片 / 链接 / 分隔线 / `[toc]` |
| `《` `》` `（` `“` `”` | i | 中文全角标点自动成对 |

## 四、外部命令依赖

| 命令 | 用途 | 现状 | 安装 |
|:--|:--|:--|:--|
| `prettier` | markdown 格式化（主力） | ✅ 已装 | `npm i -g prettier` |
| `markdownlint-cli2` | 写作规范检查 + 自动修复 | ❌ 未装 | `npm i -g markdownlint-cli2 markdownlint-cli2-formatter-default` |
| `markdown-toc` | 刷新 `<!-- toc -->` 目录 | ❌ 未装 | `npm i -g markdown-toc` |
| `marksman` | markdown 语言服务器（补全/跳转/重命名标题） | ✅ 已装 | 发行版包管理器 |

缺哪个命令，用到它的那一步就会**自动跳过**，不会报错：

- `lint.lua`：`vim.fn.executable("markdownlint-cli2") == 0` 时直接不检查。
- `format.lua`：两个 formatter 的 `condition` 里都带 `executable` 判断。
- `marksman`：由 `lua/plugins/lsp.lua` 的 `servers.marksman = {}` 统一启用，本模块未改动它。

不想用 npm 全局安装，也可以加装 `mason.nvim`，在 `ensure_installed` 里写
`{ "markdownlint-cli2", "markdown-toc" }`，参考 LazyVim 的 `lang.markdown` extra。

## 五、与 LazyVim `lang.markdown` extra 的差异

| LazyVim 做法 | 本配置做法 | 原因 |
|:--|:--|:--|
| 用 `mason.nvim` 保证 `markdownlint-cli2` / `markdown-toc` 存在 | 不引入 mason，改为 `executable` 判断 + 文档说明 | 本配置所有格式化工具（stylua/prettier/clang-format/ruff…）都走系统命令，保持一致 |
| `<leader>um` 用 `Snacks.toggle` 实现 | 用 `require("render-markdown").toggle()` | 本配置没有 snacks.nvim |
| 注册 `markdown.mdx` 文件类型 | 未注册 | 只有写 MDX 才需要；要的话在 `lua/core/markdown_writing.lua` 里加 `vim.filetype.add({ extension = { mdx = "markdown.mdx" } })`，并把它加进各模块的 `ft` |
| `render-markdown` 的 `opts` 与 LazyVim 一致 | 一致（`code` / `heading` / `checkbox` 三项） | 保持同步，改起来方便对比 |

## 六、已知注意事项

1. **拼写检查默认关闭**：本机 Neovim runtime 只带 `en` 词表，没有 `cjk` 词表。
   一开启，所有中文词都会被标成拼写错误。需要时用 `<leader>us` 手动开关；
   装了 cjk 词表后把 `lua/core/markdown_features.lua` 的 `spelllang` 改成 `{ "en", "cjk" }`。
2. **`<C-m>` 等于 `<CR>`**：`lua/keymap/markdown.lua` 里把 `<C-m>` 映射成了预览开关，
   这在终端里和回车是同一个键码，会顶掉 markdown buffer 里普通模式的回车。
   建议只用 `<C-k>` 或 LazyVim 风格的 `<leader>cp`，`<C-m>` 那行可以直接删。
3. **表格被两个插件同时处理**：`markdown-table-mode` 负责输入时补齐，
   `render-markdown` 负责显示成对齐表格。觉得太吵就在
   `lua/plugins/markdown/render.lua` 里打开 `pipe_table = { enabled = false }`。
4. **`prettier` 与硬折行冲突**：本模块保持 `textwidth = 0`（段落不写死换行，靠软换行显示）。
   若要改成 80 列硬折行，见 `lua/core/markdown_writing.lua` 里的注释，
   同时应把 `format.lua` 的 `prettier` 去掉。
5. **`nvim-treesitter` 配置与 main 分支**：`lazy-lock.json` 锁的是 `nvim-treesitter` 的
   `main` 分支，而 `lua/plugins/treesitter.lua` 用的是旧版 `ensure_installed` / `highlight` 写法。
   这个问题**不影响本模块**：Neovim 0.12 内置了 `markdown` / `markdown_inline` 解析器，
   且 `ftplugin/markdown.lua` 会自动 `vim.treesitter.start()`，render-markdown 正常工作。
   但如果哪天想整理 treesitter 配置，这里是个待办。

## 七、怎么验证改动没坏

不安装任何插件、只验证 spec 能否被正确解析（需要一份 `lazy.nvim`）：

```bash
cd ~/.config/nvim
# 1. 语法/格式
stylua --check lua/plugins/markdown lua/core/markdown_features.lua lua/core/markdown_writing.lua

# 2. 起一个 nvim，看有没有 spec 报错
nvim --headless -c 'lua print(vim.inspect(vim.tbl_keys(require("lazy.core.config").plugins)))' -c 'qa!'
```

也可以用 `:Lazy` 看 `render-markdown.nvim` / `nvim-lint` 是否出现、`:checkhealth render-markdown` 看解析器是否就绪。
