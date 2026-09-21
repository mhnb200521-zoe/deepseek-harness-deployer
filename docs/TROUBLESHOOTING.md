# 故障排查

## 先收集什么

失败时不要把 API Key、Cookie 或完整 URL token 发到群聊。只收集：

1. 终端中的 `Error ID`，例如 `DSH-E004`。
2. 对应的 install/runtime/diagnostic 日志路径。
3. 操作系统版本和 CPU 架构。
4. Node/npm 版本（如果终端显示）。
5. 发生在 Stage 几。

日志已经对 token、authorization、api-key、Cookie 和 `sk-` 形式的密钥做脱敏；分享前仍应人工快速检查。

## Error ID 对照

| Error ID | 含义 | 优先处理 |
|---|---|---|
| DSH-E001 | Node 下载、解压或安装失败 | 检查网络、磁盘空间和目标目录权限，重试 |
| DSH-E002 | Node SHA256 校验失败 | 删除本产品 cache 后重试；不要执行未通过校验的文件 |
| DSH-E003 | npm/npx 不可用 | 检查 Node 安装和运行期私有 Runtime，勿手工改系统 PATH |
| DSH-E004 | npm registry 不可达 | 检查 DNS、HTTPS、校园网/公司代理和网络认证 |
| DSH-E005 | DSH 包不可达 | 确认 npm registry 能访问 `@deepseek-ai/dsh` |
| DSH-E006 | Harness 启动或 Web 健康检查失败 | 查看 runtime 日志、端口状态，运行 Repair |
| DSH-E007 | 端口被非 Harness 程序占用 | 不要杀进程；关闭占用程序或按诊断报告处理 |
| DSH-E008 | 快捷启动方式创建失败 | 检查桌面/`~/DeepSeekHarness` 中是否已有同名文件及权限 |
| DSH-E009 | OS/CPU 架构不支持 | 当前支持 Windows x64 优先、macOS x86_64/arm64 |
| DSH-E010 | 目录、权限或配置问题 | 检查目标目录可写性；macOS 卸载还会校验 deployer.json 归属 |
| DSH-E011 | Node 版本元数据获取/解析失败 | 恢复网络后重试；部署器才会使用明确记录的兼容兜底版本 |

## npm 网络失败

常见原因：

- 当前网络无法访问 npm registry 或 `nodejs.org`。
- DNS 解析异常。
- 校园网/公司网络要求网页登录。
- HTTPS 被代理或安全网关拦截。

先用浏览器确认网络可用，再重新运行安装器。不要把 `--verbose` 当成 Harness 必需参数；它只应该用于诊断安装失败，正常启动不需要它。

## 3080 已占用

部署器不会默认杀掉占用 3080 的进程。

- 如果端口上已经是 Harness，启动器会使用明确标记的 fallback URL 并打开页面。
- 如果是其他软件，终端和日志会显示端口冲突。请先确认进程归属，再关闭其他软件或等待其退出。

## URL 中包含 token

这是 Harness Web UI 可能需要的会话信息。部署器会：

1. 从实际 DSH 输出捕获 URL。
2. 在内存中保留 query/token，用同一 URL 验证和打开。
3. 日志只记录 `source=detected` 和 `tokenPresent=true`，不记录完整 token。

如果只有 `source=fallback`，说明本次没有从新启动输出取得 token URL；不要把日志中的 fallback 地址当成 token URL。关闭已有实例后重新启动，可以让启动器重新捕获实际输出。

## Repair 命令

Windows：

```powershell
powershell -ExecutionPolicy Bypass -File windows/repair-windows.ps1
```

macOS：

```bash
./macos/repair-macos.sh
```

Repair 失败本身不修改已有 Node 或防火墙。把 Diagnostic Report 和 Error ID 一起提供给技术人员即可。

## 卸载后如何恢复

默认卸载保留 workspace 和 logs。如果只是想重建 launcher/config，优先重新运行安装器，不要使用 `--purge`。只有确认 workspace 中没有需要保留的文件时，才使用 `--purge --yes`。
