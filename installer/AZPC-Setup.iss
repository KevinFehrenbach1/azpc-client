#define MyAppName "Azerothian Price Checker"
#define MyAppVersion "0.4.74"
#define MyAppPublisher "Kevin Fehrenbach"
#define MyAppURL "https://azpc.market"
#define MyAppExeName "AZPC-Setup.exe"

[Setup]
AppId={{0D3D6632-50B8-41C2-A2DD-35D59F66903A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\AZPC
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=output
OutputBaseFilename=AZPC-Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#MyAppName}
VersionInfoVersion=0.4.74.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=AZPC TBC Anniversary Setup Wizard
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
ArchitecturesAllowed=x64compatible

[Files]
Source: "payload\INSTALL-AZPC.ps1"; DestDir: "{app}\payload"; Flags: ignoreversion
Source: "payload\VERSION.json"; DestDir: "{app}\payload"; Flags: ignoreversion
Source: "payload\addon\AZPC\AZPC.lua"; DestDir: "{app}\payload\addon\AZPC"; Flags: ignoreversion
Source: "payload\addon\AZPC\AZPC.toc"; DestDir: "{app}\payload\addon\AZPC"; Flags: ignoreversion
Source: "payload\watcher\AZPC-Watcher.ps1"; DestDir: "{app}\payload\watcher"; Flags: ignoreversion

[Icons]
Name: "{group}\AZPC Website"; Filename: "https://azpc.market"
Name: "{group}\Uninstall AZPC"; Filename: "{uninstallexe}"

[Registry]
Root: HKLM; Subkey: "Software\AZPC"; ValueType: string; ValueName: "WowRoot"; ValueData: "{code:GetWowRoot}"; Flags: uninsdeletekey

[UninstallRun]
Filename: "{sys}\schtasks.exe"; Parameters: "/End /TN ""AZPC Watcher"""; Flags: runhidden waituntilterminated skipifdoesntexist; RunOnceId: "StopAZPCWatcher"
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /F /TN ""AZPC Watcher"""; Flags: runhidden waituntilterminated skipifdoesntexist; RunOnceId: "DeleteAZPCWatcherTask"

[Code]
var
  WowPage: TInputDirWizardPage;
  CodePage: TInputQueryWizardPage;

function DefaultWowRoot: String;
begin
  if DirExists('C:\Program Files (x86)\World of Warcraft\_anniversary_') then
    Result := 'C:\Program Files (x86)\World of Warcraft'
  else if DirExists('C:\Program Files\World of Warcraft\_anniversary_') then
    Result := 'C:\Program Files\World of Warcraft'
  else if DirExists('D:\Games\World of Warcraft\_anniversary_') then
    Result := 'D:\Games\World of Warcraft'
  else if DirExists('D:\World of Warcraft\_anniversary_') then
    Result := 'D:\World of Warcraft'
  else
    Result := '';
end;

procedure InitializeWizard;
begin
  WowPage := CreateInputDirPage(wpSelectDir,
    'Locate World of Warcraft',
    'Choose the main World of Warcraft folder.',
    'AZPC will install only its addon inside _anniversary_\Interface\AddOns.',
    False,
    '');
  WowPage.Add('World of Warcraft folder:');
  WowPage.Values[0] := DefaultWowRoot;

  CodePage := CreateInputQueryPage(WowPage.ID,
    'Connect this PC to AZPC',
    'Enter your one-time setup code.',
    'Sign in at azpc.market/account, generate an 8-character setup code, and enter it below.');
  CodePage.Add('Setup code:', False);
end;

function NormalizeCode(Value: String): String;
begin
  Result := Uppercase(Trim(Value));
  StringChangeEx(Result, '-', '', True);
  StringChangeEx(Result, ' ', '', True);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  WowRoot: String;
  SetupCode: String;
begin
  Result := True;
  if CurPageID = WowPage.ID then
  begin
    WowRoot := RemoveBackslashUnlessRoot(Trim(WowPage.Values[0]));
    if not DirExists(WowRoot + '\_anniversary_') then
    begin
      MsgBox('That folder does not contain _anniversary_. Choose the main World of Warcraft folder.', mbError, MB_OK);
      Result := False;
    end;
  end
  else if CurPageID = CodePage.ID then
  begin
    SetupCode := NormalizeCode(CodePage.Values[0]);
    CodePage.Values[0] := SetupCode;
    if Length(SetupCode) <> 8 then
    begin
      MsgBox('The AZPC setup code must be exactly 8 characters.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function GetWowRoot(Param: String): String;
begin
  Result := RemoveBackslashUnlessRoot(Trim(WowPage.Values[0]));
end;

function GetSetupCode(Param: String): String;
begin
  Result := NormalizeCode(CodePage.Values[0]);
end;

procedure StopWatcherProcesses;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like ''*AZPC-Watcher.ps1*'' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure RemoveAddonFrom(const WowRoot: String);
var
  AddonPath: String;
begin
  if WowRoot = '' then
    Exit;
  AddonPath := AddBackslash(RemoveBackslashUnlessRoot(WowRoot)) +
    '_anniversary_\Interface\AddOns\AZPC';
  if DirExists(AddonPath) then
    DelTree(AddonPath, True, True, True);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  PowerShellPath: String;
  InstallParams: String;
begin
  if CurStep = ssPostInstall then
  begin
    PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
    InstallParams := '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' +
      ExpandConstant('{app}\payload\INSTALL-AZPC.ps1') + '" -WowRoot "' +
      GetWowRoot('') + '" -SetupCode "' + GetSetupCode('') + '"';

    if (not Exec(PowerShellPath, InstallParams, ExpandConstant('{app}\payload'),
      SW_HIDE, ewWaitUntilTerminated, ResultCode)) or (ResultCode <> 0) then
      RaiseException('AZPC client installation failed. Setup did not make any success claim.');

    if not FileExists(ExpandConstant('{localappdata}\AZPC\install-result.json')) then
      RaiseException('AZPC installation could not be verified. The success marker is missing.');

    if not FileExists(GetWowRoot('') + '\_anniversary_\Interface\AddOns\AZPC\AZPC.lua') then
      RaiseException('AZPC addon installation could not be verified.');

    if not Exec(ExpandConstant('{sys}\schtasks.exe'), '/Query /TN "AZPC Watcher"', '',
      SW_HIDE, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
      RaiseException('AZPC watcher startup task could not be verified.');
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  WowRoot: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    StopWatcherProcesses;
    if RegQueryStringValue(HKLM,
      'Software\AZPC', 'WowRoot', WowRoot) then
      RemoveAddonFrom(WowRoot);

    { Safe fallbacks for standard WoW locations if registry state was damaged. }
    RemoveAddonFrom('C:\Program Files (x86)\World of Warcraft');
    RemoveAddonFrom('C:\Program Files\World of Warcraft');
    RemoveAddonFrom('D:\Games\World of Warcraft');
    RemoveAddonFrom('D:\World of Warcraft');
    RemoveAddonFrom('E:\Games\World of Warcraft');
    RemoveAddonFrom('E:\World of Warcraft');
    RemoveAddonFrom('F:\Games\World of Warcraft');
    RemoveAddonFrom('F:\World of Warcraft');

    DelTree(ExpandConstant('{localappdata}\AZPC'), True, True, True);
    DeleteFile(ExpandConstant('{userdesktop}\AZPC Watcher.lnk'));
    DeleteFile(ExpandConstant('{userstartup}\AZPC Watcher.lnk'));
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = CodePage.ID then
    WizardForm.NextButton.Caption := 'Install'
  else if CurPageID = wpFinished then
    WizardForm.NextButton.Caption := 'Finish';
end;
