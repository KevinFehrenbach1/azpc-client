local frames,timers,combat,reloads,popups={},{},false,0,0
UIParent={};UISpecialFrames={};SlashCmdList={AZPCFOREVER=function(cmd)return 'old:'..cmd end}
function InCombatLockdown()return combat end
function ReloadUI()reloads=reloads+1 end
C_Timer={After=function(_,fn)timers[#timers+1]=fn end}
StaticPopupDialogs={};function StaticPopup_Show()popups=popups+1 end
function CreateFrame(_,name)
 local f={name=name,scripts={},events={}};frames[#frames+1]=f;if name then _G[name]=f end
 for _,m in ipairs({'SetSize','SetFrameStrata','SetClampedToScreen','EnableMouse','SetMovable','RegisterForDrag','SetBackdrop','SetWidth','SetJustifyH','ClearAllPoints','StopMovingOrSizing','StartMoving'})do f[m]=function()end end
 function f:SetPoint(...)self.point={...}end
 function f:SetText(v)self.text=v end
 function f:RegisterEvent(e)self.events[e]=true end
 function f:SetScript(e,fn)self.scripts[e]=fn end
 function f:SetChecked(v)self.checked=v end;function f:GetChecked()return self.checked end
 function f:Show()self.shown=true;if self.scripts.OnShow then self.scripts.OnShow(self)end end
 function f:Hide()self.shown=false end
 function f:CreateFontString()return CreateFrame()end
 return f
end
local file=assert(io.open('addons/forever/AZPCForever/AZPCForever.lua'));local source=file:read('*a');file:close()
local function install(marker)assert((loadstring or load)(assert(source:match('%-%- BEGIN '..marker..'\n(.-)%-%- END '..marker))))()end
local function flush()local q=timers;timers={};for _,fn in ipairs(q)do fn()end end
install('AZPC USER SETTINGS');local s=AZPCForeverSettings
assert(s.Get('tooltips')=='compact'and s.Get('ownership')==true and s.Get('reminders')=='popup','existing behavior is default without DB')
AZPCForeverDB={trades={{original=true}}};assert(s.Get('ownership'))
assert(not s.Set('tooltips','bad')and not s.Set('ownership',1)and not s.Set('invalid',true))
assert(s.Set('tooltips','detailed')and s.Set('ownership',false));assert(s.Get('tooltips')=='detailed'and not s.Get('ownership'))
install('AZPC USER SETTINGS');s=AZPCForeverSettings;assert(s.Get('tooltips')=='detailed'and not s.Get('ownership'),'account preferences survive character/module reload')
assert(SlashCmdList.AZPCFOREVER('mail')=='old:mail');assert(SlashCmdList.AZPCFOREVER('settings'));assert(AZPCForeverSettingsWindow.shown)
local checkbox;for _,f in ipairs(frames)do if f.scripts.OnClick and f.GetChecked and not f.text then checkbox=f end end
assert(checkbox);checkbox.checked=true;checkbox.scripts.OnClick(checkbox);assert(s.Get('ownership'),'checkbox updates preference')
combat=true;assert(not s.Show()and not s.ResetPositions()and not s.Notify());combat=false
install('AZPC SALE SYNC REMINDER')
local p=AZPCForeverSyncPrompt;p.MarkDirty();flush();assert(popups==1,'default popup remains')
s.Set('reminders','notification');p.MarkDirty();flush();assert(popups==1 and AZPCForeverReloadNotice.shown,'notification replaces popup')
assert(reloads==0);local reloadButton;for _,f in ipairs(frames)do if f.text=='Reload to Save'then reloadButton=f end end
assert(reloadButton);combat=true;reloadButton.scripts.OnClick();assert(reloads==0);combat=false;reloadButton.scripts.OnClick();assert(reloads==1)
s.Set('reminders','both');p.MarkDirty();flush();assert(popups==2 and AZPCForeverReloadNotice.shown)
combat=true;p.MarkDirty();flush();assert(popups==2);combat=false
for _,f in ipairs(frames)do if f.events.PLAYER_REGEN_ENABLED then f.scripts.OnEvent(f,'PLAYER_REGEN_ENABLED')end end
assert(popups==3,'chosen reminders still defer in combat')
s.Set('reminders','popup');assert(not AZPCForeverReloadNotice.shown)
local reset=0;AZPCForeverMinimap={Command=function(cmd)assert(cmd=='minimap reset');reset=reset+1 end}
assert(s.ResetPositions());assert(reset==1 and AZPCForeverSettingsWindow.point[1]=='CENTER' and AZPCForeverReloadNotice.point[1]=='TOP')
assert(AZPCForeverDB.trades[1].original and #AZPCForeverDB.trades==1,'settings never modify history')
print('PASS settings: defaults, validation, account persistence, controls, command routing, popup/notification/both, combat, explicit reload, reset and immutable history')
