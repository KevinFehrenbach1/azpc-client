local events,moneyNow,held,combat={},1792000000,{[2589]=5,[2320]=2},false
function CreateFrame()local f={};function f:RegisterEvent(e)self[e]=true end;function f:SetScript(_,fn)self.handler=fn end;events[#events+1]=f;return f end
function GetRealmName()return 'Classic Beta PvP 2'end
function UnitName()return 'Phillip'end
function UnitFactionGroup()return 'Horde'end
function GetServerTime()return moneyNow end
function GetItemCount(id,bank)assert(bank==false);return held[id]end
function GetItemInfo(id)return ({[2589]='Linen Cloth',[2320]='Coarse Thread'})[id]end
function InCombatLockdown()return combat end
local function currentRegion()return 90 end
local function number(v)local n=tonumber(v);if n and n>=0 then return math.floor(n)end end
AZPCForeverDB={crafting={costing={positions={
 {itemId=2589,character='Phillip',realm='Classic Beta PvP 2',faction='horde',region=90,quantity=5,totalCopper=100,costComplete=true},
 {itemId=2320,character='Phillip',realm='Classic Beta PvP 2',faction='horde',region=90,quantity=2,totalCopper=20,costComplete=true}
}}},tooltipPrices={['90|classic beta pvp 2|horde']={[2996]={unitCopper=100,observedAt=moneyNow}}}}
local f=assert(io.open('addons/forever/AZPCForever/AZPCForever.lua'));local source=f:read('*a');f:close()
local block=assert(source:match('%-%- BEGIN AZPC PROFESSION PANEL\n(.-)%-%- END AZPC PROFESSION PANEL'))
assert((loadstring or load)('return function(currentRegion,number)'..block..'end'))()(currentRegion,number)
local p=AZPCForeverProfession
assert(p.Model(nil,1).cost==nil,'no recipe must display No data, never zero cost')
local recipe={name='Test',recipeId=1,materialsKnown=true,outputItemId=2996,outputMin=1,outputMax=1,reagents={{itemId=2589,quantity=2},{itemId=2320,quantity=1}}}
local m=p.Model(recipe,1);assert(m.cost==50 and m.profit==45);assert(m.rows[1].missing==0)
m=p.Model(recipe,3);assert(m.rows[1].needed==6 and m.rows[1].missing==1 and m.rows[2].missing==1);assert(m.cost==nil and m.profit==nil,'missing stock has no recorded purchase cost')
m=p.Model(recipe,0);assert(m.batch==1);m=p.Model(recipe,10000);assert(m.batch==999)
recipe.materialsKnown=false;assert(p.Model(recipe,1).profit==nil);recipe.materialsKnown=true
moneyNow=moneyNow+21601;assert(p.Model(recipe,1).profit==nil);moneyNow=moneyNow-21601
AZPCForeverDB.crafting.costing.positions[1].character='Other';assert(p.Model(recipe,1).cost==nil);AZPCForeverDB.crafting.costing.positions[1].character='Phillip'
held[2589]=nil;assert(p.Model(recipe,1).rows[1].missing==nil);held[2589]=5
local calls,name=0,nil
AuctionHouseFrame={SearchBar={SetSearchText=function(_,v)name=v end,StartSearch=function()calls=calls+1 end}}
assert(p.Search({itemId=2589})==false and calls==0,'no queries away from AH')
local function emit(event)for _,e in ipairs(events)do if e[event]then e.handler(e,event)end end end
emit('AUCTION_HOUSE_SHOW');assert(calls==0,'opening AH must not search automatically')
assert(p.Search({itemId=2589}) and calls==1 and name=='Linen Cloth','one explicit search')
combat=true;assert(not p.Search({itemId=2589}) and calls==1);combat=false
C_AuctionHouse={IsThrottledMessageSystemReady=function()return false end};assert(not p.Search({itemId=2589}) and calls==1);C_AuctionHouse=nil
emit('AUCTION_HOUSE_CLOSED');assert(not p.Search({itemId=2589})and calls==1)
local called
TradeSkillFrame={DetailsFrame={selectedRecipeID=123}}
AZPCForeverCrafting={ReadRecipe=function(id)called=id;return recipe end}
assert(p.ReadSelection()==recipe and called==123)
TradeSkillFrame=nil;ProfessionsFrame={CraftingPage={SchematicForm={recipeInfo={recipeID=456}}}}
assert(p.ReadSelection()==recipe and called==456)
ProfessionsFrame.CraftingPage.SchematicForm={currentRecipeInfo={recipeID=789}}
assert(p.ReadSelection()==recipe and called==789,'Forever uses currentRecipeInfo')
ProfessionsFrame.CraftingPage.SchematicForm={GetRecipeInfo=function()return {recipeID=790}end}
assert(p.ReadSelection()==recipe and called==790,'prefer the schematic public getter')
print('PASS: batch math, missing quantities, unknown/stale profit, character isolation, recipe selection and explicit guarded AH searches')
-- Exercise the real panel construction and controls, not just its calculations.
UIParent={}
local function widget()
 local w={scripts={},shown=true}
 for _,method in ipairs({'SetSize','SetPoint','SetFrameStrata','SetBackdrop','SetBackdropColor','SetBackdropBorderColor','SetMovable','EnableMouse','RegisterForDrag','SetWidth','SetJustifyH','SetScrollChild','SetHeight','StartMoving','StopMovingOrSizing','SetID','SetAutoFocus','SetMaxLetters','SetFrameLevel','ClearFocus'})do w[method]=function()end end
 function w:SetText(value)self.text=value end
 function w:GetText()return self.text or ''end
 function w:GetFrameLevel()return 1 end
 function w:GetScript(event)return self.scripts[event]end
 function w:CreateTexture()local t=widget();function t:SetTexture(v)self.texture=v end;return t end
 function w:SetEnabled(value)self.enabled=value end
 function w:SetScript(event,fn)self.scripts[event]=fn end
 function w:Show()self.shown=true end
 function w:Hide()self.shown=false end
 function w:IsShown()return self.shown end
 function w:CreateFontString()return widget()end
 return w
end
function CreateFrame(_,name)local w=widget();if name then _G[name]=w end;return w end
UISpecialFrames={}
-- Load a selected recipe through an event, then render the UI.
AuctionHouseFrame.Tabs={widget(),widget(),widget(),widget()}
AuctionHouseFrame.tabsForDisplayMode={}
AuctionHouseFrameDisplayMode={Buy={'BrowseResultsFrame'}}
local modeChanges=0
function AuctionHouseFrame:SetDisplayMode(mode)
 modeChanges=modeChanges+1
 local show=mode==AuctionHouseFrameDisplayMode.AZPCCrafting
 if AZPCForeverCraftingPage then if show then AZPCForeverCraftingPage:Show()else AZPCForeverCraftingPage:Hide()end end
end
function AuctionHouseFrame:GetName()return 'AuctionHouseFrame'end
function AuctionHouseFrame:SetTitle(value)self.title=value end
emit('TRADE_SKILL_SHOW')
assert(AZPCForeverProfessionPanel==nil,'profession opening must not create a floating panel')
emit('AUCTION_HOUSE_SHOW')
p.Show()
local panel=AZPCForeverProfessionPanel
assert(panel and panel:IsShown()and panel.rows[1].material.itemId==2589)
assert(AuctionHouseFrame.Tabs[5]==AZPCForeverCraftingPage.tabButton,'register after existing addon tabs')
assert(AuctionHouseFrame.title=='AZPC Crafting')
assert(panel.rows[1].button.enabled==true,'material search is available in AH crafting tab')
held[2589]=0;emit('AUCTION_HOUSE_SHOW')
assert(panel.rows[1].button.enabled==true,'missing material becomes searchable at AH')
panel.rows[1].button.scripts.OnClick();assert(calls==2 and name=='Linen Cloth')
p.Show();assert(panel.cost.text:find('No data',1,true)and panel.profit.text:find('No data',1,true))
print('PASS: panel construction, selected recipe rendering, missing-stock UI and search button action')
-- Grouped recipe shopping uses exact item IDs and complete, fresh search results.
local grouped,results,full,more,ready=0,{},true,0,true
local timeouts={}
C_Timer={After=function(_,fn)timeouts[#timeouts+1]=fn end}
C_AuctionHouse={
 MakeItemKey=function(id)return {itemID=id,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0}end,
 IsThrottledMessageSystemReady=function()return ready end,
 SearchForItemKeys=function(keys,sorts)
  grouped=grouped+1;assert(#keys==3 and sorts[1].sortOrder==0)
  local ids={};for _,key in ipairs(keys)do ids[key.itemID]=true end
  assert(ids[2589]and ids[2320]and ids[2996],'search all materials plus crafted output')
 end,
 GetBrowseResults=function()return results end,
 HasFullBrowseResults=function()return full end,
 RequestMoreBrowseResults=function()more=more+1 end,
}
assert(p.SearchAll() and grouped==1)
assert(p.Quote(recipe,1).ahCost==nil,'no estimate from stale cache while search pending')
results={{itemKey={itemID=2589},minPrice=200,totalQuantity=100},{itemKey={itemID=2320},minPrice=10,totalQuantity=100}}
full=false;emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
assert(more==1 and p.Quote(recipe,1).ahCost==nil,'wait for complete browse results')
results[#results+1]={itemKey={itemID=2996},minPrice=600,totalQuantity=10};full=true
emit('AUCTION_HOUSE_BROWSE_RESULTS_ADDED')
local q=p.Quote(recipe,1)
assert(q.ahCost==410 and q.missingCost==400 and q.ahProfit==160,'full recipe cost and only-missing cost are distinct')
assert(p.Quote(recipe,3).ahCost==1230,'batch cost updates without another query')
assert(panel.cost.text:find('Est. full material AH cost:',1,true))
assert(p.SearchAll());results={{itemKey={itemID=2589},minPrice=200,totalQuantity=100}}
emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');assert(p.Quote(recipe,1).ahCost==nil,'missing material price cannot become zero')
assert(p.SearchAll());results={{itemKey={itemID=2589},minPrice=200,totalQuantity=1},{itemKey={itemID=2320},minPrice=10,totalQuantity=100}}
emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');assert(p.Quote(recipe,1).ahCost==nil,'insufficient listings must not produce a full cost')
assert(p.SearchAll());results={{itemKey={itemID=999},minPrice=1,totalQuantity=100}}
emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');assert(p.Quote(recipe,1).ahCost==nil,'unrelated results rejected')
assert(p.SearchAll());for _,fn in ipairs(timeouts)do fn()end;assert(p.Quote(recipe,1).ahCost==nil,'timeout cannot reuse prior scan')
ready=false;assert(not p.SearchAll());ready=true
emit('AUCTION_HOUSE_CLOSED');assert(not p.SearchAll())
print('PASS: grouped exact-ID search, complete result paging, full/missing/batch AH cost, output margin, unavailable/short/unrelated/timeout/throttle/closed guards')
emit('AUCTION_HOUSE_SHOW')
local queryHooks={}
function hooksecurefunc(_,method,fn)queryHooks[method]=fn end
C_AuctionHouse.SendBrowseQuery=function()end
assert(p.SearchAll());queryHooks.SendBrowseQuery()
results={{itemKey={itemID=2589},minPrice=200,totalQuantity=100},{itemKey={itemID=2320},minPrice=10,totalQuantity=100},{itemKey={itemID=2996},minPrice=600,totalQuantity=10}}
emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');assert(p.Quote(recipe,1).ahCost==nil,'external queries invalidate pending scan even when item IDs overlap')
assert(p.SearchAll());emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');assert(p.Quote(recipe,1).ahCost==410)
moneyNow=moneyNow+21601;assert(p.Quote(recipe,1).ahCost==nil,'old completed quote cannot stay current forever')
print('PASS: external query interruption and quote age guard')
-- Learned catalogs are persisted per character/realm/faction and profession.
local base='Leatherworking'
C_TradeSkillUI={
 GetBaseProfessionInfo=function()return {professionName=base}end,
 GetRecipeInfo=function(id)return {recipeID=id,name=id==10 and 'Leather Bag' or id==11 and 'Unresolved Leather Recipe' or id==20 and 'Linen Bag' or 'Unlearned',learned=id~=12}end,
}
local function saved(id)
 return {recipeId=id,name=id==10 and 'Leather Bag' or 'Linen Bag',profession=base,character='Phillip',realm='Classic Beta PvP 2',faction='horde',region=90,materialsKnown=true,outputItemId=2996,outputMin=1,outputMax=1,reagents={{itemId=2589,quantity=2},{itemId=2320,quantity=1}}}
end
AZPCForeverCrafting.ReadRecipe=function(id)if id~=11 then return saved(id)end end
p.CaptureCatalog({10,11,12})
local rows,professions=p.Catalog();assert(#rows==2 and #professions==1 and professions[1]=='Leatherworking')
assert(rows[2].materialsKnown==false,'unsupported learned recipes remain visible without invented reagents')
p.CaptureCatalog({10,11,12});assert(#p.Catalog()==2,'reopening a profession must not duplicate catalog')
base='Tailoring';p.CaptureCatalog({20});rows,professions=p.Catalog();assert(#rows==3 and #professions==2,'multiple professions survive closing their windows')
assert(#p.Catalog('Tailoring','linen')==1 and #p.Catalog('Leatherworking','linen')==0)
assert(#p.Catalog(nil,'[')==0,'recipe search is literal, not a Lua pattern')
C_TradeSkillUI.IsTradeSkillLinked=function()return true end;p.CaptureCatalog({99});assert(#p.Catalog()==3,'linked profession must not overwrite own recipes');C_TradeSkillUI.IsTradeSkillLinked=nil
function UnitName()return 'Other'end;assert(#p.Catalog()==0,'another character must never see this character catalog')
function UnitName()return 'Phillip'end
local realmBefore=GetRealmName;function GetRealmName()return 'Other realm'end;assert(#p.Catalog()==0);GetRealmName=realmBefore
local page=AZPCForeverCraftingPage
page:GetScript('OnShow')()
assert(page.recipeRows[1].recipe.name=='Leather Bag','saved recipes sort by name')
page.recipeRows[1]:GetScript('OnClick')()
assert(panel.name.text=='Leather Bag','recipe browser selection drives pricing panel without opening profession')
page.menuRows[3]:GetScript('OnClick')()
assert(page.profession.text=='Tailoring'and page.recipeRows[1].recipe.name=='Linen Bag')
page.search:SetText('does not exist');page.search:GetScript('OnTextChanged')(page.search)
assert(page.empty.text=='No matching recipes.')
page.search:SetText('');page.search:GetScript('OnTextChanged')(page.search)
assert(page.recipeRows[1].recipe.name=='Linen Bag')
assert(#AuctionHouseFrame.Tabs==5,'refreshing page must not duplicate the native AH tab')
print('PASS: persistent multi-profession catalog, learned-only capture, unsupported recipes, literal search, linked/character/realm isolation, browser selection and native tab registration')
