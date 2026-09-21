# Changelog

## Unreleased

### M2 — Windows Productization

- 完成 Windows 桌面快捷方式生成，快捷方式目标保持为部署器生成的 `start-dsh.cmd`。
- 完成 Windows Repair 诊断报告，覆盖 Node/npm/npx、registry、DSH、launcher、shortcut 与端口。
- 完成 Windows Uninstall：
  - 只停止并删除本安装目录拥有的 Harness 进程与文件；
  - 不删除用户已有的系统 Node；
  - 默认保留 workspace 与 logs；
  - `-Purge` 可彻底删除部署目录；
  - 遇到无法删除的文件返回失败状态，便于售后处理。
- 完成日志轮转，安装器保留最近的 install/runtime 日志。
- 完成 DSH Token URL 处理：从实际 stdout 提取 URL，保留 query/token，在内存中验证并打开同一 URL，日志只记录脱敏信息。
- 增加 `windows/start-dsh.cmd` 交付包启动模板。

### M3 — macOS MVP

- 增加 `macos/install-macos.command` 与 `macos/install-macos.sh`，支持 Intel/Apple Silicon 架构检测、兼容 Node 复用、官方 Node 私有 Runtime 下载与 SHA256 校验、npm registry 预检和锁定 DSH 版本。
- 增加 macOS `start-dsh.command`：使用独立 workspace，捕获实际 Web URL，保留 query/token，S7 验证同一 URL；无新输出时明确记录 `source=fallback`。
- 补齐 macOS 7-Stage 输出中的 Stage 6 配置/Workspace 阶段，配置文件不保存 API Key、token 或用户聊天内容。
- 增加 `tests/macos-check.sh`；在 Windows 宿主上完成 Bash 语法与文件契约检查，macOS 真机验证留待 M5。
### M4 — macOS Productization

- 完成 macOS Repair 诊断：检查 Node/npm/npx、npm registry、DSH、launcher、用户可见启动方式、端口和最近 Web 验证日志，并生成脱敏 Diagnostic Report。
- 完成 macOS Uninstall：只停止当前安装根目录拥有的 Harness 进程树；默认删除私有 Runtime、launcher、cache、config 和本产品启动链接，保留 workspace/logs；`--purge --yes` 才删除 workspace/logs。
- macOS 启动器支持从用户可见符号链接解析真实安装路径，避免双击 `~/DeepSeekHarness/DeepSeek Harness.command` 时定位错误。
- 当前宿主为 Windows，macOS 真机网络、端口、浏览器、进程树和 purge 行为留待 M5。

### M6 — Documentation

- 增加普通用户第一屏 `README.md`，覆盖 Windows/macOS 启动路径、Node 策略、安全边界、日志、Repair、Uninstall 和当前验证状态。
- 增加 `docs/WINDOWS.md`、`docs/MACOS.md`、`docs/TROUBLESHOOTING.md` 与 `LICENSE`，并同步当前 Error ID、Token URL、缓存隔离和卸载保护行为。

### Known limitations

- 已运行的 Harness 若没有新的启动输出，启动器无法安全恢复旧 token，会明确使用 fallback 并标记 `source=fallback`。
- macOS MVP 已完成静态实现；当前宿主为 Windows，macOS 真机 Node/npx/端口/浏览器链路仍待 M5。
