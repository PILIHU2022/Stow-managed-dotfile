# DSH write 工具权限行为的实测结论

> 实测时间:2026-10-03
> 实测环境:宿主机 CachyOS,btrfs;`/home/Projects` 已完成 `chgrp -R agent` + setgid + default ACL
> 实测身份:`dsh`(uid 1002)—— DSH 的 bash 工具运行在 bwrap user namespace 内
> 触发问题:DSH 修改 Neovim(stow 管理)配置后,`user`(uid 1000)的 Neovim 提示新建文件无权限读取
>
> **修复状态:⚠️ 方案 A(`usermod -g agent dsh`)已作废** —— 实测本机沙箱
> `gid_map = 1005 -> 0`(长度 1),gid 1006 不可映射,改主组会导致 DSH 无法写文件。
> 现行方案是 **watcher 自动修权**(`scripts/share-watch.sh`),见第五节方案 C。
> DSH 自身无法执行任何需要 root 的修复(沙箱 `NoNewPrivs: 1`)。

---

## 一、一句话结论

**DSH 的文件写入工具会把文件的属组改成 `dsh` 的主组(`dsh`,gid 1005),从而破坏父目录 setgid 的组继承。**
这就是 user 读不到 dsh 新建文件的**真正根因** —— 与 `umask`、`setfacl`、ACL 掩码都无关。

> 修复方向:让 `dsh` 的**主组**变成 `agent`(方案 A),而不是继续在 ACL/umask 上找办法。

---

## 二、三个对照实验

### 实验 1:`write` 工具覆盖「已存在」的文件

```
基线: 660  dsh:agent   (属组是 agent)
```

用 `write` 工具覆盖后:

```
结果: 660  dsh:dsh     (属组退化成 dsh!)
      user::rw-
      group::rwx
      mask::rw-
      other::---
```

| 项目 | 结果 |
|---|---|
| 权限位 `660` | ✅ **被保留** |
| 属组 `agent` | ❌ **被重写为 `dsh`** |

> 权限位保住了,是因为源码里有 `existingMode` 逻辑(见第四节)。
> 但属组没保住 —— **这一条就足以让 user 失去访问**。

### 实验 2:`write` 工具「新建」文件

```
write 工具:  600  dsh:dsh     mask::---     ❌
bash 对照:   660  dsh:agent   mask::rw-     ✅
```

同一目录、同样有 setgid,**bash 继承到了父目录属组,`write` 工具没有**。

### 实验 3:目录确实带 setgid,不是它的问题

```
目录本身:  2770  dsh:agent        (setgid 已生效)
bash 新建: 660   dsh:agent   ← 继承成功
write 新建:600   dsh:dsh     ← 继承失败
```

**结论:setgid 是好的,是 `write` 工具的写入路径绕过了它。**

---

## 三、机制:临时文件 + rename

`write` 工具不是直接在目标位置写,而是**在目标目录创建临时文件、写入、再原子 rename 覆盖**:

```
目标目录/.tmp-<pid>-<uuid>   ← 创建 → 写入 → rename 到目标
```

关键点:

- rename **不是新建**,不触发父目录的 setgid 组继承;
- 临时文件拿到的是**进程的主组**(`dsh`,gid 1005),不是目录的组;
- 因此覆盖后属组变成 `dsh`,而 `user` 不在 `dsh` 组里 → 读不到。

无残留临时文件(`.tmp-*` 已被 rename 消费),符合上述判断。

---

## 四、源码依据

`node_modules/@anthropic-ai/sdk/tools/agent-toolset/fs-util.js`:

```js
/** Mode for directories the file tools create: owner-only under any umask. */
exports.DIR_CREATE_MODE = 0o700;                        // 第 21 行

/**
 * Mode for files the file tools create: owner-only, so other local users can't
 * read what an agent wrote. A file that already exists keeps its own mode.
 */
exports.FILE_CREATE_MODE = 0o600;                       // 第 26 行

async function atomicWriteFile(targetPath, content) {   // 第 150 行
    const dir = path.dirname(targetPath);
    const tempPath = path.join(dir, `.tmp-${process.pid}-${crypto.randomUUID()}`);
    const existingMode = await fs.stat(targetPath).then((st) => st.mode & 0o777, () => undefined);
    handle = await fs.open(tempPath, 'wx', exports.FILE_CREATE_MODE);   // 新建即 0600
    if (existingMode !== undefined)
        await handle.chmod(existingMode);               // 只还原「模式位」,不含属组
    await handle.writeFile(content, 'utf-8');
    await fs.rename(tempPath, targetPath);              // 原子替换
}
```

**注意 `chmod(existingMode)` 只还原权限位(`st.mode & 0o777`),完全不涉及属组** ——
所以"已存在文件保留自身模式"这条注释是**不完整的**:它保模式,不保属组。

---

## 五、修复方案

### ⛔ 方案 A 已作废:`usermod -g agent dsh` 在本机会搞坏 DSH

2026-10-05 实测 —— **不要再执行 `apply-dsh-primary-group.sh`**:

```
$ cat /proc/self/gid_map          # DSH 的 bash 沙箱内
      1005          0          1   <- 只映射 dsh 自己的 gid,长度 1
```

bwrap 把 `dsh` 的**主组**映射为容器内 gid 0。当前主组 `dsh`(1005)→ 映射 `1005 -> 0`。
若改成主组 `agent`(1006),映射将变成 `1006 -> 0`,而 **1006 不在原映射表内** ——
沙箱进程写文件时无法映射该 gid,极易以 `EINVAL` 失败。

**更关键:即便改成功也修不好问题。** 元凶是 `write` 工具自身:

```
open(tempPath, 'wx', 0600)   <- O_CREAT 掩码,umask 改不动它
  -> 父目录 setgid 的组继承被这次 open 吃掉
  -> 进程主组直接落到文件上
  -> ACL mask 被算成 000
  -> 随后的 chmod(existingMode) 只还权限位,不还属组
```

属组与 mode 都是 `write` 工具**自己定**的,与账号配置无关。

**结论**:本机唯一可行的自动化方案是下面的 **方案 C(watcher)**。

---

### 方案 A(原始设想,已作废 —— 仅存档)

> **执行状态:⛔ 已作废,勿执行。** 原脚本 `scripts/apply-dsh-primary-group.sh` 保留仅作参考。

```bash
sudo bash /home/Projects/scripts/apply-dsh-primary-group.sh   # ⛔ 勿执行
```

或手工等价的一条:

```bash
sudo usermod -g agent dsh
```

原理:临时文件由 `dsh` 进程创建,属组取**进程主组**。把主组设成 `agent` 后,
`write` 工具无论新建还是覆盖,产出的文件属组都是 `agent` → user 立刻可读。

补充要求(通常已满足):

```bash
sudo usermod -aG agent user     # user 也必须在 agent 组
```

生效方式:`usermod` 只影响**之后新启动**的进程,需要重启 `dsh web`:

```bash
# 在启动 dsh web 的那台机器上
loginctl terminate-user dsh          # 或直接断开重连 ssh 后重新启动
ssh dsh@127.0.0.1 'dsh web'
```

验证:

```bash
ssh dsh@127.0.0.1 'id'               # 主组应显示 gid=1006(agent)
```

**副作用提示**:`dsh` 主目录下之后新建的文件属组也会变成 `agent`。对这份共享场景无害;
若你希望 `dsh` 个人文件保持 `dsh` 组,改用方案 B/C。

#### 为什么这一步 DSH 自己做不到

`usermod` 需要 root,而 DSH 的 bash 工具运行在 bwrap user namespace 内。实测:

```
CapEff:     0000000000000000     <- 零能力
NoNewPrivs: 1                    <- setuid 提权被硬性禁用

$ sudo -n true
sudo: The "no new privileges" flag is set, which prevents sudo from running as root.
```

即"批准提权"也无效 —— 内核层面拒绝了。**因此方案 A 必须在宿主机的普通终端由你手动执行。**

### 方案 B:DSH 写共享文件时改用 bash

shell 创建的临时/目标文件会正确继承 setgid,因此完全遵循 POSIX 权限模型:

```bash
cat > path/to/file <<'EOF'
内容
EOF

printf '%s\n' "内容" > path/to/file
```

在 DSH 会话中直接要求:"写共享文件请用 heredoc,不要用 write 工具"。

### 方案 C(✅ 本机推荐):watcher 自动补权限

**现成脚本:`scripts/share-watch.sh`** —— 本机唯一可行的自动化方案。

它监听共享树,对**新建/rename 进来**的对象自动 `chgrp agent` + `chmod 0660/2770`
+ 修回被打成 `000` 的 ACL mask(这一步是 user 读不到的直接原因)。

**启动(一条命令,自动后台化):**

```bash
ssh dsh@127.0.0.1 'bash /home/Projects/scripts/share-watch.sh --auto /home/Projects'
```

启动时会先做一次**全量回填**(扫描并修好 watcher 未运行期间产生的所有缺口对象),
然后 `setsid` 脱离终端、写 PID 文件、日志落到 `/home/Projects/.share-watch.log`。

**体检 / 停止:**

```bash
ssh dsh@127.0.0.1 'bash /home/Projects/scripts/share-watch.sh --check /home/Projects'
pkill -f 'share-watch.sh run'
```

**自检**:拿不到 `agent` 组时脚本**拒绝启动**并给出正确命令 ——
避免像 `chgrp` 静默失败那样,让你误以为"已经在跑了"。

#### 为什么必须在"能看到 gid 1006 的会话"里运行?

常见误解:`dsh` 明明列在 `/etc/group` 的 `agent` 成员里,为什么还不行?

**因为"列在组里" ≠ "进程持有该组":**

```
getent group agent                    -> agent:x:1006:user,dsh   (成员列表有 dsh ✅)
grep ^Groups /proc/self/status        -> Groups: 65534 1005 65534 (实际凭证无 1006 ❌)
```

补充组在**登录时固化**。DSH 的 bash 工具跑在 bwrap user namespace 内,只保留了
`dsh` 自己的 gid,`agent` 被丢掉;且沙箱 `gid_map` 只映射 `1005`,1006 不可映射:

```
cat /proc/self/gid_map                -> 1005 0 1     (长度 1)
python3 -c 'import os; os.setgid(1006)'
  -> OSError: [Errno 22] Invalid argument
```

两种情况要分清:

| 操作 | 依据 | 沙箱内 |
|---|---|---|
| 新建文件**继承**父目录组 | 目录的 **setgid 位**(文件系统行为) | ✅ 有效(bash 写入得 `660 dsh:agent`) |
| 显式 `chgrp agent` | **进程组列表**必须含 1006 | ❌ 失败 |

`ssh dsh@127.0.0.1` 的登录会话会带上 `/etc/group` 里的全部补充组,所以能干活。
`sudo -u dsh` 与 systemd 服务默认**不给补充组**,必须显式 `SupplementaryGroups=agent`
—— 这正是 `--install-service` 单元里固定写上它的原因。

**开机自启**(可选,避免每次手动启动):

```bash
# 在宿主机的 dsh 会话里执行一次
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/share-watch.service <<'EOF'
[Unit]
Description=Auto-fix shared permissions for /home/Projects

[Service]
ExecStart=/home/Projects/scripts/share-watch.sh /home/Projects
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now share-watch.service
loginctl enable-linger dsh     # 需要 root;让用户服务在未登录时也运行
```

> `Restart=always` 很关键:DSH 沙箱重启或会话切换时 watcher 会随之重启,
> 重启后自动回填,不会留下缺口。

#### 下面是不使用现成脚本时的手工版本(存档)



以 root 运行,监听共享树,新建即修正属组与 ACL 掩码:

```bash
#!/usr/bin/env bash
# /usr/local/bin/dsh-share-fixperm.sh
set -uo pipefail
ROOT="${1:-/home/Projects}"; GROUP=agent
inotifywait -m -r -q --format '%w%f' -e create -e moved_to "$ROOT" | while IFS= read -r f; do
  [ -e "$f" ] || continue
  chgrp "$GROUP" "$f" 2>/dev/null
  if [ -d "$f" ]; then
    chmod 2770 "$f" 2>/dev/null
    setfacl -m 'd:u::rwx,d:g::rwx,d:m::rwx,d:o::---' "$f" 2>/dev/null
  else
    chmod 0660 "$f" 2>/dev/null
    setfacl -m 'm::rw-,g::rw-,u::rw-,o::---' "$f" 2>/dev/null   # 修回被打成 --- 的 mask
  fi
done
```

```ini
# /etc/systemd/system/dsh-share-fixperm.service
[Unit]
Description=Fix permissions for shared /home/Projects
[Service]
ExecStart=/usr/local/bin/dsh-share-fixperm.sh /home/Projects
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
```

```bash
sudo apt install inotify-tools        # 或 pacman -S inotify-tools
sudo systemctl daemon-reload && sudo systemctl enable --now dsh-share-fixperm
```

### ⚠️ 已知坑:归一化会抹掉可执行位

早期版本的修复脚本把"dsh 拥有的文件"统一 `chmod 0660`,**连 x 位一起抹掉**。
实测被改坏的文件:

```
scripts/*.sh                              (本仓库脚本)
Blog/themes/FixIt/build.sh                (#!/usr/bin/env bash)
Blog/scripts/install-dart-sass.mjs        (#!/usr/bin/env node)
```

现已修正为:属主位本来有 `x` → `0770`,否则 → `0660`。
自查命令:

```bash
find /home/Projects -name .git -prune -o -type f \
  \( -name '*.sh' -o -name '*.py' -o -name '*.mjs' -o -name '*.bash' \) ! -perm -0100 -print
# 对每个结果确认首行是否为 shebang(#!),是则应恢复: chmod 0755 <文件>
```

> 注意:`fuse.mjs` 这类无 shebang、被代码 `import` 的 `.mjs` **不应**加 x 位,
> 判断依据是**首行是否有 `#!`**,而不是扩展名。

---

### 方案 D(不推荐):改安装目录里的常量

```js
exports.FILE_CREATE_MODE = 0o600;   // → 0o660
```

**不建议**:属于打包产物,`npm/pnpm` 升级或 `dsh plugin` 重装即被覆盖;
且这是 SDK 层刻意的安全设计("other local users can't read what an agent wrote")。

---

## 六、三个必须知道的规避技巧

### 1. 「先建后写」可以绕过属组问题

`write` 工具覆盖已存在文件时会沿用其**模式**(`existingMode`),所以在 shell 侧
先把文件建好(拿到正确的 `agent` 属组与 `0660` 模式)之后,DSH 再编辑就不会出问题。

```bash
# user 或 dsh 侧先执行
touch path/to/file && chmod 0660 path/to/file
```

之后 DSH 用 `write` 工具反复编辑该文件,模式保持不变。
**但注意**:实验 1 显示属组仍会被改成 `dsh` ——
除非已执行方案 A。所以这个技巧在**方案 A 生效后**才是完整可靠的。

### 2. `write` 工具的产物在 ACL 层面是「锁死」的

新建文件的 `mask` 被算成 `---`:

```
user::rw- / group::rwx / mask::--- / other::---
```

`mask` 是 ACL 的**有效权限上限**,`mask::---` 意味着即使写了 `group:agent:rwx`
也一分权限都不生效。**只有属主和 root(CAP_DAC_OVERRIDE)能绕过 mask** ——
而 DSH 在 bwrap 沙箱里连 root 都拿不到(`CapEff: 0` + `NoNewPrivs: 1`)。

所以:**别指望用 `setfacl` 补救 `write` 工具的产物**,必须从写入路径(方案 A/B/C)解决。

### 3. 新目录同样会复发(2026-10-04 实测:`Blog` 案例)

只要 DSH 在共享树里**新建一个目录并往里写文件**,同一个缺陷就会原地复发。
`/home/Projects/Blog` 就是这样被创建的,随后 `user` 执行 `hugo` 时报:

```
ERROR failed to load config: "/home/user/Projects/Blog/hugo.toml:1:1":
  open /home/user/Projects/Blog/hugo.toml: permission denied
```

**注意:这与软链接(`/home/user/Projects` → `/home/Projects`)无关。**
实测该文件本身:

```
600  dsh:dsh(1002:1005)     /home/Projects/Blog/hugo.toml
user::rw- / group::rwx / mask::--- / other::---
```

同目录下同类文件:`archetypes/{default,posts}.md`、`package.json`、
`scripts/install-dart-sass.mjs`、`.gitignore`、`README.md`;
另有 `public/`、`public/lib` 被 hugo 建成 `2750`(user 无法写入)。

**为什么"改了 660 也还是不行"**:`660` 要求**属组必须是 user 的组**。
若属组仍是 `dsh`(1005),user 会落到 `other` 分支,而 `other=0` → 依旧 permission denied。
数字判据:

```
属主 uid=1002(不是 user 1000)
属组 gid=1005(不在 user 的组集合 {998,964,966,994,1006} 内)
  -> user 走 other 分支 -> 有效权限 = mode & 0o7 = 0 -> 拒绝
```

**修复(必须在能看到 gid 1006 的会话里执行)**:

```bash
# 通用脚本,对任意子树生效,幂等
ssh dsh@127.0.0.1 'bash /home/Projects/scripts/fix-share-perms.sh /home/Projects/Blog'
# 或宿主机 user 终端(若文件属主是 user):
bash /home/Projects/scripts/fix-share-perms.sh /home/Projects/Blog
```

脚本做四件事,且**只处理缺口对象**:

1. 属主是本用户的对象 → `chgrp agent`
2. 组位无任何权限的对象 → 目录 `2770`、文件 `0660`
3. 所有目录补 `setgid`
4. 所有目录补 `default ACL`(含 `d:m::rwx`,避免 mask 被压成 `---`)

它内置**能力自检**:若当前会话看不到 gid 1006(例如在 DSH 沙箱内),
会明确警告"第 1 步会失败"并给出正确命令 —— 因为**沙箱里 `chgrp agent`
必然以 `EINVAL` 失败,很容易误判成"已修好"**。

**根治仍然是方案 A**:`sudo usermod -g agent dsh`。
否则每新建一个目录、每写一个文件,都要再手动跑一次修复。

---


---

## 七、与"朋友方案"的逐条对照(2026-10-05 重抓聊天记录后)

用无头 Firefox + geckodriver 重新抓取并逐页核对后,结论如下。

### 朋友方案的真实内容

| 页面 | 内容 | 与本机的关系 |
|---|---|---|
| `doc-1` | btrfs 是否支持 ACL | 本机 btrfs 支持,已可用 |
| `doc-2` | 多用户共享目录放哪 + `chmod 2775` setgid | 与本机做法一致 ✅ |
| `doc-3` | SSH 回环 + `%agent NOPASSWD` sudoers | 本机**没有** `/etc/sudoers.d/agent` |
| `doc-4` | `ssh dsh@127.0.0.1 'dsh web'` 命令变体 | 与本机一致 ✅ |
| `doc-5` | ACL 方案主体(`setfacl -d`,`umask 002`) | 本机已落地 ✅ |

### 决定性差异:朋友**从未使用 `write` 工具**

逐页检索 `doc-5`(1289 行)全文:朋友的**所有**文件操作都是
`touch` / `mkdir` / `mv` / `cp -a` / `setfacl` —— **`write`/`edit` 工具一次都没出现**。

而 shell 创建的文件会**正确继承目录的 setgid 组**(本机实测 `660 dsh:agent` ✅)。
所以朋友的方案对他有效,与本机差异**不在账号配置,而在"谁来创建文件"**。

### 因此:照搬朋友的配置**无法**解决本机问题

朋友方案里与本机不同的只有两处,而**两处都不能修好它**:

1. **`/etc/sudoers.d/agent`(免密 sudo)** —— 本机没有。
   但即使补上也**无效**:DSH 的 bash 沙箱设了 `NoNewPrivs: 1`,
   实测 `sudo` 报 `The "no new privileges" flag is set`,
   **内核层面拒绝 setuid 提权**,sudoers 规则再宽也进不去。
2. **`usermod -g agent dsh`** —— 见第五节,**本机会搞坏 DSH**(gid_map 限制),
   且即便成功也修不好 `write` 工具自定的属组与 mode。

### 唯一能让"不再需要额外操作"的办法:watcher

```bash
# 一次性:在宿主机以 dsh 身份启动(会自动做全量回填)
ssh dsh@127.0.0.1 'setsid nohup bash /home/Projects/scripts/share-watch.sh \
  >/tmp/share-watch.log 2>&1 &'
```

之后 DSH 无论用 `write` 工具还是 shell 创建文件,**user 都直接可读写**,无需任何手工 chmod。
详见第五节方案 C。

---

## 八、验证清单

> 前置:watcher 已启动(方案 C)。若未启动,`write` 工具的产物仍需手工修权。

```bash
# 1. 确认 watcher 在跑,且它能看到 agent 组
ssh dsh@127.0.0.1 'id -G | tr " " "\n" | grep -x 1006 && echo OK'
ssh dsh@127.0.0.1 'pgrep -af share-watch.sh'

# 2. 让 DSH 用 write 工具新建一个文件,然后在宿主机看
stat -c '%a %U:%G %n' /home/Projects/<某个新文件>
#   期望(watcher 生效): 660 dsh:agent   -> user 可读可写

# 3. 以 user 实际读取
cat /home/Projects/<该文件>        # 期望无 Permission denied

# 4. 全树体检
bash /home/Projects/scripts/verify-shared-perms.sh /home/Projects

# 5. 统计仍是 dsh(1005) 组的文件 —— watcher 生效时该值应稳定为 0
find /home/Projects -gid "$(getent group dsh | cut -d: -f3)" -type f 2>/dev/null | wc -l
```

---

## 九、附:历史状态(供对照)

| 项目 | 修复前 | 修复后 |
|---|---|---|
| `/home/Projects` 顶层 | 属组 `nobody`,ACL 含非法条目 `group:4294967295` | `user:agent 2770` + 正确 default ACL |
| 全树属组 | 只有 2918 / 68295 属于 `agent` | **0 个例外** |
| `setfacl` 可用性 | 因 `Duplicate entries` 完全失败 | 正常 |
| `write` 工具产物模式 | `600 dsh:dsh`,`mask::---` | `600 dsh:dsh` → 由 watcher 自动改为 `660 dsh:agent` |

### 待办

```
✅ scripts/share-watch.sh          # 已就绪,启动即自动回填
⏳ ssh dsh@... 'setsid nohup bash scripts/share-watch.sh ... &'   # 需你启动一次
⏳ (~可选) systemd --user 开机自启
⏳ chmod 2770 /home/Projects/Gadgetbridge/.adbhome   # 属主是 user,无需 sudo
```

> 相关文档同目录:`dsh-user-migration-and-workspace-permissions.md`、
> `dsh-pnpm-store-mismatch-after-user-migration.md`。
> 可执行脚本统一放在 `/home/Projects/scripts/`:`share-watch.sh`(方案 C,推荐)、
> `fix-share-perms.sh`(修复任意子树,默认跳过 `.git`)、`verify-shared-perms.sh`(体检)、
> `dsh-finish-share-fix.sh`(收尾)、`apply-dsh-primary-group.sh`(⛔ 已作废)。
> 完整诊断报告位于 `/home/Projects/Docs/dsh-shared-permission-fix.md`。
