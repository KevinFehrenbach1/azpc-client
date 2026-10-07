SlashCmdList={}
function CreateFrame()return {RegisterEvent=function()end,SetScript=function()end}end
C_Timer={After=function()end}
function GetServerTime()return 1791403200 end
function GetRealmName()return 'Realm' end
function UnitName()return 'Lu' end
function UnitFactionGroup()return 'Horde' end
function GetCurrentRegion()return 90 end
assert(loadfile('addons/forever/AZPCForever/AZPCForever.lua'))('AZPCForever')
local function reset()AZPCForeverDB={trades={},crafting={recipes={},crafts={},seen={}}}end
local function trade(kind,id,q,c,at,char)
 local rows=AZPCForeverDB.trades
 local f={'AZPCFTRADE','2',tostring(#rows+1),kind,tostring(id),'Item',tostring(q),tostring(c),tostring(at),'Realm','horde','90',char or 'Lu','','','','','','','',''}
 rows[#rows+1]={tradeExport=table.concat(f,'|')}
 return rows[#rows]
end
local function craft(id,q,at,mats,char)
 local rows=AZPCForeverDB.crafting.crafts
 local r={eventId='craft:'..(#rows+1),itemId=id,quantity=q,observedAt=at,region=90,realm='Realm',faction='horde',character=char or 'Lu',name='Craft',materialsKnown=true,consumedReagents=mats}
 rows[#rows+1]=r;return r
end
local function mat(id,q)return {itemId=id,quantity=q}end
local function rebuild()local state,err=AZPCForeverCrafting.RebuildCosts();assert(state,err);return state end
local function position(id)local state=rebuild();for _,p in ipairs(state.positions)do if p.itemId==id then return p end end end
reset();trade('buy',1,10,100,1000);trade('buy',1,10,300,2000)
local a=craft(2,1,3000,{mat(1,2)});local b=craft(2,1,4000,{mat(1,2)})
trade('buy',3,1,5,4500);local bag=craft(4,1,5000,{mat(2,2),mat(3,1)})
rebuild();assert(a.costBasis.totalCopper==40 and b.costBasis.totalCopper==40 and bag.costBasis.totalCopper==85)
assert(position(1).totalCopper==320 and position(4).totalCopper==85,'cost conserved through chained crafts')
local before=#AZPCForeverDB.trades;rebuild();assert(bag.costBasis.totalCopper==85 and #AZPCForeverDB.trades==before,'replay is idempotent and never creates trades')
trade('buy',1,5,5000,6000);rebuild();assert(a.costBasis.totalCopper==40,'future purchases do not rewrite history')
trade('sell',4,1,200,7000);assert(position(4)==nil,'selling output removes its basis')
reset();trade('buy',1,10,100,1000);trade('buy',1,10,300,2000);trade('sell',1,10,500,2500)
a=craft(2,1,3000,{mat(1,2)});rebuild();assert(a.costBasis.totalCopper==60,'ordinary sales consume original purchase FIFO')
reset();trade('buy',1,2,40,1000);a=craft(2,1,2000,{mat(1,2),mat(3,1)});rebuild()
assert(not a.costBasis.complete and a.costBasis.totalCopper==nil and a.costBasis.recordedCopper==40,'missing material is unknown, never free')
b=craft(4,1,3000,{mat(2,1)});rebuild();assert(not b.costBasis.complete and b.costBasis.recordedCopper==40,'unknown upstream basis carries through')
trade('buy',3,1,5,1500);rebuild();assert(a.costBasis.totalCopper==45 and b.costBasis.totalCopper==45,'earlier evidence can resolve incomplete costs')
reset();a=craft(2,1,2000,{mat(1,2)});trade('buy',1,2,40,3000);rebuild();assert(not a.costBasis.complete,'later purchases cannot price older missing materials')
reset();trade('buy',1,2,40,1000,'Other');a=craft(2,1,2000,{mat(1,2)});rebuild();assert(not a.costBasis.complete,'character pools are separate')
reset();local row=trade('buy',1,2,41,1000);AZPCForeverDB.trades[#AZPCForeverDB.trades+1]=row
a=craft(2,2,2000,{mat(1,2)});b=craft(4,1,3000,{mat(2,1)});rebuild()
assert(a.costBasis.totalCopper==41 and b.costBasis.totalCopper==20 and position(2).totalCopper==21,'multicraft splits copper exactly and duplicates do not add stock')
reset();trade('buy',1,2,41,1000);a=craft(2,1,2000,{mat(1,2)});b=craft(2,1,3000,{mat(1,2)});rebuild();assert(not b.costBasis.complete,'consumed materials cannot be reused')
reset();trade('buy',1,999999,999999999999,1000);a=craft(2,1,2000,{mat(1,333333)});rebuild();assert(a.costBasis.totalCopper==333333333333 and position(1).totalCopper==666666666666,'large integer cost transfer is exact')
reset();trade('buy',1,2,40,1000);a=craft(2,1,2000,{mat(1,2)});rebuild();trade('buy',1,2,80,1500);rebuild()
assert(a.costConflict and a.costBasis.totalCopper==40 and not position(2).costComplete,'historical conflict preserves saved value and flags output unknown')
reset();trade('buy',1,2,40,1000);a=craft(2,1,2000,{mat(1,2)});trade('buy',3,1,1000000000000,3000);trade('buy',3,1,1,4000)
local state,err=AZPCForeverCrafting.RebuildCosts();assert(not state and err and a.costBasis==nil,'overflow fails without committing partial snapshots')
print('PASS: Forever weighted material costs, chains, missing sources, isolation, FIFO sales, replay, frozen history, exact copper and atomic failure')
