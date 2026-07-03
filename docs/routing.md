# Routing Notes

这套配置目标是“分流合理、风控变量少、适合小白导入”。

核心策略：

- `US`：Claude、OpenAI、Gemini 等高风险 AI。缺少美国节点时会降级到 `Proxies`。
- `Google`：Google 账号、登录、OAuth、支付入口和 Google 生态。
- `YouTube`：YouTube、googlevideo、ytimg 等视频相关域名。
- `Exchange`：OKX、Bybit、Binance、Bitget、Gate 等交易所域名。
- `DIRECT`：局域网、国内 IP、钉钉、常规 Apple/iCloud。
- `Proxies`：普通海外代理兜底；如果订阅里已有 `proxies` / `PROXIES` 等大小写变体，会复用原组名并自动改写规则目标，避免出现两个相似组。

使用建议：

- AI 不和日常娱乐共用浏览器 Profile。
- 交易所单独浏览器，不装广告拦截、隐私防追踪、指纹伪装插件。
- 看视频去广告放到浏览器插件层，不放到系统 DNS 或 AdGuard 本地 VPN 层。
- 基础配置不启用 `RULE-SET,reject` 广告/追踪拦截，优先避免国内站点登录、风控、统计接口被误伤。
- DNS 交给 Clash Verge Rev 的 fake-ip / DoH / DNS hijack，不额外叠系统级 AdGuard DNS。
- 当前 DNS 不使用 `geosite:cn`、`fallback`、`fallback-filter` 或 GeoIP/MMDB 兜底，避免新机器首次启动时下载 GEO 数据失败。
- 国内 DNS 只通过 `nameserver-policy` 的 `+.cn` 和 `direct-nameserver` 兜底处理；海外域名默认走 Google / Cloudflare DoH。
- `prefer-h3` 保持关闭，避免和 `respect-rules` 组合造成 DNS 行为不稳定。

交易所注意：

`Exchange` 只是分流隔离，不代表可绕过平台地区限制。交易所出口应按账号自身允许使用的地区选择。

兼容策略：

- 安装脚本不再要求订阅必须有固定策略组名。
- 安装脚本会同步 `profiles.yaml` 中已有订阅绑定的 merge/script 文件，避免当前订阅继续使用旧脚本。
- `Script.js` 会自动补齐 `Proxies / US / Google / YouTube / Telegram / Exchange`；如果已有大小写不同的同名组，会复用已有组名并改写规则目标。
- 能识别地区节点时，自动生成 `HK / JP / SG / TW / US`。
- 识别不到地区时，降级到 `Proxies` 或 `DIRECT`，优先保证配置能启动。
