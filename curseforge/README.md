# AZPC Forever — CurseForge beta release kit

**Current candidate:** 0.2.90. This directory is for the *standalone WoW addon*, not the Windows launcher or watcher.

## Release procedure

1. Run the GitHub Actions workflow **Package AZPC Forever for CurseForge** on the release commit. Wait for its Lua tests and ZIP validation to pass.
2. Download the workflow artifact and extract the nested `AZPCForever-CurseForge-vX.Y.Z.zip` file. Upload that ZIP to the CurseForge addon project as a **beta** file, selecting the exact WoW client/game version offered by CurseForge for the target Forever client. Do not select Retail, TBC, or another game flavor as a substitute.
3. Publish the project description from `LISTING.md` and the setup instructions from `INSTALL.md`. Add screenshots of the actual crafting panel, Sync Status, Getting Started and Report Bug screens.
4. Install the ZIP on a clean test client with **no launcher/watcher**, log in, verify minimap menu, Getting Started and basic standalone features. Then install the watcher/launcher and verify dashboard synchronization. Test existing-user upgrades separately to ensure SavedVariables are retained.
5. Publish externally only after a human verifies the target CurseForge game category supports this client and the fresh-install smoke test passes.

The ZIP must contain exactly one top-level `AZPCForever/` folder with the `.toc` and Lua files declared by that `.toc`. No PowerShell, EXEs, account credentials, watcher code, saved data or installer files.

**Publishing boundary:** This GitHub workflow builds a downloadable artifact; it does **not** automatically submit or publish to CurseForge. A CurseForge project and upload authorization are required for that step.

**Beta caveats:** Auction-house data depends on observed in-game scans. Website sync requires the optional Windows watcher, an AZPC account and a supported receiver. The addon cannot itself transmit data to the desktop watcher or website.
