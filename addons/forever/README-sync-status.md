# Sync details (addon 0.2.54 / watcher 0.4.41)

The existing fresh-sale/return reminder keeps its triggers, combat deferral,
Reload now and Later actions. Details opens an optional 620x440 movable panel.
`/azpcf sync` opens it manually. Escape/close/Later dismiss the panel.

Counts are new activity records this login: auction sales, expired returns,
AH/vendor purchases, confirmed material gains and completed crafts. Quantities
are records, not item units. Inventory/listing reference snapshots are excluded.
The panel reads appended records incrementally and never captures mail, rebuilds
costs, changes receipts or resets deduplication. The session count resets after
login/reload; zero does NOT mean all saved records have uploaded.

Watcher status is an optional, numeric-only section in the existing addon file.
Watcher 0.4.41 writes it at most every 30 seconds in discovered Forever addon
installations which ship the explicitly marked status section. It never writes
SavedVariables or changes code outside that status section. Successful upload branches record
the last acknowledged batch only AFTER server acknowledgement and local sent
markers; offline/wrong acknowledgements cannot create a successful status.
No token, client ID, account ID or character data is included.

The game cannot continuously read a desktop file. Status therefore explicitly
says last known, loaded at login/reload, and refers to this PC's previous batch.
A missing/stale timestamp asks the user to check the Launcher; it does not assert
that the watcher is offline. Current unsaved activity is never marked uploaded
because a previous batch succeeded. The panel's reload requires a user click
and is disabled in combat.

Test in game: update addon AND watcher, let the watcher run for 30 seconds, then
/reload. Use /azpcf sync. Capture an auction sale/return, use Details, verify counts,
then Reload now. Confirm the existing website receipt remains exactly once.
