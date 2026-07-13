# Changelog

## Unreleased

## v0.3.17

- 本机候选测试：通用国内/私网基础规则改用 DustinWin MRS，通用海外域名改用 blackmatrix7 Global_Domain；保留专用业务规则和最终 `MATCH,DIRECT`。
- Google 基础规则改用 blackmatrix7 Google，补齐 Gmail 与通用 Google 域名，专用 Gemini / YouTube 规则继续优先匹配。
- 补齐 Claude 内容与 MCP、Codex/OpenAI CDN、Gemini/NotebookLM 专用端点，避免严格业务流量落入普通 `Proxies` 或共享 `Google` 组。
- 补充 OKX、Bybit、Binance 关联域名，继续限制交易所流量只使用 `TW / SG`。
- 将 `applications,DIRECT` 调整到业务规则之后、CN/Global 基础层之前，避免通用海外域名规则抢走应用直连流量。
- 增加严格业务域名与规则顺序回归测试，并同步更新路由设计文档。

## v0.3.16

- 修复节点名恰好为 `US / TW / Proxies` 等固定组名时，自动策略组形成同名循环并导致 Mihomo 拒绝启动的问题。
- 固定组因节点同名而使用备用名称时，同步改写 `rule-providers.*.proxy`，避免规则集下载误指向同名节点。
- 兼容订阅里的旧式 `FINAL,策略组` 兜底规则：自动转换为 Mihomo 支持的 `MATCH,策略组`，并同步改写备用策略组名称。
- 按括号层级解析 `AND / OR / NOT` 组合规则，确保组名复用或改名后，组合规则目标也能同步更新。
- 修复同时包含内联节点和 `proxy-providers` 的混合订阅被错误压缩、provider 策略组和节点入口消失的问题。
- provider 订阅已有 `Proxies / US / TW / SG` 等现成组时直接保留其 `use/filter/url-test` 配置，避免重写后形成策略组自循环。
- 强制管理已有 `Claude / AI / Exchange` 等业务组时清理 `use/filter/include-all` 等动态包含字段，防止受控地区之外的节点重新混入。
- 补充 OpenAI 专用域名及 OKX / Binance 相关资源域名，减少 AI 和交易所会话落入普通 `Proxies` 的出口拆分。
- Loyalsoldier 远程规则集显式通过 `Proxies` 下载，降低新机器首次直连 GitHub Raw 失败的概率。
- 敏感信息扫描新增 `CHANGELOG.md`、测试目录和最终打包目录，临时扫描文件改用随机文件名，避免并发扫描冲突。
- 自动备份清理仅处理安装器标准命名的备份，不再删除 `backup_*_manual_*` 手工备份。
- 新建文件清单改为可见的 `created-files.txt`，文档补充精确手动还原步骤。
- `created-files.txt` 对重复路径去重，避免同一缺失文件同时作为通用绑定和订阅绑定时重复列出。
- 调整 merge/script 写入顺序，修复通用文件安装前不存在时，同步步骤把新文件误存为旧备份、失败回滚后仍残留新配置的问题。
- macOS 安装脚本读取 `profiles.yaml` 时保留完整文件名，兼容带空格的 merge/script 文件名。
- 发布前新增 `Script.js` 语法检查和回归测试。

## 升级摘要：v0.3.4 -> v0.3.8

- 分流结构从“AI 主要走 US、交易所可选多地区”调整为更明确的受控组：`Claude: US`、`AI: US / TW`、`Exchange: TW / SG`。
- 交易所域名覆盖扩展到 OKX、Bybit、Binance、Bitget、Gate、KuCoin、MEXC 等，并固定只使用台湾/新加坡地区组。
- Claude / AI / Exchange 缺少目标地区节点时改为 `REJECT`，避免直连泄露或误用其它地区。
- 最终兜底从 `MATCH,Proxies` 改为 `MATCH,DIRECT`，避免国内 `.com` 小站误走代理导致 502。
- 安装脚本会同步 Clash Verge Rev 订阅绑定的随机 merge/script 文件，避免只改通用文件但当前订阅不生效。
- 修复安装脚本备份可能被新文件覆盖的问题，确保还原时拿到的是安装前旧配置。
- 移除基础配置里的 Loyalsoldier `reject` 广告拦截规则，降低登录、验证码、风控和国内网站误伤风险。
- 发布流程新增 `VERSION.txt` 单一版本来源和版本号格式校验，降低发错 zip 的风险。

## v0.3.15

- Windows 安装结构改为 `.bat` 极简双击入口，真正安装、备份、同步和回滚逻辑迁移到 `install-windows.ps1`。
- `install-windows.ps1` 保持纯 ASCII，通过 Base64 输出中文提示，兼顾 Windows PowerShell 5.1 编码兼容和中文安装体验。
- Release 包新增 `install-windows.ps1`，并在 build-release 中校验 Windows `.bat` / `.ps1` 都保持纯 ASCII。

## v0.3.14

- Windows 安装脚本改为纯 ASCII 批处理主体，通过 PowerShell 按 UTF-8 输出中文提示，避免 cmd 把中文行误解析成命令。
- Windows 安装成功提示同步显示 v0.3.13 起的新代理组顺序。
- build-release 增加 Windows .bat 纯 ASCII 校验，防止后续再次引入批处理编码问题。

## v0.3.13

- 固定代理页核心策略组显示顺序：业务组在前，地区组在后，最后是普通代理兜底，避免服务组和地区组混排。

## v0.3.12

- Windows 安装脚本恢复中文安装提示和中文错误说明，避免小白用户看到英文流程。
- 保持 PowerShell 同步脚本纯 ASCII，不回退 v0.3.10 修复过的 Windows PowerShell 5.1 编码问题。
- build-release 增加 Windows 安装入口中文提示校验，防止后续打包时又退回英文提示。
- README 移除“英文维护脚本”表述，避免和当前中文安装体验不一致。
- DeepSeek、Kimi、豆包、通义、文心、腾讯元宝、智谱、MiniMax 等中国大陆 AI 从国际 `AI` 组移出，改为明确 `DIRECT`，避免 US / TW 节点导致地区判断错误。

## v0.3.11

- Script.js 新增策略组界面压缩：普通内联节点订阅只保留核心业务组，隐藏订阅自带的杂乱原始策略组；无内联节点订阅保守保留原始组。

## v0.3.10

- 修复 Windows PowerShell 5.1 可能把 UTF-8 无 BOM 的 sync-profile-bound-files.ps1 按本地编码解析，导致安装时报 “string is missing the terminator” 的问题。
- sync-profile-bound-files.ps1 改为纯 ASCII 内容，Windows .bat 主逻辑也保持 ASCII 输出，避免 PowerShell / cmd 编码解析失败。
- build-release 增加 sync-profile-bound-files.ps1 纯 ASCII 检查，并在 Release zip 中把该脚本转为 CRLF。
- Windows 安装脚本改用环境变量向 sync-profile-bound-files.ps1 传递路径，避免空参数触发 PowerShell 交互式提示。
- sync-profile-bound-files.ps1 取消 Mandatory 参数，改为启动后校验必要目录并输出明确错误。
- Windows 安装脚本改为纯 ASCII 输出，避免 cmd 在不同系统编码下把中文提示误解析成命令；成功提示压缩为小白可读的短信息。
- Release zip 根目录只保留两个安装入口：`Windows点我安装.bat` 和 `macOS点我安装.command`；英文 install-* 脚本只作为仓库里的维护源文件。
- Windows 安装脚本补齐失败回滚：安装中途失败时会尝试从本次 backup_* 恢复，并删除本次新建的配置文件。
- sync-profile-bound-files.ps1 明确使用 UTF-8 读取 profiles.yaml，并把新建的订阅绑定文件写入回滚清单。
- 移除 macOS 回滚逻辑中无法被 glob 命中的 `.created-files` 死分支，降低维护误导。
- build-release 修复 Python ZipInfo 默认 STORE 导致 Release zip 未压缩的问题。
- Windows 安装脚本提前检查 PowerShell，避免无 PowerShell 环境下先创建 backup_* 再失败。
- build-release 统一 Release zip 内文件权限：普通文件 0644，macOS 安装入口 0755，避免源文件权限差异进入发布包。
- 仓库根目录也新增 `Windows点我安装.bat` 和 `macOS点我安装.command`，避免从 GitHub Code 下载源码时只看到英文 install-* 维护脚本。

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
