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
assert(loadfile('addons/forever/AZPCForever/AZPCForeverSyncPrompt.lua'))()
assert(loadfile('addons/forever/AZPCForever/AZPCForever.lua'))('AZPCForever')
emit('MAIL_SHOW');flush();assert(#AZPCForeverDB.trades==1);assert(popups==0,'saved sale visible in mailbox must not prompt')
hooks.TakeInboxMoney(1);visible=false;money=1200;emit('PLAYER_MONEY');emit('MAIL_INBOX_UPDATE');flush();assert(popups==1,'real receipt capture must reach the collected-payout prompt');assert(#AZPCForeverDB.trades==1,'prompt must not duplicate or delete sale records')
print('PASS: live mailbox capture-to-collection reminder integration and record preservation')
