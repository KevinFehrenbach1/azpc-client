param([ValidateSet('Overview','Updates','Settings')][string]$PreviewPage='Overview')
# Windows PowerShell 5.1; installs run in a separate worker process.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'Launcher.Core.ps1')
$script:remote=$null; $script:job=$null; $script:resultPath=''; $script:requestPath=''
$script:launcherVersion='0.2.0'
$script:uiRoot=Join-Path $script:ClientRoot 'Launcher'
$jobs=Join-Path $script:uiRoot 'jobs'
New-Item -ItemType Directory -Path $jobs -Force | Out-Null
$acl=New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true,$false)
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
Set-Acl -LiteralPath $jobs -AclObject $acl
$bg=[Drawing.ColorTranslator]::FromHtml('#202226')
$card=[Drawing.ColorTranslator]::FromHtml('#282b30')
$muted=[Drawing.ColorTranslator]::FromHtml('#a6aebb')
$blue=[Drawing.ColorTranslator]::FromHtml('#4379fa')
$green=[Drawing.ColorTranslator]::FromHtml('#7bd88a')
$form=New-Object Windows.Forms.Form
$form.Text='AZPC Launcher'; $form.ClientSize=New-Object Drawing.Size(1080,730)
$form.MinimumSize=New-Object Drawing.Size(1096,769); $form.MaximumSize=$form.MinimumSize
$form.StartPosition='CenterScreen'; $form.BackColor=$bg; $form.ForeColor=[Drawing.Color]::WhiteSmoke
$form.Font=New-Object Drawing.Font('Segoe UI',10)
function Panel($Parent,[int]$X,[int]$Y,[int]$W,[int]$H,$Color) {
    $c=New-Object Windows.Forms.Panel; $c.SetBounds($X,$Y,$W,$H); $c.BackColor=$Color; $Parent.Controls.Add($c); return $c
}
function Label($Parent,[string]$Text,[int]$X,[int]$Y,[int]$W,[int]$H=28,[int]$Size=10,[bool]$Bold=$false) {
    $c=New-Object Windows.Forms.Label; $c.Text=$Text; $c.SetBounds($X,$Y,$W,$H)
    $style=if($Bold){[Drawing.FontStyle]::Bold}else{[Drawing.FontStyle]::Regular}
    $c.Font=New-Object Drawing.Font('Segoe UI',$Size,$style); $Parent.Controls.Add($c); return $c
}
function Button($Parent,[string]$Text,[int]$X,[int]$Y,[int]$W,[scriptblock]$Click,[bool]$Primary=$false) {
    $c=New-Object Windows.Forms.Button; $c.Text=$Text; $c.SetBounds($X,$Y,$W,42)
    $c.FlatStyle='Flat'; $c.FlatAppearance.BorderSize=0
    $c.BackColor=if($Primary){$blue}else{[Drawing.ColorTranslator]::FromHtml('#343940')}
    $c.ForeColor=[Drawing.Color]::WhiteSmoke; $c.Cursor=[Windows.Forms.Cursors]::Hand
    $c.Add_Click($Click); $Parent.Controls.Add($c); return $c
}
function TextBox($Parent,[int]$X,[int]$Y,[int]$W) {
    $c=New-Object Windows.Forms.TextBox; $c.SetBounds($X,$Y,$W,30)
    $c.BackColor=[Drawing.ColorTranslator]::FromHtml('#343940'); $c.ForeColor=[Drawing.Color]::WhiteSmoke
    $c.BorderStyle='FixedSingle'; $Parent.Controls.Add($c); return $c
}
function Icon($Parent,[int]$Code,[int]$X,[int]$Y,[int]$Size=25) {
    $c=Label $Parent ([char]$Code) $X $Y 48 50 $Size
    $c.Font=New-Object Drawing.Font('Segoe MDL2 Assets',$Size); $c.ForeColor=$muted; return $c
}
$sidebar=Panel $form 0 0 215 730 ([Drawing.ColorTranslator]::FromHtml('#1c1e22'))
$null=Panel $form 214 0 1 730 ([Drawing.ColorTranslator]::FromHtml('#353940'))
# Neutral AZPC diamond/chart mark drawn as vector paths so it stays sharp at Windows DPI scales.
$brand=Panel $sidebar 17 27 183 70 $sidebar.BackColor
$brand.Add_Paint({param($sender,$e)
    $g=$e.Graphics; $g.SmoothingMode='AntiAlias'
    $pen=New-Object Drawing.Pen([Drawing.Color]::Silver,2)
    $pts=[Drawing.Point[]]@((New-Object Drawing.Point(29,4)),(New-Object Drawing.Point(55,31)),(New-Object Drawing.Point(29,58)),(New-Object Drawing.Point(3,31)))
    $g.DrawPolygon($pen,$pts)
    $g.DrawLines($pen,[Drawing.Point[]]@((New-Object Drawing.Point(11,36)),(New-Object Drawing.Point(20,29)),(New-Object Drawing.Point(27,33)),(New-Object Drawing.Point(39,17)),(New-Object Drawing.Point(47,21))))
    $g.DrawLine($pen,19,40,19,45); $g.DrawLine($pen,27,37,27,49); $g.DrawLine($pen,35,30,35,43)
    $font=New-Object Drawing.Font('Segoe UI',26,[Drawing.FontStyle]::Bold)
    $g.DrawString('AZPC',$font,[Drawing.Brushes]::WhiteSmoke,57,7)
    $small=New-Object Drawing.Font('Segoe UI',6)
    $g.DrawString('AZEROTHIAN PRICE CHECKER',$small,[Drawing.Brushes]::Silver,60,48)
    $pen.Dispose(); $font.Dispose(); $small.Dispose()
})
$navOverview=Button $sidebar 'Overview' 12 115 191 { Show-Page 'Overview' }
$navUpdates=Button $sidebar 'Updates' 12 168 191 { Show-Page 'Updates' }
$navSettings=Button $sidebar 'Settings' 12 221 191 { Show-Page 'Settings' }
$null=Button $sidebar 'Open dashboard' 12 654 191 { Start-Process 'https://azpc.market' }
$null=Label $sidebar 'Launcher 0.2.0' 25 704 175 20 8
$title=Label $form 'Overview' 250 27 560 60 28 $true
$game=New-Object Windows.Forms.ComboBox; $game.SetBounds(859,40,184,30); $game.DropDownStyle='DropDownList'
$game.BackColor=$card; $game.ForeColor=$form.ForeColor
$null=$game.Items.Add('Anniversary / TBC'); $game.SelectedIndex=0; $form.Controls.Add($game)
$overview=Panel $form 250 111 793 461 $bg
$updates=Panel $form 250 111 793 461 $bg
$settingsPage=Panel $form 250 111 793 461 $bg
$accountCard=Panel $overview 0 0 793 96 $card
$null=Icon $accountCard 0xE77B 22 28 28
$connection=Label $accountCard 'Connect your account' 84 17 470 32 16 $true
$accountDetail=Label $accountCard 'Link the watcher to upload your saved game activity.' 84 52 480 28 11
$accountDetail.ForeColor=$muted
$account=Button $accountCard 'Connect account' 601 27 168 { Show-Page 'Settings'; Start-Process 'https://azpc.market/account'; $codeBox.Focus() }
$components=Panel $overview 0 117 793 256 $card
$null=Icon $components 0xEA86 24 27
$null=Label $components 'Addon' 86 20 350 32 17 $true
$addonDetail=Label $components 'Ready in World of Warcraft.' 86 57 490 28 11; $addonDetail.ForeColor=$muted
$addonBadge=Label $components 'Not installed' 590 38 175 30 11
$null=Panel $components 0 105 793 1 ([Drawing.ColorTranslator]::FromHtml('#393d44'))
$null=Icon $components 0xE9D9 24 128
$null=Label $components 'Watcher' 86 122 350 32 17 $true
$watcherDetail=Label $components 'Collects your saved game activity.' 86 159 485 28 11; $watcherDetail.ForeColor=$muted
$watcherStatus=Label $components 'Stopped' 590 141 175 30 11
$activity=Label $components '' 86 197 665 44 9; $activity.ForeColor=$muted
$folderCard=Panel $overview 0 394 793 67 $card
$null=Icon $folderCard 0xE8B7 24 18 21
$folderLabel=Label $folderCard 'Choose your game folder' 80 10 480 26 12
$folderDetail=Label $folderCard 'Select the main World of Warcraft folder.' 80 36 500 23 9; $folderDetail.ForeColor=$muted
$null=Button $folderCard 'Change folder' 601 13 168 { Show-Page 'Settings'; $browse.PerformClick() }
$null=Label $updates 'Manage your components' 0 0 790 38 20 $true
$null=Label $updates 'Install or update each component. Your trading history stays in place.' 0 43 790 28 11
$updateCard=Panel $updates 0 90 793 256 $card
$null=Label $updateCard 'COMPONENT' 23 18 180 24 9
$null=Label $updateCard 'INSTALLED' 236 18 150 24 9
$null=Label $updateCard 'AVAILABLE' 418 18 160 24 9
$null=Label $updateCard 'AZPC addon' 23 66 180 30 13 $true
$addonInstalled=Label $updateCard '-' 236 68 150
$addonAvailable=Label $updateCard '-' 418 68 180
$addonButton=Button $updateCard 'Install / Update' 612 59 158 { Begin-Action 'addon' }
$null=Label $updateCard 'AZPC watcher' 23 138 180 30 13 $true
$watcherInstalled=Label $updateCard '-' 236 140 150
$watcherAvailable=Label $updateCard '-' 418 140 180
$watcherButton=Button $updateCard 'Install / Update' 612 131 158 { Begin-Action 'watcher' }
$allButton=Button $updateCard 'Install / Update All' 23 200 240 { Begin-Action 'all' } $true
$startButton=Button $updateCard 'Start watcher' 418 200 165 { Begin-Action 'start' }
$stopButton=Button $updateCard 'Stop watcher' 605 200 165 { Begin-Action 'stop' }
$versionNote=Label $updates 'Available versions are bundled until you check online.' 0 368 785 55 11; $versionNote.ForeColor=$muted
$null=Label $settingsPage 'Game folder' 0 0 790 35 18 $true
$null=Label $settingsPage 'Select the main World of Warcraft folder containing _anniversary_.' 0 39 790 28 11
$rootBox=TextBox $settingsPage 0 77 599
$browse=Button $settingsPage 'Browse' 621 72 172 {
    $picker=New-Object Windows.Forms.FolderBrowserDialog
    $picker.Description='Select the main World of Warcraft folder containing _anniversary_.'
    if($picker.ShowDialog() -eq 'OK'){ $rootBox.Text=$picker.SelectedPath; Save-Settings; Refresh-Status }
    $picker.Dispose()
}
$null=Label $settingsPage 'Account connection' 0 145 790 35 18 $true
$null=Label $settingsPage 'Get a setup code from your AZPC Account page. Enter it below.' 0 185 790 28 11
$codeBox=TextBox $settingsPage 0 226 210; $codeBox.MaxLength=8; $codeBox.CharacterCasing='Upper'; $codeBox.UseSystemPasswordChar=$true
$null=Button $settingsPage 'Get setup code' 233 219 178 { Start-Process 'https://azpc.market/account' }
$null=Button $settingsPage 'Connect / Install watcher' 431 219 260 { Begin-Action 'watcher' } $true
$null=Label $settingsPage 'Existing account connections are reused automatically.' 0 277 790 28 10
$null=Label $settingsPage 'Troubleshooting' 0 337 790 35 18 $true
$logsButton=Button $settingsPage 'Open watcher log' 0 386 200 {
    try { $profile=Get-Profile; $path=Join-Path $profile.State 'watcher.log'
        if(Test-Path -LiteralPath $path){ Start-Process notepad.exe -ArgumentList ('"'+$path+'"') }
        else { $message.Text='No watcher log exists yet.' }
    } catch { $message.Text=$_.Exception.Message }
}
$null=Button $settingsPage 'Open Account page' 220 386 200 { Start-Process 'https://azpc.market/account' }
$null=Panel $form 215 599 865 1 ([Drawing.ColorTranslator]::FromHtml('#393d44'))
$checkButton=Button $form 'Check for updates' 250 622 226 { Begin-Action 'check' } $true
$quickInstall=Button $form 'Install components' 498 622 216 { Show-Page 'Updates'; Begin-Action 'all' }
$null=Button $form 'Manage components' 827 622 216 { Show-Page 'Updates' }
$message=Label $form 'Ready. Install components to get started.' 250 682 793 42 10; $message.ForeColor=$muted
function Show-Page([string]$Page) {
    $overview.Visible=($Page -eq 'Overview'); $updates.Visible=($Page -eq 'Updates'); $settingsPage.Visible=($Page -eq 'Settings')
    $title.Text=$Page
    foreach($nav in @($navOverview,$navUpdates,$navSettings)) {
        $nav.BackColor=if($nav.Text -eq $Page){[Drawing.ColorTranslator]::FromHtml('#293a60')}else{$sidebar.BackColor}
    }
}
$script:mutating=@($browse,$game,$rootBox,$codeBox,$addonButton,$watcherButton,$startButton,$stopButton,$checkButton,$allButton,$quickInstall)
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
        $connection.Text=if($state.Connected){'Account connected'}else{'Connect your account'}
        $accountDetail.Text=if($state.Connected){'Your saved account connection is ready.'}else{'Link the watcher to upload your saved game activity.'}
        $account.Text=if($state.Connected){'Manage account'}else{'Connect account'}
        $watcherStatus.Text=if($state.Running){'Running'}else{'Stopped'}
        $watcherStatus.ForeColor=if($state.Running){$green}else{$muted}
        $activity.Text=$state.Activity
        $bundled=Read-JsonFile (Join-Path $script:AppRoot 'installer\payload\VERSION.json')
        $available=if($script:remote){$script:remote}else{$bundled}
        $suffix=if($script:remote){' (online)'}else{' (bundled)'}
        $addonAvailable.Text=[string]$available.addonVersion+$suffix
        $watcherAvailable.Text=[string]$available.watcherVersion+$suffix
        $addonDetail.Text='Installed: '+$state.Addon+'  |  Available: '+$available.addonVersion
        $watcherDetail.Text='Installed: '+$state.Watcher+'  |  Available: '+$available.watcherVersion
        $addonBadge.Text=if($state.Addon -eq 'Not installed'){'Not installed'}elseif(-not $script:remote){'Installed'}elseif([version]$state.Addon -lt [version]$available.addonVersion){'Update available'}else{'Up to date'}
        $addonBadge.ForeColor=if($addonBadge.Text -in @('Installed','Up to date')){$green}else{$muted}
        $addonButton.Text=if($state.Addon -eq 'Not installed'){'Install addon'}elseif($script:remote -and $addonBadge.Text -eq 'Update available'){'Update addon'}else{'Reinstall addon'}
        $watcherButton.Text=if($state.Watcher -eq 'Not installed'){'Install watcher'}elseif($script:remote -and $state.Watcher -match '^\d+\.' -and [version]$state.Watcher -lt [version]$available.watcherVersion){'Update watcher'}else{'Reinstall watcher'}
        $found=$false
        try { $null=Assert-WowRoot $rootBox.Text; $found=$true } catch {}
        $folderLabel.Text=if($found){'Game folder detected'}else{'Choose your game folder'}
        $folderDetail.Text=if($found){$rootBox.Text}else{'Select the main World of Warcraft folder in Settings.'}
        $folderDetail.AutoEllipsis=$true
        $startButton.Enabled=(-not $script:job -and -not $state.Running -and $state.Watcher -ne 'Not installed')
        $stopButton.Enabled=(-not $script:job -and $state.Running)
        $quickInstall.Visible=($state.Addon -eq 'Not installed' -or $state.Watcher -eq 'Not installed')
        $versionNote.Text=if($script:remote){'Checked online. Install buttons use these released versions.'}else{'Available versions are bundled until you check online.'}
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
                $message.Text='Update check complete. Open Manage components to see available versions.'
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
Show-Page $PreviewPage
$timer.Start(); $statusTimer.Start(); Refresh-Status
try { [Windows.Forms.Application]::Run($form) } finally { $timer.Dispose(); $statusTimer.Dispose(); $form.Dispose() }
