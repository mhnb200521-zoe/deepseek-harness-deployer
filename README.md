# DeepSeek Harness Cross-Platform Deployer

面向普通用户的 DeepSeek Harness（`@deepseek-ai/dsh`）Windows + macOS 部署工具。

## Windows：三步开始

1. 下载并解压整个项目目录。
2. 双击 `windows/install-windows.cmd`，等待检测、Node/npm 准备、Harness 启动和 Web UI 验证完成。
3. 安装完成后，双击桌面的 `DeepSeek Harness`。

如果机器没有 `D:` 盘，安装器会让你选择当前用户目录、其他路径或退出，不会创建虚拟磁盘、不改分区。

## macOS：三步开始

1. 下载并解压整个项目目录。
2. 首次运行前，在 Terminal 执行：

   ```bash
   chmod +x macos/install-macos.command macos/install-macos.sh
   ```

   然后双击 `macos/install-macos.command`；如果 Gatekeeper 提示阻止，请在 Finder 中右键选择“打开”，确认后再运行。

3. 安装完成后，双击 `~/DeepSeekHarness/DeepSeek Harness.command`。

macOS 安装器会自动识别 Intel（`x86_64`）或 Apple Silicon（`arm64`），优先复用兼容 Node；不兼容或缺少 Node 时，仅为本产品安装私有 Runtime，不修改系统 PATH。

## 安装器做什么

- 检测 OS、CPU 架构、Node.js 和 npm/npx。
- 兼容基线为 `^22.19.0 OR >=24.0.0`；兼容 Node 直接复用，不覆盖。
- 缺少兼容 Node 时，只从官方 `nodejs.org` 获取 Node，并校验 SHA256。
- 通过 npm registry 检查 `@deepseek-ai/dsh`，使用锁定的 DSH 版本运行：

  ```text
  npx --yes @deepseek-ai/dsh@<pinned> web --no-open
  ```

- 优先从 Harness 实际输出捕获 Web URL，保留 path/query/token，并用同一个 URL 验证和打开浏览器。
- 只有无法获取新 URL 时才使用明确标记的 `source=fallback`；fallback 不会伪造 token。
- 默认 workspace 是专用目录，不会把整个磁盘授权给 Harness。

## API Key 与安全

安装器绝不要求在终端输入 API Key，也不会把 API Key、token、密码、Cookie 或聊天内容写入配置和日志。

安装完成后，请在 Harness Web UI 中进入：

```text
Settings → Models
```

自行配置模型/API。Harness 能够读取和修改 workspace 文件并执行工具，请只在 Web UI 中选择确实需要授权的项目目录。

## 日志、Repair、Uninstall

Windows 日志：`<安装目录>\logs\`

macOS 日志：`~/Library/Logs/DeepSeekHarness/`

日志包括 `install-YYYYMMDD-HHMMSS.log`、`runtime-YYYYMMDD-HHMMSS.log` 和诊断报告。发生失败时，优先提供终端显示的 `Error ID` 和对应日志路径。

Windows：

```powershell
powershell -ExecutionPolicy Bypass -File windows/repair-windows.ps1
powershell -ExecutionPolicy Bypass -File windows/uninstall-windows.ps1
```

macOS：

```bash
./macos/repair-macos.sh
./macos/uninstall-macos.sh
./macos/uninstall-macos.sh --purge --yes
```

默认卸载保留 workspace 和日志；`--purge --yes` 才会删除它们。系统已有 Node 永远不由卸载器删除。

## 当前验证状态

- Windows 11 x64：Node 兼容判定、npm/registry、Harness 启动、Token URL、快捷方式、Repair、Uninstall 已有实测证据。
- macOS：安装器、启动器、Repair、Uninstall 已完成 Bash 语法和静态契约检查；Intel/Apple Silicon 真机网络、端口、浏览器、进程树与完整卸载矩阵需在 Mac 上执行 M5 验收。

详细说明：

- [Windows 使用说明](docs/WINDOWS.md)
- [Windows 普通用户安装操作方法](docs/WINDOWS_USER_SOP.md)
- [macOS 使用说明](docs/MACOS.md)
- [故障排查](docs/TROUBLESHOOTING.md)
- [架构设计](docs/ARCHITECTURE.md)
- [测试计划与证据](docs/test_plan.md)
- [风险登记册](docs/risk_register.md)
