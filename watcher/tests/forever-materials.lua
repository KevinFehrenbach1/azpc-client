SlashCmdList={};local frames,hooks={},{}
function CreateFrame()local f={events={}};frames[#frames+1]=f;function f:RegisterEvent(e)self.events[e]=true end;function f:SetScript(_,fn)self.handler=fn end;return f end
local function emit(e,...)for _,f in ipairs(frames)do if f.events[e]then f.handler(f,e,...)end end end
C_Timer={After=function(_,fn)fn()end}
function hooksecurefunc(a,b,c)if c then hooks[b]=c else hooks[a]=b end end
local char='Wet';local clock=1791410000;local counts={[2589]=10};local attachment=true
function GetServerTime()return clock end
function UnitName()return char end
function UnitGUID()return 'Player-'..char end
function GetRealmName()return 'Realm' end
function UnitFactionGroup()return 'Horde' end
function GetCurrentRegion()return 90 end
C_Item={GetItemCount=function(id)return counts[id]or 0 end}
function GetSendMailItem(slot)if slot==1 and attachment then return 'Linen Cloth',2589,nil,10 end end
function GetInboxNumItems()return 1 end
function GetInboxInvoiceInfo()return nil end
function GetInboxHeaderInfo()return nil,nil,'Wet','cloth',0,0,30 end
function GetInboxItem(_,slot)if slot==1 and attachment then return 'Linen Cloth',2589,nil,10 end end
assert(loadfile('addons/forever/AZPCForever/AZPCForever.lua'))('AZPCForever');emit('ADDON_LOADED','AZPCForever')
AZPCForeverMaterialCommands={{commandId='material-free:test',itemId=2589,quantity=10,region=90,faction='horde',realm='Realm',character='Wet',name='Linen Cloth',source='farmed'}}
emit('PLAYER_LOGIN');assert(#AZPCForeverDB.crafting.materialEvents==1);emit('PLAYER_LOGIN');assert(#AZPCForeverDB.crafting.materialEvents==1,'command replay is idempotent')
emit('MAIL_SEND_INFO_UPDATE');hooks.SendMail('Lu','cloth');clock=clock+1;emit('MAIL_SEND_SUCCESS');assert(#AZPCForeverDB.crafting.materialEvents==2);assert(AZPCForeverDB.crafting.materialEvents[2].kind=='transfer_out')
char='Lu';counts[2589]=0;clock=clock+1;emit('MAIL_SHOW');hooks.TakeInboxItem(1,1);assert(#AZPCForeverDB.crafting.materialEvents==2,'take intent alone cannot record a receipt')
counts[2589]=10;attachment=false;emit('BAG_UPDATE_DELAYED');assert(#AZPCForeverDB.crafting.materialEvents==3);assert(AZPCForeverDB.crafting.materialEvents[3].kind=='transfer_in')
emit('MAIL_INBOX_UPDATE');emit('BAG_UPDATE_DELAYED');assert(#AZPCForeverDB.crafting.materialEvents==3,'mail receipt records once after bag confirmation')
local state=AZPCForeverCrafting.RebuildCosts();assert(state);assert(#state.positions==1 and state.positions[1].character=='Lu' and state.positions[1].quantity==10 and state.positions[1].totalCopper==0,'free cloth moves between characters exactly once')
local function trade(id,q,c,at,who)AZPCForeverDB.trades[#AZPCForeverDB.trades+1]={tradeExport=table.concat({'AZPCFTRADE','2',tostring(at),'buy',id,'Linen%20Cloth',q,c,at,'Realm','horde',90,who,'','','','','','','',''},'|')}end
clock=clock+1;trade(2589,20,100000,clock*1000,'Lu');clock=clock+1
local craft={eventId='mixed',recipeId=1,recipeKey='r',itemId=2996,quantity=1,observedAt=clock*1000,region=90,realm='Realm',faction='horde',character='Lu',name='Bolt',materialsKnown=true,consumedReagents={{itemId=2589,quantity=6}},recipeReagents={{itemId=2589,quantity=6}},resourcesReturned={},confirmation='player_spell_success_and_item_result'}
AZPCForeverDB.crafting.crafts[#AZPCForeverDB.crafting.crafts+1]=craft;state=AZPCForeverCrafting.RebuildCosts();assert(state and craft.costBasis.totalCopper==20000,'paid and free transferred cloth average to 2g for six units')
assert(AZPCForeverDB.crafting.materialEvents[1].syncExport:find('AZPCFCRAFT|1|',1,true),'material events use existing durable upload exports')
local before=#AZPCForeverDB.crafting.materialEvents;AZPCForeverMaterialCommands={{commandId='material-free:bad',itemId=2589,quantity=100,region=90,faction='horde',realm='Realm',character='Lu',name='Cloth',source='farmed'}};emit('PLAYER_LOGIN');assert(#AZPCForeverDB.crafting.materialEvents==before+1 and AZPCForeverDB.crafting.materialEvents[before+1].kind=='request_rejected','invalid source request is durably rejected without adding stock');before=before+1
attachment=true;emit('MAIL_SEND_INFO_UPDATE');hooks.SendMail('Wet','fail');emit('MAIL_FAILED');emit('MAIL_SEND_SUCCESS');assert(#AZPCForeverDB.crafting.materialEvents==before,'failed send creates no transfer')
print('PASS: real material commands, explicit free stock, confirmed send/receive, failed mail, replay, current quantity guards, cross-character cost transfer and mixed averages')

counts[2589]=100000;emit('PLAYER_LOGIN');assert(#AZPCForeverDB.crafting.materialEvents==before,'rejected requests never apply automatically to later acquisitions')
-- Normal loot APIs cover corpses and gathering objects, including skinning.
LOOT_ITEM_SELF='You receive loot: %s.';LOOT_ITEM_SELF_MULTIPLE='You receive loot: %sx%d.'
local lootId,lootQuantity,lootGuid=2318,3,'Creature-0-1-2-3-4-5'
function GetNumLootItems()return 1 end
function GetLootSlotLink()return '|cffffffff|Hitem:'..lootId..'::::::::|h[Light Leather]|h|r' end
function GetLootSlotInfo()return nil,'Light Leather',lootQuantity end
function GetLootSourceInfo()return lootGuid,lootQuantity end
local function lootChat()return 'You receive loot: '..GetLootSlotLink()..'x'..lootQuantity..'.'end
local n=#AZPCForeverDB.crafting.materialEvents;counts[lootId]=0
emit('LOOT_OPENED');emit('LOOT_SLOT_CLEARED',1);emit('CHAT_MSG_LOOT',lootChat());assert(#AZPCForeverDB.crafting.materialEvents==n,'loot evidence without bags does not add stock')
counts[lootId]=3;emit('BAG_UPDATE_DELAYED');assert(#AZPCForeverDB.crafting.materialEvents==n+1,'skinning leather is automatically farmed');local e=AZPCForeverDB.crafting.materialEvents[n+1];assert(e.source=='farmed' and e.quantity==3 and e.untrackedQuantity==3)
emit('BAG_UPDATE_DELAYED');emit('LOOT_SLOT_CLEARED',1);assert(#AZPCForeverDB.crafting.materialEvents==n+1,'repeated notifications do not duplicate loot')
n=n+1;lootGuid='GameObject-0-1-2-3-4-5';emit('LOOT_OPENED');emit('LOOT_SLOT_CLEARED',1);counts[lootId]=6;emit('CHAT_MSG_LOOT',lootChat());assert(#AZPCForeverDB.crafting.materialEvents==n+1,'gathering objects also record free gains');n=n+1
emit('LOOT_OPENED');emit('LOOT_SLOT_CLEARED',1);counts[lootId]=9;emit('BAG_UPDATE_DELAYED');assert(#AZPCForeverDB.crafting.materialEvents==n,'another player clearing a slot is insufficient')
lootGuid='Item-0-1-2-3';emit('LOOT_OPENED');emit('LOOT_SLOT_CLEARED',1);counts[lootId]=12;emit('CHAT_MSG_LOOT',lootChat());emit('BAG_UPDATE_DELAYED');assert(#AZPCForeverDB.crafting.materialEvents==n,'processing or opening an item cannot erase its paid basis')
print('PASS: automatic corpse/skinning and gathering loot, self receipt plus bags, duplicate protection and exclusion of item-container sources')
