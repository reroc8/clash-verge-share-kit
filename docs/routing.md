# Routing Notes

这套配置目标是“分流合理、风控变量少、适合小白导入”。

核心策略：

- `AI`：统一承载 Claude / Anthropic、OpenAI / Codex、Copilot、Cursor、Perplexity 等国际 AI 服务，只保留 `US` 地区组。Gemini、NotebookLM 等 Google AI 归入 `Google + YouTube + Telegram` 组，默认台湾。这样 Claude 与 Codex 使用同一个出口，避免同一账号在两个业务组之间选出不同地区。OpenAI 专用静态与状态域名一并进入该组，减少同一会话落入普通 `Proxies` 的出口拆分。取舍是 Codex 等服务没有 TW 备用，首次连接可能增加跨洲 RTT；持续速度仍取决于节点质量和拥塞。
- AI 专属的 Feature Gates、Feature Assets、Statsig 配套域名也进入 `AI` 组，避免功能开关和遥测接口落到不同出口。hCaptcha、Cloudflare challenge、Stripe 同时服务大量非 AI 站点，沿用通用规则，不固定到 US-only 的 `AI` 组。
- OpenAI / ChatGPT 的 UDP/443 仅按域名拒绝，强制回落 TCP；不做全局 UDP/443 或 STUN 拦截，避免影响会议、游戏和其它 HTTP/3 流量。
- `Google + YouTube + Telegram`：Google 账号、登录、OAuth、支付入口、Gemini / NotebookLM / Google AI、YouTube 和 Telegram 共用同一个默认 `TW` 出口，避免同一 Google 账号在 Google 与 YouTube 之间出现地区分裂。
- 业务组统一遵循「**地区优先**」：`AI` / `Google + YouTube + Telegram` / `Exchange` 的**第一个选项都是明确的地区组**，`Proxies`（兜底组）降到选项列表末尾。这样每个组的默认行为都能一句话说清：

| 组 | 默认首选 | 理由 |
|---|---|---|
| `AI` | `US` | Claude / Codex 等国际 AI 统一出口 |
| `Google + YouTube + Telegram` | `TW` | 同一 Google 账号与日常海外服务共用出口 |
| `Exchange` | `TW` | 台 / 新 |

  早先三个业务组把 `Proxies` 放在首位，默认行为因此是「跟随 `Proxies` 当前选中的节点」——分组形同虚设，此时观察到的出口地区只是 `Proxies` 恰好选到某地区的巧合，换掉 `Proxies` 的节点，Google、YouTube 和 Telegram 的出口就一起变化。统一组仍保留 `Proxies` 选项（排在后面），需要「跟随全局」时依旧可选。
- `Google + YouTube + Telegram`：Google 账号与 AI 生态、YouTube 视频和 CDN、Telegram 域名及官方 IP 段共用一个业务组，默认 `TW`；三者需要同一地区时只维护一个选择。
- `Exchange`：OKX、Bybit、Binance、Bitget、Gate、KuCoin、MEXC、Crypto.com、Coinbase、Kraken、HTX、BingX、BitMart、Bitfinex、Bitstamp、Upbit 等交易所主域名、静态资源域名和 HTTPDNS 辅助域名。
- `DIRECT`：局域网、国内 IP、钉钉（含进程级兜底，见下）、常规 Apple/iCloud、DeepSeek、Kimi、豆包、通义、文心、腾讯元宝、智谱、MiniMax 等中国大陆 AI。
- `Proxies`：明确海外规则命中的普通代理；如果订阅里已有 `proxies` / `PROXIES` 等大小写变体，会复用原组名并自动改写规则目标。节点名与固定组名冲突时，自动组使用 `US Group` 等备用名，避免代理组循环。

代理页只把三层核心组作为主要入口：

```text
业务组：AI / Google + YouTube + Telegram / Exchange
地区组：US / TW / SG / HK / JP / UK（按订阅节点实际生成）
普通代理：Proxies
```

业务组表达“这个服务应该走什么出口”，地区组表达“这个地区有哪些节点”，`Proxies` 负责普通海外规则和用户手动兜底。机场自带的 `PROXY`、`GLOBAL`、`订阅更新`、`Auto`、`Fallback` 等技术组会保留，供原始规则、provider、监听器或隧道继续引用，但会标记为隐藏，不再与三层核心组并列显示。没有命中技术组名称的自定义组仍保留可见，避免破坏用户自己的策略入口。

使用建议：

- AI 不和日常娱乐共用浏览器 Profile。
- 交易所单独浏览器，不装广告拦截、隐私防追踪、指纹伪装插件。
- 看视频去广告放到浏览器插件层，不放到系统 DNS 或 AdGuard 本地 VPN 层。
- 基础配置不启用 `RULE-SET,reject` 广告/追踪拦截，优先避免国内站点登录、风控、统计接口被误伤。
- DNS 交给 Clash Verge Rev 的 fake-ip / DoH / DNS hijack，不额外叠系统级 AdGuard DNS。
- 当前 DNS 不使用 `geosite:cn`、`fallback`、`fallback-filter` 或 GeoIP/MMDB 兜底，避免新机器首次启动时下载 GEO 数据失败。
- 国内 DNS 只通过 `nameserver-policy` 的 `+.cn` 和 `direct-nameserver` 兜底处理；海外域名默认走 Google / Cloudflare DoH。
- `prefer-h3` 保持关闭，避免和 `respect-rules` 组合造成 DNS 行为不稳定。

最终兜底：

最终规则使用 `MATCH,DIRECT`，不是 `MATCH,Proxies`。原因是国内很多小站是 `.com`，不一定会被国内规则集收录；如果未知域名默认走代理，节点或上游可能返回 502。当前设计先处理国际 AI（含 Claude / Codex）、Google AI、YouTube、Telegram 和交易所等专用业务规则，再处理应用直连；DustinWin MRS 负责私网、国内域名、国内 IP 和国外顶级域名，blackmatrix7 Global_Domain 负责常见海外域名补漏。中国大陆 AI、国内网站和剩余未知流量默认直连，优先保证国内网站和小白用户日常访问稳定。

这个取舍的副作用是：少数没被规则集覆盖的海外冷门网站可能直连失败。遇到这类网站时，应补明确域名规则，而不是把全局兜底改回 `Proxies`。

交易所注意：

`AI` 和 `Exchange` 都只是分流隔离，不代表可绕过平台地区限制。国际 AI（含 Claude / Codex）只保留 `US`，`Exchange` 只保留 `TW / SG`。这三个地区组会重新筛选节点，不沿用订阅同名组中的嵌套组、DIRECT 或 Proxies，且统一为手动选择，不继承自动测速切换。没有对应地区节点时使用 `REJECT`，不直连兜底；`US` 始终存在但为空时也只含 `REJECT`，直接指向 US 的 Lexmount、mail.com 等规则同样会被拒绝。

对于动态 provider，三个地区组直接引用 provider 并在内核中按节点名称过滤；更新时仍执行相同过滤。`empty-fallback: REJECT` 用于阻止筛空后的默认 `COMPATIBLE` 回退（见 [Mihomo 代理组字段](https://wiki.metacubex.one/config/proxy-groups/#empty-fallback)）。因此没有美国节点时，纯内联订阅的 `AI` 显示 `REJECT`；provider 订阅可能显示 `AI → US → REJECT`。原订阅的非受管组仍保留给普通流量使用，不作为 AI/Exchange 的地区证明。

识别依据仍是节点标签，不是出口 IP 检测。含多个已识别地区的名称（如 `US HK`）会被保守排除；只有 `US` 组名、节点却叫 `Node 01` 的订阅也不会被推定为美国，需按已核实的出口地区修正节点名。无法保证标签真实、供应商不改变出口，或平台不触发风控。DeepSeek、Kimi、豆包、通义、文心、腾讯元宝、智谱、MiniMax 等中国大陆 AI 明确走 `DIRECT`。未知站点最终兜底为 `DIRECT`，避免国内小站误走代理。

钉钉防偷跑：

钉钉主程序内嵌 Google Firebase / Crashlytics 等海外分析 SDK，其海外对端（Google IP 段）会被 `RULE-SET,google` 命中并送入代理组，实测存在后台持续上传（仅上不下、量级上百 MB）的情况。钉钉自身的钉盘同步、会议中继、大文件 P2P 加速也可能产生大流量，若对端在海外同样会消耗订阅流量。因此在域名直连规则之外增加进程级兜底：

```yaml
- PROCESS-NAME-REGEX,(?i)ding(talk|meeting),DIRECT
```

该规则按进程名匹配（大小写不敏感），覆盖主进程 `DingTalk` 与会议子进程 `DingMeeting` 等全家桶。规则置于私网直连之后、所有业务精确域名规则之前，因此**无条件生效**：钉钉进程的任何连接都会被强制直连，不受后面 AI/Google 精确域名规则或规则集影响。已知的边缘取舍是钉钉内置浏览器打开 AI 等需代理站点时同样走直连（无法加载），对 IM 场景可接受。钉钉自己的域名直连规则保留在原位置，服务于浏览器等非钉钉进程访问钉钉站点。`MATCH,DIRECT` 兜底保证其余国内应用（网盘、远程桌面等）只有命中代理规则集时才走代理，无需逐个加进程规则。修改 Merge.yaml 后需重新激活订阅（或重启内核）才生效。

验证工具：`scripts/clash-monitor.sh` 与同目录 `monitor-traffic.py` 配合，通过内核 Unix socket（无需开启外部控制器 TCP 端口）按连接 ID 计算增量，再按进程和路径分类汇总。首次采样只建立基线，不把启动前的历史累计量算进本次；之后出现的新连接计入已观察到的累计字节，存活连接按自身计数差值计算，旧连接关闭不再抵消其他连接的增量。

新日志默认写 `monitor/clash-traffic-v2.log`，CSV 六列为 `timestamp,process,upload_delta_mb,download_delta_mb,connections,route`，其中 MB 按 1048576 字节换算。`route` 分为 `proxy`（代理）、`direct`（直连）、`unknown`（未知），终端也分别显示；同进程的三类流量不会混算。路径根据连接实际出站节点和 API 返回的类型判断，不按策略组名称猜测；provider 节点按 provider 名与节点名共同定位。类型元数据缺失或不认识时保留未知，不能当作已证实的代理流量。可用它复查某应用的**已观测连接**是否走代理。

边界：轮询只能看到当时仍存活的连接，采样间开始并结束的短连接、已关闭连接最后一段字节可能漏计；`unknown` 也不代表直连。因此观测累计不是完整流量审计，更不是机场计费账单。原 `clash-traffic.log` 保留不动；若手动指定已有五列旧日志，脚本会拒绝追加并提示换新文件，避免格式混写。只拷贝启动器不够，应保留完整 `scripts/` 目录。

接口地址由脚本自动探测，**不再写死**：Clash Verge Rev 2.5.4 起 macOS 上分两种形态——服务模式为 `/var/run/clash-verge-service/users/<uid>/verge-mihomo.sock`，用户模式（Sidecar）为 `$TMPDIR/verge-mihomo.sock`；只有 2.5.4 之前的旧版本才是固定的 `/tmp/verge/verge-mihomo.sock`。也可用 `CLASH_SOCK=/路径` 手动指定。注意 `clash-verge.yaml` 里的 `external-controller-unix` 在服务模式下写的仍是用户模式地址，不能当作当前实际在用的地址。

WorkBuddy 遥测强制代理：

WorkBuddy AI 国际版的遥测端点 `sg.tgalileo.com` 解析到腾讯云新加坡（43.156.86.0/24），但该域在 `cn-domain` 规则集里（`+.tgalileo.com`），按常规会被判为国内直连。因此在业务规则区最前面加了一条精确规则：

```yaml
- DOMAIN-SUFFIX,tgalileo.com,Proxies
```

位次在两条私网规则与钉钉进程规则之后、其余业务规则与规则集之前。这是「国内域名直连」原则的一个已知例外，且**必须留在 `cn-domain` 之前**：`cn-domain` 是唯一会把该域劫持成直连的规则集（`applications` 与 `global-domain` 实测都不含它），一旦排到后面，这条规则就等于没写。`tests/test-script.js` 对此有位次断言。

取舍：该规则把遥测 SNI 从「对 ISP 可见」变为「对代理节点可见」，并非消除可见性；换来的是 ISP 侧看不到该 SNI，以及海外端点走代理链路的质量。另外目标组 `Proxies` 是可手动选择、且选项里含 `DIRECT` 的通用组，是否真的走代理取决于用户当前选择（`DIRECT` 排在最后，默认第一项是真节点，实际会走代理）。国内版遥测 `galileotelemetry.tencent.com` 命中 `cn-domain` 的 `+.tencent.com`，继续直连。

地区受限服务的出口定向：

有四个服务对出口有明确要求，各加了精确规则（都排在通用规则集之前）：

- **Lexmount**（AI Agent 云浏览器，`browser.lexmount.com`）：云浏览器服务需海外出口；该域不在任何规则集内，默认会落到兜底 `DIRECT`。

```yaml
- DOMAIN-SUFFIX,lexmount.com,US
```

- **订阅服务商面板**（`vx.wjkc.xyz` / `www.wjkc.xyz`）：解析到 Cloudflare（`104.21.x` / `172.67.x`），国内直连常被干扰限速（实测 2–15 秒波动）；该域不在任何规则集内，默认会落到兜底 `DIRECT`。

```yaml
- DOMAIN-SUFFIX,wjkc.xyz,TW
```

  目标写地区组名而非兜底组，出口可预期。

- **Meta Muse**（个人 AI 代理，2026-09 起仅北美开放）与 **muse.ai**：需美区出口，归入统一的 `AI` 组。Muse 桌面版实际连的是 `graph.facebook.com` 等 Meta 域名（在 `global-domain` 规则集内），按域名无法与服务区分，故用进程名前缀匹配（以覆盖可能存在的 helper 子进程）；网页版入口 `muse.meta.com` 另加域名规则。`muse.ai` 是同名的另一个产品（视频 AI 平台），一并定向。

```yaml
- PROCESS-NAME-REGEX,(?i)^muse,AI
- DOMAIN-SUFFIX,muse.meta.com,AI
- DOMAIN-SUFFIX,muse.ai,AI
```

- **Dola**（字节豆包海外版，`dola.com`）：**区域锁定——美国、加拿大、澳大利亚、中国大陆均不可用**，主力市场为东南亚与英国。

```yaml
- DOMAIN-SUFFIX,dola.com,SG
```

  注意这里用 `SG` 而不是 `US`：Dola 明确屏蔽美国 IP，走 `US` 反而不可用。

- **PriceAI**（`priceai.cc`，AI 订阅/中转 API 比价雷达）与 **982xj.xyz**：都是 Cloudflare 站点（`104.21.x` / `172.67.x`），不在任何规则集内，默认落兜底 `MATCH,DIRECT`。实测国内直连极差——`priceai.cc` 3 次里 2 次 5 秒超时，成功那次 TLS 握手 5.5s、首字节 11.2s；`982xj.xyz` 3 次里 1 次超时，成功那次 TLS 1.2–3.1s、首字节 2.6–3.8s，CF-RAY 落 LAX。同一批域经台湾节点实测 38ms。

```yaml
- DOMAIN-SUFFIX,priceai.cc,Google + YouTube + Telegram
- DOMAIN-SUFFIX,982xj.xyz,Google + YouTube + Telegram
```

  目标写 `Google + YouTube + Telegram` 组而非具体地区组：该组由 `Script.js` 保证存在、默认台湾出口，不依赖订阅是否恰好生成了某个地区组。

位次要求：以上规则必须排在 `global-domain`、`tld-proxy`、`cn-domain` 之前。Muse 的进程规则若落到 `global-domain` 之后，`graph.facebook.com` 会先被判给 `Proxies`（默认台湾出口，Muse 不可用）；`muse.ai` 同理会被 `tld-proxy` 抢走。`tests/test-script.js` 对这八条规则都有位次断言。

取舍：这些是**把某个服务固定到某地区组**，组内节点仍由用户选择。只有规则的地区目标组本身不存在时，才沿用兼容逻辑改指 `Proxies`，此时不保证地区要求；已生成的受限 `US / TW / SG` 组如果筛空，则使用 `REJECT`。`AI / Exchange` 不使用上述缺组降级逻辑，始终拒绝不具备合格地区节点的连接。

兼容策略：
- 安装脚本不再要求订阅必须有固定策略组名。
- 安装脚本会同步 `profiles.yaml` 中已有订阅绑定的 merge/script 文件，避免当前订阅继续使用旧脚本。
- `Script.js` 会自动补齐 `Proxies / AI / US / Google + YouTube + Telegram / Exchange`；旧订阅里的 `Google`、`YouTube`、`Telegram` 组会隐藏并指向统一组，旧规则目标会自动改写。
- 统一 Google 组的完整名称也参与大小写不敏感映射；复用小写组名，或因节点/provider 重名分配备用组名时，主规则、子规则和规则集下载目标均使用实际组名。
- 顶层节点键优先使用标准小写 `proxies`；小写键缺失时兼容 `Proxies / PROXIES` 等大小写变体，并统一规范化为小写。
- 纯内联节点订阅会压缩原始策略组；存在 `proxy-providers` 的纯 provider 或混合订阅会保留非受管 provider 组。`US / TW / SG` 由受限过滤重新建立；与节点或 provider 重名时使用 `US Group` 等备用名，避免名称冲突。
- 纯内联节点订阅如果仍有规则、子规则、规则集下载、`dialer-proxy`、监听器、隧道或 NTP 引用自定义组，会自动关闭压缩并保留全部原始组，避免生成悬空引用。
- 删除提示节点时同步清理保留组的成员；残留规则目标、监听器等引用改为 `REJECT`，空组也拒绝连接。兼容别名建立后检查完整依赖链，只移除 `Proxies` 与统一 Google 组中造成循环的选项，保留其他自定义入口。
- 订阅原有的 `REJECT` 规则和 reject rule-provider 会保留；基础包自身不注入广告拦截规则。
- 远程规则集显式通过 `Proxies` 下载，降低新机器首次启动时直连 GitHub Raw 失败的概率。
- `AI` 组会被强制更新为仅包含 `US`，用于统一 Claude / Codex / OpenAI 等国际 AI 的出口地区；中国大陆 AI 不进入该组。旧订阅里的 `Claude` 组会保留为隐藏兼容别名。
- `Exchange` 组会被强制更新为仅包含 `TW / SG`，用于降低交易所登录出口地区变化。
- 能识别地区节点时，自动生成 `HK / JP / SG / TW / US / UK`。
- 代理页核心组会重新排序为业务组、地区组、普通代理兜底，不保留订阅原始组的混排顺序。
- 普通海外流量保留 `Proxies` / `DIRECT` 兼容兜底；`AI / Exchange` 缺合格地区节点时拒绝连接，不扩大到其它地区或直连。
