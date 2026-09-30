# DeepSeek Harness Cross-Platform Deployer

为 Windows 和 macOS 提供 DeepSeek Harness 部署入口。仓库现包含**官方桌面版预览安装器**；原 Web UI 部署通道继续保留，两个入口目前分开，避免把旧 Web 的验证结果误当成桌面版验收。

> 桌面版当前从官方 feed 动态选择版本。2026-09-30 检查时官方稳定 feed 尚无版本，候选版本为 `0.2.0-rc.2`（预发布）。安装器会明确提示并要求确认；预发布版可能有缺陷，官方 App 后续自更新也可能继续提示候选版本。

## 官方桌面版预览：Windows

1. 下载并解压本仓库。
2. 双击 `windows/install-desktop-windows.cmd`。
3. 阅读预发布提示并确认；随后按官方 Windows 安装界面完成安装。
4. 安装成功后从桌面的 **DeepSeek Harness** 快捷方式启动。

目前只支持 Windows x64；ARM64 会明确停止，不会错误安装 x64 包。官方原生安装界面负责最终安装位置。

## 官方桌面版预览：macOS

1. 下载并解压本仓库。
2. 双击 `macos/install-desktop-macos.command`。如果 macOS 因下载隔离而拦截此未由本项目签名的脚本，在 Finder 中按住 Control 点击该文件并选“打开”；只对本文件作明确允许，不要关闭 Gatekeeper。
3. 如果系统提示没有执行权限，在 Terminal 进入解压目录后只运行：

   ```bash
   chmod u+x macos/install-desktop-macos.command macos/install-desktop-macos.sh
   ```

4. 阅读预发布提示并确认。安装完成后，可双击 `~/Applications/DeepSeek Harness.app` 或桌面的 **DeepSeek Harness Desktop.command**。

安装器自动选择 Apple Silicon 或 Intel 对应官方包，验证 SHA-512、Bundle ID、代码签名、Team ID 和 Gatekeeper。首次运行仍可能显示系统安全确认；本部署器不会清除 quarantine 或关闭系统安全设置。

## 重要：桌面版与旧 Web 版入口分开

桌面版尚未通过 Apple Silicon 和 Intel Mac 真机验收，所以原入口暂不切换：

- `windows/install-windows.cmd`、`macos/install-macos.command`：原 **Web UI + Node/npm** 部署器。
- `windows/install-desktop-windows.cmd`、`macos/install-desktop-macos.command`：新增 **官方原生桌面版预览**部署器。

请根据要测试的版本选择对应入口。桌面版的 Windows 冷安装和两种 Mac 架构真机验证仍是发布阻塞项。

macOS 安装器会自动识别 Intel（`x86_64`）或 Apple Silicon（`arm64`），优先复用兼容 Node；不兼容或缺少 Node 时，仅为本产品安装私有 Runtime，不修改系统 PATH。

## 原 Web UI 部署器做什么

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

以上 Node/npm、npx、3080 与 Token URL 说明只适用于**原 Web UI 通道**。桌面版由官方 App 管理其内置运行时，不使用本部署器的系统 Node、npm 或 3080 健康检查。

## API Key 与安全

安装器绝不要求在终端输入 API Key，也不会把 API Key、token、密码、Cookie 或聊天内容写入配置和日志。

无论使用 Web UI 还是桌面版，请在 Harness 应用内进入：

```text
Settings → Models
```

自行配置模型/API。部署器不会要求终端输入或保存 API Key。Harness 能够读取和修改项目文件并执行工具，请只选择确实需要授权的项目目录，不要默认授权整个磁盘。

## 日志、Repair、Uninstall

Windows 日志：`<安装目录>\logs\`

macOS Web 日志：`~/Library/Logs/DeepSeekHarness/`；桌面版日志：`~/Library/Logs/DeepSeekHarnessDesktopDeployer/`

日志包括 `install-YYYYMMDD-HHMMSS.log`、`runtime-YYYYMMDD-HHMMSS.log` 和诊断报告。发生失败时，优先提供终端显示的 `Error ID` 和对应日志路径。

Windows：

```powershell
powershell -ExecutionPolicy Bypass -File windows/repair-windows.ps1
powershell -ExecutionPolicy Bypass -File windows/uninstall-windows.ps1
powershell -ExecutionPolicy Bypass -File windows/repair-desktop-windows.ps1
powershell -ExecutionPolicy Bypass -File windows/uninstall-desktop-windows.ps1
```

macOS：

```bash
./macos/repair-macos.sh
./macos/uninstall-macos.sh
./macos/uninstall-macos.sh --purge --yes
./macos/repair-desktop-macos.sh
./macos/uninstall-desktop-macos.sh
```

原 Web 通道卸载默认保留 workspace 和日志；桌面版卸载使用官方应用卸载流程（Windows 系统“已安装的应用”设置，macOS 将已验证 App 移入废纸篓），不会删除应用用户数据、旧 Web runtime 或升级备份。系统已有 Node 永远不由 Web 卸载器删除。

## 当前验证状态

- 原 Web 通道：Windows regression PASS；macOS 静态检查 PASS（Windows 主机上的非 macOS WARN 保留）。
- 桌面预览通道：Windows PowerShell 5.1 自测、签名应用只读探测 PASS；冷安装未在开发机运行。macOS Bash 静态与 feed/版本自测 PASS，但未在 Mac 执行。
- Apple Silicon 与 Intel Mac：NOT TESTED。桌面版跨平台发布仍 BLOCKED，具体门槛见 [桌面版预览与验收说明](docs/DESKTOP.md)。

详细说明：

- [Windows 使用说明](docs/WINDOWS.md)
- [Windows 朋友简明安装说明](docs/WINDOWS_FRIEND_QUICK_START.md)
- [Windows 朋友简明安装说明 Word 文档](docs/WINDOWS_FRIEND_QUICK_START.docx)
- [Windows 普通用户安装操作方法](docs/WINDOWS_USER_SOP.md)
- [macOS 使用说明](docs/MACOS.md)
- [macOS 朋友简明安装说明](docs/MACOS_FRIEND_QUICK_START.md)
- [macOS 朋友简明安装说明 Word 文档](docs/MACOS_FRIEND_QUICK_START.docx)
- [故障排查](docs/TROUBLESHOOTING.md)
- [架构设计](docs/ARCHITECTURE.md)
- [官方桌面版预览与安装说明](docs/DESKTOP.md)
- [测试计划与证据](docs/test_plan.md)
- [风险登记册](docs/risk_register.md)
