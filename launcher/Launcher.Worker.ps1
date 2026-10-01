param([Parameter(Mandatory=$true)][string]$RequestPath)
$ErrorActionPreference = 'Stop'
$resultPath = $RequestPath + '.result.json'
$mutex = $null; $locked = $false
try {
    . (Join-Path $PSScriptRoot 'Launcher.Core.ps1')
    $request = Read-JsonFile $RequestPath
    Remove-Item -LiteralPath $RequestPath -Force
    $mutex = New-Object Threading.Mutex($false, 'Local\AZPC-Launcher-Operation')
    try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { throw 'Another AZPC operation is already running.' }
    $result = Invoke-LauncherAction $request
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    exit 0
} catch {
    @{ ok = $false; message = $_.Exception.Message } | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8
    exit 1
} finally {
    if (Test-Path -LiteralPath $RequestPath) { Remove-Item -LiteralPath $RequestPath -Force }
    if ($locked) { $mutex.ReleaseMutex() }
    if ($mutex) { $mutex.Dispose() }
}
