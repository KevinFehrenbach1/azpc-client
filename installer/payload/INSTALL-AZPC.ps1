param(
    [string]$WowRoot = "",
    [string]$SetupCode = ""
)

$ErrorActionPreference = "Stop"
$PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$AddonSource = Join-Path $PackageRoot "addon\AZPC"
$WatcherSource = Join-Path $PackageRoot "watcher"
$AzpcRoot = Join-Path $env:LOCALAPPDATA "AZPC"
$LegacyWatcherTarget = Join-Path $AzpcRoot "Watcher"
$LegacyStateDir = $AzpcRoot

function Say([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::Gray) {
    Write-Host $Text -ForegroundColor $Color
}

function Find-WowRoot([string]$Explicit) {
    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($Explicit)) { $candidates.Add($Explicit) }
    foreach ($p in @(
        "C:\Program Files (x86)\World of Warcraft",
        "C:\Program Files\World of Warcraft",
        "D:\World of Warcraft",
        "D:\Games\World of Warcraft",
        "E:\World of Warcraft",
        "E:\Games\World of Warcraft"
    )) { if (Test-Path -LiteralPath $p) { $candidates.Add($p) } }

    foreach ($p in ($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath (Join-Path $p "_anniversary_")) { return $p }
    }
    return $null
}

function New-LocalProfileId {
    $alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    $bytes = New-Object byte[] 8
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $chars = for ($i=0; $i -lt 8; $i++) { $alphabet[$bytes[$i] % $alphabet.Length] }
    return (-join $chars)
}

function Find-ExistingWatcherIdentities {
    if (-not (Test-Path -LiteralPath $AzpcRoot)) { return @() }

    # A watcher identity exists as soon as private-client-id.txt is created.
    # watcher-credentials.json is only written AFTER a successful activation,
    # so checking credentials alone misses previously-created/linked identities
    # when an activation attempt was interrupted or rejected.
    $markers = @(
        Get-ChildItem -LiteralPath $AzpcRoot -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @("private-client-id.txt", "watcher-credentials.json") } |
        Sort-Object LastWriteTime -Descending
    )

    # Return one marker per state directory.
    return @($markers | Group-Object DirectoryName | ForEach-Object { $_.Group | Select-Object -First 1 })
}

function Resolve-WatcherTargetForStateDir([string]$StateDir) {
    if ([string]::Equals($StateDir, $LegacyStateDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $LegacyWatcherTarget
    }
    $leaf = Split-Path -Leaf $StateDir
    return Join-Path (Join-Path $AzpcRoot "Watchers") $leaf
}

function Write-Launcher([string]$WatcherTarget, [string]$StateDir) {
    $launcher = Join-Path $WatcherTarget "START-AZPC-WATCHER.bat"
    $script = Join-Path $WatcherTarget "AZPC-Watcher.ps1"
    $lines = @(
        '@echo off',
        'title AZPC Watcher v0.4.21',
        ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}" -DataDir "{1}"' -f $script,$StateDir),
        'if errorlevel 1 (',
        '  echo.',
        ('  echo AZPC Watcher stopped with an error. See "{0}"' -f (Join-Path $StateDir 'watcher.log')),
        '  pause',
        ')'
    )
    Set-Content -LiteralPath $launcher -Value $lines -Encoding ASCII
    return $launcher
}



function Write-HiddenWatcherLauncher([string]$WatcherTarget, [string]$StateDir) {
    # Use wscript.exe as the parent process so the long-running PowerShell watcher
    # has no visible console window. Activation remains on the proven synchronous
    # PowerShell path so Setup gets a reliable exit code.
    $vbsPath = Join-Path $WatcherTarget "START-AZPC-WATCHER-HIDDEN.vbs"
    $script = Join-Path $WatcherTarget "AZPC-Watcher.ps1"
    $psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $cmd = '"' + $psExe + '" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $script + '" -DataDir "' + $StateDir + '"'
    $escaped = $cmd.Replace('"','""')
    $vbs = @(
        'Set shell = CreateObject("WScript.Shell")',
        ('shell.Run "{0}", 0, False' -f $escaped)
    )
    Set-Content -LiteralPath $vbsPath -Value $vbs -Encoding ASCII
    return $vbsPath
}

function Stop-AzpcWatcherInstances([string]$WatcherTarget, [string]$StateDir) {
    # Installer upgrades must restart the watcher process itself. Replacing the
    # .ps1 on disk does NOT update an already-running PowerShell process.
    # That was leaving an older scheduled watcher alive while a manual launch
    # used the new detector, causing conflicting game-presence heartbeats.
    $script = Join-Path $WatcherTarget "AZPC-Watcher.ps1"
    try {
        $candidates = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $cmd = [string]$_.CommandLine
            $name = [string]$_.Name
            ($name -match '(?i)^powershell(?:\.exe)?$') -and
            (-not [string]::IsNullOrWhiteSpace($cmd)) -and
            (($cmd.IndexOf($script, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
             (($cmd.IndexOf('AZPC-Watcher.ps1', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -and
              ($cmd.IndexOf($StateDir, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)))
        })
        foreach ($proc in $candidates) {
            if ([int]$proc.ProcessId -eq $PID) { continue }
            try {
                Stop-Process -Id ([int]$proc.ProcessId) -Force -ErrorAction Stop
                Say ("Stopped old AZPC watcher process PID " + $proc.ProcessId + " so the update can take effect immediately.") DarkGray
            } catch { }
        }
    } catch { }
}

function Install-AzpcStartupTask([string]$WatcherTarget, [string]$StateDir) {
    $taskName = "AZPC Watcher"
    $script = Join-Path $WatcherTarget "AZPC-Watcher.ps1"
    $hiddenLauncher = Write-HiddenWatcherLauncher $WatcherTarget $StateDir
    $wscript = Join-Path $env:SystemRoot "System32\wscript.exe"
    $arguments = ('"{0}"' -f $hiddenLauncher)

    # Remove the older Startup-folder shortcut so only one watcher starts at logon.
    try {
        $startup = [Environment]::GetFolderPath("Startup")
        $legacyStartupLink = Join-Path $startup "AZPC Watcher.lnk"
        if (Test-Path -LiteralPath $legacyStartupLink) { Remove-Item -LiteralPath $legacyStartupLink -Force }
    } catch { }

    # Create a per-user Task Scheduler task. This does not require storing a password.
    # It starts 15 seconds after logon, hidden, and retries up to 3 times if startup fails.
    try {
        $service = New-Object -ComObject "Schedule.Service"
        $service.Connect()
        $root = $service.GetFolder("\")

        # Stop any already-running scheduled instance before replacing the task.
        # Otherwise Task Scheduler can keep the old PowerShell process alive even
        # after the watcher file on disk has been upgraded.
        try {
            $oldTask = $root.GetTask($taskName)
            try { $oldTask.Stop(0) } catch { }
        } catch { }
        try { $root.DeleteTask($taskName, 0) } catch { }

        $task = $service.NewTask(0)
        $task.RegistrationInfo.Description = "Azerothian Price Checker background watcher"
        $task.Settings.Enabled = $true
        $task.Settings.StartWhenAvailable = $true
        $task.Settings.DisallowStartIfOnBatteries = $false
        $task.Settings.StopIfGoingOnBatteries = $false
        $task.Settings.ExecutionTimeLimit = "PT0S"
        $task.Settings.MultipleInstances = 2 # TASK_INSTANCES_IGNORE_NEW
        $task.Settings.RestartCount = 3
        $task.Settings.RestartInterval = "PT1M"

        $principal = $task.Principal
        $principal.UserId = ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
        $principal.LogonType = 3 # TASK_LOGON_INTERACTIVE_TOKEN
        $principal.RunLevel = 0 # LUA / normal user

        $trigger = $task.Triggers.Create(9) # TASK_TRIGGER_LOGON
        $trigger.Enabled = $true
        $trigger.Delay = "PT15S"
        $trigger.UserId = $principal.UserId

        $action = $task.Actions.Create(0) # TASK_ACTION_EXEC
        $action.Path = $wscript
        $action.Arguments = $arguments
        $action.WorkingDirectory = $WatcherTarget

        # TASK_CREATE_OR_UPDATE = 6, TASK_LOGON_INTERACTIVE_TOKEN = 3
        $null = $root.RegisterTaskDefinition($taskName, $task, 6, $principal.UserId, $null, 3, $null)

        # Start the newly registered task now as well as at future logons. This
        # guarantees the background process is running the same watcher version
        # that was just installed, without requiring a reboot.
        try {
            $registered = $root.GetTask($taskName)
            $null = $registered.Run($null)
            Say "Windows auto-start configured and refreshed: Task Scheduler -> AZPC Watcher (15-second logon delay)." Green
        } catch {
            Say "Windows auto-start configured: Task Scheduler -> AZPC Watcher (15-second logon delay)." Green
            Say ("The task was installed but could not be started immediately: " + $_.Exception.Message) Yellow
        }
        return $true
    } catch {
        Say ("Task Scheduler auto-start could not be configured: " + $_.Exception.Message) Yellow
        Say "Falling back to the Windows Startup folder." Yellow

        try {
            $wsh = New-Object -ComObject WScript.Shell
            $startup = [Environment]::GetFolderPath("Startup")
            $startupLink = $wsh.CreateShortcut((Join-Path $startup "AZPC Watcher.lnk"))
            $startupLink.TargetPath = (Join-Path $env:SystemRoot "System32\wscript.exe")
            $startupLink.Arguments = ('"{0}"' -f $hiddenLauncher)
            $startupLink.WorkingDirectory = $WatcherTarget
            $startupLink.Description = "Azerothian Price Checker Watcher"
            $startupLink.Save()
            Say "Fallback auto-start configured in the Windows Startup folder." Green
            return $true
        } catch {
            Say ("WARNING: Automatic startup could not be configured: " + $_.Exception.Message) Red
            return $false
        }
    }
}

Say ""; Say "AZPC TBC Anniversary installer v0.4.74" Yellow
Say "This installs the WoW addon and your private AZPC watcher." Cyan
Say "No shared AZPC server secret is included in this package." DarkGray

$resolved = Find-WowRoot $WowRoot
while ([string]::IsNullOrWhiteSpace($resolved)) {
    Say ""; Say "World of Warcraft was not found automatically." Yellow
    $manual = Read-Host "Enter your World of Warcraft folder (example C:\Program Files (x86)\World of Warcraft)"
    $resolved = Find-WowRoot $manual
    if (-not $resolved) { Say "That folder does not contain _anniversary_. Try again." Red }
}

$addonTarget = Join-Path $resolved "_anniversary_\Interface\AddOns\AZPC"
Say ""; Say ("WoW found: " + $resolved) Green
Say ("Installing addon to: " + $addonTarget)
New-Item -ItemType Directory -Force -Path $addonTarget | Out-Null
Copy-Item -LiteralPath (Join-Path $AddonSource "AZPC.lua") -Destination (Join-Path $addonTarget "AZPC.lua") -Force
Copy-Item -LiteralPath (Join-Path $AddonSource "AZPC.toc") -Destination (Join-Path $addonTarget "AZPC.toc") -Force

New-Item -ItemType Directory -Force -Path $AzpcRoot | Out-Null
$existing = Find-ExistingWatcherIdentities
$installMode = "fresh"
$stateDir = $LegacyStateDir
$watcherTarget = $LegacyWatcherTarget
$skipActivation = $false

if ($existing.Count -gt 0) {
    Say ""; Say "Existing AZPC watcher connection detected on this PC." Yellow
    $stateDir = Split-Path -Parent $existing[0].FullName
    $watcherTarget = Resolve-WatcherTargetForStateDir $stateDir
    if ([string]::IsNullOrWhiteSpace($SetupCode)) {
        $installMode = "keep"
        $skipActivation = $true
        Say "Keeping the existing account connection." Green
    } else {
        $installMode = "reconnect"
        $skipActivation = $false
        Say "Reconnect mode selected automatically from the graphical setup code. Your cloud history remains preserved." Green
    }
}

Say ("Installing watcher to: " + $watcherTarget)
New-Item -ItemType Directory -Force -Path $watcherTarget | Out-Null
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
Stop-AzpcWatcherInstances $watcherTarget $stateDir
Start-Sleep -Milliseconds 350
Copy-Item -LiteralPath (Join-Path $WatcherSource "AZPC-Watcher.ps1") -Destination (Join-Path $watcherTarget "AZPC-Watcher.ps1") -Force
$launcher = Write-Launcher $watcherTarget $stateDir

if (-not $skipActivation) {
    if ([string]::IsNullOrWhiteSpace($SetupCode)) {
        Say ""; Say "Connect this PC to your AZPC account" Yellow
        Say "1. Sign in at https://azpc.market/account"
        Say "2. Click Generate Setup Code (or Need a new setup code? if reconnecting)."
        Say "3. Return here and enter the 8-character code."
        try { Start-Process "https://azpc.market/account" } catch { }
        $SetupCode = Read-Host "AZPC setup code"
    }
    $SetupCode = ($SetupCode.Trim().ToUpperInvariant() -replace '[^A-Z0-9]','')
    if ($SetupCode.Length -ne 8) { throw "Setup code must be exactly 8 characters." }

    Say "Connecting watcher to your account..." Cyan
    $activationStartedUtc = [DateTime]::UtcNow
    # Keep activation completely hidden. This prevents the extra watcher/PowerShell
    # command window from flashing or remaining open during graphical Setup.
    & powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File (Join-Path $watcherTarget "AZPC-Watcher.ps1") -DataDir $stateDir -SetupCode $SetupCode -ActivateOnly
    if ($LASTEXITCODE -ne 0) {
        Say "Activation failed. Existing watcher credentials were NOT replaced." Red
        throw "Watcher activation failed."
    }

    $credentialPath = Join-Path $stateDir "watcher-credentials.json"
    if (-not (Test-Path -LiteralPath $credentialPath)) { throw "Watcher activation returned success but no credential file was written." }
    $credentialInfo = Get-Item -LiteralPath $credentialPath
    if ($credentialInfo.LastWriteTimeUtc -lt $activationStartedUtc.AddSeconds(-2)) {
        throw "Watcher activation did not refresh the credential file. Setup will not report success."
    }
}

# Only one AZPC watcher should auto-start per Windows user. Prefer a delayed,
# hidden Task Scheduler job; fall back to the Startup folder if Task Scheduler
# is unavailable on the machine.
$autoStartConfigured = Install-AzpcStartupTask $watcherTarget $stateDir

if (-not $autoStartConfigured) { throw "AZPC automatic startup could not be configured." }
if (-not (Test-Path -LiteralPath (Join-Path $addonTarget "AZPC.lua"))) { throw "AZPC addon verification failed." }
if (-not (Test-Path -LiteralPath (Join-Path $watcherTarget "AZPC-Watcher.ps1"))) { throw "AZPC watcher verification failed." }
if (-not (Test-Path -LiteralPath (Join-Path $stateDir "watcher-credentials.json"))) { throw "AZPC account credential verification failed." }

$credentialSummary = $null
try {
    $credentialSummary = Get-Content -LiteralPath (Join-Path $stateDir "watcher-credentials.json") -Raw -Encoding UTF8 | ConvertFrom-Json
} catch { throw "AZPC credential verification failed after installation." }

$installResult = @{
    ok = $true
    packageVersion = "0.4.74"
    watcherVersion = "0.4.21"
    addonVersion = "0.4.27"
    connectionMode = $installMode
    paired = (-not $skipActivation)
    watcherClientId = [string]$credentialSummary.clientId
    credentialUpdatedAtUtc = (Get-Item -LiteralPath (Join-Path $stateDir "watcher-credentials.json")).LastWriteTimeUtc.ToString("o")
    wowRoot = $resolved
    addonPath = $addonTarget
    watcherPath = $watcherTarget
    statePath = $stateDir
    installedAtUtc = [DateTime]::UtcNow.ToString("o")
}
$installResult | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $AzpcRoot "install-result.json") -Encoding UTF8

Say ""
if ($skipActivation) {
    Say "AZPC was updated and your existing watcher connection was preserved." Green
} else {
    Say "AZPC is installed and connected." Green
}
Say "NEXT:" Yellow
Say "  1. Launch/restart WoW and make sure AZPC is enabled in AddOns."
Say "  2. Log into your TBC Anniversary character once so AZPC.lua SavedVariables exists."
Say "  3. Visit https://azpc.market/my-trading after activity is synced."
Say ""
if ($installMode -eq 'new') {
    Say "Your previous watcher profile is still stored on this PC, but Windows startup now points to this new watcher." DarkGray
}
if ($autoStartConfigured) { Say "The selected watcher will start automatically about 15 seconds after you sign into Windows." DarkGray }
