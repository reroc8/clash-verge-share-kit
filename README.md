# Clash Verge Rev Share Kit

面向小白用户的 Clash Verge Rev 稳定分流配置包。

这个项目只提供配置模板和安装脚本，**不包含任何订阅、节点、账号、密码或 token**。使用者必须先导入自己的订阅。

## 适合谁

- 想要一套稳定分流规则，但不想自己写规则的人。
- 主要需要 AI、Google、YouTube、Telegram、交易所和国内服务合理分流的人。
- 已经有自己的 Clash Verge Rev 订阅，但不懂怎么优化配置的人。

## 不适合谁

- 想迁移别人订阅或节点的人。
- 想用它绕过交易所地区限制的人。

## 包含内容

```text
config/
  Merge.yaml
  Script.js
  dns_config.yaml
  verge.yaml

install/
  install-macos.command
  install-windows.bat

scripts/
  check-sensitive.sh
  build-release.command
```

## 分流逻辑

| 类型 | 策略组 |
|---|---|
| 高风险 AI | `US` |
| Google 账号和 Google 生态 | `Google` |
| YouTube | `YouTube` |
| Telegram | `Telegram` |
| 交易所 | `Exchange` |
| 国内和局域网 | `DIRECT` |
| 兜底代理 | `Proxies` |

`Exchange` 会由 `Script.js` 自动生成，可选项为：

```text
Proxies / JP / HK / SG / TW / US / DIRECT
```

如果订阅里没有这些固定组名，`Script.js` 会尽量自动识别常见节点和地区名称，并补齐缺失策略组。识别不到时会降级到 `Proxies` 或 `DIRECT`，优先保证配置能启动。

## 安装前

1. 安装 Clash Verge Rev。
2. 导入自己的订阅。
3. 打开 Clash Verge Rev，并确认能正常代理。
4. 完全退出 Clash Verge Rev。

## 安装方式

最简单方法：

1. 下载 Release 里的 zip。
2. 解压 zip。
3. 完全退出 Clash Verge Rev。
4. 按系统双击安装脚本。

macOS 双击：

```text
install-macos.command
```

Windows 10/11 双击：

```text
install-windows.bat
```

安装脚本会先备份原文件，然后覆盖：

```text
profiles/Merge.yaml
profiles/Script.js
verge.yaml
dns_config.yaml
```

安装脚本不会修改订阅和节点。

## 让自己的 AI Agent 帮你安装

如果你不会操作，可以把下面这段发给自己的 AI Agent：

```text
请帮我安装这个 Clash Verge Rev 分享配置包。

要求：
1. 不要上传、复制、泄露我的订阅链接、节点、token 或账号信息。
2. 先确认我已经安装 Clash Verge Rev，并且已经导入自己的订阅。
3. 让我完全退出 Clash Verge Rev。
4. 解压下载的 zip。
5. macOS 运行 install-macos.command；Windows 10/11 运行 install-windows.bat。
6. 安装完成后重新打开 Clash Verge Rev，确认能正常代理。
7. 如果看到 US / Google / YouTube / Exchange 这些组，只需要按用途选择稳定节点。
```

## 发布 Release 包

在项目目录运行：

```bash
./scripts/build-release.command
```

生成的 zip 会放在：

```text
dist/
```

发布前脚本会先做敏感信息扫描。

## 安全原则

不要提交这些内容到 GitHub：

- `profiles.yaml`
- 订阅链接
- 节点配置
- 私密备份包
- `server` / `password` / `uuid` / `token`
- 日志、缓存、数据库

## 免责声明

这套配置只解决 Clash Verge Rev 的分流和 DNS 路径问题。AI 服务、交易所、流媒体平台可能有自己的账号风控和地区限制，使用者需要遵守对应平台规则。
