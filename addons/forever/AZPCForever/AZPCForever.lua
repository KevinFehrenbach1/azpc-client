-- AZPC Forever: read-only AH collector. Does not buy, sell, or issue auction queries.
local addon, VERSION = ..., "0.2.15"
-- Beta builds changed the region API from 90 to 110 without changing realms.
-- Keep the established Forever beta market; never alias live realms.
local function canonicalRegion(region, realm)
    if tonumber(region)==110 and type(realm)=='string' and realm:match('^Classic Beta ') then return 90 end
    return region
end
local function currentRegion()
    return canonicalRegion(GetCurrentRegion and GetCurrentRegion() or 0, GetRealmName and GetRealmName() or '')
end
local frame = CreateFrame("Frame")
local open, pending = false, false
local function message(text) print("|cff9cc1ffAZPC Forever:|r " .. text) end
local function number(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    local ok, n = pcall(tonumber, value)
    if ok and n and n >= 0 and n < 9007199254740991 then return math.floor(n) end
end
local function encode(text)
    return (tostring(text or ""):gsub("([^%w%-_%.])", function(c) return string.format("%%%02X", string.byte(c)) end))
end
local function setup()
    if type(AZPCForeverDB) ~= "table" then AZPCForeverDB = {} end
    AZPCForeverDB.version = VERSION
    AZPCForeverDB.game = "forever"
    AZPCForeverDB.snapshots = AZPCForeverDB.snapshots or {}
    AZPCForeverDB.itemIds = AZPCForeverDB.itemIds or {}
    AZPCForeverDB.trades = AZPCForeverDB.trades or {}
end
local function observedMillis()
    local at=(GetServerTime and GetServerTime() or time())*1000
    AZPCForeverDB.lastTradeMillis=math.max(at,(AZPCForeverDB.lastTradeMillis or 0)+1)
    return AZPCForeverDB.lastTradeMillis
end
local function capture()
    setup()
    if not open then return 0, "Open the Auction House first." end
    local rows, mode = {}, ""
    local function add(id, name, price, qty, count)
        id, price, qty, count = number(id), number(price), number(qty), number(count)
        if not id or id == 0 or not price or price == 0 then return end
        if name then AZPCForeverDB.itemIds[name] = id end
        local old = rows[id]
        if old then
            old.price = math.min(old.price, price)
            old.quantity = old.quantity + (qty or 0)
            old.auctions = old.auctions + (count or 0)
        else rows[id] = {id=id, name=name or ("Item "..id), price=price, quantity=qty or 0, auctions=count or 0} end
    end
    if C_AuctionHouse and type(C_AuctionHouse.GetBrowseResults) == "function" then
        mode = "modern browse"
        for _, result in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
            local key = result.itemKey
            if key and key.itemID then
                local info = C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo(key)
                -- Browse minPrice is the lowest unit price; totalQuantity is loaded browse coverage.
                add(key.itemID, info and info.itemName, result.minPrice, result.totalQuantity, 0)
            end
        end
    elseif type(GetNumAuctionItems) == "function" and type(GetAuctionItemInfo) == "function" then
        mode = "classic browse"
        local count = GetNumAuctionItems("list") or 0
        for index=1,count do
            local name, _, qty, _, _, _, _, _, _, buyout, _, _, _, _, _, _, id = GetAuctionItemInfo("list",index)
            qty, buyout = number(qty), number(buyout)
            if qty and qty > 0 and buyout then add(id,name,math.floor(buyout/qty),qty,1) end
        end
    else return 0, "This beta build exposes no supported auction browse API." end
    local ids = {}; for id in pairs(rows) do ids[#ids+1]=id end; table.sort(ids)
    if #ids == 0 then return 0, "No buyout-priced results loaded. Search for an item first." end
    local realm = GetRealmName() or ""
    local faction = (UnitFactionGroup("player") or ""):lower()
    if realm == "" or (faction ~= "horde" and faction ~= "alliance") then return 0,"Realm/faction unavailable." end
    local region = currentRegion()
    local timestamp = GetServerTime and GetServerTime() or time()
    local lines = {"AZPCFOREVER|1|"..encode(realm).."|"..faction.."|"..region.."|"..timestamp}
    for _,id in ipairs(ids) do
        local r=rows[id]
        if #lines <= 5000 then lines[#lines+1]=table.concat({r.id,encode(r.name),r.price,r.quantity,r.auctions},"|") end
    end
    local export=table.concat(lines,";")
    local last=AZPCForeverDB.snapshots[#AZPCForeverDB.snapshots]
    if not last or last.export ~= export then
        AZPCForeverDB.snapshots[#AZPCForeverDB.snapshots+1]={export=export,scope="loaded_browse_results",mode=mode}
        while #AZPCForeverDB.snapshots > 30 do table.remove(AZPCForeverDB.snapshots,1) end
    end
    return #lines-1,"Captured "..(#lines-1).." items from loaded results. /reload or log out to save for the watcher."
end
local function schedule()
    if pending then return end
    pending=true
    C_Timer.After(1,function()
        pending=false
        local ok,err=pcall(capture)
        if not ok then message("Capture failed: "..tostring(err)) end
    end)
end
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
-- Event availability differs between beta builds. An unavailable event must not prevent addon startup.
for _,event in ipairs({"AUCTION_ITEM_LIST_UPDATE","AUCTION_HOUSE_BROWSE_RESULTS_UPDATED","AUCTION_HOUSE_BROWSE_RESULTS_ADDED"}) do pcall(frame.RegisterEvent,frame,event) end
frame:SetScript("OnEvent",function(_,event,name)
    if event == "ADDON_LOADED" and name == addon then setup(); message("Loaded. Browse/search AH items, then /reload to save scans.")
    elseif event == "AUCTION_HOUSE_SHOW" then open=true
    elseif event == "AUCTION_HOUSE_CLOSED" then open=false
    elseif open then schedule() end
end)
SLASH_AZPCFOREVER1="/azpcf"
local captureTrades
SlashCmdList.AZPCFOREVER=function(command)
    if command == "capture" then local ok,count,text=pcall(capture); message(ok and text or tostring(count))
    elseif command == "crafts" then AZPCForeverCrafting.Status()
    elseif command == "mail" then
        local ok,err=pcall(captureTrades)
        message(ok and "Mailbox checked. /reload saves records for My Trades." or tostring(err))
    else setup(); message("v"..VERSION.." | "..#AZPCForeverDB.snapshots.." saved captures | "..#(AZPCForeverDB.trades or {}).." mailbox records. /azpcf mail checks mail; /reload writes records to disk.") end
end

-- Confirmed mailbox invoice ledger. No purchase intent or price scan is a trade.
local tradeFrame = CreateFrame("Frame")
local function expiredSubject(subject)
    if type(subject) ~= "string" then return nil end
    local template = type(AUCTION_EXPIRED_MAIL_SUBJECT)=="string" and AUCTION_EXPIRED_MAIL_SUBJECT or "Auction expired: %s"
    local slot = template:find("%s",1,true)
    if not slot then return nil end
    local prefix,suffix=template:sub(1,slot-1),template:sub(slot+2)
    if subject:sub(1,#prefix) ~= prefix or (#suffix>0 and subject:sub(-#suffix) ~= suffix) then return nil end
    local name=subject:sub(#prefix+1,#subject-#suffix):match("^%s*(.-)%s*$")
    return name ~= "" and name or nil
end
local function expiredExpiry(base,timestamp,daysLeft)
    -- Reuse the saved expiry anchor when the mailbox estimate drifts slightly.
    -- Occurrence counts distinguish identical returned stacks in one mailbox.
    if type(daysLeft) ~= "number" or daysLeft<=0 then return nil end
    local estimate=timestamp+daysLeft*86400
    AZPCForeverDB.expiredMailAnchors=AZPCForeverDB.expiredMailAnchors or {}
    local anchors=AZPCForeverDB.expiredMailAnchors[base] or {}
    AZPCForeverDB.expiredMailAnchors[base]=anchors
    for _,anchor in ipairs(anchors) do if math.abs(anchor-estimate)<=120 then return anchor end end
    local anchor=math.floor(estimate+0.5)
    anchors[#anchors+1]=anchor
    return anchor
end
captureTrades=function()
    setup()
    AZPCForeverDB.trades = AZPCForeverDB.trades or {}
    AZPCForeverDB.tradeSeen = AZPCForeverDB.tradeSeen or {}
    if type(GetInboxNumItems) ~= "function" or type(GetInboxInvoiceInfo) ~= "function" or type(GetInboxHeaderInfo) ~= "function" then return end
    local timestamp = GetServerTime and GetServerTime() or time()
    local realm = GetRealmName() or ""
    local faction = (UnitFactionGroup("player") or ""):lower()
    local region = currentRegion()
    local character = (UnitName and UnitName("player")) or ""
    local guid = (UnitGUID and UnitGUID("player")) or character
    if realm == "" or character == "" or (faction ~= "horde" and faction ~= "alliance") then return end
    local occurrences = {}
    local count = GetInboxNumItems() or 0
    for index=1,count do
        local invoice, itemName, otherPlayer, bid, buyout, deposit, fee, delay, hour, minute, invoiceCount = GetInboxInvoiceInfo(index)
        local _, _, sender, subject, money, cod, daysLeft = GetInboxHeaderInfo(index)
        -- Preserve 0.1.1/0.1.2 mailbox identities while fixing the export shape.
        -- Those versions included gsub's subject replacement count in the fingerprint.
        local _, subjectEscapes = tostring(subject or ""):gsub("([^%w%-_%.])", "")
        local returnedName = expiredSubject(subject)
        if returnedName and number(money)==0 and number(cod)==0 then invoice="expired" end
        if invoice == "buyer" or invoice == "seller" or invoice == "expired" then
            local id, quantity, name
            if (invoice == "buyer" or invoice == "expired") and type(GetInboxItem) == "function" then name,id,_,quantity = GetInboxItem(index,1) end
            name = name or itemName
            if invoice == "expired" and (not name or name ~= returnedName) then name=nil;id=nil;quantity=nil end
            if name and not id and C_Item and C_Item.GetItemInfo then
                local _, link = C_Item.GetItemInfo(name)
                if type(link) == "string" then id=tonumber(link:match("item:(%d+)")) end
            elseif name and not id and type(GetItemInfo) == "function" then
                local _, link = GetItemInfo(name)
                if type(link) == "string" then id=tonumber(link:match("item:(%d+)")) end
            end
            id=id or (AZPCForeverDB.itemIds and AZPCForeverDB.itemIds[name])
            -- Purchase quantities must come from the attached stack, never an invoice fallback.
            quantity = number(quantity) or (invoice=="seller" and number(invoiceCount) or nil)
            local copper = invoice == "expired" and 0 or (invoice == "buyer" and (number(buyout) or number(bid)) or number(money))
            if invoice == "buyer" and copper == 0 then copper = number(bid) end
            -- Missing item ID/count or delayed seller proceeds stay unresolved; never assume one item.
            if number(id) and id>0 and quantity and quantity>0 and copper and (copper>0 or invoice=="expired") and name and not (number(delay) and delay>0) and (invoice~="seller" or type(otherPlayer)=="string" and otherPlayer~="") then
                local expiry=0
                if type(daysLeft)=="number" and daysLeft>0 then expiry=math.floor((timestamp+daysLeft*86400+30)/60) end
                if invoice=="expired" then
                    local base=table.concat({guid,realm,region,id,quantity,encode(sender),encode(subject),subjectEscapes},":")
                    expiry=expiredExpiry(base,timestamp,daysLeft) or 0
                end
                if expiry>0 then
                    if invoice~="expired" then
                        -- Mail daysLeft is an estimate, not an immutable receipt ID.
                        -- Reuse the original minute anchor across small estimate drift.
                        -- Keep the occurrence suffix below so simultaneous equal sales remain distinct.
                        local prefix=table.concat({guid,realm,region,invoice,id,quantity,copper},":")..":"
                        local suffix=":"..table.concat({encode(otherPlayer),encode(sender),encode(subject),subjectEscapes},":")..":"
                        local best
                        for seen in pairs(AZPCForeverDB.tradeSeen) do
                            if seen:sub(1,#prefix)==prefix then
                                local tail=seen:sub(#prefix+1)
                                local anchor=tonumber(tail:match("^(%d+):"))
                                if anchor and math.abs(anchor-expiry)<=2 and tail:sub(#tostring(anchor)+1,#tostring(anchor)+#suffix)==suffix then
                                    if not best or anchor<best then best=anchor end
                                end
                            end
                        end
                        expiry=best or expiry
                    end
                    local fingerprint=table.concat({guid,realm,region,invoice,id,quantity,copper,expiry,encode(otherPlayer),encode(sender),encode(subject),subjectEscapes},":")
                    occurrences[fingerprint]=(occurrences[fingerprint] or 0)+1
                    fingerprint=fingerprint..":"..occurrences[fingerprint]
                    local oldExport=encode(fingerprint)
                    local existing
                    if AZPCForeverDB.tradeSeen[fingerprint] then
                        for _,saved in ipairs(AZPCForeverDB.trades) do
                            if saved.tradeExport:find("|"..oldExport.."|",1,true) then existing=saved;break end
                        end
                    end
                    if not AZPCForeverDB.tradeSeen[fingerprint] or existing then
                        if existing or #AZPCForeverDB.trades < 10000 then
                            local kind=invoice=="expired" and "expired" or (invoice=="buyer" and "buy" or "sell")
                            local refundable=invoice=="seller" and number(deposit) or nil
                            -- If the invoice does not expose a refund, preserve v1 rather than guessing net proceeds.
                            local fields={"AZPCFTRADE","1",encode(fingerprint),kind,id,encode(name),quantity,copper,timestamp,encode(realm),faction,region,encode(character)}
                            if invoice~="seller" or (refundable and refundable<=copper) then
                                fields[2]="2";fields[8]=invoice=="seller" and copper-refundable or copper
                                fields[9]=observedMillis()
                                if existing then local savedFields={};for field in (existing.tradeExport.."|"):gmatch("(.-)|") do savedFields[#savedFields+1]=field end;fields[9]=savedFields[2]=="2" and tonumber(savedFields[9]) or tonumber(savedFields[9])*1000 end
                                fields[14]=refundable or "";fields[15]=invoice=="seller" and (number(fee) or "") or ""
                                fields[16]=invoice=="seller" and copper or ""
                                for field=17,21 do fields[field]="" end
                            end
                            local export=table.concat(fields,"|")
                            if existing then existing.tradeExport=export else AZPCForeverDB.trades[#AZPCForeverDB.trades+1]={tradeExport=export} end
                            local fresh=not AZPCForeverDB.tradeSeen[fingerprint]
                            AZPCForeverDB.tradeSeen[fingerprint]=true
                            if fresh then
                                -- A terminal mail record closes one pending, unresolved or active owner quantity.
                                local k=table.concat({region,realm,faction,character},"|")
                                AZPCForeverDB.settledOwners=AZPCForeverDB.settledOwners or {}
                                if invoice=="seller" then
                                    local receipts=AZPCForeverDB.settledOwners[k] or {};AZPCForeverDB.settledOwners[k]=receipts
                                    local old=receipts[id];receipts[id]={quantity=(old and old.quantity or 0)+quantity,at=timestamp}
                                end
                                local state=AZPCForeverDB.owners and AZPCForeverDB.owners[k] and AZPCForeverDB.owners[k][id]
                                if state and invoice~="buyer" then local remaining=quantity;for _,field in ipairs({"pending","unresolved","listed"}) do local used=math.min(remaining,state[field] or 0);state[field]=(state[field] or 0)-used;remaining=remaining-used;if remaining==0 then break end end end
                            end
                            if fresh then message("Recorded mailbox "..kind..": "..name.." x"..quantity..". /reload saves it for My Trading.") end
                        else message("Trade ledger is full. Existing records are preserved; contact AZPC before clearing it.") end
                    end
                end
            end
        end
    end
end
for _, event in ipairs({"MAIL_SHOW","MAIL_INBOX_UPDATE"}) do pcall(tradeFrame.RegisterEvent,tradeFrame,event) end
tradeFrame:SetScript("OnEvent",function()
    C_Timer.After(0.5,function() local ok,err=pcall(captureTrades);if not ok then message("Mailbox capture unavailable: "..tostring(err)) end end)
end)


-- Capture only complete owner lists; partial beta responses cannot close auctions.
local function identity()
    local realm=GetRealmName() or ""
    local faction=(UnitFactionGroup("player") or ""):lower()
    local character=UnitName and UnitName("player") or ""
    local region=currentRegion()
    if realm=="" or character=="" or (faction~="horde" and faction~="alliance") then return end
    return realm,faction,region,character
end
local function statusRecord(kind,id,name,q,listed,pending,unresolved,bag)
    local realm,faction,region,character=identity();if not realm then return end
    local at=observedMillis()
    local event=table.concat({UnitGUID and UnitGUID("player") or character,realm,region,kind,id,at},":")
    local fields={"AZPCFTRADE","2",encode(event),kind,id,encode(name),q,0,at,encode(realm),faction,region,encode(character),"","","",listed or "",pending or "",unresolved or "",bag or "",""}
    if #AZPCForeverDB.trades<10000 then AZPCForeverDB.trades[#AZPCForeverDB.trades+1]={tradeExport=table.concat(fields,"|")} end
end
local function ownerKey()
    local realm,faction,region,character=identity();if not realm then return end
    return table.concat({region,realm,faction,character},"|")
end
local function ownerState()
    setup();AZPCForeverDB.owners=AZPCForeverDB.owners or {}
    local k=ownerKey();if not k then return end
    AZPCForeverDB.owners[k]=AZPCForeverDB.owners[k] or {}
    return AZPCForeverDB.owners[k]
end
local function captureOwned()
    if not open then return end
    local state=ownerState();if not state then return end
    local rows={}
    local function add(id,name,q,sold)
        id,q=number(id),number(q);if not id or id<1 or not q or q<1 or type(name)~="string" then return false end
        AZPCForeverDB.itemIds[name]=id
        local r=rows[id] or {name=name,listed=0,pending=0};rows[id]=r
        if sold then r.pending=r.pending+q else r.listed=r.listed+q end
        return true
    end
    if C_AuctionHouse and type(C_AuctionHouse.GetOwnedAuctions)=="function" then
        if type(C_AuctionHouse.HasFullOwnedAuctionResults)~="function" or not C_AuctionHouse.HasFullOwnedAuctionResults() then return end
        for _,a in ipairs(C_AuctionHouse.GetOwnedAuctions() or {}) do
            local id=a.itemKey and a.itemKey.itemID
            local info=id and C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo(a.itemKey)
            if not add(id,info and info.itemName,a.quantity,a.status==1) then return end
        end
    elseif type(GetNumAuctionItems)=="function" and type(GetAuctionItemInfo)=="function" then
        local count,total=GetNumAuctionItems("owner")
        if type(count)~="number" or type(total)~="number" or count~=total then return end
        for i=1,count do
            local name,_,q,_,_,_,_,_,_,_,_,_,_,_,_,saleStatus,id,hasAllInfo=GetAuctionItemInfo("owner",i)
            if hasAllInfo==false or not add(id,name,q,saleStatus==1) then return end
        end
    else return end
    local receipts=AZPCForeverDB.settledOwners and AZPCForeverDB.settledOwners[ownerKey()] or {}
    local at=GetServerTime and GetServerTime() or time()
    for id,r in pairs(rows) do
        local receipt=receipts[id]
        if receipt then
            if r.pending==0 or at-receipt.at>120 then receipts[id]=nil else r.pending=math.max(0,r.pending-receipt.quantity) end
        end
    end
    local all={};for id in pairs(state) do all[id]=true end;for id in pairs(rows) do all[id]=true end
    for id in pairs(all) do
        local old=state[id] or {listed=0,pending=0,unresolved=0}
        local r=rows[id] or {name=old.name,listed=0,pending=0}
        local missing=math.max(0,old.listed+old.pending-r.listed-r.pending)
        local waiting=math.min(missing,math.max(0,old.pending-r.pending))
        r.pending=r.pending+waiting;r.unresolved=(old.unresolved or 0)+missing-waiting
        if r.listed~=old.listed or r.pending~=old.pending or r.unresolved~=old.unresolved or not old.recordedAt or (GetServerTime and GetServerTime() or time())-old.recordedAt>1800 then
            statusRecord("listing_snapshot",id,r.name,r.listed+r.pending+r.unresolved,r.listed,r.pending,r.unresolved)
            r.recordedAt=GetServerTime and GetServerTime() or time()
        else r.recordedAt=old.recordedAt end
        state[id]=r
    end
end
local function captureBags()
    setup();local k=ownerKey();if not k then return end
    local info=C_Container and C_Container.GetContainerItemInfo
    local slots=C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    if type(slots)~="function" or (type(info)~="function" and type(GetContainerItemInfo)~="function") then return end
    local rows={}
    for bag=0,(NUM_BAG_SLOTS or 4) do
        local count=slots(bag);if type(count)~="number" then return end
        for slot=1,count do
            local id,q,link
            if info then local v=info(bag,slot);if v then id,q,link=v.itemID,number(v.stackCount),v.hyperlink end
            else local _,count,_,_,_,_,l=GetContainerItemInfo(bag,slot);q=number(count);link=l;id=type(link)=="string" and tonumber(link:match("item:(%d+)")) end
            if id and q then
                local name=GetItemInfo and GetItemInfo(id) or C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)
                if not name then return end
                local r=rows[id] or {name=name,quantity=0};r.quantity=r.quantity+q;rows[id]=r
            elseif link then return end
        end
    end
    AZPCForeverDB.bagStates=AZPCForeverDB.bagStates or {};local previous=AZPCForeverDB.bagStates[k] or {}
    for id,r in pairs(previous) do if not rows[id] then rows[id]={name=r.name,quantity=0} end end
    local at=GetServerTime and GetServerTime() or time()
    for id,r in pairs(rows) do
        local old=previous[id]
        if not old or old.quantity~=r.quantity or not old.recordedAt or at-old.recordedAt>1800 then statusRecord("inventory_snapshot",id,r.name,r.quantity,nil,nil,nil,r.quantity);r.recordedAt=at else r.recordedAt=old.recordedAt end
    end
    AZPCForeverDB.bagStates[k]=rows
end
local lifecycle=CreateFrame("Frame")
for _,event in ipairs({"AUCTION_OWNED_LIST_UPDATE","OWNED_AUCTIONS_UPDATED","BAG_UPDATE_DELAYED","PLAYER_ENTERING_WORLD","PLAYER_LOGOUT"}) do pcall(lifecycle.RegisterEvent,lifecycle,event) end
lifecycle:SetScript("OnEvent",function(_,event)
    if event=="PLAYER_LOGOUT" then pcall(captureBags);return end
    C_Timer.After(0.5,function()
        if event=="AUCTION_OWNED_LIST_UPDATE" or event=="OWNED_AUCTIONS_UPDATED" then local ok,err=pcall(captureOwned);if not ok then message("Owner capture deferred: "..tostring(err)) end
        else local ok,err=pcall(captureBags);if not ok then message("Bag capture deferred: "..tostring(err)) end end
    end)
end)


-- Crafting capture is bundled here for compatibility with existing launchers.
do
-- Stage 1: recipe evidence and completed item crafts only. No cost or trade mutations.
local frame = CreateFrame('Frame')
local casts, order, seenOperations = {}, {}, {}
local hooked, recipePending = false, false
local function message(s) print('|cff9cc1ffAZPC Forever:|r '..s) end
local function integer(v)
    if type(issecretvalue)=='function' and issecretvalue(v) then return nil end
    if type(v)=='number' and v>=0 and v<9007199254740991 and v==math.floor(v) then return v end
end
local function clock() return GetTime and GetTime() or (GetServerTime and GetServerTime() or time()) end
local function setup()
    AZPCForeverDB=AZPCForeverDB or {}
    AZPCForeverDB.crafting=AZPCForeverDB.crafting or {schema=1,recipes={},crafts={},seen={}}
    return AZPCForeverDB.crafting
end
local function identity()
    local realm=GetRealmName() or ''
    local character=UnitName('player') or ''
    local faction=(UnitFactionGroup('player') or ''):lower()
    local guid=UnitGUID('player')
    if realm=='' or character=='' or not guid or (faction~='horde' and faction~='alliance') then return end
    return {realm=realm,character=character,faction=faction,region=currentRegion(),guid=guid}
end
local function api(name,...)
    local fn=C_TradeSkillUI and C_TradeSkillUI[name]
    if type(fn)~='function' then return end
    local ok,value=pcall(fn,...);if ok then return value end
end
local function recipe(id)
    id=integer(id);if not id or id<1 then return end
    local who=identity();if not who then return end
    if api('IsTradeSkillLinked') or api('IsTradeSkillGuild') or api('IsNPCCrafting') then return end
    local info=api('GetRecipeInfo',id)
    local schematic=api('GetRecipeSchematic',id,false)
    if type(info)~='table' or not info.learned or info.isRecraft or info.isEnchantingRecipe or info.isGatheringRecipe or info.isSalvageRecipe then return end
    if type(schematic)~='table' or schematic.isRecraft then return end
    local output=integer(schematic.outputItemID)
    if not output or output<1 or type(schematic.reagentSlotSchematics)~='table' then return end
    local min,max=integer(schematic.quantityMin),integer(schematic.quantityMax)
    if not min or min<1 or not max or max<min then return end
    local slots,materials,complete={},{},true
    for _,slot in ipairs(schematic.reagentSlotSchematics) do
        local q=integer(slot.quantityRequired)
        if not q or type(slot.reagents)~='table' then return end
        local options={}
        for _,r in ipairs(slot.reagents) do
            local item,currency=integer(r.itemID),integer(r.currencyID)
            if item and item>0 then options[#options+1]={itemId=item}
            elseif currency and currency>0 then options[#options+1]={currencyId=currency}
            else return end
        end
        slots[#slots+1]={quantity=q,required=slot.required==true,options=options,slotIndex=slot.dataSlotIndex}
        -- Alternatives, optional slots and variable quantities require later selection evidence.
        if slot.required==true and q>0 and #options==1 and options[1].itemId and (not slot.variableQuantities or #slot.variableQuantities==0) then
            local item=options[1].itemId;materials[item]=(materials[item] or 0)+q
        else complete=false end
    end
    if #slots==0 then complete=false end
    local reagents={};for item,q in pairs(materials) do reagents[#reagents+1]={itemId=item,quantity=q} end
    table.sort(reagents,function(a,b)return a.itemId<b.itemId end)
    local profession=api('GetBaseProfessionInfo')
    local key=table.concat({who.guid,who.region,who.realm,id},':')
    local r={schema=1,recipeId=id,recipeKey=key,name=info.name or schematic.name or ('Recipe '..id),outputItemId=output,outputMin=min,outputMax=max,
        reagentSlots=slots,reagents=reagents,materialsKnown=complete,profession=type(profession)=='table' and profession.professionName or nil,
        character=who.character,realm=who.realm,faction=who.faction,region=who.region,observedAt=(GetServerTime and GetServerTime() or time())*1000}
    setup().recipes[key]=r
    return r
end
local function copyMaterials(rows)
    local out={};for _,r in ipairs(rows) do out[#out+1]={itemId=r.itemId,quantity=r.quantity} end;return out
end
local function finish(c)
    if not c.success or not c.result then return end
    local db=setup();local eventId=c.who.guid..':craft:'..c.guid
    if db.seen[eventId] then return end
    if #db.crafts>=10000 then message('Craft ledger is full; existing records are preserved.');return end
    local result=c.result
    local required=copyMaterials(c.recipe.reagents)
    local consumed=copyMaterials(required)
    local known=c.recipe.materialsKnown and not c.selectionsUnknown
    local returned={}
    for _,r in ipairs(result.resourcesReturned or {}) do
        local item=type(r.reagent)=='table' and integer(r.reagent.itemID)
        local q=integer(r.quantity)
        if not item or item<1 or not q then known=false
        else
            returned[#returned+1]={itemId=item,quantity=q}
            local found=false
            for _,m in ipairs(consumed) do if m.itemId==item then found=true;if q>m.quantity then known=false else m.quantity=m.quantity-q end end end
            if not found then known=false end
        end
    end
    local at=observedMillis()
    db.lastMillis=math.max(at,(db.lastMillis or 0)+1)
    local record={schema=1,eventId=eventId,castGuid=c.guid,operationId=result.operationID,recipeId=c.recipe.recipeId,recipeKey=c.recipe.recipeKey,
        name=c.recipe.name,itemId=result.itemID,quantity=result.quantity,observedAt=db.lastMillis,character=c.who.character,realm=c.who.realm,faction=c.who.faction,region=c.who.region,
        confirmation='player_spell_success_and_item_result',materialsKnown=known,recipeReagents=required,resourcesReturned=returned}
    local candidates={};record.candidateItemIds={}
    for _,slot in ipairs(c.recipe.reagentSlots or {})do for _,option in ipairs(slot.options or {})do if option.itemId then candidates[option.itemId]=true end end end
    for id in pairs(candidates)do record.candidateItemIds[#record.candidateItemIds+1]=id end;table.sort(record.candidateItemIds)
    if known then record.consumedReagents=consumed end
    db.crafts[#db.crafts+1]=record;db.seen[eventId]=true
    if AZPCForeverCrafting.ScheduleCosts then AZPCForeverCrafting.ScheduleCosts() end
    message('Recorded craft: '..record.name..' x'..record.quantity..(known and '' or ' (material usage unresolved)')..'. /reload saves it.')
end
local function prune()
    local now=clock()
    for i=#order,1,-1 do
        local c=casts[order[i]]
        if not c or now-c.started>120 or (c.successAt and now-c.successAt>5) then casts[order[i]]=nil;table.remove(order,i) end
    end
    for key,at in pairs(seenOperations) do if now-at>120 then seenOperations[key]=nil end end
end
local selectionsUnknown=false
local function begin(guid,spell)
    if type(guid)~='string' or guid=='' or casts[guid] then return end
    local r=recipe(spell);local who=identity();if not r or not who then return end
    prune();if #order>=50 then return end
    casts[guid]={guid=guid,recipe=r,who=who,started=clock(),selectionsUnknown=selectionsUnknown}
    order[#order+1]=guid
end
local function result(data)
    if type(data)~='table' or data.firstCraftReward or data.bonusCraft or data.isEnchant then return end
    local item,q,operation=integer(data.itemID),integer(data.quantity),integer(data.operationID)
    if not item or item<1 or not q or q<1 then return end
    prune()
    -- Operation IDs identify duplicate result notifications; a cast GUID identifies the persisted craft.
    local key=operation and operation>0 and tostring(operation)..':'..item or nil
    if key and seenOperations[key] then return end
    for _,guid in ipairs(order) do
        local c=casts[guid]
        if c and not c.result and c.recipe.outputItemId==item then
            -- Classic reports operationID=0, including results before spell success.
            -- Stage one result per cast; finish still requires that cast to succeed.
            -- Repeated notifications cannot append a second record for this cast.
            c.result={itemID=item,quantity=q,operationID=operation,resourcesReturned=data.resourcesReturned}
            if key then seenOperations[key]=clock() end
            finish(c);return
        end
    end
end
local function captureRecipes()
    local ids=api('GetAllRecipeIDs') or api('GetFilteredRecipeIDs')
    if type(ids)~='table' then return 0 end
    local count=0
    for _,id in ipairs(ids) do if recipe(id) then count=count+1 end end
    return count
end
local function installHook()
    if hooked or type(hooksecurefunc)~='function' or not C_TradeSkillUI or type(C_TradeSkillUI.CraftRecipe)~='function' then return end
    hooksecurefunc(C_TradeSkillUI,'CraftRecipe',function(id,_,selected,_,orderId)
        local r=recipe(id)
        local unknown=orderId~=nil and orderId~=0
        if type(selected)=='table' and next(selected)~=nil then
            local chosen={}
            for _,entry in ipairs(selected) do
                local item=type(entry.reagent)=='table' and integer(entry.reagent.itemID)
                local q=integer(entry.quantity)
                if not item or not q then unknown=true else chosen[item]=(chosen[item] or 0)+q end
            end
            if not r or not r.materialsKnown then unknown=true
            else
                for _,m in ipairs(r.reagents) do if chosen[m.itemId]~=m.quantity then unknown=true end;chosen[m.itemId]=nil end
                if next(chosen) then unknown=true end
            end
        end
        selectionsUnknown=unknown
        -- The secure post-hook can run after the game's synchronous cast-start notification.
        for _,guid in ipairs(order) do local c=casts[guid];if c and not c.success and c.recipe.recipeId==id then c.selectionsUnknown=unknown end end
    end)
    hooked=true
end
AZPCForeverCrafting={Status=function()
    local db=setup();installHook();local n=captureRecipes();local total=0;for _ in pairs(db.recipes) do total=total+1 end
    local last=db.crafts[#db.crafts]
    message('Craft capture: '..total..' recipes | '..#db.crafts..' completed crafts | '..n..' recipes read now. '..(C_TradeSkillUI and type(C_TradeSkillUI.GetRecipeSchematic)=='function' and 'Open your profession and craft normally; /reload saves records.' or 'Recipe API unavailable in this build.'))
    if last then message('Last craft: '..last.name..' x'..last.quantity..' ('..last.character..')'..(last.materialsKnown and ' | materials recorded.' or ' | material usage unresolved.')) end
end}
for _,event in ipairs({'ADDON_LOADED','TRADE_SKILL_SHOW','TRADE_SKILL_LIST_UPDATE','TRADE_SKILL_DATA_SOURCE_CHANGED','UNIT_SPELLCAST_SENT','UNIT_SPELLCAST_START','UNIT_SPELLCAST_SUCCEEDED','UNIT_SPELLCAST_FAILED','UNIT_SPELLCAST_INTERRUPTED','TRADE_SKILL_ITEM_CRAFTED_RESULT'}) do pcall(frame.RegisterEvent,frame,event) end
frame:SetScript('OnEvent',function(_,event,...)
    local args={...}
    local ok,err=pcall(function()
        if event=='ADDON_LOADED' then setup();installHook()
        elseif event=='TRADE_SKILL_SHOW' or event=='TRADE_SKILL_LIST_UPDATE' or event=='TRADE_SKILL_DATA_SOURCE_CHANGED' then
            installHook();if not recipePending then recipePending=true;C_Timer.After(0.5,function()recipePending=false;local success,errorText=pcall(captureRecipes);if not success then message('Recipe capture deferred: '..tostring(errorText)) end end) end
        elseif event=='TRADE_SKILL_ITEM_CRAFTED_RESULT' then result(args[1])
        elseif args[1]=='player' then
            local guid,spell=args[2],args[3]
            if event=='UNIT_SPELLCAST_SENT' then guid,spell=args[3],args[4] end
            if event=='UNIT_SPELLCAST_SENT' or event=='UNIT_SPELLCAST_START' then begin(guid,spell)
            elseif event=='UNIT_SPELLCAST_SUCCEEDED' then
                begin(guid,spell);local c=casts[guid];if c then c.success=true;c.successAt=clock();finish(c) end
            else casts[guid]=nil end
        end
    end)
    if not ok then message('Craft capture deferred: '..tostring(err)) end
end)

end

-- Stage 2: local material-cost transfers. Website FIFO/trade events are untouched.
do
local MAX=1000000000000
local function integer(n,max) return type(n)=='number' and n>=0 and n==math.floor(n) and n<=(max or MAX) end
-- Multiply/divide without a potentially inexact total*quantity intermediate.
local function share(total,n,d)
    local whole=math.floor(total/d);local rem=total-whole*d
    local value=whole*n;local aq,ar,fq,fr=0,0,0,rem
    while n>0 do
        if n%2==1 then aq=aq+fq;ar=ar+fr;if ar>=d then ar=ar-d;aq=aq+1 end end
        n=math.floor(n/2)
        if n>0 then fq=fq*2;fr=fr*2;if fr>=d then fr=fr-d;fq=fq+1 end end
    end
    return value+aq
end
local function decode(s) return (s:gsub('%%(%x%x)',function(h)return string.char(tonumber(h,16))end)) end
local function market(e) return table.concat({canonicalRegion(e.region,e.realm),e.realm:lower(),e.faction,e.character:lower()},'|') end
local function mail(export)
    if type(export)~='string' then return end
    local f={};for s in (export..'|'):gmatch('(.-)|') do f[#f+1]=s end
    if f[1]~='AZPCFTRADE' or (f[2]~='1' and f[2]~='2') or (f[4]~='buy' and f[4]~='sell') then return end
    if not ((f[2]=='1' and (#f==13 or #f==14)) or (f[2]=='2' and #f==21)) then return end
    local id,q,c,at,region=tonumber(f[5]),tonumber(f[7]),tonumber(f[8]),tonumber(f[9]),canonicalRegion(tonumber(f[12]),decode(f[10]))
    if not integer(id,10000000) or id<1 or not integer(q,1000000) or q<1 or not integer(c) or not integer(at,4102444800000) or not integer(region,100) or region<1 then return end
    local e={kind=f[4],itemId=id,quantity=q,copper=c,observedAt=f[2]=='1' and at*1000 or at,eventId='mail:'..f[3],realm=decode(f[10]),faction=f[11],region=region,character=decode(f[13]),name=decode(f[6])}
    if e.realm=='' or e.character=='' or (e.faction~='horde' and e.faction~='alliance') then return end
    local prefix,expiry,suffix=decode(f[3]):match('^(.*:seller:%d+:%d+:%d+:)(%d+)(:[^:]*:[^:]*:[^:]*:%d+:%d+)$')
    if not prefix then prefix,expiry,suffix=decode(f[3]):match('^(.*:buyer:%d+:%d+:%d+:)(%d+)(:[^:]*:[^:]*:[^:]*:%d+:%d+)$')end
    if prefix then e.mailIdentity=prefix..suffix;e.mailExpiry=tonumber(expiry);if e.kind=='buy'then e.mailPurchaseIdentity=prefix:gsub('(:buyer:%d+:)%d+:(%d+:)$','%1%2')..suffix end end
    if prefix then local buyer,rest=suffix:match('^:([^:]*)(:.*)$');e.mailBuyerKnown=buyer~='';e.mailEnvelope=prefix..rest end
    return e
end
local function rebuild()
    local db=AZPCForeverDB.crafting
    if db.vendorCostingBlocked then error('Vendor ledger capacity reached; material costs cannot currently be verified.')end
    local events,seen,mailAnchors={},{},{}
    local receipts={}
    for _,row in ipairs(AZPCForeverDB.trades or {})do local e=mail(row.tradeExport);if e then receipts[#receipts+1]=e end end
    table.sort(receipts,function(a,b)return a.observedAt<b.observedAt or a.observedAt==b.observedAt and a.eventId<b.eventId end)
    for _,e in ipairs(receipts)do
        local duplicate=false
        if e.kind=='buy' and e.quantity==e.copper and e.mailPurchaseIdentity then
            local matches={};local count=0
            for _,other in ipairs(receipts)do
                if other.kind=='buy' and other.quantity~=e.quantity and other.mailPurchaseIdentity==e.mailPurchaseIdentity and other.copper==e.copper and math.abs(other.observedAt-e.observedAt)<=5000 and math.abs(other.mailExpiry-e.mailExpiry)<=2 and not matches[other.mailIdentity]then matches[other.mailIdentity]=true;count=count+1 end
            end
            duplicate=count==1
        end
        if e.kind=='sell' and e.mailEnvelope and not e.mailBuyerKnown then
            local matches={};local count=0
            for _,other in ipairs(receipts)do
                if other.mailBuyerKnown and other.mailEnvelope==e.mailEnvelope and other.copper==e.copper and math.abs(other.observedAt-e.observedAt)<=5000 and math.abs(other.mailExpiry-e.mailExpiry)<=2 and not matches[other.mailIdentity]then matches[other.mailIdentity]=true;count=count+1 end
            end
            duplicate=count==1
        end
        if e.mailIdentity and not duplicate then
            local anchors=mailAnchors[e.mailIdentity] or {};mailAnchors[e.mailIdentity]=anchors
            for _,old in ipairs(anchors)do if math.abs(old.mailExpiry-e.mailExpiry)<=2 and old.copper==e.copper then duplicate=true;break end end
            if not duplicate then anchors[#anchors+1]=e end
        end
        if not duplicate and not seen[e.eventId] then seen[e.eventId]=true;events[#events+1]=e end
    end
    for _,e in ipairs(db.vendorEvents or {})do
        if type(e.eventId)=='string' and not seen[e.eventId] and (e.kind=='buy' or e.kind=='sell' or e.kind=='vendor_unresolved') and integer(e.itemId,10000000) and e.itemId>0 and integer(e.quantity,1000000) and e.quantity>0 and integer(e.copper) then
            seen[e.eventId]=true;events[#events+1]=e
        end
    end
    for _,e in ipairs(db.materialEvents or {})do
        if e.kind~='request_rejected' and type(e.eventId)=='string' and not seen[e.eventId]then seen[e.eventId]=true;events[#events+1]=e end
    end
    for _,r in ipairs(db.crafts) do
        if type(r.eventId)=='string' and not seen[r.eventId] then
            seen[r.eventId]=true;events[#events+1]={kind='craft',itemId=r.itemId,quantity=r.quantity,observedAt=r.observedAt,eventId=r.eventId,realm=r.realm,faction=r.faction,region=r.region,character=r.character,name=r.name,record=r}
        end
    end
    -- Canonicalize working copies only; retain original saved region evidence.
    for i,e in ipairs(events)do
        local region=canonicalRegion(e.region,e.realm)
        if region~=e.region then local copy={};for k,v in pairs(e)do copy[k]=v end;copy.region=region;events[i]=copy end
    end
    local rank={buy=1,free=1,transfer_out=2,transfer_in=2,craft=3,sell=4,vendor_unresolved=5,reconcile=6}
    table.sort(events,function(a,b)if a.observedAt~=b.observedAt then return a.observedAt<b.observedAt end;if rank[a.kind]~=rank[b.kind] then return rank[a.kind]<rank[b.kind] end;return a.eventId<b.eventId end)
    local pools={};local transit={};local unresolved=0;local updates={}
    local function pool(e,id)
        local key=market(e)..'|'..id
        if not pools[key] then pools[key]={key=key,itemId=id,realm=e.realm,character=e.character,faction=e.faction,region=e.region,name=id==e.itemId and e.name or ('Item '..id),lots={}} end
        return pools[key]
    end
    local function totals(p)
        local q,c,known=0,0,not p.uncertain
        for _,l in ipairs(p.lots) do q=q+l.quantity;c=c+(l.copper or l.partialCopper or 0);if l.copper==nil then known=false end end
        if c>MAX or q>10000000000 then error('Material cost totals exceed the supported exact range.') end
        return q,c,known
    end
    local function average(p,wanted)
        local q,c,known=totals(p);local used=math.min(q,wanted)
        local transferred=q>0 and share(c,used,q) or 0
        p.lots={}
        if q>used then p.lots[1]={quantity=q-used,copper=known and c-transferred or nil,partialCopper=not known and c-transferred or nil} end
        if q==used then p.uncertain=nil end
        return {quantity=wanted,availableQuantity=q,recordedQuantity=used,knownCopper=transferred,complete=known and used==wanted}
    end
    local function sale(p,wanted)
        while wanted>0 and #p.lots>0 do
            local l=p.lots[1];local use=math.min(wanted,l.quantity);local c=l.copper or l.partialCopper or 0
            local removed=use==l.quantity and c or share(c,use,l.quantity)
            l.quantity=l.quantity-use;if l.copper~=nil then l.copper=c-removed else l.partialCopper=c-removed end
            wanted=wanted-use;if l.quantity==0 then table.remove(p.lots,1) end
        end
        if #p.lots==0 then p.uncertain=nil end
    end
    local function normalizedName(n)return (n:match('^%s*(.-)%s*$'):gsub('%s+',' ')):lower()end
    local function sameCharacter(address,character,e)
        local a,c=normalizedName(address),normalizedName(character);if a==c then return true end
        if a:find('-',1,true)then return false end
        local names={}
        for _,other in ipairs(events)do if other.realm==e.realm and other.region==e.region and other.faction==e.faction then names[normalizedName(other.character)]=true end end
        if names[a]then return false end
        local count,matched=0,nil;for name in pairs(names)do if a:sub(1,#name+1)==name..' 'then count=count+1;matched=name end end
        return count==1 and matched==c
    end
    for _,e in ipairs(events) do
        local p=pool(e,e.itemId)
        if e.kind=='buy' then p.lots[#p.lots+1]={quantity=e.quantity,copper=e.copper}
        elseif e.kind=='free' then
            local remaining=e.quantity-e.untrackedQuantity
            local new={}
            for _,l in ipairs(p.lots)do
                if l.copper==nil and remaining>0 then
                    if (l.partialCopper or 0)>0 then error('Cannot classify partially paid material stock as free.')end
                    local use=math.min(remaining,l.quantity);l.quantity=l.quantity-use;remaining=remaining-use;new[#new+1]={quantity=use,copper=0}
                end
            end
            if remaining>0 then error('Free classification exceeds unknown material stock.')end
            if e.untrackedQuantity>0 then new[#new+1]={quantity=e.untrackedQuantity,copper=0}end
            for _,l in ipairs(p.lots)do if l.quantity>0 then new[#new+1]=l end end;p.lots=new
        elseif e.kind=='transfer_out' then
            local used=average(p,e.quantity);transit[#transit+1]={event=e,quantity=e.quantity,copper=used.complete and used.knownCopper or nil,partialCopper=not used.complete and used.knownCopper or nil}
        elseif e.kind=='transfer_in' then
            local matches={}
            for _,t in ipairs(transit)do local from=t.event
                if not t.received and from.itemId==e.itemId and from.quantity==e.quantity and from.realm==e.realm and from.region==e.region and from.faction==e.faction and sameCharacter(e.counterparty,from.character,from) and sameCharacter(from.counterparty,e.character,e) and from.transferKey==e.transferKey and from.observedAt<=e.observedAt then matches[#matches+1]=t end
            end
            if #matches==1 then local t=matches[1];t.received=true;p.lots[#p.lots+1]={quantity=e.quantity,copper=t.copper,partialCopper=t.partialCopper}
            else p.lots[#p.lots+1]={quantity=e.quantity,partialCopper=0}end
        elseif e.kind=='reconcile' then
            if not integer(e.targetQuantity,1000000) or not integer(e.totalCopper) or e.targetQuantity==0 and e.totalCopper~=0 or e.confirmation~='inventory_and_cost_reconciled' then error('Invalid material reconciliation.') end
            p.lots=e.targetQuantity>0 and {{quantity=e.targetQuantity,copper=e.totalCopper}} or {};p.uncertain=nil
        elseif e.kind=='sell' then sale(p,e.quantity)
        elseif e.kind=='vendor_unresolved' then p.uncertain=true
        else
            local r=e.record;local inputs,missing,partial,complete={},{},0,r.materialsKnown==true and type(r.consumedReagents)=='table'
            local demand={}
            if complete then
                for _,m in ipairs(r.consumedReagents) do
                    if not integer(m.itemId,10000000) or m.itemId<1 or not integer(m.quantity,1000000) then complete=false;break end
                    demand[m.itemId]=(demand[m.itemId] or 0)+m.quantity
                end
            end
            if complete and next(demand) then
                local ids={};for id in pairs(demand)do ids[#ids+1]=id end;table.sort(ids)
                for _,id in ipairs(ids) do
                    local used=average(pool(e,id),demand[id]);used.itemId=id;inputs[#inputs+1]=used;partial=partial+used.knownCopper
                    if not used.complete then complete=false;missing[#missing+1]={itemId=id,quantity=demand[id],recordedQuantity=used.recordedQuantity,reason=used.recordedQuantity<demand[id] and 'purchase_cost_missing' or 'upstream_cost_unresolved'} end
                end
            else
                complete=false
                -- Without reliable consumption, these candidate material pools cannot establish later costs.
                local candidates={}
                for _,m in ipairs(r.recipeReagents or {})do candidates[m.itemId]=true end
                for _,id in ipairs(r.candidateItemIds or {})do candidates[id]=true end
                local catalog=db.recipes[r.recipeKey]
                for _,slot in ipairs(catalog and catalog.reagentSlots or {})do for _,option in ipairs(slot.options or {})do if option.itemId then candidates[option.itemId]=true end end end
                for id in pairs(candidates)do pool(e,id).uncertain=true end
                missing[#missing+1]={reason='material_usage_unresolved'}
            end
            if partial>MAX then error('Craft cost exceeds the supported exact range.') end
            local old=r.costBasis
            local conflict=old and old.complete and (not complete or old.totalCopper~=partial) or false
            if conflict then complete=false;missing[#missing+1]={reason='saved_cost_conflict'} end
            local basis=old and old.complete and old or {schema=1,method='remaining_material_weighted_average',complete=complete,totalCopper=complete and partial or nil,recordedCopper=partial,outputQuantity=e.quantity,inputs=inputs,missing=missing,costedAt=r.observedAt}
            updates[#updates+1]={record=r,basis=basis,conflict=conflict,missing=missing}
            if not complete then unresolved=unresolved+1 end
            p.lots[#p.lots+1]={quantity=e.quantity,copper=complete and basis.totalCopper or nil,partialCopper=not complete and partial or nil}
        end
    end
    local positions={}
    for _,p in pairs(pools) do
        local q,c,known=totals(p)
        if q>0 then positions[#positions+1]={key=p.key,itemId=p.itemId,name=p.name,realm=p.realm,character=p.character,faction=p.faction,region=p.region,quantity=q,costComplete=known,totalCopper=known and c or nil,recordedCopper=c,unknownQuantity=(function()local n=0;for _,l in ipairs(p.lots)do if l.copper==nil then n=n+l.quantity end end;return n end)(),unknownRecordedCopper=(function()local n=0;for _,l in ipairs(p.lots)do if l.copper==nil then n=n+(l.partialCopper or 0)end end;return n end)()} end
    end
    table.sort(positions,function(a,b)return a.key<b.key end)
    local state={schema=1,method='remaining_material_weighted_average',positions=positions,unresolvedCrafts=unresolved}
    for _,u in ipairs(updates)do u.record.costBasis=u.basis;u.record.costConflict=u.conflict;u.record.costingMissing=u.missing end
    db.costing=state
    return state
end
local pending=false
AZPCForeverCrafting.RebuildCosts=function()
    if not AZPCForeverDB or not AZPCForeverDB.crafting then return end
    local ok,state=pcall(rebuild)
    if not ok then AZPCForeverDB.crafting.costingError=tostring(state);return nil,state end
    AZPCForeverDB.crafting.costingError=nil;return state
end
local function schedule()
    if pending then return end;pending=true
    C_Timer.After(0.25,function()pending=false;AZPCForeverCrafting.RebuildCosts()end)
end
AZPCForeverCrafting.ScheduleCosts=schedule
local function money(c)
    return math.floor(c/10000)..'g '..math.floor(c%10000/100)..'s '..(c%100)..'c'
end
local oldStatus=AZPCForeverCrafting.Status
AZPCForeverCrafting.Status=function()
    local state,err=AZPCForeverCrafting.RebuildCosts();oldStatus()
    if err then print('|cff9cc1ffAZPC Forever:|r Craft costing deferred: '..tostring(err));return end
    local db=AZPCForeverDB.crafting;local r=db.crafts[#db.crafts]
    if not r or not r.costBasis then return end
    if r.costBasis.complete and not r.costConflict then
        print('|cff9cc1ffAZPC Forever:|r Saved craft cost: '..money(r.costBasis.totalCopper)..' for '..r.quantity..' output. Based on your recorded material purchases at crafting time.')
    else
        print('|cff9cc1ffAZPC Forever:|r Craft cost incomplete: '..money(r.costBasis.recordedCopper or 0)..' recorded material cost; missing costs are unknown. Unrecorded purchases and transfers have unknown costs.')
        if r.costConflict then print('|cff9cc1ffAZPC Forever:|r Historical source conflict: the saved craft cost is preserved, but cannot currently be verified.') end
        for _,m in ipairs(r.costingMissing or r.costBasis.missing or {})do if m.itemId then print('|cff9cc1ffAZPC Forever:|r Material '..m.itemId..': '..m.recordedQuantity..' of '..m.quantity..' units have a recorded source.') end end
    end
end
local frame=CreateFrame('Frame')
for _,event in ipairs({'ADDON_LOADED','MAIL_INBOX_UPDATE','MAIL_SHOW','PLAYER_LOGOUT'})do pcall(frame.RegisterEvent,frame,event)end
frame:SetScript('OnEvent',function(_,event)
    if event=='PLAYER_LOGOUT' then AZPCForeverCrafting.RebuildCosts()
    elseif event=='ADDON_LOADED' then schedule()
    else C_Timer.After(0.75,schedule) end
end)
end

-- Cash-only vendor transactions: hook intent, then require matching money and bag changes.
do
local active,baseline,requests,items,buybacks=false,nil,{}, {},{}
local queued,generation,attempts=false,0,0
local function safe(n,max)
    if type(issecretvalue)=='function' and issecretvalue(n) then return end
    if type(n)=='number' and n>=0 and n==math.floor(n) and n<=(max or 1000000000000) then return n end
end
local function call(fn,...)
    if type(fn)~='function' then return end
    local ok,value=pcall(fn,...);if ok then return value end
end
local function db()
    setup();AZPCForeverDB.crafting=AZPCForeverDB.crafting or {schema=1,recipes={},crafts={},seen={}}
    local d=AZPCForeverDB.crafting;d.vendorEvents=d.vendorEvents or {};return d
end
local function snapshot()
    if not C_Container or not GetMoney then return end
    local cash=safe(call(GetMoney));if not cash then return end
    local s={money=cash,counts={},slots={},craftCount=AZPCForeverDB and AZPCForeverDB.crafting and #AZPCForeverDB.crafting.crafts or 0}
    for bag=0,(NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        local slots=safe(call(C_Container.GetContainerNumSlots,bag),1000);if not slots then return end
        for slot=1,slots do
            local info=call(C_Container.GetContainerItemInfo,bag,slot)
            if info then
                local id=safe(info.itemID,10000000);local q=safe(info.stackCount,1000000)
                if not id or id<1 or not q then return end
                local sell
                if C_Item and type(C_Item.GetItemInfo)=='function' then
                    local ok,_,_,_,_,_,_,_,_,_,_,price=pcall(C_Item.GetItemInfo,id);if ok then sell=safe(price)end
                end
                local refund=call(C_Container.GetContainerItemPurchaseInfo,bag,slot,false)
                s.counts[id]=(s.counts[id] or 0)+q
                s.slots[bag..':'..slot]={itemId=id,quantity=q,name=info.itemName or ('Item '..id),sellCopper=sell,refund=refund}
            end
        end
    end
    return s
end
local function catalog()
    items={};buybacks={}
    for i=1,(safe(call(GetMerchantNumItems),1000) or 0)do
        local info=call(C_MerchantFrame and C_MerchantFrame.GetItemInfo,i)
        if not info and type(GetMerchantItemInfo)=='function' then
            local name,_,price,stack,_,purchasable,_,extended=GetMerchantItemInfo(i)
            info={name=name,price=price,stackCount=stack,isPurchasable=purchasable,hasExtendedCost=extended}
        end
        local link=call(GetMerchantItemLink,i);local id=type(link)=='string' and tonumber(link:match('item:(%d+)'))
        if info and safe(id,10000000) and id>0 and safe(info.price) and safe(info.stackCount,1000000) and info.stackCount>0 and not info.hasExtendedCost and not info.currencyID then
            items[i]={itemId=id,name=info.name or ('Item '..id),price=info.price,stack=info.stackCount}
        end
    end
    for i=1,(safe(call(GetNumBuybackItems),100) or 0)do
        if type(GetBuybackItemInfo)=='function' then
            local name,_,price,q=GetBuybackItemInfo(i)
            local link=call(GetBuybackItemLink,i);local id=type(link)=='string' and tonumber(link:match('item:(%d+)'))
            if safe(id,10000000) and id>0 and safe(price) and safe(q,1000000) and q>0 then buybacks[i]={itemId=id,name=name or ('Item '..id),price=price,quantity=q}end
        end
    end
end
local function save(kind,id,q,c,name,at,source)
    local d=db();if #d.vendorEvents>=10000 then d.vendorError='Vendor ledger is full; existing records are preserved.';d.vendorCostingBlocked=true;return false end
    local realm,character,faction=GetRealmName() or '',UnitName('player') or '',(UnitFactionGroup('player') or ''):lower()
    local region=safe(currentRegion(),100)
    if realm=='' or character=='' or not region or region<1 or (faction~='horde' and faction~='alliance') then return false end
    d.vendorSequence=(d.vendorSequence or 0)+1
    d.vendorEvents[#d.vendorEvents+1]={schema=1,eventId=tostring(call(UnitGUID,'player') or character)..':vendor:'..at..':'..d.vendorSequence,
        kind=kind,itemId=id,quantity=q,copper=c,name=name or ('Item '..id),observedAt=at,realm=realm,character=character,faction=faction,region=region,source=source,confirmation='vendor_intent_money_and_bags'}
    return true
end
local schedule
local function reconcile(force)
    local now=snapshot();if not baseline or not now then return end
    local deltas={};for id,q in pairs(baseline.counts)do deltas[id]=(now.counts[id] or 0)-q end
    for id,q in pairs(now.counts)do if baseline.counts[id]==nil then deltas[id]=q end end
    local expected,cash,directions,valid={},0,{},#requests>0
    for _,r in ipairs(requests)do
        local sign=r.kind=='buy' and 1 or -1
        if directions[r.itemId] and directions[r.itemId]~=sign then valid=false end
        directions[r.itemId]=sign;expected[r.itemId]=(expected[r.itemId] or 0)+sign*r.quantity;cash=cash-sign*r.copper
    end
    if now.money-baseline.money~=cash then valid=false end
    for id,q in pairs(expected)do if (deltas[id] or 0)~=q then valid=false end end
    for id,q in pairs(deltas)do if q~=(expected[id] or 0)then valid=false end end
    if valid and #db().vendorEvents+#requests>10000 then
        db().vendorCostingBlocked=true;db().vendorError='Vendor ledger is full; existing records are preserved.'
    elseif valid then
        for _,r in ipairs(requests)do save(r.kind,r.itemId,r.quantity,r.copper,r.name,r.at,r.source)end
        db().vendorError=nil
    elseif #requests>0 and not force and attempts<10 then attempts=attempts+1;schedule();return
    else
        -- Crafting while a merchant remains open is not a vendor disposal.
        local crafts=db().crafts;local craftChange=#requests==0 and now.money==baseline.money and #crafts>baseline.craftCount
        local craftDelta={}
        if craftChange then
            for i=baseline.craftCount+1,#crafts do
                local r=crafts[i];if not r.materialsKnown or type(r.consumedReagents)~='table'then craftChange=false;break end
                craftDelta[r.itemId]=(craftDelta[r.itemId] or 0)+r.quantity
                for _,m in ipairs(r.consumedReagents)do craftDelta[m.itemId]=(craftDelta[m.itemId] or 0)-m.quantity end
            end
            for id,q in pairs(craftDelta)do if q~=(deltas[id] or 0)then craftChange=false end end
            for id,q in pairs(deltas)do if q~=(craftDelta[id] or 0)then craftChange=false end end
        end
        local changed=false
        if not craftChange then
        for id,q in pairs(deltas)do if q~=0 then changed=true;save('vendor_unresolved',id,math.abs(q),0,nil,observedMillis(),'unconfirmed_vendor_change')end end
        end
        if changed then db().vendorError='Vendor change could not be matched to cash-only payment; affected material costs are unresolved.' end
    end
    baseline=now;requests={};attempts=0
    catalog();if not active then baseline=nil end;if AZPCForeverCrafting.ScheduleCosts then AZPCForeverCrafting.ScheduleCosts()end
end
schedule=function()
    if queued then return end;queued=true;local token=generation
    C_Timer.After(0.2,function()if token~=generation then return end;queued=false;local ok,err=pcall(reconcile,false);if not ok then db().vendorError=tostring(err)end end)
end
local function request(kind,r,q,c,source)
    if not active or not baseline or not r or not safe(q,1000000) or q<1 or not safe(c) then return end
    requests[#requests+1]={kind=kind,itemId=r.itemId,name=r.name,quantity=q,copper=c,source=source,at=observedMillis()};attempts=0;schedule()
end
local hooked=false
local function install()
    if hooked or type(hooksecurefunc)~='function' then return end
    local function hook(target,key,fn)
        local f=target and target[key] or _G[key]
        if type(f)=='function' then
            local safeFn=function(...)local ok,err=pcall(fn,...);if not ok then db().vendorError=tostring(err)end end
            if target then hooksecurefunc(target,key,safeFn)else hooksecurefunc(key,safeFn)end
        end
    end
    hook(nil,'BuyMerchantItem',function(index,quantity)
        local r=items[index];if not r then return end
        local q=quantity or r.stack;request('buy',r,q,r.price*q/r.stack,'vendor_purchase')
    end)
    hook(nil,'BuybackItem',function(index)local r=buybacks[index];if r then request('buy',r,r.quantity,r.price,'vendor_buyback')end end)
    hook(C_Container,'UseContainerItem',function(bag,slot)
        local r=baseline and baseline.slots[bag..':'..slot]
        if r and r.sellCopper then request('sell',r,r.quantity,r.sellCopper*r.quantity,'vendor_sale')end
    end)
    hook(C_Container,'ContainerRefundItemPurchase',function(bag,slot,equipped)
        local r=baseline and baseline.slots[bag..':'..slot];local info=r and r.refund
        if not equipped and info and safe(info.money) and info.itemCount==0 and info.currencyCount==0 then request('sell',r,r.quantity,info.money,'vendor_refund')end
    end)
    hooked=true
end
local frame=CreateFrame('Frame')
for _,event in ipairs({'ADDON_LOADED','MERCHANT_SHOW','MERCHANT_CLOSED','MERCHANT_UPDATE','PLAYER_MONEY','BAG_UPDATE_DELAYED','PLAYER_LOGOUT'})do pcall(frame.RegisterEvent,frame,event)end
frame:SetScript('OnEvent',function(_,event)
    local ok,err=pcall(function()
        if event=='ADDON_LOADED'then db();install()
        elseif event=='MERCHANT_SHOW'then
            if baseline then reconcile(true)end
            generation=generation+1;queued=false;requests={};attempts=0;active=true;baseline=snapshot();catalog();install()
        elseif event=='MERCHANT_CLOSED'then active=false;schedule()
        elseif event=='PLAYER_LOGOUT'then if baseline then reconcile(true)end;AZPCForeverCrafting.RebuildCosts()
        elseif baseline and (active or #requests>0)then schedule()end
    end)
    if not ok then db().vendorError=tostring(err)end
end)
local oldStatus=AZPCForeverCrafting.Status
AZPCForeverCrafting.Status=function()
    oldStatus();local d=db();local n=0;for _,e in ipairs(d.vendorEvents)do if e.source=='vendor_purchase' or e.source=='vendor_buyback'then n=n+1 end end
    message('Vendor capture: '..n..' confirmed purchases/buybacks.'..(d.vendorError and ' '..d.vendorError or ' Cash purchases require matching bag and money changes.'))
end
end

-- Explicit material sources and confirmed personal mail transfers.
do
local function d() local c=AZPCForeverDB.crafting;c.materialEvents=c.materialEvents or {};return c end
local function call(fn,...)if type(fn)=='function'then local ok,a,b,c,e=pcall(fn,...);if ok then return a,b,c,e end end end
local function held(id)return call(C_Item and C_Item.GetItemCount or GetItemCount,id,false,false)or 0 end
local function current()
 return {realm=GetRealmName() or '',character=UnitName('player') or '',faction=(UnitFactionGroup('player')or''):lower(),region=currentRegion()}
end
local function counterpart(name)
 if type(name)~='string'then return ''end
 local char,realm=name:match('^(.-)%-(.+)$')
 if char and realm:gsub('%s',''):lower()==(GetRealmName()or''):gsub('%s',''):lower()then return char end
 return name
end
local function record(kind,id,q,name,extra,eventId)
 local c=d();if #c.materialEvents>=10000 then message('Material ledger full; existing data preserved.');return end
 for _,e in ipairs(c.materialEvents)do if eventId and e.eventId==eventId then return end end
 c.materialSequence=(c.materialSequence or 0)+1
 local e=current();e.kind=kind;e.itemId=id;e.quantity=q;e.name=name or ('Item '..id);e.observedAt=observedMillis();e.eventId=eventId or tostring(UnitGUID('player'))..':material:'..e.observedAt..':'..c.materialSequence;e.confirmation='material_quantity_confirmed'
 for k,v in pairs(extra or {})do e[k]=v end;c.materialEvents[#c.materialEvents+1]=e
 AZPCForeverCrafting.RebuildCosts();return e
end
local function free(command)
 local me=current();if command.character~=me.character or command.realm~=me.realm or command.region~=me.region or command.faction~=me.faction then return end
 for _,e in ipairs(d().materialEvents)do if e.eventId==command.commandId then return end end
 local state=AZPCForeverCrafting.RebuildCosts();if not state then return end
 local recorded,unknown,partial=0,0,0
 for _,p in ipairs(state.positions)do if p.itemId==command.itemId and p.character==me.character and p.realm==me.realm and p.region==me.region and p.faction==me.faction then recorded=p.quantity;unknown=p.unknownQuantity or 0;partial=p.unknownRecordedCopper or 0 end end
 local owners=AZPCForeverDB.owners and AZPCForeverDB.owners[table.concat({me.region,me.realm,me.faction,me.character},'|')]
 local reserved=owners and owners[command.itemId];reserved=reserved and ((reserved.listed or 0)+(reserved.pending or 0)+(reserved.unresolved or 0))or 0
 local untracked=math.max(0,held(command.itemId)-math.max(0,recorded-reserved))
 if command.quantity<1 or command.quantity%1~=0 or command.quantity>math.min(held(command.itemId),untracked+unknown) or unknown>0 and partial>0 then record('request_rejected',command.itemId,command.quantity,command.name,{reason='quantity_or_source_changed',confirmation='material_request_rejected'},command.commandId);message('Free material request rejected: '..command.name..' quantity/source changed. Known paid costs cannot be erased.');return end
 local extra=math.min(command.quantity,untracked)
 record('free',command.itemId,command.quantity,command.name,{untrackedQuantity=extra,heldQuantity=held(command.itemId),source=command.source},command.commandId)
 message('Classified '..command.quantity..' '..command.name..' as '..command.source..' at zero cash cost. /reload saves it.')
end
AZPCForeverCrafting.ApplyMaterialCommands=function()
 for _,command in ipairs(AZPCForeverMaterialCommands or {})do local ok,err=pcall(free,command);if not ok then message('Material classification deferred: '..tostring(err))end end
end
-- Loot provenance plus self-loot text and bag confirmation; never infer from bags alone.
local lootSlots,lootBase,lootCleared,lootSelf={},{},{},{}
local lootGeneration=0
local function lootPattern(format)
 if type(format)~='string'then return nil end
 local p=format:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])','%%%1')
 p=p:gsub('%%%%s','(.+)'):gsub('%%%%d','(%%d+)')
 return '^'..p..'$'
end
local function confirmLoot()
 for id,r in pairs(lootCleared)do
  local q=r.quantity
  if q>0 and (lootSelf[id]or 0)>=q and held(id)-(lootBase[id]or held(id))==q then
   record('free',id,q,r.name,{source='farmed',untrackedQuantity=q,heldQuantity=held(id)})
   lootBase[id]=held(id);lootSelf[id]=(lootSelf[id]or 0)-q;lootCleared[id]=nil
  end
 end
end
local function openLoot()
 confirmLoot();lootSlots={};lootBase={};lootCleared={};lootSelf={};lootGeneration=lootGeneration+1
 for slot=1,(call(GetNumLootItems)or 0)do
  local link=call(GetLootSlotLink,slot);local id=type(link)=='string'and tonumber(link:match('item:(%d+)'))
  local _,name,q=call(GetLootSlotInfo,slot)
  local safe=false
  if type(GetLootSourceInfo)=='function'then
   local sources={GetLootSourceInfo(slot)};safe=#sources>0
   for i=1,#sources,2 do local guid=sources[i];if type(guid)~='string'or not(guid:match('^Creature%-')or guid:match('^Vehicle%-')or guid:match('^GameObject%-'))then safe=false end end
  end
  if safe and id and q and q>0 then lootSlots[slot]={itemId=id,name=name,quantity=q};if lootBase[id]==nil then lootBase[id]=held(id)end end
 end
end
local function selfLoot(text)
 if type(text)~='string'then return end
 local link,q
 local multi=lootPattern(LOOT_ITEM_SELF_MULTIPLE);local single=lootPattern(LOOT_ITEM_SELF)
 if multi then link,q=text:match(multi)end
 if not link and single then link=text:match(single);q=1 end
 local id=link and tonumber(link:match('item:(%d+)'));q=tonumber(q)
 if id and lootBase[id]~=nil and q and q>0 then lootSelf[id]=(lootSelf[id]or 0)+q;confirmLoot()end
end
local sentItems,sendPending={},nil
local inbox,incoming,baseline,generation={},{},{},0
local function sentCatalog()
 local rows={}
 for slot=1,12 do local name,id,_,q=call(GetSendMailItem,slot)
  if id and q and q>0 then local r=rows[id]or{itemId=id,quantity=0,name=name};r.quantity=r.quantity+q;rows[id]=r end
 end
 sentItems=rows
end
local function inboxCatalog()
 local rows={};local count=call(GetInboxNumItems)or 0
 for index=1,count do
  local invoice=call(GetInboxInvoiceInfo,index)
  local _,_,sender,subject,money,cod=GetInboxHeaderInfo(index)
  if not invoice and sender and (money or 0)==0 and (cod or 0)==0 and not expiredSubject(subject) and not sender:lower():find('auction',1,true)then
   local items={}
   for slot=1,16 do local name,id,_,q=call(GetInboxItem,index,slot);if id and q and q>0 then items[slot]={itemId=id,quantity=q,name=name}end end
   rows[index]={sender=counterpart(sender),subject=subject or '',items=items}
  end
 end
 inbox=rows
end
local function reconcile(g)
 if g~=generation or not next(incoming)then return end
 local expected={};for _,r in pairs(incoming)do expected[r.itemId]=(expected[r.itemId]or 0)+r.quantity end
 for id,q in pairs(expected)do if held(id)-(baseline[id]or 0)~=q then return end end
 local grouped={}
 for _,r in pairs(incoming)do local k=r.sender..'|'..r.subject..'|'..r.itemId;local row=grouped[k];if row then row.quantity=row.quantity+r.quantity else grouped[k]={itemId=r.itemId,quantity=r.quantity,name=r.name,sender=r.sender,subject=r.subject}end end
 for _,r in pairs(grouped)do record('transfer_in',r.itemId,r.quantity,r.name,{counterparty=r.sender,transferKey='mail:'..r.subject})end
 incoming={};baseline={};generation=generation+1
end
local frame=CreateFrame('Frame')
for _,event in ipairs({'ADDON_LOADED','PLAYER_LOGIN','MAIL_SEND_INFO_UPDATE','MAIL_SEND_SUCCESS','MAIL_FAILED','MAIL_SHOW','MAIL_INBOX_UPDATE','BAG_UPDATE_DELAYED','MAIL_CLOSED','LOOT_OPENED','LOOT_SLOT_CLEARED','LOOT_CLOSED','CHAT_MSG_LOOT'})do pcall(frame.RegisterEvent,frame,event)end
frame:SetScript('OnEvent',function(_,event,arg)
 local ok,err=pcall(function()
  if event=='ADDON_LOADED'then d()
  elseif event=='PLAYER_LOGIN'then C_Timer.After(1,function()AZPCForeverCrafting.ApplyMaterialCommands()end)
  elseif event=='MAIL_SEND_INFO_UPDATE'then sentCatalog()
  elseif event=='MAIL_SEND_SUCCESS'then if sendPending then for _,r in pairs(sendPending.items)do record('transfer_out',r.itemId,r.quantity,r.name,{counterparty=sendPending.recipient,transferKey='mail:'..sendPending.subject})end end;sendPending=nil;sentItems={}
  elseif event=='MAIL_FAILED'then sendPending=nil
  elseif event=='MAIL_SHOW'or event=='MAIL_INBOX_UPDATE'then reconcile(generation);inboxCatalog()
  elseif event=='LOOT_OPENED'then openLoot()
  elseif event=='LOOT_SLOT_CLEARED'then local r=lootSlots[arg];if r then local prev=lootCleared[r.itemId];if prev then prev.quantity=prev.quantity+r.quantity else lootCleared[r.itemId]={quantity=r.quantity,name=r.name}end;lootSlots[arg]=nil;confirmLoot()end
  elseif event=='CHAT_MSG_LOOT'then selfLoot(arg)
  elseif event=='LOOT_CLOSED'then confirmLoot();local g=lootGeneration;C_Timer.After(2,function()if g==lootGeneration then confirmLoot();lootSlots={};lootCleared={};lootSelf={};lootBase={}end end)
  elseif event=='BAG_UPDATE_DELAYED'then reconcile(generation);confirmLoot()
  elseif event=='MAIL_CLOSED'then reconcile(generation);incoming={};baseline={};generation=generation+1 end
 end);if not ok then message('Material capture deferred: '..tostring(err))end
end)
if type(hooksecurefunc)=='function'then
 pcall(hooksecurefunc,'SendMail',function(recipient,subject)
  if (call(GetSendMailMoney)or 0)>0 or (call(GetSendMailCOD)or 0)>0 then sendPending=nil;return end
  sendPending={recipient=counterpart(recipient),subject=subject or '',items=sentItems}
 end)
 pcall(hooksecurefunc,'TakeInboxItem',function(index,slot)
  local mail=inbox[index];if not mail then return end
  for i,r in pairs(mail.items)do if not slot or slot==i then
   local k=index..':'..i;if not incoming[k]then if baseline[r.itemId]==nil then baseline[r.itemId]=held(r.itemId)end;incoming[k]={itemId=r.itemId,quantity=r.quantity,name=r.name,sender=mail.sender,subject=mail.subject}end
  end end
  local g=generation;C_Timer.After(0.25,function()reconcile(g)end)
 end)
end
end

-- Percent-encoded JSON exports keep the desktop reader away from executable Lua.
do
local arrays={candidateItemIds=true,reagents=true,reagentSlots=true,options=true,recipeReagents=true,consumedReagents=true,resourcesReturned=true,inputs=true,missing=true,evidence=true}
local function json(value,key,depth)
    depth=depth or 0;if depth>12 then error('Crafting export exceeds nesting limit.')end
    local kind=type(value)
    if kind=='nil'then return 'null'
    elseif kind=='boolean'then return value and 'true' or 'false'
    elseif kind=='number'then if value~=value or value==math.huge or value==-math.huge then error('Invalid crafting number.')end;return string.format('%.0f',value)
    elseif kind=='string'then return '"'..value:gsub('[%z\1-\31\\"]',function(c)if c=='"'then return '\\"'elseif c=='\\'then return '\\\\'else return string.format('\\u%04x',string.byte(c))end end)..'"'
    elseif kind=='table'then
        local out={}
        if arrays[key]then for _,v in ipairs(value)do out[#out+1]=json(v,nil,depth+1)end;return '['..table.concat(out,',')..']'end
        local keys={};for k in pairs(value)do if type(k)=='string'and k~='syncExport' and k~='costingMissing'then keys[#keys+1]=k end end;table.sort(keys)
        for _,k in ipairs(keys)do out[#out+1]=json(k,nil,depth+1)..':'..json(value[k],k,depth+1)end
        return '{'..table.concat(out,',')..'}'
    end
    error('Unsupported crafting export value.')
end
local function exports()
    local d=AZPCForeverDB and AZPCForeverDB.crafting;if not d then return end
    for _,r in pairs(d.recipes)do r.syncExport='AZPCFCRAFT|1|'..encode(json({schema=1,recordType='recipe',recordId=r.recipeKey,data=r}))end
    for _,r in ipairs(d.crafts)do
        if not r.candidateItemIds then
            local ids={};r.candidateItemIds={};local catalog=d.recipes[r.recipeKey]
            for _,m in ipairs(r.recipeReagents or {})do ids[m.itemId]=true end
            for _,slot in ipairs(catalog and catalog.reagentSlots or {})do for _,option in ipairs(slot.options or {})do if option.itemId then ids[option.itemId]=true end end end
            for id in pairs(ids)do r.candidateItemIds[#r.candidateItemIds+1]=id end;table.sort(r.candidateItemIds)
        end
        r.syncExport='AZPCFCRAFT|1|'..encode(json({schema=1,recordType='craft',recordId=r.eventId,data=r}))end
    for _,r in ipairs(d.vendorEvents or {})do r.syncExport='AZPCFCRAFT|1|'..encode(json({schema=1,recordType='vendor',recordId=r.eventId,data=r}))end
    for _,r in ipairs(d.materialEvents or {})do r.syncExport='AZPCFCRAFT|1|'..encode(json({schema=1,recordType='material',recordId=r.eventId,data=r}))end
end
local old=AZPCForeverCrafting.RebuildCosts
AZPCForeverCrafting.RebuildCosts=function()
    local state,err=old();local ok,exportError=pcall(exports)
    if not ok and AZPCForeverDB and AZPCForeverDB.crafting then AZPCForeverDB.crafting.syncError=tostring(exportError)
    elseif AZPCForeverDB and AZPCForeverDB.crafting then AZPCForeverDB.crafting.syncError=nil end
    return state,err
end
end

-- One-time, evidence-bounded migration of the legacy linen ledger.
-- Append audited checkpoints; do not delete receipts or rewrite frozen craft costs.
do
local migration='linen-ledger-20261008'
local function migrate()
    local db=AZPCForeverDB;local d=db and db.crafting
    if not d or not d.materialEvents or not d.crafts then return false end
    local ids={'material-reconcile:lu-linen-20261008:2589','material-reconcile:lu-linen-20261008:2996'}
    local found={};for _,e in ipairs(d.materialEvents)do for _,id in ipairs(ids)do if e.eventId==id then found[id]=true end end end
    if found[ids[1]] or found[ids[2]] then return false end
    if #d.materialEvents>9998 then return false end
    local rows={};local latest={};local buys={};local after=false
    for _,row in ipairs(db.trades or {})do
        if type(row.tradeExport)=='string' then
            local f={};for v in (row.tradeExport..'|'):gmatch('(.-)|')do f[#f+1]=v end
            if (f[2]=='1' or f[2]=='2')and f[10]=='Classic%20Beta%20PvP%202'and f[11]=='horde'and (f[12]=='90'or f[12]=='110')and f[13]=='Lu' then
                local id,q,c,at=tonumber(f[5]),tonumber(f[7]),tonumber(f[8]),tonumber(f[9])
                if at and f[2]=='1'then at=at*1000 end
                if (id==2589 or id==2996)and q and c and at then
                    if f[4]=='inventory_snapshot' then rows[#rows+1]={id=id,q=q,at=at};if not latest[id]or latest[id].at<at then latest[id]={q=q,at=at}end
                    else
                        if at>1791447247001 then after=true end
                        if f[4]=='buy'and id==2589 and at>=1791444677000 and at<=1791447230000 then buys[#buys+1]={q=q,c=c,at=at}end
                    end
                end
            end
        end
    end
    if after or not latest[2589]or latest[2589].q~=0 or not latest[2996]or latest[2996].q~=11 then return false end
    local times={1791444821000,1791444824000,1791444827000,1791444830000,1791444834000,1791444836000,1791444840000,1791444843000}
    for i,t in ipairs(times)do
        local cloth,bolts=0,0
        for _,r in ipairs(rows)do if math.abs(r.at-t)<=1 then if r.id==2589 and r.q==16-2*i then cloth=cloth+1 elseif r.id==2996 and r.q==i then bolts=bolts+1 end end end
        if cloth~=1 or bolts~=1 then return false end
    end
    local q,c=0,0;for _,r in ipairs(buys)do q=q+r.q;c=c+r.c end
    if #buys~=3 or q~=14 or c~=14 then return false end
    for _,records in ipairs({d.crafts,d.materialEvents,d.vendorEvents or {}})do for _,r in ipairs(records)do
        if r.character=='Lu'and r.realm=='Classic Beta PvP 2'and canonicalRegion(r.region,r.realm)==90 and r.faction=='horde'and(r.observedAt or 0)>1791447247001 then
            if r.itemId==2589 or r.itemId==2996 then return false end
            for _,m in ipairs(r.consumedReagents or {})do if m.itemId==2589 or m.itemId==2996 then return false end end
        end
    end end
    local corrections={}
    for i,id in ipairs({2589,2996})do
        local quantity=id==2996 and 11 or 0
        corrections[#corrections+1]={schema=1,eventId=ids[i],kind='reconcile',itemId=id,quantity=math.max(quantity,1),targetQuantity=quantity,totalCopper=id==2996 and 14 or 0,name=id==2996 and 'Bolt of Linen Cloth'or'Linen Cloth',observedAt=1791447247002,region=90,realm='Classic Beta PvP 2',faction='horde',character='Lu',confirmation='inventory_and_cost_reconciled',sourceQuantities=id==2996 and {crafted=11}or{},reason='Verified legacy linen migration: eight free alt cloth plus fourteen bought cloth costing fourteen copper produced eleven bolts; historical records retained.',evidence={'inventory_snapshot:2996:1791447247000:11','inventory_snapshot:2589:1791447247001:0','paired_recipe_conversions:1791444821000:1791444843000:8','cloth_purchases:8+2+4:14c','confirmed_free_alt_cloth:8'}}
    end
    -- Retain the pre-migration pool summary alongside the untouched raw history.
    d.migrations=d.migrations or {};d.migrations[migration]={schema=1,previousCosting=d.costing,correctionIds=ids,observedAt=observedMillis()}
    for _,r in ipairs(corrections)do d.materialEvents[#d.materialEvents+1]=r end
    return true
end
local f=CreateFrame('Frame');f:RegisterEvent('ADDON_LOADED')
f:SetScript('OnEvent',function(_,_,name)
    if name~=addon then return end
    local ok,changed=pcall(migrate)
    if ok and changed then
        AZPCForeverCrafting.RebuildCosts()
        message('Historical linen balance corrected: 0 cloth, 11 bolts, 14 copper total material cost. /reload saves the correction for upload.')
    elseif not ok then message('Historical material migration deferred; original records retained.')end
end)
end
