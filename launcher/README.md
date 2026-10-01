# AZPC Launcher 0.1.0

Windows 10/11 launcher for the existing Anniversary addon and watcher. Installs per Windows user and uses Windows PowerShell 5.1, Windows Forms, and the .NET Framework already included with Windows. No separate runtime download is needed.

## User flow

Install `AZPC-Launcher-Setup.exe`, open AZPC Launcher, select the main WoW folder containing `_anniversary_`, then click **Install / Update All**. New watcher installations need an eight-character setup code from https://azpc.market/account. Existing connections are reused automatically; entering a code does not change an existing account. Close WoW before changing component files.

The addon and watcher can be installed independently. The watcher is configured to start at Windows sign-in. Start/Stop and Open watcher log are available in the launcher. A running watcher is distinct from a connected account or a successful upload; the heartbeat is shown as the watcher's own reported status. The portable ZIP must be extracted before launching `AZPC-Launcher.exe`.

Forever appears as unavailable because this repository's addon and watcher target Anniversary. There is no simulated Forever data collection.

## Updates

The initial launcher bundles addon 0.4.29 and watcher 0.4.25. **Check for updates** reads `azpc-update.json` from the latest non-prerelease release in this repository. Existing releases without this asset produce an explanatory message and leave bundled installation available. Downloaded updates must match SHA-256, repository origin, game, schema, and component versions. ZIP extraction accepts only the four expected files. Updates never downgrade a detected newer component.

Build `launcher/Build.ps1 -ReleaseTag <tag>` on Windows. It emits the launcher EXE, portable ZIP, `azpc-components.zip`, and manifest. Compile `launcher/AZPC-Launcher-Setup.iss` with Inno Setup 6 for the per-user setup EXE. Attach the bundle and manifest together to a reviewed release with the matching tag to enable online updates. Test artifacts are not automatically published or made latest. Build a fresh bundle and manifest whenever either component changes.

A newer launcher version is reported after checking updates; launcher replacement uses its installer rather than overwriting a running application.

## State preservation and recovery

Watcher account files and upload caches under `%LOCALAPPDATA%\AZPC` are never deleted by the launcher. WoW `WTF` SavedVariables are untouched. Existing profiles are discovered from identity markers; ambiguous multiple profiles require resolution instead of selecting a random account. Addon replacement stages files and retains the previous directory under WoW `_anniversary_\Interface\AZPC-Backups` on the same volume. Watcher code is backed up before replacement and restored on activation/startup failure. A failed second component reports partial success accurately. Backups are retained for manual recovery; this release does not include a restore button.

Setup codes use private short-lived job files and are not stored in launcher settings or logs. Download/install operations run in a helper process so the window remains responsive, and a mutex prevents simultaneous launcher operations. The launcher cannot be closed during an active operation. Uninstalling this launcher removes only its program files, preserving the addon, watcher, and trading history.

## Validation

`launcher/tests/Run.Tests.ps1` parses all shipped scripts and checks custom WoW paths, addon backup/rollback, watcher code rollback, account/cache/identity preservation, malformed manifests, valid release extraction, checksum failures, and unsafe ZIP extraction using temporary directories and mocked process/network/startup operations. CI builds the EXE, smoke-tests the window, captures a screenshot, and compiles the setup installer on Windows.

Before public release, use a real Windows/WoW installation to test clean install, existing-user upgrade, account activation, custom paths, watcher startup at sign-in, logout/reload data uploads, and an actual published update. CI cannot validate a real AZPC account or WoW session. EXEs are unsigned test builds until code signing is configured.
