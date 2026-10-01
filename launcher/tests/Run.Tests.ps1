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
    $privateJobs=Join-Path $testRoot 'private-jobs'
    Initialize-PrivateJobsDirectory $privateJobs
    $acl=[IO.Directory]::GetAccessControl($privateJobs,[Security.AccessControl.AccessControlSections]::Access)
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
    Assert $acl.AreAccessRulesProtected 'Job directory disables inherited permissions'
    $rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    Assert (@($rules | Where-Object { $_.IdentityReference -eq $sid -and $_.AccessControlType -eq 'Allow' -and ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq [Security.AccessControl.FileSystemRights]::FullControl }).Count -gt 0) 'Current user can read and write private jobs'
    Initialize-PrivateJobsDirectory $privateJobs
    Assert (Test-Path $privateJobs) 'Private job permissions can be initialized again on upgrade'
    # Reproduce a standard-user token with all optional privileges removed, including SeSecurityPrivilege.
    Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class AzpcRestrictedToken {
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool CreateRestrictedToken(IntPtr existing, uint flags, uint disableCount, IntPtr disable, uint deleteCount, IntPtr delete, uint restrictCount, IntPtr restrict, out IntPtr token);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
    public static IntPtr Create() {
        IntPtr original, limited;
        if(!OpenProcessToken(Process.GetCurrentProcess().Handle, 0x000A, out original)) throw new Win32Exception();
        try {
            if(!CreateRestrictedToken(original,1,0,IntPtr.Zero,0,IntPtr.Zero,0,IntPtr.Zero,out limited)) throw new Win32Exception();
            return limited;
        } finally { CloseHandle(original); }
    }
}
'@
    $token=[AzpcRestrictedToken]::Create()
    $context=$null
    try {
        $context=[Security.Principal.WindowsIdentity]::Impersonate($token)
        Initialize-PrivateJobsDirectory (Join-Path $testRoot 'no-privilege-jobs')
        Assert (Test-Path (Join-Path $testRoot 'no-privilege-jobs')) 'Launcher job setup succeeds without SeSecurityPrivilege'
    } finally {
        if($context){ $context.Undo(); $context.Dispose() }
        $null=[AzpcRestrictedToken]::CloseHandle($token)
    }
    # Validate every shipped PowerShell script without executing installers or watchers.
    Get-ChildItem $script:AppRoot -Filter '*.ps1' -Recurse | Where-Object { $_.FullName -notmatch '\\(dist|output)\\' } | ForEach-Object {
        $tokens=$null; $errors=$null
        $null=[Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors)
        Assert ($errors.Count -eq 0) ('PowerShell syntax: '+$_.Name+' '+($errors | Out-String))
    }
    Must-Throw { Assert-ReleaseUrl 'https://evil.example/update.zip' } 'AZPC GitHub release'
    Must-Throw { Assert-ReleaseUrl 'https://github.com/other/repo/releases/download/v1/bundle.zip' } 'AZPC GitHub release'
    Must-Throw { Assert-Version 'latest' } 'invalid version'
    $manifest=@{schema=1;game='tbc-anniversary';addonVersion='0.4.29';watcherVersion='0.4.28';launcherVersion='0.1.1';bundleUrl='https://github.com/KevinFehrenbach1/azpc-client/releases/download/test/azpc-components.zip';bundleSha256=('a'*64)}
    Test-Manifest $manifest
    $bad=$manifest.Clone(); $bad.game='retail'
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
    Assert (@(Get-ChildItem (Join-Path $wow '_anniversary_\Interface\AZPC-Backups') -Directory).Count -eq 1) 'Previous addon backed up'
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
    $realWaitWatcherStarted = ${function:Wait-LauncherWatcherStarted}
    # Account/cache preservation is isolated from live process startup.
    function Wait-LauncherWatcherStarted { }
    Install-Watcher $payload $wow ''
    foreach($p in $hashes.Keys) { Assert ((Get-FileHash $p).Hash -eq $hashes[$p]) ('Watcher update preserves '+(Split-Path -Leaf $p)) }
    $watcher=Join-Path $profile.Watcher 'AZPC-Watcher.ps1'
    $before=(Get-FileHash $watcher).Hash
    function Install-AzpcStartupTask { return $false }
    Must-Throw { Install-Watcher $payload $wow '' } 'startup'
    Assert ((Get-FileHash $watcher).Hash -eq $before) 'Watcher restored after startup failure'
    foreach($p in $hashes.Keys) { Assert ((Get-FileHash $p).Hash -eq $hashes[$p]) ('Failed update preserves '+(Split-Path -Leaf $p)) }
    # Watcher control regressions use fake processes, never start the network watcher.
    Set-Item Function:\Wait-LauncherWatcherStarted $realWaitWatcherStarted
    $script:watcherProcesses = @([pscustomobject]@{
        ProcessId=424242; Name='powershell.exe'; CommandLine=('powershell.exe -File "'+$watcher+'"')
    })
    function Get-CimInstance { param($ClassName,$Filter,$ErrorAction) return $script:watcherProcesses }
    $heartbeatPath=Join-Path $profile.State 'watcher-heartbeat.json'
    @{pid=424242;status='running';updatedAt=[DateTimeOffset]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content $heartbeatPath
    Wait-LauncherWatcherStarted $profile
    Assert (Get-InstalledStatus $wow).Running 'Live watcher with current matching heartbeat is detected'
    Set-Content $heartbeatPath '{"pid":'
    Assert (Get-InstalledStatus $wow).Running 'Partial heartbeat JSON does not hide a live watcher'
    $script:watcherProcesses=@()
    Assert (-not (Get-InstalledStatus $wow).Running) 'No process means stopped despite existing heartbeat file'
    $script:watcherProcesses=@([pscustomobject]@{ProcessId=424242;Name='pwsh.exe';CommandLine=('pwsh.exe -File "'+$watcher+'"')})
    Assert (Get-InstalledStatus $wow).Running 'PowerShell Core watcher is detected'
    $script:watcherProcesses+= [pscustomobject]@{ProcessId=424243;Name='powershell.exe';CommandLine=('powershell.exe -File "'+$watcher+'"')}
    Must-Throw { Wait-LauncherWatcherStarted $profile } 'Multiple watcher processes'
    function Stop-Process { param($Id,[switch]$Force,$ErrorAction) $script:watcherProcesses=@($script:watcherProcesses | Where-Object { $_.ProcessId -ne $Id }) }
    Stop-Watcher
    Assert ($script:watcherProcesses.Count -eq 0) 'Stop ends every matching watcher process'
    # Advance only the polling clock so startup failure tests do not wait 20 seconds.
    $script:pollClock=[DateTime]::UtcNow
    function Get-Date { $script:pollClock=$script:pollClock.AddSeconds(30); return $script:pollClock }
    function Start-Sleep { param($Milliseconds) }
    function Install-AzpcStartupTask { return $true }
    Must-Throw { Start-Watcher $wow } 'startup was not confirmed'
    $script:watcherProcesses=@([pscustomobject]@{ProcessId=424242;Name='powershell.exe';CommandLine=('powershell.exe -File "'+$watcher+'"')})
    @{pid=424242;status='running';updatedAt=[DateTimeOffset]::UtcNow.AddMinutes(-5).ToString('o')} | ConvertTo-Json | Set-Content $heartbeatPath
    Must-Throw { Wait-LauncherWatcherStarted $profile } 'startup was not confirmed'
    @{pid=111111;status='running';updatedAt=[DateTimeOffset]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content $heartbeatPath
    Must-Throw { Wait-LauncherWatcherStarted $profile } 'startup was not confirmed'
    Remove-Item Function:\Get-CimInstance,Function:\Stop-Process,Function:\Get-Date,Function:\Start-Sleep
    Remove-Item $credentials,$identity
    Must-Throw { Install-Watcher $payload $wow '' } 'setup code'
    # Safe extraction tests use a fake network download and real ZIP/checksum logic.
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    $script:testZip=Join-Path $testRoot 'unsafe.zip'
    $zip=[IO.Compression.ZipFile]::Open($script:testZip,[IO.Compression.ZipArchiveMode]::Create)
    $entry=$zip.CreateEntry('../escaped.ps1'); $writer=New-Object IO.StreamWriter($entry.Open()); $writer.Write('bad'); $writer.Dispose(); $zip.Dispose()
    function Invoke-WebRequest { param([switch]$UseBasicParsing,$Uri,$OutFile,$TimeoutSec,$Headers) Copy-Item $script:testZip $OutFile }
    $work=Join-Path $testRoot 'download'; New-Item -ItemType Directory $work | Out-Null
    $manifest.bundleSha256=(Get-FileHash $script:testZip).Hash
    Must-Throw { Get-UpdatePayload $manifest $work } 'unsafe file'
    $script:testZip=Join-Path $testRoot 'valid.zip'
    $tbcPackage=Join-Path $testRoot 'tbc-package'
    New-Item -ItemType Directory (Join-Path $tbcPackage 'addon') -Force | Out-Null
    Copy-Item (Join-Path $payload 'addon/AZPC') (Join-Path $tbcPackage 'addon') -Recurse
    Copy-Item (Join-Path $payload 'watcher'),(Join-Path $payload 'VERSION.json') $tbcPackage -Recurse
    Compress-Archive -Path (Join-Path $tbcPackage '*') -DestinationPath $script:testZip
    $manifest.bundleSha256=(Get-FileHash $script:testZip).Hash
    $validWork=Join-Path $testRoot 'valid-download'; New-Item -ItemType Directory $validWork | Out-Null
    $extracted=Get-UpdatePayload $manifest $validWork
    Assert ((Get-FileHash (Join-Path $extracted 'addon\AZPC\AZPC.lua')).Hash -eq (Get-FileHash (Join-Path $payload 'addon\AZPC\AZPC.lua')).Hash) 'Valid release bundle extracted and matched its source'
    $manifest.bundleSha256=('0'*64)
    Must-Throw { Get-UpdatePayload $manifest $work } 'checksum mismatch'
    Assert (-not (Test-Path (Join-Path $testRoot 'escaped.ps1'))) 'Archive path traversal did not write files'
    # Tagged-source compatibility uses an immutable commit and verifies every downloaded component.
    $sourceManifest=@{schema=2;game='tbc-anniversary';addonVersion='0.4.29';watcherVersion='0.4.28';launcherVersion='0.2.0';sourceCommit=('a'*40);files=@()}
    foreach($path in @('addon/AZPC/AZPC.lua','addon/AZPC/AZPC.toc','watcher/AZPC-Watcher.ps1','VERSION.json')) {
        $sourceManifest.files+=@{path=$path;sha256=(Get-FileHash (Join-Path $payload $path) -Algorithm SHA256).Hash}
    }
    function Invoke-WebRequest { param([switch]$UseBasicParsing,$Uri,$OutFile,$TimeoutSec,$Headers)
        $path=([string]$Uri).Split(@('/installer/payload/'),[StringSplitOptions]::None)[1]
        Copy-Item -LiteralPath (Join-Path $payload $path) -Destination $OutFile
    }
    $sourceWork=Join-Path $testRoot 'source-download'; New-Item -ItemType Directory $sourceWork | Out-Null
    $extracted=Get-UpdatePayload $sourceManifest $sourceWork
    Assert ((Get-FileHash (Join-Path $extracted 'watcher/AZPC-Watcher.ps1')).Hash -eq (Get-FileHash (Join-Path $payload 'watcher/AZPC-Watcher.ps1')).Hash) 'Tagged release watcher download validated'
    $bad=$sourceManifest.Clone(); $bad.sourceCommit='main'
    Must-Throw { Test-Manifest $bad } 'source commit'
    $bad=$sourceManifest.Clone(); $bad.files=@(@{path='../escaped.ps1';sha256=('a'*64)})
    Must-Throw { Test-Manifest $bad } 'source file'
    $sourceManifest.files[0].sha256=('0'*64)
    Must-Throw { Get-UpdatePayload $sourceManifest $sourceWork } 'checksum mismatch'
    # Exercise the release lookup fallback without contacting the live API in a unit test.
    function Invoke-RestMethod { param($Uri,$Headers,$TimeoutSec)
        if($Uri -like '*/releases/latest'){ return [pscustomobject]@{tag_name='v0.4.76';assets=@()} }
        if($Uri -like '*/commits/*'){ return [pscustomobject]@{sha=('b'*40)} }
        $path=(([string]$Uri).Split(@('/installer/payload/'),[StringSplitOptions]::None)[1]).Split('?')[0]
        $bytes=[IO.File]::ReadAllBytes((Join-Path $payload $path))
        return [pscustomobject]@{encoding='base64';size=$bytes.Length;content=[Convert]::ToBase64String($bytes)}
    }
    $releaseManifest=Get-RemoteManifest
    Assert ($releaseManifest.schema -eq 2 -and $releaseManifest.addonVersion -eq '0.4.29' -and $releaseManifest.sourceCommit -eq ('b'*40)) 'Existing release resolved to pinned source versions'
    Write-Host 'All launcher checks passed.'
    # Forever installs only into beta; both games' SavedVariables and addons survive.
    $beta=Join-Path $wow '_classic_beta_'
    New-Item -ItemType Directory -Path (Join-Path $beta 'WTF/Account/Test/SavedVariables') -Force | Out-Null
    $foreverSaved=Join-Path $beta 'WTF/Account/Test/SavedVariables/AZPCForever.lua'
    Set-Content $foreverSaved 'forever-history-sentinel'
    $beforeTbc=(Get-FileHash (Join-Path $wow '_anniversary_/Interface/AddOns/AZPC/AZPC.lua')).Hash
    $null=Assert-WowRoot $wow 'forever'
    Install-Addon $payload $wow 'forever'
    Assert (Test-Path (Join-Path $beta 'Interface/AddOns/AZPCForever/AZPCForever.toc')) 'Forever addon installs in beta'
    Assert ((Get-Content $foreverSaved -Raw).Trim() -eq 'forever-history-sentinel') 'Forever SavedVariables preserved'
    Assert ((Get-FileHash (Join-Path $wow '_anniversary_/Interface/AddOns/AZPC/AZPC.lua')).Hash -eq $beforeTbc) 'Forever install leaves TBC addon unchanged'
    Assert ((Get-InstalledStatus $wow 'forever').Addon -eq '0.1.1') 'Forever version detection'
    $foreverPackage=Join-Path $testRoot 'forever-package'
    New-Item -ItemType Directory (Join-Path $foreverPackage 'addon') -Force | Out-Null
    Copy-Item (Join-Path $payload 'addon/AZPCForever') (Join-Path $foreverPackage 'addon') -Recurse
    Copy-Item (Join-Path $payload 'watcher') $foreverPackage -Recurse
    @{game='forever';addonVersion='0.1.1';watcherVersion='0.4.28'} | ConvertTo-Json | Set-Content (Join-Path $foreverPackage 'VERSION.json')
    $script:testZip=Join-Path $testRoot 'forever.zip'
    Compress-Archive -Path (Join-Path $foreverPackage '*') -DestinationPath $script:testZip
    $foreverManifest=@{schema=1;game='forever';addonVersion='0.1.1';watcherVersion='0.4.28';launcherVersion='0.2.3';bundleUrl='https://github.com/KevinFehrenbach1/azpc-client/releases/download/test/azpc-forever-components.zip';bundleSha256=(Get-FileHash $script:testZip).Hash}
    $foreverWork=Join-Path $testRoot 'forever-download';New-Item -ItemType Directory $foreverWork | Out-Null
    function Invoke-WebRequest { param([switch]$UseBasicParsing,$Uri,$OutFile,$TimeoutSec,$Headers) Copy-Item $script:testZip $OutFile }
    $foreverPayload=Get-UpdatePayload $foreverManifest $foreverWork
    Assert (Test-Path (Join-Path $foreverPayload 'addon/AZPCForever/AZPCForever.lua')) 'Verified Forever release download'
    $result=Invoke-LauncherAction @{game='forever';action='addon';wowRoot=$wow;setupCode='';manifest=$null}
    Assert $result.ok 'Forever bundled installation through launcher action'
} finally { $env:LOCALAPPDATA=$oldLocal; Remove-Item -LiteralPath $testRoot -Recurse -Force }

