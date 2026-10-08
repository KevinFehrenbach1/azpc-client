## Purchase quantity repair (addon 0.2.10 / watcher 0.4.37)
Purchase capture requires the attached stack quantity; invoice fallback is disabled. Historical purchase records where the quantity equals the copper amount are omitted from accounting only if exactly one differently quantified observation of the same mail (including counterpart, subject and occurrence) is found within five seconds and two expiry minutes. Unpaired records stay unchanged. Raw records remain intact. Watcher upgrades and requeues old JSON evidence once so the server can repair the same history. The material table separates bought, farmed, crafted and received origins; missing earlier actions are not invented.

## Automatic farmed materials (Forever addon 0.2.8)
New corpse and gathering loot (including skinning, herbs, mining and fishing loot windows) is recorded automatically at zero cash cost when a world loot source, your localized self-loot receipt and exact bag increase match. Repeated notifications cannot add duplicate stock. Item-container sources and unexplained changes remain unknown; purchases retain paid costs. Reload/logout saves events for the watcher. Existing inventory still needs explicit classification because its origin was not observed. Confirmed alt mail retains the original material cost. Manual classification remains a fallback.

# AZPC Client

Official desktop client and addon installer for Azerothian Price Checker.

https://azpc.market


## Forever material sources (addon 0.2.7 / watcher 0.4.36)

The private Crafting page has a Material sources panel. Select an item/character, quantity and Farmed or Gift/free. The declaration is queued for that account's watcher. After 30 seconds, /reload on the selected character to apply it; /reload again saves the confirmed result for upload. The addon verifies current bag quantities and remaining recorded stock before adding untracked units or reclassifying zero-cost unknown units. It cannot erase known paid material cost. Failed quantity/source checks are durably rejected rather than applied to later acquisitions.

Paid and explicit free material stock use the remaining weighted average for crafts and transfers, with integer-copper remainder conservation. Completed costs stay frozen; future acquisitions do not reprice older crafts. Ordinary AH purchase/sale FIFO behavior is preserved. Market quote comparisons are estimates and never enter the paid-cost ledger.

Personal-mail attachments are recorded after successful sending, and received attachments after take intent and matching bag quantity changes. Only uniquely matched sender/recipient, item, quantity, subject and market carry source costs. Unmatched/ambiguous receipts remain unknown; mailing an item never automatically makes it free. Use a distinct mail subject for repeated identical shipments. Transfers remove sender stock into transit and add it once on receipt. Sends with money/COD and AH invoices are excluded from this personal-material path. Source declarations and transfers are private crafting data and do not clutter the AH history table.

Website declarations travel as byte-escaped data in an addon-owned trailing command block. The watcher never rewrites SavedVariables or copies account credentials into addon files. Applied and rejected requests are acknowledged through the existing durable crafting upload and keep stable identities across reloads/retries.
