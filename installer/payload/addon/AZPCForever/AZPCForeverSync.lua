-- Read-only presentation of session activity. Never rebuilds costs or captures mail.
AZPCForeverSyncStatus={}
local status=AZPCForeverSyncStatus
local cursors,counts={}, {sales=0,returns=0,purchases=0,activity=0}
local initialized=false
local function lists()
 local d=AZPCForeverDB or {};local c=d.crafting or {}
 return {trades=d.trades or {},crafts=c.crafts or {},materials=c.materialEvents or {},vendor=c.vendorEvents or {}}
end
local function belongs(row)
 return row.character==(UnitName and UnitName('player') or '') and row.realm==(GetRealmName and GetRealmName() or '')
end
function status.Initialize()
 if initialized then return end
 for kind,rows in pairs(lists())do cursors[kind]=#rows end
 initialized=true
end
function status.Counts()
 status.Initialize()
 for kind,rows in pairs(lists())do
  local first=cursors[kind] or 0
  if #rows<first then first=#rows end
  for i=first+1,#rows do
   local row=rows[i]
   if kind=='trades' then
    local action=row.tradeExport and row.tradeExport:match('^AZPCFTRADE|%d+|[^|]*|([^|]*)|')
    if action=='sell' then counts.sales=counts.sales+1 elseif action=='expired' then counts.returns=counts.returns+1 elseif action=='buy' then counts.purchases=counts.purchases+1 end
   elseif belongs(row) then
    if kind=='crafts' or kind=='materials' and row.kind=='free' then counts.activity=counts.activity+1
    elseif kind=='vendor' and row.kind=='buy' then counts.purchases=counts.purchases+1 end
   end
  end
  cursors[kind]=#rows
 end
 return {sales=counts.sales,returns=counts.returns,purchases=counts.purchases,activity=counts.activity,total=counts.sales+counts.returns+counts.purchases+counts.activity}
end
function status.CompactText()
 local c=status.Counts()
 if c.total==0 then return 'Auction data recorded.\n\nReload to save it so your watcher can sync it to AZPC.' end
 return c.sales..' sale(s), '..c.returns..' return(s), '..c.purchases..' purchase(s), '..c.activity..' loot/craft record(s) captured.\n\nReload to save for AZPC. Your watcher must be running.'
end
local function stamp(at)
 if type(at)~='number' or at<=0 then return 'No confirmed upload available' end
 return type(date)=='function' and date('%b %d, %I:%M %p',at) or tostring(at)
end
function status.WatcherText(now)
 local s=AZPCForeverWatcherStatus
 if type(s)~='table' or s.schema~=1 or type(s.checkedAt)~='number' then return 'No saved watcher status','Open AZPC Launcher to check your watcher.','Status becomes available after a reload.' end
 local age=now-s.checkedAt
 local check=age<0 and 'Saved check-in time could not be verified' or age<=120 and 'Recent saved watcher check-in' or 'No recent saved watcher check-in'
 local upload=type(s.lastUploadAt)=='number' and s.lastUploadAt>0 and 'This PC - Last acknowledged batch:\n'..stamp(s.lastUploadAt) or 'No confirmed upload available'
 return check,upload,'Last known status at '..stamp(s.checkedAt)..'\nLoaded at login/reload; this is not a live connection.'
end
local panel,labels,reload
local function combat()return type(InCombatLockdown)=='function' and InCombatLockdown()end
local function refresh()
 if not panel then return end
 local c=status.Counts()
 labels.summary:SetText(c.total>0 and c.total..' captured activity record(s) ready to save' or 'No new trade activity this session')
 for key,label in pairs(labels.counts)do label:SetText(tostring(c[key]))end
 labels.note:SetText(c.total>0 and 'New activity is not saved to disk until reload/logout.' or 'Saved records may still be queued. Check the last acknowledged batch below.')
 local now=GetServerTime and GetServerTime() or time();local check,upload,detail=status.WatcherText(now)
 labels.check:SetText(check);labels.upload:SetText(upload);labels.detail:SetText(detail)
 reload:SetEnabled(c.total>0 and not combat())
end
function status.Show()
 if combat() then if print then print('AZPC: Open sync details after combat.')end;return false end
 if not panel then
  panel=CreateFrame('Frame','AZPCForeverSyncWindow',UIParent,BackdropTemplateMixin and 'BackdropTemplate' or nil)
  panel:SetSize(620,440);panel:SetPoint('CENTER');panel:SetFrameStrata('DIALOG');panel:SetClampedToScreen(true)
  if panel.SetBackdrop then panel:SetBackdrop({bgFile='Interface\\DialogFrame\\UI-DialogBox-Background',edgeFile='Interface\\DialogFrame\\UI-DialogBox-Border',tile=true,tileSize=32,edgeSize=24,insets={left=7,right=7,top=7,bottom=7}})end
  panel:EnableMouse(true);panel:SetMovable(true);panel:RegisterForDrag('LeftButton');panel:SetScript('OnDragStart',panel.StartMoving);panel:SetScript('OnDragStop',panel.StopMovingOrSizing)
  local function text(value,x,y,width,font)
   local f=panel:CreateFontString(nil,'OVERLAY',font or 'GameFontHighlight');f:SetPoint('TOPLEFT',x,y);f:SetWidth(width);f:SetJustifyH('LEFT');f:SetText(value);return f
  end
  text('|cff54dbd1AZPC|r  |  Sync Status',26,-26,550,'GameFontNormalLarge')
  text((UnitName and UnitName('player') or '')..'  -  '..(GetRealmName and GetRealmName() or ''),26,-55,560,'GameFontHighlightSmall')
  local close=CreateFrame('Button',nil,panel,'UIPanelCloseButton');close:SetPoint('TOPRIGHT',-4,-4)
  labels={counts={}};labels.summary=text('',26,-91,568,'GameFontNormalLarge')
  text('CAPTURED THIS SESSION',26,-135,275,'GameFontNormal');text('LAST KNOWN WATCHER STATUS',325,-135,265,'GameFontNormal')
  local rows={{'Auction sales','sales'},{'Expired / returned','returns'},{'Purchases','purchases'},{'Loot & crafts','activity'}}
  for i,row in ipairs(rows)do local y=-165-(i-1)*32;text(row[1],26,y,220);labels.counts[row[2]]=text('0',270,y,35)end
  labels.check=text('',325,-166,260);labels.upload=text('',325,-208,260,'GameFontHighlightSmall');labels.detail=text('',325,-247,260,'GameFontDisableSmall')
  labels.note=text('',26,-315,568,'GameFontNormalSmall')
  reload=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate');reload:SetSize(270,34);reload:SetPoint('BOTTOMLEFT',55,51);reload:SetText('Reload to Save');reload:SetScript('OnClick',function()if not combat() and type(ReloadUI)=='function' then ReloadUI()end end)
  local later=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate');later:SetSize(160,34);later:SetPoint('LEFT',reload,'RIGHT',16,0);later:SetText('Later');later:SetScript('OnClick',function()panel:Hide()end)
  text('Reload saves locally. Your watcher then uploads to your AZPC account.',26,-404,570,'GameFontDisableSmall')
  panel:SetScript('OnShow',refresh);local elapsed=0;panel:SetScript('OnUpdate',function(_,dt)elapsed=elapsed+dt;if elapsed>=1 then elapsed=0;refresh()end end)
  if type(UISpecialFrames)=='table' then UISpecialFrames[#UISpecialFrames+1]='AZPCForeverSyncWindow'end
 end
 panel:Show();refresh();return true
end
local events=CreateFrame('Frame');events:RegisterEvent('ADDON_LOADED');events:SetScript('OnEvent',function(_,_,name)if name=='AZPCForever' then status.Initialize()end end)
