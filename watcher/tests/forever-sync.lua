assert(loadfile('watcher/tests/forever-crafting.lua'))()
local d=AZPCForeverDB.crafting
local r=d.crafts[1];r.name='Cloth "quoted" \\ café';AZPCForeverCrafting.RebuildCosts()
local function decoded(s)return(s:gsub('%%(%x%x)',function(h)return string.char(tonumber(h,16))end))end
assert(r.syncExport:sub(1,13)=='AZPCFCRAFT|1|','export protocol identity')
local payload=decoded(r.syncExport:sub(14))
assert(payload:find('"recordType":"craft"',1,true) and payload:find('"recordId":"'..r.eventId..'"',1,true))
assert(payload:find('\\"quoted\\"',1,true) and payload:find('\\\\ café',1,true),'JSON escapes quotes, backslashes and preserves Unicode')
assert(not payload:find('syncExport',1,true),'export does not recursively include itself')
local count=0;for _,recipe in pairs(d.recipes)do assert(recipe.syncExport and decoded(recipe.syncExport):find('"reagents":[',1,true),'recipe arrays export as JSON arrays');count=count+1 end
assert(count>0)
local previous=r.syncExport;AZPCForeverCrafting.RebuildCosts();assert(r.syncExport==previous,'identical evidence exports deterministically')
print('PASS: crafting JSON exports, recipe arrays, Unicode escaping, stable identities, deterministic replay and no self recursion')
