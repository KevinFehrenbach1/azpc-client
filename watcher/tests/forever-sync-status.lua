local frames={};local current=1000;local reloads=0
function UnitName()return 'Wet'end;function GetRealmName()return 'Classic Beta PvP 2'end
function GetServerTime()return current end;function InCombatLockdown()return false end
function ReloadUI()reloads=reloads+1 end
function CreateFrame(_,name)
 local f={scripts={},text='',name=name};frames[#frames+1]=f
 for _,method in ipairs({'RegisterEvent','SetSize','SetPoint','SetFrameStrata','SetClampedToScreen','SetBackdrop','EnableMouse','SetMovable','RegisterForDrag','SetWidth','SetJustifyH'})do f[method]=function()end end
 function f:SetScript(k,fn)self.scripts[k]=fn end
 function f:SetText(t)self.text=t end
 function f:SetEnabled(v)self.enabled=v end
 function f:Show()self.shown=true;if self.scripts.OnShow then self.scripts.OnShow(self)end end
 function f:Hide()self.shown=false end
 function f:CreateFontString()return CreateFrame()end
 return f
end
AZPCForeverDB={trades={{tradeExport='old'}},crafting={crafts={},materialEvents={},vendorEvents={}}}
local file=assert(io.open('addons/forever/AZPCForever/AZPCForever.lua','r'));local source=file:read('*a');file:close()
assert((loadstring or load)(assert(source:match('%-%- BEGIN AZPC SYNC DETAILS\n(.-)%-%- END AZPC SYNC DETAILS'))))()
local s=AZPCForeverSyncStatus;s.Initialize();assert(s.Counts().total==0)
local original=AZPCForeverDB.trades[1]
for _,kind in ipairs({'sell','expired','buy','inventory_snapshot','listing_snapshot'})do AZPCForeverDB.trades[#AZPCForeverDB.trades+1]={tradeExport='AZPCFTRADE|2|id|'..kind..'|2589|Cloth'}end
local identity={character='Wet',realm='Classic Beta PvP 2'}
AZPCForeverDB.crafting.crafts[1]=identity
AZPCForeverDB.crafting.materialEvents[1]={character='Wet',realm=identity.realm,kind='free'}
AZPCForeverDB.crafting.materialEvents[2]={character='Wet',realm=identity.realm,kind='inventory_observation'}
AZPCForeverDB.crafting.vendorEvents[1]={character='Wet',realm=identity.realm,kind='buy'}
local c=s.Counts();assert(c.sales==1 and c.returns==1 and c.purchases==2 and c.activity==2 and c.total==6)
assert(s.Counts().total==6,'repainting never duplicates session counts')
assert(AZPCForeverDB.trades[1]==original and #AZPCForeverDB.trades==6,'status preserves original evidence')
assert(s.CompactText():find('Reload to save',1,true))
assert(s.WatcherText(1000)=='No saved watcher status')
AZPCForeverWatcherStatus={schema=1,checkedAt=990,lastUploadAt=900,lastUploadCount=20}
local check,upload,detail=s.WatcherText(1000);assert(check=='Recent saved watcher check-in' and upload:find('Last acknowledged batch',1,true) and detail:find('not a live connection',1,true))
assert(s.WatcherText(1200)=='No recent saved watcher check-in','stale data never claims watcher is online')
assert(s.WatcherText(900)=='Saved check-in time could not be verified','clock skew cannot imply online')
assert(s.Show());local panel
for _,f in ipairs(frames)do if f.name=='AZPCForeverSyncWindow'then panel=f end end
assert(panel and panel.shown and reloads==0,'opening details never reloads automatically')
for _,f in ipairs(frames)do if f.text=='Reload to Save'then f.scripts.OnClick()end end
assert(reloads==1,'reload requires explicit click')
InCombatLockdown=function()return true end;assert(s.Show()==false)
for _,f in ipairs(frames)do if f.text=='Reload to Save'then f.scripts.OnClick()end end
assert(reloads==1,'combat prevents reload')
print('PASS sync details: incremental counts, excluded snapshots, unchanged evidence, no false upload/online claims, panel, explicit reload and combat guards')
