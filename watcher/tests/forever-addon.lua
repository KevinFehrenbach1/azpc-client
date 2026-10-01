SlashCmdList={}
local callback
function CreateFrame() return {RegisterEvent=function(_,event) if event=='AUCTION_ITEM_LIST_UPDATE' then error('unsupported') end end,SetScript=function(_,_,fn) callback=fn end} end
C_Timer={After=function(_,fn) fn() end}
function GetRealmName() return 'Forever Test' end
function UnitFactionGroup() return 'Horde' end
function GetCurrentRegion() return 1 end
local stamp=1790830800
function GetServerTime() return stamp end
local results={{itemKey={itemID=2447},minPrice=150,totalQuantity=20},{itemKey={itemID=2447},minPrice=100,totalQuantity=5},{itemKey={itemID=1},minPrice=0,totalQuantity=1}}
C_AuctionHouse={GetBrowseResults=function() return results end,GetItemKeyInfo=function() return {itemName='Peace; bloom|%'} end}
assert(loadfile('addons/forever/AZPCForever/AZPCForever.lua'))('AZPCForever')
callback(nil,'ADDON_LOADED','AZPCForever');callback(nil,'AUCTION_HOUSE_SHOW')
SlashCmdList.AZPCFOREVER('capture')
local snapshot=AZPCForeverDB.snapshots[1].export
assert(snapshot=='AZPCFOREVER|1|Forever%20Test|horde|1|1790830800;2447|Peace%3B%20bloom%7C%25|100|25|0',snapshot)
SlashCmdList.AZPCFOREVER('capture');assert(#AZPCForeverDB.snapshots==1)
C_AuctionHouse=nil
function GetNumAuctionItems() return 1 end
function GetAuctionItemInfo() return 'Peacebloom',nil,5,nil,nil,nil,nil,nil,nil,500,nil,nil,nil,nil,nil,nil,2447 end
stamp=stamp+1
SlashCmdList.AZPCFOREVER('capture');assert(AZPCForeverDB.snapshots[2].export:find('2447|Peacebloom|100|5|1',1,true))
for i=1,40 do stamp=stamp+1;SlashCmdList.AZPCFOREVER('capture') end
assert(#AZPCForeverDB.snapshots==30)
callback(nil,'AUCTION_HOUSE_CLOSED');SlashCmdList.AZPCFOREVER('capture');assert(#AZPCForeverDB.snapshots==30)
print('PASS: modern/legacy exports, aggregation, percent encoding, duplicate/capture cap and closed AH')
