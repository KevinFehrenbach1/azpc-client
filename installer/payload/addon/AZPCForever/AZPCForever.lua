-- AZPC Forever: AH collector and profession planner. Searches require explicit user actions; never buys or sells.
local addon, VERSION = ..., "0.2.53"
-- BEGIN AZPC TIMING DIAGNOSTICS
local perf={enabled=false,stats={}}
AZPCForeverDiagnostics=perf
local perfUnpack=unpack or table.unpack
local function perfClock()
    local fn=type(debugprofilestop)=='function' and debugprofilestop
    if not fn then return nil end
    local ok,value=pcall(fn)
    if ok and type(value)=='number' and value==value then return value end
end
local function perfResults(...)return {n=select('#',...),...}end
function perf.Wrap(name,fn)
    return function(...)
        if not perf.enabled then return fn(...) end
        local start=perfClock()
        -- Do not catch or transform capture errors; existing callers retain their
        -- original error handling. Preserve all return values, including nils.
        local result=perfResults(fn(...))
        local finish=perfClock()
        if start and finish and finish>=start then
            local elapsed=finish-start
            local s=perf.stats[name] or {calls=0,total=0,max=0,last=0};perf.stats[name]=s
            s.calls=s.calls+1;s.total=s.total+elapsed;s.max=math.max(s.max,elapsed);s.last=elapsed
        end
        return perfUnpack(result,1,result.n)
    end
end
function perf.Command(command)
    local action=(command or ''):match('^perf%s*(.-)%s*$')
    if action==nil then return false end
    if action=='on' then
        if not perfClock() then print('AZPC timing: timer unavailable; diagnostics remain off.');perf.enabled=false;return true end
        perf.stats={};perf.enabled=true;print('AZPC timing ON. Loot/skin one mob and collect mail, then /azpcf perf. No reload needed to view timings.')
    elseif action=='off' then perf.enabled=false;print('AZPC timing OFF. Existing results remain available with /azpcf perf.')
    elseif action=='reset' then perf.stats={};print('AZPC timing results cleared.')
    elseif action=='' then
        print('AZPC timing '..(perf.enabled and 'ON' or 'OFF')..' | milliseconds; nested totals overlap.')
        local names={};for name in pairs(perf.stats)do names[#names+1]=name end;table.sort(names)
        if #names==0 then print('No timings yet. Use /azpcf perf on, reproduce the pause, then /azpcf perf.')end
        for _,name in ipairs(names)do local s=perf.stats[name];print(string.format('%s: %d calls | max %.2f ms | last %.2f ms | total %.2f ms',name,s.calls,s.max,s.last,s.total))end
    else print('AZPC timing: /azpcf perf on | /azpcf perf | /azpcf perf off | /azpcf perf reset')end
    return true
end
-- END AZPC TIMING DIAGNOSTICS
-- BEGIN AZPC SALE SYNC REMINDER
do
-- A reminder is not an upload acknowledgement: SavedVariables reach the watcher only after reload/logout.
AZPCForeverSyncPrompt = {}
local prompt = AZPCForeverSyncPrompt
local visible, capturing, pending = {}, {}, {}
local mailboxOpen, queued, timerPending = false, false, false
local dirty=false
local popupKey = 'AZPC_FOREVER_SYNC_SALES'
local function inCombat() return type(InCombatLockdown)=='function' and InCombatLockdown() end
local function showReminder()
    timerPending=false
    if not queued then return end
    if inCombat() then return end
    if type(StaticPopup_Show)~='function' or type(StaticPopupDialogs)~='table' then return end
    queued=false;dirty=false
    StaticPopup_Show(popupKey)
end
if type(StaticPopupDialogs)=='table' then
    StaticPopupDialogs[popupKey]={
        text='Auction data recorded!\n\nReloading saves your latest data so the AZPC Watcher can sync it to your account dashboard at azpc.market.\n\nYour watcher must be running and connected. Reload now?',
        button1='Reload now',button2='Later',timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3,
        OnAccept=function()
            if inCombat() then dirty=true;queued=true;return end
            if type(ReloadUI)=='function' then ReloadUI() end
        end,
    }
end
local function queueReminder()
    if not dirty then return end
    queued=true
    if not timerPending then
        timerPending=true
        if C_Timer and type(C_Timer.After)=='function' then C_Timer.After(0.8,showReminder) else showReminder() end
    end
end
local function confirmCollected()
    if not mailboxOpen or type(GetMoney)~='function' then return end
    local money=GetMoney()
    for fingerprint,sale in pairs(pending) do
        local remains=false
        for _,current in pairs(visible) do if current.fingerprint==fingerprint then remains=true;break end end
        if not remains and money>=sale.moneyBefore+sale.amount then
            pending[fingerprint]=nil
            queueReminder()
        end
    end
end
function prompt.MarkDirty() dirty=true;queueReminder() end
function prompt.BeginCapture() capturing={} end
function prompt.ObserveSale(index,fingerprint,amount)
    if not mailboxOpen or type(GetMoney)~='function' or not amount or amount<=0 then return end
    capturing[index]={fingerprint=fingerprint,amount=amount,moneyBefore=GetMoney()}
end
function prompt.EndCapture() visible=capturing;confirmCollected() end
local events=CreateFrame('Frame')
for _,event in ipairs({'MAIL_SHOW','MAIL_CLOSED','PLAYER_MONEY','PLAYER_REGEN_ENABLED'}) do pcall(events.RegisterEvent,events,event) end
events:SetScript('OnEvent',function(_,event)
    if event=='MAIL_SHOW' then mailboxOpen=true;visible={};pending={}
    elseif event=='MAIL_CLOSED' then
        mailboxOpen=false;visible={};pending={}
        if dirty then queueReminder() end
    elseif event=='PLAYER_MONEY' then confirmCollected()
    elseif event=='PLAYER_REGEN_ENABLED' then showReminder() end
end)
if type(hooksecurefunc)=='function' and type(TakeInboxMoney)=='function' then
    hooksecurefunc('TakeInboxMoney',function(index)
        local sale=visible[index]
        if mailboxOpen and sale then
            pending[sale.fingerprint]={amount=sale.amount,moneyBefore=sale.moneyBefore}
        end
    end)
end
end
-- END AZPC SALE SYNC REMINDER
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
    AZPCForeverDB.tooltipPrices=AZPCForeverDB.tooltipPrices or {}
    local tooltipScope=table.concat({region,realm:lower(),faction},'|')
    AZPCForeverDB.tooltipPrices[tooltipScope]=AZPCForeverDB.tooltipPrices[tooltipScope] or {}
    for id,r in pairs(rows) do AZPCForeverDB.tooltipPrices[tooltipScope][id]={unitCopper=r.price,observedAt=timestamp,scope='loaded_browse_results'} end
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
local mailboxReceipts
SlashCmdList.AZPCFOREVER=function(command)
    if perf.Command(command)then return end
    if command == "capture" then local ok,count,text=pcall(capture); message(ok and text or tostring(count))
    elseif command == "materials" then AZPCForeverProfession.Show()
    elseif command == "crafts" then AZPCForeverCrafting.Status()
    elseif command == "mail" then
        local ok,err=pcall(captureTrades)
        message(ok and "Mailbox checked. /reload saves records for My Trades." or tostring(err))
    else setup(); message("v"..VERSION.." | "..#AZPCForeverDB.snapshots.." saved captures | "..#(AZPCForeverDB.trades or {}).." trade/history records. /azpcf mail checks mail; /reload writes records to disk.") end
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
-- BEGIN AZPC MAIL RELOAD CHECKPOINT
do
-- Only live mailbox continuity may bridge a drifting expiry estimate. This is
-- not a permanent item/price dedup key: collected or absent mails retire it.
local open,session,closedCheckpoint=false,nil,nil
local function clock()return GetServerTime and GetServerTime()or time()end
local function checkpoint()
    if not session then return end
    local entries={}
    for _,r in ipairs(session.entries)do
        local invoice,name,_,_,_,deposit,fee,delay,_,_,quantity=GetInboxInvoiceInfo(r.index)
        local _,_,sender,subject,money,cod=GetInboxHeaderInfo(r.index)
        if invoice=='seller' and name==r.name and number(quantity)==r.quantity and number(money)==r.amount and number(cod)==0 and sender==r.sender and subject==r.subject and number(deposit)==r.deposit and number(fee)==r.fee and (not number(delay)or delay==0)then
            local copy={};for k,v in pairs(r)do copy[k]=v end;entries[#entries+1]=copy
        end
    end
    if #entries>0 then return {schema=1,owner=session.owner,at=clock(),entries=entries}end
end
mailboxReceipts={}
function mailboxReceipts.Open()
    if not open then session=nil end;open=true;closedCheckpoint=nil
end
function mailboxReceipts.Begin(owner,count,total)
    AZPCForeverDB.retiredMailReceipts=AZPCForeverDB.retiredMailReceipts or{}
    if not session or session.owner~=owner or session.trades~=AZPCForeverDB.trades then
        local saved=AZPCForeverDB.mailReloadCheckpoint
        local entries={}
        if open and saved and saved.schema==1 and saved.owner==owner and clock()>=saved.at and clock()-saved.at<=300 then entries=saved.entries or{}end
        session={owner=owner,trades=AZPCForeverDB.trades,entries=entries,resumeUntil=clock()+10}
        AZPCForeverDB.mailReloadCheckpoint=nil
    end
    session.next={};session.used={};session.partial=total and total>count
    session.count=count
end
function mailboxReceipts.Match(base,buyer,expiry,at,deposit,fee)
    local exact,compatible={},{}
    for _,r in ipairs(session.entries)do
        local advance=expiry-(r.estimateExpiry or expiry)
        local drift=advance>=-2 and advance<=math.ceil(math.max(0,at-(r.seenAt or at))/60)+2
        local sameInvoice=(r.deposit==nil or deposit==nil or r.deposit==deposit)and(r.fee==nil or fee==nil or r.fee==fee)
        if r.base==base and drift and sameInvoice and not session.used[r.fingerprint]then
            if r.buyer==buyer then exact[#exact+1]=r
            elseif r.buyer=='' or buyer=='' then compatible[#compatible+1]=r end
        end
    end
    local r=exact[1]or(#compatible==1 and compatible[1])
    if r then session.used[r.fingerprint]=true;return r.fingerprint end
end
function mailboxReceipts.Remember(r)
    session.used[r.fingerprint]=true;session.next[#session.next+1]=r
end
function mailboxReceipts.Retired(fingerprint)return AZPCForeverDB.retiredMailReceipts[fingerprint]end
function mailboxReceipts.End(incomplete)
    if not session then return end
    if incomplete or session.partial or session.count==0 and clock()<=session.resumeUntil then
        for _,r in ipairs(session.entries)do if not session.used[r.fingerprint]then session.next[#session.next+1]=r end end
    else
        for _,r in ipairs(session.entries)do if not session.used[r.fingerprint]then AZPCForeverDB.retiredMailReceipts[r.fingerprint]=true end end
    end
    session.entries=session.next;session.next=nil;session.used=nil
    if session.count>0 and not incomplete and not session.partial then session.resumeUntil=0 end
end
local f=CreateFrame('Frame')
for _,event in ipairs({'MAIL_SHOW','MAIL_CLOSED','PLAYER_LOGOUT'})do pcall(f.RegisterEvent,f,event)end
f:SetScript('OnEvent',function(_,event)
    if event=='MAIL_SHOW'then mailboxReceipts.Open()
    elseif event=='MAIL_CLOSED'then
        local ok,saved=pcall(checkpoint);closedCheckpoint=ok and saved or nil;open=false;session=nil
    elseif event=='PLAYER_LOGOUT'then
        local ok,saved
        if open then ok,saved=pcall(checkpoint)
        elseif closedCheckpoint and clock()-closedCheckpoint.at<=5 then ok,saved=true,closedCheckpoint end
        AZPCForeverDB.mailReloadCheckpoint=ok and saved or nil
    end
end)
end
-- END AZPC MAIL RELOAD CHECKPOINT
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
    if AZPCForeverSyncPrompt then AZPCForeverSyncPrompt.BeginCapture() end
    local occurrences,usedFingerprints = {},{}
    local count,total = GetInboxNumItems();count=count or 0
    mailboxReceipts.Begin(table.concat({guid,realm,region,faction},':'),count,total)
    local incomplete=false
    for index=1,count do
        local invoice, itemName, otherPlayer, bid, buyout, deposit, fee, delay, hour, minute, invoiceCount = GetInboxInvoiceInfo(index)
        local _, _, sender, subject, money, cod, daysLeft = GetInboxHeaderInfo(index)
        -- Headers can load before seller invoice details after a UI reload.
        -- An unresolved monetary mail is not proof that an old receipt left.
        if not invoice and number(money)and money>0 then incomplete=true end
        -- Preserve 0.1.1/0.1.2 mailbox identities while fixing the export shape.
        -- Those versions included gsub's subject replacement count in the fingerprint.
        local _, subjectEscapes = tostring(subject or ""):gsub("([^%w%-_%.])", "")
        local returnedName = expiredSubject(subject)
        if returnedName and number(money)==0 and number(cod)==0 then invoice="expired" end
        local resolved=false
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
            local copper = invoice == "expired" and 0 or (invoice == "buyer" and number(bid) or number(money))
            -- Buyer Amount Paid is bid, exactly as displayed by Blizzard MailFrame.
            -- buyout can be a different field value; never substitute it for actual payment.
            -- Missing item ID/count or delayed seller proceeds stay unresolved; never assume one item.
            if number(id) and id>0 and quantity and quantity>0 and copper and (copper>0 or invoice=="expired") and name and not (number(delay) and delay>0) then
                local expiry=0
                if type(daysLeft)=="number" and daysLeft>0 then expiry=math.floor((timestamp+daysLeft*86400+30)/60) end
                if invoice=="expired" then
                    local base=table.concat({guid,realm,region,id,quantity,encode(sender),encode(subject),subjectEscapes},":")
                    expiry=expiredExpiry(base,timestamp,daysLeft) or 0
                end
                if expiry>0 then
                    local base=table.concat({guid,realm,region,invoice,id,quantity,copper,encode(sender),encode(subject),subjectEscapes},':')
                    local estimateExpiry=expiry
                    local reused=invoice=='seller'and mailboxReceipts.Match(base,encode(otherPlayer),expiry,timestamp,number(deposit),number(fee))
                    if invoice~="expired" and not reused then
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
                    if invoice=='seller' and otherPlayer and otherPlayer~='' then
                        local unnamed=table.concat({guid,realm,region,invoice,id,quantity,copper,expiry,'',encode(sender),encode(subject),subjectEscapes},':')..':'..occurrences[fingerprint:match('^(.*):%d+$')]
                        if AZPCForeverDB.tradeSeen[unnamed]then fingerprint=unnamed end
                    end
                    if reused then fingerprint=reused
                    else
                        local stem=fingerprint:match('^(.*):%d+$');local occurrence=tonumber(fingerprint:match(':(%d+)$'))
                        while usedFingerprints[fingerprint]or mailboxReceipts.Retired(fingerprint)do occurrence=occurrence+1;fingerprint=stem..':'..occurrence end
                    end
                    usedFingerprints[fingerprint]=true
                    local oldExport=encode(fingerprint)
                    local existing
                    if AZPCForeverDB.tradeSeen[fingerprint] then
                        for _,saved in ipairs(AZPCForeverDB.trades) do
                            if saved.tradeExport:find("|"..oldExport.."|",1,true) then existing=saved;break end
                        end
                    end
                    if not AZPCForeverDB.tradeSeen[fingerprint] or existing then
                        -- Receipts must never be blocked by the shared snapshot history count.
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
                            local receipt=existing or {tradeExport=export}
                            if receipt.tradeExport~=export and AZPCForeverCrafting and AZPCForeverCrafting.InvalidateCosts then AZPCForeverCrafting.InvalidateCosts()end
                            receipt.tradeExport=export
                            receipt.invoiceEvidence={schema=1,invoiceType=invoice,bid=number(bid),buyout=number(buyout),invoiceCount=number(invoiceCount),attachmentQuantity=quantity,amountSource=invoice=='buyer' and 'invoice_bid' or 'mail_money',observedAt=timestamp*1000}
                            if not existing then AZPCForeverDB.trades[#AZPCForeverDB.trades+1]=receipt;if AZPCForeverCrafting and AZPCForeverCrafting.InvalidateCosts then AZPCForeverCrafting.InvalidateCosts()end end
                            local fresh=not AZPCForeverDB.tradeSeen[fingerprint]
                            AZPCForeverDB.tradeSeen[fingerprint]=true
                            resolved=true
                            if invoice=='seller'then mailboxReceipts.Remember({base=base,buyer=encode(otherPlayer),fingerprint=fingerprint,index=index,name=name,quantity=quantity,amount=copper,sender=sender,subject=subject,deposit=number(deposit),fee=number(fee),estimateExpiry=estimateExpiry,seenAt=timestamp})end
                            if invoice=='seller' and AZPCForeverSyncPrompt then AZPCForeverSyncPrompt.ObserveSale(index,fingerprint,copper) end
                            if fresh then
                                if AZPCForeverSyncPrompt and (invoice=="seller" or invoice=="expired") then AZPCForeverSyncPrompt.MarkDirty() end
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
                    end
                end
            end
        end
        if invoice=='seller' and not resolved then incomplete=true end
    end
    mailboxReceipts.End(incomplete)
    if AZPCForeverSyncPrompt then AZPCForeverSyncPrompt.EndCapture() end
end
captureTrades=perf.Wrap("Mailbox capture",captureTrades)
for _, event in ipairs({"MAIL_SHOW","MAIL_INBOX_UPDATE"}) do pcall(tradeFrame.RegisterEvent,tradeFrame,event) end
tradeFrame:SetScript("OnEvent",function(_,event)
    if event=='MAIL_SHOW'then mailboxReceipts.Open()end
    local ok,err=pcall(captureTrades);if not ok then message("Mailbox capture unavailable: "..tostring(err))end
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
    AZPCForeverDB.trades[#AZPCForeverDB.trades+1]={tradeExport=table.concat(fields,"|")}
    if AZPCForeverCrafting and AZPCForeverCrafting.InvalidateCosts then AZPCForeverCrafting.InvalidateCosts()end
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
    for bag=0,(NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
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
captureBags=perf.Wrap("Bag scan",captureBags)
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
    if AZPCForeverCrafting and AZPCForeverCrafting.InvalidateCosts then AZPCForeverCrafting.InvalidateCosts()end
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
    if AZPCForeverCrafting.InvalidateCosts then AZPCForeverCrafting.InvalidateCosts()end
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
    if AZPCForeverProfession and AZPCForeverProfession.CaptureCatalog then AZPCForeverProfession.CaptureCatalog(ids)end
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
AZPCForeverCrafting={ReadRecipe=recipe,Status=function()
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
    if f[1]~='AZPCFTRADE' or (f[2]~='1' and f[2]~='2') or (f[4]~='buy' and f[4]~='sell' and f[4]~='inventory_snapshot') then return end
    if not ((f[2]=='1' and (#f==13 or #f==14)) or (f[2]=='2' and #f==21)) then return end
    local id,q,c,at,region=tonumber(f[5]),tonumber(f[7]),tonumber(f[8]),tonumber(f[9]),canonicalRegion(tonumber(f[12]),decode(f[10]))
    if not integer(id,10000000) or id<1 or not integer(q,1000000) or q<(f[4]=='inventory_snapshot' and 0 or 1) or not integer(c) or not integer(at,4102444800000) or not integer(region,100) or region<1 then return end
    local e={kind=f[4],itemId=id,quantity=q,copper=c,observedAt=f[2]=='1' and at*1000 or at,eventId='mail:'..f[3],realm=decode(f[10]),faction=f[11],region=region,character=decode(f[13]),name=decode(f[6])}
    if e.realm=='' or e.character=='' or (e.faction~='horde' and e.faction~='alliance') then return end
    -- Apply verified legacy payment evidence to working costs, retaining raw exports.
    if e.kind=='buy' and e.itemId==2318 and e.quantity==1 and e.copper==1 and e.character=='Wet' and e.realm=='Classic Beta PvP 2' and e.region==90 and e.faction=='horde' then
        local receipt=decode(f[3])
        if receipt=="Player-4613-008756AB:Classic Beta PvP 2:90:buyer:2318:1:1:29901904:Drox%20Pvp:Horde%20Auction%20House:Auction%20won%3A%20Light%20Leather:4:1" and e.observedAt==1791522259000 then e.copper=48;e.purchaseCostKnown=true
        elseif receipt=="Player-4613-008756AB:Classic Beta PvP 2:90:buyer:2318:1:1:29901896:Evade%20Dex:Horde%20Auction%20House:Auction%20won%3A%20Light%20Leather:4:1" and e.observedAt==1791521790000 then e.purchaseCostKnown=false end
    end
    if e.kind=='buy' and e.itemId==2318 and e.quantity==20 and e.copper==40 and e.observedAt==1791301099000 and e.character=='Wet' and e.region==90 and e.realm=='Classic Beta PvP 2' and e.faction=='horde' and decode(f[3])=="Player-4613-008756AB:Classic Beta PvP 2:90:buyer:2318:20:40:29898218::Horde%20Auction%20House:Auction%20won%3A%20Light%20Leather%20%2840%29:7:1" then e.purchaseCostKnown=false end
    local prefix,expiry,suffix=decode(f[3]):match('^(.*:seller:%d+:%d+:%d+:)(%d+)(:[^:]*:[^:]*:[^:]*:%d+:%d+)$')
    if not prefix then prefix,expiry,suffix=decode(f[3]):match('^(.*:buyer:%d+:%d+:%d+:)(%d+)(:[^:]*:[^:]*:[^:]*:%d+:%d+)$')end
    if prefix then e.mailIdentity=prefix..suffix;e.mailExpiry=tonumber(expiry);if e.kind=='buy'then e.mailPurchaseIdentity=prefix:gsub('(:buyer:%d+:)%d+:(%d+:)$','%1%2')..suffix end end
    if prefix then local buyer,rest=suffix:match('^:([^:]*)(:.*)$');e.mailBuyerKnown=buyer~='';e.mailEnvelope=prefix..rest end
    return e
end
local parsedMail=setmetatable({},{__mode="k"})
local function rebuild(db,tradeRows,step,deferred)
    db=db or AZPCForeverDB.crafting
    tradeRows=tradeRows or AZPCForeverDB.trades or {}
    step=step or function()end
    if db.vendorCostingBlocked then error('Vendor ledger capacity reached; material costs cannot currently be verified.')end
    local events,seen,mailAnchors={},{},{}
    local receipts={}
    for _,row in ipairs(tradeRows)do step();
        local cached=parsedMail[row]
        if not cached or cached.export~=row.tradeExport then cached={export=row.tradeExport,event=mail(row.tradeExport)};parsedMail[row]=cached end
        if cached.event then receipts[#receipts+1]=cached.event end
    end
    table.sort(receipts,function(a,b)return a.observedAt<b.observedAt or a.observedAt==b.observedAt and a.eventId<b.eventId end)
    local purchases,envelopes={},{}
    for _,e in ipairs(receipts)do step();
        if e.kind=='buy' and e.quantity~=e.copper and e.mailPurchaseIdentity then local a=purchases[e.mailPurchaseIdentity]or{};purchases[e.mailPurchaseIdentity]=a;a[#a+1]=e end
        if e.mailBuyerKnown and e.mailEnvelope then local a=envelopes[e.mailEnvelope]or{};envelopes[e.mailEnvelope]=a;a[#a+1]=e end
    end
    for _,e in ipairs(receipts)do step();
        local duplicate=false
        if e.kind=='buy' and e.quantity==e.copper and e.mailPurchaseIdentity then
            local matches={};local count=0
            for _,other in ipairs(purchases[e.mailPurchaseIdentity]or{})do step();
                if other.kind=='buy' and other.quantity~=e.quantity and other.mailPurchaseIdentity==e.mailPurchaseIdentity and other.copper==e.copper and math.abs(other.observedAt-e.observedAt)<=5000 and math.abs(other.mailExpiry-e.mailExpiry)<=2 and not matches[other.mailIdentity]then matches[other.mailIdentity]=true;count=count+1 end
            end
            duplicate=count==1
        end
        if e.kind=='sell' and e.mailEnvelope and not e.mailBuyerKnown then
            local matches={};local count=0
            for _,other in ipairs(envelopes[e.mailEnvelope]or{})do step();
                if other.mailBuyerKnown and other.mailEnvelope==e.mailEnvelope and other.copper==e.copper and math.abs(other.observedAt-e.observedAt)<=5000 and math.abs(other.mailExpiry-e.mailExpiry)<=2 and not matches[other.mailIdentity]then matches[other.mailIdentity]=true;count=count+1 end
            end
            duplicate=count==1
        end
        if e.mailIdentity and not duplicate then
            local anchors=mailAnchors[e.mailIdentity] or {};mailAnchors[e.mailIdentity]=anchors
            for _,old in ipairs(anchors)do step(); if math.abs(old.mailExpiry-e.mailExpiry)<=2 and old.copper==e.copper then duplicate=true;break end end
            if not duplicate then anchors[#anchors+1]=e end
        end
        if not duplicate and not seen[e.eventId] then seen[e.eventId]=true;events[#events+1]=e end
    end
    for _,e in ipairs(db.vendorEvents or {})do step();
        if type(e.eventId)=='string' and not seen[e.eventId] and (e.kind=='buy' or e.kind=='sell' or e.kind=='vendor_unresolved') and integer(e.itemId,10000000) and e.itemId>0 and integer(e.quantity,1000000) and e.quantity>0 and integer(e.copper) then
            seen[e.eventId]=true;events[#events+1]=e
        end
    end
    for _,e in ipairs(db.materialEvents or {})do step();
        if e.kind~='request_rejected' and type(e.eventId)=='string' and not seen[e.eventId]then seen[e.eventId]=true;events[#events+1]=e end
    end
    for _,r in ipairs(db.crafts) do step();
        if type(r.eventId)=='string' and not seen[r.eventId] then
            seen[r.eventId]=true;events[#events+1]={kind='craft',itemId=r.itemId,quantity=r.quantity,observedAt=r.observedAt,eventId=r.eventId,realm=r.realm,faction=r.faction,region=r.region,character=r.character,name=r.name,record=r}
        end
    end
    -- Canonicalize working copies only; retain original saved region evidence.
    for i,e in ipairs(events)do step();
        local region=canonicalRegion(e.region,e.realm)
        if region~=e.region then local copy={};for k,v in pairs(e)do step(); copy[k]=v end;copy.region=region;events[i]=copy end
    end
    local rank={buy=1,free=1,transfer_out=2,transfer_in=2,craft=3,sell=4,vendor_unresolved=5,reconcile=6,inventory_observation=7,inventory_snapshot=8}
    table.sort(events,function(a,b)if a.observedAt~=b.observedAt then return a.observedAt<b.observedAt end;if rank[a.kind]~=rank[b.kind] then return rank[a.kind]<rank[b.kind] end;return a.eventId<b.eventId end)
    local pools={};local transit={};local unresolved=0;local updates={}
    local function pool(e,id)
        local key=market(e)..'|'..id
        if not pools[key] then pools[key]={key=key,itemId=id,realm=e.realm,character=e.character,faction=e.faction,region=e.region,name=id==e.itemId and e.name or ('Item '..id),lots={}} end
        return pools[key]
    end
    local function totals(p)
        local q,c,known=0,0,not p.uncertain
        for _,l in ipairs(p.lots) do step(); q=q+l.quantity;c=c+(l.copper or l.partialCopper or 0);if l.copper==nil then known=false end end
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
        while wanted>0 and #p.lots>0 do step();
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
        for _,other in ipairs(events)do step(); if other.realm==e.realm and other.region==e.region and other.faction==e.faction then names[normalizedName(other.character)]=true end end
        if names[a]then return false end
        local count,matched=0,nil;for name in pairs(names)do step(); if a:sub(1,#name+1)==name..' 'then count=count+1;matched=name end end
        return count==1 and matched==c
    end
    for _,e in ipairs(events) do step();
        local p=pool(e,e.itemId)
        if e.kind=='buy' then p.lots[#p.lots+1]={quantity=e.quantity,copper=e.purchaseCostKnown~=false and e.copper or nil}
        elseif e.kind=='free' then
            local remaining=e.quantity-e.untrackedQuantity
            local new={}
            for _,l in ipairs(p.lots)do step();
                if l.copper==nil and remaining>0 then
                    if (l.partialCopper or 0)>0 then error('Cannot classify partially paid material stock as free.')end
                    local use=math.min(remaining,l.quantity);l.quantity=l.quantity-use;remaining=remaining-use;new[#new+1]={quantity=use,copper=0}
                end
            end
            if remaining>0 then error('Free classification exceeds unknown material stock.')end
            if e.untrackedQuantity>0 then new[#new+1]={quantity=e.untrackedQuantity,copper=0}end
            for _,l in ipairs(p.lots)do step(); if l.quantity>0 then new[#new+1]=l end end
            -- Adjacent confirmed zero-cash lots have identical FIFO value. Compact
            -- only those lots; paid and partially known lots retain their order.
            local compact={}
            for _,l in ipairs(new)do step(); local last=compact[#compact]
                if last and last.copper==0 and l.copper==0 then last.quantity=last.quantity+l.quantity
                else compact[#compact+1]=l end
            end
            p.lots=compact
        elseif e.kind=='transfer_out' then
            p.costChangedAt=e.observedAt
            local used=average(p,e.quantity);transit[#transit+1]={event=e,quantity=e.quantity,copper=used.complete and used.knownCopper or nil,partialCopper=not used.complete and used.knownCopper or nil}
        elseif e.kind=='transfer_in' then
            local matches={}
            for _,t in ipairs(transit)do step(); local from=t.event
                if not t.received and from.itemId==e.itemId and from.quantity==e.quantity and from.realm==e.realm and from.region==e.region and from.faction==e.faction and sameCharacter(e.counterparty,from.character,from) and sameCharacter(from.counterparty,e.character,e) and from.transferKey==e.transferKey and from.observedAt<=e.observedAt then matches[#matches+1]=t end
            end
            if #matches==1 then local t=matches[1];t.received=true;p.lots[#p.lots+1]={quantity=e.quantity,copper=t.copper,partialCopper=t.partialCopper}
            else p.lots[#p.lots+1]={quantity=e.quantity,partialCopper=0}end
        elseif e.kind=='inventory_observation' then
            if e.confirmation~='bags_and_character_bank_observed' or not integer(e.bagQuantity,1000000) or not integer(e.bankQuantity,1000000) or not integer(e.reservedQuantity,1000000) or e.ownedQuantity~=e.bagQuantity+e.bankQuantity then error('Invalid bank observation.')end
            -- Purchases, loot and crafts enter bags. Bank observations move existing
            -- costs only when the other location has a matching surplus.
            p.bank=p.bank or {lots={}}
            local bank=p.bank;local bagTarget=e.bagQuantity+e.reservedQuantity
            local bq=totals(p);local nq=totals(bank)
            local function move(from,to,quantity)
                if quantity<=0 then return end
                local used=average(from,quantity)
                to.lots[#to.lots+1]={quantity=quantity,copper=used.complete and used.knownCopper or nil,partialCopper=not used.complete and used.knownCopper or nil}
            end
            if nq<e.bankQuantity and bq>bagTarget then move(p,bank,math.min(e.bankQuantity-nq,bq-bagTarget))
            elseif nq>e.bankQuantity and bq<bagTarget then move(bank,p,math.min(nq-e.bankQuantity,bagTarget-bq))end
            bq=totals(p);nq=totals(bank)
            if bagTarget>bq then p.lots[#p.lots+1]={quantity=bagTarget-bq,partialCopper=0}end
            if e.bankQuantity>nq then bank.lots[#bank.lots+1]={quantity=e.bankQuantity-nq,partialCopper=0}end
            local expected=e.ownedQuantity+e.reservedQuantity
            p.bankQuantity=e.bankQuantity;p.bagQuantity=e.bagQuantity;p.bankObservedAt=e.observedAt;p.costChangedAt=e.observedAt
            p.inventoryMismatch=bq+nq>expected and {recorded=bq+nq,observed=expected,at=e.observedAt} or nil
            if bq>bagTarget then p.uncertain=true end
            if nq>e.bankQuantity then bank.uncertain=true end
        elseif e.kind=='reconcile' then
            if not integer(e.targetQuantity,1000000) or not integer(e.totalCopper) or e.targetQuantity==0 and e.totalCopper~=0 or e.confirmation~='inventory_and_cost_reconciled' then error('Invalid material reconciliation.') end
            p.lots=e.targetQuantity>0 and {{quantity=e.targetQuantity,copper=e.totalCopper}} or {};p.uncertain=nil;p.bank=nil;p.bankQuantity=nil;p.bagQuantity=nil;p.bankObservedAt=nil;p.inventoryMismatch=nil
        elseif e.kind=='inventory_snapshot' then p.observedBagQuantity=e.quantity;p.observedBagAt=e.observedAt
        elseif e.kind=='sell' then sale(p,e.quantity);p.costChangedAt=e.observedAt
        elseif e.kind=='vendor_unresolved' then p.uncertain=true
        else
            local r=e.record;local inputs,missing,partial,complete={},{},0,r.materialsKnown==true and type(r.consumedReagents)=='table'
            local demand={}
            if complete then
                for _,m in ipairs(r.consumedReagents) do step();
                    if not integer(m.itemId,10000000) or m.itemId<1 or not integer(m.quantity,1000000) then complete=false;break end
                    demand[m.itemId]=(demand[m.itemId] or 0)+m.quantity
                end
            end
            if complete and next(demand) then
                local ids={};for id in pairs(demand)do step(); ids[#ids+1]=id end;table.sort(ids)
                for _,id in ipairs(ids) do step();
                    local material=pool(e,id)
                    if material.bank and material.observedBagAt and material.observedBagAt>(material.costChangedAt or -1)then
                        local bagQ=totals(material)
                        if material.observedBagQuantity>bagQ then material.lots[#material.lots+1]={quantity=material.observedBagQuantity-bagQ,partialCopper=0}end
                    end
                    local used=average(material,demand[id]);material.costChangedAt=e.observedAt;used.itemId=id;inputs[#inputs+1]=used;partial=partial+used.knownCopper
                    if not used.complete then complete=false;missing[#missing+1]={itemId=id,quantity=demand[id],recordedQuantity=used.recordedQuantity,reason=used.recordedQuantity<demand[id] and 'purchase_cost_missing' or 'upstream_cost_unresolved'} end
                end
            else
                complete=false
                -- Without reliable consumption, these candidate material pools cannot establish later costs.
                local candidates={}
                for _,m in ipairs(r.recipeReagents or {})do step(); candidates[m.itemId]=true end
                for _,id in ipairs(r.candidateItemIds or {})do step(); candidates[id]=true end
                local catalog=db.recipes[r.recipeKey]
                for _,slot in ipairs(catalog and catalog.reagentSlots or {})do step(); for _,option in ipairs(slot.options or {})do step(); if option.itemId then candidates[option.itemId]=true end end end
                for id in pairs(candidates)do step(); pool(e,id).uncertain=true end
                missing[#missing+1]={reason='material_usage_unresolved'}
            end
            if partial>MAX then error('Craft cost exceeds the supported exact range.') end
            local old=r.costBasis
            local conflict=old and old.complete and (not complete or old.totalCopper~=partial) or false
            if conflict then complete=false;missing[#missing+1]={reason='saved_cost_conflict'} end
            local basis=old and old.complete and old or {schema=1,method='remaining_material_weighted_average',scope='bags',complete=complete,totalCopper=complete and partial or nil,recordedCopper=partial,outputQuantity=e.quantity,inputs=inputs,missing=missing,costedAt=r.observedAt}
            updates[#updates+1]={record=r,basis=basis,conflict=conflict,missing=missing}
            if not complete then unresolved=unresolved+1 end
            p.lots[#p.lots+1]={quantity=e.quantity,copper=complete and basis.totalCopper or nil,partialCopper=not complete and partial or nil}
        end
    end
    local positions={}
    for _,p in pairs(pools) do step();
        local q,c,known=totals(p)
        local bagQ,bagC,bagKnown=q,c,known
        local bankQ,bankC,bankKnown=0,0,true
        if p.bank then bankQ,bankC,bankKnown=totals(p.bank);q=q+bankQ;c=c+bankC;known=known and bankKnown end
        if c>MAX or q>10000000000 then error('Material cost totals exceed the supported exact range.')end
        local allLots={};for _,l in ipairs(p.lots)do step(); allLots[#allLots+1]=l end;for _,l in ipairs(p.bank and p.bank.lots or {})do step(); allLots[#allLots+1]=l end
        if q>0 then positions[#positions+1]={key=p.key,itemId=p.itemId,name=p.name,realm=p.realm,character=p.character,faction=p.faction,region=p.region,quantity=q,bagLedgerQuantity=bagQ,bagRecordedCopper=bagC,bagCostComplete=bagKnown,bankLedgerQuantity=bankQ,bankRecordedCopper=bankC,bankCostComplete=bankKnown,bagQuantity=p.bagQuantity,bankQuantity=p.bankQuantity,bankObservedAt=p.bankObservedAt,inventoryMismatch=p.inventoryMismatch,costComplete=known,totalCopper=known and c or nil,recordedCopper=c,unknownQuantity=(function()local n=0;for _,l in ipairs(allLots)do step(); if l.copper==nil then n=n+l.quantity end end;return n end)(),unknownRecordedCopper=(function()local n=0;for _,l in ipairs(allLots)do step(); if l.copper==nil then n=n+(l.partialCopper or 0)end end;return n end)()} end
    end
    table.sort(positions,function(a,b)return a.key<b.key end)
    local state={schema=1,method='remaining_material_weighted_average',positions=positions,unresolvedCrafts=unresolved}
    if deferred then return state,updates end
    for _,u in ipairs(updates)do step(); u.record.costBasis=u.basis;u.record.costConflict=u.conflict;u.record.costingMissing=u.missing end
    db.costing=state
    return state
end
local computeCosts=rebuild
rebuild=perf.Wrap("Cost replay",rebuild)
-- Automatic updates use isolated evidence and publish only after validation.
-- Explicit requests and logout keep the original synchronous rebuild/export path.
local job,queued,lastEvidence,lastRoot=nil,false,nil,nil
local epoch,revision=0,0
AZPCForeverCrafting.InvalidateCosts=function()revision=revision+1 end
local worker=CreateFrame('Frame')
local function evidence()
    local root=AZPCForeverDB;local d=root and root.crafting
    if not d then return end
    return {trades=root.trades or {},recipes=d.recipes or {},crafts=d.crafts or {},vendorEvents=d.vendorEvents or {},materialEvents=d.materialEvents or {},vendorCostingBlocked=d.vendorCostingBlocked}
end
-- Invoice display/enrichment metadata is not an input to local costing; the
-- exact tradeExport already contains the receipt evidence used by replay.
local function evidenceField(k)return k~='syncExport' and k~='costingMissing' and k~='invoiceEvidence'end
local function copyEvidence(value,step,depth)
    if type(value)~='table'then return value end
    depth=depth or 0;if depth>16 then error('Cost evidence exceeds nesting limit.')end
    local result={}
    for k,v in pairs(value)do
        step()
        if evidenceField(k)then result[k]=copyEvidence(v,step,depth+1)end
    end
    return result
end
local function sameEvidence(a,b,depth,step)
    if type(a)~=type(b)then return false end
    if type(a)~='table'then return a==b end
    depth=depth or 0;if depth>16 then return false end
    for k,v in pairs(a)do if step then step()end;if evidenceField(k)and not sameEvidence(v,b[k],depth+1,step)then return false end end
    for k in pairs(b)do if step then step()end;if evidenceField(k)and a[k]==nil then return false end end
    return true
end
local function stopJob()
    epoch=epoch+1;job=nil;queued=false
    worker:SetScript('OnUpdate',nil)
end
AZPCForeverCrafting.RebuildCosts=function()
    stopJob();lastEvidence=nil;lastRoot=nil
    if not AZPCForeverDB or not AZPCForeverDB.crafting then return end
    local ok,state=pcall(rebuild)
    if not ok then AZPCForeverDB.crafting.costingError=tostring(state);return nil,state end
    AZPCForeverDB.crafting.costingError=nil;return state
end
local function supported()
    return type(GetTimePreciseSec)=='function' and type(coroutine)=='table' and type(coroutine.create)=='function' and type(coroutine.resume)=='function'
end
local function now()
    local ok,value=pcall(GetTimePreciseSec)
    if ok and type(value)=='number' and value==value then return value end
end
local function publishExports()
    if AZPCForeverCrafting.ExportCosts then AZPCForeverCrafting.ExportCosts()end
end
local startJob
local function advance()
    local current=job;if not current then worker:SetScript('OnUpdate',nil);return end
    current.started=now();current.work=0
    local ok,result=coroutine.resume(current.thread)
    if not ok then
        job=nil;worker:SetScript('OnUpdate',nil)
        if AZPCForeverDB==current.root and AZPCForeverDB.crafting then
            AZPCForeverDB.crafting.costingError=tostring(result);publishExports()
        end
        return
    end
    if coroutine.status(current.thread)~='dead'then return end
    job=nil;worker:SetScript('OnUpdate',nil)
    local live=current.root and current.root.crafting
    local valid=AZPCForeverDB==current.root and live==current.db and revision==current.revision and not result.stale
    if valid then
        valid=current.trades==current.root.trades and current.crafts==live.crafts and current.materials==live.materialEvents and current.vendors==live.vendorEvents and current.recipes==live.recipes
            and #(current.root.trades or {})==#result.snapshot.trades and #(live.crafts or {})==#result.snapshot.crafts and #(live.materialEvents or {})==#result.snapshot.materialEvents and #(live.vendorEvents or {})==#result.snapshot.vendorEvents and live.vendorCostingBlocked==result.snapshot.vendorCostingBlocked
    end
    if not valid then
        -- No partially computed costs have been assigned to live records.
        startJob();return
    end
    if not result.unchanged then
        local d=AZPCForeverDB.crafting;local originals={}
        for i,r in ipairs(result.snapshot.crafts)do originals[r]=d.crafts[i]end
        for _,u in ipairs(result.updates)do
            local r=originals[u.record]
            r.costBasis=u.basis;r.costConflict=u.conflict;r.costingMissing=u.missing
            u.record.costBasis=u.basis;u.record.costConflict=u.conflict
        end
        d.costing=result.state;d.costingError=nil
        publishExports()
        -- The existing exporter fills legacy candidate IDs. Include that exact
        -- enrichment in the cache so unchanged mail does not replay once more.
        for i,r in ipairs(result.snapshot.crafts)do
            if not r.candidateItemIds and d.crafts[i].candidateItemIds then
                r.candidateItemIds=copyEvidence(d.crafts[i].candidateItemIds,function()end)
            end
        end
    end
    lastEvidence=result.snapshot;lastRoot=current.root
end
advance=perf.Wrap('Cost replay slice',advance)
startJob=function()
    if not AZPCForeverDB or not AZPCForeverDB.crafting then return end
    local root=AZPCForeverDB;local d=root.crafting
    local current={root=root,db=d,work=0,revision=revision,trades=root.trades,crafts=d.crafts,materials=d.materialEvents,vendors=d.vendorEvents,recipes=d.recipes};job=current
    local function step()
        current.work=current.work+1
        if current.work%32~=0 then return end
        local stamp=now()
        -- A broken/unavailable clock still yields after bounded work.
        if stamp and current.started and stamp-current.started>=0.003 or (not stamp or not current.started)and current.work>=256 then coroutine.yield()end
    end
    current.thread=coroutine.create(function()
        current.phase='snapshot'
        local snapshot=copyEvidence(evidence(),step)
        local unchanged=lastRoot==current.root and lastEvidence and sameEvidence(snapshot,lastEvidence,nil,step)
        local state,updates
        if not unchanged then current.phase='replay';state,updates=computeCosts(snapshot,snapshot.trades,step,true)end
        -- Exact comparison is sliced; revision/ref/count checks immediately before
        -- publication reject any event arriving after an earlier field was checked.
        current.phase='validate'
        local valid=sameEvidence(snapshot,evidence(),nil,step)
        return {snapshot=snapshot,state=state,updates=updates,unchanged=unchanged,stale=not valid}
    end)
    worker:SetScript('OnUpdate',advance)
end
local function schedule()
    if queued or job then return end
    queued=true;local token=epoch
    C_Timer.After(0.25,function()
        if token~=epoch then return end
        queued=false
        if supported()then startJob()else AZPCForeverCrafting.RebuildCosts()end
    end)
end
AZPCForeverCrafting.ScheduleCosts=schedule
AZPCForeverCrafting.CostsPending=function()return queued or job~=nil end
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
    if AZPCForeverCrafting.InvalidateCosts then AZPCForeverCrafting.InvalidateCosts()end
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
 AZPCForeverDB.itemIds=AZPCForeverDB.itemIds or {};if type(name)=='string' and id then AZPCForeverDB.itemIds[name]=id end
 local e=current();e.kind=kind;e.itemId=id;e.quantity=q;e.name=name or ('Item '..id);e.observedAt=observedMillis();e.eventId=eventId or tostring(UnitGUID('player'))..':material:'..e.observedAt..':'..c.materialSequence;e.confirmation='material_quantity_confirmed'
 for k,v in pairs(extra or {})do e[k]=v end;c.materialEvents[#c.materialEvents+1]=e
 if AZPCForeverCrafting.InvalidateCosts then AZPCForeverCrafting.InvalidateCosts()end
 AZPCForeverCrafting.ScheduleCosts();return e
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
local lootWindows,currentLoot={},nil
local function lootPattern(format)
 if type(format)~='string'then return nil end
 local p=format:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])','%%%1')
 p=p:gsub('%%%%s','(.+)'):gsub('%%%%d','(%%d+)')
 return '^'..p..'$'
end
local function confirmLoot()
 local now=GetServerTime and GetServerTime()or time()
 for index,window in ipairs(lootWindows)do
  for id,r in pairs(window.items)do
   local q=r.received-r.recorded
   if q>0 and held(id)-r.base>=q then
    record('free',id,q,r.name,{source='farmed',untrackedQuantity=q,heldQuantity=held(id)})
    r.recorded=r.recorded+q;r.base=r.base+q
    -- Later windows may have opened before the bags reflected this receipt.
    for later=index+1,#lootWindows do local other=lootWindows[later].items[id];if other then other.base=math.max(other.base,r.base)end end
   end
  end
 end
 for i=#lootWindows,1,-1 do
  local window=lootWindows[i]
  if window.closed and now-window.closed>=30 then
   for _,r in pairs(window.items)do if r.received>r.recorded then message('Loot capture unresolved: '..r.name..' (bag confirmation missing).')end end
   table.remove(lootWindows,i)
  end
 end
end
confirmLoot=perf.Wrap("Loot confirmation",confirmLoot)
local function openLoot()
 confirmLoot()
 if currentLoot and not currentLoot.closed then currentLoot.closed=GetServerTime and GetServerTime()or time()end
 currentLoot={items={}};lootWindows[#lootWindows+1]=currentLoot
 for slot=1,(call(GetNumLootItems)or 0)do
  local link=call(GetLootSlotLink,slot);local id=type(link)=='string'and tonumber(link:match('item:(%d+)'))
  local _,name,q=call(GetLootSlotInfo,slot)
  local safe=false
  if type(GetLootSourceInfo)=='function'then
   local sources={GetLootSourceInfo(slot)};safe=#sources>0
   for i=1,#sources,2 do local guid=sources[i];if type(guid)~='string'or not(guid:match('^Creature%-')or guid:match('^Vehicle%-')or guid:match('^GameObject%-'))then safe=false end end
  end
  if safe and id and q and q>0 then
   local r=currentLoot.items[id]
   if r then r.available=r.available+q else currentLoot.items[id]={name=name,available=q,received=0,recorded=0,base=held(id)}end
  end
 end
end
openLoot=perf.Wrap("Loot window scan",openLoot)
local function selfLoot(text)
 if type(text)~='string'or not currentLoot then return end
 local link,q
 local multi=lootPattern(LOOT_ITEM_SELF_MULTIPLE);local single=lootPattern(LOOT_ITEM_SELF)
 if multi then link,q=text:match(multi)end
 if not link and single then link=text:match(single);q=1 end
 local id=link and tonumber(link:match('item:(%d+)'));q=tonumber(q)
 local r=id and currentLoot.items[id]
 if r and q and q>0 then r.received=math.min(r.available,r.received+q);confirmLoot()end
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
  elseif event=='LOOT_SLOT_CLEARED'then confirmLoot()
  elseif event=='CHAT_MSG_LOOT'then selfLoot(arg)
  elseif event=='LOOT_CLOSED'then
   if currentLoot then currentLoot.closed=GetServerTime and GetServerTime()or time()end
   confirmLoot();C_Timer.After(2,confirmLoot);C_Timer.After(30,confirmLoot)
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
local exportCache=setmetatable({},{__mode='k'})
local function exportField(k)return k~='syncExport' and k~='costingMissing'end
local function sameExport(a,b,depth)
    if type(a)~=type(b)then return false end
    if type(a)~='table'then return a==b end
    if depth>12 then return false end
    for k,v in pairs(a)do if exportField(k)and not sameExport(v,b[k],depth+1)then return false end end
    for k in pairs(b)do if exportField(k)and a[k]==nil then return false end end
    return true
end
local function copyExport(v)
    if type(v)~='table'then return v end
    local copy={};for k,x in pairs(v)do if exportField(k)then copy[k]=copyExport(x)end end;return copy
end
local function syncExport(r,kind,id)
    local cached=exportCache[r]
    if cached and cached.kind==kind and cached.id==id and r.syncExport==cached.export and sameExport(r,cached.data,0)then return end
    local payload=json({schema=1,recordType=kind,recordId=id,data=r})
    r.syncExport='AZPCFCRAFT|1|'..encode(payload)
    exportCache[r]={kind=kind,id=id,export=r.syncExport,data=copyExport(r)}
end
local function exports()
    local d=AZPCForeverDB and AZPCForeverDB.crafting;if not d then return end
    for _,r in pairs(d.recipes)do syncExport(r,'recipe',r.recipeKey)end
    for _,r in ipairs(d.crafts)do
        if not r.candidateItemIds then
            local ids={};r.candidateItemIds={};local catalog=d.recipes[r.recipeKey]
            for _,m in ipairs(r.recipeReagents or {})do ids[m.itemId]=true end
            for _,slot in ipairs(catalog and catalog.reagentSlots or {})do for _,option in ipairs(slot.options or {})do if option.itemId then ids[option.itemId]=true end end end
            for id in pairs(ids)do r.candidateItemIds[#r.candidateItemIds+1]=id end;table.sort(r.candidateItemIds)
        end
        syncExport(r,'craft',r.eventId)end
    for _,r in ipairs(d.vendorEvents or {})do syncExport(r,'vendor',r.eventId)end
    for _,r in ipairs(d.materialEvents or {})do syncExport(r,'material',r.eventId)end
end
exports=perf.Wrap("Export generation",exports)
AZPCForeverCrafting.ExportCosts=function()
    local ok,err=pcall(exports)
    local d=AZPCForeverDB and AZPCForeverDB.crafting
    if d then d.syncError=not ok and tostring(err) or nil end
    return ok,err
end
local old=AZPCForeverCrafting.RebuildCosts
AZPCForeverCrafting.RebuildCosts=function()
    local state,err=old();local ok,exportError=pcall(exports)
    if not ok and AZPCForeverDB and AZPCForeverDB.crafting then AZPCForeverDB.crafting.syncError=tostring(exportError)
    elseif AZPCForeverDB and AZPCForeverDB.crafting then AZPCForeverDB.crafting.syncError=nil end
    return state,err
end
AZPCForeverCrafting.RebuildCosts=perf.Wrap("Costs plus exports",AZPCForeverCrafting.RebuildCosts)
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


-- Capture the character bank only while it is actually open. Never read Bagnon caches.
do
local open=false;local generation=0;local last={}
local function readContainers(ids)
 local rows={};local slotAPI=C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
 local infoAPI=C_Container and C_Container.GetContainerItemInfo
 if type(slotAPI)~='function' or type(infoAPI)~='function' and type(GetContainerItemInfo)~='function' then return end
 local capacity=0
 for _,bag in ipairs(ids)do
  local ok,n=pcall(slotAPI,bag);if not ok or type(n)~='number' or n<0 then return end;capacity=capacity+n
  for slot=1,n do
   local id,q,link
   if infoAPI then local ok,v=pcall(infoAPI,bag,slot);if not ok then return end;if v then id,q,link=v.itemID,v.stackCount,v.hyperlink;if v.isLocked then return end end
   else local _,count,locked,_,_,_,l=GetContainerItemInfo(bag,slot);if locked then return end;q=count;link=l;id=type(l)=='string' and tonumber(l:match('item:(%d+)'))end
   if id then
    if type(q)~='number' or q<1 or q~=math.floor(q) then return end
    local name=(C_Item and C_Item.GetItemInfo or GetItemInfo);name=type(name)=='function' and name(id)
    if not name then return end
    local r=rows[id]or{name=name,quantity=0};r.quantity=r.quantity+q;rows[id]=r
   elseif link then return end
  end
 end
 return rows,capacity
end
local function capture()
 if not open then return end;setup()
 if C_Bank and type(C_Bank.CanViewBank)=='function' and Enum and Enum.BankType then local ok,visible=pcall(C_Bank.CanViewBank,Enum.BankType.Character);if not ok or not visible then return end end
 local bags={};local count=NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
 for i=0,count do bags[#bags+1]=i end
 local bank={};local enum=Enum and Enum.BagIndex
 if C_Bank and type(C_Bank.FetchPurchasedBankTabIDs)=='function' and Enum and Enum.BankType and Enum.BankType.Character then
  local ok,ids=pcall(C_Bank.FetchPurchasedBankTabIDs,Enum.BankType.Character);if not ok or type(ids)~='table' then return end
  for _,id in ipairs(ids)do if type(id)~='number' then return end;bank[#bank+1]=id end
 else
  bank[1]=BANK_CONTAINER or enum and enum.Bank or -1
  for i=1,(NUM_BANKBAGSLOTS or 7)do bank[#bank+1]=enum and enum['BankBag_'..i] or count+i end
  local reagent=enum and enum.Reagentbank or REAGENTBANK_CONTAINER
  if reagent then bank[#bank+1]=reagent end
 end
 local bagRows=readContainers(bags);local bankRows,capacity=readContainers(bank)
 if not bagRows or not bankRows or capacity==0 and #bank>0 then return end
 local k=ownerKey();if not k then return end
 local previous=last[k]or{};local ids={};for id in pairs(bagRows)do ids[id]=true end;for id in pairs(bankRows)do ids[id]=true end;for id in pairs(previous)do ids[id]=true end
 local pending={};local at=observedMillis();local states=AZPCForeverDB.owners and AZPCForeverDB.owners[k]or{}
 for id in pairs(ids)do
  local bag,bank=bagRows[id],bankRows[id];local b,n=bag and bag.quantity or 0,bank and bank.quantity or 0
  local getter=C_Item and C_Item.GetItemCount or GetItemCount
  local verified=true
  if type(getter)=='function' then local ok,total=pcall(getter,id,true,false,false);verified=ok and type(total)=='number' and total==b+n end
  -- Equipped copies can differ from bag+bank counts; do not block other materials.
  if verified then
  local old=previous[id];local owner=states[id];local reserved=owner and ((owner.listed or 0)+(owner.pending or 0)+(owner.unresolved or 0))or 0
  local name=bag and bag.name or bank and bank.name or old and old.name
  if not old or old.bag~=b or old.bank~=n or old.reserved~=reserved or at-old.at>1800000 then
   pending[#pending+1]={id=id,name=name,bag=b,bank=n,reserved=reserved}
  end
  end
 end
 local d=AZPCForeverDB.crafting;if not d then return end;d.materialEvents=d.materialEvents or{}
 if #d.materialEvents+#pending>10000 then message('Material ledger full; bank observation deferred.');return end
 for _,r in ipairs(pending)do
  d.materialSequence=(d.materialSequence or 0)+1
  local e={schema=1,kind='inventory_observation',confirmation='bags_and_character_bank_observed',itemId=r.id,name=r.name,quantity=math.max(1,r.bag+r.bank),ownedQuantity=r.bag+r.bank,bagQuantity=r.bag,bankQuantity=r.bank,reservedQuantity=r.reserved,observedAt=at,realm=GetRealmName(),character=UnitName('player'),faction=UnitFactionGroup('player'):lower(),region=currentRegion(),eventId=tostring(UnitGUID('player'))..':bank:'..at..':'..d.materialSequence}
  d.materialEvents[#d.materialEvents+1]=e;if AZPCForeverCrafting.InvalidateCosts then AZPCForeverCrafting.InvalidateCosts()end;previous[r.id]={name=r.name,bag=r.bag,bank=r.bank,reserved=r.reserved,at=at}
 end
 last[k]=previous
 if #pending>0 then AZPCForeverCrafting.RebuildCosts()end
end
local frame=CreateFrame('Frame')
for _,event in ipairs({'BANKFRAME_OPENED','BANKFRAME_CLOSED','PLAYERBANKSLOTS_CHANGED','BAG_UPDATE_DELAYED','PLAYER_LOGOUT'})do pcall(frame.RegisterEvent,frame,event)end
frame:SetScript('OnEvent',function(_,event)
 if event=='BANKFRAME_CLOSED' then open=false;generation=generation+1;return end
 if event=='BANKFRAME_OPENED' then open=true;generation=generation+1 end
 if not open then return end
 if event=='PLAYER_LOGOUT' then pcall(capture);return end
 local g=generation;C_Timer.After(1,function()if open and generation==g then local ok,err=pcall(capture);if not ok then message('Bank capture deferred: '..tostring(err))end end end)
end)
end

-- BEGIN AZPC ITEM TOOLTIPS
-- Add information through supported tooltip hooks; never replace another addon's scripts.
do
    local function money(value)
        local sign=value<0 and '-' or '';value=math.abs(value)
        if type(GetCoinTextureString)=='function' then return sign..GetCoinTextureString(value) end
        local parts={}
        for _,coin in ipairs({{10000,'Gold'},{100,'Silver'},{1,'Copper'}}) do
            local amount=math.floor(value/coin[1]);value=value%coin[1]
            if amount>0 or (coin[1]==1 and #parts==0) then
                parts[#parts+1]=amount..'|TInterface\\MoneyFrame\\UI-'..coin[2]..'Icon:0:0:2:0|t'
            end
        end
        return sign..table.concat(parts,' ')
    end
    local function scope()
        local realm=GetRealmName and GetRealmName() or ''
        local faction=UnitFactionGroup and (UnitFactionGroup('player') or ''):lower() or ''
        local character=UnitName and UnitName('player') or ''
        return table.concat({currentRegion(),realm:lower(),faction},'|'),realm,faction,character
    end
    local function add(tooltip,label,value,r,g,b)
        if type(tooltip.AddDoubleLine)=='function' then tooltip:AddDoubleLine(label,value,1,0.82,0,r or 0.9,g or 0.95,b or 0.95)
        else tooltip:AddLine(label..': '..value,r or 0.9,g or 0.95,b or 0.95,true) end
    end
    local function append(tooltip,itemId)
        itemId=number(itemId)
        if not itemId or itemId<=0 or not tooltip or type(tooltip.AddLine)~='function' then return end
        if tooltip.azpcForeverItem==itemId then return end
        tooltip.azpcForeverItem=itemId
        local db=AZPCForeverDB or {}
        local key,realm,faction,character=scope()
        local price=db.tooltipPrices and db.tooltipPrices[key] and db.tooltipPrices[key][itemId]
        local now=GetServerTime and GetServerTime() or time()
        local valid=price and number(price.unitCopper) and price.unitCopper>0 and number(price.observedAt) and price.observedAt<=now
        local age
        if valid then
            age=now-price.observedAt
            add(tooltip,'AZPC Auction / each'..(age>3600 and ' (stale)' or ''),money(price.unitCopper))
        else add(tooltip,'AZPC Auction / each','No data',0.65,0.65,0.65) end
        local materials=db.crafting;local cost
        if materials and not materials.costingError and not materials.vendorCostingBlocked then
            for _,p in ipairs(materials.costing and materials.costing.positions or {}) do
                if p.itemId==itemId and p.region==currentRegion() and p.realm==realm and p.faction==faction and p.character==character and p.quantity and p.quantity>0 then
                    if p.costComplete==true and not p.inventoryMismatch and number(p.totalCopper) then cost=math.ceil(p.totalCopper/p.quantity) end
                    break
                end
            end
        end
        add(tooltip,'AZPC Cost / each',cost~=nil and money(cost) or 'No data')
        if valid and cost~=nil and age<=21600 then
            local profit=math.floor(price.unitCopper*95/100)-cost
            add(tooltip,'AZPC Est. profit / each*',money(profit),profit>=0 and 0.5 or 1,profit>=0 and 0.86 or 0.5,profit>=0 and 0.65 or 0.45)
            tooltip:AddLine('*After 5% AH cut; excludes deposit.',0.55,0.55,0.55)
        else add(tooltip,'AZPC Est. profit / each','No data',0.65,0.65,0.65) end
        if type(tooltip.Show)=='function' then tooltip:Show() end
    end
    local function clear(tooltip)tooltip.azpcForeverItem=nil end
    local function legacy(tooltip)
        if type(tooltip.GetItem)~='function' then return end
        local _,link=tooltip:GetItem()
        if type(issecretvalue)=='function' and issecretvalue(link) then return end
        if type(link)=='string' then append(tooltip,link:match('item:(%d+)')) end
    end
    for _,tooltip in ipairs({GameTooltip,ItemRefTooltip,ShoppingTooltip1,ShoppingTooltip2}) do
        if type(tooltip.HookScript)=='function' then pcall(tooltip.HookScript,tooltip,'OnTooltipCleared',clear) end
    end
    local modern=false
    if TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall)=='function' and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        modern=pcall(TooltipDataProcessor.AddTooltipPostCall,Enum.TooltipDataType.Item,function(tooltip,data)
            local ok,err=pcall(append,tooltip,data and data.id)
            if not ok then clear(tooltip) end
        end)
    end
    if not modern then
        for _,tooltip in ipairs({GameTooltip,ItemRefTooltip,ShoppingTooltip1,ShoppingTooltip2}) do
            if type(tooltip.HookScript)=='function' then pcall(tooltip.HookScript,tooltip,'OnTooltipSetItem',function(t)local ok=pcall(legacy,t);if not ok then clear(t) end end) end
        end
    end
end
-- END AZPC ITEM TOOLTIPS

-- BEGIN AZPC PROFESSION PANEL
do
    local panel,selected,quantity,auctionOpen,elapsed=nil,nil,1,false,0
    local scan,render,ownQuery,pendingAuto
    local completedQuotes={}
    local page,ensurePage,refreshBrowser
    local filterProfession,filterText=nil,''
    local tab='ah'
    local function notify(text)print('|cff4cddd4AZPC:|r '..text)end
    local function api(object,name,...)
        if object and type(object[name])=='function' then local ok,value=pcall(object[name],...);if ok then return value end end
    end
    local function itemName(id)
        return (GetItemInfo and GetItemInfo(id)) or (C_Item and api(C_Item,'GetItemNameByID',id)) or ('Item '..id)
    end
    local function money(copper,iconSize)
        if copper==nil then return 'No data' end
        local sign=copper<0 and '-' or '';copper=math.abs(copper)
        local parts={}
        for _,coin in ipairs({{10000,'Gold'},{100,'Silver'},{1,'Copper'}})do
            local amount=math.floor(copper/coin[1]);copper=copper%coin[1]
            if amount>0 or (coin[1]==1 and #parts==0)then
                parts[#parts+1]=amount..'|TInterface\\MoneyFrame\\UI-'..coin[2]..'Icon:'..(iconSize or 12)..':'..(iconSize or 12)..':1:0|t'
            end
        end
        return sign..table.concat(parts,' ')
    end
    local function count(id)
        local value
        if C_Item and type(C_Item.GetItemCount)=='function' then value=api(C_Item,'GetItemCount',id,false,false,false)
        elseif type(GetItemCount)=='function' then value=GetItemCount(id,false,false,false) end
        return number(value)
    end
    local function position(id)
        local db=AZPCForeverDB and AZPCForeverDB.crafting
        if not db or db.costingError or db.vendorCostingBlocked then return end
        for _,p in ipairs(db.costing and db.costing.positions or {})do
            if p.itemId==id and p.character==UnitName('player') and p.realm==GetRealmName() and p.faction==(UnitFactionGroup('player') or ''):lower() and p.region==currentRegion() then
                if p.costComplete==true and not p.inventoryMismatch and number(p.quantity) and p.quantity>0 and number(p.totalCopper) then return p end
            end
        end
    end
    local function price(id)
        local db=AZPCForeverDB or {}
        local key=table.concat({currentRegion(),(GetRealmName() or ''):lower(),(UnitFactionGroup('player') or ''):lower()},'|')
        local p=db.tooltipPrices and db.tooltipPrices[key] and db.tooltipPrices[key][id]
        local now=GetServerTime and GetServerTime() or time()
        if p and number(p.unitCopper) and p.unitCopper>0 and number(p.observedAt) and p.observedAt<=now and now-p.observedAt<=21600 then return p.unitCopper end
    end
    local function model(recipe,batch)
        batch=math.max(1,math.min(999,number(batch) or 1))
        local out={rows={},cost=0,complete=recipe and recipe.materialsKnown==true,batch=batch}
        if not recipe then out.complete=false;out.cost=nil;return out end
        for _,m in ipairs(recipe.reagents or {})do
            local needed=m.quantity*batch
            local held=count(m.itemId)
            local p=position(m.itemId)
            local cost=p and held and held>=needed and p.quantity>=needed and math.ceil(p.totalCopper/p.quantity*needed) or nil
            out.rows[#out.rows+1]={itemId=m.itemId,name=itemName(m.itemId),needed=needed,held=held,missing=held and math.max(0,needed-held) or nil,cost=cost}
            if cost==nil then out.complete=false else out.cost=out.cost+cost end
        end
        if #out.rows==0 then out.complete=false end
        if not out.complete then out.cost=nil end
        local unit=price(recipe.outputItemId)
        if out.complete and unit and recipe.outputMin==recipe.outputMax then
            out.profit=(math.floor(unit*95/100)*recipe.outputMin*batch)-out.cost
        end
        return out
    end
    local function canOpenRecipe(recipe)
        local id=recipe and tonumber(recipe.recipeId)
        if not id or id<=0 or id>2147483647 or id~=math.floor(id)then return false end
        if recipe.character and recipe.character~=(UnitName('player')or '')then return false end
        if recipe.realm and recipe.realm~=(GetRealmName()or '')then return false end
        if recipe.region and recipe.region~=currentRegion()then return false end
        if recipe.faction and recipe.faction~=(UnitFactionGroup('player')or ''):lower()then return false end
        return C_TradeSkillUI and type(C_TradeSkillUI.OpenRecipe)=='function'and not(InCombatLockdown and InCombatLockdown())
    end
    local function openRecipe(recipe)
        recipe=recipe or selected
        if not canOpenRecipe(recipe)then notify('Select your recipe and open it outside combat. Recipe navigation may be unavailable in this client.');return false end
        -- Blizzard opens the profession and selects the recipe, including delayed
        -- cross-profession loading. Never invoke a craft or a Create button here.
        local ok,result=pcall(C_TradeSkillUI.OpenRecipe,tonumber(recipe.recipeId))
        if not ok or result==false then notify('Could not open that recipe. Open its profession once and try again.');return false end
        return true
    end
    local function readSelection()
        local modern=ProfessionsFrame and (not ProfessionsFrame.IsShown or ProfessionsFrame:IsShown())and ProfessionsFrame.CraftingPage
        local form=modern and modern.SchematicForm
        local details=TradeSkillFrame and TradeSkillFrame.DetailsFrame
        -- Forever's schematic stores currentRecipeInfo and exposes GetRecipeInfo().
        local info=form and (api(form,'GetRecipeInfo') or form.currentRecipeInfo or form.recipeInfo)
        local id=info and info.recipeID or form and form.recipeID or details and details.selectedRecipeID
        if not id and modern and modern.RecipeList and type(modern.RecipeList.GetSelectedRecipeID)=='function' then id=modern.RecipeList:GetSelectedRecipeID() end
        if id and AZPCForeverCrafting and AZPCForeverCrafting.ReadRecipe then
            local recipe=AZPCForeverCrafting.ReadRecipe(id);if recipe then return recipe end
        end
        -- Older profession windows expose an index and fixed reagent rows.
        if type(GetTradeSkillSelectionIndex)=='function' and type(GetTradeSkillNumReagents)=='function' and type(GetTradeSkillReagentInfo)=='function' and type(GetTradeSkillReagentItemLink)=='function' then
            local index=GetTradeSkillSelectionIndex();if not index or index<1 then return end
            local name,kind=GetTradeSkillInfo(index);if kind=='header' then return end
            local link=GetTradeSkillItemLink and GetTradeSkillItemLink(index)
            local output=type(link)=='string' and tonumber(link:match('item:(%d+)'))
            local lo,hi=1,1;if GetTradeSkillNumMade then lo,hi=GetTradeSkillNumMade(index)end
            local recipe={recipeId=index,name=name,outputItemId=output,outputMin=lo,outputMax=hi,reagents={},materialsKnown=true}
            for i=1,GetTradeSkillNumReagents(index)do
                local _,_,q=GetTradeSkillReagentInfo(index,i)
                local reagent=GetTradeSkillReagentItemLink(index,i)
                local item=type(reagent)=='string' and tonumber(reagent:match('item:(%d+)'))
                if item and number(q) then recipe.reagents[#recipe.reagents+1]={itemId=item,quantity=q} else recipe.materialsKnown=false end
            end
            return recipe
        end
    end
    local function search(row)
        if not row then notify('No missing material selected.');return false end
        if not auctionOpen then notify('Open the Auction House, then click Search beside a material.');return false end
        if type(InCombatLockdown)=='function' and InCombatLockdown() then notify('Search after combat.');return false end
        local name=itemName(row.itemId)
        if name=='Item '..row.itemId then notify('Item name is loading. Try again.');return false end
        local bar=AuctionHouseFrame and AuctionHouseFrame.SearchBar
        if bar and type(bar.SetSearchText)=='function' and type(bar.StartSearch)=='function' then
            if C_AuctionHouse and type(C_AuctionHouse.IsThrottledMessageSystemReady)=='function' and not C_AuctionHouse.IsThrottledMessageSystemReady() then notify('The AH is busy. Try again shortly.');return false end
            if AuctionHouseFrame.SetDisplayMode and AuctionHouseFrameDisplayMode then AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)end
            bar:SetSearchText(name);bar:StartSearch();return true
        end
        if BrowseName and type(BrowseName.SetText)=='function' and type(AuctionFrameBrowse_Search)=='function' then
            BrowseName:SetText(name);AuctionFrameBrowse_Search();return true
        end
        notify('AH search is unavailable in this build. Search for '..name..'.');return false
    end
    local function recipeKey(recipe)
        if not recipe then return '' end
        local parts={currentRegion(),GetRealmName() or '',UnitName('player') or '',(UnitFactionGroup('player') or ''):lower(),recipe.recipeId or '',recipe.outputItemId or ''}
        for _,m in ipairs(recipe.reagents or {})do parts[#parts+1]=m.itemId..':'..m.quantity end
        return table.concat(parts,'|')
    end
    local function stopScan(reason)
        if scan and scan.waiting then scan.waiting=false;scan.status=reason or 'Search cancelled' end
    end
    local function quote(recipe,batch)
        local data=model(recipe,batch)
        local complete=recipe and recipe.materialsKnown==true and #data.rows>0
        local missingKnown=true;local total,missing=0,0
        local now=GetServerTime and GetServerTime() or time()
        local previous=completedQuotes[recipeKey(recipe)]
        local valid=previous and previous.at and now>=previous.at and now-previous.at<=21600
        for _,row in ipairs(data.rows)do
            local unit=valid and previous.prices[row.itemId] or nil
            row.unit=unit;row.available=valid and previous.available[row.itemId] or nil
            row.lineCost=unit and unit*row.needed
            if not unit or not row.available or row.available<row.needed then complete=false else total=total+row.lineCost end
            if row.missing==nil then missingKnown=false
            elseif row.missing>0 then
                if not unit or not row.available or row.available<row.missing then missingKnown=false else missing=missing+row.missing*unit end
            end
        end
        data.ahCost=complete and total or nil
        data.missingCost=recipe and recipe.materialsKnown and missingKnown and missing or nil
        data.quoteFresh=valid==true
        local output=valid and previous.prices[recipe.outputItemId] or nil
        data.salePrice=output
        if complete and output and recipe.outputMin==recipe.outputMax then data.ahProfit=math.floor(output*95/100)*recipe.outputMin*data.batch-total end
        return data
    end
    local function readResults()
        if not scan or not scan.waiting or scan.retryPending then return end
        local rows=api(C_AuctionHouse,'GetBrowseResults')
        if type(rows)~='table' then return end
        -- Reject results from an unrelated manual/addon search.
        for _,r in ipairs(rows)do if not r.itemKey or not scan.ids[r.itemKey.itemID]then stopScan('Another AH search interrupted this one. Scan prices again.');return end end
        local prices,available={},{}
        for _,r in ipairs(rows)do
            local id=r.itemKey.itemID;local unit=number(r.minPrice);local amount=number(r.totalQuantity)
            if unit and unit>0 and amount then
                prices[id]=math.min(prices[id] or unit,unit)
                available[id]=amount
            end
        end
        if scan.retried then
            -- Keep only evidence from this scan, never fill gaps from older cached quotes.
            for id,price in pairs(scan.firstPrices)do
                if not prices[id]then prices[id]=price;available[id]=scan.firstAvailable[id]end
            end
        end
        scan.prices=prices;scan.available=available
        if api(C_AuctionHouse,'HasFullBrowseResults')==true then
            scan.waiting=false;scan.complete=true;scan.at=GetServerTime and GetServerTime() or time()
            -- Publish one completed snapshot; partial and unrelated searches never erase it.
            completedQuotes[scan.key]={at=scan.at,prices=scan.prices,available=scan.available}
            local found,total=0,0;for id in pairs(scan.ids)do total=total+1;if scan.prices[id]then found=found+1 end end
            scan.status='Search complete • '..found..'/'..total..' items priced'
            if found<total and not scan.retried then
                scan.firstPrices=prices;scan.firstAvailable=available
                scan.waiting=true;scan.complete=false;scan.retryPending=true;scan.more=false
                scan.status='Checking missing prices…'
            end
        else scan.more=true;scan.status='Loading remaining results…' end
        if render then render()end
    end
    local function searchAll(recipe)
        pendingAuto=nil -- a manual scan supersedes any deferred selection
        recipe=recipe or selected
        if not recipe or not recipe.materialsKnown or #(recipe.reagents or {})==0 then notify('Select a recipe with fixed materials first.');return false end
        if not auctionOpen then notify('Open the Auction House to scan prices.');return false end
        if type(InCombatLockdown)=='function' and InCombatLockdown()then notify('Search after combat.');return false end
        if not C_AuctionHouse or type(C_AuctionHouse.SearchForItemKeys)~='function' or type(C_AuctionHouse.GetBrowseResults)~='function' then notify('Grouped AH search is unavailable in this build.');return false end
        if type(C_AuctionHouse.IsThrottledMessageSystemReady)=='function' and not C_AuctionHouse.IsThrottledMessageSystemReady()then notify('The AH is busy. Try again shortly.');return false end
        local ids,keys={},{}
        local function add(id)
            if number(id) and id>0 and not ids[id]then
                ids[id]=true;keys[#keys+1]=api(C_AuctionHouse,'MakeItemKey',id) or {itemID=id,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0}
            end
        end
        for _,m in ipairs(recipe.reagents)do add(m.itemId)end;add(recipe.outputItemId)
        stopScan()
        scan={key=recipeKey(recipe),ids=ids,keys=keys,prices={},available={},waiting=true,status='Searching all materials and output…'}
        local current=scan
        local sorts={{sortOrder=Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0,reverseSort=false}}
        ownQuery=true
        local ok=pcall(C_AuctionHouse.SearchForItemKeys,keys,sorts)
        ownQuery=false
        if not ok then stopScan('Search unavailable. Try again.');return false end
        tab='ah'
        if C_Timer and C_Timer.After then C_Timer.After(20,function()
            if scan==current and scan.waiting then stopScan('Search timed out. Scan prices again.');if render then render()end end
        end)end
        if render then render()end
        return true
    end
    local hookedQueries=false
    local function installQueryHooks()
        if hookedQueries or type(hooksecurefunc)~='function' or not C_AuctionHouse then return end
        hookedQueries=true
        for _,name in ipairs({'SendBrowseQuery','SearchForItemKeys','SendSearchQuery'})do
            if type(C_AuctionHouse[name])=='function'then pcall(hooksecurefunc,C_AuctionHouse,name,function()
                if not ownQuery then pendingAuto=nil;stopScan('Another AH search interrupted this one. Scan prices again.')end
            end)end
        end
    end
    local purchaseQueue,purchaseAttempt,advancePurchase,pendingQuantity,showReadyPopup,buyMissing
    local function tryMissingScan()
        if not scan or not scan.waiting or not scan.retryPending then return end
        if not auctionOpen or scan.key~=recipeKey(selected)or purchaseQueue or purchaseAttempt
            or (InCombatLockdown and InCombatLockdown())then
            stopScan('Price scan interrupted. Scan prices again.');return
        end
        if api(C_AuctionHouse,'IsThrottledMessageSystemReady')==false then return end
        scan.retryPending=false;scan.retried=true
        scan.status='Checking missing prices…'
        ownQuery=true
        local ok=pcall(C_AuctionHouse.SearchForItemKeys,scan.keys,{{sortOrder=Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0,reverseSort=false}})
        ownQuery=false
        if not ok then stopScan('Search unavailable. Try again.')end
    end
    local function tryAutoScan(delta)
        local request=pendingAuto
        if not request then return end
        request.remaining=request.remaining-(delta or 0)
        if not auctionOpen or recipeKey(selected)~=request.key or request.remaining<=0
            or purchaseQueue or purchaseAttempt or (InCombatLockdown and InCombatLockdown())then
            pendingAuto=nil;return
        end
        if api(C_AuctionHouse,'IsThrottledMessageSystemReady')==false then return end
        installQueryHooks()
        searchAll(request.recipe)
    end
    local function buyMaterial(row)
        if purchaseQueue or purchaseAttempt then notify('Stop the current buying queue first.');return false end
        if not row or not number(row.itemId) or not number(row.needed)then return false end
        local bags=count(row.itemId)
        if bags==nil then notify('Bag quantity: No data.');return false end
        if row.needed<=bags+pendingQuantity(row.itemId)then notify('You already own or have ordered enough of this material.');return false end
        return buyMissing({materialsKnown=true,reagents={{itemId=row.itemId,quantity=row.needed}}},1)
    end
    -- AZPC owns the purchase UI; only the auction service API handles quotes and orders.
    local function deliveryLedger()
        AZPCForeverDB=AZPCForeverDB or {};AZPCForeverDB.pendingMaterials=AZPCForeverDB.pendingMaterials or {}
        local key=table.concat({currentRegion(),GetRealmName() or '',UnitName('player') or '',UnitFactionGroup('player') or ''},'|')
        local all=AZPCForeverDB.pendingMaterials;all[key]=all[key] or {};return all[key]
    end
    pendingQuantity=function(id)
        local entry=deliveryLedger()[tostring(id)];return entry and entry.quantity or 0
    end
    local function reconcileDelivery()
        for id,entry in pairs(deliveryLedger())do
            local bags=count(tonumber(id))
            if bags then
                local arrived=math.max(0,bags-(entry.bags or bags))
                entry.quantity=math.max(0,entry.quantity-arrived);entry.bags=bags
                if entry.quantity==0 then deliveryLedger()[id]=nil end
            end
        end
    end
    local function queueStatus(text)
        if purchaseQueue then purchaseQueue.status=text end
        notify(text)
        if render and page and page.ready and page:IsShown()then render()end
    end
    local function cancelQueue()
        purchaseQueue=nil
        if StaticPopup_Hide then StaticPopup_Hide('AZPC_BUY_MATERIAL')end
        -- Never discard a submitted order: its result can arrive after the AH closes.
        if purchaseAttempt and not purchaseAttempt.submitted then
            purchaseAttempt=nil
            if C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then pcall(C_AuctionHouse.CancelCommoditiesPurchase)end
        end
    end
    local function installPurchaseHook()
        if not hooksecurefunc or not C_AuctionHouse or type(C_AuctionHouse.ConfirmCommoditiesPurchase)~='function' then return false end
        if not C_AuctionHouse.azpcQueueHooked then
            hooksecurefunc(C_AuctionHouse,'ConfirmCommoditiesPurchase',function(id,amount)
                local a=purchaseAttempt
                if a and not a.submitted and a.itemId==id and a.quantity==amount then
                    a.submitted=true
                    local ledger=deliveryLedger();local key=tostring(id);local old=ledger[key]
                    ledger[key]={quantity=(old and old.quantity or 0)+amount,bags=count(id),uncertain=true}
                end
            end)
            C_AuctionHouse.azpcQueueHooked=true
        end
        return true
    end
    advancePurchase=function()
        local q=purchaseQueue
        if not q or purchaseAttempt or not auctionOpen then return end
        if InCombatLockdown and InCombatLockdown()then queueStatus('Buying paused during combat. Return to Crafting to continue.');return end
        if api(C_AuctionHouse,'IsThrottledMessageSystemReady')==false then q.waiting=true;return end
        reconcileDelivery()
        while q.index<=#q.rows do
            local row=q.rows[q.index];local bags=count(row.itemId)
            if bags==nil then queueStatus('Bag quantity: No data. Buying paused.');return end
            local missing=math.max(0,row.needed-bags-pendingQuantity(row.itemId))
            if missing>0 then
                q.current={itemId=row.itemId,quantity=missing};q.waiting=true;q.detailKey=nil;q.detailSent=nil;q.moreDepth=nil;q.ready=nil
                ownQuery=true
                local ok=pcall(C_AuctionHouse.SearchForItemKeys,{api(C_AuctionHouse,'MakeItemKey',row.itemId) or {itemID=row.itemId}}, {{sortOrder=0,reverseSort=false}})
                ownQuery=false
                if not ok then q.waiting=false;queueStatus('Material search failed. Return to Crafting to retry.')else queueStatus('Buying '..q.index..'/'..#q.rows..': searching '..itemName(row.itemId))end
                local current=q.current
                if C_Timer and C_Timer.After then C_Timer.After(20,function()if purchaseQueue==q and q.current==current and q.waiting then q.waiting=false;queueStatus('Material search timed out. Click Buy missing materials to retry.')end end)end
                return
            end
            q.index=q.index+1
        end
        purchaseQueue=nil;queueStatus('Materials ordered. Collect purchased materials from your mailbox.');if render then render()end
    end
    local function readPurchaseDepth(id)
        local q=purchaseQueue;local target=q and q.current
        if not target or target.itemId~=id or not q.detailSent or purchaseAttempt then return end
        local bags=count(id);if bags==nil then queueStatus('Bag quantity: No data. Buying paused.');return end
        target.quantity=math.max(0,q.rows[q.index].needed-bags-pendingQuantity(id))
        if target.quantity==0 then q.index=q.index+1;q.current=nil;advancePurchase();return end
        local left,total=target.quantity,0
        for index=1,(api(C_AuctionHouse,'GetNumCommoditySearchResults',id) or 0)do
            local row=api(C_AuctionHouse,'GetCommoditySearchResultInfo',id,index)
            if row and number(row.quantity) and number(row.unitPrice) and row.unitPrice>0 then
                local available=math.max(0,row.quantity-(number(row.numOwnerItems) or 0))
                local take=math.min(left,available);total=total+take*row.unitPrice;left=left-take
                if left==0 then break end
            end
        end
        if left>0 then
            if api(C_AuctionHouse,'HasFullCommoditySearchResults',id)==false then
                q.moreDepth=true
                if api(C_AuctionHouse,'IsThrottledMessageSystemReady')~=false and type(C_AuctionHouse.RequestMoreCommoditySearchResults)=='function'then q.moreDepth=false;pcall(C_AuctionHouse.RequestMoreCommoditySearchResults,id)end
                return
            end
            q.waiting=false;q.ready=nil;queueStatus('Not enough '..itemName(id)..' listed. Buying paused.');return
        end
        q.waiting=false
        if q.ready and q.ready.itemId==id and q.ready.quantity==target.quantity and q.ready.total==total then return end
        q.ready={itemId=id,quantity=target.quantity,total=total,unit=math.ceil(total/target.quantity)}
        queueStatus('Ready to buy: '..itemName(id)..' x'..target.quantity)
        if showReadyPopup then showReadyPopup()end
    end
    local function sendPurchaseSearch()
        local q=purchaseQueue
        if not q or not q.detailKey or q.detailSent then return end
        if api(C_AuctionHouse,'IsThrottledMessageSystemReady')==false then return end
        q.detailSent=true;ownQuery=true
        local ok=pcall(C_AuctionHouse.SendSearchQuery,q.detailKey,{{sortOrder=0,reverseSort=false}},true)
        ownQuery=false
        if not ok then q.detailSent=false;queueStatus('Material listings could not load. Stop and try again.')end
    end
    local function openQueuedQuote()
        local q=purchaseQueue
        if not q or not q.waiting or not q.current or q.detailKey or purchaseAttempt then return end
        if not api(C_AuctionHouse,'HasFullBrowseResults')then return end
        local target=q.current
        for _,row in ipairs(api(C_AuctionHouse,'GetBrowseResults') or {})do
            if row.itemKey and row.itemKey.itemID==target.itemId and number(row.minPrice) and row.minPrice>0 then
                local info=api(C_AuctionHouse,'GetItemKeyInfo',row.itemKey)
                if not info or not info.isCommodity then queueStatus('This item is not a commodity. AZPC quantity buying supports commodity materials.');cancelQueue();return end
                q.detailKey=row.itemKey;sendPurchaseSearch();return
            end
        end
        q.waiting=false;queueStatus('No data: '..itemName(target.itemId)..' is not listed. Buying paused.')
    end
    -- Restricted quote requests must originate from a button click, never an AH event or timer.
    local function reviewPurchase(maxTotal)
        local q=purchaseQueue;local target=q and q.ready
        if not target or purchaseAttempt or not auctionOpen then return false end
        if InCombatLockdown and InCombatLockdown()then return false end
        if api(C_AuctionHouse,'IsThrottledMessageSystemReady')==false then notify('The AH is busy. Try again shortly.');return false end
        reconcileDelivery()
        local bags=count(target.itemId)
        if bags==nil then return false end
        local missing=math.max(0,q.rows[q.index].needed-bags-pendingQuantity(target.itemId))
        if missing~=target.quantity then q.ready=nil;readPurchaseDepth(target.itemId);return false end
        if not C_AuctionHouse or type(C_AuctionHouse.StartCommoditiesPurchase)~='function'then queueStatus('Purchasing unavailable in this client.');return false end
        if AuctionHouseFrame and AuctionHouseFrame.BuyDialog and AuctionHouseFrame.BuyDialog:IsShown()then notify('Close the other purchase dialog first.');return false end
        purchaseAttempt={itemId=target.itemId,quantity=target.quantity,autoCap=maxTotal or target.total}
        local attempt=purchaseAttempt
        local ok=pcall(C_AuctionHouse.StartCommoditiesPurchase,target.itemId,target.quantity)
        if not ok then purchaseAttempt=nil;queueStatus('Could not request a purchase quote. Stop and try again.');return false end
        queueStatus('Buying '..target.quantity..' '..itemName(target.itemId)..': waiting for the live quote...')
        if C_Timer and C_Timer.After then C_Timer.After(12,function()
            if purchaseAttempt==attempt and not attempt.quoted and not attempt.submitted then
                cancelQueue();notify('The AH did not return a quote. Try buying again.');if render then render()end
            end
        end)end
        if render then render()end
        return true
    end
    showReadyPopup=function()
        local q=purchaseQueue;local target=q and q.ready
        if not target or not StaticPopupDialogs or not StaticPopup_Show then return end
        if not StaticPopupDialogs.AZPC_BUY_MATERIAL then
            StaticPopupDialogs.AZPC_BUY_MATERIAL={
                text='%s',button1='Buy',button2='Cancel',timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3,
                OnAccept=function(_,data)
                    if not data or purchaseQueue~=data.queue or purchaseQueue.ready~=data.target then return end
                    if not reviewPurchase(data.target.total)then
                        -- A throttle or inventory change must leave the action available.
                        if C_Timer and C_Timer.After then C_Timer.After(0,function()if purchaseQueue==data.queue and not purchaseAttempt then showReadyPopup()end end)end
                    end
                end,
                OnCancel=function(_,data)if data and purchaseQueue==data.queue then cancelQueue();if render then render()end end end,
            }
        end
        local text='Buy '..target.quantity..' '..itemName(target.itemId)..'?\n\nMaximum total: '..money(target.total)..'\n\nThe live quote must stay within this total. Price increases require another confirmation.'
        StaticPopup_Show('AZPC_BUY_MATERIAL',text,nil,{queue=q,target=target})
    end
    buyMissing=function(recipe,batch)
        if purchaseAttempt then notify('Finish or cancel the current purchase first.');return false end
        if purchaseQueue and purchaseQueue.ready then showReadyPopup();return true end
        if not auctionOpen or not recipe or recipe.materialsKnown~=true then notify('Open the AH and choose a recipe with known materials.');return false end
        if InCombatLockdown and InCombatLockdown()then return false end
        if not installPurchaseHook() or type(C_AuctionHouse.SearchForItemKeys)~='function'then notify('Material buying is unavailable in this client.');return false end
        stopScan('Buying missing materials.');reconcileDelivery()
        local data=model(recipe,batch);local rows,byId={},{}
        for _,row in ipairs(data.rows)do
            if row.held==nil then notify('Bag quantity: No data.');return false end
            if byId[row.itemId]then byId[row.itemId].needed=byId[row.itemId].needed+row.needed else local entry={itemId=row.itemId,needed=row.needed};byId[row.itemId]=entry;rows[#rows+1]=entry end
        end
        purchaseQueue={rows=rows,index=1};advancePurchase();return true
    end
    local function purchaseEvent(event,id,total)
        local a=purchaseAttempt
        if event=='COMMODITY_SEARCH_RESULTS_RECEIVED' then
            -- Forever's RECEIVED event has no payload; ADDED and UPDATED carry itemID.
            -- Read only the item that this queue has an outstanding detailed query for.
            local q=purchaseQueue
            if q and q.detailSent and q.current then readPurchaseDepth(q.current.itemId)end
        elseif event=='COMMODITY_SEARCH_RESULTS_ADDED' or event=='COMMODITY_SEARCH_RESULTS_UPDATED' then readPurchaseDepth(id)
        elseif event=='COMMODITY_PRICE_UPDATED' and a then
            a.quoted=true;a.liveTotal=number(total)
            if a.autoCap and a.liveTotal and a.liveTotal<=a.autoCap and not a.submitted and C_Timer and C_Timer.After then
                C_Timer.After(0,function()
                    if purchaseAttempt~=a or a.submitted or not auctionOpen or not a.autoCap or not a.liveTotal or a.liveTotal>a.autoCap then return end
                    if InCombatLockdown and InCombatLockdown()then return end
                    if type(GetMoney)=='function' and GetMoney()<a.liveTotal then cancelQueue();notify('Not enough money for this purchase.');return end
                    queueStatus('Purchasing '..a.quantity..' '..itemName(a.itemId)..'...')
                    local ok=pcall(C_AuctionHouse.ConfirmCommoditiesPurchase,a.itemId,a.quantity)
                    if not ok then cancelQueue();notify('Purchase could not be confirmed. Try again.')end
                end)
            elseif a.autoCap and a.liveTotal and a.liveTotal>a.autoCap then
                local q=purchaseQueue
                purchaseAttempt=nil
                if C_AuctionHouse.CancelCommoditiesPurchase then pcall(C_AuctionHouse.CancelCommoditiesPurchase)end
                if q and q.current then
                    q.ready={itemId=a.itemId,quantity=a.quantity,total=a.liveTotal,unit=math.ceil(a.liveTotal/a.quantity)}
                    queueStatus('Price increased. Confirm the updated total in AZPC or cancel.');showReadyPopup()
                end
            end
        elseif event=='COMMODITY_PRICE_UNAVAILABLE' and a then cancelQueue();notify('The live quote is unavailable. Try buying again.')
        elseif event=='BAG_UPDATE_DELAYED' then reconcileDelivery()
        elseif event=='COMMODITY_PURCHASE_SUCCEEDED' and a and a.submitted then
            local entry=deliveryLedger()[tostring(a.itemId)];if entry then entry.uncertain=nil end
            purchaseAttempt=nil
            if purchaseQueue then purchaseQueue.index=purchaseQueue.index+1;purchaseQueue.ready=nil;purchaseQueue.current=nil;purchaseQueue.detailKey=nil;purchaseQueue.detailSent=nil end
            -- Wait for the completed order before preparing the next AZPC confirmation.
            if C_Timer and C_Timer.After then C_Timer.After(0.2,advancePurchase)end
        elseif event=='COMMODITY_PURCHASE_FAILED' and a then
            if a.submitted then local entry=deliveryLedger()[tostring(a.itemId)];if entry then entry.quantity=math.max(0,entry.quantity-a.quantity);if entry.quantity==0 then deliveryLedger()[tostring(a.itemId)]=nil end end end
            purchaseAttempt=nil;cancelQueue();notify('Purchase failed. No automatic retry; scan and try again.')
        elseif event=='AUCTION_HOUSE_THROTTLED_SYSTEM_READY' and purchaseQueue then
            if not purchaseQueue.current then advancePurchase()
            elseif purchaseQueue.moreDepth then readPurchaseDepth(purchaseQueue.current.itemId)
            else sendPurchaseSearch()end
        end
    end
    local function itemTooltip(frame,itemId)
        frame:EnableMouse(true)
        local function hide(self)
            if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(self))then GameTooltip:Hide()end
        end
        frame:SetScript('OnEnter',function(self)
            local id=itemId()
            if not id or not GameTooltip or type(GameTooltip.SetHyperlink)~='function'then return end
            GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
            GameTooltip:SetHyperlink('item:'..id)
            GameTooltip:Show()
        end)
        frame:SetScript('OnLeave',hide)
        frame:SetScript('OnHide',hide)
    end
    local function typography(text,style,size)
        local heading=style=='GameFontNormalLarge' or style=='GameFontNormalSmall'
        if type(text.SetFont)=='function'then text:SetFont('Fonts/FRIZQT__.TTF',size or (style=='GameFontNormalLarge' and 18 or (style=='GameFontDisableSmall' and 10 or 12)),'')end
        if style=='GameFontDisableSmall'then text:SetTextColor(0.65,0.69,0.68)
        elseif heading then text:SetTextColor(0.94,0.79,0.42)else text:SetTextColor(0.92,0.94,0.91)end
        if type(text.SetShadowColor)=='function'then text:SetShadowColor(0,0,0,0.8);text:SetShadowOffset(1,-1)end
    end
    local function uiText(parent,style,x,y,width,align)
        local text=parent:CreateFontString(nil,'OVERLAY',style)
        text:SetPoint('TOPLEFT',x,y);text:SetWidth(width);text:SetJustifyH(align or 'LEFT');typography(text,style)
        return text
    end
    local function surface(frame,r,g,b,border)
        frame:SetBackdrop({bgFile='Interface/Buttons/WHITE8X8',edgeFile='Interface/Tooltips/UI-Tooltip-Border',edgeSize=10,insets={left=3,right=3,top=3,bottom=3}})
        if not frame.azpcSheen then
            frame.azpcSheen=frame:CreateTexture(nil,'BORDER');frame.azpcSheen:SetTexture('Interface/Buttons/WHITE8X8')
            frame.azpcSheen:SetPoint('TOPLEFT',4,-4);frame.azpcSheen:SetPoint('TOPRIGHT',-4,-4);frame.azpcSheen:SetHeight(12);frame.azpcSheen:SetVertexColor(0.65,0.75,0.75,0.045)
        end
        frame:SetBackdropColor(r,g,b,1);frame:SetBackdropBorderColor(unpack(border or {0.38,0.32,0.21}))
    end
    local function uiButton(parent,label,width,height,teal)
        local button=CreateFrame('Button',nil,parent,'BackdropTemplate');button:SetSize(width,height)
        local text=button:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        text:SetPoint('CENTER');typography(text,'GameFontHighlightSmall',12);button:SetFontString(text);button:SetText(label)
        local function rest()surface(button,teal and 0.025 or 0.065,teal and 0.18 or 0.075,teal and 0.18 or 0.075,teal and {0.12,0.63,0.60} or {0.34,0.31,0.24})end
        rest()
        button:SetScript('OnEnter',function()surface(button,0.08,0.23,0.23,{0.23,0.76,0.71})end)
        button:SetScript('OnLeave',rest)
        button:SetScript('OnDisable',function()button:SetAlpha(0.4)end)
        button:SetScript('OnEnable',function()button:SetAlpha(1)end)
        return button
    end
    local function itemIcon(id)
        return (id and ((C_Item and api(C_Item,'GetItemIconByID',id)) or (GetItemIcon and GetItemIcon(id)))) or 'Interface/Icons/INV_Misc_QuestionMark'
    end
    local function create()
        if panel then return panel end
        if not page or not page.ready then return end
        panel=CreateFrame('Frame','AZPCForeverProfessionPanel',page,'BackdropTemplate')
        panel:SetPoint('TOPLEFT',page,'TOPLEFT',236,0);panel:SetPoint('BOTTOMRIGHT',page,'BOTTOMRIGHT',0,0)
        surface(panel,0.025,0.037,0.04)
        panel:EnableMouse(true)
        panel.icon=panel:CreateTexture(nil,'ARTWORK');panel.icon:SetSize(58,58);panel.icon:SetPoint('TOPLEFT',16,-16)
        panel.iconBorder=panel:CreateTexture(nil,'OVERLAY');panel.iconBorder:SetTexture('Interface/Buttons/UI-Quickslot2');panel.iconBorder:SetSize(85,85);panel.iconBorder:SetPoint('CENTER',panel.icon,'CENTER')
        panel.name=uiText(panel,'GameFontNormalLarge',86,-20,290);panel.name:SetTextColor(0.95,0.94,0.87);typography(panel.name,'GameFontHighlight',22)
        panel.subtitle=uiText(panel,'GameFontDisableSmall',86,-53,290)
        panel.itemHover=CreateFrame('Frame',nil,panel);panel.itemHover:SetSize(375,70);panel.itemHover:SetPoint('TOPLEFT',16,-12)
        itemTooltip(panel.itemHover,function()return selected and selected.outputItemId end)
        local crafts=uiText(panel,'GameFontNormalSmall',0,0,90)
        crafts:ClearAllPoints();crafts:SetPoint('TOPRIGHT',-12,-15);crafts:SetJustifyH('RIGHT');crafts:SetText('Crafts')
        panel.minus=uiButton(panel,'-',24,25);panel.minus:SetPoint('TOPRIGHT',-91,-34)
        panel.plus=uiButton(panel,'+',24,25);panel.plus:SetPoint('TOPRIGHT',-12,-34)
        panel.openRecipe=uiButton(panel,'Open Recipe',104,20,true);panel.openRecipe:SetPoint('TOPRIGHT',-12,-60)
        panel.openRecipe:SetScript('OnClick',function()openRecipe()end)
        panel.batch=CreateFrame('EditBox',nil,panel,'BackdropTemplate');panel.batch:SetSize(49,25);panel.batch:SetPoint('TOPRIGHT',-39,-34)
        surface(panel.batch,0.035,0.045,0.045,{0.34,0.31,0.24})
        panel.batch:SetFontObject(GameFontHighlight);panel.batch:SetJustifyH('CENTER');panel.batch:SetAutoFocus(false);panel.batch:SetNumeric(true);panel.batch:SetMaxLetters(3)
        local function applyBatch(self)if purchaseQueue then cancelQueue()end;quantity=math.max(1,math.min(999,number(self:GetText())or 1));self:ClearFocus();render()end
        panel.batch:SetScript('OnEnterPressed',applyBatch)
        panel.batch:SetScript('OnEditFocusLost',applyBatch)
        panel.batch:SetScript('OnEscapePressed',function(self)self:ClearFocus()end)
        panel.minus:SetScript('OnClick',function()if purchaseQueue then cancelQueue()end;quantity=math.max(1,quantity-1);render()end)
        panel.plus:SetScript('OnClick',function()if purchaseQueue then cancelQueue()end;quantity=math.min(999,quantity+1);render()end)
        panel.headerRule=panel:CreateTexture(nil,'BORDER');panel.headerRule:SetTexture('Interface/Buttons/WHITE8X8');panel.headerRule:SetVertexColor(0.45,0.36,0.20,0.65);panel.headerRule:SetHeight(1);panel.headerRule:SetPoint('TOPLEFT',14,-82);panel.headerRule:SetPoint('TOPRIGHT',-14,-82)
        panel.market=uiText(panel,'GameFontHighlightSmall',16,-124,330)
        panel.buyMissing=uiButton(panel,'Buy missing materials',190,28,true);panel.buyMissing:SetPoint('TOPLEFT',14,-90)
        panel.buyMissing:SetScript('OnClick',function()buyMissing(selected,quantity)end)
        panel.cancelBuying=uiButton(panel,'Stop',62,28);panel.cancelBuying:SetPoint('TOPLEFT',210,-90)
        panel.cancelBuying:SetScript('OnClick',function()cancelQueue();render()end)
        panel.searchAll=uiButton(panel,'Scan prices',138,32,true);panel.searchAll:SetPoint('TOPRIGHT',-14,-91)
        panel.searchAll:SetScript('OnClick',function()installQueryHooks();searchAll()end)
        local headings={{'Material',0,126},{'Need',128,34},{'Bags',166,34},{'Missing',204,52},{'Unit price',264,70},{'Total',338,70}}
        panel.tableHeader=CreateFrame('Frame',nil,panel,'BackdropTemplate');panel.tableHeader:SetPoint('TOPLEFT',14,-137);panel.tableHeader:SetPoint('TOPRIGHT',-14,-137);panel.tableHeader:SetHeight(26)
        surface(panel.tableHeader,0.065,0.065,0.055,{0.25,0.23,0.17})
        panel.columnHeaders={}
        for _,h in ipairs(headings)do
            local text=uiText(panel.tableHeader,h[2]==0 and 'GameFontNormalSmall' or 'GameFontHighlightSmall',h[2]+(h[2]==0 and 4 or 0),-7,h[3],h[2]==0 and 'LEFT' or (h[2]<264 and 'CENTER' or 'RIGHT'))
            typography(text,h[2]==0 and 'GameFontNormalSmall' or 'GameFontHighlightSmall',11)
            if h[1]=='Missing'then text:SetTextColor(1,0.79,0.3)end
            text:SetText(h[1]);panel.columnHeaders[h[1]]=text
        end
        local scroll=CreateFrame('ScrollFrame',nil,panel,'UIPanelScrollFrameTemplate');scroll:SetPoint('TOPLEFT',14,-166);scroll:SetPoint('BOTTOMRIGHT',-30,166)
        panel.child=CreateFrame('Frame',nil,scroll);panel.child:SetSize(498,1);scroll:SetScrollChild(panel.child);panel.rows={}
        local help=uiText(panel,'GameFontDisableSmall',0,0,520);help:ClearAllPoints();help:SetPoint('BOTTOMLEFT',14,145);help:SetText('Buy missing opens a quantity and price confirmation. Quantities scale with crafts and bags.')
        panel.cards={}
        for i,label in ipairs({'Material cost','AH sale price','Est. profit / craft'})do
            local card=CreateFrame('Frame',nil,panel,'BackdropTemplate');card:SetSize(160,90);card:SetPoint('BOTTOMLEFT',14+(i-1)*166,47)
            surface(card,0.04,0.045,0.043,{0.45,0.36,0.20})
            card.title=uiText(card,'GameFontNormalSmall',10,-10,144)
            card.title:SetText(label)
            card.value=uiText(card,'GameFontNormalLarge',10,-32,144);card.value:SetTextColor(0.92,0.94,0.91);typography(card.value,'GameFontHighlight',16)
            card.value:SetHeight(24)
            if card.value.SetWordWrap then card.value:SetWordWrap(false)end
            card.helper=uiText(card,'GameFontDisableSmall',10,-66,144)
            panel.cards[i]=card
        end
        panel.cost=panel.cards[1].value;panel.missing=panel.cards[1].helper
        panel.sale=panel.cards[2].value;panel.cards[2].helper:SetText('Lowest listing / each')
        panel.profit=panel.cards[3].value;panel.cards[3].helper:SetText('After 5% AH cut')
        panel.note=uiText(panel,'GameFontDisableSmall',0,0,520);panel.note:ClearAllPoints();panel.note:SetPoint('BOTTOMLEFT',14,28)
        panel.note:SetText('Lowest unit prices; price depth and deposit excluded. Vendor materials may cost less.')
        panel.status=uiText(panel,'GameFontHighlightSmall',0,0,520);panel.status:ClearAllPoints();panel.status:SetPoint('BOTTOMLEFT',14,10)
        return panel
    end
    render=function()
        local p=create();if not p then return end
        if scan and scan.key~=recipeKey(selected)then stopScan('Recipe changed. Scan prices again.');scan=nil end
        local data=quote(selected,quantity)
        p.buyMissing:SetText('Buy missing materials')
        p.buyMissing:SetEnabled((not purchaseQueue or purchaseQueue.ready~=nil or not purchaseQueue.waiting) and auctionOpen and selected~=nil and selected.materialsKnown==true and not purchaseAttempt)
        p.cancelBuying:SetEnabled(purchaseQueue~=nil)
        p.openRecipe:SetEnabled(canOpenRecipe(selected)==true)
        p.name:SetText(selected and selected.name or 'Choose a recipe')
        p.subtitle:SetText(selected and ((selected.profession or 'Saved recipe')..' • Creates '..(selected.outputMin or '?')..(selected.outputMax and selected.outputMax~=selected.outputMin and ('–'..selected.outputMax)or ''))or 'Select a learned recipe from the list.')
        p.icon:SetTexture(itemIcon(selected and selected.outputItemId))
        p.batch:SetText(tostring(quantity))
        p.searchAll:SetEnabled(auctionOpen and selected~=nil and selected.materialsKnown==true and not(scan and scan.waiting))
        p.searchAll:SetText(pendingAuto and 'Waiting for AH…' or (scan and scan.waiting and 'Scanning…' or 'Scan prices'))
        p.market:SetText(purchaseQueue and purchaseQueue.status or (scan and scan.waiting and (data.quoteFresh and 'Last scan prices - refreshing...' or 'Fetching AH prices…') or (data.quoteFresh and 'Latest AH search' or 'Scan for current prices')))
        p.market:SetTextColor(data.quoteFresh and 0.4 or 0.65,data.quoteFresh and 0.84 or 0.67,data.quoteFresh and 0.63 or 0.67)
        for _,row in ipairs(p.rows)do row:Hide()end
        for i,m in ipairs(data.rows)do
            local row=p.rows[i]
            if not row then
                row=CreateFrame('Frame',nil,p.child,'BackdropTemplate');row:SetSize(498,46);row:SetPoint('TOPLEFT',0,-(i-1)*48)
                surface(row,0.035,0.047,0.049,{0.11,0.14,0.14})
                row.icon=row:CreateTexture(nil,'ARTWORK');row.icon:SetSize(22,22);row.icon:SetPoint('LEFT',4,0)
                row.label=uiText(row,'GameFontHighlightSmall',31,-15,94)
                row.itemHover=CreateFrame('Frame',nil,row);row.itemHover:SetSize(125,46);row.itemHover:SetPoint('TOPLEFT',0,0)
                itemTooltip(row.itemHover,function()return row.material and row.material.itemId end)
                row.need=uiText(row,'GameFontHighlightSmall',128,-16,34,'CENTER')
                row.bags=uiText(row,'GameFontHighlightSmall',166,-16,34,'CENTER')
                row.missing=uiText(row,'GameFontHighlightSmall',204,-16,52,'CENTER')
                row.unit=uiText(row,'GameFontHighlightSmall',264,-16,70,'RIGHT')
                row.total=uiText(row,'GameFontHighlightSmall',338,-16,70,'RIGHT')
                row.button=uiButton(row,'Buy',62,26,true);row.button:SetPoint('TOPLEFT',430,-10)
                row.button:SetScript('OnClick',function()buyMaterial(row.material)end);p.rows[i]=row
            end
            row.material=m;row.icon:SetTexture(itemIcon(m.itemId));row.label:SetText(m.name)
            row.need:SetText(m.needed);row.bags:SetText(m.held~=nil and m.held or 'No data');row.missing:SetText(m.missing~=nil and m.missing or 'No data')
            row.missing:SetTextColor(m.missing and m.missing>0 and 1 or 0.55,m.missing and m.missing>0 and 0.78 or 0.63,0.4)
            row.unit:SetText(money(m.unit));row.total:SetText(m.available and m.available<m.needed and 'Short stock' or money(m.lineCost))
            row.button:SetText(pendingQuantity(m.itemId)>0 and 'In mail' or 'Buy')
            row.button:SetEnabled(pendingQuantity(m.itemId)==0 and not purchaseQueue and auctionOpen and m.missing~=nil and m.missing>0 and not(scan and scan.waiting));row:Show()
        end
        p.child:SetHeight(math.max(1,#data.rows*48))
        p.cost:SetText(money(data.ahCost,12));p.missing:SetText('To buy missing: '..money(data.missingCost))
        p.sale:SetText(money(data.salePrice,12))
        p.cards[3].title:SetText(quantity==1 and 'Est. profit / craft' or 'Est. profit / batch')
        p.profit:SetText((data.ahProfit and data.ahProfit>0 and '+'or '')..money(data.ahProfit,12))
        if data.ahProfit==nil then p.profit:SetTextColor(0.65,0.67,0.67)
        elseif data.ahProfit<0 then p.profit:SetTextColor(1,0.4,0.4)else p.profit:SetTextColor(0.48,0.9,0.48)end
        p.status:SetText(selected and not selected.materialsKnown and 'Material choices unresolved • No data' or (scan and scan.complete and not data.quoteFresh and 'Prices are stale. Scan prices again.' or (scan and scan.status or 'Choose a recipe, then Scan prices.')))
    end
    local function ownedRecipe(r)
        return type(r)=='table' and r.character==UnitName('player') and r.realm==GetRealmName() and r.faction==(UnitFactionGroup('player') or ''):lower() and r.region==currentRegion()
    end
    local function catalog(profession,query)
        local db=AZPCForeverDB or {};local merged,groups={},{}
        for _,group in pairs(db.professionCatalog or {})do
            if ownedRecipe(group) then groups[group.profession]=true end
        end
        for _,r in pairs(db.crafting and db.crafting.recipes or {})do
            if ownedRecipe(r) and not groups[r.profession or 'Other recipes']then merged[r.recipeId]=r end
        end
        for _,group in pairs(db.professionCatalog or {})do
            if ownedRecipe(group)then for _,r in ipairs(group.recipes or {})do merged[r.recipeId]=r end end
        end
        local rows,names={},{}
        query=(query or ''):lower()
        for _,r in pairs(merged)do
            local name=r.profession or 'Other recipes';names[name]=true
            if (not profession or profession==name) and (query=='' or (r.name or ''):lower():find(query,1,true))then rows[#rows+1]=r end
        end
        table.sort(rows,function(a,b)return (a.name or ''):lower()<(b.name or ''):lower()end)
        local professions={};for name in pairs(names)do professions[#professions+1]=name end;table.sort(professions)
        return rows,professions
    end
    local function captureCatalog(ids)
        if type(ids)~='table' or not C_TradeSkillUI or api(C_TradeSkillUI,'IsTradeSkillLinked') or api(C_TradeSkillUI,'IsTradeSkillGuild') or api(C_TradeSkillUI,'IsNPCCrafting') then return end
        local base=api(C_TradeSkillUI,'GetBaseProfessionInfo')
        local profession=type(base)=='table' and base.professionName
        if type(profession)~='string' or profession=='' then return end
        local who={character=UnitName('player'),realm=GetRealmName(),faction=(UnitFactionGroup('player') or ''):lower(),region=currentRegion()}
        if not who.character or not who.realm or who.realm=='' or who.faction=='' then return end
        local recipes={}
        for _,id in ipairs(ids)do
            local info=api(C_TradeSkillUI,'GetRecipeInfo',id)
            if info and info.learned and info.name then
                local r=AZPCForeverCrafting and AZPCForeverCrafting.ReadRecipe and AZPCForeverCrafting.ReadRecipe(id)
                if not r then
                    r={recipeId=id,name=info.name,materialsKnown=false,reagents={},character=who.character,realm=who.realm,faction=who.faction,region=who.region}
                end
                r.profession=profession;recipes[#recipes+1]=r
            end
        end
        if #recipes==0 then return end -- transient loading must not erase a saved catalog
        AZPCForeverDB=AZPCForeverDB or {};AZPCForeverDB.professionCatalog=AZPCForeverDB.professionCatalog or {}
        who.profession=profession;who.recipes=recipes;who.observedAt=GetServerTime and GetServerTime() or time()
        local key=table.concat({who.character,who.realm,who.faction,who.region,profession},'|')
        AZPCForeverDB.professionCatalog[key]=who
        if refreshBrowser then refreshBrowser()end
    end
    local function selectRecipe(recipe)
        stopScan('Recipe changed. Scan prices again.');scan=nil
        selected=recipe;quantity=1;tab='ah'
        if refreshBrowser then refreshBrowser()end
        if render then render()end
        -- Only an explicit recipe selection starts a scan; refreshes stay passive.
        pendingAuto=nil
        if auctionOpen and recipe and recipe.materialsKnown and #(recipe.reagents or {})>0 then
            installQueryHooks()
            pendingAuto={recipe=recipe,key=recipeKey(recipe),remaining=20}
            tryAutoScan()
            if render then render()end
        end
    end
    local function font(parent,style,x,y,width)
        return uiText(parent,style,x,y,width)
    end
    refreshBrowser=function()
        if not page or not page.ready then return end
        local rows,professions=catalog(filterProfession,filterText)
        page.profession:SetText(filterProfession or 'All professions')
        page.count:SetText(#rows..' learned recipes')
        for _,button in ipairs(page.recipeRows)do button:Hide()end
        for i,recipe in ipairs(rows)do
            local button=page.recipeRows[i]
            if not button then
                button=CreateFrame('Button',nil,page.listChild,'BackdropTemplate');button:SetSize(204,38);button:SetPoint('TOPLEFT',0,-(i-1)*40)
                button.accent=button:CreateTexture(nil,'OVERLAY');button.accent:SetTexture('Interface/Buttons/WHITE8X8');button.accent:SetVertexColor(0.12,0.78,0.74);button.accent:SetWidth(2);button.accent:SetPoint('TOPLEFT');button.accent:SetPoint('BOTTOMLEFT')
                button.icon=button:CreateTexture(nil,'ARTWORK');button.icon:SetSize(24,24);button.icon:SetPoint('LEFT',7,0)
                button.iconBorder=button:CreateTexture(nil,'OVERLAY');button.iconBorder:SetTexture('Interface/Buttons/UI-Quickslot2');button.iconBorder:SetSize(37,37);button.iconBorder:SetPoint('CENTER',button.icon,'CENTER')
                button.name=font(button,'GameFontHighlightSmall',37,-12,161)
                button:SetScript('OnClick',function()selectRecipe(button.recipe)end)
                itemTooltip(button,function()return button.recipe and button.recipe.outputItemId end)
                page.recipeRows[i]=button
            end
            button.recipe=recipe;button.name:SetText(recipe.name)
            local active=selected and recipeKey(selected)==recipeKey(recipe)
            surface(button,active and 0.025 or 0.04,active and 0.15 or 0.05,active and 0.15 or 0.05,active and {0.12,0.55,0.52} or {0.16,0.18,0.17})
            if active then button.accent:Show()else button.accent:Hide()end
            local icon=recipe.outputItemId and ((C_Item and api(C_Item,'GetItemIconByID',recipe.outputItemId)) or (GetItemIcon and GetItemIcon(recipe.outputItemId)))
            button.icon:SetTexture(icon or 'Interface/Icons/INV_Misc_QuestionMark');button:Show()
        end
        page.listChild:SetHeight(math.max(1,#rows*40))
        page.empty:SetText(#rows==0 and (filterText~='' and 'No matching recipes.' or 'Open each profession once to capture your learned recipes, then return here.') or '')
        for _,button in ipairs(page.menuRows)do button:Hide()end
        local options={'All professions'};for _,name in ipairs(professions)do options[#options+1]=name end
        for i,name in ipairs(options)do
            local button=page.menuRows[i]
            if not button then
                button=uiButton(page.menu,'',196,24);button:SetPoint('TOPLEFT',4,-4-(i-1)*25)
                button:SetScript('OnClick',function()filterProfession=button.value;page.menu:Hide();refreshBrowser()end)
                page.menuRows[i]=button
            end
            button.value=i>1 and name or nil;button:SetText(name);button:Show()
        end
        page.menu:SetHeight(#options*25+8)
    end
    ensurePage=function()
        if page then return page.ready==true end
        local owner=AuctionHouseFrame
        if not UIParent or not owner or type(owner.SetDisplayMode)~='function' or type(AuctionHouseFrameDisplayMode)~='table' or type(owner.Tabs)~='table' then return false end
        page=CreateFrame('Frame','AZPCForeverCraftingPage',owner,'BackdropTemplate')
        page:SetPoint('TOPLEFT',owner,'TOPLEFT',10,-34);page:SetPoint('BOTTOMRIGHT',owner,'BOTTOMRIGHT',-10,29)
        page:SetBackdrop({bgFile='Interface/Buttons/WHITE8X8'});page:SetBackdropColor(0.025,0.04,0.045,1)
        page:EnableMouse(true)
        owner.AZPCCraftingPage=page
        local mode={'AZPCCraftingPage'};AuctionHouseFrameDisplayMode.AZPCCrafting=mode
        -- The native template appends itself through parentArray="Tabs".
        -- Capture the previous tab BEFORE CreateFrame to avoid anchoring to self.
        local last=owner.Tabs[#owner.Tabs]
        local id=#owner.Tabs+1
        local name=(owner.GetName and owner:GetName() or 'AuctionHouseFrame')..'Tab'..id
        local button=CreateFrame('Button',name,owner,'AuctionHouseFrameDisplayModeTabTemplate')
        button:SetID(id);button:SetText('AZPC Crafting');button.displayMode=mode
        if last then button:SetPoint('LEFT',last,'RIGHT',-15,0)else button:SetPoint('BOTTOMLEFT',20,-28)end
        owner.Tabs[id]=button;owner.tabsForDisplayMode=owner.tabsForDisplayMode or {};owner.tabsForDisplayMode[mode]=id
        if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(owner,id)end
        if PanelTemplates_TabResize then PanelTemplates_TabResize(button,20,nil,70)end
        button:SetScript('OnClick',function()
            owner:SetDisplayMode(mode)
            if owner.SetTitle then owner:SetTitle('AZPC Crafting')end
            refreshBrowser();render()
        end)
        page.tabButton=button
        font(page,'GameFontNormalLarge',64,-13,160):SetText('RECIPES')
        page.profession=uiButton(page,'All professions',212,29);page.profession:SetPoint('TOPLEFT',12,-40)
        page.professionArrow=page.profession:CreateTexture(nil,'OVERLAY');page.professionArrow:SetTexture('Interface/Buttons/UI-ScrollBar-ScrollDownButton-Up');page.professionArrow:SetSize(18,18);page.professionArrow:SetPoint('RIGHT',-5,0)
        page.profession:SetScript('OnClick',function()if page.menu:IsShown()then page.menu:Hide()else page.menu:Show()end end)
        page.search=CreateFrame('EditBox',nil,page,'BackdropTemplate');page.search:SetSize(212,29);page.search:SetPoint('TOPLEFT',12,-76);surface(page.search,0.03,0.04,0.04,{0.34,0.31,0.24});page.search:SetFontObject(GameFontHighlightSmall);if page.search.SetFont then page.search:SetFont('Fonts/FRIZQT__.TTF',12,'')end;page.search:SetTextInsets(8,8,0,0);page.search:SetAutoFocus(false);page.search:SetMaxLetters(100)
        page.search:SetScript('OnTextChanged',function(self)filterText=self:GetText()or '';refreshBrowser()end)
        page.search:SetScript('OnEscapePressed',function(self)self:ClearFocus()end)
        page.search:SetScript('OnEnterPressed',function(self)self:ClearFocus()end)
        page.placeholder=font(page.search,'GameFontDisableSmall',8,-8,182);page.placeholder:SetText('Search recipes…')
        page.search:HookScript('OnTextChanged',function(self)if self:GetText()==''then page.placeholder:Show()else page.placeholder:Hide()end end)
        local scroll=CreateFrame('ScrollFrame',nil,page,'UIPanelScrollFrameTemplate');scroll:SetPoint('TOPLEFT',12,-134);scroll:SetPoint('BOTTOMLEFT',12,38);scroll:SetWidth(204)
        page.listChild=CreateFrame('Frame',nil,scroll);page.listChild:SetSize(204,1);scroll:SetScrollChild(page.listChild)
        page.recipeRows={};page.menuRows={}
        page.empty=font(page,'GameFontHighlightSmall',18,-155,194)
        page.count=font(page,'GameFontDisableSmall',12,-114,200)
        local hint=font(page,'GameFontDisableSmall',0,0,200);hint:ClearAllPoints();hint:SetPoint('BOTTOMLEFT',12,14);hint:SetText('Open a profession to refresh recipes.')
        page.menu=CreateFrame('Frame',nil,page,'BackdropTemplate');page.menu:SetSize(204,100);page.menu:SetPoint('TOPLEFT',12,-66);page.menu:SetFrameLevel(page:GetFrameLevel()+20)
        page.menu:SetBackdrop({bgFile='Interface/Buttons/WHITE8X8'});page.menu:SetBackdropColor(0.04,0.06,0.065,1);page.menu:EnableMouse(true);page.menu:Hide()
        page:SetScript('OnShow',function()refreshBrowser();render()end)
        page:SetScript('OnHide',function()page.menu:Hide();cancelQueue();stopScan('Crafting tab closed. Scan prices again.')end)
        page.ready=true
        page:Hide();refreshBrowser()
        return true
    end
    local function showPage()
        if not auctionOpen then notify('Open the Auction House, then choose AZPC Crafting. Open each profession once to save its recipes.');return end
        if not ensurePage()then notify('The AH crafting tab is waiting for the auction UI. Reopen the AH.');return end
        page.tabButton:GetScript('OnClick')(page.tabButton)
    end
    local professionOpen=false
    local craftSearchButton,craftSearchHost
    local function updateCraftSearch(recipe)
        local owner=ProfessionsFrame
        if not owner or type(owner.IsShown)~='function'or not owner:IsShown()then owner=TradeSkillFrame end
        if not auctionOpen or not professionOpen or not owner or type(owner.IsShown)~='function'or not owner:IsShown()then
            if craftSearchButton then craftSearchButton:Hide()end;return
        end
        local host=owner.CraftingPage and owner.CraftingPage.SchematicForm or owner.DetailsFrame or owner
        if host~=craftSearchHost then
            if craftSearchButton then craftSearchButton:Hide()end
            craftSearchHost=host
            craftSearchButton=uiButton(host,'AZPC Craft Search',154,25,true)
            -- Separate header row above reagents; never reanchor Auctionator's search button.
            craftSearchButton:SetPoint('TOPRIGHT',host,'TOPRIGHT',-14,-72)
            owner.AZPCCraftSearchButton=craftSearchButton
            craftSearchButton:SetScript('OnClick',function()
                if not auctionOpen or not professionOpen then return end
                if InCombatLockdown and InCombatLockdown()then notify('Search after combat.');return end
                local current=readSelection()
                if not current then notify('Select a recipe in your profession window first.');return end
                showPage()
                if page and page.ready and page:IsShown()then
                    filterProfession=current.profession;filterText=''
                    if page.search then page.search:SetText('')end
                    selectRecipe(current)
                end
            end)
        end
        local current=recipe or readSelection()
        craftSearchButton:SetEnabled(current~=nil and not(InCombatLockdown and InCombatLockdown()))
        craftSearchButton:Show()
    end
    AZPCForeverProfession={Model=model,Search=search,ReadSelection=readSelection,OpenRecipe=openRecipe,Buy=buyMaterial,BuyMissing=buyMissing,Pending=pendingQuantity,CancelBuying=cancelQueue,PurchaseEvent=purchaseEvent,OpenQueuedQuote=openQueuedQuote,ReviewPurchase=reviewPurchase,ShowPurchasePopup=showReadyPopup,SearchAll=function(recipe)installQueryHooks();return searchAll(recipe)end,Quote=quote,Show=showPage,Catalog=catalog,CaptureCatalog=captureCatalog,Select=selectRecipe}
    local events=CreateFrame('Frame')
    for _,event in ipairs({'TRADE_SKILL_SHOW','TRADE_SKILL_CLOSE','TRADE_SKILL_LIST_UPDATE','TRADE_SKILL_DATA_SOURCE_CHANGED','BAG_UPDATE_DELAYED','AUCTION_HOUSE_SHOW','AUCTION_HOUSE_CLOSED','GET_ITEM_INFO_RECEIVED','AUCTION_HOUSE_BROWSE_RESULTS_UPDATED','AUCTION_HOUSE_BROWSE_RESULTS_ADDED','AUCTION_HOUSE_THROTTLED_SYSTEM_READY','COMMODITY_PURCHASE_SUCCEEDED','COMMODITY_PURCHASE_FAILED','COMMODITY_PRICE_UPDATED','COMMODITY_PRICE_UNAVAILABLE','COMMODITY_SEARCH_RESULTS_RECEIVED','COMMODITY_SEARCH_RESULTS_ADDED','COMMODITY_SEARCH_RESULTS_UPDATED'})do pcall(events.RegisterEvent,events,event)end
    events:SetScript('OnEvent',function(_,event,id,total)
        local ok=pcall(function()
            if event=='TRADE_SKILL_SHOW' then professionOpen=true
            elseif event=='TRADE_SKILL_CLOSE' then professionOpen=false
            elseif event=='AUCTION_HOUSE_SHOW' then auctionOpen=true;ensurePage()
            elseif event=='AUCTION_HOUSE_CLOSED' then auctionOpen=false;pendingAuto=nil;cancelQueue();stopScan('AH closed. Scan prices again.');
            elseif event=='AUCTION_HOUSE_BROWSE_RESULTS_UPDATED' or event=='AUCTION_HOUSE_BROWSE_RESULTS_ADDED' then readResults();openQueuedQuote() end
            purchaseEvent(event,id,total)
            if event=='AUCTION_HOUSE_THROTTLED_SYSTEM_READY' then tryAutoScan()end
            tryMissingScan()
            if scan and scan.waiting and scan.more and (not InCombatLockdown or not InCombatLockdown()) and api(C_AuctionHouse,'IsThrottledMessageSystemReady')~=false and type(C_AuctionHouse.RequestMoreBrowseResults)=='function'then
                scan.more=false;pcall(C_AuctionHouse.RequestMoreBrowseResults)
            end
            updateCraftSearch()
            if professionOpen and not(page and page:IsShown())then selected=readSelection() end
            if page and page.ready and page:IsShown()then refreshBrowser();render()end
        end)
        if not ok then notify('Crafting panel is waiting for profession data. /azpcf materials opens it again.')end
    end)
    local retryElapsed=0
    if UIParent then events:SetScript('OnUpdate',function(_,delta)
        if scan and scan.waiting and scan.retryPending then
            retryElapsed=retryElapsed+delta
            if retryElapsed>=0.2 then retryElapsed=0;tryMissingScan();if render then render()end end
        end
        if pendingAuto then local before=pendingAuto;tryAutoScan(delta);if pendingAuto~=before and render then render()end end
        if not professionOpen then return end
        elapsed=elapsed+delta;if elapsed<0.4 then return end;elapsed=0
        pcall(function()
            local recipe=readSelection()
            updateCraftSearch(recipe)
            if not(page and page:IsShown())then selected=recipe end
        end)
    end) end
end
-- END AZPC PROFESSION PANEL



-- BEGIN AZPC DISENCHANT EVIDENCE
do
-- Capture-only disenchant evidence. Deliberately separate from crafting/cash ledgers.
local DISENCHANT, LIMIT = 13262, 10000
local pending
local function call(fn, ...)
    if type(fn) ~= 'function' then return end
    local ok, a, b, c, d, e, f, g = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g end
end
local function number(n)
    if type(issecretvalue) == 'function' and issecretvalue(n) then return end
    if type(n) == 'number' and n >= 0 and n <= 1000000 and n == math.floor(n) then return n end
end
local function now() return call(GetTime) or call(GetServerTime) or time() end
local function millis() return (call(GetServerTime) or time()) * 1000 end
local function message(s) print('|cff9cc1ffAZPC Forever:|r '..s) end
local function db()
    AZPCForeverDB = AZPCForeverDB or {}
    AZPCForeverDB.disenchanting = AZPCForeverDB.disenchanting or {schema=1, events={}, seen={}}
    return AZPCForeverDB.disenchanting
end
local function bags()
    local slots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    local info = C_Container and C_Container.GetContainerItemInfo
    if type(slots) ~= 'function' or type(info) ~= 'function' and type(GetContainerItemInfo) ~= 'function' then return end
    local counts, guids = {}, {}
    for bag=0,(NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        local size = number(call(slots, bag)); if not size or size > 200 then return end
        for slot=1,size do
            local id, quantity
            if info then
                local item = call(info, bag, slot)
                if item then id, quantity = number(item.itemID), number(item.stackCount) end
            else
                local _, q, _, _, _, _, link = call(GetContainerItemInfo, bag, slot)
                id, quantity = type(link)=='string' and tonumber(link:match('item:(%d+)')), number(q)
            end
            if id and quantity and quantity > 0 then
                counts[id] = (counts[id] or 0) + quantity
                local location = ItemLocation and call(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
                local guid = location and call(C_Item and C_Item.GetItemGUID, location)
                if type(guid)=='string' then guids[guid] = id end
            end
        end
    end
    return {counts=counts, guids=guids}
end
local function held(id)
    return number(call(C_Item and C_Item.GetItemCount or GetItemCount, id, false, false))
end
local function refresh(c)
    local r = c and c.record; if not r then return end
    local confirmed = #r.outputs > 0
    for _, output in ipairs(r.outputs) do
        local count = held(output.itemId)
        if count and output.receivedQuantity > 0 and count-output.bagBefore >= output.receivedQuantity then
            output.quantity = output.receivedQuantity
            output.bagConfirmed = true
        end
        if not output.bagConfirmed or output.quantity ~= output.availableQuantity then confirmed=false end
    end
    r.outputsConfirmed = confirmed
    r.complete = r.inputConfirmed == true and confirmed
    r.status = r.complete and 'confirmed_capture' or 'unresolved_capture'
end
local function input(c)
    if not c or not c.record or not c.before or c.record.inputConfirmed then return end
    local after = bags(); if not after then return end
    local candidates = {}
    for id, quantity in pairs(c.before.counts) do
        local used = quantity-(after.counts[id] or 0)
        if used > 0 then candidates[#candidates+1]={itemId=id, quantity=used} end
    end
    table.sort(candidates,function(a,b) return a.itemId<b.itemId end)
    c.record.inputCandidates = candidates
    -- A bag decrement alone is not proof of which item was targeted.
    -- Require the destroyed item's GUID from the matching loot source as well.
    local source
    for guid in pairs(c.sources or {}) do
        local id = c.before.guids[guid]
        if not id or source and source ~= id then return end
        source = id
    end
    if source and #candidates==1 and candidates[1].itemId==source and candidates[1].quantity==1 then
        c.record.input={itemId=source, quantity=1, confirmation='loot_source_guid_and_bag_decrease'}
        c.record.inputConfirmed=true
    end
end
local function active()
    if pending and (now()-pending.started > 120 or pending.closedAt and now()-pending.closedAt > 30) then pending=nil end
    return pending
end
local function begin(guid)
    if type(guid)~='string' or guid=='' then return end
    if db().seen[tostring(call(UnitGUID,'player'))..':disenchant:'..guid] then return end
    local c=active(); if c and c.guid==guid then return c end
    if c and c.record then refresh(c) end
    local realm, character, faction, player=call(GetRealmName),call(UnitName,'player'),call(UnitFactionGroup,'player'),call(UnitGUID,'player')
    if type(realm)~='string' or realm=='' or type(character)~='string' or character=='' or type(player)~='string' then return end
    faction=type(faction)=='string' and faction:lower()
    if faction~='horde' and faction~='alliance' then return end
    local region=call(GetCurrentRegion) or 0
    if region==110 and realm:match('^Classic Beta ') then region=90 end
    pending={guid=guid,started=now(),before=bags(),who={character=character,realm=realm,faction=faction,region=region,playerGuid=player}}
    return pending
end
local openLoot
local function success(guid)
    local c=active()
    if not c or c.guid~=guid then
        c=begin(guid)
        -- A success-only notification cannot establish a before-cast inventory.
        if c then c.before=nil end
    end
    if not c or c.record then return end
    local d=db(); local id=c.who.playerGuid..':disenchant:'..guid
    if d.seen[id] then return end
    if #d.events>=LIMIT then message('Disenchant capture full; existing records preserved.');pending=nil;return end
    local r={schema=1,eventId=id,spellId=DISENCHANT,castGuid=guid,observedAt=millis(),character=c.who.character,realm=c.who.realm,faction=c.who.faction,region=c.who.region,confirmation='player_disenchant_spell_success',captureOnly=true,inputConfirmed=false,outputsConfirmed=false,complete=false,status='unresolved_capture',inputCandidates={},outputs={}}
    c.record=r;d.events[#d.events+1]=r;d.seen[id]=true
    input(c);refresh(c)
    if openLoot then openLoot() end
    message('Disenchant observed. /azpcf disenchant shows capture evidence; /reload saves it locally.')
end
openLoot=function()
    local c=active()
    if not c or not c.record or now()-c.started>30 then return end
    if c.windowOpened then if c.closedAt then c.rows=nil end;return end
    local count=number(call(GetNumLootItems));if not count or count<1 or count>100 then return end
    local rows,sources={},{}
    for slot=1,count do
        local link=call(GetLootSlotLink,slot)
        local id=type(link)=='string' and tonumber(link:match('item:(%d+)'))
        local _,name,q=call(GetLootSlotInfo,slot);q=number(q)
        if not id or not q or q<1 then return end
        if type(GetLootSourceInfo)~='function' then return end
        local raw={GetLootSourceInfo(slot)}
        if #raw==0 then return end
        for i=1,#raw,2 do
            local guid=raw[i]
            if type(guid)~='string' or not guid:match('^Item%-') then return end
            sources[guid]=true
        end
        local row=rows[id]
        if row then row.availableQuantity=row.availableQuantity+q
        else
            local before=held(id);if not before then return end
            rows[id]={itemId=id,name=name or ('Item '..id),availableQuantity=q,receivedQuantity=0,quantity=0,bagBefore=before,bagConfirmed=false}
        end
    end
    c.windowOpened=true;c.sources=sources;c.rows=rows
    for _,r in pairs(rows)do c.record.outputs[#c.record.outputs+1]=r end
    table.sort(c.record.outputs,function(a,b)return a.itemId<b.itemId end)
    c.record.lootSourceGuids={};for guid in pairs(sources)do c.record.lootSourceGuids[#c.record.lootSourceGuids+1]=guid end
    table.sort(c.record.lootSourceGuids)
    input(c);refresh(c)
end
local function pattern(format)
    if type(format)~='string' then return end
    local p=format:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])','%%%1')
    return '^'..p:gsub('%%%%s','(.+)'):gsub('%%%%d','(%%d+)')..'$'
end
local function selfLoot(text)
    local c=active();if not c or not c.rows or c.closedAt and now()-c.closedAt>2 or type(text)~='string' then return end
    local link,q
    local multi,single=pattern(LOOT_ITEM_SELF_MULTIPLE),pattern(LOOT_ITEM_SELF)
    if multi then link,q=text:match(multi) end
    if not link and single then link=text:match(single);q=1 end
    local id=link and tonumber(link:match('item:(%d+)'));q=tonumber(q)
    local r=id and c.rows[id]
    if r and number(q) and q>0 then
        -- Chat evidence is capped by this exact loot window, never by bag gains.
        r.receivedQuantity=math.min(r.availableQuantity,r.receivedQuantity+q)
        refresh(c)
    end
end
AZPCForeverDisenchant={Status=function()
    local d=db();local r=d.events[#d.events]
    message('Disenchant capture: '..#d.events..' successful casts saved locally. Capture only; profit calculations unchanged.')
    if d.lastError then message('Disenchant capture deferred: '..d.lastError) end
    if r then
        local total=0;for _,v in ipairs(r.outputs)do total=total+(v.quantity or 0) end
        message('Last disenchant: '..r.status..' | input '..(r.input and tostring(r.input.itemId) or 'unresolved')..' | '..total..' material(s) confirmed. /reload saves this evidence to disk.')
    end
end}
local frame=CreateFrame('Frame')
for _,event in ipairs({'ADDON_LOADED','UNIT_SPELLCAST_SENT','UNIT_SPELLCAST_START','UNIT_SPELLCAST_SUCCEEDED','UNIT_SPELLCAST_FAILED','UNIT_SPELLCAST_INTERRUPTED','LOOT_READY','LOOT_OPENED','LOOT_CLOSED','CHAT_MSG_LOOT','BAG_UPDATE_DELAYED','PLAYER_LOGOUT'})do pcall(frame.RegisterEvent,frame,event)end
local function event(_,event,...)
    local unit,a,b,c=...
    if event=='ADDON_LOADED' then db()
    elseif event=='UNIT_SPELLCAST_SENT' and unit=='player' and c==DISENCHANT then begin(b)
    elseif event=='UNIT_SPELLCAST_START' and unit=='player' and b==DISENCHANT then begin(a)
    elseif event=='UNIT_SPELLCAST_SUCCEEDED' and unit=='player' and b==DISENCHANT then success(a)
    elseif (event=='UNIT_SPELLCAST_FAILED' or event=='UNIT_SPELLCAST_INTERRUPTED') and unit=='player' and pending and pending.guid==a and not pending.record then pending=nil
    elseif event=='LOOT_READY' or event=='LOOT_OPENED' then openLoot()
    elseif event=='CHAT_MSG_LOOT' then selfLoot(unit)
    elseif event=='LOOT_CLOSED' then local p=active();if p and p.windowOpened then p.closedAt=now();input(p);refresh(p)end
    elseif event=='BAG_UPDATE_DELAYED' then local p=active();if p then input(p);refresh(p)end
    elseif event=='PLAYER_LOGOUT' then local p=active();if p then input(p);refresh(p)end;pending=nil end
end
local wrapped=AZPCForeverDiagnostics and AZPCForeverDiagnostics.Wrap and AZPCForeverDiagnostics.Wrap('Disenchant capture',event) or event
frame:SetScript('OnEvent',function(...)
    local ok,err=pcall(wrapped,...)
    if not ok then db().lastError=tostring(err) end
end)
if SlashCmdList then
    local previous=SlashCmdList.AZPCFOREVER
    SlashCmdList.AZPCFOREVER=function(command)
        if (command or ''):lower():match('^%s*disenchant%s*$') then AZPCForeverDisenchant.Status()
        elseif previous then return previous(command) end
    end
end

end
-- END AZPC DISENCHANT EVIDENCE
