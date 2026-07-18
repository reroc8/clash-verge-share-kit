# Routing Notes

这套配置目标是“分流合理、风控变量少、适合小白导入”。

核心策略：

- `Claude`：Claude / Anthropic 独立组，只保留 `US`。
- `AI`：OpenAI、Gemini、Copilot、Cursor、Perplexity 等国际 AI 服务，只保留 `US / TW` 两个地区组；默认优先 US。OpenAI 专用静态与状态域名一并进入该组，减少同一会话落入普通 `Proxies` 的出口拆分。
- `Google`：Google 账号、登录、OAuth、支付入口和 Google 生态。
- `YouTube`：`youtube.com`、`youtu.be`、`youtube-nocookie.com`、`youtubeeducation.com`、`youtubegaming.com`、`youtubekids.com`、`googlevideo.com`、`ytimg.com`、`youtubei.googleapis.com`、`yt3.ggpht.com` 等视频、图片、嵌入播放器和儿童/教育子产品域名。
- `Exchange`：OKX、Bybit、Binance、Bitget、Gate、KuCoin、MEXC、Crypto.com、Coinbase、Kraken、HTX、BingX、BitMart、Bitfinex、Bitstamp、Upbit 等交易所主域名、静态资源域名和 HTTPDNS 辅助域名。
- `DIRECT`：局域网、国内 IP、钉钉、常规 Apple/iCloud、DeepSeek、Kimi、豆包、通义、文心、腾讯元宝、智谱、MiniMax 等中国大陆 AI。
- `Proxies`：明确海外规则命中的普通代理；如果订阅里已有 `proxies` / `PROXIES` 等大小写变体，会复用原组名并自动改写规则目标。节点名与固定组名冲突时，自动组使用 `US Group` 等备用名，避免代理组循环。

代理页显示顺序固定为：

```text
Claude / AI / Google / YouTube / Telegram / Exchange / US / TW / SG / HK / JP / Proxies
```

前 6 个是业务组，中间 5 个是地区节点池，最后 `Proxies` 是普通代理兜底。

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

最终规则使用 `MATCH,DIRECT`，不是 `MATCH,Proxies`。原因是国内很多小站是 `.com`，不一定会被国内规则集收录；如果未知域名默认走代理，节点或上游可能返回 502。当前设计先处理 Claude、国际 AI、Google、YouTube、Telegram 和交易所等专用业务规则，再处理应用直连；DustinWin MRS 负责私网、国内域名、国内 IP 和国外顶级域名，blackmatrix7 Global_Domain 负责常见海外域名补漏。中国大陆 AI、国内网站和剩余未知流量默认直连，优先保证国内网站和小白用户日常访问稳定。

这个取舍的副作用是：少数没被规则集覆盖的海外冷门网站可能直连失败。遇到这类网站时，应补明确域名规则，而不是把全局兜底改回 `Proxies`。

交易所注意：

`Claude`、`AI` 和 `Exchange` 都只是分流隔离，不代表可绕过平台地区限制。`Claude` 只保留 `US`，国际 `AI` 只保留 `US / TW`，`Exchange` 只保留 `TW / SG`，都不混入其它地区、DIRECT 或 Proxies；没有对应地区节点时使用 `REJECT`，避免直连泄露或误用其它地区。DeepSeek、Kimi、豆包、通义、文心、腾讯元宝、智谱、MiniMax 等中国大陆 AI 明确走 `DIRECT`。未知站点最终兜底为 `DIRECT`，避免国内小站误走代理。

兼容策略：

- 安装脚本不再要求订阅必须有固定策略组名。
- 安装脚本会同步 `profiles.yaml` 中已有订阅绑定的 merge/script 文件，避免当前订阅继续使用旧脚本。
- `Script.js` 会自动补齐 `Proxies / Claude / AI / US / Google / YouTube / Telegram / Exchange`；如果已有大小写不同的同名组，会复用已有组名并改写规则目标。
- 顶层节点键优先使用标准小写 `proxies`；小写键缺失时兼容 `Proxies / PROXIES` 等大小写变体，并统一规范化为小写。
- 纯内联节点订阅会压缩原始策略组；存在 `proxy-providers` 的纯 provider 或混合订阅会保留原始 provider 组，避免节点入口丢失。
- 纯内联节点订阅如果仍有规则、子规则或规则集下载引用自定义组，会自动关闭压缩并保留全部原始组，避免规则指向不存在的策略组。
- 远程规则集显式通过 `Proxies` 下载，降低新机器首次启动时直连 GitHub Raw 失败的概率。
- `Claude` 组会被强制更新为仅包含 `US`，用于降低 Claude 出口地区变化。
- `AI` 组会被强制更新为仅包含 `US / TW`，用于降低国际 AI 服务出口地区变化；中国大陆 AI 不进入该组。
- `Exchange` 组会被强制更新为仅包含 `TW / SG`，用于降低交易所登录出口地区变化。
- 能识别地区节点时，自动生成 `HK / JP / SG / TW / US`。
- 代理页核心组会重新排序为业务组、地区组、普通代理兜底，不保留订阅原始组的混排顺序。
- 识别不到地区时，降级到 `Proxies` 或 `DIRECT`，优先保证配置能启动。
