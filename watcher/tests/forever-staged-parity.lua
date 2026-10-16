-- Run every existing cost regression through BOTH execution paths, retaining the
-- original fixture's live record references for its assertions.
local frames={};local tick=0
function GetTimePreciseSec()tick=tick+0.0002;return tick end
local function copy(v)if type(v)~='table'then return v end;local r={};for k,x in pairs(v)do r[k]=copy(x)end;return r end
local function equal(a,b)if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end;for k,v in pairs(a)do if not equal(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true end
local loader=loadfile;local comparisons=0
loadfile=function(path,...)
 local fn,err=loader(path,...)
 if not fn or path~='addons/forever/AZPCForever/AZPCForever.lua'then return fn,err end
 return function(...)
  function CreateFrame()local f={};frames[#frames+1]=f;function f:RegisterEvent()end;function f:SetScript(k,v)self[k]=v end;return f end
  C_Timer={After=function(_,callback)callback()end}
  fn(...)
  local synchronous=AZPCForeverCrafting.RebuildCosts
  AZPCForeverCrafting.RebuildCosts=function()
   local live=AZPCForeverDB
   AZPCForeverDB=copy(live);local expectedState,expectedError=synchronous();local expected=AZPCForeverDB
   AZPCForeverDB=live;AZPCForeverCrafting.ScheduleCosts()
   for i=1,10000 do
    for _,f in ipairs(frames)do if f.OnUpdate then f.OnUpdate(f,0.016)end end
    if not AZPCForeverCrafting.CostsPending()then break end
    assert(i<10000,'parity job did not finish')
   end
   assert(equal(live,expected),'staged state/exports differ from synchronous reference at comparison '..(comparisons+1))
   comparisons=comparisons+1
   if not expectedState then return nil,live.crafting.costingError or expectedError end
   return live.crafting.costing
  end
 end
end
assert(loadfile('watcher/tests/forever-costing.lua'))()
loadfile=loader
assert(comparisons>20)
print('PASS: '..comparisons..' existing cost fixtures/replays have exact synchronous/staged state and export parity')
