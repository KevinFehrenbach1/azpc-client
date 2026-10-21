# Install AZPC Forever

## CurseForge-only setup

Install **AZPC Forever** through CurseForge for the supported Forever game client. If installing manually, unzip the package so your WoW addon's folder contains `AZPCForever/AZPCForever.toc` (not `AZPCForever/AZPCForever/AZPCForever.toc`). Launch WoW and enable **AZPC Forever** on the AddOns screen.

Log in and open the **AZPC minimap icon**. Use **Getting Started** to review setup, **Crafting** for recipes and profit estimates, **Sync Status** for saved status information, and **Report Bug** for support.

The addon works without the Windows watcher, but **website dashboard syncing requires the watcher**.

## Optional dashboard syncing (Windows)

Visit https://azpc.market and install the AZPC Launcher. Select **Forever Beta**, install/update the Forever addon and watcher, then start the watcher. Sign into your AZPC account as directed by the launcher. Return to WoW and `/reload` to save captured data and refresh status loaded from disk. Check https://forever.azpc.market/ for dashboard activity.

**Status accuracy:** Sync Status displays the last saved information available when the addon loaded; it cannot continuously inspect a Windows process or independently prove an upload reached the website.

## Useful commands

- `/azpcf setup` — Getting Started.
- `/azpcf sync` — Sync Status.
- `/azpcf bug` — Report Bug.
- `/azpcf testsetup` — Preview the optional watcher setup reminder (for testing only).

## Troubleshooting

If the addon is absent, confirm you installed it under the correct game client's `Interface/AddOns/AZPCForever` folder, the `.toc` file is directly inside that folder, and the addon is enabled. If the dashboard is empty, check that the separate watcher is running, you have signed into the correct account, and you have captured supported data; then `/reload`. Do not delete SavedVariables or trading history as a troubleshooting shortcut.

**Privacy:** Review the report preview before posting. Character details in the bug reporter are opt-in. Never paste passwords, tokens, or private account information into bug reports.
