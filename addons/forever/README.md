# AZPC Forever 0.1.0 / Watcher 0.4.27

Install the `AZPCForever` folder in `_classic_beta_/Interface/AddOns`, then restart WoW and enable AZPC Forever. Browse/search the Auction House. `/azpcf capture` captures currently loaded results; `/reload` or logout writes SavedVariables for the watcher. This is browse coverage, not a complete AH scan. No automated bidding, buying, selling, or auction queries.

In Launcher 0.2.2: Check for updates, then Update watcher. The Anniversary addon stays 0.4.29. Existing account credentials and private transaction history are preserved.

Watcher searches `_classic_beta_/WTF/Account/*/SavedVariables/AZPCForever.lua` under its configured WoW root and standard C/D/E WoW paths, across accounts. If beta is installed in another location, supply that parent WoW directory as `-WowRoot`. Forever observations are deduplicated and queued under `<watcher DataDir>/Forever/scans`. Logs say `FOREVER COLLECTED`.

**Forever upload is not implemented:** the current Anniversary receiver cannot accept Forever realms. This build keeps Forever observations local, identified by game, realm, faction, region and capture timestamp. It does not send them to the Anniversary API. Unknown auction counts are zero. Different item variants collapse to the lowest item-ID price. Real beta API behavior still needs in-game validation.

Watcher 0.4.27 accepts region 90 reported by the Forever Beta and preserves that identifier. It reads changed SavedVariables once, logs each invalid snapshot once per file change, and continues collecting valid snapshots after an invalid one.
