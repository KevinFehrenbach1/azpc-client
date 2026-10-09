$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('azpc-materials-'+[guid]::NewGuid().ToString('N'))
function Assert($condition,$message){if(-not $condition){throw $message};Write-Host ('PASS: '+$message)}
try {
 . (Join-Path $PSScriptRoot '../../installer/payload/watcher/AZPC-Watcher.ps1') -DataDir (Join-Path $root 'state') -FunctionsOnly
 $wow=Join-Path $root 'WoW';$saved=Join-Path $wow '_classic_beta_\WTF\Account\A\SavedVariables\AZPCForever.lua';$addon=Join-Path $wow '_classic_beta_\Interface\AddOns\AZPCForever\AZPCForever.lua'
 New-Item -ItemType Directory -Path (Split-Path $saved),(Split-Path $addon) -Force | Out-Null
 Set-Content $saved 'saved variables sentinel' -Encoding UTF8
 Set-Content $addon 'AZPCForeverCrafting.ApplyMaterialCommands=function()end' -Encoding UTF8
 $script:command=@{commandId=('material-free:'+ [guid]::NewGuid().ToString());itemId=2589;quantity=10;region=90;faction='horde';source='farmed';realm='Realm';character='Wet';name='Cloth"; malicious() --'}
 function Invoke-RestMethod {param($Uri,$Method,$Headers,$TimeoutSec);Assert ($Uri -eq 'https://forever.azpc.market/api/trades/material-commands' -and $Method -eq 'Get') 'Material declarations use private authenticated GET';Assert ($Headers['x-azpc-client-id'] -eq 'client' -and $Headers['x-azpc-watcher-token'] -eq 'token') 'Material download reuses watcher credentials';return @{ok=$true;commands=@($script:command)}}
 Sync-ForeverMaterialCommands 'client' 'token' $wow
 $text=Get-Content $addon -Raw
 Assert ($text -match 'AZPCForeverMaterialCommands = ' -and $text -match 'itemId=2589' -and $text -match 'quantity=10') 'Website declarations reach the installed addon as bounded data'
 Assert ($text -notmatch 'malicious\(' -and $text -notmatch 'token') 'Untrusted text is Lua byte-escaped; credentials never enter addon files'
 Assert ((Get-Content $saved -Raw).Trim() -eq 'saved variables sentinel') 'Round-trip sync never rewrites SavedVariables'
 $script:MaterialCommandsAttempt=[datetime]::MinValue;Sync-ForeverMaterialCommands 'client' 'token' $wow
 Assert ((Get-Content $addon -Raw) -eq $text) 'Repeated download does not append multiple command blocks'
 $script:command.quantity=0;$script:MaterialCommandsAttempt=[datetime]::MinValue;Sync-ForeverMaterialCommands 'client' 'token' $wow
 Assert ((Get-Content $addon -Raw) -eq $text) 'Invalid command replies preserve the previously validated addon'
 $row=@{schema=1;recordType='material';recordId='free-test';data=@{eventId='free-test';kind='free';itemId=2589;quantity=10;realm='Realm';character='Wet';region=90;faction='horde';observedAt=1791400000000L;name='Cloth';source='farmed';untrackedQuantity=10;confirmation='material_quantity_confirmed'}}
 $export='AZPCFCRAFT|1|'+[uri]::EscapeDataString(($row | ConvertTo-Json -Depth 8 -Compress));$parsed=Convert-ForeverCrafting $export
 Assert ($parsed.recordType -eq 'material' -and $parsed.data.quantity -eq 10) 'Addon-confirmed material sources return through durable crafting uploads'
 $identity='Player-test:Realm:90:buyer:2319:20:29:29899816:Senpai%20Luck:Horde%20Auction%20House:Auction%20won%3A%20Medium%20Leather%20%2829%29:7:1'
 $trade='AZPCFTRADE|1|'+[uri]::EscapeDataString($identity)+'|buy|2319|Medium%20Leather|20|29|1791396972|Realm|horde|90|Wet'
 $other='AZPCFTRADE|1|'+[uri]::EscapeDataString($identity.Replace(':2319:20:29:',':2319:29:29:'))+'|buy|2319|Medium%20Leather|29|29|1791396973|Realm|horde|90|Wet'
 $first=Convert-ForeverTrade $trade;$second=Convert-ForeverTrade $other
 Assert ($first.metadata.mailPurchaseIdentity -eq $second.metadata.mailPurchaseIdentity -and $first.eventId -ne $second.eventId) 'Quantity-independent purchase evidence preserves raw events while identifying conflicting copies'
 $dir=Join-Path $StateDir 'Forever\trades';New-Item -ItemType Directory -Path $dir -Force | Out-Null;$target=Join-Path $dir ($first.eventId.Substring(5)+'.json')
 $old=$first.Clone();$old.metadata=$first.metadata.Clone();$old.metadata.Remove('mailPurchaseIdentity');$old|ConvertTo-Json -Depth 5|Set-Content $target -Encoding UTF8;Set-Content ($target+'.sent') 'ack'
 Collect-ForeverTrades ('["tradeExport"] = "'+$trade+'"')
 Assert (-not (Test-Path ($target+'.sent')) -and (Get-Content $target -Raw|ConvertFrom-Json).metadata.mailPurchaseIdentity) 'Old sent purchases are requeued once with repair evidence'
 $row=@{schema=1;recordType='material';recordId='bank-test';data=@{eventId='bank-test';kind='inventory_observation';itemId=2318;quantity=22;bagQuantity=2;bankQuantity=20;ownedQuantity=22;reservedQuantity=0;realm='Realm';character='Wet';region=90;faction='horde';observedAt=1791524000000L;name='Light Leather';confirmation='bags_and_character_bank_observed'}}
 $export='AZPCFCRAFT|1|'+[uri]::EscapeDataString(($row | ConvertTo-Json -Depth 8 -Compress));$parsed=Convert-ForeverCrafting $export
 Assert ($parsed.data.bankQuantity -eq 20 -and $parsed.data.bagQuantity -eq 2) 'Confirmed bank quantities survive the existing upload queue'
 foreach($change in @(-1,19)){$row.data.bankQuantity=$change;$bad='AZPCFCRAFT|1|'+[uri]::EscapeDataString(($row | ConvertTo-Json -Depth 8 -Compress));$rejected=$false;try{Convert-ForeverCrafting $bad | Out-Null}catch{$rejected=$true};Assert $rejected 'Invalid bank counts and mismatched totals are rejected'}
} finally {Remove-Item $root -Recurse -Force}
