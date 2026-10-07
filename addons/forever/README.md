# AZPC Forever 0.1.1 / Watcher 0.4.28

Use Launcher 0.2.3, choose Forever Beta, Check for updates, then Install / Update All with WoW closed. This updates both the Forever addon and shared watcher. TBC addon and existing credentials/history are preserved.

Open the Auction House to collect loaded market prices. `/azpcf capture` captures loaded browse results. These market observations remain local; they are not purchases or sales.

Open your mailbox before collecting Auction House mail, then `/reload` or log out. The addon records confirmed buyer/seller invoices with known item IDs, stack quantities and total purchase cost or net seller proceeds. Missing invoice quantities, delayed proceeds or unresolved item IDs are not guessed. It captures observed mailbox records, not click intents, and does not retrospectively reconstruct removed mail. Existing old mail is recorded when first observed; the website labels the time as Recorded.

Watcher uploads confirmed trade records to `https://forever.azpc.market/api/trades/upload` using its existing AZPC account credential. A durable local queue under `Forever/trades` retries unacknowledged uploads. Receiver deduplicates records per account. Market observations still stay under `Forever/scans` and are not uploaded to TBC.

Open `https://forever.azpc.market/my-trades`, connect your existing AZPC account, and continue to Forever. Trading data is account private and stored separately from TBC. The page includes copper-exact FIFO realized profit/loss, net sale proceeds, open basis/positions, graph ranges, and a filtered/paginated timeline. Unknown purchase basis is shown explicitly and excluded from realized profit. Manual entries allow older purchases/sales and zero-cost farmed/other acquisitions; do not manually add events already captured automatically.

Real beta mailbox API support must be validated in-game after rollout. Region 90 remains separate from live regions. Characters/realms/factions stay separate. Untracked cross-character transfers are not inferred as purchases or sales. The existing launcher background start issue remains separate; use the working visible PowerShell start until repaired.


## 0.2.0 trading lifecycle

Update through Launcher 0.2.8 (watcher 0.4.32). Open your bags, AH owner tab and mailbox, then /reload. The addon captures complete owned-auction status, bag quantities and confirmed mailbox buy/sale/expired records. Refunded sale deposits are separate from net proceeds. Old saved mailbox IDs are preserved and seller invoices can enrich the existing record. Partial owner pages and missing metadata are deferred. Expired deposit losses remain unknown unless captured evidence establishes them; no beta vendor formula is assumed. The website shows FIFO P/L, profit/revenue history, pending/unresolved listings, exact-market valuation and unlisted bag opportunities.


## 0.2.1 recipe and completed-craft capture (stage 1)

Update Forever through Launcher 0.2.9. Open Tailoring (or another item-crafting profession), craft normally, then use `/azpcf crafts` and `/reload`. The status reports saved recipe and completed-craft counts and the most recent output. Requirements are captured automatically on profession updates; the command also refreshes loaded recipes. Each completed craft reports its actual output quantity.

Records live in `AZPCForeverDB.crafting` in the existing account SavedVariables file. Recipes include output item/range, reagent slots and per-craft requirements, profession, character and exact market. Craft records preserve their own recipe requirements, actual output quantity, cast identity, material returns, time and character. They require a successful player spell and a matching `TRADE_SKILL_ITEM_CRAFTED_RESULT`; clicking Craft, cancellation, ordinary loot and bag changes do not count. Cast identities persist for deduplication across reloads. Only learned item recipes are accepted; linked/guild/NPC, enchants, recrafts, gathering and salvage are excluded. Missing/ambiguous selection evidence leaves material consumption unresolved rather than assigning a zero cost.

This stage is local capture only: the watcher does not upload these records yet, and they do not enter My Trades or change cost basis. Material-cost transfer, vendor purchase tracking, calculator UI and realized crafted profit are subsequent steps. Existing purchases/sales and FIFO accounting remain unchanged. Beta runtime validation is still required: craft one Bolt of Linen Cloth, inspect `/azpcf crafts`, then `/reload` and confirm the count survives.

API reference used: Blizzard UI source for the Forever branch, `TradeSkillUIDocumentation.lua` and `TradeSkillUITypesDocumentation.lua` (https://github.com/Gethe/wow-ui-source/tree/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated). Tests cover confirmations in either order, separate batch casts into the same stack, duplicate notifications, failures/interruption, refunds of materials, unknown selections, reload replay and unavailable APIs.

## 0.2.2 material costs (stage 2)

Update Forever through Launcher 0.2.10, then run `/azpcf crafts`. Saved purchase invoices and completed crafts are replayed chronologically per character and market. Each craft consumes the weighted average copper cost of remaining recorded materials, transfers it to the actual output quantity, and saves its cost basis. Intermediate outputs can supply later recipes (cloth → bolts → bags). Ordinary material sales consume purchase lots FIFO. Integer copper is conserved through partial usage and output splits.

Missing purchases, vendor materials, untracked transfers, or uncertain reagent usage keep the total incomplete; recorded partial cost is never represented as a full cost. Earlier purchase evidence may resolve an incomplete craft; later purchases do not rewrite a completed cost. Conflicting historical evidence preserves the saved cost and flags the derived output as unresolved. Repeated processing does not duplicate acquisitions or modify trade exports. `/reload` saves the local records. Website upload, calculator UI, and sale profit linkage are the next stage.
