# M5 macOS Intel Real Hardware Acceptance

状态：`NOT TESTED`

原因：当前 Codex 执行环境为 Windows，没有可用的 Intel Mac。Apple Silicon 的结果不能替代 Intel 验收；此文件只记录测试方法和未测试状态。

## 测试环境

```text
MACOS ACCEPTANCE ENVIRONMENT

Date: NOT TESTED
Machine: NOT AVAILABLE
macOS version: NOT TESTED
Architecture: NOT TESTED (expected x86_64)
Shell: NOT TESTED
Existing Node: NOT TESTED
Existing npm: NOT TESTED
Existing npx: NOT TESTED
Install root exists before test: NOT TESTED
Existing DSH process: NOT TESTED
Port 3080 initial state: NOT TESTED
```

在 Intel Mac 上开始测试前执行并保存：

```bash
sw_vers
uname -m
which node || true
node -v || true
which npm || true
npm -v || true
which npx || true
lsof -i :3080 || true
```

## Acceptance Gate

以下各项在真实 x86_64 Mac 上全部 PASS 后，才能把本文件状态改为 `PASS`：

```text
[ ] x86_64 detected
[ ] darwin-x64 Node artifact selected
[ ] official Node source and SHASUMS256 verified
[ ] private runtime works
[ ] npm works
[ ] npx works
[ ] @deepseek-ai/dsh package reachable and downloaded
[ ] Harness starts with web --no-open semantics
[ ] Harness PID recorded
[ ] actual Web URL captured
[ ] token/query preserved, report only Token present: YES/NO
[ ] HTTP verification PASS
[ ] browser open PASS
[ ] ~/DeepSeekHarness/workspace exists
[ ] ~/DeepSeekHarness/DeepSeek Harness.command works by double-click
[ ] repeated install PASS
[ ] Repair PASS and Diagnostic Report generated
[ ] default Uninstall removes product files and preserves workspace/logs
[ ] safety guard refuses untrusted directory with DSH-E010
[ ] --purge --yes removes only owned product data
[ ] token log scan PASS
[ ] Windows regression after any shared change PASS
```

## Evidence rules

只记录 URL source、Token present、Host、port、HTTP status、版本和报告路径。不得记录完整 token、API Key、Cookie、密码或用户聊天内容。

## 当前可引用的宿主机静态证据

这些证据不等于 x86_64 真机通过：

- `bash -n`：macOS 脚本全部 PASS。
- `tests/macos-check.sh`：`PASS=9 WARN=1 FAIL=0`；WARN 表示当前不是 macOS。
- Windows 回归：`tests/windows-check.ps1` 退出码 0。
