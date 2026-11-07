# Firefox 系统文件对话框：中文输入法切不出来 + 从 Firefox 复制的内容粘不进去

> 主机 `host` ｜ Hyprland（uwsm 会话）+ fcitx5 ｜ 报告时间：2026-10-03
> 现象：在 Firefox 里弹出系统文件对话框（打开 / 另存为）时
> 1. 切不出中文输入法；2. 在 Firefox 里复制的文本粘不进对话框的“文件名”栏。

> ## ⚠️ 本页记录的修改已全部回退（2026-10-03）
> 把 `gtk-im-module=fcitx` 挪到 GTK 真正会读的 `~/.config/gtk-3.0/settings.ini` 之后，
> **Firefox 的输入法通路也被改成了 fcitx 的 GTK 模块**（而不是 Wayland `text-input-v3`），
> 表现为**在 GitHub 里打字时拼音被直接上屏**。据此按用户要求全部回退：
> 仓库中的 `gtk3.0` 路径 / `uwsm` 环境变量 / systemd drop-in 均已还原，live 状态的回退命令见 4.2。
>
> ## ❗ 回退后补充实测（同日稍后）：该现象**仍在**，且是 GitHub 站点特定的
> 完整回退并重启 Firefox 后，GitHub 里的「拼音直接上屏」**依旧存在**，而同一浏览器里的
> **DSH 网页输入完全正常** → 说明这个现象是 **GitHub 的编辑器（CodeMirror 一类）特定**的，
> **不能归因于本页那次改动**（或至少不是唯一原因）。后续定位见 6.3。
>
> **教训（仍然成立）**：Wayland 会话里不要给 GTK 设 `gtk-im-module` / `GTK_IM_MODULE`——它是
> **全局**设置，会连带改掉 Firefox 的输入法通路。要做也只能用 systemd drop-in 给**单个服务**注入。
> 文件选择器的输入法问题**仍未解决**，结论与待办见第 6 节。

---

## 摘要（TL;DR）

| 问题 | 结论 | 依据 |
| --- | --- | --- |
| 对话框是谁画的 | `xdg-desktop-portal-gtk`（GTK3，D-Bus 激活的**独立进程**），而且是**纯 Wayland 客户端** | 实测：`hyprctl clients` → `class: xdg-desktop-portal-gtk, xwayland: 0, pid: 1251`；`ldd /usr/lib/xdg-desktop-portal-gtk` → `libgtk-3.so.0` |
| 输入法为什么切不出来 | **未定论**。曾以为是"Wayland 下 GTK 不读 settings.ini、该服务又没设 `GTK_IM_MODULE`"，但按这个方向修会连带弄坏 Firefox 的输入法（见顶部警告），已回退；真正原因待查 | 实测 portal 进程 environ 无 `GTK_IM_MODULE`；改动后 Firefox 出现拼音直接上屏 |
| 仓库里那个 GTK 配置的坑 | `gtk-im-module=fcitx` 被放在 `~/.config/gtk3.0/`（GTK3 只读 `gtk-3.0`），**从来没生效过**；它若生效会连带影响 Firefox，所以**保持它不生效**才是对的 | 实测：`strings /usr/lib/libgtk-3.so.0` 命中 `gtk-3.0`；`~/.config/gtk-3.0/settings.ini` 不存在 |
| 粘贴为什么失败 | **未能复现**：复制侧正常（`wl-paste` / `xclip` 都读得到），对话框侧 `Ctrl+V`、右键菜单、`Shift+Insert` 实测**都能粘** → 最初那次失败无法归因到目前已确认的任何一条原因，需要复现条件 | 见第 3 节（3.2 实测结果 / 3.3 排除清单） |
| 曾做过的修改 | ① `gtk3.0` 包内路径修正 ② systemd drop-in 给 portal 设 `GTK_IM_MODULE=fcitx` ③ uwsm 会话环境补 `QT_IM_MODULE`/`SDL_IM_MODULE`/`XMODIFIERS` —— **三项均已回退** | 见第 4 节 |

---

## 1. 现场证据（user 会话实测，2026-10-03 11:53）

探针脚本：[Docs/diagnose-file-dialog.sh](diagnose-file-dialog.sh)（只读）。

| # | 事实 | 结论 |
| --- | --- | --- |
| 1 | 对话框窗口：`class: xdg-desktop-portal-gtk`、`title: Save As - …`、`xwayland: 0`、`pid: 1251` | 独立进程、**Wayland 原生** |
| 2 | portal 进程环境：`WAYLAND_DISPLAY=wayland-1`、`DISPLAY=:0`、`XDG_SESSION_TYPE=wayland`、`XMODIFIERS=@im=fcitx`，**没有** `GTK_IM_MODULE`/`QT_IM_MODULE` | 显示环境正常；输入法模块没指定 |
| 3 | systemd user 环境里有 `WAYLAND_DISPLAY=wayland-1`、`DISPLAY=:0` | 之前怀疑的“没跑 `uwsm finalize`”**不成立**，已排除 |
| 4 | fcitx5 里有 `program:xdg-desktop-portal-gtk frontend:wayland_v2 cap:72 focus:0`，且全机没有任何 `frontend:dbus` 的 IC | 输入法走的是合成器 text-input 转发，不是 fcitx 的 GTK/Qt 模块 |
| 5 | `~/.config/gtk-3.0/settings.ini` **不存在**；`~/.config/gtk-4.0/settings.ini` 是**真实文件**（`-rw-------` 410B）；`~/.config/gtk3.0` 是指向仓库旧目录的**悬空软链** | 决定第 5 节的 stow 步骤与 gtk-4.0 的取舍 |
| 6 | `wl-paste`（CLIPBOARD）= kitty 里那条命令；`wl-paste -p`（PRIMARY）= Firefox 标签标题；`xclip` 两侧都报 `target STRING not available` | 剪贴板的关键线索，见第 3 节 |

---

## 2. 输入法：按 GTK 的规则只有两条路

GTK 选择 IM 模块的顺序（fcitx 官方文档，已按本机 GTK 3.24.52 / 4.22.5 核对）：

| 后端 | 顺序 |
| --- | --- |
| X11 / XWayland | `GTK_IM_MODULE` 环境变量 → XSettings `Gtk/IMModule` → **`settings.ini` 的 `gtk-im-module`** → 按 locale 自动挑 |
| Wayland | `GTK_IM_MODULE` 环境变量 → 内置 `"wayland"`（text-input-v3）——**不读 settings.ini** |

本机这个文件对话框走的是 Wayland 分支（证据第 1、2 条），所以：

* 放在 `~/.config/gtk-3.0/settings.ini` 里的 `gtk-im-module=fcitx` **对它无效**（那份配置只救 X11/XWayland 的 GTK 程序，比如用 XWayland 跑的 zenity）；
* 要让它用上 fcitx5，只能给**这个服务**设 `GTK_IM_MODULE=fcitx`，让它改走 fcitx 的 GTK IM 模块（D-Bus 直连 fcitx5，不依赖合成器转发）。

### 2.1 本次修改

* 新增 [`systemd/.config/systemd/user/xdg-desktop-portal-gtk.service.d/gtk-im-module.conf`](../systemd/.config/systemd/user/xdg-desktop-portal-gtk.service.d/gtk-im-module.conf)：`Environment=GTK_IM_MODULE=fcitx`，**只影响 portal 服务**，Firefox 等继续用 Wayland 的 text-input-v3（不设全局 `GTK_IM_MODULE` 是为了避开 fcitx 文档里提到的候选窗闪烁问题）。
* 修正 `gtk3.0` 包内的 `settings.ini` 路径（`gtk3.0/` → `gtk-3.0/`），让 X11/XWayland 的 GTK 程序也能用上 fcitx。
* uwsm 会话环境补 `XMODIFIERS` / `QT_IM_MODULE=fcitx` / `SDL_IM_MODULE=fcitx`（非 KWin 合成器上 Qt 必须显式指定，否则 Qt 程序和 KDE 那套 portal 对话框切不出输入法）。

### 2.2 机制已实测确认

```bash
# 对照实验：同一个 GTK3 程序，加不加环境变量
zenity --entry                      # 里面切输入法：出不来
GTK_IM_MODULE=fcitx zenity --entry  # 里面切输入法：能出候选词 ✅（2026-10-03 user 实测确认）
```

确认后应用 drop-in：

```bash
systemctl --user daemon-reload
systemctl --user restart xdg-desktop-portal-gtk.service
# 然后开 Firefox 的“另存为”，在“文件名”栏里打拼音
```

---

## 3. 粘贴：复制侧已排除，断点在对话框

**复制侧已实测排除**（2026-10-03）：在 Firefox 里 `Ctrl+C` 后立刻跑

```bash
wl-paste -n; echo "  <-- Wayland CLIPBOARD"; xclip -selection clipboard -o; echo "  <-- X11 CLIPBOARD"
```

两边都能看到刚复制的内容 → Firefox → Wayland CLIPBOARD → X11 桥这一整条链路是好的，问题只在**文件对话框本身**。

### 3.1 关键线索：GTK3 的文件选择器**自己也绑定了 `Control + V`**

GTK3 官方文档把 `Gtk.FileChooserWidget::location-popup-on-paste` 定义为 **keybinding signal，默认绑定就是 `Control + V`**：

> This is used to make the file chooser show a “Location” prompt when the user pastes into a `GtkFileChooserWidget`. **The default binding for this signal is `Control + V`.**

本机 `gtk3 3.24.52` 的 `libgtk-3.so.0` 里同时存在两个 Ctrl+V 键绑定信号：

```
location-popup-on-paste   ← GtkFileChooserWidget 的（会被 FileChooser 抢走 → 变成"粘贴到 Location 栏"或不发生任何可见动作）
paste-clipboard            ← GtkEditable / GtkEntry 的（真正把文本粘进输入框的那个）
```

也就是说：**`Ctrl+V` 理论上可能被 FileChooser 的绑定接走、到不了"文件名"输入框**（同类问题在 GTK4 上有上游修复：[GNOME/gtk#4905](https://gitlab.gnome.org/GNOME/gtk/-/issues/4905)，GTK4 4.6.4 起修好）。

### 3.2 清单实测结果（2026-10-03）：**抢键假设被否**

| # | 操作 | 结果 |
| --- | --- | --- |
| 1 | 敲拉丁字母 | （未单独回报；2/4/5 能粘说明输入框本身有焦点、可用） |
| 2 | `Ctrl+V` | ✅ 能粘出 |
| 3 | 中键粘贴 | 未测 |
| 4 | 右键 → 粘贴 | ✅ 能粘出 |
| 5 | `Shift+Insert` | ✅ 能粘出 |

结论：

* `Ctrl+V` **没有**被 `location-popup-on-paste` 抢走（至少在本机 GTK 3.24.52 + 这条路径上不会）；右键菜单与 `Shift+Insert` 也都正常 → **输入框的粘贴通路完全正常**。
* 也就是说，最初那次“在 Firefox 复制、粘进文件名栏没反应”**在本次复现中不再出现**，属于**尚未复现的现象**，不能归因到目前任何一条已确认的原因上。要定案需要复现条件，候选（按可能性排序）：
  1. **来源标签页在粘贴前发生了变化**：Wayland 剪贴板的数据由复制它的那个客户端进程持有，Firefox 的 WebContent 进程若在粘贴前导航/关闭/被回收，剪贴板内容会随数据源一起消失（表现就是“粘不出东西”）。
  2. **当时用的是旧 portal 进程**（09:33 起就在跑）：需要对比“刚重启过 portal”与“跑了一整天的 portal”两种情况。
  3. **粘贴的文本形态**：例如从 DSH 界面复制的“建议文件名/完整路径”，是否含 `/` 等被保存对话框按路径解释的字符。

### 3.3 已被证据排除的猜想

* ~~Firefox 的 Ctrl+C 没写进 Wayland CLIPBOARD~~ → `wl-paste -n` 看得到，**排除**。
* ~~`Ctrl+V` 被 GtkFileChooser 的 `location-popup-on-paste` 抢走~~ → 实测 Ctrl+V / 右键 / Shift+Insert 都能粘，**排除**。
* ~~对话框是 XWayland 客户端，踩中 Hyprland 的 Wayland↔X11 剪贴板桥问题（hyprwm/Hyprland#6132）~~ → 实测 `xwayland: 0`，**排除**。
* ~~会话没跑 `uwsm finalize`，portal 在缺 `WAYLAND_DISPLAY` 的环境里启动~~ → systemd user 环境里两个变量都在，**排除**。

> 可选的兜底方案：把 portal 的 FileChooser 后端换成 KDE（`~/.config/xdg-desktop-portal/hyprland-portals.conf` 里写 `org.freedesktop.impl.portal.FileChooser=kde`），Qt 对话框的 Ctrl+V 行为正常，而且本次已给会话补了 `QT_IM_MODULE=fcitx`，输入法也能用。代价是对话框变成 KDE 风格、依赖 KIO 那一套，属于“要换实现”而不是“修配置”，所以先不动。



---

## 4. 曾经做过的修改（**2026-10-03 已全部回退**）

| 文件 | 曾经的改动 | 现状 |
| --- | --- | --- |
| `gtk3.0/.config/gtk-3.0/settings.ini` | 从 `gtk3.0/`（GTK 不读）挪到 `gtk-3.0/`（GTK 会读），让 `gtk-im-module=fcitx` 首次真正生效 | **已回退**：文件搬回 `gtk3.0/.config/gtk3.0/settings.ini`，内容恢复原样（仍是那条陈旧的 `gtk-im-module=fcitx`，但路径让 GTK 不读它，即回到"无副作用"的原状态） |
| `systemd/.config/systemd/user/xdg-desktop-portal-gtk.service.d/gtk-im-module.conf` | 新增 drop-in：只给 portal 服务设 `GTK_IM_MODULE=fcitx` | **已删除** |
| `uwsm/.config/uwsm/env-hyprland`、`env-hyprland-uwsm` | 新增 `XMODIFIERS` / `QT_IM_MODULE=fcitx` / `SDL_IM_MODULE=fcitx` | **已回退** |

### 4.1 为什么回退：激活 GTK 的 fcitx 模块会**连带改掉 Firefox 的输入法通路**

`~/.config/gtk-3.0/settings.ini` 一旦真的存在并被 GTK 读取，**Firefox 也被算在内**（它同样是 GTK3 程序）：它的 IM 上下文从 Wayland 的 `text-input-v3` 换成 fcitx 的 GTK 模块，于是网页里出现

> 在 GitHub 打字时，输入的拼音被"莫名其妙地直接上屏"（没有正常的候选/上屏过程）

这与 fcitx 官方文档的提醒一致：Wayland 下**不应该**设 `GTK_IM_MODULE`，也印证了那份 `settings.ini` 里的老注释「解决QQ输入框输入太快导致字母进入输入框中」——同一类"字母漏进输入框"的问题，只是这次发生在 Firefox 上。所以这两个症状是同一个机制的两面，**这个方向不能改**。

**范围区别（下次要用得上）**：`~/.config/gtk-3.0/settings.ini` 是**全局**的，所有 GTK3 程序（含 Firefox）都会读到 → 连带改掉 Firefox 的输入法；而 systemd drop-in 只给**某一个服务**注入 `GTK_IM_MODULE`（例如只给 `xdg-desktop-portal-gtk`），Firefox 不受影响。本次两者都回退了，其中 drop-in 是"作用域安全但未验证有效"的那一半。

### 4.2 回退命令（仓库已回退，live 状态执行这些）

```bash
if [ -L ~/.config/gtk-3.0 ]; then rm -v ~/.config/gtk-3.0; else rm -v ~/.config/gtk-3.0/settings.ini && rmdir -v ~/.config/gtk-3.0; fi
rm -rf ~/.config/systemd/user/xdg-desktop-portal-gtk.service.d
systemctl --user daemon-reload
systemctl --user restart xdg-desktop-portal-gtk.service
cd ~/Projects/Stow-Dotfile && stow -R -v -t ~ gtk3.0
```

最后**重启 Firefox**（IM 上下文在进程内是缓存的，不重启不一定切回 `text-input-v3`）。

> 关于 `stow systemd`：见 5.1，这个包在本机是「配置备份」，不能整包 stow。

## 5. 生效/回退时踩过的坑

### 5.1 `stow systemd` 为什么会冲突

1. `~/.config/systemd/user/` 下的 unit 在本机是**真实文件**（不是指向仓库的软链），stow 不会覆盖（`cannot stow … over existing target … since neither a link nor a directory`），除非 `--adopt`（会把真实文件搬进仓库，风险自负）。
2. 仓库里 `systemd/.config/systemd/user/*.wants/` 下是**绝对路径软链**（当年在仓库目录里跑 `systemctl --user enable` 留下的），stow 明确拒绝这类源（`source is an absolute symlink`）。

所以要让整包可 stow，得先把 live 的真实 unit 换成软链、并把 `.wants/*` 改成相对软链（或干脆不纳入仓库）。

### 5.2 zsh 里行尾 `#` 不是注释

交互式 zsh 默认**不**把 `#` 当注释（需要 `setopt interactive_comments`），把带中文注释的命令整段粘贴进去，注释会被当成命令参数（例如 `grep: #: 没有那个文件或目录`）。给 zsh 用的命令块里不要写行尾注释。

## 6. 结论与待办

**已确认的结论**

* 文件对话框是 `xdg-desktop-portal-gtk`（GTK3）、**Wayland 原生**、独立进程；会话与 portal 的 `WAYLAND_DISPLAY`/`DISPLAY`/`XMODIFIERS` 都正常。
* 粘贴侧：复制链路（Firefox→Wayland CLIPBOARD→X11 桥）正常，对话框里 `Ctrl+V` / 右键菜单 / `Shift+Insert` 都能粘 → 最初那次"粘不进去"**未能复现**。
* **不能**通过给 GTK 塞 `gtk-im-module=fcitx` / `GTK_IM_MODULE` 来修输入法：它是全局设置，会连带改掉 Firefox 的输入法通路，导致拼音直接上屏（本次已回退）。
* **GitHub 的「拼音直接上屏」与本次改动无关（或不止一个原因）**：完整回退并重启 Firefox 后该现象仍在，而同一浏览器里 DSH 网页输入完全正常 → 站点/编辑器特定。

**待办（都没做，等有复现条件再做）**

1. 文件对话框里切不出中文输入法：根因尚未定论。候选方向是合成器↔`waylandim` 这条 text-input 链路在**这个 portal 窗口**上的路由问题（其它程序如 kitty/Firefox 是好的），而不是本机的 IM 环境变量；需要复现时抓 `fcitx5-diagnose` 里该窗口的 IC 状态（`focus` 是否为 1）。
2. 粘贴偶发失败：复现时记录 ① 从哪个程序/页面复制 ② 粘贴前页面有无导航/刷新/关闭 ③「打开」还是「另存为」 ④ portal 进程是刚重启还是跑了一整天。
3. 可选兜底（未采用）：把 FileChooser 后端换成 KDE（Qt 对话框），代价是换实现 + KIO 依赖。

### 6.3 GitHub「拼音直接上屏」的定位（进行中）

**已排除**：本页那次改动（回退后仍在，且 live 已确认 `~/.config/gtk-3.0/settings.ini`、portal drop-in 都已不存在，`fcitx5-diagnose` 里 `program:firefox frontend:wayland_v2`）、DSH 网页（同一 Firefox 里正常 → 排除"Firefox 整体 IME 坏了"）。

**三个实验，按代价从低到高**

1. 用 **CodeMirror 6 官方 demo** 做同类对照（零配置）：打开 <https://codemirror.net/try/> 打字。
   * 同样坏 → 是「CodeMirror 类编辑器 + Firefox Wayland」的通用问题，不是 GitHub 特有；
   * 正常 → 是 GitHub 自己那套编辑器/前端同步逻辑的问题。
2. 用 **XWayland 起一个 Firefox**（零配置）：

```bash
MOZ_ENABLE_WAYLAND=0 firefox
```

   （临时用 XWayland 起一个 Firefox，去 GitHub 打字；不改任何配置）

   * 这个实例里正常 → 问题在 **Firefox 的 Wayland text-input 通路**；可进一步考虑给 Firefox 单独设 `MOZ_ENABLE_WAYLAND=0`（或 `GDK_BACKEND=x11`）作为长期规避。
   * 仍然不正常 → 问题在编辑器侧的组合事件处理。

3. 如果前两个都指向 waylandim：试 fcitx5 那个**既有 override**（`~/.config/fcitx5/conf/waylandim.conf`，注意它落在 stow 包里）：

```bash
sed -i 's/^PreferKeyEvent=True/PreferKeyEvent=False/' ~/Projects/Stow-Dotfile/fcitx5/.config/fcitx5/conf/waylandim.conf
fcitx5 -r
```

   语义：`PreferKeyEvent=True` 表示「未处理的按键按**原始 key 事件**转发」；而 CodeMirror 这类编辑器自己处理 keydown，原始按键可能被它们直接插入 → 拼音原文上屏。用完回退：

```bash
git -C ~/Projects/Stow-Dotfile checkout -- fcitx5/.config/fcitx5/conf/waylandim.conf
fcitx5 -r
```

再按输入位置切分：GitHub 的**评论框**（普通 `textarea`）与**代码视图 / 搜索 / 编辑器**（CodeMirror 6 一类）分别试，看哪些坏。

**已知同类成因（都属上游问题，dotfiles 里没有开关）**

* CodeMirror 类编辑器在 IME 组合期间被前端框架（Vue/React）回写 value，导致组合被打断、拼音原文直接落下（见开源修复例：[hoppscotch PR#6443](https://www.cubic.dev/pr/hoppscotch/hoppscotch/pull/6443)）；CodeMirror view 也在持续修 composition 相关缺陷（[6.9.3 release](https://github.com/codemirror/view/releases/tag/6.9.3)）。
* Firefox 在 Wayland 下有 "key snooper" 模式会发出**伪 keydown**，上游已修（[Mozilla Bug 2028505](https://phabricator.services.mozilla.com/D313440)）——这类伪事件正是编辑器类 JS 容易误判的来源。

**实测结果与修正（2026-10-03 稍后）**

| 对象 | 结果 |
| --- | --- |
| CodeMirror 6 官方 demo（<https://codemirror.net/try/>） | **正常** |
| DSH 网页输入 | **正常** |
| GitHub 的 **issue 输入框** | **坏**（拼音直接上屏） |

→ 排除"CodeMirror 类编辑器通用问题"，锁定 **GitHub 该表单自身的 JS**：新版「新建 issue」表单是 **React 受控输入**，与 Firefox 的 IME / composition 事件上报冲突时，组合会被提前打断、按键按原文落下。"以前从未遇到"与 GitHub 把该表单换成新版 React 实现的时间点吻合。

* XWayland 对照实验**未完成**：`MOZ_ENABLE_WAYLAND=0 firefox` 报 `Error: cannot open display: :0`（是 X11 连接问题，不是输入法结论）。要重试用 `env MOZ_ENABLE_WAYLAND=0 GDK_BACKEND=x11 firefox --new-instance`，先用 `xdpyinfo` 确认 X 凭据可用。
* 下一轮 A/B（**不改 dotfiles**，about:config 即刻生效、随时还原）：
  1. `intl.ime.hack.uim.using_key_snooper` —— Linux 上为识别 uim 会开 key snooper；Wayland 下它会给页面**合成假 keydown**（上游 Bug 2028505 正在修这个），而 GitHub 的 React 表单会监听 keydown，最容易被带偏。
  2. `intl.ime.use_composition_events_for_insert_text` —— 控制 IME 插入文本时是否合成 composition 事件；受控 React 输入对此最敏感，切成相反值试。
  3. 浏览器对照：本机已装 `google-chrome`，用 Chrome 打开同一表单 → 正常即 Firefox 特有（回到 1、2）；也坏则是 GitHub 的 bug。
  4. 位置对照：**新建 issue 表单** vs **已有 issue 里的评论框**（若只有前者坏，就确认是新版 React 表单）。
* 兜底（先能干活）：中文在 DSH / 编辑器里打好再粘进 GitHub（本机粘贴链路已验证正常），或 GitHub 改用 Chrome。



