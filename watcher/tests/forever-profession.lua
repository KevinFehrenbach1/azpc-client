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
 for _,method in ipairs({'SetSize','SetPoint','SetFrameStrata','SetBackdrop','SetBackdropColor','SetBackdropBorderColor','SetMovable','EnableMouse','RegisterForDrag','SetWidth','SetJustifyH','SetScrollChild','SetHeight','StartMoving','StopMovingOrSizing','SetID','SetAutoFocus','SetMaxLetters','SetFrameLevel','ClearFocus','SetAlpha','SetFontString','SetTextColor','SetVertexColor','SetFontObject','SetNumeric','SetTextInsets','ClearAllPoints','SetFont','SetShadowColor','SetShadowOffset'})do w[method]=function()end end
 function w:SetPoint(point,relative)assert(relative~=self,'a frame must never anchor to itself')end
 function w:SetText(value)self.text=value end
 function w:GetText()return self.text or ''end
 function w:GetFrameLevel()return 1 end
 function w:GetScript(event)return self.scripts[event]end
 function w:HookScript(event,fn)local old=self.scripts[event];self.scripts[event]=function(...)if old then old(...)end;fn(...)end end
 function w:CreateTexture()local t=widget();function t:SetTexture(v)self.texture=v end;return t end
 function w:SetEnabled(value)self.enabled=value end
 function w:SetScript(event,fn)self.scripts[event]=fn end
 function w:Show()self.shown=true end
 function w:Hide()self.shown=false end
 function w:IsShown()return self.shown end
 function w:CreateFontString()return widget()end
 return w
end
function CreateFrame(_,name,parent,template)
 local w=widget();if name then _G[name]=w end
 if template=='AuctionHouseFrameDisplayModeTabTemplate'then
  parent.Tabs[#parent.Tabs+1]=w
  -- Native template registration happens before the rest of the page exists.
  -- Profession data can still arrive during construction.
  assert(AZPCForeverCraftingPage and not AZPCForeverCraftingPage.profession)
  local ok,err=pcall(function()
   local empty=AZPCForeverProfession.Catalog()
   -- Exercise the guarded browser refresh via catalog capture below.
   local previousCatalog=AZPCForeverDB.professionCatalog
   C_TradeSkillUI={GetBaseProfessionInfo=function()return {professionName='Tailoring'}end,GetRecipeInfo=function()return {name='Test',learned=true}end}
   AZPCForeverProfession.CaptureCatalog({1})
   AZPCForeverDB.professionCatalog=previousCatalog
   C_TradeSkillUI=nil
  end)
  assert(ok,err)
 end
 return w
end
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
local buyHint
function AuctionHouseFrame:CreateFontString()buyHint=widget();return buyHint end
emit('TRADE_SKILL_SHOW')
assert(AZPCForeverProfessionPanel==nil,'profession opening must not create a floating panel')
emit('AUCTION_HOUSE_SHOW')
p.Show()
local panel=AZPCForeverProfessionPanel
assert(panel and panel:IsShown()and panel.rows[1].material.itemId==2589)
assert(AuctionHouseFrame.Tabs[5]==AZPCForeverCraftingPage.tabButton,'register after existing addon tabs')
assert(AuctionHouseFrame.title=='AZPC Crafting')
assert(panel.rows[1].button.enabled==false,'Buy stays disabled when the recipe already has enough material')
held[2589]=0;emit('AUCTION_HOUSE_SHOW')
assert(panel.rows[1].button.enabled==true,'missing material becomes searchable at AH')
local oldCalls=calls;panel.rows[1].button.scripts.OnClick();assert(calls==oldCalls,'unsupported buying must not fall back to Blizzard search')
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
assert(p.SearchAll());assert(p.Quote(recipe,1).ahCost==410,'new scan retains the completed summary')
full=false;results={{itemKey={itemID=2589},minPrice=250,totalQuantity=100}};emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
assert(p.Quote(recipe,1).ahCost==410 and p.Quote(recipe,1).salePrice==600,'partial scan cannot blank or mix summary prices')
results[#results+1]={itemKey={itemID=2320},minPrice=20,totalQuantity=100};results[#results+1]={itemKey={itemID=2996},minPrice=700,totalQuantity=10};full=true
emit('AUCTION_HOUSE_BROWSE_RESULTS_ADDED')
assert(p.Quote(recipe,1).ahCost==520 and p.Quote(recipe,1).salePrice==700 and p.Quote(recipe,1).ahProfit==145,'completed scan replaces all summary prices')
assert(p.SearchAll());for _,fn in ipairs(timeouts)do fn()end
assert(p.Quote(recipe,1).ahCost==520,'failed scan preserves last completed values')
emit('AUCTION_HOUSE_CLOSED');emit('AUCTION_HOUSE_SHOW');assert(p.Quote(recipe,1).ahCost==520,'AH reopen preserves recipe summary')
assert(p.Quote(recipe,3).ahCost==1560,'retained prices still scale with craft quantity')
local originalRealm=GetRealmName;GetRealmName=function()return 'Other realm'end
assert(p.Quote(recipe,1).ahCost==nil,'completed quote cannot cross realm scope');GetRealmName=originalRealm
assert(p.SearchAll());results={{itemKey={itemID=2589},minPrice=200,totalQuantity=100},{itemKey={itemID=2320},minPrice=10,totalQuantity=100},{itemKey={itemID=2996},minPrice=600,totalQuantity=10}};emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
print('PASS: persistent summary during scans and AH reopen, completed snapshot replacement, failed-scan retention, batch recalculation and market isolation')

assert(panel.cost.text:find('UI-SilverIcon',1,true)and panel.cost.text:find('UI-CopperIcon',1,true)and panel.sale.text:find('UI-SilverIcon',1,true),'summary cards show compact native silver/copper icons')
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
assert(page.profession.text:find('Tailoring',1,true)and page.recipeRows[1].recipe.name=='Linen Bag')
page.search:SetText('does not exist');page.search:GetScript('OnTextChanged')(page.search)
assert(page.empty.text=='No matching recipes.')
page.search:SetText('');page.search:GetScript('OnTextChanged')(page.search)
assert(page.recipeRows[1].recipe.name=='Linen Bag')
assert(#AuctionHouseFrame.Tabs==5,'refreshing page must not duplicate the native AH tab')
print('PASS: persistent multi-profession catalog, learned-only capture, unsupported recipes, literal search, linked/character/realm isolation, browser selection and native tab registration')


held[2589]=1;emit('AUCTION_HOUSE_SHOW')
assert(panel.rows[1].button.text=='Buy')

-- The redesigned page exposes one scan action, distinct columns and editable quantity.
assert(panel.materialsTab==nil and panel.ahTab==nil,'redundant tabs removed')
assert(panel.searchAll.text=='Scanning…','recipe selection starts the existing scanner')
emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
assert(panel.searchAll.text=='Scan prices')
assert(panel.rows[1].need and panel.rows[1].bags and panel.rows[1].missing and panel.rows[1].unit and panel.rows[1].total,'material quantities and prices use separate columns')
panel.batch:SetText('3');panel.batch:GetScript('OnEnterPressed')(panel.batch)
assert(panel.rows[1].need.text==6 and panel.cards[3].title.text=='Est. profit / batch')
panel.batch:SetText('0');panel.batch:GetScript('OnEnterPressed')(panel.batch)
assert(panel.rows[1].need.text==2 and panel.cards[3].title.text=='Est. profit / craft','batch clamp preserves cost basis')
panel.plus:GetScript('OnClick')();assert(panel.rows[1].need.text==4)
panel.minus:GetScript('OnClick')();assert(panel.rows[1].need.text==2)
page.search:SetText('linen');page.search:GetScript('OnTextChanged')(page.search)
assert(not page.placeholder:IsShown(),'search hint disappears while typing')
page.search:SetText('');page.search:GetScript('OnTextChanged')(page.search);assert(page.placeholder:IsShown())
print('PASS: unified scan action, aligned quantity/price fields, editable batch and search placeholder')

assert(AZPCForeverCraftingPage.professionArrow,'profession dropdown uses a native texture instead of an unsupported glyph')
assert(panel.iconBorder and panel.cards[1].azpcSheen,'item framing and card surface details are present')
assert(not panel.cost.text:find('UI-GoldIcon',1,true),'small values omit zero gold denomination')
print('PASS: native dropdown arrow, framed item header, card surface details and compact coin denominations')

-- Buying requests quotes; only a user confirmation submits an order.
local quotes={}
local depthID,depthRows,depthFull=2589,{{quantity=2,unitPrice=200},{quantity=98,unitPrice=220}},true
C_AuctionHouse.SendSearchQuery=function(key)depthID=key.itemID end
C_AuctionHouse.GetNumCommoditySearchResults=function()return #depthRows end
C_AuctionHouse.GetCommoditySearchResultInfo=function(id,i)assert(id==depthID);return depthRows[i]end
C_AuctionHouse.HasFullCommoditySearchResults=function()return depthFull end
C_AuctionHouse.SearchForItemKeys=function(keys)assert(#keys==1)end
C_AuctionHouse.ConfirmCommoditiesPurchase=function()end
AuctionHouseFrame.BuyDialog=widget();AuctionHouseFrame.BuyDialog:Hide()
function AuctionHouseFrame:StartCommoditiesPurchase()error('must never hand off to Blizzard buy UI')end
function AuctionHouseFrame:SelectBrowseResult()error('must never navigate to Blizzard listings')end
C_AuctionHouse.StartCommoditiesPurchase=function(id,n)quotes[#quotes+1]={id=id,n=n}end
C_AuctionHouse.CancelCommoditiesPurchase=function()end
C_AuctionHouse.GetItemKeyInfo=function()return {isCommodity=true}end
full=true;ready=true;held[2589]=1;held[2320]=2
results={{itemKey={itemID=2589},minPrice=200,totalQuantity=100}}
assert(p.BuyMissing(recipe,3));p.OpenQueuedQuote()
assert(#quotes==0,'browse results must not request restricted purchase quotes')
p.PurchaseEvent('COMMODITY_SEARCH_RESULTS_ADDED',2320);assert(not p.ReviewPurchase(),'ignore unrelated material results')
emit('COMMODITY_SEARCH_RESULTS_RECEIVED')
assert(#quotes==0,'depth results only prepare purchase; hardware click requests quote')
assert(p.ReviewPurchase())
assert(not AuctionHouseFrame.BuyDialog:IsShown(),'requesting a quote keeps Blizzard buy UI hidden')
assert(#quotes==1 and quotes[1].id==2589 and quotes[1].n==5,'batch three subtracts one owned cloth')
assert(p.Pending(2589)==0,'requesting a quote is not a purchase')
assert(not p.BuyMissing(recipe,3),'second click cannot replace a live quote')
queryHooks.ConfirmCommoditiesPurchase(2589,5)
assert(p.Pending(2589)==5,'submitted order is reserved before asynchronous result')
p.PurchaseEvent('COMMODITY_PURCHASE_SUCCEEDED');AuctionHouseFrame.BuyDialog:Hide()
timeouts[#timeouts]()
results={{itemKey={itemID=2320},minPrice=10,totalQuantity=100}};depthRows={{quantity=100,unitPrice=10}};p.OpenQueuedQuote()
emit('COMMODITY_SEARCH_RESULTS_RECEIVED');assert(p.ReviewPurchase())
assert(#quotes==2 and quotes[2].id==2320 and quotes[2].n==1,'queue advances to missing thread')
queryHooks.ConfirmCommoditiesPurchase(2320,1);p.PurchaseEvent('COMMODITY_PURCHASE_FAILED');AuctionHouseFrame.BuyDialog:Hide()
assert(p.Pending(2320)==0 and p.Pending(2589)==5,'failure releases only its own reservation')
assert(p.BuyMissing(recipe,3));results={{itemKey={itemID=2320},minPrice=10,totalQuantity=100}};p.OpenQueuedQuote()
emit('COMMODITY_SEARCH_RESULTS_RECEIVED');assert(p.ReviewPurchase())
assert(quotes[#quotes].id==2320,'awaiting cloth is not bought twice')
p.CancelBuying();AuctionHouseFrame.BuyDialog:Hide()
held[2589]=6;p.PurchaseEvent('BAG_UPDATE_DELAYED');assert(p.Pending(2589)==0,'bag arrival clears delivery reservation')
held[2589]=0;assert(p.BuyMissing(recipe,1));results={{itemKey={itemID=2589},minPrice=200,totalQuantity=1}};depthRows={{quantity=1,unitPrice=200}};p.OpenQueuedQuote()
emit('COMMODITY_SEARCH_RESULTS_RECEIVED');assert(not p.ReviewPurchase())
assert(#quotes==3,'short supply never submits a partial order')
p.CancelBuying()
print('PASS: scaled purchase queue, native live quote, explicit confirmation, pending delivery, repeat-click and failed/short-supply guards')

-- An unresponsive quote must not strand a disabled native dialog.
p.CancelBuying();depthRows={{quantity=100,unitPrice=200}}
assert(p.BuyMissing(recipe,1));p.OpenQueuedQuote();emit('COMMODITY_SEARCH_RESULTS_RECEIVED');assert(p.ReviewPurchase())
assert(not AuctionHouseFrame.BuyDialog:IsShown());timeouts[#timeouts]();assert(p.Pending(2589)==0,'missing quote times out without a reservation')
print('PASS: detail search before quote, price-depth total, click-only quote request and disabled-dialog timeout')

print('PASS: payload-free Forever RECEIVED event reaches the queue through the registered event frame')

-- The quantity/price confirmation opens itself, without a separate Review click.
local popup,confirmed=nil,0
StaticPopupDialogs={}
function StaticPopup_Show(key,text,_,data)popup={key=key,text=text,data=data};return popup end
function StaticPopup_Hide()popup=nil end
function GetMoney()return 100000 end
function AuctionHouseFrame.BuyDialog:BuyNow()error('must never use native BuyNow')end
C_AuctionHouse.ConfirmCommoditiesPurchase=function(id,n)confirmed=confirmed+1;queryHooks.ConfirmCommoditiesPurchase(id,n)end
held[2589]=0;held[2320]=2;depthRows={{quantity=100,unitPrice=200}}
results={{itemKey={itemID=2589},minPrice=200,totalQuantity=100}}
assert(p.BuyMissing(recipe,1));p.OpenQueuedQuote();emit('COMMODITY_SEARCH_RESULTS_RECEIVED')
assert(popup and popup.text:find('Buy 2 Linen Cloth?',1,true),'quantity popup opens from results without another review click')
assert(popup.text:find('Maximum total:',1,true),'consent shows maximum spend')
local shown=popup;local before=#quotes
StaticPopupDialogs[shown.key].OnAccept(nil,shown.data)
assert(#quotes==before+1 and confirmed==0,'Buy click requests quote, never buys before a live price')
p.PurchaseEvent('COMMODITY_PRICE_UPDATED',200,400);timeouts[#timeouts]()
assert(confirmed==1 and p.Pending(2589)==2,'live quote within displayed maximum completes the explicitly approved purchase')
p.PurchaseEvent('COMMODITY_PURCHASE_FAILED');AuctionHouseFrame.BuyDialog:Hide()
assert(p.Pending(2589)==0)
assert(p.BuyMissing(recipe,1));p.OpenQueuedQuote();emit('COMMODITY_SEARCH_RESULTS_RECEIVED')
shown=popup;StaticPopupDialogs[shown.key].OnAccept(nil,shown.data)
p.PurchaseEvent('COMMODITY_PRICE_UPDATED',200,400);local confirmLater=timeouts[#timeouts]
p.PurchaseEvent('COMMODITY_PRICE_UPDATED',250,500);confirmLater()
assert(confirmed==1 and popup and popup.data.target.total==500,'price increase cancels delayed confirmation and opens updated AZPC consent')
assert(not AuctionHouseFrame.BuyDialog:IsShown(),'price changes keep Blizzard UI hidden')
p.CancelBuying();AuctionHouseFrame.BuyDialog:Hide();assert(popup==nil,'Stop dismisses the pending popup')
assert(p.BuyMissing(recipe,1));p.OpenQueuedQuote();emit('COMMODITY_SEARCH_RESULTS_RECEIVED')
shown=popup;before=#quotes;StaticPopupDialogs[shown.key].OnCancel(nil,shown.data)
assert(#quotes==before and confirmed==1 and popup==nil,'Cancel never requests a quote or buys')
print('PASS: automatic quantity popup, explicit capped consent, live quote required, price increase guard and cancellation')

-- A row Buy uses the same AZPC queue and current bag math.
held[2589]=1;local before=#quotes
assert(p.Buy({itemId=2589,needed=6,missing=999}));p.OpenQueuedQuote();emit('COMMODITY_SEARCH_RESULTS_RECEIVED')
assert(popup and popup.data.target.quantity==5 and #quotes==before,'single Buy subtracts current bags and prompts inside AZPC')
assert(AuctionHouseFrame.displayMode~=AuctionHouseFrameDisplayMode.Buy,'purchase flow does not navigate away from AZPC')
p.CancelBuying()
print('PASS: direct auction APIs, AZPC-only purchase and repricing UI, single-row quantity buying with no native handoff')

-- Explicit recipe selection scans once; passive refresh and guarded states do not.
C_AuctionHouse.SearchForItemKeys=function()grouped=grouped+1 end
local beforeSelection=grouped
p.Select(recipe)
assert(grouped==beforeSelection+1,'recipe click automatically scans prices')
p.Show();assert(grouped==beforeSelection+1,'rendering must not repeat the automatic scan')
ready=false;p.Select(recipe);assert(grouped==beforeSelection+1,'automatic scan respects AH throttle');ready=true
InCombatLockdown=function()return true end
p.Select(recipe);assert(grouped==beforeSelection+1,'automatic scan respects combat guard')
InCombatLockdown=function()return false end
emit('AUCTION_HOUSE_CLOSED');p.Select(recipe)
assert(grouped==beforeSelection+1,'recipe selection outside AH never queries')
print('PASS: recipe selection automatic scan, passive refresh and existing safety guards')

-- A throttled selection must resume without a second click and only for the latest recipe.
emit('AUCTION_HOUSE_SHOW')
local selectedOutput
C_AuctionHouse.SearchForItemKeys=function(keys)grouped=grouped+1;selectedOutput=keys[#keys].itemID end
ready=false;p.Select(recipe)
local waitingCount=grouped
assert(panel.searchAll.text=='Waiting for AH…','queued scan has visible waiting state')
emit('AUCTION_HOUSE_THROTTLED_SYSTEM_READY')
assert(grouped==waitingCount,'ready event cannot bypass actual throttle state')
local other={name='Other recipe',recipeId=2,materialsKnown=true,outputItemId=999,reagents=recipe.reagents}
p.Select(other);ready=true;emit('AUCTION_HOUSE_THROTTLED_SYSTEM_READY')
assert(grouped==waitingCount+1 and selectedOutput==999,'only the most recent recipe scans when AH becomes ready')
emit('AUCTION_HOUSE_THROTTLED_SYSTEM_READY')
assert(grouped==waitingCount+1,'duplicate ready events never repeat the scan')
ready=false;p.Select(recipe);emit('AUCTION_HOUSE_CLOSED');ready=true
emit('AUCTION_HOUSE_SHOW');emit('AUCTION_HOUSE_THROTTLED_SYSTEM_READY')
assert(grouped==waitingCount+1,'closing AH clears deferred work across reopen')
ready=false;p.Select(recipe);queryHooks.SendBrowseQuery();ready=true
emit('AUCTION_HOUSE_THROTTLED_SYSTEM_READY')
assert(grouped==waitingCount+1,'an external search cancels deferred scans')
ready=false;p.Select(recipe);ready=true;assert(p.SearchAll(recipe))
assert(grouped==waitingCount+2);emit('AUCTION_HOUSE_THROTTLED_SYSTEM_READY')
assert(grouped==waitingCount+2,'manual scan supersedes deferred scan')
print('PASS: deferred recipe scan readiness, latest selection, one-shot dispatch and cancellation')
