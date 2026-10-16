-- Load the new module exactly after the existing main addon, as the TOC does,
-- while exercising the established material/mail/bank/loot regression suite.
local original=loadfile
loadfile=function(path)
 local fn,err=original(path)
 if not fn or path~='addons/forever/AZPCForever/AZPCForever.lua' then return fn,err end
 return function(...)
  fn(...)
  assert(original('addons/forever/AZPCForever/AZPCForeverDisenchant.lua'))(...)
 end
end
assert(original('watcher/tests/forever-materials.lua'))()
assert(AZPCForeverDisenchant and AZPCForeverDB.disenchanting)
assert(#AZPCForeverDB.disenchanting.events==0,'ordinary materials, bank, mail and corpse/item loot do not become disenchants')
loadfile=original
print('PASS disenchant integration: existing loot, source commands, transfers, bags and bank scenarios remain intact with both TOC modules loaded')
