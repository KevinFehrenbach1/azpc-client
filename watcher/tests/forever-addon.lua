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
    assert(fields==21 or fields==13,'mailbox export must contain 21 v2 fields or 13 legacy fields: '..row.tradeExport)
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

-- New lifecycle capture refuses partial owner pages and preserves pending sales.
AZPCForeverDB.trades={};AZPCForeverDB.tradeSeen={};AZPCForeverDB.owners={};AZPCForeverDB.bagStates={};AZPCForeverDB.settledOwners={}
callback(nil,'AUCTION_HOUSE_SHOW')
local full=true
local ownerRows={{id=2447,q=4,sold=0},{id=2447,q=2,sold=1}}
function GetNumAuctionItems(mode) if mode=='owner' then return #ownerRows,full and #ownerRows or #ownerRows+1 else return 0,0 end end
function GetAuctionItemInfo(mode,i) local r=ownerRows[i];return 'Peacebloom',nil,r.q,nil,nil,nil,nil,nil,nil,500,nil,nil,nil,nil,nil,r.sold,r.id,true end
callback(nil,'AUCTION_OWNED_LIST_UPDATE');assert(#AZPCForeverDB.trades==1)
assert(AZPCForeverDB.trades[1].tradeExport:find('|listing_snapshot|2447|Peacebloom|6|0|',1,true))
local function fields(export) local f={};for x in (export..'|'):gmatch('(.-)|') do f[#f+1]=x end;return f end
local f=fields(AZPCForeverDB.trades[1].tradeExport);assert(#f==21);assert(f[17]=='4' and f[18]=='2' and f[19]=='0')
full=false;ownerRows={};callback(nil,'AUCTION_OWNED_LIST_UPDATE');assert(#AZPCForeverDB.trades==1,'partial pages cannot close listings')
full=true;ownerRows={{id=2447,q=4,sold=0}};callback(nil,'AUCTION_OWNED_LIST_UPDATE');f=fields(AZPCForeverDB.trades[#AZPCForeverDB.trades].tradeExport);assert(f[17]=='4' and f[18]=='2' and f[19]=='0','pending rows remain waiting when owner list clears')
function GetInboxNumItems() return 1 end
function GetInboxInvoiceInfo() return 'seller','Peacebloom','Buyer',0,210,25,10,0,0,0,2 end
function GetInboxHeaderInfo() return nil,nil,'Auction House','Auction successful: Peacebloom',225,0,30 end
callback(nil,'MAIL_SHOW');f=fields(AZPCForeverDB.trades[#AZPCForeverDB.trades].tradeExport);assert(f[4]=='sell' and f[8]=='200' and f[14]=='25' and f[16]=='225','mail refund must not become sale revenue')
ownerRows={{id=2447,q=4,sold=0},{id=2447,q=2,sold=1}};callback(nil,'AUCTION_OWNED_LIST_UPDATE');f=fields(AZPCForeverDB.trades[#AZPCForeverDB.trades].tradeExport);assert(AZPCForeverDB.owners['1|Forever Test|horde|Tester'][2447].pending==0,'stale sold rows must not resurrect a settled sale')
ownerRows={};callback(nil,'AUCTION_OWNED_LIST_UPDATE');f=fields(AZPCForeverDB.trades[#AZPCForeverDB.trades].tradeExport);assert(f[17]=='0' and f[18]=='0' and f[19]=='4','unconfirmed disappearance becomes unresolved')
C_Container={GetContainerNumSlots=function(bag)return bag==0 and 1 or 0 end,GetContainerItemInfo=function()return {itemID=2447,stackCount=3,hyperlink='item:2447'}end}
function GetItemInfo() return 'Peacebloom','item:2447' end
callback(nil,'BAG_UPDATE_DELAYED');f=fields(AZPCForeverDB.trades[#AZPCForeverDB.trades].tradeExport);assert(f[4]=='inventory_snapshot' and f[20]=='3')
local n=#AZPCForeverDB.trades;callback(nil,'BAG_UPDATE_DELAYED');assert(#AZPCForeverDB.trades==n,'unchanged bags do not flood the ledger')
C_Container.GetContainerNumSlots=function()return 0 end;callback(nil,'BAG_UPDATE_DELAYED');f=fields(AZPCForeverDB.trades[#AZPCForeverDB.trades].tradeExport);assert(f[20]=='0','removed bag items clear availability')
-- Modern beta owner API has an explicit completeness guard.
local complete=false
C_AuctionHouse={HasFullOwnedAuctionResults=function()return complete end,GetOwnedAuctions=function()return {{itemKey={itemID=2447},quantity=5,status=0}}end,GetItemKeyInfo=function()return {itemName='Peacebloom'}end}
n=#AZPCForeverDB.trades;callback(nil,'OWNED_AUCTIONS_UPDATED');assert(#AZPCForeverDB.trades==n)
complete=true;callback(nil,'OWNED_AUCTIONS_UPDATED');f=fields(AZPCForeverDB.trades[#AZPCForeverDB.trades].tradeExport);assert(f[17]=='5')
print('PASS: complete legacy/modern owner capture, partial-page guards, pending/settled exclusion, net deposit refund, bag availability and dedup')

-- One seller invoice crossing a rounded expiry boundary must stay one sale.
AZPCForeverDB.trades={};AZPCForeverDB.tradeSeen={};AZPCForeverDB.settledOwners={}
local sellerDays=30
local sellerCount=1
function GetInboxNumItems() return sellerCount end
function GetInboxInvoiceInfo() return 'seller','Peacebloom','Buyer',0,1200,40,60,0,0,0,1 end
function GetInboxHeaderInfo() return nil,nil,'Auction House','Auction successful: Peacebloom',1180,0,sellerDays end
callback(nil,'MAIL_SHOW');assert(#AZPCForeverDB.trades==1)
local original=AZPCForeverDB.trades[1].tradeExport
stamp=stamp+75;sellerDays=sellerDays-75/86400+65/86400
callback(nil,'MAIL_INBOX_UPDATE');assert(#AZPCForeverDB.trades==1,'seller expiry estimate crossing minute boundary cannot duplicate sale')
assert(AZPCForeverDB.trades[1].tradeExport==original,'repeated sale preserves timestamp and ID')
frames={};assert(loadfile('addons/forever/AZPCForever/AZPCForever.lua'))('AZPCForever');callback(nil,'ADDON_LOADED','AZPCForever');callback(nil,'MAIL_SHOW')
assert(#AZPCForeverDB.trades==1,'seller identity survives addon reload')
sellerCount=2;callback(nil,'MAIL_INBOX_UPDATE');assert(#AZPCForeverDB.trades==2,'two simultaneous identical sales retain occurrence IDs')
sellerCount=1;sellerDays=sellerDays-1/24;callback(nil,'MAIL_INBOX_UPDATE');assert(#AZPCForeverDB.trades==3,'different receipt expiry remains a distinct sale')
print('PASS: seller expiry drift, reload stability and distinct equal sales')

AZPCForeverDB.trades={};AZPCForeverDB.tradeSeen={}
local buyerName=''
function GetInboxNumItems()return 1 end
function GetInboxInvoiceInfo()return 'seller','Peacebloom',buyerName,0,1200,40,60,0,0,0,1 end
function GetInboxHeaderInfo()return nil,nil,'Auction House','Auction successful: Peacebloom',1180,0,30 end
callback(nil,'MAIL_SHOW');assert(#AZPCForeverDB.trades==0,'seller capture waits for invoice buyer name')
buyerName='Glesmord Hillmont';stamp=stamp+1;callback(nil,'MAIL_INBOX_UPDATE');assert(#AZPCForeverDB.trades==1,'hydrated invoice records one sale')
callback(nil,'MAIL_SHOW');assert(#AZPCForeverDB.trades==1)
print('PASS: actual blank-then-named invoice hydration does not duplicate sale')
