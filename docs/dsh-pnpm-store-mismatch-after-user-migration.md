# dshmarket 更新失败（`ERR_PNPM_UNEXPECTED_STORE`）排查与修复

> 主机：`host` ｜ 受影响 profile：`web`（`/home/dsh/.dsh/profiles/web`）｜ 运行时身份：`dsh(1002)`
> 记录时间：2026-10-02 ｜ 所有结论均为在本机实测得到的数据；凡属推断均已显式标注为"反推"

---

## 摘要（TL;DR）

| 现象 | 结论 |
| --- | --- |
| dshmarket 更新到 1.66.8 报 `ERR_PNPM_UNEXPECTED_STORE` | **真问题**：`node_modules/.modules.yaml` 记录的 store 在 `/home/user/...`，而 `dsh` 身份下 pnpm 解析出 `/home/dsh/...`。pnpm 11 的一致性检查在**改动任何文件之前**就退出，于是该 profile 的**全部** `add`/`remove` 都失败 |
| "更新前的构建未能验证恢复" | **同源**：回滚同样走 `pnpm add`，被同一条检查拒掉，所以既装不上新的、也回不去旧的 |
| 安装 `dsh-remote-ui` 时那段异步栈 | **同源，且栈被截断**：那是 `pnpm add` 的内部栈（`recursive` → `recursiveInstallThenUpdateWorkspaceState` → `handler4 [as add]`），真正的错误类型行在栈的更上面。市场日志里同几次运行的 `err=` 就是 `ERR_PNPM_UNEXPECTED_STORE` |
| 跟 `dsh` 用户迁移的关系 | **直接因果**：迁移前 DSH 以 `user` 跑、`DSH_HOME=/home/user/.dsh`；迁移后以 `dsh` 跑、`DSH_HOME=/home/dsh/.dsh`。profile 整体搬了家，但 `node_modules` 里记的是**旧家目录的绝对路径** |
| 市场自己建议的修法（把旧 store 写回配置）能用吗 | **本机不行**：`/home/user` 是 `700` 且属 `user(1000)`，`dsh` 进不去；那个 store 对运行身份不可达 |
| `pnpm install --store-dir <旧路径>` 能修吗 | **不能**：只对那一条命令生效，不会改写 `node_modules/.modules.yaml` 里的记录，下一条命令照错 |
| 现在还要不要重启 | **已经重启过，而且成功了**：市场 16:11:00 排程 → 16:14:12 新进程起来（`bootId 32196`），在线 `marketVersion` 已确认是 `1.66.8` |

**实际采用的修复（2026-10-02 16:05–16:07 执行）**：把 store 落到 `$DSH_HOME` 内，再把 `node_modules` 里的旧记录对齐到它。

```yaml
# ~/.dsh/profiles/web/pnpm-workspace.yaml （顶层，驼峰；kebab-case 的 store-dir 会被 pnpm 忽略）
storeDir: /home/dsh/.dsh/.pnpm-store
```

```console
# node_modules/.modules.yaml                  : storeDir → /home/dsh/.dsh/.pnpm-store/v11
# node_modules/.pnpm-workspace-state-v1.json  : projects  → /home/dsh/.dsh/profiles/web
```

---

## 1. 背景：迁移搬了 profile，没搬 pnpm 的 store 记录

### 1.1 这次迁移在 DSH 侧改了什么

`dsh` 用户、`agent` 组、`/home/Projects` 的 ACL 都是**文件层面**的迁移。对 DSH 进程本身而言还有一层**身份**变化：

| | 迁移前（反推自 profile 内的记录） | 迁移后（实测） |
| --- | --- | --- |
| 运行用户 | `user(1000)` | `dsh(1002)` |
| `HOME` | `/home/user` | `/home/dsh` |
| `DSH_HOME` | `/home/user/.dsh` | `/home/dsh/.dsh` |

```console
$ env | grep -E '^(DSH_HOME|DSH_PROFILE_DIR|HOME|USER)='
DSH_HOME=/home/dsh/.dsh
DSH_PROFILE_DIR=/home/dsh/.dsh/profiles/web
HOME=/home/dsh
USER=dsh
```

`.dsh` 目录整体搬到了新家目录，所以 `profiles/web/node_modules/` 里**由旧 pnpm 写下的绝对路径**也跟着搬了过来——这是后面所有症状的种子。

### 1.2 pnpm 的 store 位置由 `HOME` 推导

Linux 上默认是 `$XDG_DATA_HOME/pnpm/store/v11`，没有 `XDG_DATA_HOME` 时退回 `$HOME/.local/share/pnpm/store/v11`：

```console
$ cd ~/.dsh && pnpm store path          # 在没有 pnpm-workspace.yaml 的目录里问，得到的就是默认值
/home/dsh/.local/share/pnpm/store/v11
```

而 profile 里**记录**的是另一个路径（下一节）。两者一旦不同，pnpm 就不肯动手。

---

## 2. 根因（pnpm 源码级）

pnpm 11 在每次安装前都会跑一次一致性检查。检查发生在创建 store 控制器之后、任何链接/下载之前：

```js
// /usr/lib/node_modules/pnpm/dist/pnpm.mjs:223626   （pnpm 11.28.2）
function checkCompatibility(modules, opts) {
  if (!modules.layoutVersion || modules.layoutVersion !== LAYOUT_VERSION) {
    throw new ModulesBreakingChangeError({ modulesPath: opts.modulesDir });
  }
  if (!modules.storeDir
      || path.relative(modules.storeDir, opts.storeDir) !== ""
      && path.relative(modules.storeDir, path.join(opts.storeDir, "../v3")) !== "") {
    throw new UnexpectedStoreError({
      actualStorePath: opts.storeDir,      // 这次解析出来的
      expectedStorePath: modules.storeDir, // 磁盘上记录的
      modulesDir: opts.modulesDir,         // 报错里那个 "The dependencies at ..."
    });
  }
  // …virtualStoreDir / virtualStoreDirMaxLength / hoistPattern 同理
}
```

本机两个值：

| 角色 | 值 | 来源 |
| --- | --- | --- |
| **expected**（磁盘记录） | `/home/user/.local/share/pnpm/store/v11` | `node_modules/.modules.yaml` |
| **actual**（本次解析） | `/home/dsh/.local/share/pnpm/store/v11` | `HOME=/home/dsh` 推导 |

`path.relative()` 非空 → 抛 `ERR_PNPM_UNEXPECTED_STORE: Unexpected store location`。

> 📌 这个错误**不是"store 坏了"**，而是"这份 node_modules 认的是另一个 store"。pnpm 拒绝在它没把握的情况下改这份 node_modules，任何 `add`/`remove`/`install` 都在第一步就退出——包括市场用来"回滚到旧构建"的那次 `pnpm add`。

---

## 3. 实测证据（原始数据）

### 3.1 状态文件里留着旧家目录

```console
$ grep -n storeDir ~/.dsh/profiles/web/node_modules/.modules.yaml
  "storeDir": "/home/user/.local/share/pnpm/store/v11",

$ python3 - <<'EOF'
import json
print(list(json.load(open('/home/dsh/.dsh/profiles/web/node_modules/.pnpm-workspace-state-v1.json'))['projects']))
EOF
['/home/user/.dsh/profiles/web']
```

同一份 `.modules.yaml` 里 `"packageManager": "pnpm@11.26.0"`——也是迁移前那台 pnpm 写的。

### 3.2 旧 store 对 `dsh` 不可达

```console
$ ls -ld /home/user
drwx------+ 1 nobody nobody 4064 Oct  2 15:46 /home/user   # 沙箱视角：非本身份一律显示 nobody

$ getfacl -p /home/user
# file: home/user
# owner: nobody
# group: nobody
user::rwx
user:4294967295:--x    #effective:---
group::---
mask::---
other::---

$ getent passwd user dsh
user:x:1000:998::/home/user:/usr/bin/zsh
dsh:x:1002:1005::/home/dsh:/usr/bin/zsh

$ ls /home/user/.local/share/pnpm/store/v11
ls: cannot access '/home/user/.local/share/pnpm/store/v11': Permission denied
```

`/home/user` 是 `700` 且属 `user(1000)`；运行身份是 `dsh(1002)`。**"把旧 store 写回配置"这条路在本机物理上走不通。**

### 3.3 市场的失败记录

```console
$ grep -n UNEXPECTED_STORE ~/.dsh/profiles/web/.dsh-market/log.ndjson | head -3
428:{"at":"2026-10-02T06:48:43.613Z", … "event":"update-rollback","detail":"dshmarket: failed update command and restoration of the previous build could not be verified — ERR_PNPM_UNEXPECTED_STORE: Unexpected store location"}
429:{"at":"2026-10-02T06:48:43.614Z", … "event":"update","detail":"dshmarket -> dshmarket@1.66.8 exit=1 err=ERR_PNPM_UNEXPECTED_STORE: Unexpected store location"}
500:{"at":"2026-10-02T08:01:18.520Z", … "event":"install","detail":"@linxin666/dsh-remote-web-ui@0.4.4 exit=1 err=ERR_PNPM_UNEXPECTED_STORE: Unexpected store location"}
```

`.plugin-manager/logs/operation-*/pnpm.log` 里留着市场真正执行的命令行：

```console
$ grep -h "Command failed" ~/.dsh/profiles/web/.plugin-manager/logs/*/pnpm.log | sort -u
Command failed with exit code 1: pnpm add -w 'dshmarket@1.66.8' '--reporter=ndjson'
Command failed with exit code 1: pnpm add -w --force '--config.minimum-release-age=0' 'dshmarket@1.66.7' '--reporter=ndjson'
Command failed with exit code 1: pnpm add -w '@linxin666/dsh-remote-web-ui@0.4.4' '--reporter=ndjson'
```

第一行是**更新**，第二行是市场的**回滚**——两条都死在同一个检查上，这就是 "restoration of the previous build could not be verified" 的全部含义。

### 3.4 时间线：故障正好从迁移之后开始

| 本地时间 | 事件 | 证据 |
| --- | --- | --- |
| ≤ 2026-10-01 | DSH 以 `user` 运行，profile 一切正常 | `.modules.yaml` / `.pnpm-workspace-state-v1.json` 里的 `/home/user/...` |
| 2026-10-02 14:44:02 | 迁移后的一次启动尝试失败（端口占用，与本题无关） | `logs/startup-2026-10-02T06-44-02…log` |
| 2026-10-02 14:48:01 | `dsh` 身份下首次创建自己的 store 目录 | `~/.local/share/pnpm/store/v11` mtime `Oct 2 14:48` |
| **2026-10-02 14:48:35** | **第一次 `pnpm add -w dshmarket@1.66.8` 报 `ERR_PNPM_UNEXPECTED_STORE`** | `log.ndjson:428` + `operation-HMWXNX` |
| 2026-10-02 14:48:38 | 回滚 `pnpm add … dshmarket@1.66.7` 报同一个错 | `operation-5Doa2e` |
| 2026-10-02 15:58–16:03 | 反复重试（更新 + 回滚 + 安装 remote-web-ui）全部同样报错 | `operation-4j94XL/tDWD4Q/F9KfoZ/6TLTAH/upx5AG/NZCQzg/Dv653n/0nZTtI` |
| 2026-10-02 16:05–16:07 | 本次修复 + 验证 | 本机执行记录（见第 5 节） |
| 2026-10-02 16:09:39 | **dshmarket → 1.66.8 `exit=0`** | `log.ndjson`（`event":"update"`） |
| 2026-10-02 16:10:32 | **`@linxin666/dsh-remote-web-ui@0.4.4` `exit=0 hot=true`** | `log.ndjson`（`event":"hot-mount"` + `install`） |

> ⚠️ 注意最后两行：`ERR_PNPM_UNEXPECTED_STORE` 的最后一次出现是 `08:03:01Z`（16:03:01）；此后市场日志再无该错误。修复的**唯一**变量就是把 store 记录对齐。

---

## 4. 修复

### 4.1 改了什么（三处，其中一处是配置）

```yaml
# ~/.dsh/profiles/web/pnpm-workspace.yaml
packages:
  - .

nodeLinker: hoisted
autoInstallPeers: false
# Keep the content-addressable store inside $DSH_HOME. …
storeDir: /home/dsh/.dsh/.pnpm-store      # ← 新增（顶层、驼峰）
minimumReleaseAgeExclude:
  - …
```

```console
# 2) node_modules/.modules.yaml
#      "storeDir": "/home/user/.local/share/pnpm/store/v11"
#   →  "storeDir": "/home/dsh/.dsh/.pnpm-store/v11"

# 3) node_modules/.pnpm-workspace-state-v1.json
#      "/home/user/.dsh/profiles/web"  →  "/home/dsh/.dsh/profiles/web"
```

`package.json` 与 `pnpm-lock.yaml` **未改**（验证时临时动过，已按原样还原）。

### 4.2 为什么把 store 放进 `$DSH_HOME`

| 方案 | 评价 |
| --- | --- |
| 把旧 store 写回配置（市场建议） | ❌ 本机 `/home/user` 不可达（见 3.2） |
| 对齐到 pnpm 现在的默认值 `/home/dsh/.local/share/pnpm/store/v11` | ⚠️ 可行，但"谁能写这个目录"由 sandbox 策略决定：**本次修复的 shell 里 `/home/dsh` 是只读**，改不了、也就无法当场验证 |
| **store 放进 `$DSH_HOME`（采用）** | ✅ `$DSH_HOME` 是唯一对"运行时进程"和"沙箱内进程"都稳定可写的目录；store 与 profile 同生共死，随 `.dsh` 一起被备份/迁移，不会再出现"记录指向一个已不存在的家目录" |

### 4.3 为什么不能只改配置、也不能只删 `node_modules`

* **只改配置**：`checkCompatibility` 读的是 `node_modules/.modules.yaml` 里那个**已经写死的**值；配置只是决定 `actual`。两边不相等就仍然报错，所以必须同时改记录。
* **只删 `node_modules` 重装**：可行但代价大（全部重新下载），而且当时的 store 是空的，等于为一个纯路径问题付一次全量下载。实测"改记录 + 定向安装"只需几秒且**零重装**。

---

## 5. 验证

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| store 解析一致 | `cd ~/.dsh/profiles/web && pnpm store path` | `/home/dsh/.dsh/.pnpm-store/v11` ✅ |
| 安装路径恢复 | `pnpm install --frozen-lockfile` | `Lockfile is up to date, resolution step is skipped` / `Already up to date` / `Done in 3.4s`，exit 0 ✅ |
| `add` 路径恢复 | `pnpm add -w dshmarket@1.66.7 --config.minimum-release-age=0` | exit 0（此前同形态命令必报 `ERR_PNPM_UNEXPECTED_STORE`）✅ |
| 记录已同步 | `grep storeDir node_modules/.modules.yaml` | `/home/dsh/.dsh/.pnpm-store/v11` ✅ |
| 清单未漂移 | `diff` 备份的 `package.json` / `pnpm-lock.yaml` | 完全一致 ✅ |

修复前的关键输出（复现）：

```console
$ cd ~/.dsh/profiles/web && pnpm install --frozen-lockfile
[ERR_SQLITE_ERROR] unable to open database file        # ← 这是沙箱只读导致的另一回事，见第 9 节
```

```console
$ cd ~/.dsh/profiles/web && pnpm store path
/home/dsh/.dsh/.pnpm-store/v11                          # ← 修复后
```

修复后市场的真实回执（我没有代劳装插件，是市场自己跑的）：

```console
$ curl -s http://127.0.0.1:3080/dsh-market/api/v1/capabilities \
    -H 'Origin: http://127.0.0.1:3080' -H 'Host: 127.0.0.1:3080'
{"marketVersion":"1.66.8","profile":"web","bootId":"32196-1790928852672","runtime":"web",
 "restart":{"supported":true,"managedBy":"market","supervisor":null,"debugger":null}, …}
```

`bootId` 的时间戳部分 `1790928852672` = **2026-10-02 16:14:12 本地**——即重启也确实完成了。

---

## 6. 为什么不按市场自己给的那条修法做

`dshmarket/lib/pnpm-compat.js:174` 认得这个错误，并给出建议：

> 持久的修法：把**记录里的那个** store 写进 profile 的 pnpm-workspace.yaml（顶层、驼峰）……

这条建议的前提是"那个 store 还在、还归你"。它给的两个前提在本机**都不成立**：

1. `/home/user` 是 `700` 且属 `user(1000)`，`dsh` 连列目录都不行；
2. 迁移已经让 `dsh` 有了自己要用的 store（`~/.local/share/pnpm/store/v11`），继续依赖旧家目录等于把 profile 永久绑在一个已经属于别人的路径上。

所以采用它的**等价反向操作**：让它去用新的 store，并改写记录。市场源码里也明确写了这条路的存在（"想改用 pnpm 现在解析出的那个 store 也行，但那要求清空并重装整个 node_modules"）——本次实测**不需要**清空重装，改记录即可，代价小得多。

---

## 7. 后续加固与注意事项

1. **再迁移 `DSH_HOME` 时，store 要跟人一起走。** 记录里存的是**绝对路径**，配置里也是。要么把 `.pnpm-store` 一起搬，要么搬家后重跑一次本节第 4.1 步。判断方法一条命令：
   ```console
   $ cd ~/.dsh/profiles/web && pnpm store path && grep storeDir node_modules/.modules.yaml
   ```
   两个输出必须指向同一目录。
2. **`storeDir` 会活下来。** 市场只重写 `minimumReleaseAgeExclude` / `allowBuilds` 这类块，不碰未知键；这次两条真实操作（16:09 更新、16:10 安装）跑完后 `storeDir` 仍在，已验证。
3. **其它 profile 不受影响。** `~/.dsh` 下只有一个 `node_modules/.modules.yaml`（就是 `web` 的，本次备份目录里那份不算）；`profiles/remove` 没有 `node_modules`，因此没有 store 记录，不会被这条检查拦住。
4. **`ERR_PNPM_UNEXPECTED_STORE` 只由路径决定，跟网络、registry 无关。** 本机 registry 实测都通：`registry.npmjs.org` 200、`registry.npmmirror.com` 200、`codeload.github.com` 200。
5. **fresh-release 保留期是另一回事，别混淆。** profile 设了 `minimumReleaseAge: 1440`；`dshmarket@1.66.8` 发布约 932 分钟，未过保留期，也不在 `minimumReleaseAgeExclude` 里，所以市场的更新命令必须带 `--config.minimum-release-age=0`（它的回滚命令里就有）。手工 `pnpm add` 忘带这个参数会被挡，报的不是 store 的错。
6. **备份位置**：`~/.dsh/backup-store-fix-2026-10-02T16-10Z/`（`package.json`、`pnpm-lock.yaml`、`pnpm-workspace.yaml`、`.modules.yaml`、`.pnpm-workspace-state-v1.json`、`.pnpm/lock.yaml`）。

---

## 8. 回滚

只有两步，且都要在 dsh 身份下做：

```bash
cd ~/.dsh/profiles/web
# 1) 去掉配置里的 storeDir（顶层的 storeDir: 行）
# 2) 把 node_modules 的两个记录文件换成备份
cp -a ~/.dsh/backup-store-fix-2026-10-02T16-10Z/node_modules/.modules.yaml                  node_modules/
cp -a ~/.dsh/backup-store-fix-2026-10-02T16-10Z/node_modules/.pnpm-workspace-state-v1.json node_modules/
```

回滚后 profile 会退回"旧 store 不可达 + 新 store 不匹配"的原始故障态——**只在对新方案有疑虑时用来回到已知状态**，不适合当日常操作。

---

## 9. 附：为什么 AI 不能自己重启（沙箱技术说明）

和上次权限问题同源：DSH 跑的每条 shell 命令都套在 `bwrap` 里。

```console
$ tr '\0' ' ' < /proc/1/cmdline
bwrap --ro-bind / / --dev /dev --unshare-pid --proc /proc --die-with-parent \
      --tmpfs /tmp --bind /home/dsh/.dsh /home/dsh/.dsh -- bash -c …
```

由此产生的三个硬限制：

1. **`--ro-bind / /`**：整个根文件系统只读挂载，只有 `/home/dsh/.dsh` 和私有的 `/tmp` 可写。所以**沙箱内直接跑 pnpm 会换一种错**：
   ```console
   $ touch /home/dsh/.local/share/pnpm/store/v11/_probe
   touch: cannot touch '…': Read-only file system
   ```
   这正是第 4.2 节把 store 放进 `$DSH_HOME` 的另一个理由——**否则我连验证都做不了**。
2. **`--unshare-pid`**：`ps` 只能看到自己这几条命令，**看不到、也杀不掉 DSH 主进程**，所以"停掉旧进程再起新的"这类操作在沙箱内无法完成。
3. **`--tmpfs /tmp`**：市场的重启 helper 把 recovery 配置写在 `/tmp/dsh-market-restart-*.recovery.json`（`dshmarket/lib/restart.js:505`），那是**另一个** `/tmp`，我这里看不到也放不进去。

**因此重启只能由这两条路之一完成：**
* 在市场/UI 里点重启（走 `POST /dsh-market/api/v1/restart`，由服务进程自排程、detached helper 拉起替代进程）；
* 在**宿主**上停掉占用 3080 的进程后重新 `dsh --profile web`（带上原来的 `--host/--port` 参数）。

> 📌 本次不必再重启：`capabilities` 已返回 `marketVersion: "1.66.8"`，`bootId` 时间戳 16:14:12。
> 另外，`logs/` 下 `startup-2026-10-02T08-16-33.295Z-*.log` 是一次**多余的**启动尝试，报
> `listen EADDRINUSE: address already in use 0.0.0.0:3080`——因为 16:14 那个健康进程已经占着端口。
> 这是本机从 2026-09-25 起就反复出现的重启竞态（`logs/` 下 14 份 startup 日志全是失败记录），
> 与本次 store 问题无关，也不影响正在服务的进程；看到这类日志不必再点重启。

---

## 10. 附：最小修复（急用版）

```bash
# 在 dsh 身份下，于 profile 目录执行三件事：
: "${DSH_HOME:?DSH_HOME is not set}"      # 空值会写出一个把 store 指向根目录的配置
cd "$DSH_HOME/profiles/web"

# 1) 让 pnpm 用 $DSH_HOME 内的 store（顶层、驼峰；kebab-case 无效）
printf '\nstoreDir: %s/.pnpm-store\n' "$DSH_HOME" >> pnpm-workspace.yaml

# 2) 把 node_modules 里那个旧记录改成同一路径（末尾带 /v11）
sed -i "s#\"storeDir\": \".*\"#\"storeDir\": \"$DSH_HOME/.pnpm-store/v11\"#" node_modules/.modules.yaml

# 3) 把 workspace 状态里的旧 project 路径改成现在这个
sed -i "s#/home/user/.dsh/profiles/web#$PWD#g" node_modules/.pnpm-workspace-state-v1.json

# 4) 验证：两个输出必须一致，且 install 能跑通
pnpm store path && grep storeDir node_modules/.modules.yaml
pnpm install --frozen-lockfile
```

判据：`pnpm store path` == `.modules.yaml` 里的 `storeDir`，且 `pnpm install --frozen-lockfile` 输出 `Already up to date`。
