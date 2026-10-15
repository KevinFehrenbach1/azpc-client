SlashCmdList={}
local frames,timers,hooks={}, {}, {}
local money,visible,popups=1000,true,0
function CreateFrame()local f={events={}};frames[#frames+1]=f;function f:RegisterEvent(e)self.events[e]=true end;function f:SetScript(_,fn)self.handler=fn end;return f end
local function emit(event,...)for _,f in ipairs(frames)do if f.events[event]then f.handler(f,event,...)end end end
C_Timer={After=function(_,fn)timers[#timers+1]=fn end}
local function flush()for pass=1,5 do local current=timers;timers={};for _,fn in ipairs(current)do fn()end end end
StaticPopupDialogs={};function StaticPopup_Show()popups=popups+1 end
function TakeInboxMoney()end
function hooksecurefunc(name,fn)hooks[name]=fn end
function GetMoney()return money end
function GetRealmName()return 'Classic Beta PvP 2'end
function GetCurrentRegion()return 90 end
function UnitFactionGroup()return 'Horde'end
function UnitName()return 'Phillip'end
function UnitGUID()return 'Player-test'end
function GetServerTime()return 1792000000 end
function GetInboxNumItems()return visible and 1 or 0 end
function GetInboxInvoiceInfo()return 'seller','Light Leather','Buyer',0,210,0,10,0,0,0,2 end
function GetInboxHeaderInfo()return nil,nil,'Auction House','Auction successful: Light Leather',200,0,30 end
function GetItemInfo(name)return name,'|Hitem:2318|h[Light Leather]|h'end
assert(loadfile('addons/forever/AZPCForever/AZPCForever.lua'))('AZPCForever')
emit('MAIL_SHOW');flush();assert(#AZPCForeverDB.trades==1);assert(popups==1,'new sale capture prompts while mailbox is open')
hooks.TakeInboxMoney(1);visible=false;money=1200;emit('PLAYER_MONEY');emit('MAIL_INBOX_UPDATE');flush();assert(popups==1,'real receipt capture must reach the collected-payout prompt');assert(#AZPCForeverDB.trades==1,'prompt must not duplicate or delete sale records')
print('PASS: live mailbox capture-to-collection reminder integration and record preservation')

-- A fresh character can close immediately, before a payout/missing-receipt update.
visible=true;emit('MAIL_CLOSED');function UnitGUID()return 'Player-wet-spinach'end
emit('MAIL_SHOW');flush();assert(#AZPCForeverDB.trades==2)
hooks.TakeInboxMoney(1);emit('MAIL_CLOSED');flush();assert(popups==2,'fast close must preserve reminder for captured sale')
-- Expired attachments have no money event and must use the close fallback.
function GetInboxInvoiceInfo()return nil end
function GetInboxHeaderInfo()return nil,nil,'Auction House','Auction expired: Light Leather',0,0,30 end
function GetInboxItem()return 'Light Leather',2318,nil,2 end
emit('MAIL_SHOW');flush();assert(#AZPCForeverDB.trades==3);assert(popups==3,'expiration prompts before closing mailbox');emit('MAIL_CLOSED');flush();assert(popups==3,'expiration-only mailbox must remind after capture')
emit('MAIL_SHOW');flush();emit('MAIL_CLOSED');flush();assert(popups==3,'previously captured expiration must not nag')
print('PASS: fast-close sale and expiration-only mailbox fallback')

-- Existing snapshot history must not prevent new financial receipts or reminders.
while #AZPCForeverDB.trades<10000 do
 AZPCForeverDB.trades[#AZPCForeverDB.trades+1]={tradeExport='AZPCFTRADE|2|old-snapshot-'..#AZPCForeverDB.trades..'|inventory_snapshot|2318|Light Leather|0|0|1791000000000|Classic Beta PvP 2|horde|90|Old'}
end
local oldFirst=AZPCForeverDB.trades[1]
function UnitGUID()return 'Player-after-cap'end
function GetInboxInvoiceInfo()return 'seller','Light Leather','Buyer',0,210,0,10,0,0,0,2 end
function GetInboxHeaderInfo()return nil,nil,'Auction House','Auction successful: Light Leather',200,0,30 end
emit('MAIL_SHOW');flush();assert(#AZPCForeverDB.trades==10001,'sale must save beyond former shared history limit')
emit('MAIL_CLOSED');flush();assert(popups==4,'new receipt beyond former cap must trigger reminder')
assert(AZPCForeverDB.trades[1]==oldFirst,'existing history must remain untouched')
function GetInboxInvoiceInfo()return nil end
function GetInboxHeaderInfo()return nil,nil,'Auction House','Auction expired: Light Leather',0,0,30 end
emit('MAIL_SHOW');flush();assert(#AZPCForeverDB.trades==10002,'expiration must save beyond former shared history limit')
emit('MAIL_CLOSED');flush();assert(popups==5)
print('PASS: sales, expirations and reminders beyond 10000 existing records without clearing history')
