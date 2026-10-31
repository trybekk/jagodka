-- ============================================================================
-- TAB IN BLIZZARD CHAT: community General
-- ============================================================================
--  * In addition to the addon window: the same messages in a regular game chat window.
--    "Jagodki Nadina - General" = the addon's General tab (linked to /g).
--    Trade and LFG stay in the addon window; a Trade tab left by older versions is closed.
--  * Created at login whenever missing, also after the player closes it, and a duplicate
--    with the same name is closed. "/jagodka tab" recreates it.
--  * Read only: write through /g or the addon window.
--    Names are links (click = whisper, right click = menu), item links work as in the game.
--  * After login it shows the latest messages from history, then new ones as they arrive.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local ipairs = _G.ipairs
local table, math = _G.table, _G.math

local Most = addonTable.Most

local REPLAY_COUNT = 30       -- how many of the latest messages to show after login
local REPLAY_DELAY = 15       -- seconds after login (after the history sync)

-- tab = addon chat tab, color = text color (different from /g), old = earlier names (renamed)
local TABS = {
    { name = "Jagodki Nadina - General", tab = "Ogolny", color = "ff3cb43c", old = { ["Jagodki Nadina"] = true } },
}
local OBSOLETE_TAB = "Jagodki Nadina - Trade"

local Zakladka = {}
addonTable.Zakladka = Zakladka

-- The state of each tab is kept in its TABS entry: frame, lastShownTs
-- (lastShownTs = nil -> history not shown yet, nothing is printed until then)

-- A closed window keeps its name, so only a shown or docked one counts as an existing tab
local function FindTab(def)
    local found = nil
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local name, _, _, _, _, _, shown, _, docked = _G.GetChatWindowInfo(i)
        if (name == def.name or def.old[name]) and (shown or docked) then
            local frame = _G["ChatFrame" .. i]
            if found then
                if _G.FCF_Close then _G.FCF_Close(frame) end
            else
                found = frame
                -- Tab created under an old name: rename it instead of creating a second one
                if name ~= def.name and _G.FCF_SetWindowName then _G.FCF_SetWindowName(frame, def.name) end
            end
        end
    end
    return found
end

local function CreateTab(def)
    if not _G.FCF_OpenNewWindow then return nil end
    -- A new window docks at the end (with the default chat: General, Combat Log, our tabs)
    _G.FCF_OpenNewWindow(def.name, true)
    local frame = FindTab(def)
    if not frame then return nil end -- chat window limit
    -- No regular channels or message types, only what the addon prints
    if _G.ChatFrame_RemoveAllMessageGroups then _G.ChatFrame_RemoveAllMessageGroups(frame) end
    if _G.ChatFrame_RemoveAllChannels then _G.ChatFrame_RemoveAllChannels(frame) end
    -- A new window selects itself, so we go back to General
    if _G.FCF_SelectDockFrame and _G.DEFAULT_CHAT_FRAME then _G.FCF_SelectDockFrame(_G.DEFAULT_CHAT_FRAME) end
    return frame
end

local function DefFor(tab)
    for _, def in ipairs(TABS) do
        if def.tab == tab then return def end
    end
    return nil
end

local function Print(def, e)
    if def.frame and e.src ~= "S" and not addonTable.Mute.IsMuted(e.author) then
        def.frame:AddMessage(Most.FormatEntry(e, def.color))
        if not def.lastShownTs or e.ts > def.lastShownTs then def.lastShownTs = e.ts end
    end
end

local function Replay(def)
    if not def.frame then return end
    local list = {}
    for _, e in ipairs(Most.GetLog()) do
        if e.tab == def.tab and e.src ~= "S" then table.insert(list, e) end
    end
    local first = math.max(1, #list - REPLAY_COUNT + 1)
    def.frame:AddMessage("|cff808080--- " .. def.name .. ": last messages ---|r")
    def.lastShownTs = 0
    for i = first, #list do Print(def, list[i]) end
end

local function ReplayAll()
    for _, def in ipairs(TABS) do Replay(def) end
end

-- New messages: current ones always, from history only those newer than the last one shown
-- (the game chat window only appends at the end, older ones would break the order)
Most.OnNewEntry(function(e, live)
    local def = DefFor(e.tab)
    if not def or def.lastShownTs == nil then return end
    if live or e.ts > def.lastShownTs then Print(def, e) end
end)

local function Setup()
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local name, _, _, _, _, _, shown, _, docked = _G.GetChatWindowInfo(i)
        if name == OBSOLETE_TAB and (shown or docked) and _G.FCF_Close then _G.FCF_Close(_G["ChatFrame" .. i]) end
    end
    for _, def in ipairs(TABS) do
        def.frame = FindTab(def) or CreateTab(def)
    end
end

-- Whether this chat window is one of our tabs (e.g. the name menu in mute.lua)
function Zakladka.IsOurFrame(frame)
    for _, def in ipairs(TABS) do
        if frame and def.frame == frame then return true end
    end
    return false
end

-- "/jagodka tab": recreate missing tabs (e.g. after closing one)
function Zakladka.Recreate()
    local before = {}
    for _, def in ipairs(TABS) do before[def] = def.frame end
    Setup()
    local any = false
    for _, def in ipairs(TABS) do
        if def.frame then
            -- Only a new tab gets the history; an existing one already has it
            if def.frame ~= before[def] then Replay(def) end
            any = true
        end
    end
    return any
end

local Listener = CreateFrame("Frame")
Listener:RegisterEvent("PLAYER_LOGIN")
Listener:SetScript("OnEvent", function()
    -- Chat windows are ready a moment after login
    C_Timer.After(3, Setup)
    C_Timer.After(REPLAY_DELAY, ReplayAll)
end)
