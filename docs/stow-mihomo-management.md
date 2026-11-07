# 用 GNU Stow 管理 mihomo 配置：可行性、风险与方案

> 主机 `host` ｜ GNU Stow 2.4.1 ｜ systemd 262.1-1-arch ｜ mihomo 1.19.33 (Meta, `with_gvisor`)
> 仓库 `/home/user/Projects/Stow-Dotfile`（**注意**：仓库内旧文档写的 `/home/Projects/Stow-Dotfile` 已过时；`/home/Projects` 目录还在，但里面没有 `Stow-Dotfile`。下文命令一律使用实际路径）
> 研究时间 2026-11-07 22:46–22:55；**全程未使用 root、未改 `/etc`、未重启/停止 mihomo**。所有写入实验只在 `.dsh-scratch-stow/` 内完成，结束前已删除。
> 研究限制：无 root，因此 `stow -t /` 的**写操作**没有真跑；`/` 目标的结论来自只读 `-n` dry-run + 权限检查 + stow 语义。systemd 行为依据 `systemd.exec(5)` 手册与本机 systemd 262 源码（v262 tag）。

---

## 0. 一句话结论

- **能，但只有一种写法可行**：让 `mihomo` 包**只 stow `etc/mihomo/config.yaml` 一个文件**到 `/`，并且必须配 `--no-folding` + 白名单 ignore。
- **整包 `stow -t / mihomo` 不可行**：真实 `/etc/mihomo` 里 39 个同名文件**全部冲突**；stow 2.4.1 是两阶段算法，发现冲突后 `All operations aborted`，**一个文件都不改**（安全，但达不到目的）。要强行跑通只能 `--adopt` 或先删 live 文件，前者会把 `/etc` 真实文件反向搬进仓库覆盖源码，绝对不要用。
- **stow 不能消除 restart**：`LoadCredential=` 只在服务启动时读 `/etc/mihomo/config.yaml`，`ExecStartPre=/usr/lib/mihomo/start` 再把 credential 复制进 StateDirectory。改仓库后仍然必须 `systemctl restart mihomo`。
- **权限模型会变**：`/etc/mihomo/config.yaml` 从「root 独占的 `0600` 普通副本」变成「指向 user 可写仓库的相对软链」，实际权限=仓库文件的 `660 user:wheel`（+ 工作区 ACL）。root 下次启动时读的就是 user 可写的内容——这是本方案最重要的安全边界变化。
- **建议**：**A（只 stow config.yaml）是唯一可行的 stow 路线**；若更看重「0600 独立副本 / 启动不依赖 `/home` / 低风险」，选 **B（保留 `install -m 0600`、脚本化并加内容校验）**；**C（整包 stow）不建议**。只为了少打一条 `install` 就把 live 配置改成软链，**不划算**；只有把「仓库即唯一源、`/etc` 只是它的视图」当硬需求时，A 才值得。

---

## 1. 仓库与部署现状（证据）

### 1.1 仓库确实是标准 GNU Stow 布局

```bash
$ ls -d */ | wc -l                 # 36 个顶层 package：aria2/ hypr/ kitty/ nvim/ zsh/ mihomo/ etc/ ...
$ find ~/.config -maxdepth 1 -type l -lname '*Stow-Dotfile*' | wc -l
16
$ ls -l ~/.config/aria2 ~/.config/kitty
lrwxrwxrwx ... /home/user/.config/aria2 -> ../Projects/Stow-Dotfile/aria2/.config/aria2
lrwxrwxrwx ... /home/user/.config/kitty -> ../Projects/Stow-Dotfile/kitty/.config/kitty
```

- 用户级 dotfiles 走 stow，目标是 `$HOME`，软链是 **stow 生成的相对软链**（`man stow`：「Stow only creates relative symlinks」）。
- 仓库根没有 `.stow-local-ignore`（`find . -maxdepth 2 -name .stow-local-ignore` 为空），即当前用的是 stow 内置默认 ignore 列表。
- `etc/` 这个 package 也是「`etc/etc/doas.conf` → `/etc/doas.conf`」的布局，说明仓库本来就有「准备将来 stow 到 `/`」的意图，只是从没在 `/` 上真跑过。

### 1.2 `mihomo` 包现状：可部署配置和运行时数据混在一起

```bash
$ ls mihomo/etc/mihomo/
ASN.mmdb  cache.db  config-2026-07-21_back.yaml  config-2026-07-22_Back.yaml
config-default.yaml  config-ds-2026-07-20_back.yaml  config-DS-2026-07-21_18Back.yaml
config-DS.yaml  config.example.yaml  config.yaml  GeoIP.dat  GeoSite.dat
profiles/  rule_set/  ui/

$ git ls-files mihomo/
mihomo/etc/mihomo/config-2026-07-21_back.yaml
mihomo/etc/mihomo/config-2026-07-22_Back.yaml
mihomo/etc/mihomo/config-DS-2026-07-21_18Back.yaml
mihomo/etc/mihomo/config-DS.yaml
mihomo/etc/mihomo/config-default.yaml
mihomo/etc/mihomo/config-ds-2026-07-20_back.yaml
mihomo/etc/mihomo/config.example.yaml
```

包内共 **39 个普通文件**（`mihomo/etc/mihomo/` 顶层 12 个 + `rule_set/` 下 27 个），但 Git 只跟踪其中 7 个；下面这些是**运行时数据或敏感文件**，被 `.gitignore` 排除（引用 `.gitignore` 原文）：

| 被忽略的对象 | `.gitignore` 行 | 性质 |
| --- | --- | --- |
| `**/mihomo/config.yaml` | 第 32 行 | **真实订阅 token 所在**，只本地保留 |
| `**/mihomo/cache.db` | 第 33 行 | mihomo BoltDB 缓存（缓存了订阅 URL） |
| `**/mihomo/ASN.mmdb` `GeoIP.dat` `GeoSite.dat` `Country.mmdb` | 第 19–22 行 | geo 数据库（运行时按 `geox-url` 重下） |
| `**/mihomo/profiles/` `profile/` `rule_set/` | 第 23–26 行 | provider 快照 / rule-set 运行时下载缓存 |

也就是说：**这个 package 不是「配置包」，而是「整份 `/etc/mihomo` 的镜像 + 运行时数据」**。这直接决定了整包 stow 一定会撞上「目标已有同名普通文件」。

### 1.3 现在的线上部署方式（`install` 复制，不是 stow）

```bash
# 文档 docs/mihomo-config-structure.md §6 的现状命令（路径已过时，实际仓库在 /home/user/Projects）
doas cp -a /etc/mihomo/config.yaml "/etc/mihomo/config.yaml.bak.$(date +%Y%m%d-%H%M%S)"
doas install -m 0600 -o root -g root \
  /home/user/Projects/Stow-Dotfile/mihomo/etc/mihomo/config.yaml /etc/mihomo/config.yaml
doas systemctl restart mihomo
```

线上 `/etc/mihomo` 的实测状态：

```bash
$ stat -c '%n %a %U:%G %s %F' /etc/mihomo/config.yaml
/etc/mihomo/config.yaml 600 <root> <root> 29499 普通文件     # 沙箱里 uid 显示为 nobody；实际属主 root
$ ls -la /etc/mihomo/ | head
... config.yaml.bak.20261101-122800  config.yaml.bak.20261101-124538
... config.yaml.bak.20261101-124622  config.yaml.bak.20261107-223544
... Country.mmdb -> /etc/clash/Country.mmdb          # target-only 的绝对软链
... profiles/  rule_set/  ui/                        # 真实目录
```

`/etc/mihomo` 里还有 5 个仓库里没有的条目（4 个 `config.yaml.bak.*` 备份 + `Country.mmdb` 软链）。另外注意 **`config-*.yaml` 那几份历史备份在线上和仓库里尺寸/时间都不同**（例如 `config-2026-07-21_back.yaml`：线上 14404B / 仓库 14352B），说明它们本来就不是「部署目标」，只是历史存档。

> 研究期间还实测到一次真实的 drift：采样时刻 `/etc/mihomo/config.yaml` 是 29499B@22:35，仓库 `mihomo/etc/mihomo/config.yaml` 是 27822B@22:46（研究期间仓库文件被并发修改过）。不管是哪边先动，**复制式部署没有任何版本校验，天然存在漂移窗口**——这正是 B 方案必须加 `cmp` 校验的原因。

### 1.4 仓库文档里已有的 stow 记载（及过时点）

| 文档 | 内容 | 对本次的可用性 |
| --- | --- | --- |
| `docs/systemd-units-review-and-modularization.md` §3.2 / §5.2 | 用户级包改用 stow 的完整做法；`--no-folding` 让 `.wants/` 成为真实目录；**不要用 `--adopt`** | 方法论可复用；它 stow 到 `$HOME`，不涉及 `/etc` |
| `docs/file-dialog-ime-and-clipboard.md` §5.1 | 整包 stow 冲突的两类根因：live 是真实文件（`cannot stow … since neither a link nor a directory`）、源里有绝对软链（`source is an absolute symlink`）；`--adopt` 会把真实文件搬进仓库 | 与本机 `/etc/mihomo` 的情况**一模一样**（本次实测 39 条同款冲突） |
| `docs/dsh-user-migration-and-workspace-permissions.md` 第 278 行起 | stow 命令模板（`-d/-t/-nv/--restow`）、相对软链、`stow -D` 回滚 | 模板可用，但**路径是旧 `/home/Projects`**；且「`sudo -u user`」只适用于目标是 `$HOME` 的场景，stow 到 `/` 必须 root |
| `docs/mihomo-config-structure.md` §1 / §6 | 部署链（LoadCredential → state dir）、`install -m 0600` 部署与回滚 | 部署链是本次分析的核心依据；命令路径需把 `/home/Projects` 换成 `/home/user/Projects` |

---

## 2. 部署链与 systemd 行为：决定可行性的硬约束

### 2.1 真实链路（有据可查）

`/usr/lib/systemd/system/mihomo.service`（节选，原文）：

```ini
[Service]
Type=simple
DynamicUser=yes
StateDirectory=mihomo
StateDirectoryMode=0700
ExecStartPre=/usr/lib/mihomo/start
ExecStart=/usr/bin/mihomo -d "$STATE_DIRECTORY"
LoadCredential=config.yaml:/etc/mihomo/config.yaml
ProtectSystem=strict
ProtectHome=yes
UMask=077
```

`/usr/lib/mihomo/start`（全文）：

```bash
#!/usr/bin/bash

install "${CREDENTIALS_DIRECTORY}/config.yaml" "${STATE_DIRECTORY}"/config.yaml
install /etc/clash/Country.mmdb -t "${STATE_DIRECTORY}"
```

链路：

```
仓库 mihomo/etc/mihomo/config.yaml（user 660）
        │  ① doas install -m 0600 -o root -g root  ← 现状；若改 stow，这里变成软链
        ▼
/etc/mihomo/config.yaml  ← ② 服务启动时 LoadCredential=config.yaml:/etc/mihomo/config.yaml 读它
        ▼
$CREDENTIALS_DIRECTORY/config.yaml（/run/credentials/mihomo.service/config.yaml，只读、按 unit 隔离）
        │  ③ ExecStartPre=/usr/lib/mihomo/start  install 到 $STATE_DIRECTORY
        ▼
/var/lib/private/mihomo/config.yaml  ← ④ 真正被 mihomo 加载的那份（/var/lib/mihomo → private/mihomo）
        ▼
mihomo -d "$STATE_DIRECTORY"
```

关键推论：

1. **`/etc/mihomo/config.yaml` 只在 service 启动瞬间被读一次**（②）。改仓库后不 restart 不生效；`systemctl reload` 也无效（unit 没有 `ExecReload=`）。
2. **mihomo 运行时写的是 StateDirectory，不是 `/etc`**（`-d "$STATE_DIRECTORY"`；`/var/lib/private/mihomo` 是 `0700` DynamicUser 家目录，普通用户进不去）。所以「stow 折叠目录后 mihomo 把 `cache.db` 写回仓库」这个担心**对运行时数据不成立**——但这只对「运行时不读 `/etc`」成立；如果整包 stow，`/etc/mihomo/*` 会变成指向仓库文件的软链，**任何写 `/etc/mihomo` 的行为仍会写回仓库**（只是目前没有这样的行为）。
3. `DynamicUser=yes` + `LoadCredential` 的组合本身就是为「让不存在的动态 UID 读到特权文件」设计的，**credential 的读取者是 service manager/exec 子进程（root），不是 unit 内的 DynamicUser**（见 2.2/2.3）。

### 2.2 `LoadCredential` 跟不跟软链？→ **跟**

- `systemd.exec(5)`（本机手册，`/usr/share/man/man5/systemd.exec.5.gz`）原文：
  > "If the specified path is absolute it is opened as regular file and the credential data is read from it."
  > "When loading from a directory, symlinks will be ignored."（只有从**目录**加载时忽略软链；单文件路径没这个限制）
  > "The credential files/IPC sockets must be accessible to the service manager, but do not have to be directly accessible to the unit's processes: the credential data is read and copied into separate, read-only copies for the unit …"
- 本机 systemd 262 源码（v262 tag）路径：
  - `src/core/exec-credential.c` 的 `load_credential()` 对绝对路径走 `read_full_file_full()`（[exec-credential.c#L710](https://github.com/systemd/systemd/blob/v262/src/core/exec-credential.c#L710)）；
  - `src/basic/fileio.c`：`read_full_file_full()`（[#L864](https://github.com/systemd/systemd/blob/v262/src/basic/fileio.c#L864)）→ `xfopenat_full()` → `xfopenat_regular()` 用 **`fopen(path, "re")`**（[#L1056](https://github.com/systemd/systemd/blob/v262/src/basic/fileio.c#L1056)）；
  - `fopen()` 不会加 `O_NOFOLLOW`，**因此会跟随软链**。

**结论**：`/etc/mihomo/config.yaml` 是软链时，systemd 读到的是仓库文件的内容。这一点不构成障碍。

### 2.3 `ProtectHome=yes` 会不会挡住 root 读 `/home/user`？→ **不会（v262 实测源码顺序）**

- `ProtectHome=yes` 是**挂载到 unit 的 mount namespace 里**的（把 `/home` 等目录用空 tmpfs 遮住），它只影响 unit 进程，不影响 service manager 在启动前读取 credential 源文件。
- v262 源码顺序（[exec-invoke.c](https://github.com/systemd/systemd/blob/v262/src/core/exec-invoke.c)）：
  - `exec_setup_credentials()` 在 **L5863** 调用；
  - 应用 mount namespace（`setup_delegated_namespaces()` → `apply_mount_namespace()`，ProtectHome 在这里生效）第一次调用在 **L6094**，第二次在 **L6195**。
  - 即：**先读 credential、后套沙箱**。所以 `ProtectHome=yes` 不会让 credential 源变成不可读。
- `/home/user` 是 `0700 user:wheel`，但此时执行读取的仍是 **root**（PID1 fork 出的 exec 子进程，尚未 drop privilege）：root 有 `CAP_DAC_OVERRIDE`，**700 目录挡不住 root**。
- ⚠️ 这是 **systemd 262 的实现顺序**，属于实现细节。将来大版本升级后若要长期依赖 A 方案，应重新回归一次（升级后先用 `stow -n` + 一次 restart 验证）；B 方案没有这个依赖。

补充：`ProtectHome` 的语义来自 `systemd.exec(5)`「ProtectHome=」条目；root 权限模型来自 POSIX（`CAP_DAC_OVERRIDE`）。这两条决定了 A 方案「root 能读 `/home/user/.../config.yaml`」。

### 2.4 `/etc` 属 root，stow 必须 root 运行；root 跑 stow 会不会改仓库?

```bash
$ test -w /etc && echo writable || echo "NOT writable"
NOT writable
$ test -w /etc/mihomo && echo writable || echo "NOT writable"
NOT writable
```

- 所以 `stow -t /` 必须 `doas`/`sudo`（本机 `doas`、`sudo` 都在，仓库文档习惯用 `doas`）。
- **stow 作为 root 运行不会改仓库文件的所有者/权限**：stow 只读 stow 目录、只写 target（创建目录/软链）；`man stow` 明确「Stow will never delete any files, directories, or links that appear in a Stow directory」。
- **唯一例外是 `--adopt`**：它的实现是 `File::Copy::move` 把 target 文件搬到 package 里（`/usr/share/perl5/vendor_perl/Stow.pm` 的 `do_mv`/`move`），跨文件系统时退化为「复制+删除」。以 root 执行会把 **root 属主**的文件写进仓库——详见 §3.5。
- 另外，root 创建的 `/etc` 目标目录/软链属主是 root（这是正常的）；不要对 `/etc/mihomo` 做 `chown -R` 之类的收尾（chown 默认不跟随软链，但 `-R` 会递归真实目录，容易误伤）。

### 2.5 修改后何时生效：**必须 restart**

- `LoadCredential` 在 start 时读取；`ExecStartPre` 在 start 时复制。两者都只在 **start/restart** 发生。
- 因此：改仓库 `config.yaml` → `doas systemctl restart mihomo` → 验证（`curl -s http://127.0.0.1:9090/version` 等，见 `docs/mihomo-config-structure.md` §6）。
- 重启前先跑 `mihomo -t -f mihomo/etc/mihomo/config.yaml -d /tmp/cfgtest` 做语法校验（文档 §6 的部署纪律：先 `-t` 再 restart）。

---

## 3. 实验：在假目标树上复现真实 `/etc/mihomo`

### 3.1 实验设置

- 在仓库内 `.dsh-scratch-stow/` 搭假目标树 `root/etc/mihomo/`，放**普通文件**模拟线上：`config.yaml`（0600）、`GeoSite.dat`、`GeoIP.dat`、`ASN.mmdb`、`cache.db`、`config.example.yaml`、`config-DS.yaml`、`config-default.yaml`、`rule_set/others/ad_reject_1.txt`、`config.yaml.bak.*`、`Country.mmdb`（软链）、空目录 `profiles/` `ui/`。
- 破坏性实验（`--adopt`）用 `.dsh-scratch-stow/stowroot/` 里的**包副本**，绝不碰真仓库。
- `-d` 用真仓库，`-t` 用 `.dsh-scratch-stow/root*`；只读 dry-run 直接对真实 `/` 跑（`-n` 不写盘）。

### 3.2 整包 stow：39 处冲突 → 全量 abort

真实 `/` 的只读 dry-run（**非 root 也能跑**，因为 `-n` 不写）：

```bash
$ stow -d /home/user/Projects/Stow-Dotfile -t / -nv mihomo
WARNING! stowing mihomo would cause conflicts:
  * cannot stow home/user/Projects/Stow-Dotfile/mihomo/etc/mihomo/ASN.mmdb over existing target etc/mihomo/ASN.mmdb since neither a link nor a directory and --adopt not specified
  * cannot stow .../config.yaml over existing target etc/mihomo/config.yaml since neither a link nor a directory and --adopt not specified
  ...（共 39 条，包内 39 个普通文件全部命中）
All operations aborted.
$ echo $?
1
```

在假目标树上用**非** dry-run 真跑一次，前后 `find` 全树对比（`before.txt` vs `after.txt`）**完全一致**：

```bash
$ stow -d "$PWD" -t "$PWD/.dsh-scratch-stow/root" -v mihomo
...
WARNING! stowing mihomo would cause conflicts:
  * cannot stow ../../mihomo/etc/mihomo/config.yaml over existing target etc/mihomo/config.yaml ...
All operations aborted.
$ diff before.txt after.txt && echo "NO FILESYSTEM CHANGES"
NO FILESYSTEM CHANGES
```

依据（`/usr/share/info/stow.info.gz` §7.1「Deferred Operation」原文）：

> "Since version 2.0, Stow now adopts a two-phase algorithm, first scanning for any potential conflicts before any stowing or unstowing operations are performed. If any conflicts are found, they are displayed and then Stow terminates without making any modifications to the filesystem."

**意义**：stow 本身是安全的（不会半途弄坏 `/etc`），但「整包 stow」也就完全不可用——除非把 39 个同名文件都删掉或 `--adopt`，而这两条路都不可接受（见 §3.5、§4）。

### 3.3 目录折叠：默认会造出「整目录软链」，必须 `--no-folding`

假设目标树里 `/etc` 存在、但 `/etc/mihomo` **不存在**（新机器 / 第一次 stow），默认折叠行为：

```bash
# 假目标 rootB 里只有空 etc/
$ stow -d "$PWD" -t "$PWD/.dsh-scratch-stow/rootB" -v mihomo
LINK: etc/mihomo => ../../../mihomo/etc/mihomo
```

结果：`rootB/etc/mihomo` 是**一个指向仓库目录的软链**，不是真实目录。加 `--no-folding`：

```bash
$ stow -d "$PWD" -t "$PWD/.dsh-scratch-stow/rootC" -v --no-folding mihomo
MKDIR: etc/mihomo
LINK: etc/mihomo/config.yaml => ../../../../mihomo/etc/mihomo/config.yaml
LINK: etc/mihomo/GeoIP.dat => ../../../../mihomo/etc/mihomo/GeoIP.dat
...
MKDIR: etc/mihomo/rule_set/sukkaw_ruleset
LINK: etc/mihomo/rule_set/sukkaw_ruleset/ai_non_ip.txt => ../../../../../../mihomo/etc/mihomo/rule_set/sukkaw_ruleset/ai_non_ip.txt
...
```

**真实 `/` 上的相对链接长这样**（用不冲突的 probe 包对真实 `/` 做 `-n`，stow 自己算出来的）：

```bash
LINK: etc/mihomo/probe-would-link.txt => ../../home/user/Projects/Stow-Dotfile/.dsh-scratch-stow/stowroot/probe/etc/mihomo/probe-would-link.txt
LINK: etc/stow-probe-nonexist => ../home/user/Projects/Stow-Dotfile/.dsh-scratch-stow/stowroot/probe/etc/stow-probe-nonexist   # 整目录折叠形态
```

所以 A 方案部署后，`/etc/mihomo/config.yaml` 会是：

```
../../home/user/Projects/Stow-Dotfile/mihomo/etc/mihomo/config.yaml
```

（2 层 `..` 回到 `/`，再进 `/home/...`；`stow` 只生成相对软链，这一点与用户级 dotfiles 一致。）

**折叠风险**：如果哪天 `/etc/mihomo` 不存在时有人跑了默认（折叠）stow，`/etc/mihomo` 会变成指向 user 可写仓库的**整目录软链**——对 `/etc` 下由 root 服务读取的目录，这是绝不能接受的形态。**A 方案必须始终带 `--no-folding`**（本机 `/etc/mihomo` 已存在时不会折叠，但防御性参数不能省）。

### 3.4 已有普通文件：不会被覆盖，只会冲突

- 目标已有**真实目录**（`/etc/mihomo`、`/etc`）时，stow **不会替换/搬走目录**，而是下钻逐项处理；同名普通文件产生 §3.2 的冲突，冲突即整体 abort。
- 目标已有**指向同一个源的软链**时不算冲突（幂等）：

```bash
$ stow -d "$PWD" -t "$PWD/.dsh-scratch-stow/rootE" --no-folding -v mihomo   # 第二次
# 无输出、exit 0
```

**结论**：stow 不会「把 `/etc/mihomo` 整个目录替换或搬走」（除非目标目录缺失 + 折叠，见 §3.3；或有人手动删目录）。这一点风险可控，但**不能**用来做「从现状平滑接管」——live 文件必须由人先挪走。

### 3.5 `--adopt` 的真实语义（危险，绝对不要用）

在 scratch 的包副本上实测（目标 `rootD/etc/mihomo/config.yaml` 是真实文件）：

```bash
$ stow -d "$PWD/.dsh-scratch-stow/stowroot" -t "$PWD/.dsh-scratch-stow/rootD" -v --adopt mihomo-tiny
MV: etc/mihomo/config.yaml -> ../stowroot/mihomo-tiny/etc/mihomo/config.yaml
LINK: etc/mihomo/config.yaml => ../../../stowroot/mihomo-tiny/etc/mihomo/config.yaml
# 包内 config.yaml 的内容已变成目标文件的 "PORT-FROM-TARGET"
```

用整包对假 `/` 做 `--adopt` dry-run，会列出 **9 条 MV**（真实 `/` 是 39 条）——即 `--adopt` 会把 `/etc/mihomo` 下的真实文件（含 **10MB 的 ASN.mmdb**、`GeoIP.dat`/`GeoSite.dat`、`cache.db`、`config-*.yaml`、`rule_set/**`）**搬或复制进仓库、覆盖同名源文件**：

- 以 root 执行时，被搬进仓库的是 **root 属主**文件（`File::Copy::move` 跨文件系统时是复制+删除），仓库 `config.yaml` 可能直接变成 `root:root 0600`，**user 之后写不了（甚至读不了）**；
- 被覆盖的源文件里还有 **Git 跟踪的** `config.example.yaml` 等，等于把线上旧文件写回仓库，污染 Git 工作区；
- 这正是 `docs/systemd-units-review-and-modularization.md` §5.2 与 `docs/file-dialog-ime-and-clipboard.md` §5.1 都明确警告过的事。

### 3.6 正解：白名单 + `--no-folding`，只 stow `config.yaml`

推荐把白名单固化在 package 的 `.stow-local-ignore`（stow 会自动忽略该文件本身）：

```text
# mihomo/.stow-local-ignore —— 只允许 config.yaml 出库
# 其余是运行时数据、历史备份，不参与部署
ASN\.mmdb
GeoIP\.dat
GeoSite\.dat
cache\.db
profiles
rule_set
ui
config-.*\.yaml
config\.example\.yaml
# 注意：package 级 ignore 会「替换」stow 内置默认列表（stow.info §4.2），
# 所以把内核默认里与 Git 相关的几条显式补上，避免以后误 stow .git 元数据
\.git
\.gitignore
\.gitmodules
```

在 scratch 实测（目标树有全部真实文件、只把 `config.yaml` 挪走）：

```bash
$ stow -d .dsh-scratch-stow/stowroot -t .dsh-scratch-stow/rootF --no-folding -v mihomo-ign
LINK: etc/mihomo/config.yaml => ../../../stowroot/mihomo-ign/etc/mihomo/config.yaml
# 目标里其它真实文件（ASN.mmdb/GeoSite.dat/config-DS.yaml/config.yaml.bak.*/Country.mmdb）原样未动
```

对**真实 `/`** 的 dry-run 结果：整包 39 条冲突 → 白名单后**只剩 1 条冲突**，即 `/etc/mihomo/config.yaml`：

```bash
$ stow -d "$PWD" -t / --no-folding -nv \
    --ignore='ASN\.mmdb' --ignore='GeoIP\.dat' --ignore='GeoSite\.dat' --ignore='cache\.db' \
    --ignore='profiles' --ignore='rule_set' --ignore='ui' \
    --ignore='config-.*\.yaml' --ignore='config\.example\.yaml' mihomo
WARNING! stowing mihomo would cause conflicts:
  * cannot stow home/user/Projects/Stow-Dotfile/mihomo/etc/mihomo/config.yaml over existing target etc/mihomo/config.yaml ...
All operations aborted.
```

（`stow.info` §4.2：`.stow-local-ignore` 里的正则对「相对 package 根、带前导 `/` 的路径」或 basename 做**首尾锚定**匹配；命令行 `--ignore` 是 repeatable、按文件名结尾锚定。两种都能用，固化到 `.stow-local-ignore` 更不容易漏带参数。）

### 3.7 回滚语义（`stow -D`）

```bash
# 在 scratch 里对已 stow 的 rootE 撤销
$ stow -d "$PWD" -t "$PWD/.dsh-scratch-stow/rootE" -D -v --no-folding <同样的 ignore 参数> mihomo
UNLINK: etc/mihomo/config.yaml
# 目标里原本的真实文件（ASN.mmdb 等）一个没动；--no-folding 下 stow 自己创建的目录会被清掉（若为空）
```

`-D` 只删「指向本 package 的软链」，不删任何真实文件/目录；删完后 `/etc/mihomo/config.yaml` 就**不存在**了——所以回滚必须**先备份 live 副本/恢复 `0600` 文件**，再 restart。对现在还没 stow 的真实 `/` 做 `-D -n` 是 no-op（实测 exit 0），符合预期。

---

## 4. 风险清单（按严重度）

| # | 风险 | 证据 | 影响 | 规避 |
| --- | --- | --- | --- | --- |
| R1 | **secret 权限模型改变** | 现 `/etc/mihomo/config.yaml` `0600 root`，user `head` 都被拒（实测 `权限不够`）；stow 后软链 effective 权限 `stat -L` = `660 user:wheel`（实测）+ 工作区 ACL | `/etc` 里不再有 root 独占副本；live 配置的有效权限由仓库文件决定；root 启动时读的是 **user 可写**的文件 | 若接受不了，选 B；A 下把仓库文件 `chmod 600` 只能收窄到 owner user，仍非 root 独占 |
| R2 | **启动依赖 `/home/user`** | `LoadCredential` 只在 start 读源文件；源文件在 `/home/user`（700） | 仓库被移动/删除、或 `/home` 未挂载/加密卷未解锁时，`LoadCredential` 读文件失败 → **service 启动失败**（绝对路径的 credential 缺失是 fatal） | 保持 `/home` 本地盘 + 开机先于 multi-user 挂载；仓库不要随手 `mv/rm`；B 无此依赖 |
| R3 | **root 从 user 可写文件读配置**（提权边界） | root 在启动时读软链目标；user 拥有仓库 | 以 user/dsh 身份（含其上的 AI agent）能改「root 下次加载的配置」；mihomo 本身跑 DynamicUser（非 root），影响面=代理配置，不是任意 root 代码执行 | 接受「仓库即配置源」的模型；或选 B |
| R4 | **stow 必须 root** | `test -w /etc` → NOT writable | 每次部署都要 `doas`；root 跑 stow 本身不改仓库（见 §2.4），但 `--adopt` 会 | 命令固定 `doas`；禁用 `--adopt` |
| R5 | **整包 stow 会顺带 link 运行时文件** | 包内 39 个文件含 gitignored 的 `GeoIP/GeoSite/ASN/cache.db/rule_set`；整包冲突 39 | 一旦强行跑通（删 live + stow），`/etc/mihomo` 会出现指向仓库运行时数据的软链；新克隆（这些文件不在 git）会成断链；删仓库文件 = `/etc` 断链 | 用白名单只 stow `config.yaml`；**不要**整包 |
| R6 | **默认折叠在 `/etc/mihomo` 缺失时生成整目录软链** | 实测 `LINK: etc/mihomo => ../../../mihomo/etc/mihomo` | `/etc` 下关键目录变成用户可写仓库的软链；`Country.mmdb`、备份文件等全部被隐藏 | 永远 `--no-folding` |
| R7 | **改配置仍需 restart** | `LoadCredential` + `ExecStartPre` 只在 start 执行；unit 无 `ExecReload` | 改仓库后不 restart 不生效；stow 不改变这条纪律 | 部署步骤固定 `mihomo -t` → `systemctl restart` → 验证 |
| R8 | **复制式部署的 drift（现状问题）** | 研究期间实测仓库与 `/etc` 的 `config.yaml`/`config-*.yaml` 尺寸时间不一致 | 不知道 live 到底是哪版；事故时难以回滚到「已部署版」 | stow（A）天然消除 drift；B 加 `cmp -s` 校验 |
| R9 | **新机器/清理后 gitignored 文件缺失** | `.gitignore` 排除 6 类运行时文件 | 新克隆里 `mihomo` 包不完整 → 整包 stow 会产生断链；白名单 A 不受影响（只依赖 `config.yaml`，而它本来就只本地保留） | A 下确保新机器先有 `config.yaml`；不要把运行时文件当部署物 |
| R10 | **`--adopt` 破坏仓库** | 实测 `MV` 覆盖包内文件；root 执行后属主变 root；跨 fs 走 `File::Copy::move` | 仓库源被 live 旧文件覆盖、Git 工作区被污染、user 失去写权限 | 永远不要 `--adopt`（文档三处已警告） |
| R11 | **stow 无状态：只认自己建的链接** | `-D` 只删指向 package 的软链 | 手工把 `/etc/mihomo/config.yaml` 换成真实文件后，`-D` 不管它；回滚/状态核对要按 §8 步骤 | 回滚固定「`-D` → 恢复备份 → restart」 |

另外两个「不是风险但要知道」的点：

- **`stat` 看软链本身是 `777`，不代表可读权限**：软链权限位无意义，内核只做路径解析；实际权限看 `stat -L`（实测 scratch 软链 `777`，跟随目标 `660 user:wheel`）。
- **`/etc/mihomo` 目录本身的权限/属主不会被 stow 改**（stow 只建目录项）；「0600 目录保护」本来也不存在（目录 755）。

---

## 5. 方案

### 5.1 A（推荐，stow 路线）：只 stow `config.yaml`

**前提（一次性仓库改动，需你确认后才做）**：在 `mihomo/` 包根新增 `mihomo/.stow-local-ignore`（内容见 §3.6）。这是本次报告之外唯一需要的仓库文件；不改它的话，命令行必须带一长串 `--ignore`，容易漏。

**部署命令（root）**：

```bash
cd /home/user/Projects/Stow-Dotfile
TS=$(date +%Y%m%d-%H%M%S)

# 1) 先 dry-run：应只报 config.yaml 一条冲突（证明白名单生效、其它 38 个文件不会被碰）
doas stow -d "$PWD" -t / -nv mihomo

# 2) 备份 live 文件（保留 0600 root），再把它「移走」（不是删除）
doas cp -a /etc/mihomo/config.yaml "/etc/mihomo/config.yaml.bak.$TS"
doas mv /etc/mihomo/config.yaml "/etc/mihomo/config.yaml.bak.$TS.live"

# 3) dry-run 应变成一条 LINK；确认相对路径指向仓库
doas stow -d "$PWD" -t / -nv mihomo

# 4) 真跑
doas stow -d "$PWD" -t / --no-folding -v mihomo

# 5) 核对：目标应是相对软链，指向仓库 config.yaml；effective 权限看仓库文件
ls -l /etc/mihomo/config.yaml
stat -L -c '%n %a %U:%G' /etc/mihomo/config.yaml   # 期望 660 user:wheel（或你 chmod 后的值）

# 6) 先语法校验（以 user 身份即可，读的是仓库文件），再 restart
mihomo -t -f mihomo/etc/mihomo/config.yaml -d /tmp/mihomo-cfgtest
doas systemctl restart mihomo
systemctl is-active mihomo
curl -s http://127.0.0.1:9090/version

# 7) 以后每次改仓库 config.yaml 后：
mihomo -t -f mihomo/etc/mihomo/config.yaml -d /tmp/mihomo-cfgtest && doas systemctl restart mihomo
```

> 命令顺序说明：第 2 步 `mv` 与第 4 步 `stow` 之间尽量短——这段时间如果 mihomo 因故障自动重启会读不到 credential 而失败（不影响的当前运行实例，但会进 restart 循环）。

**优点**

- 仓库成为唯一源：`/etc/mihomo/config.yaml` 与仓库是同一份内容，**彻底消除 R8 的 drift**。
- 回滚语义干净：`stow -D` 删链接 + 恢复备份即可；不需要记「上次 install 的是哪版」。
- 与仓库其它 dotfiles 的管理方式统一（同一套 stow 心智模型）。
- `--no-folding` + 白名单后，stow 只碰 1 个目标路径，误伤面最小。

**风险**：R1/R2/R3/R4/R5/R6/R10 中除 R5/R6/R10 已被参数规避外，**R1、R2、R3 是这个方案的固有代价**；R7 无法消除。

**回滚**

```bash
doas stow -d /home/user/Projects/Stow-Dotfile -t / -D -v mihomo   # 删掉软链
doas mv /etc/mihomo/config.yaml.bak.<TS>.live /etc/mihomo/config.yaml  # 恢复 0600 root 副本
doas systemctl restart mihomo
```

（若第 2 步只备份没留 `.live`：`doas cp -a /etc/mihomo/config.yaml.bak.<TS> /etc/mihomo/config.yaml`。）

### 5.2 B（可选，复制路线）：保留 `install -m 0600`，脚本化 + 内容校验

**做法**：不 stow；把 `docs/mihomo-config-structure.md` §6 的手工命令固化成一个小脚本（仓库外或 `docs/` 下的运维脚本），增加「校验/备份/失败不动」逻辑。参考实现：

```bash
#!/usr/bin/env bash
# deploy-mihomo-config.sh —— 以 root 运行
set -euo pipefail
REPO=/home/user/Projects/Stow-Dotfile
SRC=$REPO/mihomo/etc/mihomo/config.yaml
DST=/etc/mihomo/config.yaml
[[ $(id -u) -eq 0 ]] || { echo "需要 root（doas）" >&2; exit 1; }
[[ -r $SRC ]] || { echo "缺少 $SRC" >&2; exit 1; }

mihomo -t -f "$SRC" -d /tmp/mihomo-cfgtest      # 1) 先校验

if [[ -f $DST ]] && cmp -s "$SRC" "$DST"; then
  echo "内容一致，无需部署"; exit 0             # 2) 幂等：消除 drift 误报
fi

TS=$(date +%Y%m%d-%H%M%S)
cp -a "$DST" "/etc/mihomo/config.yaml.bak.$TS"  # 3) 备份 live（0600 root）
install -m 0600 -o root -g root "$SRC" "$DST"   # 4) 原子替换为 root 独占副本
systemctl restart mihomo                        # 5) 重启并验证
systemctl is-active mihomo
curl -s http://127.0.0.1:9090/version
```

**优点**

- **保持 `0600 root` 独立副本**：user（以及 dsh/agent）不能改 root 下次加载的配置，R1/R3 不存在。
- **启动不依赖 `/home`**：R2 不存在；`/etc` 是 self-contained。
- 回滚最简单（`cp -a` 备份返回 + restart），不需要理解 stow 的 ignore/折叠。
- `cmp -s` 让「已部署 = 最新」可判定，能当场发现 drift（R8）。

**风险**：仍要人执行（但一条命令）；「忘 restart」仍需纪律（脚本已内置）；不是 stow，和用户级 dotfiles 的管理方式不统一。**没有 R1/R2/R3/R5/R6/R10 这些结构性风险。**

**回滚**

```bash
doas cp -a /etc/mihomo/config.yaml.bak.<TS> /etc/mihomo/config.yaml && doas systemctl restart mihomo
```

### 5.3 C（不建议）：整包 `stow -t / mihomo`（含 `--adopt` 变体）

**为什么不行/不值**

1. **直接跑不通**：真实 `/etc/mihomo` 39 个同名文件，39 条冲突 → `All operations aborted`（实测，§3.2）。
2. **强行「跑通」只有两条路，都危险**：
   - `--adopt`：把 `/etc/mihomo` 的真实文件（含 10MB `ASN.mmdb`、gitignored 运行时文件、root 属主 0600 文件）搬/复制进仓库覆盖源，污染 Git、破坏属主（§3.5、R10）；
   - 先 `rm` 掉 `/etc/mihomo` 的 39 个文件再 stow：等于用仓库里的（部分 gitignored）运行时数据填回 `/etc`，新克隆会变断链；备份文件 `config.yaml.bak.*`、`Country.mmdb` 等 target-only 内容也会被整目录折叠隐藏（R5、R6）。
3. **折叠风险**：如果 `/etc/mihomo` 哪天不存在，默认折叠把整个目录变成指向仓库的软链（§3.3）——对 `/etc` 下被 root 读取的目录，这是灾难性形态。
4. **收益为零**：stow 后仍需 root + restart，secret 保护变弱，启动多一个 `/home` 依赖——为「不用打 install」付出这些代价，不值得。

**结论：整包方案不要做。** 如果只在「A 的单文件 stow」和「B 的复制部署」之间选，见 §6。

---

## 6. 结论：能不能 stow 到 `/`？值不值得？

| 问题 | 答案 | 依据 |
| --- | --- | --- |
| stow 机制上能对 `/` 操作吗？ | **能**（root 下 `-t /` 合法；非 root 也能 `-n` 只读 dry-run，本报告已对真实 `/` 执行） | stow 支持任意 target；`test -w /etc` → 需 root |
| 整包能 stow 到 `/` 吗？ | **不能**（39 条冲突，两阶段 abort） | §3.2 实测 |
| 只 stow `config.yaml` 能到 `/` 吗？ | **能**（白名单后仅剩 1 条冲突，移走 live 文件后 dry-run 干净） | §3.6 实测 |
| LoadCredential 会跟随软链吗？ | **会** | `systemd.exec(5)` + v262 源码 `fopen("re")`（§2.2） |
| `ProtectHome=yes` / `/home/user` 700 会挡吗？ | **不会**（v262：credential 在套 mount namespace 之前由 root 读取） | §2.3 |
| 值得为「消除手工 install」改成 stow 吗？ | **整包：不值得，且不可行；单文件：只在「仓库即唯一源」是硬需求时才值得** | §5.1 vs §5.2 风险对比 |
| 最稳的落地？ | **B（复制 + 脚本 + `cmp` 校验）**；要统一 stow 心智模型则 **A** | §5 |

**选择标准（一句话版）**：

- 你要的是「**仓库是唯一源，`/etc` 只是仓库的视图**」，且接受「root 从 user 可写文件读配置」「启动依赖 `/home`」→ **A**。
- 你要的是「**安全等价于现在，但别手工敲命令、别 drift**」→ **B**。
- 你要「整包 stow、一次把 `/etc/mihomo` 全接管」→ **C，不做**。

**如果采纳 A，配套要做的三件事**（都不在本报告实施范围内）：

1. 新增 `mihomo/.stow-local-ignore`（§3.6 内容）；
2. 更新 `docs/mihomo-config-structure.md` §6 的部署/回滚命令为 A 的版本（并把路径 `/home/Projects` 改成 `/home/user/Projects`）；
3. systemd 大版本升级后，重跑一次 A 的 dry-run + restart 验证（§2.3 的顺序是 262 的实现细节）。

---

## 7. 附录：关键证据汇总

### 7.1 实验命令速查（均在 `.dsh-scratch-stow/` 内执行，目录已删除）

```bash
S=.dsh-scratch-stow
# 整包 dry-run（假 / 与真 /）
stow -d "$PWD" -t "$PWD/$S/root" -nv mihomo
stow -d "$PWD" -t / -nv mihomo                       # 39 条冲突，All operations aborted
# 折叠 vs 不折叠（空 /etc）
stow -d "$PWD" -t "$PWD/$S/rootB" -v mihomo          # LINK: etc/mihomo => ../../../mihomo/etc/mihomo
stow -d "$PWD" -t "$PWD/$S/rootC" -v --no-folding mihomo
# 已有真实文件：冲突 + 两阶段 abort（before/after find diff 为空）
stow -d "$PWD" -t "$PWD/$S/root" -v mihomo
# --adopt（只在包副本上做）
stow -d "$S/stowroot" -t "$PWD/$S/rootD" -v --adopt mihomo-tiny
# 白名单
stow -d "$S/stowroot" -t "$PWD/$S/rootF" --no-folding -v mihomo-ign
# 回滚
stow -d "$PWD" -t "$PWD/$S/rootE" -D -v --no-folding <ignore 参数> mihomo
```

### 7.2 关键实测数字

| 项 | 值 |
| --- | --- |
| `stow -t / -n mihomo`（整包）冲突数 | **39**（= 包内 39 个普通文件全部冲突） |
| `stow -t / -n --no-folding <白名单> mihomo` 冲突数 | **1**（仅 `config.yaml`） |
| 假 `/` 上非 dry-run 整包 stow 后的文件系统变化 | **0**（两阶段 abort，前后 find 一致） |
| `stow --adopt` 在假 `/` 上计划 MV 数 | **9**（真实 `/` 会是 39） |
| 目标 `/etc/mihomo` 中仓库没有的条目 | 4 个 `config.yaml.bak.*` + `Country.mmdb`（软链） |
| 默认折叠形态 | `etc/mihomo` 为**整目录软链** |
| `--no-folding` 形态 | 真实目录 + 每文件一条相对软链（如 `../../../../mihomo/etc/mihomo/config.yaml`） |
| 真实 `/` 上 `config.yaml` 软链会是 | `../../home/user/Projects/Stow-Dotfile/mihomo/etc/mihomo/config.yaml` |
| 软链自身 / 跟随目标权限 | `777`（软链无意义）/ `660 user:wheel`（仓库文件） |
| 当前 live `config.yaml` | `600` 普通文件（root 属主；user 读取被拒） |
| 当前仓库 `config.yaml` | `660 user:wheel`，被 `.gitignore` 排除 |
| `/etc` / `/etc/mihomo` 可写性（user） | 都 **NOT writable** → stow 需 root |

### 7.3 引用

- `man stow(8)`、`info stow`（本机 GNU Stow 2.4.1）：`--no-folding`、`--ignore`、`.stow-local-ignore`、两阶段冲突算法（§7.1）、「Stow only creates relative symlinks」、「never delete … in a Stow directory」。
- `man systemd.exec(5)`（本机 systemd 262）：`LoadCredential=`、`ProtectHome=`。
- systemd v262 源码（与本机 `systemd 262.1-1-arch` 对应）：
  - [exec-invoke.c](https://github.com/systemd/systemd/blob/v262/src/core/exec-invoke.c)：`exec_setup_credentials()` L5863，`setup_delegated_namespaces()`（应用 mount namespace/ProtectHome）L6094/L6195；
  - [exec-credential.c](https://github.com/systemd/systemd/blob/v262/src/core/exec-credential.c)：`load_credential()` L646 起、绝对路径读取 L710；
  - [fileio.c](https://github.com/systemd/systemd/blob/v262/src/basic/fileio.c)：`read_full_file_full()` L864、`xfopenat_regular()` L1046 / `fopen(path, "re")` L1056。
- 仓库内文档：`docs/mihomo-config-structure.md` §1/§6、`docs/systemd-units-review-and-modularization.md` §3.2/§5.2、`docs/file-dialog-ime-and-clipboard.md` §5.1、`docs/dsh-user-migration-and-workspace-permissions.md` 第 278 行起。
