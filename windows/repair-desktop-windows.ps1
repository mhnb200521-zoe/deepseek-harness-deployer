$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot 'install-desktop-windows.ps1'
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    Write-Host '[FAIL] DSH-D004: 找不到桌面版安装器。' -ForegroundColor Red
    exit 1
}
Write-Host 'DeepSeek Harness Desktop Repair' -ForegroundColor Cyan
Write-Host '修复只会重跑与当前已安装版本一致、且通过 SHA-512 与签名校验的官方安装器。'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Repair
exit $LASTEXITCODE
