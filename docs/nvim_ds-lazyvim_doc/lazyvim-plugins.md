# LazyVim 插件清单（供选装参考）

本文用于**挑选**：把 LazyVim 的插件按「核心插件」和「extras」两大类列出，附一句话说明和
本配置的现状。挑好后告诉我编号/名字，我再按 markdown 模块一样的方式模块化加进来。

- 来源：`LazyVim/LazyVim` 的 `main` 分支（`lua/lazyvim/plugins/**`）+ <https://www.lazyvim.org/extras>，
  抓取时间 2026-10。LazyVim 本身没被本配置 import，本文只是"能力清单"。
- 本配置是**纯 lazy.nvim**（不是 LazyVim 发行版），所以下面每一项都要单独搬过来。

## 状态图例

| 标记 | 含义 |
|:--|:--|
| ✅ 已有 | 这个插件本配置已经装了 |
| ➕ 需装 | 本配置没有，选它就会新增一个插件 |
| 仅配置 | 这个 extra **不引入新插件**，只是给已有的 `nvim-lspconfig` / `conform` 等加配置，可以随时加 |
| 部分 | 一半已有 |

> 说明：`lang.*` 类 extra 绝大多数属于「仅配置」——它们只是给 `nvim-lspconfig` 加
> `servers.xxx = {}`、给 treesitter 加解析器、给 conform 加 formatter。所以下面
> 很多语言支持其实是"免费"的，缺的只是那一行 server 配置。

---

## A. 核心插件（30 个）

这一组是 LazyVim 作为"发行版"的地基，也是决定"要不要更像 LazyVim"的主要选项。

| # | 插件 | 作用 | 现状 |
|:--|:--|:--|:--|
| A1 | `folke/lazy.nvim` | 插件管理器本身 | ✅ 已有 |
| A2 | `LazyVim/LazyVim` | LazyVim 发行版本体（默认插件集 + 配置 + Lua 工具库） | ➕ 需装 |
| A3 | `folke/snacks.nvim` | LazyVim 的万能工具库：选择器、文件浏览器、dashboard、终端、通知、缩进、git 等 | ✅ **本次已装**（`lua/plugins/snacks.lua`；重叠的 indent/words/statuscolumn/dashboard/explorer 已显式关闭） |
| A4 | `nvim-mini/mini.pairs` | 输入左括号/引号时自动补右半边 | ✅ 已有（mini.nvim 里的 `mini.pairs` 已启用） |
| A5 | `folke/ts-comments.nvim` | 一门语言多种注释符时也能正确注释 | ⛔ **不需要**（mini.comment 已是 treesitter 感知 + 0.12 原生 gc，详见下方附注） |
| A6 | `nvim-mini/mini.ai` | 增强 `a`/`i` 文本对象：函数、参数、引号、块、数字 | 部分（mini.nvim 已装，但只启用了 comment/pairs/surround） |
| A7 | `folke/lazydev.nvim` | 编辑 Neovim 配置时给 LuaLS 补类型 | ✅ 已有 |
| A8 | `folke/tokyonight.nvim` | tokyonight 主题 | ✅ 已有（备用主题） |
| A9 | `catppuccin/nvim` | catppuccin 主题 + 大量插件集成高亮 | ✅ 已有（当前主题） |
| A10 | `akinsho/bufferline.nvim` | 顶部缓冲区标签栏 | ✅ 已有 |
| A11 | `MagicDuck/grug-far.nvim` | 跨文件搜索替换（带预览、可按扩展名过滤） | ➕ 需装 |
| A12 | `folke/flash.nvim` | 搜索跳转：匹配处显示标签，`s`/`S`/`r`/`R` 直接跳 | ➕ 需装 |
| A13 | `folke/which-key.nvim` | 键位提示与分组说明 | ✅ 已有 |
| A14 | `lewis6991/gitsigns.nvim` | git 增删改标记、hunk 暂存/重置/预览/blame | ✅ 已有 |
| A15 | `folke/trouble.nvim` | 诊断/符号/LSP/quickfix 列表面板 | ➕ 需装 |
| A16 | `folke/todo-comments.nvim` | TODO/FIXME/HACK 高亮与跳转 | ✅ 已有 |
| A17 | `nvim-lualine/lualine.nvim` | 状态栏 | ✅ 已有 |
| A18 | `folke/noice.nvim` | 重做消息/cmdline/补全菜单 UI | ➕ 需装 |
| A19 | `nvim-mini/mini.icons` | 图标库（并 mock `nvim-web-devicons`） | ✅ 已有 |
| A20 | `MunifTanjim/nui.nvim` | UI 组件库（noice 等的依赖） | ✅ 已有 |
| A21 | `folke/persistence.nvim` | 会话保存/恢复 | ✅ 已有 |
| A22 | `nvim-lua/plenary.nvim` | Lua 函数库，多个插件的公共依赖 | ✅ 已有 |
| A23 | `nvim-treesitter/nvim-treesitter` | treesitter 高亮/缩进/折叠/解析器安装 | ✅ 已有（注意锁的是 main 分支，见下） |
| A24 | `nvim-treesitter/nvim-treesitter-textobjects` | 基于 treesitter 的文本对象与移动键位 | ✅ 已有 |
| A25 | `windwp/nvim-ts-autotag` | 自动补全/重命名 HTML、JSX 闭合标签 | ➕ 需装 |
| A26 | `stevearc/conform.nvim` | 格式化入口 | ✅ 已有 |
| A27 | `mfussenegger/nvim-lint` | 异步 linter 接入 `vim.diagnostic` | ✅ **本次同步新增**（markdown 模块的 `lint.lua`） |
| A28 | `mason-org/mason.nvim` | LSP/linter/formatter 的可视化安装器 | ➕ 需装 |
| A29 | `mason-org/mason-lspconfig.nvim` | mason 与 nvim-lspconfig 的桥接 | ➕ 需装 |
| A30 | `neovim/nvim-lspconfig` | LSP 客户端配置与各语言 server 默认值 | ✅ 已有 |

**关于 A28/A29（mason）**：装它最大的好处是能一条命令装上本次 markdown 同步缺的两个二进制——
`markdownlint-cli2` 和 `markdown-toc`。不想引入 mason 的话，直接
`npm i -g markdownlint-cli2 markdown-toc` 效果一样（本配置的 markdown 模块会自动识别）。

**关于 A23（treesitter）**：`lazy-lock.json` 锁的是 `main` 分支，而 `lua/plugins/treesitter.lua`
写的是旧版 `ensure_installed` / `highlight` 配置。markdown 不受影响（Neovim 0.12 内置了
`markdown`/`markdown_inline` 解析器），但其它语言的高亮/解析器安装可能是失效的，值得单独整理。

### 附注：ts-comments.nvim（A5）到底要不要装？

**结论：不需要。** 本配置现有的注释能力已经覆盖了它的主诉求。核实时间 2026-10，依据是
Neovim 0.12 本机 runtime 源码 + ts-comments.nvim `main` 分支源码 + 本机实测。

**已经在手的两个来源**

| 来源 | 提供什么 |
|:--|:--|
| `lua/utils/mini-nvim.lua` → `require("mini.comment").setup()` | `gc` / `gcc` / `gc` 文本对象 |
| Neovim 0.12 原生（`runtime/lua/vim/_comment.lua` + `lua/vim/_core/defaults.lua`） | 同样的 `gc` / `gcc` / `gc` 文本对象；当前被 mini.comment 的 buffer-local 映射覆盖，功能重复但**不冲突** |

关键点：**mini.comment 本身就做 treesitter 感知的 commentstring 解析**。
`MiniComment.get_commentstring()` 会遍历 LanguageTree，取嵌套语言（markdown 代码块、
vue 的 `<script>`/`<style>`）对应的 `commentstring`；Neovim 原生 `_comment.lua` 用的是同一套算法
（mini 的源码注释直接引用了相同的两个 neovim PR）。所以「让注释符用对」这个核心卖点，
本配置**现在就有**，不需要 ts-comments。

**本机实测** `vim.filetype.get_option(ft, "commentstring")`：

| 文件 | ft | commentstring | 说明 |
|:--|:--|:--|:--|
| `hyprland.conf` | `hyprlang` | `# %s` | 0.12 已内置 hyprlang，不依赖 ts-comments 的语言表 |
| `App.vue` | `vue` | `<!-- %s -->` | `<script>` 段由注入语言解析为 `// %s` |
| `note.md` | `markdown` | `<!-- %s -->` | 代码块内同理取内层语言 |
| `comp.jsx` | `javascriptreact` | `// %s` | ⚠️ **唯一的真缺口**：JSX 元素内应该用 `{/* %s */}` |

**ts-comments 真正多出来的东西**

它替换的是 `vim.filetype.get_option`，并在 `M.get()` 里读**当前行内容**，在多个候选注释符中
挑匹配的那一个（实现见其 `lua/ts-comments/config.lua` 与 `lua/ts-comments/comments.lua`；
节点类型由 `M.resolve()` 经 `vim.treesitter` 解析）。因此只有三点增益：

1. JSX/TSX 元素内用 `{/* %s */}`（原生与 mini.comment 都只会给 `// %s`）
2. 同一语言多套注释符 + 宽松取消注释（如 Haskell 的 `--` / `{- -}`、Clojure 的 `;;` / `;`）；
   原生只按当前上下文的同一个注释符做「精确 / 去空白」两种匹配
3. 按 treesitter 节点类型指定注释符

因为它 hook 的是 `get_option`，而 mini.comment 也是通过 `get_option` 取值的，
所以**真要装的话 mini.comment 也能吃到**，只需加插件、不必改动 mini.comment。

**什么时候值得装**：经常写 JSX/TSX，或者觉得 `gc` 取消注释太挑剔（必须同一种注释符）。
否则保持现状即可。

> 可选清理：如果想让注释完全走 Neovim 原生（统一 `gc` 行为），把 `lua/utils/mini-nvim.lua` 改成
> `require("mini.comment").setup({ mappings = { comment = "", comment_line = "", comment_visual = "", textobject = "" } })`
> 关掉 mini.comment 的映射即可。

---

## B. 与写作 / Markdown / 笔记直接相关的 extras（9 个）

| extra | 带来什么 | 现状 |
|:--|:--|:--|
| `lang.markdown` | 完整 markdown 写作链路：marksman LSP、render-markdown.nvim、markdown-preview.nvim、conform（prettier → markdownlint-cli2 → markdown-toc）、nvim-lint 或 none-ls、mason 装二进制。键位 `<leader>um`（行内渲染）、`<leader>cp`（浏览器预览） | 部分 → **本次已同步主体**（render / preview / format / lint 四个模块）。仍缺：mason 装二进制（可用 npm 替代）、none-ls（已有 nvim-lint，不需要）、`markdown.mdx` 文件类型 |
| `lang.tex` | texlab LSP + vimtex + `bibtex`/`latex` 解析器（并刻意禁用 treesitter 的 latex 高亮，避免与 vimtex 打架），`vimtex_mappings_disable` 关掉 `K` | ✅ 已有（vimtex + texlab 都已装；本配置还把 vimtex 前缀改成了 `<leader>v`） |
| `lang.typst` | tinymist LSP + typst-preview.nvim 实时预览 + typstyle 格式化 | 部分（conform/treesitter 已有，tinymist 与 typst-preview 需装） |
| `ai.avante` | 编辑器内 AI 结对编程（聊天/对选区 apply-edit），回答用 markdown 渲染，支持截图粘贴进对话 | 部分（nui、blink.cmp 已有；avante、img-clip 需装） |
| `ai.claudecode` | 把 Claude Code 接进 Neovim：切会话、把缓冲/选区作为上下文、在编辑器内接受或拒绝 diff | ➕ 需装 |
| `ai.copilot-chat` | 开一个 markdown 聊天缓冲与 Copilot 对话，可让它按 prompt 解释/改稿 | 部分（blink.cmp 已有；CopilotChat、edgy 需装） |
| `ai.sidekick` | 集成 AI CLI（Claude Code/Codex）+ Copilot 的 next-edit-suggestions，lualine 显示状态 | 部分（lspconfig、lualine 已有；sidekick、snacks 需装） |
| `lsp.none-ls` | null-ls 的社区 fork，用 LSP 机制跑格式化/lint 源（markdownlint、prettier、stylua…），优先级高于 conform，装上后会**接管**格式化 | ➕ 需装（本配置已有 conform + nvim-lint，功能重叠，不建议同时上） |
| `util.octo` | 在 Neovim 内浏览/编写 GitHub issue 与 PR，正文就是 markdown 缓冲区 | ➕ 需装 |

### B1. 写作相关、非插件的 LazyVim 设置（可直接抄）

| 位置 | LazyVim 原文 | 说明 |
|:--|:--|:--|
| `options.lua:59` | `opt.conceallevel = 2` | 隐藏 `**粗体**`/`*斜体*` 的标记，但不隐藏带替换的标记 |
| `options.lua:75` | `opt.formatoptions = "jcroqlnt"` | `q` 允许 `gq`、`n` 识别列表编号、`t` 按 textwidth 折行等 |
| `options.lua:82` | `opt.linebreak = true` | 在单词边界折行，而不是任意字符处 |
| `options.lua:96` | `opt.sidescrolloff = 8` | 横向留 8 列上下文 |
| `options.lua:101` | `opt.spelllang = { "en" }` | 只设语言；`spell` 默认仍是关的 |
| `options.lua:112` | `opt.virtualedit = "block"` | 块选可越过行尾（改表格方便） |
| `options.lua:117-118` | `vim.g.markdown_recommended_style = 0` | 关掉 Neovim 的 markdown 推荐风格，别自动塞 4 空格缩进 |
| `autocmds.lua:102-110` | `FileType {text, plaintex, typst, gitcommit, markdown}` → `opt_local.wrap = true` + `opt_local.spell = true` | LazyVim 唯一的 markdown 专属 autocmd：开软换行**并开拼写**。注意它直接开 `spell`——LazyVim 用户默认有 cjk 词表问题同样存在，本配置因此改成默认关、`<leader>us` 手动开 |

> LazyVim **没有**设置 `textwidth`（保持 0），换行完全靠 `wrap` + `linebreak`；也没有 markdown 专属 keymap。
> 这与本配置现在 `lua/core/markdown_writing.lua` 的做法一致。

---

## C. 其余 extras（106 个，按类别，一行一个）

### C1. ai（4）

| extra | 作用 | 现状 |
|:--|:--|:--|
| `ai.codeium` | Codeium 免费 AI 补全 | 部分 |
| `ai.copilot` | GitHub Copilot 行内建议 | 部分 |
| `ai.copilot-native` | Neovim 0.12+ 原生 Copilot LSP 补全（无需第三方插件） | ✅ 仅配置 |
| `ai.supermaven` | Supermaven 极速补全 | 部分 |
| `ai.tabnine` | Tabnine 补全 | 部分 |

### C2. coding（8）

| extra | 作用 | 现状 |
|:--|:--|:--|
| `coding.blink` | blink.cmp 补全引擎 | ✅ 已有 |
| `coding.luasnip` | LuaSnip 片段 + friendly-snippets | 部分 |
| `coding.mini-comment` | mini.comment 注释/取消注释 | 部分 |
| `coding.mini-snippets` | mini.snippets 片段管理（替代 LuaSnip） | 部分 |
| `coding.mini-surround` | mini.surround 增删改环绕 | ✅ 已有 |
| `coding.neogen` | 生成函数文档注释骨架 | ➕ 需装 |
| `coding.nvim-cmp` | nvim-cmp 补全引擎（blink 的替代） | 部分 |
| `coding.yanky` | 剪贴板历史/ring，可回看粘贴 | ➕ 需装 |

### C3. dap / test（3）

| extra | 作用 | 现状 |
|:--|:--|:--|
| `dap.core` | nvim-dap + dap-ui + dap-virtual-text，断点调试 | ➕ 需装 |
| `dap.nlua` | 调试 Neovim 自身的 Lua 代码 | ➕ 需装 |
| `test.core` | neotest + nvim-dap 测试框架（需配语言适配器） | ➕ 需装 |

### C4. editor（18）

| extra | 作用 | 现状 |
|:--|:--|:--|
| `editor.aerial` | 符号大纲侧栏 | 部分 |
| `editor.dial` | 增强 `Ctrl-a`/`Ctrl-x`：日期、十六进制、布尔 | ➕ 需装 |
| `editor.fzf` | fzf-lua 选择器（telescope 的替代） | 部分 |
| `editor.harpoon2` | 常用文件标记与快速跳转 | ➕ 需装 |
| `editor.illuminate` | 高亮当前词的其他出现 | ✅ 已有 |
| `editor.inc-rename` | LSP 重命名实时预览 | 部分 |
| `editor.leap` | leap 跳转，增强 `f`/`t`（会禁用 flash） | 部分 |
| `editor.mini-diff` | mini.diff 缓冲区 diff 与 hunk 管理 | 部分（mini.nvim 已装未启用） |
| `editor.mini-files` | mini.files 列式文件浏览器 | 部分（mini.nvim 已装未启用） |
| `editor.mini-move` | mini.move 移动行/选区 | 部分（mini.nvim 已装未启用） |
| `editor.navic` | winbar 显示 LSP 上下文面包屑 | 部分 |
| `editor.neo-tree` | neo-tree 文件浏览器 | ✅ 已有 |
| `editor.outline` | 符号大纲侧栏 | ➕ 需装 |
| `editor.overseer` | 任务运行器（构建/测试任务管理） | 部分 |
| `editor.refactoring` | 提取函数/变量等重构 | ➕ 需装 |
| `editor.snacks_explorer` | snacks 的文件浏览器 | ➕ 需装 |
| `editor.snacks_picker` | snacks 选择器（设 `vim.g.lazyvim_picker = "snacks"`） | 部分 |
| `editor.telescope` | telescope + fzf-native + dressing | 部分（telescope 已有，dressing 缺） |

### C5. formatting / linting / lsp（4）

| extra | 作用 | 现状 |
|:--|:--|:--|
| `formatting.black` | conform + mason 启用 Python black | 部分（black 已在 conform 里配了） |
| `formatting.prettier` | conform + mason 启用 prettier | 部分（prettier 已在用） |
| `linting.eslint` | 通过 nvim-lspconfig 启用 eslint LSP | ✅ 仅配置 |
| `lsp.neoconf` | 读取项目级 `.neoconf.json` 的 LSP 设置 | 部分 |

### C6. lang（50，除 B 节的 markdown/tex/typst）

| extra | 作用 | 现状 |
|:--|:--|:--|
| `lang.angular` | Angular 模板 LSP + 解析器 | 仅配置 |
| `lang.ansible` | ansiblels + 语法支持 | 部分 |
| `lang.astro` | Astro LSP + 解析器 | 仅配置 |
| `lang.clangd` | clangd + clangd_extensions | 部分（clangd 已启用） |
| `lang.clojure` | conjure REPL + paredit | 部分 |
| `lang.cmake` | cmake LSP + cmake-tools | 部分 |
| `lang.dart` | dartls + 格式化 + 测试 | 部分 |
| `lang.docker` | dockerls + hadolint | 部分 |
| `lang.dotnet` | omnisharp 等 + 测试 + 调试 | 部分 |
| `lang.elixir` | elixirls + credo + 测试 | 部分 |
| `lang.elm` | elmls + elm-format | 仅配置 |
| `lang.ember` | Ember LSP + 解析器 | 仅配置 |
| `lang.erlang` | erlangls | 仅配置 |
| `lang.git` | gitcommit/gitconfig 解析器 + 提交信息补全 | 部分 |
| `lang.gleam` | gleam LSP + 解析器 | 仅配置 |
| `lang.go` | gopls + goimports/gofumpt + 测试 + 调试 | 部分 |
| `lang.haskell` | hls + haskell-tools + hoogle | 部分 |
| `lang.helm` | helm_ls | 部分 |
| `lang.java` | jdtls + 调试 | 部分 |
| `lang.json` | jsonls + SchemaStore schema 补全 | 部分 |
| `lang.julia` | julials + 补全 | 仅配置 |
| `lang.kotlin` | kotlin LSP + 全套 | 部分 |
| `lang.lean` | lean.nvim（Lean4 定理证明） | 部分 |
| `lang.nix` | nil_ls + nixfmt + lint | 仅配置 |
| `lang.nushell` | nushell LSP + 解析器 | 仅配置 |
| `lang.ocaml` | ocamllsp + 解析器 | 仅配置 |
| `lang.php` | intelephense/phpactor + 调试 + 测试 | 部分 |
| `lang.prisma` | prismals + 解析器 | 仅配置 |
| `lang.python` | ruff/pyright + venv-selector + 调试 + 测试 | 部分（pyright 已启用） |
| `lang.r` | R LSP + R.nvim + 测试 | 部分 |
| `lang.rego` | regal/regols（OPA Rego） | 仅配置 |
| `lang.ruby` | ruby_lsp/solargraph/rubocop + 调试 + 测试 | 部分 |
| `lang.rust` | rustaceanvim + crates.nvim | 部分 |
| `lang.scala` | nvim-metals + 调试 | 部分 |
| `lang.solidity` | solidity_ls + conform | 仅配置 |
| `lang.sql` | sqls + vim-dadbod 数据库客户端 | 部分 |
| `lang.svelte` | svelte LSP + 解析器 | 仅配置 |
| `lang.tailwind` | tailwindcss LSP + 色块补全 | 部分 |
| `lang.terraform` | terraformls + fmt/tflint + 文档扩展 | 部分 |
| `lang.thrift` | thriftls + 解析器 | 仅配置 |
| `lang.toml` | taplo | 仅配置 |
| `lang.twig` | twiggy LSP + conform | 部分 |
| `lang.typescript` | TS 基础：vtsls/tsc 切换 + 调试 | 部分 |
| `lang.typescript.biome` | biome LSP + 格式化/lint | 部分 |
| `lang.typescript.oxc` | oxlint/oxfmt（Rust 实现） | 部分 |
| `lang.typescript.tsc` | tsc/tsgo LSP | 仅配置 |
| `lang.typescript.vtsls` | vtsls（默认 TS server） | 仅配置 |
| `lang.vue` | vue_ls + vtsls | 仅配置 |
| `lang.yaml` | yamlls + SchemaStore（本配置已用 yamlfmt 格式化） | 部分 |
| `lang.zig` | zls + 测试 | 部分 |

### C7. ui（9）

| extra | 作用 | 现状 |
|:--|:--|:--|
| `ui.alpha` | alpha 启动页 | 部分（alpha 已有） |
| `ui.dashboard-nvim` | dashboard-nvim 启动页 | ➕ 需装 |
| `ui.edgy` | 声明式窗口布局（侧栏/底栏管理） | 部分 |
| `ui.indent-blankline` | 缩进参考线 | ✅ 已有 |
| `ui.mini-animate` | mini.animate 动画 | 部分（mini.nvim 已装未启用） |
| `ui.mini-indentscope` | mini.indentscope（与 indent-blankline 二选一） | 部分（同上） |
| `ui.mini-starter` | mini.starter 启动页 | 部分 |
| `ui.smear-cursor` | 光标拖尾动画 | 部分 |
| `ui.treesitter-context` | 顶部固定显示当前函数/类上下文 | ➕ 需装 |

### C8. util / vscode（9）

| extra | 作用 | 现状 |
|:--|:--|:--|
| `util.chezmoi` | 直接编辑 chezmoi 管理的 dotfiles | 部分 |
| `util.dot` | dotfiles 语言支持：为 waybar/hypr/kitty/rofi 等注册 filetype 与解析器 | 部分（对本仓库的 dotfiles 有用） |
| `util.gh` | 在编辑器内评审 GitHub PR | ➕ 需装 |
| `util.gitui` | mason 装 gitui，`<leader>gg` 打开终端 git UI | ➕ 需装 |
| `util.mini-hipatterns` | 高亮色值（含 Tailwind） | 部分（mini.nvim 已装未启用） |
| `util.project` | 项目历史，`<leader>fp` 切换项目 | 部分 |
| `util.rest` | kulala.nvim HTTP/REST 客户端 | 部分 |
| `util.startuptime` | 可视化启动耗时 | ➕ 需装 |
| `vscode` | VS Code + vscode-neovim 集成适配 | ➕ 需装 |

> 注：`util.octo` 见 B 节（与写作/笔记相关）。

---

## D. 我的推荐（按性价比）

**第一档：几乎无副作用，建议加**

| 项 | 理由 |
|:--|:--|
| `mason.nvim` + `mason-lspconfig.nvim`（A28/A29） | 一条命令装齐 `markdownlint-cli2`、`markdown-toc`、`stylua`、各语言 LSP；也可以只用 `npm i -g` 代替 |
| `folke/trouble.nvim`（A15） | 诊断/引用/符号列表，配合已有的 lspsaga 用起来更顺 |
| `nvim-mini/mini.ai`（A6） | mini.nvim 已经在装了，只是多启用一个模块，零新增依赖 |

**第二档：明显提升手感，但要接受行为变化**

| 项 | 权衡 |
|:--|:--|
| `folke/flash.nvim`（A12） | 跳转很快，但会占用 `s`/`S`/`r`/`R`（默认映射），需要重新适应 |
| `MagicDuck/grug-far.nvim`（A11） | 跨文件替换比 `:g/.../s` 友好；`<leader>sr` 目前是空的 |
| `folke/treesitter-context`（`ui.treesitter-context`） | 长文件看上下文很爽，但会让顶部多一行（有 `<leader>ut` 可切） |

**第三档：大改观感，先想清楚再上**

| 项 | 权衡 |
|:--|:--|
| `folke/snacks.nvim`（A3） | LazyVim 的核心工具库，dashboard/picker/终端/通知全都换了；但会和现有的 telescope、alpha、neo-tree 功能重叠，属于"要不要整体转向 LazyVim 风格"的决定 |
| `folke/noice.nvim`（A18） | 消息与 cmdline 界面现代化；会改变所有提示的显示方式 |
| `LazyVim/LazyVim`（A2） | 直接换成 LazyVim 发行版。**注意**：那等于重写整套配置（你的 keymap/lspsaga/neogit/vimtex 等自定义都要重新接），不是"加个插件" |

**不建议**

| 项 | 理由 |
|:--|:--|
| `lsp.none-ls`（B 节） | 与已有 conform.nvim + nvim-lint 功能重叠，而且 none-ls 的优先级更高会**接管**格式化，容易和 `lua/plugins/conform.lua` 打架 |

---

## E. 怎么告诉我你的选择

直接回我编号或名字就行，比如：

- 「装 A15、A11、A6」——我按 `lua/plugins/markdown/` 的方式给它们建独立模块
- 「先装 mason，把 markdownlint-cli2 和 markdown-toc 装上」——我加 `lua/plugins/mason.lua` 并验证
- 「`util.dot` 想加，方便改本仓库的 hypr/waybar 配置」——这个对本仓库确实对口
