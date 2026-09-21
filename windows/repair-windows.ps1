<#
    DeepSeek Harness — Repair / 诊断 (Windows, L3)
    Milestone: M2
    只读为主:检测 Node/npm/npx/registry/DSH/launcher/shortcut/port,生成诊断报告。
    用法: powershell -ExecutionPolicy Bypass -File repair-windows.ps1 [-InstallDir <路径>]
#>
[CmdletBinding()]
param(
    [string]$InstallDir = ""
)
$ErrorActionPreference = 'Continue'

$DSH_PACKAGE = '@deepseek-ai/dsh'
$results = @()
function Add-Check([string]$name, [string]$status, [string]$detail='') {
    $script:results += [pscustomobject]@{ item=$name; status=$status; detail=$detail }
    $color = switch ($status) { 'PASS' {'Green'} 'WARN' {'Yellow'} 'FAIL' {'Red'} default {'Gray'} }
    Write-Host ("  [{0}] {1} {2}" -f $status.PadRight(4), $name, $(if($detail){"- $detail"}else{''})) -ForegroundColor $color
}
function Test-NodeCompatible([string]$v) {
    if ($v -match '^v?(\d+)\.(\d+)\.(\d+)') {
        $maj=[int]$Matches[1]; $min=[int]$Matches[2]
        if ($maj -eq 22 -and $min -ge 19) { return $true }
        if ($maj -ge 24) { return $true }
    }
    return $false
}
function Test-PortListening([int]$p) {
    $c = New-Object System.Net.Sockets.TcpClient
    try { $ia=$c.BeginConnect('127.0.0.1',$p,$null,$null); if ($ia.AsyncWaitHandle.WaitOne(500,$false) -and $c.Connected){ $c.EndConnect($ia); return $true }; return $false }
    catch { return $false } finally { $c.Close() }
}

Write-Host ''
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host ' DeepSeek Harness — Diagnostic (Repair)' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host ''

# 定位安装目录 / config
$cfg = $null
$root = $InstallDir
if (-not $root) {
    foreach ($cand in @('D:\DeepSeekHarness', (Join-Path $env:LOCALAPPDATA 'DeepSeekHarness'))) {
        if (Test-Path (Join-Path $cand 'config\deployer.json')) { $root = $cand; break }
    }
}
if ($root -and (Test-Path (Join-Path $root 'config\deployer.json'))) {
    try { $cfg = Get-Content -Raw (Join-Path $root 'config\deployer.json') | ConvertFrom-Json } catch {}
    Add-Check 'Install config' 'PASS' $root
} else {
    Add-Check 'Install config' 'WARN' '未找到 deployer.json,按系统环境诊断'
}

$port = if ($cfg -and $cfg.port) { [int]$cfg.port } else { 3080 }

# Node
$nodeExe = if ($cfg -and $cfg.nodePath -and (Test-Path $cfg.nodePath)) { $cfg.nodePath } else { 'node' }
$nv = $null; try { $nv = (& $nodeExe -v) 2>$null } catch {}
if ($nv -and (Test-NodeCompatible $nv)) { Add-Check 'Node.js' 'PASS' ("{0} ({1})" -f $nv.Trim(), $(if($cfg){$cfg.nodeMode}else{'system'})) }
elseif ($nv) { Add-Check 'Node.js' 'WARN' ("{0} 不满足兼容基线" -f $nv.Trim()) }
else { Add-Check 'Node.js' 'FAIL' 'node 不可用 (DSH-E003)' }

# npm / npx
$nodeDir = if ($nodeExe -ne 'node') { Split-Path $nodeExe } else { '' }
$npm = if ($nodeDir -and (Test-Path (Join-Path $nodeDir 'npm.cmd'))) { Join-Path $nodeDir 'npm.cmd' } else { 'npm' }
$npx = if ($nodeDir -and (Test-Path (Join-Path $nodeDir 'npx.cmd'))) { Join-Path $nodeDir 'npx.cmd' } else { 'npx' }
$npmv = $null; try { $npmv = (& $npm -v) 2>$null } catch {}
if ($npmv) { Add-Check 'npm' 'PASS' $npmv.Trim() } else { Add-Check 'npm' 'FAIL' 'npm 不可用 (DSH-E003)' }
if (Test-Path (Join-Path $nodeDir 'npx.cmd')) { Add-Check 'npx' 'PASS' } elseif ((Get-Command npx -ErrorAction SilentlyContinue)) { Add-Check 'npx' 'PASS' 'system' } else { Add-Check 'npx' 'WARN' '未定位 npx' }

# registry + DSH
$ver = $null
try { $out = (& $npm view $DSH_PACKAGE version) 2>&1; foreach ($l in @($out)) { if ("$l" -match '(\d+\.\d+\.\d+(?:-[0-9A-Za-z.\-]+)?)') { $ver=$Matches[1]; break } } } catch {}
if ($ver) { Add-Check 'npm registry' 'PASS'; Add-Check "$DSH_PACKAGE" 'PASS' ("reachable, latest {0}" -f $ver) }
else { Add-Check 'npm registry' 'FAIL' '软件源/包不可达 (DSH-E004/E005)'; }

# launcher
if ($root -and (Test-Path (Join-Path $root 'launcher\start-dsh.cmd'))) { Add-Check 'Launcher' 'PASS' (Join-Path $root 'launcher\start-dsh.cmd') }
else { Add-Check 'Launcher' 'WARN' '启动器缺失,重跑安装器可重建' }

# shortcut
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'DeepSeek Harness.lnk'
if (Test-Path $lnk) { Add-Check 'Desktop Shortcut' 'PASS' } else { Add-Check 'Desktop Shortcut' 'WARN' '快捷方式缺失 (DSH-E008)' }

# port
if (Test-PortListening $port) { Add-Check ("Port {0}" -f $port) 'PASS' '已监听(Harness 可能在运行)' }
else { Add-Check ("Port {0}" -f $port) 'WARN' '未监听(Harness 未启动)' }

# 生成报告
Write-Host ''
$pass=($results|?{$_.status -eq 'PASS'}).Count; $warn=($results|?{$_.status -eq 'WARN'}).Count; $fail=($results|?{$_.status -eq 'FAIL'}).Count
Write-Host ("Summary: PASS={0} WARN={1} FAIL={2}" -f $pass,$warn,$fail) -ForegroundColor Cyan
if ($root) {
    $rep = Join-Path $root ("logs\diagnostic-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    try {
        $lines = @("DeepSeek Harness Diagnostic Report", (Get-Date -Format 'o'), "InstallRoot: $root", "")
        $lines += ($results | ForEach-Object { ("[{0}] {1} {2}" -f $_.status, $_.item, $_.detail) })
        Set-Content -Path $rep -Value $lines -Encoding UTF8
        Write-Host ("诊断报告已保存: {0}" -f $rep) -ForegroundColor Gray
        Write-Host '如需售后支持,请把该报告发给技术人员。' -ForegroundColor Yellow
    } catch {}
}
Write-Host ''
if ($fail -gt 0) { exit 1 } else { exit 0 }
