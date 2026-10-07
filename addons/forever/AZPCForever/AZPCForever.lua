-- AZPC Forever: read-only AH collector. Does not buy, sell, or issue auction queries.
local addon, VERSION = ..., "0.2.1"
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
    local region = GetCurrentRegion and GetCurrentRegion() or 0
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
    local region = GetCurrentRegion and GetCurrentRegion() or 0
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
            quantity = number(quantity) or number(invoiceCount)
            local copper = invoice == "expired" and 0 or (invoice == "buyer" and (number(buyout) or number(bid)) or number(money))
            if invoice == "buyer" and copper == 0 then copper = number(bid) end
            -- Missing item ID/count or delayed seller proceeds stay unresolved; never assume one item.
            if number(id) and id>0 and quantity and quantity>0 and copper and (copper>0 or invoice=="expired") and name and not (number(delay) and delay>0) then
                local expiry=0
                if type(daysLeft)=="number" and daysLeft>0 then expiry=math.floor((timestamp+daysLeft*86400+30)/60) end
                if invoice=="expired" then
                    local base=table.concat({guid,realm,region,id,quantity,encode(sender),encode(subject),subjectEscapes},":")
                    expiry=expiredExpiry(base,timestamp,daysLeft) or 0
                end
                if expiry>0 then
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
    local region=GetCurrentRegion and GetCurrentRegion() or 0
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
    return {realm=realm,character=character,faction=faction,region=GetCurrentRegion and GetCurrentRegion() or 0,guid=guid}
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
    local at=(GetServerTime and GetServerTime() or time())*1000
    db.lastMillis=math.max(at,(db.lastMillis or 0)+1)
    local record={schema=1,eventId=eventId,castGuid=c.guid,operationId=result.operationID,recipeId=c.recipe.recipeId,recipeKey=c.recipe.recipeKey,
        name=c.recipe.name,itemId=result.itemID,quantity=result.quantity,observedAt=db.lastMillis,character=c.who.character,realm=c.who.realm,faction=c.who.faction,region=c.who.region,
        confirmation='player_spell_success_and_item_result',materialsKnown=known,recipeReagents=required,resourcesReturned=returned}
    if known then record.consumedReagents=consumed end
    db.crafts[#db.crafts+1]=record;db.seen[eventId]=true
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
            -- With no operation ID, do not associate a late result with an unfinished next cast.
            if not key and not c.success then return end
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
