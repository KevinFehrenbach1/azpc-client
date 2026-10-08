#define AppVersion "0.2.17"
[Setup]
AppId={{8AB6090C-0362-450E-A233-2ED2AEC851C8}
AppName=AZPC Launcher
AppVersion={#AppVersion}
AppPublisher=Kevin Fehrenbach
AppPublisherURL=https://azpc.market
DefaultDirName={localappdata}\Programs\AZPC Launcher
DefaultGroupName=AZPC Launcher
PrivilegesRequired=lowest
OutputDir=output
OutputBaseFilename=AZPC-Launcher-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName=AZPC Launcher
ArchitecturesAllowed=x64compatible
[Files]
Source: "dist\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\AZPC Launcher"; Filename: "{app}\AZPC-Launcher.exe"
Name: "{userdesktop}\AZPC Launcher"; Filename: "{app}\AZPC-Launcher.exe"
[Run]
Filename: "{app}\AZPC-Launcher.exe"; Description: "Open AZPC Launcher"; Flags: nowait postinstall skipifsilent
; Uninstall removes only this launcher. Account state, watcher, addon, and trading caches remain intact.



