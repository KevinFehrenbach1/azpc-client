param(
    [string]$WowRoot = "",
    [string]$SetupCode = "",
    [string]$DataDir = "",
    [switch]$ActivateOnly,
    [switch]$Once,
    [switch]$FunctionsOnly
)

$ErrorActionPreference = "Stop"

$Endpoint = "https://azpc.market/api/player-snapshots"
$PrivateEndpoint = "https://azpc.market/api/private/transactions"
$PrivateStatusEndpoint = "https://azpc.market/api/private/transactions/status"
$ActivateEndpoint = "https://azpc.market/api/watcher/activate"
$HeartbeatEndpoint = "https://azpc.market/api/watcher/heartbeat"
$StateDir = if ([string]::IsNullOrWhiteSpace($DataDir)) { Join-Path $env:LOCALAPPDATA "AZPC" } else { [System.IO.Path]::GetFullPath($DataDir) }
$StateFile = Join-Path $StateDir "watcher-state.json"
$LogFile = Join-Path $StateDir "watcher.log"
$HeartbeatFile = Join-Path $StateDir "watcher-heartbeat.json"
$PrivateStateFile = Join-Path $StateDir "private-ledger-state.json"
$ClientIdFile = Join-Path $StateDir "private-client-id.txt"
$WatcherConfigFile = Join-Path $StateDir "watcher-credentials.json"

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

function Write-Log([string]$Message) {
    $line = ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message)
    Write-Host $line
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Write-Heartbeat([string]$Status, [string]$FilePath) {
    @{
        version = "0.4.38"
        status = $Status
        savedVariables = $FilePath
        updatedAt = (Get-Date).ToUniversalTime().ToString("o")
        pid = $PID
    } | ConvertTo-Json | Set-Content -LiteralPath $HeartbeatFile -Encoding UTF8
}

function Get-WatcherCredentials([string]$RequestedSetupCode) {
    $clientId = Get-PrivateClientId
    $forceActivation = -not [string]::IsNullOrWhiteSpace([string]$RequestedSetupCode)

    # IMPORTANT v0.4.21: an explicitly supplied setup code ALWAYS means
    # "pair/re-pair this PC now". Do not silently return stale credentials.
    # This fixes rerunning AZPC Setup against a different/new account.
    if ((-not $forceActivation) -and (Test-Path -LiteralPath $WatcherConfigFile)) {
        try {
            $cfg = Get-Content -LiteralPath $WatcherConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $savedClient = [string]$cfg.clientId
            $savedToken = [string]$cfg.watcherToken
            if ($savedClient -match '^[0-9a-fA-F-]{30,64}$' -and -not [string]::IsNullOrWhiteSpace($savedToken)) {
                if ($savedClient -ne $clientId) {
                    Set-Content -LiteralPath $ClientIdFile -Value $savedClient -Encoding UTF8
                    $clientId = $savedClient
                }
                return @{ clientId = $clientId; watcherToken = $savedToken }
            }
        } catch {
            Write-Log "Existing watcher credentials could not be read; AZPC will reconnect this watcher."
        }
    }

    $code = [string]$RequestedSetupCode
    if ([string]::IsNullOrWhiteSpace($code)) {
        Write-Host ""
        Write-Host "This AZPC Watcher is not connected to an AZPC account yet." -ForegroundColor Yellow
        Write-Host "On azpc.market/account, click Generate Setup Code." -ForegroundColor Cyan
        $code = Read-Host "Enter the 8-character setup code"
    }
    $code = ($code.Trim().ToUpperInvariant() -replace '[^A-Z0-9]','')
    if ($code.Length -ne 8) { throw "The AZPC setup code must be exactly 8 characters." }

    function Invoke-AzpcActivation([string]$ActivationClientId) {
        $body = @{ code = $code; clientId = $ActivationClientId } | ConvertTo-Json -Depth 4
        return Invoke-RestMethod -Uri $ActivateEndpoint -Method Post -ContentType "application/json" -Body $body -TimeoutSec 30
    }

    Write-Log "WATCHER ACTIVATION: exchanging one-time setup code for this PC's private credential..."
    try {
        $response = Invoke-AzpcActivation $clientId
    } catch {
        $detail = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail += " | " + $_.ErrorDetails.Message }

        # Alpha safety lock: one Windows watcher identity belongs to one AZPC
        # account. Never create a second identity automatically, because doing
        # so can replay the shared local SavedVariables ledger into that account.
        if ($forceActivation -and ($detail -match '(?i)already linked to another account')) {
            throw "AZPC watcher account switch refused. This Windows watcher is already linked to another AZPC account. Alpha builds support one account per Windows watcher installation. Existing credentials and history were not changed."
        } else {
            throw "AZPC watcher activation failed: $detail"
        }
    }

    $token = [string]$response.watcherToken
    $serverClientId = [string]$response.clientId
    if ([string]::IsNullOrWhiteSpace($token)) { throw "AZPC activation succeeded but no watcher credential was returned." }
    if ($serverClientId -notmatch '^[0-9a-fA-F-]{30,64}$') { $serverClientId = $clientId }

    # Reconnects to the SAME account deliberately reuse that account's existing
    # server-side client ID so historical private trading data stays attached.
    if ($serverClientId -ne $clientId) {
        Set-Content -LiteralPath $ClientIdFile -Value $serverClientId -Encoding UTF8
        $clientId = $serverClientId
        Write-Log "WATCHER ACTIVATION: restored this account's existing private watcher identity."
    }

    @{
        clientId = $clientId
        watcherToken = $token
        connectedAt = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json | Set-Content -LiteralPath $WatcherConfigFile -Encoding UTF8

    Write-Log "WATCHER ACTIVATION: connected successfully. The one-time setup code is now consumed and credentials were replaced."
    return @{ clientId = $clientId; watcherToken = $token }
}

function Get-WowGamePresence {
    # v0.4.18: fix .NET regex option placement so process matching actually executes.
    # TBC Anniversary currently runs as WowClassic.exe, but keep the detector
    # tolerant of Blizzard executable-name changes and PTR/test variants.
    $result = @{ running = $false; processName = $null; executablePath = $null; detector = $null }

    try {
        $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $n = [string]$_.Name
            $p = [string]$_.ExecutablePath
            ($n -match '(?i)^Wow(Classic|ClassicT|T)?\.exe$') -or
            (($p -match '(?i)World of Warcraft') -and ($n -match '(?i)^Wow.*\.exe$'))
        })
        if ($processes.Count -gt 0) {
            $proc = $processes[0]
            $result.running = $true
            $result.processName = [string]$proc.Name
            $result.executablePath = [string]$proc.ExecutablePath
            $result.detector = 'CIM'
            return $result
        }
    } catch { }

    try {
        $processes = @(Get-Process -ErrorAction Stop | Where-Object {
            $_.ProcessName -match '(?i)^Wow(Classic|ClassicT|T)?$'
        })
        if ($processes.Count -gt 0) {
            $proc = $processes[0]
            $result.running = $true
            $result.processName = [string]$proc.ProcessName
            try { $result.executablePath = [string]$proc.Path } catch { }
            $result.detector = 'Get-Process'
            return $result
        }
    } catch { }

    try {
        $taskList = (& tasklist.exe /FO CSV /NH 2>$null) -join "`n"
        if ($taskList -match '(?im)"(Wow(?:Classic|ClassicT|T)?\.exe)"') {
            $result.running = $true
            $result.processName = $Matches[1]
            $result.detector = 'tasklist'
            return $result
        }
    } catch { }

    return $result
}

function Send-AzpcHeartbeat([string]$ClientId, [string]$Token) {
    try {
        $headers = @{
            "x-azpc-client-id" = $ClientId
            "x-azpc-watcher-token" = $Token
        }
        $presence = Get-WowGamePresence
        $gameRunning = $presence.running -eq $true
        $body = @{ clientId = $ClientId; watcherVersion = "0.4.38"; pid = $PID; gameRunning = $gameRunning; gameProcess = $presence.processName; gameDetector = $presence.detector } | ConvertTo-Json -Depth 3
        $response = Invoke-RestMethod -Uri $HeartbeatEndpoint -Method Post -Headers $headers -ContentType "application/json" -Body $body -TimeoutSec 20
        $serverTime = if ($null -ne $response.serverTime) { [Int64]$response.serverTime } else { 0 }
        Write-Log ("HEARTBEAT OK: account watcher is online | WoW=" + $(if ($gameRunning) { "RUNNING" } else { "NOT RUNNING" }) + $(if ($gameRunning) { " | process=" + $presence.processName + " | detector=" + $presence.detector } else { "" }) + $(if ($serverTime -gt 0) { " (serverTime=$serverTime)" } else { "" }))
        return $true
    } catch {
        $detail = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail += " | " + $_.ErrorDetails.Message }
        Write-Log ("HEARTBEAT WARNING: " + $detail)
        return $false
    }
}

function Find-AzpcSavedVariables([string]$ExplicitWowRoot) {
    $candidates = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($ExplicitWowRoot)) {
        $candidates.Add($ExplicitWowRoot)
    }

    $common = @(
        "C:\Program Files (x86)\World of Warcraft",
        "C:\Program Files\World of Warcraft",
        "D:\World of Warcraft",
        "D:\Games\World of Warcraft",
        "E:\World of Warcraft",
        "E:\Games\World of Warcraft"
    )

    foreach ($p in $common) {
        if (Test-Path -LiteralPath $p) { $candidates.Add($p) }
    }

    foreach ($root in $candidates | Select-Object -Unique) {
        $wtf = Join-Path $root "_anniversary_\WTF\Account"
        if (-not (Test-Path -LiteralPath $wtf)) { continue }

        $matches = Get-ChildItem -LiteralPath $wtf -Filter "AZPC.lua" -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\SavedVariables\\AZPC\.lua$' } |
            Sort-Object LastWriteTime -Descending

        if ($matches.Count -gt 0) {
            return $matches[0].FullName
        }
    }

    # Last-resort scan of fixed drives, constrained to the WoW path signature.
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' })) {
        $wow = Join-Path $drive.Root "World of Warcraft\_anniversary_\WTF\Account"
        if (Test-Path -LiteralPath $wow) {
            $matches = Get-ChildItem -LiteralPath $wow -Filter "AZPC.lua" -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match '\\SavedVariables\\AZPC\.lua$' } |
                Sort-Object LastWriteTime -Descending
            if ($matches.Count -gt 0) { return $matches[0].FullName }
        }
    }

    throw "Could not find _anniversary_\WTF\Account\<ACCOUNT>\SavedVariables\AZPC.lua. Run with -WowRoot `"C:\path\to\World of Warcraft`" if WoW is installed somewhere unusual."
}

function Read-State {
    if (-not (Test-Path -LiteralPath $StateFile)) {
        return @{
            lastSnapshotTimestamp = 0
            lastSnapshotSignature = ""
            lastFileWriteUtc = ""
        }
    }

    try {
        $obj = Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        return @{
            lastSnapshotTimestamp = [Int64]($obj.lastSnapshotTimestamp)
            lastSnapshotSignature = [string]($obj.lastSnapshotSignature)
            lastFileWriteUtc = [string]($obj.lastFileWriteUtc)
        }
    } catch {
        return @{
            lastSnapshotTimestamp = 0
            lastSnapshotSignature = ""
            lastFileWriteUtc = ""
        }
    }
}

function Save-State([Int64]$Timestamp, [string]$Signature, [string]$FileWriteUtc) {
    @{
        lastSnapshotTimestamp = $Timestamp
        lastSnapshotSignature = $Signature
        lastFileWriteUtc = $FileWriteUtc
    } | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

function Get-LuaStringValue([string]$Block, [string]$Key) {
    $pattern = '\["' + [regex]::Escape($Key) + '"\]\s*=\s*"((?:\\.|[^"])*)"'
    $m = [regex]::Match($Block, $pattern)
    if (-not $m.Success) { return $null }
    $s = $m.Groups[1].Value
    $s = $s -replace '\\"','"' -replace '\\\\','\'
    return $s
}

function Get-LuaNumberValue([string]$Block, [string]$Key) {
    $pattern = '\["' + [regex]::Escape($Key) + '"\]\s*=\s*(-?\d+(?:\.\d+)?)'
    $m = [regex]::Match($Block, $pattern)
    if (-not $m.Success) { return $null }
    return [double]$m.Groups[1].Value
}

function Get-SnapshotSignature($Rows) {
    $canonical = @(
        $Rows |
        Sort-Object itemId |
        ForEach-Object {
            "{0}|{1}|{2}|{3}" -f $_.itemId,$_.price,$_.quantity,$_.auctionCount
        }
    ) -join "`n"

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-","").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Convert-AzpcLuaToLatestRows([string]$Text) {
    $realmM = [regex]::Match($Text, '\["realm"\]\s*=\s*"([^"]+)"')
    $factionM = [regex]::Match($Text, '\["faction"\]\s*=\s*"([^"]+)"')

    $realm = if ($realmM.Success) { $realmM.Groups[1].Value.ToLowerInvariant() } else { "" }
    $faction = if ($factionM.Success) { $factionM.Groups[1].Value.ToLowerInvariant() } else { "" }

    $obsStart = $Text.IndexOf('["observations"] = {')
    if ($obsStart -lt 0) {
        return @{
            realm = $realm
            faction = $faction
            timestamp = 0
            signature = ""
            rows = @()
        }
    }

    $snapStart = $Text.IndexOf('["snapshots"] = {', $obsStart)
    if ($snapStart -gt $obsStart) {
        $obsText = $Text.Substring($obsStart, $snapStart - $obsStart)
    } else {
        $obsText = $Text.Substring($obsStart)
    }

    $tableMatches = [regex]::Matches(
        $obsText,
        '(?ms)^\{\s*\r?\n(.*?)^\},\s*$'
    )

    $rawRows = New-Object System.Collections.Generic.List[object]

    foreach ($tm in $tableMatches) {
        $b = $tm.Groups[1].Value
        if ($b -notmatch '\["kind"\]\s*=\s*"auction_listing"') { continue }

        $itemId = Get-LuaNumberValue $b "itemId"
        $timestamp = Get-LuaNumberValue $b "timestamp"
        $count = Get-LuaNumberValue $b "count"
        $buyout = Get-LuaNumberValue $b "buyoutPrice"
        $buyoutPerUnit = Get-LuaNumberValue $b "buyoutPerUnit"
        $name = Get-LuaStringValue $b "name"

        if ($null -eq $itemId -or $null -eq $timestamp -or [string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $stackCount = if ($null -ne $count -and $count -gt 0) { [Int64]$count } else { 1 }
        $price = 0

        if ($null -ne $buyoutPerUnit -and $buyoutPerUnit -gt 0) {
            $price = [Int64]$buyoutPerUnit
        } elseif ($null -ne $buyout -and $buyout -gt 0) {
            $price = [Int64][math]::Floor($buyout / $stackCount)
        }

        # Bid-only auctions cannot define AZPC's buyout market price.
        if ($price -le 0) { continue }

        $rawRows.Add([pscustomobject]@{
            itemId = [Int64]$itemId
            name = $name
            timestamp = [Int64]$timestamp
            price = $price
            count = $stackCount
        })
    }

    if ($rawRows.Count -eq 0) {
        return @{
            realm = $realm
            faction = $faction
            timestamp = 0
            signature = ""
            rows = @()
        }
    }

    # Only the newest logical AH snapshot is eligible for upload.
    $latestTs = [Int64](($rawRows | Measure-Object -Property timestamp -Maximum).Maximum)
    $latest = @($rawRows | Where-Object { $_.timestamp -eq $latestTs })

    # One row per item:
    #   price        = lowest per-unit buyout seen
    #   quantity     = total units represented by all buyout auctions in this snapshot
    #   auctionCount = number of buyout auctions represented
    $collapsed = @(
        $latest |
        Group-Object itemId |
        ForEach-Object {
            $group = @($_.Group)
            $best = $group | Sort-Object price | Select-Object -First 1
            $quantity = [Int64](($group | Measure-Object -Property count -Sum).Sum)
            $auctionCount = [Int64]$group.Count

            [pscustomobject]@{
                itemId = [Int64]$best.itemId
                name = [string]$best.name
                observedAt = [Int64]($latestTs * 1000)
                price = [Int64]$best.price
                quantity = $quantity
                auctionCount = $auctionCount
            }
        } |
        Sort-Object itemId
    )

    $signature = Get-SnapshotSignature $collapsed

    return @{
        realm = $realm
        faction = $faction
        timestamp = $latestTs
        signature = $signature
        rows = $collapsed
    }
}

function Format-Copper([Int64]$Copper) {
    $g = [math]::Floor($Copper / 10000)
    $silver = [math]::Floor(($Copper % 10000) / 100)
    $c = $Copper % 100
    return ("{0}g {1}s {2}c" -f $g,$silver,$c)
}

function Upload-Snapshot($Parsed, [string]$ClientId, [string]$WatcherToken) {
    if ([string]::IsNullOrWhiteSpace($Parsed.realm) -or [string]::IsNullOrWhiteSpace($Parsed.faction)) {
        throw "Could not read realm/faction from AZPC.lua."
    }

    if ($Parsed.rows.Count -eq 0) {
        Write-Log "No buyout-priced auction rows in latest AZPC snapshot; nothing to upload."
        return $false
    }

    $body = @{
        clientId = $ClientId
        realm = $Parsed.realm
        faction = $Parsed.faction
        observations = @($Parsed.rows)
    } | ConvertTo-Json -Depth 8

    Write-Log (
        "Uploading CLEAN snapshot {0}: {1} unique items ({2}/{3}) signature={4}..." -f
        $Parsed.timestamp,
        $Parsed.rows.Count,
        $Parsed.realm,
        $Parsed.faction,
        $Parsed.signature.Substring(0,12)
    )

    foreach ($row in @($Parsed.rows | Select-Object -First 25)) {
        Write-Log (
            "  ITEM {0} | {1} | min {2} | qty {3} | auctions {4}" -f
            $row.itemId,
            $row.name,
            (Format-Copper $row.price),
            $row.quantity,
            $row.auctionCount
        )
    }

    if ($Parsed.rows.Count -gt 25) {
        Write-Log ("  ... plus {0} more unique items." -f ($Parsed.rows.Count - 25))
    }

    try {
        $response = Invoke-RestMethod `
            -Uri $Endpoint `
            -Method Post `
            -ContentType "application/json" `
            -Headers @{ "x-azpc-client-id" = $ClientId; "x-azpc-watcher-token" = $WatcherToken } `
            -Body $body `
            -TimeoutSec 30

        Write-Log ("SUCCESS: " + ($response | ConvertTo-Json -Compress -Depth 10))
        return $true
    } catch {
        $detail = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $detail += " | " + $_.ErrorDetails.Message
        }
        Write-Log ("UPLOAD FAILED: " + $detail)
        return $false
    }
}


function Get-PrivateClientId {
    if (Test-Path -LiteralPath $ClientIdFile) {
        $existing = (Get-Content -LiteralPath $ClientIdFile -Raw -Encoding UTF8).Trim()
        if ($existing -match '^[0-9a-fA-F-]{30,64}$') {
            return $existing
        }
    }

    $id = [guid]::NewGuid().ToString()
    Set-Content -LiteralPath $ClientIdFile -Value $id -Encoding UTF8
    return $id
}

function Read-PrivateState([string]$ClientId) {
    if (-not (Test-Path -LiteralPath $PrivateStateFile)) {
        return @{ clientId = $ClientId; uploadedEventIds = @{}; uploadedSettlementEventIds = @{} }
    }

    try {
        $obj = Get-Content -LiteralPath $PrivateStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $savedClientId = [string]$obj.clientId
        if ([string]::IsNullOrWhiteSpace($savedClientId)) {
            Write-Log "PRIVATE SYNC: migrating the existing upload cache to this client without replaying historical events."
            $savedClientId = $ClientId
        } elseif ($savedClientId -ne $ClientId) {
            throw "PRIVATE SYNC REFUSED: local upload cache belongs to a different watcher client. Historical replay is blocked."
        }
        $set = @{}
        foreach ($id in @($obj.uploadedEventIds)) {
            if ($id) { $set[[string]$id] = $true }
        }
        $settlementSet = @{}
        foreach ($id in @($obj.uploadedSettlementEventIds)) {
            if ($id) { $settlementSet[[string]$id] = $true }
        }
        return @{ clientId = $ClientId; uploadedEventIds = $set; uploadedSettlementEventIds = $settlementSet }
    } catch {
        Write-Log ("PRIVATE SYNC REFUSED: upload cache could not be safely loaded. " + $_.Exception.Message)
        throw
    }
}

function Save-PrivateState($State) {
    $ids = @($State.uploadedEventIds.Keys | Sort-Object)
    $settlementIds = @($State.uploadedSettlementEventIds.Keys | Sort-Object)
    # Bound local state size. Server-side event IDs also make retries idempotent.
    if ($ids.Count -gt 10000) {
        $ids = @($ids | Select-Object -Last 10000)
    }
    if ($settlementIds.Count -gt 10000) {
        $settlementIds = @($settlementIds | Select-Object -Last 10000)
    }
    @{ clientId = [string]$State.clientId; uploadedEventIds = $ids; uploadedSettlementEventIds = $settlementIds } |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $PrivateStateFile -Encoding UTF8
}

function Get-LuaNullableNumberValue([string]$Block, [string]$Key) {
    return Get-LuaNumberValue $Block $Key
}

function Get-AzpcTransactionBlocks([string]$Text) {
    $marker = '["transactions"] = {'
    $startIndex = $Text.IndexOf($marker)

    if ($startIndex -lt 0) {
        return @()
    }

    $sectionStart = $startIndex + $marker.Length
    $tail = $Text.Substring($sectionStart)

    # Normalize newlines and parse the Lua table structurally.
    # We do NOT try to identify "root keys" with regex because fields inside
    # transactions are also serialized at column 1 on this WoW client.
    $lines = $tail -split "`r?`n"

    $depth = 1               # already inside ["transactions"] = {
    $current = @()
    $blocks = @()
    $capturing = $false

    foreach ($line in $lines) {
        $trim = $line.Trim()

        if ($trim -eq "{") {
            $depth = $depth + 1

            if ($depth -eq 2) {
                $capturing = $true
                $current = @()
            }
            elseif ($capturing) {
                $current = @($current + $line)
            }

            continue
        }

        if ($trim -eq "}," -or $trim -eq "}") {
            if ($depth -eq 2 -and $capturing) {
                $blocks = @($blocks + ([string]::Join("`n", [string[]]$current)))
                $current = @()
                $capturing = $false
            }
            elseif ($capturing) {
                $current = @($current + $line)
            }

            $depth = $depth - 1

            # We have closed the root transactions table.
            if ($depth -le 0) {
                break
            }

            continue
        }

        if ($capturing) {
            $current = @($current + $line)
        }
    }

    return $blocks
}

function Get-LuaNullableBooleanValue([string]$Block, [string]$Key) {
    $pattern = '\["' + [regex]::Escape($Key) + '"\]\s*=\s*(true|false)'
    $m = [regex]::Match($Block, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $m.Success) { return $null }
    return ($m.Groups[1].Value.ToLowerInvariant() -eq "true")
}

function Convert-AzpcLuaToTransactions([string]$Text) {
    Write-Log "PRIVATE PARSER: locating metadata + transaction table..."

    $realmM = [regex]::Match($Text, '\["realm"\]\s*=\s*"([^"]+)"')
    $factionM = [regex]::Match($Text, '\["faction"\]\s*=\s*"([^"]+)"')
    $characterM = [regex]::Match($Text, '\["character"\]\s*=\s*"([^"]+)"')

    $realm = if ($realmM.Success) { $realmM.Groups[1].Value.ToLowerInvariant() } else { "" }
    $faction = if ($factionM.Success) { $factionM.Groups[1].Value.ToLowerInvariant() } else { "" }
    $defaultCharacter = if ($characterM.Success) { $characterM.Groups[1].Value } else { "" }

    $blocks = @(Get-AzpcTransactionBlocks $Text)
    Write-Log ("PRIVATE PARSER: structural parser found {0} transaction block(s)." -f $blocks.Count)

    $rows = @()
    $ordinal = 0

    foreach ($b in $blocks) {
        $ordinal = $ordinal + 1
        $block = [string]$b

        $kind = Get-LuaStringValue $block "kind"
        $name = Get-LuaStringValue $block "name"
        $character = Get-LuaStringValue $block "character"
        $source = Get-LuaStringValue $block "source"
        $status = Get-LuaStringValue $block "status"
        $timestamp = Get-LuaNumberValue $block "timestamp"
        $itemId = Get-LuaNullableNumberValue $block "itemId"
        $quantity = Get-LuaNullableNumberValue $block "quantity"
        $unitPrice = Get-LuaNullableNumberValue $block "unitPrice"
        $totalPrice = Get-LuaNullableNumberValue $block "totalPrice"
        $mailPayout = Get-LuaNullableNumberValue $block "mailPayout"
        $auctionHouseCut = Get-LuaNullableNumberValue $block "auctionHouseCut"
        $deposit = Get-LuaNullableNumberValue $block "deposit"
        $depositLoss = Get-LuaNullableNumberValue $block "depositLoss"
        $netProceeds = Get-LuaNullableNumberValue $block "netProceeds"
        $realizedProfit = Get-LuaNullableNumberValue $block "realizedProfit"
        $costBasis = Get-LuaNullableNumberValue $block "costBasis"
        $actualQuantity = Get-LuaNullableNumberValue $block "actualQuantity"
        $ledgerQuantityBefore = Get-LuaNullableNumberValue $block "ledgerQuantityBefore"
        $remainingQuantity = Get-LuaNullableNumberValue $block "remainingQuantity"
        $remainingCostBasis = Get-LuaNullableNumberValue $block "remainingCostBasis"
        $settlementKey = Get-LuaStringValue $block "settlementKey"
        $matchedListing = Get-LuaNullableBooleanValue $block "matchedListing"
        $realizedProfitKnown = Get-LuaNullableBooleanValue $block "realizedProfitKnown"

        if ([string]::IsNullOrWhiteSpace([string]$kind) `
            -or [string]::IsNullOrWhiteSpace([string]$name) `
            -or $null -eq $timestamp) {
            Write-Log ("PRIVATE PARSER: skipping block {0} (missing kind/name/timestamp)." -f $ordinal)
            continue
        }

        $timestampInt = [Int64]$timestamp
        $itemIdValue = if ($null -eq $itemId) { $null } else { [Int64]$itemId }
        $quantityValue = if ($null -eq $quantity) { $null } else { [Int64]$quantity }
        $unitPriceValue = if ($null -eq $unitPrice) { $null } else { [Int64]$unitPrice }
        $totalPriceValue = if ($null -eq $totalPrice) { $null } else { [Int64]$totalPrice }
        $characterValue = if ([string]::IsNullOrWhiteSpace([string]$character)) {
            [string]$defaultCharacter
        } else {
            [string]$character
        }

        $canonicalParts = @(
            [string]$timestampInt,
            [string]$ordinal,
            [string]$kind,
            [string]$name,
            $(if ($null -eq $itemIdValue) { "" } else { [string]$itemIdValue }),
            $(if ($null -eq $quantityValue) { "" } else { [string]$quantityValue }),
            $(if ($null -eq $unitPriceValue) { "" } else { [string]$unitPriceValue }),
            $(if ($null -eq $totalPriceValue) { "" } else { [string]$totalPriceValue }),
            [string]$status,
            [string]$source,
            [string]$characterValue
        )

        # Preserve v0.4.5 event IDs for already-uploaded legacy/private events.
        # Settlement kinds were never accepted before 0.4.6, so only they add
        # authoritative invoice fields to their identity.
        if ($kind -eq "sale_settled" -or $kind -eq "auction_expired") {
            $canonicalParts += $(if ($null -eq $netProceeds) { "" } else { [string]$netProceeds })
            $canonicalParts += $(if ($null -eq $auctionHouseCut) { "" } else { [string]$auctionHouseCut })
            $canonicalParts += $(if ($null -eq $deposit) { "" } else { [string]$deposit })
            $canonicalParts += $(if ($null -eq $depositLoss) { "" } else { [string]$depositLoss })
            $canonicalParts += $(if ($null -eq $realizedProfit) { "" } else { [string]$realizedProfit })
            $canonicalParts += $(if ($null -eq $realizedProfitKnown) { "" } else { [string]$realizedProfitKnown })
            $canonicalParts += [string]$settlementKey
        }
        elseif ($kind -eq "inventory_reconciled") {
            # Reconciliation rows are enriched on the next WoW login/P&L rebuild
            # with their authoritative remaining quantity and FIFO basis. Include
            # those checkpoint fields in identity so the enriched row is uploaded
            # even if the startup watcher already saw the earlier sparse version.
            $canonicalParts += $(if ($null -eq $actualQuantity) { "" } else { [string]$actualQuantity })
            $canonicalParts += $(if ($null -eq $ledgerQuantityBefore) { "" } else { [string]$ledgerQuantityBefore })
            $canonicalParts += $(if ($null -eq $remainingQuantity) { "" } else { [string]$remainingQuantity })
            $canonicalParts += $(if ($null -eq $remainingCostBasis) { "" } else { [string]$remainingCostBasis })
        }

        $canonical = [string]::Join("|", [string[]]$canonicalParts)

        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$canonical)
            $hashBytes = $sha.ComputeHash($bytes)
            $eventId = ([BitConverter]::ToString($hashBytes)).Replace("-","").ToLowerInvariant()
        } finally {
            $sha.Dispose()
        }

        $rows = @($rows + [pscustomobject]@{
            eventId = [string]$eventId
            kind = [string]$kind
            name = [string]$name
            character = [string]$characterValue
            observedAt = [Int64]($timestampInt * 1000)
            itemId = $itemIdValue
            quantity = $quantityValue
            unitPrice = $unitPriceValue
            totalPrice = $totalPriceValue
            mailPayout = if ($null -eq $mailPayout) { $null } else { [Int64]$mailPayout }
            auctionHouseCut = if ($null -eq $auctionHouseCut) { $null } else { [Int64]$auctionHouseCut }
            deposit = if ($null -eq $deposit) { $null } else { [Int64]$deposit }
            depositLoss = if ($null -eq $depositLoss) { $null } else { [Int64]$depositLoss }
            netProceeds = if ($null -eq $netProceeds) { $null } else { [Int64]$netProceeds }
            realizedProfit = if ($null -eq $realizedProfit) { $null } else { [Int64]$realizedProfit }
            costBasis = if ($null -eq $costBasis) { $null } else { [Int64]$costBasis }
            actualQuantity = if ($null -eq $actualQuantity) { $null } else { [Int64]$actualQuantity }
            ledgerQuantityBefore = if ($null -eq $ledgerQuantityBefore) { $null } else { [Int64]$ledgerQuantityBefore }
            remainingQuantity = if ($null -eq $remainingQuantity) { $null } else { [Int64]$remainingQuantity }
            remainingCostBasis = if ($null -eq $remainingCostBasis) { $null } else { [Int64]$remainingCostBasis }
            settlementKey = if ([string]::IsNullOrWhiteSpace([string]$settlementKey)) { $null } else { [string]$settlementKey }
            matchedListing = $matchedListing
            realizedProfitKnown = $realizedProfitKnown
            status = if ($null -eq $status) { $null } else { [string]$status }
            source = if ($null -eq $source) { $null } else { [string]$source }
        })
    }

    Write-Log ("PRIVATE PARSER: accepted {0} valid transaction event(s)." -f $rows.Count)

    return @{
        realm = [string]$realm
        faction = [string]$faction
        rows = $rows
    }
}

function Upload-NewPrivateTransactions([string]$Text, [string]$WatcherToken, [string]$ClientId, $PrivateState) {
    Write-Log "PRIVATE SYNC: parsing SavedVariables..."
    $parsed = Convert-AzpcLuaToTransactions $Text

    if ($null -eq $PrivateState.uploadedEventIds -or -not ($PrivateState.uploadedEventIds -is [hashtable])) {
        $PrivateState.uploadedEventIds = @{}
    }
    if ($null -eq $PrivateState.uploadedSettlementEventIds -or -not ($PrivateState.uploadedSettlementEventIds -is [hashtable])) {
        $PrivateState.uploadedSettlementEventIds = @{}
    }

    # Keep the desktop uploader in lockstep with the Worker private-ledger validator.
    # AZPC SavedVariables also contains non-private transaction rows such as
    # auction_listing/test records. Those belong to other addon features and must
    # never be sent to /api/private/transactions, or a chunk containing only those
    # rows is rejected with HTTP 400: No valid private transaction rows supplied.
    $privateAllowedKinds = @(
        "buyout_attempt", "purchase_confirmed", "bid_attempt",
        "sell_post_attempt", "sell_post_acknowledged",
        "sell_posted", "sell_posted_confirmed", "sale_confirmed",
        "sale_settled", "auction_expired", "listing_unresolved", "craft_confirmed",
        "inventory_reconciled"
    )
    $privateAllowedKindSet = @{}
    foreach ($allowedKind in $privateAllowedKinds) {
        $privateAllowedKindSet[[string]$allowedKind] = $true
    }

    $newRows = @()
    $ignoredNonPrivate = 0
    foreach ($row in @($parsed.rows)) {
        $kind = [string]$row.kind
        if (-not $privateAllowedKindSet.ContainsKey($kind)) {
            $ignoredNonPrivate = $ignoredNonPrivate + 1
            continue
        }

        $eventId = [string]$row.eventId
        $isSettlement = ($kind -eq "sale_settled" -or $kind -eq "auction_expired")
        if ($isSettlement) {
            # v0.4.7 settlement backfill: older watcher versions could poison the
            # general uploadedEventIds cache for rows the Worker did not actually
            # store. Settlement rows therefore use their own one-time upload set.
            if (-not $PrivateState.uploadedSettlementEventIds.ContainsKey($eventId)) {
                $newRows = @($newRows + $row)
            }
        } elseif (-not $PrivateState.uploadedEventIds.ContainsKey($eventId)) {
            $newRows = @($newRows + $row)
        }
    }

    if ($ignoredNonPrivate -gt 0) {
        Write-Log ("PRIVATE SYNC: ignored {0} non-private SavedVariables event(s)." -f $ignoredNonPrivate)
    }

    if ($newRows.Count -eq 0) {
        Write-Log "PRIVATE SYNC: no new transaction events."
        return
    }

    Write-Log ("PRIVATE LEDGER: {0} new transaction event(s) ready." -f $newRows.Count)

    $offset = 0
    while ($offset -lt $newRows.Count) {
        $chunk = @($newRows | Select-Object -Skip $offset -First 100)
        if ($chunk.Count -eq 0) { break }

        Write-Log ("PRIVATE SYNC: uploading events {0}-{1}..." -f ($offset + 1), ($offset + $chunk.Count))

        $bodyObject = @{
            clientId = [string]$ClientId
            realm = [string]$parsed.realm
            faction = [string]$parsed.faction
            transactions = $chunk
        }

        $body = $bodyObject | ConvertTo-Json -Depth 10

        try {
            $response = Invoke-RestMethod `
                -Uri $PrivateEndpoint `
                -Method Post `
                -ContentType "application/json" `
                -Headers @{ "x-azpc-client-id" = $ClientId; "x-azpc-watcher-token" = $WatcherToken } `
                -Body $body `
                -TimeoutSec 30

            Write-Log ("PRIVATE SUCCESS: " + ($response | ConvertTo-Json -Compress -Depth 10))

            foreach ($row in $chunk) {
                $PrivateState.uploadedEventIds[[string]$row.eventId] = $true
                $kind = [string]$row.kind
                if ($kind -eq "sale_settled" -or $kind -eq "auction_expired") {
                    $PrivateState.uploadedSettlementEventIds[[string]$row.eventId] = $true
                }
            }
            Save-PrivateState $PrivateState
        } catch {
            $detail = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $detail += " | " + $_.ErrorDetails.Message
            }
            Write-Log ("PRIVATE UPLOAD FAILED: " + $detail)
            return
        }

        $offset = $offset + $chunk.Count
    }
}

# Forever collection is isolated from Anniversary private ledgers and upload state.
function Find-ForeverSavedVariables([string]$Root) {
    $roots=@($Root,'C:\Program Files (x86)\World of Warcraft','C:\Program Files\World of Warcraft','D:\World of Warcraft','D:\Games\World of Warcraft','E:\World of Warcraft','E:\Games\World of Warcraft') | Where-Object { $_ } | Select-Object -Unique
    foreach($candidate in $roots) {
        $accounts=[IO.Path]::Combine($candidate, '_classic_beta_\WTF\Account')
        if(Test-Path -LiteralPath $accounts) {
            Get-ChildItem -LiteralPath $accounts -Filter 'AZPCForever.lua' -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Directory.Name -eq 'SavedVariables' } | Select-Object -ExpandProperty FullName
        }
    }
}
function Convert-ForeverRegion([string]$Region, [string]$Realm) {
    if($Region -eq '110' -and $Realm -cmatch '^Classic Beta '){return '90'}
    return $Region
}
function Convert-ForeverExport([string]$Export) {
    $records=$Export.Split(';'); $header=$records[0].Split('|')
    if($header.Count -ne 6 -or $header[0] -ne 'AZPCFOREVER' -or $header[1] -ne '1' -or $header[3] -notin @('horde','alliance')) { throw 'Invalid Forever scan header.' }
    $realm=[uri]::UnescapeDataString($header[2]); $header[4]=Convert-ForeverRegion $header[4] $realm; $region=0; $timestamp=0L
    if(-not $realm -or $realm.Length -gt 100 -or -not [int]::TryParse($header[4],[ref]$region) -or $region -notin @(1,2,3,4,5,90) -or -not [long]::TryParse($header[5],[ref]$timestamp) -or $timestamp -le 0 -or $timestamp -gt 4102444800){ throw 'Invalid Forever realm, region, or timestamp.' }
    if($records.Count -lt 2 -or $records.Count -gt 5001){ throw 'Invalid Forever scan size.' }
    $rows=@(); $seen=@{}
    foreach($record in $records | Select-Object -Skip 1){
        $fields=$record.Split('|'); if($fields.Count -ne 5){ throw 'Invalid Forever item row.' }
        $id=0L; $price=0L; $quantity=0L; $auctions=0L
        if(-not [long]::TryParse($fields[0],[ref]$id) -or $id -le 0 -or $seen.ContainsKey($id) -or -not [long]::TryParse($fields[2],[ref]$price) -or $price -le 0 -or -not [long]::TryParse($fields[3],[ref]$quantity) -or $quantity -lt 0 -or -not [long]::TryParse($fields[4],[ref]$auctions) -or $auctions -lt 0){ throw 'Invalid Forever item values.' }
        $name=[uri]::UnescapeDataString($fields[1]); if(-not $name -or $name.Length -gt 200){ throw 'Invalid Forever item name.' }
        $seen[$id]=$true
        $rows+=@{itemId=$id;name=$name;price=$price;quantity=$quantity;auctionCount=$auctions;observedAt=($timestamp*1000)}
    }
    return @{game='forever';schema=1;realm=$realm;faction=$header[3];region=$region;scope='loaded_browse_results';observations=$rows;timestamp=$timestamp}
}
function Convert-ForeverTrade([string]$Export) {
    $f=$Export.Split('|')
    # Addon 0.1.1/0.1.2 accidentally appended Lua gsub's replacement count.
    # Recover already-saved records only when that extra field matches the character encoding.
    if($f.Count -eq 14 -and $f[13] -eq ([string]([regex]::Matches($f[12],'%[0-9A-Fa-f]{2}').Count))){$f=$f[0..12]}
    if((($f[1] -eq '1' -and $f.Count -ne 13) -or ($f[1] -eq '2' -and $f.Count -ne 21)) -or $f[0] -ne 'AZPCFTRADE' -or $f[1] -notin @('1','2') -or $f[3] -notin @('buy','sell','expired','listing_snapshot','inventory_snapshot') -or $f[10] -notin @('horde','alliance')){throw 'Invalid Forever trade header.'}
    if($f[1] -eq '1' -and $f[3] -notin @('buy','sell','expired')){throw 'Invalid legacy Forever trade kind.'}
    $minimumQuantity=if($f[3] -in @('listing_snapshot','inventory_snapshot')){0}else{1}
    $minimumStamp=if($f[1] -eq '2'){946684800000L}else{946684800L};$maximumStamp=if($f[1] -eq '2'){4102444800000L}else{4102444800L}
    $f[11]=Convert-ForeverRegion $f[11] ([uri]::UnescapeDataString($f[9]))
    $id=0L;$qty=0L;$copper=0L;$stamp=0L;$region=0
    if(-not [long]::TryParse($f[4],[ref]$id) -or $id -le 0 -or $id -gt 10000000 -or -not [long]::TryParse($f[6],[ref]$qty) -or $qty -lt $minimumQuantity -or $qty -gt 1000000 -or -not [long]::TryParse($f[7],[ref]$copper) -or $copper -lt 0 -or $copper -gt 1000000000000 -or -not [long]::TryParse($f[8],[ref]$stamp) -or $stamp -lt $minimumStamp -or $stamp -gt $maximumStamp -or -not [int]::TryParse($f[11],[ref]$region) -or $region -notin @(1,2,3,4,5,90)){throw 'Invalid Forever trade values.'}
    if($f[3] -eq 'expired' -and $copper -ne 0){throw 'Expired auction returns cannot have trade proceeds.'}
    $name=[uri]::UnescapeDataString($f[5]);$realm=[uri]::UnescapeDataString($f[9]);$character=[uri]::UnescapeDataString($f[12])
    if(-not $name -or $name.Length -gt 200 -or -not $realm -or $realm.Length -gt 100 -or -not $character -or $character.Length -gt 150 -or -not $f[2]){throw 'Invalid Forever trade identity.'}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$key=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([uri]::UnescapeDataString($f[2]))))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
    $metadata=@{}
    if($f[1] -eq '2'){
        $names=@('deposit','auctionHouseCut','mailPayout','listedQuantity','pendingQuantity','unresolvedQuantity','bagQuantity','depositLoss')
        for($i=0;$i -lt $names.Count;$i++){if($f[$i+13] -ne ''){$value=0L;if(-not [long]::TryParse($f[$i+13],[ref]$value) -or $value -lt 0 -or $value -gt 1000000000000){throw 'Invalid Forever lifecycle metadata.'};$metadata[$names[$i]]=$value}}
        if($f[3] -eq 'sell'){$metadata.netProceedsKnown=$true;if(-not $metadata.ContainsKey('deposit') -or -not $metadata.ContainsKey('mailPayout') -or $metadata.mailPayout-$metadata.deposit -ne $copper){throw 'Invalid net proceeds and refundable deposit.'}}
        if($f[3] -in @('listing_snapshot','inventory_snapshot') -and $copper -ne 0){throw 'Inventory observations cannot have proceeds.'}
        if($f[3] -eq 'listing_snapshot' -and (-not $metadata.ContainsKey('listedQuantity') -or -not $metadata.ContainsKey('pendingQuantity') -or -not $metadata.ContainsKey('unresolvedQuantity'))){throw 'Missing listing quantities.'}
        if($f[3] -eq 'inventory_snapshot' -and -not $metadata.ContainsKey('bagQuantity')){throw 'Missing bag quantity.'}
        if($f[3] -eq 'listing_snapshot' -and ($metadata.listedQuantity+$metadata.pendingQuantity+$metadata.unresolvedQuantity -ne $qty)){throw 'Invalid listing quantities.'}
        if($f[3] -eq 'inventory_snapshot' -and $metadata.bagQuantity -ne $qty){throw 'Invalid bag quantity.'}
    }elseif($f[3] -eq 'sell'){$metadata.netProceedsKnown=$false}
    if($f[3] -in @('buy','sell')){
        # Preserve evidence for repairing old expiry-drift duplicates without merging
        # merely equal prices. Include buyer/sender/subject and occurrence ordinal.
        $identity=[uri]::UnescapeDataString($f[2])
        if($identity -match '^(.*:(?:buyer|seller):\d+:\d+:\d+:)(\d+)(:[^:]*:[^:]*:[^:]*:\d+:\d+)$'){
            $expiry=0L
            if([long]::TryParse($Matches[2],[ref]$expiry)){
                $stable=$Matches[1]+$Matches[3]
                $sha=[Security.Cryptography.SHA256]::Create()
                try{$metadata.mailIdentity=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($stable)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
                $metadata.mailExpiryMinute=$expiry
                $parts=$identity.Split(':')
                if($parts.Count -eq 13){
                    if($f[3] -eq 'buy'){
                        $purchaseParts=$parts.Clone();$purchaseParts[5]='';$purchaseParts[7]=''
                        $sha=[Security.Cryptography.SHA256]::Create()
                        try{$metadata.mailPurchaseIdentity=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($purchaseParts -join ':'))))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
                    }
                    $metadata.mailBuyerKnown=($parts[8] -ne '')
                    $parts[7]='';$parts[8]=''
                    $sha=[Security.Cryptography.SHA256]::Create()
                    try{$metadata.mailEnvelope=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($parts -join ':'))))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
                }
            }
        }
    }
    $observedAt=if($f[1] -eq '2'){$stamp}else{$stamp*1000}
    return @{eventId=('mail:'+ $key);kind=$f[3];itemId=$id;name=$name;quantity=$qty;copper=$copper;observedAt=$observedAt;realm=$realm;faction=$f[10];region=$region;character=$character;metadata=$metadata}
}
function Collect-ForeverTrades([string]$Text) {
    $directory=Join-Path $StateDir 'Forever\trades'
    foreach($match in [regex]::Matches($Text,'\["tradeExport"\]\s*=\s*"(AZPCFTRADE\|[^"\r\n]+)"')){
        try{
            $event=Convert-ForeverTrade $match.Groups[1].Value
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $target=Join-Path $directory ($event.eventId.Substring(5)+'.json')
            $upgrade=$false
            if(Test-Path -LiteralPath $target){$old=Get-Content -LiteralPath $target -Raw -Encoding UTF8 | ConvertFrom-Json;$upgrade=($event.kind -eq 'sell' -and $event.metadata.netProceedsKnown -eq $true -and $old.metadata.netProceedsKnown -ne $true) -or ($event.metadata.mailIdentity -and $old.metadata.mailIdentity -ne $event.metadata.mailIdentity) -or ($event.metadata.mailEnvelope -and $old.metadata.mailEnvelope -ne $event.metadata.mailEnvelope) -or ($event.metadata.mailPurchaseIdentity -and $old.metadata.mailPurchaseIdentity -ne $event.metadata.mailPurchaseIdentity)}
            if(-not (Test-Path -LiteralPath $target) -or $upgrade){
                $event | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath ($target+'.tmp') -Encoding UTF8
                Move-Item -LiteralPath ($target+'.tmp') -Destination $target -Force
                if($upgrade -and (Test-Path -LiteralPath ($target+'.sent'))){Remove-Item -LiteralPath ($target+'.sent') -Force}
                Write-Log ('FOREVER TRADE QUEUED: '+$event.kind+' | '+$event.name+' x'+$event.quantity)
            }
        }catch{Write-Log ('FOREVER TRADE REJECTED: '+$_.Exception.Message)}
    }
}
$script:ForeverUploadAttempt=[datetime]::MinValue
function Send-ForeverTrades([string]$ClientId,[string]$Token) {
    if(((Get-Date)-$script:ForeverUploadAttempt).TotalSeconds -lt 30){return}
    $script:ForeverUploadAttempt=Get-Date
    $directory=Join-Path $StateDir 'Forever\trades'
    if(-not (Test-Path -LiteralPath $directory)){return}
    $files=@(Get-ChildItem -LiteralPath $directory -Filter '*.json' | Where-Object {-not (Test-Path -LiteralPath ($_.FullName+'.sent'))} | Select-Object -First 100)
    if(-not $files.Count){return}
    try{
        $events=@($files | ForEach-Object {Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json})
        $body=@{game='forever';schema=2;events=$events} | ConvertTo-Json -Depth 8 -Compress
        $result=Invoke-RestMethod -Uri 'https://forever.azpc.market/api/trades/upload' -Method Post -Headers @{'x-azpc-client-id'=$ClientId;'x-azpc-watcher-token'=$Token} -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20
        if(-not $result.ok -or $result.accepted -ne $events.Count){throw 'Receiver did not acknowledge this trade batch.'}
        foreach($file in $files){Set-Content -LiteralPath ($file.FullName+'.sent') -Value 'acknowledged' -Encoding ASCII}
        Write-Log ('FOREVER TRADES UPLOADED: '+$events.Count+' confirmed mailbox records.')
    }catch{Write-Log ('FOREVER TRADE UPLOAD PENDING: '+$_.Exception.Message+' Records kept locally; retrying later.')}
}

$script:ForeverScanUploadAttempt=[datetime]::MinValue
function Send-ForeverScans([string]$ClientId,[string]$Token) {
    if(((Get-Date)-$script:ForeverScanUploadAttempt).TotalSeconds -lt 30){return}
    $script:ForeverScanUploadAttempt=Get-Date
    $directory=Join-Path $StateDir 'Forever\scans'
    if(-not (Test-Path -LiteralPath $directory)){return}
    # Rotate failures so one old or invalid record cannot block newer captures.
    $files=@(Get-ChildItem -LiteralPath $directory -Filter '*.json' | Where-Object {-not (Test-Path -LiteralPath ($_.FullName+'.sent'))} | Sort-Object @{Expression={if(Test-Path -LiteralPath ($_.FullName+'.attempt')){(Get-Item -LiteralPath ($_.FullName+'.attempt')).LastWriteTimeUtc}else{[datetime]::MinValue}}},Name | Select-Object -First 1)
    if(-not $files.Count){return}
    $file=$files[0]
    try {
        Set-Content -LiteralPath ($file.FullName+'.attempt') -Value 'pending' -Encoding ASCII
        $scan=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if($file.BaseName -notmatch '^[a-f0-9]{64}$'){throw 'Invalid local scan ID.'}
        $scan | Add-Member -NotePropertyName uploadId -NotePropertyValue $file.BaseName -Force
        $body=$scan | ConvertTo-Json -Depth 8 -Compress
        $bytes=[Text.Encoding]::UTF8.GetBytes($body)
        if($bytes.Length -gt 1048576){throw 'Scan exceeds receiver limit of 1 MB.'}
        $result=Invoke-RestMethod -Uri 'https://forever.azpc.market/api/scans/upload' -Method Post -Headers @{'x-azpc-client-id'=$ClientId;'x-azpc-watcher-token'=$Token} -ContentType 'application/json' -Body $bytes -TimeoutSec 20
        if(-not $result.ok -or $result.accepted -ne $scan.observations.Count -or $result.uploadId -ne $file.BaseName){throw 'Receiver did not acknowledge this exact scan.'}
        Set-Content -LiteralPath ($file.FullName+'.sent') -Value 'acknowledged' -Encoding ASCII
        Write-Log ('FOREVER SCAN UPLOADED: '+$result.accepted+' items | '+$scan.realm+'/'+$scan.faction+' | '+$result.market)
    } catch { Write-Log ('FOREVER SCAN UPLOAD PENDING: '+$_.Exception.Message+' Scan kept locally; retrying later.') }
}

function Convert-ForeverCrafting([string]$Export) {
    $f=$Export.Split('|')
    if($f.Count -ne 3 -or $f[0] -ne 'AZPCFCRAFT' -or $f[1] -ne '1' -or $Export.Length -gt 200000){throw 'Invalid Forever crafting export.'}
    $json=[uri]::UnescapeDataString($f[2]);$row=$json | ConvertFrom-Json
    if($row.schema -ne 1 -or $row.recordType -notin @('recipe','craft','vendor','material') -or -not $row.recordId -or $row.recordId.Length -gt 500 -or -not $row.data){throw 'Invalid Forever crafting identity.'}
    $d=$row.data
    $d.region=[int](Convert-ForeverRegion ([string]$d.region) ([string]$d.realm))
    if(-not $d.realm -or -not $d.character -or $d.faction -notin @('horde','alliance') -or $d.region -notin @(1,2,3,4,5,90) -or $d.observedAt -lt 946684800000L -or $d.observedAt -gt 4102444800000L){throw 'Invalid Forever crafting market.'}
    if($row.recordType -eq 'recipe'){
        if($row.recordId -ne $d.recipeKey -or $d.recipeId -le 0 -or $d.outputItemId -le 0){throw 'Invalid Forever recipe.'}
    }elseif($row.recordId -ne $d.eventId -or $d.itemId -le 0 -or $d.quantity -le 0){throw 'Invalid Forever craft/vendor event.'}
    if($row.recordType -eq 'craft' -and $d.confirmation -ne 'player_spell_success_and_item_result'){throw 'Unconfirmed Forever craft.'}
    if($row.recordType -eq 'vendor' -and ($d.kind -notin @('buy','sell','vendor_unresolved') -or $d.confirmation -ne 'vendor_intent_money_and_bags')){throw 'Unconfirmed Forever vendor event.'}
    if($row.recordType -eq 'material' -and ($d.kind -notin @('free','request_rejected','transfer_out','transfer_in') -or $d.confirmation -notin @('material_quantity_confirmed','material_request_rejected'))){throw 'Unconfirmed material source.'}
    return $row
}
function Collect-ForeverCrafting([string]$Text) {
    $directory=Join-Path $StateDir 'Forever\crafting'
    foreach($match in [regex]::Matches($Text,'\["syncExport"\]\s*=\s*"(AZPCFCRAFT\|[^"\r\n]+)"')){
        try{
            $row=Convert-ForeverCrafting $match.Groups[1].Value
            $body=$row | ConvertTo-Json -Depth 16 -Compress
            $sha=[Security.Cryptography.SHA256]::Create()
            try{$key=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$row.recordId)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $target=Join-Path $directory ($key+'.json')
            if((Test-Path -LiteralPath $target) -and (Get-Content -LiteralPath $target -Raw -Encoding UTF8).Trim() -eq $body){continue}
            Set-Content -LiteralPath ($target+'.tmp') -Value $body -Encoding UTF8
            Move-Item -LiteralPath ($target+'.tmp') -Destination $target -Force
            if(Test-Path -LiteralPath ($target+'.sent')){Remove-Item -LiteralPath ($target+'.sent') -Force}
            Write-Log ('FOREVER CRAFTING QUEUED: '+$row.recordType+' | '+$row.data.name)
        }catch{Write-Log ('FOREVER CRAFTING REJECTED: '+$_.Exception.Message)}
    }
}
$script:ForeverCraftUploadAttempt=[datetime]::MinValue
function Send-ForeverCrafting([string]$ClientId,[string]$Token) {
    if(((Get-Date)-$script:ForeverCraftUploadAttempt).TotalSeconds -lt 30){return}
    $script:ForeverCraftUploadAttempt=Get-Date
    $directory=Join-Path $StateDir 'Forever\crafting'
    if(-not(Test-Path -LiteralPath $directory)){return}
    $files=@(Get-ChildItem -LiteralPath $directory -Filter '*.json' | Where-Object {-not(Test-Path -LiteralPath ($_.FullName+'.sent'))} | Sort-Object @{Expression={if(Test-Path -LiteralPath ($_.FullName+'.attempt')){(Get-Item -LiteralPath ($_.FullName+'.attempt')).LastWriteTimeUtc}else{[datetime]::MinValue}}},Name | Select-Object -First 30)
    if(-not $files.Count){return}
    try{
        $records=@($files | ForEach-Object {Set-Content -LiteralPath ($_.FullName+'.attempt') -Value 'pending' -Encoding ASCII;Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json})
        $body=@{game='forever';schema=1;records=$records} | ConvertTo-Json -Depth 16 -Compress
        $bytes=[Text.Encoding]::UTF8.GetBytes($body);if($bytes.Length -gt 1048576){throw 'Crafting batch exceeds receiver limit.'}
        $result=Invoke-RestMethod -Uri 'https://forever.azpc.market/api/trades/crafting-upload' -Method Post -Headers @{'x-azpc-client-id'=$ClientId;'x-azpc-watcher-token'=$Token} -ContentType 'application/json' -Body $bytes -TimeoutSec 20
        if(-not $result.ok -or $result.accepted -ne $records.Count -or @($result.recordIds).Count -ne $records.Count){throw 'Receiver did not acknowledge this crafting batch.'}
        for($i=0;$i -lt $records.Count;$i++){if($result.recordIds[$i] -ne $records[$i].recordId){throw 'Receiver acknowledged a different crafting identity.'}}
        foreach($file in $files){Set-Content -LiteralPath ($file.FullName+'.sent') -Value 'acknowledged' -Encoding ASCII}
        Write-Log ('FOREVER CRAFTING UPLOADED: '+$records.Count+' recipes/crafts/vendor records.')
    }catch{Write-Log ('FOREVER CRAFTING UPLOAD PENDING: '+$_.Exception.Message+' Records kept locally; retrying later.')}
}

$script:ForeverReadVersions=@{}
function Collect-ForeverScans([string]$Root) {
    foreach($path in @(Find-ForeverSavedVariables $Root)) {
        try {
            $info=Get-Item -LiteralPath $path
            $writeVersion=$info.LastWriteTimeUtc.Ticks.ToString()+':'+$info.Length
            if($script:ForeverReadVersions[$path] -eq $writeVersion){continue}
            if($info.Length -gt 67108864){ throw 'Forever SavedVariables exceeds 64 MB.' }
            $text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
            Collect-ForeverTrades $text
            Collect-ForeverCrafting $text
            foreach($match in [regex]::Matches($text,'\["export"\]\s*=\s*"(AZPCFOREVER\|[^"\r\n]+)"')) {
                $export=$match.Groups[1].Value
                try { $scan=Convert-ForeverExport $export } catch { Write-Log ('FOREVER SCAN REJECTED: '+$_.Exception.Message+' Waiting for new saved data.'); continue }
                $directory=Join-Path $StateDir 'Forever\scans'
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
                $sha=[Security.Cryptography.SHA256]::Create()
                try { $key=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($export)))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
                $target=Join-Path $directory ($key+'.json')
                if(-not (Test-Path -LiteralPath $target)) {
                    $temp=$target+'.tmp'
                    $scan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding UTF8
                    Move-Item -LiteralPath $temp -Destination $target -Force
                    Write-Log ('FOREVER COLLECTED: '+$scan.observations.Count+' items | '+$scan.realm+'/'+$scan.faction+' | saved locally; queued for website upload.')
                }
            }
            $script:ForeverReadVersions[$path]=$writeVersion
        } catch { Write-Log ('FOREVER COLLECT ERROR: '+$_.Exception.Message) }
    }
}

# Website source declarations are copied as data into the installed addon only.
# SavedVariables and account credentials are never rewritten.
function Convert-MaterialLuaString([string]$Text) {
    $encoded=([Text.Encoding]::UTF8.GetBytes($Text) | ForEach-Object {'\'+$_.ToString('000')}) -join ''
    return '"'+$encoded+'"'
}
$script:MaterialCommandsAttempt=[datetime]::MinValue
function Sync-ForeverMaterialCommands([string]$ClientId,[string]$Token,[string]$Root) {
    if(((Get-Date)-$script:MaterialCommandsAttempt).TotalSeconds -lt 30){return}
    $script:MaterialCommandsAttempt=Get-Date
    try {
        $result=Invoke-RestMethod -Uri 'https://forever.azpc.market/api/trades/material-commands' -Method Get -Headers @{'x-azpc-client-id'=$ClientId;'x-azpc-watcher-token'=$Token} -TimeoutSec 20
        if(-not $result.ok -or @($result.commands).Count -gt 500){throw 'Invalid material command reply.'}
        $rows=@()
        foreach($c in @($result.commands)){
            if(-not $c.commandId -or $c.commandId -notmatch '^material-free:[0-9a-f-]{36}$' -or $c.itemId -lt 1 -or $c.itemId -gt 10000000 -or $c.quantity -lt 1 -or $c.quantity -gt 1000000 -or $c.quantity -ne [math]::Floor($c.quantity) -or $c.region -notin @(1,2,3,4,5,90) -or $c.faction -notin @('horde','alliance') -or $c.source -notin @('farmed','gift')){throw 'Invalid material command.'}
            $fields=@();foreach($name in @('commandId','realm','character','name','faction','source')){if(-not $c.$name -or ([string]$c.$name).Length -gt 500){throw 'Invalid material command text.'};$fields+=($name+'='+ (Convert-MaterialLuaString ([string]$c.$name)))}
            foreach($name in @('itemId','quantity','region')){$fields+=($name+'='+[long]$c.$name)}
            $rows+=('{'+($fields -join ',')+'}')
        }
        $block="`n-- AZPC MATERIAL COMMANDS BEGIN`nAZPCForeverMaterialCommands = {"+($rows -join ',')+"}`n-- AZPC MATERIAL COMMANDS END`n"
        $paths=@(Find-ForeverSavedVariables $Root | ForEach-Object {
            $dir=(Get-Item -LiteralPath $_).Directory
            while($dir -and $dir.Name -ne '_classic_beta_'){$dir=$dir.Parent}
            if($dir){Join-Path $dir.FullName 'Interface\AddOns\AZPCForever\AZPCForever.lua'}
        } | Select-Object -Unique)
        foreach($path in $paths){
            if(-not(Test-Path -LiteralPath $path)){continue}
            $text=[IO.File]::ReadAllText($path)
            if($text -notmatch 'ApplyMaterialCommands'){continue}
            $base=[regex]::Replace($text,'\r?\n-- AZPC MATERIAL COMMANDS BEGIN[\s\S]*?-- AZPC MATERIAL COMMANDS END\r?\n?','')
            $updated=$base.TrimEnd()+$block
            if($updated -ne $text){[IO.File]::WriteAllText($path+'.material.tmp',$updated,(New-Object Text.UTF8Encoding($false)));Move-Item -LiteralPath ($path+'.material.tmp') -Destination $path -Force;Write-Log ('FOREVER MATERIAL COMMANDS READY: '+$rows.Count+' declaration(s); /reload applies them.')}
        }
    }catch{Write-Log ('FOREVER MATERIAL SYNC PENDING: '+$_.Exception.Message)}
}

if ($FunctionsOnly) { return }

Write-Log "AZPC Watcher v0.4.38 Alpha Account Lock starting."
Write-Log ("WATCHER INSTANCE: pid=" + $PID + " | script=" + $PSCommandPath + " | dataDir=" + $StateDir)
$credentials = Get-WatcherCredentials $SetupCode
$privateClientId = [string]$credentials.clientId
$watcherToken = [string]$credentials.watcherToken
Write-Log ("Private client ID: " + $privateClientId)
$initialHeartbeatOk = Send-AzpcHeartbeat $privateClientId $watcherToken
if ($ActivateOnly) {
    Write-Log "Activation-only mode complete. This watcher is connected to your AZPC account."
    exit 0
}

$azpcFile = $null
try { $azpcFile = Find-AzpcSavedVariables $WowRoot } catch { Write-Log 'Anniversary SavedVariables not found yet; Forever collection remains active.' }
Write-Log ("Watching: " + $azpcFile)
Write-Log ("Endpoint: " + $Endpoint)
Write-Heartbeat "running" ([string]$azpcFile)

$state = Read-State
$privateState = Read-PrivateState $privateClientId
$lastObservedWrite = [datetime]::MinValue
$lastServerHeartbeat = if ($initialHeartbeatOk) { Get-Date } else { [datetime]::MinValue }

while ($true) {
    try {
        Write-Heartbeat "running" ([string]$azpcFile)
        if (((Get-Date) - $lastServerHeartbeat).TotalSeconds -ge 30) {
            if (Send-AzpcHeartbeat $privateClientId $watcherToken) { $lastServerHeartbeat = Get-Date }
        }
        Collect-ForeverScans $WowRoot
        Send-ForeverTrades $privateClientId $watcherToken
        Send-ForeverCrafting $privateClientId $watcherToken
        Sync-ForeverMaterialCommands $privateClientId $watcherToken $WowRoot
        Send-ForeverScans $privateClientId $watcherToken
        if (-not $azpcFile -or -not (Test-Path -LiteralPath $azpcFile)) {
            Write-Log "AZPC.lua disappeared; searching again..."
            try { $azpcFile = Find-AzpcSavedVariables $WowRoot } catch { $azpcFile=$null }
            if(-not $azpcFile){ if($Once){ break }; Start-Sleep -Seconds 5; continue }
            Write-Log ("Watching: " + $azpcFile)
        }

        $fi = Get-Item -LiteralPath $azpcFile
        $writeUtc = $fi.LastWriteTimeUtc

        if ($writeUtc -gt $lastObservedWrite) {
            $lastObservedWrite = $writeUtc

            # WoW may still be finishing the write; small debounce.
            Start-Sleep -Milliseconds 750
            $text = Get-Content -LiteralPath $azpcFile -Raw -Encoding UTF8

            # Private ledger is completely separate from public market observations.
            Upload-NewPrivateTransactions $text $watcherToken $privateClientId $privateState

            $parsed = Convert-AzpcLuaToLatestRows $text

            if ($parsed.timestamp -gt 0) {
                $sameTimestamp = $parsed.timestamp -eq [Int64]$state.lastSnapshotTimestamp
                $sameContent = (
                    -not [string]::IsNullOrWhiteSpace($parsed.signature) -and
                    $parsed.signature -eq [string]$state.lastSnapshotSignature
                )

                if ($sameContent) {
                    Write-Log (
                        "SavedVariables updated, but market contents are unchanged. Duplicate snapshot skipped (timestamp {0}, signature {1})." -f
                        $parsed.timestamp,
                        $parsed.signature.Substring(0,12)
                    )

                    # Advance timestamp bookkeeping even when content is unchanged,
                    # so a manual recapture of the same AH page does not look pending.
                    Save-State $parsed.timestamp $parsed.signature $writeUtc.ToString("o")
                    $state.lastSnapshotTimestamp = $parsed.timestamp
                    $state.lastSnapshotSignature = $parsed.signature
                    $state.lastFileWriteUtc = $writeUtc.ToString("o")
                }
                elseif ($parsed.timestamp -gt [Int64]$state.lastSnapshotTimestamp -or -not $sameTimestamp) {
                    if (Upload-Snapshot $parsed $privateClientId $watcherToken) {
                        Save-State $parsed.timestamp $parsed.signature $writeUtc.ToString("o")
                        $state.lastSnapshotTimestamp = $parsed.timestamp
                        $state.lastSnapshotSignature = $parsed.signature
                        $state.lastFileWriteUtc = $writeUtc.ToString("o")
                    }
                }
                else {
                    Write-Log ("Snapshot {0} was already processed." -f $parsed.timestamp)
                }
            } else {
                Write-Log "SavedVariables updated, but no real AH snapshot was found yet."
            }
        }

        if ($Once) { break }
        Start-Sleep -Seconds 1
    } catch {
        Write-Log ("WATCH ERROR: " + $_.Exception.Message)
        if ($Once) { exit 1 }
        Start-Sleep -Seconds 5
    }
}



