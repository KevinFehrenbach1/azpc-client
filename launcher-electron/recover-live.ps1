$ErrorActionPreference = 'Stop'
$root = (Get-Location).Path
$temp = Join-Path $env:RUNNER_TEMP 'azpc-recovery'
New-Item -ItemType Directory -Force $temp | Out-Null
gh release download launcher-v1.0.30 --repo KevinFehrenbach1/azpc-client --pattern 'AZPC-Launcher*.exe' --dir $temp
if ($LASTEXITCODE) { throw 'Cannot retrieve prior Electron installer' }
$installer = Get-ChildItem $temp -Filter *.exe | Select-Object -First 1
$seven = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
& $seven x $installer.FullName "-o$temp\outer" -y
if ($LASTEXITCODE) { throw 'Cannot extract NSIS installer' }
$archive = Get-ChildItem "$temp\outer" -Recurse -Filter app-64.7z | Select-Object -First 1
if ($archive) {
 & $seven x $archive.FullName "-o$temp\inner" -y
 if ($LASTEXITCODE) { throw 'Cannot extract Electron payload' }
}
$asar = Get-ChildItem $temp -Recurse -Filter app.asar | Select-Object -First 1
if (!$asar) { throw 'Missing original app.asar' }
npx --yes --package=@electron/asar@3.2.17 asar extract $asar.FullName "$temp\source"
if ($LASTEXITCODE) { throw 'ASAR extraction failed' }
foreach ($name in @('main.js','renderer.js','preload.js','game-detection.js','index.html','assets')) {
 Copy-Item "$temp\source\$name" $root -Recurse -Force
}
foreach ($name in @('main.js','renderer.js','preload.js','game-detection.js','index.html')) {
 $p = Join-Path $root $name
 $s = [IO.File]::ReadAllText($p).Replace('_beta_','_forever_').Replace('Forever Beta','Forever Live').Replace('WowB.exe','Wow.exe')
 [IO.File]::WriteAllText($p,$s)
}
