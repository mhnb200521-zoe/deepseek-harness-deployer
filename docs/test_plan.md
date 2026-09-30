# 测试计划 (Test Plan)

> 状态: M6 文档完成；M5/G3 macOS 真机验收待补 · 2026-09-21
> 覆盖验收测试矩阵(§25/§26)。每个用例定义: 前置 / 步骤 / 期望 / 判据。

## 1. 测试层级

- **单元级**: 版本兼容判定、架构映射、端口占用判定、脱敏函数。
- **集成级**(`tests/windows-check.ps1` / `tests/macos-check.sh`): 只读诊断,输出各能力 PASS/WARN/FAIL,不改环境。
- **场景级**: 下方 Windows/macOS 矩阵,尽量在隔离环境/虚拟机执行。

## 2. Windows 11 x64 矩阵

| Case | 场景 | 期望结果 |
|---|---|---|
| A | 无 Node | 下载校验私有 Node 24 LTS,后续全通过 |
| B | Node 20(不兼容) | 判否 → 私有 Runtime,不覆盖 Node 20 |
| C | Node 22 (>=22.19) | 判兼容 → 复用,不下载 |
| D | Node 24 | 判兼容 → 复用 |
| E | 无 D: 盘 | 交互三选一,选 AppData 可完成安装,不崩溃 |
| F | npm 网络失败 | E004/E005 人类可读,日志含技术细节,非堆栈刷屏 |
| G | 3080 已占用 | 判定占用者:是 DSH→开页面;非 DSH→E007 不杀进程 |
| H | 重复执行安装器 | 幂等:跳过已达成步骤,标 PASS(reused),无重复破坏 |

## 3. macOS 矩阵

| Case | 场景 | 期望结果 |
|---|---|---|
| M1 | Apple Silicon(arm64) | 选 darwin-arm64 |
| M2 | Intel(x86_64) | 选 darwin-x64 |
| M3 | 无 Node | 私有 Runtime |
| M4 | 兼容 Node | 复用 |
| M5 | 旧 Node | 私有 Runtime,不污染 |
| M6 | 网络失败 | 人类可读错误 |
| M7 | 重复安装 | 幂等 |

## 4. 通用断言(每条场景均须满足)

- 每 Stage 输出 PASS/WARN/FAIL。
- 任一 FAIL 带 Error ID 且定位到 Stage。
- 安装日志生成且不含机密字段。
- 不修改用户已有 Node / PATH / 防火墙 / Defender。
- 成功路径必须从 DSH 实际输出提取 Web URL，保留 path/query/token；3080 只作为明确标记的 fallback。S7 使用实际 URL 验证并打开浏览器，日志只记录 URL 来源与 token 是否存在。

## 5. 里程碑对应的通过门槛

- M1: Case A/C/D + H 的 Windows 核心链路通过(Node→npm→Harness→Launcher→Verify)。
- M2: + E/F/G + Repair/Uninstall/Error ID/Logs。
- M3/M4: macOS 对应项(真机验证在 M5)。
- M5: 全矩阵;无法真机的项如实标注。

## 6. M2 Windows Productization 实测证据

| 项目 | 实测结果 |
|---|---|
| Token URL 冷启动 | PASS：从 DSH stdout 检测实际 URL，`tokenPresent=True`，HTTP 200，并打开同一 URL |
| Token 脱敏 | PASS：runtime log 只保留 `[REDACTED]`，config/logs 无完整 token |
| Repair | PASS：8 项 PASS、端口未启动时 1 项 WARN、退出码 0，生成 diagnostic report |
| 默认 Uninstall | PASS：停止本安装 DSH 进程树，删除 launcher/cache/config/快捷方式，保留 workspace/logs，系统 Node 保留 |
| Uninstall `-Purge` | PASS：删除 workspace/logs 并删除空安装根目录 |
| Regression | PASS：源脚本/生成 launcher 解析、SelfTest、`windows-check.ps1` |

## 7. M3 macOS MVP 静态证据

| 项目 | 实测结果 |
|---|---|
| Bash 语法 | PASS：`install-macos.command`、`install-macos.sh`、`start-dsh.command`、`repair-macos.sh`、`uninstall-macos.sh`、`tests/macos-check.sh` 全部通过 `bash -n` |
| macOS 文件契约 | PASS：安装入口、编排器、启动器、Repair/Uninstall 占位入口均存在 |
| URL 处理 | 已实现：优先捕获 DSH 实际 localhost/127.0.0.1 URL，保留 query/token；无新输出时使用显式 `source=fallback`，不记录完整 token |
| Stage 流程 | PASS：S1/S2/S3/S0/S5/S6/S7；S6 写入非机密 `deployer.json` |
| `tests/macos-check.sh` | PASS=9、WARN=1、FAIL=0；WARN 为当前宿主 Windows，未执行 macOS 真机链路 |
| Windows regression | PASS：`tests/windows-check.ps1` 退出码 0，既有 SelfTest 全部 PASS |

M3 未将 macOS 真机项伪标为通过。Apple Silicon/Intel Node 下载、SHA256、npx、端口、浏览器 `open` 和重复安装的真实验收留到 M5。

## 8. M4 macOS Productization 静态证据

| 项目 | 实测结果 |
|---|---|
| Repair | PASS：检查 Node/npm/npx、registry/DSH、launcher、用户可见启动方式、端口和最近 runtime Web 验证状态；报告只记录 source/tokenPresent，不记录完整 token |
| Uninstall | PASS：实现安装根目录归属进程树停止、私有 runtime/launcher/cache/config 删除；默认保留 workspace/logs，`--purge --yes` 才删除用户数据 |
| 不存在目标保护 | PASS：`--install-dir /tmp/deepseek-harness-does-not-exist --yes` 输出未找到且退出码 0，未执行删除 |
| 参数边界 | PASS：Repair/Uninstall `--help`；安装器非法端口返回 DSH-E010 |
| npm 缓存隔离 | PASS：安装器与运行期启动器将 `NPM_CONFIG_CACHE` 指向本产品 `cache/npm`，不写用户默认 npm cache |
| 真机限制 | 当前宿主为 Windows，未将 macOS registry/port/open/进程树与 purge 行为标记为真实通过，留待 M5 |

## 9. M5 Cross-platform Validation 状态

| 平台/范围 | 结果 | 证据 |
|---|---|---|
| Windows 11 x64 自检 | PASS | `tests/windows-check.ps1` 退出码 0；Node 兼容集合、Get-DshUrl、token 脱敏、Node 选版断言全部 PASS |
| Windows M2 真实 Token URL | PASS | `%TEMP%\dsh-token-fix-test\logs\install-20260920-183614.log`：`urlSource=detected tokenPresent=True httpStatus=200`，且 token 扫描 PASS |
| macOS 脚本/契约 | PASS + WARN | `tests/macos-check.sh`：PASS=9、WARN=1、FAIL=0；所有脚本 `bash -n` PASS |
| macOS Intel 真机 | PENDING | 当前 Windows 主机无法执行 Darwin Node 下载、npx、`nc`/端口、`open` 和真实进程树 |
| macOS Apple Silicon 真机 | PENDING | 同上；需在 arm64 Mac 或 CI runner 执行 |

M5 当前不能标记 completed；交付前必须补做至少一台 Intel 或 Apple Silicon Mac 的真实安装/Repair/Uninstall 测试，并最好补做另一种架构的私有 Node 下载验证。

## 10. M6 文档证据

| 文件 | 状态 |
|---|---|
| `README.md` | PASS：第一屏包含 Windows/macOS 普通用户启动路径、日志、Repair、Uninstall、安全提示和验证边界 |
| `docs/WINDOWS.md` | PASS：安装、Node、URL、Repair、Uninstall、日志说明与 Windows 实现一致 |
| `docs/MACOS.md` | PASS：Intel/Apple Silicon、权限、目录、缓存隔离、URL、Repair、Uninstall 与当前实现一致 |
| `docs/TROUBLESHOOTING.md` | PASS：Error ID、网络、端口、Token、诊断与卸载恢复路径齐全 |
| `LICENSE` | PASS：MIT License 文件存在 |

## 11. M5 真机验收证据目录

| 文件 | 当前状态 |
|---|---|
| `docs/acceptance/macos-arm64.md` | NOT TESTED：等待 Apple Silicon Mac，已准备完整验收门清单 |
| `docs/acceptance/macos-x86_64.md` | NOT TESTED：等待 Intel Mac，已准备完整验收门清单 |
| `docs/acceptance/release-gate.md` | PARTIAL：Windows PASS，两个 macOS 架构尚未真机验证 |

## 12. 官方桌面端迁移测试计划（实现中，尚未通过）

本节是与旧 Web M1–M6 **独立**的验证门。设计见 [DESKTOP_TRANSITION.md](DESKTOP_TRANSITION.md)。旧 `windows-check.ps1` 和 `macos-check.sh` 仍只证明 Web 部署，不得作为桌面链 PASS。

| 层级 | Windows x64 | macOS arm64 / x64 | 通过判据 |
|---|---|---|---|
| Feed / 版本 | 稳定 200、稳定 404→候选确认、超时/5xx/非法 feed 不回退 | 同左，分别选对 target | 精确版本、路径、size、SHA-512 一致 |
| 来源 / 完整性 | URL 跨域/跨架构、大小错误、哈希错误、无效/错误发行者签名拒绝 | SHA-512、Bundle ID、Team ID、codesign 与 spctl 错误拒绝 | 失败安装物绝不执行或覆盖 |
| 已有环境 | 无 App、同版本、旧版本、比目标新、未知同名 App、已有 Web 快捷方式 | 同左，另查 symlink/备份路径和空间 | 同版本复用；其余按所有权/升级策略处理 |
| 安装 / 恢复 | NSIS 用户取消、失败、成功，注册表和安装路径二次核查 | staging→备份→promotion，注入失败并验证回滚 | 旧安装和用户数据保留，错误可诊断 |
| 启动 / UI | 从精确安装路径启动，进程与窗口属于该路径，用户确认欢迎页/工作区 | 从精确 App 路径 `open`，用户确认窗口可操作 | Installed、Launched、UI ready 分层 PASS |
| 共存 / 回归 | `Web→Desktop→Web 重跑` 与 `Desktop→Web→Web 卸载` 均不覆盖/删除原生快捷方式；Web launcher、Token URL、Repair/Uninstall 继续通过 | Web `.command`、Node/npm/npx 路径及桌面 App 相互隔离 | 旧 Web 全部回归继续 PASS |
| 中断恢复 | 原生 NSIS 失败后重新核对安装登记，不自行删除程序 | 目标/备份/staging 各种中断组合及 journal 恢复，symlink/未知身份负例 | 旧 App 可恢复；模糊状态 fail closed |

截至 2026-09-30：官方发行物联网/哈希、Windows 签名样本和 macOS ZIP 静态 Bundle/CodeDirectory 身份属于**预检证据**。Windows 桌面安装器已实现初版，并通过 Windows PowerShell 5.1 自测、已安装官方 App 只读探测；冷安装与桌面 UI 未验收。macOS 桌面安装/修复/卸载脚本已实现初版，Git Bash 静态与 parser self-test PASS；Apple Silicon 和 Intel 真机签名、Gatekeeper、App/UI、事务中断恢复均未验收。不得将这些预检或静态结果改写成端到端 PASS。
