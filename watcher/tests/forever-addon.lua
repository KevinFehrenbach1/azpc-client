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
local days=30
local returnedQuantity=7
local subject='Auction expired: Peacebloom'
local money,cod=0,0
function GetInboxNumItems() return 1 end
function GetInboxInvoiceInfo() return nil end
function GetInboxHeaderInfo() return nil,nil,'Auction House',subject,money,cod,days end
function GetInboxItem() return 'Peacebloom',2447,nil,returnedQuantity end
callback(nil,'MAIL_SHOW')
assert(#AZPCForeverDB.trades==3)
assert(AZPCForeverDB.trades[3].tradeExport:find('|expired|2447|Peacebloom|7|0|',1,true))
stamp=stamp+75;days=days-75/86400+15/86400
callback(nil,'MAIL_INBOX_UPDATE');callback(nil,'MAIL_SHOW');SlashCmdList.AZPCFOREVER('mail')
assert(#AZPCForeverDB.trades==3,'reopening mail and expiry estimate drift must not duplicate returns')
-- Saved dedupe state survives addon reload.
frames={};assert(loadfile('addons/forever/AZPCForever/AZPCForever.lua'))('AZPCForever')
callback(nil,'ADDON_LOADED','AZPCForever');callback(nil,'MAIL_SHOW');assert(#AZPCForeverDB.trades==3)
function GetInboxNumItems() return 2 end
callback(nil,'MAIL_INBOX_UPDATE');assert(#AZPCForeverDB.trades==4,'two identical returned stacks are separate records')
function GetInboxNumItems() return 1 end
returnedQuantity=nil;callback(nil,'MAIL_INBOX_UPDATE');assert(#AZPCForeverDB.trades==4,'unresolved attachment count must wait')
returnedQuantity=9;subject='A gift';callback(nil,'MAIL_INBOX_UPDATE');assert(#AZPCForeverDB.trades==4,'ordinary mail is not an expired auction')
subject='Auction cancelled: Peacebloom';callback(nil,'MAIL_INBOX_UPDATE');assert(#AZPCForeverDB.trades==4,'cancelled mail is not falsely labelled expired')
subject='Auction expired: Other item';callback(nil,'MAIL_INBOX_UPDATE');assert(#AZPCForeverDB.trades==4,'subject and attachment must agree')
subject='Auction expired: Peacebloom';money=1;callback(nil,'MAIL_INBOX_UPDATE');assert(#AZPCForeverDB.trades==4)
money=0;cod=1;callback(nil,'MAIL_INBOX_UPDATE');assert(#AZPCForeverDB.trades==4)
cod=0;days=29;callback(nil,'MAIL_INBOX_UPDATE');assert(#AZPCForeverDB.trades==5,'a later distinct return is recorded')
AUCTION_EXPIRED_MAIL_SUBJECT='Auktion abgelaufen: %s';subject='Auktion abgelaufen: Peacebloom';returnedQuantity=11
callback(nil,'MAIL_INBOX_UPDATE');assert(#AZPCForeverDB.trades==6,'localized auction subject template is supported')
print('PASS: expired stack quantity, no trade value, reopen/reload dedupe, identical stacks, missing metadata, unrelated mail and localized subjects')
for _,row in ipairs(AZPCForeverDB.trades) do
    local fields=0
    for _ in (row.tradeExport..'|'):gmatch('(.-)|') do fields=fields+1 end
    assert(fields==13,'mailbox export must contain exactly 13 fields: '..row.tradeExport)
end
print('PASS: actual addon purchase, sale and expired exports contain exactly 13 fields')
-- Reproduce a record already saved by 0.1.2, including both gsub return values.
local function legacyEncode(text)
    return tostring(text or ''):gsub('([^%w%-_%.])',function(c)return string.format('%%%02X',string.byte(c))end)
end
AUCTION_EXPIRED_MAIL_SUBJECT=nil;subject='Auction expired: Peacebloom';returnedQuantity=13;days=28
local anchor=math.floor(stamp+days*86400+0.5)
local oldBase=table.concat({'Player-test','Forever Test',1,2447,13,legacyEncode('Auction House'),legacyEncode(subject)},':')
local oldFingerprint=table.concat({'Player-test','Forever Test',1,'expired',2447,13,0,anchor,legacyEncode(nil),legacyEncode('Auction House'),legacyEncode(subject)},':')..':1'
AZPCForeverDB.expiredMailAnchors[oldBase]={anchor}
AZPCForeverDB.tradeSeen[oldFingerprint]=true
local oldFields={'AZPCFTRADE','1',legacyEncode(oldFingerprint),'expired',2447,legacyEncode('Peacebloom'),13,0,stamp,legacyEncode('Forever Test'),'horde',1,legacyEncode('Tester')}
assert(#oldFields==14,'legacy bug fixture must have the extra field')
AZPCForeverDB.trades[#AZPCForeverDB.trades+1]={tradeExport=table.concat(oldFields,'|')}
local beforeUpgrade=#AZPCForeverDB.trades
callback(nil,'MAIL_SHOW');SlashCmdList.AZPCFOREVER('mail')
assert(#AZPCForeverDB.trades==beforeUpgrade,'upgrade must preserve legacy dedupe identity')
print('PASS: old expired export and saved dedupe anchors survive upgrade without duplicate records')
