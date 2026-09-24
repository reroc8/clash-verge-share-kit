# 🛡️ Clash Verge Rev Share Kit

> 下载 → 解压 → 双击安装。常用网站自动走最合适的线路。

[![release](https://img.shields.io/github/v/release/reroc8/clash-verge-share-kit?color=2084ff&label=最新版本)](https://github.com/reroc8/clash-verge-share-kit/releases/latest)
[![test](https://img.shields.io/github/actions/workflow/status/reroc8/clash-verge-share-kit/test.yml?label=测试)](https://github.com/reroc8/clash-verge-share-kit/actions)

> ⚠️ 只提供配置模板和安装脚本，**不含任何订阅、节点、账号**。请先在 Clash Verge Rev 里导入自己的订阅。

<!-- release-readme:start -->

## 装完后是什么效果

| 你打开的网站 | 走的线路 |
|---|---|
| Claude / ChatGPT / Gemini / Copilot 等国际 AI | 🤖 `Claude` = US ｜ `AI` = US / TW |
| DeepSeek / Kimi / 豆包 / 通义 等大陆 AI | 🏠 直连 |
| Google / YouTube / Telegram | 🌐 各自独立分组 |
| OKX / Bybit / Binance 等交易所 | 💱 `Exchange`，锁定 TW · SG |
| 国内网站 · 局域网 | 🏠 直连 |
| 其他海外网站 | 🚀 `Proxies` |

分组互相隔离：AI 不和娱乐流量混出口，交易所永远固定地区，减少风控变量。

## 安装

1. **准备** — 安装 Clash Verge Rev，导入自己的订阅，确认能代理。**不用手动退出**：安装器会先帮你把还在运行的 Clash Verge Rev 关掉。
2. **下载** — 从 [Release](https://github.com/reroc8/clash-verge-share-kit/releases/latest) 下载最新 zip 并解压。
3. **安装** — 双击 `macOS点我安装.command`（Mac）或 `Windows点我安装.bat`（Win 10/11）。
4. **完成** — 重新打开 Clash Verge Rev，按下方「安装后 60 秒检查清单」核对。

安装前自动备份，不修改订阅和节点。自动备份只保留最近 **5 个**，手工备份不会被删。

若 Clash Verge Rev 开着「服务模式」，内核由管理员权限启动，安装器无权结束它——这不影响安装，装完重新打开 Clash Verge Rev 让新配置生效即可。

万一安装器提示关不掉（界面进程卡住，或内核是管理员权限启动的），双击包内的 `macOS关闭Clash.command`（Mac）/ `Windows关闭Clash.bat`（Windows）可以手动关掉它；Windows 上还可以右键该文件选「以管理员身份运行」，这样连管理员权限启动的内核也能结束。

## 备份还原

1. 完全退出 Clash Verge Rev。
2. 打开安装完成时提示的 `backup_*` 目录。
3. 把 `profiles/` 和 `root/` 里的文件复制回原位置。
4. 若 `created-files.txt` 非空，删除其中列出的文件。
5. 重新打开 Clash Verge Rev。

## 安装后 60 秒检查清单

重新打开后，按顺序核对：

1. 代理页能看到 `Claude / AI / Google / YouTube / Telegram / Exchange` 与 `US / TW / SG / HK / JP / Proxies` 这些策略组。
2. 打开 `claude.ai` 和 `chatgpt.com`，页面正常。
3. 打开 `youtube.com`，视频能播放。
4. 打开 `baidu.com`，国内网站直连正常。
5. 某个网站异常：先到对应策略组换一个节点；仍异常再看 Clash Verge Rev 日志。

更新内容见包内 `CHANGELOG.txt`。

<!-- release-readme:pause -->

## 原理

`Script.js` 在订阅之上做增强，不动节点：

- 补齐策略组并固定地区：`Claude` = US ｜ `AI` = US / TW ｜ `Exchange` = TW / SG。
- 大陆 AI 强制直连；钉钉全家桶（含会议子进程）进程级直连，防止内嵌海外 SDK 偷跑代理流量。
- 订阅自带 `REJECT` 规则保留；引用自定义组的规则、监听器、隧道自动识别，不误删。

详见 [`docs/routing.md`](docs/routing.md)。

## 项目结构

```text
config/    Merge.yaml · Script.js · verge.yaml · dns_config.yaml
install/   macOS · Windows 安装脚本与「关闭进程」脚本
scripts/   构建 · 敏感扫描 · 流量监控（clash-monitor.sh）
tests/     回归测试
docs/      路由设计文档
monitor/   clash-monitor.sh 输出的流量日志目录（不进 Release 包）
```

Release zip 只含安装所需文件。

<!-- release-readme:resume -->

> 🔒 这个仓库不包含任何订阅、节点或 token。所有配置模板和安装脚本均不含分享者账号信息。

<!-- release-readme:end -->

## 免责

只整理线路，不解决账号风控与地区限制。使用请遵守各平台规则。
