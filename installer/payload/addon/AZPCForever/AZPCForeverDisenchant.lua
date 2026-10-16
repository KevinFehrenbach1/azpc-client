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
