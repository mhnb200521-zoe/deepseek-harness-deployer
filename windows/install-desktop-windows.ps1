<# Official DeepSeek Harness Desktop installer. Legacy Web installer remains separate. #>
param([switch]$Upgrade, [switch]$Repair, [switch]$ProbeOnly, [switch]$SelfTest)
$ErrorActionPreference = 'Stop'
$script:stage = 'Init'
$script:logPath = $null
$script:origin = 'https://download.deepseek.com'
$script:publisher = 'Hangzhou DeepSeek Artificial Intelligence Co., Ltd.'

function Write-Event([string]$level, [string]$message) {
    $safe = $message -replace '(?i)(token|api[_-]?key|password|cookie|authorization)\s*[:=]\s*\S+', '$1=[REDACTED]'
    $safe = $safe -replace '(?i)sk-[A-Za-z0-9_-]+', '[REDACTED]'
    Write-Host ('[{0}] {1}' -f $level, $safe)
    if ($script:logPath) {
        Add-Content -LiteralPath $script:logPath -Encoding UTF8 -Value ('{0} [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $level, $script:stage, $safe)
    }
}
function Stop-Desktop([string]$id, [string]$message) {
    throw ('{0}: {1}' -f $id, $message)
}
function Ensure-UserDirectory([string]$path, [string]$label) {
    $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if ($item) {
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Stop-Desktop 'DSH-D010' ("{0} 不是普通目录或属于重解析点；为保护路径外文件已停止。" -f $label)
        }
        return
    }
    New-Item -ItemType Directory -Path $path -ErrorAction Stop | Out-Null
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Stop-Desktop 'DSH-D010' ("{0} 无法验证为普通目录。" -f $label)
    }
}
function Test-OfficialSignature([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    $signature = Get-AuthenticodeSignature -LiteralPath $path
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) { return $false }
    $subject = $signature.SignerCertificate.Subject
    $hasCommonName = $subject.IndexOf(('CN="' + $script:publisher + '"'), [StringComparison]::OrdinalIgnoreCase) -ge 0
    $hasOrganization = $subject.IndexOf(('O="' + $script:publisher + '"'), [StringComparison]::OrdinalIgnoreCase) -ge 0
    $hasCountry = $subject.IndexOf('C=CN', [StringComparison]::OrdinalIgnoreCase) -ge 0
    return ($hasCommonName -and $hasOrganization -and $hasCountry)
}
function Get-InstalledDesktop {
    $base = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    $found = $null
    foreach ($key in Get-ChildItem -Path $base -ErrorAction SilentlyContinue) {
        $entry = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        if ($entry -and [string]$entry.DisplayName -like 'DeepSeek Harness*' -and $entry.InstallLocation) {
            $app = Join-Path ([string]$entry.InstallLocation) 'DeepSeek Harness.exe'
            if (-not (Test-OfficialSignature $app)) {
                Stop-Desktop 'DSH-D004' '发现同名安装，但应用签名或发行者不匹配；为避免覆盖已停止。'
            }
            if ($found) { Stop-Desktop 'DSH-D004' '发现多个已注册的桌面端，无法安全确定安装目标。' }
            $found = [pscustomobject]@{ Version = [string]$entry.DisplayVersion; Path = $app; Location = [string]$entry.InstallLocation }
        }
    }
    return $found
}
function Get-ShortcutTarget([string]$shortcutPath) {
    $shell = $null
    $shortcut = $null
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        return [string]$shortcut.TargetPath
    } catch {
        return $null
    } finally {
        if ($shortcut) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) }
        if ($shell) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
    }
}
function Assert-NotReparsePoint([string]$path, [string]$label) {
    $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return }
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Stop-Desktop 'DSH-D008' ("{0} 是重解析点；为保护路径外文件，已停止。" -f $label)
    }
}
function Test-RegisteredWebLauncher([string]$target) {
    if (-not $target -or -not [IO.Path]::IsPathRooted($target)) { return $false }
    try {
        $fullTarget = [IO.Path]::GetFullPath($target)
        if ([IO.Path]::GetFileName($fullTarget) -ine 'start-dsh.cmd' -or [IO.Path]::GetDirectoryName($fullTarget) -notmatch '(?i)\\launcher$') { return $false }
        $root = [IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($fullTarget))
        $configPath = Join-Path $root 'config\deployer.json'
        if (-not (Test-Path -LiteralPath $fullTarget -PathType Leaf) -or -not (Test-Path -LiteralPath $configPath -PathType Leaf)) { return $false }
        Assert-NotReparsePoint $fullTarget '旧 Web 启动器'
        Assert-NotReparsePoint $root '旧 Web 安装目录'
        Assert-NotReparsePoint $configPath '旧 Web 配置'
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $configuredRoot = [IO.Path]::GetFullPath([string]$config.installRoot)
        return [string]::Equals($configuredRoot, $root, [StringComparison]::OrdinalIgnoreCase)
    } catch {
        return $false
    }
}
function Prepare-DesktopShortcut([object]$installed) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $appShortcut = Join-Path $desktop 'DeepSeek Harness.lnk'
    $webShortcut = Join-Path $desktop 'DeepSeek Harness Web.lnk'
    if (-not (Test-Path -LiteralPath $appShortcut)) { return }
    Assert-NotReparsePoint $appShortcut '桌面快捷方式'
    if (-not (Test-Path -LiteralPath $appShortcut -PathType Leaf)) {
        Stop-Desktop 'DSH-D008' 'DeepSeek Harness 快捷方式路径被非文件对象占用；未覆盖。'
    }
    $target = Get-ShortcutTarget $appShortcut
    if ($installed -and $target -and [IO.Path]::IsPathRooted($target) -and
        [string]::Equals([IO.Path]::GetFullPath($target), [IO.Path]::GetFullPath($installed.Path), [StringComparison]::OrdinalIgnoreCase)) {
        return
    }
    if (-not (Test-RegisteredWebLauncher $target)) {
        Stop-Desktop 'DSH-D008' '桌面已有同名快捷方式，且无法确认它属于旧 Web 部署器；为避免覆盖其他程序，已停止。'
    }
    if (Test-Path -LiteralPath $webShortcut) {
        Assert-NotReparsePoint $webShortcut 'Web 桌面快捷方式'
        if (-not (Test-Path -LiteralPath $webShortcut -PathType Leaf)) {
            Stop-Desktop 'DSH-D008' 'DeepSeek Harness Web 快捷方式路径被非文件对象占用；未覆盖。'
        }
        $webTarget = Get-ShortcutTarget $webShortcut
        if (-not $webTarget -or -not [string]::Equals([IO.Path]::GetFullPath($webTarget), [IO.Path]::GetFullPath($target), [StringComparison]::OrdinalIgnoreCase)) {
            Stop-Desktop 'DSH-D008' 'DeepSeek Harness Web 快捷方式已被其他目标占用；未覆盖任何快捷方式。'
        }
    } else {
        try {
            Copy-Item -LiteralPath $appShortcut -Destination $webShortcut -ErrorAction Stop
            $copiedTarget = Get-ShortcutTarget $webShortcut
            if (-not $copiedTarget -or -not [string]::Equals([IO.Path]::GetFullPath($copiedTarget), [IO.Path]::GetFullPath($target), [StringComparison]::OrdinalIgnoreCase)) {
                Remove-Item -LiteralPath $webShortcut -Force -ErrorAction SilentlyContinue
                Stop-Desktop 'DSH-D008' '无法可靠保留旧 Web 快捷方式；已停止安装。'
            }
        } catch {
            if ($_.Exception.Message -match '^DSH-D008:') { throw }
            Stop-Desktop 'DSH-D008' '无法备份旧 Web 快捷方式；已停止安装。'
        }
    }
    Write-Event PASS '旧 Web 快捷方式已保留为 DeepSeek Harness Web.lnk。'
}
function Ensure-DesktopAppShortcut([object]$installed) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop 'DeepSeek Harness.lnk'
    if (Test-Path -LiteralPath $shortcutPath) {
        Assert-NotReparsePoint $shortcutPath '桌面快捷方式'
        if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
            Stop-Desktop 'DSH-D008' 'DeepSeek Harness 快捷方式路径被非文件对象占用；未覆盖。'
        }
        $existingTarget = Get-ShortcutTarget $shortcutPath
        if ($existingTarget -and [IO.Path]::IsPathRooted($existingTarget) -and
            [string]::Equals([IO.Path]::GetFullPath($existingTarget), [IO.Path]::GetFullPath($installed.Path), [StringComparison]::OrdinalIgnoreCase)) {
            Write-Event PASS '桌面快捷方式指向已验证的官方桌面应用。'
            return
        }
        if (-not (Test-RegisteredWebLauncher $existingTarget)) {
            Stop-Desktop 'DSH-D008' '官方安装后发现同名快捷方式目标异常；未覆盖该快捷方式。'
        }
    }
    $shell = $null
    $shortcut = $null
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $installed.Path
        $shortcut.WorkingDirectory = $installed.Location
        $shortcut.Description = 'DeepSeek Harness Desktop'
        $shortcut.Save()
        $verifiedTarget = Get-ShortcutTarget $shortcutPath
        if (-not $verifiedTarget -or -not [string]::Equals([IO.Path]::GetFullPath($verifiedTarget), [IO.Path]::GetFullPath($installed.Path), [StringComparison]::OrdinalIgnoreCase)) {
            Stop-Desktop 'DSH-D008' '无法验证桌面快捷方式目标。'
        }
        Write-Event PASS '官方桌面版快捷方式已创建并验证。'
    } catch {
        if ($_.Exception.Message -match '^DSH-D008:') { throw }
        Stop-Desktop 'DSH-D008' '创建官方桌面版快捷方式失败。'
    } finally {
        if ($shortcut) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) }
        if ($shell) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
    }
}
function ConvertFrom-DesktopFeed([string]$body, [string]$channel) {
    $version = [regex]::Match($body, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?)\s*$').Groups[1].Value
    $path = [regex]::Match($body, '(?m)^path:\s*>-\s*\r?\n\s*(https://\S+)\s*$').Groups[1].Value
    $firstUrl = [regex]::Match($body, '(?m)^\s+- url:\s*>-\s*\r?\n\s*(https://\S+)\s*$').Groups[1].Value
    $sha = [regex]::Match($body, '(?m)^sha512:\s*>-\s*\r?\n\s*([A-Za-z0-9+/]{86}==)\s*$').Groups[1].Value
    $firstSha = [regex]::Match($body, '(?m)^\s+sha512:\s*>-\s*\r?\n\s*([A-Za-z0-9+/]{86}==)\s*$').Groups[1].Value
    $sizeText = [regex]::Match($body, '(?m)^\s+size:\s*([0-9]+)\s*$').Groups[1].Value
    if (-not $version -or -not $path -or $firstUrl -ne $path -or -not $sha -or $firstSha -ne $sha -or -not $sizeText) {
        Stop-Desktop 'DSH-D002' '官方版本清单字段缺失或不一致。'
    }
    $uri = [uri]$path
    $expectedPath = '/dsh-desk/bin/win-x64/deepseek-harness-{0}-win-x64.exe' -f $version
    if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'download.deepseek.com' -or $uri.AbsolutePath -cne $expectedPath -or $uri.Query -or $uri.Fragment) {
        Stop-Desktop 'DSH-D002' '官方版本清单包含非预期下载地址。'
    }
    $size = [long]$sizeText
    if ($size -lt 1000000) { Stop-Desktop 'DSH-D002' '官方版本清单的文件大小异常。' }
    return [pscustomobject]@{ Version=$version; Url=$path; Size=$size; Sha512=$sha; Channel=$channel }
}
function ConvertFrom-FeedContent([object]$content) {
    if ($content -is [string]) { return $content }
    if ($content -isnot [byte[]]) { Stop-Desktop 'DSH-D002' '官方版本清单响应类型无效。' }
    try {
        return [System.Text.UTF8Encoding]::new($false, $true).GetString($content)
    } catch {
        Stop-Desktop 'DSH-D002' '官方版本清单不是有效的 UTF-8 文本。'
    }
}
function Read-Feed([string]$channel) {
    if ($channel -eq 'stable') { $feedName = 'latest.yml' } else { $feedName = 'nightly.yml' }
    $feedUrl = '{0}/dsh-desk/feeds/win-x64/{1}' -f $script:origin, $feedName
    try {
        $response = Invoke-WebRequest -Uri $feedUrl -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 25
    } catch {
        $status = 0
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        if ($channel -eq 'stable' -and $status -eq 404) { return $null }
        Stop-Desktop 'DSH-D001' ('官方 {0} 版本清单不可用（HTTP {1}）；不会自动改用其他来源。' -f $channel, $status)
    }
    $body = ConvertFrom-FeedContent $response.Content
    return (ConvertFrom-DesktopFeed $body $channel)
}
function Test-FeedParser {
    $example = @'
version: 0.2.0-rc.2
files:
  - url: >-
      https://download.deepseek.com/dsh-desk/bin/win-x64/deepseek-harness-0.2.0-rc.2-win-x64.exe
    sha512: >-
      raIlxMQd9ESXgktmViW7QwVLcjBR5JIsrNOu+SpelY8kskdSr2H51/f+ey1EqFI/eIIrKQCuRANMeb5SptRZcg==
    size: 289313640
path: >-
  https://download.deepseek.com/dsh-desk/bin/win-x64/deepseek-harness-0.2.0-rc.2-win-x64.exe
sha512: >-
  raIlxMQd9ESXgktmViW7QwVLcjBR5JIsrNOu+SpelY8kskdSr2H51/f+ey1EqFI/eIIrKQCuRANMeb5SptRZcg==
'@
    $parsed = ConvertFrom-DesktopFeed $example 'nightly'
    if ($parsed.Version -ne '0.2.0-rc.2' -or $parsed.Size -ne 289313640 -or $parsed.Sha512.Length -ne 88) { throw 'feed field parser failed' }
    $exampleBytes = [System.Text.UTF8Encoding]::new($false, $true).GetBytes($example)
    $decoded = ConvertFrom-FeedContent $exampleBytes
    $parsedBytes = ConvertFrom-DesktopFeed $decoded 'nightly'
    if ($parsedBytes.Version -ne $parsed.Version -or $parsedBytes.Url -ne $parsed.Url -or $parsedBytes.Sha512 -ne $parsed.Sha512) { throw 'UTF-8 byte response parsing failed' }
    $rejected = $false
    try { $null = ConvertFrom-FeedContent ([byte[]]@(0xC3, 0x28)) } catch { $rejected = $true }
    if (-not $rejected) { throw 'invalid UTF-8 response was accepted' }
    $badHost = $example.Replace('download.deepseek.com', 'attacker.example')
    $rejected = $false
    try { $null = ConvertFrom-DesktopFeed $badHost 'nightly' } catch { $rejected = $true }
    if (-not $rejected) { throw 'foreign host was accepted' }
    $badArch = $example.Replace('win-x64', 'win-arm64')
    $rejected = $false
    try { $null = ConvertFrom-DesktopFeed $badArch 'nightly' } catch { $rejected = $true }
    if (-not $rejected) { throw 'wrong architecture was accepted' }

    Test-VersionNotOlder '0.2.0-rc.2' '0.2.0-rc.1'
    Test-VersionNotOlder '0.2.0' '0.2.0-rc.2'
    $rejected = $false
    try { Test-VersionNotOlder '0.2.0-rc.1' '0.2.0-rc.2' } catch { $rejected = $true }
    if (-not $rejected) { throw 'version downgrade was accepted' }
    if ((ConvertFrom-WmiArchitecture 9) -ne 'AMD64' -or (ConvertFrom-WmiArchitecture 12) -ne 'ARM64' -or (ConvertFrom-WmiArchitecture 0) -ne 'x86') {
        throw 'WMI architecture mapping failed'
    }

    $fixture = Join-Path ([IO.Path]::GetTempPath()) ('DeepSeekHarnessDesktopDeployer-Test-' + [guid]::NewGuid().ToString('N'))
    try {
        $launcherDir = Join-Path $fixture 'launcher'
        $configDir = Join-Path $fixture 'config'
        New-Item -ItemType Directory -Path $launcherDir,$configDir -Force | Out-Null
        $launcher = Join-Path $launcherDir 'start-dsh.cmd'
        $configPath = Join-Path $configDir 'deployer.json'
        [IO.File]::WriteAllText($launcher, '')
        @{ installRoot=$fixture } | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
        if (-not (Test-RegisteredWebLauncher $launcher)) { throw 'registered Web launcher was not recognized' }
        @{ installRoot=(Join-Path $fixture 'other') } | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
        if (Test-RegisteredWebLauncher $launcher) { throw 'unowned Web launcher was accepted' }
    } finally {
        if ($fixture -like (([IO.Path]::GetTempPath()).TrimEnd('\') + '\DeepSeekHarnessDesktopDeployer-Test-*')) {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host 'desktop-windows selftest: PASS (feed, UTF-8 response, host, architecture, version order, Web ownership)'
}
function Get-Sha512Base64([string]$path) {
    $stream = [System.IO.File]::OpenRead($path)
    try {
        $hasher = [System.Security.Cryptography.SHA512]::Create()
        try { return [Convert]::ToBase64String($hasher.ComputeHash($stream)) }
        finally { $hasher.Dispose() }
    } finally { $stream.Dispose() }
}
function Test-VersionNotOlder([string]$candidate, [string]$installed) {
    $a = [regex]::Match($candidate, '^(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta|rc)\.(\d+))?$')
    $b = [regex]::Match($installed, '^(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta|rc)\.(\d+))?$')
    if (-not $a.Success -or -not $b.Success) { Stop-Desktop 'DSH-D004' '已安装版本无法安全比较；请使用官方客户端更新。' }
    for ($i=1; $i -le 3; $i++) {
        $av=[int]$a.Groups[$i].Value; $bv=[int]$b.Groups[$i].Value
        if ($av -gt $bv) { return }
        if ($av -lt $bv) { Stop-Desktop 'DSH-D004' '目标版本低于已安装版本，已阻止降级。' }
    }
    $rank=@{ alpha=0; beta=1; rc=2; stable=3 }
    if ($a.Groups[4].Success) { $at=$a.Groups[4].Value } else { $at='stable' }
    if ($b.Groups[4].Success) { $bt=$b.Groups[4].Value } else { $bt='stable' }
    if ($rank[$at] -lt $rank[$bt] -or ($rank[$at] -eq $rank[$bt] -and [int]$a.Groups[5].Value -lt [int]$b.Groups[5].Value)) {
        Stop-Desktop 'DSH-D004' '目标版本低于已安装版本，已阻止降级。'
    }
}
function ConvertFrom-WmiArchitecture([int]$architecture) {
    switch ($architecture) {
        0 { return 'x86' }
        5 { return 'ARM' }
        9 { return 'AMD64' }
        12 { return 'ARM64' }
        default { return 'unknown' }
    }
}
function Get-NativeArchitecture {
    if ($env:PROCESSOR_ARCHITEW6432) { return [string]$env:PROCESSOR_ARCHITEW6432 }
    if ($env:PROCESSOR_ARCHITECTURE -in @('AMD64', 'ARM64')) { return [string]$env:PROCESSOR_ARCHITECTURE }
    try {
        $processor = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($processor) { return (ConvertFrom-WmiArchitecture ([int]$processor.Architecture)) }
    } catch {}
    if ($env:PROCESSOR_ARCHITECTURE) { return [string]$env:PROCESSOR_ARCHITECTURE }
    return 'unknown'
}
function Start-And-Verify([string]$app) {
    $script:stage='Launch'
    Start-Process -FilePath $app
    $deadline=(Get-Date).AddSeconds(70)
    do {
        foreach ($p in @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue)) {
            if ($p.Path -eq $app -and $p.MainWindowHandle -ne 0) {
                Write-Event PASS '已从已验证安装路径启动原生桌面窗口。'
                $answer=Read-Host '请确认窗口中可看到并操作欢迎页或工作区 [y/N]'
                if ($answer -notmatch '^(y|Y)$') { Stop-Desktop 'DSH-D006' '桌面 UI 未经用户确认，安装不能标记完成。' }
                Write-Event PASS '用户确认桌面 UI 可操作。'
                return
            }
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    Stop-Desktop 'DSH-D006' '应用已请求启动，但没有检测到属于该安装路径的可见窗口。'
}

try {
    if ($SelfTest) { Test-FeedParser; exit 0 }
    $nativeArch = Get-NativeArchitecture
    if (-not [Environment]::Is64BitOperatingSystem -or $nativeArch -notin @('AMD64', 'x64')) {
        Stop-Desktop 'DSH-D009' '官方桌面版目前仅发布 Windows x64 安装包，本机架构未通过支持验证。'
    }
    if (-not $env:LOCALAPPDATA -or -not (Test-Path -LiteralPath $env:LOCALAPPDATA -PathType Container)) {
        Stop-Desktop 'DSH-D010' '当前用户 LocalAppData 目录不可用。'
    }
    $base=Join-Path $env:LOCALAPPDATA 'DeepSeekHarnessDesktopDeployer'
    $logs=Join-Path $base 'logs'
    $cache=Join-Path $base 'cache'
    Ensure-UserDirectory $base '部署器数据目录'
    Ensure-UserDirectory $logs '日志目录'
    Ensure-UserDirectory $cache '下载缓存目录'
    $script:logPath=Join-Path $logs ('install-{0}-{1}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N'))
    $logStream = $null
    try { $logStream = [IO.File]::Open($script:logPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read); $logStream.Dispose() }
    catch { Stop-Desktop 'DSH-D010' '无法安全创建部署器日志文件。' }
    $script:stage='InstalledProbe'
    Write-Event INFO ('DeepSeek Harness 官方桌面端安装器；Windows {0} x64（Web 部署器仍单独保留）' -f $nativeArch)
    $existing=Get-InstalledDesktop
    if ($existing) { Write-Event PASS ('检测到已签名桌面端版本 {0}。' -f $existing.Version) }
    if ($ProbeOnly) {
        if (-not $existing) { Stop-Desktop 'DSH-D004' '本机尚未安装官方桌面端。' }
        Write-Event PASS '只读探测完成；未下载、安装或启动应用。'
        exit 0
    }
    if ($Repair -and -not $existing) { Stop-Desktop 'DSH-D004' '未发现可验证的官方桌面安装；修复模式不会安装未知/缺失应用。' }
    if ($existing -and -not $Upgrade -and -not $Repair) {
        Write-Event PASS '复用现有安装。如需检查官方更新，请重新运行并加 -Upgrade。'
        Prepare-DesktopShortcut $existing
        Ensure-DesktopAppShortcut $existing
        Start-And-Verify $existing.Path
        exit 0
    }
    $script:stage='Feed'
    $feed=Read-Feed stable
    if (-not $feed) {
        Write-Event WARN '官方稳定版清单不存在（HTTP 404）；可选择官方候选版。'
        $feed=Read-Feed preview
        Write-Event WARN ('即将安装官方候选版 {0}，可能有兼容性变化。' -f $feed.Version)
        $consent=Read-Host '确认安装预发布版本？ [y/N]'
        if ($consent -notmatch '^(y|Y)$') { Write-Event WARN '用户取消；没有执行安装。'; exit 2 }
    }
    if ($existing) {
        Test-VersionNotOlder $feed.Version $existing.Version
        if ($feed.Version -eq $existing.Version) {
            if (-not $Repair) {
                Write-Event PASS '已安装同版本；不重复下载或安装。'
                Prepare-DesktopShortcut $existing
                Ensure-DesktopAppShortcut $existing
                Start-And-Verify $existing.Path
                exit 0
            }
            Write-Event WARN ('修复模式将重新运行官方安装器并覆盖同版本文件：{0}' -f $feed.Version)
        } elseif ($Repair) {
            Stop-Desktop 'DSH-D004' '修复模式只重装当前同一版本；官方版本已变化，请使用正常安装器确认升级。'
        } else {
            $upgradeConsent=Read-Host ('已安装 {0}，官方安装器将升级到 {1}。继续？ [y/N]' -f $existing.Version,$feed.Version)
            if ($upgradeConsent -notmatch '^(y|Y)$') { Write-Event WARN '用户取消升级；原安装保持不变。'; exit 2 }
        }
    }
    Prepare-DesktopShortcut $existing
    $script:stage='Download'
    $installer=Join-Path $cache ('deepseek-harness-{0}-win-x64.exe' -f $feed.Version)
    $installerItem = Get-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
    if ($installerItem -and (($installerItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $installerItem.PSIsContainer)) {
        Stop-Desktop 'DSH-D003' '缓存安装包路径不是普通文件；为保护用户数据未覆盖。'
    }
    $cachedPackageValid = $installerItem -and $installerItem.Length -eq $feed.Size -and (Get-Sha512Base64 $installer) -ceq $feed.Sha512
    if (-not $cachedPackageValid) {
        $partial="$installer.part"
        $partialItem = Get-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        if ($partialItem) {
            if (($partialItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $partialItem.PSIsContainer) {
                Stop-Desktop 'DSH-D003' '下载暂存路径不是普通文件；为保护用户数据未覆盖。'
            }
            Remove-Item -LiteralPath $partial -Force -ErrorAction Stop
        }
        try { Invoke-WebRequest -Uri $feed.Url -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 600 -OutFile $partial }
        catch { Stop-Desktop 'DSH-D003' '官方安装包下载失败。请检查网络后重试。' }
        $downloadedItem = Get-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        if (-not $downloadedItem -or ($downloadedItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $downloadedItem.PSIsContainer) {
            Stop-Desktop 'DSH-D003' '下载后暂存文件不是普通文件；未执行。'
        }
        if ($downloadedItem.Length -ne $feed.Size -or (Get-Sha512Base64 $partial) -cne $feed.Sha512) {
            Stop-Desktop 'DSH-D003' '官方安装包大小或 SHA-512 不匹配；未执行。'
        }
        Move-Item -LiteralPath $partial -Destination $installer -Force
    }
    Write-Event PASS ('安装包 SHA-512 校验通过；版本 {0}。' -f $feed.Version)
    $script:stage='Signature'
    if (-not (Test-OfficialSignature $installer)) { Stop-Desktop 'DSH-D004' '安装包 Windows 签名或 DeepSeek 发布者身份校验失败；未执行。' }
    Write-Event PASS 'Windows 签名与官方发布者身份校验通过。'
    $script:stage='NativeInstaller'
    Write-Event INFO '将打开官方 Windows 安装界面；安装位置由官方界面选择。'
    $process=Start-Process -FilePath $installer -Wait -PassThru
    if ($process.ExitCode -ne 0) { Stop-Desktop 'DSH-D005' ('官方安装器未成功完成（exit {0}）。' -f $process.ExitCode) }
    $installed=Get-InstalledDesktop
    if (-not $installed -or $installed.Version -ne $feed.Version) { Stop-Desktop 'DSH-D005' '安装器退出后，未找到匹配版本和签名的正式安装。' }
    Write-Event PASS ('官方桌面端已安装：{0}' -f $installed.Version)
    Ensure-DesktopAppShortcut $installed
    Start-And-Verify $installed.Path
    Write-Event PASS ('桌面端部署完成。日志：{0}' -f $script:logPath)
    exit 0
} catch {
    $message=$_.Exception.Message
    if ($message -notmatch '^DSH-D\d{3}:') { $message='DSH-D999: 未预期错误；请提供日志路径联系技术人员。' }
    Write-Event FAIL $message
    if ($script:logPath) { Write-Host ('日志：{0}' -f $script:logPath) }
    exit 1
}
