$ErrorActionPreference='Stop'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('azpc-tests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $testRoot | Out-Null
$oldLocal=$env:LOCALAPPDATA
$env:LOCALAPPDATA=$testRoot
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Launcher.Core.ps1')
function Assert([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message }; Write-Host ('PASS: '+$Message) }
function Must-Throw([scriptblock]$Action,[string]$Pattern) {
    try { & $Action; throw 'Expected failure did not occur' } catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }; Write-Host ('PASS: rejection '+$Pattern)
    }
}
try {
    # Validate every shipped PowerShell script without executing installers or watchers.
    Get-ChildItem $script:AppRoot -Filter '*.ps1' -Recurse | Where-Object { $_.FullName -notmatch '\\(dist|output)\\' } | ForEach-Object {
        $tokens=$null; $errors=$null
        $null=[Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors)
        Assert ($errors.Count -eq 0) ('PowerShell syntax: '+$_.Name+' '+($errors | Out-String))
    }
    Must-Throw { Assert-ReleaseUrl 'https://evil.example/update.zip' } 'AZPC GitHub release'
    Must-Throw { Assert-ReleaseUrl 'https://github.com/other/repo/releases/download/v1/bundle.zip' } 'AZPC GitHub release'
    Must-Throw { Assert-Version 'latest' } 'invalid version'
    $manifest=@{schema=1;game='tbc-anniversary';addonVersion='0.4.29';watcherVersion='0.4.25';launcherVersion='0.1.0';bundleUrl='https://github.com/KevinFehrenbach1/azpc-client/releases/download/test/azpc-components.zip';bundleSha256=('a'*64)}
    Test-Manifest $manifest
    $bad=$manifest.Clone(); $bad.game='forever'
    Must-Throw { Test-Manifest $bad } 'Unsupported'
    $bad=$manifest.Clone(); $bad.bundleSha256=''
    Must-Throw { Test-Manifest $bad } 'checksum'
    $wow=Join-Path $testRoot 'Custom WoW path'
    $wtf=Join-Path $wow '_anniversary_\WTF\Account\Test\SavedVariables'
    New-Item -ItemType Directory -Path $wtf -Force | Out-Null
    $saved=Join-Path $wtf 'AZPC.lua'; Set-Content $saved 'trading-history-must-survive'
    $savedHash=(Get-FileHash $saved).Hash
    Assert ((Assert-WowRoot $wow) -eq $wow) 'Custom WoW installation accepted'
    Must-Throw { Assert-WowRoot $testRoot } 'contains _anniversary_'
    $payload=Join-Path $script:AppRoot 'installer\payload'
    Install-Addon $payload $wow
    $addon=Join-Path $wow '_anniversary_\Interface\AddOns\AZPC\AZPC.lua'
    Set-Content $addon 'old-addon'
    Install-Addon $payload $wow
    Assert (@(Get-ChildItem (Join-Path $script:ClientRoot 'Backups') -Directory).Count -eq 1) 'Previous addon backed up'
    Assert ((Get-FileHash $saved).Hash -eq $savedHash) 'WoW trading SavedVariables preserved'
    # Force staging rename failure and verify restoration of the previous addon.
    $before=(Get-FileHash $addon).Hash
    function Move-Item {
        param([string]$LiteralPath,[string]$Destination)
        if ((Split-Path -Leaf $LiteralPath) -like 'AZPC-staging-*') { throw 'simulated rename failure' }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination
    }
    Must-Throw { Install-Addon $payload $wow } 'simulated rename'
    Remove-Item Function:\Move-Item
    Assert ((Get-FileHash $addon).Hash -eq $before) 'Addon rollback restored previous files'
    $profile=Get-Profile
    New-Item -ItemType Directory -Path $profile.State,$profile.Watcher -Force | Out-Null
    $credentials=Join-Path $profile.State 'watcher-credentials.json'
    $cache=Join-Path $profile.State 'private-ledger-state.json'
    $identity=Join-Path $profile.State 'private-client-id.txt'
    Set-Content $credentials '{"clientId":"test","watcherToken":"local-test-only"}'
    Set-Content $cache '{"uploaded":["do-not-replay"]}'
    Set-Content $identity 'same-client'
    $hashes=@{}; foreach($p in @($credentials,$cache,$identity)) { $hashes[$p]=(Get-FileHash $p).Hash }
    function Stop-AzpcWatcherInstances { }
    function Install-AzpcStartupTask { return $true }
    Install-Watcher $payload $wow ''
    foreach($p in $hashes.Keys) { Assert ((Get-FileHash $p).Hash -eq $hashes[$p]) ('Watcher update preserves '+(Split-Path -Leaf $p)) }
    $watcher=Join-Path $profile.Watcher 'AZPC-Watcher.ps1'
    $before=(Get-FileHash $watcher).Hash
    function Install-AzpcStartupTask { return $false }
    Must-Throw { Install-Watcher $payload $wow '' } 'startup'
    Assert ((Get-FileHash $watcher).Hash -eq $before) 'Watcher restored after startup failure'
    foreach($p in $hashes.Keys) { Assert ((Get-FileHash $p).Hash -eq $hashes[$p]) ('Failed update preserves '+(Split-Path -Leaf $p)) }
    Remove-Item $credentials,$identity
    Must-Throw { Install-Watcher $payload $wow '' } 'setup code'
    # Safe extraction tests use a fake network download and real ZIP/checksum logic.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $script:testZip=Join-Path $testRoot 'unsafe.zip'
    $zip=[IO.Compression.ZipFile]::Open($script:testZip,[IO.Compression.ZipArchiveMode]::Create)
    $entry=$zip.CreateEntry('../escaped.ps1'); $writer=New-Object IO.StreamWriter($entry.Open()); $writer.Write('bad'); $writer.Dispose(); $zip.Dispose()
    function Invoke-WebRequest { param([switch]$UseBasicParsing,$Uri,$OutFile,$TimeoutSec,$Headers) Copy-Item $script:testZip $OutFile }
    $work=Join-Path $testRoot 'download'; New-Item -ItemType Directory $work | Out-Null
    $manifest.bundleSha256=(Get-FileHash $script:testZip).Hash
    Must-Throw { Get-UpdatePayload $manifest $work } 'unsafe file'
    $manifest.bundleSha256=('0'*64)
    Must-Throw { Get-UpdatePayload $manifest $work } 'checksum mismatch'
    Assert (-not (Test-Path (Join-Path $testRoot 'escaped.ps1'))) 'Archive path traversal did not write files'
    Write-Host 'All launcher checks passed.'
} finally { $env:LOCALAPPDATA=$oldLocal; Remove-Item -LiteralPath $testRoot -Recurse -Force }
