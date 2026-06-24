# Routing Notes

这套配置目标是“分流合理、风控变量少、适合小白导入”。

核心策略：

- `US`：Claude、OpenAI、Gemini 等高风险 AI。缺少美国节点时会降级到 `Proxies`。
- `Google`：Google 账号、登录、OAuth、支付入口和 Google 生态。
- `YouTube`：YouTube、googlevideo、ytimg 等视频相关域名。
- `Exchange`：OKX、Bybit、Binance、Bitget、Gate 等交易所域名。
- `DIRECT`：局域网、国内 IP、钉钉、常规 Apple/iCloud。
- `Proxies`：普通海外代理兜底。

使用建议：

- AI 不和日常娱乐共用浏览器 Profile。
- 交易所单独浏览器，不装广告拦截、隐私防追踪、指纹伪装插件。
- 看视频去广告放到浏览器插件层，不放到系统 DNS 或 AdGuard 本地 VPN 层。
- DNS 交给 Clash Verge Rev 的 fake-ip / DoH / DNS hijack，不额外叠系统级 AdGuard DNS。

交易所注意：

`Exchange` 只是分流隔离，不代表可绕过平台地区限制。交易所出口应按账号自身允许使用的地区选择。

兼容策略：

- 安装脚本不再要求订阅必须有固定策略组名。
- `Script.js` 会自动补齐 `Proxies / US / Google / YouTube / Telegram / Exchange`。
- 能识别地区节点时，自动生成 `HK / JP / SG / TW / US`。
- 识别不到地区时，降级到 `Proxies` 或 `DIRECT`，优先保证配置能启动。
