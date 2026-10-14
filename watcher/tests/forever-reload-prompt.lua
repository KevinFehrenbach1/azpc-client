local frames,hooks,timers,shown={},{},{},{}
local money,combat,reloads=1000,false,0
StaticPopupDialogs={}
function StaticPopup_Show(key) shown[#shown+1]=key end
function ReloadUI() reloads=reloads+1 end
function GetMoney() return money end
function InCombatLockdown() return combat end
function TakeInboxMoney() end
function hooksecurefunc(name,fn) hooks[name]=fn end
C_Timer={After=function(_,fn)timers[#timers+1]=fn end}
function CreateFrame()local f={events={}};frames[#frames+1]=f;function f:RegisterEvent(e)self.events[e]=true end;function f:SetScript(_,fn)self.handler=fn end;return f end
local function emit(event)for _,f in ipairs(frames)do if f.events[event]then f.handler(f,event)end end end
local function flush()local current=timers;timers={};for _,fn in ipairs(current)do fn()end end
local file=assert(io.open('addons/forever/AZPCForever/AZPCForever.lua','r'));local source=file:read('*a');file:close();local reminder=assert(source:match('%-%- BEGIN AZPC SALE SYNC REMINDER\n(.-)%-%- END AZPC SALE SYNC REMINDER'));assert((loadstring or load)(reminder))()
local p=AZPCForeverSyncPrompt
local function observe(sales)p.BeginCapture();for i,sale in ipairs(sales)do p.ObserveSale(i,sale[1],sale[2])end;p.EndCapture()end
emit('MAIL_SHOW');observe({{'sale1',200},{'sale2',300}});flush();assert(#shown==0,'opening captured sales must not prompt')
hooks.TakeInboxMoney(1);emit('PLAYER_MONEY');flush();assert(#shown==0,'failed collection must not prompt')
hooks.TakeInboxMoney(2);money=1500;emit('PLAYER_MONEY');flush();assert(#shown==0,'money alone must not prompt while both receipts remain')
observe({});flush();assert(#shown==1,'multiple collected sales should produce one reminder')
local dialog=StaticPopupDialogs[shown[1]];assert(dialog.button1=='Reload now'and dialog.button2=='Later');assert(dialog.text:find('watcher must be running and connected',1,true));assert(reloads==0,'a reminder must never reload automatically')
observe({{'sale3',100}});hooks.TakeInboxMoney(1);money=1600;observe({});flush();assert(#shown==1,'Later must not nag again during the same mailbox visit')
dialog.OnAccept();assert(reloads==1,'only the explicit Reload now action reloads')
emit('MAIL_CLOSED');emit('MAIL_SHOW');observe({});hooks.TakeInboxMoney(1);money=1700;emit('PLAYER_MONEY');flush();assert(#shown==1,'unknown/non-sale mail must not prompt')
observe({{'sale4',100}});hooks.TakeInboxMoney(1);observe({});flush();assert(#shown==1,'receipt removal without money confirmation must not prompt')
combat=true;money=1800;emit('PLAYER_MONEY');flush();assert(#shown==1,'defer the popup during combat');combat=false;emit('PLAYER_REGEN_ENABLED');assert(#shown==2,'show deferred reminder after combat')
combat=true;dialog.OnAccept();assert(reloads==1,'do not reload if combat began while popup was open');combat=false;emit('PLAYER_REGEN_ENABLED');assert(#shown==3);dialog.OnAccept();assert(reloads==2)
print('PASS: confirmed collection only, batch debounce, Later without nagging, combat deferral and explicit reload')

emit('MAIL_CLOSED');emit('MAIL_SHOW');p.MarkDirty();flush();assert(#shown==3,'new records should not interrupt mailbox browsing')
emit('MAIL_CLOSED');flush();assert(#shown==4,'new expiration data must prompt when closing mailbox')
emit('MAIL_SHOW');emit('MAIL_CLOSED');flush();assert(#shown==4,'already acknowledged records must not nag again')
emit('MAIL_SHOW');p.MarkDirty();combat=true;emit('MAIL_CLOSED');flush();assert(#shown==4);combat=false;emit('PLAYER_REGEN_ENABLED');assert(#shown==5,'mailbox-close fallback must defer during combat')
