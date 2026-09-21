# DeepSeek Harness Windows 用户安装操作方法

本文适用于 Windows 10 / Windows 11 的普通用户。安装器会自动检测系统架构、Node.js、npm、npm registry 和 DeepSeek Harness，并创建桌面快捷方式。

## 一、安装前准备

请确认：

- 使用 64 位 Windows；x64 为主要验证路径，ARM64 会自动识别并按安装器提示处理。
- 当前网络可以访问 `registry.npmjs.org`。
- 如果电脑有 D 盘，默认安装位置为 `D:\DeepSeekHarness`；没有 D 盘时安装器会提示选择其他位置。
- 不需要提前安装 Homebrew 或手动配置 PATH。
- 不要在安装器窗口中输入 API Key、密码或其他密钥。

安装器不会卸载、覆盖或修改已有的兼容 Node.js，也不会修改 Windows Defender、防火墙规则或整个磁盘的访问权限。

## 二、安装步骤

1. 解压部署包到一个普通文件夹。
2. 双击：

   `windows\install-windows.cmd`

3. 等待安装器依次执行以下 Stage：

   - Stage 1/7：System Check
   - Stage 2/7：Node.js
   - Stage 3/7：npm
   - Stage 4/7：Harness 首次准备
   - Stage 5/7：Launcher
   - Stage 6/7：Shortcut
   - Stage 7/7：Verification

4. 首次准备 DSH npm 依赖时可能需要几分钟。看到“首次会下载，请稍候”后，请保持窗口打开，不要按 Ctrl+C，也不要重复启动多个安装器窗口。
5. 安装完成时，应看到：

   ```text
   Installation Complete
   Node.js: PASS
   npm / registry: PASS
   DeepSeek Harness: PASS
   Launcher: PASS
   Desktop Shortcut: PASS
   Web UI: PASS
   ```

6. 安装器会尝试自动打开浏览器。浏览器打开的是安装器从 Harness 实际启动输出中捕获的 URL；如果 URL 含 token，token 会保留用于本次 Web UI 访问，但不会写入安装日志或配置文件。

整个安装过程原则上不需要用户输入 Y、路径、命令或 API Key，也不需要管理员权限。窗口最后的“Press any key to continue”只用于关闭安装器窗口。

## 三、安装完成后如何启动

安装成功后有两种启动方式：

### 方式 A：桌面快捷方式

双击桌面上的：

`DeepSeek Harness`

快捷方式实际指向部署器生成的 `start-dsh.cmd`，不会绑定某个固定的 Node 绝对路径。

### 方式 B：安装目录中的启动器

双击：

`D:\DeepSeekHarness\launcher\start-dsh.cmd`

如果实际安装目录不是 D 盘，请使用安装器最后输出的安装路径。

启动器会设置本项目运行环境、使用默认 workspace、启动 Harness、记录运行日志并尝试打开 Web UI。

## 四、第一次进入 Web UI 后的操作

安装器不会要求输入或保存 DeepSeek API Key。进入 Harness Web UI 后，请按以下位置自行配置：

```text
Settings → Models
```

API Key 只应在 Harness 提供的配置界面中按其安全提示配置。不要把 API Key 粘贴到命令行，也不要把它写入安装日志、截图、工单或聊天记录。

默认 workspace 是一个空目录：

`D:\DeepSeekHarness\workspace`

进入 Web UI 后，请通过 Harness 的 workspace 选择功能，选择真正需要操作的项目目录。不要把 `C:\`、`D:\` 或整个用户目录作为 workspace，除非你明确理解其文件读取、文件修改和 shell 工具权限风险。

## 五、安装目录和日志

默认目录结构如下：

```text
D:\DeepSeekHarness\
├─ runtime\
├─ launcher\
├─ workspace\
├─ cache\
├─ logs\
└─ config\
```

安装日志：

`D:\DeepSeekHarness\logs\install-YYYYMMDD-HHMMSS.log`

运行日志：

`D:\DeepSeekHarness\logs\runtime-YYYYMMDD-HHMMSS.log`

日志用于诊断 Node、npm、registry、DSH 版本和启动状态。日志只应记录错误摘要、版本和 URL 来源/token 是否存在，不应包含完整 token、API Key、密码、Cookie 或聊天内容。

## 六、常见情况处理

### 1. 安装器提示没有 D: 盘

这是正常分支，不要创建虚拟 D 盘。按提示选择：

- 当前用户目录；或
- 输入一个你有写入权限的安装位置。

### 2. 发现已有兼容 Node.js

看到类似以下提示即可继续：

```text
[PASS] 检测到兼容 Node.js: v24.x.x（复用，不修改）
```

安装器不会覆盖该 Node。Node 22 只有在满足 `>=22.19.0` 且小于 23 时兼容；Node 24 及更高版本兼容，Node 23 不作为兼容版本。

### 3. 首次准备时间较长

Stage 4 会使用部署器自己的 `cache` 目录准备官方 npm 包和依赖。首次下载可能明显慢于后续启动，请保持窗口打开并等待。后续重复运行会复用已完成的 cache。

### 4. npm registry 不可达

请先更换网络，或确认公司/校园网代理允许 HTTPS 访问 npm registry。不要关闭 Defender 或防火墙来解决此问题。完整技术错误会写入安装日志。

### 5. 端口 3080 已被其他程序占用

安装器不会强制结束未知进程，也不会修改防火墙。关闭占用 3080 的非 Harness 程序后重试；如果 3080 已经是 Harness，安装器会尝试复用并打开页面。

### 6. 安装失败

请记录安装器显示的 Error ID 和日志路径，只把下面两项发给技术支持：

```text
Error ID: DSH-Exxx
Log: D:\DeepSeekHarness\logs\install-YYYYMMDD-HHMMSS.log
```

不要直接发送包含个人项目内容的 workspace，也不要发送 API Key、Cookie、完整 token 或聊天记录。

常见 Error ID：

| Error ID | 含义 |
| --- | --- |
| DSH-E001 | Node 下载、解压或私有 runtime 准备失败 |
| DSH-E002 | Node SHA256 校验失败 |
| DSH-E003 | npm 不可用 |
| DSH-E004 | npm registry 或 DSH 包不可达 |
| DSH-E006 | Harness 启动或实际 Web URL 验证失败 |
| DSH-E007 | 3080 端口冲突或已有服务不是 Harness |
| DSH-E008 | 桌面快捷方式创建失败 |
| DSH-E009 | 不支持的 32 位系统 |
| DSH-E010 | 安装目录或启动器写入权限问题 |
| DSH-E999 | 未预期错误；请同时提供日志路径 |

## 七、Repair 和卸载

高级用户或技术支持可以在部署包目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\repair-windows.ps1
```

Repair 会检查 Node、npm、npx、npm registry、DSH 包、启动器、快捷方式和 3080 端口，并生成诊断结果。

卸载时运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\uninstall-windows.ps1
```

卸载器只处理本部署器创建的内容，不会删除用户原有的系统 Node。workspace 和 logs 默认保留或询问后处理；如需彻底删除，请先备份自己的项目文件和日志。

## 八、本 SOP 的实际验证记录

本 SOP 已在以下环境按 `install-windows.cmd` 用户入口实际验证：

- Windows 11 Home China x64
- 已有兼容系统 Node：`v24.19.0`
- npm：`11.17.0`
- D: 盘存在
- 初始 3080 端口空闲
- DSH：`0.1.5-rc.2`
- 安装目录：`D:\DeepSeekHarness`
- S1–S7：PASS
- Web UI：HTTP 200
- URL 来源：detected
- token 保留：YES（仅内存传递，日志只记录存在性）
- 桌面快捷方式：PASS，目标为 `D:\DeepSeekHarness\launcher\start-dsh.cmd`

这是一台已有兼容 Node 的 Windows 验证机记录，不等同于所有网络环境下的无 Node 全新虚拟机验收。首次 DSH 依赖准备的耗时取决于网络和 npm registry 响应速度。
