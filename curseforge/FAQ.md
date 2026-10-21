# AZPC Forever — Frequently Asked Questions

## Do I need the AZPC Launcher or Watcher?
No. The CurseForge addon runs independently for supported in-game features. The separate Windows watcher is needed to upload saved data to your AZPC account and use website dashboards. The watcher is **not included** in the CurseForge addon ZIP.

## How do I open AZPC?
Use the AZPC minimap icon. It offers Getting Started, Crafting, Sync Status, settings and Report Bug. You can also type `/azpcf setup`, `/azpcf sync`, or `/azpcf bug`.

## Where does auction price information come from?
AZPC captures supported auction-house observations that the game client actually loads. Prices can be missing, delayed, or specific to a realm and faction. A listing price does not mean an item sold at that price. The addon does not automatically scan every auction in the game.

## Does AZPC automatically buy or sell items?
Do not assume it does. Review all auction and crafting actions in game. Price and crafting estimates are decision-support tools, not guarantees.

## How accurate are crafting profit estimates?
They depend on available material prices and captured acquisition costs. Historical materials, missing vendor evidence, or incomplete purchases may leave the cost basis unresolved. Unknown costs are not treated as free materials.

## Why is my dashboard empty?
The addon can work without a watcher, but website syncing cannot. Install the optional launcher and watcher from https://azpc.market, connect the intended AZPC account, confirm the watcher is running, collect supported records, and use `/reload` when needed to save game data. Sync Status shows saved status, not proof of a live upload.

## Do I need to reinstall everything for an update?
CurseForge updates the standalone addon. If you use the separate watcher, update it through the AZPC Launcher as appropriate. Preserve your SavedVariables and do not delete trading history while troubleshooting.

## How do I report a bug?
Open the AZPC minimap menu and choose Report Bug, or type `/azpcf bug`. Review the generated report before sharing. Character details are optional. Never include account tokens, passwords or other private credentials.

## Is AZPC affiliated with Blizzard?
No. AZPC is an independent community project and is not endorsed by or affiliated with Blizzard Entertainment.

## What happens when Forever moves from beta to live?
Beta and live datasets are designed to remain separate. Existing beta prices should not be presented as current live-market prices. Live-server support and game-client compatibility must be verified before public release.

## What should I do if my game client is not supported?
Do not install the addon under Retail, TBC or another client as a workaround. Wait for the correct CurseForge game flavor/version to be available and confirmed.
