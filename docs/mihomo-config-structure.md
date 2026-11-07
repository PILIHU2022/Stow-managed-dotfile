# mihomo 配置结构：分组分层、profile 机制与部署

> 主机 `host` ｜ mihomo 1.19.33 (Meta, `with_gvisor`) ｜ 生效路径 `/etc/mihomo/config.yaml`
> 仓库文件 `mihomo/etc/mihomo/config.yaml`（未跟踪，含明文凭据）+ 脱敏件 `config.example.yaml`（跟踪）

## 0. 一句话结论

- **mihomo 没有 "profiles" 这个东西。** 只有单数的 `profile:` 配置节（两个字段：
  `store-selected` / `store-fake-ip`）。`/etc/mihomo/profiles/` 是 GUI 客户端
  （Clash Verge、Mihomo Party、FlClash 之类）的目录约定，**这里的 systemd 服务从头到尾不读它**。
- "独角兽" 不是 profile，而是 **HTTP 订阅代理集**（`proxy-providers`），它的节点缓存落在
  **运行时状态目录** 的 `profile/Dujiaoshou.yaml`（单数，来自 `path:`），不在 `/etc` 下。
- 因此 `GCP-Free.yaml` 放进 `/etc/mihomo/profiles/` **不会被自动加载**；本次是把它的
  `proxies:` 段并进主配置来完成接入（原因见第 3 节）。

## 1. 为什么"独角兽"等不在 `/etc/mihomo/profiles/`

链路（全部有据可查）：

```
/etc/mihomo/config.yaml            ← 打包/手工放置的「源」
        │  systemd LoadCredential=config.yaml:/etc/mihomo/config.yaml
        ▼
$CREDENTIALS_DIRECTORY/config.yaml
        │  ExecStartPre=/usr/lib/mihomo/start  →  install 到 $STATE_DIRECTORY
        ▼
/var/lib/mihomo/config.yaml        ← 真正被加载的那份（/var/lib/mihomo → private/mihomo）
        │  ExecStart=/usr/bin/mihomo -d $STATE_DIRECTORY
        ▼
mihomo 进程
```

- 单元里 `DynamicUser=yes` + `StateDirectory=mihomo` + `StateDirectoryMode=0700`，
  状态目录实际是 `/var/lib/private/mihomo`（`/var/lib/private` 是 `0700 nobody`，普通用户进不去）。
- 配置里的 provider 是（下面只列独角兽；2026-11-07 新增的「良心云」见 2.5 节）：

  ```yaml
  proxy-providers:
    独角兽:
      type: http
      url: 'https://<机场>/api/v1/client/subscribe?token=<token>'
      path: ./profile/Dujiaoshou.yaml      # ← 相对 -d 目录，不是 /etc
  ```

  所以节点缓存是 **`/var/lib/private/mihomo/profile/Dujiaoshou.yaml`**。
  注意是 `profile/`（单数，我们自己配的路径），和 `/etc/mihomo/profiles/`（复数）毫无关系。
- 验证方式：`strings /usr/bin/mihomo | grep -i profiles` 只命中 tailscale/mieru/pprof 的字符串；
  源码里 `config.go` 只有 `type Profile struct { StoreSelected bool; StoreFakeIP bool }`。
- 另一个证据：`/etc/mihomo/cache.db` 的 mtime 停在 10-30，服务 11-01 重启后没再动过它——
  活动 cache 在状态目录里。

**结论**：在 `/etc/mihomo/profiles/` 里放多少 yaml 都不会生效；mihomo 只会读
`-d` 目录下的 `config.yaml`，以及 `path:` 指向的 provider 缓存。

## 2. 引入 GCP 节点

`GCP-Free.yaml` 是一份**完整的** mihomo 配置（自带 `mixed-port` / `proxy-groups` / `rules`），
只有一个节点：`GCP-Reality-443`（vless + REALITY，xtls-rprx-vision）。

为什么没有改用 `type: file` 的 provider 直接指向它：

```text
level=fatal msg="Parse config error: parse proxy provider gcp error:
path is not subpath of home directory or SAFE_PATHS: /etc/mihomo/profiles/GCP-Free.yaml
allowed paths: [<state dir>]"
```

mihomo 1.19 起 provider 的 `path` 必须在 home 目录（`-d`）或 `SAFE_PATHS` 之内，
而状态目录是 `0700` 的 DynamicUser 家目录，`/etc` 下的文件既进不去也不该进去。
所以最终做法：**把 `proxies:` 段原样并入主配置**，节点名保持 `GCP-Reality-443`。

- 明文凭据只落在本地 `config.yaml`（`.gitignore` 已排除）与线上 `/etc/mihomo/config.yaml`；
  提交进 git 的 `config.example.yaml` 用 `YOUR_GCP_SERVER_IP` / `YOUR_VLESS_UUID` /
  `YOUR_REALITY_PUBLIC_KEY` 占位。
- 该节点 12:2x 实测可用（经它访问 `gstatic/generate_204` 返回 204）。早期一次
  "REALITY authentication failed" 是瞬时失败，不是配置错误。

## 2.5 良心云订阅：UA 嗅探有三档，第三档是「假 YAML」

2026-11-07 接入第二个订阅，provider 名 `良心云`（节点前缀 `[良心云] `），
缓存 `/var/lib/private/mihomo/profile/Liangxin.yaml`。它与独角兽最大的不同还是
**服务端按 User-Agent 嗅探返回格式**，而且比一般机场更刁：同一个 URL 有三种返回，
全部 HTTP 200、Content-Type 都是 `text/html`：

| 请求 UA | 返回 | provider 结果 |
| --- | --- | --- |
| 非 Clash 系（`curl` 默认、`mihomo/1.19.33`、未知 UA） | base64 的 vless 链接列表（8816 B） | http provider 解不出，0 节点 |
| 「通用 Clash」UA（裸 `clash`、`ClashX`、`ClashforWindows`，或 URL 加 `&flag=clash`） | **假 YAML**（24700 B）：5 个 `server=127.0.0.1:65535` 的 ss 占位节点 | 3 个占位节点会混进分组 |
| Clash-Meta/Verge 系（`clash-verge/*`、`ClashMeta`、`clash.meta/*`） | 真 YAML（31665 B）：18 个 vless | 18 → 过滤广告后 16 |

所以 provider 必须显式覆盖：

```yaml
    header:
      User-Agent:
        - 'clash-verge/v2.0.0'
```

三个要点：

1. **`&flag=clash` 是假数据的入口，不是格式开关。** 它返回的 5 个占位 ss 名字含
   「客户端」「代理软件」，仓库原有 `exclude-filter` 只能滤掉含「支持」的 2 个，
   剩下 3 个会真的出现在 `手动选择` / `自动选择` / `其他策略` 里。本配置在
   `exclude-filter` 末尾追加了 `|客户端|代理软件` 兜底（实测 5 个全滤掉，不误伤真实节点）。
2. **mihomo 1.19.33 自己的默认 UA 是 `clash.meta/1.19.33`**（mock server 抓包实测），
   目前正好命中真 YAML 分支——所以不写 header 也能用；但这是服务端嗅探规则的实现细节，
   随时可能收紧，header 必须显式写死，不能依赖。
3. 18 个真节点是 10 个 REALITY/TCP + 6 个 WS/TLS（另 2 条广告），
   `剩余流量：1024 GB` / `套餐到期：2026-12-07` 由 `exclude-filter` 的「剩余」「到期」命中；
   订阅头 `Subscription-Userinfo`（**只有 Clash-YAML 分支才带**）给出 1 TiB / 到期 2026-12-07。

分组接入沿用 `include-all`：16 个节点自动进 `手动选择` / `自动选择` / 地区组。实测
`香港策略` 4、`新加坡策略` 4、`日本策略` 4、`美国策略` 2、`其他策略` 2（英国 2 个）；
`台湾策略` 0（订阅无 TW 节点，该组退化为 COMPATIBLE，属既有行为）。

验证（`-t` 只验语法；节点数要起实例看 API）：

```bash
curl -s http://127.0.0.1:9090/providers/proxies/良心云 | python3 -c \
  'import sys,json; print(len(json.load(sys.stdin)["proxies"]))'   # 期望 16
```

> 已移除的 Test（赔钱机场）订阅是同一类 UA 嗅探（mihomo 自带 UA 拿到 base64、
> Clash UA 才拿到 YAML）；2026-11-07 当天接入后又移除，节点前缀 `[Test] `。

## 3. 分组结构

分层思路取自上游 [HenryChiao/MIHOMO_YAMLS](https://github.com/HenryChiao/MIHOMO_YAMLS)
的 HenryChiao/666OS 系模板，但只取"结构"，没有套用其整份 50+ 组文件（原因见第 4 节）。

```
Proxy（总入口，MATCH 目标）
├── 自动选择        url-test, include-all + FilterAL（全量节点）
├── 手动选择        select,    include-all + FilterAL
├── 故障转移        fallback → 香港自动 / 日本自动 / 新加坡自动 / 美国自动 / 其他策略 / 直连
├── 香港策略/台湾策略/日本策略/新加坡策略/美国策略    select，默认选该地区的「自动」组
├── 其他策略        select，不属上面任何地区的节点（韩国、欧洲、南美…）
├── GCP             免费节点独立入口（不参与自动优选，见下）
└── 直连

服务组（默认都指 Proxy，可单独改指某地区）：
  AI · 流媒体 · 电报 · 微软 · 谷歌 · GitHub · Apple_Service

隐藏层（hidden: true，只在策略组里作为默认项出现）：
  香港自动 · 台湾自动 · 日本自动 · 新加坡自动 · 美国自动   （url-test, tolerance 50）
```

关键点：

| 机制 | 作用 |
| --- | --- |
| `include-all: true` + `filter` 正则 | 新增机场/节点零改动接入；节点名里带地区词就自动归组 |
| `filter` 用的是 Perl 兼容正则（regexp2），支持 `(?=)`/`(?!)` | 正向命中地区 + 反向排除"剩余/到期/官网/客服"等广告节点 |
| 叶子组 `hidden: true` | 面板只留 12 个需要点的组，测速实现细节不外露 |
| `proxies` 列表顺序 = 默认值 | `Proxy` 默认「手动选择」（首个节点是独角兽新加坡）；`Apple_Service` 默认「直连」；服务组默认「Proxy」 |
| `profile.store-selected: true` | 面板里手选的结果写进 cache.db，重启不回默认值 |
| `unified-delay: true` | 延迟口径统一（握手 + 首字节），避免 url-test 选到"握手快但首包慢"的节点 |
| `tolerance: 50` | 延迟差 50ms 以内不切节点，避免抖动导致反复切换 |

`GCP` 节点单独成组、并从 `手动选择`/`自动选择`/`其他策略` 里用 `exclude-filter` 排除：
它的延迟极低（实测 0.08s），但会间歇性 `REALITY authentication failed`。一旦让它参与
`url-test`，它会被选成最快节点，然后整条出口时通时断——这正是一次实测事故的原因：
`Proxy` 默认曾指向 `自动选择`，重启后自动选中 GCP，随后所有流量改走它并大面积失败。

## 3.5 国内 AI 走不走直连（DeepSeek / 通义千问 等）

查了三个来源，结论是**原来没有**，现在显式加了：

| 来源 | 是否含 DeepSeek |
| --- | --- |
| `ruleset.skk.moe` 的 `non_ip/domestic.txt`（883 行）、`direct.txt`（232 行）、`ai.txt`（68 行）、`global.txt`（1289 行） | **全部 0 命中**。`ai.txt` 只覆盖 OpenAI / Claude |
| Loyalsoldier `clash-rules` 的 `direct.txt` | **有**：`+.deepseek.com`、`+.deepseeksvc.com`（仅此两行，且只在 direct 里） |
| 我们自己的 `rule_set/sukkaw_ruleset/*` 缓存 | 0 命中 |

没有规则时的实际行为（部署前抓到的日志，426 条）：

```text
[TCP] dial Proxy (match Match/) 198.18.0.1:50376 --> api.deepseek.com:443 error: ...
```

即 `api.deepseek.com` 一路落到 `MATCH` → `Proxy`，绕代理一圈。所以在本配置的
「国内直连」段加了：

```yaml
  - DOMAIN-SUFFIX,deepseek.com,DIRECT
  - DOMAIN-SUFFIX,deepseeksvc.com,DIRECT
```

验证（测试实例 debug 日志）：

```text
[TCP] ... --> api.deepseek.com:443  match DomainSuffix(deepseek.com) using DIRECT
[TCP] ... --> chat.deepseek.com:443 match DomainSuffix(deepseek.com) using DIRECT
```

覆盖 `api.` / `chat.` / `platform.` / `www.` / `cdn.deepseek.com` 等所有子域。

### 3.5.1 2026-11-07 补：通义千问等国产 AI 同样漏网

用户反馈 `qianwenai.com` 会被路由到代理组；测试实例复现：

```text
[TCP] ... --> qianwenai.com:443 match Match using Proxy[[良心云] 🇭🇰香港高速01|BGP|CMCU]
```

一路落到 `MATCH`。逐表核对当日线上规则集：

| 规则集 | 行数 | 含 `qianwenai.com`？ |
| --- | --- | --- |
| `non_ip/domestic.txt` | 884 | 否 |
| `non_ip/direct.txt` | 232 | 否 |
| `non_ip/ai.txt` | 68（只收 OpenAI / Claude 系） | 否 |
| `non_ip/global.txt` | 1289 | 否 |

四张表全部 0 命中，于是落到 MATCH → Proxy。顺着查，其它国产 AI 也大多不在表里
（豆包/元宝/文心/通义网页版是例外，见下）。本次在「国内直连」段补了 11 条
（均实测解析到国内 IP：阿里云 / 火山引擎 / 电信）：

```yaml
  - DOMAIN-SUFFIX,qianwenai.com,DIRECT      # 通义千问
  - DOMAIN-SUFFIX,kimi.com,DIRECT           # Kimi（月之暗面）
  - DOMAIN-SUFFIX,moonshot.cn,DIRECT        # Kimi 国内站
  - DOMAIN-SUFFIX,bigmodel.cn,DIRECT        # 智谱清言
  - DOMAIN-SUFFIX,chatglm.cn,DIRECT         # 智谱清言
  - DOMAIN-SUFFIX,minimaxi.com,DIRECT       # MiniMax
  - DOMAIN-SUFFIX,hailuoai.com,DIRECT       # 海螺 AI（MiniMax）
  - DOMAIN-SUFFIX,stepfun.com,DIRECT        # 阶跃星辰
  - DOMAIN-SUFFIX,baichuan-ai.com,DIRECT    # 百川智能
  - DOMAIN-SUFFIX,sensetime.com,DIRECT      # 商汤
  - DOMAIN-SUFFIX,lingyiwanwu.com,DIRECT    # 零一万物
```

- **不必重复加的**：`tongyi.aliyun.com`、`dashscope.aliyuncs.com`（domestic 的
  `aliyun.com` / `aliyuncs.com` 已覆盖）、`doubao.com`、`*.tencent.com`、`*.baidu.com`。
- **有意不加的**：Qwen 国际版 `chat.qwen.ai`（香港 Alibaba）、`qwen.ai`（英国）——
  出海服务，保持走代理。

验证（测试实例，修复前后对比）：

```text
修复前: --> qianwenai.com:443      match Match using Proxy[[良心云] ...]
修复后: --> qianwenai.com:443      match DomainSuffix(qianwenai.com) using DIRECT
        --> www.qianwenai.com:443  match DomainSuffix(qianwenai.com) using DIRECT
        --> kimi.com:443           match DomainSuffix(kimi.com) using DIRECT
        --> bigmodel.cn:443        match DomainSuffix(bigmodel.cn) using DIRECT
        --> chat.qwen.ai:443       match RuleSet(global_non_ip) using Proxy   # 国际版仍走代理
        --> example.com:443        match Match using Proxy                    # 兜底不变
```

**为什么不做「通用兜底」**（例如在 MATCH 前加一条不带 `no-resolve` 的
`RULE-SET,domestic_ip,DIRECT`，按解析出的国内 IP 判定）：那样每条未被域名表匹配的
连接都要多做一次 DNS 解析，而且会把「域名在国内 CDN、但业务需要代理」的服务误判直连；
继续用显式规则补漏更可控，也方便把漏网域名反馈给上游 ruleset。

> 维护提示：以后再遇到「某国内域名走代理」，先查上面四张表；确认漏网后按本节格式
> 补 `DOMAIN-SUFFIX,...,DIRECT`，**不要动 MATCH 兜底**（防止 DNS / IP 泄露）。

## 3.6 去广告规则集：Loyalsoldier/clash-rules（`reject.txt`）

2026-11-07 引入 [Loyalsoldier/clash-rules](https://github.com/Loyalsoldier/clash-rules) 的
`reject.txt` 作为 skk 拦截表的**补充**。该项目每天北京时间 06:30 用 GitHub Actions 构建，
数据主要来自 `Loyalsoldier/v2ray-rules-dat` 与 `v2fly/domain-list-community`。

先盘了一遍它的 13 个规则集，对照本配置已有能力：

| Loyalsoldier 列表 | 大小 | 本配置是否已覆盖 |
| --- | --- | --- |
| `reject.txt`（广告） | 5.8 MB / 199,133 条 | skk `reject_domainset` 149,448 条与它**只重叠 68%** → 净增 63,364 条，值得加 |
| `direct.txt` / `proxy.txt` / `gfw.txt` | 2.3 MB / 0.6 MB / 95 KB | 已由 skk `direct_non_ip` / `global_non_ip` 覆盖，不重复加 |
| `private.txt` / `lancidr.txt` / `cncidr.txt` | 3.5 KB / 0.5 KB / 212 KB | 已由 skk `lan_*` / `china_ip` / `domestic_ip` 覆盖 |
| `apple.txt` / `icloud.txt` / `google.txt` | 5.4 KB / 1.1 KB / 3.4 KB | 已有 apple 规则与 `Apple_Service` 组；`google.txt` 是「Google 国内可直连」列表，与 `谷歌` 组策略相悖，不加 |
| `tld-not-cn.txt` | 12 KB | 未命中任何规则本来就走 `MATCH → Proxy`，等价，不需要 |
| `telegramcidr.txt` / `applications.txt` | 0.3 KB / 2.8 KB | 已有 telegram 规则；应用列表与 domestic/direct 大量重叠 |

所以只引入 `reject.txt` 这一个。

### 3.6.1 两个坑

1. **release 分支的 `reject.txt` 不是纯文本**，而是 Clash YAML payload：

   ```yaml
   payload:
     - '+.0.avmarket.rs'
   ```

   所以 `behavior` 要写 `domain`、`format` 要写 `yaml`；若照 skk 的写法给
   `format: text` 会解析出 0 条。199,133 条全部带 `+.` 前缀（suffix 匹配，含自身与所有子域）。
2. **URL 选 `raw.githubusercontent.com`**：jsdelivr 地址有 12 小时延迟，本机实测还会
   中途 TLS 中断；mihomo 拉取走 `proxy: Proxy`，raw 源没问题。

### 3.6.2 配置

```yaml
  loyalsoldier_reject:
    type: http
    behavior: domain
    format: yaml
    url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/reject.txt'
    path: ./rule_set/loyalsoldier/reject.yaml
    interval: 86400
    proxy: Proxy
```

规则放在 `[1] 广告 / 恶意 / 拦截` 段**最后**（skk 五条拦截规则之后）：

```yaml
  - RULE-SET,loyalsoldier_reject,REJECT
```

放最后是为了让与 skk 重叠的域名保持原有判定（尤其 `reject_non_ip_drop` 的
`REJECT-DROP` 语义），新列表只补 skk 没有的那 63,364 条；两者并集 212,812 个域名。

### 3.6.3 实测

```text
/providers/rules: loyalsoldier_reject  behavior=Domain  ruleCount=199133
请求 doubleclick.net                    → match RuleSet(reject_non_ip)        using REJECT  # skk 旧表先命中
请求 successesservicetrips.com（仅 Loy）→ match RuleSet(loyalsoldier_reject)  using REJECT
请求 freebestgames2025.com（仅 Loy）    → match RuleSet(loyalsoldier_reject)  using REJECT
请求 example.com                        → match Match using Proxy                           # 兜底不变
```

代价：缓存 5.8 MB（每 24h 经代理拉一次）；进程 RSS 实测 **115.2 MB vs 103.5 MB**
（+11.7 MB，199k 域名匹配表）；启动解析略慢。

误杀处理：Loyalsoldier 是社区聚合列表，若正常站点被拦，把 `loyalsoldier_reject` 那条
`RULE-SET` 注释掉，或给具体域名加一条 `DOMAIN-SUFFIX,<domain>,DIRECT` 放到规则最前面。

## 4. 从上游借鉴了什么、没借什么

借鉴（均已落地）：

1. **分层**：总入口 → 地区策略 → 地区自动 → 节点；服务组与地区组解耦。
2. **`fallback` 故障转移**：整组节点全挂时自动往后切。
3. **`url-test` + `tolerance` + `lazy`**：自动优选，未使用时不做健康检查。
4. **`include-all + filter` 而非 `use: [独角兽]`**：加机场不用改 5 处。
5. **YAML 锚点模板**（`BaseUT`/`BaseFB`/`SelectPY`/`FilterXX`）：20+ 组只写一次模板。
6. **服务组直接暴露"地区策略"选项**：AI 想锁美国、流媒体想锁日本，改一个组即可。

没借（有意为之）：

| 上游特性 | 不采用的原因 |
| --- | --- |
| 整份 51–61 组模板 | 单机场 37 节点撑不起 7 地区 × 3 层；且会覆盖我们已有的 Apple storefront / Tailscale / QUIC 修复 |
| `load-balance`（一致性哈希/轮询） | 单机场节点质量参差，哈希会把坏节点也算进去；桌面场景收益低 |
| `listeners` 分地区端口（50000+） | 单机桌面用不到，徒增暴露面 |
| `type: smart`（uselightgbm） | 需要 smart 魔改内核，本机是 `with_gvisor` 官方 tag，不认这个类型 |
| `format: mrs` 规则集 | 现有 skk.moe `text` 规则已落地缓存，换 mrs 要重下全套并重验规则 |
| `Overwrite/` 三套订阅覆盖机制 | 那是给 subconverter / OpenClash 用的，与 systemd + LoadCredential 的部署链无关 |

> 许可证：上游是 **AGPL-3.0**，README 明确禁止转载到中国大陆公共平台。
> 这里只借鉴思路与正则写法（结构/思想不受版权保护），未复制其文件内容。

## 5. 顺带修掉的问题

| 问题 | 处理 |
| --- | --- |
| `dns.store-fake-ip` 是**无效键**（源码 DNS struct 无此字段，未知键静默通过） | 删除；真键在 `profile.store-fake-ip` |
| `DOMAIN,*.steamcontent.com` / `DOMAIN,*.fastly.steamstatic.com` 用错类型（`DOMAIN` 是精确匹配，通配符永不命中） | 删除（前面的 `DOMAIN-SUFFIX` 已覆盖） |
| `RULE-SET,reject_ip,REJECT` 缺 `no-resolve`，可能触发额外 DNS 解析 | 补 `no-resolve` |
| `log-level: info` 常驻，一天 3 万+ 行日志 | 改 `warning`（排障时临时改回 info） |
| 手选结果重启后丢失 | `profile.store-selected: true` |
| 服务流量只能整体走 `Proxy` | 拆出 AI / 流媒体 / 电报 / 微软 / 谷歌 / GitHub |
| 国产 AI 域名（`qianwenai.com`、`kimi.com` 等）不在 skk 四张规则集里，落到 `MATCH → Proxy` | 国内直连段补 11 条 `DOMAIN-SUFFIX,...,DIRECT`（见 3.5.1） |
| 广告拦截只有 skk `reject_domainset` 一张表（149k 域名） | 补 Loyalsoldier `reject.txt`（199k，净增 63k，并集 212k，见 3.6） |

## 6. 部署与回滚

```bash
# 1) 校验（不会动线上实例，用一次性 -d 目录）
mihomo -t -f mihomo/etc/mihomo/config.yaml -d /tmp/cfgtest

# 2) 备份 + 部署（root；0600，避免 token/节点凭据被普通用户读取）
doas cp -a /etc/mihomo/config.yaml "/etc/mihomo/config.yaml.bak.$(date +%Y%m%d-%H%M%S)"
doas install -m 0600 -o root -g root \
  /home/Projects/Stow-Dotfile/mihomo/etc/mihomo/config.yaml /etc/mihomo/config.yaml

# 3) 重启（只 reload 不会重新复制 credential）
doas systemctl restart mihomo
systemctl is-active mihomo
curl -s http://127.0.0.1:9090/version          # {"meta":true,"version":"1.19.33"}
curl -s http://127.0.0.1:9090/proxies | python3 -m json.tool | head

# 回滚
doas cp -a /etc/mihomo/config.yaml.bak.<ts> /etc/mihomo/config.yaml && doas systemctl restart mihomo
```

验证要点：`/proxies` 里 `Proxy`、`手动选择`、5 个地区策略、5 个 `*自动` 都要出现；
`/providers/proxies/良心云` 有 16 个节点（名字带 `[良心云] ` 前缀）；`/rules` 74 条；
`/providers/rules/loyalsoldier_reject` 199,133 条（配合 `reject_domainset` 149,448 条，见 3.6）；
面板里 `*自动` 应为隐藏。

## 7. 已知问题（未在本次改动中处理）

1. **订阅源当前不可达**：`<机场订阅地址>` 直连/走代理都超时（`code=000`），
   provider 刷新失败（`pull error: EOF`），节点列表冻结在 10:26 的 37 个（约 27 个存活）。
   `<节点 IP>:<端口> connection refused` 刷屏就是机场侧节点拒连，不是规则问题。
2. **IPv6 可能绕过代理**：`tun.auto-route` 只拿到 `inet4-address 198.18.0.1/30`，
   没有 `inet6-address`；主机有全局 `240e::/…`。若要强制 v6 走代理，在 `tun:` 下加
   `inet6-address: [fdfe:dcba:9876::1/126]` 后重启验证 `ip -6 route | grep Mihomo`。
   本次未改：无法在部署前实测，留给你决定。
3. **`dns.listen: 0.0.0.0:53` + `allow-lan: true`**：对局域网开放递归解析器（放大/污染风险）。
   若不需要 LAN DNS，改成 `127.0.0.1:53`。
4. **`127.0.0.1:7890` 连接超时**，而 `<本机 LAN IP>:7890` 正常——疑似本机残留的
   redirect/nft 规则，需要 root 查 `ss -tlnp 'sport = :7890'` 与 `nft list ruleset`。
5. **GCP 免费节点间歇性不可用**：会返回 `REALITY authentication failed`（孤立刻测试 5/5 通过、
   耗时 0.08s，但跑在主实例里会成片失败）。已隔离成独立组，不进自动优选；要用时手动选。
6. `rule-providers` 仍带 `proxy: Proxy`：代理全挂时规则集无法刷新（有本地缓存兜底）。
   若想更容易自愈，可去掉 `proxy:` 依赖 `respect-rules`（上游做法）。
