$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$installer = Join-Path $root 'windows\install-desktop-windows.ps1'
$entry = Join-Path $root 'windows\install-desktop-windows.cmd'
$repair = Join-Path $root 'windows\repair-desktop-windows.ps1'
$uninstall = Join-Path $root 'windows\uninstall-desktop-windows.ps1'
$webInstaller = Join-Path $root 'windows\install-windows.ps1'
$webUninstaller = Join-Path $root 'windows\uninstall-windows.ps1'

function Assert([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
    Write-Host "[PASS] $message" -ForegroundColor Green
}

$bytes = [IO.File]::ReadAllBytes($installer)
Assert ($bytes.Length -gt 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) 'Windows PowerShell 5.1 UTF-8 BOM'

$output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -SelfTest 2>&1
if ($LASTEXITCODE -ne 0) { $output | ForEach-Object { Write-Host $_ }; throw 'desktop installer self-test failed' }
Assert (($output -join "`n") -match 'desktop-windows selftest: PASS') 'desktop feed parser self-test'

$entryText = [IO.File]::ReadAllText($entry)
$moduleIsolation = $entryText.IndexOf('set "PSModulePath="', [StringComparison]::OrdinalIgnoreCase)
$powershellInvocation = $entryText.IndexOf('powershell -NoProfile', [StringComparison]::OrdinalIgnoreCase)
Assert ($moduleIsolation -ge 0 -and $powershellInvocation -gt $moduleIsolation) 'one-click entry isolates Windows PowerShell module path'

foreach ($scriptPath in @($repair, $uninstall)) {
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
    Assert ($errors.Count -eq 0) ("PowerShell 5.1 syntax: {0}" -f (Split-Path -Leaf $scriptPath))
}

$webText = [IO.File]::ReadAllText($webInstaller)
$uninstallText = [IO.File]::ReadAllText($webUninstaller)
Assert ($webText -match "DeepSeek Harness Web\.lnk") 'legacy Web installer uses a distinct shortcut name'
Assert ($uninstallText -match "Get-ShortcutTarget|CreateShortcut") 'legacy Web uninstaller validates shortcut ownership'
Assert ($uninstallText -notmatch 'Remove-Safe\s+\$lnk\s+''桌面快捷方式''') 'legacy Web uninstaller no longer deletes the native-app shortcut unconditionally'

Write-Host 'windows-desktop-check: PASS' -ForegroundColor Green
