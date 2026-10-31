-- ============================================================================
-- MONITOR: sync log and addon statistics (Monitoring tab, officers only)
-- ============================================================================
--  * Log: every addon packet sent and received, plus errors and changes of the relay, linked guilds
--    and channel. Only packet types and player names, never message contents.
--  * The last LOG_SIZE entries are kept in memory for this session; older ones are overwritten.
--  * Statistics under the log refresh once a second while the tab is visible.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local GetTime = _G.GetTime
local date = _G.date
local strsplit = _G.strsplit
local ipairs, pairs, tostring = _G.ipairs, _G.pairs, _G.tostring
local table, math, wipe = _G.table, _G.math, _G.wipe

local LOG_SIZE = 500
local STATS_HEIGHT = 145
local WATCH_INTERVAL = 5          -- how often we check the relay and linked guilds (s)
local CHANNEL_LIST_INTERVAL = 30  -- how often an open tab reads the channel member list (s)
local MAX_NAMES_SHOWN = 15

-- Packet type -> filter category and description
local TYPES = {
    GMSG = { "chat", "chat message" }, HIST = { "chat", "chat history" }, HREQ = { "chat", "history request" }, HCLAIM = { "chat", "history request taken" },
    EV_ADD = { "events", "event" }, EV_DESC = { "events", "event description" }, EV_EDIT = { "events", "event edit" }, EV_REM = { "events", "event removed" },
    EV_RM = { "events", "event removal marker" }, EV_REQ = { "events", "events request" }, EV_CLAIM = { "events", "events request taken" }, EV_ROS = { "events", "sign-up list" },
    EV_SIGN = { "events", "sign-up" }, EV_SPEC = { "events", "sign-up spec" }, EV_RL = { "events", "raid leader mark" }, EV_KICK = { "events", "removal from event" },
    RF = { "rosters", "full roster" }, RD = { "rosters", "roster change" }, RQ = { "rosters", "roster request" },
    MUTE = { "mutes", "mute" }, MREQ = { "mutes", "mutes request" }, MCLAIM = { "mutes", "mutes request taken" },
    PING = { "presence", "hello" }, PONG = { "presence", "online signal" }, PROF = { "presence", "professions" },
    NREQ = { "presence", "note request" }, NOTE = { "presence", "public note" },
}
local FILTERS = {
    { key = "all", label = "All" }, { key = "chat", label = "Chat" }, { key = "events", label = "Events" }, { key = "rosters", label = "Rosters" },
    { key = "mutes", label = "Mutes" }, { key = "presence", label = "Presence" }, { key = "errors", label = "Errors" },
}

local Monitor = {}
addonTable.Monitor = Monitor

-- Context from core.lua: activePlayers
local ctx, logFrame, statsText, filterButtons = nil, nil, nil, {}
local entries = {}           -- { cat, err, text }
local currentFilter = "all"
local startedAt = GetTime()
local stats = {
    tx = 0, txBytes = 0, txFailed = 0, rx = 0, rxBytes = 0, errors = 0, throttled = 0,
    lastError = nil, txTimes = {}, rxTimes = {}, byType = {},
}
local lastRelay, lastLinked = nil, nil

local function Matches(entry)
    if currentFilter == "all" then return true end
    if currentFilter == "errors" then return entry.err end
    return entry.cat == currentFilter
end

local function Add(cat, err, text)
    local entry = { cat = cat, err = err, text = "|cff808080" .. date("%H:%M:%S") .. "|r " .. text }
    table.insert(entries, entry)
    if #entries > LOG_SIZE then table.remove(entries, 1) end
    if logFrame and Matches(entry) then logFrame:AddMessage(entry.text) end
end

-- Keeps only the times of the last minute, for the rate per minute
local function Stamp(times)
    local now = GetTime()
    table.insert(times, now)
    while times[1] and now - times[1] > 60 do table.remove(times, 1) end
end

local function RecentCount(times)
    local now, count = GetTime(), 0
    for _, t in ipairs(times) do if now - t <= 60 then count = count + 1 end end
    return count
end

local function Describe(pType)
    local info = TYPES[pType]
    return info and info[2] or pType, info and info[1] or "other"
end

-- ============================================================================
-- CALLED BY bridge.lua
-- ============================================================================
function Monitor.TX(msg, kind, target, ok, result)
    local pType, rest = strsplit(":", msg, 2)
    local suffix = ""
    -- A wrapped packet: the type inside, and whose packet it carries
    if pType == "FW" and rest then
        local origin, inner = strsplit(":", rest, 2)
        pType = strsplit(":", inner or "", 2)
        suffix = " |cff808080(forward for " .. tostring(origin) .. ")|r"
    end
    local label, cat = Describe(pType)
    stats.tx = stats.tx + 1
    stats.txBytes = stats.txBytes + #msg
    stats.byType[pType] = (stats.byType[pType] or 0) + 1
    Stamp(stats.txTimes)
    local peer = target and (" -> " .. target) or ""
    if ok then
        Add(cat, false, "|cff66ccffTX|r " .. kind .. " " .. label .. peer .. suffix)
    else
        stats.txFailed = stats.txFailed + 1
        Monitor.Error("Send failed: " .. label .. peer .. " (" .. kind .. ", result " .. tostring(result) .. ")")
    end
end

function Monitor.RX(text, channel, sender)
    local pType = strsplit(":", text, 2)
    local label, cat = Describe(pType)
    stats.rx = stats.rx + 1
    stats.rxBytes = stats.rxBytes + #text
    stats.byType[pType] = (stats.byType[pType] or 0) + 1
    Stamp(stats.rxTimes)
    local via = (channel == "FW") and "via relay" or channel
    Add(cat, false, "|cff66ff99RX|r " .. tostring(via) .. " " .. label .. " <- " .. tostring(sender))
end

-- The game's temporary limit: the packet stays in the queue and is sent again
function Monitor.Throttled(msg)
    stats.throttled = stats.throttled + 1
    Add("system", false, "|cffffd100Limit reached, retrying:|r " .. Describe((strsplit(":", msg, 2))))
end

function Monitor.Error(text)
    stats.errors = stats.errors + 1
    stats.lastError = date("%H:%M:%S") .. " " .. text
    Add("system", true, "|cffff5555" .. text .. "|r")
end

function Monitor.Note(text)
    Add("system", false, "|cffffd100" .. text .. "|r")
end

-- ============================================================================
-- STATISTICS
-- ============================================================================
local function Kilobytes(bytes)
    return string.format("%.1f KB", bytes / 1024)
end

local function BuildStats()
    local Most = addonTable.Most
    local info = Most.GetMonitorInfo()
    local lines = {}
    local channel = info.channelId and ("|cff00ff00connected|r (" .. info.channelName .. ", /" .. info.channelId .. ")")
        or ("|cffff5555not connected|r" .. (info.channelProblem and (" - " .. info.channelProblem) or ""))
    table.insert(lines, "|cffffd100Channel:|r " .. channel)
    local names = info.channelMembers
    local shown = {}
    for i = 1, math.min(#names, MAX_NAMES_SHOWN) do shown[i] = names[i] end
    table.insert(lines, "|cffffd100On the channel (" .. #names .. "):|r " .. (#names > 0 and table.concat(shown, ", ") or "-")
        .. (#names > MAX_NAMES_SHOWN and (" +" .. (#names - MAX_NAMES_SHOWN) .. " more") or ""))
    table.insert(lines, "|cffffd100Your guild relay:|r " .. (info.relay or "-") .. (info.isRelay and " |cff00ff00(you)|r" or "")
        .. "   |cffffd100Linked guilds:|r " .. (#info.linked > 0 and table.concat(info.linked, ", ") or "-"))
    table.insert(lines, string.format("|cff66ccffTX:|r %d packets, %s, %d/min, %d failed, %d limited   |cff66ff99RX:|r %d packets, %s, %d/min",
        stats.tx, Kilobytes(stats.txBytes), RecentCount(stats.txTimes), stats.txFailed, stats.throttled, stats.rx, Kilobytes(stats.rxBytes), RecentCount(stats.rxTimes)))
    table.insert(lines, "|cffffd100Queue:|r " .. info.queueHigh .. " high, " .. info.queueLow .. " low, " .. info.queueGuild .. " /g lines   |cffffd100Chat log:|r " .. info.history .. " messages")
    -- Who has which version
    local versions, online = {}, 0
    for _, p in ipairs(ctx.activePlayers) do
        online = online + 1
        local v = p.version or "?"
        versions[v] = (versions[v] or 0) + 1
    end
    local versionList = {}
    for v, count in pairs(versions) do table.insert(versionList, v .. " x" .. count) end
    table.sort(versionList)
    table.insert(lines, "|cffffd100Addon users online:|r " .. online .. " (" .. table.concat(versionList, ", ") .. ")   |cffffd100Uptime:|r " .. math.floor((GetTime() - startedAt) / 60) .. " min")
    -- The busiest packet types
    local byType = {}
    for pType, count in pairs(stats.byType) do table.insert(byType, { pType, count }) end
    table.sort(byType, function(a, b) return a[2] > b[2] end)
    local top = {}
    for i = 1, math.min(#byType, 6) do top[i] = byType[i][1] .. " " .. byType[i][2] end
    table.insert(lines, "|cffffd100Busiest:|r " .. (#top > 0 and table.concat(top, ", ") or "-"))
    local rejected = {}
    for reason, count in pairs(info.rejected) do table.insert(rejected, reason .. " " .. count) end
    table.sort(rejected)
    table.insert(lines, "|cffffd100Rejected:|r " .. (#rejected > 0 and table.concat(rejected, ", ") or "-"))
    table.insert(lines, (stats.errors > 0 and "|cffff5555Errors: " or "|cffffd100Errors:|r ") .. stats.errors
        .. (stats.lastError and (" - last: " .. stats.lastError) or "") .. (stats.errors > 0 and "|r" or ""))
    return table.concat(lines, "\n")
end

-- Logs changes of the relay and linked guilds, also while the tab is closed
local function WatchLinks()
    if not ctx then return end
    local info = addonTable.Most.GetMonitorInfo()
    local relay = info.relay or "-"
    if lastRelay and relay ~= lastRelay then Monitor.Note("Guild relay changed: " .. lastRelay .. " -> " .. relay) end
    lastRelay = relay
    local linked = table.concat(info.linked, ", ")
    if lastLinked and linked ~= lastLinked then Monitor.Note("Linked guilds: " .. (linked ~= "" and linked or "none")) end
    lastLinked = linked
end

-- ============================================================================
-- UI
-- ============================================================================
local function Rebuild()
    logFrame:Clear()
    for _, entry in ipairs(entries) do
        if Matches(entry) then logFrame:AddMessage(entry.text) end
    end
    for key, btn in pairs(filterButtons) do
        btn:GetFontString():SetTextColor(key == currentFilter and 1 or 0.7, key == currentFilter and 0.82 or 0.7, key == currentFilter and 0 or 0.7)
    end
end

-- c: activePlayers, applyStyle; panel = the Monitoring tab
function Monitor.Attach(panel, c)
    ctx = c
    local x = 0
    for _, filter in ipairs(FILTERS) do
        local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        btn:SetSize(66, 22)
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -2)
        btn:SetText(filter.label)
        btn:SetScript("OnClick", function() currentFilter = filter.key Rebuild() end)
        filterButtons[filter.key] = btn
        x = x + 68
    end
    local clear = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clear:SetSize(50, 22)
    clear:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -2)
    clear:SetText("Clear")
    clear:SetScript("OnClick", function() wipe(entries) Rebuild() end)
    local latest = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    latest:SetSize(55, 22)
    latest:SetPoint("RIGHT", clear, "LEFT", -2, 0)
    latest:SetText("Latest")

    local statsBox = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    statsBox:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    statsBox:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    statsBox:SetHeight(STATS_HEIGHT)
    c.applyStyle(statsBox)
    statsText = statsBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statsText:SetPoint("TOPLEFT", statsBox, "TOPLEFT", 8, -6)
    statsText:SetPoint("BOTTOMRIGHT", statsBox, "BOTTOMRIGHT", -8, 6)
    statsText:SetJustifyH("LEFT")
    statsText:SetJustifyV("TOP")

    local logBox = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    logBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -28)
    logBox:SetPoint("BOTTOMRIGHT", statsBox, "TOPRIGHT", 0, 4)
    c.applyStyle(logBox)
    logFrame = CreateFrame("ScrollingMessageFrame", nil, logBox)
    logFrame:SetPoint("TOPLEFT", logBox, "TOPLEFT", 8, -6)
    logFrame:SetPoint("BOTTOMRIGHT", logBox, "BOTTOMRIGHT", -8, 6)
    logFrame:SetFontObject("GameFontHighlightSmall")
    logFrame:SetMaxLines(LOG_SIZE)
    logFrame:SetFading(false)
    logFrame:SetJustifyH("LEFT")
    logFrame:EnableMouseWheel(true)
    -- Wheel: 3 lines (Shift = page, Ctrl = start / end)
    logFrame:SetScript("OnMouseWheel", function(self, delta)
        if _G.IsControlKeyDown() then
            if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
        elseif _G.IsShiftKeyDown() then
            if delta > 0 then self:PageUp() else self:PageDown() end
        else
            for _ = 1, 3 do
                if delta > 0 then self:ScrollUp() else self:ScrollDown() end
            end
        end
    end)
    latest:SetScript("OnClick", function() logFrame:ScrollToBottom() end)
    Rebuild()

    C_Timer.NewTicker(1, function()
        if panel:IsVisible() then statsText:SetText(BuildStats()) end
    end)
    C_Timer.NewTicker(CHANNEL_LIST_INTERVAL, function()
        if panel:IsVisible() then addonTable.Most.RefreshChannelList() end
    end)
    panel:HookScript("OnShow", function()
        addonTable.Most.RefreshChannelList()
        statsText:SetText(BuildStats())
    end)
    C_Timer.NewTicker(WATCH_INTERVAL, WatchLinks)
end
