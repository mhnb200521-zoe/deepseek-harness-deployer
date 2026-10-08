# Windows Desktop Acceptance Record — 2026-10-08

## Result

`PARTIAL_PASS`: the real one-click entry passes on the current Windows 11 x64 machine for the already-installed official app, including feed update checking, shortcut verification, launch, and visible UI confirmation. A clean first-time install is still `NOT TESTED`; this record does not claim cold-install PASS.

## Environment

- Windows 11 Home x64, build `10.0.26200`
- Windows PowerShell `5.1.26100.9444`
- Existing official DeepSeek Harness Desktop: `0.2.0-rc.2`
- The installed app is under the current user's `LocalAppData\Programs\DeepSeek Harness` and passed the installer's Authenticode publisher check.

## Tests performed

| Test | Result | Evidence |
|---|---|---|
| `tests/windows-desktop-check.ps1` | PASS, exit 0 | PowerShell 5.1 BOM/syntax, feed parser including UTF-8 byte response and invalid-byte rejection, module-path wrapper guard, shortcut coexistence assertions |
| `tests/windows-check.ps1` | PASS, exit 0 | Existing Web deployment regression and SelfTest all PASS |
| `windows/install-desktop-windows.cmd -ProbeOnly` | PASS, exit 0 | Real `.cmd` wrapper recognized signed `0.2.0-rc.2` without downloading, installing, or launching |
| `windows/install-desktop-windows.cmd` | PASS, exit 0 | Existing-install path verified signature, shortcut target, launch from the verified install path, and a visible/usable workspace UI |
| `windows/install-desktop-windows.cmd -Upgrade` | PASS, exit 0 | Live official feed: stable `latest.yml` returned HTTP 404; official `nightly.yml` returned `0.2.0-rc.2`; byte response decoded; same version reused without download/reinstall; UI confirmed |
| Package-only download / size / SHA-512 / Authenticode preflight | NOT TESTED | The extra temporary `.exe` download command was rejected by the execution policy as `blocked by policy`; no package was downloaded |

Latest successful upgrade-check log is stored under the current user's `LocalAppData\DeepSeekHarnessDesktopDeployer\logs` directory (filename: `install-20261008-204629-520aa8a9b54743bd809fe4a19e72a4a2.log`).

## Defects found and fixed

1. The one-click `.cmd` inherited a `PSModulePath` containing PowerShell 7 modules. Under this host's Codex shell, Windows PowerShell 5.1 then failed to load `Microsoft.PowerShell.Security` because extended type members were duplicated, producing `DSH-D999` during signature verification. The wrapper now clears `PSModulePath` only inside its `setlocal` scope; it does not persistently change the user's environment.
2. The official YAML feed is returned as `byte[]` by Windows PowerShell 5.1. The installer previously cast the bytes to a string of numbers and rejected the feed with `DSH-D002`. It now performs strict UTF-8 decoding and rejects invalid UTF-8. Regression coverage includes both valid byte content and invalid encoding.

## Remaining cold-install gap

The current account already has the official app, so the installer correctly takes its existing-install path. `-Upgrade` found the same version and skipped the actual package download and NSIS installer. Windows Sandbox, Hyper-V, VirtualBox, VMware, and QEMU were unavailable on this host. The existing app was not uninstalled to manufacture a test state.

Therefore these items remain `NOT TESTED`:

- First-install feed → package download → size/SHA-512 → Authenticode → native NSIS install → post-install registry/path verification.
- A clean Windows user/profile with an existing Web deployment and unknown/occupied shortcut negative cases.

Run those cases on a clean Windows x64 VM or a dedicated test machine before marking Windows cold-install acceptance complete.
