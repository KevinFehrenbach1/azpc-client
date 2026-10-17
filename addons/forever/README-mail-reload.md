# Forever 0.2.47: mailbox reload identity

Seller mail that remains in the mailbox during a UI reload retains its saved receipt fingerprint and original recorded time. The addon checkpoints only uncollected receipts that still match live invoice and header values at logout. The checkpoint is restricted to the same character/market and a five-minute reload window. It also handles mailbox-close immediately before logout and an initially empty inbox cache after loading.

The active mailbox can reuse the same receipt while expiry estimates drift or a buyer name loads. Different invoice values and separate simultaneous occurrences remain distinct. After a complete loaded inbox confirms a receipt absent, its fingerprint is retired; a genuinely new identical-priced sale cannot reuse the consumed occurrence. Partial invoice/inbox reads do not retire unseen receipts.

This prevents new duplicate captures in the supported reload flow. It does not delete historical uploaded records or guess that equal item names and prices are duplicates. The website continues to reconcile receipt copies only where its identity/evidence rules support the match. Existing copies with changed identities may require targeted reconciliation.

Test with one seller mail: open the mailbox, leave the gold uncollected, reload, then reopen the mailbox. Repeat once, then collect the gold and reload. The sale should retain one receipt and its original timestamp. Ordinary mail collection, source tracking, cost formulas and disenchant capture are unchanged. Watcher remains 0.4.40; TBC remains 0.4.29; launcher remains 0.2.21.
