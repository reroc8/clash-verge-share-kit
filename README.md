# Clash Verge Rev Share Kit

给小白用的 Clash Verge Rev 分流配置包：下载、解压、双击安装，AI、Google、YouTube、Telegram、交易所、国内网站自动各走各的。**不含任何订阅、节点、账号**，需先导入自己的订阅。

<!-- release-readme:start -->

## 装完后是什么效果

| 打开的网站 | 走的线路 |
|---|---|
| Claude / ChatGPT / Gemini 等 | `Claude` / `AI` 组 |
| 中国大陆 AI（DeepSeek、Kimi、豆包等） | 直连 |
| Google / YouTube / Telegram | 各自对应组 |
| 交易所（OKX / Bybit / Binance 等） | `Exchange` 组（TW / SG） |
| 国内网站、局域网 | 直连 |
| 其他海外网站 | `Proxies` |

## 安装

1. 安装 Clash Verge Rev，导入自己的订阅，确认能代理后**完全退出**。
2. 下载 Release 里的 zip 并解压。
3. 双击 `macOS点我安装.command`（macOS）或 `Windows点我安装.bat`（Windows 10/11）。
4. 重新打开 Clash Verge Rev，在代理页按用途选节点。

安装脚本会先备份再覆盖配置，不修改你的订阅和节点。装完检查：Claude、Google、YouTube、交易所能否正常打开；哪一类异常就换对应组的节点。

## 备份还原

自动备份只保留最近 5 个（`backup_*_manual_*` 手工备份不删）。还原：完全退出 Clash Verge Rev → 把安装脚本提示的 `backup_*` 目录里 `profiles/` 和 `root/` 的文件复制回原位置 → 若 `created-files.txt` 非空，删除其中列出的文件 → 重新打开。

<!-- release-readme:pause -->

## 原理（简述）

`Script.js` 自动补策略组、改写规则、隐藏订阅自带杂乱组；规则、子规则、`dialer-proxy`、监听器、隧道、NTP 仍引用自定义组时自动关闭压缩，避免悬空配置。`Claude`=US，`AI`=US/TW，`Exchange`=TW/SG；目标地区节点全缺时该组显示 `REJECT`。中国大陆 AI 强制直连。订阅自带的 `REJECT` 规则保留。详细见 [`docs/routing.md`](docs/routing.md)。

## 包含内容

仓库：`config/`（四个配置模板）、`install/`（安装脚本）、`scripts/`（构建与敏感扫描）、`tests/`（回归测试）。Release zip 只含安装所需文件。

<!-- release-readme:resume -->

## 发布与安全

发布：`./scripts/build-release.command`（开发版）或 `./scripts/build-release.command v0.3.XX`（正式版），产物在 `dist/`；push 后 GitHub Actions 会在 Ubuntu / Windows / macOS 三平台自动跑测试。

不要提交到 GitHub：订阅链接、节点配置、`server` / `password` / `uuid` / `token`、`profiles.yaml`、日志缓存。

<!-- release-readme:end -->

## 免责声明

只整理线路，不解决账号风控与地区限制，请遵守各平台规则。
