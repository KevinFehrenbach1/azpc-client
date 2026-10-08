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
    foreach($kind in @('buy','sell','expired')) {
        $current=$trade.Replace('|buy|',('|'+$kind+'|'))
        if($kind -eq 'expired'){$current=$current.Replace('|3|100|','|3|0|')}
        $correct=Convert-ForeverTrade $current
        $legacy=Convert-ForeverTrade ($current+'|0')
        Assert ($legacy.eventId -eq $correct.eventId -and $legacy.kind -eq $correct.kind -and $legacy.quantity -eq $correct.quantity) 'Recover old addon extra-field exports without changing event identity'
    }
    $encoded=$trade.Replace('|Tester','|Test%20Name')
    Assert ((Convert-ForeverTrade ($encoded+'|1')).character -eq 'Test Name') 'Recover legacy percent-encoded character export'
    foreach($bad in @(($trade+'|1'),($trade+'|unexpected'),($trade+'|0|0'))) {
        $rejected=$false;try {Convert-ForeverTrade $bad | Out-Null} catch {$rejected=$true}
        Assert $rejected 'Reject malformed extra fields beyond the known legacy format'
    }
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


# v2 preserves exact mail refund and lifecycle observations without fabricating trades.
$v2='AZPCFTRADE|2|v2-sale|sell|2447|Peacebloom|3|200|1790830800000|Forever%20Test|horde|90|Tester|25|10|225|||||'
$parsed=Convert-ForeverTrade $v2
Assert ($parsed.copper -eq 200 -and $parsed.metadata.mailPayout -eq 225 -and $parsed.metadata.deposit -eq 25 -and $parsed.metadata.netProceedsKnown -eq $true) 'v2 sale separates refunded deposit from net proceeds'
$listing='AZPCFTRADE|2|v2-owner|listing_snapshot|2447|Peacebloom|6|0|1790830800001|Forever%20Test|horde|90|Tester||||4|2|0||'
$parsed=Convert-ForeverTrade $listing
Assert ($parsed.metadata.listedQuantity -eq 4 -and $parsed.metadata.pendingQuantity -eq 2 -and $parsed.observedAt -eq 1790830800001) 'v2 owner capture preserves listed and pending quantities with event order'
$bag='AZPCFTRADE|2|v2-bags|inventory_snapshot|2447|Peacebloom|0|0|1790830800002|Forever%20Test|horde|90|Tester|||||||0|'
$parsed=Convert-ForeverTrade $bag
Assert ($parsed.quantity -eq 0 -and $parsed.metadata.bagQuantity -eq 0) 'empty bags clear available inventory'
foreach($bad in @($v2.Replace('|200|','|225|'),$listing.Replace('|6|0|','|7|0|'),$bag.Replace('|inventory_snapshot|','|sell|'))){$rejected=$false;try{Convert-ForeverTrade $bad | Out-Null}catch{$rejected=$true};Assert $rejected 'Reject inconsistent v2 accounting and lifecycle records'}

$identity='Player-test:Forever Test:90:seller:2447:1:1180:30000000:Buyer:Auction%20House:Auction%20successful%3A%20Peacebloom:3:1'
$receipt=$v2.Replace('v2-sale',[uri]::EscapeDataString($identity))
$first=Convert-ForeverTrade $receipt
$repeat=Convert-ForeverTrade ($receipt.Replace([uri]::EscapeDataString($identity),[uri]::EscapeDataString($identity.Replace(':30000000:',':30000001:'))))
Assert ($first.eventId -ne $repeat.eventId -and $first.metadata.mailIdentity -eq $repeat.metadata.mailIdentity -and $repeat.metadata.mailExpiryMinute -eq 30000001) 'Historical drifting IDs retain stable full mailbox evidence'
$second=Convert-ForeverTrade ($receipt.Replace([uri]::EscapeDataString($identity),[uri]::EscapeDataString($identity.Substring(0,$identity.Length-1)+'2')))
Assert ($first.metadata.mailIdentity -ne $second.metadata.mailIdentity) 'Simultaneous identical receipts preserve occurrence ordinal'
$queueRoot=Join-Path ([IO.Path]::GetTempPath()) ('azpc-receipts-'+[guid]::NewGuid().ToString('N'))
try {
 $StateDir=$queueRoot
 New-Item -ItemType Directory -Path $queueRoot -Force | Out-Null
 $LogFile=Join-Path $queueRoot 'watcher.log'
 Collect-ForeverTrades ('{ ["tradeExport"]="'+$receipt+'" }')
 $file=Get-ChildItem (Join-Path $queueRoot 'Forever/trades') -Filter '*.json' | Select-Object -First 1
 $old=Get-Content $file.FullName -Raw | ConvertFrom-Json
 $old.metadata.PSObject.Properties.Remove('mailIdentity');$old.metadata.PSObject.Properties.Remove('mailExpiryMinute')
 $old | ConvertTo-Json -Depth 8 | Set-Content $file.FullName -Encoding UTF8
 Set-Content ($file.FullName+'.sent') 'sent'
 Collect-ForeverTrades ('{ ["tradeExport"]="'+$receipt+'" }')
 Assert (-not (Test-Path ($file.FullName+'.sent'))) 'Previously acknowledged receipt is requeued for evidence enrichment'
 Assert ((Get-Content $file.FullName -Raw | ConvertFrom-Json).metadata.mailIdentity -eq $first.metadata.mailIdentity) 'Enrichment retains stable evidence without changing event ID'
} finally {Remove-Item $queueRoot -Recurse -Force}

$blank=Convert-ForeverTrade ($receipt.Replace([uri]::EscapeDataString($identity),[uri]::EscapeDataString($identity.Replace(':Buyer:', '::'))))
Assert ($blank.metadata.mailEnvelope -eq $first.metadata.mailEnvelope -and $blank.metadata.mailBuyerKnown -eq $false -and $first.metadata.mailBuyerKnown -eq $true) 'Blank and hydrated buyer share envelope evidence while keeping distinct receipt IDs'
