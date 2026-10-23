-- Historical inventory replay prototype (read-only, Lua 5.1).
-- Inputs are normalized events, not live addon state. No saved variables are changed.
local M={}
local function key(e)
  return table.concat({tostring(e.region or ''),tostring(e.realm or ''),tostring(e.faction or ''),tostring(e.character or ''),tostring(e.itemId or '')},'|')
end
local function copy(e)
  local t={};for k,v in pairs(e) do t[k]=v end;return t
end
function M.replay(events)
  local sorted={}
  for i,e in ipairs(events) do
    assert(type(e)=='table' and type(e.at)=='number' and type(e.itemId)=='number','invalid event')
    local v=copy(e);v._ordinal=i;sorted[#sorted+1]=v
  end
  table.sort(sorted,function(a,b) if a.at~=b.at then return a.at<b.at end return a._ordinal<b._ordinal end)
  local balances,results={},{}
  for _,e in ipairs(sorted) do
    local id=key(e);local p=balances[id] or {quantity=0,knownCopper=0,unknownQuantity=0}
    local q=assert(tonumber(e.quantity),'quantity required')
    assert(q>0 and q==math.floor(q),'quantity must be positive integer')
    if e.kind=='acquire' then
      p.quantity=p.quantity+q
      if e.complete==true and type(e.copper)=='number' and e.copper>=0 then
        p.knownCopper=p.knownCopper+e.copper
      else
        p.unknownQuantity=p.unknownQuantity+q
        p.knownCopper=p.knownCopper+math.max(0,tonumber(e.copper) or 0)
      end
    elseif e.kind=='consume' then
      local available=p.quantity;local used=math.min(q,available)
      local total=p.knownCopper
      local cost=available>0 and math.floor(total*used/available+0.5) or 0
      local unresolved=available>0 and math.min(used,p.unknownQuantity) or 0
      local complete=(used==q and p.unknownQuantity==0)
      p.quantity=available-used;p.knownCopper=total-cost
      p.unknownQuantity=math.max(0,p.unknownQuantity-unresolved)
      results[#results+1]={eventId=e.eventId,itemId=e.itemId,quantity=q,matched=used,recordedCopper=cost,complete=complete,unknownUnits=unresolved,unmatched=q-used}
    else error('unknown event kind '..tostring(e.kind)) end
    balances[id]=p
  end
  return {balances=balances,consumptions=results}
end
return M
