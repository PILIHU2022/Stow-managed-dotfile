#!/usr/bin/env bash
# 只读诊断：Firefox 弹的系统文件对话框（xdg-desktop-portal / GTK）
#   - 为什么切不出中文输入法（fcitx5）
#   - 为什么在 Firefox 里复制的内容粘贴不进去
#
# 用法（用 user 账号，在自己的桌面终端里跑）：
#   1. 先在 Firefox 里触发一次文件对话框（上传附件 / 另存为），**让对话框开着不要关**；
#   2. 切到终端执行：  bash ~/Projects/Stow-Dotfile/Docs/diagnose-file-dialog.sh
#   3. 把完整输出贴回来。
#
# 本脚本只读取状态，不修改任何配置，也不会重启任何服务。
set -uo pipefail

sep() { printf '\n===== %s =====\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

sep "0. 时间 / 会话基本信息"
date '+%F %T %z'
printf 'user=%s uid=%s\n' "$(id -un)" "$(id -u)"
printf 'XDG_SESSION_TYPE=%s XDG_CURRENT_DESKTOP=%s\n' "${XDG_SESSION_TYPE:-}" "${XDG_CURRENT_DESKTOP:-}"

sep "1. 当前 shell 的输入法/图形环境"
env | grep -E '^(XDG_SESSION_TYPE|XDG_CURRENT_DESKTOP|WAYLAND_DISPLAY|DISPLAY|XDG_RUNTIME_DIR|GDK_BACKEND|QT_QPA_PLATFORM|GTK_IM_MODULE|QT_IM_MODULE|QT_IM_MODULES|XMODIFIERS|SDL_IM_MODULE|GLFW_IM_MODULE|MOZ_ENABLE_WAYLAND|GTK_USE_PORTAL|GTK_THEME)=' | sort

sep "2. systemd user manager 里的同名变量（D-Bus 激活的 portal 继承这一份）"
systemctl --user show-environment 2>/dev/null \
  | grep -E '^(XDG_SESSION_TYPE|XDG_CURRENT_DESKTOP|WAYLAND_DISPLAY|DISPLAY|GDK_BACKEND|QT_QPA_PLATFORM|GTK_IM_MODULE|QT_IM_MODULE|QT_IM_MODULES|XMODIFIERS|SDL_IM_MODULE|MOZ_ENABLE_WAYLAND|GTK_USE_PORTAL)=' \
  | sort || echo "（取不到）"

sep "3. xdg-desktop-portal 进程及其环境"
if have pgrep; then
  for p in $(pgrep -f 'xdg-desktop-portal' | sort -n); do
    printf -- '--- PID %s: %s\n' "$p" "$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)"
    tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null \
      | grep -E '^(WAYLAND_DISPLAY|DISPLAY|GDK_BACKEND|QT_QPA_PLATFORM|GTK_IM_MODULE|QT_IM_MODULE|XMODIFIERS|XDG_CURRENT_DESKTOP|XDG_RUNTIME_DIR|XDG_SESSION_TYPE)=' \
      | sort | sed 's/^/      /'
    printf '      started: %s\n' "$(ps -o lstart= -p "$p" 2>/dev/null)"
  done
else
  echo "（没有 pgrep）"
fi
printf -- '--- 对应的 systemd user unit（看 MainPID 和启动时间，判断是不是会话早期就被 D-Bus 拉起来了）---\n'
systemctl --user list-units 'xdg-desktop-portal*' --all --no-legend --no-pager 2>/dev/null | sed 's/^/      /' || true
for u in xdg-desktop-portal.service xdg-desktop-portal-gtk.service xdg-desktop-portal-hyprland.service; do
  printf '      %-40s MainPID=%s ActiveEnter=%s\n' "$u" \
    "$(systemctl --user show -p MainPID --value "$u" 2>/dev/null)" \
    "$(systemctl --user show -p ActiveEnterTimestamp --value "$u" 2>/dev/null)"
done

sep "4. 窗口清单：xwayland=true 就是 XWayland 客户端（关键证据）"
if have hyprctl; then
  hyprctl -j clients 2>/dev/null | python3 -c '
import json,sys
try: cs=json.load(sys.stdin)
except Exception as e:
    print("解析失败:",e); sys.exit()
if not cs: print("（当前没有窗口？）")
for c in cs:
    print(f"class={c.get(\"class\")!r} initialClass={c.get(\"initialClass\")!r} xwayland={c.get(\"xwayland\")} title={c.get(\"title\")!r}")
' 2>/dev/null || hyprctl clients
  printf -- '--- activewindow ---\n'
  hyprctl -j activewindow 2>/dev/null | python3 -c '
import json,sys
try: w=json.load(sys.stdin)
except Exception as e:
    print("解析失败:",e); sys.exit()
print(f"class={w.get(\"class\")!r} xwayland={w.get(\"xwayland\")} title={w.get(\"title\")!r}")
' 2>/dev/null
else
  echo "（没有 hyprctl，不在 Hyprland 会话里？）"
fi

sep "5. Clipboard 两边看到的内容（先在 Firefox 里 Ctrl+C 复制一段独特的文本再跑）"
if have wl-paste; then
  printf 'wl-paste  (Wayland CLIPBOARD): %s\n' "$(timeout 3 wl-paste -n 2>&1 | head -c 200)"
  printf 'wl-paste  (Wayland PRIMARY)  : %s\n' "$(timeout 3 wl-paste -p -n 2>&1 | head -c 200)"
else
  echo "（没有 wl-paste，装 wl-clipboard）"
fi
if have xclip; then
  printf 'xclip     (X11 CLIPBOARD)    : %s\n' "$(timeout 3 xclip -selection clipboard -o 2>&1 | head -c 200)"
  printf 'xclip     (X11 PRIMARY)      : %s\n' "$(timeout 3 xclip -selection primary -o 2>&1 | head -c 200)"
else
  echo "（没有 xclip）"
fi

sep "6. 可能抢走剪贴板/快捷键的东西"
pgrep -a -f 'copyq|cliphist|wl-clip-persist|greenclip|clipman|clipcat|xclip' 2>/dev/null || echo "（没有这类进程）"

sep "7. Firefox：进程环境 + 相关首选项"
fpids=$(pgrep -x firefox 2>/dev/null | head -3)
if [ -n "${fpids:-}" ]; then
  for p in $fpids; do
    printf -- '--- PID %s\n' "$p"
    tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null \
      | grep -E '^(WAYLAND_DISPLAY|DISPLAY|GDK_BACKEND|MOZ_ENABLE_WAYLAND|GTK_IM_MODULE|QT_IM_MODULE|XMODIFIERS|MOZ_X11_EGL)=' \
      | sort | sed 's/^/      /'
  done
else
  echo "（没有 firefox 进程）"
fi
for d in "$HOME"/.mozilla/firefox/*/; do
  [ -f "$d/prefs.js" ] || continue
  printf -- '--- %s\n' "$d"
  grep -hE 'focusmanager\.testmode|use-xdg-desktop-portal' "$d/prefs.js" "$d/user.js" 2>/dev/null | sed 's/^/      /' || echo "      （没有这两个首选项，即都是默认值）"
done

sep "8. fcitx5 前端现状（GTK / XIM / 输入上下文）"
if have fcitx5-diagnose; then
  fcitx5-diagnose 2>&1 \
    | grep -nE 'GTK_IM_MODULE|gtk-im-module|im-fcitx5|frontend:|XMODIFIERS|XIM_SERVERS|XIM encoding|InputContext|IC \[' \
    | head -60 | sed 's/^/      /' || true
  echo "      提示：program:firefox frontend:dbus = 走 fcitx 的 GTK 模块；"
  echo "            frontend:wayland = 走合成器 text-input-v3。文件对话框属于哪个进程对照第 3、4 节。"
else
  echo "（没有 fcitx5-diagnose）"
fi

sep "9. GTK IM 模块缓存与 settings.ini 实际路径"
printf 'gtk3 settings.ini : %s\n' "$(ls -l "$HOME/.config/gtk-3.0/settings.ini" 2>&1)"
printf 'gtk4 settings.ini : %s\n' "$(ls -l "$HOME/.config/gtk-4.0/settings.ini" 2>&1)"
printf '旧错误路径 gtk3.0 : %s\n' "$(ls -ld "$HOME/.config/gtk3.0" 2>&1)"
printf 'gtk-query-immodules-3.0 | grep fcitx:\n'
gtk-query-immodules-3.0 2>/dev/null | grep -i fcitx | sed 's/^/      /' || echo "      （命令不存在）"

sep "完成"
echo "把以上全部输出贴回来即可。"
