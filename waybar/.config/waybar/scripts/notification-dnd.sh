#!/usr/bin/env bash
# 免打扰/开启通知按钮（基于 mako 的 do-not-disturb mode）
#
# 用法:
#   notification-dnd.sh status    # 输出 waybar custom 模块所需 JSON
#   notification-dnd.sh toggle    # 在「通知开启」与「免打扰」之间切换
#
# 依赖: mako (makoctl)
set -uo pipefail

# mako 的免打扰 mode 名，makoctl mode 每行输出一个当前激活的 mode
MODE_NAME="do-not-disturb"

# 图标用 Pango markup 放大。Nerd Font 字形在 16px 字号下比文字显小，
# 这里按字形墨迹高度与历史按钮的铃铛（115%）对齐：
# bell-ring 用 141%，bell-off 用 132%（见 style.css 顶部说明）。
ICON_BELL="<span size='141%'>󰂞</span>"
ICON_OFF="<span size='132%'>󰂛</span>"

# waybar 自定义模块的刷新信号（config.jsonc 中 "signal": 9）
refresh_waybar() {
    pkill -RTMIN+9 -x waybar 2>/dev/null || true
}

# 读取 mako 当前激活的 mode（每行一个）；mako 未运行/查询失败时返回非零。
# 注意：mako 在跑但没有任何额外 mode 时输出可能为空，这属于「正常」而不是不可用，
# 所以只以 makoctl 的退出码判断可用性。
fetch_modes() {
    local out
    out="$(makoctl mode 2>/dev/null)" || return 1
    printf '%s' "${out}"
}

status_json() {
    local modes
    if ! modes="$(fetch_modes)"; then
        printf '{"text":"%s","tooltip":"mako 未运行，无法切换免打扰","class":"unavailable"}\n' "${ICON_OFF}"
        return 0
    fi

    if grep -qxF "${MODE_NAME}" <<<"${modes}"; then
        printf '{"text":"%s","tooltip":"免打扰已开启，通知只进历史、不弹窗不响铃，点击开启通知","class":"dnd"}\n' "${ICON_OFF}"
    else
        printf '{"text":"%s","tooltip":"通知已开启，点击开启免打扰（不弹窗、不响铃）","class":"enabled"}\n' "${ICON_BELL}"
    fi
}

toggle() {
    local modes
    if ! modes="$(fetch_modes)"; then
        # mako 未运行：静默返回 0，不报错、不弹通知
        return 0
    fi

    if grep -qxF "${MODE_NAME}" <<<"${modes}"; then
        makoctl mode -r "${MODE_NAME}" >/dev/null 2>&1 || true
    else
        makoctl mode -a "${MODE_NAME}" >/dev/null 2>&1 || true
    fi

    refresh_waybar
}

case "${1:-status}" in
    status) status_json ;;
    toggle) toggle ;;
    *)
        printf 'usage: %s {status|toggle}\n' "$(basename "$0")" >&2
        exit 2
        ;;
esac
