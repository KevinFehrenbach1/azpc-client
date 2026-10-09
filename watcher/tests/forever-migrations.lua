SlashCmdList={};local frames={}
function CreateFrame()local f={events={}};function f:RegisterEvent(e)self.events[e]=true end;function f:SetScript(_,h)self.handler=h end;frames[#frames+1]=f;return f end
C_Timer={After=function()end};function GetServerTime()return 1791449000 end
function GetRealmName()return 'Classic Beta PvP 2'end;function UnitName()return 'Lu'end;function UnitGUID()return 'Player-Lu'end;function UnitFactionGroup()return 'Horde'end;function GetCurrentRegion()return 90 end
assert(loadfile('addons/forever/AZPCForever/AZPCForever.lua'))('AZPCForever')
local function emit()for _,f in ipairs(frames)do if f.events.ADDON_LOADED then f.handler(f,'ADDON_LOADED','AZPCForever')end end end
local function fixture()
 local rows={};local function row(kind,id,q,c,at)rows[#rows+1]={tradeExport=table.concat({'AZPCFTRADE','2','fixture'..#rows,kind,id,'Item',q,c,at,'Classic%20Beta%20PvP%202','horde',90,'Lu','','','','','','','',''},'|')}end
 local times={1791444821000,1791444824000,1791444827000,1791444830000,1791444834000,1791444836000,1791444840000,1791444843000}
 for i,t in ipairs(times)do row('inventory_snapshot',2996,i,0,t);row('inventory_snapshot',2589,16-2*i,0,t+1)end
 row('buy',2589,8,8,1791444677000);row('buy',2589,2,2,1791445396000);row('buy',2589,4,4,1791447230000)
 row('inventory_snapshot',2996,11,0,1791447247000);row('inventory_snapshot',2589,0,0,1791447247001)
 return {trades=rows,crafting={recipes={},crafts={},seen={},materialEvents={},costing={original=true}}}
end
AZPCForeverDB=fixture();local raw=AZPCForeverDB.trades;emit();local d=AZPCForeverDB.crafting
assert(#d.materialEvents==2 and raw==AZPCForeverDB.trades,'migration appends both checkpoints and preserves original receipts')
assert(d.migrations['linen-ledger-20261008'].previousCosting.original,'previous pool summary retained')
local p=d.costing.positions[1];assert(p.itemId==2996 and p.quantity==11 and p.totalCopper==14,'migration corrects both quantities and verified copper')
assert(d.materialEvents[1].syncExport and d.materialEvents[2].syncExport,'corrections exported for existing watcher')
emit();assert(#d.materialEvents==2,'reload migration is idempotent')
AZPCForeverDB=fixture();AZPCForeverDB.trades[1].tradeExport=AZPCForeverDB.trades[1].tradeExport:gsub('1791444821000','1791444829000');emit();assert(#AZPCForeverDB.crafting.materialEvents==0,'missing recipe evidence leaves save untouched')
AZPCForeverDB=fixture();AZPCForeverDB.trades[20].tradeExport=AZPCForeverDB.trades[20].tradeExport:gsub('|11|0|','|12|0|');emit();assert(#AZPCForeverDB.crafting.materialEvents==0,'changed inventory blocks historical checkpoint')
AZPCForeverDB=fixture();AZPCForeverDB.crafting.crafts={{character='Lu',realm='Classic Beta PvP 2',region=90,faction='horde',observedAt=1791448000000,itemId=253664,consumedReagents={{itemId=2996,quantity=6}}}};emit();assert(#AZPCForeverDB.crafting.materialEvents==0,'later relevant crafts block stale migration')
print('PASS: addon-load migration, original data retention, exported corrections, replay, changed inventory and later crafting guards')

-- Reproduce the post-maintenance save: old region-90 login zero, newest region-110 eleven.
AZPCForeverDB=fixture()
local rows=AZPCForeverDB.trades
rows[#rows+1]={tradeExport='AZPCFTRADE|2|old-login|inventory_snapshot|2996|Bolt|0|0|1791511948000|Classic%20Beta%20PvP%202|horde|90|Lu||||||||'}
rows[#rows+1]={tradeExport='AZPCFTRADE|2|new-login|inventory_snapshot|2996|Bolt|11|0|1791511949020|Classic%20Beta%20PvP%202|horde|110|Lu||||||||'}
GetCurrentRegion=function()return 110 end
emit()
assert(#AZPCForeverDB.crafting.materialEvents==2,'beta region change does not discard newest inventory evidence')
assert(AZPCForeverDB.crafting.costing.positions[1].quantity==11,'post-maintenance quantity corrected')
AZPCForeverDB=fixture();AZPCForeverDB.crafting.crafts={{character='Lu',realm='Classic Beta PvP 2',region=110,faction='horde',observedAt=1791512000000,itemId=253664,consumedReagents={{itemId=2996,quantity=6}}}};emit()
assert(#AZPCForeverDB.crafting.materialEvents==0,'new-region crafts also block stale correction')
print('PASS: region-110 inventory and subsequent craft guards')
