local shift=true
function IsShiftKeyDown()return shift end
local stamp,realm,faction,character,region=1792000000,'Classic Beta PvP 2','horde','Phillip',90
function GetRealmName()return realm end
function UnitFactionGroup()return faction end
function UnitName()return character end
function GetCurrentRegion()return region end
function GetServerTime()return stamp end
function GetCoinTextureString(value)return 'coins('..value..')' end
local function currentRegion()return region end
local function number(v)if v=='secret'then return nil end;local n=tonumber(v);return n and n>=0 and math.floor(n) or nil end
local function tooltip()local t={lines={},hooks={},id=2318};function t:AddLine(s)self.lines[#self.lines+1]=s end;function t:AddDoubleLine(a,b)self.lines[#self.lines+1]=a..': '..b end;function t:Show()end;function t:GetItem()return 'Light Leather','|Hitem:'..self.id..'|h[Light Leather]|h'end;function t:HookScript(event,fn)self.hooks[event]=fn end;return t end
GameTooltip=tooltip();ItemRefTooltip=tooltip()
AZPCForeverDB={tooltipPrices={['90|classic beta pvp 2|horde']={[2318]={unitCopper=100,observedAt=stamp}}},crafting={costing={positions={{itemId=2318,region=90,realm=realm,faction=faction,character=character,quantity=2,totalCopper=40,costComplete=true}}}}}
local file=assert(io.open('addons/forever/AZPCForever/AZPCForever.lua','r'));local source=file:read('*a');file:close();local block=assert(source:match('%-%- BEGIN AZPC ITEM TOOLTIPS\n(.-)%-%- END AZPC ITEM TOOLTIPS'))
local function install()local fn=assert((loadstring or load)('return function(currentRegion,number) '..block..' end'))();fn(currentRegion,number)end
local function hover()GameTooltip.hooks.OnTooltipCleared(GameTooltip);GameTooltip.lines={};GameTooltip.hooks.OnTooltipSetItem(GameTooltip);return table.concat(GameTooltip.lines,'\n')end
install();local text=hover();assert(text:find('Auction / each: coins(100)',1,true));assert(text:find('Cost / each: coins(20)',1,true));assert(text:find('Est. profit / each: coins(75)',1,true));local n=#GameTooltip.lines;GameTooltip.hooks.OnTooltipSetItem(GameTooltip);assert(#GameTooltip.lines==n,'repeat callback must not duplicate lines')
AZPCForeverDB.crafting.costing.positions[1].totalCopper=0;text=hover();assert(text:find('Cost / each: coins(0)',1,true))
AZPCForeverDB.crafting.costing.positions[1].costComplete=false;text=hover();assert(not text:find('Cost / each:',1,true));assert(not text:find('Est. profit / each:',1,true))
AZPCForeverDB.crafting.costing.positions[1].costComplete=true;AZPCForeverDB.crafting.costingError='blocked';text=hover();assert(not text:find('Est. profit / each:',1,true));AZPCForeverDB.crafting.costingError=nil
character='Another';text=hover();assert(not text:find('Cost / each:',1,true));character='Phillip'
realm='Launch';text=hover();assert(not text:find('Auction / each',1,true));realm='Classic Beta PvP 2'
stamp=stamp+21601;text=hover();assert(text:find('(stale)',1,true));assert(not text:find('Est. profit / each:',1,true));stamp=stamp-21601
local postCall;TooltipDataProcessor={AddTooltipPostCall=function(_,fn)postCall=fn end};Enum={TooltipDataType={Item=1}};install();GameTooltip.lines={};GameTooltip.hooks.OnTooltipCleared(GameTooltip);postCall(GameTooltip,{id=2318});assert(table.concat(GameTooltip.lines,'\n'):find('Auction / each',1,true));local n=#GameTooltip.lines;postCall(GameTooltip,{id='secret'});assert(#GameTooltip.lines==n)
GetCoinTextureString=nil;text=hover();assert(text:find('UI-SilverIcon',1,true));assert(not text:find('UI-GoldIcon',1,true));
-- Ownership reads snapshots only, and indexes historical bank evidence in bounded timer slices.
local queue={};C_Timer={After=function(_,fn)queue[#queue+1]=fn end}
local function drain()local count=0;while #queue>0 do local fn=table.remove(queue,1);fn();count=count+1;assert(count<100)end;return count end
local owner='90|Classic Beta PvP 2|horde|Wet'
AZPCForeverDB.bagStates={[owner]={[2318]={quantity=4,recordedAt=stamp-60}},['90|Classic Beta PvP 2|horde|Phillip']={[2318]={quantity=2,recordedAt=stamp-120}},['90|Other Realm|horde|Wrong']={[2318]={quantity=999,recordedAt=stamp}}}
local events={};for i=1,250 do events[i]={kind='free'}end
local function bank(q,at)return {kind='inventory_observation',confirmation='bags_and_character_bank_observed',region=90,realm=realm,faction='horde',character='Wet',itemId=2318,bagQuantity=3,bankQuantity=q,observedAt=at*1000}end
events[#events+1]=bank(20,stamp-86400);events[#events+1]=bank(50,stamp-172800)
AZPCForeverDB.crafting.materialEvents=events
install();hover();assert(drain()==3,'bank indexing yields every 100 historical records')
text=hover();assert(text:find('Owned (saved): 26 known',1,true));assert(text:find('Wet: 4 bags / 20 bank',1,true));assert(text:find('Phillip: 2 bags / bank unknown',1,true));assert(text:find('bank 1d ago',1,true));assert(not text:find('Wrong',1,true))
assert(#events==252 and events[251].bankQuantity==20,'display never changes evidence')
events[#events+1]=bank(0,stamp);drain();text=hover();assert(text:find('Wet: 3 bags / 0 bank',1,true),'newer bank observation wins over old bags')
-- New records are indexed after a hover/event request; no history replay in hover itself.
events[#events+1]=bank(10,stamp+1);drain();stamp=stamp+2;text=hover();assert(text:find('Wet: 3 bags / 10 bank',1,true))
realm='Other Realm';text=hover();assert(not text:find('Wet:',1,true));realm='Classic Beta PvP 2'
AZPCForeverDB.crafting.materialEvents={};drain();text=hover();assert(text:find('Wet: 4 bags / bank unknown',1,true),'replaced history invalidates only the derived cache')
print('PASS ownership: cross-character counts, realm isolation, saved ages, unknown banks, latest observations, bounded indexing, zero bank and immutable evidence')
GetCoinTextureString=function(value)return 'coins('..value..')'end
shift=false
text=hover();assert(text:find('Owned (saved): 6 known',1,true));assert(not text:find('Wet:',1,true)and not text:find('Bags 1m',1,true),'compact ownership is one line')
Auctionator={Config={Options={AUCTION_TOOLTIPS='auction'},Get=function()return true end},API={v1={GetAuctionPriceByItemID=function(caller,id)assert(caller=='AZPCForever'and id==2318);return 100 end}}}
Bagnon={sets={countItems=true}}
AZPCForeverDB.crafting.costing.positions[1].costComplete=false
text=hover();assert(text=='','nothing useful means no AZPC section, no empty rows or duplicated addon counts/prices')
Bagnon.sets.countItems=false;text=hover();assert(text:find('Owned (saved)',1,true),'disabled external inventory tooltip keeps AZPC fallback')
Bagnon.sets.countItems=true;Auctionator.Config.Get=function()return false end;text=hover();assert(text:find('Auction / each',1,true),'disabled external price tooltip keeps AZPC fallback')
Auctionator.Config.Get=function()return true end;Auctionator.API.v1.GetAuctionPriceByItemID=function()return nil end;text=hover();assert(text:find('Auction / each',1,true),'no external item price keeps AZPC fallback')
Auctionator.API.v1.GetAuctionPriceByItemID=function()error('unavailable')end;text=hover();assert(text:find('Auction / each',1,true),'external API failure keeps AZPC fallback')
Auctionator.API.v1.GetAuctionPriceByItemID=function()return 100 end
shift=true;text=hover();assert(text:find('Wet:',1,true)and text:find('Auction / each',1,true),'Shift reveals AZPC breakdown even with other addons')
shift=false;AZPCForeverDB.crafting.costing.positions[1].costComplete=true;AZPCForeverDB.crafting.costing.positions[1].totalCopper=40
text=hover();assert(text:find('Cost / each: coins(20)',1,true));assert(text:find('Est. profit / each: coins(75)',1,true));assert(not text:find('Owned (saved)',1,true));assert(not text:find('No data',1,true))
local headings=0;for _,line in ipairs(GameTooltip.lines)do if line=='AZPC'then headings=headings+1 end end;assert(headings==1,'one shared heading')
Auctionator=nil;Bagnon=nil;shift=true
print('PASS compact: empty rows omitted, lazy heading, Shift details, Auctionator/Bagnon compatibility, disabled settings, missing price and failed API fallbacks')
TooltipDataProcessor=nil;GameTooltip={HookScript=function()error('unsupported')end};ItemRefTooltip=nil;install()
print('PASS: legacy/modern hooks, price age, exact unit cost/profit, free/unknown, market/character isolation, stale/secret guards and deduplication')
