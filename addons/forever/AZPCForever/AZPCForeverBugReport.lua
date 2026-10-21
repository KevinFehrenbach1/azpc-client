-- AZPC Forever bug report helper. No network requests or automatic personal-data capture.
local panel
local function addonVersion()
 local fn=(C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
 if fn then return tostring(fn('AZPCForever','Version') or 'unknown') end
 return 'unknown'
end
local function makeEdit(parent,x,y,w,h,multi)
 local e=CreateFrame('EditBox',nil,parent,multi and nil or 'InputBoxTemplate')
 e:SetPoint('TOPLEFT',x,y);e:SetSize(w,h);e:SetAutoFocus(false)
 if multi then e:SetMultiLine(true);e:SetMaxLetters(1500);e:SetTextInsets(8,8,5,5) end
 e:SetScript('OnEscapePressed',function(self)self:ClearFocus()end)
 return e
end
local function show()
 if InCombatLockdown and InCombatLockdown() then print('AZPC: Open bug reports after combat.');return end
 if not panel then
  panel=CreateFrame('Frame','AZPCForeverBugReportWindow',UIParent,'BackdropTemplate')
  panel:SetSize(530,400);panel:SetPoint('CENTER');panel:SetFrameStrata('DIALOG')
  panel:SetMovable(true);panel:EnableMouse(true);panel:SetClampedToScreen(true)
  panel:RegisterForDrag('LeftButton')
  panel:SetScript('OnDragStart',function(self)if not InCombatLockdown or not InCombatLockdown() then self:StartMoving() end end)
  panel:SetScript('OnDragStop',function(self)self:StopMovingOrSizing()end)
  panel:SetBackdrop({bgFile='Interface/DialogFrame/UI-DialogBox-Background',edgeFile='Interface/DialogFrame/UI-DialogBox-Border',tile=true,tileSize=32,edgeSize=24,insets={left=7,right=7,top=7,bottom=7}})
  local title=panel:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');title:SetPoint('TOP',0,-22);title:SetText('AZPC - Report a Bug')
  local close=CreateFrame('Button',nil,panel,'UIPanelCloseButton');close:SetPoint('TOPRIGHT',-4,-4)
  local instruction=panel:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
  instruction:SetPoint('TOPLEFT',24,-61);instruction:SetText('Describe what happened and how to reproduce it:')
  local input=makeEdit(panel,25,-89,475,112,true)
  local descriptionBG=CreateFrame('Frame',nil,panel,'BackdropTemplate');descriptionBG:SetPoint('TOPLEFT',input,-7,7);descriptionBG:SetPoint('BOTTOMRIGHT',input,7,-7)
  descriptionBG:SetBackdrop({bgFile='Interface/Tooltips/UI-Tooltip-Background',edgeFile='Interface/Tooltips/UI-Tooltip-Border',tile=true,tileSize=16,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
  descriptionBG:SetBackdropColor(0.02,0.05,0.06,0.95);descriptionBG:SetFrameLevel(input:GetFrameLevel()-1)
  local outputLabel=panel:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');outputLabel:SetPoint('TOPLEFT',25,-225);outputLabel:SetText('Copy the report below, then paste it into a GitHub issue:')
  local output=makeEdit(panel,25,-251,475,42,false)
  output:SetScript('OnEscapePressed',function(self)self:ClearFocus()end)
  local link=makeEdit(panel,25,-319,475,25,false)
  link:SetText('https://github.com/KevinFehrenbach1/azpc-client/issues/new')
  local copy=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate');copy:SetSize(165,28);copy:SetPoint('BOTTOMLEFT',24,18);copy:SetText('Select Report Text')
  copy:SetScript('OnClick',function()
   local desc=input:GetText() or ''
   desc=desc:gsub('[\r\n]+',' '):sub(1,1500)
   output:SetText('AZPC Forever addon '..addonVersion()..' | Bug: '..desc)
   output:SetFocus();output:HighlightText()
  end)
  local help=panel:CreateFontString(nil,'OVERLAY','GameFontDisableSmall');help:SetPoint('BOTTOMRIGHT',-22,24)
  help:SetText('Ctrl+C to copy; paste into a new issue')
  panel.input=input;panel.output=output;panel.link=link
  if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]='AZPCForeverBugReportWindow' end
 end
 panel:Show()
 panel.output:SetText('AZPC Forever addon '..addonVersion()..' | Bug: ')
end
AZPCForeverBugReport={Show=show}
if SlashCmdList then
 local previous=SlashCmdList.AZPCFOREVER
 SlashCmdList.AZPCFOREVER=function(command)
  if (command or ''):lower():match('^%s*bug%s*$') then return show() end
  if previous then return previous(command) end
 end
end
