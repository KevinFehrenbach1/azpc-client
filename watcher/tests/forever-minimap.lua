local frames={};local textures=0;local combat=false;local calls={};local clock=1
local width,height,scale=1000,800,1
UIParent={GetWidth=function()return width end,GetHeight=function()return height end,GetEffectiveScale=function()return scale end};UISpecialFrames={};AZPCForeverDB={trades={{original=true}},minimap={angle=90}}
SlashCmdList={AZPCFOREVER=function(command)return 'existing:'..command end}
Minimap={GetWidth=function()return 140 end,GetHeight=function()return 140 end,GetFrameLevel=function()return 1 end,GetCenter=function()return 100,100 end,GetEffectiveScale=function()return 2 end}
function InCombatLockdown()return combat end;function GetCursorPosition()return 400,200 end;function GetTime()return clock end
AZPCForeverProfession={Show=function()calls.crafting=(calls.crafting or 0)+1 end}
AZPCForeverSyncStatus={Show=function()calls.sync=(calls.sync or 0)+1;return true end}
AZPCForeverSettings={Show=function()calls.settings=(calls.settings or 0)+1;return true end}
AZPCForeverSetup={Show=function()calls.setup=(calls.setup or 0)+1;return true end}
function CreateFrame(_,name)
 local f={name=name,scripts={},shown=true};frames[#frames+1]=f
 for _,method in ipairs({'SetMovable','RegisterEvent','SetSize','SetFrameStrata','SetFrameLevel','SetClampedToScreen','SetBackdrop','EnableMouse','RegisterForClicks','RegisterForDrag','SetHighlightTexture','SetText'})do f[method]=function()end end
 function f:SetScript(key,fn)self.scripts[key]=fn end
 function f:SetPoint(...)self.point={...}end;function f:ClearAllPoints()end
 function f:GetCenter()return self.centerX or 500,self.centerY or 400 end
 function f:GetEffectiveScale()return self.scale or 1 end
 function f:StartMoving()self.moving=true end;function f:StopMovingOrSizing()self.moving=false end
 function f:Show()self.shown=true end;function f:Hide()local was=self.shown;self.shown=false;if was and self.scripts.OnHide then self.scripts.OnHide()end end;function f:IsShown()return self.shown end
 function f:CreateFontString()return CreateFrame()end
 function f:CreateTexture()textures=textures+1;local t={};for _,m in ipairs({'SetAllPoints','SetTexture','SetSize','SetPoint','SetColorTexture','SetVertexColor'})do t[m]=function()end end;return t end
 return f
end
local file=assert(io.open('addons/forever/AZPCForever/AZPCForever.lua','r'));local source=file:read('*a');file:close()
assert((loadstring or load)(assert(source:match('%-%- BEGIN AZPC MINIMAP MENU\n(.-)%-%- END AZPC MINIMAP MENU'))))()
local m=AZPCForeverMinimap;assert(m.Initialize());local icon
for _,f in ipairs(frames)do if f.name=='AZPCForeverMinimapButton'then icon=f end end
assert(icon and icon.shown and icon.scripts.OnUpdate==nil,'no idle frame loop')
assert(math.abs(icon.point[4])<0.001 and math.abs(icon.point[5]-79)<0.001,'saved angle restored')
local created=textures;m.Initialize();m.SetHidden(false);assert(textures==created,'logo is built once')
assert(m.Invoke('crafting') and m.Invoke('sync') and m.Invoke('setup'));assert(calls.crafting==1 and calls.sync==1 and calls.setup==1)
assert(m.Invoke('settings')and calls.settings==1,'settings route opens panel')
assert(m.ToggleMenu());local menu
for _,f in ipairs(frames)do if f.name=='AZPCForeverMinimapMenu'then menu=f end end
assert(menu and menu.shown and menu.point[1]=='TOPRIGHT','initial menu stays beside icon')
menu.centerX=300;menu.centerY=240;menu.scripts.OnDragStart();assert(menu.moving);menu.scripts.OnDragStop()
assert(not menu.moving and AZPCForeverDB.minimap.menuPosition.x==0.3 and AZPCForeverDB.minimap.menuPosition.y==0.3,'shared account settings store normalized center')
m.ToggleMenu();assert(not menu.shown);width=2000;height=1600;m.ToggleMenu()
assert(menu.point[1]=='CENTER' and menu.point[4]==600 and menu.point[5]==480,'reopen adapts to screen dimensions')
menu.centerX=200;menu.centerY=160;menu.scale=2;menu.scripts.OnDragStart();menu:Hide()
assert(not menu.moving and AZPCForeverDB.minimap.menuPosition.x==0.2,'hide stops dragging and accounts for UI scale')
AZPCForeverDB.minimap.menuPosition={x=0/0,y=0.5};m.ToggleMenu();assert(menu.point[1]=='TOPRIGHT','invalid saved position falls back safely');m.ToggleMenu()
AZPCForeverDB.minimap.menuPosition={x=0.4,y=0.5}
-- Reinitialize the module as another character would, keeping account SavedVariables.
assert((loadstring or load)(assert(source:match('%-%- BEGIN AZPC MINIMAP MENU\n(.-)%-%- END AZPC MINIMAP MENU'))))()
m=AZPCForeverMinimap;m.Initialize();m.ToggleMenu()
for _,f in ipairs(frames)do if f.name=='AZPCForeverMinimapMenu'then menu=f end;if f.name=='AZPCForeverMinimapButton'then icon=f end end
assert(menu.point[4]==800 and menu.point[5]==800,'position survives module reload across characters')
combat=true;menu.scripts.OnDragStart();assert(not menu.moving,'combat cannot start dragging');combat=false
m.ToggleMenu()
icon.scripts.OnDragStart();assert(icon.scripts.OnUpdate);icon.scripts.OnUpdate();assert(AZPCForeverDB.minimap.angle==0,'drag uses effective minimap scale')
icon.scripts.OnDragStop();assert(icon.scripts.OnUpdate==nil);icon.scripts.OnClick();assert(not menu.shown,'drag release is not a menu click')
clock=2;icon.scripts.OnClick();assert(menu.shown)
assert(m.Invoke('hide'));assert(not icon.shown and AZPCForeverDB.minimap.hidden and not menu.shown)
assert(SlashCmdList.AZPCFOREVER('minimap show')==nil);assert(icon.shown and not AZPCForeverDB.minimap.hidden)
m.Command('minimap reset');assert(AZPCForeverDB.minimap.angle==225 and AZPCForeverDB.minimap.menuPosition==nil)
assert(m.SetAngle(-90));assert(AZPCForeverDB.minimap.angle==270);assert(not m.SetAngle(0/0))
combat=true;assert(not m.Invoke('crafting'));assert(calls.crafting==1);assert(not m.ToggleMenu());combat=false
assert(SlashCmdList.AZPCFOREVER('mail')=='existing:mail','other slash commands keep existing handlers')
assert(AZPCForeverDB.trades[1].original and #AZPCForeverDB.trades==1,'menu never edits captured history')
print('PASS minimap: provided logo built once, saved position, scaled drag, no idle loop, click/drag separation, menu routing, hide/restore/reset, combat and preserved history')
