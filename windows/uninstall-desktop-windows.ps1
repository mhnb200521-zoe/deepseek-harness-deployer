$ErrorActionPreference = 'Continue'
$base = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
$found = $null
foreach ($key in Get-ChildItem -Path $base -ErrorAction SilentlyContinue) {
    $entry = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
    if ($entry -and [string]$entry.DisplayName -like 'DeepSeek Harness*' -and $entry.InstallLocation) {
        $app = Join-Path ([string]$entry.InstallLocation) 'DeepSeek Harness.exe'
        $sig = if (Test-Path -LiteralPath $app -PathType Leaf) { Get-AuthenticodeSignature -LiteralPath $app } else { $null }
        if ($sig -and $sig.Status -eq 'Valid' -and $sig.SignerCertificate -and $sig.SignerCertificate.Subject -match 'DeepSeek Artificial Intelligence') {
            $found = $entry
            break
        }
    }
}
if (-not $found) {
    Write-Host '[WARN] 未找到可验证的官方 DeepSeek Harness Desktop 安装。没有删除任何文件。' -ForegroundColor Yellow
    exit 0
}
Write-Host ('检测到官方桌面版 {0}。' -f $found.DisplayVersion) -ForegroundColor Cyan
Write-Host '即将打开 Windows“已安装的应用”设置。请只卸载 DeepSeek Harness；此脚本不会删除用户数据、旧 Web 版或 Node.js。'
Start-Process 'ms-settings:appsfeatures'
