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
local C_Timer = addonTable.SafeTimer -- protected callbacks (safe.lua)
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

-- Every community message starts with the blueberry, so in a tab that also shows whispers, guild, party or
-- game channels (Settings > Chats) it is clear at a glance which lines are the community chat
local MARK = "|TInterface\\AddOns\\jagodka\\Media\\blueberry_one.tga:14:14|t "

local function Print(def, e)
    if def.frame and e.src ~= "S" and not addonTable.Mute.IsMuted(e.author) then
        def.frame:AddMessage(MARK .. Most.FormatEntry(e, def.color))
        if not def.lastShownTs or e.ts > def.lastShownTs then def.lastShownTs = e.ts end
    end
end

-- The community's Trade, LFG and officers chats show in the General tab too when ticked in Settings > Chats,
-- after the blueberry with their name and their own color
local EXTRA = {
    Handel = { label = "[Trade]", color = "ffe6a85c" },
    ["Szukaj grupy"] = { label = "[LFG]", color = "ff6cc4e6" },
    Oficerowie = { label = "[Officers]", color = "ffd58cff" },
}
local function PrintExtra(e)
    local extra, def = EXTRA[e.tab], TABS[1]
    if not extra or not def.frame or def.lastShownTs == nil or addonTable.Mute.IsMuted(e.author) then return end
    -- Ticked in Settings, or my own message (written here in that mode, so it does not seem lost)
    if not (addonTable.Settings and addonTable.Settings.ShowsCommunity(e.tab)) and e.author ~= Most.MyName() then return end
    def.frame:AddMessage(MARK .. "|c" .. extra.color .. extra.label .. "|r " .. Most.FormatEntry(e, extra.color))
end

-- After login and /reload: the latest messages again, General together with the chats ticked in Settings
-- (Trade, LFG, the officers chat), in the order they were written
local function Replay(def)
    if not def.frame then return end
    local function Shown(tab) return addonTable.Settings and addonTable.Settings.ShowsCommunity(tab) end
    local list = {}
    for _, e in ipairs(Most.GetLog()) do
        if e.src ~= "S" and (e.tab == def.tab or (def == TABS[1] and EXTRA[e.tab] and Shown(e.tab))) then table.insert(list, e) end
    end
    if def == TABS[1] and addonTable.Officers and Shown("Oficerowie") then
        for _, e in ipairs(addonTable.Officers.GetLog()) do table.insert(list, e) end
    end
    table.sort(list, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
    local first = math.max(1, #list - REPLAY_COUNT + 1)
    def.frame:AddMessage("|cff808080--- " .. def.name .. ": last messages ---|r")
    def.lastShownTs = 0
    for i = first, #list do
        if list[i].tab == def.tab then Print(def, list[i]) else PrintExtra(list[i]) end
    end
end

local function ReplayAll()
    for _, def in ipairs(TABS) do Replay(def) end
end

Most.OnNewEntry(function(e, live)
    local def = DefFor(e.tab)
    if not def then
        if live and e.src ~= "S" then PrintExtra(e) end
        return
    end
    if def.lastShownTs == nil then return end
    if live or e.ts > def.lastShownTs then Print(def, e) end
end)
-- The officers chat has its own log (officers.lua), never part of the shared one
if addonTable.Officers then
    addonTable.Officers.OnNewMessage(function(e, live)
        if live then PrintExtra(e) end
    end)
end

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

-- MODES of the input in our tab: the community's General (default), Trade, LFG and, for officers, the officers
-- chat. "/jntrade" + Tab (or a space) switches the input, its header shows "Jagódki Trade:" and every message
-- goes there until another mode is chosen. Trade and LFG go on the same chat channel as General with their tag
-- ("[Trade] "), which every client reads (bridge.lua); the officers chat on its own channel (officers.lua).
-- Kept per input. Only hooks are used (never a replaced handler), so other chat addons keep working, and every
-- hook is wrapped in pcall: an error from another addon's state cannot break the game's chat.
local MODES = {
    -- "/jnglobal", not "/jn": typing "/jntrade" passes through "/jn", which switched the input too early
    Ogolny = { cmd = "jnglobal", label = "Jagódki", color = "7f9f7f" },
    Handel = { cmd = "jntrade", label = "Jagódki Trade", color = "e6a85c", tag = "[Trade] " },
    ["Szukaj grupy"] = { cmd = "jnlfg", label = "Jagódki LFG", color = "6cc4e6", tag = "[LFG] " },
    Oficerowie = { cmd = "jnofficers", label = "Jagódki Officers", color = "d58cff", officers = true },
}
local MODE_BY_CMD = {}
for key, m in pairs(MODES) do MODE_BY_CMD[m.cmd] = key end
local modeOf = setmetatable({}, { __mode = "k" })   -- input -> mode key (missing = General)

local function Safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and addonTable.Monitor then addonTable.Monitor.Error("Chat input: " .. tostring(err)) end
end

-- The channel a mode writes on (nil = not joined yet)
local function TargetFor(mode)
    if mode == "Oficerowie" then return addonTable.Officers and addonTable.Officers.ChannelId() end
    return CommunityChannelId()
end

-- Which of our modes the input is set to now, or nil (another chat: /g, /w...)
local function InputMode(box)
    if not box or box:GetAttribute("chatType") ~= "CHANNEL" then return nil end
    local target = tonumber(box:GetAttribute("channelTarget"))
    if not target then return nil end
    local officers = addonTable.Officers and addonTable.Officers.ChannelId()
    if officers and target == officers then return "Oficerowie" end
    if target == CommunityChannelId() then
        local m = modeOf[box]
        return (m and m ~= "Oficerowie") and m or "Ogolny"
    end
    return nil
end

-- The input's header: instead of "[7. Jgdh26g9i7]:" (channel number and the name from the key) it shows
-- "Jagódki:" (or the mode's name) whenever the input is set to one of our chats, also after "/7" typed by hand
local function DressHeader(box)
    local mode = InputMode(box)
    if not mode then return end
    local header = box.header or (box:GetName() and _G[box:GetName() .. "Header"])
    if not header then return end
    local m = MODES[mode]
    header:SetText("|cff" .. m.color .. m.label .. ":|r")
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
    DressHeader(box)
end

-- Sets the input to a mode; false when its channel is not there (the officers chat for a non-officer)
local function ApplyMode(box, mode)
    if not box then return false end
    mode = MODES[mode] and mode or "Ogolny"
    local id = TargetFor(mode)
    if not id then
        if mode ~= "Ogolny" and _G.DEFAULT_CHAT_FRAME then
            _G.DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[Jagodka]: " .. MODES[mode].label .. " is not available right now.|r")
        end
        return false
    end
    modeOf[box] = mode
    SetChatType(box, "CHANNEL", "CHANNEL", id)
    return true
end

-- Kept for later while the player is typing in the input
local function Restore()
    if not saved or saved.box:HasFocus() then return end
    local s = saved
    saved = nil
    SetChatType(s.box, s.chatType, s.stickyType, s.channelTarget)
end

-- Called on tab changes, when the window shows or hides, and every few seconds (the channel number can
-- change, e.g. after a new key). Nothing is changed while the player is typing. Keeps the chosen mode.
local function UpdateInput()
    local def = SelectedDef()
    if not def then Restore() return end
    local box = InputFor(def.frame)
    if not box or box:HasFocus() then return end
    local mode = modeOf[box] or "Ogolny"
    if not TargetFor(mode) then mode = "Ogolny" end
    local id = TargetFor(mode)
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
    if InputMode(box) ~= mode then ApplyMode(box, mode) end
end

-- After a message is sent from our tab on any chat (/g, /p, /w...), the input goes back to its mode (General,
-- Trade, LFG, officers), so the next Enter or click writes there again instead of the game remembering /g. Only
-- once the input has closed: a "/w Name" that only switches the input is left alone. R (reply) still works.
local function BackToCommunity(box)
    C_Timer.After(0, function()
        if not box or box:HasFocus() or not SelectedDef() then return end
        local mode = modeOf[box] or "Ogolny"
        if InputMode(box) ~= mode then Safe(ApplyMode, box, TargetFor(mode) and mode or "Ogolny") end
    end)
end

-- Trade and LFG: the game sends the text itself on the chat channel; right before it does (after it parsed the
-- text, ChatEdit_ParseText), the tag goes in front, unless it is a command or already tagged
local function TagBeforeSend(box, send)
    if send ~= 1 or not box then return end
    local mode = InputMode(box)
    local tag = mode and MODES[mode].tag
    if not tag then return end
    local text = box:GetText() or ""
    if text:find("%S") and not text:find("^%s*/") and text:sub(1, #tag) ~= tag then box:SetText(tag .. text) end
end

-- "/jntrade" + Tab or a space: switches the input to that mode (like "/g " in the game)
local function SwitchFromText(box, needSpace)
    local text = box:GetText() or ""
    local cmd = needSpace and text:match("^/(%a+) $") or text:match("^/(%a+)%s*$")
    local mode = cmd and MODE_BY_CMD[cmd:lower()]
    if not mode then return end
    if ApplyMode(box, mode) then box:SetText("") end
end

-- Sends a message to one of our chats from a command ("/jntrade text")
local function SendTo(mode, msg)
    local me, guild = Most.MyName(), Most.MyGuild()
    if mode == "Oficerowie" then
        local ok, why = addonTable.Officers.Say(msg)
        if not ok and _G.DEFAULT_CHAT_FRAME then _G.DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[Jagodka]: " .. tostring(why) .. "|r") end
        return
    end
    if addonTable.Mute.IsMuted(me) then
        if _G.DEFAULT_CHAT_FRAME then _G.DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[Jagodka]: You are muted on the community chat - message not sent.|r") end
    elseif guild and Most.IsGuildAllowed(guild) then
        Most.PublishTyped(mode, msg, me, guild)
    end
end

-- "/jnglobal", "/jntrade", "/jnlfg", "/jnofficers": with text, it goes to that chat from any chat tab; without
-- text, the input switches to it
for mode, m in pairs(MODES) do
    local id = "JAGODKA" .. m.cmd:upper()
    _G["SLASH_" .. id .. "1"] = "/" .. m.cmd
    _G.SlashCmdList[id] = function(msg, box)
        msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if msg ~= "" then Safe(SendTo, mode, msg) end
        local target = box or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow()) or (_G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.editBox)
        -- After the game resets the input following the command
        -- Without text: that mode; with text: the input keeps its mode
        local nextMode = (msg == "") and mode or ((target and modeOf[target]) or "Ogolny")
        C_Timer.After(0, function() Safe(ApplyMode, target, nextMode) end)
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
    if _G.ChatEdit_UpdateHeader then _G.hooksecurefunc("ChatEdit_UpdateHeader", function(box) Safe(DressHeader, box) end) end
    -- The tag for Trade and LFG right before the game sends (global function and, on newer clients, a method)
    if _G.ChatEdit_ParseText then _G.hooksecurefunc("ChatEdit_ParseText", function(box, send) Safe(TagBeforeSend, box, send) end) end
    local function Later(box) C_Timer.After(0, function() Safe(DressHeader, box) end) end
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local box = _G["ChatFrame" .. i .. "EditBox"]
        if box then
            if box.UpdateHeader then _G.hooksecurefunc(box, "UpdateHeader", function(b) Safe(DressHeader, b) end) end
            -- Both where both exist: the tag is added only once (TagBeforeSend checks)
            if box.ParseText then _G.hooksecurefunc(box, "ParseText", function(b, send) Safe(TagBeforeSend, b, send) end) end
            box:HookScript("OnShow", Later)
            box:HookScript("OnEditFocusGained", Later)
            box:HookScript("OnEnterPressed", BackToCommunity)
            -- "/jntrade" + Tab, or + a space
            box:HookScript("OnTabPressed", function(b) Safe(SwitchFromText, b, false) end)
            box:HookScript("OnTextChanged", function(b, userInput) if userInput then Safe(SwitchFromText, b, true) end end)
        end
    end
    C_Timer.NewTicker(CHECK_INTERVAL, UpdateInput)
end

-- The other messages chosen in Settings > Chats (settings.lua)
local function ApplySettings()
    if addonTable.Settings then addonTable.Settings.ApplyChatTab(TABS[1].frame) end
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
    ApplySettings()
end
-- The community tab's chat window (settings.lua adds the other messages chosen in Settings > Chats)
function Zakladka.Frame() return TABS[1].frame end
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
addonTable.SafeScript(Listener, "OnEvent", "chattab.lua:439", function()
    -- Chat windows are ready a moment after login
    C_Timer.After(3, Setup)
    C_Timer.After(REPLAY_DELAY, ReplayAll)
    -- Game channels (General, Trade...) are joined a moment after login: the chosen ones are added again then
    C_Timer.After(REPLAY_DELAY, ApplySettings)
end)
