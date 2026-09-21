# M5 Cross-platform Real Hardware Release Gate

日期：2026-09-21

## 当前总状态

```text
MILESTONE:
M5 Cross-platform Real Hardware Validation

STATUS:
PARTIAL

WINDOWS:
PASS

APPLE SILICON:
NOT TESTED

INTEL MAC:
NOT TESTED
```

## Windows

状态：`PASS`

证据：

- `tests/windows-check.ps1` 退出码 0。
- Node 22/24/25 兼容判定和 Node 20/23 不兼容判定全部 PASS。
- Get-DshUrl 实测断言 PASS，包含 detected、fallback、path/query 保留和 token 脱敏。
- Windows Token URL 冷启动日志：

  ```text
  C:\Users\Lenovo\dsh-token-fix-test\logs\install-20260920-183614.log
  ```

  仅记录以下非机密证据：

  ```text
  urlSource=detected tokenPresent=True port=3080 httpStatus=200
  URL=detected, token preserved=YES
  ```

- 完整 token 扫描 PASS。

## Apple Silicon

状态：`NOT TESTED`

阻塞原因：当前没有可用 Apple Silicon Mac。必须先完成 [macos-arm64.md](macos-arm64.md) 中的真实安装、启动、URL、浏览器、Repair、Uninstall、Safety Guard、Purge 和日志安全测试。

## Intel Mac

状态：`NOT TESTED`

阻塞原因：当前没有可用 Intel Mac。必须先完成 [macos-x86_64.md](macos-x86_64.md) 中的真实安装、启动、URL、浏览器、Repair、Uninstall、Safety Guard、Purge 和日志安全测试。

## Feature Freeze 规则

在真实 Mac 测试开始后：

```text
Test → Diagnose → Minimal Fix → Retest
```

除非真机证据确认明确缺陷，否则不得重构目录架构、修改 Windows 已通过模块、新增非必要功能或重构错误码体系。

如果真机修复触及 shared config、README、错误码或版本策略，必须重新执行：

```powershell
powershell -ExecutionPolicy Bypass -File tests/windows-check.ps1
```

## Release Blockers

当前阻塞正式发布的项目：

1. 缺少 Apple Silicon 真机验收证据。
2. 缺少 Intel Mac 真机验收证据。
3. 缺少至少一台 Mac 上的真实 Node 下载、SHA256、npx、端口、浏览器 `open` 和卸载进程树证据。

因此当前不能输出：

```text
Cross-platform validation = PASS
```

只有满足：

```text
Windows PASS
+ Apple Silicon PASS
+ Intel PASS
```

才允许把 M5 标记为 `completed`，并进入最终交付关闭流程。
