param([string]$ReleaseTag = 'launcher-v0.2.0')
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
Compress-Archive -Path (Join-Path $payload 'addon'),(Join-Path $payload 'watcher'),(Join-Path $payload 'VERSION.json') -DestinationPath $bundle
$version = Get-Content (Join-Path $payload 'VERSION.json') -Raw | ConvertFrom-Json
$manifest = @{
    schema=1; game='tbc-anniversary'; channel='alpha'; launcherVersion='0.2.0'
    addonVersion=$version.addonVersion; watcherVersion=$version.watcherVersion
    bundleUrl=('https://github.com/KevinFehrenbach1/azpc-client/releases/download/'+$ReleaseTag+'/azpc-components.zip')
    bundleSha256=(Get-FileHash $bundle -Algorithm SHA256).Hash.ToLowerInvariant()
}
$manifest | ConvertTo-Json | Set-Content (Join-Path $output 'azpc-update.json') -Encoding UTF8
$portable=Join-Path $output 'AZPC-Launcher-Portable.zip'
if (Test-Path $portable) { Remove-Item $portable -Force }
Compress-Archive -Path (Join-Path $dist '*') -DestinationPath $portable
