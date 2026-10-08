$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Launcher.Core.ps1')
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};Write-Host ('PASS: '+$Message)}
$script:gameOpen=$false
function Assert-GameClosed{if($script:gameOpen){throw 'Close WoW first'}}
function Get-InstalledStatus{return @{Addon='0.2.12'}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('azpc-repair-tests-'+[guid]::NewGuid().ToString('N'))
$folder=Join-Path $root '_classic_beta_\WTF\Account\TEST\SavedVariables'
New-Item -ItemType Directory $folder -Force|Out-Null
$file=Join-Path $folder 'AZPCForever.lua'
function Row($kind,$item,$q,$c,$at){return '["tradeExport"]="AZPCFTRADE|2|fixture|'+$kind+'|'+$item+'|Item|'+$q+'|'+$c+'|'+$at+'|Classic%20Beta%20PvP%202|horde|90|Lu||||||||",'}
$times=@(1791444821000L,1791444824000L,1791444827000L,1791444830000L,1791444834000L,1791444836000L,1791444840000L,1791444843000L)
$rows=@()
for($i=0;$i -lt 8;$i++){$rows+=(Row 'inventory_snapshot' 2996 ($i+1) 0 $times[$i]);$rows+=(Row 'inventory_snapshot' 2589 (14-2*$i) 0 ($times[$i]+1))}
$rows+=(Row 'buy' 2589 8 8 1791444677000L);$rows+=(Row 'buy' 2589 2 2 1791445396000L);$rows+=(Row 'buy' 2589 4 4 1791447230000L)
$rows+=(Row 'inventory_snapshot' 2996 11 0 1791447247000L);$rows+=(Row 'inventory_snapshot' 2589 0 0 1791447247001L)
$original='AZPCForeverDB={ ["trades"]={'+($rows -join "`r`n")+'}, ["crafting"]={["materialEvents"] = {}, ["crafts"]={{["eventId"]="preserve-craft",["costBasis"]={["totalCopper"]=77}}}},["other"]="preserve-current-data" }'
try{
 [IO.File]::WriteAllText($file,$original,(New-Object Text.UTF8Encoding($false)))
 $before=(Get-FileHash $file).Hash
 $script:gameOpen=$true
 try{Repair-ForeverLinen $root|Out-Null;throw 'Expected game guard'}catch{Assert ($_.Exception.Message -match 'Close WoW') 'Running WoW blocks repair'}
 Assert ((Get-FileHash $file).Hash -eq $before) 'Game guard leaves save unchanged'
 $script:gameOpen=$false
 $result=Repair-ForeverLinen $root
 Assert ($result.ok) 'Launcher applies verified repair'
 $updated=[IO.File]::ReadAllText($file)
 Assert ($updated.Contains('preserve-craft') -and $updated.Contains('preserve-current-data') -and $updated.Contains('["totalCopper"]=77')) 'Historical and newly recorded data retained'
 Assert ([regex]::Matches($updated,'\["eventId"\]="material-reconcile:lu-linen-20261008:').Count -eq 2) 'Exactly two corrections appended'
 $backup=@(Get-ChildItem $folder -Filter '*.azpc-linen-backup-*')
 Assert ($backup.Count -eq 1 -and (Get-FileHash $backup[0].FullName).Hash -eq $before) 'Automatic backup preserves original bytes'
 $after=(Get-FileHash $file).Hash
 $null=Repair-ForeverLinen $root
 Assert ((Get-FileHash $file).Hash -eq $after -and @(Get-ChildItem $folder -Filter '*.azpc-linen-backup-*').Count -eq 1) 'Repeated clicks are idempotent'
 [IO.File]::WriteAllText($file,$original.Replace('|2996|Item|11|0|1791447247000','|2996|Item|12|0|1791447247000'))
 try{Repair-ForeverLinen $root|Out-Null;throw 'Expected inventory guard'}catch{Assert ($_.Exception.Message -match 'inventory has changed') 'Changed inventory is not silently corrected'}
 [IO.File]::WriteAllText($file,$original.Replace('|2589|Item|4|4|1791447230000','|2589|Item|4|40|1791447230000'))
 try{Repair-ForeverLinen $root|Out-Null;throw 'Expected cost guard'}catch{Assert ($_.Exception.Message -match 'purchase costs') 'Changed paid costs block repair'}
 [IO.File]::WriteAllText($file,$original.Replace('1791444821000','1791444829000'))
 try{Repair-ForeverLinen $root|Out-Null;throw 'Expected evidence guard'}catch{Assert ($_.Exception.Message -match 'No unique') 'Missing conversion evidence blocks repair'}
}finally{Remove-Item $root -Recurse -Force}
