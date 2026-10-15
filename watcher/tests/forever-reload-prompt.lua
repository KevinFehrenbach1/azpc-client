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
emit('MAIL_SHOW');p.MarkDirty();p.MarkDirty();flush();assert(#shown==1,'new sale/expiration batch prompts without closing mail')
local dialog=StaticPopupDialogs[shown[1]];assert(dialog.button1=='Reload now'and dialog.button2=='Later');assert(reloads==0,'never reload automatically')
observe({{'sale1',200}});hooks.TakeInboxMoney(1);money=1200;observe({});flush();assert(#shown==1,'collecting an already prompted receipt does not duplicate prompt')
p.MarkDirty();flush();assert(#shown==2,'another new record in the same mailbox visit prompts again after Later')
emit('MAIL_CLOSED');flush();assert(#shown==2,'close does not duplicate a prompt already shown')
emit('MAIL_SHOW');observe({});flush();assert(#shown==2,'reopening previously captured mail does not prompt')
combat=true;p.MarkDirty();flush();assert(#shown==2,'new expiration defers during combat')
combat=false;emit('PLAYER_REGEN_ENABLED');assert(#shown==3,'combat exit shows queued prompt')
combat=true;dialog.OnAccept();assert(reloads==0,'combat cannot trigger reload');combat=false;emit('PLAYER_REGEN_ENABLED');assert(#shown==4);dialog.OnAccept();assert(reloads==1,'explicit acceptance reloads')
print('PASS: every fresh sale/expiration batch prompts, repeated captures/collection do not duplicate, Later permits new events, combat deferral and explicit reload')
