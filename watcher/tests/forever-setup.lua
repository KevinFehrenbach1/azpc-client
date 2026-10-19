local frames={};local combat=false;local clock=1000;local reloads=0
UIParent={};UISpecialFrames={};SlashCmdList={AZPCFOREVER=function(cmd)return 'existing:'..cmd end}
function UnitName()return 'Wet'end;function GetRealmName()return 'Classic Beta PvP 2'end;function UnitGUID()return 'Player-Wet'end
function GetServerTime()return clock end;function currentRegion()return 90 end
function InCombatLockdown()return combat end;function ReloadUI()reloads=reloads+1 end
function GetProfessions()return 1,2 end
function GetProfessionInfo(id)if id==1 then return 'Tailoring',nil,nil,nil,nil,nil,197 else return 'Leatherworking',nil,nil,nil,nil,nil,165 end end
function CreateFrame(_,name)
 local f={scripts={},name=name};frames[#frames+1]=f
 for _,method in ipairs({'RegisterEvent','SetSize','SetPoint','SetFrameStrata','SetClampedToScreen','SetBackdrop','EnableMouse','SetMovable','RegisterForDrag','SetWidth','SetJustifyH'})do f[method]=function()end end
 function f:SetScript(k,fn)self.scripts[k]=fn end
 function f:SetText(t)self.text=t end;function f:SetEnabled(v)self.enabled=v end
 function f:Show()self.shown=true;if self.scripts.OnShow then self.scripts.OnShow(self)end end
 function f:Hide()self.shown=false;if self.scripts.OnHide then self.scripts.OnHide(self)end end
 function f:CreateFontString()return CreateFrame()end
 return f
end
local file=assert(io.open('addons/forever/AZPCForever/AZPCForever.lua','r'));local source=file:read('*a');file:close()
local block=assert(source:match('%-%- BEGIN AZPC FIRST RUN SETUP\n(.-)%-%- END AZPC FIRST RUN SETUP'))
assert((loadstring or load)(block))();local s=AZPCForeverSetup
AZPCForeverDB={trades={},crafting={recipes={},materialEvents={}}}
local rows,state=s.Progress();assert(rows[1].done and not rows[2].done and not rows[3].done and not rows[4].done and not rows[5].done)
AZPCForeverDB.crafting.recipes.a={character='Other',realm='Classic Beta PvP 2',region=90,profession='Tailoring'}
assert(not s.Progress()[2].done,'another character cannot complete recipe setup')
AZPCForeverDB.crafting.recipes.b={character='Wet',realm='Classic Beta PvP 2',region=90,profession='Tailoring'}
assert(not s.Progress()[2].done,'one profession cannot complete both')
AZPCForeverDB.crafting.recipes.c={character='Wet',realm='Classic Beta PvP 2',region=90,profession='Leatherworking'}
assert(s.Progress()[2].done)
AZPCForeverDB.crafting.materialEvents[1]={character='Wet',realm='Classic Beta PvP 2',region=90,kind='inventory_observation',confirmation='bags_and_character_bank_observed'}
assert(s.Progress()[3].done)
AZPCForeverWatcherStatus={schema=1,lastUploadAt=900};rows=s.Progress();assert(rows[4].done and not rows[5].done,'old upload never confirms this setup session')
AZPCForeverWatcherStatus.lastUploadAt=1001;assert(s.Progress()[5].done)
local recipes=AZPCForeverDB.crafting.recipes;local material=AZPCForeverDB.crafting.materialEvents[1]
assert(s.Show());assert(reloads==0 and recipes==AZPCForeverDB.crafting.recipes and material==AZPCForeverDB.crafting.materialEvents[1])
local panel;for _,f in ipairs(frames)do if f.name=='AZPCForeverSetupWindow'then panel=f end end
panel:Hide();assert(state.dismissed);assert(s.Show(),'dismissed checklist can reopen manually')
assert(SlashCmdList.AZPCFOREVER('mail')=='existing:mail','other commands keep their handler')
combat=true;assert(s.Show()==false);for _,f in ipairs(frames)do if f.text=='Reload to Save'then f.scripts.OnClick()end end;assert(reloads==0)
combat=false;for _,f in ipairs(frames)do if f.text=='Reload to Save'then f.scripts.OnClick()end end;assert(reloads==1)
-- Existing ledgers do not trigger automatic onboarding, even on another character.
panel:Hide();AZPCForeverDB={trades={{tradeExport='original'}},crafting={}};s.MaybePrompt();assert(not panel.shown)
-- A fresh player gets one automatic prompt; dismissal persists in SavedVariables.
AZPCForeverDB={trades={},crafting={}};s.MaybePrompt();assert(panel.shown);panel:Hide();s.MaybePrompt();assert(not panel.shown)
assert(SlashCmdList.AZPCFOREVER('setup'));assert(panel.shown)
print('PASS setup: character/realm scope, each profession, confirmed bank, acknowledgement freshness, saved dismissal, existing-user protection, command routing, explicit reload and combat guards')
