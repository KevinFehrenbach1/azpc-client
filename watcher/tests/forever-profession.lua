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
 for _,method in ipairs({'SetTexCoord','SetSize','SetPoint','SetFrameStrata','SetBackdrop','SetBackdropColor','SetBackdropBorderColor','SetMovable','EnableMouse','RegisterForDrag','SetWidth','SetJustifyH','SetScrollChild','SetHeight','StartMoving','StopMovingOrSizing','SetID','SetAutoFocus','SetMaxLetters','SetFrameLevel','ClearFocus','SetAlpha','SetFontString','SetTextColor','SetVertexColor','SetFontObject','SetNumeric','SetTextInsets','ClearAllPoints','SetFont','SetShadowColor','SetShadowOffset'})do w[method]=function()end end
 function w:SetPoint(point,relative)assert(relative~=self,'a frame must never anchor to itself')end
 function w:SetFont(_,size)self.fontSize=size end
 function w:SetWordWrap(value)self.wordWrap=value end
 function w:SetHeight(value)self.height=value end
 function w:SetText(value)self.text=value end
 function w:GetText()return self.text or ''end
 function w:GetFrameLevel()return 1 end
 function w:GetScript(event)return self.scripts[event]end
 function w:HookScript(event,fn)local old=self.scripts[event];self.scripts[event]=function(...)if old then old(...)end;fn(...)end end
 function w:CreateTexture()local t=widget();function t:SetTexture(v)self.texture=v end;return t end
 function w:SetChecked(value)self.checked=value end
 function w:GetChecked()return self.checked end
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
 self.displayMode=mode
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
local atBeforePartial=p.Quote(recipe,1).quoteAt
full=false;results={{itemKey={itemID=2589},minPrice=250,totalQuantity=100}};emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
assert(p.Quote(recipe,1).quoteAt==atBeforePartial,'partial loading preserves timestamp of displayed prices')
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
local fresh=p.Quote(recipe,1);assert(fresh.quoteAt and fresh.pricedMaterials==2 and fresh.materialCount==2 and fresh.outputPriced)
local label,complete=p.PriceStatus(fresh,moneyNow);assert(label=='Updated just now'and complete)
label,complete=p.PriceStatus(fresh,moneyNow+720);assert(label=='Scanned 12m ago'and complete)
label,complete=p.PriceStatus(fresh,moneyNow+21601);assert(label:find('(stale)',1,true)and not complete)
label,complete=p.PriceStatus(fresh,moneyNow-1);assert(not complete and label:find('unknown',1,true))
assert(p.PriceStatus({},moneyNow)=='No price scan yet')
local partial={quoteAt=moneyNow,pricedMaterials=1,materialCount=2,outputPriced=true,shortMaterials=0}
label,complete=p.PriceStatus(partial,moneyNow);assert(not complete and label:find('1/2 materials priced',1,true))
partial.pricedMaterials=2;partial.outputPriced=false;label,complete=p.PriceStatus(partial,moneyNow);assert(not complete and label:find('output price missing',1,true))
partial.outputPriced=true;partial.shortMaterials=1;label,complete=p.PriceStatus(partial,moneyNow);assert(not complete and label:find('limited AH stock',1,true))
local queriesBeforeAge=grouped;local savedQuoteAt=p.Quote(recipe,1).quoteAt
moneyNow=moneyNow+720;panel:GetScript('OnUpdate')(panel,15)
assert(panel.market.text:find('12m ago',1,true),'visible label ages without another query or full panel rerender')
assert(grouped==queriesBeforeAge and p.Quote(recipe,1).quoteAt==savedQuoteAt,'age update cannot change scan evidence')
moneyNow=moneyNow-720
print('PASS price status: completed timestamp, relative age, stale/future guards, missing materials/output, limited stock, visible aging and no price queries')
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
assert(panel.iconBorder and panel.cards[1].azpcSheen,'three bordered summary cards are restored')
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

-- Reproduce the screenshot: first complete response omits thread, follow-up supplies it.
ready=true;p.Select(recipe)
local firstCount=grouped
results={{itemKey={itemID=2589},minPrice=200,totalQuantity=100},{itemKey={itemID=2996},minPrice=600,totalQuantity=10}}
ready=false;emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
assert(grouped==firstCount and p.Quote(recipe,1).ahCost==nil,'missing prices remain unknown while AH is throttled')
ready=true;emit('AUCTION_HOUSE_THROTTLED_SYSTEM_READY')
assert(grouped==firstCount+1,'one follow-up search is sent when ready')
results={{itemKey={itemID=2320},minPrice=10,totalQuantity=100}}
full=false;emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
assert(p.Quote(recipe,1).ahCost==nil,'follow-up pages are not published prematurely')
full=true;emit('AUCTION_HOUSE_BROWSE_RESULTS_ADDED')
assert(p.Quote(recipe,1).ahCost==410 and p.Quote(recipe,1).salePrice==600,'follow-up fills missing thread and preserves same-scan leather and output')
emit('AUCTION_HOUSE_THROTTLED_SYSTEM_READY');emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
assert(grouped==firstCount+1,'follow-up is strictly bounded to one query')

p.Select(recipe);firstCount=grouped
results={{itemKey={itemID=2589},minPrice=250,totalQuantity=100}}
emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');assert(grouped==firstCount+1)
results={};emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
assert(p.Quote(recipe,1).ahCost==nil and p.Quote(recipe,1).salePrice==nil,'genuinely absent listings cannot reuse an older recipe quote')
assert(grouped==firstCount+1,'empty follow-up never loops')

p.Select(recipe);firstCount=grouped;ready=false
results={{itemKey={itemID=2589},minPrice=200,totalQuantity=100}}
emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');queryHooks.SendBrowseQuery()
ready=true;emit('AUCTION_HOUSE_THROTTLED_SYSTEM_READY')
assert(grouped==firstCount,'external search cancels a waiting follow-up')
p.Select(recipe);firstCount=grouped;ready=false;emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
emit('AUCTION_HOUSE_CLOSED');ready=true;emit('AUCTION_HOUSE_SHOW');emit('AUCTION_HOUSE_THROTTLED_SYSTEM_READY')
assert(grouped==firstCount,'AH close cancels a waiting follow-up')
print('PASS: missing recipe price recovery, paged follow-up, same-scan evidence, no invented prices, one retry and cancellation')

-- Native item tooltips are confined to item areas and resolve reused rows dynamically.
local tooltipOwner,tooltipLink,tooltipShown
GameTooltip={
 SetOwner=function(_,owner)tooltipOwner=owner end,
 SetHyperlink=function(_,link)tooltipLink=link end,
 Show=function()tooltipShown=true end,
 Hide=function()tooltipShown=false end,
 IsOwned=function(_,owner)return tooltipOwner==owner end,
}
local beforeHover=grouped
panel.itemHover:GetScript('OnEnter')(panel.itemHover)
assert(tooltipLink=='item:'..recipe.outputItemId and tooltipShown,'output header shows native item tooltip')
panel.itemHover:GetScript('OnLeave')(panel.itemHover);assert(not tooltipShown)
local materialRow=panel.rows[1]
materialRow.itemHover:GetScript('OnEnter')(materialRow.itemHover)
assert(tooltipLink=='item:'..materialRow.material.itemId and tooltipShown,'material name/icon shows current row item')
local oldMaterial=materialRow.material;materialRow.material={itemId=999}
materialRow.itemHover:GetScript('OnEnter')(materialRow.itemHover)
assert(tooltipLink=='item:999','reused hover region reads latest material')
materialRow.material=oldMaterial
local recipeButton=page.recipeRows[1]
recipeButton:GetScript('OnEnter')(recipeButton)
assert(tooltipLink=='item:'..recipeButton.recipe.outputItemId,'recipe browser shows output item')
materialRow.itemHover:GetScript('OnHide')(materialRow.itemHover)
assert(tooltipShown,'hiding another row cannot hide a different tooltip owner')
recipeButton:GetScript('OnHide')(recipeButton);assert(not tooltipShown,'hidden item row releases tooltip')
assert(grouped==beforeHover,'hovering never sends an AH query')
GameTooltip=nil;assert(pcall(panel.itemHover:GetScript('OnEnter'),panel.itemHover),'missing tooltip API is harmless')
for _,card in ipairs(panel.cards)do
 assert(card.value.fontSize==16 and card.value.wordWrap==false and card.value.height==24,'compact one-line values stay clear of helper text')
end
print('PASS: output/material/recipe tooltips, dynamic reused rows, ownership, passive hover and compact non-wrapping summary values')

-- Profession shortcut is separate from Auctionator and resolves the current selection at click time.
emit('AUCTION_HOUSE_CLOSED');emit('TRADE_SKILL_CLOSE')
local shortcutRecipe={name='Selected Woolen Bag',recipeId=3757,profession='Tailoring',materialsKnown=true,outputItemId=4240,outputMin=1,outputMax=1,reagents=recipe.reagents}
local otherShortcut={name='Selected Leather Item',recipeId=999,profession='Leatherworking',materialsKnown=true,outputItemId=999,outputMin=1,outputMax=1,reagents=recipe.reagents}
local liveRecipe=shortcutRecipe
InCombatLockdown=function()return combat end
ProfessionsFrame=widget();ProfessionsFrame.CraftingPage={SchematicForm=widget()}
function ProfessionsFrame.CraftingPage.SchematicForm:GetRecipeInfo()return liveRecipe and {recipeID=liveRecipe.recipeId}end
AZPCForeverCrafting.ReadRecipe=function(id)if liveRecipe and id==liveRecipe.recipeId then return liveRecipe end end
local auctionatorSearch=widget();local auctionatorClicks=0
auctionatorSearch:SetScript('OnClick',function()auctionatorClicks=auctionatorClicks+1 end)
ProfessionsFrame.AuctionatorSearchButton=auctionatorSearch
local auctionatorHandler=auctionatorSearch:GetScript('OnClick')
emit('TRADE_SKILL_SHOW')
assert(not ProfessionsFrame.AZPCCraftSearchButton,'profession opening away from AH adds no visible shortcut')
emit('AUCTION_HOUSE_SHOW')
local shortcut=assert(ProfessionsFrame.AZPCCraftSearchButton)
assert(shortcut:IsShown() and shortcut.enabled and shortcut.text=='AZPC Craft Search')
local beforeShortcut=grouped
shortcut:GetScript('OnClick')()
assert(AuctionHouseFrame.displayMode==AuctionHouseFrameDisplayMode.AZPCCrafting and panel.name.text==shortcutRecipe.name,'shortcut opens AZPC tab on exact profession selection')
assert(grouped==beforeShortcut+1,'shortcut uses guarded automatic price scan once')
assert(page.search:GetText()=='' and page.profession.text=='Tailoring','shortcut clears conflicting browser search/profession filters')
liveRecipe=otherShortcut;shortcut:GetScript('OnClick')()
assert(panel.name.text==otherShortcut.name and page.profession.text=='Leatherworking','shortcut reads newly selected recipe at click time')
assert(ProfessionsFrame.AuctionatorSearchButton==auctionatorSearch and auctionatorSearch:GetScript('OnClick')==auctionatorHandler and auctionatorClicks==0,'AZPC leaves Auctionator controls and handlers untouched')
combat=true;emit('TRADE_SKILL_LIST_UPDATE');assert(not shortcut.enabled)
local combatCount=grouped;shortcut:GetScript('OnClick')();assert(grouped==combatCount,'shortcut never queries during combat');combat=false
liveRecipe=nil;emit('TRADE_SKILL_LIST_UPDATE');assert(not shortcut.enabled,'no profession selection disables shortcut')
liveRecipe=shortcutRecipe;emit('TRADE_SKILL_CLOSE');assert(not shortcut:IsShown())
emit('TRADE_SKILL_SHOW');assert(shortcut:IsShown(),'shortcut returns when both windows open')
emit('AUCTION_HOUSE_CLOSED');assert(not shortcut:IsShown())
local closedCount=grouped;shortcut:GetScript('OnClick')();assert(grouped==closedCount,'AH closure makes even a stale click harmless')
-- Legacy details windows use the same isolated shortcut path.
ProfessionsFrame:Hide();TradeSkillFrame=widget();TradeSkillFrame.DetailsFrame=widget();TradeSkillFrame.DetailsFrame.selectedRecipeID=shortcutRecipe.recipeId
emit('AUCTION_HOUSE_SHOW');assert(TradeSkillFrame.AZPCCraftSearchButton and TradeSkillFrame.AZPCCraftSearchButton:IsShown())
TradeSkillFrame.AZPCCraftSearchButton:GetScript('OnClick')();assert(panel.name.text==shortcutRecipe.name)
print('PASS: profession Craft Search exact recipe, AH-only visibility, filter reset, selection changes, combat/no-selection/closed guards and isolated Auctionator/legacy controls')

-- Open Recipe delegates exact recipe navigation to Blizzard and never crafts/buys.
local openedIds,craftCalls={},0
C_TradeSkillUI.OpenRecipe=function(id)openedIds[#openedIds+1]=id end
C_TradeSkillUI.CraftRecipe=function()craftCalls=craftCalls+1 end
DoTradeSkill=function()craftCalls=craftCalls+1 end
combat=false;p.Select(shortcutRecipe)
assert(panel.openRecipe.text=='Open Recipe' and panel.openRecipe.enabled,'selected recipe enables navigation')
local beforeOpen=grouped
panel.openRecipe:GetScript('OnClick')()
assert(#openedIds==1 and openedIds[1]==shortcutRecipe.recipeId,'open exact selected recipe through native API')
p.Select(otherShortcut);beforeOpen=grouped;panel.openRecipe:GetScript('OnClick')()
assert(#openedIds==2 and openedIds[2]==otherShortcut.recipeId,'cross-profession selection uses that recipe ID')
assert(grouped==beforeOpen and craftCalls==0,'opening recipe triggers neither price queries nor crafting')
assert(ProfessionsFrame.AuctionatorSearchButton==auctionatorSearch and auctionatorSearch:GetScript('OnClick')==auctionatorHandler,'recipe navigation never hooks Auctionator')
combat=true;p.Select(shortcutRecipe);assert(not panel.openRecipe.enabled)
assert(not p.OpenRecipe());assert(#openedIds==2,'combat blocks even stale button clicks');combat=false
for _,change in ipairs({{character='Other'},{realm='Other realm'},{region=91},{faction='alliance'}})do
 local foreign={};for k,v in pairs(shortcutRecipe)do foreign[k]=v end;for k,v in pairs(change)do foreign[k]=v end
 assert(not p.OpenRecipe(foreign),'never navigate another character/market saved recipe')
end
assert(not p.OpenRecipe({recipeId=0}));assert(not p.OpenRecipe({recipeId=1.5}))
C_TradeSkillUI.OpenRecipe=nil;p.Select(shortcutRecipe);assert(not panel.openRecipe.enabled and not p.OpenRecipe(),'unsupported client gives no misleading success')
C_TradeSkillUI.OpenRecipe=function()return false end;assert(not p.OpenRecipe(),'native rejection is reported')
C_TradeSkillUI.OpenRecipe=function()error('recipe unavailable')end;assert(not p.OpenRecipe(),'API errors are contained')
assert(craftCalls==0 and #openedIds==2,'all navigation failures preserve explicit crafting control')
print('PASS: Open Recipe native navigation, exact/cross-profession IDs, ownership, combat, unsupported/rejected/error guards, no automatic crafts or Auctionator changes')
-- A missing-price row has its own exact-item retry without replacing other prices.
local retryQueries={};ready=true;full=true
C_AuctionHouse.IsThrottledMessageSystemReady=function()return ready end
C_AuctionHouse.SearchForItemKeys=function(keys)retryQueries[#retryQueries+1]=keys end
C_AuctionHouse.GetBrowseResults=function()return results end
C_AuctionHouse.HasFullBrowseResults=function()return full end
emit('AUCTION_HOUSE_SHOW');p.Select(recipe)
local function missingQuote()
 assert(p.SearchAll(recipe));results={{itemKey={itemID=2589},minPrice=200,totalQuantity=100},{itemKey={itemID=2996},minPrice=600,totalQuantity=10}}
 full=true;emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');emit('AUCTION_HOUSE_THROTTLED_SYSTEM_READY');emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
 assert(p.Quote(recipe,1).pricedMaterials==1)
end
missingQuote();local retryRow=panel.rows[2];assert(retryRow.material.itemId==2320 and retryRow.retryButton.shown and retryRow.retryButton.enabled and retryRow.total.text=='No price')
local oldAt=p.Quote(recipe,1).quoteAt;local oldUnit=p.Quote(recipe,1).rows[1].unit
assert(not p.RetryMaterial(999)and not p.RetryMaterial(2589),'only a missing reagent can be retried')
combat=true;assert(not p.RetryMaterial(2320));combat=false;ready=false;assert(not p.RetryMaterial(2320));ready=true
moneyNow=moneyNow+60;retryRow.retryButton:GetScript('OnClick')();local keys=retryQueries[#retryQueries];assert(#keys==1 and keys[1].itemID==2320,'Retry queries only clicked reagent')
assert(not p.RetryMaterial(2320),'no overlapping retries')
full=false;results={{itemKey={itemID=2320},minPrice=10,totalQuantity=100}};emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');assert(p.Quote(recipe,1).pricedMaterials==1,'partial results do not publish')
full=true;emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');local repaired=p.Quote(recipe,1)
assert(repaired.ahCost==410 and repaired.salePrice==600 and repaired.rows[1].unit==oldUnit and repaired.quoteAt==oldAt,'merge only clicked material and preserve retained quote age')
assert(not retryRow.retryButton.shown and retryRow.unit.shown and retryRow.button.text=='Buy','successful retry restores regular price and Buy action')
-- Publish a complete quote using the same production scan path as the material Retry tests.
assert(p.SearchAll(recipe));results={{itemKey={itemID=2589},minPrice=200,totalQuantity=100},{itemKey={itemID=2320},minPrice=10,totalQuantity=100},{itemKey={itemID=2996},minPrice=600,totalQuantity=10}};full=true;emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
local profit=p.Quote(recipe,1).ahProfit;assert(profit~=nil)
local unpriced={name='AAA no scan',recipeId=99999,materialsKnown=true,reagents=recipe.reagents,outputItemId=2996,outputMin=1,outputMax=1}
ranked=p.SortRecipes({unpriced,recipe},'profit',{});assert(ranked[1]==recipe,'complete quotes rank before unknown even if name sorts later')
local oldTime=moneyNow;moneyNow=moneyNow+21601;ranked=p.SortRecipes({recipe,unpriced},'profit',{});assert(ranked[1]==unpriced,'stale quotes are unknown and use name tie-break');moneyNow=oldTime
missingQuote();oldAt=p.Quote(recipe,1).quoteAt;assert(p.RetryMaterial(2320));results={};emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');assert(p.Quote(recipe,1).pricedMaterials==1 and p.Quote(recipe,1).quoteAt==oldAt,'empty exact result cannot invent a price or refresh other values')
assert(p.RetryMaterial(2320));results={{itemKey={itemID=999},minPrice=1,totalQuantity=100}};emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');assert(p.Quote(recipe,1).pricedMaterials==1,'unrelated results rejected')
assert(p.RetryMaterial(2320));for _,fn in ipairs(timeouts)do fn()end;assert(p.Quote(recipe,1).pricedMaterials==1,'timeout preserves quote')
moneyNow=moneyNow+21601;assert(not p.RetryMaterial(2320),'stale recipes require full refresh');moneyNow=moneyNow-21601
emit('AUCTION_HOUSE_CLOSED');assert(not p.RetryMaterial(2320));emit('AUCTION_HOUSE_SHOW')
print('PASS material retry: amber missing-price row, one-item query, passive retained prices/age, atomic publication, empty/unrelated/timeout/stale/closed/combat/throttle guards and restored Buy controls')
-- Favorites are UI preferences, separate from captured recipe/cost evidence.
local fav=p.Catalog()[1];assert(fav and not p.IsFavorite(fav));local beforeFavorite=grouped
local tradeCount=#(AZPCForeverDB.trades or{});local recipeName=fav.name
assert(p.ToggleFavorite(fav)and p.IsFavorite(fav));assert(#p.Catalog(nil,'',true)==1)
assert(#p.Catalog(fav.profession,'',true)==1 and #p.Catalog(nil,'does not match',true)==0,'favorites combine with existing filters')
local changed={};for k,v in pairs(fav)do changed[k]=v end;changed.reagents={};assert(p.IsFavorite(changed),'stable recipe ID survives updated reagents')
assert(not p.ToggleFavorite({recipeId=0})and not p.ToggleFavorite({recipeId=1.5}),'invalid IDs cannot write preferences')
local originalName,originalRealm,originalFaction=UnitName,GetRealmName,UnitFactionGroup
UnitName=function()return 'Other'end;assert(not p.IsFavorite(fav)and not p.FavoritesOnly());assert(not p.ToggleFavorite(fav));UnitName=originalName
GetRealmName=function()return 'Launch realm'end;assert(not p.IsFavorite(fav));GetRealmName=originalRealm
UnitFactionGroup=function()return 'Alliance'end;assert(not p.IsFavorite(fav));UnitFactionGroup=originalFaction
page.menuRows[1]:GetScript('OnClick')();page.search:SetText('');page.search:GetScript('OnTextChanged')(page.search)
p.SetFavoritesOnly(true);assert(p.FavoritesOnly()and page.recipeRows[1].recipe==fav)
assert(page.favorites.text:find('Favorites',1,true));page.recipeRows[1].favorite:GetScript('OnClick')()
assert(not p.IsFavorite(fav)and #p.Catalog(nil,'',true)==0 and page.empty.text:find('Star recipes',1,true),'unstar removes from filtered list with clear empty state')
page.allRecipes:GetScript('OnClick')();assert(not p.FavoritesOnly());page.recipeRows[1].favorite:GetScript('OnClick')();fav=page.recipeRows[1].recipe;assert(p.IsFavorite(fav))
assert(grouped==beforeFavorite,'star and filter clicks never start price queries')
p.SetFavoritesOnly(true)
-- Browser selection and filters are restored passively after an AH reopen.
p.Select(fav)
local choices=page.menuRows
for _,option in ipairs(choices)do if option.value==fav.profession then option:GetScript('OnClick')();break end end
page.search:SetText(fav.name);page.search:GetScript('OnTextChanged')(page.search)
emit('AUCTION_HOUSE_CLOSED');emit('AUCTION_HOUSE_SHOW')
local queriesBeforeRestore=#retryQueries;p.Show()
assert(panel.name.text==fav.name and page.search.text==fav.name and page.profession.text==fav.profession and p.FavoritesOnly(),'restore selection and all filters')
assert(#retryQueries==queriesBeforeRestore and panel.market.text=='Scan prices to refresh','opening saved recipe never scans or claims fresh prices')
local savedBrowser
for _,scope in pairs(AZPCForeverDB.recipeFavorites)do if scope.browser and scope.browser.recipeId==fav.recipeId then savedBrowser=scope.browser end end
assert(savedBrowser and savedBrowser.query==fav.name and savedBrowser.profession==fav.profession)
local oldRecipe=savedBrowser.recipeId;savedBrowser.recipeId=99999999
assert(not p.RestoreBrowser(),'removed/unknown recipe never restores a stale catalog object');assert(savedBrowser.recipeId==99999999,'temporary missing catalog does not erase saved choice');savedBrowser.recipeId=oldRecipe
assert(p.RestoreBrowser())
local oldWho=UnitName;UnitName=function()return 'Other'end;assert(not p.RestoreBrowser(),'other characters cannot restore this browser state');UnitName=oldWho
assert(savedBrowser.recipeId==oldRecipe and #retryQueries==queriesBeforeRestore)
print('PASS browser restore: selection, profession/search/favorites filters, AH reopen, no queries, refresh prompt, missing catalog preservation and character isolation')
assert((loadstring or load)('return function(currentRegion,number)'..block..'end'))()(currentRegion,number)
local restored=AZPCForeverProfession;assert(restored.IsFavorite(fav)and restored.FavoritesOnly(),'favorites and filter survive module reload')
assert(restored.RestoreBrowser()and savedBrowser.query==fav.name,'browser state survives module reload without a scan');assert(#retryQueries==queriesBeforeRestore)
assert(#(AZPCForeverDB.trades or{})==tradeCount and fav.name==recipeName,'favorites do not edit captured data')
print('PASS favorites: stars, filtering/search/profession composition, no scans, empty/unstar behavior, per-character/realm/faction isolation, stable IDs and reload persistence')
-- Craftable recipes use live player bag counts, never saved bank/alt positions.
held[2589]=6;held[2320]=3
local can={materialsKnown=true,reagents={{itemId=2589,quantity=2},{itemId=2320,quantity=1}}}
assert(p.CraftableCount(can)==3,'limiting reagent determines whole crafts')
local duplicate={materialsKnown=true,reagents={{itemId=2589,quantity=2},{itemId=2589,quantity=2}}};assert(p.CraftableCount(duplicate)==1,'repeated reagent requirements are combined')
assert(p.CraftableCount({materialsKnown=false,reagents=can.reagents})==nil)
assert(p.CraftableCount({materialsKnown=true,reagents={}})==nil)
assert(p.CraftableCount({materialsKnown=true,reagents={{itemId=2589,quantity=0}}})==nil)
held[2320]=nil;assert(p.CraftableCount(can)==nil,'unavailable bag count is not invented');held[2320]=0;assert(p.CraftableCount(can)==0,'zero in bags cannot use bank or alt stock');held[2320]=3
local getCountBefore=GetItemCount;local callsById={}
GetItemCount=function(id,bank,uses,reagentBank)assert(bank==false and uses==false and reagentBank==false,'never include banks');callsById[id]=(callsById[id]or 0)+1;return held[id]end
local cache={};assert(p.CraftableCount(can,cache)==3 and p.CraftableCount(can,cache)==3);assert(callsById[2589]==1 and callsById[2320]==1,'one live count per unique reagent per refresh')
GetInventoryItemID=function(_,slot)if slot==1 then return 2589 end end
GetInventoryItemCount=function()return 1 end
assert(p.CraftableCount(can)==2,'equipped copies do not count as bag materials')
GetInventoryItemID=nil;GetInventoryItemCount=nil;GetItemCount=getCountBefore
local beforeCraftFilter=#retryQueries;page.search:SetText('');page.search:GetScript('OnTextChanged')(page.search);page.menuRows[1]:GetScript('OnClick')();p.SetFavoritesOnly(false)
page.canCraft.checked=true;page.canCraft:GetScript('OnClick')(page.canCraft)
assert(p.CraftableOnly()and #p.Catalog(nil,'',false,true)==2,'ready filter excludes unresolved learned recipes')
assert(page.recipeRows[1].craftCount.text=='[3]')
held[2589]=0;emit('BAG_UPDATE_DELAYED');assert(page.empty.text:find('No matching recipes ready',1,true),'bag changes refresh the ready filter')
assert(#p.Catalog(nil,'',false,true)==0 and #retryQueries==beforeCraftFilter,'filtering and bag refresh never query AH')
held[2589]=6;p.SetCraftableOnly(false);assert(not p.CraftableOnly())
local readyRecipe=p.Catalog()[1];if not p.IsFavorite(readyRecipe)then p.ToggleFavorite(readyRecipe)end
assert(#p.Catalog(readyRecipe.profession,readyRecipe.name,true,true)==1,'ready combines with favorites, profession and text search')
p.SetCraftableOnly(true)
assert((loadstring or load)('return function(currentRegion,number)'..block..'end'))()(currentRegion,number)
assert(AZPCForeverProfession.CraftableOnly(),'ready filter preference survives reload')
local whoBefore=UnitName;UnitName=function()return 'Other'end;assert(not AZPCForeverProfession.CraftableOnly(),'ready preference is per character');UnitName=whoBefore
print('PASS craftable: limiting/duplicate reagents, unknown/zero guards, bags-only counts, equipped exclusion, per-refresh cache, filter controls, passive bag refresh, combined filters and saved preference')
-- Blizzard category names/order are UI metadata; capture evidence stays untouched.
local nativeRecords={}
for id,name in pairs({[301]='Bolt Sample',[302]='Linen Bag Sample',[303]='Specialty Bag Sample'})do nativeRecords[id]={recipeId=id,name=name,profession='Tailoring',character='Phillip',realm='Classic Beta PvP 2',faction='horde',region=90,materialsKnown=true,outputItemId=2996,reagents={{itemId=2589,quantity=2}},outputMin=1,outputMax=1}end
C_TradeSkillUI={GetBaseProfessionInfo=function()return {professionName='Tailoring'}end,GetRecipeInfo=function(id)if nativeRecords[id]then return {name=nativeRecords[id].name,learned=true,categoryID=id-300}end end,GetCategoryInfo=function(id)return ({[1]={name='Reagents',uiOrder=1},[2]={name='Bags',uiOrder=2},[3]={name='Specialty Bags',uiOrder=3}})[id]end}
AZPCForeverCrafting.ReadRecipe=function(id)return nativeRecords[id]end
p.CaptureCatalog({301,302,303});assert(nativeRecords[301].browserCategory==nil,'presentation metadata must not mutate captured recipe records')
p.SetCraftableOnly(false);p.SetFavoritesOnly(false)
for _,option in ipairs(page.menuRows)do if option.value=='Tailoring'then option:GetScript('OnClick')();break end end
page.search:SetText('');page.search:GetScript('OnTextChanged')(page.search)
local nativeGroups=p.RecipeGroups(p.Catalog('Tailoring'));assert(#nativeGroups==3 and nativeGroups[1].name=='Reagents'and nativeGroups[2].name=='Bags'and nativeGroups[3].name=='Specialty Bags','native category order')
local reagentHeader=page.categoryRows[nativeGroups[1].key];assert(reagentHeader and reagentHeader.shown)
local beforeCategories=#retryQueries;reagentHeader:GetScript('OnClick')();assert(p.CategoryClosed(nativeGroups[1].key));assert(not page.recipeRows[1].shown,'collapse hides only category recipe rows')
page.search:SetText('Bolt');page.search:GetScript('OnTextChanged')(page.search);assert(page.recipeRows[1].shown and not p.CategoryClosed(nativeGroups[1].key),'search reveals matching rows inside collapsed categories')
page.search:SetText('');page.search:GetScript('OnTextChanged')(page.search);assert(p.CategoryClosed(nativeGroups[1].key),'clearing search restores saved collapsed state')
page.filtersButton:GetScript('OnClick')();assert(page.filters.shown)
page.canCraft.checked=true;page.canCraft:GetScript('OnClick')(page.canCraft);assert(p.CraftableOnly()and not page.filters.shown,'compact Filters popup keeps existing craftable functionality')
assert(#retryQueries==beforeCategories,'category and filter controls never scan prices')
assert(page.recipeRows[1].craftCount.text~='Missing materials','compact list omits repetitive missing-material subtitles')
assert((loadstring or load)('return function(currentRegion,number)'..block..'end'))()(currentRegion,number)
assert(AZPCForeverProfession.CategoryClosed(nativeGroups[1].key),'category collapse persists per character')
print('PASS native layout: category metadata/order, compact collapse/search behavior, Filters popup, saved preferences, no queries and unchanged captured recipe evidence')

-- Sorting uses complete cached quotes, is stable and never queries or mutates capture data.
p.SetCraftableOnly(false);p.SetFavoritesOnly(false)
local beforeSort=#retryQueries
assert(p.SortMode()=='name'and not p.SetSortMode('invalid'))
local a={name='Alpha',recipeId=9001,materialsKnown=true,reagents={{itemId=2589,quantity=2}}}
local b={name='Beta',recipeId=9002,materialsKnown=true,reagents={{itemId=2589,quantity=1}}}
local u={name='Unknown',recipeId=9003,materialsKnown=false,reagents={}}
local original={a,u,b};held[2589]=6
local ranked=p.SortRecipes(original,'craftable',{});assert(ranked[1]==b and ranked[2]==a and ranked[3]==u and original[2]==u)
held[2589]=0;ranked=p.SortRecipes({u,b,a},'craftable',{});assert(ranked[1]==a and ranked[2]==b and ranked[3]==u,'known zero sorts ahead of unknown')
held[2589]=6
local afterScan=#retryQueries
assert(p.SetSortMode('profit')and p.SortMode()=='profit');assert(page.sortButton.text=='Sort: Estimated profit')
assert(p.SetSortMode('craftable'));page.sortOptions[1]:GetScript('OnClick')();assert(p.SortMode()=='name'and not page.filters.shown)
assert(p.SetSortMode('profit'))
assert((loadstring or load)('return function(currentRegion,number)'..block..'end'))()(currentRegion,number)
assert(AZPCForeverProfession.SortMode()=='profit','sort persists per character')
local oldName=UnitName;UnitName=function()return 'Other'end;assert(AZPCForeverProfession.SortMode()=='name');UnitName=oldName
assert(#retryQueries==afterScan,'sort controls and restored preferences never query AH')
print('PASS recipe sorting: ranked bag counts, unknown/zero, complete vs missing/stale quotes, passive controls, stable source order and saved character preference')
