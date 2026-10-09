# DeepSeek Harness 官方桌面版预览

本说明适用于仓库新增的**原生桌面版**入口；旧 Web UI 入口仍然独立保留。桌面版官方客户端自带运行时，不依赖本项目的 Node/npm、npx、3080 端口或 Web Token URL。

## 当前版本状态

部署器每次从 DeepSeek 官方版本 feed 读取版本、下载地址、文件大小和 SHA-512，不把某个 RC 版本永久写死。2026-09-30 核验时，稳定版 feed 返回 HTTP 404，官方 nightly feed 指向 `0.2.0-rc.2`，并且 GitHub Releases 将其标记为预发布版。首次安装因此会明确显示“候选/预发布版本”，必须由本机用户确认；取消不会安装。

安装器只在稳定版 feed **精确返回 404** 时尝试候选版。网络失败、超时、其他 HTTP 状态、非法元数据均直接报错，不会改用非官方地址。用户确认只代表允许本次部署；官方 App 的自动更新策略由官方客户端管理，未来仍可能收到预发布更新。

官方来源：

- [DeepSeek Harness 官方桌面版说明](https://github.com/deepseek-ai/deepseek-harness/blob/master/apps/desktop/README.md)
- [官方发布页](https://github.com/deepseek-ai/deepseek-harness/releases)
- 官方下载域名：`https://download.deepseek.com`

## Windows 安装

1. 下载并解压仓库。
2. 双击 `windows/install-desktop-windows.cmd`。
3. 确认预发布警告；随后在官方 Windows 安装界面完成安装。
4. 安装完成后，启动桌面的 **DeepSeek Harness**。

目标支持 Windows x64。官方桌面 feed 没有可验证的 Windows ARM64 安装包，因此 ARM64 机器会 fail closed。安装位置由官方安装程序决定，不强制安装到旧 Web 部署器的 `D:\DeepSeekHarness`。

部署器会验证官方 HTTPS 主机、目标架构、版本化文件路径、feed 声明的大小和 SHA-512，再验证 Authenticode 状态及 DeepSeek 发布者 CN/O/C；任何一项失败均不会执行安装包。它会复用完全匹配且签名有效的现有安装；默认不会升级。`-Upgrade` 用于用户明确检查升级，`repair-desktop-windows.ps1` 只允许对已验证的同一版本重跑官方安装器。

桌面快捷方式命名为 `DeepSeek Harness.lnk`。旧 Web 快捷方式会被核验并保留为 `DeepSeek Harness Web.lnk`；未知同名快捷方式会导致安装停止，不会被覆盖。

修复：

```powershell
powershell -ExecutionPolicy Bypass -File windows/repair-desktop-windows.ps1
```

卸载：

```powershell
powershell -ExecutionPolicy Bypass -File windows/uninstall-desktop-windows.ps1
```

卸载脚本只打开 Windows“已安装的应用”设置，让用户选择官方桌面版。它不会自动执行注册表中的任意卸载命令，也不会删除桌面用户数据、旧 Web 部署器或系统 Node.js。

## macOS 安装

支持 Apple Silicon（arm64）和 Intel（x86_64），不需要 Homebrew、Node.js 或 npm。安装目标：

```text
~/Applications/DeepSeek Harness.app
```

安装完成后会创建桌面 `DeepSeek Harness Desktop.command`，同时可以在 Finder 的 Applications 文件夹中双击 App。安装器按架构选择官方 ZIP，并校验文件大小、SHA-512、Bundle ID `com.deepseek.dsh`、版本、Team ID `NAN929V4UM`、`codesign` 和 Gatekeeper `spctl`。不会移除 quarantine、关闭 Gatekeeper 或修改系统安全设置。

从 GitHub/聊天软件下载源码压缩包时，macOS 可能因下载隔离拦截未签名的安装脚本。按住 Control 点击 `install-desktop-macos.command`，选“打开”；只允许本项目脚本运行。若提示没有执行权限，在 Terminal 进入仓库目录后只给该入口和目标脚本添加用户执行位：

```bash
chmod u+x macos/install-desktop-macos.command macos/install-desktop-macos.sh
```

这不是关闭 Gatekeeper 或清除 quarantine。官方 App 本身仍必须通过代码签名与 Gatekeeper 验证。某些 Mac 会在首次打开桌面 App 时继续要求用户到“系统设置 → 隐私与安全性”确认；如果校验不通过，不能绕过该保护。

修复（需已有本部署器安装凭据；确认后只重装同一版本）：

```bash
bash macos/repair-desktop-macos.sh
```

卸载（输入 `REMOVE` 后，将签名已验证的 App 移入废纸篓；默认保留日志、cache、升级备份和应用数据）：

```bash
bash macos/uninstall-desktop-macos.sh
```

要额外删除本部署器的 cache 和日志，可使用 `--purge` 并再次输入 `PURGE`。已有的升级备份或失败暂存 App 仍保留；应用自己的用户数据不由本卸载器删除。

## API Key、工作区与隐私

安装器不会询问、保存、记录或上传 API Key、密码、token、Cookie 或聊天内容。安装后在桌面应用中自行登录或进入 `Settings → Models` 配置模型/API。Harness 具有读写文件和执行工具的能力；请在应用中只选择具体项目目录，不要把整个磁盘作为工作区。

## 日志与错误编号

- Windows：`%LOCALAPPDATA%\DeepSeekHarnessDesktopDeployer\logs\install-*.log`
- macOS：`~/Library/Logs/DeepSeekHarnessDesktopDeployer/install-*.log`

错误编号：

| 编号 | 含义 |
|---|---|
| `DSH-D001` | 官方版本清单或网络访问失败 |
| `DSH-D002` | 版本清单内容、架构或地址不符合预期 |
| `DSH-D003` | 安装包下载、大小或 SHA-512 校验失败 |
| `DSH-D004` | 已有安装、版本、Bundle 或发布者身份校验失败 |
| `DSH-D005` | 官方安装程序/应用暂存或放置失败 |
| `DSH-D006` | 应用启动或本机 UI 确认失败 |
| `DSH-D007` | macOS 事务恢复或路径所有权不明确 |
| `DSH-D008` | 桌面快捷方式被未知目标占用 |
| `DSH-D009` | 操作系统或架构不支持 |
| `DSH-D010` | 用户目录权限、系统工具或参数问题 |
| `DSH-D999` | 未预期错误；请同时提供对应日志 |

不要公开完整日志前忘记检查隐私内容。提供错误编号和日志文件路径通常就足够排查。

## 当前验证边界

| 项目 | 证据 / 状态 |
|---|---|
| Windows PowerShell 5.1 与一键入口 | 桌面自检（含本地 HTTP fixture 四路 Range 和 `.part` 续传 SHA-512）、旧 Web 回归、`.cmd -ProbeOnly`、现有安装幂等部署、稳定版 404→候选版 feed 解析及同版本复用 PASS；快捷方式、启动路径和可见 UI 已确认 |
| Windows 冷安装 | NOT TESTED：开发机已存在官方桌面版，且无可用隔离 VM；未卸载现有应用来制造测试环境，需在干净 VM/新用户机验收 |
| macOS 静态检查 | Bash 语法、feed/版本自测、官方来源与 Gatekeeper 静态契约 PASS（Windows 主机的 Git Bash） |
| Apple Silicon 真机 | NOT TESTED |
| Intel Mac 真机 | NOT TESTED |

Windows 本次验收记录见 [Windows 桌面端验收记录](acceptance/windows-desktop-2026-10-08.md)。桌面版仍是预览实施，尚不代表冷安装或跨平台 Release PASS。查看 [迁移架构与完整验收矩阵](DESKTOP_TRANSITION.md) 和 [测试计划](test_plan.md)。

## Windows 桌面安装包下载

官方桌面版需要下载完整 Windows 安装包；已观测候选版约 289 MB，旧 Web 部署器下载的运行环境和 npm 包通常小得多，因此两条安装流程的耗时不能直接比较。下载速度还会受测试者到官方 CDN 的网络线路、代理和本机安全软件影响。

桌面安装器会先确认官方服务器支持 HTTP 字节范围，再尝试最多 4 路并行下载；无法确认或并行请求失败时会自动退回单连接。进度显示已下载大小、平均速度和剩余时间。中断后重新运行新版入口会请求从缓存中的连续 `.part` 文件续传；若服务器忽略范围请求，则安全地从头下载，避免把重复数据拼入安装包。下载结束仍必须通过官方清单大小、SHA-512 和 Authenticode 发布者校验，之后才执行安装器。

若已下载字节数连续数分钟不变，先检查测试者的网络是否能稳定访问 `download.deepseek.com`，并排查代理、VPN、防火墙或安全软件对下载的影响。旧测试包不具备断点续传；换用新版前需先结束旧安装窗口，新版会保留并验证旧版本产生的连续下载部分。
