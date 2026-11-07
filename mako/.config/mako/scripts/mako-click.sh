#!/usr/bin/env bash
# mako 左键点击处理：触发通知的默认动作，并把焦点切回发通知的程序。
#
# mako 会把通知 id 作为 shell 变量 $id 传给 exec 绑定，所以在配置里这样用：
#   on-button-left=exec bash $HOME/.config/mako/scripts/mako-click.sh "$id"
#
# 为什么不用 mako 自带的 invoke-default-action：点击时 mako 会把 xdg-activation
# 令牌交给应用，但 Hyprland 的 misc:focus_on_activate 是全局开关且默认 false，
# 为 false 时所有激活请求都被丢弃（应用只能闪一下 urgent），窗口不会被抬起。
# 这里改成 hyprctl 显式聚焦：只在用户主动点击通知时生效，不影响其它程序的焦点。

set -u

id=${1:-}
[[ $id =~ ^[0-9]+$ ]] || exit 0

command -v jq >/dev/null 2>&1 || exit 0

# 取出这条通知的元数据（-j 的字段是 snake_case：app_name / desktop_entry ...）
notif=$(makoctl list -j 2>/dev/null | jq -c --argjson id "$id" '.[] | select(.id == $id)')
[[ -n $notif ]] || exit 0

# 1. 先让应用执行自己的默认动作（例如 Telegram 打开对应会话）
makoctl invoke -n "$id" >/dev/null 2>&1

# 2. 再把焦点切到它的窗口
desktop_entry=$(jq -r '.desktop_entry // ""' <<<"$notif")
app_name=$(jq -r '.app_name // ""' <<<"$notif")

address=$(hyprctl clients -j 2>/dev/null | jq -r \
	--arg desktop_entry "$desktop_entry" \
	--arg app_name "$app_name" '
	# 归一化：转小写并去掉非字母数字，"Google Chrome" 与 "google-chrome" 视为同一个
	def norm: ascii_downcase | gsub("[^a-z0-9]"; "");
	# desktop_entry 有时带 .desktop 后缀，先去掉再归一化
	[ $desktop_entry, $app_name ] as $raw
	| ($raw | map(sub("(?i)\\.desktop$"; "")) | map(select(. != "") | norm) | map(select(. != ""))) as $wanted
	| [ .[]
		| select(.mapped)
		| (.class // "" | norm) as $class
		| ([ $wanted[] | select(. == $class) ] | length) as $exact
		| ([ $wanted[] | . as $c | select(($c | length) >= 4 and ($class | startswith($c))) ] | length) as $prefix
		| select($exact > 0 or $prefix > 0)
		| { address: .address, score: (if $exact > 0 then 2 else 1 end), recency: .focusHistoryID }
	  ]
	| sort_by([-.score, .recency])
	| first
	| .address // empty')

if [[ -n $address ]]; then
	# Hyprland 0.55 起 dispatch 改为 Lua：hyprctl dispatch '<表达式>' == eval 'hl.dispatch(<表达式>)'
	# 老写法 hyprctl dispatch focuswindow address:... 会被当成 Lua 解析而报错
	hyprctl dispatch "hl.dsp.focus({ window = \"address:$address\" })" >/dev/null 2>&1
fi

# 3. 点击过就收起这条通知（仍可在 makoctl history 里找回并 restore）
makoctl dismiss -n "$id" >/dev/null 2>&1
