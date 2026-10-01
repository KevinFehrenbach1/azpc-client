param([string]$ReleaseTag = 'launcher-v0.2.3')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $PSScriptRoot 'dist'
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Path $dist,(Join-Path $dist 'launcher'),(Join-Path $dist 'installer\payload') -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot '*.ps1') (Join-Path $dist 'launcher')
Copy-Item (Join-Path $repoRoot 'installer\payload\*') (Join-Path $dist 'installer\payload') -Recurse
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $csc /nologo /target:winexe /platform:anycpu /reference:System.Windows.Forms.dll ('/out:' + (Join-Path $dist 'AZPC-Launcher.exe')) (Join-Path $PSScriptRoot 'Launcher.cs')
if ($LASTEXITCODE -ne 0) { throw 'Launcher EXE compilation failed.' }
$output = Join-Path $PSScriptRoot 'output'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$bundle = Join-Path $output 'azpc-components.zip'
if (Test-Path $bundle) { Remove-Item $bundle -Force }
$payload = Join-Path $repoRoot 'installer\payload'
$components=Join-Path $dist 'components'
New-Item -ItemType Directory -Path (Join-Path $components 'addon') -Force | Out-Null
Copy-Item (Join-Path $payload 'addon\AZPC') (Join-Path $components 'addon') -Recurse
Copy-Item (Join-Path $payload 'watcher'),(Join-Path $payload 'VERSION.json') $components -Recurse
Compress-Archive -Path (Join-Path $components '*') -DestinationPath $bundle
$version = Get-Content (Join-Path $payload 'VERSION.json') -Raw | ConvertFrom-Json
$manifest = @{
    schema=1; game='tbc-anniversary'; channel='alpha'; launcherVersion='0.2.3'
    addonVersion=$version.addonVersion; watcherVersion=$version.watcherVersion
    bundleUrl=('https://github.com/KevinFehrenbach1/azpc-client/releases/download/'+$ReleaseTag+'/azpc-components.zip')
    bundleSha256=(Get-FileHash $bundle -Algorithm SHA256).Hash.ToLowerInvariant()
}
$manifest | ConvertTo-Json | Set-Content (Join-Path $output 'azpc-update.json') -Encoding UTF8
Remove-Item $components -Recurse -Force
$portable=Join-Path $output 'AZPC-Launcher-Portable.zip'
if (Test-Path $portable) { Remove-Item $portable -Force }
Compress-Archive -Path (Join-Path $dist '*') -DestinationPath $portable

$forever=Join-Path $dist 'forever-components'
New-Item -ItemType Directory -Path (Join-Path $forever 'addon') -Force | Out-Null
Copy-Item (Join-Path $payload 'addon/AZPCForever') (Join-Path $forever 'addon') -Recurse
Copy-Item (Join-Path $payload 'watcher') $forever -Recurse
$foreverVersions=@{game='forever';addonVersion=$version.foreverAddonVersion;watcherVersion=$version.watcherVersion}
$foreverVersions | ConvertTo-Json | Set-Content (Join-Path $forever 'VERSION.json') -Encoding UTF8
$foreverBundle=Join-Path $output 'azpc-forever-components.zip'
Compress-Archive -Path (Join-Path $forever '*') -DestinationPath $foreverBundle -Force
@{schema=1;game='forever';launcherVersion='0.2.3';addonVersion=$version.foreverAddonVersion;watcherVersion=$version.watcherVersion;bundleUrl=('https://github.com/KevinFehrenbach1/azpc-client/releases/download/'+$ReleaseTag+'/azpc-forever-components.zip');bundleSha256=(Get-FileHash $foreverBundle -Algorithm SHA256).Hash.ToLowerInvariant()} | ConvertTo-Json | Set-Content (Join-Path $output 'azpc-forever-update.json') -Encoding UTF8
Remove-Item $forever -Recurse -Force
