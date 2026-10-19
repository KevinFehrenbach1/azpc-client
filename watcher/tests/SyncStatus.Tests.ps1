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
 $main=Join-Path $addon 'AZPCForever.lua'
 $target=$main;Set-Content -LiteralPath $main -Value "original capture code`n-- AZPC WATCHER STATUS BEGIN`nAZPCForeverWatcherStatus=nil`n-- AZPC WATCHER STATUS END`noriginal footer"
 $script:ForeverReadVersions=@{};$script:ForeverReadVersions[$sv]='verified'
 Save-ForeverUploadStatus 12
 Write-ForeverAddonStatus
 $text=Get-Content -LiteralPath $target -Raw
 Assert ($text -match 'schema=1,checkedAt=\d+,lastUploadAt=\d+,lastUploadCount=12') 'Confirmed upload count and numeric times reach optional status file'
 Assert ($text -notmatch 'token|clientId|userId') 'Addon status contains no credentials or account identifiers'
 Assert ((Get-Content -LiteralPath $sv -Raw).Trim() -eq 'original saved evidence') 'Status never writes SavedVariables'
 Assert (([regex]::Replace((Get-Content -LiteralPath $main -Raw),'(?s)-- AZPC WATCHER STATUS BEGIN.*?-- AZPC WATCHER STATUS END','STATUS')).Trim() -eq "original capture code`nSTATUS`noriginal footer") 'Status leaves capture code byte-for-byte outside its section'
 $script:ForeverLastUploadAt=0L;$script:ForeverLastUploadCount=0;$script:ForeverStatusWriteAttempt=[datetime]::MinValue
 Write-ForeverAddonStatus
 Assert ((Get-Content -LiteralPath $target -Raw) -match 'lastUploadCount=12') 'Last acknowledged upload survives watcher restart'
 Set-Content -LiteralPath $target -Value 'old addon with no status section';$script:ForeverStatusWriteAttempt=[datetime]::MinValue
 Write-ForeverAddonStatus
 Assert ((Get-Content -LiteralPath $target -Raw).Trim() -eq 'old addon with no status section') 'Older addon installations without status section are untouched'
 # Existing transport tests verify failures/wrong acknowledgements stay queued.
 # Only successful acknowledgement branches call Save-ForeverUploadStatus.
 $source=Get-Content (Join-Path $PSScriptRoot '../../installer/payload/watcher/AZPC-Watcher.ps1') -Raw
 Assert (($source | Select-String -Pattern 'Save-ForeverUploadStatus \$(events|records|scan)' -AllMatches).Matches.Count -eq 3) 'Status is published only from the three confirmed Forever upload branches'
} finally {if(Test-Path $root){Remove-Item $root -Recurse -Force}}
