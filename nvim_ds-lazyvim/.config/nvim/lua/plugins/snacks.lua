-- snacks.nvim —— LazyVim 的核心工具库（清单里的 A3）
--
-- LazyVim 把 snacks 当"QoL 大礼包"：通知、输入框、终端、大文件、平滑滚动、
-- 选择器、文件浏览器、dashboard、indent 参考线……全都塞在一个插件里。
--
-- 本配置已经有自己的一整套 UI（telescope / neo-tree / alpha-nvim /
-- indent-blankline / vim-illuminate），所以这里**只开不打架的部分**，
-- 功能重叠的那几个全部显式关掉，并在注释里写了怎么换成 snacks 版本。
--
-- 加载方式与 LazyVim 一致：priority = 1000 + lazy = false。
-- 必须启动就加载，因为 notifier / bigfile / quickfile 要在早期挂钩子。
return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      -- ─── 开启：与你现有插件不冲突的能力 ───
      bigfile = { enabled = true }, -- 大文件自动降级（关语法/treesitter 等）
      bufdelete = { enabled = true }, -- 删 buffer 但不打乱窗口布局
      git = { enabled = true }, -- git 工具（blame 当前行等）
      gitbrowse = { enabled = true }, -- 在浏览器打开当前文件/分支/提交
      input = { enabled = true }, -- 更好看的 vim.ui.input
      lazygit = { enabled = true }, -- 浮窗 lazygit（本机已装 /usr/bin/lazygit）
      notifier = { enabled = true }, -- 好看的通知，取代默认消息区
      quickfile = { enabled = true }, -- 启动时先出文件内容，再慢慢加载插件
      rename = { enabled = true }, -- 改文件名时联动 LSP 重命名（neo-tree 也能吃到）
      scope = { enabled = true }, -- 高亮当前代码作用域
      scratch = { enabled = true }, -- 临时草稿 buffer
      scroll = { enabled = true }, -- 平滑滚动（不习惯就改 false）
      terminal = { enabled = true }, -- 浮窗 / 分屏终端
      picker = {
        enabled = true, -- 让 :lua Snacks.picker.files() 可用；<leader>ff 等仍走 telescope
        ui_select = true, -- vim.ui.select 换成 snacks 的模糊选择（想保留原生改 false）
      },

      -- ─── 显式关闭：与你已有插件重叠，避免两套 UI 同时生效 ───
      -- 有 indent-blankline 缩进线了；它的默认值是 enabled = true，必须显式关。
      -- 想改用 snacks 的：这里改 true，并删掉 lua/plugins/ui.lua 里的 indent-blankline。
      indent = { enabled = false },
      -- 有 vim-illuminate 高亮光标下相同的词了；snacks.words 做的是同一件事。
      words = { enabled = false },
      -- 你没用 statuscolumn（options.lua 里是 signcolumn = "yes"）；
      -- 开启会让数字/符号列换成 snacks 的排版，属于观感大改，保持关闭。
      statuscolumn = { enabled = false },
      -- 有 alpha-nvim 启动页；两者都会在 VimEnter 抢首页，必须关一个。
      dashboard = { enabled = false },
      -- 有 neo-tree 了；而且 snacks 的 explorer 默认 replace_netrw = true，
      -- 会顶掉 lazy_setup.lua 里特意保留的 netrw 兜底，所以整个模块关掉。
      -- 想用 snacks explorer：改 true，并按需设 replace_netrw = false。
      explorer = { enabled = false },
      -- 说明：dim（聚焦当前作用域、变暗其余部分）是 opt-in 模块，
      -- 没有 enabled 开关、也不会自动生效，所以这里不配置。
    },
    keys = {
      {
        "<leader>n",
        function()
          Snacks.notifier.show_history()
        end,
        desc = "通知历史",
      },
      {
        "<leader>un",
        function()
          Snacks.notifier.hide()
        end,
        desc = "清空所有通知",
      },
      {
        "<leader>bd",
        function()
          Snacks.bufdelete()
        end,
        desc = "删除当前 buffer",
      },
      {
        "<leader>gg",
        function()
          Snacks.lazygit()
        end,
        desc = "Lazygit",
      },
      {
        "<leader>gb",
        function()
          Snacks.git.blame_line()
        end,
        desc = "Git: 当前行 blame",
      },
      {
        "<leader>gB",
        function()
          Snacks.gitbrowse()
        end,
        desc = "Git: 在浏览器打开",
      },
      {
        "<leader>uz",
        function()
          Snacks.zen()
        end,
        desc = "Zen 模式（专注写作）",
      },
      {
        "<leader>.",
        function()
          Snacks.scratch()
        end,
        desc = "临时草稿 buffer",
      },
      {
        "<leader>S",
        function()
          Snacks.scratch.select()
        end,
        desc = "选择草稿 buffer",
      },
      {
        "<C-/>",
        function()
          Snacks.terminal()
        end,
        desc = "终端开关",
      },
    },
  },
}
