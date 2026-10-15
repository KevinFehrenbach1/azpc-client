assert(loadfile('watcher/tests/forever-costing.lua'))()
-- Exact export cache must detect in-place mutations, array changes, receipt
-- enrichments and overwritten checkpoints; unchanged records skip JSON/encoding.
local r=AZPCForeverDB.crafting.materialEvents and AZPCForeverDB.crafting.materialEvents[1]
if not r then
 r={kind='free',eventId='cache-loot',itemId=999,quantity=1,untrackedQuantity=1,observedAt=1792100000000,realm='Realm',region=90,faction='horde',character='Lu',name='Cache',source='farmed'}
 AZPCForeverDB.crafting.materialEvents=AZPCForeverDB.crafting.materialEvents or {};table.insert(AZPCForeverDB.crafting.materialEvents,r)
end
assert(AZPCForeverCrafting.RebuildCosts())
local previous=r.syncExport;local original=string.format;local serialized=0
string.format=function(pattern,...)if pattern=='%.0f'or pattern=='%%%02X'then serialized=serialized+1 end;return original(pattern,...)end
assert(AZPCForeverCrafting.RebuildCosts());string.format=original
assert(serialized==0,'unchanged history is not serialized/percent encoded again')
r.name='Changed';assert(AZPCForeverCrafting.RebuildCosts());assert(r.syncExport~=previous,'in-place fields invalidate cached exports')
r.evidence={'first'};assert(AZPCForeverCrafting.RebuildCosts());previous=r.syncExport;r.evidence[1]='second';assert(AZPCForeverCrafting.RebuildCosts());assert(r.syncExport~=previous,'nested in-place array changes invalidate cache')
previous=r.syncExport;r.syncExport='broken';assert(AZPCForeverCrafting.RebuildCosts());assert(r.syncExport==previous,'corrupted exports are regenerated')
AZPCForeverDB={trades={{tradeExport='AZPCFTRADE|2|cache-receipt|buy|2318|Leather|2|40|1000|Realm|horde|90|Lu||||||||'}},crafting={recipes={},crafts={},seen={}}}
local state=assert(AZPCForeverCrafting.RebuildCosts());assert(state.positions[1].totalCopper==40)
AZPCForeverDB.trades[1].tradeExport=AZPCForeverDB.trades[1].tradeExport:gsub('|40|','|80|')
state=assert(AZPCForeverCrafting.RebuildCosts());assert(state.positions[1].totalCopper==80,'same receipt row enrichment invalidates parsed cache')
print('PASS: unchanged export fast path, in-place/nested edits, export repair and parsed receipt enrichment')
