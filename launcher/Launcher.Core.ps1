Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$script:ClientRoot = Join-Path $env:LOCALAPPDATA 'AZPC'
$script:AppRoot = Split-Path -Parent $PSScriptRoot
$script:Repo = 'KevinFehrenbach1/azpc-client'
. (Join-Path $script:AppRoot 'installer\payload\INSTALL-AZPC.ps1') -FunctionsOnly

function Initialize-PrivateJobsDirectory([string]$Path) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    # Read and write only the DACL. Set-Acl can request SeSecurityPrivilege to handle auditing,
    # which standard Windows users do not possess. No audit or owner changes are needed here.
    $acl=[IO.Directory]::GetAccessControl($Path,[Security.AccessControl.AccessControlSections]::Access)
    $acl.SetAccessRuleProtection($true,$false)
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
    $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    $acl.SetAccessRule($rule)
    [IO.Directory]::SetAccessControl($Path,$acl)
}

function Read-JsonFile([string]$Path) {
    if (Test-Path -LiteralPath $Path) { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    return $null
}
function Get-Profile {
    $identities = @(Find-ExistingWatcherIdentities)
    if ($identities.Count -gt 1) { throw 'Multiple watcher profiles were found. Use your existing installer to select the correct profile before using this launcher.' }
    $state = $script:ClientRoot
    if ($identities.Count -eq 1) { $state = $identities[0].DirectoryName }
    return @{ State = $state; Watcher = (Resolve-WatcherTargetForStateDir $state) }
}
function Assert-WowRoot([string]$Root, [string]$Game='tbc-anniversary') {
    if ([string]::IsNullOrWhiteSpace($Root)) { throw 'Choose your main World of Warcraft folder first.' }
    $full = [IO.Path]::GetFullPath($Root.Trim())
    if ($full.Contains('"')) { throw 'The folder path contains an unsupported character.' }
    $folder=if($Game -eq 'forever'){'_classic_beta_'}else{'_anniversary_'}
    if (-not (Test-Path -LiteralPath (Join-Path $full $folder) -PathType Container)) {
        throw ('Choose the main WoW folder that contains '+$folder+'.')
    }
    return $full
}
function Assert-GameClosed {
    if (@(Get-Process -Name Wow,WowClassic,WowClassicT,WowB -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Close World of Warcraft before installing or updating. This keeps the addon and saved trading history safe.'
    }
}
function Get-LauncherWatcherProcesses($Profile) {
    $watcherFile = Join-Path $Profile.Watcher 'AZPC-Watcher.ps1'
    return @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.ProcessId -ne $PID -and [string]$_.Name -match '^(powershell|pwsh)(\.exe)?$' -and
        ([string]$_.CommandLine).IndexOf($watcherFile, [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
}
function Read-WatcherHeartbeat($Profile) {
    # The watcher currently writes this file in place. A concurrent read can see partial JSON.
    try { return Read-JsonFile (Join-Path $Profile.State 'watcher-heartbeat.json') } catch { return $null }
}
function Wait-LauncherWatcherStarted($Profile) {
    $deadline = (Get-Date).AddSeconds(20)
    do {
        $processes = @(Get-LauncherWatcherProcesses $Profile)
        $heartbeat = Read-WatcherHeartbeat $Profile
        if ($processes.Count -gt 1) { throw 'Multiple watcher processes are running. Click Stop, then Start again.' }
        if ($processes.Count -eq 1 -and $heartbeat -and $heartbeat.PSObject.Properties['pid'] -and
            [int]$heartbeat.pid -eq [int]$processes[0].ProcessId -and $heartbeat.PSObject.Properties['updatedAt']) {
            $age = [DateTimeOffset]::UtcNow - [DateTimeOffset]::Parse([string]$heartbeat.updatedAt)
            if ($age.TotalSeconds -ge -5 -and $age.TotalSeconds -le 15) { return }
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw ('Watcher startup was not confirmed. Open ' + (Join-Path $Profile.State 'watcher.log') + ' and check the latest lines. No new scan is needed.')
}

function Get-InstalledStatus([string]$Root, [string]$Game='tbc-anniversary') {
    $profile = Get-Profile
    $addonVersion = 'Not installed'; $watcherVersion = 'Not installed'
    if ($Root) {
        $tocPath=if($Game -eq 'forever'){'_classic_beta_\Interface\AddOns\AZPCForever\AZPCForever.toc'}else{'_anniversary_\Interface\AddOns\AZPC\AZPC.toc'}
        $toc = Join-Path $Root $tocPath
        if (Test-Path -LiteralPath $toc) {
            $match = [regex]::Match((Get-Content -LiteralPath $toc -Raw), '(?m)^## Version:\s*(\S+)')
            $addonVersion = if ($match.Success) { $match.Groups[1].Value } else { 'Unknown' }
        }
    }
    $watcherFile = Join-Path $profile.Watcher 'AZPC-Watcher.ps1'
    if (Test-Path -LiteralPath $watcherFile) {
        $match = [regex]::Match((Get-Content -LiteralPath $watcherFile -Raw), 'version\s*=\s*"([0-9.]+)"')
        $watcherVersion = if ($match.Success) { $match.Groups[1].Value } else { 'Unknown' }
    }
    $processes = @(Get-LauncherWatcherProcesses $profile)
    $running = $processes.Count -gt 0
    $activity = if ($running) { 'Watcher process running; waiting for heartbeat' } else { 'Watcher stopped' }
    $heartbeat = Read-WatcherHeartbeat $profile
    if ($heartbeat -and $heartbeat.PSObject.Properties['status'] -and $heartbeat.PSObject.Properties['updatedAt']) {
        $activity = [string]$heartbeat.status + ' | ' + [string]$heartbeat.updatedAt
        if (-not $running) { $activity = 'Watcher stopped | Last heartbeat: ' + [string]$heartbeat.updatedAt }
    }
    if ($processes.Count -gt 1) { $activity = 'Multiple watcher processes running. Click Stop, then Start.' }
    return @{ Addon = $addonVersion; Watcher = $watcherVersion; Running = $running;
        Connected = (Test-Path -LiteralPath (Join-Path $profile.State 'watcher-credentials.json'));
        Activity = $activity; Profile = $profile }
}
function Assert-Version([string]$Value) {
    if ($Value -notmatch '^\d+\.\d+\.\d+(\.\d+)?$') { throw 'The update contains an invalid version number.' }
    return [version]$Value
}
function Assert-ReleaseUrl([string]$Url) {
    $uri = [uri]$Url
    if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'github.com' -or $uri.UserInfo -or
        $uri.AbsolutePath -notmatch '^/KevinFehrenbach1/azpc-client/releases/download/[^/]+/[^/]+$') {
        throw 'Updates must come from an AZPC GitHub release.'
    }
}
function Test-Manifest($Manifest) {
    if ($Manifest.schema -notin @(1,2) -or $Manifest.game -notin @('tbc-anniversary','forever')) { throw 'Unsupported update manifest or game version.' }
    $null = Assert-Version ([string]$Manifest.addonVersion)
    $null = Assert-Version ([string]$Manifest.watcherVersion)
    $null = Assert-Version ([string]$Manifest.launcherVersion)
    if ($Manifest.game -eq 'forever' -and $Manifest.schema -ne 1) { throw 'Unsupported Forever source manifest.' }
    if ($Manifest.schema -eq 2) {
        if ([string]$Manifest.sourceCommit -notmatch '^[a-f0-9]{40}$') { throw 'Invalid release source commit.' }
        $allowed=@('addon/AZPC/AZPC.lua','addon/AZPC/AZPC.toc','watcher/AZPC-Watcher.ps1','VERSION.json')
        $seen=@{}
        foreach($file in $Manifest.files) {
            if ($file.path -notin $allowed -or $seen.ContainsKey([string]$file.path) -or [string]$file.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid release source file or checksum.' }
            $seen[[string]$file.path]=$true
        }
        if($seen.Count -ne 4){ throw 'Release source is incomplete.' }
        return
    }
    Assert-ReleaseUrl ([string]$Manifest.bundleUrl)
    if ([string]$Manifest.bundleSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'The update checksum is missing or invalid.' }
}
function Get-RemoteManifest {
    param([string]$ApiToken='', [string]$Game='tbc-anniversary')
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent' = 'AZPC-Launcher/0.2.21'; Accept = 'application/vnd.github+json' }
    if($ApiToken){ $headers['Authorization']='Bearer '+$ApiToken }
    $release = Invoke-RestMethod -Uri ('https://api.github.com/repos/' + $script:Repo + '/releases/latest') -Headers $headers -TimeoutSec 30
    $manifestName=if($Game -eq 'forever'){'azpc-forever-update.json'}else{'azpc-update.json'}
    $asset = @($release.assets | Where-Object { $_.name -eq $manifestName })
    if($Game -eq 'forever' -and $asset.Count -eq 0){ throw 'The latest release has no Forever addon package. Try again after its release is published.' }
    if ($asset.Count -eq 0) {
        # Compatibility with existing releases: resolve the released tag once, then pin all files to its immutable commit.
        $tag=[uri]::EscapeDataString([string]$release.tag_name)
        $commit=Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$script:Repo+'/commits/'+$tag) -Headers $headers -TimeoutSec 30
        if([string]$commit.sha -notmatch '^[a-f0-9]{40}$'){ throw 'Could not resolve the release commit.' }
        $files=@(); $versionData=$null
        foreach($path in @('addon/AZPC/AZPC.lua','addon/AZPC/AZPC.toc','watcher/AZPC-Watcher.ps1','VERSION.json')) {
            $entry=Invoke-RestMethod -Uri ('https://api.github.com/repos/'+$script:Repo+'/contents/installer/payload/'+$path+'?ref='+$commit.sha) -Headers $headers -TimeoutSec 30
            if($entry.encoding -ne 'base64' -or [long]$entry.size -gt 5242880){ throw 'Release file is missing or too large.' }
            $bytes=[Convert]::FromBase64String([string]$entry.content)
            $hash=[Security.Cryptography.SHA256]::Create()
            try { $digest=([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally { $hash.Dispose() }
            $files+=@{path=$path;sha256=$digest}
            if($path -eq 'VERSION.json'){ $versionData=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json }
        }
        $manifest=@{schema=2;game=$versionData.game;addonVersion=$versionData.addonVersion;watcherVersion=$versionData.watcherVersion;launcherVersion='0.2.21';sourceCommit=[string]$commit.sha;files=$files}
        Test-Manifest $manifest
        return $manifest
    }
    if($asset.Count -ne 1){ throw 'The release includes multiple update manifests.' }
    Assert-ReleaseUrl $asset[0].browser_download_url
    if ([long]$asset[0].size -gt 65536) { throw 'Update manifest is too large.' }
    $manifest = Invoke-RestMethod -Uri $asset[0].browser_download_url -Headers @{ 'User-Agent' = 'AZPC-Launcher/0.2.21' } -TimeoutSec 30
    if($manifest -is [string]){ $manifest=$manifest.TrimStart([char[]]@(0xFEFF,0xEF,0xBB,0xBF)) | ConvertFrom-Json }
    Test-Manifest $manifest
    if($manifest.game -ne $Game){ throw 'Release game does not match your selection.' }
    return $manifest
}
function Get-UpdatePayload($Manifest, [string]$Workspace) {
    Test-Manifest $Manifest
    if($Manifest.schema -eq 2) {
        $target=Join-Path $Workspace 'payload'
        foreach($file in $Manifest.files) {
            $destination=Join-Path $target ([string]$file.path)
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            $url='https://raw.githubusercontent.com/'+$script:Repo+'/'+$Manifest.sourceCommit+'/installer/payload/'+$file.path
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $destination -TimeoutSec 120 -Headers @{'User-Agent'='AZPC-Launcher/0.2.21'}
            if((Get-Item $destination).Length -gt 5242880 -or (Get-FileHash $destination -Algorithm SHA256).Hash -ne $file.sha256){ throw 'Release source checksum mismatch. Nothing was installed.' }
        }
        $versions=Read-JsonFile (Join-Path $target 'VERSION.json')
        if($versions.addonVersion -ne $Manifest.addonVersion -or $versions.watcherVersion -ne $Manifest.watcherVersion -or $versions.game -ne $Manifest.game){ throw 'Release source versions do not match.' }
        return $target
    }
    $archive = Join-Path $Workspace 'bundle.zip' 
    Invoke-WebRequest -UseBasicParsing -Uri $Manifest.bundleUrl -OutFile $archive -TimeoutSec 120 -Headers @{ 'User-Agent' = 'AZPC-Launcher/0.2.21' }
    if ((Get-Item $archive).Length -gt 10485760) { throw 'Update download exceeds the maximum size.' }
    if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne $Manifest.bundleSha256) { throw 'Update checksum mismatch. Nothing was installed.' }
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    $target = Join-Path $Workspace 'payload'
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    $addonName=if($Manifest.game -eq 'forever'){'AZPCForever'}else{'AZPC'}
    $allowed = @(('addon/'+$addonName+'/'+$addonName+'.lua'),('addon/'+$addonName+'/'+$addonName+'.toc'),'watcher/AZPC-Watcher.ps1','VERSION.json')
    $seen = @{}
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\','/')
            if ($name.EndsWith('/')) {
                if ($name -notin @('addon/',('addon/'+$addonName+'/'),'watcher/')) { throw 'Unexpected directory in update archive.' }
                continue
            }
            if ($name -notin $allowed -or $seen.ContainsKey($name) -or $entry.Length -gt 5242880) { throw 'Unexpected or unsafe file in update archive.' }
            $seen[$name] = $true
            $destination = Join-Path $target $name
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination, $false)
        }
        if ($seen.Count -ne $allowed.Count) { throw 'The update archive is incomplete.' }
    } finally { $zip.Dispose() }
    $versions = Read-JsonFile (Join-Path $target 'VERSION.json')
    if ($versions.addonVersion -ne $Manifest.addonVersion -or $versions.watcherVersion -ne $Manifest.watcherVersion -or $versions.game -ne $Manifest.game) {
        throw 'Bundle versions do not match the update manifest.'
    }
    return $target
}
function Install-Addon([string]$Payload, [string]$Root, [string]$Game='tbc-anniversary') {
    $folder=if($Game -eq 'forever'){'_classic_beta_'}else{'_anniversary_'}
    $name=if($Game -eq 'forever'){'AZPCForever'}else{'AZPC'}
    $parent = Join-Path $Root ($folder+'\Interface\AddOns')
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $target = Join-Path $parent $name
    $id = [guid]::NewGuid().ToString('N')
    $staged = Join-Path $parent ('AZPC-staging-' + $id)
    # Keep directory swaps on the WoW volume, even when WoW is on D: and the user profile is on C:.
    $backup = Join-Path $Root ($folder+'\Interface\AZPC-Backups\addon-' + $id)
    New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
    $moved = $false
    try {
        Copy-Item -LiteralPath (Join-Path $Payload ('addon\'+$name)) -Destination $staged -Recurse
        foreach ($fileName in @(($name+'.lua'),($name+'.toc'))) {
            if (-not (Test-Path -LiteralPath (Join-Path $staged $fileName))) { throw 'Addon package is incomplete.' }
        }
        if (Test-Path -LiteralPath $target) { Move-Item -LiteralPath $target -Destination $backup; $moved = $true }
        Move-Item -LiteralPath $staged -Destination $target
    } catch {
        if ($moved -and -not (Test-Path -LiteralPath $target)) { Move-Item -LiteralPath $backup -Destination $target }
        throw
    } finally { if (Test-Path -LiteralPath $staged) { Remove-Item -LiteralPath $staged -Recurse -Force } }
}
function Install-Watcher([string]$Payload, [string]$Root, [string]$Code) {
    $profile = Get-Profile
    $paired = Test-Path -LiteralPath (Join-Path $profile.State 'watcher-credentials.json')
    if ($Code -and $Code -notmatch '^[A-Z0-9]{8}$') { throw 'The setup code must contain exactly eight letters or numbers.' }
    if (-not $paired -and -not $Code) { throw 'Generate a setup code on the Account page and enter it to install the watcher.' }
    # Existing credentials are never re-paired as part of an update.
    if ($paired) { $Code = '' }
    New-Item -ItemType Directory -Path $profile.Watcher,$profile.State -Force | Out-Null
    $target = Join-Path $profile.Watcher 'AZPC-Watcher.ps1'
    $source = Join-Path $Payload 'watcher\AZPC-Watcher.ps1'
    if (-not (Test-Path -LiteralPath $source)) { throw 'Watcher package is incomplete.' }
    $backup = Join-Path $script:ClientRoot ('Backups\watcher-' + [guid]::NewGuid().ToString('N') + '.ps1')
    New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
    $hadPrevious = Test-Path -LiteralPath $target
    if ($hadPrevious) { Copy-Item -LiteralPath $target -Destination $backup }
    Stop-AzpcWatcherInstances $profile.Watcher $profile.State
    try {
        Copy-Item -LiteralPath $source -Destination $target -Force
        if (-not $paired) {
            & powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File $target -DataDir $profile.State -SetupCode $Code -ActivateOnly *> $null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $profile.State 'watcher-credentials.json'))) {
                throw 'Account connection failed. Check the setup code or generate a new one. Existing trading caches were preserved.'
            }
        }
        if (-not (Install-AzpcStartupTask $profile.Watcher $profile.State $Root)) { throw 'Windows could not configure watcher startup.' }
        Wait-LauncherWatcherStarted $profile
    } catch {
        Stop-AzpcWatcherInstances $profile.Watcher $profile.State
        if ($hadPrevious) {
            Copy-Item -LiteralPath $backup -Destination $target -Force
            if ($paired) { $null = Install-AzpcStartupTask $profile.Watcher $profile.State $Root }
        } elseif (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
        throw
    }
}
function Start-Watcher([string]$Root) {
    $profile = Get-Profile
    if (-not (Test-Path -LiteralPath (Join-Path $profile.State 'watcher-credentials.json'))) { throw 'Install and connect the watcher first.' }
    if (-not (Test-Path -LiteralPath (Join-Path $profile.Watcher 'AZPC-Watcher.ps1'))) { throw 'Install the watcher first.' }
    Stop-Watcher
    if (-not (Install-AzpcStartupTask $profile.Watcher $profile.State $Root)) { throw 'Watcher startup could not be configured.' }
    Wait-LauncherWatcherStarted $profile
}
function Stop-Watcher {
    $profile = Get-Profile
    # End the scheduler instance as well as fallback/manual watcher instances.
    try { $service = New-Object -ComObject 'Schedule.Service'; $service.Connect(); $service.GetFolder('\').GetTask('AZPC Watcher').Stop(0) } catch { }
    Stop-AzpcWatcherInstances $profile.Watcher $profile.State
    # Verify stop instead of accepting the installer's best-effort result.
    foreach ($process in @(Get-LauncherWatcherProcesses $profile)) {
        Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction Stop
    }
    $deadline = (Get-Date).AddSeconds(5)
    while (@(Get-LauncherWatcherProcesses $profile).Count -gt 0) {
        if ((Get-Date) -ge $deadline) { throw 'The watcher did not stop. Check Task Scheduler -> AZPC Watcher.' }
        Start-Sleep -Milliseconds 250
    }
}
function Repair-ForeverLinen([string]$Root) {
    Assert-GameClosed
    $status=Get-InstalledStatus $Root 'forever'
    if ($status.Addon -notmatch '^\d+\.\d+\.\d+$' -or [version]$status.Addon -lt [version]'0.2.12') { throw 'Update the Forever addon to 0.2.12 or newer first.' }
    $accountRoot=Join-Path $Root '_classic_beta_\WTF\Account'
    if (-not (Test-Path -LiteralPath $accountRoot)) { throw 'No Forever saved account data was found.' }
    $candidates=@()
    foreach ($file in @(Get-ChildItem -LiteralPath $accountRoot -Filter 'AZPCForever.lua' -Recurse -File)) {
        if ($file.Directory.Name -ne 'SavedVariables') { continue }
        $content=[IO.File]::ReadAllText($file.FullName,[Text.Encoding]::UTF8)
        $rows=@()
        foreach ($match in [regex]::Matches($content,'\["tradeExport"\]\s*=\s*"(AZPCFTRADE\|[^"\r\n]+)"')) {
            $f=$match.Groups[1].Value.Split('|')
            if ($f.Length -lt 13 -or $f[1] -notin @('1','2')) { continue }
            if ($f[12] -ne 'Lu' -or $f[9] -ne 'Classic%20Beta%20PvP%202' -or $f[10] -ne 'horde' -or $f[11] -ne '90') { continue }
            $at=0L;$item=0L;$quantity=0L;$copper=0L
            if (-not [long]::TryParse($f[8],[ref]$at) -or -not [long]::TryParse($f[4],[ref]$item) -or -not [long]::TryParse($f[6],[ref]$quantity) -or -not [long]::TryParse($f[7],[ref]$copper)) { continue }
            if ($f[1] -eq '1') { $at*=1000 }
            $rows+=@{kind=$f[3];item=$item;quantity=$quantity;copper=$copper;at=$at}
        }
        $times=@(1791444821000L,1791444824000L,1791444827000L,1791444830000L,1791444834000L,1791444836000L,1791444840000L,1791444843000L)
        $verified=$true
        for($i=0;$i -lt 8;$i++) {
            if (@($rows | Where-Object { $_.kind -eq 'inventory_snapshot' -and $_.item -eq 2996 -and $_.quantity -eq ($i+1) -and [Math]::Abs($_.at-$times[$i]) -le 1 }).Count -ne 1) { $verified=$false }
            if (@($rows | Where-Object { $_.kind -eq 'inventory_snapshot' -and $_.item -eq 2589 -and $_.quantity -eq (14-2*$i) -and [Math]::Abs($_.at-$times[$i]) -le 1 }).Count -ne 1) { $verified=$false }
        }
        if (-not $verified) { continue }
        $cloth=@($rows | Where-Object {$_.kind -eq 'inventory_snapshot' -and $_.item -eq 2589} | Sort-Object at -Descending)[0]
        $bolts=@($rows | Where-Object {$_.kind -eq 'inventory_snapshot' -and $_.item -eq 2996} | Sort-Object at -Descending)[0]
        if ($cloth.quantity -ne 0 -or $bolts.quantity -ne 11) { throw 'Linen inventory has changed since this repair was verified. Refresh your saved data before repairing.' }
        $buys=@($rows | Where-Object {$_.kind -eq 'buy' -and $_.item -eq 2589 -and $_.at -ge 1791444677000L -and $_.at -le 1791447230000L})
        if ($buys.Count -ne 3 -or ($buys | Measure-Object quantity -Sum).Sum -ne 14 -or ($buys | Measure-Object copper -Sum).Sum -ne 14) { throw 'The verified cloth purchase costs no longer match. No repair was applied.' }
        $ids=@('material-reconcile:lu-linen-20261008:2589','material-reconcile:lu-linen-20261008:2996')
        $existing=@($ids | Where-Object {$content.Contains($_)})
        if ($existing.Count -eq 2) { return @{ok=$true;message='Linen repair is already applied. Open Lu, /reload, then refresh Crafting after the watcher uploads.'} }
        if ($existing.Count -ne 0) { throw 'A partial linen repair exists. No additional changes were made.' }
        if ([regex]::Matches($content,'\["materialEvents"\]\s*=\s*\{').Count -ne 1) { throw 'The material ledger could not be located safely.' }
        $candidates+=@{file=$file.FullName;content=$content;hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
    }
    if ($candidates.Count -ne 1) { throw 'No unique saved account matched the verified linen repair. Nothing was changed.' }
    $selected=$candidates[0]
    # Data-only Lua literals. Never evaluate a saved file as PowerShell or Lua.
    $insert=@'
{["schema"]=1,["eventId"]="material-reconcile:lu-linen-20261008:2589",["kind"]="reconcile",["itemId"]=2589,["quantity"]=1,["targetQuantity"]=0,["totalCopper"]=0,["name"]="Linen Cloth",["observedAt"]=1791447247002,["region"]=90,["realm"]="Classic Beta PvP 2",["faction"]="horde",["character"]="Lu",["confirmation"]="inventory_and_cost_reconciled",["sourceQuantities"]={},["reason"]="Confirmed inventory and eight paired cloth-to-bolt conversions; preserve historical records.",["evidence"]={"inventory_snapshot:2589:1791447247001:0","paired_recipe_conversions:1791444821000:1791444843000:8"}},
{["schema"]=1,["eventId"]="material-reconcile:lu-linen-20261008:2996",["kind"]="reconcile",["itemId"]=2996,["quantity"]=11,["targetQuantity"]=11,["totalCopper"]=14,["name"]="Bolt of Linen Cloth",["observedAt"]=1791447247002,["region"]=90,["realm"]="Classic Beta PvP 2",["faction"]="horde",["character"]="Lu",["confirmation"]="inventory_and_cost_reconciled",["sourceQuantities"]={["crafted"]=11},["reason"]="Eight free alt cloth plus fourteen bought cloth costing fourteen copper produced eleven bolts; preserve historical records.",["evidence"]={"inventory_snapshot:2996:1791447247000:11","paired_recipe_conversions:1791444821000:1791444843000:8","cloth_purchases:8+2+4:14c","confirmed_free_alt_cloth:8"}},
'@
    $match=[regex]::Match($selected.content,'\["materialEvents"\]\s*=\s*\{')
    $offset=$match.Index+$match.Length
    $updated=$selected.content.Insert($offset,"`r`n"+$insert+"`r`n")
    $backup=$selected.file+'.azpc-linen-backup-'+[guid]::NewGuid().ToString('N')
    $staged=$selected.file+'.azpc-staging-'+[guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($staged,$updated,(New-Object Text.UTF8Encoding($false)))
        Assert-GameClosed
        if ((Get-FileHash -LiteralPath $selected.file -Algorithm SHA256).Hash -ne $selected.hash) { throw 'The save changed during repair. Nothing was replaced; try again with WoW closed.' }
        [IO.File]::Replace($staged,$selected.file,$backup)
    } finally { if(Test-Path -LiteralPath $staged){Remove-Item -LiteralPath $staged -Force} }
    return @{ok=$true;message='Linen repair applied with an automatic backup: 0 cloth, 11 bolts, 14 copper total material cost. Open Lu, /reload, then refresh Crafting after the watcher uploads.'}
}

function Invoke-LauncherAction($Request) {
    $game='tbc-anniversary'
    if($Request -is [Collections.IDictionary]){ if($Request.Contains('game')){$game=[string]$Request.game} } elseif($Request.PSObject.Properties['game']){$game=[string]$Request.game}
    if($game -notin @('tbc-anniversary','forever')){ throw 'Unsupported game selection.' }
    if ($Request.action -eq 'check') { return @{ ok = $true; manifest = (Get-RemoteManifest -Game $game) } }
    if ($Request.action -eq 'stop') { Stop-Watcher; return @{ ok = $true; message = 'Watcher stopped. It remains configured to start at Windows sign-in.' } }
    $root = Assert-WowRoot ([string]$Request.wowRoot) $game
    if ($Request.action -eq 'repair-linen') { if($game -ne 'forever'){throw 'Linen repair is only available for Forever.'}; return (Repair-ForeverLinen $root) }
    if ($Request.action -eq 'start') { Start-Watcher $root; return @{ ok = $true; message = 'Watcher started. It may need a WoW logout or reload before new data is available.' } }
    if ($Request.action -notin @('addon','watcher','all')) { throw 'Unknown launcher action.' }
    Assert-GameClosed
    $workspace = Join-Path $script:ClientRoot ('Launcher\jobs\payload-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workspace -Force | Out-Null
    try {
        $payload = Join-Path $script:AppRoot 'installer\payload'
        if ($Request.manifest) { $payload = Get-UpdatePayload $Request.manifest $workspace }
        $versions = Read-JsonFile (Join-Path $payload 'VERSION.json')
        if($Request.manifest -and $versions.game -ne $game){ throw 'Package does not match selected game.' }
        if($game -eq 'forever' -and -not $Request.manifest){ $versions.addonVersion=$versions.foreverAddonVersion }
        $status = Get-InstalledStatus $root $game
        foreach ($component in @('addon','watcher')) {
            if ($Request.action -ne 'all' -and $Request.action -ne $component) { continue }
            $installed = [string]$status[$component]
            $available = [string]$versions.($component + 'Version')
            $null = Assert-Version $available
            if ($installed -match '^\d+\.\d+\.\d+' -and [version]$available -lt [version]$installed) {
                throw ('Refusing to downgrade ' + $component + '. Check for a newer release.')
            }
        }
        if ($Request.action -in @('all','watcher') -and -not $status.Connected -and [string]$Request.setupCode -notmatch '^[A-Z0-9]{8}$') {
            throw 'Enter an eight-character setup code before installing the watcher.'
        }
        # Each component is committed separately; a failed second component is reported honestly.
        $completed = @()
        try {
            if ($Request.action -in @('all','addon')) { Install-Addon $payload $root $game; $completed += 'Addon' }
            if ($Request.action -in @('all','watcher')) { Install-Watcher $payload $root ([string]$Request.setupCode); $completed += 'Watcher' }
        } catch {
            $prefix = if ($completed.Count) { ($completed -join ' and ') + ' installed successfully. ' } else { '' }
            throw ($prefix + $_.Exception.Message)
        }
        return @{ ok = $true; message = ($completed -join ' and ') + ' installed. Existing account credentials, upload caches, and WoW SavedVariables were preserved.' }
    } finally { if (Test-Path -LiteralPath $workspace) { Remove-Item -LiteralPath $workspace -Recurse -Force } }
}


