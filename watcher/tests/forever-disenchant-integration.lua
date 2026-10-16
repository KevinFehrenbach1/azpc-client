-- Exercise the established material/mail/bank/loot regression suite while the
-- new isolated capture block is loaded as part of the normal addon file.
assert(loadfile('watcher/tests/forever-materials.lua'))()
assert(AZPCForeverDisenchant and AZPCForeverDB.disenchanting)
assert(#AZPCForeverDB.disenchanting.events==0,'ordinary materials, bank, mail and corpse/item loot do not become disenchants')
print('PASS disenchant integration: existing loot, source commands, transfers, bags and bank scenarios remain intact with capture loaded')
