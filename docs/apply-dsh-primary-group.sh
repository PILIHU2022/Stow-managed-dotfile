#!/usr/bin/env bash
# ============================================================================
# apply-dsh-primary-group.sh
#
# 目的:把 dsh 的主组改成 agent,让 DSH 的 write 工具产出的文件属组为 agent,
#       从而 user(uid 1000)可以直接读取。
#
# 背景(实测结论,见 Docs/dsh-write-tool-permission-behavior.md):
#   write 工具 = 建临时文件 + rename 覆盖。rename 不是新建,不触发父目录
#   setgid 组继承,临时文件取「进程主组」。dsh 主组原为 dsh(1005),
#   于是覆盖/新建后属组变成 dsh,user 不在该组 -> 读不到。
#
# 需要 root(usermod)。用 sudo 或 pkexec 执行本脚本。
#
# 用法:
#   sudo bash /home/Projects/scripts/apply-dsh-primary-group.sh
# ============================================================================
set -uo pipefail

GRP=agent
USER_NAME=dsh
TARGET_USER=user
FAIL=0

say()  { printf '\n=== %s ===\n' "$*"; }
ok()   { printf '  [ok]   %s\n' "$*"; }
warn() { printf '  [warn] %s\n' "$*"; }
bad()  { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }

if [ "$(id -u)" != 0 ]; then
  echo "需要 root 权限运行: sudo bash $0" >&2
  exit 1
fi

say "0. 修复前状态"
BEFORE="$(id -gn "$USER_NAME" 2>/dev/null || echo '?')"
echo "   $USER_NAME 主组: $BEFORE (gid $(id -g "$USER_NAME" 2>/dev/null))"
echo "   $USER_NAME 附加组: $(id -Gn "$USER_NAME" 2>/dev/null | tr ' ' ',')"
echo "   $TARGET_USER  附加组: $(id -Gn "$TARGET_USER" 2>/dev/null | tr ' ' ',')"

getent group "$GRP" >/dev/null || { bad "组 $GRP 不存在"; exit 1; }
GID="$(getent group "$GRP" | cut -d: -f3)"
ok "组 $GRP = gid $GID"

# ---------------------------------------------------------------------------
# 1. 两侧成员资格:user 必须在 agent 组;dsh 也要保留成员地位
# ---------------------------------------------------------------------------
say "1. 组成员资格"
if id -Gn "$TARGET_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$GRP"; then
  ok "$TARGET_USER 已在 $GRP 组"
else
  usermod -aG "$GRP" "$TARGET_USER" && ok "已把 $TARGET_USER 加入 $GRP" || bad "加入 $TARGET_USER 失败"
fi
if id -Gn "$USER_NAME" 2>/dev/null | tr ' ' '\n' | grep -qx "$GRP"; then
  ok "$USER_NAME 已在 $GRP 组"
else
  usermod -aG "$GRP" "$USER_NAME" && ok "已把 $USER_NAME 加入 $GRP" || bad "加入 $USER_NAME 失败"
fi

# ---------------------------------------------------------------------------
# 2. 核心改动:把 dsh 的主组改成 agent
# ---------------------------------------------------------------------------
say "2. 修改 $USER_NAME 主组 -> $GRP"
if [ "$BEFORE" = "$GRP" ]; then
  ok "主组已经是 $GRP,无需修改"
else
  if usermod -g "$GRP" "$USER_NAME"; then
    ok "$USER_NAME 主组: $BEFORE -> $GRP"
  else
    bad "usermod -g 失败"
  fi
fi
AFTER="$(id -gn "$USER_NAME" 2>/dev/null || echo '?')"
echo "   修复后主组: $AFTER (gid $(id -g "$USER_NAME" 2>/dev/null))"

# ---------------------------------------------------------------------------
# 3. 顺手:修复 /home/dsh 的属组(主组变更后家目录属组也应跟上)
# ---------------------------------------------------------------------------
say "3. /home/dsh 属组"
HD=/home/dsh
if [ -d "$HD" ]; then
  if [ "$(stat -c %G "$HD")" != "$GRP" ]; then
    chgrp "$GRP" "$HD" 2>/dev/null && ok "$HD 属组 -> $GRP" || warn "chgrp $HD 失败(可忽略)"
  else
    ok "$HD 属组已是 $GRP"
  fi
  # 家目录权限:给同组可进入,但不要开放给其他人
  m="$(stat -c %a "$HD")"
  case "$m" in
    750|2770|770|2775) ok "$HD 模式 $m" ;;
    *) warn "$HD 模式是 $m(建议 750,便于同组访问)" ;;
  esac
fi

# ---------------------------------------------------------------------------
# 4. 全树属组复查
# ---------------------------------------------------------------------------
say "4. /home/Projects 属组复查"
if [ -d /home/Projects ]; then
  LEFT="$(find /home/Projects -mindepth 1 ! -gid "$GID" 2>/dev/null | wc -l)"
  echo "   不属于 $GRP 的对象: $LEFT"
  [ "$LEFT" -eq 0 ] && ok "全树归组正确" || warn "仍有 $LEFT 个例外(多为核心/探针文件)"
fi

# ---------------------------------------------------------------------------
# 5. 重启 dsh 会话的必要性说明
# ---------------------------------------------------------------------------
say "5. 让新主组生效"
echo "   usermod 只影响之后新启动的进程。请重启 dsh web:"
echo "     1) 停掉当前 dsh web 进程"
echo "     2) ssh dsh@127.0.0.1 'dsh web'"
echo "   或直接: loginctl terminate-user $USER_NAME  然后重新启动"
echo
echo "   验证新主组:"
echo "     ssh dsh@127.0.0.1 'id'          # 期望 gid=$GID($GRP)"

say "汇总"
[ "$FAIL" -eq 0 ] && printf '  完成,无致命失败。\n' || printf '  有 %d 项失败,见上文。\n' "$FAIL"
printf '  重启 dsh 后,请让 DSH 用 write 工具建一个文件,再于宿主机确认:\n'
printf '    stat -c "%%a %%U:%%G %%n" <该文件>   # 期望 660 dsh:agent\n'
exit 0
