-- ============================================================================
-- TAB IN BLIZZARD CHAT: community General
-- ============================================================================
--  * In addition to the addon window: the same messages in a regular game chat window.
--    "Jagodki Nadina - General" = a copy of the addon's General tab.
--    Trade and LFG stay in the addon window; a Trade tab left by older versions is closed.
--  * Created at login whenever missing, also after the player closes it, and a duplicate
--    with the same name is closed. "/jagodka tab" recreates it.
--  * Writing: while the tab is selected, the game's own chat input writes on the community channel
--    (UpdateInput). Slash commands work as usual, and the input's chat type comes back on other tabs.
--    Names are links (click = whisper, right click = menu), item links work as in the game.
--  * After login it shows the latest messages from history, then new ones as they arrive.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local ipairs, tonumber = _G.ipairs, _G.tonumber
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

-- ============================================================================
-- WRITING FROM THE TAB: the game's own chat input
-- ============================================================================
-- While our tab is selected, the game's chat input writes on the community channel: the chat channel from
-- the key (key.lua), or the public one without a key (bridge.lua). The game sends it itself as a normal
-- channel message, and every client shows it in the community chat. "/s", "/g", "/w" etc. still work as
-- usual. When another tab is selected, the input gets back the chat type it had before.
local CHECK_INTERVAL = 5      -- how often we check the selection and the channel number (s)
local saved = nil             -- the input's settings before we changed them: { box, chatType, stickyType, channelTarget }
local warnedNoChannel = false

-- A docked window is visible only while its tab is selected
local function IsSelected(frame)
    if not frame or not frame:IsVisible() then return false end
    return frame.isDocked or _G.SELECTED_CHAT_FRAME == frame
end

local function SelectedDef()
    for _, def in ipairs(TABS) do
        if IsSelected(def.frame) then return def end
    end
    return nil
end

local function CommunityChannelId()
    if addonTable.Key and addonTable.Key.HasKey() then return addonTable.Key.ChannelId() end
    return Most.GetChannelId()
end

-- The input the game uses for this window (with the "classic" chat style it is the main window's)
local function InputFor(frame)
    if _G.ChatEdit_ChooseBoxForSend then return _G.ChatEdit_ChooseBoxForSend(frame) end
    return frame.editBox or (_G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.editBox)
end

-- The input's header: instead of "[7. Jgdh26g9i7]:" (channel number and the name from the key) it shows
-- "Jagódki:" whenever the input is set to the community channel, also after "/7" typed by hand
local PROMPT = "|cff7f9f7fJagódki:|r"

local function IsCommunityInput(box)
    local id = CommunityChannelId()
    return id ~= nil and box:GetAttribute("chatType") == "CHANNEL" and tonumber(box:GetAttribute("channelTarget")) == id
end

local function DressHeader(box)
    if not box or not IsCommunityInput(box) then return end
    local header = box.header or (box:GetName() and _G[box:GetName() .. "Header"])
    if not header then return end
    header:SetText(PROMPT)
    header:SetWidth(header:GetStringWidth())
    -- The same insets the game uses: room for the header on the left, for its suffix on the right
    local suffix = box.headerSuffix or (box:GetName() and _G[box:GetName() .. "HeaderSuffix"])
    box:SetTextInsets(15 + header:GetWidth(), 13 + ((suffix and suffix:IsShown() and suffix:GetWidth()) or 0), 0, 0)
end

local function SetChatType(box, chatType, stickyType, channelTarget)
    box:SetAttribute("chatType", chatType)
    box:SetAttribute("stickyType", stickyType)
    box:SetAttribute("channelTarget", channelTarget)
    if _G.ChatEdit_UpdateHeader then _G.ChatEdit_UpdateHeader(box) end
end

-- Kept for later while the player is typing in the input
local function Restore()
    if not saved or saved.box:HasFocus() then return end
    local s = saved
    saved = nil
    SetChatType(s.box, s.chatType, s.stickyType, s.channelTarget)
end

-- Called on tab changes, when the window shows or hides, and every few seconds (the channel number can
-- change, e.g. after a new key). Nothing is changed while the player is typing.
local function UpdateInput()
    local def = SelectedDef()
    if not def then Restore() return end
    local id = CommunityChannelId()
    local box = InputFor(def.frame)
    if not box or box:HasFocus() then return end
    if not id then
        -- Not on the channel yet (a few seconds after login): the input stays as it was, so we say so once
        Restore()
        if not warnedNoChannel then
            warnedNoChannel = true
            def.frame:AddMessage("|cffff5555[System]: The community channel is not joined yet - wait a moment before writing here.|r")
        end
        return
    end
    if saved and saved.box ~= box then Restore() end
    if not saved then
        saved = { box = box, chatType = box:GetAttribute("chatType"), stickyType = box:GetAttribute("stickyType"), channelTarget = box:GetAttribute("channelTarget") }
    end
    if box:GetAttribute("chatType") ~= "CHANNEL" or box:GetAttribute("channelTarget") ~= id then
        SetChatType(box, "CHANNEL", "CHANNEL", id)
    end
end

local function WatchSelection(def)
    if not def.frame or def.watched == def.frame then return end
    def.watched = def.frame
    def.frame:HookScript("OnShow", UpdateInput)
    def.frame:HookScript("OnHide", UpdateInput)
end

local hooked = false
local function InitHooks()
    if hooked then return end
    hooked = true
    if _G.FCF_Tab_OnClick then _G.hooksecurefunc("FCF_Tab_OnClick", function() UpdateInput() end) end
    -- After the game writes the header, ours replaces it for the community channel. Older clients use the
    -- global ChatEdit_UpdateHeader, newer ones (WoW Forever) a method of each input, so both are hooked,
    -- and also showing the input and focusing it (one frame later, after the game's own update).
    if _G.ChatEdit_UpdateHeader then _G.hooksecurefunc("ChatEdit_UpdateHeader", DressHeader) end
    local function Later(box) C_Timer.After(0, function() DressHeader(box) end) end
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local box = _G["ChatFrame" .. i .. "EditBox"]
        if box then
            if box.UpdateHeader then _G.hooksecurefunc(box, "UpdateHeader", DressHeader) end
            box:HookScript("OnShow", Later)
            box:HookScript("OnEditFocusGained", Later)
        end
    end
    C_Timer.NewTicker(CHECK_INTERVAL, UpdateInput)
end

local function Setup()
    InitHooks()
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local name, _, _, _, _, _, shown, _, docked = _G.GetChatWindowInfo(i)
        if name == OBSOLETE_TAB and (shown or docked) and _G.FCF_Close then _G.FCF_Close(_G["ChatFrame" .. i]) end
    end
    for _, def in ipairs(TABS) do
        def.frame = FindTab(def) or CreateTab(def)
        WatchSelection(def)
    end
    UpdateInput()
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
