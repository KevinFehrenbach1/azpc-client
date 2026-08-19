local ADDON_NAME = ...

local frame = CreateFrame("Frame")

local function safeRegisterEvent(eventName)
    local ok = pcall(frame.RegisterEvent, frame, eventName)
    return ok
end

-- Core Anniversary/Classic events.
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
safeRegisterEvent("MAIL_SHOW")
safeRegisterEvent("MAIL_INBOX_UPDATE")

-- Optional AH events vary by WoW client/version. Never let one unsupported
-- event prevent the entire addon (including /azpc) from loading.
safeRegisterEvent("AUCTION_OWNED_LIST_UPDATE")
safeRegisterEvent("AUCTION_BIDDER_LIST_UPDATE")
safeRegisterEvent("NEW_AUCTION_UPDATE")
local HAS_AUCTION_CREATED_EVENT = safeRegisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
safeRegisterEvent("CHAT_MSG_SYSTEM")
safeRegisterEvent("CHAT_MSG_LOOT")
safeRegisterEvent("AUCTION_BIDDER_LIST_UPDATE")

local AH_OPEN = false
local lastSnapshotFingerprint = nil
local dirtySinceFlush = false
local sellItemCache = nil
local pendingSell = nil
local hookInstalled = false
local lastOwnedSnapshot = nil
local recentSaleConfirmations = {}
local ownerRefreshGeneration = 0
local pendingBuys = {}
local purchaseProbeMessages = {}
local purchaseProbeWindowSeconds = 30
local pendingCrafts = {}
local craftHookInstalled = false


local function now()
    if GetServerTime then
        return GetServerTime()
    end
    return time()
end

local function ensureDB()
    if type(AZPCDB) ~= "table" then
        AZPCDB = {}
    end

    local previousVersion = tonumber(AZPCDB.version) or 0

    AZPCDB.observations = AZPCDB.observations or {}
    AZPCDB.snapshots = AZPCDB.snapshots or {}
    AZPCDB.transactions = AZPCDB.transactions or {}
    AZPCDB.ownedAuctions = AZPCDB.ownedAuctions or {}
    AZPCDB.ownedAuctionPages = AZPCDB.ownedAuctionPages or {}
    AZPCDB.recentPostedAuctions = AZPCDB.recentPostedAuctions or {}
    AZPCDB.purchaseDiagnostics = AZPCDB.purchaseDiagnostics or {}
    AZPCDB.mailboxCaptures = AZPCDB.mailboxCaptures or {}
    AZPCDB.mailboxSettlements = AZPCDB.mailboxSettlements or {}
    AZPCDB.mailboxActiveCounts = AZPCDB.mailboxActiveCounts or {}
    AZPCDB.meta = AZPCDB.meta or {}
    AZPCDB.settings = AZPCDB.settings or {}

    -- v0.4.14 used daysLeft/estimated expiry time in the settlement identity.
    -- That value drifts during MAIL_INBOX_UPDATE, so the same physical mail could
    -- be inserted again. On the one-time 4.15 migration, discard only the
    -- normalized settlement test records created by that buggy reconciler and
    -- reset its listing-consumption flags. The original AH ledger is preserved.
    if previousVersion < 415 and not AZPCDB.meta.settlementDedupeMigration415 then
        local keptTransactions = {}
        for _, tx in ipairs(AZPCDB.transactions) do
            if tx.kind ~= "sale_settled" and tx.kind ~= "auction_expired" then
                tx.mailSettlementConsumedCount = nil
                tx.mailSettlementConsumed = nil
                tx.mailSettlementConsumedAt = nil
                tx.mailSettlementOutcome = nil
                table.insert(keptTransactions, tx)
            end
        end
        AZPCDB.transactions = keptTransactions
        AZPCDB.mailboxSettlements = {}
        AZPCDB.meta.settlementDedupeMigration415 = true
        AZPCDB.meta.settlementDedupeMigration415At = now()
    end


    -- v0.4.15 still allowed seller invoice fields to resolve in stages, so a
    -- physical sale mail could receive a second logical identity on the next
    -- MAIL_INBOX_UPDATE. Rebuild only mailbox-generated settlement records once
    -- for 4.16, preserving the original buy/sell/post ledger.
    if previousVersion < 416 and not AZPCDB.meta.settlementIdentityMigration416 then
        local keptTransactions = {}
        for _, tx in ipairs(AZPCDB.transactions) do
            if tx.kind ~= "sale_settled" and tx.kind ~= "auction_expired" then
                tx.mailSettlementConsumedCount = nil
                tx.mailSettlementConsumed = nil
                tx.mailSettlementConsumedAt = nil
                tx.mailSettlementOutcome = nil
                table.insert(keptTransactions, tx)
            end
        end
        AZPCDB.transactions = keptTransactions
        AZPCDB.mailboxSettlements = {}
        AZPCDB.meta.settlementIdentityMigration416 = true
        AZPCDB.meta.settlementIdentityMigration416At = now()
    end

    -- v0.4.16 still tried to identify individual physical mails from fields that
    -- Blizzard resolves/changes asynchronously. v0.4.17 switches to a mailbox
    -- snapshot multiset: canonical content counts only move upward during an open
    -- mailbox session, so partial refreshes cannot duplicate the same messages.
    -- Rebuild only mailbox-generated settlement test rows once; preserve the
    -- original AH buy/sell/post ledger.
    if previousVersion < 417 and not AZPCDB.meta.settlementSnapshotMigration417 then
        local keptTransactions = {}
        for _, tx in ipairs(AZPCDB.transactions) do
            if tx.kind ~= "sale_settled" and tx.kind ~= "auction_expired" then
                tx.mailSettlementConsumedCount = nil
                tx.mailSettlementConsumed = nil
                tx.mailSettlementConsumedAt = nil
                tx.mailSettlementOutcome = nil
                table.insert(keptTransactions, tx)
            end
        end
        AZPCDB.transactions = keptTransactions
        AZPCDB.mailboxSettlements = {}
        AZPCDB.mailboxActiveCounts = {}
        AZPCDB.meta.settlementSnapshotMigration417 = true
        AZPCDB.meta.settlementSnapshotMigration417At = now()
    end

    if previousVersion < 418 and not AZPCDB.meta.realizedPnlMigration418 then
        AZPCDB.meta.realizedPnlMigration418 = true
        AZPCDB.meta.realizedPnlMigration418At = now()
    end

    -- v0.4.18 incorrectly used a batch posting's TOTAL quantity as the quantity
    -- sold by every individual seller mail. Example: posting 12 stacks of 1
    -- recorded quantity=12, then every one-stack sale tried to consume 12 units
    -- of FIFO cost basis. v0.4.19 derives a per-auction stack quantity instead.
    -- Existing settlements are preserved; rebuildRealizedPnl() repairs their
    -- quantities and recomputes basis from the original purchase ledger.
    if previousVersion < 419 and not AZPCDB.meta.stackPnlMigration419 then
        AZPCDB.meta.stackPnlMigration419 = true
        AZPCDB.meta.stackPnlMigration419At = now()
    end

    AZPCDB.version = 424
    if AZPCDB.settings.mailDebug == nil then
        AZPCDB.settings.mailDebug = false
    end
    if AZPCDB.settings.autoSyncOnClose == nil then
        AZPCDB.settings.autoSyncOnClose = true
    end
end

local function updateCharacterMeta()
    ensureDB()

    AZPCDB.meta.character = UnitName("player")
    AZPCDB.meta.realm = GetRealmName()
    AZPCDB.meta.faction = UnitFactionGroup("player")
    AZPCDB.meta.lastSeen = now()

    if GetBuildInfo then
        local version, build, date, tocVersion = GetBuildInfo()
        AZPCDB.meta.clientVersion = version
        AZPCDB.meta.clientBuild = build
        AZPCDB.meta.interface = tocVersion
    end
end

local function trimObservations()
    -- Safety cap for the MVP so SavedVariables cannot grow forever.
    local MAX_OBSERVATIONS = 10000
    local count = #AZPCDB.observations
    if count > MAX_OBSERVATIONS then
        local removeCount = count - MAX_OBSERVATIONS
        for i = 1, removeCount do
            table.remove(AZPCDB.observations, 1)
        end
    end

    local MAX_SNAPSHOTS = 250
    while #AZPCDB.snapshots > MAX_SNAPSHOTS do
        table.remove(AZPCDB.snapshots, 1)
    end
end

local function trimTransactions()
    local MAX_TRANSACTIONS = 5000
    while #AZPCDB.transactions > MAX_TRANSACTIONS do
        table.remove(AZPCDB.transactions, 1)
    end
end

local function addTransaction(entry)
    ensureDB()
    updateCharacterMeta()

    entry.timestamp = entry.timestamp or now()
    entry.character = entry.character or AZPCDB.meta.character
    entry.realm = entry.realm or AZPCDB.meta.realm
    entry.faction = entry.faction or AZPCDB.meta.faction

    table.insert(AZPCDB.transactions, entry)
    AZPCDB.meta.lastTransactionWrite = entry.timestamp
    dirtySinceFlush = true
    trimTransactions()
end


local function installCraftHook()
    if craftHookInstalled then return end
    if type(DoTradeSkill) ~= "function" or type(hooksecurefunc) ~= "function" then return end
    craftHookInstalled = true
    hooksecurefunc("DoTradeSkill", function(index, count)
        index = tonumber(index)
        count = math.max(1, tonumber(count) or 1)
        if not index or type(GetTradeSkillItemLink) ~= "function" then return end
        local outLink = GetTradeSkillItemLink(index)
        local outId = parseItemIdFromLink and parseItemIdFromLink(outLink) or tonumber(outLink and string.match(outLink, "item:(%d+)"))
        local outName = outLink and GetItemInfo(outLink) or nil
        if not outId or not outName then return end
        local madeMin, madeMax = 1, 1
        if type(GetTradeSkillNumMade) == "function" then
            local a,b = GetTradeSkillNumMade(index)
            madeMin = tonumber(a) or 1; madeMax = tonumber(b) or madeMin
        end
        local made = math.max(1, madeMin)
        local reagents = {}
        if type(GetTradeSkillNumReagents) == "function" then
            local n = tonumber(GetTradeSkillNumReagents(index)) or 0
            for r=1,n do
                local rLink = type(GetTradeSkillReagentItemLink)=="function" and GetTradeSkillReagentItemLink(index,r) or nil
                local rId = tonumber(rLink and string.match(rLink, "item:(%d+)"))
                local _,_,rCount = GetTradeSkillReagentInfo(index,r)
                rCount = tonumber(rCount) or 0
                if rId and rCount>0 then table.insert(reagents, tostring(rId)..":"..tostring(rCount)) end
            end
        end
        local reagentSpec = table.concat(reagents, ",")
        for i=1,count do
            table.insert(pendingCrafts, {itemId=outId,name=outName,quantity=made,reagentSpec=reagentSpec,queuedAt=now()})
        end
        while #pendingCrafts > 50 do table.remove(pendingCrafts,1) end
    end)
end

local function confirmCraftFromLoot(text)
    if type(text) ~= "string" or #pendingCrafts == 0 then return false end
    local link = string.match(text, "(|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r)") or string.match(text, "(|Hitem:[^|]+|h%[[^%]]+%]|h)")
    local itemId = tonumber(link and string.match(link, "item:(%d+)"))
    if not itemId then return false end
    local t = now()
    for i=1,#pendingCrafts do
        local c = pendingCrafts[i]
        if c.itemId == itemId and (t-(c.queuedAt or t)) <= 30 then
            table.remove(pendingCrafts,i)
            addTransaction({kind="craft_confirmed",name=c.name,itemId=c.itemId,quantity=c.quantity,status="reagents="..(c.reagentSpec or ""),source="TRADE_SKILL_CRAFT_CONFIRMED"})
            print("|cff00ff98AZPC|r: CRAFT CONFIRMED: "..tostring(c.name).." x"..tostring(c.quantity))
            return true
        end
    end
    return false
end

local function parseItemIdFromLink(link)
    if not link then
        return nil
    end

    local id = string.match(link, "item:(%d+)")
    id = tonumber(id)
    if id and id > 0 then
        return id
    end

    return nil
end

local function cacheSellItem()
    local cached = {}

    -- Best source on Classic/TBC: the actual item link currently sitting
    -- in the Auction House sell slot. This preserves identity even when
    -- GetAuctionSellItemInfo does not expose itemID on this client.
    if type(GetAuctionSellItemLink) == "function" then
        local link = GetAuctionSellItemLink()
        if link then
            cached.itemLink = link
            cached.itemId = parseItemIdFromLink(link)

            if type(GetItemInfo) == "function" then
                local itemName, itemLink, quality, _, _, _, _, _, _, _, sellPrice = GetItemInfo(link)
                cached.vendorSellPrice = tonumber(sellPrice) or cached.vendorSellPrice
                cached.name = itemName
                cached.itemLink = itemLink or cached.itemLink
                cached.quality = quality
            end
        end
    end

    -- Quantity/stack information from the sell slot.
    if type(GetAuctionSellItemInfo) == "function" then
        local name, texture, count, quality, canUse, price, pricePerUnit,
              stackCount, totalCount = GetAuctionSellItemInfo()

        cached.name = cached.name or name
        cached.count = tonumber(count) or cached.count
        cached.stackCount = tonumber(stackCount) or cached.stackCount
        cached.totalCount = tonumber(totalCount) or cached.totalCount
        cached.quality = cached.quality or quality
    end

    -- If Classic gave us a name but not an item ID, ask GetItemInfo by name.
    -- It can return an item link even when GetAuctionSellItemLink() is nil;
    -- parsing that link gives us the numeric item ID.
    if cached.name and (not cached.itemId) and type(GetItemInfo) == "function" then
        local itemName, itemLink, quality, _, _, _, _, _, _, _, sellPrice = GetItemInfo(cached.name)
        cached.vendorSellPrice = tonumber(sellPrice) or cached.vendorSellPrice
        cached.name = itemName or cached.name
        cached.itemLink = itemLink or cached.itemLink
        cached.quality = cached.quality or quality
        cached.itemId = parseItemIdFromLink(cached.itemLink)
    end

    -- Final fallback: if we have an item ID but the name/link had not resolved,
    -- ask the item cache by ID.
    if cached.itemId and type(GetItemInfo) == "function" then
        local itemName, itemLink, quality, _, _, _, _, _, _, _, sellPrice = GetItemInfo(cached.itemId)
        cached.vendorSellPrice = tonumber(sellPrice) or cached.vendorSellPrice
        cached.name = cached.name or itemName
        cached.itemLink = itemLink or cached.itemLink
        cached.quality = cached.quality or quality
        cached.itemId = cached.itemId or parseItemIdFromLink(cached.itemLink)
    end

    if cached.itemId or cached.name then
        cached.count = tonumber(cached.count) or 1
        cached.stackCount = tonumber(cached.stackCount) or cached.count or 1
        cached.totalCount = tonumber(cached.totalCount) or cached.count or 1
        cached.cachedAt = now()
        sellItemCache = cached
    else
        -- Important: do NOT destroy a previously good cache just because
        -- the sell slot became empty during the post action.
        -- This is what caused "Item ?" in v0.4.1.
        return sellItemCache
    end

    return sellItemCache
end

local function scheduleOwnerRefresh(reason)
    if type(GetOwnerAuctionItems) ~= "function" then
        return
    end

    ownerRefreshGeneration = ownerRefreshGeneration + 1
    local generation = ownerRefreshGeneration

    local function attempt(delayLabel)
        if generation ~= ownerRefreshGeneration then
            return
        end

        local ok, err = pcall(GetOwnerAuctionItems)
        if ok then
            AZPCDB.meta.lastOwnerRefreshRequest = now()
            AZPCDB.meta.lastOwnerRefreshReason = reason or "unknown"
            AZPCDB.meta.lastOwnerRefreshAttempt = delayLabel
        else
            AZPCDB.meta.lastOwnerRefreshError = tostring(err)
        end
    end

    attempt("immediate")

    if C_Timer and C_Timer.After then
        C_Timer.After(0.75, function() attempt("0.75s") end)
        C_Timer.After(1.75, function() attempt("1.75s") end)
        C_Timer.After(3.25, function() attempt("3.25s") end)
    end
end

local function pruneRecentPostedAuctions()
    ensureDB()

    local cutoff = now() - 900
    local kept = {}

    for _, row in ipairs(AZPCDB.recentPostedAuctions or {}) do
        if tonumber(row.acknowledgedAt or 0) >= cutoff and not row.reconciled then
            table.insert(kept, row)
        end
    end

    AZPCDB.recentPostedAuctions = kept
end

local function recentPostLogicalKey(row)
    return table.concat({
        tostring(row.itemId or 0),
        tostring(row.name or ""),
        tostring(row.stackSize or row.count or 0),
        tostring(row.totalBuyoutPerStack or row.buyoutPrice or 0),
    }, "|")
end

local function addRecentPostedAuctionFromPending(pending)
    if not pending then
        return
    end

    ensureDB()
    pruneRecentPostedAuctions()

    local stacks = tonumber(pending.numStacks) or 1
    if stacks < 1 then stacks = 1 end

    local entry = {
        itemId = pending.itemId,
        itemLink = pending.itemLink,
        name = pending.name,
        stackSize = tonumber(pending.stackSize) or 1,
        numStacks = stacks,
        quantity = tonumber(pending.quantity) or stacks,
        totalBuyoutPerStack = tonumber(pending.totalBuyoutPerStack) or 0,
        buyoutPerUnit = tonumber(pending.buyoutPerUnit) or 0,
        minBidPerStack = tonumber(pending.minBidPerStack) or 0,
        runTime = pending.runTime,
        auctionDeposit = tonumber(pending.auctionDeposit),
        auctionDepositPerStack = tonumber(pending.auctionDepositPerStack),
        auctionDepositSource = pending.auctionDepositSource,
        acknowledgedAt = now(),
        reconciled = false,
    }

    entry.logicalKey = recentPostLogicalKey(entry)
    table.insert(AZPCDB.recentPostedAuctions, entry)
    AZPCDB.meta.lastRecentPostAck = entry.acknowledgedAt
end

local function serverOwnedCountForRecent(recent)
    local count = 0

    for _, row in ipairs(AZPCDB.ownedAuctions or {}) do
        local sameId = recent.itemId and row.itemId
            and tonumber(recent.itemId) == tonumber(row.itemId)
        local sameName = recent.name and row.name
            and tostring(recent.name) == tostring(row.name)
        local sameIdentity = sameId or sameName
        local sameStack = tonumber(row.count or 0) == tonumber(recent.stackSize or 0)
        local sameBuyout = tonumber(row.buyoutPrice or 0)
            == tonumber(recent.totalBuyoutPerStack or 0)

        if sameIdentity and sameStack and sameBuyout then
            count = count + 1
        end
    end

    return count
end

local function reconcileRecentPostedAuctions()
    ensureDB()
    pruneRecentPostedAuctions()

    local kept = {}

    for _, recent in ipairs(AZPCDB.recentPostedAuctions or {}) do
        local expected = tonumber(recent.numStacks) or 1
        local visible = serverOwnedCountForRecent(recent)

        if visible >= expected then
            recent.reconciled = true
            recent.reconciledAt = now()

            addTransaction({
                kind = "sell_posted_confirmed",
                source = "OWNER_LIST_RECONCILE",
                itemId = recent.itemId,
                itemLink = recent.itemLink,
                name = recent.name,
                quantity = recent.quantity,
                stackSize = recent.stackSize,
                numStacks = recent.numStacks,
                totalPrice = recent.totalBuyoutPerStack,
                unitPrice = recent.buyoutPerUnit,
                minBidPerStack = recent.minBidPerStack,
                runTime = recent.runTime,
                auctionDeposit = recent.auctionDeposit,
                auctionDepositPerStack = recent.auctionDepositPerStack,
                auctionDepositSource = recent.auctionDepositSource,
                status = "posted_confirmed",
            })

            print("|cff00ff98AZPC|r: Owner list caught up and confirmed "
                .. tostring(recent.name or "auction item")
                .. " x" .. tostring(expected) .. ".")
        else
            recent.serverVisibleCount = visible
            table.insert(kept, recent)
        end
    end

    AZPCDB.recentPostedAuctions = kept
end

local function azpcKnownActiveCount()
    ensureDB()
    pruneRecentPostedAuctions()

    local serverCount = #(AZPCDB.ownedAuctions or {})
    local extra = 0

    for _, recent in ipairs(AZPCDB.recentPostedAuctions or {}) do
        local expected = tonumber(recent.numStacks) or 1
        local visible = serverOwnedCountForRecent(recent)
        if expected > visible then
            extra = extra + (expected - visible)
        end
    end

    return serverCount, extra, serverCount + extra
end

local function ownedAuctionKey(row)
    return table.concat({
        tostring(row.itemId or 0),
        tostring(row.name or ""),
        tostring(row.count or 0),
        tostring(row.minBid or 0),
        tostring(row.buyoutPrice or 0),
        tostring(row.bidAmount or 0),
        tostring(row.saleStatus or 0),
    }, "|")
end

local function currentOwnedPage()
    -- Classic AuctionFrame uses a zero-based page field when the owner list is paged.
    -- If the UI global is unavailable, page 0 is the safe fallback.
    if type(AuctionFrameAuctions) == "table" then
        local p = tonumber(AuctionFrameAuctions.page)
        if p and p >= 0 then
            return math.floor(p)
        end
    end
    return 0
end

local function rebuildOwnedAuctionCache(totalCount)
    ensureDB()

    local merged = {}
    local seen = {}

    local pageNumbers = {}
    for pageKey, _ in pairs(AZPCDB.ownedAuctionPages or {}) do
        local n = tonumber(pageKey)
        if n then
            table.insert(pageNumbers, n)
        end
    end
    table.sort(pageNumbers)

    for _, pageNum in ipairs(pageNumbers) do
        local pageRows = AZPCDB.ownedAuctionPages[tostring(pageNum)] or {}
        for _, row in ipairs(pageRows) do
            -- Preserve identical auctions as distinct listings by adding a
            -- per-page occurrence counter to the logical key.
            local base = ownedAuctionKey(row)
            seen[base] = (seen[base] or 0) + 1
            row.instanceKey = base .. "|#" .. tostring(seen[base])
            table.insert(merged, row)
        end
    end

    AZPCDB.ownedAuctions = merged
    AZPCDB.meta.ownedAuctionCount = #merged
    AZPCDB.meta.ownedAuctionTotalReported = tonumber(totalCount) or #merged

    local total = tonumber(totalCount) or #merged
    AZPCDB.meta.ownedAuctionScanComplete = (#merged >= total)

    return merged
end

local function captureOwnedAuctions()
    ensureDB()

    if type(GetNumAuctionItems) ~= "function" or type(GetAuctionItemInfo) ~= "function" then
        return nil
    end

    local batchCount, totalCount = GetNumAuctionItems("owner")
    batchCount = tonumber(batchCount) or 0
    totalCount = tonumber(totalCount) or batchCount

    local page = currentOwnedPage()

    local snapshot = {
        timestamp = now(),
        page = page,
        batchCount = batchCount,
        totalCount = totalCount,
        rows = {},
        counts = {},
    }

    for index = 1, batchCount do
        local name, texture, count, quality, canUse, level, levelColHeader,
              minBid, minIncrement, buyoutPrice, bidAmount, highBidder,
              bidderFullName, owner, ownerFullName, saleStatus, itemId,
              hasAllInfo = GetAuctionItemInfo("owner", index)

        if name then
            count = tonumber(count) or 1
            minBid = tonumber(minBid) or 0
            buyoutPrice = tonumber(buyoutPrice) or 0

            local itemLink = nil
            if type(GetAuctionItemLink) == "function" then
                itemLink = GetAuctionItemLink("owner", index)
            end

            if (not itemId) and itemLink then
                itemId = parseItemIdFromLink(itemLink)
            end

            if (not itemId) and type(GetItemInfo) == "function" then
                local _, resolvedLink = GetItemInfo(name)
                itemLink = itemLink or resolvedLink
                itemId = parseItemIdFromLink(itemLink)
            end

            local row = {
                page = page,
                pageIndex = index,
                itemId = itemId,
                itemLink = itemLink,
                name = name,
                count = count,
                minBid = minBid,
                minBidPerUnit = count > 0 and math.floor(minBid / count) or 0,
                buyoutPrice = buyoutPrice,
                buyoutPerUnit = (buyoutPrice > 0 and count > 0) and math.floor(buyoutPrice / count) or 0,
                bidAmount = tonumber(bidAmount) or 0,
                saleStatus = tonumber(saleStatus) or 0,
            }

            row.key = ownedAuctionKey(row)
            table.insert(snapshot.rows, row)
            snapshot.counts[row.key] = (snapshot.counts[row.key] or 0) + 1
        end
    end

    -- Replace only the page currently being viewed. This prevents stale entries
    -- from an older version of the same page while preserving other pages that
    -- were already captured during this AH session.
    AZPCDB.ownedAuctionPages[tostring(page)] = snapshot.rows

    local merged = rebuildOwnedAuctionCache(totalCount)

    AZPCDB.meta.lastOwnedSnapshot = snapshot.timestamp
    AZPCDB.meta.lastOwnedBatchCount = batchCount
    AZPCDB.meta.lastOwnedPage = page

    snapshot.mergedRows = merged
    snapshot.mergedCount = #merged
    snapshot.complete = (#merged >= totalCount)

    reconcileRecentPostedAuctions()

    return snapshot
end

local function resetOwnedPageCache()
    ensureDB()
    AZPCDB.ownedAuctionPages = {}
    AZPCDB.ownedAuctions = {}
    AZPCDB.meta.ownedAuctionCount = 0
    AZPCDB.meta.ownedAuctionScanComplete = false
    AZPCDB.meta.ownedAuctionTotalReported = 0
    lastOwnedSnapshot = nil
end

local function findOwnedMatchForPending(snapshot, pending)
    if not snapshot or not pending then
        return nil
    end

    for _, row in ipairs(snapshot.rows or {}) do
        -- Lua 5.1-safe explicit matching below.
        local sameId = pending.itemId and row.itemId and tonumber(pending.itemId) == tonumber(row.itemId)
        local sameName = pending.name and row.name and tostring(pending.name) == tostring(row.name)
        local identityMatches = sameId or sameName

        local sameCount = (not pending.stackSize) or tonumber(row.count or 0) == tonumber(pending.stackSize or 0)
        local sameBuyout = (not pending.totalBuyoutPerStack) or
            tonumber(row.buyoutPrice or 0) == tonumber(pending.totalBuyoutPerStack or 0)

        if identityMatches and sameCount and sameBuyout then
            return row
        end
    end

    return nil
end

local function confirmPendingSellFromOwned(snapshot)
    if not pendingSell then
        return
    end

    local row = findOwnedMatchForPending(snapshot, pendingSell)
    if not row then
        return
    end

    addTransaction({
        kind = "sell_posted_confirmed",
        source = "AUCTION_OWNED_LIST_UPDATE",
        itemId = row.itemId or pendingSell.itemId,
        itemLink = row.itemLink or pendingSell.itemLink,
        name = row.name or pendingSell.name,
        quantity = pendingSell.quantity,
        stackSize = pendingSell.stackSize,
        numStacks = pendingSell.numStacks,
        totalPrice = row.buyoutPrice or pendingSell.totalBuyoutPerStack,
        unitPrice = row.buyoutPerUnit or pendingSell.buyoutPerUnit,
        minBidPerStack = row.minBid or pendingSell.minBidPerStack,
        runTime = pendingSell.runTime,
        auctionDeposit = pendingSell.auctionDeposit,
        auctionDepositPerStack = pendingSell.auctionDepositPerStack,
        auctionDepositSource = pendingSell.auctionDepositSource,
        status = "posted_confirmed",
    })

    print("|cff00ff98AZPC|r: Owned-auction list confirmed post for "
        .. tostring(row.name or pendingSell.name or "auction item") .. ".")

    pendingSell = nil
end

local function findRecentOwnedByName(name)
    if not name or not lastOwnedSnapshot then
        return nil
    end

    for _, row in ipairs(lastOwnedSnapshot.rows or {}) do
        if row.name == name then
            return row
        end
    end

    return nil
end

local function recordSaleConfirmed(name)
    if not name or name == "" then
        return
    end

    local t = now()
    local previous = recentSaleConfirmations[name]
    if previous and (t - previous) < 5 then
        return
    end
    recentSaleConfirmations[name] = t

    local listing = nil
    local listingIndex = nil

    ensureDB()

    -- Newest unconsumed confirmed listing with the same item name.
    local i
    for i = #AZPCDB.transactions, 1, -1 do
        local tx = AZPCDB.transactions[i]
        if tx then
            if tx.kind == "sell_posted_confirmed" then
                if tx.name == name then
                    if not tx.saleConsumed then
                        listing = tx
                        listingIndex = i
                        break
                    end
                end
            end
        end
    end

    local owned = findRecentOwnedByName(name)

    local itemId = nil
    local itemLink = nil
    local quantity = 1
    local unitPrice = nil
    local totalPrice = nil

    if listing then
        itemId = listing.itemId
        itemLink = listing.itemLink
        quantity = tonumber(listing.quantity) or tonumber(listing.stackSize) or 1
        unitPrice = tonumber(listing.unitPrice) or tonumber(listing.buyoutPerUnit)

        if unitPrice then
            totalPrice = unitPrice * quantity
        elseif listing.totalPrice then
            totalPrice = tonumber(listing.totalPrice)
        end
    elseif owned then
        itemId = owned.itemId
        itemLink = owned.itemLink
        quantity = tonumber(owned.count) or 1
        unitPrice = tonumber(owned.buyoutPerUnit)

        if unitPrice then
            totalPrice = unitPrice * quantity
        elseif owned.buyoutPrice then
            totalPrice = tonumber(owned.buyoutPrice)
        end
    end

    addTransaction({
        kind = "sale_confirmed",
        source = "CHAT_MSG_SYSTEM",
        itemId = itemId,
        itemLink = itemLink,
        name = name,
        quantity = quantity,
        totalPrice = totalPrice,
        unitPrice = unitPrice,
        status = "sold_confirmed",
    })

    if listing and listingIndex then
        AZPCDB.transactions[listingIndex].saleConsumed = true
        AZPCDB.transactions[listingIndex].saleConsumedAt = t
        dirtySinceFlush = true
    end

    print("|cff00ff98AZPC|r: SALE CONFIRMED: "
        .. tostring(name)
        .. " | qty " .. tostring(quantity)
        .. " | unit " .. tostring(unitPrice or "?") .. "c.")
end

-- A buyer-found system message is positive sale evidence, but it is not the
-- terminal mailbox settlement. During the short owner-list refresh that follows
-- the message, do not misclassify the disappearing listing as UNRESOLVED.
local function hasRecentSaleConfirmation(name, quantity)
    local wanted = string.lower(tostring(name or ""))
    local wantedQty = tonumber(quantity) or 1
    local cutoff = now() - (15 * 60)

    for i = #(AZPCDB.transactions or {}), 1, -1 do
        local tx = AZPCDB.transactions[i]
        local at = tonumber(tx and tx.observedAt) or tonumber(tx and tx.timestamp) or 0
        if at > 1000000000000 then
            at = math.floor(at / 1000)
        end
        if at > 0 and at < cutoff then
            break
        end
        if tx and tx.kind == "sale_confirmed"
            and string.lower(tostring(tx.name or "")) == wanted
            and (tonumber(tx.quantity) or 1) == wantedQty then
            return true
        end
    end

    return false
end

local function mergedSnapshotForReconcile(pageSnapshot)
    local out = {
        timestamp = pageSnapshot and pageSnapshot.timestamp or now(),
        rows = {},
        counts = {},
        complete = pageSnapshot and pageSnapshot.complete == true or false,
        totalCount = pageSnapshot and tonumber(pageSnapshot.totalCount) or nil,
    }

    for _, row in ipairs(AZPCDB.ownedAuctions or {}) do
        table.insert(out.rows, row)
        local key = ownedAuctionKey(row)
        out.counts[key] = (out.counts[key] or 0) + 1
    end

    return out
end

local function reconcileOwnedAuctions(newSnapshot)
    if not newSnapshot then
        return
    end

    local mergedSnapshot = mergedSnapshotForReconcile(newSnapshot)

    if lastOwnedSnapshot then
        local disappeared = 0

        -- Only convert owner-list disappearances into ledger evidence when both
        -- snapshots are complete. Partial/paged owner lists are not trustworthy
        -- enough to close a position.
        local canResolveDisappearances = lastOwnedSnapshot.complete == true
            and mergedSnapshot.complete == true

        for key, oldCount in pairs(lastOwnedSnapshot.counts or {}) do
            local newCount = (mergedSnapshot.counts and mergedSnapshot.counts[key]) or 0
            if oldCount > newCount then
                local missing = oldCount - newCount
                disappeared = disappeared + missing

                if canResolveDisappearances then
                    local sample = nil
                    for _, oldRow in ipairs(lastOwnedSnapshot.rows or {}) do
                        if ownedAuctionKey(oldRow) == key then
                            sample = oldRow
                            break
                        end
                    end

                    if sample then
                        local disappearedQty = (tonumber(sample.count) or 1) * missing
                        if hasRecentSaleConfirmation(sample.name, disappearedQty) then
                            print("|cff00ff98AZPC|r: Sold listing left the owner list: "
                                .. tostring(sample.name or "auction item")
                                .. " x" .. tostring(disappearedQty)
                                .. ". SALE CONFIRMED; awaiting mailbox settlement for final proceeds and P/L.")
                        else
                            addTransaction({
                                kind = "listing_unresolved",
                                source = "OWNER_LIST_DISAPPEARED",
                                itemId = sample.itemId,
                                itemLink = sample.itemLink,
                                name = sample.name,
                                quantity = disappearedQty,
                                unitPrice = tonumber(sample.buyoutPerUnit) or 0,
                                totalPrice = (tonumber(sample.buyoutPrice) or 0) * missing,
                                status = "awaiting_mail_settlement",
                            })

                            print("|cffffcc00AZPC|r: Listing disappeared from the owner list without sale or mailbox evidence: "
                                .. tostring(sample.name or "auction item")
                                .. " x" .. tostring(disappearedQty)
                                .. ". Marked UNRESOLVED until settlement evidence is captured.")
                        end
                    end
                end
            end
        end

        AZPCDB.meta.lastOwnedDisappearCount = disappeared
    end

    confirmPendingSellFromOwned(mergedSnapshot)
    lastOwnedSnapshot = mergedSnapshot
end

local function probeOwnedAuctions()
    ensureDB()

    if type(GetNumAuctionItems) ~= "function" or type(GetAuctionItemInfo) ~= "function" then
        print("|cff00ff98AZPC|r: Owner probe unavailable: auction APIs missing.")
        return
    end

    local batchCount, totalCount = GetNumAuctionItems("owner")
    batchCount = tonumber(batchCount) or 0
    totalCount = tonumber(totalCount) or 0

    print("|cff00ff98AZPC|r OWNER PROBE")
    print("  GetNumAuctionItems(owner): batch=" .. tostring(batchCount)
        .. " total=" .. tostring(totalCount))

    local discovered = {}
    local consecutiveEmpty = 0
    local MAX_INDEX = 250
    local STOP_AFTER_EMPTY = 20

    for index = 1, MAX_INDEX do
        local name, texture, count, quality, canUse, level, levelColHeader,
              minBid, minIncrement, buyoutPrice, bidAmount, highBidder,
              bidderFullName, owner, ownerFullName, saleStatus, itemId,
              hasAllInfo = GetAuctionItemInfo("owner", index)

        if name then
            consecutiveEmpty = 0

            local itemLink = nil
            if type(GetAuctionItemLink) == "function" then
                itemLink = GetAuctionItemLink("owner", index)
            end

            if (not itemId) and itemLink then
                itemId = parseItemIdFromLink(itemLink)
            end

            table.insert(discovered, {
                index = index,
                name = name,
                itemId = itemId,
                count = tonumber(count) or 1,
                buyoutPrice = tonumber(buyoutPrice) or 0,
            })
        else
            consecutiveEmpty = consecutiveEmpty + 1

            if index > math.max(batchCount, totalCount) and
               consecutiveEmpty >= STOP_AFTER_EMPTY then
                break
            end
        end
    end

    AZPCDB.meta.ownerProbeBatch = batchCount
    AZPCDB.meta.ownerProbeTotal = totalCount
    AZPCDB.meta.ownerProbeDiscovered = #discovered
    AZPCDB.meta.ownerProbeAt = now()

    print("  Direct GetAuctionItemInfo(owner,index) rows found: "
        .. tostring(#discovered))

    if #discovered > totalCount then
        print("|cff00ff98AZPC|r: IMPORTANT: direct owner indexes exceed reported total.")
    elseif #discovered < totalCount then
        print("|cff00ff98AZPC|r: Direct rows are fewer than the reported total; paging/query state is involved.")
    else
        print("|cff00ff98AZPC|r: Direct rows equal the API-reported total.")
    end

    local firstExtra = nil
    for _, row in ipairs(discovered) do
        if row.index > totalCount then
            firstExtra = row
            break
        end
    end

    if firstExtra then
        print("|cff00ff98AZPC|r First row beyond reported total:")
        print("  index " .. tostring(firstExtra.index)
            .. " | " .. tostring(firstExtra.name)
            .. " | qty " .. tostring(firstExtra.count)
            .. " | buyout " .. tostring(firstExtra.buyoutPrice) .. "c")
    end

    local start = math.max(1, #discovered - 9)
    print("|cff00ff98AZPC|r Last directly visible owner rows:")
    for i = start, #discovered do
        local row = discovered[i]
        if row then
            print("  #" .. tostring(row.index)
                .. " " .. tostring(row.name)
                .. " | qty " .. tostring(row.count)
                .. " | ID " .. tostring(row.itemId or "?"))
        end
    end
end

local function printOwnedSummary()
    ensureDB()

    local captured = #(AZPCDB.ownedAuctions or {})
    local total = tonumber(AZPCDB.meta.ownedAuctionTotalReported) or captured
    local serverCount, pendingExtra, knownActive = azpcKnownActiveCount()

    print("|cff00ff98AZPC|r Blizzard owner list: "
        .. tostring(serverCount) .. " visible / " .. tostring(total) .. " reported")
    print("|cff00ff98AZPC|r AZPC known active auctions: "
        .. tostring(knownActive)
        .. " (" .. tostring(serverCount) .. " server + "
        .. tostring(pendingExtra) .. " recent unreconciled)")

    if pendingExtra > 0 then
        print("|cff00ff98AZPC|r: Blizzard owner list appears stale; recent auction-created acknowledgements are being retained until it catches up.")
    end

    local totalRows = #(AZPCDB.ownedAuctions or {})
    local showStart = math.max(1, totalRows - 4)
    for i = showStart, totalRows do
        local row = AZPCDB.ownedAuctions[i]
        if row then
            print("  SERVER | " .. tostring(row.name or ("Item " .. tostring(row.itemId or "?")))
                .. " | qty " .. tostring(row.count or "?")
                .. " | buyout/unit " .. tostring(row.buyoutPerUnit or 0) .. "c")
        end
    end

    local recentCount = #(AZPCDB.recentPostedAuctions or {})
    if recentCount > 0 then
        local recentStart = math.max(1, recentCount - 4)
        for i = recentStart, recentCount do
            local row = AZPCDB.recentPostedAuctions[i]
            if row then
                local expected = tonumber(row.numStacks) or 1
                local visible = serverOwnedCountForRecent(row)
                local missing = math.max(0, expected - visible)
                if missing > 0 then
                    print("  AZPC PENDING | " .. tostring(row.name or ("Item " .. tostring(row.itemId or "?")))
                        .. " | stacks not yet in server list " .. tostring(missing)
                        .. " | buyout/unit " .. tostring(row.buyoutPerUnit or 0) .. "c")
                end
            end
        end
    end
end

local function transactionSummary()
    ensureDB()

    local total = #AZPCDB.transactions
    local buyAttempts = 0
    local confirmedPurchases = 0
    local bidAttempts = 0
    local sellPosts = 0
    local sellCreated = 0
    local sellPostedConfirmed = 0
    local salesConfirmed = 0

    for _, tx in ipairs(AZPCDB.transactions) do
        if tx.kind == "buyout_attempt" then
            buyAttempts = buyAttempts + 1
        elseif tx.kind == "purchase_confirmed" then
            confirmedPurchases = confirmedPurchases + 1
        elseif tx.kind == "bid_attempt" then
            bidAttempts = bidAttempts + 1
        elseif tx.kind == "sell_post_attempt" then
            sellPosts = sellPosts + 1
        elseif tx.kind == "sell_posted" then
            sellCreated = sellCreated + 1
        elseif tx.kind == "sell_posted_confirmed" then
            sellPostedConfirmed = sellPostedConfirmed + 1
        elseif tx.kind == "sale_confirmed" then
            salesConfirmed = salesConfirmed + 1
        end
    end

    print("|cff00ff98AZPC|r Personal AH ledger:")
    print("  Total records: " .. tostring(total))
    print("  Buyout attempts: " .. tostring(buyAttempts)
        .. " | Confirmed purchases: " .. tostring(confirmedPurchases))
    print("  Bid attempts: " .. tostring(bidAttempts))
    print("  Sell post attempts: " .. tostring(sellPosts)
        .. " | Owned-list post confirmations: " .. tostring(sellPostedConfirmed))
    print("  Confirmed sales: " .. tostring(salesConfirmed)
        .. " | Legacy auction-created confirmations: " .. tostring(sellCreated))

    if total > 0 then
        local start = math.max(1, total - 4)
        print("|cff00ff98AZPC|r Last " .. tostring(total - start + 1) .. " records:")
        for i = start, total do
            local tx = AZPCDB.transactions[i]
            local label = tostring(tx.kind or "unknown")
            local name = tostring(tx.name or ("Item " .. tostring(tx.itemId or "?")))
            local qty = tostring(tx.quantity or tx.stackSize or "?")
            local price = tostring(tx.unitPrice or tx.buyoutPerUnit or tx.bidPerUnit or "?")
            print("  " .. label .. " | " .. name .. " | qty " .. qty .. " | unit " .. price .. "c")
        end
    end
end


local function trimPurchaseDiagnostics()
    ensureDB()
    while #AZPCDB.purchaseDiagnostics > 250 do
        table.remove(AZPCDB.purchaseDiagnostics, 1)
    end
end

local function addPurchaseDiagnostic(kind, message, extra)
    ensureDB()

    local row = {
        timestamp = now(),
        kind = kind,
        message = message,
        character = AZPCDB.meta.character,
        realm = AZPCDB.meta.realm,
        faction = AZPCDB.meta.faction,
    }

    if type(extra) == "table" then
        for k, v in pairs(extra) do
            row[k] = v
        end
    end

    table.insert(AZPCDB.purchaseDiagnostics, row)
    AZPCDB.meta.lastPurchaseDiagnostic = row.timestamp
    dirtySinceFlush = true
    trimPurchaseDiagnostics()
end

local function prunePendingBuys()
    local cutoff = now() - purchaseProbeWindowSeconds
    local kept = {}

    for _, row in ipairs(pendingBuys or {}) do
        if tonumber(row.timestamp or 0) >= cutoff then
            table.insert(kept, row)
        end
    end

    pendingBuys = kept
end

local function pendingBuyActive()
    prunePendingBuys()
    return #pendingBuys > 0
end

local function startPurchaseProbe(entry)
    prunePendingBuys()

    local row = {
        timestamp = entry.timestamp or now(),
        itemId = entry.itemId,
        name = entry.name,
        quantity = entry.quantity,
        totalPrice = entry.totalPrice,
        unitPrice = entry.unitPrice,
        owner = entry.owner,
        auctionIndex = entry.auctionIndex,
        accepted = false,
        acceptedAt = nil,
    }

    table.insert(pendingBuys, row)

    print("|cff00ff98AZPC|r: Purchase confirmation queued for "
        .. tostring(entry.name or "auction item")
        .. " | qty " .. tostring(entry.quantity or "?")
        .. " | unit " .. tostring(entry.unitPrice or "?") .. "c"
        .. " | pending confirmations: " .. tostring(#pendingBuys))
end

local function normalizePurchaseItemName(name)
    local text = tostring(name or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return string.lower(text)
end

local function acceptOldestPendingBuy()
    prunePendingBuys()

    for _, row in ipairs(pendingBuys) do
        if not row.accepted then
            row.accepted = true
            row.acceptedAt = now()

            addPurchaseDiagnostic("bid_accepted", "Bid accepted.", {
                itemId = row.itemId,
                name = row.name,
                quantity = row.quantity,
                totalPrice = row.totalPrice,
                unitPrice = row.unitPrice,
                pendingCount = #pendingBuys,
            })

            print("|cff00ff98AZPC|r: Purchase queue accepted "
                .. tostring(row.name or "auction item")
                .. " | qty " .. tostring(row.quantity or "?")
                .. " | unit " .. tostring(row.unitPrice or "?") .. "c")
            return true
        end
    end

    return false
end

local function confirmPendingPurchaseFromSystemMessage(msg)
    prunePendingBuys()
    if #pendingBuys <= 0 then
        return false
    end

    local text = tostring(msg or "")
    local wonName = string.match(text, "^You won an auction for (.+)%.?$")
    if not wonName then
        return false
    end

    local actual = normalizePurchaseItemName(wonName)
    local matchIndex = nil

    -- Strong path: oldest ACCEPTED pending buy with the matching item name.
    for i, row in ipairs(pendingBuys) do
        local expected = normalizePurchaseItemName(row.name)
        if row.accepted and expected ~= "" and expected == actual then
            matchIndex = i
            break
        end
    end

    -- Safe fallback: if Blizzard skipped/ordered Bid accepted differently,
    -- consume the oldest matching item rather than losing confirmation.
    if not matchIndex then
        for i, row in ipairs(pendingBuys) do
            local expected = normalizePurchaseItemName(row.name)
            if expected ~= "" and expected == actual then
                matchIndex = i
                break
            end
        end
    end

    if not matchIndex then
        addPurchaseDiagnostic("confirmation_unmatched", text, {
            wonName = wonName,
            pendingCount = #pendingBuys,
        })

        print("|cff00ff98AZPC|r: Purchase confirmation had no matching pending buy: "
            .. tostring(wonName))
        return false
    end

    local pendingBuy = table.remove(pendingBuys, matchIndex)

    addTransaction({
        kind = "purchase_confirmed",
        source = "CHAT_MSG_SYSTEM",
        itemId = pendingBuy.itemId,
        name = pendingBuy.name or wonName,
        quantity = pendingBuy.quantity,
        totalPrice = pendingBuy.totalPrice,
        unitPrice = pendingBuy.unitPrice,
        owner = pendingBuy.owner,
        auctionIndex = pendingBuy.auctionIndex,
        status = "won_confirmed",
        timestamp = now(),
    })

    addPurchaseDiagnostic("purchase_confirmed", text, {
        itemId = pendingBuy.itemId,
        name = pendingBuy.name or wonName,
        quantity = pendingBuy.quantity,
        totalPrice = pendingBuy.totalPrice,
        unitPrice = pendingBuy.unitPrice,
        accepted = pendingBuy.accepted and true or false,
        pendingRemaining = #pendingBuys,
    })

    print("|cff00ff98AZPC|r: PURCHASE CONFIRMED: "
        .. tostring(pendingBuy.name or wonName)
        .. " x" .. tostring(pendingBuy.quantity or 1)
        .. " @ " .. tostring(pendingBuy.unitPrice or "?") .. "c/unit"
        .. " | accepted: " .. tostring(pendingBuy.accepted and "YES" or "FALLBACK")
        .. " | pending confirmations: " .. tostring(#pendingBuys))

    return true
end

local function recordPurchaseProbeSystemMessage(msg)
    if not pendingBuyActive() then
        return
    end

    local text = tostring(msg or "")

    -- First bind Blizzard's generic acceptance message to the oldest queued buy.
    if text == "Bid accepted." then
        acceptOldestPendingBuy()
        return
    end

    if confirmPendingPurchaseFromSystemMessage(text) then
        return
    end

    if text == "" then
        return
    end

    if purchaseProbeMessages[text] then
        return
    end
    purchaseProbeMessages[text] = true

    local oldest = pendingBuys[1]

    addPurchaseDiagnostic("system_message", text, {
        itemId = oldest and oldest.itemId or nil,
        name = oldest and oldest.name or nil,
        quantity = oldest and oldest.quantity or nil,
        totalPrice = oldest and oldest.totalPrice or nil,
        unitPrice = oldest and oldest.unitPrice or nil,
        pendingCount = #pendingBuys,
    })

    print("|cff00ff98AZPC|r PURCHASE PROBE SYSTEM: " .. text)
end

local function recordPurchaseProbeEvent(eventName)
    if not pendingBuyActive() then
        return
    end

    local oldest = pendingBuys[1]

    addPurchaseDiagnostic("event", eventName, {
        itemId = oldest and oldest.itemId or nil,
        name = oldest and oldest.name or nil,
        quantity = oldest and oldest.quantity or nil,
        totalPrice = oldest and oldest.totalPrice or nil,
        unitPrice = oldest and oldest.unitPrice or nil,
        pendingCount = #pendingBuys,
    })

    print("|cff00ff98AZPC|r PURCHASE PROBE EVENT: "
        .. tostring(eventName)
        .. " | pending confirmations: " .. tostring(#pendingBuys))
end

local function printPurchaseDiagnostics()
    ensureDB()

    local total = #AZPCDB.purchaseDiagnostics
    print("|cff00ff98AZPC|r Purchase diagnostics: " .. tostring(total))

    if total <= 0 then
        print("  No purchase probe evidence recorded yet.")
        return
    end

    local start = math.max(1, total - 11)
    for i = start, total do
        local row = AZPCDB.purchaseDiagnostics[i]
        if row then
            print("  " .. tostring(row.kind or "?")
                .. " | " .. tostring(row.name or "?")
                .. " | qty " .. tostring(row.quantity or "?")
                .. " | unit " .. tostring(row.unitPrice or "?") .. "c"
                .. " | " .. tostring(row.message or "?"))
        end
    end
end


local function probeAuctionDeposit(runTime, stackSize, numStacks, item)
    -- First prefer Blizzard's own deposit calculator. On some Classic clients the
    -- sell slot is already clearing by the time the PostAuction secure hook runs,
    -- so a zero result is not trusted for an item with a positive vendor value.
    local candidates = { "GetAuctionDeposit", "CalculateAuctionDeposit" }
    for _, functionName in ipairs(candidates) do
        local fn = _G and _G[functionName] or nil
        if type(fn) == "function" then
            local ok, value = pcall(fn, runTime, stackSize, numStacks)
            value = ok and tonumber(value) or nil
            if value and value > 0 then
                return math.floor(value + 0.5), functionName
            end
        end
    end

    -- Deterministic Classic/TBC faction-AH fallback: 15% of vendor value per
    -- 12 hours, multiplied by the total quantity posted. We only use it when
    -- GetItemInfo supplied an actual positive vendor sell price.
    local vendor = item and tonumber(item.vendorSellPrice) or nil
    local stacks = tonumber(numStacks) or 1
    local perStack = tonumber(stackSize) or 1
    local duration = tonumber(runTime)
    if vendor and vendor > 0 and stacks > 0 and perStack > 0 and duration then
        local durationHours = duration
        if duration > 100 then
            durationHours = duration / 60
        elseif duration <= 3 then
            durationHours = duration * 12
        end
        local multiplier = durationHours / 12
        if multiplier > 0 then
            local value = vendor * perStack * stacks * 0.15 * multiplier
            return math.floor(value + 0.5), "VENDOR_FORMULA_15PCT"
        end
    end

    return nil, nil
end

local function installAuctionHooks()
    if hookInstalled then
        return
    end

    if type(hooksecurefunc) ~= "function" then
        return
    end

    if type(PlaceAuctionBid) == "function" then
        hooksecurefunc("PlaceAuctionBid", function(listType, index, bid)
            if not AH_OPEN then
                return
            end

            local name, texture, count, quality, canUse, level, levelColHeader,
                  minBid, minIncrement, buyoutPrice, bidAmount, highBidder,
                  bidderFullName, owner, ownerFullName, saleStatus, itemId,
                  hasAllInfo = GetAuctionItemInfo(listType, index)

            if not name or not itemId then
                return
            end

            count = tonumber(count) or 1
            local amount = tonumber(bid) or 0
            local buyout = tonumber(buyoutPrice) or 0
            local kind = (buyout > 0 and amount >= buyout) and "buyout_attempt" or "bid_attempt"

            local txEntry = {
                kind = kind,
                source = "PlaceAuctionBid",
                itemId = itemId,
                name = name,
                quantity = count,
                totalPrice = amount,
                unitPrice = count > 0 and math.floor(amount / count) or amount,
                listedBuyout = buyout,
                listedBuyoutPerUnit = (buyout > 0 and count > 0) and math.floor(buyout / count) or 0,
                owner = owner,
                auctionIndex = index,
                listType = listType,
                status = "attempted",
                timestamp = now(),
            }

            addTransaction(txEntry)

            if kind == "buyout_attempt" then
                startPurchaseProbe(txEntry)
            end

            print("|cff00ff98AZPC|r: Personal ledger recorded "
                .. (kind == "buyout_attempt" and "buyout" or "bid")
                .. " attempt for " .. tostring(name) .. ".")
        end)
    end

    if type(PostAuction) == "function" then
        hooksecurefunc("PostAuction", function(minBid, buyoutPrice, runTime, stackSize, numStacks, warningAcknowledged)
            -- Try one last refresh, but cacheSellItem() preserves the earlier
            -- good identity if the sell slot has already begun clearing.
            cacheSellItem()

            local item = sellItemCache or {}
            local stacks = tonumber(numStacks) or 1
            local perStack = tonumber(stackSize) or tonumber(item.stackCount) or tonumber(item.count) or 1
            local totalQty = math.max(0, stacks * perStack)
            local buyout = tonumber(buyoutPrice) or 0
            local bid = tonumber(minBid) or 0
            local auctionDeposit, auctionDepositSource = probeAuctionDeposit(runTime, perStack, stacks, item)

            pendingSell = {
                timestamp = now(),
                itemId = item.itemId,
                itemLink = item.itemLink,
                name = item.name,
                quantity = totalQty,
                stackSize = perStack,
                numStacks = stacks,
                totalBuyoutPerStack = buyout,
                buyoutPerUnit = (buyout > 0 and perStack > 0) and math.floor(buyout / perStack) or 0,
                minBidPerStack = bid,
                bidPerUnit = (bid > 0 and perStack > 0) and math.floor(bid / perStack) or 0,
                runTime = runTime,
                auctionDeposit = auctionDeposit,
                auctionDepositPerStack = (auctionDeposit and stacks > 0) and math.floor(auctionDeposit / stacks) or nil,
                auctionDepositSource = auctionDepositSource,
            }

            addTransaction({
                kind = "sell_post_attempt",
                source = "PostAuction",
                itemId = pendingSell.itemId,
                itemLink = pendingSell.itemLink,
                name = pendingSell.name,
                quantity = pendingSell.quantity,
                stackSize = pendingSell.stackSize,
                numStacks = pendingSell.numStacks,
                totalPrice = pendingSell.totalBuyoutPerStack,
                unitPrice = pendingSell.buyoutPerUnit,
                minBidPerStack = pendingSell.minBidPerStack,
                runTime = pendingSell.runTime,
                auctionDeposit = pendingSell.auctionDeposit,
                auctionDepositPerStack = pendingSell.auctionDepositPerStack,
                auctionDepositSource = pendingSell.auctionDepositSource,
                status = "attempted",
            })

            print("|cff00ff98AZPC|r: Personal ledger recorded sell-post attempt for "
                .. tostring(pendingSell.name or ("Item " .. tostring(pendingSell.itemId or "?"))) .. ".")

            -- The identity is now safely stored in pendingSell/transactions.
            -- Allow the next sell-slot item to build a fresh cache.
            sellItemCache = nil
        end)
    end

    hookInstalled = true
end

local function makeFingerprint(rows)
    if #rows == 0 then
        return "empty"
    end

    local first = rows[1]
    local last = rows[#rows]
    return table.concat({
        tostring(#rows),
        tostring(first.itemId or 0),
        tostring(first.buyoutPrice or 0),
        tostring(first.count or 0),
        tostring(last.itemId or 0),
        tostring(last.buyoutPrice or 0),
        tostring(last.count or 0),
    }, ":")
end

local function captureBrowseResults(source)
    ensureDB()
    updateCharacterMeta()

    if not AH_OPEN then
        return 0, "Auction House is not open."
    end

    if type(GetNumAuctionItems) ~= "function" or type(GetAuctionItemInfo) ~= "function" then
        return 0, "Classic Auction House API is unavailable on this client."
    end

    local batchCount, totalCount = GetNumAuctionItems("list")
    batchCount = tonumber(batchCount) or 0
    totalCount = tonumber(totalCount) or batchCount

    if batchCount <= 0 then
        return 0, "No browse results are currently loaded."
    end

    local capturedAt = now()
    local rows = {}

    for index = 1, batchCount do
        local name, texture, count, quality, canUse, level, levelColHeader,
              minBid, minIncrement, buyoutPrice, bidAmount, highBidder,
              bidderFullName, owner, ownerFullName, saleStatus, itemId,
              hasAllInfo = GetAuctionItemInfo("list", index)

        if name and itemId then
            count = tonumber(count) or 1
            buyoutPrice = tonumber(buyoutPrice) or 0
            minBid = tonumber(minBid) or 0
            bidAmount = tonumber(bidAmount) or 0

            local timeLeft = nil
            if type(GetAuctionItemTimeLeft) == "function" then
                timeLeft = GetAuctionItemTimeLeft("list", index)
            end

            local itemLink = nil
            if type(GetAuctionItemLink) == "function" then
                itemLink = GetAuctionItemLink("list", index)
            end

            local row = {
                kind = "auction_listing",
                timestamp = capturedAt,
                source = source or "browse_update",

                character = AZPCDB.meta.character,
                realm = AZPCDB.meta.realm,
                faction = AZPCDB.meta.faction,

                index = index,
                itemId = itemId,
                itemLink = itemLink,
                name = name,
                count = count,
                quality = quality,
                requiredLevel = level,
                levelType = levelColHeader,

                minBid = minBid,
                minBidPerUnit = count > 0 and math.floor(minBid / count) or 0,
                minIncrement = tonumber(minIncrement) or 0,
                buyoutPrice = buyoutPrice,
                buyoutPerUnit = (buyoutPrice > 0 and count > 0) and math.floor(buyoutPrice / count) or 0,
                bidAmount = bidAmount,
                bidPerUnit = (bidAmount > 0 and count > 0) and math.floor(bidAmount / count) or 0,

                owner = owner,
                ownerFullName = ownerFullName,
                timeLeft = timeLeft,
                hasAllInfo = hasAllInfo and true or false,
            }

            table.insert(rows, row)
        end
    end

    local fingerprint = makeFingerprint(rows)

    -- AUCTION_ITEM_LIST_UPDATE can fire more than once for the same page as
    -- item/name information resolves. Avoid storing identical snapshots.
    if source == "automatic" and fingerprint == lastSnapshotFingerprint then
        return 0, "Duplicate snapshot ignored."
    end
    lastSnapshotFingerprint = fingerprint

    for _, row in ipairs(rows) do
        table.insert(AZPCDB.observations, row)
    end

    table.insert(AZPCDB.snapshots, {
        timestamp = capturedAt,
        source = source or "browse_update",
        rowCount = #rows,
        batchCount = batchCount,
        totalCount = totalCount,
        fingerprint = fingerprint,
    })

    AZPCDB.meta.lastWrite = capturedAt
    AZPCDB.meta.lastCaptureCount = #rows
    AZPCDB.meta.lastAuctionTotal = totalCount
    dirtySinceFlush = true

    trimObservations()

    return #rows, nil
end

local function mailExpiryMinute(daysLeft)
    local d = tonumber(daysLeft)
    if not d then
        return 0
    end

    -- GetInboxHeaderInfo daysLeft is a countdown and therefore changes every
    -- refresh. now() + daysLeft reconstructs the approximately fixed expiry
    -- timestamp. Round to the nearest minute to absorb small API jitter.
    local estimatedExpiry = now() + (d * 86400)
    return math.floor((estimatedExpiry + 30) / 60)
end

local function mailboxFingerprint(row)
    return table.concat({
        tostring(row.sender or ""),
        tostring(row.subject or ""),
        tostring(row.money or 0),
        tostring(row.mailExpiryMinute or 0),
        tostring(row.itemId or 0),
        tostring(row.itemCount or 0),
        tostring(row.invoiceType or ""),
        tostring(row.invoiceItemName or ""),
        tostring(row.invoiceBid or 0),
        tostring(row.invoiceBuyout or 0),
        tostring(row.invoiceDeposit or 0),
        tostring(row.invoiceConsignment or 0),
    }, "|")
end
local function captureMailbox(source)
    ensureDB()
    updateCharacterMeta()

    if type(GetInboxNumItems) ~= "function" or type(GetInboxHeaderInfo) ~= "function" then
        return 0, "Mailbox API unavailable on this client."
    end

    local numItems, totalItems = GetInboxNumItems()
    numItems = tonumber(numItems) or 0
    totalItems = tonumber(totalItems) or numItems
    local captured = 0
    local seen = {}

    for _, old in ipairs(AZPCDB.mailboxCaptures or {}) do
        if old.fingerprint then seen[old.fingerprint] = true end
    end

    for index = 1, numItems do
        local packageIcon, stationeryIcon, sender, subject, money, CODAmount,
              daysLeft, hasItem, wasRead, wasReturned, textCreated,
              canReply, isGM = GetInboxHeaderInfo(index)

        if sender or subject then
            local row = {
                timestamp = now(),
                source = source or "mailbox",
                inboxIndex = index,
                character = AZPCDB.meta.character,
                realm = AZPCDB.meta.realm,
                faction = AZPCDB.meta.faction,
                sender = sender,
                subject = subject,
                money = tonumber(money) or 0,
                CODAmount = tonumber(CODAmount) or 0,
                daysLeft = tonumber(daysLeft),
                mailExpiryMinute = mailExpiryMinute(daysLeft),
                hasItem = hasItem and true or false,
                wasRead = wasRead and true or false,
                wasReturned = wasReturned and true or false,
                canReply = canReply and true or false,
                isGM = isGM and true or false,
            }

            if type(GetInboxItem) == "function" and hasItem then
                local itemName, itemId, itemTexture, itemCount, quality, canUse = GetInboxItem(index, 1)
                row.itemName = itemName
                row.itemId = tonumber(itemId)
                row.itemCount = tonumber(itemCount) or 1
                row.itemQuality = quality
                if type(GetInboxItemLink) == "function" then
                    row.itemLink = GetInboxItemLink(index, 1)
                    row.itemId = row.itemId or parseItemIdFromLink(row.itemLink)
                end
            end

            if type(GetInboxInvoiceInfo) == "function" then
                local invoiceType, itemName, playerName, bid, buyout, deposit,
                      consignment = GetInboxInvoiceInfo(index)
                row.invoiceType = invoiceType
                row.invoiceItemName = itemName
                row.invoiceBuyer = playerName
                row.invoiceBid = tonumber(bid) or 0
                row.invoiceBuyout = tonumber(buyout) or 0
                row.invoiceDeposit = tonumber(deposit) or 0
                row.invoiceConsignment = tonumber(consignment) or 0
            end

            row.fingerprint = mailboxFingerprint(row)
            if not seen[row.fingerprint] then
                table.insert(AZPCDB.mailboxCaptures, row)
                seen[row.fingerprint] = true
                captured = captured + 1
                dirtySinceFlush = true
            end
        end
    end

    while #AZPCDB.mailboxCaptures > 500 do
        table.remove(AZPCDB.mailboxCaptures, 1)
    end

    AZPCDB.meta.lastMailboxCapture = now()
    AZPCDB.meta.lastMailboxVisible = numItems
    AZPCDB.meta.lastMailboxTotal = totalItems
    AZPCDB.meta.lastMailboxNewRows = captured
    return captured, nil
end

local function normalizeAuctionMail(index)
    if type(GetInboxHeaderInfo) ~= "function" then
        return nil
    end

    local packageIcon, stationeryIcon, sender, subject, money, CODAmount,
          daysLeft, hasItem, wasRead, wasReturned, textCreated,
          canReply, isGM = GetInboxHeaderInfo(index)

    sender = tostring(sender or "")
    subject = tostring(subject or "")
    if sender == "" or subject == "" or subject == "Retrieving data" then
        return nil
    end

    local soldName = string.match(subject, "^Auction successful:%s*(.+)$")
    local expiredName = string.match(subject, "^Auction expired:%s*(.+)$")
    if not soldName and not expiredName then
        return nil
    end

    local row = {
        observedAt = now(),
        inboxIndex = index,
        sender = sender,
        subject = subject,
        daysLeft = tonumber(daysLeft),
        mailExpiryMinute = mailExpiryMinute(daysLeft),
        money = tonumber(money) or 0,
        character = AZPCDB.meta.character,
        realm = AZPCDB.meta.realm,
        faction = AZPCDB.meta.faction,
    }

    if soldName then
        if type(GetInboxInvoiceInfo) ~= "function" then
            return nil
        end
        local invoiceType, itemName, playerName, bid, buyout, deposit,
              consignment = GetInboxInvoiceInfo(index)
        if tostring(invoiceType or "") ~= "seller" or not itemName then
            return nil
        end

        row.outcome = "sold"
        row.name = itemName or soldName
        row.buyer = playerName
        row.bid = tonumber(bid) or 0
        row.buyout = tonumber(buyout) or 0
        row.deposit = tonumber(deposit) or 0
        row.auctionHouseCut = tonumber(consignment) or 0
        row.mailPayout = tonumber(money) or 0
        row.netSaleAfterCut = math.max(0, row.buyout - row.auctionHouseCut)
        row.depositReturned = row.deposit
        row.depositLoss = 0

        -- Seller invoice payloads resolve in stages on this Classic client.
        -- Do not create a settlement from the early payout-only state; wait
        -- until both the sale price and the actual mailbox payout are present.
        if row.buyout <= 0 or row.mailPayout <= 0 then
            return nil
        end
    else
        if not hasItem or type(GetInboxItem) ~= "function" then
            return nil
        end
        local itemName, itemId, itemTexture, itemCount, quality, canUse = GetInboxItem(index, 1)
        if not itemName then
            return nil
        end

        row.outcome = "expired"
        row.name = itemName or expiredName
        row.itemId = tonumber(itemId)
        row.returnedQuantity = tonumber(itemCount) or 1
        row.itemQuality = quality
        if type(GetInboxItemLink) == "function" then
            row.itemLink = GetInboxItemLink(index, 1)
            row.itemId = row.itemId or parseItemIdFromLink(row.itemLink)
        end
        row.mailPayout = 0
    end

    return row
end

local function settlementBaseKey(row)
    -- Canonical AUCTION OUTCOME identity, not physical-mail identity.
    -- Deliberately excludes inbox index, daysLeft/expiry estimate and buyer,
    -- because those fields can change while Blizzard finishes loading mail.
    -- Identical mails are represented by the count of this key in the snapshot.
    return table.concat({
        tostring(row.outcome or ""),
        tostring(row.name or ""),
        tostring(row.mailPayout or 0),
        tostring(row.buyout or 0),
        tostring(row.deposit or 0),
        tostring(row.auctionHouseCut or 0),
        tostring(row.returnedQuantity or 0),
        tostring(row.itemId or 0),
    }, "|")
end

local function listingSettlementCapacity(tx)
    local stacks = tonumber(tx and tx.numStacks) or 1
    if stacks < 1 then stacks = 1 end
    return stacks
end

local function listingMatchesMail(tx, row)
    if not tx or not row then
        return false
    end
    if tx.kind ~= "sell_posted_confirmed" and tx.kind ~= "sell_post_attempt" and tx.kind ~= "sell_posted" then
        return false
    end

    local consumed = tonumber(tx.mailSettlementConsumedCount) or 0
    if consumed >= listingSettlementCapacity(tx) then
        return false
    end

    if tostring(tx.name or "") ~= tostring(row.name or "") then
        return false
    end

    if row.outcome == "sold" and row.buyout and row.buyout > 0 then
        local listedTotal = tonumber(tx.totalPrice) or tonumber(tx.totalBuyoutPerStack) or 0
        if listedTotal > 0 and listedTotal ~= tonumber(row.buyout) then
            return false
        end
    end

    if row.outcome == "expired" and row.returnedQuantity then
        local stackQty = tonumber(tx.stackSize) or tonumber(tx.quantity)
        if stackQty and stackQty ~= tonumber(row.returnedQuantity) then
            return false
        end
    end

    return true
end

local function matchSettlementToListing(row)
    for i = #AZPCDB.transactions, 1, -1 do
        local tx = AZPCDB.transactions[i]
        if listingMatchesMail(tx, row) then
            tx.mailSettlementConsumedCount = (tonumber(tx.mailSettlementConsumedCount) or 0) + 1
            tx.mailSettlementConsumed = tx.mailSettlementConsumedCount >= listingSettlementCapacity(tx)
            tx.mailSettlementConsumedAt = now()
            tx.mailSettlementOutcome = row.outcome
            dirtySinceFlush = true
            return tx, i
        end
    end
    return nil, nil
end

local function settlementMatchesPurchase(tx, row)
    if not tx or not row or tx.kind ~= "purchase_confirmed" then
        return false
    end

    -- Cost basis must come from this same character/market context and cannot
    -- come from a purchase that happened after the settlement was recorded.
    if tx.character and row.character and tostring(tx.character) ~= tostring(row.character) then
        return false
    end
    if tx.realm and row.realm and tostring(tx.realm) ~= tostring(row.realm) then
        return false
    end
    if tx.faction and row.faction and tostring(tx.faction) ~= tostring(row.faction) then
        return false
    end
    if tx.timestamp and row.timestamp and tonumber(tx.timestamp) > tonumber(row.timestamp) then
        return false
    end

    local txId = tonumber(tx.itemId)
    local rowId = tonumber(row.itemId)
    if txId and rowId and txId > 0 and rowId > 0 then
        return txId == rowId
    end

    return tostring(tx.name or "") ~= "" and tostring(tx.name or "") == tostring(row.name or "")
end

local function purchaseUnitCost(tx)
    local qty = tonumber(tx and tx.quantity) or 0
    local total = tonumber(tx and tx.totalPrice)
    if qty > 0 and total and total >= 0 then
        return total / qty
    end
    local unit = tonumber(tx and tx.unitPrice)
    if unit and unit >= 0 then
        return unit
    end
    return nil
end

local function settlementListing(row)
    local index = tonumber(row and row.matchedListingIndex)
    if not index or index < 1 then
        return nil
    end
    local tx = AZPCDB.transactions and AZPCDB.transactions[index] or nil
    if not tx then return nil end
    if tx.kind ~= "sell_posted_confirmed" and tx.kind ~= "sell_post_attempt" and tx.kind ~= "sell_posted" then
        return nil
    end
    return tx
end

local function resolveVendorSellPrice(row, listing)
    if type(GetItemInfo) ~= "function" then return nil end

    local candidates = {
        row and row.itemLink,
        row and row.itemId,
        listing and listing.itemLink,
        listing and listing.itemId,
        row and row.name,
        listing and listing.name,
    }

    for _, candidate in ipairs(candidates) do
        if candidate then
            local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(candidate)
            sellPrice = tonumber(sellPrice)
            if sellPrice and sellPrice > 0 then
                return sellPrice
            end
        end
    end
    return nil
end

local function listingDurationMultiplier(runTime)
    local duration = tonumber(runTime)
    if not duration then return nil end

    local hours = duration
    if duration > 100 then
        hours = duration / 60
    elseif duration <= 3 then
        hours = duration * 12
    end
    if hours <= 0 then return nil end
    return hours / 12
end

local function repairExpiredSettlementDeposit(row)
    if not row or row.outcome ~= "expired" then return false end
    if row.depositKnown and row.depositLoss ~= nil then return false end

    local listing = settlementListing(row)
    if not listing then return false end

    local perStack = tonumber(listing.auctionDepositPerStack)
    if (not perStack or perStack <= 0) then
        local totalDeposit = tonumber(listing.auctionDeposit)
        local stacks = math.max(1, tonumber(listing.numStacks) or 1)
        if totalDeposit and totalDeposit > 0 then
            perStack = math.floor((totalDeposit / stacks) + 0.5)
        end
    end

    local source = listing.auctionDepositSource
    if not perStack or perStack <= 0 then
        -- Historical listings created before deposit capture can still be repaired
        -- exactly enough for faction AH accounting from the listing duration,
        -- stack quantity and the item's vendor sell price. Never invent a value
        -- when one of those inputs is unavailable.
        local vendor = resolveVendorSellPrice(row, listing)
        local stackQty = tonumber(listing.stackSize) or tonumber(row.returnedQuantity) or tonumber(listing.quantity)
        local multiplier = listingDurationMultiplier(listing.runTime)
        if vendor and stackQty and stackQty > 0 and multiplier and multiplier > 0 then
            perStack = math.floor((vendor * stackQty * 0.15 * multiplier) + 0.5)
            source = "HISTORICAL_VENDOR_FORMULA_15PCT"
        end
    end

    if perStack and perStack > 0 then
        row.deposit = perStack
        row.depositLoss = perStack
        row.depositKnown = true
        row.depositSource = source or "LISTING_REPAIR"
        return true
    end

    return false
end

local function soldSettlementQuantity(row)
    if not row then return 1 end

    -- A seller invoice represents ONE auction/stack, even when PostAuction()
    -- created many identical stacks in one call. The posting transaction's
    -- quantity is the whole batch (stackSize * numStacks), so using it here
    -- would multiply the basis consumed by every individual sale mail.
    local listing = settlementListing(row)
    if listing then
        local stackSize = tonumber(listing.stackSize)
        if stackSize and stackSize > 0 then
            return math.max(1, math.floor(stackSize + 0.5))
        end

        local totalQty = tonumber(listing.quantity)
        local stacks = tonumber(listing.numStacks)
        if totalQty and totalQty > 0 and stacks and stacks > 0 then
            local perStack = totalQty / stacks
            if perStack > 0 then
                return math.max(1, math.floor(perStack + 0.5))
            end
        end
    end

    local explicit = tonumber(row.saleQuantity) or tonumber(row.listingStackSize)
    if explicit and explicit > 0 then
        return math.max(1, math.floor(explicit + 0.5))
    end

    -- Old unmatched seller mails cannot safely infer quantity from the batch
    -- total. One is the conservative fallback; unknown historical basis remains
    -- unknown rather than charging an entire posting batch to one sale.
    return 1
end

local function applyRealizedPnl(row)
    if not row then return end

    if row.outcome == "expired" then
        repairExpiredSettlementDeposit(row)
    end

    row.costBasis = nil
    row.costBasisKnown = false
    row.costBasisQuantity = 0
    row.costBasisMissingQuantity = 0
    row.netProceeds = nil
    row.realizedProfit = nil
    row.realizedProfitKnown = false

    if row.outcome == "expired" then
        if row.depositKnown and row.depositLoss ~= nil then
            row.realizedProfit = -math.abs(tonumber(row.depositLoss) or 0)
            row.realizedProfitKnown = true
            row.pnlType = "deposit_loss"
        else
            row.pnlType = "deposit_loss_unknown"
        end
        return
    end

    if row.outcome ~= "sold" then
        return
    end

    local qtyNeeded = soldSettlementQuantity(row)
    row.saleQuantity = qtyNeeded
    if qtyNeeded < 1 then qtyNeeded = 1 end
    local remaining = qtyNeeded
    local basis = 0

    for _, tx in ipairs(AZPCDB.transactions or {}) do
        if remaining <= 0 then break end
        if settlementMatchesPurchase(tx, row) then
            local purchasedQty = tonumber(tx.quantity) or 0
            local consumedQty = tonumber(tx.pnlConsumedQuantity) or 0
            local available = math.max(0, purchasedQty - consumedQty)
            if available > 0 then
                local unitCost = purchaseUnitCost(tx)
                if unitCost then
                    local take = math.min(remaining, available)
                    basis = basis + (unitCost * take)
                    tx.pnlConsumedQuantity = consumedQty + take
                    tx.pnlConsumedAt = now()
                    remaining = remaining - take
                end
            end
        end
    end

    row.costBasisQuantity = qtyNeeded - remaining
    row.costBasisMissingQuantity = remaining
    row.netProceeds = math.max(0, (tonumber(row.buyout) or 0) - (tonumber(row.auctionHouseCut) or 0))

    if remaining <= 0 then
        row.costBasis = math.floor(basis + 0.5)
        row.costBasisKnown = true
        row.realizedProfit = row.netProceeds - row.costBasis
        row.realizedProfitKnown = true
        row.pnlType = "sale_realized"
    else
        row.costBasis = row.costBasisQuantity > 0 and math.floor(basis + 0.5) or nil
        row.costBasisKnown = false
        row.pnlType = "sale_cost_basis_unknown"
    end
end

local function syncSettlementTransactionPnl(row)
    if not row or not row.settlementKey then return end
    for _, tx in ipairs(AZPCDB.transactions or {}) do
        if tx.settlementKey == row.settlementKey then
            if row.outcome == "sold" then
                tx.quantity = tonumber(row.saleQuantity) or tx.quantity or 1
            elseif row.outcome == "expired" then
                tx.quantity = tonumber(row.returnedQuantity) or tx.quantity or 1
            end
            tx.costBasis = row.costBasis
            tx.costBasisKnown = row.costBasisKnown
            tx.costBasisQuantity = row.costBasisQuantity
            tx.costBasisMissingQuantity = row.costBasisMissingQuantity
            tx.deposit = row.deposit
            tx.depositLoss = row.depositLoss
            tx.depositSource = row.depositSource
            tx.netProceeds = row.netProceeds
            tx.realizedProfit = row.realizedProfit
            tx.realizedProfitKnown = row.realizedProfitKnown
            tx.pnlType = row.pnlType
        end
    end
end

local function rebuildRealizedPnl()
    ensureDB()

    for _, tx in ipairs(AZPCDB.transactions or {}) do
        if tx.kind == "purchase_confirmed" then
            tx.pnlConsumedQuantity = nil
            tx.pnlConsumedAt = nil
        end
    end

    local knownPnl = 0
    local knownRows = 0
    local unknownRows = 0
    for _, row in ipairs(AZPCDB.mailboxSettlements or {}) do
        applyRealizedPnl(row)
        syncSettlementTransactionPnl(row)
        if row.realizedProfitKnown then
            knownPnl = knownPnl + (tonumber(row.realizedProfit) or 0)
            knownRows = knownRows + 1
        else
            unknownRows = unknownRows + 1
        end
    end

    AZPCDB.meta.realizedPnlKnown = math.floor(knownPnl + (knownPnl >= 0 and 0.5 or -0.5))
    AZPCDB.meta.realizedPnlKnownRows = knownRows
    AZPCDB.meta.realizedPnlUnknownRows = unknownRows
    AZPCDB.meta.realizedPnlRebuiltAt = now()
    dirtySinceFlush = true
end

local function printRealizedPnl()
    ensureDB()

    local grossSales = 0
    local ahCuts = 0
    local knownCostBasis = 0
    local knownSaleProfit = 0
    local knownDepositLoss = 0
    local unknownSales = 0
    local unknownExpirations = 0
    local soldCount = 0
    local expiredCount = 0

    for _, row in ipairs(AZPCDB.mailboxSettlements or {}) do
        if row.outcome == "sold" then
            soldCount = soldCount + 1
            grossSales = grossSales + (tonumber(row.buyout) or 0)
            ahCuts = ahCuts + (tonumber(row.auctionHouseCut) or 0)
            if row.realizedProfitKnown then
                knownCostBasis = knownCostBasis + (tonumber(row.costBasis) or 0)
                knownSaleProfit = knownSaleProfit + (tonumber(row.realizedProfit) or 0)
            else
                unknownSales = unknownSales + 1
            end
        elseif row.outcome == "expired" then
            expiredCount = expiredCount + 1
            if row.realizedProfitKnown then
                knownDepositLoss = knownDepositLoss + math.abs(tonumber(row.realizedProfit) or 0)
            else
                unknownExpirations = unknownExpirations + 1
            end
        end
    end

    local totalKnown = knownSaleProfit - knownDepositLoss
    print("|cff00ff98AZPC|r REALIZED P&L")
    print("  Settlements: " .. tostring(soldCount + expiredCount)
        .. " | SOLD " .. tostring(soldCount) .. " | EXPIRED " .. tostring(expiredCount))
    print("  Gross sales: " .. tostring(grossSales) .. "c | AH cuts: " .. tostring(ahCuts) .. "c")
    print("  Known purchase cost basis: " .. tostring(knownCostBasis) .. "c")
    print("  Known sale profit: " .. tostring(knownSaleProfit) .. "c | known expired-deposit losses: " .. tostring(knownDepositLoss) .. "c")
    print("  KNOWN REALIZED P&L: " .. tostring(totalKnown) .. "c")
    if unknownSales > 0 or unknownExpirations > 0 then
        print("  Incomplete basis: " .. tostring(unknownSales) .. " sold settlement(s), "
            .. tostring(unknownExpirations) .. " expiration(s). These are NOT guessed into P&L.")
    end

    local total = #(AZPCDB.mailboxSettlements or {})
    local start = math.max(1, total - 9)
    for i = start, total do
        local row = AZPCDB.mailboxSettlements[i]
        if row.outcome == "sold" then
            if row.realizedProfitKnown then
                print("  #" .. tostring(i) .. " SOLD | " .. tostring(row.name or "?")
                    .. " x" .. tostring(row.saleQuantity or 1)
                    .. " | net " .. tostring(row.netProceeds or 0) .. "c"
                    .. " - basis " .. tostring(row.costBasis or 0) .. "c"
                    .. " = P&L " .. tostring(row.realizedProfit or 0) .. "c")
            else
                print("  #" .. tostring(i) .. " SOLD | " .. tostring(row.name or "?")
                    .. " x" .. tostring(row.saleQuantity or 1)
                    .. " | P&L UNKNOWN (missing purchase basis for "
                    .. tostring(row.costBasisMissingQuantity or 1) .. " unit(s))")
            end
        else
            if row.realizedProfitKnown then
                print("  #" .. tostring(i) .. " EXPIRED | " .. tostring(row.name or "?")
                    .. " | deposit P&L " .. tostring(row.realizedProfit or 0) .. "c | item returned")
            else
                print("  #" .. tostring(i) .. " EXPIRED | " .. tostring(row.name or "?")
                    .. " | deposit P&L UNKNOWN | item returned")
            end
        end
    end
end

local function addMailboxSettlement(row, occurrence)
    local baseKey = settlementBaseKey(row)
    local listing, listingIndex = matchSettlementToListing(row)
    row.timestamp = now()
    row.source = "MAILBOX_SNAPSHOT_RECONCILE"
    row.baseKey = baseKey
    row.occurrence = occurrence or 1
    -- This key is diagnostic only. Dedupe is driven by snapshot counts, not by
    -- attempting to fingerprint an individual Blizzard mail.
    row.settlementKey = baseKey .. "|seq:" .. tostring(#AZPCDB.mailboxSettlements + 1)
    row.matchedListing = listing and true or false
    row.matchedListingIndex = listingIndex

    if listing then
        row.itemId = row.itemId or listing.itemId
        row.itemLink = row.itemLink or listing.itemLink
        row.listingBatchQuantity = tonumber(listing.quantity)
        row.listingStackSize = tonumber(listing.stackSize)
        row.listingNumStacks = tonumber(listing.numStacks)
        -- Keep listedQuantity as the quantity represented by THIS physical
        -- auction mail, not the total quantity from a multi-stack PostAuction.
        row.listedQuantity = tonumber(listing.stackSize)
        if (not row.listedQuantity or row.listedQuantity < 1) and row.listingBatchQuantity and row.listingNumStacks and row.listingNumStacks > 0 then
            row.listedQuantity = math.max(1, math.floor((row.listingBatchQuantity / row.listingNumStacks) + 0.5))
        end
        row.listedQuantity = row.listedQuantity or 1
        row.saleQuantity = row.outcome == "sold" and row.listedQuantity or nil
        row.listedUnitPrice = tonumber(listing.unitPrice) or tonumber(listing.buyoutPerUnit)
        row.listedTotalPrice = tonumber(listing.totalPrice) or tonumber(listing.totalBuyoutPerStack)
        row.listingTimestamp = listing.timestamp

        if row.outcome == "expired" then
            local recordedDeposit = tonumber(listing.auctionDepositPerStack)
            if (not recordedDeposit or recordedDeposit <= 0) and tonumber(listing.auctionDeposit) then
                local listingStacks = math.max(1, tonumber(listing.numStacks) or 1)
                recordedDeposit = math.floor((tonumber(listing.auctionDeposit) / listingStacks) + 0.5)
            end
            if recordedDeposit and recordedDeposit > 0 then
                row.deposit = recordedDeposit
                row.depositLoss = recordedDeposit
                row.depositKnown = true
                row.depositSource = listing.auctionDepositSource
            else
                row.deposit = nil
                row.depositLoss = nil
                row.depositKnown = false
            end
        end
    elseif row.outcome == "expired" then
        row.depositKnown = false
    end

    if row.outcome == "expired" and not row.depositKnown then
        repairExpiredSettlementDeposit(row)
    end

    applyRealizedPnl(row)
    table.insert(AZPCDB.mailboxSettlements, row)
    addTransaction({
        kind = row.outcome == "sold" and "sale_settled" or "auction_expired",
        source = "MAILBOX_SNAPSHOT_RECONCILE",
        itemId = row.itemId,
        itemLink = row.itemLink,
        name = row.name,
        quantity = row.outcome == "expired" and row.returnedQuantity or (row.saleQuantity or row.listedQuantity or 1),
        totalPrice = row.buyout,
        unitPrice = (row.outcome == "sold" and row.saleQuantity and row.saleQuantity > 0)
            and math.floor(((tonumber(row.buyout) or 0) / row.saleQuantity) + 0.5)
            or row.listedUnitPrice,
        mailPayout = row.mailPayout,
        auctionHouseCut = row.auctionHouseCut,
        deposit = row.deposit,
        depositLoss = row.depositLoss,
        depositSource = row.depositSource,
        buyer = row.buyer,
        status = row.outcome == "sold" and "sold_settled" or "expired_settled",
        settlementKey = row.settlementKey,
        matchedListing = row.matchedListing,
        costBasis = row.costBasis,
        costBasisKnown = row.costBasisKnown,
        costBasisQuantity = row.costBasisQuantity,
        costBasisMissingQuantity = row.costBasisMissingQuantity,
        netProceeds = row.netProceeds,
        realizedProfit = row.realizedProfit,
        realizedProfitKnown = row.realizedProfitKnown,
        pnlType = row.pnlType,
    })

    dirtySinceFlush = true
end

local function reconcileMailbox(source)
    ensureDB()
    updateCharacterMeta()

    if type(GetInboxNumItems) ~= "function" then
        return 0, 0, 0, "Mailbox API unavailable on this client."
    end

    local numItems, totalItems = GetInboxNumItems()
    numItems = tonumber(numItems) or 0
    totalItems = tonumber(totalItems) or numItems

    local normalized = {}
    local snapshotCounts = {}
    local rowsByKey = {}

    for index = 1, numItems do
        local row = normalizeAuctionMail(index)
        if row then
            table.insert(normalized, row)
            local key = settlementBaseKey(row)
            snapshotCounts[key] = (snapshotCounts[key] or 0) + 1
            rowsByKey[key] = rowsByKey[key] or {}
            table.insert(rowsByKey[key], row)
        end
    end

    local created = 0
    local sold = 0
    local expired = 0

    -- IMPORTANT: mailboxActiveCounts is a HIGH-WATER snapshot. During one of
    -- Blizzard's partial MAIL_INBOX_UPDATE refreshes, visible/normalized rows can
    -- temporarily fall from 7 to 5 and then return to 7. We never lower the
    -- baseline here, so that recovery cannot be mistaken for new mail.
    for key, currentCount in pairs(snapshotCounts) do
        local knownCount = tonumber(AZPCDB.mailboxActiveCounts[key]) or 0
        if currentCount > knownCount then
            local missing = currentCount - knownCount
            local keyRows = rowsByKey[key] or {}
            for n = 1, missing do
                local sourceIndex = knownCount + n
                local row = keyRows[sourceIndex] or keyRows[#keyRows]
                if row then
                    addMailboxSettlement(row, sourceIndex)
                    created = created + 1
                    if row.outcome == "sold" then sold = sold + 1 end
                    if row.outcome == "expired" then expired = expired + 1 end
                end
            end
            AZPCDB.mailboxActiveCounts[key] = currentCount
        end
    end

    while #AZPCDB.mailboxSettlements > 1000 do
        table.remove(AZPCDB.mailboxSettlements, 1)
    end

    AZPCDB.meta.lastMailboxReconcile = now()
    AZPCDB.meta.lastMailboxReconcileSource = source or "mailbox"
    AZPCDB.meta.lastMailboxNormalized = #normalized
    AZPCDB.meta.lastMailboxSettlementsCreated = created
    AZPCDB.meta.lastMailboxInboxCount = numItems
    AZPCDB.meta.lastMailboxInboxTotal = totalItems
    return created, sold, expired, nil
end

local function printMailboxProbe()
    ensureDB()
    local total = #(AZPCDB.mailboxCaptures or {})
    print("|cff00ff98AZPC|r Mailbox captures: " .. tostring(total))
    if total <= 0 then
        print("  No mailbox rows captured yet. Open the mailbox and wait a moment.")
        return
    end
    local start = math.max(1, total - 11)
    for i = start, total do
        local row = AZPCDB.mailboxCaptures[i]
        print("  #" .. tostring(i)
            .. " | " .. tostring(row.subject or "?")
            .. " | sender " .. tostring(row.sender or "?")
            .. " | money " .. tostring(row.money or 0) .. "c"
            .. " | item " .. tostring(row.itemName or row.invoiceItemName or "-")
            .. " x" .. tostring(row.itemCount or 0)
            .. " | invoice " .. tostring(row.invoiceType or "-")
            .. " | buyout " .. tostring(row.invoiceBuyout or 0) .. "c"
            .. " | deposit " .. tostring(row.invoiceDeposit or 0) .. "c"
            .. " | cut " .. tostring(row.invoiceConsignment or 0) .. "c")
    end
end

local function printMailboxSettlements()
    ensureDB()
    local total = #(AZPCDB.mailboxSettlements or {})
    local sold = 0
    local expired = 0
    local matched = 0
    for _, row in ipairs(AZPCDB.mailboxSettlements or {}) do
        if row.outcome == "sold" then sold = sold + 1 end
        if row.outcome == "expired" then expired = expired + 1 end
        if row.matchedListing then matched = matched + 1 end
    end

    print("|cff00ff98AZPC|r Mailbox settlements: " .. tostring(total)
        .. " | SOLD " .. tostring(sold)
        .. " | EXPIRED " .. tostring(expired)
        .. " | matched listings " .. tostring(matched))

    if total <= 0 then
        print("  No normalized settlements yet. Open mailbox and wait for invoice data.")
        return
    end

    local start = math.max(1, total - 11)
    for i = start, total do
        local row = AZPCDB.mailboxSettlements[i]
        if row.outcome == "sold" then
            print("  #" .. tostring(i)
                .. " SOLD | " .. tostring(row.name or "?")
                .. " | sale " .. tostring(row.buyout or 0) .. "c"
                .. " | cut " .. tostring(row.auctionHouseCut or 0) .. "c"
                .. " | deposit returned " .. tostring(row.deposit or 0) .. "c"
                .. " | payout " .. tostring(row.mailPayout or 0) .. "c"
                .. " | listing " .. (row.matchedListing and "MATCHED" or "UNMATCHED"))
        else
            print("  #" .. tostring(i)
                .. " EXPIRED | " .. tostring(row.name or "?")
                .. " x" .. tostring(row.returnedQuantity or 1)
                .. " | deposit loss " .. (row.depositKnown and (tostring(row.depositLoss or 0) .. "c") or "UNKNOWN")
                .. " | listing " .. (row.matchedListing and "MATCHED" or "UNMATCHED"))
        end
    end
end


local function printDepositDiagnostics()
    ensureDB()

    local rows = AZPCDB.mailboxSettlements or {}
    local expired = 0
    local unknown = 0
    for _, row in ipairs(rows) do
        if row.outcome == "expired" then
            expired = expired + 1
            if not (row.depositKnown and row.depositLoss ~= nil) then
                unknown = unknown + 1
            end
        end
    end

    print("|cff00ff98AZPC|r DEPOSIT DIAGNOSTICS | expired " .. tostring(expired)
        .. " | unknown " .. tostring(unknown))
    print("  DISPLAY ONLY. No mailbox, settlement, listing, or P&L state is changed.")

    if expired == 0 then
        print("  No expired settlements recorded yet.")
        return
    end

    for i, row in ipairs(rows) do
        if row.outcome == "expired" then
            local listing = settlementListing(row)
            local listingIndex = tonumber(row.matchedListingIndex)
            local vendor = listing and resolveVendorSellPrice(row, listing) or nil
            local multiplier = listing and listingDurationMultiplier(listing.runTime) or nil
            local stackQty = listing and (tonumber(listing.stackSize) or tonumber(row.returnedQuantity) or tonumber(listing.quantity)) or nil
            local formula = nil
            if vendor and stackQty and stackQty > 0 and multiplier and multiplier > 0 then
                formula = math.floor((vendor * stackQty * 0.15 * multiplier) + 0.5)
            end

            print("  #" .. tostring(i) .. " EXPIRED | " .. tostring(row.name or "?")
                .. " x" .. tostring(row.returnedQuantity or 1)
                .. " | matched=" .. tostring(row.matchedListing and true or false)
                .. " | listingIndex=" .. tostring(listingIndex or "nil"))

            if not listing then
                print("    LISTING: unavailable")
            else
                print("    LISTING: kind=" .. tostring(listing.kind or "nil")
                    .. " | itemId=" .. tostring(listing.itemId or "nil")
                    .. " | qty=" .. tostring(listing.quantity or "nil")
                    .. " | stackSize=" .. tostring(listing.stackSize or "nil")
                    .. " | numStacks=" .. tostring(listing.numStacks or "nil")
                    .. " | runTime=" .. tostring(listing.runTime or "nil"))
                print("    DEPOSIT FIELDS: total=" .. tostring(listing.auctionDeposit or "nil")
                    .. " | perStack=" .. tostring(listing.auctionDepositPerStack or "nil")
                    .. " | source=" .. tostring(listing.auctionDepositSource or "nil"))
                print("    REPAIR INPUTS: vendorSell=" .. tostring(vendor or "nil")
                    .. " | stackQty=" .. tostring(stackQty or "nil")
                    .. " | durationMult=" .. tostring(multiplier or "nil")
                    .. " | formula15pct=" .. tostring(formula or "nil"))
            end

            print("    SETTLEMENT: depositKnown=" .. tostring(row.depositKnown and true or false)
                .. " | deposit=" .. tostring(row.deposit or "nil")
                .. " | depositLoss=" .. tostring(row.depositLoss or "nil")
                .. " | depositSource=" .. tostring(row.depositSource or "nil"))
        end
    end
end


local function printBasisDiagnostics()
    ensureDB()

    local rows = AZPCDB.mailboxSettlements or {}
    local incomplete = {}
    for i, row in ipairs(rows) do
        if row.outcome == "sold" and not row.costBasisKnown then
            table.insert(incomplete, { index = i, row = row })
        end
    end

    print("|cff00ff98AZPC|r SOLD COST BASIS DIAGNOSTICS | incomplete " .. tostring(#incomplete))
    print("  DISPLAY ONLY. No purchase, settlement, listing, or P&L state is changed.")

    if #incomplete == 0 then
        print("  No sold settlements currently have incomplete purchase basis.")
        return
    end

    for _, entry in ipairs(incomplete) do
        local row = entry.row
        local listing = settlementListing(row)
        local qtyNeeded = soldSettlementQuantity(row)
        local candidates = 0
        local pricedCandidates = 0
        local candidateQty = 0
        local availableQty = 0
        local availablePricedQty = 0
        local candidateBasis = 0

        for _, tx in ipairs(AZPCDB.transactions or {}) do
            if settlementMatchesPurchase(tx, row) then
                candidates = candidates + 1
                local purchasedQty = math.max(0, tonumber(tx.quantity) or 0)
                local consumedQty = math.max(0, tonumber(tx.pnlConsumedQuantity) or 0)
                local available = math.max(0, purchasedQty - consumedQty)
                local unitCost = purchaseUnitCost(tx)
                candidateQty = candidateQty + purchasedQty
                availableQty = availableQty + available
                if unitCost then
                    pricedCandidates = pricedCandidates + 1
                    availablePricedQty = availablePricedQty + available
                    candidateBasis = candidateBasis + (unitCost * available)
                end
            end
        end

        local reason
        if candidates == 0 then
            reason = "NO_MATCHING_PURCHASE_ROWS"
        elseif pricedCandidates == 0 then
            reason = "MATCHING_PURCHASES_HAVE_NO_PRICE"
        elseif availablePricedQty < qtyNeeded then
            reason = "INSUFFICIENT_UNCONSUMED_PURCHASE_QTY"
        else
            reason = "BASIS_REBUILD_OR_MATCHING_REVIEW_NEEDED"
        end

        print("  #" .. tostring(entry.index) .. " SOLD | " .. tostring(row.name or "?")
            .. " x" .. tostring(qtyNeeded)
            .. " | missingBasisQty=" .. tostring(row.costBasisMissingQuantity or qtyNeeded)
            .. " | reason=" .. reason)
        print("    SALE: itemId=" .. tostring(row.itemId or "nil")
            .. " | char=" .. tostring(row.character or "nil")
            .. " | realm=" .. tostring(row.realm or "nil")
            .. " | faction=" .. tostring(row.faction or "nil")
            .. " | net=" .. tostring(row.netProceeds or "nil") .. "c")
        print("    LISTING: matched=" .. tostring(row.matchedListing and true or false)
            .. " | index=" .. tostring(row.matchedListingIndex or "nil")
            .. " | kind=" .. tostring(listing and listing.kind or "nil")
            .. " | qty=" .. tostring(listing and listing.quantity or "nil")
            .. " | stackSize=" .. tostring(listing and listing.stackSize or "nil")
            .. " | numStacks=" .. tostring(listing and listing.numStacks or "nil"))
        print("    PURCHASES: matches=" .. tostring(candidates)
            .. " | priced=" .. tostring(pricedCandidates)
            .. " | totalQty=" .. tostring(candidateQty)
            .. " | availableQty=" .. tostring(availableQty)
            .. " | availablePricedQty=" .. tostring(availablePricedQty)
            .. " | availablePricedBasis=" .. tostring(math.floor(candidateBasis + 0.5)) .. "c")

        local shown = 0
        for txIndex, tx in ipairs(AZPCDB.transactions or {}) do
            if settlementMatchesPurchase(tx, row) then
                shown = shown + 1
                if shown <= 8 then
                    local purchasedQty = math.max(0, tonumber(tx.quantity) or 0)
                    local consumedQty = math.max(0, tonumber(tx.pnlConsumedQuantity) or 0)
                    local available = math.max(0, purchasedQty - consumedQty)
                    print("      tx#" .. tostring(txIndex)
                        .. " qty=" .. tostring(purchasedQty)
                        .. " consumed=" .. tostring(consumedQty)
                        .. " available=" .. tostring(available)
                        .. " unitCost=" .. tostring(purchaseUnitCost(tx) or "nil")
                        .. " | at=" .. tostring(tx.timestamp or "nil")
                        .. " | source=" .. tostring(tx.source or "nil"))
                end
            end
        end
        if shown > 8 then
            print("      ... " .. tostring(shown - 8) .. " more matching purchase row(s)")
        end
    end
end

local function syncNow(reason)
    ensureDB()

    local why = reason or "manual"
    print("|cff00ff98AZPC|r: Sync requested (" .. tostring(why) .. ").")
    print("|cff00ff98AZPC|r: Type |cffffff00/reload|r now, or log out/quit WoW, to write AZPC data to disk.")
end

local function scheduleAutoSync()
    ensureDB()

    if not AZPCDB.settings.autoSyncOnClose then
        return
    end

    if not dirtySinceFlush then
        return
    end

    print("|cff00ff98AZPC|r: New AH data captured and ready to sync.")
    print("|cff00ff98AZPC|r: Type |cffffff00/reload|r when convenient; the background watcher will upload automatically.")
end

local function addTestObservation()
    ensureDB()
    updateCharacterMeta()

    local entry = {
        kind = "test",
        timestamp = now(),
        character = UnitName("player"),
        realm = GetRealmName(),
        faction = UnitFactionGroup("player"),
        message = "AZPC test observation"
    }

    table.insert(AZPCDB.observations, entry)
    AZPCDB.meta.lastWrite = entry.timestamp
    trimObservations()

    print("|cff00ff98AZPC|r: Test observation written.")
end

local function printStatus()
    ensureDB()
    updateCharacterMeta()

    local obsCount = #AZPCDB.observations
    local snapshotCount = #AZPCDB.snapshots
    local transactionCount = #AZPCDB.transactions

    print("|cff00ff98AZPC|r v0.4.23 DEPOSIT DIAGNOSTICS is running.")
    print("|cff00ff98AZPC|r Character: " .. tostring(AZPCDB.meta.character)
        .. " | Realm: " .. tostring(AZPCDB.meta.realm)
        .. " | Faction: " .. tostring(AZPCDB.meta.faction))
    print("|cff00ff98AZPC|r Saved observations: " .. tostring(obsCount)
        .. " | AH snapshots: " .. tostring(snapshotCount))
    print("|cff00ff98AZPC|r Personal AH records: " .. tostring(transactionCount))
    print("|cff00ff98AZPC|r Mailbox settlements: " .. tostring(#(AZPCDB.mailboxSettlements or {})))
    print("|cff00ff98AZPC|r Known realized P&L: " .. tostring(AZPCDB.meta.realizedPnlKnown or 0) .. "c")
    local serverOwned, pendingOwned, knownOwned = azpcKnownActiveCount()
    print("|cff00ff98AZPC|r Owned auctions: server "
        .. tostring(serverOwned)
        .. " + recent unreconciled " .. tostring(pendingOwned)
        .. " = AZPC known " .. tostring(knownOwned))
    print("|cff00ff98AZPC|r Auction-created confirmation event: "
        .. (HAS_AUCTION_CREATED_EVENT and "|cff00ff00AVAILABLE|r" or "|cffffff00UNAVAILABLE on this client|r"))
    if sellItemCache then
        print("|cff00ff98AZPC|r Cached sell item: "
            .. tostring(sellItemCache.name or ("Item " .. tostring(sellItemCache.itemId or "?")))
            .. " | ID " .. tostring(sellItemCache.itemId or "?"))
    end
    print("|cff00ff98AZPC|r Sync reminder on AH close: "
        .. (AZPCDB.settings.autoSyncOnClose and "|cff00ff00ON|r" or "|cffff4444OFF|r"))

    if AZPCDB.meta.lastCaptureCount then
        print("|cff00ff98AZPC|r Last AH capture: "
            .. tostring(AZPCDB.meta.lastCaptureCount)
            .. " listings | AH total reported: "
            .. tostring(AZPCDB.meta.lastAuctionTotal or "?"))
    end
end

SLASH_AZPC1 = "/azpc"
SlashCmdList["AZPC"] = function(msg)
    msg = string.lower((msg or ""):match("^%s*(.-)%s*$"))

    if msg == "" or msg == "status" then
        printStatus()

    elseif msg == "test" then
        addTestObservation()

    elseif msg == "scan" then
        local count, err = captureBrowseResults("manual")
        if count > 0 then
            print("|cff00ff98AZPC|r: Captured " .. tostring(count) .. " real AH listings.")
            print("|cff00ff98AZPC|r: Use |cffffff00/reload|r or log out to flush SavedVariables to disk.")
        else
            print("|cff00ff98AZPC|r: Scan captured nothing. " .. tostring(err or ""))
        end

    elseif msg == "sync" then
        syncNow("manual command")

    elseif msg == "autosync on" then
        ensureDB()
        AZPCDB.settings.autoSyncOnClose = true
        print("|cff00ff98AZPC|r: Sync reminder on Auction House close is now |cff00ff00ON|r.")

    elseif msg == "autosync off" then
        ensureDB()
        AZPCDB.settings.autoSyncOnClose = false
        print("|cff00ff98AZPC|r: Sync reminder on Auction House close is now |cffff4444OFF|r.")

    elseif msg == "autosync" or msg == "autosync status" then
        ensureDB()
        print("|cff00ff98AZPC|r: Sync reminder on Auction House close is "
            .. (AZPCDB.settings.autoSyncOnClose and "|cff00ff00ON|r." or "|cffff4444OFF|r."))

    elseif msg == "ledger" or msg == "transactions" or msg == "tx" then
        transactionSummary()

    elseif msg == "owned" or msg == "auctions" then
        printOwnedSummary()

    elseif msg == "owned reset" or msg == "auctions reset" then
        resetOwnedPageCache()
        print("|cff00ff98AZPC|r: Owned-auction page cache reset. Revisit your Auctions tab/pages.")

    elseif msg == "ownedprobe" or msg == "owned probe" or msg == "auctions probe" then
        probeOwnedAuctions()

    elseif msg == "owned refresh" or msg == "auctions refresh" then
        scheduleOwnerRefresh("manual_command")
        print("|cff00ff98AZPC|r: Owner-list refresh requested with retries.")

    elseif msg == "buyprobe" or msg == "purchaseprobe" then
        printPurchaseDiagnostics()

    elseif msg == "buyprobe clear" or msg == "purchaseprobe clear" then
        ensureDB()
        AZPCDB.purchaseDiagnostics = {}
        pendingBuys = {}
        purchaseProbeMessages = {}
        print("|cff00ff98AZPC|r: Purchase diagnostics cleared.")


    elseif msg == "mailprobe" or msg == "mail" then
        local count, err = captureMailbox("manual_command")
        print("|cff00ff98AZPC|r: Mailbox probe captured " .. tostring(count or 0) .. " new rows. " .. tostring(err or ""))
        printMailboxProbe()

    elseif msg == "mailprobe clear" then
        ensureDB()
        AZPCDB.mailboxCaptures = {}
        print("|cff00ff98AZPC|r: Mailbox probe captures cleared.")

    elseif msg == "depositdebug" or msg == "deposit debug" or msg == "depositdiag" then
        printDepositDiagnostics()

    elseif msg == "basisdebug" or msg == "basis debug" or msg == "basisdiag" then
        printBasisDiagnostics()

    elseif msg == "settlements" or msg == "settle" then
        -- DISPLAY ONLY. Never mutate settlement state from the reporting command.
        printMailboxSettlements()

    elseif msg == "pnl" or msg == "profit" then
        -- DISPLAY ONLY. P&L is rebuilt on login and incrementally on new settlements.
        printRealizedPnl()

    elseif msg == "pnl rebuild" or msg == "profit rebuild" then
        rebuildRealizedPnl()
        print("|cff00ff98AZPC|r: Realized P&L allocations rebuilt from confirmed purchases + mailbox settlements.")
        printRealizedPnl()

    elseif msg == "maildebug on" then
        ensureDB()
        AZPCDB.settings.mailDebug = true
        print("|cff00ff98AZPC|r: Mailbox raw-capture debug output is ON.")

    elseif msg == "maildebug off" then
        ensureDB()
        AZPCDB.settings.mailDebug = false
        print("|cff00ff98AZPC|r: Mailbox raw-capture debug output is OFF.")

    elseif msg == "mailreconcile" then
        local created, sold, expired, err = reconcileMailbox("manual_command")
        print("|cff00ff98AZPC|r: Mail reconcile created " .. tostring(created or 0)
            .. " new settlements | sold " .. tostring(sold or 0)
            .. " | expired " .. tostring(expired or 0)
            .. ". " .. tostring(err or ""))
        printMailboxSettlements()

    elseif msg == "settlements clear" or msg == "mailreconcile clear" then
        ensureDB()
        AZPCDB.mailboxSettlements = {}
        AZPCDB.mailboxActiveCounts = {}
        for _, tx in ipairs(AZPCDB.transactions or {}) do
            tx.mailSettlementConsumed = nil
            tx.mailSettlementConsumedCount = nil
            tx.mailSettlementConsumedAt = nil
            tx.mailSettlementOutcome = nil
        end
        print("|cff00ff98AZPC|r: Mailbox settlements + active snapshot counts cleared; listing match flags reset.")

    elseif msg == "ledger clear" or msg == "transactions clear" or msg == "tx clear" then
        ensureDB()
        AZPCDB.transactions = {}
        AZPCDB.meta.lastTransactionWrite = now()
        dirtySinceFlush = true
        print("|cff00ff98AZPC|r: Personal AH ledger cleared.")

    elseif msg == "clear" then
        ensureDB()
        AZPCDB.observations = {}
        AZPCDB.snapshots = {}
        AZPCDB.meta.lastWrite = now()
        AZPCDB.meta.lastCaptureCount = nil
        AZPCDB.meta.lastAuctionTotal = nil
        lastSnapshotFingerprint = nil
        dirtySinceFlush = false
        print("|cff00ff98AZPC|r: Market observations and AH snapshots cleared. Personal ledger preserved.")

    elseif msg == "help" then
        print("|cff00ff98AZPC|r commands:")
        print("  /azpc - show status")
        print("  /azpc scan - capture the currently loaded AH browse results")
        print("  /azpc sync - show safe sync instructions")
        print("  /azpc autosync on - show sync reminder after closing AH")
        print("  /azpc autosync off - disable automatic AH-close sync")
        print("  /azpc ledger - show personal AH ledger summary")
        print("  /azpc owned - show merged owned-auction scan progress")
        print("  /azpc owned reset - clear owner-page cache and rescan")
        print("  /azpc ownedprobe - directly probe owner API indexes")
        print("  /azpc owned refresh - force owner-list refresh + retries")
        print("  /azpc buyprobe - show recent purchase-confirmation evidence")
        print("  /azpc buyprobe clear - clear purchase probe diagnostics")
        print("  /azpc mailprobe - capture/read mailbox metadata WITHOUT collecting mail")
        print("  /azpc mailprobe clear - clear raw mailbox probe captures")
        print("  /azpc depositdebug - DISPLAY ONLY: show expired-listing deposit evidence")
        print("  /azpc basisdebug - DISPLAY ONLY: diagnose SOLD settlements missing purchase basis")
        print("  /azpc settlements - DISPLAY ONLY: show normalized SOLD/EXPIRED settlements")
        print("  /azpc pnl - DISPLAY ONLY: show realized personal AH profit/loss")
        print("  /azpc pnl rebuild - rebuild purchase-cost allocations for P&L")
        print("  /azpc maildebug on|off - toggle raw mailbox diagnostic capture/output")
        print("  /azpc settlements clear - clear settlement test records + reset match flags")
        print("  /azpc ledger clear - clear ONLY personal AH records")
        print("  /azpc test - write a test observation")
        print("  /azpc clear - clear market observations/snapshots")
        print("  /azpc help - show commands")
    else
        print("|cff00ff98AZPC|r: Unknown command. Try |cffffff00/azpc help|r.")
    end
end

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ensureDB()
        dirtySinceFlush = false
        installAuctionHooks()

    elseif event == "PLAYER_LOGIN" then
        installCraftHook()
        updateCharacterMeta()
        rebuildRealizedPnl()
        print("|cff00ff98AZPC|r v0.4.27 CRAFT COST BASIS CAPTURE loaded. Buyer-found sales now wait for terminal mailbox settlement instead of being marked unresolved.")

    elseif event == "MAIL_SHOW" then
        if AZPCDB.settings.mailDebug then
            local count, err = captureMailbox("MAIL_SHOW")
            print("|cff00ff98AZPC|r: Mailbox debug captured "
                .. tostring(count or 0) .. " new raw rows. " .. tostring(err or ""))
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(1.0, function()
                local created, sold, expired = reconcileMailbox("MAIL_SHOW_DELAYED")
                if created and created > 0 then
                    rebuildRealizedPnl()
                    print("|cff00ff98AZPC|r: MAIL SETTLEMENTS +" .. tostring(created)
                        .. " | sold " .. tostring(sold or 0)
                        .. " | expired " .. tostring(expired or 0) .. ".")
                end
            end)
        end

    elseif event == "MAIL_INBOX_UPDATE" then
        if AZPCDB.settings.mailDebug then
            local count = captureMailbox("MAIL_INBOX_UPDATE")
            if count and count > 0 then
                print("|cff00ff98AZPC|r: Mailbox debug captured " .. tostring(count) .. " new raw rows.")
            end
        end
        local created, sold, expired = reconcileMailbox("MAIL_INBOX_UPDATE")
        if created and created > 0 then
            rebuildRealizedPnl()
            print("|cff00ff98AZPC|r: MAIL SETTLEMENTS +" .. tostring(created)
                .. " | sold " .. tostring(sold or 0)
                .. " | expired " .. tostring(expired or 0) .. ".")
        end

    elseif event == "AUCTION_HOUSE_SHOW" then
        AH_OPEN = true
        installAuctionHooks()
        resetOwnedPageCache()

        scheduleOwnerRefresh("auction_house_show")

        print("|cff00ff98AZPC|r: Auction House detected. Browse + personal AH activity tracking enabled.")

    elseif event == "NEW_AUCTION_UPDATE" then
        local item = cacheSellItem()
        if item and (item.itemId or item.name) then
            print("|cff00ff98AZPC|r: Sell item cached: "
                .. tostring(item.name or ("Item " .. tostring(item.itemId or "?")))
                .. " (ID " .. tostring(item.itemId or "?") .. ").")
        end

    elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
        if pendingSell then
            addTransaction({
                kind = "sell_posted",
                source = "AUCTION_HOUSE_AUCTION_CREATED",
                itemId = pendingSell.itemId,
                name = pendingSell.name,
                quantity = pendingSell.quantity,
                stackSize = pendingSell.stackSize,
                numStacks = pendingSell.numStacks,
                totalPrice = pendingSell.totalBuyoutPerStack,
                unitPrice = pendingSell.buyoutPerUnit,
                minBidPerStack = pendingSell.minBidPerStack,
                runTime = pendingSell.runTime,
                status = "created",
            })

            print("|cff00ff98AZPC|r: Auction-created event recorded for "
                .. tostring(pendingSell.name or "posted item") .. ".")
            pendingSell = nil
        end

    elseif event == "AUCTION_OWNED_LIST_UPDATE" then
        AZPCDB.meta.lastOwnedListUpdate = now()
        local snapshot = captureOwnedAuctions()
        reconcileOwnedAuctions(snapshot)

        if snapshot then
            local serverCount, pendingExtra, knownActive = azpcKnownActiveCount()
            print("|cff00ff98AZPC|r: Owner refresh -> server "
                .. tostring(serverCount)
                .. " | recent unreconciled " .. tostring(pendingExtra)
                .. " | AZPC known active " .. tostring(knownActive))
        end

    elseif event == "AUCTION_BIDDER_LIST_UPDATE" then
        AZPCDB.meta.lastBidderListUpdate = now()
        recordPurchaseProbeEvent("AUCTION_BIDDER_LIST_UPDATE")

    elseif event == "CHAT_MSG_LOOT" then
        confirmCraftFromLoot(arg1)
    elseif event == "CHAT_MSG_SYSTEM" then
        local msg = tostring(arg1 or "")
        recordPurchaseProbeSystemMessage(msg)

        if msg == "Auction created." and pendingSell then
            addRecentPostedAuctionFromPending(pendingSell)

            addTransaction({
                kind = "sell_post_acknowledged",
                source = "CHAT_MSG_SYSTEM",
                itemId = pendingSell.itemId,
                itemLink = pendingSell.itemLink,
                name = pendingSell.name,
                quantity = pendingSell.quantity,
                stackSize = pendingSell.stackSize,
                numStacks = pendingSell.numStacks,
                totalPrice = pendingSell.totalBuyoutPerStack,
                unitPrice = pendingSell.buyoutPerUnit,
                minBidPerStack = pendingSell.minBidPerStack,
                runTime = pendingSell.runTime,
                status = "auction_created_message",
            })

            print("|cff00ff98AZPC|r: WoW acknowledged auction creation for "
                .. tostring(pendingSell.name or "auction item") .. ".")

            scheduleOwnerRefresh("auction_created")
            pendingSell = nil
        end

        local soldName = string.match(msg, "^A buyer has been found for your auction of (.+)%.$")
        if soldName then
            recordSaleConfirmed(soldName)
            scheduleOwnerRefresh("buyer_found")
        end

    elseif event == "AUCTION_HOUSE_CLOSED" then
        AH_OPEN = false
        scheduleAutoSync()

    elseif event == "AUCTION_ITEM_LIST_UPDATE" and AH_OPEN then
        local count = captureBrowseResults("automatic")
        if count and count > 0 then
            print("|cff00ff98AZPC|r: Auto-captured " .. tostring(count) .. " AH listings.")
        end
    end
end)
