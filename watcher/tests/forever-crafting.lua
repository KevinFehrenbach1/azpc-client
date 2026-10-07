SlashCmdList={}
local frames,hooks={},{}
local now=1
function GetTime() return now end
function GetServerTime() return 1791403200 end
function GetRealmName() return 'Classic Beta PvP 2' end
function UnitName() return 'Lu' end
function UnitGUID() return 'Player-Lu' end
function UnitFactionGroup() return 'Horde' end
function GetCurrentRegion() return 90 end
function CreateFrame()
    local f={events={}};frames[#frames+1]=f
    function f:RegisterEvent(e) self.events[e]=true end
    function f:SetScript(_,fn) self.handler=fn end
    return f
end
local function emit(event,...)
    for _,f in ipairs(frames) do if f.events[event] then f.handler(f,event,...) end end
end
C_Timer={After=function(_,fn)fn()end}
function hooksecurefunc(_,name,fn) hooks[name]=fn end
local function schema(id)
    return {recipeID=id,outputItemID=id==100 and 2996 or 4496,name='Bolt of Linen Cloth',quantityMin=1,quantityMax=1,
        reagentSlotSchematics={{dataSlotIndex=1,required=true,quantityRequired=2,reagents={{itemID=2589}},variableQuantities={}}}}
end
local linked=false
C_TradeSkillUI={
    GetAllRecipeIDs=function()return {100,200,300}end,
    GetRecipeInfo=function(id)if id==100 or id==200 then return {recipeID=id,learned=true,name=id==100 and 'Bolt of Linen Cloth' or 'Bag'} end end,
    GetRecipeSchematic=schema,
    GetBaseProfessionInfo=function()return {professionName='Tailoring'}end,
    IsTradeSkillLinked=function()return linked end,
    CraftRecipe=function()end,
}
assert(loadfile('addons/forever/AZPCForever/AZPCForever.lua'))('AZPCForever')
emit('ADDON_LOADED','AZPCForever');emit('TRADE_SKILL_SHOW')
local db=AZPCForeverDB.crafting
local n=0;for _ in pairs(db.recipes)do n=n+1 end;assert(n==2,'only learned recipes are saved')
local r=db.recipes['Player-Lu:90:Classic Beta PvP 2:100']
assert(r.outputItemId==2996 and r.reagents[1].itemId==2589 and r.reagents[1].quantity==2)
assert(r.materialsKnown and r.character=='Lu' and r.region==90)
for i=1,3 do emit('TRADE_SKILL_LIST_UPDATE')end
n=0;for _ in pairs(db.recipes)do n=n+1 end;assert(n==2,'recipe updates do not duplicate catalog rows')
local function start(guid,id)
    hooks.CraftRecipe(id,1,{{reagent={itemID=2589},quantity=2}},nil,nil)
    emit('UNIT_SPELLCAST_SENT','player','',guid,id);emit('UNIT_SPELLCAST_START','player',guid,id)
end
local function success(guid,id)emit('UNIT_SPELLCAST_SUCCEEDED','player',guid,id)end
local function output(operation,q,item,extra)
    local d={operationID=operation,itemID=item or 2996,quantity=q or 1,itemGUID='Item-stack'}
    for k,v in pairs(extra or {})do d[k]=v end
    emit('TRADE_SKILL_ITEM_CRAFTED_RESULT',d)
end
start('cast-fail',100);emit('UNIT_SPELLCAST_FAILED','player','cast-fail',100);output(1)
assert(#db.crafts==0,'failed attempts never become crafts')
start('cast-interrupt',100);emit('UNIT_SPELLCAST_INTERRUPTED','player','cast-interrupt',100);output(2)
assert(#db.crafts==0,'interrupted attempts never become crafts')
start('cast-a',100);success('cast-a',100);assert(#db.crafts==0,'spell success alone has no actual output quantity')
output(3,2);assert(#db.crafts==1,'completed craft needs both confirmations')
local c=db.crafts[1]
assert(c.quantity==2 and c.itemId==2996 and c.castGuid=='cast-a' and c.eventId=='Player-Lu:craft:cast-a')
assert(c.materialsKnown and c.consumedReagents[1].quantity==2,'multicraft quantity does not multiply per-cast material usage')
output(3,2);success('cast-a',100);assert(#db.crafts==1,'duplicate result and success notifications are idempotent')
now=now+2;start('cast-b',100);output(4,1);assert(#db.crafts==1,'early output waits for player success');success('cast-b',100);assert(#db.crafts==2)
now=now+2;start('cast-c',100);success('cast-c',100);output(5,1);assert(#db.crafts==3,'same stack GUID does not merge separate batch casts')
now=now+2;start('cast-return',100);success('cast-return',100);output(6,1,nil,{resourcesReturned={{reagent={itemID=2589},quantity=1}}})
assert(db.crafts[4].consumedReagents[1].quantity==1,'returned materials reduce evidenced consumption')
now=now+2;start('cast-other',100);success('cast-other',100);output(7,1,4496);output(8,1,nil,{firstCraftReward=true});output(9,1,nil,{bonusCraft=true});assert(#db.crafts==4,'unrelated results and bonus rewards are not normal crafts')
now=now+10;output(10);assert(#db.crafts==4,'late unmatched results are ignored')
-- Result notifications without an operation ID still require player success.
now=now+1;start('cast-no-operation',100);success('cast-no-operation',100);output(0);assert(#db.crafts==5)
output(0);assert(#db.crafts==5,'duplicate zero-operation result has no second successful cast')
-- Optional/alternative materials are preserved as recipe evidence but never guessed as consumed.
C_TradeSkillUI.GetRecipeSchematic=function(id)local s=schema(id);s.reagentSlotSchematics[1].reagents={{itemID=2589},{itemID=2592}};return s end
emit('TRADE_SKILL_LIST_UPDATE');assert(not db.recipes['Player-Lu:90:Classic Beta PvP 2:100'].materialsKnown)
C_TradeSkillUI.GetRecipeSchematic=schema
-- Catalog changes do not rewrite material requirements on previous craft records.
C_TradeSkillUI.GetRecipeSchematic=function(id)local s=schema(id);s.reagentSlotSchematics[1].quantityRequired=3;return s end
emit('TRADE_SKILL_LIST_UPDATE');assert(db.crafts[1].recipeReagents[1].quantity==2)
now=now+1;start('cast-unresolved',100);success('cast-unresolved',100);output(11)
assert(#db.crafts==6 and not db.crafts[6].materialsKnown and not db.crafts[6].consumedReagents,'selected reagent mismatch stays unresolved')
-- Reload restores the saved ledger but creates no pending craft and no duplicate.
frames={};hooks={};assert(loadfile('addons/forever/AZPCForever/AZPCForever.lua'))('AZPCForever');emit('ADDON_LOADED','AZPCForever')
output(11);assert(#db.crafts==6)
success('cast-unresolved',100);output(12);assert(#db.crafts==6,'persisted cast identity prevents replay across reload')
linked=true;local before=0;for _ in pairs(db.recipes)do before=before+1 end;emit('TRADE_SKILL_SHOW');linked=false
local after=0;for _ in pairs(db.recipes)do after=after+1 end;assert(before==after,'linked professions are not the player recipe catalog')
C_TradeSkillUI=nil;SlashCmdList.AZPCFOREVER('crafts');emit('TRADE_SKILL_SHOW');success('other-spell',999);assert(#db.crafts==6,'unsupported APIs and unrelated spells do not break capture')
assert(#AZPCForeverDB.trades==0,'craft evidence never adds free acquisitions or changes the trading ledger')
print('PASS: learned recipes, per-cast requirements, actual output quantities, batch identity, success/result ordering, cancellations, replay/reload dedupe, material returns, unknown selections and API guards')
