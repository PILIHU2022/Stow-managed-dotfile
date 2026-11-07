local map = require("core.keymap_script")

local function setup()
  map.i({
    ["《"] = "《》<Esc>i",
    ["》"] = "> ",
    ["（"] = "（）<Esc>i",
    ["“"] = "“”<Esc>i",
    ["”"] = "“”<Esc>i",
    [",b"] = "****<Esc>F*ha",
    [",s"] = "~~~~<Esc>F~ha",
    [",h"] = "====<Esc>F=ha",
    [",i"] = "**<Esc>F*a",
    [",d"] = "``<++><Esc>F`a",
    [",c"] = "```<Enter><Enter>```<Esc>kA",
    [",m"] = "- [ ] ",
    [",p"] = "![]()<Esc>F[a",
    [",a"] = "[]()<Esc>F[a",
    [",l"] = "--- ",
    [",t"] = "[toc]",
    [",1"] = "#<Space>",
    [",2"] = "##<Space>",
    [",3"] = "###<Space>",
    [",4"] = "####<Space>",
    [",5"] = "#####<Space>",
  }, { buffer = true })
  -- 浏览器预览开关。
  -- 注意：<C-m> 在终端里和 <CR> 是同一个键码，映射它会顶掉普通模式下的回车；
  -- 另外 LazyVim 风格的 <leader>cp 由 lua/plugins/markdown/preview.lua 定义。
  map.n({
    ["<C-m>"] = ":MarkdownPreviewToggle<CR>",
    ["<C-k>"] = ":MarkdownPreviewToggle<CR>",
  }, { buffer = true })

  -- 拼写检查开关（LazyVim 风格键位）。
  -- 默认不开：本机没有 cjk 词表，开了会把所有中文词标成拼写错误。
  vim.keymap.set("n", "<leader>us", function()
    local enabled = require("core.markdown_writing").toggle_spell()
    vim.notify(
      enabled and "拼写检查: 开" or "拼写检查: 关",
      vim.log.levels.INFO
    )
  end, { buffer = true, desc = "Markdown: 拼写检查开关" })

  -- 标题跳转不用自己写：Neovim 0.12 的 markdown ftplugin 已自带
  --   [[ / ]]  上一个 / 下一个标题（走 treesitter）
  --   gO       当前文档的标题大纲
end

return { setup = setup }
