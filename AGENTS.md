# AGENTS.md — 所有 AI Agent 的工作守则

本仓库可能被多个 AI 工具（Claude Code、Cursor、Codex、WorkBuddy 等）操作。
动手前先读本文件——它是所有 agent 的共同约定，避免不同工具各行其是。
规则优先级：**用户当前指令 > 本文件 > 其他**。

## 事实来源

1. `CHANGELOG.md` / `docs/routing.md`：已发布的行为与设计决策。
2. 代码与测试（`config/` `install/` `tests/`）：**测试是行为的最终裁判**。
3. 重要决策不要只留在某个工具的私有记忆里——落进 git（代码注释、docs、CHANGELOG、测试断言）。

## 改动流程（必做）

1. 改完跑对应测试（在仓库根目录执行）：

   ```bash
   bash tests/test-installers.sh                              # 安装器与关闭脚本（仅 macOS）
   MIHOMO_BIN=<mihomo 路径> node tests/test-script.js         # Script.js + Merge.yaml（真实内核校验）
   pwsh -NoProfile -File tests/test-close-clash-windows.ps1   # Windows 关闭脚本（任意装有 pwsh 的平台）
   bash scripts/check-sensitive.sh                            # 提交前敏感扫描
   ```

   `MIHOMO_BIN` 可用任意 mihomo 二进制（macOS 本机通常可直接用 Clash Verge 内置内核）。

2. 新修复/新功能必须有测试覆盖，并做变异验证（故意破坏应导致测试失败），结论写进 commit 说明。
3. **收工纪律**：`git status` 干净、改动已提交。不要把半成品工作区留给下一个 agent。

## 发版流程（逐条执行；发版属对外可见动作，需仓库所有者明确确认）

```bash
git push origin main
bash scripts/build-release.command vX.Y.Z          # 跑全部门禁并打包到 dist/
git tag vX.Y.Z && git push origin vX.Y.Z           # 轻量 tag，逐个推送
gh release create vX.Y.Z dist/clash-verge-share-kit-vX.Y.Z.zip \
  --title vX.Y.Z --notes-file <说明文件> --verify-tag
```

发版前必须更新 `CHANGELOG.md` 与 `VERSION.txt`。先打 tag 再建 Release（不要用 `gh release create` 自动建 tag）。

## 红线

- **不要提交**凭据或个人环境文件：`.env`、订阅/节点信息、`profiles.yaml`、`.mcp.json`、`.reasonix/`、`reasonix.toml`、`.workbuddy/` 等——均已被 `.gitignore` 覆盖，不要强制 `add`。
- **不要擅自移除「个人规则」**：部分指向个人服务的规则是所有者确认保留的正式功能（例如 `wjkc.xyz → TW`、`mail.com → US`），移除前必须先询问。详见 `docs/routing.md`。
- **不要**在未获明确确认时做不可逆操作（删除、force push、重写历史）。
- 如果机器上存在本仓库的其他副本/快照：**以当前工作区（正在读本文件的那份检出）为准**，不要在旧副本上改动或发版。
- `install/` 下的 PowerShell 与 bat 文件保持**纯 ASCII**（Windows PowerShell 5.1 按 ANSI 解码无 BOM 的文件）。

## 本机生效须知（macOS + Clash Verge Rev）

- CVR 实际使用的是**订阅专属链文件**（`profiles.yaml` 中 `option.merge` / `option.script` 指向的 uid 文件），不是全局 `Merge.yaml`。改配置后需要全部覆盖同步并**重新激活订阅**才生效。
- 内核接口、数据目录约束等操作细节见项目记忆 `.workbuddy/memory/MEMORY.md`（若存在）与 `docs/routing.md`。
