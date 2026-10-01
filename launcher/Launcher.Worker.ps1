param([Parameter(Mandatory=$true)][string]$RequestPath)
$ErrorActionPreference = 'Stop'
$resultPath = $RequestPath + '.result.json'
$resultTemp = $resultPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
$mutex = $null; $locked = $false
try {
    . (Join-Path $PSScriptRoot 'Launcher.Core.ps1')
    $request = Read-JsonFile $RequestPath
    Remove-Item -LiteralPath $RequestPath -Force
    $mutex = New-Object Threading.Mutex($false, 'Local\AZPC-Launcher-Operation')
    try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { throw 'Another AZPC operation is already running.' }
    $result = Invoke-LauncherAction $request
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultTemp -Encoding UTF8
    Move-Item -LiteralPath $resultTemp -Destination $resultPath -Force
    exit 0
} catch {
    @{ ok = $false; message = $_.Exception.Message } | ConvertTo-Json | Set-Content -LiteralPath $resultTemp -Encoding UTF8
    Move-Item -LiteralPath $resultTemp -Destination $resultPath -Force
    exit 1
} finally {
    if (Test-Path -LiteralPath $resultTemp) { Remove-Item -LiteralPath $resultTemp -Force }
    if (Test-Path -LiteralPath $RequestPath) { Remove-Item -LiteralPath $RequestPath -Force }
    if ($locked) { $mutex.ReleaseMutex() }
    if ($mutex) { $mutex.Dispose() }
}
