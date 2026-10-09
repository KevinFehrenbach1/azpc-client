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
emit('MAIL_SEND_INFO_UPDATE');hooks.SendMail('Lu Skunt','cloth');clock=clock+1;emit('MAIL_SEND_SUCCESS');assert(#AZPCForeverDB.crafting.materialEvents==2);assert(AZPCForeverDB.crafting.materialEvents[2].kind=='transfer_out')
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

-- Actual bank events use live containers; cached addon totals never enter costs.
AZPCForeverDB={trades={},crafting={recipes={},crafts={},seen={},materialEvents={}}};emit('ADDON_LOADED','AZPCForever')
char='Wet';clock=clock+100;local bagLeather,bankLeather=2,20
NUM_BAG_SLOTS=4;NUM_BANKBAGSLOTS=7
C_Container={GetContainerNumSlots=function(bag)if bag==0 or bag==-1 then return 1 else return 0 end end,GetContainerItemInfo=function(bag,slot)local n=bag==0 and bagLeather or bag==-1 and bankLeather or 0;if n>0 then return {itemID=2318,stackCount=n,hyperlink='item:2318'}end end}
C_Item.GetItemInfo=function(id)return id==2318 and 'Light Leather' or 'Item'end
C_Item.GetItemCount=function(id,includeBank)if id==2318 then return bagLeather+(includeBank and bankLeather or 0)end;return 0 end
Bagnon={total=35};trade(2318,21,97,clock*1000-1000,'Wet')
emit('BAG_UPDATE_DELAYED');assert(#AZPCForeverDB.crafting.materialEvents==0,'closed bank is not authoritative')
emit('BANKFRAME_OPENED');local rows=AZPCForeverDB.crafting.materialEvents;assert(#rows==1 and rows[1].bagQuantity==2 and rows[1].bankQuantity==20 and rows[1].ownedQuantity==22,'bags and live bank counted separately without Bagnon cached 13')
local state=AZPCForeverCrafting.RebuildCosts();local p=state.positions[1];assert(p.quantity==22 and p.recordedCopper==97 and not p.costComplete and p.unknownQuantity==1,'surplus adds unknown acquisition without inventing free cost')
local raw=rows[1].syncExport;assert(raw:find('inventory_observation',1,true),'bank observations use durable material exports')
emit('BAG_UPDATE_DELAYED');assert(#rows==1,'unchanged bank observations do not duplicate stock')
clock=clock+1;bagLeather=3;bankLeather=19;emit('BAG_UPDATE_DELAYED');state=AZPCForeverCrafting.RebuildCosts();assert(state.positions[1].quantity==22 and state.positions[1].recordedCopper==97,'bank withdrawal conserves quantity and copper')
emit('BANKFRAME_CLOSED');bankLeather=100;clock=clock+1;emit('BAG_UPDATE_DELAYED');assert(#rows==2,'closed bank never interprets stale counts as gains')
bankLeather=18;emit('BANKFRAME_OPENED');state=AZPCForeverCrafting.RebuildCosts();p=state.positions[1];assert(p.quantity==22 and p.recordedCopper==97 and p.inventoryMismatch.observed==21,'deficits flag mismatch without deleting paid stock')
emit('BANKFRAME_CLOSED');clock=clock+1
C_Container.GetContainerItemInfo=function()return {hyperlink='item:2318'}end
local n=#rows;emit('BANKFRAME_OPENED');assert(#rows==n,'unloaded bank items cannot masquerade as zero stock')
print('PASS bank observations: live bags/bank, closed-cache exclusion, surplus unknowns, withdrawals, replay, deficits and incomplete data')

-- Modern character-bank tabs exclude the account-wide bank entirely.
emit('BANKFRAME_CLOSED');clock=clock+1;bagLeather=2;bankLeather=20
Enum={BankType={Character=2,Account=1}}
local canView=false;C_Bank={CanViewBank=function(kind)assert(kind==2);return canView end,FetchPurchasedBankTabIDs=function(kind)assert(kind==2,'only character bank queried');return {13}end}
C_Container.GetContainerNumSlots=function(bag)if bag==0 or bag==13 or bag==26 then return 1 else return 0 end end
C_Container.GetContainerItemInfo=function(bag)local q=bag==0 and bagLeather or bag==13 and bankLeather or bag==26 and 99 or 0;if q>0 then return {itemID=2318,stackCount=q,hyperlink='item:2318'}end end
local beforeModern=#rows;emit('BANKFRAME_OPENED');assert(#rows==beforeModern,'account-only access cannot capture closed character bank')
canView=true;emit('BAG_UPDATE_DELAYED');assert(rows[#rows].ownedQuantity==22 and rows[#rows].bankQuantity==20,'modern character tab capture excludes account bank 99')
print('PASS modern bank tabs and account-bank isolation')
