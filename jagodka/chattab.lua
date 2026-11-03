-- ============================================================================
-- TAB IN BLIZZARD CHAT: community General
-- ============================================================================
--  * In addition to the addon window: the same messages in a regular game chat window.
--    "Jagodki Nadina - General" = a copy of the addon's General tab.
--    Trade and LFG stay in the addon window; a Trade tab left by older versions is closed.
--  * Created at login whenever missing, also after the player closes it, and a duplicate
--    with the same name is closed. "/jagodka tab" recreates it.
--  * The tab has its own input, always visible under the window and attached to it, so other chat
--    addons do not move or replace it. Messages go to the addon's General. A click on the input or tab,
--    or Enter, starts writing, and it ends with a click elsewhere, Esc or Enter on an empty input.
--    Enter is rebound only while the tab is selected (not changeable in combat, so it follows
--    after combat). The game's input is not touched. Text starting with "/" moves to the game's input.
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

-- ============================================================================
-- WRITING FROM THE TAB
-- ============================================================================
local INPUT_BUTTON = "JagodkaTabChatButton"
local inputButton, input, inputDef = nil, nil, nil

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

-- Returns false when the text should stay in the input (guild not known yet)
local function SendFromTab(def, text)
    local me, guild = _G.UnitName("player"), Most.MyGuild()
    if addonTable.Mute.IsMuted(me) then
        def.frame:AddMessage("|cffff5555[System]: You are muted on the community chat - message not sent.|r")
    elseif Most.IsGuildAllowed(guild) then
        Most.Publish(def.tab, text, "A", me, guild)
    elseif not guild and _G.IsInGuild() then
        def.frame:AddMessage("|cffff5555[System]: Guild info not loaded yet - try again in a moment (message kept).|r")
        return false
    else
        def.frame:AddMessage("|cffff5555[System]: Your guild (" .. tostring(guild) .. ") is not on the Community list - message not sent.|r")
    end
    return true
end

local function BuildInput()
    local box = CreateFrame("EditBox", "JagodkaTabChatInput", _G.UIParent, "BackdropTemplate")
    box:SetHeight(22)
    box:SetClampedToScreen(true)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    box:SetBackdropColor(0, 0, 0, 0.35)
    box:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
    local fontPath, fontSize, fontFlags = _G.ChatFontNormal:GetFont()
    box:SetFont(fontPath, fontSize - 2, fontFlags)
    box:SetAutoFocus(false)
    box:SetAltArrowKeyMode(false)
    box:SetMaxBytes(Most.MAX_CHAT_BYTES)
    local label = box:CreateFontString(nil, "OVERLAY")
    label:SetFont(fontPath, fontSize - 2, fontFlags)
    label:SetPoint("LEFT", box, "LEFT", 6, 0)
    label:SetText("|cff7f9f7fJagódki:|r")
    box:SetTextInsets(label:GetStringWidth() + 11, 6, 0, 0)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    box:SetScript("OnEnterPressed", function(self)
        local text = _G.strtrim(self:GetText() or "")
        -- Enter on an empty input leaves it; after a message the focus stays until a click elsewhere
        if text == "" then
            self:SetText("")
            self:ClearFocus()
            return
        end
        if not SendFromTab(inputDef, text) then return end
        self:AddHistoryLine(text)
        self:SetText("")
    end)
    -- A click elsewhere ends writing (Shift + click inserts a link, so it does not count)
    local blurWatcher = CreateFrame("Frame")
    _G.pcall(blurWatcher.RegisterEvent, blurWatcher, "GLOBAL_MOUSE_DOWN")
    blurWatcher:SetScript("OnEvent", function()
        if box:HasFocus() and not box:IsMouseOver() and not _G.IsShiftKeyDown() then box:ClearFocus() end
    end)
    -- A slash command (/w, /g, /cast...) goes to the game's own input
    box:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText() or ""
        if userInput and text:sub(1, 1) == "/" and _G.ChatFrame_OpenChat then
            self:SetText("")
            self:ClearFocus()
            _G.ChatFrame_OpenChat(text, inputDef.frame)
        end
    end)
    -- Shift + click inserts a link (the game only inserts links into its own input)
    _G.hooksecurefunc("ChatEdit_InsertLink", function(link)
        if link and box:HasFocus() then box:Insert(link) end
    end)
    return box
end

-- A child of the tab's window: it follows the window, and shows and hides with the tab
local function AttachInput(def)
    if not def.frame then return end
    input = input or BuildInput()
    inputDef = def
    input:SetParent(def.frame)
    input:SetFrameLevel(def.frame:GetFrameLevel() + 5)
    input:ClearAllPoints()
    input:SetPoint("TOPLEFT", def.frame, "BOTTOMLEFT", 0, -2)
    input:SetPoint("TOPRIGHT", def.frame, "BOTTOMRIGHT", 0, -2)
    input:Show()
end

local function OpenInput(def)
    AttachInput(def)
    input:SetFocus()
end

-- Enter points to our input only while our tab is selected. Called on tab changes and after combat.
local function UpdateEnterKey()
    if not inputButton then return end
    if _G.InCombatLockdown() then return end
    _G.ClearOverrideBindings(inputButton)
    if not SelectedDef() then return end
    local keys = { _G.GetBindingKey("OPENCHAT") }
    for _, key in ipairs(keys) do
        _G.SetOverrideBindingClick(inputButton, false, key, INPUT_BUTTON)
    end
end

local function WatchSelection(def)
    if not def.frame or def.watched == def.frame then return end
    def.watched = def.frame
    def.frame:HookScript("OnShow", UpdateEnterKey)
    def.frame:HookScript("OnHide", UpdateEnterKey)
end

local function InitInputButton()
    if inputButton then return end
    inputButton = CreateFrame("Button", INPUT_BUTTON, _G.UIParent)
    inputButton:SetScript("OnClick", function()
        local def = SelectedDef()
        -- The tab changed during combat and the key is not given back yet
        if def then OpenInput(def) elseif _G.ChatFrame_OpenChat then _G.ChatFrame_OpenChat("") end
    end)
    if _G.FCF_Tab_OnClick then
        _G.hooksecurefunc("FCF_Tab_OnClick", function(tab, button)
            UpdateEnterKey()
            -- A left click on our tab goes straight to writing
            local def = SelectedDef()
            if button == "LeftButton" and def and tab == _G[def.frame:GetName() .. "Tab"] then OpenInput(def) end
        end)
    end
end

local function Setup()
    InitInputButton()
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local name, _, _, _, _, _, shown, _, docked = _G.GetChatWindowInfo(i)
        if name == OBSOLETE_TAB and (shown or docked) and _G.FCF_Close then _G.FCF_Close(_G["ChatFrame" .. i]) end
    end
    for _, def in ipairs(TABS) do
        def.frame = FindTab(def) or CreateTab(def)
        WatchSelection(def)
        AttachInput(def)
    end
    UpdateEnterKey()
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
Listener:RegisterEvent("PLAYER_REGEN_ENABLED")
Listener:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then UpdateEnterKey() return end
    -- Chat windows are ready a moment after login
    C_Timer.After(3, Setup)
    C_Timer.After(REPLAY_DELAY, ReplayAll)
end)
