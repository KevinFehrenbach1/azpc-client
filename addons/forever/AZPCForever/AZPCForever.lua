-- AZPC Forever: AH collector and profession planner. Searches require explicit user actions; never buys or sells.
local addon, VERSION = ..., ((C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata('AZPCForever','Version')) or (GetAddOnMetadata and GetAddOnMetadata('AZPCForever','Version')) or 'unknown')
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
    local cfg=AZPCForeverSettings;local mode=cfg and cfg.Get('reminders')or'popup'
    if mode=='notification' then
        if cfg and cfg.Notify()then queued=false;dirty=false end
        return
    end
    if type(StaticPopup_Show)~='function' or type(StaticPopupDialogs)~='table' then return end
    queued=false;dirty=false
    if mode=='both' and cfg then cfg.Notify()end
    StaticPopup_Show(popupKey)
end
if type(StaticPopupDialogs)=='table' then
    StaticPopupDialogs[popupKey]={
        text='Auction data recorded!\n\nReloading saves your latest data so the AZPC Watcher can sync it to your account dashboard at azpc.market.\n\nYour watcher must be running and connected. Reload now?',
        button1='Reload now',button2='Later',button3='Details',
        OnAlt=function()if AZPCForeverSyncStatus then AZPCForeverSyncStatus.Show()end end,
        OnShow=function(self)if AZPCForeverSyncStatus and self.text then self.text:SetText(AZPCForeverSyncStatus.CompactText())end end,timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3,
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
    if command == "sync" then if AZPCForeverSyncStatus then AZPCForeverSyncStatus.Show()end
    elseif command == "capture" then local ok,count,text=pcall(capture); message(ok and text or tostring(count))
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
        if not tooltip.azpcForeverHeading then tooltip.azpcForeverHeading=true;tooltip:AddLine('AZPC',0.33,0.86,0.82)end
        if type(tooltip.AddDoubleLine)=='function' then tooltip:AddDoubleLine(label,value,0.7,0.75,0.75,r or 0.9,g or 0.95,b or 0.95)
        else tooltip:AddLine(label..': '..value,r or 0.9,g or 0.95,b or 0.95,true) end
    end

    -- Read-only, bounded indexing of existing bank evidence; never replay the cost ledger on hover.
    local bankIndex,bankEvents,bankCursor={},nil,0
    local indexPending=false
    local function validCount(n)return type(n)=='number' and n==n and n>=0 and n<=1000000 and n==math.floor(n)end
    local function indexBanks()
        indexPending=false
        local events=AZPCForeverDB and AZPCForeverDB.crafting and AZPCForeverDB.crafting.materialEvents or {}
        if events~=bankEvents or #events<bankCursor then bankEvents=events;bankCursor=0;bankIndex={}end
        local stop=math.min(#events,bankCursor+100)
        for i=bankCursor+1,stop do
            local e=events[i]
            if type(e)=='table' and e.kind=='inventory_observation' and e.confirmation=='bags_and_character_bank_observed' and validCount(e.bankQuantity) and validCount(e.bagQuantity) and type(e.observedAt)=='number' and e.observedAt>0 and type(e.character)=='string' and type(e.realm)=='string' and type(e.faction)=='string' and type(e.region)=='number' and type(e.itemId)=='number' then
                local key=table.concat({e.region,e.realm,e.faction,e.character},'|')
                bankIndex[key]=bankIndex[key]or{}
                local old=bankIndex[key][e.itemId]
                if not old or e.observedAt>=old.observedAt then bankIndex[key][e.itemId]=e end
            end
        end
        bankCursor=stop
        if bankCursor<#events and C_Timer and type(C_Timer.After)=='function' then indexPending=true;C_Timer.After(0.01,indexBanks)end
    end
    local function requestIndex()
        if not indexPending and C_Timer and type(C_Timer.After)=='function' then indexPending=true;C_Timer.After(0.01,indexBanks)end
    end
    local function savedAge(at,now)
        if type(at)~='number' or at~=at or at<=0 or at>now then return 'time unknown'end
        local age=now-at
        if age<60 then return 'just now'
        elseif age<3600 then return math.floor(age/60)..'m ago'
        elseif age<86400 then return math.floor(age/3600)..'h ago'
        else return math.floor(age/86400)..'d ago'end
    end
    local function ownership(tooltip,itemId,realm,faction,now,detailed)
        local db=AZPCForeverDB or {};local bags=db.bagStates or {};local prefix=table.concat({currentRegion(),realm,faction},'|')..'|'
        local owners={}
        for key in pairs(bags)do if type(key)=='string' and key:sub(1,#prefix)==prefix then owners[key]=true end end
        for key,items in pairs(bankIndex)do if key:sub(1,#prefix)==prefix and items[itemId]then owners[key]=true end end
        local rows,total={},0
        for key in pairs(owners)do
            local states=bags[key];local bag=type(states)=='table' and states[itemId];local bank=bankIndex[key]and bankIndex[key][itemId]
            local b=bag and validCount(bag.quantity)and bag.quantity or nil
            local bagAt=bag and bag.recordedAt
            if bank and (not bagAt or bank.observedAt/1000>bagAt)then b=bank.bagQuantity;bagAt=bank.observedAt/1000 end
            -- Absent items in a complete saved bag map have no saved bag copies.
            if b==nil and type(states)=='table' then b=0 end
            local n=bank and bank.bankQuantity
            if (b or 0)+(n or 0)>0 then
                rows[#rows+1]={name=key:sub(#prefix+1),bags=b,bank=n,bagAt=bagAt,bankAt=bank and bank.observedAt/1000}
                total=total+(b or 0)+(n or 0)
            end
        end
        table.sort(rows,function(a,b)return a.name<b.name end)
        if #rows>0 then
            add(tooltip,'Owned (saved)',tostring(total)..' known')
            if detailed then
                for _,r in ipairs(rows)do
                    add(tooltip,r.name,(r.bags~=nil and r.bags..' bags' or 'bags unknown')..' / '..(r.bank~=nil and r.bank..' bank' or 'bank unknown'))
                    tooltip:AddLine('  Bags '..savedAge(r.bagAt,now)..'; bank '..savedAge(r.bankAt,now),0.6,0.6,0.6,true)
                end
                tooltip:AddLine('Saved counts on this realm/faction; may have changed.',0.55,0.55,0.55,true)
            end
        end
        requestIndex()
    end
    if type(CreateFrame)=='function' then
        local observer=CreateFrame('Frame')
        for _,event in ipairs({'PLAYER_LOGIN','BAG_UPDATE_DELAYED','BANKFRAME_CLOSED'})do observer:RegisterEvent(event)end
        observer:SetScript('OnEvent',requestIndex)
    end
    local function otherAuctionPrice(itemId)
        -- Explicit Auctionator configuration/API checks; never inspect localized tooltip text.
        local a=Auctionator
        if type(a)~='table' or not a.Config or not a.Config.Options or type(a.Config.Get)~='function' then return false end
        local option=a.Config.Options.AUCTION_TOOLTIPS
        if not option then return false end
        local ok,enabled=pcall(a.Config.Get,option)
        local api=a.API and a.API.v1 and a.API.v1.GetAuctionPriceByItemID
        if not ok or enabled~=true or type(api)~='function' then return false end
        local found,price=pcall(api,'AZPCForever',itemId)
        local value=found and number(price)
        return value~=nil and value~=false and value>0
    end
    local function otherInventory()
        -- BagBrother's Bagnon tooltip module is enabled through sets.countItems.
        return type(Bagnon)=='table' and type(Bagnon.sets)=='table' and Bagnon.sets.countItems==true
    end
    local function append(tooltip,itemId)
        itemId=number(itemId)
        if not itemId or itemId<=0 or not tooltip or type(tooltip.AddLine)~='function' then return end
        local cfg=AZPCForeverSettings
        if cfg and cfg.Get('tooltips')=='off'then return end
        if tooltip.azpcForeverItem==itemId then return end
        tooltip.azpcForeverItem=itemId
        local db=AZPCForeverDB or {}
        local key,realm,faction,character=scope()
        local price=db.tooltipPrices and db.tooltipPrices[key] and db.tooltipPrices[key][itemId]
        local now=GetServerTime and GetServerTime() or time()
        local valid=price and number(price.unitCopper) and price.unitCopper>0 and number(price.observedAt) and price.observedAt<=now
        local detailed=cfg and cfg.Get('tooltips')=='detailed' or type(IsShiftKeyDown)=='function' and IsShiftKeyDown()
        local age=valid and now-price.observedAt
        if valid and (detailed or not otherAuctionPrice(itemId)) then
            add(tooltip,'Auction / each'..(age>3600 and ' (stale)' or ''),money(price.unitCopper))
            if detailed then tooltip:AddLine('  Price checked '..savedAge(price.observedAt,now),0.6,0.6,0.6,true)end
        end
        local materials=db.crafting;local cost
        if materials and not materials.costingError and not materials.vendorCostingBlocked then
            for _,p in ipairs(materials.costing and materials.costing.positions or {}) do
                if p.itemId==itemId and p.region==currentRegion() and p.realm==realm and p.faction==faction and p.character==character and p.quantity and p.quantity>0 then
                    if p.costComplete==true and not p.inventoryMismatch and number(p.totalCopper) then cost=math.ceil(p.totalCopper/p.quantity) end
                    break
                end
            end
        end
        if cost~=nil then add(tooltip,'Cost / each',money(cost))end
        if valid and cost~=nil and age<=21600 then
            local profit=math.floor(price.unitCopper*95/100)-cost
            add(tooltip,'Est. profit / each',money(profit),profit>=0 and 0.5 or 1,profit>=0 and 0.86 or 0.5,profit>=0 and 0.65 or 0.45)
            if detailed then tooltip:AddLine('After 5% AH cut; excludes deposit.',0.55,0.55,0.55,true)end
        end
        if (not cfg or cfg.Get('ownership'))and(detailed or not otherInventory())then ownership(tooltip,itemId,realm,faction,now,detailed)else requestIndex()end
        if tooltip.azpcForeverHeading and not detailed then tooltip:AddLine('Hold Shift before hovering for AZPC details.',0.55,0.55,0.55,true)end
        if type(tooltip.Show)=='function' then tooltip:Show() end
    end
    local function clear(tooltip)tooltip.azpcForeverItem=nil;tooltip.azpcForeverHeading=nil end
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
    local batchScan,onMaterialsOrdered,refreshCraftPlan
    local completedQuotes={}
    local page,ensurePage,refreshBrowser
    local filterProfession,filterText=nil,''
    local restoredSelection=false
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
    local function craftableCount(recipe,cache)
        if not recipe or recipe.materialsKnown~=true or type(recipe.reagents)~='table'or #recipe.reagents==0 then return nil end
        cache=cache or{}
        if not cache.equipped then
            cache.equipped={}
            if type(GetInventoryItemID)=='function'then
                for slot=1,(INVSLOT_LAST_EQUIPPED or 19)+(NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)do
                    local ok,id=pcall(GetInventoryItemID,'player',slot)
                    if not ok then cache.unknownEquipment=true;break end
                    if id then
                        local q=1
                        if type(GetInventoryItemCount)=='function'then local success,value=pcall(GetInventoryItemCount,'player',slot);if not success or type(value)~='number'or value<1 then cache.unknownEquipment=true;break end;q=value end
                        cache.equipped[id]=(cache.equipped[id]or 0)+q
                    end
                end
            end
        end
        if cache.unknownEquipment then return nil end
        local needs={}
        for _,m in ipairs(recipe.reagents)do
            if type(m.itemId)~='number'or m.itemId<=0 or m.itemId~=math.floor(m.itemId)or type(m.quantity)~='number'or m.quantity<=0 or m.quantity~=math.floor(m.quantity)then return nil end
            needs[m.itemId]=(needs[m.itemId]or 0)+m.quantity
        end
        local result
        for id,needed in pairs(needs)do
            if cache[id]==nil then
                local ok,held=pcall(count,id)
                cache[id]=ok and held~=nil and math.max(0,held-(cache.equipped[id]or 0))or false
            end
            local held=cache[id];if held==false then return nil end
            local n=math.floor(held/needed);result=result and math.min(result,n)or n
        end
        return result
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
        batchScan=nil
        if scan and scan.waiting then scan.waiting=false;scan.status=reason or 'Search cancelled' end
    end
    local function quote(recipe,batch)
        local data=model(recipe,batch)
        local complete=recipe and recipe.materialsKnown==true and #data.rows>0
        local missingKnown=true;local total,missing=0,0
        data.materialCount=#data.rows;data.pricedMaterials=0;data.shortMaterials=0
        local now=GetServerTime and GetServerTime() or time()
        local previous=completedQuotes[recipeKey(recipe)]
        local valid=previous and previous.at and now>=previous.at and now-previous.at<=21600
        data.quoteAt=previous and previous.at
        for _,row in ipairs(data.rows)do
            local unit=valid and previous.prices[row.itemId] or nil
            row.unit=unit;row.available=valid and previous.available[row.itemId] or nil
            if unit and unit>0 then data.pricedMaterials=data.pricedMaterials+1;if not row.available or row.available<row.needed then data.shortMaterials=data.shortMaterials+1 end end
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
        data.outputPriced=output~=nil and output>0
        if complete and output and recipe.outputMin==recipe.outputMax then data.ahProfit=math.floor(output*95/100)*recipe.outputMin*data.batch-total end
        return data
    end
    local function priceStatus(data,now)
        if not data or not data.quoteAt then return 'No price scan yet',false end
        local age=now-data.quoteAt
        if age<0 then return 'Scan time unknown - scan again',false end
        local when=age<60 and 'Updated just now' or ('Scanned '..(age<3600 and math.floor(age/60)..'m' or age<86400 and math.floor(age/3600)..'h' or math.floor(age/86400)..'d')..' ago')
        if age>21600 then return when..' (stale) - scan again',false end
        if data.pricedMaterials<data.materialCount then return when..' | '..data.pricedMaterials..'/'..data.materialCount..' materials priced',false end
        if not data.outputPriced then return when..' | output price missing',false end
        if data.shortMaterials>0 then return when..' | limited AH stock',false end
        return when,true
    end
    local function updatePriceStatus(p,queue)
        local data=p.priceSnapshot
        if not data then return end
        local text,complete=priceStatus(data,GetServerTime and GetServerTime()or time())
        if queue then text=queue.status;complete=false
        elseif scan and scan.waiting then text=(data.quoteAt and 'Refreshing prices... (showing last scan)'or'Scanning prices...');complete=false
        elseif pendingAuto then text='Waiting for AH...';complete=false
        elseif restoredSelection then text='Scan prices to refresh';complete=false
        elseif not selected then text='Choose a recipe to scan prices';complete=false
        elseif not selected.materialsKnown then text='Recipe materials unavailable';complete=false end
        p.market:SetText(text or 'Scanning prices...')
        if complete then p.market:SetTextColor(0.4,0.84,0.63)else p.market:SetTextColor(0.9,0.72,0.4)end
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
            restoredSelection=false
            if scan.single then
                -- A targeted retry updates one item without refreshing the age of retained prices.
                local base=scan.base;local merged,stock={},{}
                for id,value in pairs(base.prices)do merged[id]=value end
                for id,value in pairs(base.available)do stock[id]=value end
                if prices[scan.single]then merged[scan.single]=prices[scan.single];stock[scan.single]=available[scan.single]end
                completedQuotes[scan.key]={at=base.at,prices=merged,available=stock}
                scan.status=prices[scan.single]and'Material price refreshed; other prices retained.'or'No listings found. Retry or scan all prices.'
                if refreshBrowser then refreshBrowser()end
                if render then render()end;return
            end
            -- Publish one completed snapshot; partial and unrelated searches never erase it.
            completedQuotes[scan.key]={at=scan.at,prices=scan.prices,available=scan.available}
            if refreshBrowser then refreshBrowser()end
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
    local function searchAll(recipe,fromBatch)
        if not fromBatch then batchScan=nil end
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
        local queued=fromBatch and batchScan
        stopScan();batchScan=queued
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
    local function retryMaterial(itemId)
        if not auctionOpen or not selected or not selected.materialsKnown or purchaseQueue or purchaseAttempt or(scan and scan.waiting)then return false end
        if InCombatLockdown and InCombatLockdown()then notify('Retry after combat.');return false end
        local found=false;for _,m in ipairs(selected.reagents or{})do if m.itemId==itemId then found=true;break end end
        local key=recipeKey(selected);local previous=completedQuotes[key]
        local now=GetServerTime and GetServerTime()or time()
        if not found or not previous or now<previous.at or now-previous.at>21600 then notify('Scan all prices first to refresh this recipe.');return false end
        if previous.prices[itemId]then return false end
        if not C_AuctionHouse or type(C_AuctionHouse.SearchForItemKeys)~='function'or type(C_AuctionHouse.GetBrowseResults)~='function'then return false end
        if api(C_AuctionHouse,'IsThrottledMessageSystemReady')==false then notify('The AH is busy. Retry shortly.');return false end
        installQueryHooks();pendingAuto=nil
        local itemKey=api(C_AuctionHouse,'MakeItemKey',itemId)or{itemID=itemId,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0}
        scan={key=key,ids={[itemId]=true},keys={itemKey},prices={},available={},waiting=true,single=itemId,base=previous,status='Retrying missing material price...'}
        local current=scan;ownQuery=true
        local ok=pcall(C_AuctionHouse.SearchForItemKeys,scan.keys,{{sortOrder=Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0,reverseSort=false}})
        ownQuery=false
        if not ok then stopScan('Material retry unavailable. Try again.');if render then render()end;return false end
        if C_Timer and C_Timer.After then C_Timer.After(20,function()if scan==current and scan.waiting then stopScan('Material retry timed out. Try again.');if render then render()end end end)end
        if render then render()end;return true
    end
    local function tryMissingScan()
        if not scan or not scan.waiting or not scan.retryPending then return end
        if not auctionOpen or (scan.key~=recipeKey(selected)and not(batchScan and batchScan.active and scan.key==batchScan.key))or purchaseQueue or purchaseAttempt
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
        if onMaterialsOrdered and q.recipe then onMaterialsOrdered(q.recipe,q.batch)end
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
        purchaseQueue={rows=rows,index=1,recipe=recipe,batch=data.batch};advancePurchase();return true
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
        local priceElapsed=0;panel:SetScript('OnUpdate',function(self,delta)priceElapsed=priceElapsed+delta;if priceElapsed>=15 then priceElapsed=0;updatePriceStatus(self,purchaseQueue)end end)
        return panel
    end
    render=function()
        local p=create();if not p then return end
        if scan and scan.key~=recipeKey(selected)and not batchScan then stopScan('Recipe changed. Scan prices again.');scan=nil end
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
        p.priceSnapshot=data;updatePriceStatus(p,purchaseQueue)
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
                row.retryButton=uiButton(row,'Retry',62,26);row.retryButton:SetPoint('TOPLEFT',272,-10)
                row.retryButton:SetScript('OnClick',function()retryMaterial(row.material.itemId)end)
                row.total=uiText(row,'GameFontHighlightSmall',338,-16,70,'RIGHT')
                row.button=uiButton(row,'Buy',62,26,true);row.button:SetPoint('TOPLEFT',430,-10)
                row.button:SetScript('OnClick',function()buyMaterial(row.material)end);p.rows[i]=row
            end
            row.material=m;row.icon:SetTexture(itemIcon(m.itemId));row.label:SetText(m.name)
            row.need:SetText(m.needed);row.bags:SetText(m.held~=nil and m.held or 'No data');row.missing:SetText(m.missing~=nil and m.missing or 'No data')
            row.missing:SetTextColor(m.missing and m.missing>0 and 1 or 0.55,m.missing and m.missing>0 and 0.78 or 0.63,0.4)
            local unpriced=data.quoteAt~=nil and m.unit==nil
            if unpriced then
                surface(row,0.12,0.085,0.025,{0.55,0.36,0.1});row.label:SetTextColor(1,0.8,0.35)
                row.unit:Hide();row.retryButton:Show();row.total:SetText('No price');row.total:SetTextColor(1,0.8,0.35)
                row.retryButton:SetEnabled(data.quoteFresh and auctionOpen and not purchaseQueue and not purchaseAttempt and not(scan and scan.waiting)and not(InCombatLockdown and InCombatLockdown()))
            else
                surface(row,0.035,0.047,0.049,{0.11,0.14,0.14});row.label:SetTextColor(0.9,0.95,0.95)
                row.retryButton:Hide();row.unit:Show();row.unit:SetText(money(m.unit));row.total:SetText(m.available and m.available<m.needed and 'Short stock'or money(m.lineCost));row.total:SetTextColor(0.9,0.95,0.95)
            end
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
        local warning
        if data.quoteAt and data.quoteFresh and not(scan and scan.waiting)then
            if data.pricedMaterials<data.materialCount then warning='Prices incomplete - scan again.'
            elseif not data.outputPriced then warning='Output price missing - scan again to estimate profit.'
            elseif data.shortMaterials>0 then warning='Not enough AH stock for this quantity. Scan again or reduce crafts.'end
        end
        p.status:SetText(selected and not selected.materialsKnown and 'Material choices unresolved • No data' or warning or (data.quoteAt and not data.quoteFresh and 'Prices are stale. Scan prices again.' or (scan and scan.status or 'Choose a recipe, then Scan prices.')))
    end
    local function ownedRecipe(r)
        return type(r)=='table' and r.character==UnitName('player') and r.realm==GetRealmName() and r.faction==(UnitFactionGroup('player') or ''):lower() and r.region==currentRegion()
    end
    local function favoriteScope(create)
        local name,realm=UnitName('player'),GetRealmName()
        local faction=(UnitFactionGroup('player')or''):lower()
        if not name or name==''or not realm or realm==''or faction==''then return end
        local owner=table.concat({currentRegion(),realm,faction,UnitGUID and UnitGUID('player')or name},'|')
        local db=AZPCForeverDB
        if not db and create then db={};AZPCForeverDB=db end
        if not db then return end
        if create and type(db.recipeFavorites)~='table'then db.recipeFavorites={}end
        local scopes=type(db.recipeFavorites)=='table'and db.recipeFavorites
        local saved=scopes and scopes[owner]
        if create and type(saved)~='table'then saved={recipes={}};scopes[owner]=saved end
        return type(saved)=='table'and saved or nil
    end
    local function isFavorite(recipe)
        if not ownedRecipe(recipe)then return false end
        local saved=favoriteScope(false)
        return saved and type(saved.recipes)=='table'and saved.recipes[tostring(recipe.recipeId)]==true or false
    end
    local function favoritesOnly()
        local saved=favoriteScope(false);return saved and saved.only==true or false
    end
    local function setFavoritesOnly(value)
        if type(value)~='boolean'then return false end
        local saved=favoriteScope(true);if not saved then return false end
        saved.only=value
        if page and page.recipeScroll and page.recipeScroll.SetVerticalScroll then page.recipeScroll:SetVerticalScroll(0)end
        if refreshBrowser then refreshBrowser()end
        return true
    end
    local function craftableOnly()
        local saved=favoriteScope(false);return saved and saved.craftableOnly==true or false
    end
    local function setCraftableOnly(value)
        if type(value)~='boolean'then return false end
        local saved=favoriteScope(true);if not saved then return false end
        saved.craftableOnly=value
        if page and page.recipeScroll and page.recipeScroll.SetVerticalScroll then page.recipeScroll:SetVerticalScroll(0)end
        if refreshBrowser then refreshBrowser()end;return true
    end
    local function toggleFavorite(recipe)
        if not ownedRecipe(recipe)or type(recipe.recipeId)~='number'or recipe.recipeId<=0 or recipe.recipeId~=math.floor(recipe.recipeId)then return false end
        local saved=favoriteScope(true);if not saved then return false end
        if type(saved.recipes)~='table'then saved.recipes={}end
        local id=tostring(recipe.recipeId);saved.recipes[id]=not saved.recipes[id]or nil
        if refreshBrowser then refreshBrowser()end
        return saved.recipes[id]==true
    end
    local sortLabels={name='Name',profit='Estimated profit',craftable='Craftable now'}
    local function sortMode()
        local saved=favoriteScope(false);local mode=saved and saved.sort
        return sortLabels[mode]and mode or 'name'
    end
    -- Read completed session quotes directly: sorting never replays the cost ledger or queries AH.
    local function sortProfit(recipe)
        local q=completedQuotes[recipeKey(recipe)]
        local now=GetServerTime and GetServerTime()or time()
        if not q or not q.at or now<q.at or now-q.at>21600 or not recipe.materialsKnown or #(recipe.reagents or{})==0 or recipe.outputMin~=recipe.outputMax or not number(recipe.outputMin)or recipe.outputMin<=0 then return end
        local output=q.prices[recipe.outputItemId];if not number(output)or output<=0 then return end
        local needs={};local total=0
        for _,r in ipairs(recipe.reagents)do
            if not number(r.itemId)or not number(r.quantity)or r.quantity<=0 then return end
            needs[r.itemId]=(needs[r.itemId]or 0)+r.quantity
        end
        for id,needed in pairs(needs)do
            local price=q.prices[id];local stock=q.available[id]
            if not number(price)or price<=0 or not number(stock)or stock<needed then return end
            total=total+price*needed
        end
        return math.floor(output*95/100)*recipe.outputMin-total
    end
    local function profitDisplay(recipe)
        local value=sortProfit(recipe)
        if value==nil then return 'No data',0.55,0.6,0.6 end
        local text='Est. '..(value>0 and '+'or'')..money(value,9)
        if value>0 then return text,0.48,0.88,0.62
        elseif value<0 then return text,1,0.4,0.4 end
        return text,0.65,0.7,0.7
    end

    -- WoW addons cannot write arbitrary CSV files. Offer copyable, paginated CSV instead.
    local exportHeader='Recipe ID,Recipe,Item ID,Output Quantity,Material Cost Copper,Sale Unit Copper,Net Sale Copper,Estimated Profit Copper,Quote Time,Status'
    local function exportField(value)
        local v=tostring(value==nil and '' or value):gsub('[\r\n]+',' ')
        return '"'..v:gsub('"','""')..'"'
    end
    local function exportCraftingRows()
        local rows=catalog(filterProfession,filterText,favoritesOnly(),craftableOnly())
        local chunks,current={},{exportHeader}
        local length=#exportHeader
        local function flush()
            if #current>1 then chunks[#chunks+1]=table.concat(current,'\n')end
            current={exportHeader};length=#exportHeader
        end
        for _,recipe in ipairs(rows)do
            local q=completedQuotes[recipeKey(recipe)]
            local now=GetServerTime and GetServerTime()or time()
            local valid=q and q.at and now>=q.at and now-q.at<=21600
            local output=valid and q.prices and q.prices[recipe.outputItemId]
            local profit=sortProfit(recipe)
            local total
            if profit~=nil then
                total=0
                for _,reagent in ipairs(recipe.reagents or {})do
                    total=total+(q.prices[reagent.itemId]or 0)*reagent.quantity
                end
            end
            local qty=recipe.outputMin==recipe.outputMax and recipe.outputMin or nil
            local net=profit and output and qty and math.floor(output*95/100)*qty or nil
            local values={recipe.recipeId,recipe.name,recipe.outputItemId,qty,total,output,net,profit,valid and q.at or nil,profit~=nil and 'Complete' or 'No data'}
            local fields={}
            for i=1,10 do fields[i]=exportField(values[i])end
            local line=table.concat(fields,',')
            if length+#line+1>12000 and #current>1 then flush()end
            current[#current+1]=line;length=length+#line+1
        end
        flush()
        return chunks,#rows
    end
    local function showCraftingExport()
        local chunks,count=exportCraftingRows()
        if #chunks==0 then notify('No recipes match your current filters.');return end
        if not page.exportDialog then
            local frame=CreateFrame('Frame','AZPCForeverCraftingExport',UIParent,'BackdropTemplate')
            frame:SetSize(610,380);frame:SetPoint('CENTER');frame:SetFrameStrata('DIALOG')
            surface(frame,0.025,0.04,0.045,{0.34,0.31,0.24});frame:EnableMouse(true);frame:SetMovable(true)
            frame:RegisterForDrag('LeftButton');frame:SetScript('OnDragStart',frame.StartMoving);frame:SetScript('OnDragStop',frame.StopMovingOrSizing)
            font(frame,'GameFontNormalLarge',16,-18,500):SetText('AZPC Crafting CSV Export')
            frame.help=font(frame,'GameFontHighlightSmall',16,-50,570)
            frame.help:SetText('Select and copy (Ctrl+C). Paste into a .csv file. Copy every part in order.')
            frame.part=font(frame,'GameFontHighlightSmall',16,-76,570)
            local scroll=CreateFrame('ScrollFrame',nil,frame,'UIPanelScrollFrameTemplate')
            scroll:SetPoint('TOPLEFT',16,-102);scroll:SetPoint('BOTTOMRIGHT',-36,48)
            local edit=CreateFrame('EditBox',nil,scroll)
            edit:SetMultiLine(true);edit:SetAutoFocus(false);edit:SetFontObject(ChatFontNormal)
            edit:SetWidth(545);edit:SetMaxLetters(0)
            edit:SetScript('OnEscapePressed',function()frame:Hide()end)
            scroll:SetScrollChild(edit);frame.edit=edit
            frame.previous=uiButton(frame,'Previous',94,26);frame.previous:SetPoint('BOTTOMLEFT',16,12)
            frame.next=uiButton(frame,'Next',94,26);frame.next:SetPoint('LEFT',frame.previous,'RIGHT',8,0)
            frame.selectAll=uiButton(frame,'Select All',104,26);frame.selectAll:SetPoint('LEFT',frame.next,'RIGHT',8,0)
            frame.close=uiButton(frame,'Close',94,26);frame.close:SetPoint('BOTTOMRIGHT',-16,12)
            frame.close:SetScript('OnClick',function()frame:Hide()end)
            frame.selectAll:SetScript('OnClick',function()edit:SetFocus();edit:HighlightText()end)
            local function showPart()
                edit:SetText(frame.chunks[frame.index]or'');edit:SetHeight(math.max(230,edit:GetStringHeight()+18))
                edit:SetFocus();edit:HighlightText()
                frame.part:SetText('Recipes: '..frame.count..' | Part '..frame.index..' of '..#frame.chunks)
                frame.previous:SetEnabled(frame.index>1);frame.next:SetEnabled(frame.index<#frame.chunks)
            end
            frame.previous:SetScript('OnClick',function()frame.index=frame.index-1;showPart()end)
            frame.next:SetScript('OnClick',function()frame.index=frame.index+1;showPart()end)
            frame.showPart=showPart;page.exportDialog=frame
        end
        local dialog=page.exportDialog
        dialog.chunks=chunks;dialog.count=count;dialog.index=1;dialog:Show();dialog.showPart()
    end

    local function sortRecipes(rows,mode,bagCounts)
        local ranked,values={},{}
        for i,r in ipairs(rows)do
            ranked[i]=r
            if mode=='profit'then values[r]=sortProfit(r)
            elseif mode=='craftable'then values[r]=craftableCount(r,bagCounts)end
        end
        table.sort(ranked,function(a,b)
            local x,y=values[a],values[b]
            if x~=y then if x==nil then return false elseif y==nil then return true else return x>y end end
            local an,bn=(a.name or''):lower(),(b.name or''):lower()
            if an~=bn then return an<bn end
            return (a.recipeId or 0)<(b.recipeId or 0)
        end)
        return ranked
    end
    local function setSortMode(mode)
        if not sortLabels[mode]then return false end
        local saved=favoriteScope(true);if not saved then return false end
        saved.sort=mode
        if page and page.recipeScroll and page.recipeScroll.SetVerticalScroll then page.recipeScroll:SetVerticalScroll(0)end
        if refreshBrowser then refreshBrowser()end;return true
    end
    local function categoryFor(recipe)
        local c=recipe.browserCategory
        if type(c)=='table'and type(c.name)=='string'and type(c.id)=='number'then return {key=(recipe.profession or'Other')..'|'..c.id,name=c.name,order=tonumber(c.order)or 9999}end
        local info=api(C_TradeSkillUI,'GetRecipeInfo',recipe.recipeId)
        local category=info and info.categoryID and api(C_TradeSkillUI,'GetCategoryInfo',info.categoryID)
        if type(category)=='table'and type(category.name)=='string'then return {key=(recipe.profession or'Other')..'|'..info.categoryID,name=category.name,order=tonumber(category.uiOrder)or 9999}end
        return {key=(recipe.profession or'Other')..'|other',name=recipe.profession or'Other recipes',order=9999}
    end
    local function recipeGroups(rows)
        local groups,index={},{}
        for _,r in ipairs(rows)do
            local c=categoryFor(r);local g=index[c.key]
            if not g then g={key=c.key,name=c.name,order=c.order,recipes={}};index[c.key]=g;groups[#groups+1]=g end
            g.recipes[#g.recipes+1]=r
        end
        table.sort(groups,function(a,b)if a.order~=b.order then return a.order<b.order end;if a.name~=b.name then return a.name<b.name end;return a.key<b.key end)
        return groups
    end
    local function categoryClosed(key)
        local saved=favoriteScope(false)
        return filterText==''and saved and type(saved.closedCategories)=='table'and saved.closedCategories[key]==true or false
    end
    local function toggleCategory(key)
        if type(key)~='string'then return end
        local saved=favoriteScope(true);if not saved then return end
        if type(saved.closedCategories)~='table'then saved.closedCategories={}end
        saved.closedCategories[key]=not saved.closedCategories[key]or nil
        if refreshBrowser then refreshBrowser()end
    end
    local function catalog(profession,query,onlyFavorites,onlyCraftable)
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
        local rows,names,bagCounts={},{},{}
        query=(query or ''):lower()
        for _,r in pairs(merged)do
            local name=r.profession or 'Other recipes';names[name]=true
            if (not onlyFavorites or isFavorite(r))and(not profession or profession==name) and (query=='' or (r.name or ''):lower():find(query,1,true))and(not onlyCraftable or (craftableCount(r,bagCounts)or 0)>0)then rows[#rows+1]=r end
        end
        table.sort(rows,function(a,b)return (a.name or ''):lower()<(b.name or ''):lower()end)
        local professions={};for name in pairs(names)do professions[#professions+1]=name end;table.sort(professions)
        return rows,professions,bagCounts
    end
    local function stopBatch()
        if batchScan then stopScan('Scan all recipes stopped. Completed prices retained.')end
        if refreshBrowser then refreshBrowser()end
    end
    local function startBatch()
        if not auctionOpen or purchaseQueue or purchaseAttempt or(InCombatLockdown and InCombatLockdown())then notify('Open the AH outside combat and finish buying first.');return false end
        local recipes={}
        for _,r in ipairs(catalog())do
            if r.materialsKnown and #(r.reagents or{})>0 and r.outputItemId then recipes[#recipes+1]=r end
        end
        if #recipes==0 then notify('Open your professions once to capture learned recipes first.');return false end
        installQueryHooks();stopScan();pendingAuto=nil
        batchScan={recipes=recipes,index=1,delay=0};if refreshBrowser then refreshBrowser()end;return true
    end
    local function advanceBatch(delta)
        local b=batchScan;if not b then return end
        if not auctionOpen or purchaseQueue or purchaseAttempt or(InCombatLockdown and InCombatLockdown())then stopBatch();return end
        if b.active then
            if scan and scan.waiting then return end
            if not scan or not scan.complete or scan.key~=b.key then stopBatch();return end
            b.index=b.index+1;b.active=false;b.delay=0
            if b.index>#b.recipes then batchScan=nil;notify('All recipes scanned. Profit sorting now uses available prices.');if refreshBrowser then refreshBrowser()end;return end
        end
        b.delay=b.delay+(delta or 0)
        if b.delay<0.5 or api(C_AuctionHouse,'IsThrottledMessageSystemReady')==false then return end
        local recipe=b.recipes[b.index]
        if searchAll(recipe,true)then b.active=true;b.key=recipeKey(recipe);batchScan=b
        else batchScan=nil end
        if refreshBrowser then refreshBrowser()end
    end
    local craftPrompt,craftPromptMoving
    local function restoreCraftPosition()
        local db=AZPCForeverDB or{};local pos=db.craftPromptPosition
        craftPrompt:ClearAllPoints()
        local w,h=api(UIParent,'GetWidth'),api(UIParent,'GetHeight')
        if type(pos)=='table'and type(pos.x)=='number'and type(pos.y)=='number'and pos.x==pos.x and pos.y==pos.y and pos.x>=0 and pos.x<=1 and pos.y>=0 and pos.y<=1 and w and h and w>0 and h>0 then
            craftPrompt:SetPoint('CENTER',UIParent,'BOTTOMLEFT',pos.x*w,pos.y*h)
        else craftPrompt:SetPoint('CENTER',0,140)end
    end
    local function stopCraftDrag()
        if not craftPromptMoving then return end
        craftPromptMoving=false;craftPrompt:StopMovingOrSizing()
        local x,y=craftPrompt:GetCenter();local w,h=api(UIParent,'GetWidth'),api(UIParent,'GetHeight')
        local scale=api(craftPrompt,'GetEffectiveScale');local parentScale=api(UIParent,'GetEffectiveScale')
        if not x or not y or not w or not h or w<=0 or h<=0 or not scale or not parentScale or parentScale<=0 or scale<=0 then return end
        x=x*scale/parentScale/w;y=y*scale/parentScale/h
        if x==x and y==y and x>=0 and x<=1 and y>=0 and y<=1 then
            AZPCForeverDB=AZPCForeverDB or{};AZPCForeverDB.craftPromptPosition={x=x,y=y};restoreCraftPosition()
        end
    end
    local function craftPlan()
        local saved=favoriteScope(false);local plan=saved and saved.craftPlan
        if type(plan)=='table'and ownedRecipe(plan.recipe)and number(plan.batch)and plan.batch>0 and plan.batch<=999 then return plan end
    end
    local function dismissCraftPlan()
        local saved=favoriteScope(false);if saved then saved.craftPlan=nil end
        if craftPrompt then craftPrompt:Hide()end
    end
    local function plannedCraftEvent(event,unit,castGuid,spellId)
        local plan=craftPlan()
        if event~='UNIT_SPELLCAST_SUCCEEDED'or not plan or unit~='player'or spellId~=plan.recipe.recipeId or type(castGuid)~='string'or castGuid==''then return end
        if type(plan.finishedCasts)~='table'then plan.finishedCasts={}end
        if plan.finishedCasts[castGuid]then return end
        plan.finishedCasts[castGuid]=true
        plan.completedCasts=math.min(plan.batch,(number(plan.completedCasts)or 0)+1)
        if plan.completedCasts>=plan.batch then dismissCraftPlan()else refreshCraftPlan()end
    end
    refreshCraftPlan=function()
        local plan=craftPlan()
        if not plan then if craftPrompt then craftPrompt:Hide()end;return end
        if not UIParent then return end
        if not craftPrompt then
            craftPrompt=CreateFrame('Frame','AZPCForeverCraftReady',UIParent,'BackdropTemplate');craftPrompt:SetSize(304,132);craftPrompt:SetPoint('CENTER',0,140);surface(craftPrompt,0.035,0.05,0.05);craftPrompt:SetFrameStrata('DIALOG');craftPrompt:EnableMouse(true)
            craftPrompt:SetMovable(true);craftPrompt:SetClampedToScreen(true);craftPrompt:RegisterForDrag('LeftButton')
            craftPrompt:SetScript('OnDragStart',function()if not(InCombatLockdown and InCombatLockdown())then craftPromptMoving=true;craftPrompt:StartMoving()end end)
            craftPrompt:SetScript('OnDragStop',stopCraftDrag);craftPrompt:SetScript('OnHide',stopCraftDrag)
            restoreCraftPosition()
            craftPrompt.title=uiText(craftPrompt,'GameFontNormal',14,-14,276)
            craftPrompt.detail=uiText(craftPrompt,'GameFontHighlightSmall',14,-39,276);craftPrompt.detail:SetHeight(40)
            craftPrompt.craft=uiButton(craftPrompt,'Open Recipe',150,26,true);craftPrompt.craft:SetPoint('BOTTOMLEFT',14,14);craftPrompt.craft:SetScript('OnClick',function()local current=craftPlan();if current then openRecipe(current.recipe)end end)
            craftPrompt.later=uiButton(craftPrompt,'Dismiss',112,26);craftPrompt.later:SetPoint('BOTTOMRIGHT',-14,14);craftPrompt.later:SetScript('OnClick',dismissCraftPlan)
        end
        local enough=(craftableCount(plan.recipe)or 0)>=plan.batch
        craftPrompt.title:SetText('AZPC • '..plan.recipe.name)
        local completed=number(plan.completedCasts)or 0
        craftPrompt.detail:SetText(completed>0 and('Crafted '..completed..' / '..plan.batch..'. Finish this batch in your profession window.')or enough and('Ready for '..plan.batch..' craft(s). Open the recipe and use your profession Craft All button.')or('Planned: '..plan.batch..' craft(s). Collect your purchased materials from the mailbox.'))
        craftPrompt.craft:SetText('Open Recipe');craftPrompt.craft:SetEnabled(canOpenRecipe(plan.recipe)==true)
        craftPrompt:Show()
    end
    onMaterialsOrdered=function(recipe,batch)
        local saved=favoriteScope(true);if not saved or not ownedRecipe(recipe)then return end
        local copy={};for k,v in pairs(recipe)do copy[k]=v end
        saved.craftPlan={recipe=copy,batch=batch};refreshCraftPlan()
    end
    local restoringBrowser,restorePending=false,false
    local function saveBrowser(recipe)
        if restoringBrowser then return end
        local saved=favoriteScope(true);if not saved then return end
        if type(saved.browser)~='table'then saved.browser={}end
        saved.browser.profession=filterProfession
        saved.browser.query=filterText:sub(1,100)
        if ownedRecipe(recipe)and type(recipe.recipeId)=='number'and recipe.recipeId>0 and recipe.recipeId==math.floor(recipe.recipeId)then saved.browser.recipeId=recipe.recipeId end
    end
    local function restoreBrowser()
        -- Opening a tab must never interrupt an active, explicitly requested operation.
        if scan and scan.waiting or pendingAuto or purchaseQueue or purchaseAttempt then return false end
        local saved=favoriteScope(false);local browser=saved and saved.browser
        if type(browser)~='table'then return false end
        restoringBrowser=true
        local all,professions=catalog()
        filterProfession=nil
        if type(browser.profession)=='string'then for _,name in ipairs(professions)do if name==browser.profession then filterProfession=name;break end end end
        filterText=type(browser.query)=='string'and browser.query:sub(1,100)or''
        selected=nil;quantity=1;scan=nil
        if type(browser.recipeId)=='number'then for _,r in ipairs(all)do if r.recipeId==browser.recipeId then selected=r;break end end end
        restoredSelection=selected~=nil;restorePending=type(browser.recipeId)=='number'and selected==nil
        if page and page.search then page.search:SetText(filterText)end
        restoringBrowser=false
        return selected~=nil
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
                -- Category metadata is presentation-only; never mutate capture records.
                local copy={};for k,v in pairs(r)do copy[k]=v end;r=copy
                local category=info.categoryID and api(C_TradeSkillUI,'GetCategoryInfo',info.categoryID)
                if type(category)=='table'and type(category.name)=='string'then r.browserCategory={id=info.categoryID,name=category.name,order=category.uiOrder}end
                r.profession=profession;recipes[#recipes+1]=r
            end
        end
        if #recipes==0 then return end -- transient loading must not erase a saved catalog
        AZPCForeverDB=AZPCForeverDB or {};AZPCForeverDB.professionCatalog=AZPCForeverDB.professionCatalog or {}
        who.profession=profession;who.recipes=recipes;who.observedAt=GetServerTime and GetServerTime() or time()
        local key=table.concat({who.character,who.realm,who.faction,who.region,profession},'|')
        AZPCForeverDB.professionCatalog[key]=who
        if restorePending then restoreBrowser()end
        if refreshBrowser then refreshBrowser()end
    end
    local function selectRecipe(recipe)
        batchScan=nil
        stopScan('Recipe changed. Scan prices again.');scan=nil
        selected=recipe;quantity=1;tab='ah';restoredSelection=false;restorePending=false
        saveBrowser(recipe)
        if ownedRecipe(recipe)then local saved=favoriteScope(false);if saved and type(saved.closedCategories)=='table'then saved.closedCategories[categoryFor(recipe).key]=nil end end
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
        local only=favoritesOnly()
        local craftOnly=craftableOnly()
        local rows,professions,bagCounts=catalog(filterProfession,filterText,only,craftOnly)
        local mode=sortMode();rows=sortRecipes(rows,mode,bagCounts)
        page.sortButton:SetText('Sort: '..sortLabels[mode])
        page.canCraft:SetChecked(craftOnly)
        page.scanAll:SetText(batchScan and('Scanning '..batchScan.index..'/'..#batchScan.recipes)or'Scan All Recipes')
        page.scanAll:SetEnabled(not batchScan and not purchaseQueue and not purchaseAttempt)
        page.stopAll:SetEnabled(batchScan~=nil)
        page.profession:SetText(filterProfession or 'All professions')
        page.count:SetText(#rows..(only and ' favorites'or' recipes')..(craftOnly and ' | Craftable'or''))
        page.filtersButton:SetText(craftOnly and '|cff54dbd1Filters*|r'or'Filters')
        page.allRecipes:SetText(not only and '|cff54dbd1All|r'or'All')
        page.favorites:SetText(only and '|cffffd25aFavorites|r'or'Favorites')
        for _,button in ipairs(page.recipeRows)do button:Hide()end
        for _,header in pairs(page.categoryRows)do header:Hide()end
        local positions,y={},0
        page.nextProfitExpiry=nil
        local displayGroups=mode=='name'and recipeGroups(rows)or{{key='sort:'..mode,name=sortLabels[mode],recipes=rows}}
        for _,group in ipairs(displayGroups)do
            local header=page.categoryRows[group.key]
            if not header then
                header=CreateFrame('Button',nil,page.listChild,'BackdropTemplate');header:SetSize(204,22)
                header:SetBackdrop({bgFile='Interface/Buttons/WHITE8X8',edgeFile='Interface/Tooltips/UI-Tooltip-Border',edgeSize=8});header:SetBackdropColor(0.13,0.095,0.035,1);header:SetBackdropBorderColor(0.45,0.32,0.12)
                header.label=font(header,'GameFontNormalSmall',7,-5,172);header.symbol=font(header,'GameFontNormalSmall',184,-5,16)
                header:SetScript('OnClick',function()toggleCategory(header.key)end);page.categoryRows[group.key]=header
            end
            header.key=group.key;header.label:SetText(group.name);header.symbol:SetText(mode=='name'and(categoryClosed(group.key)and'+'or'-')or'')
            header:ClearAllPoints();header:SetPoint('TOPLEFT',0,-y);header:Show();y=y+25
            if mode~='name'or not categoryClosed(group.key)then for _,recipe in ipairs(group.recipes)do positions[recipe]=y;y=y+38 end end
            y=y+5
        end
        for i,recipe in ipairs(rows)do
            local button=page.recipeRows[i]
            if not button then
                button=CreateFrame('Button',nil,page.listChild,'BackdropTemplate');button:SetSize(204,37)
                button.accent=button:CreateTexture(nil,'OVERLAY');button.accent:SetTexture('Interface/Buttons/WHITE8X8');button.accent:SetVertexColor(0.12,0.78,0.74);button.accent:SetWidth(2);button.accent:SetPoint('TOPLEFT');button.accent:SetPoint('BOTTOMLEFT')
                button.icon=button:CreateTexture(nil,'ARTWORK');button.icon:SetSize(16,16);button.icon:SetPoint('TOPLEFT',10,-4)
                button.iconBorder=button:CreateTexture(nil,'OVERLAY');button.iconBorder:SetTexture('Interface/Buttons/UI-Quickslot2');button.iconBorder:SetSize(25,25);button.iconBorder:SetPoint('CENTER',button.icon,'CENTER')
                button.name=font(button,'GameFontHighlightSmall',32,-7,118);typography(button.name,'GameFontHighlightSmall',11);if button.name.SetWordWrap then button.name:SetWordWrap(false)end
                button.craftCount=font(button,'GameFontHighlightSmall',151,-7,26);button.craftCount:SetJustifyH('RIGHT')
                button.profit=font(button,'GameFontHighlightSmall',32,-22,145);typography(button.profit,'GameFontHighlightSmall',10);if button.profit.SetWordWrap then button.profit:SetWordWrap(false)end
                button.profit:SetHeight(12)
                button.favorite=CreateFrame('Button',nil,button);button.favorite:SetSize(24,37);button.favorite:SetPoint('TOPRIGHT',0,0)
                button.favoriteIcon=button.favorite:CreateTexture(nil,'ARTWORK');button.favoriteIcon:SetSize(14,14);button.favoriteIcon:SetPoint('CENTER');button.favoriteIcon:SetTexture('Interface/Common/ReputationStar');button.favoriteIcon:SetTexCoord(0,0.5,0,0.5)
                button.favorite:SetScript('OnClick',function()toggleFavorite(button.recipe)end)
                button.favorite:SetScript('OnEnter',function(self)if GameTooltip and GameTooltip.SetOwner then GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:AddLine(isFavorite(button.recipe)and'Remove from Favorites'or'Add to Favorites',1,0.82,0.35);GameTooltip:Show()end end)
                button.favorite:SetScript('OnLeave',function()if GameTooltip then GameTooltip:Hide()end end)
                button:SetScript('OnClick',function()selectRecipe(button.recipe)end)
                itemTooltip(button,function()return button.recipe and button.recipe.outputItemId end)
                page.recipeRows[i]=button
            end
            button.recipe=recipe;button.name:SetText(recipe.name)
            local estimate,r,g,b=profitDisplay(recipe);button.profit:SetText(estimate);button.profit:SetTextColor(r,g,b)
            local completed=completedQuotes[recipeKey(recipe)]
            local expiry=completed and completed.at and completed.at+21601
            local now=GetServerTime and GetServerTime()or time()
            if expiry and expiry>now and(not page.nextProfitExpiry or expiry<page.nextProfitExpiry)then page.nextProfitExpiry=expiry end
            local available=craftableCount(recipe,bagCounts)
            button.craftCount:SetText(available and available>0 and ('['..available..']')or'')
            if available and available>0 then button.craftCount:SetTextColor(0.48,0.88,0.62)else button.craftCount:SetTextColor(0.55,0.6,0.6)end
            if isFavorite(recipe)then button.favoriteIcon:SetVertexColor(1,0.82,0.25,1)else button.favoriteIcon:SetVertexColor(0.45,0.48,0.48,0.65)end
            local active=selected and recipeKey(selected)==recipeKey(recipe)
            button:SetBackdrop({bgFile='Interface/Buttons/WHITE8X8'});button:SetBackdropColor(active and 0.23 or 0.025,active and 0.16 or 0.035,active and 0.035 or 0.035,active and 0.8 or 0.15)
            if active then button.accent:Show()else button.accent:Hide()end
            local icon=recipe.outputItemId and ((C_Item and api(C_Item,'GetItemIconByID',recipe.outputItemId)) or (GetItemIcon and GetItemIcon(recipe.outputItemId)))
            button.icon:SetTexture(icon or 'Interface/Icons/INV_Misc_QuestionMark');button:ClearAllPoints();if positions[recipe]then button:SetPoint('TOPLEFT',0,-positions[recipe]);button:Show()else button:Hide()end
        end
        page.listChild:SetHeight(math.max(1,y))
        page.empty:SetText(#rows==0 and (craftOnly and 'No matching recipes ready to craft from your bags. Clear Can craft now to see all.'or only and (filterText~=''and'No matching favorites.'or'Star recipes to add them to Favorites. Choose All recipes to browse.')or filterText~='' and 'No matching recipes.' or 'Open each profession once to capture your learned recipes, then return here.') or '')
        for _,button in ipairs(page.menuRows)do button:Hide()end
        local options={'All professions'};for _,name in ipairs(professions)do options[#options+1]=name end
        for i,name in ipairs(options)do
            local button=page.menuRows[i]
            if not button then
                button=uiButton(page.menu,'',196,24);button:SetPoint('TOPLEFT',4,-4-(i-1)*25)
                button:SetScript('OnClick',function()filterProfession=button.value;saveBrowser();page.menu:Hide();refreshBrowser()end)
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
            restoreBrowser();refreshBrowser();render()
        end)
        page.tabButton=button
        font(page,'GameFontNormalLarge',64,-13,160):SetText('RECIPES')
        page.profession=uiButton(page,'All professions',212,29);page.profession:SetPoint('TOPLEFT',12,-40)
        page.professionArrow=page.profession:CreateTexture(nil,'OVERLAY');page.professionArrow:SetTexture('Interface/Buttons/UI-ScrollBar-ScrollDownButton-Up');page.professionArrow:SetSize(18,18);page.professionArrow:SetPoint('RIGHT',-5,0)
        page.profession:SetScript('OnClick',function()page.filters:Hide();if page.menu:IsShown()then page.menu:Hide()else page.menu:Show()end end)
        page.search=CreateFrame('EditBox',nil,page,'BackdropTemplate');page.search:SetSize(212,29);page.search:SetPoint('TOPLEFT',12,-76);surface(page.search,0.03,0.04,0.04,{0.34,0.31,0.24});page.search:SetFontObject(GameFontHighlightSmall);if page.search.SetFont then page.search:SetFont('Fonts/FRIZQT__.TTF',12,'')end;page.search:SetTextInsets(8,8,0,0);page.search:SetAutoFocus(false);page.search:SetMaxLetters(100)
        page.search:SetScript('OnTextChanged',function(self)filterText=self:GetText()or '';saveBrowser();refreshBrowser()end)
        page.search:SetScript('OnEscapePressed',function(self)self:ClearFocus()end)
        page.search:SetScript('OnEnterPressed',function(self)self:ClearFocus()end)
        page.placeholder=font(page.search,'GameFontDisableSmall',8,-8,182);page.placeholder:SetText('Search recipes…')
        page.search:HookScript('OnTextChanged',function(self)if self:GetText()==''then page.placeholder:Show()else page.placeholder:Hide()end end)
        page.allRecipes=uiButton(page,'All',70,25);page.allRecipes:SetPoint('TOPLEFT',12,-111);page.allRecipes:SetScript('OnClick',function()setFavoritesOnly(false)end)
        page.favorites=uiButton(page,'Favorites',72,25);page.favorites:SetPoint('TOPLEFT',86,-111);page.favorites:SetScript('OnClick',function()setFavoritesOnly(true)end)
        page.filtersButton=uiButton(page,'Filters',62,25);page.filtersButton:SetPoint('TOPLEFT',162,-111)
        page.filters=CreateFrame('Frame',nil,page,'BackdropTemplate');page.filters:SetSize(212,166);page.filters:SetPoint('TOPLEFT',12,-139);page.filters:SetFrameLevel(page:GetFrameLevel()+25);surface(page.filters,0.035,0.05,0.05);page.filters:EnableMouse(true);page.filters:Hide()
        page.canCraft=CreateFrame('CheckButton',nil,page.filters,'UICheckButtonTemplate');page.canCraft:SetSize(24,24);page.canCraft:SetPoint('TOPLEFT',6,-9)
        font(page.filters,'GameFontHighlightSmall',34,-16,170):SetText('Can craft now (bags)')
        font(page.filters,'GameFontDisableSmall',10,-42,192):SetText('Green [n] = crafts from your bags')
        page.sortButton=font(page.filters,'GameFontNormalSmall',10,-70,192)
        page.sortOptions={}
        for i,mode in ipairs({'name','profit','craftable'})do
            local option=uiButton(page.filters,sortLabels[mode],192,22);option:SetPoint('TOPLEFT',10,-91-(i-1)*23)
            option:SetScript('OnClick',function()setSortMode(mode);page.filters:Hide()end);page.sortOptions[i]=option
        end
        page.filtersButton:SetScript('OnClick',function()page.menu:Hide();if page.filters:IsShown()then page.filters:Hide()else page.filters:Show()end end)
        page.canCraft:SetScript('OnClick',function(self)setCraftableOnly(self:GetChecked()==true);page.filters:Hide()end)
        local scroll=CreateFrame('ScrollFrame',nil,page,'UIPanelScrollFrameTemplate');page.recipeScroll=scroll;scroll:SetPoint('TOPLEFT',12,-162);scroll:SetPoint('BOTTOMLEFT',12,68);scroll:SetWidth(204)
        page.listChild=CreateFrame('Frame',nil,scroll);page.listChild:SetSize(204,1);scroll:SetScrollChild(page.listChild)
        page.recipeRows={};page.menuRows={};page.categoryRows={}
        page.empty=font(page,'GameFontHighlightSmall',18,-180,194)
        page.count=font(page,'GameFontDisableSmall',12,-142,200)
        page.scanAll=uiButton(page,'Scan All Recipes',142,24);page.scanAll:SetPoint('BOTTOMLEFT',12,8);page.scanAll:SetScript('OnClick',startBatch)
        page.stopAll=uiButton(page,'Stop',62,24);page.stopAll:SetPoint('BOTTOMLEFT',158,8);page.stopAll:SetScript('OnClick',stopBatch)
        page.exportButton=uiButton(page,'Export CSV',104,24);page.exportButton:SetPoint('BOTTOMRIGHT',-12,8);page.exportButton:SetScript('OnClick',showCraftingExport)
        page.menu=CreateFrame('Frame',nil,page,'BackdropTemplate');page.menu:SetSize(204,100);page.menu:SetPoint('TOPLEFT',12,-66);page.menu:SetFrameLevel(page:GetFrameLevel()+20)
        page.menu:SetBackdrop({bgFile='Interface/Buttons/WHITE8X8'});page.menu:SetBackdropColor(0.04,0.06,0.065,1);page.menu:EnableMouse(true);page.menu:Hide()
        local ageElapsed=0
        page:SetScript('OnUpdate',function(_,delta)
            ageElapsed=ageElapsed+delta;if ageElapsed<1 then return end;ageElapsed=0
            local now=GetServerTime and GetServerTime()or time()
            if page.nextProfitExpiry and now>=page.nextProfitExpiry then refreshBrowser()end
        end)
        page:SetScript('OnShow',function()restoreBrowser();refreshBrowser();render()end)
        page:SetScript('OnHide',function()page.menu:Hide();page.filters:Hide();cancelQueue();stopScan('Crafting tab closed. Scan prices again.')end)
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
                setFavoritesOnly(false);setCraftableOnly(false)
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
    AZPCForeverProfession={Model=model,Search=search,ReadSelection=readSelection,OpenRecipe=openRecipe,Buy=buyMaterial,BuyMissing=buyMissing,Pending=pendingQuantity,CancelBuying=cancelQueue,PurchaseEvent=purchaseEvent,OpenQueuedQuote=openQueuedQuote,ReviewPurchase=reviewPurchase,ShowPurchasePopup=showReadyPopup,SearchAll=function(recipe)installQueryHooks();return searchAll(recipe)end,Quote=quote,RetryMaterial=retryMaterial,PriceStatus=priceStatus,Show=showPage,Catalog=catalog,StartScanAll=startBatch,StopScanAll=stopBatch,AdvanceScanAll=advanceBatch,ScanAllState=function()return batchScan end,CraftPlan=craftPlan,PlannedCraftEvent=plannedCraftEvent,RefreshCraftPlan=refreshCraftPlan,ProfitDisplay=profitDisplay,SortRecipes=sortRecipes,SortMode=sortMode,SetSortMode=setSortMode,RecipeGroups=recipeGroups,ToggleCategory=toggleCategory,CategoryClosed=categoryClosed,IsFavorite=isFavorite,ToggleFavorite=toggleFavorite,CraftableCount=craftableCount,CraftableOnly=craftableOnly,SetCraftableOnly=setCraftableOnly,FavoritesOnly=favoritesOnly,SetFavoritesOnly=setFavoritesOnly,RestoreBrowser=restoreBrowser,SaveBrowser=saveBrowser,CaptureCatalog=captureCatalog,Select=selectRecipe}
    local events=CreateFrame('Frame')
    for _,event in ipairs({'UNIT_SPELLCAST_START','UNIT_SPELLCAST_SUCCEEDED','UNIT_SPELLCAST_FAILED','UNIT_SPELLCAST_INTERRUPTED','PLAYER_LOGIN','PLAYER_REGEN_ENABLED','PLAYER_REGEN_DISABLED','TRADE_SKILL_SHOW','TRADE_SKILL_CLOSE','TRADE_SKILL_LIST_UPDATE','TRADE_SKILL_DATA_SOURCE_CHANGED','BAG_UPDATE_DELAYED','AUCTION_HOUSE_SHOW','AUCTION_HOUSE_CLOSED','GET_ITEM_INFO_RECEIVED','AUCTION_HOUSE_BROWSE_RESULTS_UPDATED','AUCTION_HOUSE_BROWSE_RESULTS_ADDED','AUCTION_HOUSE_THROTTLED_SYSTEM_READY','COMMODITY_PURCHASE_SUCCEEDED','COMMODITY_PURCHASE_FAILED','COMMODITY_PRICE_UPDATED','COMMODITY_PRICE_UNAVAILABLE','COMMODITY_SEARCH_RESULTS_RECEIVED','COMMODITY_SEARCH_RESULTS_ADDED','COMMODITY_SEARCH_RESULTS_UPDATED'})do pcall(events.RegisterEvent,events,event)end
    events:SetScript('OnEvent',function(_,event,id,total,spellId)
        local ok=pcall(function()
            plannedCraftEvent(event,id,total,spellId)
            if event=='TRADE_SKILL_SHOW' then professionOpen=true
            elseif event=='TRADE_SKILL_CLOSE' then professionOpen=false
            elseif event=='AUCTION_HOUSE_SHOW' then auctionOpen=true;ensurePage()
            elseif event=='AUCTION_HOUSE_CLOSED' then auctionOpen=false;pendingAuto=nil;cancelQueue();stopScan('AH closed. Scan prices again.');
            elseif event=='AUCTION_HOUSE_BROWSE_RESULTS_UPDATED' or event=='AUCTION_HOUSE_BROWSE_RESULTS_ADDED' then readResults();openQueuedQuote() end
            purchaseEvent(event,id,total)
            if event=='BAG_UPDATE_DELAYED'or event=='PLAYER_LOGIN'or event=='TRADE_SKILL_SHOW'or event=='TRADE_SKILL_LIST_UPDATE'or event=='PLAYER_REGEN_ENABLED'or event=='PLAYER_REGEN_DISABLED'then refreshCraftPlan()end
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
        advanceBatch(delta)
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

-- BEGIN AZPC SYNC DETAILS
do
-- Read-only presentation of session activity. Never rebuilds costs or captures mail.
AZPCForeverSyncStatus={}
local status=AZPCForeverSyncStatus
local cursors,counts={}, {sales=0,returns=0,purchases=0,activity=0}
local initialized=false
local function lists()
 local d=AZPCForeverDB or {};local c=d.crafting or {}
 return {trades=d.trades or {},crafts=c.crafts or {},materials=c.materialEvents or {},vendor=c.vendorEvents or {}}
end
local function belongs(row)
 return row.character==(UnitName and UnitName('player') or '') and row.realm==(GetRealmName and GetRealmName() or '')
end
function status.Initialize()
 if initialized then return end
 for kind,rows in pairs(lists())do cursors[kind]=#rows end
 initialized=true
end
function status.Counts()
 status.Initialize()
 for kind,rows in pairs(lists())do
  local first=cursors[kind] or 0
  if #rows<first then first=#rows end
  for i=first+1,#rows do
   local row=rows[i]
   if kind=='trades' then
    local action=row.tradeExport and row.tradeExport:match('^AZPCFTRADE|%d+|[^|]*|([^|]*)|')
    if action=='sell' then counts.sales=counts.sales+1 elseif action=='expired' then counts.returns=counts.returns+1 elseif action=='buy' then counts.purchases=counts.purchases+1 end
   elseif belongs(row) then
    if kind=='crafts' or kind=='materials' and row.kind=='free' then counts.activity=counts.activity+1
    elseif kind=='vendor' and row.kind=='buy' then counts.purchases=counts.purchases+1 end
   end
  end
  cursors[kind]=#rows
 end
 return {sales=counts.sales,returns=counts.returns,purchases=counts.purchases,activity=counts.activity,total=counts.sales+counts.returns+counts.purchases+counts.activity}
end
function status.CompactText()
 local c=status.Counts()
 if c.total==0 then return 'Auction data recorded.\n\nReload to save it so your watcher can sync it to AZPC.' end
 return c.sales..' sale(s), '..c.returns..' return(s), '..c.purchases..' purchase(s), '..c.activity..' loot/craft record(s) captured.\n\nReload to save for AZPC. Your watcher must be running.'
end
local function stamp(at)
 if type(at)~='number' or at<=0 then return 'No confirmed upload available' end
 return type(date)=='function' and date('%b %d, %I:%M %p',at) or tostring(at)
end
function status.WatcherText(now)
 local s=AZPCForeverWatcherStatus
 if type(s)~='table' or s.schema~=1 or type(s.checkedAt)~='number' then return 'No saved watcher status','Open AZPC Launcher to check your watcher.','Status becomes available after a reload.' end
 local age=now-s.checkedAt
 local check=age<0 and 'Saved check-in time could not be verified' or age<=120 and 'Recent saved watcher check-in' or 'No recent saved watcher check-in'
 local upload=type(s.lastUploadAt)=='number' and s.lastUploadAt>0 and 'This PC - Last acknowledged batch:\n'..stamp(s.lastUploadAt) or 'No confirmed upload available'
 return check,upload,'Last known status at '..stamp(s.checkedAt)..'\nLoaded at login/reload; this is not a live connection.'
end
local panel,labels,reload
local function combat()return type(InCombatLockdown)=='function' and InCombatLockdown()end
local function refresh()
 if not panel then return end
 local c=status.Counts()
 labels.summary:SetText(c.total>0 and c.total..' captured activity record(s) ready to save' or 'No new trade activity this session')
 for key,label in pairs(labels.counts)do label:SetText(tostring(c[key]))end
 labels.note:SetText(c.total>0 and 'New activity is not saved to disk until reload/logout.' or 'Saved records may still be queued. Check the last acknowledged batch below.')
 local now=GetServerTime and GetServerTime() or time();local check,upload,detail=status.WatcherText(now)
 labels.check:SetText(check);labels.upload:SetText(upload);labels.detail:SetText(detail)
 reload:SetEnabled(c.total>0 and not combat())
end
function status.Show()
 if combat() then if print then print('AZPC: Open sync details after combat.')end;return false end
 if not panel then
  panel=CreateFrame('Frame','AZPCForeverSyncWindow',UIParent,BackdropTemplateMixin and 'BackdropTemplate' or nil)
  panel:SetSize(620,440);panel:SetPoint('CENTER');panel:SetFrameStrata('DIALOG');panel:SetClampedToScreen(true)
  if panel.SetBackdrop then panel:SetBackdrop({bgFile='Interface\\DialogFrame\\UI-DialogBox-Background',edgeFile='Interface\\DialogFrame\\UI-DialogBox-Border',tile=true,tileSize=32,edgeSize=24,insets={left=7,right=7,top=7,bottom=7}})end
  panel:EnableMouse(true);panel:SetMovable(true);panel:RegisterForDrag('LeftButton');panel:SetScript('OnDragStart',panel.StartMoving);panel:SetScript('OnDragStop',panel.StopMovingOrSizing)
  local function text(value,x,y,width,font)
   local f=panel:CreateFontString(nil,'OVERLAY',font or 'GameFontHighlight');f:SetPoint('TOPLEFT',x,y);f:SetWidth(width);f:SetJustifyH('LEFT');f:SetText(value);return f
  end
  text('|cff54dbd1AZPC|r  |  Sync Status',26,-26,550,'GameFontNormalLarge')
  text((UnitName and UnitName('player') or '')..'  -  '..(GetRealmName and GetRealmName() or ''),26,-55,560,'GameFontHighlightSmall')
  local close=CreateFrame('Button',nil,panel,'UIPanelCloseButton');close:SetPoint('TOPRIGHT',-4,-4)
  labels={counts={}};labels.summary=text('',26,-91,568,'GameFontNormalLarge')
  text('CAPTURED THIS SESSION',26,-135,275,'GameFontNormal');text('LAST KNOWN WATCHER STATUS',325,-135,265,'GameFontNormal')
  local rows={{'Auction sales','sales'},{'Expired / returned','returns'},{'Purchases','purchases'},{'Loot & crafts','activity'}}
  for i,row in ipairs(rows)do local y=-165-(i-1)*32;text(row[1],26,y,220);labels.counts[row[2]]=text('0',270,y,35)end
  labels.check=text('',325,-166,260);labels.upload=text('',325,-208,260,'GameFontHighlightSmall');labels.detail=text('',325,-247,260,'GameFontDisableSmall')
  labels.note=text('',26,-315,568,'GameFontNormalSmall')
  reload=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate');reload:SetSize(270,34);reload:SetPoint('BOTTOMLEFT',55,51);reload:SetText('Reload to Save');reload:SetScript('OnClick',function()if not combat() and type(ReloadUI)=='function' then ReloadUI()end end)
  local later=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate');later:SetSize(160,34);later:SetPoint('LEFT',reload,'RIGHT',16,0);later:SetText('Later');later:SetScript('OnClick',function()panel:Hide()end)
  text('Reload saves locally. Your watcher then uploads to your AZPC account.',26,-404,570,'GameFontDisableSmall')
  panel:SetScript('OnShow',refresh);local elapsed=0;panel:SetScript('OnUpdate',function(_,dt)elapsed=elapsed+dt;if elapsed>=1 then elapsed=0;refresh()end end)
  if type(UISpecialFrames)=='table' then UISpecialFrames[#UISpecialFrames+1]='AZPCForeverSyncWindow'end
 end
 panel:Show();refresh();return true
end
local events=CreateFrame('Frame');events:RegisterEvent('ADDON_LOADED');events:SetScript('OnEvent',function(_,_,name)if name=='AZPCForever' then status.Initialize()end end)

end
-- END AZPC SYNC DETAILS
-- BEGIN AZPC FIRST RUN SETUP
do
AZPCForeverSetup={}
local setup=AZPCForeverSetup
local panel,labels,reload
local autoPending=false
local function now()return GetServerTime and GetServerTime() or time()end
local function combat()return type(InCombatLockdown)=='function' and InCombatLockdown()end
local function character()
 local name=UnitName and UnitName('player');local realm=GetRealmName and GetRealmName();local guid=UnitGUID and UnitGUID('player')
 if not name or name=='' or not realm or realm=='' or not guid then return end
 return name,realm,guid..'|'..realm..'|'..tostring(currentRegion())
end
local function state()
 local name,realm,key=character();if not key then return end
 AZPCForeverDB=AZPCForeverDB or {};local d=AZPCForeverDB
 d.onboarding=d.onboarding or {schema=1,characters={}};d.onboarding.characters=d.onboarding.characters or {}
 if not d.onboarding.characters[key]then
  local c=d.crafting or {};local veteran=#(d.trades or {})>0 or next(c.recipes or {})~=nil or #(c.crafts or {})>0 or #(c.materialEvents or {})>0
  d.onboarding.characters[key]={startedAt=now(),existingHistory=veteran}
 end
 return d.onboarding.characters[key],name,realm
end
function setup.Progress()
 local s,name,realm=state();if not s then return end
 local c=(AZPCForeverDB or {}).crafting or {};local professions={};local seen={}
 for _,r in pairs(c.recipes or {})do if r.character==name and r.realm==realm and r.region==currentRegion() and type(r.profession)=='string' and r.profession~='' then seen[r.profession]=true end end
 local supported=type(GetProfessions)=='function' and type(GetProfessionInfo)=='function'
 if supported then
  local ids={GetProfessions()};for _,id in pairs(ids)do
   local title,_,_,_,_,_,skill=GetProfessionInfo(id)
   if title and skill~=182 and skill~=393 and skill~=356 and skill~=794 then professions[#professions+1]={name=title,seen=seen[title]==true}end
  end
 end
 table.sort(professions,function(a,b)return a.name<b.name end)
 local recipeDone=false;local recipeText
 if supported and #professions>0 then
  local missing={};for _,p in ipairs(professions)do if not p.seen then missing[#missing+1]=p.name end end
  recipeDone=#missing==0;recipeText=recipeDone and 'Saved recipes found for each detected crafting profession.' or 'Open: '..table.concat(missing,', ')..'. Then refresh this checklist.'
 elseif supported then recipeDone=true;recipeText='Optional: no crafting professions detected. Learn one whenever you like.'
 else
  local found={};for title in pairs(seen)do found[#found+1]=title end;table.sort(found)
  recipeText=#found>0 and 'Recipes found: '..table.concat(found,', ')..'. Open any other professions you use.' or 'Optional: open each crafting profession you use, then refresh.'
  recipeDone=false
 end
 local bankDone=false
 for _,r in ipairs(c.materialEvents or {})do if r.kind=='inventory_observation' and r.confirmation=='bags_and_character_bank_observed' and r.character==name and r.realm==realm and r.region==currentRegion() then bankDone=true;break end end
 local w=AZPCForeverWatcherStatus;local acknowledged=type(w)=='table' and w.schema==1 and type(w.lastUploadAt)=='number' and w.lastUploadAt>0
 local uploaded=acknowledged and w.lastUploadAt>=s.startedAt
 return {
  {done=true,title='Character detected',detail=name..' - '..realm},
  {done=recipeDone,title='Open your crafting professions (optional)',detail=recipeText},
  {done=bankDone,title='Open your character bank (optional)',detail=bankDone and 'A confirmed bag and character-bank observation is saved.' or 'Visit your banker to record stored materials. Then refresh.'},
  {done=acknowledged,title='Create your AZPC account, then connect the Launcher',detail=acknowledged and 'This PC has an acknowledged upload. Account connection worked at that time.' or 'Go to azpc.market/login to create your account. Then connect it in AZPC Launcher and start the watcher.'},
  {done=uploaded,title='Reload and confirm your first upload',detail=uploaded and 'Upload confirmed. Sign in at azpc.market, then open My Trades to see your character.' or 'Reload to save, let the watcher upload, then reload to load its confirmation.'}
 },s
end
local function refresh()
 if not panel then return end
 local rows=setup.Progress();if not rows then return end
 for i,row in ipairs(rows)do labels[i].title:SetText((row.done and '|cff66dd99[Done]|r ' or '|cffffcc66[Next]|r ')..row.title);labels[i].detail:SetText(row.detail)end
 reload:SetEnabled(not combat())
end
function setup.Show()
 if combat()then if print then print('AZPC: Open /azpcf setup after combat.')end;return false end
 if not UIParent then return false end
 local rows,s=setup.Progress();if not rows then return false end
 if not panel then
  panel=CreateFrame('Frame','AZPCForeverSetupWindow',UIParent,BackdropTemplateMixin and 'BackdropTemplate' or nil)
  panel:SetSize(620,555);panel:SetPoint('CENTER');panel:SetFrameStrata('DIALOG');panel:SetClampedToScreen(true)
  if panel.SetBackdrop then panel:SetBackdrop({bgFile='Interface\\DialogFrame\\UI-DialogBox-Background',edgeFile='Interface\\DialogFrame\\UI-DialogBox-Border',tile=true,tileSize=32,edgeSize=24,insets={left=7,right=7,top=7,bottom=7}})end
  panel:EnableMouse(true);panel:SetMovable(true);panel:RegisterForDrag('LeftButton');panel:SetScript('OnDragStart',panel.StartMoving);panel:SetScript('OnDragStop',panel.StopMovingOrSizing)
  local function text(value,x,y,width,font)
   local f=panel:CreateFontString(nil,'OVERLAY',font or 'GameFontHighlight');f:SetPoint('TOPLEFT',x,y);f:SetWidth(width);f:SetJustifyH('LEFT');f:SetText(value);return f
  end
  text('|cff54dbd1AZPC|r  |  Getting Started',26,-27,550,'GameFontNormalLarge')
  text('First, create your account at azpc.market/login. Then connect it in AZPC Launcher.',26,-57,565,'GameFontHighlightSmall')
  local close=CreateFrame('Button',nil,panel,'UIPanelCloseButton');close:SetPoint('TOPRIGHT',-4,-4)
  labels={};for i=1,5 do local y=-96-(i-1)*70;labels[i]={title=text('',26,y,565,'GameFontNormal'),detail=text('',45,y-24,545,'GameFontHighlightSmall')}end
  text('Dashboard: forever.azpc.market/my-trades\nOptional steps can wait. Reopen this checklist with /azpcf setup.',26,-453,565,'GameFontDisableSmall')
  local function button(title,x,width,fn)local b=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate');b:SetSize(width,30);b:SetPoint('BOTTOMLEFT',x,24);b:SetText(title);b:SetScript('OnClick',fn);return b end
  button('Refresh checklist',26,174,refresh)
  reload=button('Reload to Save',218,174,function()if not combat() and type(ReloadUI)=='function'then ReloadUI()end end)
  button('Later',410,174,function()panel:Hide()end)
  panel:SetScript('OnShow',refresh);panel:SetScript('OnHide',function()local current=state();if current then current.dismissed=true end end)
  if type(UISpecialFrames)=='table'then UISpecialFrames[#UISpecialFrames+1]='AZPCForeverSetupWindow'end
 end
 s.prompted=true;autoPending=false;panel:Show();refresh();return true
end
function setup.MaybePrompt()
 local s=state();if not s or s.existingHistory or s.dismissed or s.prompted then return end
 if combat()then autoPending=true;return end
 setup.Show()
end
local f=CreateFrame('Frame');f:RegisterEvent('PLAYER_LOGIN');f:RegisterEvent('PLAYER_REGEN_ENABLED')
f:SetScript('OnEvent',function(_,event)
 if event=='PLAYER_LOGIN' then
  local fn=function()local ok,err=pcall(setup.MaybePrompt);if not ok and print then print('AZPC setup: '..tostring(err))end end
  if C_Timer and type(C_Timer.After)=='function'then C_Timer.After(3,fn)else fn()end
 elseif autoPending then setup.MaybePrompt()end
end)
if SlashCmdList then local previous=SlashCmdList.AZPCFOREVER;SlashCmdList.AZPCFOREVER=function(command)
 if (command or ''):lower():match('^%s*setup%s*$')then return setup.Show()elseif previous then return previous(command)end
end end
end
-- END AZPC FIRST RUN SETUP

-- BEGIN AZPC MINIMAP MENU
do
AZPCForeverMinimap={}
local minimap=AZPCForeverMinimap
local button,menu
local function settings()
 AZPCForeverDB=AZPCForeverDB or {};local d=AZPCForeverDB
 d.minimap=d.minimap or {};local s=d.minimap
 if type(s.angle)~='number' or s.angle~=s.angle or math.abs(s.angle)>360000 then s.angle=225 end
 s.angle=s.angle%360;return s
end
local function combat()return type(InCombatLockdown)=='function' and InCombatLockdown()end
local function notify(text)if print then print('|cff54dbd1AZPC:|r '..text)end end
local function position()
 if not button or not Minimap then return end
 local a=settings().angle*math.pi/180
 local rx=(Minimap.GetWidth and Minimap:GetWidth() or 140)/2+9
 local ry=(Minimap.GetHeight and Minimap:GetHeight() or 140)/2+9
 button:ClearAllPoints();button:SetPoint('CENTER',Minimap,'CENTER',math.cos(a)*rx,math.sin(a)*ry)
end
function minimap.SetAngle(angle)
 if type(angle)~='number' or angle~=angle or math.abs(angle)>360000 then return false end
 settings().angle=angle%360;position();return true
end
local function angleFor(x,y)
 if x==0 then return y>=0 and 90 or 270 end
 local a=math.atan(y/x)*180/math.pi;if x<0 then a=a+180 end;return a%360
end
local function drag()
 if combat()then if button then button:SetScript('OnUpdate',nil)end;return end
 if type(GetCursorPosition)~='function' or not Minimap.GetCenter then return end
 local x,y=GetCursorPosition();local cx,cy=Minimap:GetCenter();if not cx or not cy then return end
 local scale=Minimap.GetEffectiveScale and Minimap:GetEffectiveScale() or 1
 if not scale or scale<=0 then return end
 minimap.SetAngle(angleFor(x/scale-cx,y/scale-cy))
end
-- Palette and rectangles sampled from the user-supplied AZPC diamond emblem.
-- Rendered once at creation; no texture files, timers, history reads or network calls.
local logoColors={'cbab72','35a7a4','6e633d','095d5f','403d22','15322c','013638','161c14','061a1e','03181c','071214','041216','041015','041014','021117','010a0f'}
local logoRects={{15,3,1,1,7},{16,3,1,1,5},{17,3,1,1,6},{14,4,1,1,7},{15,4,1,1,3},{16,4,2,1,1},{18,4,1,1,4},{19,4,1,1,7},{13,5,1,1,7},{14,5,1,1,3},{15,5,1,1,1},{16,5,2,1,3},{18,5,1,1,1},{19,5,1,1,4},{20,5,1,1,7},{12,6,1,1,7},{13,6,1,1,3},{14,6,1,1,1},{15,6,1,1,3},{18,6,1,1,3},{19,6,1,1,1},{20,6,1,1,4},{21,6,1,1,7},{11,7,1,1,4},{12,7,1,1,3},{13,7,1,1,1},{14,7,1,1,3},{16,7,1,1,6},{19,7,1,1,3},{20,7,1,1,1},{21,7,1,1,4},{22,7,1,1,7},{10,8,1,1,4},{11,8,1,1,3},{12,8,1,1,1},{13,8,1,1,3},{20,8,1,1,3},{21,8,1,1,1},{22,8,1,1,4},{23,8,1,1,7},{9,9,1,1,4},{10,9,1,1,3},{11,9,1,1,1},{12,9,1,1,5},{16,9,1,1,6},{21,9,1,1,3},{22,9,1,1,1},{23,9,1,3,2},{24,9,1,1,4},{25,9,1,1,7},{8,10,1,1,4},{9,10,1,1,3},{10,10,1,1,1},{11,10,1,1,5},{16,10,1,3,1},{17,10,1,1,5},{21,10,1,1,7},{22,10,1,4,2},{24,10,2,3,2},{26,10,1,2,7},{7,11,1,1,7},{8,11,1,1,3},{9,11,1,1,1},{10,11,1,1,5},{15,11,1,1,3},{17,11,1,3,1},{20,11,1,1,7},{21,11,1,3,2},{6,12,1,1,7},{7,12,1,2,3},{8,12,1,1,1},{9,12,1,1,5},{14,12,1,1,6},{15,12,1,3,1},{18,12,1,1,5},{19,12,1,1,7},{20,12,1,1,4},{23,12,1,1,1},{26,12,1,1,2},{27,12,1,1,7},{5,13,1,1,7},{6,13,1,2,3},{14,13,1,1,3},{16,13,1,1,3},{18,13,1,2,1},{23,13,2,1,2},{25,13,1,1,4},{26,13,1,1,1},{27,13,1,1,3},{28,13,1,1,7},{4,14,1,1,7},{5,14,1,2,3},{14,14,1,2,1},{17,14,1,1,3},{19,14,1,1,6},{20,14,1,2,1},{21,14,1,1,3},{22,14,1,1,4},{23,14,1,1,2},{24,14,1,1,4},{26,14,1,2,5},{27,14,1,1,1},{28,14,1,2,3},{29,14,1,1,7},{3,15,1,1,6},{4,15,1,1,3},{6,15,2,1,5},{13,15,1,1,3},{15,15,1,1,6},{17,15,1,1,5},{18,15,1,1,3},{19,15,1,2,1},{22,15,1,1,7},{23,15,1,2,4},{27,15,1,3,5},{29,15,1,1,3},{30,15,1,2,6},{3,16,1,1,5},{4,16,1,1,1},{6,16,2,1,3},{13,16,1,2,1},{14,16,1,2,3},{15,16,1,1,5},{16,16,3,1,1},{21,16,1,1,7},{22,16,1,2,4},{26,16,1,1,1},{28,16,1,1,5},{29,16,1,1,1},{4,17,2,1,3},{12,17,1,3,3},{15,17,1,1,1},{16,17,1,1,5},{17,17,1,1,3},{18,17,1,1,1},{20,17,2,3,4},{23,17,1,2,7},{28,17,1,1,3},{29,17,1,1,5},{4,18,1,2,7},{5,18,2,1,3},{10,18,1,1,3},{11,18,1,1,5},{13,18,1,1,3},{14,18,1,1,1},{15,18,1,1,3},{19,18,1,6,4},{22,18,1,3,2},{26,18,1,1,5},{27,18,1,1,3},{28,18,1,1,5},{29,18,1,1,7},{5,19,1,2,7},{6,19,1,1,3},{7,19,1,1,1},{9,19,1,1,3},{10,19,2,1,1},{13,19,1,1,1},{14,19,1,1,3},{17,19,2,2,4},{23,19,1,1,6},{25,19,1,1,5},{26,19,1,1,1},{27,19,1,1,5},{28,19,1,1,7},{6,20,1,2,7},{7,20,2,1,3},{9,20,1,1,1},{10,20,1,1,5},{11,20,1,1,3},{12,20,1,1,1},{13,20,1,1,3},{20,20,1,3,2},{21,20,1,2,4},{24,20,1,1,5},{25,20,1,1,1},{26,20,1,1,5},{27,20,1,1,7},{7,21,1,1,4},{8,21,1,1,3},{9,21,1,2,5},{12,21,1,1,5},{15,21,1,1,4},{16,21,1,1,7},{17,21,1,5,2},{18,21,1,1,4},{22,21,1,1,4},{23,21,1,1,3},{24,21,1,1,1},{25,21,1,1,5},{26,21,1,1,7},{6,22,1,2,4},{7,22,1,1,2},{8,22,1,2,4},{10,22,1,2,3},{13,22,2,1,7},{15,22,1,4,2},{16,22,1,4,4},{18,22,1,3,2},{22,22,1,2,3},{23,22,1,1,1},{24,22,1,1,5},{25,22,1,1,7},{7,23,1,1,4},{9,23,1,1,4},{11,23,1,1,1},{12,23,1,1,6},{13,23,2,1,4},{20,23,1,1,4},{21,23,1,1,3},{23,23,1,1,5},{24,23,1,1,4},{9,24,1,1,7},{10,24,1,1,4},{11,24,2,1,3},{14,24,1,1,4},{20,24,1,1,3},{21,24,1,1,1},{22,24,1,1,5},{23,24,1,2,4},{31,24,1,1,7},{10,25,1,1,7},{11,25,1,1,4},{12,25,1,1,3},{13,25,1,1,1},{18,25,1,1,4},{19,25,1,1,5},{20,25,1,1,1},{21,25,1,1,5},{22,25,1,1,4},{24,25,1,2,7},{25,25,3,1,4},{28,25,4,1,2},{11,26,1,1,7},{12,26,1,1,4},{13,26,2,1,3},{15,26,1,1,6},{16,26,2,1,7},{18,26,2,1,3},{20,26,1,1,5},{21,26,1,1,4},{22,26,2,1,7},{25,26,2,1,7},{27,26,3,1,4},{30,26,2,1,2},{12,27,2,1,7},{14,27,1,1,3},{15,27,1,1,1},{17,27,1,1,5},{18,27,1,1,1},{19,27,1,1,5},{20,27,1,1,7},{13,28,2,1,7},{15,28,1,1,5},{16,28,1,1,1},{17,28,1,1,3},{18,28,1,1,5},{19,28,1,1,7},{20,28,1,1,6},{14,29,2,1,7},{16,29,2,1,5},{18,29,1,1,7},{16,30,2,1,7}}
local function drawLogo(owner)
 for _,r in ipairs(logoRects)do
  local hex=logoColors[r[5]];local red=tonumber(hex:sub(1,2),16)/255;local green=tonumber(hex:sub(3,4),16)/255;local blue=tonumber(hex:sub(5,6),16)/255
  local t=owner:CreateTexture(nil,'ARTWORK');t:SetSize(r[3]*0.75,r[4]*0.75);t:SetPoint('TOPLEFT',4+r[1]*0.75,-4-r[2]*0.75)
  if t.SetColorTexture then t:SetColorTexture(red,green,blue,1)else t:SetTexture('Interface/Buttons/WHITE8X8');t:SetVertexColor(red,green,blue,1)end
 end
end
function minimap.Invoke(action)
 if combat()then notify('Open the AZPC menu after combat.');return false end
 if menu then menu:Hide()end
 if action=='crafting' and AZPCForeverProfession and AZPCForeverProfession.Show then AZPCForeverProfession.Show();return true
 elseif action=='sync' and AZPCForeverSyncStatus then return AZPCForeverSyncStatus.Show()
 elseif action=='setup' and AZPCForeverSetup then return AZPCForeverSetup.Show()
 elseif action=='settings' and AZPCForeverSettings then return AZPCForeverSettings.Show()
 elseif action=='bug' and AZPCForeverBugReport then return AZPCForeverBugReport.Show()
 elseif action=='hide' then return minimap.SetHidden(true)end
 return false
end
local function restoreMenuPosition()
 local p=settings().menuPosition
 menu:ClearAllPoints()
 if type(p)=='table' and type(p.x)=='number' and type(p.y)=='number' and p.x==p.x and p.y==p.y and p.x>=0 and p.x<=1 and p.y>=0 and p.y<=1 and UIParent.GetWidth and UIParent.GetHeight then
  menu:SetPoint('CENTER',UIParent,'BOTTOMLEFT',p.x*UIParent:GetWidth(),p.y*UIParent:GetHeight())
 else menu:SetPoint('TOPRIGHT',button,'BOTTOMRIGHT',0,-4)end
end
local function saveMenuPosition()
 local x,y=menu:GetCenter();local w,h=UIParent:GetWidth(),UIParent:GetHeight()
 local scale=menu:GetEffectiveScale()/UIParent:GetEffectiveScale()
 if not x or not y or w<=0 or h<=0 or scale<=0 then return end
 x=x*scale/w;y=y*scale/h
 if x==x and y==y and x>=0 and x<=1 and y>=0 and y<=1 then settings().menuPosition={x=x,y=y}end
end
function minimap.ToggleMenu()
 if combat()then notify('Open the AZPC menu after combat.');return false end
 if not button then return false end
 if not menu then
  menu=CreateFrame('Frame','AZPCForeverMinimapMenu',UIParent,BackdropTemplateMixin and 'BackdropTemplate' or nil)
  menu:SetSize(212,266);menu:SetFrameStrata('DIALOG');menu:SetClampedToScreen(true);menu:EnableMouse(true)
  menu:SetMovable(true);menu:RegisterForDrag('LeftButton')
  local moving=false
  local function stopMoving()if moving then moving=false;menu:StopMovingOrSizing();saveMenuPosition()end end
  menu:SetScript('OnDragStart',function()if not combat()then moving=true;menu:StartMoving()end end)
  menu:SetScript('OnDragStop',stopMoving);menu:SetScript('OnHide',stopMoving)
  if menu.SetBackdrop then menu:SetBackdrop({bgFile='Interface/DialogFrame/UI-DialogBox-Background',edgeFile='Interface/DialogFrame/UI-DialogBox-Border',tile=true,tileSize=32,edgeSize=20,insets={left=6,right=6,top=6,bottom=6}})end
  local title=menu:CreateFontString(nil,'OVERLAY','GameFontNormal');title:SetPoint('TOPLEFT',16,-17);title:SetText('|cff54dbd1AZPC|r')
  local close=CreateFrame('Button',nil,menu,'UIPanelCloseButton');close:SetPoint('TOPRIGHT',-2,-2)
  for i,row in ipairs({{'Crafting','crafting'},{'Sync Status','sync'},{'Getting Started','setup'},{'Settings','settings'},{'Report Bug','bug'},{'Hide minimap icon','hide'}})do
   local action=row[2];local b=CreateFrame('Button',nil,menu,'UIPanelButtonTemplate');b:SetSize(180,28);b:SetPoint('TOPLEFT',16,-43-(i-1)*34);b:SetText(row[1]);b:SetScript('OnClick',function()minimap.Invoke(action)end)
  end
  menu:Hide();if type(UISpecialFrames)=='table'then UISpecialFrames[#UISpecialFrames+1]='AZPCForeverMinimapMenu'end
 end
 if menu:IsShown()then menu:Hide()else restoreMenuPosition();menu:Show()end
 return true
end
function minimap.Initialize()
 if button then return true end
 if not Minimap or not UIParent then return false end
 button=CreateFrame('Button','AZPCForeverMinimapButton',Minimap)
 button:SetSize(32,32);button:SetFrameStrata('MEDIUM');button:SetFrameLevel(Minimap:GetFrameLevel()+5);button:EnableMouse(true)
 local background=button:CreateTexture(nil,'BACKGROUND');background:SetAllPoints();background:SetTexture('Interface/Minimap/UI-Minimap-Background')
 drawLogo(button)
 local ring=button:CreateTexture(nil,'OVERLAY');ring:SetTexture('Interface/Minimap/MiniMap-TrackingBorder');ring:SetSize(54,54);ring:SetPoint('TOPLEFT',-2,2)
 button:SetHighlightTexture('Interface/Minimap/UI-Minimap-ZoomButton-Highlight')
 button:RegisterForClicks('LeftButtonUp','RightButtonUp');button:RegisterForDrag('LeftButton')
 local stopped=-10
 button:SetScript('OnDragStart',function()if combat()then return end;if menu then menu:Hide()end;button:SetScript('OnUpdate',drag)end)
 button:SetScript('OnDragStop',function()button:SetScript('OnUpdate',nil);stopped=GetTime and GetTime() or -10 end)
 button:SetScript('OnClick',function()if GetTime and GetTime()-stopped<0.15 then return end;minimap.ToggleMenu()end)
 button:SetScript('OnEnter',function()
  if GameTooltip and GameTooltip.SetOwner then GameTooltip:SetOwner(button,'ANCHOR_LEFT');GameTooltip:AddLine('AZPC',0.33,0.86,0.82);GameTooltip:AddLine('Click: Crafting, Sync Status, Setup, Settings',1,1,1);GameTooltip:AddLine('Drag to move. /azpcf minimap hide to hide.',0.7,0.7,0.7);GameTooltip:Show()end
 end)
 button:SetScript('OnLeave',function()if GameTooltip then GameTooltip:Hide()end end)
 position();if settings().hidden then button:Hide()else button:Show()end;return true
end
function minimap.SetHidden(hidden)
 settings().hidden=hidden==true
 minimap.Initialize()
 if button then if hidden then button:SetScript('OnUpdate',nil);button:Hide()else position();button:Show()end end
 if menu then menu:Hide()end
 if hidden then notify('Minimap icon hidden. /azpcf minimap show restores it.')end
 return true
end
function minimap.Command(command)
 local action=(command or ''):lower():match('^%s*minimap%s*(.-)%s*$');if action==nil then return false end
 if action=='show'then minimap.SetHidden(false)
 elseif action=='hide'then minimap.SetHidden(true)
 elseif action=='reset'then settings().menuPosition=nil;minimap.SetAngle(225);minimap.SetHidden(false)
 elseif action==''then minimap.SetHidden(not settings().hidden)
 else notify('/azpcf minimap show | hide | reset')end
 return true
end
local events=CreateFrame('Frame');events:RegisterEvent('PLAYER_LOGIN');events:SetScript('OnEvent',function()minimap.Initialize()end)
if SlashCmdList then local previous=SlashCmdList.AZPCFOREVER;SlashCmdList.AZPCFOREVER=function(command)
 if minimap.Command(command)then return elseif previous then return previous(command)end
end end
end
-- END AZPC MINIMAP MENU

-- BEGIN AZPC USER SETTINGS
do
AZPCForeverSettings={}
local settings=AZPCForeverSettings
local defaults={tooltips='compact',ownership=true,reminders='popup'}
local choices={tooltips={compact=true,detailed=true,off=true},reminders={popup=true,notification=true,both=true}}
local panel,notice,refresh
local function combat()return type(InCombatLockdown)=='function' and InCombatLockdown()end
function settings.Get(key)
 local p=AZPCForeverDB and AZPCForeverDB.preferences
 local v;if type(p)=='table'then v=p[key]end
 if key=='ownership' then if type(v)=='boolean'then return v end
 elseif choices[key]and choices[key][v]then return v end
 return defaults[key]
end
function settings.Set(key,value)
 if key=='ownership' then if type(value)~='boolean'then return false end
 elseif not choices[key]or not choices[key][value]then return false end
 AZPCForeverDB=AZPCForeverDB or{};if type(AZPCForeverDB.preferences)~='table'then AZPCForeverDB.preferences={}end
 AZPCForeverDB.preferences[key]=value
 if key=='reminders' and value=='popup' and notice then notice:Hide()end
 if refresh then refresh()end;return true
end
local function frame(name,w,h,title)
 local f=CreateFrame('Frame',name,UIParent,BackdropTemplateMixin and 'BackdropTemplate' or nil)
 f:SetSize(w,h);f:SetPoint('CENTER');f:SetFrameStrata('DIALOG');f:SetClampedToScreen(true);f:EnableMouse(true);f:SetMovable(true);f:RegisterForDrag('LeftButton')
 f:SetScript('OnDragStart',function(self)if not combat()then self:StartMoving()end end);f:SetScript('OnDragStop',f.StopMovingOrSizing)
 if f.SetBackdrop then f:SetBackdrop({bgFile='Interface/DialogFrame/UI-DialogBox-Background',edgeFile='Interface/DialogFrame/UI-DialogBox-Border',tile=true,tileSize=32,edgeSize=24,insets={left=7,right=7,top=7,bottom=7}})end
 local label=f:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');label:SetPoint('TOPLEFT',24,-24);label:SetText('|cff54dbd1AZPC|r  |  '..title)
 local close=CreateFrame('Button',nil,f,'UIPanelCloseButton');close:SetPoint('TOPRIGHT',-3,-3)
 if type(UISpecialFrames)=='table'then UISpecialFrames[#UISpecialFrames+1]=name end
 return f
end
local function text(f,value,x,y,width,font)
 local t=f:CreateFontString(nil,'OVERLAY',font or 'GameFontHighlightSmall');t:SetPoint('TOPLEFT',x,y);t:SetWidth(width);t:SetJustifyH('LEFT');t:SetText(value);return t
end
local function button(f,title,x,y,width,fn)
 local b=CreateFrame('Button',nil,f,'UIPanelButtonTemplate');b:SetSize(width,28);b:SetPoint('TOPLEFT',x,y);b:SetText(title);b:SetScript('OnClick',fn);return b
end
function settings.Notify()
 if combat()or not UIParent then return false end
 if not notice then
  notice=frame('AZPCForeverReloadNotice',350,150,'Ready to sync')
  notice:ClearAllPoints();notice:SetPoint('TOP',UIParent,'TOP',0,-100)
  text(notice,'New auction data captured. Reload to save it for your watcher.',24,-55,300)
  button(notice,'Reload to Save',24,-102,170,function()if not combat()and type(ReloadUI)=='function'then ReloadUI()end end)
  button(notice,'Later',205,-102,115,function()notice:Hide()end)
 end
 notice:Show();return true
end
function settings.ResetPositions()
 if combat()then return false end
 for _,name in ipairs({'AZPCForeverSettingsWindow','AZPCForeverSyncWindow','AZPCForeverSetupWindow'})do
  local f=_G[name];if f then f:StopMovingOrSizing();f:ClearAllPoints();f:SetPoint('CENTER',UIParent,'CENTER',0,0)end
 end
 if notice then notice:StopMovingOrSizing();notice:ClearAllPoints();notice:SetPoint('TOP',UIParent,'TOP',0,-100)end
 if AZPCForeverMinimap then AZPCForeverMinimap.Command('minimap reset')end
 return true
end
function settings.Show()
 if combat()then if print then print('AZPC: Open settings after combat.')end;return false end
 if not UIParent then return false end
 if not panel then
  panel=frame('AZPCForeverSettingsWindow',580,410,'Settings')
  text(panel,'Shared across all characters on this WoW account/client.',24,-56,530)
  local controls={}
  local function options(key,title,rows,y)
   text(panel,title,24,y,530,'GameFontNormal')
   for i,row in ipairs(rows)do
    local value=row[2];local b=button(panel,row[1],24+(i-1)*177,y-25,165,function()settings.Set(key,value)end)
    controls[#controls+1]={button=b,key=key,value=value,label=row[1]}
   end
  end
  options('tooltips','ITEM TOOLTIPS',{{'Compact','compact'},{'Detailed','detailed'},{'Off','off'}},-90)
  text(panel,'Compact: useful values only. Hold Shift before hovering for details.',24,-150,530,'GameFontDisableSmall')
  local owned=CreateFrame('CheckButton',nil,panel,'UICheckButtonTemplate');owned:SetSize(26,26);owned:SetPoint('TOPLEFT',22,-174)
  text(panel,'Show saved ownership counts in AZPC tooltips',54,-181,490)
  owned:SetScript('OnClick',function(self)settings.Set('ownership',self:GetChecked()==true)end)
  options('reminders','RELOAD REMINDERS',{{'Popup','popup'},{'Small notification','notification'},{'Both','both'}},-225)
  text(panel,'Reminders save nothing automatically. You choose when to reload.',24,-285,530,'GameFontDisableSmall')
  button(panel,'Reset window positions',24,-335,245,function()settings.ResetPositions()end)
  button(panel,'Done',345,-335,210,function()panel:Hide()end)
  refresh=function()
   for _,r in ipairs(controls)do r.button:SetText((settings.Get(r.key)==r.value and '|cff54dbd1[x]|r 'or'')..r.label)end
   owned:SetChecked(settings.Get('ownership'))
  end
  panel:SetScript('OnShow',refresh)
 end
 panel:Show();refresh();return true
end
if SlashCmdList then
 local previous=SlashCmdList.AZPCFOREVER
 SlashCmdList.AZPCFOREVER=function(command)
  if (command or''):lower():match('^%s*settings%s*$')then return settings.Show()
  elseif previous then return previous(command)end
 end
end
end
-- END AZPC USER SETTINGS

-- AZPC Forever: nonintrusive onboarding for fresh CurseForge-only installs.
local function now() return (GetServerTime and GetServerTime()) or (time and time()) or 0 end
local function watcherSeen()
    local w=AZPCForeverWatcherStatus
    local checked=type(w)=='table' and tonumber(w.checkedAt)
    return checked and checked>0 and now()>=checked and (now()-checked)<3600
end
local function hasExistingHistory()
    local db=AZPCForeverDB
    return type(db)=='table' and ((type(db.trades)=='table' and next(db.trades)~=nil) or (type(db.snapshots)=='table' and next(db.snapshots)~=nil))
end
local function dismissed()
    return type(AZPCForeverDB)=='table' and AZPCForeverDB.setupPromptDismissed==true
end
local function markDismissed()
    if type(AZPCForeverDB)=='table' then AZPCForeverDB.setupPromptDismissed=true end
end
local window
local function createWindow()
    if window then return window end
    local f=CreateFrame('Frame','AZPCForeverSetupWindow',UIParent,'BackdropTemplate')
    if not f or not f.SetSize then return nil end
    f:SetSize(430,230)
    f:SetPoint('CENTER')
    f:SetFrameStrata('DIALOG')
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag('LeftButton')
    f:SetScript('OnDragStart',function(self) self:StartMoving() end)
    f:SetScript('OnDragStop',function(self) self:StopMovingOrSizing() end)
    f:SetBackdrop({bgFile='Interface\\DialogFrame\\UI-DialogBox-Background',edgeFile='Interface\\DialogFrame\\UI-DialogBox-Border',edgeSize=26,insets={left=8,right=8,top=8,bottom=8}})
    local title=f:CreateFontString(nil,'OVERLAY','GameFontNormalLarge')
    title:SetPoint('TOP',0,-25)
    title:SetText('Connect AZPC to Your Dashboard')
    local body=f:CreateFontString(nil,'OVERLAY','GameFontHighlight')
    body:SetPoint('TOPLEFT',30,-65)
    body:SetPoint('TOPRIGHT',-30,-65)
    body:SetJustifyH('LEFT')
    body:SetText('The AZPC Watcher has not checked in.\n\nInstall the AZPC Launcher and Watcher from azpc.market to enable dashboard syncing.')
    -- WoW addons cannot write to the system clipboard; select the URL for Ctrl+C.
    local url=CreateFrame('EditBox',nil,f,'InputBoxTemplate')
    url:SetSize(205,24)
    url:SetPoint('TOP',-58,-149)
    url:SetAutoFocus(false)
    url:SetText('https://azpc.market')
    url:SetCursorPosition(0)
    url:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
    local copy=CreateFrame('Button',nil,f,'UIPanelButtonTemplate')
    copy:SetSize(112,25)
    copy:SetPoint('LEFT',url,'RIGHT',12,0)
    copy:SetText('Copy Website')
    copy:SetScript('OnClick',function()
        url:SetText('https://azpc.market')
        url:SetFocus()
        url:HighlightText()
    end)
    local ok=CreateFrame('Button',nil,f,'UIPanelButtonTemplate')
    ok:SetSize(160,26)
    ok:SetPoint('BOTTOMLEFT',28,21)
    ok:SetText('Got it')
    ok:SetScript('OnClick',function() if not f.testMode then markDismissed() end f:Hide() end)
    local later=CreateFrame('Button',nil,f,'UIPanelButtonTemplate')
    later:SetSize(160,26)
    later:SetPoint('BOTTOMRIGHT',-28,21)
    later:SetText('Remind me later')
    later:SetScript('OnClick',function() f:Hide() end)
    f:Hide()
    window=f
    return f
end
local function show(force)
    force=force==true
    if InCombatLockdown and InCombatLockdown() then return end
    -- An existing trading history indicates a configured installation.
    -- Do not surprise established users after a launcher update resets the heartbeat.
    if not force and (watcherSeen() or dismissed() or hasExistingHistory()) then return end
    local f=createWindow()
    if not f then return end
    f.testMode=force
    f:Show()
end
local f=CreateFrame('Frame')
f:RegisterEvent('PLAYER_LOGIN')
f:SetScript('OnEvent',function()
    if C_Timer and C_Timer.After then C_Timer.After(12,function() show(false) end) else show(false) end
end)
AZPCForeverSetupHelp={Show=show,WatcherSeen=watcherSeen}
if SlashCmdList and SlashCmdList.AZPCFOREVER then
    local previous=SlashCmdList.AZPCFOREVER
    SlashCmdList.AZPCFOREVER=function(command)
        if (command or ''):lower()=='testsetup' then show(true) return end
        return previous(command)
    end
end

-- AZPC WATCHER STATUS BEGIN
AZPCForeverWatcherStatus = nil
-- AZPC WATCHER STATUS END
