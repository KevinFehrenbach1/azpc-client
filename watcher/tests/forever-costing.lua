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
reset()
local function purchase(q,c,stamp)
 local fingerprint='Player-test:Realm:90:buyer:2319:'..q..':'..c..':29899816:Senpai%20Luck:Horde%20Auction%20House:Auction%20won%3A%20Medium%20Leather%20%2829%29:7:1'
 fingerprint=fingerprint:gsub('([^%w%-_%.])',function(x)return string.format('%%%02X',string.byte(x))end)
 AZPCForeverDB.trades[#AZPCForeverDB.trades+1]={tradeExport=table.concat({'AZPCFTRADE','1',fingerprint,'buy',2319,'Medium%20Leather',q,c,stamp,'Realm','horde',90,'Lu'},'|')}
end
purchase(20,29,1791396972);purchase(29,29,1791396973)
local repaired=position(2319);assert(repaired.quantity==20 and repaired.totalCopper==29,'old quantity/price duplicate cannot inflate materials or copper')
reset();purchase(29,29,1791396973);assert(position(2319).quantity==29,'unpaired record stays unchanged')
print('PASS: legacy buyer quantity/price conflicts are repaired conservatively')

reset();trade('buy',2996,43,118,1000)
AZPCForeverDB.crafting.materialEvents={{eventId='repair',kind='reconcile',itemId=2996,quantity=11,targetQuantity=11,totalCopper=14,observedAt=2000,region=90,realm='Realm',faction='horde',character='Lu',name='Bolts',confirmation='inventory_and_cost_reconciled'}}
assert(position(2996).quantity==11 and position(2996).totalCopper==14,'audited correction supersedes old pool without changing raw purchases')
local repairedBag=craft(253664,1,3000,{mat(2996,6)});rebuild()
assert(repairedBag.costBasis.totalCopper==7 and position(2996).totalCopper==7,'future crafts consume corrected weighted copper exactly')
assert(#AZPCForeverDB.trades==1,'repair retains original transaction')
print('PASS: audited reconciliation and subsequent craft copper conservation')

local function bankObservation(id,bags,bank,at)
 local d=AZPCForeverDB.crafting;d.materialEvents=d.materialEvents or {}
 d.materialEvents[#d.materialEvents+1]={eventId='bank:'..at,kind='inventory_observation',itemId=id,quantity=math.max(1,bags+bank),bagQuantity=bags,bankQuantity=bank,ownedQuantity=bags+bank,reservedQuantity=0,observedAt=at,character='Lu',realm='Realm',region=90,faction='horde',confirmation='bags_and_character_bank_observed'}
end
reset();bankObservation(2318,0,20,1000);trade('buy',2318,24,1008,2000);trade('buy',2320,15,510,2000)
local first=craft(2309,1,3000,{mat(2318,8),mat(2320,5)});local second=craft(2309,1,4000,{mat(2318,8),mat(2320,5)});local third=craft(2309,1,5000,{mat(2318,8),mat(2320,5)})
rebuild();assert(first.costBasis.complete and first.costBasis.totalCopper==506 and second.costBasis.totalCopper==506 and third.costBasis.totalCopper==506,'unknown bank stock cannot dilute known bag purchases')
local leather=position(2318);assert(leather.quantity==20 and leather.bankLedgerQuantity==20 and leather.bagLedgerQuantity==0 and not leather.costComplete,'untouched bank inventory stays unresolved')
reset();trade('buy',1,10,101,1000);bankObservation(1,2,8,2000);bankObservation(1,5,5,3000)
a=craft(2,1,4000,{mat(1,5)});rebuild();assert(a.costBasis.complete and a.costBasis.totalCopper==51 and position(1).recordedCopper==50,'deposit and withdrawal preserve exact copper')
reset();bankObservation(1,0,10,1000);trade('buy',1,2,40,2000);bankObservation(1,4,8,3000);a=craft(2,1,4000,{mat(1,4)});rebuild();assert(not a.costBasis.complete and a.costBasis.recordedCopper==40,'unknown bank withdrawal remains unknown in bags')
reset();bankObservation(2318,4,20,1000);trade('buy',2318,20,840,2000);trade('buy',2320,15,510,2000)
a=craft(2309,1,3000,{mat(2318,8),mat(2320,5)});rebuild();assert(not a.costBasis.complete and a.costBasis.inputs[1].availableQuantity==24 and a.costBasis.recordedCopper==450,'four unknown bag leather remains unresolved without averaging twenty bank leather into the craft')
print('PASS: bag/bank cost isolation, exact location transfers, unknown withdrawals and Wet boots mixed-bag regression')
reset();bankObservation(2318,3,20,1000);trade('buy',2318,20,840,2000);trade('buy',2320,15,510,2000);trade('inventory_snapshot',2318,24,0,2500)
a=craft(2309,1,3000,{mat(2318,8),mat(2320,5)});b=craft(2309,1,4000,{mat(2318,8),mat(2320,5)});local c=craft(2309,1,5000,{mat(2318,8),mat(2320,5)})
rebuild();assert(a.costBasis.inputs[1].availableQuantity==24 and a.costBasis.recordedCopper==450 and not a.costBasis.complete,'fresh bag proof adds the fourth unresolved bag leather')
assert(b.costBasis.recordedCopper==450 and c.costBasis.recordedCopper==450 and position(2318).quantity==20 and position(2318).bagLedgerQuantity==0,'stale pre-craft snapshot cannot create stock again on later crafts')
print('PASS: Wet exact bank-three, purchase-twenty, bag-twenty-four sequence and no repeated snapshot stock')
