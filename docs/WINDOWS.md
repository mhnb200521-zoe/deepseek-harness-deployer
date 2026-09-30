# Windows 使用与维护

## 官方桌面版预览入口

若你要安装 **DeepSeek Harness 原生桌面 App**，请运行 `windows/install-desktop-windows.cmd`，不要运行下方旧 Web UI 入口 `windows/install-windows.cmd`。桌面版当前为预览部署；版本选择、签名校验、快捷方式、修复/卸载与未完成验收见 [DESKTOP.md](DESKTOP.md)。Windows ARM64 目前不支持。

## 普通用户安装

以下步骤描述的是旧 **Web UI + Node/npm** 部署通道。

支持 Windows 10/11，x64 为主要验证目标。双击：

```text
windows/install-windows.cmd
```

入口文件只负责启动 PowerShell 编排器；业务逻辑位于 `windows/install-windows.ps1`。

安装器按以下阶段工作：

```text
Stage 1/7  System Check
Stage 2/7  Node.js
Stage 3/7  npm
Stage 4/7  Harness
Stage 5/7  Launcher
Stage 6/7  Shortcut
Stage 7/7  Verification
```

默认安装到 `D:\DeepSeekHarness`。没有 `D:` 时会让用户选择回退目录或退出，不会创建虚拟磁盘或修改分区。

## Node 策略

兼容集合是：

```text
22.19.0 及以上的 Node 22
或 24.0.0 及以上
```

兼容的已有 Node 只会被复用。旧 Node、缺少 Node 或缺少 npm 时，安装器从 `https://nodejs.org/dist/` 选择兼容 LTS，下载后核对官方 `SHASUMS256.txt`，放入本产品的 `runtime\node`。不会修改系统 PATH，也不会删除用户已有 Node。

## 启动与 URL 验证

桌面快捷方式的目标是本产品生成的 `launcher\start-dsh.cmd`，不是某个固定的 Node 绝对路径。

启动器会：

1. 使用安装时锁定的 `@deepseek-ai/dsh` 版本。
2. 以 `workspace` 作为工作目录。
3. 捕获 Harness 实际输出中的 localhost URL。
4. 保留 query/token，并用实际 URL完成验证和浏览器打开。
5. 仅在没有新输出时使用显式 `source=fallback`，不杀死其他程序。

如果 3080 被其他程序占用，安装器不会盲目终止进程，而是报告 `DSH-E007` 并建议关闭占用程序或按诊断报告处理。

## Repair

```powershell
powershell -ExecutionPolicy Bypass -File windows/repair-windows.ps1
```

Repair 检查 Node/npm/npx、npm registry、DSH、launcher、桌面快捷方式和端口，并在安装目录 `logs` 中生成 `diagnostic-*.txt`。

## Uninstall

默认：

```powershell
powershell -ExecutionPolicy Bypass -File windows/uninstall-windows.ps1
```

默认删除本产品的私有 Runtime、launcher、cache、config 和快捷方式，保留 workspace/logs。彻底删除用户数据前明确使用：

```powershell
powershell -ExecutionPolicy Bypass -File windows/uninstall-windows.ps1 -Purge -Yes
```

卸载器只停止命令行明确属于当前安装根目录的 Harness 进程，不按 `node.exe` 名称或端口盲杀；系统已有 Node 不会删除。

## 日志位置

```text
<InstallRoot>\logs\install-YYYYMMDD-HHMMSS.log
<InstallRoot>\logs\runtime-YYYYMMDD-HHMMSS.log
<InstallRoot>\logs\diagnostic-YYYYMMDD-HHMMSS.txt
```

日志只记录版本、阶段、来源和错误信息。Token 只以“是否存在”表示，不记录完整值。
