SlashCmdList={};local frames,timers={},{}
function CreateFrame()local f={events={},scripts={}};frames[#frames+1]=f;function f:RegisterEvent(e)self.events[e]=true end;function f:SetScript(k,fn)self.scripts[k]=fn end;return f end
C_Timer={After=function(_,fn)timers[#timers+1]=fn end}
local ticks=0;function GetTimePreciseSec()ticks=ticks+0.0002;return ticks end
function GetRealmName()return 'Realm'end;function GetCurrentRegion()return 90 end
function UnitName()return 'Wet'end;function UnitFactionGroup()return 'Horde'end
function GetServerTime()return 1792000000 end
local function copy(v)if type(v)~='table'then return v end;local r={};for k,x in pairs(v)do r[k]=copy(x)end;return r end
local function same(a,b)if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end;for k,v in pairs(a)do if not same(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true end
assert(loadfile('addons/forever/AZPCForever/AZPCForever.lua'))('AZPCForever')
local function fixture()
 local d={recipes={},crafts={},seen={},materialEvents={},vendorEvents={}};local root={trades={},crafting=d}
 for i=1,300 do root.trades[i]={tradeExport=table.concat({'AZPCFTRADE','2','purchase'..i,'buy',2318,'Leather',1,42,1000+i,'Realm','horde',90,'Wet','','','','','','','',''},'|')}end
 for i=1,20 do d.crafts[i]={schema=1,eventId='craft'..i,recipeId=2165,recipeKey='recipe',itemId=2313,quantity=1,observedAt=3000+i,region=90,realm='Realm',faction='horde',character='Wet',name='Kit',materialsKnown=true,consumedReagents={{itemId=2318,quantity=4}},recipeReagents={{itemId=2318,quantity=4}},resourcesReturned={},confirmation='player_spell_success_and_item_result'}end
 return root
end
local function tick()for _,f in ipairs(frames)do if f.scripts.OnUpdate then f.scripts.OnUpdate(f,0.016)end end end
local function start()local t=timers;timers={};for _,fn in ipairs(t)do fn()end end
local function finish()for i=1,10000 do tick();if not AZPCForeverCrafting.CostsPending()then return i end end;error('staged replay did not finish')end
local function sync(input)AZPCForeverDB=copy(input);assert(AZPCForeverCrafting.RebuildCosts());return copy(AZPCForeverDB)end
local input=fixture();local expected=sync(input)
AZPCForeverDB=copy(input);AZPCForeverCrafting.ScheduleCosts();AZPCForeverCrafting.ScheduleCosts();assert(#timers==1,'bursts schedule once');start();tick()
assert(AZPCForeverCrafting.CostsPending()and AZPCForeverDB.crafting.costing==nil and AZPCForeverDB.crafting.crafts[1].costBasis==nil,'first slice cannot publish partial costs')
assert(finish()>1);assert(same(AZPCForeverDB,expected),'staged final state and exports exactly match synchronous replay')
local before=AZPCForeverDB.crafting.costing
AZPCForeverCrafting.ScheduleCosts();start();finish();assert(AZPCForeverDB.crafting.costing==before,'unchanged evidence skips replay and publication')
AZPCForeverDB.trades[1].invoiceEvidence={observedAt=123456};AZPCForeverCrafting.ScheduleCosts();start();finish();assert(AZPCForeverDB.crafting.costing==before,'display-only invoice refresh cannot trigger cost replay')
-- Mutate a receipt already copied by a paused job; stale result must be discarded.
AZPCForeverDB=copy(input);AZPCForeverCrafting.ScheduleCosts();start();tick()
AZPCForeverDB.trades[1].tradeExport=AZPCForeverDB.trades[1].tradeExport:gsub('|42|','|84|')
local changed=copy(AZPCForeverDB);finish();local actual=copy(AZPCForeverDB);assert(same(actual,sync(changed)),'in-place receipt enrichment during job is recomputed, not lost')
-- Append evidence mid-job and request another schedule: no dropped acquisitions.
AZPCForeverDB=copy(input);AZPCForeverCrafting.ScheduleCosts();start();tick()
AZPCForeverDB.trades[#AZPCForeverDB.trades+1]={tradeExport='AZPCFTRADE|2|late|buy|2318|Leather|2|200|1500|Realm|horde|90|Wet||||||||'}
changed=copy(AZPCForeverDB);AZPCForeverCrafting.ScheduleCosts();finish();actual=copy(AZPCForeverDB);assert(same(actual,sync(changed)),'new evidence during replay is retained exactly')
-- Explicit flush supersedes paused jobs; old frame/timer callbacks cannot publish.
AZPCForeverDB=copy(input);AZPCForeverCrafting.ScheduleCosts();start();tick();assert(AZPCForeverCrafting.RebuildCosts());assert(same(AZPCForeverDB,expected));assert(not AZPCForeverCrafting.CostsPending());tick();start();assert(same(AZPCForeverDB,expected),'explicit/reload-style flush cancels stale jobs')
-- Actual logout handler must complete costs and exports before saving.
AZPCForeverDB=copy(input);AZPCForeverCrafting.ScheduleCosts();start();tick()
for _,f in ipairs(frames)do if f.events.PLAYER_LOGOUT and f.scripts.OnEvent then f.scripts.OnEvent(f,'PLAYER_LOGOUT')end end
assert(same(AZPCForeverDB.crafting,expected.crafting)and same(AZPCForeverDB.trades,expected.trades),'logout flush matches original synchronous costs/exports and raw receipts')
-- A capture during incremental validation invalidates even fields already checked.
local function currentJob()
 for i=1,10 do local name,value=debug.getupvalue(AZPCForeverCrafting.CostsPending,i);if name=='job'then return value end end
end
AZPCForeverDB=copy(input);AZPCForeverCrafting.ScheduleCosts();start()
for i=1,10000 do tick();local j=currentJob();if j and j.phase=='validate'then break end;assert(i<10000)end
assert(currentJob()and currentJob().phase=='validate')
AZPCForeverDB.trades[1].tradeExport=AZPCForeverDB.trades[1].tradeExport:gsub('|42|','|126|')
AZPCForeverCrafting.InvalidateCosts();changed=copy(AZPCForeverDB);finish();actual=copy(AZPCForeverDB)
assert(same(actual,sync(changed)),'capture during validation rejects stale publication')
-- Queued callbacks and complete DB replacement cannot revive an obsolete job.
AZPCForeverDB=copy(input);AZPCForeverCrafting.ScheduleCosts();assert(AZPCForeverCrafting.RebuildCosts());start();assert(not AZPCForeverCrafting.CostsPending())
AZPCForeverDB=copy(input);local abandoned=AZPCForeverDB;AZPCForeverCrafting.ScheduleCosts();start();tick()
AZPCForeverDB=copy(input);changed=copy(AZPCForeverDB);finish();actual=copy(AZPCForeverDB)
assert(abandoned.crafting.costing==nil and same(actual,sync(changed)),'replaced source never receives old job publication')
-- Atomic failure preserves old state and still exports raw craft evidence.
AZPCForeverDB=copy(input);local old={marker=true};AZPCForeverDB.crafting.costing=old;AZPCForeverDB.crafting.vendorCostingBlocked=true
AZPCForeverCrafting.ScheduleCosts();start();finish();assert(AZPCForeverDB.crafting.costing==old and AZPCForeverDB.crafting.costingError,'failed replay does not replace prior state')
assert(AZPCForeverDB.crafting.crafts[1].costBasis==nil and AZPCForeverDB.crafting.crafts[1].syncExport,'failure retains raw exports without publishing partial craft costs')
print('PASS: staged/sync exact parity, unchanged evidence, nested slices, in-place edits, new arrivals, explicit and logout flushes, atomic failure and raw evidence preservation')
