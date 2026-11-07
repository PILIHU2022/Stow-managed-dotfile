# Tailscale + mihomo（TUN/fake-ip）：`tailscale up` 卡在注册、始终不给登录链接

> 主机 `host` ｜ Arch Linux ｜ mihomo 1.19.33 (Meta, `with_gvisor`) ｜ tailscale 1.104.4
> 记录时间：2026-10-30 22:20 – 23:05（故障期采样 + 修复后复测）
>
> **现象**：mihomo 服务运行时执行 `doas tailscale up`，命令**不打印任何登录链接**（tailscaled 在后台反复重试
> `https://controlplane.tailscale.com/machine/register` 并超时）；`systemctl stop mihomo` 之后同一条命令
> 立刻给出 `https://login.tailscale.com/a/...`，登录、使用一切正常。
>
> **状态**：✅ 已修复并验证。2026-10-30 22:44 部署新配置，22:46 通过浏览器完成登录，`tailscale status`
> 正常列出节点。改动只有 `mihomo/etc/mihomo/config.yaml` 两处（DNS 豁免 + DIRECT 规则），见第 4 节。

---

## 摘要（TL;DR）

| 问题 | 结论 | 关键依据 |
| --- | --- | --- |
| 是不是 mihomo 把 Tailscale 拦了？ | **不是**。mihomo 从头到尾没收到过 `controlplane.tailscale.com` 的连接，日志里 0 条记录 | `journalctl -u mihomo \| grep controlplane` 为空 |
| 那到底卡在哪？ | **fake-ip 与 tailscaled 自带的 fwmark 路由打架**：DNS 给了 `198.18.0.9`，SYN 却按 tailscaled 的规则从**物理网卡**发往 `198.18.0.9` —— 该地址只存在于 mihomo 内部，永远没人应答 | `ss -tn state syn-sent` → `192.168.1.100:54316 → 198.18.0.9:443` 长期 SYN-SENT |
| 为什么关掉 mihomo 就好了？ | TUN 消失 → DNS 不再返回 fake-ip → 得到真实 `192.200.0.x` → 物理直连成立 | 关掉后立即出登录链接；`curl --interface enp7s0 --resolve …:192.200.0.106` → 302 |
| 修复办法 | ① `dns.fake-ip-filter` 给 Tailscale 域名豁免，返回**真实 IP**；② 规则段给 Tailscale 域名/tailnet 网段加 `DIRECT` | 本页第 4 节；临时实例实测过滤器生效（第 6 节） |
| 修复后 | 22:44 部署 → 22:46 登录成功；`getent ahosts controlplane.tailscale.com` = `192.200.0.110` | 第 9 节 |

---

## 1. 环境与版本

| 组件 | 值 | 来源 |
| --- | --- | --- |
| 系统 / 主机 | Arch Linux，`host` | `hostnamectl` |
| 登录用户 | `user`（uid=1000，gid=998 `wheel`） | `id` |
| 物理网卡 / 地址 | `enp7s0` / `192.168.1.100`，网关 `192.168.1.1` | `ip -br addr`、`ip route` |
| tailscale | `1.104.4`，commit `9382131983ca16de1357091618fd903e35db3c4e-dirty` | `tailscale version` |
| tailscaled 单元 | `tailscaled.service`（Arch 官方包） | `systemctl cat tailscaled` |
| mihomo | `Mihomo Meta 1.19.33 linux amd64 with go1.27.3-X:nodwarf5 2026-10-21`，tags `with_gvisor` | `/usr/bin/mihomo -v` |
| mihomo 单元 | `/usr/lib/systemd/system/mihomo.service` | 见下 |
| 生效配置源文件 | `/etc/mihomo/config.yaml`（普通文件，**不是**软链） | `ls -l` |
| 实际被读取的配置 | `/var/lib/mihomo/config.yaml`（systemd 启动时由 credential 复制过去） | 见第 5 节 |
| 仓库内配置 | `mihomo/etc/mihomo/config.yaml`（被 `.gitignore:32` 的 `**/mihomo/config.yaml` 忽略，**git 不跟踪**） | `git check-ignore -v` |

mihomo 的单元文件用 `DynamicUser=yes`，因此它**不读家目录、也不直接读 `/etc`**：

```ini
# /usr/lib/systemd/system/mihomo.service（节选）
[Service]
Type=simple
DynamicUser=yes
StateDirectory=mihomo
ExecStartPre=/usr/lib/mihomo/start
ExecStart=/usr/bin/mihomo -d "$STATE_DIRECTORY"
LoadCredential=config.yaml:/etc/mihomo/config.yaml
ProtectSystem=strict
```

```sh
# /usr/lib/mihomo/start
install "${CREDENTIALS_DIRECTORY}/config.yaml" "${STATE_DIRECTORY}"/config.yaml
install /etc/clash/Country.mmdb -t "${STATE_DIRECTORY}"
```

也就是说：`/etc/mihomo/config.yaml` 只是**源**，每次启动会被复制到 `/var/lib/mihomo/config.yaml`，真正加载的是后者。
改配置必须「改 `/etc` 的那份 + `systemctl restart mihomo`」，只 reload 不会重新复制。

与本故障相关的配置片段（行号为仓库文件 `mihomo/etc/mihomo/config.yaml`，下同）：

```yaml
# mihomo/etc/mihomo/config.yaml:24
tun:
  enable: true
  device: Mihomo
  stack: gvisor
  mtu: 1400
  auto-route: true
  auto-detect-interface: true
  dns-hijack:
    - any:53
    - tcp://any:53

# mihomo/etc/mihomo/config.yaml:61
dns:
  enable: true
  listen: 0.0.0.0:53
  enhanced-mode: fake-ip       # ← 关键
  respect-rules: true
  fake-ip-range: 198.18.0.1/16 # ← 关键
  store-fake-ip: true
  # fake-ip-filter: …           # ← 原文件里没有任何 tailscale 条目
```

---

## 2. 根因

### 2.1 tailscaled 会给自己的连接打 fwmark

tailscaled 会创建 `tailscale0`，并且**必须保证自己发起的控制/DERP/STUN 流量不会再次进入自己的隧道**（否则成环）。
它的做法是：给这些 socket 设 `SO_MARK = 0x80000`，再装三条 `ip rule` 让带这个 mark 的包**跳过自己的路由表、直接走物理网卡**：

```
# ip rule（故障期与修复后相同，其中 5210/5230/5250/5270 由 tailscaled 安装）
0:      from all lookup local
5210:   from all fwmark 0x80000/0xff0000 lookup main          # ← 打 mark 的包走 main（物理网卡）
5230:   from all fwmark 0x80000/0xff0000 lookup default
5250:   from all fwmark 0x80000/0xff0000 unreachable
5270:   from all lookup 52                                     # tailnet 地址查 table 52
9000:   from all to 198.18.0.0/30 lookup 2022                  # ↓ 以下由 mihomo 安装
9001:   not from all dport 53 lookup main suppress_prefixlength 0
9001:   from all iif Mihomo goto 9010
9002:   not from all iif lo lookup 2022
9002:   from 0.0.0.0 iif lo lookup 2022
9002:   from 198.18.0.0/30 iif lo lookup 2022
9010:   from all nop
```

`main` 表里只有一条默认路由，指向物理网关：

```
# ip route show table main
default via 192.168.1.1 dev enp7s0 proto dhcp src 192.168.1.100 metric 100
```

而 mihomo 的默认路由在**它自己的 table 2022**，不在 `main`：

```
# ip route show table 2022
default via 198.18.0.2 dev Mihomo
```

结论：**带 mark 的 socket 从物理网卡出去，不带 mark 的才进 TUN**。

### 2.2 冲突是这样发生的

1. `tailscale up` 需要连 `https://controlplane.tailscale.com/machine/register`。
2. tailscaled 解析这个域名时，DNS 查询（未打 mark）被 mihomo 的 `dns-hijack: any:53` 接走。
3. mihomo 处于 `enhanced-mode: fake-ip`，且 `fake-ip-filter` 里**没有** Tailscale 的条目
   → 回答一个**假地址** `198.18.0.9`（实测；`login.tailscale.com` 拿到 `198.18.0.12`）。
4. tailscaled 拿着 `198.18.0.9` 去建 TCP。这个 socket **带 mark 0x80000**，于是命中 `ip rule 5210` → `main` 表
   → 从 `enp7s0` 发出去，源地址 `192.168.1.100`。
5. `198.18.0.9` 是 mihomo **进程内部**的假地址，物理网络上没有任何设备持有它 → SYN 有去无回。

所以看到的是：

```
$ ss -tn state syn-sent
Local Address:Port            Peer Address:Port
192.168.1.100:54316            198.18.0.9:443        # 源是物理网卡 IP，目标却是 fake-ip
```

而 tailscaled 只会报超时：

```
Received error: register request: Post "https://controlplane.tailscale.com/machine/register":
    connection attempts aborted by context: context deadline exceeded
control: doLogin(regen=true, hasUrl=false)          # 反复重试，永远拿不到 URL
```

### 2.3 为什么关掉 mihomo 就正常

`systemctl stop mihomo` 之后的差别只有一个：**TUN 和它劫持的 DNS 都没了**。

- DNS 改由路由器/上游真实解析 → `controlplane.tailscale.com` 得到真实 `192.200.0.x`；
- tailscaled 的 SYN 依旧从物理网卡出去，但这次目标是真的 → 立刻 302/200，登录链接出现。

这也反向证明了「网络到 controlplane 的物理直连本来是通的」，坏掉的只是「**返回 fake-ip 的 DNS** + **强制物理直连的 fwmark**」这个组合。

---

## 3. 现场证据（故障期，2026-10-30 22:20–22:40）

| # | 事实 | 命令 | 结论 |
| --- | --- | --- | --- |
| 1 | `controlplane.tailscale.com` → `198.18.0.9`，`login.tailscale.com` → `198.18.0.12` | `getent ahosts controlplane.tailscale.com`；`dig +short @127.0.0.1 controlplane.tailscale.com` | 命中了 fake-ip |
| 2 | SYN 长期停在 `192.168.1.100:* → 198.18.0.9:443` | `ss -tn state syn-sent` | **决定性证据**：源是物理网卡，目标是假地址 |
| 3 | tailscaled 的 mark 规则在 | `ip rule \| grep 0x80000` | 打 mark 的包被强制走 `main`/物理网卡 |
| 4 | mihomo 的默认路由不在 `main` | `ip route show table 2022`、`ip route show table main` | 不带 mark 的包才进 TUN |
| 5 | tailscaled 反复注册超时 | `journalctl -u tailscaled -g 'register\|doLogin'` | 不出登录链接的直接原因 |
| 6 | mihomo 日志**从未**出现 `controlplane.tailscale.com` | `journalctl -u mihomo -g tailscale` | 该连接根本没进 mihomo，排除「mihomo 拦截」 |
| 7 | 物理直连真实 IP 成功，打 fake-ip 超时 | 见下方 curl 对照 | 证明物理链路本身通畅 |

原始输出（故障期，22:21 起 mihomo 实例 PID 9359）：

```
$ getent ahosts controlplane.tailscale.com
198.18.0.9      STREAM controlplane.tailscale.com

$ ss -tn state syn-sent
Recv-Q Send-Q  Local Address:Port   Peer Address:Port
0      1       192.168.1.100:54316   198.18.0.9:443

$ journalctl -u tailscaled -n 5 --no-pager
… Received error: register request: Post "https://controlplane.tailscale.com/machine/register":
  connection attempts aborted by context: context deadline exceeded
… control: doLogin(regen=true, hasUrl=false)
```

curl 对照（关掉/绕开 mihomo 的 TUN，直接指定网卡）：

```sh
# ① 走 TUN（不指定网卡）：DNS 给 fake-ip，但连接也在 TUN 里，所以是通的
#    （以下三条都在「filters 尚未加豁免」的故障期执行；修复后 ① 会直接拿到真实 IP）
curl --noproxy '*' -sv https://controlplane.tailscale.com/ 2>&1 | grep -E "Connected to|HTTP/"
#   Connected to controlplane.tailscale.com (198.18.0.9) port 443
#   < HTTP/2 302

# ② 模拟 tailscaled：指定物理网卡 + fake-ip → 超时（124）
curl --noproxy '*' --interface enp7s0 -m 8 -s -o /dev/null -w '%{http_code}\n' https://controlplane.tailscale.com/
#   exit 124

# ③ 模拟 tailscaled：指定物理网卡 + 真实 IP → 302
curl --noproxy '*' --interface enp7s0 -m 8 -s -o /dev/null -w '%{http_code}\n' \
     --resolve controlplane.tailscale.com:443:192.200.0.106 https://controlplane.tailscale.com/
#   302
```

> 说明：`--noproxy '*'` 是必须的 —— 本机 shell 里带着 harness 的 `http_proxy`/`HTTPS_PROXY`（`127.0.0.1:36917`），
> 不加的话 curl 会走那个代理，测不到真实的 TUN/物理路径。

### 3.1 顺带排除的说法

- **不是 mihomo 的规则拦的**：规则表里没有任何 Tailscale 相关条目（`grep -ni 'tailscale\|ts\.net' config.yaml` 在修复前为空），
  且 mihomo 日志里没有该域名的连接记录（证据 6）。
- **不是 Tailscale 账号/服务端问题**：同一条命令在停掉 mihomo 后 10 秒内就出登录链接。
- **不是 DNS 服务器坏了**：`dig` 能拿到 A 记录，只是被 fake-ip 替换成了假地址。
- **不是 MTU**：SYN 根本没到正确目的地，谈不上分片。

---

## 4. 修复

改动全部在 `mihomo/etc/mihomo/config.yaml`，两处，互相对应。

### 4.1 DNS：让 Tailscale 域名拿真实 IP

`dns.fake-ip-filter` 末尾（`mihomo/etc/mihomo/config.yaml:84-97`）新增：

```yaml
    # ---- Tailscale ----
    # tailscaled 给自己的 socket 打 fwmark 0x80000，并安装
    #   ip rule pref 5210 fwmark 0x80000/0xff0000 lookup main
    # 让这些连接绕开任何 TUN、直接从物理网卡出去（避免自己套自己）。因此
    # fake-ip 对它有害：DNS 若返回 198.18.0.9，SYN 却按上面的规则从物理网卡
    # 发往 198.18.0.9，会永久停在 SYN-SENT，`tailscale up` 于是卡在
    # controlplane.tailscale.com/machine/register，反复报
    # "connection attempts aborted by context: context deadline exceeded"。
    # 让这些域名返回真实 IP（192.200.0.x），tailscaled 的直连才成立；
    # DERP（derp*.tailscale.com）、log、login 同理，一并豁免。
    - '+.tailscale.com'
    - '+.tailscale.io'
    - '+.tailscale.net'
    - '+.ts.net'
```

要点：

- 用 `+.` 前缀：同时匹配 apex（`tailscale.com`）和所有子域；`*.` 只匹配子域，会漏掉 apex。
- 覆盖了控制面（`controlplane`）、登录页（`login`）、日志（`log`）、DERP 中继（`derpN`）和 MagicDNS 域（`ts.net`）。

### 4.2 规则：让这些流量走直连，别绕代理

`rules` 段在 `IP-CIDR,203.0.113.1/32,DIRECT,no-resolve` 之后插入（`mihomo/etc/mihomo/config.yaml:391-406`）：

```yaml
  # ======== [3.2] Tailscale 直连 ========
  # 与 dns.fake-ip-filter 里的 tailscale 域名配套：
  #   * tailscaled 自己的连接带 fwmark，本来就不进 mihomo；这些规则管的是
  #     浏览器打开登录页（login.tailscale.com）以及其它程序访问 tailnet 的情况。
  #   * 命中 DIRECT 后，respect-rules 会让 DNS 改用 direct-nameserver（国内 DoH）
  #     解析，拿到的就是 192.200.0.x 的真实地址，不需要再绕代理。
  #   * 若要改成走代理（例如所在网络直连 controlplane 不通），把这四条
  #     DOMAIN-SUFFIX 的 DIRECT 换成 Proxy 即可，同时保留 fake-ip-filter 豁免。
  - DOMAIN-SUFFIX,tailscale.com,DIRECT
  - DOMAIN-SUFFIX,tailscale.io,DIRECT
  - DOMAIN-SUFFIX,tailscale.net,DIRECT
  - DOMAIN-SUFFIX,ts.net,DIRECT
  # tailnet 网段（100.64.0.0/10）。正常情况下 tailscaled 的 ip rule 5270
  # 会先把这些包送去 tailscale0，轮不到 mihomo；这条只是登录前/掉线时的兜底，
  # 防止 tailnet 地址被 MATCH 误送去代理出口。
  - IP-CIDR,100.64.0.0/10,DIRECT,no-resolve
```

### 4.3 为什么加 DIRECT 规则（DNS 豁免不是就够了吗）

DNS 豁免只解决 **tailscaled**（它打 mark、走物理网卡）。但登录流程里还有**浏览器**：

- 浏览器打开 `login.tailscale.com` 时走的是 TUN → mihomo。若被分到 `MATCH,Proxy`，登录页就会从机场出口
  出去（能开，但慢、且部分出口会被 Tailscale 判风险）；
- 加了 `DOMAIN-SUFFIX,…,DIRECT` 后，登录页、控制台、tailnet 内网访问都走物理直连，符合「Tailscale 本身
  不该走代理」的预期；`respect-rules: true` 还会让这些域名改用 `direct-nameserver`（国内 DoH）解析，避免
  `nameserver`（境外 DoH）绕一圈。

### 4.4 一个实测踩过的坑：不要把 `*.` 和 `+.` 混着写

验证过滤器时曾试图一次性加入 GitHub 的豁免：

```yaml
  fake-ip-filter:
    - '+.tailscale.com'
    - '+.github.com'
    - 'github.com'
    - '*.github.com'      # ← 混入这条之后
```

结果**整张过滤表失效**：连 `controlplane.tailscale.com` 都退回 fake-ip（`198.18.0.9`）。
去掉 `*.` 变体、只保留 `+.` 形式后立刻恢复正常。没有深究 mihomo 的解析细节，但实践结论明确：

> `fake-ip-filter` 统一用 `+.domain` 写法，不要在同一条列表里混用 `*.domain`/裸域名变体；
> 改完必须实测（第 6 节），不能只看「配置文件里写了」。

---

## 5. 配置在哪、怎么生效（DynamicUser 的坑）

1. 仓库文件 `mihomo/etc/mihomo/config.yaml` —— 只是版本管理用的源（而且被 git 忽略，见第 1 节）。
2. `/etc/mihomo/config.yaml` —— 打包/手工放置的源，**必须是普通文件**（`LoadCredential` 读它）。
3. `/var/lib/mihomo/config.yaml` —— **实际被加载的副本**，每次 `systemctl restart mihomo` 由
   `/usr/lib/mihomo/start` 从 credential 复制过去。

所以正确的生效流程永远是：

```sh
doas cp mihomo/etc/mihomo/config.yaml /etc/mihomo/config.yaml
doas systemctl restart mihomo
```

校验「三处一致」：

```sh
sha256sum mihomo/etc/mihomo/config.yaml /etc/mihomo/config.yaml
doas sha256sum /var/lib/mihomo/config.yaml
```

---

## 6. 复现与验证方法（不需要 root，不影响生产）

核心思路：**用另一个空闲端口起一个临时 mihomo 实例**，只跑 DNS，不动 TUN，不影响正在运行的 mihomo（它占着
7890/9090 和 53 端口）。下面的命令都实测过，端口取 15xxx 段即可。

### 6.1 验证过滤表是否真的生效

```sh
cd /tmp && rm -rf fip && mkdir fip && cd fip
cat > d.yaml <<'EOF'
mixed-port: 17896
log-level: warning
dns:
  enable: true
  listen: 127.0.0.1:15359
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - '+.tailscale.com'
    - '+.tailscale.io'
    - '+.tailscale.net'
    - '+.ts.net'
  nameserver:
    - https://doh.pub/dns-query
    - https://dns.alidns.com/dns-query
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
EOF
/usr/bin/mihomo -d /tmp/fip -f /tmp/fip/d.yaml >/tmp/fip/log 2>&1 &
sleep 5

q() { printf '%-30s -> %s\n' "$1" "$(dig +short @127.0.0.1 -p 15359 "$1" A | head -1)"; }
q controlplane.tailscale.com
q login.tailscale.com
q derp1.tailscale.com
q tailscale.com
q github.com                 # 对照组：应当仍是 fake-ip

# 收工：按端口找 PID，别用 pkill -f（会连执行它的 shell 一起匹配到）
P=$(ss -ltnp 2>/dev/null | awk '/15359/{print $NF}' | grep -o 'pid=[0-9]*' | cut -d= -f2 | head -1)
[ -n "$P" ] && kill "$P"; sleep 1; rm -rf /tmp/fip
```

实测输出（2026-10-30 22:35）：

```
controlplane.tailscale.com     -> 192.200.0.102
login.tailscale.com            -> 192.200.0.101
derp1.tailscale.com            -> 159.89.225.99
tailscale.com                  -> 76.76.21.21
github.com                     -> 198.18.0.4      ← 非豁免域名照旧走 fake-ip，说明没把整台机器的 DNS 搞坏
```

> 注意：`ss -ltnp` 要看到 `pid=` 需要相应权限；若当前用户看不到，用 `doas ss -ltnp`。不要用
> `pkill -f <配置文件路径>` —— 执行它的那个 shell 命令行里也含同样的字符串，会被一起杀掉。

### 6.2 验证旧 `cache.db` 不会覆盖过滤器

`store-fake-ip: true` 会把映射持久化到 `cache.db`。担心「以前存过 `198.18.0.9`，加了豁免也没用」——实测不会：

##### 完整可跑的复现脚本

```sh
cd /tmp && rm -rf fipcache && mkdir fipcache && cd fipcache

# 生成两份配置：都不带 / 都带 tailscale 豁免，二者共用同一份 cache.db
base() { cat <<EOF
mixed-port: 17897
log-level: warning
dns:
  enable: true
  listen: 127.0.0.1:15360
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  store-fake-ip: true
  nameserver: [https://doh.pub/dns-query, https://dns.alidns.com/dns-query]
  default-nameserver: [223.5.5.5, 119.29.29.29]
$1
EOF
}
base "" > nofilter.yaml
base '  fake-ip-filter:
    - "+.tailscale.com"
    - "+.tailscale.io"
    - "+.tailscale.net"
    - "+.ts.net"' > filtered.yaml

run()  { /usr/bin/mihomo -d /tmp/fipcache -f "/tmp/fipcache/$1" >"/tmp/fipcache/$1.log" 2>&1 & sleep 5; }
stop() { P=$(ss -ltnp 2>/dev/null | awk '/15360/{print $NF}' | grep -o 'pid=[0-9]*' | cut -d= -f2 | head -1); [ -n "$P" ] && kill "$P"; sleep 3; }
q()    { dig +short @127.0.0.1 -p 15360 controlplane.tailscale.com A | head -1; }

run nofilter.yaml; echo "① 无豁免: $(q)"; stop            # 期望 198.18.x → fake 映射已写入 cache.db
run filtered.yaml; echo "② 加豁免、复用 cache.db: $(q)"; stop   # 期望 192.200.x → 过滤器优先
rm -rf /tmp/fipcache
```

输出（2026-10-30 22:41 与 23:22 两次实测，真实 IP 属 CDN 轮换，尾数会变）：

```
① 无豁免: 198.18.0.4
② 加豁免、复用 cache.db: 192.200.0.104      # 第二次跑得到 192.200.0.106
```

结论：**过滤器优先于缓存映射**，重启即生效，不必删 `cache.db`。若仍想强制刷新，mihomo 提供了 API（实测 204）：

```sh
curl -X POST http://127.0.0.1:9090/cache/fakeip/flush     # 只清 fake-ip 映射
curl -X POST http://127.0.0.1:9090/cache/dns/flush        # 清整个 DNS 缓存
```

### 6.3 校验整份配置能加载

```sh
rm -rf /tmp/cfgtest && cp -a mihomo/etc/mihomo /tmp/cfgtest
/usr/bin/mihomo -t -d /tmp/cfgtest -f /tmp/cfgtest/config.yaml
# → configuration file /tmp/cfgtest/config.yaml test is successful
rm -rf /tmp/cfgtest
```

`-t` 只做解析和初始化（会读 GeoIP/GeoSite、rule-set），不接管网络；`cp -a` 会把 `cache.db`、`rule_set/`、
`profiles/` 一起带上，所以需要目录可写（`/tmp` 没问题）。

### 6.4 复现「fake-ip 黑洞」

修复后如果还想亲眼看到故障原理，不需要改任何配置：

```sh
# 真实 IP：物理直连可达
curl --noproxy '*' --interface enp7s0 -m 8 -s -o /dev/null -w '%{http_code}\n' \
     --resolve controlplane.tailscale.com:443:192.200.0.106 https://controlplane.tailscale.com/
# → 302

# fake-ip：从物理网卡发出去，必然超时
curl --noproxy '*' --interface enp7s0 -m 8 -s -o /dev/null -w '%{http_code}\n' \
     --resolve controlplane.tailscale.com:443:198.18.0.9 https://controlplane.tailscale.com/
# → 卡住 8 秒后退出（124）
```

这就等价于 tailscaled 在故障期做的事：**用真实网卡去连一个只存在于 mihomo 内部的地址**。

---

## 7. 部署步骤（本机已执行，留档）

```sh
cd /home/Projects/Stow-Dotfile

# 1) 先确认改的是同一份
diff -q mihomo/etc/mihomo/config.yaml /etc/mihomo/config.yaml || true

# 2) 源配置 → /etc（mihomo 单元从 /etc 读 credential）
doas cp mihomo/etc/mihomo/config.yaml /etc/mihomo/config.yaml

# 3) 重启 mihomo（会重新复制 credential，重建 TUN 与 DNS 劫持）
doas systemctl restart mihomo
sleep 2

# 4) 关键检查：DNS 必须已经返回真实 IP
getent ahosts controlplane.tailscale.com        # 期望 192.200.0.x

# 5) 重启 tailscaled，丢掉它缓存的假地址和失败状态
doas systemctl restart tailscaled

# 6) 重新登录
doas tailscale up
```

顺序为什么重要：

- 先重启 mihomo：新 DNS 规则必须先就位，否则 tailscaled 重启后拿到的还是假地址；
- 再重启 tailscaled：它可能已经缓存了 `198.18.0.9`，且 `doLogin` 处于退避重试；
- `tailscale up` 会打印 `https://login.tailscale.com/a/…`，浏览器打开即可（此时登录页命中的是 `DIRECT` 规则，走物理直连）。

本机执行记录：`/etc/mihomo/config.yaml` 与仓库文件一致（`repo==etc`），mihomo `ExecMainStartTimestamp=2026-10-30 22:44:42`，
tailscaled `22:15:29`（未重启，登录是后续 `tailscale up` 完成的）。

---

## 8. 验证清单

| 检查项 | 命令 | 修复前 | 修复后期望 |
| --- | --- | --- | --- |
| DNS 不再是 fake-ip | `getent ahosts controlplane.tailscale.com` | `198.18.0.9` | `192.200.0.x`（本机实测 `192.200.0.110`） |
| 没有去往 fake-ip 的 SYN | `ss -tn state syn-sent \| grep 198.18` | 有 `192.168.1.100:* → 198.18.0.9:443` | 空 |
| tailscaled 不再报注册超时 | `journalctl -u tailscaled -g register -n 20` | `context deadline exceeded` 循环 | 无新条目 |
| 出登录链接 | `doas tailscale up` | 无输出/超时 | 打印 `https://login.tailscale.com/a/…` |
| 登录成功 | `tailscale status` | `Logged out.` | 列出节点（本机 `100.64.0.1 host`） |
| 登录页走直连 | `journalctl -u mihomo -g tailscale` | 无记录 | `match DomainSuffix(tailscale.com) using DIRECT` |
| 配置三处一致 | `sha256sum` × `/etc` × `/var/lib/mihomo` | — | 三个哈希相同 |

---

## 9. 修复后实测（2026-10-30 22:44 起）

```
$ getent ahosts controlplane.tailscale.com
192.200.0.110   STREAM controlplane.tailscale.com

$ journalctl -u mihomo --since 22:44 | grep tailscale
… [TCP] 198.18.0.1:38920 --> login.tailscale.com:443     match DomainSuffix(tailscale.com) using DIRECT
… [TCP] 198.18.0.1:48010 --> wwwv2.tailscale.com:443     match DomainSuffix(tailscale.com) using DIRECT
… [TCP] 198.18.0.1:59140 --> console.tailscale.com:443   match DomainSuffix(tailscale.com) using DIRECT

$ tailscale status
100.64.0.1   host        username@  linux    -
100.64.0.2   phone   username@  android  offline, last seen 13m ago
```

说明：

- `22:46` 浏览器访问 `login.tailscale.com` 时，mihomo 已经按新规则把它送去 `DIRECT`，登录一次成功；
- `198.18.0.1` 是 mihomo TUN 的本地地址，浏览器经 TUN 访问时源地址就是它，属正常现象。

---

## 10. 残余告警（与登录无关，但值得知道）

修复后仍会周期性看到两类日志，均**不影响** Tailscale 登录和上网：

| 现象 | 原始日志 | 目前判断 | 追查方法 |
| --- | --- | --- | --- |
| 有连接卡在直连 `8.8.8.8:443` | `ss -tn state syn-sent` 里多条 `192.168.1.100:* → 8.8.8.8:443`，长期 SYN-SENT | 某个带 fwmark 的进程（mihomo 或 tailscaled）在物理直连 DoH 端点，墙内被掐。属 mihomo 的 DoH 可用性话题 | `doas ss -tnp state syn-sent`（需要 root 才看得到进程） |
| `open-conn-track` 告警 | `open-conn-track: timeout opening (TCP 100.64.0.1:* => 198.18.0.5:80); no associated peer node` | 有连接经过 `tailscale0` 打到 fake-ip 段（`198.18.0.5`）；fake-ip 只在本机 mihomo 内有意义，tailscaled 找不到对应 peer 后丢弃。出现频率与某台设备在线时间相关 | `journalctl -u mihomo \| grep 198.18.0.5`（本机 0 条，说明包未进 TUN）；`doas ss -tnp \| grep 198.18.0.5` |

这两条都不是本次登录故障的成因（故障期 mihomo 日志里没有任何 `controlplane` 记录，且 `8.8.8.8:443` 的 SYN
是在修复后才被注意到的噪声）。若以后要治理，前者可把 `dns.nameserver` 的 `https://dns.google/dns-query`
换成可达的 DoH，后者需先定位是哪台设备/进程在往 fake-ip 段发包。

---

## 11. 已知限制与可选改进

1. **MagicDNS（`*.ts.net`）在 mihomo 下仍不可用**：mihomo 劫持了 53 端口，`100.100.100.100` 的 MagicDNS
   查询进不来。需要时在 `dns.nameserver-policy` 里单独指定：

   ```yaml
   nameserver-policy:
     "+.ts.net":
       - "100.100.100.100"
   ```

   注意 `100.100.100.100` 是 tailscaled 在 `tailscale0` 上应答的地址，必须保证查询不被 `dns-hijack` 抢走，
   属于另一个话题，改前先实测。

2. **如果所在网络连真实 IP 都连不上 controlplane**（比如机房/校园网封锁），把 `[3.2]` 的四条
   `DOMAIN-SUFFIX,…,DIRECT` 改成 `Proxy`，**同时保留** `fake-ip-filter` 的四条豁免（两者解决的是不同环节）。

3. **另一种兜底：给 tailscaled 设代理**（不改规则也能让 `tailscale up` 成功）：

   ```sh
   doas systemctl edit tailscaled
   # [Service]
   # Environment=HTTPS_PROXY=http://127.0.0.1:7890
   ```

   它只影响 tailscaled 的 HTTP(S) 出站（控制面、DERP over TCP）；STUN/UDP 仍按 fwmark 直连。而且此时
   `[3.2]` 的 `DIRECT` 会让 mihomo 收到代理请求后再直连，等于没走机场出口 —— 要真正走代理就得把规则改成
   `Proxy`。所以它是「网络直连也不通」时的补丁，不是本次方案的替代品。

4. **不要用 `tailscale logout` 排障**：会丢登录态，得重新走浏览器授权。只想重置连接用
   `tailscale down` / `tailscale up` 即可。

---

## 12. 教训（可复用到其它 TUN + fake-ip 场景）

1. **TUN + fake-ip 与「自带 fwmark 的自研网络栈」天然冲突**（tailscale、wireguard 系工具、部分 VPN 客户端）。
   诊断三板斧：`ss -tn state syn-sent`（看谁在黑洞里）、`ip rule`（看包被哪条策略改道）、两侧日志对照。
2. **`ss` 的源地址就是判决书**：源地址是物理网卡 IP，说明 socket 带 mark 绕过了 TUN；目标同时是 fake-ip 段，
   基本可以定案。
3. **`fake-ip-filter` 用 `+.domain`，别混 `*.domain`**；混用会让整表失效（第 4.4 节实测），且这种失效
   **没有报错日志**，只能靠 `dig` 验证。
4. **`store-fake-ip` 的旧映射不会覆盖过滤器**，重启即生效；真要强制刷新再调 `/cache/fakeip/flush`。
5. **fake-ip 段的地址从物理网卡永远不可达**；「能上网」不代表「DNS 返回的地址可用」，一定要区分「谁在发这个包」。
6. **mihomo（DynamicUser）改配置必须 cp 到 `/etc` 再 restart**，实际加载的是 `/var/lib/mihomo/config.yaml`；
   `mihomo -t` + 临时实例（换端口）是零风险验证手段。
7. **验证要看输出，不要看配置**：改完必须 `getent`/`dig` 确认返回真实 IP，否则等于没改。

---

## 13. 附录

### 13.1 一键自检脚本（只读）

```sh
#!/usr/bin/env bash
# 检查 Tailscale 在 mihomo(TUN+fake-ip) 下是否处于健康状态。只读，不改任何东西。
set -u
fails=0
chk() { if eval "$2" >/dev/null 2>&1; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi; }

echo "== 1. DNS 是否已被豁免（期望非 198.18/16）"
ip=$(getent ahosts controlplane.tailscale.com | awk 'NR==1{print $1}')
echo "     controlplane.tailscale.com -> ${ip:-<空>}"
case "$ip" in 198.18.*) echo "  FAIL 仍是 fake-ip"; fails=$((fails+1));; "") echo "  FAIL 解析失败"; fails=$((fails+1));; *) echo "  ok";; esac

echo "== 2. 是否还有去往 fake-ip 段的 SYN-SENT"
n=$(ss -tn state syn-sent 2>/dev/null | awk '$3 ~ /198\.18\./ || $4 ~ /198\.18\./' | wc -l)
echo "     命中 ${n} 条"; [ "$n" -eq 0 ] && echo "  ok" || { echo "  FAIL 仍在黑洞里"; fails=$((fails+1)); }

echo "== 3. tailscaled 最近的注册错误（期望为空）"
if journalctl -u tailscaled --since "-10 min" --no-pager 2>/dev/null | grep -q "machine/register"; then
  echo "  FAIL 最近 10 分钟仍有 register 失败"; fails=$((fails+1))
else echo "  ok"; fi

echo "== 4. tailscale 是否已登录"
tailscale status >/dev/null 2>&1 && echo "  ok" || { echo "  FAIL 未登录/未运行"; fails=$((fails+1)); }

echo; [ "$fails" -eq 0 ] && echo "全部通过" || echo "有 ${fails} 项失败"
exit "$fails"
```

> 只读脚本，依赖 `getent`（不用装 `dig`）、`ss`、`journalctl`、`tailscale`。若某步提示权限不足，
> 把该行换成 `doas …` 重跑即可（`doas` 对 `:wheel` 是 nopass）。本机 2026-10-30 23:12 实测输出：
>
> ```
> == 1. DNS 是否已被豁免（期望非 198.18/16）
>      controlplane.tailscale.com -> 192.200.0.101
>   ok
> == 2. 是否还有去往 fake-ip 段的 SYN-SENT
>      命中 0 条
>   ok
> == 3. tailscaled 最近的注册错误（期望为空）
>   ok
> == 4. tailscale 是否已登录
>   ok
>
> 全部通过
> ```

### 13.2 涉及的文件

| 文件 | 作用 |
| --- | --- |
| `mihomo/etc/mihomo/config.yaml` | 仓库内的配置源；本页改动 `dns.fake-ip-filter`（:84-97）与 `rules`（:391-406） |
| `/etc/mihomo/config.yaml` | mihomo 单元的 `LoadCredential` 源，需 `doas cp` 覆盖 |
| `/var/lib/mihomo/config.yaml` | 实际加载的副本（每次 restart 由 `/usr/lib/mihomo/start` 复制） |
| `/usr/lib/systemd/system/mihomo.service` | `DynamicUser=yes`、`StateDirectory=mihomo`、`ExecStartPre=/usr/lib/mihomo/start` |
| `/usr/lib/mihomo/start` | `install` credential 与 `Country.mmdb` 到 `$STATE_DIRECTORY` |

### 13.3 参考

- mihomo 文档 `dns` 段（`fake-ip-filter`、`respect-rules`、`nameserver-policy`）：<https://wiki.metacubex.one/config/dns/>
- Tailscale CLI（`up` / `down` / `status`）：<https://tailscale.com/docs/reference/tailscale-cli>
- Tailscale DNS / MagicDNS（`100.100.100.100`、`*.ts.net`）：<https://tailscale.com/docs/reference/dns-in-tailscale>

> `tailscale.com/kb/<数字>` 旧路径现在会 308 跳到 `tailscale.com/docs/...`，上面写的是最终地址。
