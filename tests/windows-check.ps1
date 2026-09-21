<#
    DeepSeek Harness — 只读环境自检 (Windows, tests)
    Milestone: M2
    只读:不修改任何环境。汇总 OS/arch/Node/npm/D:/port,并调用安装器 -SelfTest 单元断言。
    用法: powershell -ExecutionPolicy Bypass -File windows-check.ps1
#>
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installer = Join-Path (Split-Path $here) 'windows\install-windows.ps1'

function Line([string]$s,[string]$c='Gray'){ Write-Host $s -ForegroundColor $c }

Line ''
Line '==================================================' Cyan
Line ' DeepSeek Harness — 只读环境自检' Cyan
Line '==================================================' Cyan
Line ''

# 环境
$arch = $env:PROCESSOR_ARCHITECTURE; if ($env:PROCESSOR_ARCHITEW6432){$arch=$env:PROCESSOR_ARCHITEW6432}
Line ("OS Arch:   {0}" -f $arch)
$nv=$null; try{$nv=(node -v) 2>$null}catch{}
Line ("Node:      {0}" -f $(if($nv){$nv.Trim()}else{'(none)'}))
$npmv=$null; try{$npmv=(npm -v) 2>$null}catch{}
Line ("npm:       {0}" -f $(if($npmv){$npmv.Trim()}else{'(none)'}))
Line ("D: drive:  {0}" -f $(if(Test-Path 'D:\'){'present'}else{'absent'}))

# 端口 3080
$c=New-Object System.Net.Sockets.TcpClient
$listening=$false
try{$ia=$c.BeginConnect('127.0.0.1',3080,$null,$null); if($ia.AsyncWaitHandle.WaitOne(500,$false) -and $c.Connected){$c.EndConnect($ia);$listening=$true}}catch{}finally{$c.Close()}
Line ("Port 3080: {0}" -f $(if($listening){'listening'}else{'free'}))
Line ''

# 单元断言(委托安装器 SelfTest)
if (Test-Path $installer) {
    Line '运行安装器单元断言 (-SelfTest):' White
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -SelfTest
    $rc = $LASTEXITCODE
    Line ''
    if ($rc -eq 0) { Line 'windows-check: PASS' Green; exit 0 }
    else { Line 'windows-check: FAIL' Red; exit 1 }
} else {
    Line ("未找到安装器: {0}" -f $installer) Red
    exit 1
}
