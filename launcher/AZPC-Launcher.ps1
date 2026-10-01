# Windows PowerShell 5.1, STA. The helper process keeps network and install work off the UI thread.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'Launcher.Core.ps1')
$script:remote = $null; $script:job = $null; $script:resultPath = ''; $script:requestPath = ''
$script:launcherVersion = '0.1.0'
$script:uiRoot = Join-Path $script:ClientRoot 'Launcher'
New-Item -ItemType Directory -Path $script:uiRoot -Force | Out-Null
# Setup codes live only in a private, short-lived request file, never in settings or logs.
$jobs = Join-Path $script:uiRoot 'jobs'
New-Item -ItemType Directory -Path $jobs -Force | Out-Null
$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
$rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$acl.AddAccessRule($rule)
Set-Acl -LiteralPath $jobs -AclObject $acl
$form = New-Object Windows.Forms.Form
$form.Text = 'AZPC Launcher'; $form.ClientSize = New-Object Drawing.Size(850,690)
$form.MinimumSize = New-Object Drawing.Size(866,729); $form.MaximumSize = $form.MinimumSize
$form.StartPosition = 'CenterScreen'; $form.BackColor = [Drawing.Color]::FromArgb(15,27,34)
$form.ForeColor = [Drawing.Color]::FromArgb(230,237,237); $form.Font = New-Object Drawing.Font('Segoe UI',10)
function Label([string]$Text,[int]$X,[int]$Y,[int]$Width,[int]$Height=28,[int]$Size=10) {
    $c = New-Object Windows.Forms.Label; $c.Text=$Text; $c.SetBounds($X,$Y,$Width,$Height)
    $c.Font = New-Object Drawing.Font('Segoe UI',$Size); $form.Controls.Add($c); return $c
}
function Button([string]$Text,[int]$X,[int]$Y,[int]$Width,[scriptblock]$Click) {
    $c=New-Object Windows.Forms.Button; $c.Text=$Text; $c.SetBounds($X,$Y,$Width,38)
    $c.FlatStyle='Flat'; $c.BackColor=[Drawing.Color]::FromArgb(34,60,69)
    $c.FlatAppearance.BorderColor=[Drawing.Color]::FromArgb(181,151,89)
    $c.Add_Click($Click); $form.Controls.Add($c); return $c
}
function TextBox([int]$X,[int]$Y,[int]$Width) {
    $c=New-Object Windows.Forms.TextBox; $c.SetBounds($X,$Y,$Width,30)
    $c.BackColor=[Drawing.Color]::FromArgb(27,42,50); $c.ForeColor=$form.ForeColor
    $form.Controls.Add($c); return $c
}
$null=Label 'AZEROTHIAN PRICE CHECKER' 28 20 760 45 23
$subtitle=Label 'Your addon, watcher, and updates. All in one place.' 30 68 780
$subtitle.ForeColor=[Drawing.Color]::FromArgb(181,151,89)
$null=Label 'Game version' 30 112 180
$game=New-Object Windows.Forms.ComboBox; $game.SetBounds(210,108,300,30); $game.DropDownStyle='DropDownList'
$null=$game.Items.Add('Anniversary / TBC'); $null=$game.Items.Add('Forever - coming later'); $game.SelectedIndex=0
$form.Controls.Add($game)
$null=Label 'World of Warcraft folder' 30 152 450
$rootBox=TextBox 30 182 650
$browse=Button 'Browse' 700 177 120 {
    $picker=New-Object Windows.Forms.FolderBrowserDialog
    $picker.Description='Select the main World of Warcraft folder containing _anniversary_.'
    if ($picker.ShowDialog() -eq 'OK') { $rootBox.Text=$picker.SelectedPath; Save-Settings; Refresh-Status }
    $picker.Dispose()
}
$null=Label 'Setup code (only needed for first watcher connection)' 30 224 630
$codeBox=TextBox 30 254 180; $codeBox.MaxLength=8; $codeBox.CharacterCasing='Upper'; $codeBox.UseSystemPasswordChar=$true
$account=Button 'Get setup code' 230 248 180 { Start-Process 'https://azpc.market/account' }
$connection=Label 'Checking account connection...' 430 256 390
$null=Label 'COMPONENT' 30 310 180
$null=Label 'INSTALLED' 260 310 140
$null=Label 'AVAILABLE' 450 310 160
$null=Label 'AZPC addon' 30 350 200
$addonInstalled=Label '-' 260 350 150
$addonAvailable=Label '-' 450 350 150
$addonButton=Button 'Install / Update' 640 342 180 { Begin-Action 'addon' }
$null=Label 'AZPC watcher' 30 406 200
$watcherInstalled=Label '-' 260 406 150
$watcherAvailable=Label '-' 450 406 150
$watcherButton=Button 'Install / Update' 640 398 180 { Begin-Action 'watcher' }
$watcherStatus=Label 'Watcher: checking...' 30 458 590
$startButton=Button 'Start' 640 451 85 { Begin-Action 'start' }
$stopButton=Button 'Stop' 735 451 85 { Begin-Action 'stop' }
$activity=Label '' 30 493 785 28 9
$checkButton=Button 'Check for updates' 30 529 200 { Begin-Action 'check' }
$allButton=Button 'Install / Update All' 250 529 225 { Begin-Action 'all' }
$logsButton=Button 'Open watcher log' 495 529 180 {
    try {
        $profile=Get-Profile; $path=Join-Path $profile.State 'watcher.log'
        if (Test-Path -LiteralPath $path) { Start-Process notepad.exe -ArgumentList ('"'+$path+'"') }
        else { $message.Text='No watcher log exists yet.' }
    } catch { $message.Text=$_.Exception.Message }
}
$siteButton=Button 'Open AZPC' 695 529 125 { Start-Process 'https://azpc.market' }
$message=Label 'Ready. Install bundled versions, or check for a newer public release.' 30 583 790 65 10
$footer=Label 'Launcher 0.1.0 test build | Forever support is not enabled yet.' 30 657 790 22 9
$footer.ForeColor=[Drawing.Color]::FromArgb(157,176,185)
$script:mutating=@($browse,$game,$rootBox,$codeBox,$addonButton,$watcherButton,$startButton,$stopButton,$checkButton,$allButton)
function Save-Settings {
    @{ wowRoot=$rootBox.Text } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:uiRoot 'settings.json') -Encoding UTF8
}
function Set-Busy([bool]$Busy) {
    foreach ($control in $script:mutating) { $control.Enabled=-not $Busy }
    $form.UseWaitCursor=$Busy
}
function Refresh-Status {
    try {
        $state=Get-InstalledStatus $rootBox.Text
        $addonInstalled.Text=$state.Addon; $watcherInstalled.Text=$state.Watcher
        $connection.Text=if ($state.Connected) { 'Account connected (saved credentials)' } else { 'Account not connected' }
        $watcherStatus.Text=if ($state.Running) { 'Watcher: running' } else { 'Watcher: stopped' }
        $activity.Text=$state.Activity
        $bundled=Read-JsonFile (Join-Path $script:AppRoot 'installer\payload\VERSION.json')
        $available=if ($script:remote) { $script:remote } else { $bundled }
        $suffix=if ($script:remote) { ' (online)' } else { ' (bundled)' }
        $addonAvailable.Text=[string]$available.addonVersion+$suffix
        $watcherAvailable.Text=[string]$available.watcherVersion+$suffix
    } catch { $message.Text=$_.Exception.Message }
}
function Begin-Action([string]$Action) {
    if ($script:job) { return }
    if ($game.SelectedIndex -ne 0) { $message.Text='Forever requires its own addon and watcher configuration. Choose Anniversary for this build.'; return }
    try {
        Save-Settings
        $request=@{ action=$Action; wowRoot=$rootBox.Text; setupCode=$codeBox.Text; manifest=$script:remote }
        $script:requestPath=Join-Path $jobs ([guid]::NewGuid().ToString('N')+'.json')
        $script:resultPath=$script:requestPath+'.result.json'
        $request | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:requestPath -Encoding UTF8
        $codeBox.Clear()
        $psi=New-Object Diagnostics.ProcessStartInfo
        $psi.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $psi.Arguments='-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'Launcher.Worker.ps1')+'" -RequestPath "'+$script:requestPath+'"'
        $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
        $script:job=[Diagnostics.Process]::Start($psi)
        Set-Busy $true
        $message.Text=if ($Action -eq 'check') { 'Checking the latest public AZPC release...' } else { 'Working... Keep the launcher open until this finishes.' }
    } catch {
        if ($script:requestPath -and (Test-Path -LiteralPath $script:requestPath)) { Remove-Item -LiteralPath $script:requestPath -Force }
        $message.Text=$_.Exception.Message; Set-Busy $false
    }
}
try {
    $settings=Read-JsonFile (Join-Path $script:uiRoot 'settings.json')
    if ($settings) { $rootBox.Text=$settings.wowRoot }
    if (-not $rootBox.Text) {
        $old=Read-JsonFile (Join-Path $script:ClientRoot 'install-result.json')
        if ($old) { $rootBox.Text=$old.wowRoot }
        else { $found=Find-WowRoot ''; if ($found) { $rootBox.Text=$found } }
    }
} catch { $message.Text='Choose your WoW folder to get started.' }
$timer=New-Object Windows.Forms.Timer; $timer.Interval=1000
$timer.Add_Tick({
    if ($script:job -and $script:job.HasExited) {
        try {
            $result=Read-JsonFile $script:resultPath
            if (-not $result) { throw 'The operation stopped unexpectedly. No success was reported. Open the watcher log for details.' }
            if ($result.ok -and $result.PSObject.Properties['manifest']) {
                $script:remote=$result.manifest
                $message.Text='Update check complete. Available versions are shown above.'
                if ([version]$script:remote.launcherVersion -gt [version]$script:launcherVersion) {
                    $message.Text+=' A newer launcher is also available on the GitHub Releases page.'
                }
            } else { $message.Text=[string]$result.message }
        } catch { $message.Text=$_.Exception.Message }
        finally {
            foreach ($path in @($script:requestPath,$script:resultPath)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
            $script:job.Dispose(); $script:job=$null; Set-Busy $false; Refresh-Status
        }
    }
})
$statusTimer=New-Object Windows.Forms.Timer; $statusTimer.Interval=10000
$statusTimer.Add_Tick({ if (-not $script:job) { Refresh-Status } })
$form.Add_FormClosing({ param($sender,$eventArgs)
    if ($script:job -and -not $script:job.HasExited) { $eventArgs.Cancel=$true; $message.Text='An operation is still running. Wait for it to finish before closing.' }
})
$timer.Start(); $statusTimer.Start(); Refresh-Status
try { [Windows.Forms.Application]::Run($form) } finally { $timer.Dispose(); $statusTimer.Dispose(); $form.Dispose() }
