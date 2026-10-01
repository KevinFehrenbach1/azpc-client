SlashCmdList={}
local frames={}
local function callback(_,event,name) for _,f in ipairs(frames) do if f.events[event] and f.handler then f.handler(f,event,name) end end end
function CreateFrame() local f={events={}};frames[#frames+1]=f;function f:RegisterEvent(event) if event=='AUCTION_ITEM_LIST_UPDATE' then error('unsupported') end self.events[event]=true end;function f:SetScript(_,fn) self.handler=fn end;return f end
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
function UnitName() return 'Tester' end
function UnitGUID() return 'Player-test' end
function GetInboxNumItems() return 2 end
function GetInboxInvoiceInfo(i) if i==1 then return 'buyer','Peacebloom','Seller',0,100,0,0,0,0,0,3 else return 'seller','Peacebloom','Buyer',0,210,0,10,0,0,0,3 end end
function GetInboxHeaderInfo(i) return nil,nil,'Auction House','Auction invoice',i==2 and 200 or 0,0,30 end
function GetInboxItem() return 'Peacebloom',2447,nil,3 end
AZPCForeverDB.itemIds.Peacebloom=2447
callback(nil,'MAIL_SHOW')
assert(#AZPCForeverDB.trades==2)
assert(AZPCForeverDB.trades[1].tradeExport:find('|buy|2447|Peacebloom|3|100|',1,true))
assert(AZPCForeverDB.trades[2].tradeExport:find('|sell|2447|Peacebloom|3|200|',1,true))
callback(nil,'MAIL_INBOX_UPDATE');assert(#AZPCForeverDB.trades==2)
function GetInboxInvoiceInfo() return 'seller','Peacebloom','Buyer',0,210,0,10,0,0,0,nil end
callback(nil,'MAIL_INBOX_UPDATE');assert(#AZPCForeverDB.trades==2)
print('PASS: confirmed buyer/seller mailbox records, net seller proceeds, repeated mailbox dedup and no invented quantity')
