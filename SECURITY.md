# Security

这个项目只应包含公开配置模板和安装脚本。

不要提交：

- `profiles.yaml`
- 订阅链接
- 节点配置
- `server` / `password` / `uuid` / `token`
- 私密备份包
- 日志、缓存、数据库文件

发布前请运行：

```bash
./scripts/check-sensitive.sh
```

如果扫描失败，不要发布 Release，也不要推送到 GitHub。
