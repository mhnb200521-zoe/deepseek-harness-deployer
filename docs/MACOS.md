# macOS 使用与维护

## 普通用户安装

支持 Intel Mac（`x86_64`）和 Apple Silicon（`arm64`）。项目不要求预先安装 Homebrew。

首次运行前，如果压缩包没有保留 Unix 可执行权限，请在 Terminal 进入项目目录执行：

```bash
chmod +x macos/install-macos.command macos/install-macos.sh
```

然后双击：

```text
macos/install-macos.command
```

Gatekeeper 首次拦截时，在 Finder 中右键文件选择“打开”，确认后再运行。不要为了运行本工具关闭 Gatekeeper 或系统安全软件。

安装器阶段：

```text
Stage 1/7  System Check
Stage 2/7  Node.js
Stage 3/7  npm
Stage 4/7  Harness（S0 能力探测）
Stage 5/7  Launcher
Stage 6/7  Configuration, Workspace and Shortcut
Stage 7/7  Verification
```

## 安装目录

```text
~/Library/Application Support/DeepSeekHarness/
├─ runtime/node/    仅在需要时创建的私有 Node
├─ launcher/        start-dsh.command
├─ cache/            npm/npx 隔离缓存
└─ config/           deployer.json（非机密决策）

~/DeepSeekHarness/workspace/
~/DeepSeekHarness/DeepSeek Harness.command
~/Library/Logs/DeepSeekHarness/
```

用户可双击 `~/DeepSeekHarness/DeepSeek Harness.command` 启动。它是指向本产品启动器的链接；启动器会解析链接后定位真实安装根目录。

## Node 与 npm 缓存

兼容基线为 `^22.19.0 OR >=24.0.0`。已有兼容 Node 直接复用；否则仅从官方 Node 来源下载匹配架构的 tarball，并用 `SHASUMS256.txt` 校验。

运行期通过 `NPM_CONFIG_CACHE` 使用本产品的 `cache/npm`，不把 Harness 缓存写入用户默认 npm cache，也不修改系统 PATH。

## URL 验证与日志

启动器执行：

```text
npx --yes @deepseek-ai/dsh@<pinned> web --no-open
```

它会优先捕获 DSH 实际输出中的 `localhost`/`127.0.0.1` URL，保留 query/token，验证后打开同一个 URL。无法从新输出获得 URL 时，才使用明确标记的 `source=fallback`；日志仅记录 `tokenPresent=true/false`。

安装器和运行期日志位于：

```text
~/Library/Logs/DeepSeekHarness/
```

## Repair

```bash
./macos/repair-macos.sh
```

Repair 只做诊断，检查 Node/npm/npx、npm registry、DSH、launcher、用户启动链接、端口和最近运行日志，并生成 `diagnostic-*.txt`。报告不包含 API Key、token、Cookie 或聊天内容。

## Uninstall

默认卸载：

```bash
./macos/uninstall-macos.sh
```

删除本产品的私有 Runtime、launcher、cache、config 和用户启动链接，保留 workspace 与日志。彻底删除用户数据前使用：

```bash
./macos/uninstall-macos.sh --purge --yes
```

如果安装目录缺少本产品的 `config/deployer.json`，卸载器会拒绝删除，以避免把任意目录误当作本产品目录。系统已有 Node 永远不会删除。

## 当前验证边界

当前开发主机为 Windows，因此已经完成 Bash 语法、文件契约和静态安全检查，但 Intel/Apple Silicon Mac 上的 Node 下载、npx 启动、端口、浏览器 `open`、真实进程树和 purge 行为仍需 M5 真机验收。
