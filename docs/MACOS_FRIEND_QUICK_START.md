# DeepSeek Harness macOS 安装说明

请按下面步骤操作，不需要提前安装 Homebrew 或 Node.js。安装器会自动识别 Intel Mac 或 Apple Silicon，并只为本产品准备需要的 Node Runtime。

## 1. 解压安装包

收到的 macOS 安装包是：

```text
DeepSeekHarness-macOS-Validation-M5.tar.gz
```

双击压缩包，使用 macOS 自带的“归档实用工具”解压到“下载”目录或其他本地文件夹。

不要直接在压缩包内部运行文件，也不要把整个磁盘设置为 Harness workspace。

## 2. 首次运行安装器

打开解压后的目录，双击：

```text
macos/install-macos.command
```

如果 macOS 第一次阻止打开：

1. 在 Finder 中右键 `install-macos.command`。
2. 选择“打开”。
3. 在系统提示中再次选择“打开”。

如果提示没有执行权限，在 Terminal 中进入解压目录后执行一次：

```bash
chmod +x macos/install-macos.command macos/install-macos.sh
```

然后再次双击 `install-macos.command`。

不要关闭 Gatekeeper，也不要为了安装本工具关闭系统安全软件。

## 3. 等待安装完成

安装器会自动识别：

```text
Intel Mac       x86_64
Apple Silicon   arm64
```

不需要手动选择架构。安装器会依次显示 7 个阶段：

```text
Stage 1/7  System Check
Stage 2/7  Node.js
Stage 3/7  npm
Stage 4/7  Harness（S0 能力探测）
Stage 5/7  Launcher
Stage 6/7  Configuration, Workspace and Shortcut
Stage 7/7  Verification
```

第一次运行会访问官方 Node.js 和 npm 软件源，可能需要几分钟。请保持窗口打开，不要按 Ctrl+C，也不要重复启动安装器。

## 4. 确认安装成功

正常情况下应看到以下结果：

```text
Node.js:            PASS
npm / registry:     PASS
DeepSeek Harness:   PASS
Launcher:           PASS
Web UI:             PASS
```

浏览器会自动打开 Harness Web UI。用户可双击启动方式位于：

```text
~/DeepSeekHarness/DeepSeek Harness.command
```

默认 workspace 位于：

```text
~/DeepSeekHarness/workspace
```

## 5. 以后如何启动

安装完成后，直接双击：

```text
~/DeepSeekHarness/DeepSeek Harness.command
```

启动过程中请等待浏览器打开，不要提前关闭启动窗口，否则 Harness 进程可能会停止。

## 6. 配置模型和 API

进入 Harness Web UI 后，在下面的位置自行配置模型和 API：

```text
Settings → Models
```

安装器不会要求你输入 API Key。请不要把 API Key 输入 Terminal 或安装器中，也不要把包含 `token=` 的完整浏览器地址发到群聊、截图或公开位置。

## 7. 如果安装失败

请先记录终端中显示的：

```text
Error ID: DSH-Exxx
```

日志目录为：

```text
~/Library/Logs/DeepSeekHarness/
```

反馈时请提供：

```text
macOS 版本：
Mac 类型：Intel 或 Apple Silicon
Error ID：
发生在 Stage 几：
日志路径：
```

不要发送 API Key、密码、Cookie、完整 token URL 或个人项目文件。

## 8. Repair 和卸载

Repair 只做诊断，不删除已有 Node 或 workspace：

```bash
./macos/repair-macos.sh
```

默认卸载会保留 workspace 和日志：

```bash
./macos/uninstall-macos.sh
```

只有确认不再需要用户数据时，才使用彻底删除：

```bash
./macos/uninstall-macos.sh --purge --yes
```
