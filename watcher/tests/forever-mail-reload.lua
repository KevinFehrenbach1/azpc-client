SlashCmdList={}
local frames,timers={},{}
function CreateFrame()
 local f={events={}};frames[#frames+1]=f
 function f:RegisterEvent(e)self.events[e]=true end
 function f:SetScript(_,fn)self.handler=fn end
 return f
end
local function emit(e,...)for _,f in ipairs(frames)do if f.events[e]and f.handler then f.handler(f,e,...)end end end
C_Timer={After=function(_,fn)timers[#timers+1]=fn end}
local clock=1792130000
function GetServerTime()return clock end
function GetRealmName()return 'Classic Beta PvP 2' end
function UnitName()return 'Wet' end
function UnitGUID()return 'Player-Wet' end
function UnitFactionGroup()return 'Horde' end
function GetCurrentRegion()return 90 end
local rows,loaded={},true
function GetInboxNumItems()if not loaded then return 0,0 end;return #rows,#rows end
function GetInboxInvoiceInfo(i)
 local r=loaded and rows[i];if r then return 'seller',r.name,r.buyer,0,16000,r.deposit,r.fee,0,0,0,r.quantity end
end
function GetInboxHeaderInfo(i)
 local r=loaded and rows[i];if r then return nil,nil,'Auction House','Auction successful: '..r.name,r.amount,0,r.days end
end
function GetItemInfo(name)return name,name=='Choker'and 'item:12020' or 'item:3182' end
local function row(name,buyer)return {name=name or 'Choker',buyer=buyer or '',quantity=1,amount=15993,deposit=793,fee=800,days=30}end
local function loadAddon()frames={};timers={};assert(loadfile('addons/forever/AZPCForever/AZPCForever.lua'))('AZPCForever');emit('ADDON_LOADED','AZPCForever')end
local function sales()
 local out={};for _,r in ipairs(AZPCForeverDB.trades)do if r.tradeExport:find('|sell|',1,true)then out[#out+1]=r end end;return out
end
loadAddon();rows={row()};emit('MAIL_SHOW')
assert(#sales()==1);local original=sales()[1].tradeExport
clock=clock+1200;emit('MAIL_INBOX_UPDATE')
assert(#sales()==1 and sales()[1].tradeExport==original,'20-minute cached expiry drift in the same visible mail is not a new sale')
emit('PLAYER_LOGOUT')
assert(AZPCForeverDB.mailReloadCheckpoint and #AZPCForeverDB.mailReloadCheckpoint.entries==1,'uncollected live receipt checkpoint survives logout')
clock=clock+8;loadAddon();loaded=false;emit('MAIL_SHOW')
loaded=true;rows[1].buyer='Buyer';clock=clock+1;emit('MAIL_INBOX_UPDATE')
assert(#sales()==1 and sales()[1].tradeExport==original,'empty initial cache, reload, expiry drift and buyer hydration preserve original identity and time')
rows[2]=row(nil,'Buyer');emit('MAIL_INBOX_UPDATE')
assert(#sales()==2,'another identical receipt remains a distinct sale')
emit('PLAYER_LOGOUT');clock=clock+8;loadAddon();emit('MAIL_SHOW')
assert(#sales()==2,'both identical receipt occurrences survive a second reload')
-- Once a complete loaded inbox has lost both mails, a new identical sale must
-- not reuse either consumed receipt ID even if its expiry minute is the same.
rows={};emit('MAIL_INBOX_UPDATE');rows={row(nil,'Buyer')};emit('MAIL_INBOX_UPDATE')
assert(#sales()==3,'confirmed absence followed by identical mail is a new sale')
local third=sales()[3].tradeExport
emit('PLAYER_LOGOUT');clock=clock+8;loadAddon();emit('MAIL_SHOW')
assert(#sales()==3 and sales()[3].tradeExport==third,'retired occurrence IDs cannot collide with a resumed live receipt')
-- Collection just before logout is visible in headers even before an inbox
-- update: do not persist a stale live-mail checkpoint.
rows={};emit('PLAYER_LOGOUT');assert(AZPCForeverDB.mailReloadCheckpoint==nil,'collected mail is not checkpointed')
-- Closing the mailbox as part of reload may precede PLAYER_LOGOUT.
rows={row('Silk','Buyer')};emit('MAIL_SHOW');local n=#sales();emit('MAIL_CLOSED');clock=clock+1;emit('PLAYER_LOGOUT')
assert(AZPCForeverDB.mailReloadCheckpoint,'immediate mailbox-close/logout preserves the validated receipt')
clock=clock+8;loadAddon();emit('MAIL_SHOW');assert(#sales()==n,'close-before-reload remains idempotent')
-- A closed mailbox checkpoint cannot be reused after unrelated play/logins.
emit('MAIL_CLOSED');clock=clock+20;emit('PLAYER_LOGOUT');assert(AZPCForeverDB.mailReloadCheckpoint==nil,'stale close evidence is not a future-sale identity')
print('PASS mailbox reload: 20-minute cached expiry, buyer hydration, empty load, repeated reloads, equal receipt occurrences, collection/absence, new equal sales and close/logout ordering')
