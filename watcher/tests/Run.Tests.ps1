$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('azpc-forever-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
function Assert($condition,$message){if(-not $condition){throw $message};Write-Host "PASS: $message"}
try {
    $data=Join-Path $root 'state'
    . (Join-Path $PSScriptRoot '../../installer/payload/watcher/AZPC-Watcher.ps1') -DataDir $data -FunctionsOnly
    function Invoke-RestMethod { throw 'Forever collection must never use Anniversary upload' }
    $export='AZPCFOREVER|1|Forever%20Test|horde|1|1790830800;2447|Peacebloom|150|20|2'
    $betaExport=$export.Replace('Forever%20Test|horde|1|1790830800','Classic%20Beta%20PvP%202|horde|90|1790830800')
    $betaScan=Convert-ForeverExport $betaExport
    Assert ($betaScan.region -eq 90 -and $betaScan.realm -eq 'Classic Beta PvP 2') 'Accept real Forever beta region 90 without mapping to live regions'
    $scan=Convert-ForeverExport $export
    Assert ($scan.game -eq 'forever' -and $scan.realm -eq 'Forever Test' -and $scan.observations[0].price -eq 150) 'Parse realm and per-unit copper'
    foreach($bad in @($export.Replace('|horde|','|invalid|'),$export.Replace('|1|179','|0|179'),($export+';2447|duplicate|10|1|1'),$export.Replace('|150|','|-1|'),$export.Replace('1790830800','9223372036854775807'))){
        $rejected=$false;try { Convert-ForeverExport $bad | Out-Null } catch {$rejected=$true};Assert $rejected 'Reject invalid export'
    }
    $wow=Join-Path $root 'WoW'
    foreach($account in @('A','B')){
        $sv=Join-Path $wow "_classic_beta_/WTF/Account/$account/SavedVariables"
        New-Item -ItemType Directory -Path $sv -Force | Out-Null
        Set-Content (Join-Path $sv 'AZPCForever.lua') ('AZPCForeverDB = { ["snapshots"] = { { ["export"] = "'+$export+'" } } }')
    }
    Set-Content (Join-Path $data 'watcher-credentials.json') 'credential sentinel'
    Set-Content (Join-Path $data 'private-ledger-state.json') 'private sentinel'
    Assert (@(Find-ForeverSavedVariables $wow).Count -eq 2) 'Find all beta accounts'
    Collect-ForeverScans $wow;Collect-ForeverScans $wow
    $files=@(Get-ChildItem (Join-Path $data 'Forever/scans') -Filter '*.json')
    Assert ($files.Count -eq 1) 'Repeated captures deduplicate across accounts'
    $queued=Get-Content $files[0].FullName -Raw | ConvertFrom-Json
    Assert ($queued.game -eq 'forever' -and $queued.scope -eq 'loaded_browse_results') 'Queue explicitly identifies Forever browse coverage'
    Assert ((Get-Content (Join-Path $data 'watcher-credentials.json') -Raw).Trim() -eq 'credential sentinel') 'Credentials preserved'
    Assert ((Get-Content (Join-Path $data 'private-ledger-state.json') -Raw).Trim() -eq 'private sentinel') 'Private ledger preserved'
    $svFile=Join-Path $wow '_classic_beta_/WTF/Account/A/SavedVariables/AZPCForever.lua'
    $invalid=$export.Replace('|horde|','|invalid|')
    Set-Content $svFile ('{ ["export"]="'+$invalid+'", ["snapshots"]={ { ["export"]="'+$betaExport+'" } } }')
    Collect-ForeverScans $wow
    $logBefore=(Get-Item $LogFile).Length
    Collect-ForeverScans $wow
    Assert ((Get-Item $LogFile).Length -eq $logBefore) 'Unchanged rejected data does not spam the log'
    Assert (@(Get-ChildItem (Join-Path $data 'Forever/scans') -Filter '*.json').Count -eq 2) 'Invalid snapshot does not block valid beta snapshot'
    $trade='AZPCFTRADE|1|unique-mail-id|buy|2447|Peacebloom|3|100|1790830800|Classic%20Beta%20PvP%202|horde|90|Tester'
    $event=Convert-ForeverTrade $trade
    Assert ($event.quantity -eq 3 -and $event.copper -eq 100 -and $event.region -eq 90) 'Trade preserves total copper, stack quantity and beta region'
    Collect-ForeverTrades ('{ ["tradeExport"]="'+$trade+'" }')
    Collect-ForeverTrades ('{ ["tradeExport"]="'+$trade+'" }')
    Assert (@(Get-ChildItem (Join-Path $data 'Forever/trades') -Filter '*.json').Count -eq 1) 'Mailbox trade is queued exactly once'
    function Invoke-RestMethod {param($Uri,$Method,$Headers,$ContentType,$Body,$TimeoutSec)
        Assert ($Uri -eq 'https://forever.azpc.market/api/trades/upload') 'Private Forever records go only to Forever receiver'
        Assert ($Headers['x-azpc-watcher-token'] -eq 'test-token') 'Upload uses existing authenticated watcher credential'
        $sent=[Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
        Assert ($sent.game -eq 'forever' -and $sent.events[0].quantity -eq 3) 'Receiver gets versioned private event batch'
        return @{ok=$true;accepted=1}
    }
    Send-ForeverTrades 'test-client' 'test-token'
    Assert (@(Get-ChildItem (Join-Path $data 'Forever/trades') -Filter '*.sent').Count -eq 1) 'Only acknowledged upload is marked sent'
    $expired=$trade.Replace('unique-mail-id|buy','expired-mail-id|expired').Replace('|3|100|','|7|0|')
    $event=Convert-ForeverTrade $expired
    Assert ($event.kind -eq 'expired' -and $event.quantity -eq 7 -and $event.copper -eq 0) 'Expired returns preserve stack count without proceeds'
    $rejected=$false;try {Convert-ForeverTrade ($expired.Replace('|7|0|','|7|1|')) | Out-Null} catch {$rejected=$true}
    Assert $rejected 'Expired returns reject invented proceeds'
    Collect-ForeverTrades ('{ ["tradeExport"]="'+$expired+'" }')
    Collect-ForeverTrades ('{ ["tradeExport"]="'+$expired+'" }')
    Assert (@(Get-ChildItem (Join-Path $data 'Forever/trades') -Filter '*.json').Count -eq 2) 'Expired return queues exactly once'
    $script:ForeverUploadAttempt=[datetime]::MinValue
    function Invoke-RestMethod {throw 'simulated offline receiver'}
    Send-ForeverTrades 'test-client' 'test-token'
    Assert (@(Get-ChildItem (Join-Path $data 'Forever/trades') -Filter '*.sent').Count -eq 1) 'Offline expired return stays queued'
    $script:ForeverUploadAttempt=[datetime]::MinValue
    function Invoke-RestMethod {param($Uri,$Method,$Headers,$ContentType,$Body,$TimeoutSec)
        $sent=[Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
        Assert ($Uri -eq 'https://forever.azpc.market/api/trades/upload' -and $sent.events[0].kind -eq 'expired' -and $sent.events[0].quantity -eq 7 -and $sent.events[0].copper -eq 0) 'Expired return uploads with zero trade value'
        return @{ok=$true;accepted=1}
    }
    Send-ForeverTrades 'test-client' 'test-token'
    Assert (@(Get-ChildItem (Join-Path $data 'Forever/trades') -Filter '*.sent').Count -eq 2) 'Acknowledged expired return is marked sent'
    function Invoke-RestMethod {param($Uri,$Method,$Headers,$ContentType,$Body,$TimeoutSec)
        Assert ($Uri -eq 'https://forever.azpc.market/api/scans/upload') 'Market scans go only to Forever scan receiver'
        Assert ($Headers['x-azpc-watcher-token'] -eq 'test-token') 'Scan upload uses existing watcher credential'
        $sent=[Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
        Assert ($sent.scope -eq 'loaded_browse_results' -and $sent.uploadId -match '^[a-f0-9]{64}$') 'Scan upload retains partial scope and stable ID'
        return @{ok=$true;accepted=$sent.observations.Count;uploadId=$sent.uploadId;market='test-market'}
    }
    Send-ForeverScans 'test-client' 'test-token'
    Assert (@(Get-ChildItem (Join-Path $data 'Forever/scans') -Filter '*.sent').Count -eq 1) 'Acknowledged market scan is marked sent'
    $script:ForeverScanUploadAttempt=[datetime]::MinValue
    function Invoke-RestMethod { throw 'simulated offline receiver' }
    Send-ForeverScans 'test-client' 'test-token'
    Assert (@(Get-ChildItem (Join-Path $data 'Forever/scans') -Filter '*.sent').Count -eq 1) 'Offline scan is retained without a false acknowledgement'
    $script:ForeverScanUploadAttempt=[datetime]::MinValue
    function Invoke-RestMethod { return @{ok=$true;accepted=1;uploadId='wrong-id';market='test-market'} }
    Send-ForeverScans 'test-client' 'test-token'
    Assert (@(Get-ChildItem (Join-Path $data 'Forever/scans') -Filter '*.sent').Count -eq 1) 'Mismatched acknowledgement does not mark a scan sent'
} finally { Remove-Item $root -Recurse -Force }

