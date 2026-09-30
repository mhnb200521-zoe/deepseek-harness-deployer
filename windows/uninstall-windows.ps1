<#
    DeepSeek Harness — Uninstall (Windows, L3)
    Milestone: M2
    只删除本部署器创建的文件。绝不删除用户已有(系统)Node。
    - 私有 runtime 可安全删除
    - workspace 默认询问用户
    - logs 默认保留
    - 快捷方式删除
    用法: powershell -ExecutionPolicy Bypass -File uninstall-windows.ps1 [-InstallDir <路径>] [-Purge] [-Yes]
#>
[CmdletBinding()]
param(
    [string]$InstallDir = "",
    [switch]$Purge,      # 彻底删除(含 workspace 与 logs)
    [switch]$Yes         # 非交互:接受默认(保留 workspace/logs,除非 -Purge)
)
$ErrorActionPreference = 'Continue'

Write-Host ''
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host ' DeepSeek Harness — Uninstall' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host ''

# 定位安装目录
$root = $InstallDir
if (-not $root) {
    foreach ($cand in @('D:\DeepSeekHarness', (Join-Path $env:LOCALAPPDATA 'DeepSeekHarness'))) {
        if (Test-Path (Join-Path $cand 'config\deployer.json')) { $root = $cand; break }
    }
}
if (-not $root -or -not (Test-Path $root)) {
    Write-Host '  未找到 DeepSeek Harness 安装目录。可用 -InstallDir 指定。' -ForegroundColor Yellow
    exit 0
}
Write-Host ("  安装目录: {0}" -f $root)

# 读取 config 以确认 nodeMode(保护系统 Node)
$cfg = $null
try { $cfg = Get-Content -LiteralPath (Join-Path $root 'config\deployer.json') -Raw -ErrorAction Stop | ConvertFrom-Json } catch {}
if ($cfg -and $cfg.nodeMode -eq 'reuse') {
    Write-Host ("  检测到复用的系统 Node ({0}),将【不会】被删除。" -f $cfg.nodePath) -ForegroundColor Green
}

$script:RemoveFailures = @()

function Stop-OwnedHarnessProcesses([string]$InstallRoot) {
    # 只识别命令行同时指向本安装根目录、且明确属于 DSH/本项目 launcher 的进程。
    # 不按端口盲杀，也不按 node.exe 进程名盲杀。
    $rootMarker = [regex]::Escape(([IO.Path]::GetFullPath($InstallRoot)).TrimEnd('\'))
    $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $owned = @($all | Where-Object {
        $_.ProcessId -ne $PID -and $_.CommandLine -and
        $_.CommandLine -match $rootMarker -and
        (($_.CommandLine -match '(?i)@deepseek-ai[\\/]dsh') -or
         ($_.CommandLine -match '(?i)start-dsh\.ps1'))
    })

    if (-not $owned) {
        Write-Host '  [信息] 未发现属于本安装目录的运行中 Harness 进程。' -ForegroundColor Gray
        return
    }

    $ids = New-Object System.Collections.Generic.List[int]
    $queue = New-Object System.Collections.Generic.Queue[int]
    foreach ($p in $owned) { [void]$ids.Add([int]$p.ProcessId); $queue.Enqueue([int]$p.ProcessId) }
    while ($queue.Count -gt 0) {
        $parent = $queue.Dequeue()
        foreach ($child in ($all | Where-Object { $_.ParentProcessId -eq $parent })) {
            if (-not $ids.Contains([int]$child.ProcessId)) {
                [void]$ids.Add([int]$child.ProcessId)
                $queue.Enqueue([int]$child.ProcessId)
            }
        }
    }

    $ordered = @($ids | Sort-Object -Descending)
    foreach ($id in $ordered) {
        try {
            Stop-Process -Id $id -Force -ErrorAction Stop
            Write-Host ("  [停止] Harness 进程 PID {0}" -f $id) -ForegroundColor Gray
        } catch {
            Write-Host ("  [跳过] 无法停止已确认的 Harness 进程 PID {0}: {1}" -f $id, $_.Exception.Message) -ForegroundColor Yellow
        }
    }
    Start-Sleep -Milliseconds 500
}

function Remove-Safe([string]$path, [string]$label) {
    if (Test-Path $path) {
        try { Remove-Item $path -Recurse -Force -ErrorAction Stop; Write-Host ("  [删除] {0}" -f $label) -ForegroundColor Gray }
        catch { $script:RemoveFailures += $label; Write-Host ("  [跳过] {0} - {1}" -f $label, $_.Exception.Message) -ForegroundColor Yellow }
    }
}

# 先停止本安装目录拥有的 Harness，释放 cache/launcher 文件锁。
Stop-OwnedHarnessProcesses $root

# 只删除明确指向本安装 launcher 的快捷方式；保留官方桌面 App 或其他同名快捷方式。
$desktop = [Environment]::GetFolderPath('Desktop')
$ownedLauncher = [IO.Path]::GetFullPath((Join-Path $root 'launcher\start-dsh.cmd'))
$shell = $null
try {
    $shell = New-Object -ComObject WScript.Shell
    foreach ($name in @('DeepSeek Harness Web.lnk', 'DeepSeek Harness.lnk')) {
        $shortcutPath = Join-Path $desktop $name
        if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) { continue }
        try {
            $shortcutItem = Get-Item -LiteralPath $shortcutPath -Force -ErrorAction Stop
            if (($shortcutItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                Write-Host ("  [保留] 快捷方式是重解析点: {0}" -f $shortcutPath) -ForegroundColor Yellow
                continue
            }
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $target = [string]$shortcut.TargetPath
            if ($target -and [IO.Path]::IsPathRooted($target) -and
                [string]::Equals([IO.Path]::GetFullPath($target), $ownedLauncher, [StringComparison]::OrdinalIgnoreCase)) {
                Remove-Safe $shortcutPath '属于本安装的桌面快捷方式'
            } else {
                Write-Host ("  [保留] 快捷方式目标不属于本安装: {0}" -f $shortcutPath) -ForegroundColor Yellow
            }
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut)
        } catch {
            Write-Host ("  [保留] 无法验证快捷方式归属: {0}" -f $shortcutPath) -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host '  [保留] 无法验证快捷方式归属，因此没有删除任何快捷方式。' -ForegroundColor Yellow
} finally {
    if ($shell) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
}

# 删除私有 runtime(安全:仅本产品目录内)
Remove-Safe (Join-Path $root 'runtime') '私有 Node Runtime'
# 删除 launcher / cache / config
Remove-Safe (Join-Path $root 'launcher') '启动器'
Remove-Safe (Join-Path $root 'cache') '缓存'

# workspace 处理(用户数据,谨慎)
$wsPath = Join-Path $root 'workspace'
$removeWs = $false
if ($Purge) { $removeWs = $true }
elseif (-not $Yes -and (Test-Path $wsPath)) {
    $ans = Read-Host '  是否删除 workspace(可能含你的项目文件)? [y/N]'
    if ($ans -match '^(y|Y)') { $removeWs = $true }
}
if ($removeWs) { Remove-Safe $wsPath 'workspace' }
elseif (Test-Path $wsPath) { Write-Host '  [保留] workspace(用户数据)' -ForegroundColor Green }

# logs 处理(默认保留)
$logPath = Join-Path $root 'logs'
if ($Purge) { Remove-Safe $logPath '日志' }
elseif (Test-Path $logPath) { Write-Host '  [保留] logs(如需彻底清除请加 -Purge)' -ForegroundColor Green }

# config
Remove-Safe (Join-Path $root 'config') '配置'

# 若目录已空则删除根
try {
    if ((Get-ChildItem -Path $root -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
        Remove-Item $root -Force -ErrorAction SilentlyContinue
        Write-Host ("  [删除] 空的安装根目录 {0}" -f $root) -ForegroundColor Gray
    }
} catch {}

Write-Host ''
if ($script:RemoveFailures.Count -gt 0) {
    Write-Host ("  卸载未完全完成，仍有 {0} 项无法删除。请关闭相关程序后重试。" -f $script:RemoveFailures.Count) -ForegroundColor Yellow
    Write-Host '  用户系统 Node 未被改动。' -ForegroundColor Yellow
    exit 1
}
Write-Host '  卸载完成。用户系统 Node 未被改动。' -ForegroundColor Green
Write-Host ''
exit 0
