$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('azpc-sync-'+[guid]::NewGuid().ToString('N'))
function Assert($condition,$message){if(-not $condition){throw $message};Write-Host ('PASS: '+$message)}
try {
 . (Join-Path $PSScriptRoot '../../installer/payload/watcher/AZPC-Watcher.ps1') -DataDir $root -FunctionsOnly
 $client=Join-Path $root 'WoW/_classic_beta_'
 $sv=Join-Path $client 'WTF/Account/ACCOUNT/SavedVariables/AZPCForever.lua'
 $addon=Join-Path $client 'Interface/AddOns/AZPCForever'
 New-Item -ItemType Directory -Force -Path (Split-Path $sv),$addon | Out-Null
 Set-Content -LiteralPath $sv -Value 'original saved evidence'
 $main=Join-Path $addon 'AZPCForever.lua';Set-Content -LiteralPath $main -Value 'original capture code'
 $target=Join-Path $addon 'AZPCForeverStatus.lua';Set-Content -LiteralPath $target -Value 'AZPCForeverWatcherStatus=nil'
 $script:ForeverReadVersions=@{};$script:ForeverReadVersions[$sv]='verified'
 Save-ForeverUploadStatus 12
 Write-ForeverAddonStatus
 $text=Get-Content -LiteralPath $target -Raw
 Assert ($text -match 'schema=1,checkedAt=\d+,lastUploadAt=\d+,lastUploadCount=12') 'Confirmed upload count and numeric times reach optional status file'
 Assert ($text -notmatch 'token|clientId|userId') 'Addon status contains no credentials or account identifiers'
 Assert ((Get-Content -LiteralPath $sv -Raw).Trim() -eq 'original saved evidence') 'Status never writes SavedVariables'
 Assert ((Get-Content -LiteralPath $main -Raw).Trim() -eq 'original capture code') 'Status never modifies capture code'
 $script:ForeverLastUploadAt=0L;$script:ForeverLastUploadCount=0;$script:ForeverStatusWriteAttempt=[datetime]::MinValue
 Write-ForeverAddonStatus
 Assert ((Get-Content -LiteralPath $target -Raw) -match 'lastUploadCount=12') 'Last acknowledged upload survives watcher restart'
 Remove-Item -LiteralPath $target;$script:ForeverStatusWriteAttempt=[datetime]::MinValue
 Write-ForeverAddonStatus
 Assert (-not(Test-Path -LiteralPath $target)) 'Older addon installations without status file are untouched'
 # Existing transport tests verify failures/wrong acknowledgements stay queued.
 # Only successful acknowledgement branches call Save-ForeverUploadStatus.
 $source=Get-Content (Join-Path $PSScriptRoot '../../installer/payload/watcher/AZPC-Watcher.ps1') -Raw
 Assert (($source | Select-String -Pattern 'Save-ForeverUploadStatus \$(events|records|scan)' -AllMatches).Matches.Count -eq 3) 'Status is published only from the three confirmed Forever upload branches'
} finally {if(Test-Path $root){Remove-Item $root -Recurse -Force}}
