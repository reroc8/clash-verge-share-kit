# Clash Verge Rev Share Kit

面向小白用户的 Clash Verge Rev 稳定分流配置包：下载、解压、双击安装，让 Claude、ChatGPT、Google、YouTube、Telegram、交易所和国内网站各走各的线路。

这个项目只提供配置模板和安装脚本，**不包含任何订阅、节点、账号、密码或 token**。使用者必须先导入自己的订阅。

<!-- release-readme:start -->

## 这是什么

你已经有自己的机场订阅，但只会导入、不会调。这个包帮你把常见网站自动分到合适的策略组：

| 你打开的网站 | 它会尽量安排到 |
|---|---|
| Claude | `Claude`（美区专用） |
| ChatGPT / Gemini / Copilot / Cursor 等国际 AI | `AI`（US / TW） |
| DeepSeek / Kimi / 豆包 / 通义 / 文心 / 腾讯元宝 / 智谱 / MiniMax 等中国大陆 AI | 直连 |
| Google / Gmail / Google 登录 | `Google` |
| YouTube / YouTube Kids / 嵌入播放器 | `YouTube` |
| Telegram | `Telegram` |
| OKX / Bybit / Binance / Bitget / Gate / KuCoin / MEXC 等 | `Exchange`（TW / SG） |
| 国内网站、局域网 | 直连 |
| 明确海外网站 | `Proxies` |

安装后，Clash Verge Rev 的代理页会出现 `Claude / AI / Google / YouTube / Telegram / Exchange` 这些业务组，按用途选一个稳定节点即可，不需要理解"规则""策略组""DNS"这些词。

## 适合谁

- 你已经有自己的机场订阅，但只会导入，不知道后面怎么调。
- 你希望 ChatGPT、Claude、Gemini 这类 AI 尽量稳定，不想今天能用明天异常。
- 你希望 YouTube、Google、Gmail、Telegram、交易所和国内网站各走各的，不要混在一起。
- 你更重视网页能正常打开，不希望系统级广告拦截误伤国内网站。
- 你不想研究"规则""策略组""DNS""TUN"这些词，只想下载、解压、双击安装。
- 你经常帮家人、朋友、新机器配置 Clash Verge Rev，希望有一个不会带自己订阅的公开包。
- 你愿意让自己的 AI Agent 帮忙安装，但不希望它接触或泄露你的订阅、节点、token。

## 不适合谁

- 你还没有任何 Clash Verge Rev 订阅。这个包不提供节点，也不能替代机场订阅。
- 你想拿到作者的节点、订阅、账号或 token。这个项目没有这些内容。
- 你已经有一套很复杂的自定义配置，并且不希望 `Merge.yaml`、`Script.js`、`verge.yaml`、`dns_config.yaml` 被覆盖。
- 你想用它绕过交易所、AI、流媒体的平台地区限制。这个包只做线路整理，不处理账号合规问题。
- 你想靠它做系统级广告拦截或视频去广告。基础包为稳定优先，不启用 `REJECT` 广告规则。
- 你需要公司级、团队级、审计级的统一代理方案。这个包是个人使用和小白分享场景。
- 你完全不想备份、不想看提示、也不愿意先退出 Clash Verge Rev。安装脚本会要求先退出软件。

## 安装

### 安装前

1. 安装 Clash Verge Rev。
2. 导入自己的订阅。
3. 打开 Clash Verge Rev，并确认能正常代理。
4. 完全退出 Clash Verge Rev。

### 安装方式

1. 下载 Release 里的 zip。
2. 解压 zip。
3. 完全退出 Clash Verge Rev。
4. 按系统双击安装脚本：

- macOS：双击 `macOS点我安装.command`
- Windows 10/11：双击 `Windows点我安装.bat`

Windows 的 `.bat` 只是双击入口，真正安装逻辑在 `install-windows.ps1`。普通用户只需要双击 `Windows点我安装.bat`。

如果你是从 GitHub 的 Code 下载源码，也同样双击项目根目录这两个中文入口，不要进 `install/` 目录找维护脚本。

安装脚本会显示安装包版本和来源目录，然后先备份原文件，再覆盖通用配置，并同步已有订阅绑定的 merge/script 文件：

```text
profiles/Merge.yaml
profiles/Script.js
verge.yaml
dns_config.yaml
```

安装脚本不会修改订阅和节点。

### 安装后 60 秒检查清单

安装完成并重新打开 Clash Verge Rev 后，按下面顺序快速看一遍：

| 检查项 | 打开什么 | 正常表现 | 如果不正常先看哪里 |
|---|---|---|---|
| Google | `google.com` 或 Gmail | 能打开、能搜索或进入邮箱 | `Google` 组换一个稳定节点 |
| YouTube | `youtube.com` | 首页图片能加载，视频能播放 | `YouTube` 组换节点 |
| Claude | `claude.ai` | 能打开并正常对话 | `Claude` 组只选 US；如果只有 REJECT，先补美国节点 |
| 交易所 | OKX / Bybit / Binance | 页面能打开，登录前确认账号允许地区 | `Exchange` 只选 TW / SG；如果只有 REJECT，就先别登录 |
| 国内网站 | 百度、淘宝、钉钉、腾讯系网站 | 打开速度正常，不绕远 | 确认当前模式不是全局代理 |

如果只有某一类网站异常，先换对应策略组里的节点；如果国内小站打开异常，先看是否被误判为代理流量；如果全部异常，再检查订阅是否过期、系统代理/TUN 是否打开。

如果代理页没有出现 `Claude / AI / Google / YouTube / Telegram / Exchange`，或者日志里提示规则集下载失败，请先确认 `Proxies` 里有可用节点，再打开 Clash Verge Rev 的日志查看具体失败项。远程规则集更新会显式通过 `Proxies` 下载，首次安装不再完全依赖直连 GitHub。

### 如何从备份还原

安装器自动生成的备份只保留最近 5 个，避免长期堆积；`backup_*_manual_*` 等手工备份不会被自动删除。如果安装中途失败，脚本会尽量用本次备份恢复到安装前状态；极端情况下仍可按下面方式手动还原：

1. 完全退出 Clash Verge Rev。
2. 打开安装脚本提示的 `backup_*` 目录。
3. 把备份目录 `profiles/` 里的文件复制回 Clash Verge Rev 数据目录里的 `profiles/`。
4. 把备份目录 `root/` 里的文件复制回 Clash Verge Rev 数据目录根目录。
5. 如果备份目录里的 `created-files.txt` 不是空的，删除其中逐行列出的文件；这些文件在安装前不存在，是本次安装新建的。
6. 重新打开 Clash Verge Rev。

安装脚本不会自动还原备份，避免误覆盖你安装后的新配置。

<!-- release-readme:pause -->

## 原理与维护

下面这些内容面向想了解它怎么工作、或想自行修改的人。

### 分流逻辑

| 类型 | 策略组 |
|---|---|
| Claude | `Claude` |
| 国际 AI 服务 | `AI` |
| 中国大陆 AI 服务 | `DIRECT` |
| Google 账号和 Google 生态 | `Google` |
| YouTube / YouTube Kids / 嵌入播放器 | `YouTube` |
| Telegram | `Telegram` |
| 交易所 | `Exchange` |
| 国内和局域网 | `DIRECT` |
| 明确海外代理 | `Proxies` |

代理页核心组按下面顺序显示：`Claude / AI / Google / YouTube / Telegram / Exchange / US / TW / SG / HK / JP / Proxies`。前 6 个是常用业务组，中间 5 个是地区节点池，最后 `Proxies` 是普通海外代理兜底。

`Claude`、`AI` 和 `Exchange` 会由 `Script.js` 自动生成，可选项为：

```text
Claude: US
AI: US / TW
Exchange: TW / SG
```

`Claude` 只保留美国地区组。`AI` 只保留美国和台湾地区组，不混用港区、日区、新加坡或普通代理兜底。目标地区节点全部缺失时该组只显示 `REJECT`（例如 `Exchange` 的 TW、SG 都没有时），表示不要登录或使用该类服务；只缺少其中一个地区时，组内保留其余地区节点。OpenAI、Gemini 这类高风险服务建议优先选 US。

DeepSeek、Kimi、豆包、通义、文心、腾讯元宝、智谱、MiniMax 等中国大陆 AI 不进入 `AI` 组，而是明确走 `DIRECT`。它们的账号、服务和合规环境更接近中国大陆产品，强行走 US / TW 反而容易触发错误地区判断。部分大陆 AI 使用 `.com`、`.ai`、`.chat` 域名，所以不能只看顶级域名来判断是否海外。

`Exchange` 只保留台湾和新加坡地区组，不混用美区、港区、日区或普通代理兜底。交易所域名规则由 `Script.js` 强制管理并提升到兜底层之前，用户订阅里的交易所规则会被统一替换，避免误配直连带来的合规风险。

如果订阅里没有这些固定组名，`Script.js` 会尽量自动识别常见节点和地区名称，并补齐缺失策略组。已有 `proxies` 这类大小写不同的同名组时，会复用原组名并自动改写规则目标。若节点本身恰好叫 `US`、`TW`、`Proxies` 等固定组名，自动策略组会改用 `US Group`、`TW Group`、`Proxies Group` 这类备用名，避免和节点同名形成循环。识别不到时会降级到 `Proxies` 或 `DIRECT`，优先保证配置能启动。

普通机场订阅通常会带很多自有策略组。对于节点直接写在 `proxies` 中、且不使用 `proxy-providers` 的普通订阅，安装后会隐藏没有被使用的杂乱原始组，只保留核心组；节点本身不会删除。如果规则、子规则、规则集下载、`dialer-proxy`、监听器、隧道或 NTP 仍引用自定义策略组，脚本会自动关闭界面压缩并保留全部原始组，避免产生悬空引用。只要订阅使用或混合使用 `proxy-providers`，脚本也会保守保留原始 provider 策略组。

订阅自带的 `REJECT` 规则和 `reject` rule-provider 会被保留，基础包自身不注入广告拦截规则。详细的规则与 DNS 路由说明见 [`docs/routing.md`](docs/routing.md)。

### 它做了什么

- 订阅节点：继续使用你自己的订阅，不带分享者的节点。
- 自动补策略组：如果订阅里缺少 `Claude / AI / US / Google / YouTube / Telegram / Exchange`，脚本会尽量自动补齐。
- 同步已有订阅：Clash Verge Rev 可能给每个订阅生成随机 merge/script 文件，安装脚本会一并写入，避免只改通用文件但当前订阅不生效。
- 按业务分流：AI、Google、YouTube、Telegram、交易所、国内网站分开走，减少互相影响。
- 压缩策略组界面：保留订阅节点，但隐藏订阅自带的杂乱策略组，只显示常用业务组；引用自定义组的场景自动关闭压缩，避免断配置。
- 不做系统级广告拦截：避免国内网站登录、风控、统计接口被误伤；去广告放到浏览器插件层。
- DNS 稳定解析：海外域名走海外 DNS，`.cn` 和直连流量优先走国内 DNS，避免新机器依赖额外 GEO 数据。
- 安装前自动备份：覆盖配置前先备份原文件，装错也能找回。

### 包含内容

仓库结构：

```text
macOS点我安装.command       # macOS 双击入口
Windows点我安装.bat         # Windows 双击入口

config/
  Merge.yaml                # 通用规则、rule-providers、DNS
  Script.js                 # 自动补组、规则改写、界面压缩
  dns_config.yaml           # DNS 解析策略
  verge.yaml                # Clash Verge Rev 基础设置

install/
  install-macos.command     # macOS 安装逻辑
  install-windows.bat       # Windows 入口
  install-windows.ps1       # Windows 安装逻辑
  sync-profile-bound-files.ps1  # 订阅绑定文件同步

scripts/
  check-sensitive.sh        # 敏感信息扫描
  build-release.command     # 构建 Release 包

tests/                      # 回归测试
```

Release zip 里只有安装所需文件：两个安装入口、`install-windows.ps1`、`sync-profile-bound-files.ps1`、`config/` 下四个配置，以及生成的 `README.txt`、`CHANGELOG.txt`、`VERSION.txt`。

<!-- release-readme:resume -->

## 让自己的 AI Agent 帮你安装

如果你不会操作，可以把下面这段发给自己的 AI Agent：

```text
请帮我安装这个 Clash Verge Rev 分享配置包。

要求：
1. 不要上传、复制、泄露我的订阅链接、节点、token 或账号信息。
2. 先确认我已经安装 Clash Verge Rev，并且已经导入自己的订阅。
3. 让我完全退出 Clash Verge Rev。
4. 解压下载的 zip。
5. macOS 运行 macOS点我安装.command；Windows 10/11 运行 Windows点我安装.bat。
6. 安装完成后重新打开 Clash Verge Rev，确认能正常代理。
7. 如果看到 Claude / AI / Google / YouTube / Telegram / Exchange 这些组，只需要按用途选择稳定节点。
```

<!-- release-readme:end -->

## 发布 Release 包

在项目目录运行：

```bash
./scripts/build-release.command            # 开发版（zip 带时间戳）
./scripts/build-release.command v0.3.XX    # 正式版（zip 带版本号，校验 VERSION.txt 与 CHANGELOG）
```

生成的 zip 会放在 `dist/`。发布前脚本会先跑完整门禁：Script.js 回归 + 真实 Mihomo 验证、安装器测试、敏感信息扫描、YAML 校验；ZIP 完成自检后再原子替换正式文件。GitHub 仓库已配置 Actions CI，push 后会在 Ubuntu / Windows / macOS 三平台自动重跑这些测试。

## 安全原则

不要提交这些内容到 GitHub：

- `profiles.yaml`
- 订阅链接
- 节点配置
- 私密备份包
- `server` / `password` / `uuid` / `token`
- 日志、缓存、数据库

## 免责声明

这套配置只解决 Clash Verge Rev 的分流和 DNS 路径问题。明确命中的海外服务走对应代理组，未命中的未知站点默认直连，减少国内 .com 小站被误送代理导致 502。AI 服务、交易所、流媒体平台可能有自己的账号风控和地区限制，使用者需要遵守对应平台规则。
