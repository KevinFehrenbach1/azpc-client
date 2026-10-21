-- AZPC Forever: optional first-run setup help for CurseForge-only installations.
-- The watcher writes AZPCForeverWatcherStatus into the addon on disk.
-- This is a last-known signal, not direct Windows process detection.
local function now() return (GetServerTime and GetServerTime()) or (time and time()) or 0 end
local function watcherSeen()
    local w=AZPCForeverWatcherStatus
    local checked=type(w)=='table' and tonumber(w.checkedAt)
    return checked and checked>0 and now()>=checked and (now()-checked)<3600
end
local function dismissed()
    return type(AZPCForeverDB)=='table' and AZPCForeverDB.setupPromptDismissed==true
end
local function markDismissed()
    if type(AZPCForeverDB)=='table' then AZPCForeverDB.setupPromptDismissed=true end
end
local function show()
    if watcherSeen() or dismissed() or (InCombatLockdown and InCombatLockdown()) then return end
    if not StaticPopupDialogs or not StaticPopup_Show then return end
    StaticPopupDialogs.AZPC_FOREVER_SETUP_HELP={
        text='Connect AZPC to your dashboard!\\n\\nThe AZPC Watcher has not checked in recently. If you installed this addon from CurseForge, visit azpc.market to install the launcher and watcher.\\n\\nYour addon still works without the watcher, but dashboard sync needs it.',
        button1='Got it',button2='Remind me later',
        OnAccept=markDismissed,
        timeout=0,whileDead=true,hideOnEscape=true,
    }
    StaticPopup_Show('AZPC_FOREVER_SETUP_HELP')
end
local f=CreateFrame('Frame')
f:RegisterEvent('PLAYER_LOGIN')
f:SetScript('OnEvent',function()
    if C_Timer and C_Timer.After then C_Timer.After(12,show) else show() end
end)
AZPCForeverSetupHelp={Show=show,WatcherSeen=watcherSeen}
