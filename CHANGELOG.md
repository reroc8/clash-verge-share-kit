# Changelog

## 升级摘要：v0.3.4 -> v0.3.8

- 分流结构从“AI 主要走 US、交易所可选多地区”调整为更明确的受控组：`Claude: US`、`AI: US / TW`、`Exchange: TW / SG`。
- 交易所域名覆盖扩展到 OKX、Bybit、Binance、Bitget、Gate、KuCoin、MEXC 等，并固定只使用台湾/新加坡地区组。
- Claude / AI / Exchange 缺少目标地区节点时改为 `REJECT`，避免直连泄露或误用其它地区。
- 最终兜底从 `MATCH,Proxies` 改为 `MATCH,DIRECT`，避免国内 `.com` 小站误走代理导致 502。
- 安装脚本会同步 Clash Verge Rev 订阅绑定的随机 merge/script 文件，避免只改通用文件但当前订阅不生效。
- 修复安装脚本备份可能被新文件覆盖的问题，确保还原时拿到的是安装前旧配置。
- 移除基础配置里的 Loyalsoldier `reject` 广告拦截规则，降低登录、验证码、风控和国内网站误伤风险。
- 发布流程新增 `VERSION.txt` 单一版本来源和版本号格式校验，降低发错 zip 的风险。

## v0.3.10

- 修复 Windows PowerShell 5.1 可能把 UTF-8 无 BOM 的 sync-profile-bound-files.ps1 按本地编码解析，导致安装时报 “string is missing the terminator” 的问题。
- sync-profile-bound-files.ps1 改为纯 ASCII 内容，Windows 安装脚本继续保留中文错误提示。
- build-release 增加 sync-profile-bound-files.ps1 纯 ASCII 检查，并在 Release zip 中把该脚本转为 CRLF。

## v0.3.9

- build-release 增加 CHANGELOG.md 校验，正式版本必须有当前版本标题和变更条目。
- docs/routing.md 补充 MATCH,DIRECT 的设计理由：避免国内 .com 小站误走代理导致 502。
- 将 codebuddy.cn / copilot.tencent.com 自定义直连提前到宽泛代理规则前，避免被后续规则集抢先命中。
- 移除 Script.js 中冗余且容易误解的 `🇨🇳 Taiwan` 台湾节点识别正则。
- 新增 v0.3.4 到 v0.3.8 的跨版本升级摘要，并将 CHANGELOG.txt 打入 Release zip。
- Windows 订阅绑定文件同步拆成独立 PowerShell 脚本，使用 ErrorAction Stop 和 try/catch，避免 Copy-Item 失败被吞。
- macOS 安装脚本移除备份时的静默错误隐藏；安装中途失败时会尝试从本次备份恢复已覆盖文件。
- 文档补齐 YouTube 子产品和视频 CDN 域名说明，与 Merge.yaml 的实际规则保持一致。

## v0.3.8

- 新增根目录 VERSION.txt，作为发布版本唯一来源。
- build-release 只接受 vX.Y.Z 格式，且参数版本必须与 VERSION.txt 一致。
- 正式版本构建后自动清理 dist 旧 zip，降低发错包风险。
- Windows 安装脚本改用 for /f 读取 VERSION.txt，减少换行兼容风险。

## v0.3.7

- 修复 macOS / Windows 安装脚本在同步已有 merge/script 绑定文件时覆盖旧备份的问题。
- Windows 安装脚本同步处理 profiles.yaml file 字段的单引号和双引号。

## v0.3.6

- Claude 独立成组，只保留 US。
- AI 组只保留 US / TW。
- Exchange 组只保留 TW / SG，并补充主流交易所域名。
- Claude / AI / Exchange 缺少目标地区节点时使用 REJECT，避免直连泄露或误用其它地区。
- 最终兜底为 DIRECT，减少国内 .com 小站误走代理导致 502。

## v0.3.5

- 增加 Claude / AI / Exchange 的受控分流设计。
- 扩展交易所规则覆盖。
- 同步 README 和安装提示。
