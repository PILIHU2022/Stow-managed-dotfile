# steam — 只给 Steam 注入输入法配置（修「打字快漏字」）

## 结论先行

Steam 客户端（Chromium/CEF + GTK3）在 Wayland 会话下打字快会漏字，原因是它的
输入法通路不对。按 fcitx 官方
[Using Fcitx 5 on Wayland](https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland)
的 Chromium / Electron 一节，只有两种正确配置：

| Steam 实际运行在 | 需要什么 |
| --- | --- |
| **XWayland**（X11 窗口） | `GTK_IM_MODULE=fcitx` —— 和普通 X11 程序一样 |
| **原生 Wayland** | 必须显式加 `--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime`，否则 CEF 根本不启用输入法 |

关键点：我在系统 `libcef.so`（Chrome/152）里确认过，`GTK_IM_MODULE` /
`XMODIFIERS` / `fcitx` 这些字符串在 CEF 本体里是 **0 次命中**，`libcef.so` 也不
链接 libgtk。所以 **CEF 自己完全不读这些变量**，它们是被 Steam 的 GTK 壳读走
的；而原生 Wayland 下 CEF 另有 `--enable-wayland-ime` 硬开关
（`zwp_text_input_manager_v1/v3` 都在，但默认不启用）。

本包提供两个档位，**默认装的是 XWayland 档**：

| 文件 | 何时用 |
| --- | --- |
| `steam.desktop` | Steam 走 XWayland 时先试这一档（`GTK_IM_MODULE=fcitx`） |
| `steam-wayland.desktop` | 上面那档无效时改用它：让 Steam 改用 Wayland 的 text-input |

### 实测结论（2026-10-04，Steam 走 XWayland）

`hyprctl activewindow` 显示 Steam 窗口 `xwayland: 1`，而 XWayland 档**没能修掉
漏字**。这与 CEF 的实现一致：`libcef.so`（Chrome/152）里 `GTK_IM_MODULE` /
`XMODIFIERS` / `fcitx` 全部 0 次命中，也不链接 libgtk——所以 Steam 界面根本
不经过 GTK 的 IM 模块。此时 Chromium 在 X11 下走的是 **XIM**，而 XIM 是同步
协议（每次按键跨 XWayland 往返一次），这正是漏字的来源，加 `GTK_IM_MODULE`
改变不了它。

因此走 XWayland 的 Steam 目前**只有换到 Wayland 原生 IME 这一条可靠出路**：
`--ozone-platform=wayland --enable-wayland-ime`，让输入法改走 text-input，
彻底绕开 XIM。

## 怎么做

1. 确认 Steam 的窗口后端（关键是 `xwayland:` 字段）：

   ```sh
   hyprctl activewindow | grep -E 'class|xwayland'
   # 或
   xwininfo -root -tree | grep -i steam     # 有输出 = X11/XWayland
   ```

2. 确认注入是否真的进了进程（Steam 已启动时查它自己或 steamwebhelper）：

   ```sh
   for p in $(pgrep -f 'steam|steamwebhelper'); do
     printf '== pid %s\n' "$p"
     tr '\0' '\n' < /proc/$p/environ 2>/dev/null \
       | grep -E '^(GTK_IM_MODULE|SDL_IM_MODULE|XMODIFIERS)='
   done
   ```

   若这里看不到 `GTK_IM_MODULE=fcitx`，说明桌面入口覆盖没生效（多半是 Steam
   早就启动了、或不是从菜单启动的）——**完全退出 Steam** 再从菜单启动。

3. 切到 Wayland 档：

   ```sh
   cd ~/Projects/Stow-Dotfile
   stow steam          # 把两份 desktop 一起装出去
   cp ~/.local/share/applications/steam-wayland.desktop \
      ~/.local/share/applications/steam.desktop
   # 完全退出 Steam，再从菜单启动
   ```

   不想覆盖文件也可以直接在终端试一行（验证有效后再固化）：

   ```sh
   steam --enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime
   ```

## 一键体检

同目录的 [`steam-ime-check`](steam-ime-check) 会一次性回答：覆盖装没装、实际生效的
`Exec` 是什么、运行中的 Steam 进程到底有没有拿到注入变量、窗口是 XWayland 还是
原生 Wayland。

```sh
sh ~/Projects/Stow-Dotfile/steam/steam-ime-check
```

**2026-10-04 实测**：Steam 进程里只有 `XMODIFIERS=@im=fcitx`，**没有**
`GTK_IM_MODULE`/`SDL_IM_MODULE` —— 说明 desktop 覆盖当时并没生效（Steam 早已在
运行，菜单点击只是唤醒旧进程）。这种情况下漏字的"改善"多半来自重启 Steam 本身
（XIM 状态刷新），而不是注入起了作用。

判断注入是否真的生效，只看一个信号：**进程环境里出现 `GTK_IM_MODULE=fcitx`**。

## 为什么不做成全局（会话级）

[`Docs/file-dialog-ime-and-clipboard.md`](../Docs/file-dialog-ime-and-clipboard.md)
已记录实测教训：把 `GTK_IM_MODULE` / `gtk-im-module` 设成**全局**会连带改掉
Firefox 的输入法通路（表现为拼音直接上屏），当时已全部回退。所以这里把作用域
限定在 Steam：`~/.local/share/applications/steam.desktop` 与系统同名文件构成
用户级覆盖，只影响 Steam 自己的启动；Steam 启动的游戏是它的子进程，因此一并
继承。

## 已知局限

* 覆盖只在**从应用菜单 / 桌面入口**启动 Steam 时生效。若你在终端直接敲 `steam`，
  用上面第 2 步的命令即可。
* **`SDL_IM_MODULE=fcitx` 放在 Steam 作用域、不放进会话环境**：fcitx 官方原话是
  “SDL2-based applications that doesn't default to wayland. Set `SDL_IM_MODULE`
  to fcitx”——只该给「不默认走 Wayland 的 SDL2 程序」。Steam 启动的游戏正是这
  一类，写成子进程环境就全覆盖；若写进会话环境，Wayland 原生的 SDL2 程序会被
  强行改道。**非 Steam** 的 SDL2 游戏请单独给该程序加这个变量。

* 同一道理，`SDL_IM_MODULE=fcitx` 也会作用于 Steam 里那些**本来就是 Wayland
  原生**的 SDL2 游戏，把它们的输入法改道。若某个游戏因此出问题，别改这个全局
  作用域，改为在该游戏的「属性 → 启动选项」里单独写：

  ```
  SDL_IM_MODULE=fcitx %command%
  ```

  并把 Steam 桌面入口里的 `SDL_IM_MODULE=fcitx` 去掉即可。
* 强制 `--ozone-platform=wayland` 会把 Steam 的 GUI 从 XWayland 搬到 Wayland，
  属于换后端而非纯配置修复，因此没作为默认；请先按上面第 3 步实测再固化。

## 回退

```sh
rm ~/.local/share/applications/steam.desktop \
   ~/.local/share/applications/steam-wayland.desktop
# 或对仓库取消 stow：cd ~/Projects/Stow-Dotfile && stow -D steam
```
