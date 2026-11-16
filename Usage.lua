-- VoidMark usage stamps. The same file ships in every VoidMark addon; each copy only
-- looks after its own addon.
--
-- Keeps only this in <AddonFolder>Usage (SavedVariables):
--   init    when this addon last loaded (login or /reload)
--   active  when you last really used it: opened one of its windows, clicked its
--           minimap button or typed one of its slash commands
--   version the addon's version
-- No character, account, realm, gameplay, chat or gold data. Nothing is sent from the
-- game. VoidMark Warpath reads these times after WoW saves (logout or /reload) and sends
-- them only if you said yes to anonymous statistics in Warpath.
local addonName = ...
if type(addonName) ~= "string" then return end
local KEY = addonName .. "Usage"

-- What counts as really using each addon. Windows that open by themselves at login are
-- left out (that is just the addon loading), and window shows in the first seconds after
-- login are ignored for the same reason.
local WATCH = {
    VoidMarkMarket = {
        slash = { "VOIDMARKMARKET" },
        frames = { "VoidMarkMarketWindow" },
        clicks = { "VoidMarkMarketMinimapButton" },
    },
    VoidMarkNexus = {
        slash = { "VOIDMARKNEXUS" },
        frames = { "VoidMarkNexusWindow", "VoidMarkNexusDashboard" },
        clicks = { "VoidMarkNexusMapButton" },
    },
    VoidMarkJourney = {
        slash = { "VOIDMARKJOURNEY" },
        frames = { "VoidMarkJourneyList" },
    },
    VoidMarkMiniMap = {
        slash = { "VOIDMARKHERB", "VOIDMARKLAYER" },
        frames = { "VoidMarkMiniMapOptions" },
    },
    VoidMarkDebug = {
        slash = { "VOIDMARKDEBUG" },
        frames = { "VoidMarkDebugWindow", "VoidMarkDebugProblem" },
    },
    VoidMarkForever = {
        slash = { "TALIAAGANK", "TALIAATHREAT", "TALIAARUNBACK", "TALIAABOATS", "TALIAASRIDEORDIE",
                  "TALIAATAUNT", "VOIDMARKENEMYMOVES", "VOIDMARKMC", "VOIDMARKWHO" },
        frames = { "TaliaaVoidMarkGankTrackerFrame", "TaliaaVoidMarkGankOptionsFrame", "VoidMarkEnemyMovesOptions",
                   "VoidMarkKillEffectsOptions", "VoidMarkMCMarksBoard", "TaliaasRideOrDieConfig" },
        clicks = { "VoidMarkMinimapButton" },
    },
}
local watch = WATCH[addonName] or {}
local QUIET_AFTER_LOGIN = 10 -- seconds
local loginAt

local function clock()
    local ok, t = pcall(GetTime)
    if ok and type(t) == "number" then return t end
end

local function mark(field)
    pcall(function()
        local t = time()
        if type(t) ~= "number" then return end
        local u = _G[KEY]
        if type(u) ~= "table" then u = {}; _G[KEY] = u end
        u.v = 1
        u[field] = t
    end)
end

local function markShown()
    local t = clock()
    if loginAt and t and t - loginAt < QUIET_AFTER_LOGIN then return end
    mark("active")
end

local hooked = {}
local hookAll
local function onUse()
    mark("active")
    hookAll() -- windows made on first use can be watched from now on
end

hookAll = function()
    for _, name in ipairs(watch.frames or {}) do
        local f = _G[name]
        if not hooked[name] and type(f) == "table" and type(f.HookScript) == "function" then
            if pcall(f.HookScript, f, "OnShow", markShown) then hooked[name] = true end
        end
    end
    for _, name in ipairs(watch.clicks or {}) do
        local f, k = _G[name], "click:" .. name
        if not hooked[k] and type(f) == "table" and type(f.HookScript) == "function" then
            if pcall(f.HookScript, f, "OnClick", onUse) then hooked[k] = true end
        end
    end
    for _, cmd in ipairs(watch.slash or {}) do
        local k = "slash:" .. cmd
        if not hooked[k] and type(SlashCmdList) == "table" and type(SlashCmdList[cmd]) == "function"
            and type(hooksecurefunc) == "function" then
            if pcall(hooksecurefunc, SlashCmdList, cmd, onUse) then hooked[k] = true end
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    loginAt = clock()
    mark("init")
    pcall(function()
        local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
        local v = get and get(addonName, "Version")
        if type(v) == "string" and #v <= 40 then _G[KEY].version = v end
    end)
    pcall(hookAll)
    if C_Timer and type(C_Timer.After) == "function" then
        pcall(C_Timer.After, QUIET_AFTER_LOGIN + 1, function() pcall(hookAll) end)
    end
end)
