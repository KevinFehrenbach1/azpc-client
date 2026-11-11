# AZPC Electron launcher v1.0.31

This is the build location for the modern Electron launcher, not the legacy PowerShell launcher.

Before triggering the release workflow, commit the **complete recovered source** from the v1.0.30 app.asar here: main.js, renderer.js, preload.js, game-detection.js, index.html, and assets/azpc-account-logo.png. Preserve the approved UI and account behavior. Do not substitute the old PowerShell launcher.

Update the recovered source to use _forever_ and Forever Live; preserve _anniversary_ and _retail_. The existing launcher looks for GitHub release tags launcher-vX.Y.Z and installer assets named AZPC-Launcher*.exe.

Run the Windows build on a branch, test the installer and update over v1.0.30, then merge and tag launcher-v1.0.31 to publish. The previous installer identity must be checked before release to avoid a side-by-side install.
