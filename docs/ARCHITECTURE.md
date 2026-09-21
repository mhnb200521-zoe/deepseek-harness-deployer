# DeepSeek Harness Deployer — 架构设计文档 (ARCHITECTURE)

> 文档状态: **M0 / G1 草案,待架构审查**
> 版本: 0.1.0-M0
> 日期: 2026-09-19

本文件是整个部署产品的架构基线。M1—M6 的所有实现必须与本文件一致;任何冻结接口的变更需回退本阶段重新评审。

---

## 1. 产品定位

这是一套**交付给普通用户**的 DeepSeek Harness 部署产品,不是临时脚本。核心非功能目标:

```
可靠 · 可重复(幂等) · 可诊断 · 可维护 · 可升级 · 可卸载 · 普通用户可用
```

用户理想路径:

- Windows: 双击 `install-windows.cmd` → 等待 → 桌面出现 `DeepSeek Harness` → 双击启动
- macOS: 打开 `install-macos.command` → 等待 → 双击 `DeepSeek Harness.command`

---

## 2. 总体架构分层

```
┌─────────────────────────────────────────────────────────────┐
│  L0 入口层  install-windows.cmd / install-macos.command       │
│            (最薄封装:提权/绕过执行策略/调用 L1)                 │
├─────────────────────────────────────────────────────────────┤
│  L1 编排层  install-windows.ps1 / install-macos.sh            │
│            (7-Stage 状态机;串联 L2 各模块;统一日志/错误码)      │
├─────────────────────────────────────────────────────────────┤
│  L2 能力模块层 (跨平台功能对等,平台各自实现)                    │
│   ├ SysProbe      OS/CPU/磁盘/权限检测                          │
│   ├ NodeResolver  现有 Node 兼容判定 + 版本选择                 │
│   ├ NodeProvision 私有 Runtime 下载/校验/解压                   │
│   ├ NetPreflight  npm/registry/包可达性预检                     │
│   ├ HarnessPrep   npx 拉起 DSH(首次准备)                       │
│   ├ Launcher      生成 start-dsh 启动器                         │
│   ├ ServiceProbe  端口轮询/占用判定/健康检查                    │
│   ├ Shortcut      桌面快捷方式 / .command                       │
│   └ Logger        结构化日志 + 脱敏                             │
├─────────────────────────────────────────────────────────────┤
│  L3 运维层  repair-* / uninstall-* / tests/*-check             │
├─────────────────────────────────────────────────────────────┤
│  L4 运行期  start-dsh.cmd / start-dsh.command (装后每次启动)    │
└─────────────────────────────────────────────────────────────┘
```

**设计要点**:入口层(L0)必须极薄——只负责“把用户从双击带到编排器”,所有逻辑集中在 L1/L2,便于测试与维护。

---

## 3. 目录布局

### 3.1 部署器源码仓库(交付物)

```
deepseek-harness-deployer/
├─ README.md               (M6)
├─ CHANGELOG.md            (M2起维护)
├─ LICENSE
├─ project_manifest.json   (治理状态,已建)
├─ windows/
│  ├─ install-windows.cmd     (L0 入口)
│  ├─ install-windows.ps1     (L1 编排)
│  ├─ start-dsh.cmd           (L4 启动器模板)
│  ├─ uninstall-windows.ps1   (L3)
│  └─ repair-windows.ps1      (L3)
├─ macos/
│  ├─ install-macos.command   (L0 入口)
│  ├─ install-macos.sh        (L1 编排)
│  ├─ start-dsh.command       (L4 启动器模板)
│  ├─ uninstall-macos.sh      (L3)
│  └─ repair-macos.sh         (L3)
├─ docs/
│  ├─ WINDOWS.md  MACOS.md  TROUBLESHOOTING.md  ARCHITECTURE.md
│  ├─ risk_register.md
│  └─ test_plan.md
└─ tests/
   ├─ windows-check.ps1
   └─ macos-check.sh
```

### 3.2 安装目标布局(运行期,用户机)

Windows(优先 D:,无 D: 时回退 `%LOCALAPPDATA%\DeepSeekHarness`):

```
D:\DeepSeekHarness\
├─ runtime\node\    私有 Node(仅当现有 Node 不兼容时创建)
├─ launcher\        start-dsh.cmd(实际启动器)
├─ workspace\       默认工作目录(Harness working dir)
├─ cache\           npm/npx 缓存(隔离,不污染用户 ~\.npm)
├─ logs\            install-*.log / runtime-*.log
└─ config\          deployer.json(记录运行时决策,非机密)
```

macOS:

```
~/Library/Application Support/DeepSeekHarness/
├─ runtime/node/    私有 Node
├─ launcher/        start-dsh.command
├─ cache/
└─ config/
~/DeepSeekHarness/workspace/            (工作目录,用户可见处)
~/Library/Logs/DeepSeekHarness/         (日志)
```

**关键规则**: `config/` 只记录 OS/arch/node 路径/端口/安装时间等**非机密决策**,严禁写入 API Key/token。

---

## 4. 安装状态机(7-Stage)

编排层是一台确定性状态机。每个 Stage 产出 `PASS / WARN / FAIL`,`FAIL` 立即带 Error ID 中止(除非该步定义了回退分支)。

```
[S0 Probe] → [S1 SysCheck] → [S2 Node] → [S3 npm] → [S4 Harness] →
[S5 Launcher] → [S6 Shortcut] → [S7 Verification] → DONE
```

> **S0 能力探测(闭合审查 B1)**: 在正式流程前,用**已确认可用的 Node**实跑 dsh CLI,解析其真实子命令、`web` 是否存在、`--no-open` 是否支持、默认端口、是否支持指定端口(如 `--port`)。探测结论写入 `config/deployer.json` 并入日志。§7 的端口与命令、E007 的“换端口”建议**以 S0 实测结果为准**,不以本文假设为硬事实。若 CLI 无法自省(非 TTY 无输出等),则以“保守默认 + 显式标注 unverified”方式记录,并在 Web UI 提示用户以官方文档为准。注:S0 依赖 Node,故实际排在 S2 得到可用 Node 之后立即执行(逻辑上是 S4 的前置)。

| Stage | 名称 | 模块 | 成功判据 | 失败/分支 |
|---|---|---|---|---|
| S1 | System Check | SysProbe | 识别 OS/CPU;确定安装目录(D: 或回退) | 无 D: → 交互三选一(非崩溃) |
| S2 | Node.js | NodeResolver→NodeProvision | 得到一个兼容 node 可执行路径 | 现有兼容→复用;否则下载私有;下载/校验失败 E001/E002 |
| S3 | npm | NetPreflight | `npm -v` 通过 + registry 可达 + 包可达 | E003/E004/E005,转人类可读 |
| S4 | Harness | HarnessPrep | `npx --yes @deepseek-ai/dsh@<pinned> web --no-open`(命令/参数以 S0 实测校正)拉起进程 | E006 |
| S5 | Launcher | Launcher | 生成 start-dsh 且自检可执行 | 写入失败→权限 E010 |
| S6 | Shortcut | Shortcut | 桌面快捷方式/.command 创建 | E008(降级为 WARN,不阻断) |
| S7 | Verification | ServiceProbe | 轮询 127.0.0.1:3080 健康 | 超时 E006;端口占用 E007 分支判定 |

状态机对每个 Stage 记录 `{stage, status, errorId?, durationMs, detail}` 到安装日志。

**幂等保证**: 每个 Stage 进入前先探测“是否已达成目标态”(如 Node 已兼容、launcher 已存在且有效、端口已在跑 Harness),达成则跳过重复动作,标记 `PASS(reused)`。重复运行安装器不产生破坏。

**进程生命周期(闭合审查补强)**: S4 与 L4 启动器均以**分离/后台**方式拉起 Harness(Win `Start-Process` 分离进程 / mac `nohup … &`),并捕获 PID 写入 `config/deployer.json` 与 runtime 日志。安装结束后服务默认**保持运行**直至用户关闭;启动前先由 ServiceProbe 探端口,已在运行则不重复拉起(幂等)。

**dsh 版本锁定(闭合审查 B2)**: 由于 `@deepseek-ai/dsh` 处于早期 RC(见 R01),`npx` 一律使用**锁定版本** `@deepseek-ai/dsh@<pinned>`(取自 `config.dshVersion`),不使用无版本 latest,以保证“可重复”。首次安装时把当次解析到的可用版本写入 config 并冻结,升级由 M2 的升级路径显式触发。

---

## 5. Node 版本策略(核心)

### 5.1 兼容判定(N0)

兼容集合:`^22.19.0`(即 `>=22.19.0 <23.0.0`) **或** `>=24.0.0`。

判定伪代码(实现层遵循):

```
parse major.minor.patch
compatible =
   (major == 22 && (minor > 19 || (minor == 19 && patch >= 0)))
   || (major >= 24)
```

明确后果:

- `24.19.0` → 兼容(但**不得**把它当唯一硬编码判据)
- `22.19.0`+ → 兼容
- `20.x` / `23.x` / `22.18-` → **不兼容**,走私有 Runtime

现有 Node 兼容时:**复用,绝不覆盖/修改用户安装**。

### 5.2 版本选择(需私有 Runtime 时)

- 数据源:官方 `https://nodejs.org/dist/index.json`(含 `version`/`lts` 字段)。
- 优先级:**最新的兼容 LTS**。
  1. 首选 Node 24 LTS 线的最新兼容版本
  2. 回退 Node 22 线且 `>=22.19` 的最新版本
- 不默认安装 Node Current(奇数线),除非无任何兼容 LTS 可用。
- **“复用判定” ≠ “主动安装选择”(闭合审查建议)**: §5.1 的兼容集合用于**是否复用现有 Node**(此时即便是 25.x Current 也复用,因用户已装,不越权替换);而本节 §5.2 的“优先 LTS、不装 Current”仅约束**部署器主动下载私有 Runtime 时**的选版。两套规则目的不同,不得混用。
- 版本号**不永久硬编码**;仅缓存一个“已知良好”兜底版本用于离线索引失败时的最后手段,并在日志标注为兜底。

### 5.3 完整性验证

- 下载 `SHASUMS256.txt`(官方),核对压缩包/安装包 SHA256。
- 校验失败 → 立即停止(E002),不解压不执行。
- 只从 `nodejs.org` 官方域获取,禁止第三方镜像作为默认(镜像可作为“网络失败重试”的可选项,但需明确来源与校验)。

---

## 6. OS / CPU 检测

| 平台 | 检测手段 | 识别目标 → Node 包 |
|---|---|---|
| Windows | `$env:PROCESSOR_ARCHITECTURE` / `PROCESSOR_ARCHITEW6432` | x64 → `win-x64`;ARM64 → `win-arm64`(可靠则支持,否则明确 WARN) |
| macOS | `uname -m` | `x86_64` → `darwin-x64`;`arm64` → `darwin-arm64` |

普通用户**不手动选架构**。不支持的架构 → E009 明确提示。

---

## 7. 服务启动与健康检查

- 默认 Web UI: `127.0.0.1:3080`(**以 S0 探测结果与 `config.port` 为准**;S7 健康检查一律读 `config.port`,实现不得硬编码 3080)。
- 启动后轮询该端口(超时 60–120s),期间显示 `Starting DeepSeek Harness...`。
- 成功 → `[PASS] DeepSeek Harness is running.` → 打开浏览器(Win `Start-Process` / mac `open`)。
- **端口占用处理**(严禁盲杀进程):
  1. 端口已监听 → 探测其响应特征,判断是否为 DSH(HTTP 探测/进程命令行比对)。
  2. 是 DSH → 直接打开页面(视为幂等成功)。
  3. 非 DSH → 报 E007,给出建议。**换端口建议仅在 S0 已确认 dsh 支持指定端口(如 `--port`)时给出**;若不支持,则改为“请关闭占用该端口的程序后重试”,不承诺不可执行的方案。

---

## 8. 安全模型

Harness 是可**读写文件、执行 shell、调用工具**的 Agent,因此部署器采取最小授权:

1. **不**把 `C:\` `D:\` `/` `~` 整盘设为 workspace;默认 workspace 为专用子目录,并引导用户在 Web UI 内选择具体项目目录。
2. **不**保存/上传/内置/硬编码/明文记录任何 API Key、token、密码、Cookie、聊天内容。安装完成仅提示用户去 Web UI `Settings → Models` 自行配置。
3. **不**关闭 Windows Defender;**不**改防火墙规则;**不**要求手改 PATH(私有 Runtime 通过启动器局部注入 PATH)。
4. **不**执行来源不明二进制;Node 仅来自官方域并校验哈希。
5. **不**删除/覆盖用户已有 Node 或无关软件;卸载器只删本产品创建物。
6. 提权最小化:安装到 D: 用户目录/AppData 通常无需管理员;若确需提权,明确告知原因并可拒绝。
7. 日志脱敏:Logger 统一过滤敏感字段(见 §10)。

---

## 9. 失败处理与错误码

所有 `FAIL` 必须:①定位到具体 Stage;②给出统一 Error ID;③终端显示**人类可读**提示(禁止直接甩异常堆栈);④完整技术细节(含 stack)写入日志。

| Error ID | 含义 | 触发 Stage |
|---|---|---|
| DSH-E001 | Node 下载失败 | S2 |
| DSH-E002 | Node 校验(SHA256)失败 | S2 |
| DSH-E003 | npm 不可用 | S3 |
| DSH-E004 | npm registry 不可达 | S3 |
| DSH-E005 | @deepseek-ai/dsh 包不可达 | S3 |
| DSH-E006 | Harness 启动/健康检查失败 | S4/S7 |
| DSH-E007 | 端口冲突(非 DSH 占用 3080) | S7 |
| DSH-E008 | 快捷方式创建失败(降级 WARN) | S6 |
| DSH-E009 | 不支持的架构 | S1/S2 |
| DSH-E010 | 权限问题(写目录/建启动器) | 任意 |
| DSH-E011 | Node 版本元数据(index.json/SHASUMS)获取或解析失败 | S2 |
| DSH-E999 | 未预期异常(脚本崩溃/未捕获错误)——兜底码,必附原始堆栈入日志 | 任意 |

网络类失败(E004/E005)统一转译为“换网络/DNS/校园网代理”提示模板。用户报障只需提供 Error ID。

---

## 10. 日志系统

- 位置: Win `…\logs\`;mac `~/Library/Logs/DeepSeekHarness/`。
- 命名: `install-YYYYMMDD-HHMMSS.log`、`runtime-YYYYMMDD-HHMMSS.log`。
- 允许记录: OS、arch、node/npm/dsh 版本、网络检测、Stage 结果、Error ID、stack trace。
- **禁止记录**: API Key、密码、token、Cookie、用户聊天内容。
- 脱敏: Logger 在写入前对匹配 `sk-…`/`token`/`authorization`/`api[_-]?key` 等模式做打码。

---

## 11. 冻结接口(G2 起冻结,变更需回退 G1)

以下为跨模块契约,M1 起冻结:

1. **安装目录布局**(§3.2 的子目录名: runtime/launcher/workspace/cache/logs/config)。
2. **Error ID 表**(§9)。
3. **启动器契约**: 启动器负责“局部 PATH 注入 → 设 workdir=workspace → 启动 DSH → 写 runtime 日志 → 健康检查 → 开浏览器”,对外零参数即可运行。
4. **config/deployer.json 字段**(闭合审查 B2/B3): `os, arch, installRoot, workspaceDir, logDir, cacheDir, nodePath, nodeMode(reuse|private), nodeVersion, dshVersion(锁定版本), port, webCommand(S0 实测), portConfigurable(bool), pid, installedAt, deployerVersion`。Windows 三目录同处单根 `installRoot`;macOS 的 `workspaceDir`/`logDir` 可独立于 `installRoot`,由这三个显式字段承载,保证 Win/mac 在同一冻结契约下并行实现。
5. **Stage 结果记录结构**: `{stage,status,errorId?,durationMs,detail}`。
6. **端口默认值** 3080(可被 config 覆盖;S7 健康检查读 config,不硬编码)。
7. **日志字段 schema(闭合审查 B4)**: 每条日志记录字段固定为 `timestamp, level, stage, message, errorId?`;安装摘要含 `os, arch, nodeVersion, npmVersion, dshVersion, installRoot`。脱敏正则集合(`sk-[A-Za-z0-9]+`、`(?i)authorization`、`(?i)api[_-]?key`、`(?i)token`、`(?i)cookie`)作为冻结契约,Win/mac 共用同一集合,保证跨平台日志字段与脱敏行为一致。

---

## 12. 跨平台对等原则

Windows 与 macOS 在**用户可见行为**上必须对等:相同 7-Stage、相同 Error ID、相同日志字段、相同验收界面结构。平台差异仅体现在实现手段(PowerShell vs bash、.lnk vs .command、注册表/plist 均不使用)。
