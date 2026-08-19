# AZPC Setup v0.4.73 test build

This is a **test build**, not yet the public GitHub release. It is derived from the retained v0.4.71 installer builder and changes only watcher re-pair/setup verification behavior.

Use the included GitHub Actions workflow to compile on a Windows runner, or compile `installer/AZPC-Setup.iss` with Inno Setup 6 locally.

Do not publish as `latest` until the clean/re-pair test passes.


V0.4.73 DETACHED WATCHER FIX
- Scheduled/background watcher now launches through wscript.exe + AZPC-Watcher-Hidden.vbs.
- No persistent PowerShell/command window should remain visible.
- Re-pairing behavior from v0.4.72 is preserved.
