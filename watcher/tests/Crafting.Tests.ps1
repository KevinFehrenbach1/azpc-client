$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('azpc-crafts-'+[guid]::NewGuid().ToString('N'))
function Assert($condition,$message){if(-not $condition){throw $message};Write-Host "PASS: $message"}
try {
 . (Join-Path $PSScriptRoot '../../installer/payload/watcher/AZPC-Watcher.ps1') -DataDir $root -FunctionsOnly
 $fixture=Get-Content (Join-Path $PSScriptRoot 'fixtures/forever-crafting.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 $text=($fixture.exports | ForEach-Object {'["syncExport"] = "'+$_+'"'}) -join "`n"
 Collect-ForeverCrafting $text;Collect-ForeverCrafting $text
 $dir=Join-Path $root 'Forever/crafting';$files=@(Get-ChildItem $dir -Filter '*.json')
 Assert ($files.Count -eq 4) 'Actual addon JSON recipes, vendor purchases and crafts queue once'
 $parsed=Convert-ForeverCrafting $fixture.exports[3]
 Assert ($parsed.data.name -eq 'Bag café' -and $parsed.data.costBasis.totalCopper -eq 12 -and $parsed.data.consumedReagents.Count -eq 2) 'UTF8 name and chained cost survive JSON export parsing'
 $script:requests=0;$script:fail=$true;$script:badAck=$false
 function Invoke-RestMethod {
  param($Uri,$Method,$Headers,$ContentType,$Body,$TimeoutSec)
  Assert ($Uri -eq 'https://forever.azpc.market/api/trades/crafting-upload') 'Crafting stays on the authenticated Forever endpoint'
  Assert ($Headers['x-azpc-client-id'] -eq 'client' -and $Headers['x-azpc-watcher-token'] -eq 'token') 'Watcher sends existing credentials'
  $script:requests++;if($script:fail){throw 'offline'}
  $data=[Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
  Assert ($data.game -eq 'forever' -and $data.schema -eq 1 -and $data.records.Count -eq 4) 'Upload retains all record types in a single private batch'
  $ids=@($data.records | ForEach-Object {$_.recordId});if($script:badAck){$ids[0]='wrong'}
  return @{ok=$true;accepted=$data.records.Count;recordIds=$ids}
 }
 Send-ForeverCrafting 'client' 'token';Assert (@(Get-ChildItem $dir -Filter '*.sent').Count -eq 0) 'Offline upload keeps every record pending'
 $script:ForeverCraftUploadAttempt=[datetime]::MinValue;$script:fail=$false;$script:badAck=$true
 Send-ForeverCrafting 'client' 'token';Assert (@(Get-ChildItem $dir -Filter '*.sent').Count -eq 0) 'Wrong acknowledgement cannot discard data'
 $script:ForeverCraftUploadAttempt=[datetime]::MinValue;$script:badAck=$false
 Send-ForeverCrafting 'client' 'token';Assert (@(Get-ChildItem $dir -Filter '*.sent').Count -eq 4) 'Exact record acknowledgement marks the batch sent'
 $script:ForeverCraftUploadAttempt=[datetime]::MinValue;Send-ForeverCrafting 'client' 'token';Assert ($script:requests -eq 3) 'Sent records do not upload repeatedly'
 $record=$parsed;$record.data.costConflict=$true
 $changed='AZPCFCRAFT|1|'+[uri]::EscapeDataString(($record | ConvertTo-Json -Depth 16 -Compress))
 Collect-ForeverCrafting ('["syncExport"]="'+$changed+'"')
 Assert (@(Get-ChildItem $dir -Filter '*.sent').Count -eq 3) 'Changed cost evidence requeues the same identity without another craft file'
 Assert (@(Get-ChildItem $dir -Filter '*.json').Count -eq 4) 'Evidence updates retain stable identities'
} finally {if(Test-Path $root){Remove-Item $root -Recurse -Force}}
