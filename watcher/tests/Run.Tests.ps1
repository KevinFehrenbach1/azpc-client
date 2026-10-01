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
} finally { Remove-Item $root -Recurse -Force }
