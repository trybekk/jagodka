-- ============================================================================
-- CHANNEL ORDER (1.3.0): the game's channels first, ours after them
-- ============================================================================
--  * The server keeps the channels in the order the character joined them. Our three channels (public,
--    chat key, officers) often got /1, /2, /3, and General, Trade, LocalDefense moved down to /4, /5, /6
--    (players' reports, 25.11.2026). After login, a /reload and every loading screen, ours go to the end of
--    the list with the game's own reorder (C_ChatInfo.SwapChatChannelsByChannelIndex, the same as dragging
--    them in the game's Channels window). The other channels keep their order. Nothing when already right.
--  * Nobody leaves or joins a channel: only the numbers change. Everything of ours finds its channel by name
--    each time (sending, receiving, /jnX), and sync never uses channels (GUILD and whispers).
--  * One swap at a time, the next one after the game shows the new order. Only out of combat and while no
--    chat input is open. A chat input that remembers a channel number (the game's own and chattab.lua's) gets
--    the new number of the same channel after each swap.
--  * Always on, no switch.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_Timer = addonTable.SafeTimer -- protected callbacks (safe.lua)
local CreateFrame = _G.CreateFrame
local ipairs, type, tonumber, tostring = _G.ipairs, _G.type, _G.tonumber, _G.tostring
local table, GetTime = _G.table, _G.GetTime

local ChannelOrder = {}
addonTable.ChannelOrder = ChannelOrder

local START_DELAY = 15   -- s after login or a loading screen: the game joins its channels first
local RETRY = 5          -- s, in combat or while typing
local STEP_WAIT = 0.5    -- s between checks for the new order after a swap
local STEP_TIMEOUT = 3   -- s without a new order: the game did not do it
local MAX_SWAPS = 40

local running, swaps, pending = false, 0, false

local function Monitor() return addonTable.Monitor end

-- Always on (user: "ten checkbox Keep them first nie jest potrzebny, to zawsze ma działać"); the Settings switch
-- of the first build is gone
function ChannelOrder.Enabled() return true end

-- Our channels by their names (lower case); the key and officers names exist only with a key
local function OurNames()
    local set, Most = {}, addonTable.Most
    local function Add(name) if type(name) == "string" and name ~= "" then set[name:lower()] = true end end
    if Most and Most.ChannelName then Add(Most.ChannelName()) end
    if addonTable.Key and addonTable.Key.ChannelName then Add(addonTable.Key.ChannelName()) end
    if addonTable.Officers and addonTable.Officers.ChannelName then Add(addonTable.Officers.ChannelName()) end
    return set
end

-- { { id, name, ours } } in the game's order (GetChannelList gives id, name, disabled in a row)
local function List()
    local values, list, ours = { _G.GetChannelList() }, {}, OurNames()
    for i = 1, #values do
        local id, name = values[i], values[i + 1]
        if type(id) == "number" and type(name) == "string" then
            -- Also a channel of an older key still joined (log of 25.11: an old officers channel stood at /6,
            -- before ours): our names' form, "Jgd" / "Jgo" + faction + 6 letters or digits
            local mine = ours[name:lower()] == true or name:match("^Jg[do][ah]%w%w%w%w%w%w$") ~= nil
            table.insert(list, { id = id, name = name, ours = mine })
        end
    end
    return list
end

-- The first of ours that stands right before a channel that is not ours: that pair is swapped next
local function NextPair(list)
    for i = 1, #list - 1 do
        if list[i].ours and not list[i + 1].ours then return list[i], list[i + 1] end
    end
    return nil
end

local function Text(list)
    local out = {}
    for _, c in ipairs(list) do table.insert(out, c.id .. "." .. (c.ours and "(Jagodka)" or c.name)) end
    return table.concat(out, " ")
end

-- The chat inputs of the game's chat windows
local function Boxes()
    local out = {}
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local box = _G["ChatFrame" .. i .. "EditBox"]
        if box then table.insert(out, box) end
    end
    return out
end

-- An open chat input (the "IM" chat style keeps the input shown all the time, so not IsShown)
local function Typing()
    if _G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow() then return true end
    for _, box in ipairs(Boxes()) do
        if box:HasFocus() then return true end
    end
    return false
end

-- After a swap: every remembered channel number points at the same channel (by name) as before it
local function Remap(before)
    local function New(old)
        local name = before[tonumber(old) or -1]
        if not name then return old end
        local id = _G.GetChannelName(name)
        return (id and id > 0) and id or old
    end
    for _, box in ipairs(Boxes()) do
        if box:GetAttribute("chatType") == "CHANNEL" then
            local old = box:GetAttribute("channelTarget")
            local new = New(old)
            if new ~= old then box:SetAttribute("channelTarget", new) end
        end
    end
    if addonTable.Zakladka and addonTable.Zakladka.RemapSaved then addonTable.Zakladka.RemapSaved(New) end
end

local Step

-- A check later (one at a time)
local function Later(delay)
    if pending then return end
    pending = true
    C_Timer.After(delay, function() pending = false ChannelOrder.Check() end)
end

-- The running reorder stops for now and tries again later
local function Again(delay)
    running = false
    Later(delay)
end

-- Waits for the game to show the swapped order, then the next swap
local function WaitFor(before, firstId, startedAt)
    C_Timer.After(STEP_WAIT, function()
        local list = List()
        local now = nil
        for _, c in ipairs(list) do if c.name == before[firstId] then now = c.id end end
        if now ~= firstId then
            Remap(before)
            Step()
        elseif GetTime() - startedAt >= STEP_TIMEOUT then
            running = false
            if Monitor() then Monitor().Channel("Channel order: the game did not swap the channels (" .. Text(list) .. ")", true) end
        else
            WaitFor(before, firstId, startedAt)
        end
    end)
end

Step = function()
    if not ChannelOrder.Enabled() then running = false return end
    if _G.InCombatLockdown and _G.InCombatLockdown() then Again(RETRY) return end
    if Typing() then Again(RETRY) return end
    local list = List()
    local ours, other = NextPair(list)
    if not ours then
        running = false
        if swaps > 0 and Monitor() then Monitor().Channel("Channel order: Jagodka channels moved after the game's ones (" .. Text(list) .. ")") end
        swaps = 0
        return
    end
    if swaps >= MAX_SWAPS then
        running, swaps = false, 0
        if Monitor() then Monitor().Channel("Channel order: stopped after " .. MAX_SWAPS .. " swaps (" .. Text(list) .. ")", true) end
        return
    end
    local swap = _G.C_ChatInfo and _G.C_ChatInfo.SwapChatChannelsByChannelIndex
    if type(swap) ~= "function" then
        running = false
        if Monitor() then Monitor().Channel("Channel order: this game client cannot reorder channels", true) end
        return
    end
    local before = {}
    for _, c in ipairs(list) do before[c.id] = c.name end
    local ok, err = pcall(swap, ours.id, other.id)
    if not ok then
        running = false
        if Monitor() then Monitor().Channel("Channel order: the game refused the swap (" .. tostring(err) .. ")", true) end
        return
    end
    swaps = swaps + 1
    WaitFor(before, ours.id, GetTime())
end

-- Starts a reorder when one of ours stands before a channel that is not ours
function ChannelOrder.Check()
    if running or not ChannelOrder.Enabled() then return end
    if not NextPair(List()) then return end
    running, swaps = true, 0
    Step()
end

-- ============================================================================
-- OUR CHANNELS STAY OFF THE GAME'S CHAT WINDOWS (1.3.0)
-- ============================================================================
-- Ticking one of ours in the game's chat settings showed its raw lines (with our tags) in that window, every
-- message twice next to the community tab. The game's checkbox itself is not touched (changing Blizzard's
-- frames can taint them); after the game adds one of our channels to a chat window we take it off again
-- (hooksecurefunc only runs after the game's own code), so the tick goes away on the next refresh.
local unticking = {}

local function OffChatWindows(_, name)
    if type(name) ~= "string" or not OurNames()[name:lower()] or unticking[name] then return end
    unticking[name] = true
    C_Timer.After(0, function()
        unticking[name] = nil
        local Most = addonTable.Most
        if Most and Most.HideFromChat then Most.HideFromChat(name) end
        if Monitor() then Monitor().Channel("Chat window: a Jagodka channel was ticked in the game's chat settings and was taken off again (the addon shows it in its own tab)") end
    end)
end

local hooked = false
local function HookChatWindows()
    if hooked or not _G.hooksecurefunc then return end
    hooked = true
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame and type(frame.AddChannel) == "function" then _G.hooksecurefunc(frame, "AddChannel", OffChatWindows) end
    end
    -- The old global too (on Forever only an alias, the method above may not be called through it)
    if type(_G.ChatFrame_AddChannel) == "function" then _G.hooksecurefunc("ChatFrame_AddChannel", OffChatWindows) end
end

-- After login, a /reload and every loading screen (the game joins its channels on entering the world)
local Listener = CreateFrame("Frame")
Listener:RegisterEvent("PLAYER_ENTERING_WORLD")
addonTable.SafeScript(Listener, "OnEvent", "channelorder.lua", function()
    HookChatWindows()
    Later(START_DELAY)
end)
