# Forever 0.2.46: disenchant evidence test

Update the Forever addon in the AZPC launcher with WoW closed. Disenchant one expendable item, collect the materials, then run `/azpcf disenchant` in WoW chat. The command reports the latest input, confirmed output count and whether the evidence is complete. Run `/reload` to save it to the normal `AZPCForeverDB` SavedVariables file under `disenchanting.events`.

This stage saves local evidence only. It does not upload disenchant records, transfer cost basis or change My Trades profit. Existing auction, mail, farming, crafting and cost replay remain separate.

A confirmed input requires a successful Disenchant cast, the input item GUID in the loot source, and a matching one-item decrease in bags. Outputs require matching self-loot messages and bag increases. Missing APIs, ambiguous consumption or unconfirmed loot stay explicitly unresolved. Failed/interrupted casts do not create completed records. Stored cast identities prevent repeated success notifications from duplicating the capture.

Capture is isolated in a separate local scope inside the existing addon file, preserving the current launcher archive layout. It scans bags only while capturing a disenchant and does not schedule accounting replays. Watcher remains 0.4.40 and TBC remains 0.4.29.
