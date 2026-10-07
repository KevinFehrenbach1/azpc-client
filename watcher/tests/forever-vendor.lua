SlashCmdList={}
local frames,timers,hooks={},{},{}
function CreateFrame()local f={events={}};frames[#frames+1]=f;function f:RegisterEvent(e)self.events[e]=true end;function f:SetScript(_,fn)self.handler=fn end;return f end
local function emit(e,...)for _,f in ipairs(frames)do if f.events[e]then f.handler(f,e,...)end end end
C_Timer={After=function(_,fn)timers[#timers+1]=fn end}
local function flush()local n=0;while #timers>0 do n=n+1;assert(n<200,'timers settle');local fn=table.remove(timers,1);fn()end end
function hooksecurefunc(a,b,c)if type(a)=='table'then hooks[b]=c else hooks[a]=b end end
function GetServerTime()return 1791403200 end
function GetRealmName()return 'Realm' end
function UnitName()return 'Lu' end
function UnitGUID()return 'Player-Lu' end
function UnitFactionGroup()return 'Horde' end
function GetCurrentRegion()return 90 end
local cash=10000;local slots={};local info={name='Thread',price=10,stackCount=1,hasExtendedCost=false}
local buyback=nil
function GetMoney()return cash end
function GetMerchantNumItems()return 1 end
function GetMerchantItemLink()return 'item:2320' end
C_MerchantFrame={GetItemInfo=function()return info end}
function GetNumBuybackItems()return buyback and 1 or 0 end
function GetBuybackItemInfo()return 'Thread',nil,buyback.price,buyback.quantity end
function GetBuybackItemLink()return 'item:2320' end
function BuyMerchantItem()end
function BuybackItem()end
C_Container={GetContainerNumSlots=function(b)return b==0 and 4 or 0 end,GetContainerItemInfo=function(_,s)return slots[s]end,UseContainerItem=function()end,ContainerRefundItemPurchase=function()end,GetContainerItemPurchaseInfo=function(_,s)return slots[s] and slots[s].refund end}
C_Item={GetItemInfo=function()return 'Thread',nil,nil,nil,nil,nil,nil,nil,nil,nil,2 end}
local function set(q)slots[1]=q>0 and {itemID=2320,stackCount=q,itemName='Thread'}or nil end
local function reset()emit('MERCHANT_CLOSED');flush();cash=10000;slots={};buyback=nil;info={name='Thread',price=10,stackCount=1,hasExtendedCost=false};AZPCForeverDB={trades={},crafting={schema=1,recipes={},crafts={},seen={},vendorEvents={}}};emit('MERCHANT_SHOW');flush()end
assert(loadfile('addons/forever/AZPCForever/AZPCForever.lua'))('AZPCForever')
emit('ADDON_LOADED','AZPCForever');flush();reset()
-- Post-hook follows synchronous bag/money notifications: delayed observation retains pre-state.
set(3);cash=cash-30;emit('PLAYER_MONEY');emit('BAG_UPDATE_DELAYED');hooks.BuyMerchantItem(1,3);flush()
local d=AZPCForeverDB.crafting;assert(#d.vendorEvents==1 and d.vendorEvents[1].quantity==3 and d.vendorEvents[1].copper==30)
assert(d.vendorEvents[1].source=='vendor_purchase' and not table.concat((function()local t={};for _,r in ipairs(AZPCForeverDB.trades)do t[#t+1]=r.tradeExport end;return t end)(), '\n'):find('|buy|',1,true),'vendor evidence stays out of mailbox purchase exports')
emit('MERCHANT_UPDATE');emit('BAG_UPDATE_DELAYED');flush();assert(#d.vendorEvents==1,'repeat notifications do not duplicate purchase')
d.crafts[1]={eventId='craft',itemId=4496,name='Bag',quantity=1,observedAt=d.vendorEvents[1].observedAt+1,region=90,realm='Realm',faction='horde',character='Lu',materialsKnown=true,consumedReagents={{itemId=2320,quantity=1}}}
AZPCForeverCrafting.RebuildCosts();assert(d.crafts[1].costBasis.totalCopper==10,'vendor purchase supplies a craft')
reset();set(1);cash=cash-10;hooks.BuyMerchantItem(1,1);flush();d=AZPCForeverDB.crafting
local at=d.vendorEvents[1].observedAt
AZPCForeverDB.trades={{tradeExport=table.concat({'AZPCFTRADE','2','cloth','buy','2589','Linen','6','6',tostring(at-1),'Realm','horde','90','Lu','','','','','','','',''},'|')}}
local function recorded(id,q,time,mats)return {eventId='craft:'..time,itemId=id,name='Craft',quantity=q,observedAt=time,region=90,realm='Realm',faction='horde',character='Lu',materialsKnown=true,consumedReagents=mats}end
for i=1,3 do d.crafts[i]=recorded(2996,1,at+i,{{itemId=2589,quantity=2}})end
d.crafts[4]=recorded(4496,1,at+4,{{itemId=2996,quantity=3},{itemId=2320,quantity=1}})
AZPCForeverCrafting.RebuildCosts();assert(d.crafts[4].costBasis.complete and d.crafts[4].costBasis.totalCopper==16,'AH cloth plus vendor thread make a fully costed chained craft')
reset();set(1);cash=cash-10;hooks.BuyMerchantItem(1,1);flush();d=AZPCForeverDB.crafting
set(0);slots[2]={itemID=4496,stackCount=1,itemName='Bag'}
d.crafts[1]=recorded(4496,1,d.vendorEvents[1].observedAt+1,{{itemId=2320,quantity=1}})
emit('BAG_UPDATE_DELAYED');flush();assert(#d.vendorEvents==1 and d.crafts[1].costBasis.totalCopper==10,'crafting with merchant open is not another disposal')
reset();info.price=45;info.stackCount=5;emit('MERCHANT_UPDATE');flush();set(5);cash=cash-45;hooks.BuyMerchantItem(1);flush();d=AZPCForeverDB.crafting;assert(d.vendorEvents[1].quantity==5 and d.vendorEvents[1].copper==45,'default purchase uses vendor bundle size and discounted total')
reset();set(2);cash=cash-20;hooks.BuyMerchantItem(1,1);hooks.BuyMerchantItem(1,1);flush();d=AZPCForeverDB.crafting;assert(#d.vendorEvents==2 and d.vendorEvents[1].eventId~=d.vendorEvents[2].eventId,'rapid purchases share confirmation but keep distinct evidence')
reset();hooks.BuyMerchantItem(1,1);flush();assert(#AZPCForeverDB.crafting.vendorEvents==0,'failed purchase never becomes a cost')
reset();set(1);cash=cash-11;hooks.BuyMerchantItem(1,1);flush();d=AZPCForeverDB.crafting;assert(#d.vendorEvents==1 and d.vendorEvents[1].kind=='vendor_unresolved','unmatched payment is not invented purchase cost')
reset();info.hasExtendedCost=true;emit('MERCHANT_UPDATE');flush();set(1);cash=cash-10;hooks.BuyMerchantItem(1,1);emit('BAG_UPDATE_DELAYED');flush();assert(AZPCForeverDB.crafting.vendorEvents[1].kind=='vendor_unresolved','currency/barter costs remain unknown')
reset();set(3);cash=cash-30;hooks.BuyMerchantItem(1,3);flush();set(0);cash=cash+6;hooks.UseContainerItem(0,1);buyback={price=6,quantity=3};flush();d=AZPCForeverDB.crafting;assert(d.vendorEvents[2].source=='vendor_sale' and d.vendorEvents[2].quantity==3)
local state=AZPCForeverCrafting.RebuildCosts();assert(#state.positions==0,'selling to vendor removes material cost')
set(3);cash=cash-6;hooks.BuybackItem(1);buyback=nil;flush();assert(d.vendorEvents[3].source=='vendor_buyback' and d.vendorEvents[3].copper==6)
state=AZPCForeverCrafting.RebuildCosts();assert(state.positions[1].quantity==3 and state.positions[1].totalCopper==6,'buyback is actual acquisition without duplicating original stock')
reset();set(1);cash=cash-10;hooks.BuyMerchantItem(1,1);flush();slots[1].refund={money=10,itemCount=0,currencyCount=0};emit('BAG_UPDATE_DELAYED');flush();set(0);cash=cash+10;hooks.ContainerRefundItemPurchase(0,1,false);flush();d=AZPCForeverDB.crafting;assert(d.vendorEvents[2].source=='vendor_refund' and #AZPCForeverCrafting.RebuildCosts().positions==0,'cash refund removes cost')
reset();set(1);cash=cash-10;hooks.BuyMerchantItem(1,1);emit('MERCHANT_CLOSED');flush();d=AZPCForeverDB.crafting;assert(#d.vendorEvents==1,'closing merchant after purchase still settles it');set(5);emit('BAG_UPDATE_DELAYED');flush();emit('MERCHANT_SHOW');flush();assert(#d.vendorEvents==1,'activity after merchant close is not attributed to vendor')
-- Repeat costing and reload keep the same persisted evidence and quantities.
state=AZPCForeverCrafting.RebuildCosts();local count=#d.vendorEvents;assert(loadfile('addons/forever/AZPCForever/AZPCForever.lua'))('AZPCForever');emit('ADDON_LOADED','AZPCForever');flush();assert(#d.vendorEvents==count and AZPCForeverCrafting.RebuildCosts().positions[1].quantity==1)
print('PASS: vendor cash/bag confirmation, bundle prices, batches, failure, dedupe, barter guards, sales, refunds, buybacks, close timing and reload')
