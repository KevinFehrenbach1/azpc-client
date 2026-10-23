local replay=assert(loadfile('watcher/tests/lib/forever-history-replay.lua'))()
local function e(kind,at,itemId,quantity,copper,complete,character,eventId)
 return {kind=kind,at=at,itemId=itemId,quantity=quantity,copper=copper,complete=complete,character=character or 'Wet',realm='Realm',faction='horde',region=90,eventId=eventId}
end
local events={
 e('acquire',1,2589,10,0,true),
 e('acquire',2,2589,20,100000,true),
 e('consume',3,2589,6,nil,nil,nil,'mixed'),
 e('acquire',4,3385,1,0,true),
 e('acquire',5,3385,1,nil,false),
 e('consume',6,3385,2,nil,nil,nil,'unknown'),
 e('acquire',7,4265,1,10150,true),
 e('consume',8,4265,1,nil,nil,nil,'intermediate'),
 e('consume',9,4265,1,nil,nil,nil,'unmatched')
}
local snapshot={}
for i,v in ipairs(events) do snapshot[i]={kind=v.kind,quantity=v.quantity,copper=v.copper} end
local out=replay.replay(events)
assert(#out.consumptions==4)
assert(out.consumptions[1].recordedCopper==20000 and out.consumptions[1].complete,'weighted average of paid and free cloth')
assert(out.consumptions[2].complete==false and out.consumptions[2].unknownUnits==1,'unknown acquisition never becomes verified')
assert(out.consumptions[3].complete and out.consumptions[3].recordedCopper==10150,'intermediate crafted input cost')
assert(not out.consumptions[4].complete and out.consumptions[4].unmatched==1,'cannot reuse already consumed craft output')
for i,v in ipairs(events) do assert(v.kind==snapshot[i].kind and v.quantity==snapshot[i].quantity and v.copper==snapshot[i].copper,'read-only replay mutated source') end
print('PASS: read-only chronological replay, weighted averages, unknown cost, and intermediate consumption')
