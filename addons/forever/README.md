# AZPC Forever 0.1.1 / Watcher 0.4.28

Use Launcher 0.2.3, choose Forever Beta, Check for updates, then Install / Update All with WoW closed. This updates both the Forever addon and shared watcher. TBC addon and existing credentials/history are preserved.

Open the Auction House to collect loaded market prices. `/azpcf capture` captures loaded browse results. These market observations remain local; they are not purchases or sales.

Open your mailbox before collecting Auction House mail, then `/reload` or log out. The addon records confirmed buyer/seller invoices with known item IDs, stack quantities and total purchase cost or net seller proceeds. Missing invoice quantities, delayed proceeds or unresolved item IDs are not guessed. It captures observed mailbox records, not click intents, and does not retrospectively reconstruct removed mail. Existing old mail is recorded when first observed; the website labels the time as Recorded.

Watcher uploads confirmed trade records to `https://forever.azpc.market/api/trades/upload` using its existing AZPC account credential. A durable local queue under `Forever/trades` retries unacknowledged uploads. Receiver deduplicates records per account. Market observations still stay under `Forever/scans` and are not uploaded to TBC.

Open `https://forever.azpc.market/my-trades`, connect your existing AZPC account, and continue to Forever. Trading data is account private and stored separately from TBC. The page includes copper-exact FIFO realized profit/loss, net sale proceeds, open basis/positions, graph ranges, and a filtered/paginated timeline. Unknown purchase basis is shown explicitly and excluded from realized profit. Manual entries allow older purchases/sales and zero-cost farmed/other acquisitions; do not manually add events already captured automatically.

Real beta mailbox API support must be validated in-game after rollout. Region 90 remains separate from live regions. Characters/realms/factions stay separate. Untracked cross-character transfers are not inferred as purchases or sales. The existing launcher background start issue remains separate; use the working visible PowerShell start until repaired.


## 0.2.0 trading lifecycle

Update through Launcher 0.2.8 (watcher 0.4.32). Open your bags, AH owner tab and mailbox, then /reload. The addon captures complete owned-auction status, bag quantities and confirmed mailbox buy/sale/expired records. Refunded sale deposits are separate from net proceeds. Old saved mailbox IDs are preserved and seller invoices can enrich the existing record. Partial owner pages and missing metadata are deferred. Expired deposit losses remain unknown unless captured evidence establishes them; no beta vendor formula is assumed. The website shows FIFO P/L, profit/revenue history, pending/unresolved listings, exact-market valuation and unlisted bag opportunities.
