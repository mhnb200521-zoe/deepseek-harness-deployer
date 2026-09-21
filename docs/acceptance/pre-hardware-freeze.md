# Pre-Hardware Release Validation Freeze

日期：2026-09-21

## Freeze Result

```text
FREEZE: PASS — local Git baseline established; release remains blocked by M5 hardware validation
```

Git Baseline Freeze 已完成。本地仓库已初始化、默认分支已建立、baseline commit 和 annotated tag 已创建；没有配置 remote，也没有 push。Feature Freeze 和 Code Freeze 继续有效。

## Repository State

```text
Repository root: C:\Users\Lenovo\deepseek-harness-deployer
Repository initialized: YES
Git metadata: present
Branch: main
Baseline commit: 60039fcd541d50093ac317fcc0a13c60c69cc138
Baseline tag: pre-hardware-validation
Remote: none
Baseline git status: clean before governance metadata update
Final git status: clean after governance metadata update
```

首个 baseline commit 使用指定 message：

```text
chore(repo): establish pre-hardware-validation baseline
```

annotated tag message：

```text
Windows validated; macOS implementation complete; real Mac hardware validation pending.
```

baseline commit 纳入了完整 Source Inventory，共 27 个正式文件；本报告的 Git 元数据更新属于允许范围内的治理文档更新。

```text
.gitignore
CHANGELOG.md
LICENSE
README.md
project_manifest.json
docs/ARCHITECTURE.md
docs/WINDOWS.md
docs/MACOS.md
docs/TROUBLESHOOTING.md
docs/risk_register.md
docs/test_plan.md
docs/acceptance/macos-arm64.md
docs/acceptance/macos-x86_64.md
docs/acceptance/pre-hardware-freeze.md
docs/acceptance/release-gate.md
macos/install-macos.command
macos/install-macos.sh
macos/start-dsh.command
macos/repair-macos.sh
macos/uninstall-macos.sh
tests/macos-check.sh
```

本次冻结期间没有修改 Windows 核心实现、目录架构、Node compatibility policy、Error ID taxonomy 或 Token URL 逻辑。

## Temporary Files

```text
runtime/log/cache/workspace/download artifacts: NONE
*.log / *.tmp / *.part / *.tar.gz / *.dmg / *.pkg: NONE
```

发现并清理的唯一临时残留是根目录下的 `windows$f`：大小 3 字节、内容为空、不属于产品结构。清理后未发现其他临时测试文件。

## Gitignore Coverage

`.gitignore` 覆盖：

```text
**/logs/
**/cache/
**/runtime/
**/workspace/
**/config/deployer.json
*.log
*.pid
*.tmp
*.part
*.download
*.tar.gz
*.tgz
*.zip
*.dmg
*.pkg
diagnostic-*.txt
*.lnk
```

```text
GITIGNORE COVERAGE: PASS
```

没有 `.git`，无法使用 `git check-ignore` 做仓库级追踪状态验证；这里只确认规则文件和要求的模式存在。

## Secrets Scan

高置信度敏感值扫描结果：

```text
sk-* values: NONE
ghp_* values: NONE
xox* values: NONE
AIza* values: NONE
api-key/authorization/password/secret assignment values: NONE
```

```text
SECRETS SCAN: PASS
```

代码中的 `tokenPresent=true`、`source=detected` 和脱敏正则表达式是逻辑文本，不是实际 secret。

## Validated Status

```text
Windows implementation: PASS
Windows regression: PASS
macOS implementation: COMPLETE
macOS productization: COMPLETE
macOS static validation: PASS
Apple Silicon hardware validation: NOT TESTED
Intel hardware validation: NOT TESTED
Cross-platform release: BLOCKED
```

Windows 回归：`tests/windows-check.ps1` 退出码 0，`SelfTest RESULT: ALL PASS`。

macOS 静态检查：`tests/macos-check.sh` 退出码 0，`Summary: PASS=9 WARN=1 FAIL=0`。WARN 仅表示当前执行环境为 Windows，未执行 Darwin Node、npx、端口和 `open` 操作。

验收记录：

- [Apple Silicon acceptance](macos-arm64.md)
- [Intel acceptance](macos-x86_64.md)
- [Release gate](release-gate.md)

## Outstanding Release Blockers

```text
[ ] Apple Silicon arm64 real hardware acceptance
[ ] Intel x86_64 real hardware acceptance
[ ] darwin-arm64 and darwin-x64 private Node real execution evidence
[ ] SHA256 verification real installation evidence on Mac
[ ] npm/npx/DSH real execution evidence on Mac
[ ] actual URL and HTTP verification on Mac
[ ] browser open verification on Mac
[ ] launcher double-click verification on Mac
[ ] repeated install verification on Mac
[ ] Repair report verification on Mac
[ ] default Uninstall preservation verification on Mac
[ ] safety guard verification on Mac
[ ] --purge --yes ownership verification on Mac
[ ] port conflict and recoverable network failure verification on Mac
```

## Exact Next Hardware Actions

### Apple Silicon Mac

1. 记录 `sw_vers`、`uname -m`、Node/npm/npx、安装根目录、DSH 进程和 3080 初始状态。
2. 确认 `uname -m` 为 `arm64`。
3. 在没有预装兼容 Node、预建 runtime 或手工启动 DSH 的条件下执行 `./macos/install-macos.command`。
4. 确认实际选择 `darwin-arm64`、官方 `SHASUMS256.txt` 和校验 PASS。
5. 确认 `cache/npm` 被使用，系统默认 npm cache 未被写入。
6. 确认 DSH 调用包含 `@deepseek-ai/dsh@<pinned> web --no-open`。
7. 确认 `source=detected`、Token present 状态和 HTTP 验证；报告中不得写完整 token。
8. 通过 Finder 双击 `~/DeepSeekHarness/DeepSeek Harness.command`，确认 Web UI 可见。
9. 重复安装，执行 Repair、默认 Uninstall、安全防护和 `--purge --yes`。
10. 扫描 logs，保存 `macos-arm64.md` 的非敏感证据。

### Intel Mac

使用相同流程，并额外确认：

```text
uname -m = x86_64
downloaded artifact = darwin-x64
```

Apple Silicon PASS 不得替代 Intel PASS。

### After Any Shared Fix

如果真机发现明确缺陷，遵循：

```text
capture evidence
→ identify root cause
→ minimal patch
→ rerun failed Mac test
→ rerun tests/windows-check.ps1
```

在收到真实 Mac 验收输入前，停止继续开发。
