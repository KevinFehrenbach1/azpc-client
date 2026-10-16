-- Pure capture tests: no cash/crafting mutation, no timers or protected actions.
local frames,messages={},{}
local originalCommandCalls=0
SlashCmdList={AZPCFOREVER=function()originalCommandCalls=originalCommandCalls+1 end}
function CreateFrame()
 local f={events={}};frames[#frames+1]=f
 function f:RegisterEvent(e)self.events[e]=true end
 function f:SetScript(_,fn)self.handler=fn end
 return f
end
local function emit(event,...)for _,f in ipairs(frames)do if f.events[event]then f.handler(f,event,...)end end end
function print(text)messages[#messages+1]=text end
local clock=1792130000
function GetServerTime()return clock end
function GetTime()return clock end
function UnitGUID()return 'Player-Wet' end
function UnitName()return 'Wet' end
function GetRealmName()return 'Classic Beta PvP 2' end
function UnitFactionGroup()return 'Horde' end
function GetCurrentRegion()return 110 end
NUM_BAG_SLOTS=0
local equipment,other,dust,essence=1,0,0,0
local scans=0
C_Container={
 GetContainerNumSlots=function()scans=scans+1;return 4 end,
 GetContainerItemInfo=function(_,slot)
  local rows={{12020,equipment},{10940,dust},{10938,essence},{12021,other}}
  local r=rows[slot];if r and r[2]>0 then return {itemID=r[1],stackCount=r[2]} end
 end,
}
ItemLocation={CreateFromBagAndSlot=function(self,bag,slot)assert(self==ItemLocation);return {bag=bag,slot=slot}end}
C_Item={
 GetItemGUID=function(location)if location.slot==1 then return 'Item-Test-Input' end;return 'Item-Test-'..location.slot end,
 GetItemCount=function(id)return ({[12020]=equipment,[10940]=dust,[10938]=essence,[12021]=other})[id] or 0 end,
}
local loot,source={},'Item-Test-Input'
function GetNumLootItems()return #loot end
function GetLootSlotLink(slot)return '|Hitem:'..loot[slot].id..'::::::::|h[Material]|h' end
function GetLootSlotInfo(slot)return nil,'Material',loot[slot].quantity end
function GetLootSourceInfo(slot)return source,loot[slot].quantity end
LOOT_ITEM_SELF='You receive loot: %s.'
LOOT_ITEM_SELF_MULTIPLE='You receive loot: %sx%d.'
local function receipt(id,q)return 'You receive loot: |Hitem:'..id..'::::::::|h[Material]|h'..(q>1 and 'x'..q or '')..'.' end
local trades,crafting={evidence='unchanged'},{evidence='unchanged'}
AZPCForeverDB={trades=trades,crafting=crafting}
AZPCForeverCrafting={ScheduleCosts=function()error('capture must not schedule accounting')end,RebuildCosts=function()error('capture must not replay accounting')end}
assert(loadfile('addons/forever/AZPCForever/AZPCForeverDisenchant.lua'))('AZPCForever')
emit('ADDON_LOADED','AZPCForever')
local events=AZPCForeverDB.disenchanting.events
emit('BAG_UPDATE_DELAYED');emit('LOOT_OPENED');emit('CHAT_MSG_LOOT',receipt(10940,2))
assert(#events==0 and scans==0,'ordinary loot and bags incur no scans and create no disenchants')
emit('UNIT_SPELLCAST_START','other','other',13262)
emit('UNIT_SPELLCAST_START','player','craft',2161)
assert(scans==0,'other units and spells are ignored')
emit('UNIT_SPELLCAST_SENT','player','target','de-1',13262)
local initialScans=scans
emit('UNIT_SPELLCAST_START','player','de-1',13262)
assert(scans==initialScans,'one before-cast scan despite sent/start events')
equipment=0
emit('UNIT_SPELLCAST_SUCCEEDED','player','de-1',13262)
assert(#events==1 and not events[1].complete,'spell success alone is unresolved')
loot={{id=10940,quantity=2},{id=10938,quantity=1}}
emit('LOOT_OPENED')
assert(events[1].inputConfirmed and events[1].input.itemId==12020,'input requires source GUID and one bag decrement')
assert(events[1].region==90,'beta region canonicalization matches existing capture')
emit('CHAT_MSG_LOOT',receipt(10940,2));emit('CHAT_MSG_LOOT',receipt(10938,1))
assert(not events[1].outputsConfirmed,'loot text without bags never confirms output')
dust=2;essence=1;emit('BAG_UPDATE_DELAYED')
assert(events[1].complete and events[1].outputs[1].quantity==1 and events[1].outputs[2].quantity==2,'multiple outputs confirmed by self receipts plus bag increases')
emit('UNIT_SPELLCAST_SUCCEEDED','player','de-1',13262);emit('LOOT_OPENED');emit('CHAT_MSG_LOOT',receipt(10940,2));emit('BAG_UPDATE_DELAYED')
assert(#events==1 and events[1].outputs[2].quantity==2,'repeat notifications do not duplicate successful cast or outputs')
assert(events[1].captureOnly and events[1].costBasis==nil and events[1].syncExport==nil,'capture creates no cost or upload records')
assert(AZPCForeverDB.trades==trades and AZPCForeverDB.crafting==crafting and trades.evidence=='unchanged' and crafting.evidence=='unchanged','existing accounting collections are untouched')
emit('LOOT_CLOSED')
-- Failed/interrupted casts never become completed records.
clock=clock+1;equipment=1;loot={}
emit('UNIT_SPELLCAST_START','player','failed',13262);emit('UNIT_SPELLCAST_FAILED','player','failed',13262)
emit('LOOT_OPENED');assert(#events==1)
emit('UNIT_SPELLCAST_START','player','interrupted',13262);emit('UNIT_SPELLCAST_INTERRUPTED','player','interrupted',13262)
assert(#events==1)
-- No GUID API: keep candidate evidence, never claim a known input.
local guidAPI=C_Item.GetItemGUID;C_Item.GetItemGUID=nil
emit('UNIT_SPELLCAST_START','player','no-guid',13262);equipment=0;emit('UNIT_SPELLCAST_SUCCEEDED','player','no-guid',13262)
loot={{id=10940,quantity=1}};emit('LOOT_OPENED');dust=3;emit('CHAT_MSG_LOOT',receipt(10940,1));emit('BAG_UPDATE_DELAYED')
assert(#events==2 and not events[2].inputConfirmed and events[2].inputCandidates[1].itemId==12020 and events[2].outputsConfirmed and not events[2].complete,'missing GUID keeps explicit unresolved input with confirmed outputs')
C_Item.GetItemGUID=guidAPI;emit('LOOT_CLOSED')
-- Reordered success after loot-open still reads the active window safely.
equipment=1;loot={};clock=clock+1
emit('UNIT_SPELLCAST_START','player','reordered',13262);equipment=0;loot={{id=10940,quantity=1}};emit('LOOT_OPENED');emit('UNIT_SPELLCAST_SUCCEEDED','player','reordered',13262)
emit('LOOT_CLOSED');dust=4;emit('CHAT_MSG_LOOT',receipt(10940,1));emit('BAG_UPDATE_DELAYED')
assert(events[3].complete,'loot-open before success and chat after close are supported')
-- New unrelated loot window cannot supply receipts to the closed disenchant.
equipment=1;loot={};clock=clock+1
emit('UNIT_SPELLCAST_START','player','unrelated',13262);equipment=0;emit('UNIT_SPELLCAST_SUCCEEDED','player','unrelated',13262)
loot={{id=10940,quantity=1}};emit('LOOT_OPENED');emit('LOOT_CLOSED');source='Creature-Other';emit('LOOT_OPENED');dust=5;emit('CHAT_MSG_LOOT',receipt(10940,1));emit('BAG_UPDATE_DELAYED')
assert(not events[4].outputsConfirmed,'another loot window cannot complete prior outputs')
source='Item-Test-Input'
-- Missing start evidence and expired sessions never become confirmed input.
loot={};emit('UNIT_SPELLCAST_SUCCEEDED','player','success-only',13262)
assert(#events==5 and not events[5].inputConfirmed)
clock=clock+121;loot={{id=10940,quantity=1}};emit('LOOT_OPENED');emit('CHAT_MSG_LOOT',receipt(10940,1));emit('BAG_UPDATE_DELAYED')
assert(#events[5].outputs==0,'expired sessions do not absorb later loot')
SlashCmdList.AZPCFOREVER('disenchant');assert(originalCommandCalls==0 and messages[#messages]:find('unresolved',1,true),'status exposes capture results')
SlashCmdList.AZPCFOREVER('materials');assert(originalCommandCalls==1,'existing slash commands are preserved')
emit('PLAYER_LOGOUT')
-- Reloaded module uses durable cast IDs to suppress duplicate success.
assert(loadfile('addons/forever/AZPCForever/AZPCForeverDisenchant.lua'))('AZPCForever')
emit('UNIT_SPELLCAST_SUCCEEDED','player','de-1',13262);assert(#events==5,'saved cast identity survives reload')
io.write('PASS disenchant capture: source GUID + consumed item, multiple self-loot/bag outputs, duplicates/reload, failures, missing APIs, event ordering, expiry, isolation and command compatibility\n')
