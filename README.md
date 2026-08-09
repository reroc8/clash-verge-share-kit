# 🛡️ Clash Verge Rev Share Kit

> 下载、解压、双击安装。让所有常用网站自动走最合适的线路。

[![release](https://img.shields.io/github/v/release/reroc8/clash-verge-share-kit?color=2084ff&label=最新版本)](https://github.com/reroc8/clash-verge-share-kit/releases/latest)
[![test](https://github.com/reroc8/clash-verge-share-kit/actions/workflows/test.yml/badge.svg)](https://github.com/reroc8/clash-verge-share-kit/actions)

> ⚠️ 这个项目只提供配置模板和安装脚本，**不含任何订阅、节点、账号**。需先导入自己的订阅。

<!-- release-readme:start -->

## 装完后是什么效果

| 打开的网站 | 走的线路 |
|---|---|
| `Claude` / `ChatGPT` / `Gemini` / `Copilot` 等国际 AI | `Claude` · `AI` |
| DeepSeek / Kimi / 豆包 / 通义 等大陆 AI | 🏠 直连 |
| `Google` / `YouTube` / `Telegram` | 各自对应组 |
| `OKX` / `Bybit` / `Binance` 等交易所 | `Exchange`（TW · SG） |
| 国内网站 · 局域网 | 🏠 直连 |
| 其他海外网站 | `Proxies` |

## 安装

1. **准备** — 安装 Clash Verge Rev，导入自己的订阅，确认能代理后**完全退出**。
2. **下载** — 从 [Release](https://github.com/reroc8/clash-verge-share-kit/releases/latest) 下载最新 zip 并解压。
3. **安装** — 双击 `macOS点我安装.command`（Mac）或 `Windows点我安装.bat`（Win 10/11）。
4. **完成** — 重新打开 Clash Verge Rev，在代理页按用途选节点。

安装脚本会先备份再覆盖配置，不修改订阅和节点。自动备份只保留最近 **5 个**，手工备份不会被删。

## 备份还原

退出 Clash Verge Rev → 打开安装时提示的 `backup_*` 目录 → 把 `profiles/` 和 `root/` 的文件复制回原位置 → 若 `created-files.txt` 非空，删掉其中列出的文件 → 重新打开。

<!-- release-readme:pause -->

## 原理

`Script.js` 自动补齐策略组、改写规则、隐藏订阅自带杂乱组：

- `Claude` = US ｜ `AI` = US / TW ｜ `Exchange` = TW / SG
- 大陆 AI 强制直连
- 规则、监听器、隧道等引用自定义组时自动保留，不动节点
- 订阅自带 `REJECT` 规则保留

详细说明见 [`docs/routing.md`](docs/routing.md)。

## 项目结构

```
config/    Merge.yaml · Script.js · verge.yaml · dns_config.yaml
install/   macOS · Windows 安装脚本
scripts/   构建 + 敏感扫描
tests/     回归测试
```

Release zip 只含安装所需文件。

<!-- release-readme:resume -->

## 发布

```bash
./scripts/build-release.command              # 开发版
./scripts/build-release.command v0.3.XX      # 正式版
```

产物在 `dist/`。push 后仓库 CI 会在 Ubuntu / Windows / macOS 自动重跑全部门禁。

## 安全

不要提交到 GitHub：订阅链接 · 节点配置 · `server` / `password` / `uuid` / `token` · `profiles.yaml` · 日志缓存。

<!-- release-readme:end -->

## 免责

只整理线路，不解决账号风控与地区限制。使用请遵守各平台规则。
