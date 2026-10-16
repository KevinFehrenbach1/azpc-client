local f=assert(io.open('addons/forever/AZPCForever/AZPCForever.lua'));local source=f:read('*a');f:close()
local block=assert(source:match('%-%- BEGIN AZPC TIMING DIAGNOSTICS\n(.-)%-%- END AZPC TIMING DIAGNOSTICS'))
assert((loadstring or load)(block))()
local p=AZPCForeverDiagnostics;local clockCalls,ran=0,0
function debugprofilestop()clockCalls=clockCalls+1;return clockCalls*10 end
local wrapped=p.Wrap('Test',function(a,b,c)ran=ran+1;assert(a==1 and b==nil and c==3);return nil,42,nil,'ok'end)
local function result(...)assert(select('#',...)==4);local a,b,c,d=...;assert(a==nil and b==42 and c==nil and d=='ok')end
result(wrapped(1,nil,3));assert(clockCalls==0 and next(p.stats)==nil,'disabled diagnostics never read clock or accumulate stats')
p.Command('perf on');result(wrapped(1,nil,3));assert(p.stats.Test.calls==1 and p.stats.Test.max==10 and ran==2,'enabled timings preserve nil-containing arguments/results and invoke once')
local sentinel={};local fail=p.Wrap('Failure',function()error(sentinel)end);local ok,err=pcall(fail);assert(not ok and err==sentinel,'original error propagates unchanged');assert(p.stats.Failure==nil)
function debugprofilestop()error('timer unavailable')end
result(wrapped(1,nil,3));assert(ran==3 and p.stats.Test.calls==1,'timer failure cannot suppress capture')
local values={100,10};function debugprofilestop()return table.remove(values,1)end
result(wrapped(1,nil,3));assert(p.stats.Test.calls==1,'timer reset cannot produce negative measurements')
p.Command('perf off');p.Command('perf reset');assert(not p.enabled and next(p.stats)==nil)
print('PASS: disabled fast path, exact arguments/results, original errors, timer failure/reset isolation and reset/off controls')

assert(loadfile('watcher/tests/forever-costing.lua'))()
local before={};for _,r in ipairs(AZPCForeverDB.crafting.crafts)do before[r]=r.syncExport end
local originalCosting=AZPCForeverDB.crafting.costing
local tick=0;function debugprofilestop()tick=tick+1;return tick end
AZPCForeverDiagnostics.Command('perf on')
local state,err=AZPCForeverCrafting.RebuildCosts();assert(state and not err)
for r,export in pairs(before)do assert(r.syncExport==export,'enabled diagnostics retain exact craft exports')end
assert(AZPCForeverDiagnostics.stats['Costs plus exports'].calls==1)
assert(AZPCForeverDiagnostics.stats['Cost replay'].calls==1)
assert(AZPCForeverDiagnostics.stats['Export generation'].calls==1)
AZPCForeverDiagnostics.Command('perf');AZPCForeverDiagnostics.Command('perf off')
print('PASS: real cost/export instrumentation preserves evidence and records nested timings')
local originalLoad=loadfile
loadfile=function(path,...)
 local fn,err=originalLoad(path,...)
 if fn and path=='addons/forever/AZPCForever/AZPCForever.lua'then
  return function(...)fn(...);AZPCForeverDiagnostics.enabled=true end
 end
 return fn,err
end
AZPCForeverDB=nil
assert(loadfile('watcher/tests/forever-reload-integration.lua'))()
loadfile=originalLoad
assert(AZPCForeverDiagnostics.stats['Mailbox capture'].calls>0,'actual mailbox capture measured with diagnostics enabled')
print('PASS: diagnostics enabled during real mailbox capture, reload prompts, expired mail and retained large history')
