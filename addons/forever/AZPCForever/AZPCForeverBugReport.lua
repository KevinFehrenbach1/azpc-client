-- AZPC Forever bug reports: local-only, opt-in diagnostic summary.
local panel
local function addonVersion()
 local fn=(C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
 if fn then return tostring(fn('AZPCForever','Version') or 'unknown') end
 return 'unknown'
end
-- Scrollable multi-line text areas prevent long diagnostics from spilling over controls.
local function makeTextArea(parent,top,width,height,maxLetters)
 local bg=CreateFrame('Frame',nil,parent,'BackdropTemplate')
 bg:SetPoint('TOPLEFT',parent,'TOPLEFT',26,top)
 bg:SetSize(width,height)
 bg:SetBackdrop({bgFile='Interface/Tooltips/UI-Tooltip-Background',edgeFile='Interface/Tooltips/UI-Tooltip-Border',tile=true,tileSize=16,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
 bg:SetBackdropColor(0.02,0.05,0.06,0.94)
 local scroll=CreateFrame('ScrollFrame',nil,bg,'UIPanelScrollFrameTemplate')
 scroll:SetPoint('TOPLEFT',9,-8)
 scroll:SetPoint('BOTTOMRIGHT',-29,8)
 local edit=CreateFrame('EditBox',nil,scroll)
 edit:SetMultiLine(true)
 edit:SetAutoFocus(false)
 edit:SetFontObject('ChatFontNormal')
 edit:SetMaxLetters(maxLetters)
 edit:SetWidth(width-49)
 edit:SetHeight(height-16)
 edit:SetScript('OnEscapePressed',function(self)self:ClearFocus()end)
 edit:SetScript('OnTextChanged',function(self)
  local h=self:GetStringHeight()
  if h then self:SetHeight(math.max(height-16,h+20)) end
  scroll:UpdateScrollChildRect()
 end)
 scroll:SetScrollChild(edit)
 return edit
end
local function safeText(v,max)
 return tostring(v or ''):gsub('[\r\n|]',' '):sub(1,max or 120)
end
local function stamp(value)
 local n=tonumber(value)
 if not n or n<=0 then return 'Not available' end
 if type(date)=='function' then
  local ok,formatted=pcall(date,'%Y-%m-%d %H:%M',n)
  if ok and formatted then return formatted end
 end
 return tostring(math.floor(n))
end
local function diagnostics(includeCharacter)
 local lines={'Addon: AZPC Forever '..addonVersion(),'Game: Forever'}
 if GetBuildInfo then
  local ok,version,build=pcall(GetBuildInfo)
  if ok then lines[#lines+1]='WoW client: '..safeText(version,40)..' (build '..safeText(build,20)..')' end
 end
 if includeCharacter then
  local name=UnitName and UnitName('player') or nil
  local realm=GetRealmName and GetRealmName() or nil
  local faction=UnitFactionGroup and UnitFactionGroup('player') or nil
  lines[#lines+1]='Character: '..safeText(name or 'Unknown',60)
  lines[#lines+1]='Realm: '..safeText(realm or 'Unknown',80)
  lines[#lines+1]='Faction: '..safeText(faction or 'Unknown',40)
 else
  lines[#lines+1]='Character / realm / faction: excluded by player'
 end
 local w=AZPCForeverWatcherStatus
 if type(w)=='table' and w.schema==1 and tonumber(w.checkedAt) then
  local checked=tonumber(w.checkedAt)
  local now=(GetServerTime and GetServerTime()) or (time and time()) or 0
  local age=now-checked
  lines[#lines+1]='Watcher: '..((age>=0 and age<=120) and 'Recent saved check-in' or 'Saved check-in is stale or unverified')
  lines[#lines+1]='Watcher last check-in: '..stamp(checked)
  lines[#lines+1]='Last acknowledged upload: '..stamp(w.lastUploadAt)
 else
  lines[#lines+1]='Watcher: No saved check-in data'
  lines[#lines+1]='Last acknowledged upload: Not available'
 end
 lines[#lines+1]='Watcher status is a saved snapshot, not a live process check.'
 local db=AZPCForeverDB
 if type(db)=='table' and type(db.lastError)=='string' and db.lastError~='' then
  -- Never export arbitrary error text automatically: it may contain player names,
  -- paths, account details, or other private data.
  lines[#lines+1]='AZPC recorded error: Yes (details excluded for privacy)'
 else
  lines[#lines+1]='AZPC recorded error: None available'
 end
 return table.concat(lines,'\n')
end
local function show()
 if InCombatLockdown and InCombatLockdown() then print('AZPC: Open bug reports after combat.');return end
 if not panel then
  panel=CreateFrame('Frame','AZPCForeverBugReportWindow',UIParent,'BackdropTemplate')
  panel:SetSize(570,530)
  panel:SetPoint('CENTER')
  panel:SetFrameStrata('DIALOG')
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:SetClampedToScreen(true)
  panel:RegisterForDrag('LeftButton')
  panel:SetScript('OnDragStart',function(self)
   if not InCombatLockdown or not InCombatLockdown() then self:StartMoving() end
  end)
  panel:SetScript('OnDragStop',function(self)self:StopMovingOrSizing()end)
  panel:SetBackdrop({bgFile='Interface/DialogFrame/UI-DialogBox-Background',edgeFile='Interface/DialogFrame/UI-DialogBox-Border',tile=true,tileSize=32,edgeSize=24,insets={left=7,right=7,top=7,bottom=7}})
  local title=panel:CreateFontString(nil,'OVERLAY','GameFontNormalLarge')
  title:SetPoint('TOP',0,-22)
  title:SetText('AZPC - Report a Bug')
  local close=CreateFrame('Button',nil,panel,'UIPanelCloseButton')
  close:SetPoint('TOPRIGHT',-4,-4)
  local instruction=panel:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
  instruction:SetPoint('TOPLEFT',26,-62)
  instruction:SetText('Describe what happened and how to reproduce it:')
  local input=makeTextArea(panel,-89,518,104,1500)
  local check=CreateFrame('CheckButton',nil,panel,'UICheckButtonTemplate')
  check:SetPoint('TOPLEFT',23,-209)
  check:SetSize(26,26)
  check:SetChecked(false)
  local checkLabel=panel:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
  checkLabel:SetPoint('LEFT',check,'RIGHT',3,0)
  checkLabel:SetText('Include character name, realm and faction (optional)')
  local outputLabel=panel:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
  outputLabel:SetPoint('TOPLEFT',26,-249)
  outputLabel:SetText('Report preview - scroll to review before copying:')
  local output=makeTextArea(panel,-276,518,160,6000)
  local issueLabel=panel:CreateFontString(nil,'OVERLAY','GameFontDisableSmall')
  issueLabel:SetPoint('TOPLEFT',27,-449)
  issueLabel:SetText('Submit at: github.com/KevinFehrenbach1/azpc-client/issues/new')
  local copy=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate')
  copy:SetSize(168,28)
  copy:SetPoint('BOTTOMLEFT',26,19)
  copy:SetText('Select Report Text')
  local function report()
   local desc=(input:GetText() or ''):gsub('[\r\n]+',' '):sub(1,1500)
   return 'AZPC Forever bug report\nDescription: '..desc..'\n\nDiagnostics:\n'..diagnostics(check:GetChecked())
  end
  local function refresh()
   output:SetText(report())
  end
  copy:SetScript('OnClick',function()
   refresh()
   output:SetFocus()
   output:HighlightText()
  end)
  check:SetScript('OnClick',refresh)
  local help=panel:CreateFontString(nil,'OVERLAY','GameFontDisableSmall')
  help:SetPoint('BOTTOMRIGHT',-23,27)
  help:SetText('Ctrl+C to copy')
  panel.input=input
  panel.output=output
  panel.check=check
  panel.refresh=refresh
  if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]='AZPCForeverBugReportWindow' end
 end
 panel:Show()
 panel.check:SetChecked(false)
 panel.refresh()
end
AZPCForeverBugReport={Show=show,Diagnostics=diagnostics}
if SlashCmdList then
 local previous=SlashCmdList.AZPCFOREVER
 SlashCmdList.AZPCFOREVER=function(command)
  if (command or ''):lower():match('^%s*bug%s*$') then return show() end
  if previous then return previous(command) end
 end
end
