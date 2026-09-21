# DeepSeek Harness Windows 安装说明

请按下面步骤操作，不需要提前安装 Node.js，也不要手动编辑 PATH。

## 1. 解压

把收到的压缩包完整解压到本地文件夹，例如：

```text
C:\DeepSeekHarnessDeployer
```

不要直接在压缩包内部运行文件。

电脑需要能够访问 npm 和 Node.js 官方下载服务。首次安装会下载依赖，可能需要几分钟。

## 2. 开始安装

打开解压后的：

```text
DeepSeekHarness-Windows-Validation-16c7948\windows
```

双击：

```text
install-windows.cmd
```

不要运行 `install-windows.ps1`。

安装器会自动检查 Node.js、npm、网络、DeepSeek Harness，并创建桌面快捷方式。正常情况下不需要管理员权限，也不需要输入命令。

如果电脑没有 D 盘，按照提示选择当前用户目录或其他有写入权限的位置即可。

## 3. 等待完成

安装器会依次显示 7 个 Stage。第一次运行时看到“首次会下载，请稍候”，请保持窗口打开，不要按 Ctrl+C，也不要重复打开安装器。

成功时应看到：

```text
Node.js:            PASS
npm / registry:     PASS
DeepSeek Harness:   PASS
Launcher:           PASS
Desktop Shortcut:   PASS
Web UI:             PASS
```

浏览器会自动打开 Harness Web UI，桌面会出现：

```text
DeepSeek Harness
```

## 4. 以后如何启动

安装完成后，直接双击桌面的：

```text
DeepSeek Harness
```

也可以运行安装目录中的：

```text
launcher\start-dsh.cmd
```

## 5. 配置模型/API

进入 Web UI 后，在：

```text
Settings → Models
```

中自行配置模型和 API。

不要把 API Key 输入到 CMD、PowerShell 或安装器中，也不要把带有 `token=` 的完整浏览器地址发到群聊或公开位置。

## 6. 如果安装失败

请记录安装器显示的：

```text
Error ID: DSH-Exxx
```

以及日志路径，例如：

```text
D:\DeepSeekHarness\logs\install-YYYYMMDD-HHMMSS.log
```

然后把以下信息发回来：

```text
Windows 版本：
是否有 D 盘：
Node 是否已安装：
Error ID：
日志路径：
```

不要发送 API Key、密码、Cookie、完整 token URL 或个人项目文件。
