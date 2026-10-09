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
Assert (($output -join "`n") -match 'range planning, Content-Range') 'desktop download range self-test'
$installerText = [IO.File]::ReadAllText($installer)
Assert ($installerText -match 'Invoke-DesktopParallelDownload' -and $installerText -match 'Start-Job -ScriptBlock \$worker') 'desktop installer supports parallel HTTP range download'
Assert ($installerText -match 'Invoke-DesktopSingleDownload' -and $installerText -match 'FileMode]::Append') 'desktop installer resumes partial downloads'

function Test-ParallelDownloadResume {
    $fixture = Join-Path ([IO.Path]::GetTempPath()) ('DeepSeekHarnessDesktop-RangeTest-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixture | Out-Null
    $dataPath = Join-Path $fixture 'payload.bin'
    $partialPath = Join-Path $fixture 'payload.part'
    $readyPath = Join-Path $fixture 'ready.txt'
    $stopPath = Join-Path $fixture 'stop.txt'
    $requestLog = Join-Path $fixture 'requests.log'
    $payload = New-Object byte[] (8 * 1MB)
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $random.GetBytes($payload) } finally { $random.Dispose() }
    [IO.File]::WriteAllBytes($dataPath, $payload)
    [IO.File]::WriteAllBytes($partialPath, $payload[0..(1MB - 1)])
    $serverJob = $null
    try {
        $serverJob = Start-Job -ArgumentList $dataPath,$readyPath,$stopPath,$requestLog -ScriptBlock {
            param($DataPath,$ReadyPath,$StopPath,$RequestLog)
            $ErrorActionPreference = 'Stop'
            $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
            $listener.Start()
            [IO.File]::WriteAllText($ReadyPath, [string]$listener.LocalEndpoint.Port)
            $bytes = [IO.File]::ReadAllBytes($DataPath)
            while (-not (Test-Path -LiteralPath $StopPath)) {
                if (-not $listener.Pending()) { Start-Sleep -Milliseconds 25; continue }
                $client = $listener.AcceptTcpClient()
                $stream = $client.GetStream()
                $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::ASCII, $false, 1024, $true)
                try {
                    $requestLine = $reader.ReadLine()
                    if (-not $requestLine) { $client.Close(); continue }
                    $method = $requestLine.Split(' ')[0]; $requestPath = $requestLine.Split(' ')[1]
                    $rangeStart = $null; $rangeEnd = $null
                    while ($true) {
                        $header = $reader.ReadLine()
                        if ($null -eq $header -or $header -eq '') { break }
                        if ($header -match '(?i)^Range:\s*bytes=(\d+)-(\d+)') {
                            $rangeStart = [long]$Matches[1]; $rangeEnd = [long]$Matches[2]
                        }
                    }
                    Add-Content -LiteralPath $RequestLog -Value ('{0} {1}-{2}' -f $method,$rangeStart,$rangeEnd)
                    if ($method -eq 'HEAD') {
                        $rangeCapability = if ($requestPath -eq '/single') { '' } else { "Accept-Ranges: bytes`r`n" }
                        $response = "HTTP/1.1 200 OK`r`nContent-Length: $($bytes.Length)`r`n$rangeCapability" + "Connection: close`r`n`r`n"
                        $headerBytes = [Text.Encoding]::ASCII.GetBytes($response)
                        $stream.Write($headerBytes, 0, $headerBytes.Length)
                    } elseif ($null -ne $rangeStart) {
                        $length = [int]($rangeEnd - $rangeStart + 1)
                        $response = "HTTP/1.1 206 Partial Content`r`nContent-Length: $length`r`nContent-Range: bytes $rangeStart-$rangeEnd/$($bytes.Length)`r`nAccept-Ranges: bytes`r`nConnection: close`r`n`r`n"
                        $headerBytes = [Text.Encoding]::ASCII.GetBytes($response)
                        $stream.Write($headerBytes, 0, $headerBytes.Length)
                        $stream.Write($bytes, [int]$rangeStart, $length)
                    } else {
                        $response = "HTTP/1.1 200 OK`r`nContent-Length: $($bytes.Length)`r`nAccept-Ranges: bytes`r`nConnection: close`r`n`r`n"
                        $headerBytes = [Text.Encoding]::ASCII.GetBytes($response)
                        $stream.Write($headerBytes, 0, $headerBytes.Length)
                        $stream.Write($bytes, 0, $bytes.Length)
                    }
                    $stream.Flush()
                } finally {
                    $reader.Dispose()
                    $client.Close()
                }
            }
            $listener.Stop()
        }
        $deadline = (Get-Date).AddSeconds(10)
        while (-not (Test-Path -LiteralPath $readyPath) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 50 }
        if (-not (Test-Path -LiteralPath $readyPath)) { throw 'local range fixture did not start' }

        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$errors)
        $functionNames = @('Write-Event','Stop-Desktop','Get-Sha512Base64','Get-DesktopRangePlan','Test-DesktopContentRange','Format-DesktopDuration','Invoke-DesktopSingleDownload','Invoke-DesktopParallelDownload')
        $definitions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $functionNames -contains $node.Name }, $true) | ForEach-Object { $_.Extent.Text })
        if ($definitions.Count -ne $functionNames.Count) { throw 'could not load desktop downloader functions for local test' }
        foreach ($definition in $definitions) { Invoke-Expression $definition }
        $script:logPath = $null
        $port = Get-Content -LiteralPath $readyPath -Raw
        Invoke-DesktopParallelDownload ('http://127.0.0.1:{0}/parallel' -f $port) $partialPath $payload.Length
        if ((Get-Sha512Base64 $partialPath) -cne (Get-Sha512Base64 $dataPath)) { throw 'resumed parallel download SHA-512 mismatch' }
        $requests = @(Get-Content -LiteralPath $requestLog)
        if ($requests.Count -ne 5 -or $requests[0] -notmatch '^HEAD' -or @($requests | Where-Object { $_ -match '^GET' }).Count -ne 4) {
            throw ('unexpected local parallel request pattern: ' + ($requests -join ', '))
        }

        $singlePartialPath = Join-Path $fixture 'single.part'
        [IO.File]::WriteAllBytes($singlePartialPath, $payload[0..(1MB - 1)])
        Invoke-DesktopParallelDownload ('http://127.0.0.1:{0}/single' -f $port) $singlePartialPath $payload.Length
        if ((Get-Sha512Base64 $singlePartialPath) -cne (Get-Sha512Base64 $dataPath)) { throw 'single connection resume SHA-512 mismatch' }
        $requests = @(Get-Content -LiteralPath $requestLog)
        if ($requests.Count -ne 7 -or $requests[5] -notmatch '^HEAD' -or $requests[6] -notmatch '^GET 1048576-') {
            throw ('unexpected local single connection request pattern: ' + ($requests -join ', '))
        }
    } finally {
        [IO.File]::WriteAllText($stopPath, 'stop')
        if ($serverJob) {
            Wait-Job $serverJob -Timeout 5 | Out-Null
            if ($serverJob.State -eq 'Running') { Stop-Job $serverJob }
            Remove-Job $serverJob -Force -ErrorAction SilentlyContinue
        }
        $expectedPrefix = Join-Path ([IO.Path]::GetTempPath()) 'DeepSeekHarnessDesktop-RangeTest-'
        if ($fixture.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Test-ParallelDownloadResume
Assert $true 'desktop parallel and fallback downloads resume an existing prefix and verify exact SHA-512'

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
