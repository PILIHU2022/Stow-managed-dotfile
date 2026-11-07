#!/usr/bin/env bash
# 通知提示音：非免打扰时播放，免打扰时静默。
#
# 配置里这样用：
#   on-notify=exec $HOME/.config/mako/scripts/notify-sound.sh
#
# 为什么不直接 on-notify=exec mpv ...：
# mako 的 on-notify 在通知“打开/显示”时触发，而免打扰 mode 只是 invisible=1，
# 触发时机本身并不可靠。这里在播放前显式查询一次当前 mode，保证免打扰期间绝不发声。
#
# 查询失败（makoctl 不存在 / mako 没在运行 / 输出为空）时一律静默，即 fail-closed：
# 宁可少响一次，也不要在免打扰里漏响。需要恢复提示音时检查 mako 是否正常。

set -uo pipefail

# makoctl mode 输出为每行一个当前启用的 mode（默认至少有 default）
command -v makoctl >/dev/null 2>&1 || exit 0
modes=$(makoctl mode 2>/dev/null) || exit 0
[[ -n $modes ]] || exit 0

# 精确整行比较，避免 do-not-disturb-xxx 这类名字被误判成免打扰
while IFS= read -r mode; do
	[[ $mode == 'do-not-disturb' ]] && exit 0
done <<<"$modes"

# 非免打扰：播放提示音。用 exec 让 mpv 直接替换 shell，省一个常驻进程
exec mpv /usr/share/sounds/freedesktop/stereo/message.oga
