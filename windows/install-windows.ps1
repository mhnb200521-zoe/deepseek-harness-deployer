<#
    DeepSeek Harness One-Click Installer — Windows 编排层 (L1)
    Milestone: M1 Windows MVP
    语言路线: 纯 PowerShell (Win10/11 自带 PS5.1)
    对应 ARCHITECTURE.md 的 S0..S7 状态机 (M1 覆盖 S0/S1/S2/S3/S4/S5/S7,S6 快捷方式在 M2)

    设计原则: 幂等 / 不覆盖兼容 Node / 不污染 PATH / 不存 API Key / 每步 PASS·WARN·FAIL / 失败带 Error ID
#>

[CmdletBinding()]
param(
    # 覆盖安装目录(测试或高级用户用);为空则走 D: 优先 + 交互回退
    [string]$InstallDir = "",
    # 仅执行检测与准备,不真正拉起 Harness 服务(用于 CI/自检)
    [switch]$NoLaunch,
    # 非交互模式:无 D: 盘时自动回退到 LOCALAPPDATA,不提示
    [switch]$NonInteractive,
    # 覆盖 Web UI 端口(默认 3080,以 config 为准)
    [int]$Port = 3080,
    # 诊断模式(更详细日志)
    [switch]$VerboseDiag,
    # 自检模式:只跑单元断言(版本兼容/选版),不执行安装
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# ============================================================
# 全局常量 / 冻结基线 (见 ARCHITECTURE §5 / §11)
# ============================================================
$script:DEPLOYER_VERSION = '0.1.0-M1'
$script:DSH_PACKAGE       = '@deepseek-ai/dsh'
# 兜底"已知良好"版本(S0 会尝试解析实际 latest;失败时用此值),标注为 fallback
$script:DSH_FALLBACK_VER  = '0.1.5-rc.2'
$script:NODE_DIST_INDEX   = 'https://nodejs.org/dist/index.json'
$script:HEALTH_TIMEOUT_S  = 120
$script:PREP_TIMEOUT_S    = 900

# 运行期状态(写入 config/deployer.json 的冻结字段)
$script:Cfg = [ordered]@{
    os              = 'windows'
    arch            = $null
    installRoot     = $null
    workspaceDir    = $null
    logDir          = $null
    cacheDir        = $null
    nodePath        = $null
    nodeMode        = $null      # reuse | private
    nodeVersion     = $null
    dshVersion      = $null
    port            = $Port
    webCommand      = 'web'      # S0 校正
    portConfigurable = $false    # S0 校正;未知时保守 false
    pid             = $null
    installedAt     = $null
    deployerVersion = $script:DEPLOYER_VERSION
    webVerified     = $false     # S0 是否确认了命令面
}

$script:LogFile = $null
$script:StageResults = @()

# ============================================================
# 日志 / 脱敏 (ARCHITECTURE §10, 脱敏正则为冻结契约)
# ============================================================
$script:RedactPatterns = @(
    'sk-[A-Za-z0-9]+',
    '(?i)authorization\s*[:=]\s*\S+',
    '(?i)api[_-]?key\s*[:=]\s*\S+',
    '(?i)token\s*[:=]\s*\S+',
    '(?i)cookie\s*[:=]\s*\S+'
)

function Protect-Sensitive([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return $text }
    foreach ($p in $script:RedactPatterns) {
        $text = [regex]::Replace($text, $p, '[REDACTED]')
    }
    return $text
}

function Write-Log {
    param([string]$Level, [string]$Stage, [string]$Message, [string]$ErrorId = '')
    $line = ('{0} [{1}] {2} {3}{4}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
        $Level, $Stage, (Protect-Sensitive $Message),
        ($(if ($ErrorId) { " ($ErrorId)" } else { '' })))
    if ($script:LogFile) {
        try { Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 } catch {}
    }
    if ($VerboseDiag -and $Level -eq 'DEBUG') { Write-Host $line -ForegroundColor DarkGray }
}

function Show-Line([string]$text, [string]$color = 'Gray') { Write-Host $text -ForegroundColor $color }

function Show-Result {
    param([string]$Status, [string]$Text, [string]$ErrorId = '')
    $color = switch ($Status) { 'PASS' {'Green'} 'WARN' {'Yellow'} 'FAIL' {'Red'} default {'Gray'} }
    $tag = "[$Status]".PadRight(7)
    $suffix = if ($ErrorId) { " ($ErrorId)" } else { '' }
    Write-Host ("  {0}{1}{2}" -f $tag, $Text, $suffix) -ForegroundColor $color
    Write-Log -Level $Status -Stage 'STAGE' -Message $Text -ErrorId $ErrorId
}

function Record-Stage {
    param([string]$Stage, [string]$Status, [string]$Detail = '', [string]$ErrorId = '', [int]$DurationMs = 0)
    $script:StageResults += [pscustomobject]@{
        stage = $Stage; status = $Status; errorId = $ErrorId; durationMs = $DurationMs; detail = $Detail
    }
}

# 统一致命失败: 人类可读 + Error ID + 日志(含堆栈),然后退出
function Stop-WithError {
    param([string]$ErrorId, [string]$Human, [string]$Tech = '')
    Show-Result -Status 'FAIL' -Text $Human -ErrorId $ErrorId
    Write-Log -Level 'ERROR' -Stage 'FATAL' -Message ("{0} | {1}" -f $Human, $Tech) -ErrorId $ErrorId
    Write-Host ''
    Write-Host '安装未完成。请把下面这一行发给技术支持:' -ForegroundColor Yellow
    Write-Host ("  Error ID: {0}   Log: {1}" -f $ErrorId, $script:LogFile) -ForegroundColor Yellow
    exit 1
}

# ============================================================
# 工具函数
# ============================================================
function Test-NodeCompatible([string]$v) {
    # 兼容集合: ^22.19.0 (>=22.19.0 <23) 或 >=24.0.0
    if ($v -match '^v?(\d+)\.(\d+)\.(\d+)') {
        $maj = [int]$Matches[1]; $min = [int]$Matches[2]
        if ($maj -eq 22 -and $min -ge 19) { return $true }
        if ($maj -ge 24) { return $true }
    }
    return $false
}

function Get-Arch {
    $a = $env:PROCESSOR_ARCHITECTURE
    if (-not [string]::IsNullOrWhiteSpace($env:PROCESSOR_ARCHITEW6432)) {
        $a = $env:PROCESSOR_ARCHITEW6432
    }
    if ([string]::IsNullOrWhiteSpace($a)) {
        try {
            $a = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        } catch {
            $a = if ([Environment]::Is64BitOperatingSystem) { 'AMD64' } else { 'x86' }
        }
    }
    switch -Regex ("$a") {
        'ARM64|ARM'  { return 'arm64' }
        'AMD64|X64'  { return 'x64' }
        'x86|X86'    { return 'x86' }
        default      { return ("$a").ToLowerInvariant() }
    }
}

function Test-PortListening([int]$p) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect('127.0.0.1', $p, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(500, $false)
        if ($ok -and $client.Connected) { $client.EndConnect($iar); return $true }
        return $false
    } catch { return $false } finally { $client.Close() }
}

function Test-IsHarnessOnPort([int]$p) {
    # 判断端口占用者是否像 Harness。
    # 注意: dsh web 无 token 时根路径返回 401(带 ?token= 的访问才放行),
    # 故不能只认 200;401/403/3xx 或响应体含关键词都视为 dsh(我们自建服务)。
    try {
        $resp = Invoke-WebRequest -Uri ("http://127.0.0.1:{0}/" -f $p) -UseBasicParsing -TimeoutSec 3
        $body = "$($resp.Content)"
        if ($body -match '(?i)deepseek|dsh|harness') { return $true }
        # 有 HTTP 响应本身,且是我们默认端口,倾向认为是 dsh
        return $true
    } catch {
        if ($_.Exception.Response) {
            try { $sc = [int]$_.Exception.Response.StatusCode } catch { $sc = 0 }
            if ($sc -eq 401 -or $sc -eq 403 -or ($sc -ge 300 -and $sc -lt 400)) { return $true }
        }
        return $false
    }
}

function Get-DshUrl {
    <#
        从 DSH 的实际输出中提取 Web UI URL。完整 URL 仅在内存中返回，
        调用方不得把 Url 字段直接写入日志（query 中可能包含临时 token）。
    #>
    [CmdletBinding()]
    param(
        [string[]]$OutputLines = @(),
        [int]$FallbackPort = 3080,
        [switch]$AllowFallback
    )

    $pattern = '(?i)https?://(?:127\.0\.0\.1|localhost):(?<port>\d+)(?:/[^\s<>"'']*)?'
    for ($i = $OutputLines.Count - 1; $i -ge 0; $i--) {
        $line = "$($OutputLines[$i])"
        $match = [regex]::Match($line, $pattern)
        if (-not $match.Success) { continue }

        # 清除常见句末标点，但保留 URL path/query/fragment。
        $url = $match.Value.TrimEnd(')', ']', '}', ',', ';', '.')
        $uri = $null
        if (-not [uri]::TryCreate($url, [System.UriKind]::Absolute, [ref]$uri)) { continue }

        $hasToken = $false
        if ($uri.Query -match '(?i)(?:^|[?&])token=') { $hasToken = $true }
        return [pscustomobject]@{
            Url        = $uri.AbsoluteUri
            Source     = 'detected'
            HasToken   = $hasToken
            Port       = $uri.Port
            DetectedAt = (Get-Date -Format 'o')
        }
    }

    if ($AllowFallback) {
        return [pscustomobject]@{
            Url        = ("http://127.0.0.1:{0}/" -f $FallbackPort)
            Source     = 'fallback'
            HasToken   = $false
            Port       = $FallbackPort
            DetectedAt = $null
        }
    }
    return $null
}

function Test-DshWebUrl {
    param([Parameter(Mandatory=$true)]$UrlInfo)
    try {
        $resp = Invoke-WebRequest -Uri $UrlInfo.Url -UseBasicParsing -TimeoutSec 8
        $status = [int]$resp.StatusCode
        return [pscustomobject]@{ Success = ($status -ge 200 -and $status -lt 400); StatusCode = $status }
    } catch {
        $status = 0
        if ($_.Exception.Response) {
            try { $status = [int]$_.Exception.Response.StatusCode } catch { $status = 0 }
        }
        # fallback URL 没有 token 时，DSH 正常会返回 401/403；这只能证明服务可达，
        # 不能证明用户已认证。detected URL 则必须真正通过 HTTP 验证。
        $reachableFallback = ($UrlInfo.Source -eq 'fallback' -and ($status -eq 401 -or $status -eq 403))
        return [pscustomobject]@{ Success = $reachableFallback; StatusCode = $status }
    }
}

# ============================================================
# 头部
# ============================================================
function Show-Header {
    Write-Host ''
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host ' DeepSeek Harness One-Click Installer' -ForegroundColor Cyan
    Write-Host '==================================================' -ForegroundColor Cyan
    $osName = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
    Write-Host ''
    Write-Host ('System:        {0} {1}' -f $osName, $script:Cfg.arch)
    Write-Host ('Install dir:   {0}' -f $script:Cfg.installRoot)
    Write-Host ('Deployer:      {0}' -f $script:DEPLOYER_VERSION)
    Write-Host ''
}

# ============================================================
# S1 System Check — OS/CPU/磁盘/目录
# ============================================================
function Invoke-S1-SystemCheck {
    $t0 = Get-Date
    Write-Host 'Stage 1/7  System Check' -ForegroundColor White
    $script:Cfg.arch = Get-Arch

    if ($script:Cfg.arch -eq 'x86') {
        Stop-WithError 'DSH-E009' '不支持 32 位(x86)系统。DeepSeek Harness 需要 64 位 Windows。' 'arch=x86'
    }
    if ($script:Cfg.arch -eq 'arm64') {
        Show-Result 'WARN' 'ARM64 架构:将优先尝试 win-arm64 Node;若不可靠会明确提示。'
    }
    Show-Result 'PASS' ("架构识别: {0}" -f $script:Cfg.arch)

    # 决定安装目录
    if ([string]::IsNullOrWhiteSpace($InstallDir)) {
        if (Test-Path 'D:\') {
            $script:Cfg.installRoot = 'D:\DeepSeekHarness'
            Show-Result 'PASS' '检测到 D: 盘,安装到 D:\DeepSeekHarness'
        } else {
            Show-Result 'WARN' '未检测到 D: 盘。'
            if ($NonInteractive) {
                $script:Cfg.installRoot = Join-Path $env:LOCALAPPDATA 'DeepSeekHarness'
                Show-Result 'PASS' ("非交互模式,回退到: {0}" -f $script:Cfg.installRoot)
            } else {
                Write-Host ''
                Write-Host '  请选择:' -ForegroundColor Yellow
                Write-Host '   [1] 安装到当前用户目录 (LOCALAPPDATA)'
                Write-Host '   [2] 输入其他安装位置'
                Write-Host '   [3] 退出'
                $choice = Read-Host '  输入 1 / 2 / 3'
                switch ($choice) {
                    '1' { $script:Cfg.installRoot = Join-Path $env:LOCALAPPDATA 'DeepSeekHarness' }
                    '2' {
                        $custom = Read-Host '  请输入完整路径'
                        if ([string]::IsNullOrWhiteSpace($custom)) { Stop-WithError 'DSH-E010' '未提供有效安装路径。' 'empty custom path' }
                        $script:Cfg.installRoot = $custom
                    }
                    default { Write-Host '已取消。' ; exit 0 }
                }
            }
        }
    } else {
        $script:Cfg.installRoot = $InstallDir
        Show-Result 'PASS' ("使用指定安装目录: {0}" -f $InstallDir)
    }

    # 建目录(幂等)
    $script:Cfg.workspaceDir = Join-Path $script:Cfg.installRoot 'workspace'
    $script:Cfg.logDir       = Join-Path $script:Cfg.installRoot 'logs'
    $script:Cfg.cacheDir     = Join-Path $script:Cfg.installRoot 'cache'
    $sub = @('runtime\node','launcher','workspace','cache','logs','config')
    try {
        foreach ($s in $sub) {
            $full = Join-Path $script:Cfg.installRoot $s
            if (-not (Test-Path $full)) { New-Item -ItemType Directory -Path $full -Force | Out-Null }
        }
    } catch {
        Stop-WithError 'DSH-E010' ("无法创建安装目录: {0}。请检查磁盘权限或换一个位置。" -f $script:Cfg.installRoot) $_.Exception.Message
    }

    # 现在可以初始化日志文件
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:LogFile = Join-Path $script:Cfg.logDir ("install-{0}.log" -f $ts)
    Write-Log 'INFO' 'S1' ("installRoot={0} arch={1}" -f $script:Cfg.installRoot, $script:Cfg.arch)
    Show-Result 'PASS' ("目录就绪,日志: {0}" -f $script:LogFile)
    Record-Stage 'S1' 'PASS' -DurationMs ([int]((Get-Date)-$t0).TotalMilliseconds)
}

# ============================================================
# S2 Node — 复用兼容 Node,否则私有 Runtime
# ============================================================
function Invoke-S2-Node {
    $t0 = Get-Date
    Write-Host 'Stage 2/7  Node.js' -ForegroundColor White

    # N0: 检测现有 Node
    $existing = $null
    try {
        $existing = (& node -v) 2>$null
    } catch { $existing = $null }

    if ($existing -and (Test-NodeCompatible $existing)) {
        $nodeCmd = (Get-Command node -ErrorAction SilentlyContinue).Source
        $script:Cfg.nodeMode = 'reuse'
        $script:Cfg.nodeVersion = $existing.Trim()
        $script:Cfg.nodePath = $nodeCmd
        Show-Result 'PASS' ("检测到兼容 Node.js: {0}(复用,不修改)" -f $existing.Trim())
        Write-Log 'INFO' 'S2' ("reuse node {0} at {1}" -f $existing.Trim(), $nodeCmd)
        Record-Stage 'S2' 'PASS' -Detail 'reuse' -DurationMs ([int]((Get-Date)-$t0).TotalMilliseconds)
        return
    }

    if ($existing) {
        Show-Result 'WARN' ("现有 Node.js {0} 不满足兼容基线(^22.19.0 或 >=24.0.0),将安装私有 Runtime,不改动它。" -f $existing.Trim())
    } else {
        Show-Result 'WARN' '未检测到 Node.js,将安装私有 Runtime(隔离,不污染系统)。'
    }

    Install-PrivateNode
    Record-Stage 'S2' 'PASS' -Detail 'private' -DurationMs ([int]((Get-Date)-$t0).TotalMilliseconds)
}

function Install-PrivateNode {
    $nodeRoot = Join-Path $script:Cfg.installRoot 'runtime\node'

    # 幂等: 已有可用私有 node?
    $existingNodeExe = Join-Path $nodeRoot 'node.exe'
    if (Test-Path $existingNodeExe) {
        $v = (& $existingNodeExe -v) 2>$null
        if ($v -and (Test-NodeCompatible $v)) {
            $script:Cfg.nodeMode = 'private'; $script:Cfg.nodeVersion = $v.Trim(); $script:Cfg.nodePath = $existingNodeExe
            Show-Result 'PASS' ("复用已安装的私有 Node: {0}" -f $v.Trim())
            return
        }
    }

    # 选版: 官方 index.json,优先最新兼容 LTS(24),回退 22>=22.19
    $target = Select-NodeVersion
    $ver = $target.version   # 形如 v24.9.0
    $arch = $script:Cfg.arch # x64 / arm64
    $pkg = "node-$ver-win-$arch.zip"
    $base = "https://nodejs.org/dist/$ver"
    $zipUrl = "$base/$pkg"
    $shaUrl = "$base/SHASUMS256.txt"
    $tmp = Join-Path $script:Cfg.cacheDir $pkg
    $shaTmp = Join-Path $script:Cfg.cacheDir "SHASUMS256-$ver.txt"

    Show-Line ("  下载 Node $ver ($arch) ...") 'Gray'
    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 120
    } catch {
        Stop-WithError 'DSH-E001' 'Node.js 下载失败。可能是网络问题,请更换网络后重试。' ("url={0} err={1}" -f $zipUrl, $_.Exception.Message)
    }

    # 校验 SHA256
    try {
        Invoke-WebRequest -Uri $shaUrl -OutFile $shaTmp -UseBasicParsing -TimeoutSec 60
        $expected = (Select-String -Path $shaTmp -Pattern ([regex]::Escape($pkg)) | Select-Object -First 1).Line
        if (-not $expected) { throw "SHASUMS 未包含 $pkg" }
        $expectedHash = ($expected -split '\s+')[0].ToLower()
        $actualHash = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash.ToLower()
        if ($expectedHash -ne $actualHash) {
            Stop-WithError 'DSH-E002' 'Node.js 安装包校验失败(SHA256 不匹配),已停止以确保安全。请重试或更换网络。' ("expected={0} actual={1}" -f $expectedHash, $actualHash)
        }
        Show-Result 'PASS' 'Node 安装包 SHA256 校验通过'
    } catch {
        if ($_.Exception.Message -notmatch 'DSH-E002') {
            Stop-WithError 'DSH-E002' 'Node.js 校验数据获取/比对失败,已停止安装。' $_.Exception.Message
        }
    }

    # 解压
    try {
        $extractTo = Join-Path $script:Cfg.cacheDir "extract-$ver"
        if (Test-Path $extractTo) { Remove-Item $extractTo -Recurse -Force }
        Expand-Archive -Path $tmp -DestinationPath $extractTo -Force
        $inner = Get-ChildItem -Path $extractTo -Directory | Select-Object -First 1
        if (Test-Path $nodeRoot) { Remove-Item $nodeRoot -Recurse -Force }
        Move-Item -Path $inner.FullName -Destination $nodeRoot -Force
    } catch {
        Stop-WithError 'DSH-E001' 'Node.js 解压失败。' $_.Exception.Message
    }

    $nodeExe = Join-Path $nodeRoot 'node.exe'
    if (-not (Test-Path $nodeExe)) { Stop-WithError 'DSH-E001' 'Node.js 安装后未找到 node.exe。' "missing $nodeExe" }
    $script:Cfg.nodeMode = 'private'
    $script:Cfg.nodeVersion = $ver
    $script:Cfg.nodePath = $nodeExe
    Show-Result 'PASS' ("私有 Node 安装完成: {0}" -f $ver)
}

function Select-NodeVersion {
    try {
        $json = Invoke-RestMethod -Uri $script:NODE_DIST_INDEX -TimeoutSec 30
    } catch {
        Show-Result 'WARN' ("无法获取 Node 版本索引,使用兜底策略。")
        Write-Log 'WARN' 'S2' ("index fetch failed: {0}" -f $_.Exception.Message) 'DSH-E011'
        return [pscustomobject]@{ version = 'v24.9.0'; fallback = $true }
    }
    # 优先: 最新兼容 LTS(major 24) → 回退 22>=22.19
    $lts24 = $json | Where-Object { $_.lts -and ($_.version -match '^v24\.') } | Select-Object -First 1
    if ($lts24) { return [pscustomobject]@{ version = $lts24.version; fallback = $false } }
    $lts22 = $json | Where-Object {
        $_.lts -and ($_.version -match '^v22\.(\d+)\.') -and [int]$Matches[1] -ge 19
    } | Select-Object -First 1
    if ($lts22) { return [pscustomobject]@{ version = $lts22.version; fallback = $false } }
    # 无兼容 LTS → 最新兼容 Current
    $cur = $json | Where-Object { $_.version -match '^v(\d+)\.' -and [int]$Matches[1] -ge 24 } | Select-Object -First 1
    if ($cur) { return [pscustomobject]@{ version = $cur.version; fallback = $false } }
    return [pscustomobject]@{ version = 'v24.9.0'; fallback = $true }
}

# npm/npx: 一律解析到 node 目录下的 .cmd 全路径(避免 PowerShell 误选 npm.ps1 被执行策略阻止)
function Get-NpmCmd {
    if ($script:Cfg.nodePath) {
        $c = Join-Path (Split-Path $script:Cfg.nodePath) 'npm.cmd'
        if (Test-Path $c) { return $c }
    }
    return 'npm'
}
function Get-NpxCmd {
    if ($script:Cfg.nodePath) {
        $c = Join-Path (Split-Path $script:Cfg.nodePath) 'npx.cmd'
        if (Test-Path $c) { return $c }
    }
    return 'npx'
}

# ============================================================
# S3 npm — 网络预检
# ============================================================
function Invoke-S3-Npm {
    $t0 = Get-Date
    Write-Host 'Stage 3/7  npm' -ForegroundColor White
    $npm = Get-NpmCmd

    # npm -v
    $npmv = $null
    try { $npmv = (& $npm -v) 2>$null } catch { $npmv = $null }
    if (-not $npmv) {
        Stop-WithError 'DSH-E003' 'npm 不可用。Node.js 可能安装不完整,请重试安装。' 'npm -v failed'
    }
    Show-Result 'PASS' ("npm: {0}" -f $npmv.Trim())

    # registry 可达 + 包可达(合并成一次 npm view)
    Show-Line '  检测 npm 软件源与 DeepSeek Harness 包 ...' 'Gray'
    $viewOut = $null
    try {
        $viewOut = (& $npm view $script:DSH_PACKAGE version) 2>&1
    } catch { $viewOut = "$($_.Exception.Message)" }

    # 从输出中提取 semver(容忍 npm 附带的通知/警告行)
    $ver = $null
    foreach ($ln in @($viewOut)) {
        if ("$ln" -match '(\d+\.\d+\.\d+(?:-[0-9A-Za-z.\-]+)?)') { $ver = $Matches[1]; break }
    }

    if (-not $ver) {
        Stop-WithError 'DSH-E004' @"
无法连接 npm 软件源或获取 DeepSeek Harness 包信息。

可能原因:
  1. 当前网络无法访问 npm
  2. DNS 异常
  3. 校园网 / 公司网络限制
  4. HTTPS 请求受到代理影响

请更换网络后重试。
"@ ("npm view output: {0}" -f ("$viewOut"))
    }
    $script:Cfg.dshVersion = "$ver".Trim()
    Show-Result 'PASS' 'npm 软件源可达'
    Show-Result 'PASS' ("{0} 可达,最新版本: {1}" -f $script:DSH_PACKAGE, $script:Cfg.dshVersion)
    Record-Stage 'S3' 'PASS' -Detail ("dsh={0}" -f $script:Cfg.dshVersion) -DurationMs ([int]((Get-Date)-$t0).TotalMilliseconds)
}

# ============================================================
# S0 Probe(逻辑前置于 S4)— dsh 能力探测
# ============================================================
function Invoke-S0-Probe {
    Write-Host 'Stage 4/7  Harness (S0 能力探测 + 首次准备)' -ForegroundColor White
    if (-not $script:Cfg.dshVersion) { $script:Cfg.dshVersion = $script:DSH_FALLBACK_VER }
    $spec = "$($script:DSH_PACKAGE)@$($script:Cfg.dshVersion)"
    $npx = Get-NpxCmd

    Show-Line ("  探测 {0} 命令面(首次会下载,请稍候;最多等待 {1}s)..." -f $spec, $script:PREP_TIMEOUT_S) 'Gray'
    $help = ''
    $previousNpmCache = [Environment]::GetEnvironmentVariable('npm_config_cache', 'Process')
    try {
        # S4 与最终启动器必须使用同一个私有 cache,避免把首次完整依赖下载延迟到 S7。
        [Environment]::SetEnvironmentVariable('npm_config_cache', $script:Cfg.cacheDir, 'Process')
        $job = Start-Job -ScriptBlock {
            param($npxCmd, $specArg)
            & $npxCmd --yes $specArg --help 2>&1 | Out-String
        } -ArgumentList $npx, $spec
        if (Wait-Job $job -Timeout $script:PREP_TIMEOUT_S) {
            $help = (Receive-Job $job) | Out-String
        } else {
            Stop-Job $job -ErrorAction SilentlyContinue
            $help = ''
            Write-Log 'WARN' 'S0' ("probe timed out at {0}s; treating as unverified" -f $script:PREP_TIMEOUT_S)
        }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    } catch { $help = '' } finally {
        [Environment]::SetEnvironmentVariable('npm_config_cache', $previousNpmCache, 'Process')
    }

    if ($help -and $help.Trim().Length -gt 0) {
        $script:Cfg.webVerified = $true
        if ($help -match '(?i)\bweb\b') { $script:Cfg.webCommand = 'web' }
        if ($help -match '(?i)--no-open') { } # 记录支持
        if ($help -match '(?i)--port') { $script:Cfg.portConfigurable = $true }
        if ($help -match '(?i)3080') { } # 默认端口确认
        Show-Result 'PASS' 'dsh 命令面已探测确认(webVerified=true)'
        Write-Log 'INFO' 'S0' ("help captured; portConfigurable={0}" -f $script:Cfg.portConfigurable)
    } else {
        # 保守默认 + 标注(用户在 M1 选定的策略)
        $script:Cfg.webVerified = $false
        $script:Cfg.webCommand = 'web'
        $script:Cfg.portConfigurable = $false
        Show-Result 'WARN' 'dsh CLI 未返回可解析帮助(非 TTY 常见)。采用保守默认: web / 端口 3080,标注为 unverified。'
        Write-Log 'WARN' 'S0' 'help empty; using conservative defaults (web, 3080, unverified)'
    }
}

# ============================================================
# S5 Launcher — 生成启动器(不绑定绝对 node 路径的可迁移写法见 §11.3)
# ============================================================
function Invoke-S5-Launcher {
    $t0 = Get-Date
    Write-Host 'Stage 5/7  Launcher' -ForegroundColor White
    $launcherDir = Join-Path $script:Cfg.installRoot 'launcher'
    $cmdPath = Join-Path $launcherDir 'start-dsh.cmd'
    $ps1Path = Join-Path $launcherDir 'start-dsh.ps1'

    # 若私有 node,启动器需局部注入其 bin 目录;复用则依赖系统 PATH
    $nodeDir = if ($script:Cfg.nodeMode -eq 'private') { Split-Path $script:Cfg.nodePath } else { '' }
    # 解析 npx.cmd 全路径供启动器直接调用(规避 npx.ps1 被执行策略拦截)
    $npxForLauncher = Get-NpxCmd

    $ps1Template = @'
# DeepSeek Harness 启动器（由安装器生成）
[CmdletBinding()]
param([string]$ResultPipe = '')

$ErrorActionPreference = 'Continue'
$installRoot = '__INSTALL_ROOT__'
$workspace   = '__WORKSPACE__'
$logDir      = '__LOG_DIR__'
$port        = __PORT__
$spec        = '__SPEC__'
$nodeExe     = '__NODE_EXE__'
$nodeDir     = '__NODE_DIR__'
$npxCmd      = '__NPX_CMD__'
$healthTimeout = __HEALTH_TIMEOUT__

if ($nodeDir -and (Test-Path $nodeDir)) { $env:Path = $nodeDir + ';' + $env:Path }
if (-not (Test-Path $npxCmd)) { $npxCmd = 'npx.cmd' }
$env:npm_config_cache = Join-Path $installRoot 'cache'
Set-Location $workspace
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$runLog = Join-Path $logDir ("runtime-$ts.log")

function Protect-DshOutput([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $safe = [regex]::Replace($Text, '(?i)([?&](?:token|api[_-]?key|authorization|cookie)=)[^&\s]+', '$1[REDACTED]')
    $safe = [regex]::Replace($safe, 'sk-[A-Za-z0-9]+', '[REDACTED]')
    return $safe
}

function Write-RunLog([string]$Level, [string]$Message) {
    $line = ('{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, (Protect-DshOutput $Message))
    try { Add-Content -LiteralPath $runLog -Value $line -Encoding UTF8 } catch {}
}

function Test-PortListening([int]$PortNumber) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect('127.0.0.1', $PortNumber, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne(500, $false) -and $client.Connected) {
            $client.EndConnect($async)
            return $true
        }
        return $false
    } catch { return $false } finally { $client.Close() }
}

function Get-DshUrl {
    [CmdletBinding()]
    param([string[]]$OutputLines = @(), [int]$FallbackPort = 3080, [switch]$AllowFallback)

    $pattern = '(?i)https?://(?:127\.0\.0\.1|localhost):(?<port>\d+)(?:/[^\s<>"'']*)?'
    for ($i = $OutputLines.Count - 1; $i -ge 0; $i--) {
        $match = [regex]::Match("$($OutputLines[$i])", $pattern)
        if (-not $match.Success) { continue }
        $candidate = $match.Value.TrimEnd(')', ']', '}', ',', ';', '.')
        $uri = $null
        if (-not [uri]::TryCreate($candidate, [System.UriKind]::Absolute, [ref]$uri)) { continue }
        return [pscustomobject]@{
            Url = $uri.AbsoluteUri
            Source = 'detected'
            HasToken = ($uri.Query -match '(?i)(?:^|[?&])token=')
            Port = $uri.Port
            DetectedAt = (Get-Date -Format 'o')
        }
    }
    if ($AllowFallback) {
        return [pscustomobject]@{
            Url = ("http://127.0.0.1:{0}/" -f $FallbackPort)
            Source = 'fallback'
            HasToken = $false
            Port = $FallbackPort
            DetectedAt = $null
        }
    }
    return $null
}

function Test-DshWebUrl($UrlInfo) {
    try {
        $response = Invoke-WebRequest -Uri $UrlInfo.Url -UseBasicParsing -TimeoutSec 8
        $status = [int]$response.StatusCode
        return [pscustomobject]@{ Success = ($status -ge 200 -and $status -lt 400); StatusCode = $status }
    } catch {
        $status = 0
        if ($_.Exception.Response) {
            try { $status = [int]$_.Exception.Response.StatusCode } catch { $status = 0 }
        }
        $fallbackReachable = ($UrlInfo.Source -eq 'fallback' -and ($status -eq 401 -or $status -eq 403))
        return [pscustomobject]@{ Success = $fallbackReachable; StatusCode = $status }
    }
}

function Send-UrlResult([string]$PipeName, $UrlInfo) {
    if (-not $PipeName) { return $false }
    $pipe = $null
    $writer = $null
    try {
        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', $PipeName, [System.IO.Pipes.PipeDirection]::Out)
        $pipe.Connect(10000)
        $writer = New-Object System.IO.StreamWriter($pipe)
        $writer.AutoFlush = $true
        $writer.WriteLine(($UrlInfo | ConvertTo-Json -Compress))
        return $true
    } catch {
        Write-RunLog 'WARN' '无法通过内存管道返回 Web URL；将由启动器本地验证。'
        return $false
    } finally {
        if ($writer) { $writer.Dispose() }
        if ($pipe) { $pipe.Dispose() }
    }
}

function Complete-Launch($UrlInfo) {
    Write-RunLog 'INFO' ("URL source={0} tokenPresent={1} port={2}" -f $UrlInfo.Source, $UrlInfo.HasToken, $UrlInfo.Port)
    if ($ResultPipe -and (Send-UrlResult $ResultPipe $UrlInfo)) { return }

    $verification = Test-DshWebUrl $UrlInfo
    if ($verification.Success) {
        Write-RunLog 'PASS' ("URL verification succeeded source={0} tokenPresent={1} status={2}" -f $UrlInfo.Source, $UrlInfo.HasToken, $verification.StatusCode)
        Start-Process $UrlInfo.Url
    } else {
        Write-RunLog 'FAIL' ("URL verification failed source={0} tokenPresent={1} status={2} (DSH-E006)" -f $UrlInfo.Source, $UrlInfo.HasToken, $verification.StatusCode)
    }
}

Write-RunLog 'INFO' ("Starting DeepSeek Harness on configured fallback port {0}" -f $port)

# 幂等分支：服务已存在时无法从进程输出恢复 token，明确使用 fallback。
if (Test-PortListening $port) {
    $existingUrl = Get-DshUrl -FallbackPort $port -AllowFallback
    Write-RunLog 'WARN' 'Harness 已在运行；本次没有新的启动输出，URL source=fallback。'
    Complete-Launch $existingUrl
    exit 0
}

# 直接托管子进程 stdout/stderr。原始 URL 只保存在内存；写盘前统一脱敏。
$lines = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
$process = New-Object System.Diagnostics.Process
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$npxCli = Join-Path (Split-Path $npxCmd) 'node_modules\npm\bin\npx-cli.js'
if ((Test-Path $nodeExe) -and (Test-Path $npxCli)) {
    $startInfo.FileName = $nodeExe
    $startInfo.Arguments = ('"{0}" --yes "{1}" web --no-open' -f $npxCli, $spec)
} else {
    $startInfo.FileName = $env:ComSpec
    $startInfo.Arguments = ('/d /s /c ""{0}" --yes "{1}" web --no-open"' -f $npxCmd, $spec)
}
$startInfo.WorkingDirectory = $workspace
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$process.StartInfo = $startInfo

$eventData = @{ Lines = $lines; Log = $runLog }
$captureAction = {
    $line = $Event.SourceEventArgs.Data
    if ([string]::IsNullOrEmpty($line)) { return }
    [void]$Event.MessageData.Lines.Add($line)
    $safe = [regex]::Replace($line, '(?i)([?&](?:token|api[_-]?key|authorization|cookie)=)[^&\s]+', '$1[REDACTED]')
    $safe = [regex]::Replace($safe, 'sk-[A-Za-z0-9]+', '[REDACTED]')
    try { Add-Content -LiteralPath $Event.MessageData.Log -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' [DSH] ' + $safe) -Encoding UTF8 } catch {}
}
$stdoutEvent = Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -MessageData $eventData -Action $captureAction
$stderrEvent = Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -MessageData $eventData -Action $captureAction

try {
    if (-not $process.Start()) { throw 'Process.Start returned false' }
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()

    $deadline = (Get-Date).AddSeconds($healthTimeout)
    $urlInfo = $null
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
        $urlInfo = Get-DshUrl -OutputLines @($lines.ToArray()) -FallbackPort $port
        if ($urlInfo -and (Test-PortListening $urlInfo.Port)) { break }
        if ($process.HasExited) { break }
    }

    if (-not $urlInfo -and (Test-PortListening $port)) {
        $urlInfo = Get-DshUrl -FallbackPort $port -AllowFallback
        Write-RunLog 'WARN' '服务端口已监听，但启动输出中未检测到 URL；URL source=fallback。'
    }

    if ($urlInfo) {
        Complete-Launch $urlInfo
    } else {
        Write-RunLog 'FAIL' '启动超时或未捕获 Web URL (DSH-E006)。'
    }

    # 保持 stdout/stderr 管道有效，避免子进程因父进程退出而失去输出接收端。
    if (-not $process.HasExited) { $process.WaitForExit() }
} catch {
    Write-RunLog 'FAIL' ("Harness 启动异常 (DSH-E006): {0}" -f $_.Exception.Message)
} finally {
    Unregister-Event -SourceIdentifier $stdoutEvent.Name -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier $stderrEvent.Name -ErrorAction SilentlyContinue
    Remove-Job -Id $stdoutEvent.Id -Force -ErrorAction SilentlyContinue
    Remove-Job -Id $stderrEvent.Id -Force -ErrorAction SilentlyContinue
    $process.Dispose()
}
'@

    $ps1 = $ps1Template.Replace('__INSTALL_ROOT__', ($script:Cfg.installRoot -replace "'", "''"))
    $ps1 = $ps1.Replace('__WORKSPACE__', ($script:Cfg.workspaceDir -replace "'", "''"))
    $ps1 = $ps1.Replace('__LOG_DIR__', ($script:Cfg.logDir -replace "'", "''"))
    $ps1 = $ps1.Replace('__PORT__', "$($script:Cfg.port)")
    $ps1 = $ps1.Replace('__SPEC__', ("{0}@{1}" -f $script:DSH_PACKAGE, $script:Cfg.dshVersion))
    $ps1 = $ps1.Replace('__NODE_EXE__', ($script:Cfg.nodePath -replace "'", "''"))
    $ps1 = $ps1.Replace('__NODE_DIR__', ($nodeDir -replace "'", "''"))
    $ps1 = $ps1.Replace('__NPX_CMD__', ($npxForLauncher -replace "'", "''"))
    $ps1 = $ps1.Replace('__HEALTH_TIMEOUT__', "$($script:HEALTH_TIMEOUT_S)")

    $cmd = @"
@echo off
REM DeepSeek Harness 启动器入口 (deployer $($script:DEPLOYER_VERSION))
 powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-dsh.ps1" %*
"@

    try {
        Set-Content -Path $ps1Path -Value $ps1 -Encoding UTF8
        Set-Content -Path $cmdPath -Value $cmd -Encoding ASCII
    } catch {
        Stop-WithError 'DSH-E010' '启动器写入失败(可能是权限问题)。' $_.Exception.Message
    }
    if (-not (Test-Path $cmdPath)) { Stop-WithError 'DSH-E010' '启动器创建后未找到。' "missing $cmdPath" }
    Show-Result 'PASS' ("启动器已生成: {0}" -f $cmdPath)
    Record-Stage 'S5' 'PASS' -DurationMs ([int]((Get-Date)-$t0).TotalMilliseconds)
    return $cmdPath
}

# ============================================================
# S7 Verification — 启动并轮询健康(除非 -NoLaunch)
# ============================================================
function Invoke-S7-Verification([string]$launcherPath) {
    $t0 = Get-Date
    Write-Host 'Stage 7/7  Verification' -ForegroundColor White
    $p = $script:Cfg.port

    if ($NoLaunch) {
        Show-Result 'WARN' '（-NoLaunch）跳过实际启动,仅完成准备。可稍后运行启动器。'
        Record-Stage 'S7' 'WARN' -Detail 'skipped(NoLaunch)' -DurationMs ([int]((Get-Date)-$t0).TotalMilliseconds)
        return
    }

    # 端口占用判定(不盲杀)。若是已运行的 Harness，仍交给 launcher 明确走 fallback；
    # 冷启动时 launcher 会从实际 stdout 中提取带 token/query 的 URL。
    if (Test-PortListening $p) {
        if (-not (Test-IsHarnessOnPort $p)) {
            Stop-WithError 'DSH-E007' ("端口 {0} 已被其它程序占用(非 DeepSeek Harness)。请关闭占用该端口的程序后重试。" -f $p) 'port in use by non-dsh'
        }
        Show-Line ("  端口 {0} 已有 Harness 响应；尝试恢复可用 URL，无法恢复时明确使用 fallback。" -f $p) 'Gray'
    } else {
        Show-Line '  正在启动 DeepSeek Harness并捕获实际 Web URL...' 'Gray'
    }

    $launcherPs1 = Join-Path (Split-Path $launcherPath) 'start-dsh.ps1'
    if (-not (Test-Path $launcherPs1)) {
        Stop-WithError 'DSH-E006' '未找到 Harness PowerShell 启动器。' ("missing {0}" -f $launcherPs1)
    }

    # Named Pipe 仅在内存中传递实际 URL，避免把完整 token 写入日志/config/临时文件。
    $pipeName = 'dsh-url-' + [guid]::NewGuid().ToString('N')
    $pipe = $null
    $reader = $null
    $urlInfo = $null
    try {
        $pipe = New-Object System.IO.Pipes.NamedPipeServerStream(
            $pipeName,
            [System.IO.Pipes.PipeDirection]::In,
            1,
            [System.IO.Pipes.PipeTransmissionMode]::Byte,
            [System.IO.Pipes.PipeOptions]::Asynchronous
        )
        $wait = $pipe.BeginWaitForConnection($null, $null)
        $quotedLauncher = '"' + $launcherPs1 + '"'
        Start-Process -FilePath 'powershell.exe' -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $quotedLauncher,
            '-ResultPipe', $pipeName
        ) -WindowStyle Minimized

        if (-not $wait.AsyncWaitHandle.WaitOne($script:HEALTH_TIMEOUT_S * 1000, $false)) {
            Stop-WithError 'DSH-E006' ("在 {0} 秒内未捕获 Harness Web URL。请查看 runtime 日志。" -f $script:HEALTH_TIMEOUT_S) 'named pipe URL timeout'
        }
        $pipe.EndWaitForConnection($wait)
        $reader = New-Object System.IO.StreamReader($pipe)
        $payload = $reader.ReadLine()
        if (-not $payload) { throw 'launcher returned empty URL payload' }
        $urlInfo = $payload | ConvertFrom-Json
    } catch {
        Stop-WithError 'DSH-E006' '未能从 Harness 启动输出获取可验证的 Web URL。' $_.Exception.Message
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($pipe) { $pipe.Dispose() }
    }

    $verification = Test-DshWebUrl $urlInfo
    Write-Log 'INFO' 'S7' ("urlSource={0} tokenPresent={1} port={2} httpStatus={3}" -f $urlInfo.Source, $urlInfo.HasToken, $urlInfo.Port, $verification.StatusCode)
    if (-not $verification.Success) {
        Stop-WithError 'DSH-E006' 'Harness Web URL 验证失败。实际 URL 已捕获但未通过 HTTP 检查。' ("source={0} hasToken={1} port={2} status={3}" -f $urlInfo.Source, $urlInfo.HasToken, $urlInfo.Port, $verification.StatusCode)
    }

    # 验证与浏览器打开使用同一个内存 URL；日志只记录来源和 token 是否存在。
    Start-Process $urlInfo.Url
    if ($urlInfo.Source -eq 'detected') {
        Show-Result 'PASS' ("DeepSeek Harness is running. URL=detected, token preserved={0}." -f $(if ($urlInfo.HasToken) { 'YES' } else { 'NO' }))
        Record-Stage 'S7' 'PASS' -Detail ("source=detected hasToken={0} status={1}" -f $urlInfo.HasToken, $verification.StatusCode) -DurationMs ([int]((Get-Date)-$t0).TotalMilliseconds)
    } else {
        Show-Result 'WARN' ("Harness 已可达，但实际启动 URL 不可恢复；已明确使用端口 {0} fallback。" -f $urlInfo.Port)
        Record-Stage 'S7' 'WARN' -Detail ("source=fallback hasToken=false status={0}" -f $verification.StatusCode) -DurationMs ([int]((Get-Date)-$t0).TotalMilliseconds)
    }
}

# ============================================================
# 写 config
# ============================================================
function Save-Config {
    $script:Cfg.installedAt = (Get-Date -Format 'o')
    $configPath = Join-Path $script:Cfg.installRoot 'config\deployer.json'
    try {
        ($script:Cfg | ConvertTo-Json -Depth 5) | Set-Content -Path $configPath -Encoding UTF8
        Write-Log 'INFO' 'CONFIG' ("saved {0}" -f $configPath)
    } catch {
        Show-Result 'WARN' ("配置写入失败(不阻断): {0}" -f $_.Exception.Message)
    }
}

# ============================================================
# 日志轮转 (R17): 每类日志仅保留最近 N 份
# ============================================================
function Rotate-Logs([int]$Keep = 10) {
    try {
        foreach ($pat in @('install-*.log','runtime-*.log','runtime-*.log.err')) {
            $files = Get-ChildItem -Path $script:Cfg.logDir -Filter $pat -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending
            if ($files.Count -gt $Keep) {
                $files | Select-Object -Skip $Keep | ForEach-Object {
                    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                }
            }
        }
    } catch {}
}

# ============================================================
# S6 Shortcut — 桌面快捷方式(目标为 start-dsh.cmd,不绑定 node 绝对路径)
# ============================================================
function Invoke-S6-Shortcut {
    $t0 = Get-Date
    Write-Host 'Stage 6/7  Shortcut' -ForegroundColor White
    $launcherCmd = Join-Path $script:Cfg.installRoot 'launcher\start-dsh.cmd'
    $desktop = [Environment]::GetFolderPath('Desktop')
    $lnkPath = Join-Path $desktop 'DeepSeek Harness.lnk'
    try {
        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut($lnkPath)
        $sc.TargetPath = $launcherCmd
        $sc.WorkingDirectory = $script:Cfg.workspaceDir
        $sc.Description = 'DeepSeek Harness One-Click Launcher'
        $sc.WindowStyle = 7  # 最小化启动控制台窗口
        $sc.Save()
        if (Test-Path $lnkPath) {
            Show-Result 'PASS' ("桌面快捷方式已创建: {0}" -f $lnkPath)
            Record-Stage 'S6' 'PASS' -DurationMs ([int]((Get-Date)-$t0).TotalMilliseconds)
        } else {
            throw 'shortcut file not found after save'
        }
    } catch {
        # 快捷方式失败降级为 WARN,不阻断安装(E008)
        Show-Result 'WARN' '桌面快捷方式创建失败,可稍后从 launcher\start-dsh.cmd 手动创建。' 'DSH-E008'
        Write-Log 'WARN' 'S6' ("shortcut failed: {0}" -f $_.Exception.Message) 'DSH-E008'
        Record-Stage 'S6' 'WARN' -ErrorId 'DSH-E008' -DurationMs ([int]((Get-Date)-$t0).TotalMilliseconds)
    }
}
function Show-Summary {
    $get = { param($s) ($script:StageResults | Where-Object { $_.stage -eq $s } | Select-Object -Last 1) }
    Write-Host ''
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host ' Installation Complete' -ForegroundColor Cyan
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host ('Node.js:            {0} ({1})' -f $script:Cfg.nodeVersion, $script:Cfg.nodeMode)
    Write-Host ('npm / registry:     PASS')
    Write-Host ('DeepSeek Harness:   {0}' -f $script:Cfg.dshVersion)
    Write-Host ('Launcher:           PASS')
    $scStatus = ((& $get 'S6') | ForEach-Object { $_.status })
    if (-not $scStatus) { $scStatus = 'N/A' }
    Write-Host ('Desktop Shortcut:   {0}' -f $scStatus)
    $webStatus = ((& $get 'S7') | ForEach-Object { $_.status })
    Write-Host ('Web UI:             {0}' -f $webStatus)
    Write-Host ''
    Write-Host '安全提示: 请勿在终端输入 API Key。' -ForegroundColor Yellow
    Write-Host '安装完成后,请在 Harness Web UI 的 Settings -> Models 中自行配置模型/API。' -ForegroundColor Yellow
    Write-Host ('启动方式: 运行 {0}' -f (Join-Path $script:Cfg.installRoot 'launcher\start-dsh.cmd'))
    Write-Host ('工作目录: {0}(进入 Web UI 后请选择你真正要操作的项目目录)' -f $script:Cfg.workspaceDir)
    Write-Host ('日志:     {0}' -f $script:LogFile)
    Write-Host '=================================================='
}

# ============================================================
# 主流程
# ============================================================
function Main {
    $script:Cfg.arch = Get-Arch
    Invoke-S1-SystemCheck
    Show-Header
    Invoke-S2-Node
    Invoke-S3-Npm
    Invoke-S0-Probe
    $launcher = Invoke-S5-Launcher
    Invoke-S6-Shortcut
    Save-Config
    Invoke-S7-Verification $launcher
    Save-Config
    Rotate-Logs 10
    Show-Summary
}

try {
    if ($SelfTest) {
        $fail = 0
        Write-Host 'SelfTest: Test-NodeCompatible' -ForegroundColor White
        $cases = @(
            @{ v='v20.11.0';  exp=$false; name='Case B: Node 20 不兼容' },
            @{ v='v22.18.0';  exp=$false; name='22.18 < 22.19 不兼容' },
            @{ v='v22.19.0';  exp=$true;  name='Case C: 22.19.0 兼容' },
            @{ v='v22.20.5';  exp=$true;  name='22.20 兼容' },
            @{ v='v23.5.0';   exp=$false; name='23.x 不兼容(低于 24)' },
            @{ v='v24.0.0';   exp=$true;  name='Case D: 24.0 兼容' },
            @{ v='v24.19.0';  exp=$true;  name='24.19 兼容' },
            @{ v='v25.1.0';   exp=$true;  name='25.x 复用兼容' }
        )
        foreach ($c in $cases) {
            $got = Test-NodeCompatible $c.v
            $ok = ($got -eq $c.exp)
            if (-not $ok) { $fail++ }
            $st = if ($ok) { 'PASS' } else { 'FAIL' }
            Show-Result $st ("{0} → {1} (期望 {2})" -f $c.name, $got, $c.exp)
        }

        Write-Host 'SelfTest: Get-DshUrl' -ForegroundColor White
        $sampleToken = 'unit-test-token-value'
        $detected = Get-DshUrl -OutputLines @(
            'booting...',
            ("dsh web: http://127.0.0.1:3080/?token={0}&mode=test" -f $sampleToken)
        ) -FallbackPort 3080
        $urlOk = ($detected.Source -eq 'detected' -and $detected.HasToken -and $detected.Port -eq 3080 -and $detected.Url -match [regex]::Escape("token=$sampleToken"))
        if (-not $urlOk) { $fail++ }
        Show-Result $(if ($urlOk) { 'PASS' } else { 'FAIL' }) ("检测 URL: source={0} hasToken={1} port={2}" -f $detected.Source, $detected.HasToken, $detected.Port)

        $localhost = Get-DshUrl -OutputLines @('Open http://localhost:3080/ui?token=abc123') -FallbackPort 3080
        $localhostOk = ($localhost.Source -eq 'detected' -and $localhost.HasToken -and $localhost.Url -match '/ui\?token=abc123')
        if (-not $localhostOk) { $fail++ }
        Show-Result $(if ($localhostOk) { 'PASS' } else { 'FAIL' }) ("localhost URL 保留 path/query: {0}" -f $localhostOk)

        $fallback = Get-DshUrl -OutputLines @('no URL here') -FallbackPort 3080 -AllowFallback
        $fallbackOk = ($fallback.Source -eq 'fallback' -and -not $fallback.HasToken -and $fallback.Port -eq 3080)
        if (-not $fallbackOk) { $fail++ }
        Show-Result $(if ($fallbackOk) { 'PASS' } else { 'FAIL' }) ("fallback 明确标记: source={0}" -f $fallback.Source)

        $redacted = Protect-Sensitive ("http://127.0.0.1:3080/?token={0}" -f $sampleToken)
        $redactOk = ($redacted -notmatch [regex]::Escape($sampleToken))
        if (-not $redactOk) { $fail++ }
        Show-Result $(if ($redactOk) { 'PASS' } else { 'FAIL' }) ("日志 token 脱敏: {0}" -f $redactOk)

        Write-Host 'SelfTest: Select-NodeVersion (需联网)' -ForegroundColor White
        try {
            $script:Cfg.arch = 'x64'
            $sel = Select-NodeVersion
            $comp = Test-NodeCompatible $sel.version
            $st = if ($comp) { 'PASS' } else { 'FAIL' }
            if (-not $comp) { $fail++ }
            Show-Result $st ("选版结果: {0} fallback={1} 兼容={2}" -f $sel.version, $sel.fallback, $comp)
        } catch {
            Show-Result 'WARN' ("选版联网失败(不计入断言): {0}" -f $_.Exception.Message)
        }
        Write-Host ''
        if ($fail -eq 0) { Write-Host 'SelfTest RESULT: ALL PASS' -ForegroundColor Green; exit 0 }
        else { Write-Host ("SelfTest RESULT: {0} FAILED" -f $fail) -ForegroundColor Red; exit 1 }
    }
    Main
} catch {
    # 兜底未预期异常 → E999
    $tech = ($_ | Out-String)
    Stop-WithError 'DSH-E999' '安装过程中发生未预期错误。请把 Error ID 和日志发给技术支持。' $tech
}
