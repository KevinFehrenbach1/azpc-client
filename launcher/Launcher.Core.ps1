Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$script:ClientRoot = Join-Path $env:LOCALAPPDATA 'AZPC'
$script:AppRoot = Split-Path -Parent $PSScriptRoot
$script:Repo = 'KevinFehrenbach1/azpc-client'
. (Join-Path $script:AppRoot 'installer\payload\INSTALL-AZPC.ps1') -FunctionsOnly

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
function Assert-WowRoot([string]$Root) {
    if ([string]::IsNullOrWhiteSpace($Root)) { throw 'Choose your main World of Warcraft folder first.' }
    $full = [IO.Path]::GetFullPath($Root.Trim())
    if ($full.Contains('"')) { throw 'The folder path contains an unsupported character.' }
    if (-not (Test-Path -LiteralPath (Join-Path $full '_anniversary_') -PathType Container)) {
        throw 'Choose the main WoW folder that contains _anniversary_. Forever is not supported by this addon yet.'
    }
    return $full
}
function Assert-GameClosed {
    if (@(Get-Process -Name Wow,WowClassic,WowClassicT,WowB -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Close World of Warcraft before installing or updating. This keeps the addon and saved trading history safe.'
    }
}
function Get-InstalledStatus([string]$Root) {
    $profile = Get-Profile
    $addonVersion = 'Not installed'; $watcherVersion = 'Not installed'
    if ($Root) {
        $toc = Join-Path $Root '_anniversary_\Interface\AddOns\AZPC\AZPC.toc'
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
    $running = $false; $activity = 'No watcher heartbeat yet'
    $heartbeat = Read-JsonFile (Join-Path $profile.State 'watcher-heartbeat.json')
    if ($heartbeat) {
        $process = Get-CimInstance Win32_Process -Filter ('ProcessId = ' + [int]$heartbeat.pid) -ErrorAction SilentlyContinue
        $running = ($null -ne $process -and [string]$process.Name -match '^powershell.exe$' -and
            ([string]$process.CommandLine).IndexOf($watcherFile, [StringComparison]::OrdinalIgnoreCase) -ge 0)
        $activity = [string]$heartbeat.status + ' | ' + [string]$heartbeat.updatedAt
    }
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
    if ($Manifest.schema -ne 1 -or $Manifest.game -ne 'tbc-anniversary') { throw 'Unsupported update manifest or game version.' }
    $null = Assert-Version ([string]$Manifest.addonVersion)
    $null = Assert-Version ([string]$Manifest.watcherVersion)
    $null = Assert-Version ([string]$Manifest.launcherVersion)
    Assert-ReleaseUrl ([string]$Manifest.bundleUrl)
    if ([string]$Manifest.bundleSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'The update checksum is missing or invalid.' }
}
function Get-RemoteManifest {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent' = 'AZPC-Launcher/0.1.0'; Accept = 'application/vnd.github+json' }
    $release = Invoke-RestMethod -Uri ('https://api.github.com/repos/' + $script:Repo + '/releases/latest') -Headers $headers -TimeoutSec 30
    $asset = @($release.assets | Where-Object { $_.name -eq 'azpc-update.json' })
    if ($asset.Count -ne 1) { throw 'The latest public release does not include launcher updates yet. You can install the bundled versions now; launcher updates will become available when a compatible release is published.' }
    Assert-ReleaseUrl $asset[0].browser_download_url
    if ([long]$asset[0].size -gt 65536) { throw 'Update manifest is too large.' }
    $manifest = Invoke-RestMethod -Uri $asset[0].browser_download_url -Headers @{ 'User-Agent' = 'AZPC-Launcher/0.1.0' } -TimeoutSec 30
    Test-Manifest $manifest
    return $manifest
}
function Get-UpdatePayload($Manifest, [string]$Workspace) {
    Test-Manifest $Manifest
    $archive = Join-Path $Workspace 'bundle.zip'
    Invoke-WebRequest -UseBasicParsing -Uri $Manifest.bundleUrl -OutFile $archive -TimeoutSec 120 -Headers @{ 'User-Agent' = 'AZPC-Launcher/0.1.0' }
    if ((Get-Item $archive).Length -gt 10485760) { throw 'Update download exceeds the maximum size.' }
    if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne $Manifest.bundleSha256) { throw 'Update checksum mismatch. Nothing was installed.' }
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    $target = Join-Path $Workspace 'payload'
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    $allowed = @('addon/AZPC/AZPC.lua','addon/AZPC/AZPC.toc','watcher/AZPC-Watcher.ps1','VERSION.json')
    $seen = @{}
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\','/')
            if ($name.EndsWith('/')) {
                if ($name -notin @('addon/','addon/AZPC/','watcher/')) { throw 'Unexpected directory in update archive.' }
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
function Install-Addon([string]$Payload, [string]$Root) {
    $parent = Join-Path $Root '_anniversary_\Interface\AddOns'
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $target = Join-Path $parent 'AZPC'
    $id = [guid]::NewGuid().ToString('N')
    $staged = Join-Path $parent ('AZPC-staging-' + $id)
    # Keep directory swaps on the WoW volume, even when WoW is on D: and the user profile is on C:.
    $backup = Join-Path $Root ('_anniversary_\Interface\AZPC-Backups\addon-' + $id)
    New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
    $moved = $false
    try {
        Copy-Item -LiteralPath (Join-Path $Payload 'addon\AZPC') -Destination $staged -Recurse
        foreach ($name in @('AZPC.lua','AZPC.toc')) {
            if (-not (Test-Path -LiteralPath (Join-Path $staged $name))) { throw 'Addon package is incomplete.' }
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
    Stop-AzpcWatcherInstances $profile.Watcher $profile.State
    if (-not (Install-AzpcStartupTask $profile.Watcher $profile.State $Root)) { throw 'Watcher startup could not be configured.' }
}
function Stop-Watcher {
    $profile = Get-Profile
    # End the scheduler instance as well as fallback/manual watcher instances.
    try { $service = New-Object -ComObject 'Schedule.Service'; $service.Connect(); $service.GetFolder('\').GetTask('AZPC Watcher').Stop(0) } catch { }
    Stop-AzpcWatcherInstances $profile.Watcher $profile.State
}
function Invoke-LauncherAction($Request) {
    if ($Request.action -eq 'check') { return @{ ok = $true; manifest = (Get-RemoteManifest) } }
    if ($Request.action -eq 'stop') { Stop-Watcher; return @{ ok = $true; message = 'Watcher stopped. It remains configured to start at Windows sign-in.' } }
    $root = Assert-WowRoot ([string]$Request.wowRoot)
    if ($Request.action -eq 'start') { Start-Watcher $root; return @{ ok = $true; message = 'Watcher started. It may need a WoW logout or reload before new data is available.' } }
    if ($Request.action -notin @('addon','watcher','all')) { throw 'Unknown launcher action.' }
    Assert-GameClosed
    $workspace = Join-Path $script:ClientRoot ('Launcher\jobs\payload-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workspace -Force | Out-Null
    try {
        $payload = Join-Path $script:AppRoot 'installer\payload'
        if ($Request.manifest) { $payload = Get-UpdatePayload $Request.manifest $workspace }
        $versions = Read-JsonFile (Join-Path $payload 'VERSION.json')
        if ($versions.game -ne 'tbc-anniversary') { throw 'This package is not for Anniversary.' }
        $status = Get-InstalledStatus $root
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
            if ($Request.action -in @('all','addon')) { Install-Addon $payload $root; $completed += 'Addon' }
            if ($Request.action -in @('all','watcher')) { Install-Watcher $payload $root ([string]$Request.setupCode); $completed += 'Watcher' }
        } catch {
            $prefix = if ($completed.Count) { ($completed -join ' and ') + ' installed successfully. ' } else { '' }
            throw ($prefix + $_.Exception.Message)
        }
        return @{ ok = $true; message = ($completed -join ' and ') + ' installed. Existing account credentials, upload caches, and WoW SavedVariables were preserved.' }
    } finally { if (Test-Path -LiteralPath $workspace) { Remove-Item -LiteralPath $workspace -Recurse -Force } }
}
