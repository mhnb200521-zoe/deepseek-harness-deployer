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

如果 macOS 第一次阻止打开，看到“未打开 install-macos.command”“Apple 无法验证”或类似提示，这是 Gatekeeper 对未做 Apple 开发者签名的脚本进行的首次确认。不要点击“移到废纸篓”，按下面操作：

1. 在 Finder 中右键 `install-macos.command`。
2. 选择“打开”，再在系统提示中选择“打开”。
3. 如果右键“打开”后仍被拦截，打开“系统设置 → 隐私与安全性”，在“安全性”区域找到关于 `install-macos.command` 的提示，点击“仍要打开”，按系统要求确认。

如果提示“文件无法执行，因为你没有正确的访问权限”，说明解压或微信传输时没有保留脚本的执行权限。请在 Terminal 中执行一次下面两行命令（假设解压目录在“下载”中）：

```bash
cd ~/Downloads/DeepSeekHarness-macOS-Validation-M5
chmod u+x macos/*.command macos/*.sh
```

如果你的解压目录不在“下载”中，先输入 `cd `，再把解压后的 `DeepSeekHarness-macOS-Validation-M5` 文件夹拖入 Terminal，按回车，然后执行第二行 `chmod` 命令。执行完成后，回到 Finder 再次双击 `macos/install-macos.command`，必要时重复一次“右键 → 打开”。

这只是给本项目文件补回执行权限，不会关闭 Gatekeeper，也不需要管理员密码。不要关闭 Gatekeeper、系统安全软件或防火墙。

如果收到的压缩包不是从可信来源获得，先不要运行；可以在 Terminal 中核对安装包 SHA256：

```bash
shasum -a 256 ~/Downloads/DeepSeekHarness-macOS-Validation-M5.tar.gz
```

应与发送者提供的校验值一致。

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
