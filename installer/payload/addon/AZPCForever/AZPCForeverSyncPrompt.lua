-- A reminder is not an upload acknowledgement: SavedVariables reach the watcher only after reload/logout.
AZPCForeverSyncPrompt = {}
local prompt = AZPCForeverSyncPrompt
local visible, capturing, pending = {}, {}, {}
local mailboxOpen, reminded, queued, timerPending = false, false, false, false
local popupKey = 'AZPC_FOREVER_SYNC_SALES'
local function inCombat() return type(InCombatLockdown)=='function' and InCombatLockdown() end
local function showReminder()
    timerPending=false
    if not queued then return end
    if inCombat() then return end
    if type(StaticPopup_Show)~='function' or type(StaticPopupDialogs)~='table' then return end
    queued=false
    StaticPopup_Show(popupKey)
end
if type(StaticPopupDialogs)=='table' then
    StaticPopupDialogs[popupKey]={
        text='Auction sale collected!\n\nReloading saves your latest data so the AZPC Watcher can sync it to your account dashboard at azpc.market.\n\nYour watcher must be running and connected. Reload now?',
        button1='Reload now',button2='Later',timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3,
        OnAccept=function()
            if inCombat() then queued=true;return end
            if type(ReloadUI)=='function' then ReloadUI() end
        end,
    }
end
local function queueReminder()
    if reminded then return end
    reminded=true;queued=true
    if not timerPending then
        timerPending=true
        if C_Timer and type(C_Timer.After)=='function' then C_Timer.After(0.8,showReminder) else showReminder() end
    end
end
local function confirmCollected()
    if not mailboxOpen or type(GetMoney)~='function' then return end
    local money=GetMoney()
    for fingerprint,sale in pairs(pending) do
        local remains=false
        for _,current in pairs(visible) do if current.fingerprint==fingerprint then remains=true;break end end
        if not remains and money>=sale.moneyBefore+sale.amount then
            pending[fingerprint]=nil
            queueReminder()
        end
    end
end
function prompt.BeginCapture() capturing={} end
function prompt.ObserveSale(index,fingerprint,amount)
    if not mailboxOpen or type(GetMoney)~='function' or not amount or amount<=0 then return end
    capturing[index]={fingerprint=fingerprint,amount=amount,moneyBefore=GetMoney()}
end
function prompt.EndCapture() visible=capturing;confirmCollected() end
local events=CreateFrame('Frame')
for _,event in ipairs({'MAIL_SHOW','MAIL_CLOSED','PLAYER_MONEY','PLAYER_REGEN_ENABLED'}) do pcall(events.RegisterEvent,events,event) end
events:SetScript('OnEvent',function(_,event)
    if event=='MAIL_SHOW' then mailboxOpen=true;reminded=false;visible={};pending={}
    elseif event=='MAIL_CLOSED' then mailboxOpen=false;visible={};pending={}
    elseif event=='PLAYER_MONEY' then confirmCollected()
    elseif event=='PLAYER_REGEN_ENABLED' then showReminder() end
end)
if type(hooksecurefunc)=='function' and type(TakeInboxMoney)=='function' then
    hooksecurefunc('TakeInboxMoney',function(index)
        local sale=visible[index]
        if mailboxOpen and sale then
            pending[sale.fingerprint]={amount=sale.amount,moneyBefore=sale.moneyBefore}
        end
    end)
end
