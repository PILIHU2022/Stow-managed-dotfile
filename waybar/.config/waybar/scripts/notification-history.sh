#!/usr/bin/env bash
# 通知历史按钮（基于 mako 的 history 缓冲区）
#
# 用法:
#   notification-history.sh status    # 输出 waybar custom 模块所需 JSON
#   notification-history.sh menu      # fuzzel 中列出历史，选中后弹出完整内容
#   notification-history.sh restore   # 把最近一条已关闭的通知重新弹出来
#   notification-history.sh dismiss   # 关闭当前屏幕上所有通知
#
# 依赖: mako (makoctl)、jq、python3、fuzzel、notify-send
# 可选: zenity（用文本窗口查看正文，不会把看过的通知重新写进历史）
set -uo pipefail

# 图标用 Pango markup 放大到 115%，和 config.jsonc 里其它模块图标的处理保持一致
# （Nerd Font 字形在 16px 字号下比文字显小，见 style.css 顶部说明）
ICON_BELL="<span size='115%'>󰂚</span>"
ICON_EMPTY="<span size='115%'>󰂛</span>"
PREVIEW_LINES=8

# waybar 自定义模块的刷新信号（config.jsonc 中 "signal": 8）
refresh_waybar() {
    pkill -RTMIN+8 -x waybar 2>/dev/null || true
}

fetch_history() {
    makoctl history -j 2>/dev/null || true
}

status_json() {
    local raw
    raw="$(fetch_history)"
    if [[ -z "${raw}" ]]; then
        printf '{"text":"%s","tooltip":"mako 未运行，无法读取通知历史","class":"unavailable"}\n' "${ICON_EMPTY}"
        return 0
    fi
    printf '%s' "${raw}" | python3 -c '
import html, json, sys

icon_bell, icon_empty, limit = sys.argv[1], sys.argv[2], int(sys.argv[3])

try:
    data = json.load(sys.stdin)
except Exception:
    print(json.dumps({"text": icon_empty, "tooltip": "mako 历史解析失败", "class": "unavailable"}, ensure_ascii=False))
    sys.exit(0)

if not isinstance(data, list):
    data = []

count = len(data)
if count == 0:
    print(json.dumps({
        "text": icon_empty,
        "tooltip": "通知历史：暂无记录\n左键打开列表 · 中键恢复最近一条",
        "class": "empty",
    }, ensure_ascii=False))
    sys.exit(0)

lines = ["<b>通知历史（%d）</b>" % count]
for entry in data[:limit]:
    app = html.escape((entry.get("app_name") or "unknown").strip())
    summary = html.escape((entry.get("summary") or "").strip())
    body = (entry.get("body") or "").strip().replace("\n", " ")
    if len(body) > 60:
        body = body[:60] + "…"
    head = summary or body or "(无内容)"
    line = "• <b>%s</b> · %s" % (app, head)
    if body and summary:
        line += "\n  <small>%s</small>" % html.escape(body)
    lines.append(line)

print(json.dumps({
    "text": "%s %s" % (icon_bell, count),
    "tooltip": "\n".join(lines),
    "class": "has",
}, ensure_ascii=False))
' "${ICON_BELL}" "${ICON_EMPTY}" "${PREVIEW_LINES}"
}

menu() {
    local raw tmp sel idx app summary body
    raw="$(fetch_history)"
    if [[ -z "${raw}" || "${raw}" == "[]" ]]; then
        # 空的也提示一下；有 zenity 就走窗口，避免往 mako 历史里塞一条“暂无历史”
        if command -v zenity >/dev/null 2>&1; then
            setsid zenity --info --title="通知历史" --text="暂无历史通知" --width=320 >/dev/null 2>&1 &
        else
            notify-send -a waybar -u low "通知历史" "暂无历史通知" 2>/dev/null || true
        fi
        return 0
    fi

    tmp="$(mktemp)"
    printf '%s' "${raw}" > "${tmp}"

    if ! command -v fuzzel >/dev/null 2>&1; then
        rm -f "${tmp}"
        notify-send -a waybar -u normal "通知历史" "缺少 fuzzel，无法打开历史列表" 2>/dev/null || true
        return 0
    fi

    sel="$(jq -r '
        def clip(n): if (length > n) then .[0:n] + "…" else . end;
        .[] | "\(.app_name // "unknown") ｜ \((.summary // "") | clip(40))\(if (.body // "") == "" then "" else " ·  " + ((.body | gsub("\n"; " ")) | clip(50)) end)"
    ' "${tmp}" | fuzzel --dmenu --index --lines=12 --width=70 --prompt="通知历史 ❯ ")" || sel=""

    if [[ -z "${sel}" ]]; then
        rm -f "${tmp}"
        return 0
    fi

    idx="${sel}"
    app="$(jq -r ".[${idx}].app_name // \"通知历史\"" "${tmp}")"
    summary="$(jq -r ".[${idx}].summary // \"(无标题)\"" "${tmp}")"
    body="$(jq -r ".[${idx}].body // \"\"" "${tmp}")"
    rm -f "${tmp}"

    # 查看正文：优先用 zenity 文本窗口（可滚动、可选中复制），完全不碰 mako 历史；
    # 没有 zenity 时退回 notify-send（简单但会把这条重新写进历史）
    if command -v zenity >/dev/null 2>&1; then
        local view
        view="$(mktemp "${TMPDIR:-/tmp}/waybar-notif-XXXXXX.txt")" || return 0
        {
            printf '%s · %s\n' "${app}" "${summary}"
            printf '%s\n' "──────────────────────────────"
            if [[ -n "${body}" ]]; then printf '%s\n' "${body}"; else printf '%s\n' "(这条通知没有正文)"; fi
        } > "${view}"
        setsid sh -c 'zenity --text-info --title="通知历史" --width=620 --height=420 --filename="$1"; rm -f "$1"' _ "${view}" >/dev/null 2>&1 &
    elif [[ -n "${body}" ]]; then
        notify-send -a "${app}" -u normal -t 15000 "${summary}" "${body}" 2>/dev/null || true
    else
        notify-send -a "${app}" -u normal -t 15000 "${summary}" 2>/dev/null || true
    fi
    refresh_waybar
}

case "${1:-status}" in
    status) status_json ;;
    menu) menu ;;
    restore)
        makoctl restore 2>/dev/null || true
        refresh_waybar
        ;;
    dismiss)
        makoctl dismiss --all 2>/dev/null || true
        refresh_waybar
        ;;
    *)
        printf 'usage: %s {status|menu|restore|dismiss}\n' "$(basename "$0")" >&2
        exit 2
        ;;
esac
