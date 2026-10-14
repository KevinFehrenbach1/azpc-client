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
install();local text=hover();assert(text:find('AZPC Auction / each: coins(100)',1,true));assert(text:find('AZPC Cost / each: coins(20)',1,true));assert(text:find('AZPC Est. profit / each*: coins(75)',1,true));local n=#GameTooltip.lines;GameTooltip.hooks.OnTooltipSetItem(GameTooltip);assert(#GameTooltip.lines==n,'repeat callback must not duplicate lines')
AZPCForeverDB.crafting.costing.positions[1].totalCopper=0;text=hover();assert(text:find('AZPC Cost / each: coins(0)',1,true))
AZPCForeverDB.crafting.costing.positions[1].costComplete=false;text=hover();assert(text:find('AZPC Cost / each: No data',1,true));assert(text:find('AZPC Est. profit / each: No data',1,true))
AZPCForeverDB.crafting.costing.positions[1].costComplete=true;AZPCForeverDB.crafting.costingError='blocked';text=hover();assert(text:find('AZPC Est. profit / each: No data',1,true));AZPCForeverDB.crafting.costingError=nil
character='Another';text=hover();assert(text:find('AZPC Cost / each: No data',1,true));character='Phillip'
realm='Launch';text=hover();assert(text:find('AZPC Auction / each: No data',1,true));realm='Classic Beta PvP 2'
stamp=stamp+21601;text=hover();assert(text:find('(stale)',1,true));assert(text:find('AZPC Est. profit / each: No data',1,true));stamp=stamp-21601
local postCall;TooltipDataProcessor={AddTooltipPostCall=function(_,fn)postCall=fn end};Enum={TooltipDataType={Item=1}};install();GameTooltip.lines={};GameTooltip.hooks.OnTooltipCleared(GameTooltip);postCall(GameTooltip,{id=2318});assert(table.concat(GameTooltip.lines,'\n'):find('AZPC Auction / each',1,true));local n=#GameTooltip.lines;postCall(GameTooltip,{id='secret'});assert(#GameTooltip.lines==n)
GetCoinTextureString=nil;text=hover();assert(text:find('UI-SilverIcon',1,true));assert(not text:find('UI-GoldIcon',1,true));
TooltipDataProcessor=nil;GameTooltip={HookScript=function()error('unsupported')end};ItemRefTooltip=nil;install()
print('PASS: legacy/modern hooks, price age, exact unit cost/profit, free/unknown, market/character isolation, stale/secret guards and deduplication')
