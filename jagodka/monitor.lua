-- ============================================================================
-- MONITOR: sync log and addon statistics (Monitoring tab, officers only)
-- ============================================================================
--  * Log: every addon packet sent and received with its size, queue time and route, plus errors, sync
--    stages and changes of the relay, linked guilds and channel. Names, event titles and packet
--    types only, never message or note contents.
--  * Network view: relays of all guilds, our own links, players, channel, sync stages, packet types.
--    We only see our own links: relays of other guilds come from the same rule everyone computes.
--  * The last LOG_SIZE entries are kept in memory for this session; older ones are overwritten.
--  * Statistics and the Network view refresh once a second while the tab is visible.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local GetTime = _G.GetTime
local UnitName = _G.UnitName
local date = _G.date
local pcall = _G.pcall
local strsplit = _G.strsplit
local ipairs, pairs, tostring, tonumber = _G.ipairs, _G.pairs, _G.tostring, _G.tonumber
local table, math, string, wipe = _G.table, _G.math, _G.string, _G.wipe

local LOG_SIZE = 1000
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
    { key = "mutes", label = "Mutes" }, { key = "presence", label = "Presence" }, { key = "relay", label = "Relay" }, { key = "sync", label = "Sync" },
    { key = "errors", label = "Errors" },
}
local SYNC_STAGES = { "channel", "history", "events", "rosters" }

local Monitor = {}
addonTable.Monitor = Monitor

-- Context from core.lua: activePlayers
local ctx, logFrame, statsText, filterButtons = nil, nil, nil, {}
local netScroll, netChild, netText, networkBtn = nil, nil, nil, nil
local entries = {}           -- { cat, err, relay, text }
local currentFilter = "all"
local showNetwork = false
local startedAt = GetTime()
local stats = {
    tx = 0, txBytes = 0, txFailed = 0, rx = 0, rxBytes = 0, errors = 0, throttled = 0,
    lastError = nil, txTimes = {}, rxTimes = {}, byType = {},
}
local peers = {}             -- name -> { tx, rx, fwTx, fwRx, lastTx, lastRx }: who we exchange packets with directly
local syncStages = {}        -- stage -> latest state, also after the sync bar has cleared its own
local lastRelays, lastLinked, lastOnline, lastLocked = {}, nil, nil, false

local function Matches(entry)
    if currentFilter == "all" then return true end
    if currentFilter == "errors" then return entry.err end
    if currentFilter == "relay" and entry.relay then return true end
    return entry.cat == currentFilter
end

local function Add(cat, err, text, relay)
    local entry = { cat = cat, err = err, relay = relay, text = "|cff808080" .. date("%H:%M:%S") .. "|r " .. text }
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

local function Peer(name)
    if not peers[name] then peers[name] = { tx = 0, rx = 0, fwTx = 0, fwRx = 0 } end
    return peers[name]
end

local function TypeStats(pType)
    if not stats.byType[pType] then stats.byType[pType] = { tx = 0, rx = 0, bytes = 0 } end
    return stats.byType[pType]
end

-- Field from a packet of another player: decoded, without formatting codes
local function Field(s)
    local Most = addonTable.Most
    return s and Most.Plain(Most.DecodeField(s)) or "?"
end

-- What the packet is about. Never the text of a message, description or note.
local function Detail(pType, payload)
    if not payload or payload == "" then return nil end
    local a, b, c, d, e = strsplit(":", payload, 6)
    if pType == "GMSG" or pType == "HIST" then return Field(d) .. ", " .. Field(c) .. ", tab " .. Field(e) end
    if pType == "RF" then return Field(a) .. ", part " .. Field(c) .. "/" .. Field(d) end
    if pType == "RD" then return Field(a) end
    if pType == "RQ" then return Field(a) end
    if pType == "HCLAIM" or pType == "MCLAIM" or pType == "EV_CLAIM" then return "for " .. Field(a) end
    if pType == "HREQ" or pType == "MREQ" then
        local since = tonumber(a) or 0
        return since > 0 and ("newer than " .. date("%d.%m %H:%M", since)) or "everything"
    end
    if pType == "PING" or pType == "PONG" then
        local guild, version = c, e
        return Field(guild) .. ", v" .. Field(version)
    end
    if pType == "EV_ADD" then return Field(b) .. ", " .. Field(c) .. " " .. Field(d) end
    if pType == "EV_EDIT" then return Field(c) .. ", " .. Field(d) .. " " .. Field(e) end
    if pType == "EV_DESC" then return "event " .. Field(a) .. ", part " .. Field(b) end
    if pType == "EV_KICK" then return Field(b) .. " from event " .. Field(a) .. ", by " .. Field(d) end
    if pType == "EV_SIGN" or pType == "EV_SPEC" then return "event " .. Field(a) .. ", " .. Field(b) end
    if pType == "EV_RL" then return "event " .. Field(a) .. ", " .. (b == "1" and "set" or "cleared") end
    if pType == "EV_REM" or pType == "EV_RM" or pType == "EV_ROS" then return "event " .. Field(a) end
    if pType == "MUTE" then return Field(a) .. ", " .. (b == "1" and "muted" or "unmuted") .. ", by " .. Field(d) end
    if pType == "NREQ" or pType == "NOTE" then return Field(a) end
    return nil
end

-- A diagnostic must never stop a packet, whatever the packet contains
local function SafeDetail(pType, payload)
    local ok, detail = pcall(Detail, pType, payload)
    return ok and detail and (" |cffc0c0c0[" .. detail .. "]|r") or ""
end

-- ============================================================================
-- CALLED BY bridge.lua AND sync.lua
-- ============================================================================
-- waited: seconds in our send queue; tries: how many times the game's limit made it wait
function Monitor.TX(msg, kind, target, ok, result, waited, tries)
    local pType, payload = strsplit(":", msg, 2)
    local route = kind .. (target and (" -> " .. target) or "")
    local isForward = false
    -- A wrapped packet: the type inside, and whose packet it carries
    if pType == "FW" and payload then
        local origin, inner = strsplit(":", payload, 2)
        pType, payload = strsplit(":", inner or "", 2)
        isForward = true
        if origin == UnitName("player") then route = "greeting -> " .. tostring(target)
        elseif target then route = "relay -> " .. target .. " |cff808080(from " .. tostring(origin) .. ")|r"
        else route = "repost to my guild |cff808080(from " .. tostring(origin) .. ")|r" end
    end
    local label, cat = Describe(pType)
    local byType = TypeStats(pType)
    stats.tx = stats.tx + 1
    stats.txBytes = stats.txBytes + #msg
    byType.tx = byType.tx + 1
    byType.bytes = byType.bytes + #msg
    Stamp(stats.txTimes)
    if target then
        local peer = Peer(target)
        peer.tx = peer.tx + 1
        peer.lastTx = GetTime()
        if isForward then peer.fwTx = peer.fwTx + 1 end
    end
    if ok then
        local timing = (waited and waited >= 1) and string.format(", waited %.1f s", waited) or ""
        if tries and tries > 0 then timing = timing .. ", " .. tries .. " retries" end
        Add(cat, false, "|cff66ccffTX|r " .. route .. ": " .. label .. SafeDetail(pType, payload) .. " |cff808080" .. #msg .. " B" .. timing .. "|r", isForward)
    else
        stats.txFailed = stats.txFailed + 1
        Monitor.Error("Send failed: " .. label .. " " .. route .. " (result " .. tostring(result) .. ")")
    end
end

-- deliverer and delivery only for a wrapped packet: who handed it to us, and how (WHISPER = a relay
-- whispered it to us, GUILD = a guildmate reposted it)
function Monitor.RX(text, channel, sender, deliverer, delivery)
    local pType, payload = strsplit(":", text, 2)
    local Plain = addonTable.Most.Plain
    pType = Plain(pType)
    local label, cat = Describe(pType)
    local byType = TypeStats(pType)
    stats.rx = stats.rx + 1
    stats.rxBytes = stats.rxBytes + #text
    byType.rx = byType.rx + 1
    byType.bytes = byType.bytes + #text
    Stamp(stats.rxTimes)
    local direct = deliverer or sender
    local peer = Peer(direct)
    peer.rx = peer.rx + 1
    peer.lastRx = GetTime()
    local route = tostring(channel) .. " <- " .. tostring(sender)
    if deliverer then
        peer.fwRx = peer.fwRx + 1
        if delivery == "WHISPER" and deliverer == sender then route = "greeting <- " .. tostring(sender)
        elseif delivery == "WHISPER" then route = "relay " .. deliverer .. " -> me |cff808080(from " .. tostring(sender) .. ")|r"
        else route = "repost by " .. deliverer .. " |cff808080(from " .. tostring(sender) .. ")|r" end
    end
    Add(cat, false, "|cff66ff99RX|r " .. route .. ": " .. label .. SafeDetail(pType, payload) .. " |cff808080" .. #text .. " B|r", deliverer ~= nil)
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

function Monitor.Relay(text)
    Add("relay", false, "|cffbf9fff" .. text .. "|r", true)
end

function Monitor.SyncStage(key, text)
    syncStages[key] = date("%H:%M:%S") .. " " .. text
    Add("sync", false, "|cffbf9fffSync " .. key .. ":|r " .. text)
end

-- ============================================================================
-- STATISTICS
-- ============================================================================
local function Kilobytes(bytes)
    return string.format("%.1f KB", bytes / 1024)
end

local function Ago(t)
    return t and (math.floor(GetTime() - t) .. " s ago") or "never"
end

-- Sorted list of the packet types: { type, counters }
local function TypesByTraffic()
    local list = {}
    for pType, counters in pairs(stats.byType) do table.insert(list, { pType, counters }) end
    table.sort(list, function(a, b) return a[2].tx + a[2].rx > b[2].tx + b[2].rx end)
    return list
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
    table.insert(lines, "|cffffd100Queue:|r " .. info.queueHigh .. " high, " .. info.queueLow .. " low"
        .. (info.queueOldest and string.format(" (oldest %.0f s)", info.queueOldest) or "") .. ", " .. info.queueGuild .. " /g lines   |cffffd100Chat log:|r " .. info.history .. " messages")
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
    local byType, top = TypesByTraffic(), {}
    for i = 1, math.min(#byType, 6) do top[i] = byType[i][1] .. " " .. (byType[i][2].tx + byType[i][2].rx) end
    table.insert(lines, "|cffffd100Busiest:|r " .. (#top > 0 and table.concat(top, ", ") or "-"))
    local rejected = {}
    for reason, count in pairs(info.rejected) do table.insert(rejected, reason .. " " .. count) end
    table.sort(rejected)
    table.insert(lines, "|cffffd100Rejected:|r " .. (#rejected > 0 and table.concat(rejected, ", ") or "-"))
    table.insert(lines, (stats.errors > 0 and "|cffff5555Errors: " or "|cffffd100Errors:|r ") .. stats.errors
        .. (stats.lastError and (" - last: " .. stats.lastError) or "") .. (stats.errors > 0 and "|r" or ""))
    return table.concat(lines, "\n")
end

-- ============================================================================
-- NETWORK VIEW
-- ============================================================================
local function Heading(lines, text)
    if #lines > 0 then table.insert(lines, " ") end
    table.insert(lines, "|cffffd100" .. text .. "|r")
end

-- Online players by guild: guild -> sorted names
local function PlayersByGuild()
    local guilds = {}
    for _, p in ipairs(ctx.activePlayers) do
        guilds[p.guild] = guilds[p.guild] or {}
        table.insert(guilds[p.guild], p.name)
    end
    for _, names in pairs(guilds) do table.sort(names) end
    return guilds
end

local function BuildNetwork()
    local Most, Sync = addonTable.Most, addonTable.Sync
    local info = Most.GetMonitorInfo()
    local me, myGuild = UnitName("player"), Most.MyGuild()
    local guilds = PlayersByGuild()
    local lines = {}

    Heading(lines, "Guilds and their relays")
    if myGuild and not guilds[myGuild] then guilds[myGuild] = {} end
    local guildNames = {}
    for guild in pairs(guilds) do table.insert(guildNames, guild) end
    table.sort(guildNames)
    for _, guild in ipairs(guildNames) do
        local relay = Most.GetRelayName(guild)
        local isMine = guild == myGuild
        table.insert(lines, (isMine and "|cff00ff00" or "|cffffffff") .. guild .. (isMine and " (your guild)" or "") .. "|r: relay "
            .. tostring(relay) .. (relay == me and " |cff00ff00(you)|r" or "") .. ", online " .. #guilds[guild] .. ": " .. table.concat(guilds[guild], ", "))
    end
    if info.isRelay then
        table.insert(lines, "You carry packets between your guild and the relays above.")
    elseif info.relayReadyIn then
        table.insert(lines, string.format("Relay role possible in %.0f s (waiting for answers after login).", info.relayReadyIn))
    else
        table.insert(lines, "You are not a relay: packets from other guilds reach you as reposts from " .. tostring(info.relay) .. ".")
    end

    Heading(lines, "Your direct traffic (TX / RX, of which relayed)")
    local peerNames = {}
    for name in pairs(peers) do table.insert(peerNames, name) end
    table.sort(peerNames, function(a, b) return peers[a].tx + peers[a].rx > peers[b].tx + peers[b].rx end)
    if #peerNames == 0 then table.insert(lines, "-") end
    for _, name in ipairs(peerNames) do
        local peer = peers[name]
        table.insert(lines, string.format("%s: %d (%d) / %d (%d), last sent %s, last received %s", name, peer.tx, peer.fwTx, peer.rx, peer.fwRx, Ago(peer.lastTx), Ago(peer.lastRx)))
    end

    Heading(lines, "Players with the addon")
    local players = {}
    for _, p in ipairs(ctx.activePlayers) do table.insert(players, p) end
    table.sort(players, function(a, b)
        if a.guild ~= b.guild then return a.guild < b.guild end
        return a.name < b.name
    end)
    if #players == 0 then table.insert(lines, "-") end
    local isOnline = {}
    for _, p in ipairs(players) do
        isOnline[p.name] = true
        local quiet = GetTime() - (p.lastSeen or 0)
        local color = quiet > Most.ONLINE_TIMEOUT * 0.7 and "|cffff9933" or "|cffc0c0c0"
        table.insert(lines, p.name .. " |cff808080" .. p.guild .. ", v" .. tostring(p.version) .. ", " .. tostring(p.rank) .. "|r " .. color .. "signal " .. math.floor(quiet) .. " s ago|r")
    end

    Heading(lines, "Channel: no answer yet")
    local silent = {}
    for _, name in ipairs(info.channelMembers) do
        if name ~= me and not isOnline[name] then
            local greeted = info.greeted[name]
            table.insert(silent, name .. " |cff808080(" .. (greeted and ("greeted " .. Ago(greeted)) or "not greeted") .. ")|r")
        end
    end
    table.insert(lines, #silent > 0 and table.concat(silent, ", ") or "-")
    table.insert(lines, "List read " .. Ago(info.listAskedAt) .. ". Only a relay greets, every " .. info.helloRetry .. " s per player.")

    Heading(lines, "Sync")
    table.insert(lines, "Officer actions: " .. (Sync.LoginLocked() and "|cffff9933locked|r" or "|cff00ff00available|r"))
    for _, key in ipairs(SYNC_STAGES) do
        table.insert(lines, key .. ": " .. (syncStages[key] or "-"))
    end

    Heading(lines, "Packet types (TX / RX, bytes)")
    local byType = TypesByTraffic()
    if #byType == 0 then table.insert(lines, "-") end
    for _, item in ipairs(byType) do
        table.insert(lines, item[1] .. ": " .. item[2].tx .. " / " .. item[2].rx .. ", " .. Kilobytes(item[2].bytes))
    end
    return table.concat(lines, "\n")
end

local function RefreshNetwork()
    netChild:SetWidth(netScroll:GetWidth())
    netText:SetWidth(netScroll:GetWidth() - 4)
    netText:SetText(BuildNetwork())
    netChild:SetHeight(netText:GetStringHeight() + 4)
end

-- Logs changes of the relays, linked guilds and players, also while the tab is closed
local function WatchLinks()
    if not ctx then return end
    local Most = addonTable.Most
    local info = Most.GetMonitorInfo()
    local guilds = PlayersByGuild()
    local myGuild = Most.MyGuild()
    if myGuild and not guilds[myGuild] then guilds[myGuild] = {} end
    for guild in pairs(guilds) do
        local relay = Most.GetRelayName(guild) or "-"
        if lastRelays[guild] and lastRelays[guild] ~= relay then
            Monitor.Relay("Relay of " .. guild .. " changed: " .. lastRelays[guild] .. " -> " .. relay .. (relay == UnitName("player") and " (you)" or ""))
        end
        lastRelays[guild] = relay
    end
    local linked = table.concat(info.linked, ", ")
    if lastLinked and linked ~= lastLinked then Monitor.Relay("Linked guilds: " .. (linked ~= "" and linked or "none")) end
    lastLinked = linked
    -- Who appeared on and left the online list
    local online = {}
    for _, p in ipairs(ctx.activePlayers) do
        online[p.name] = p.guild
        if lastOnline and not lastOnline[p.name] then
            Add("presence", false, "|cffffd100Online:|r " .. p.name .. " (" .. p.guild .. ", v" .. tostring(p.version) .. ")")
        end
    end
    if lastOnline then
        for name, guild in pairs(lastOnline) do
            if not online[name] then Add("presence", false, "|cffffd100No longer online:|r " .. name .. " (" .. guild .. ")") end
        end
    end
    lastOnline = online
    local locked = addonTable.Sync.LoginLocked()
    if lastLocked and not locked then Monitor.SyncStage("lock", "officer actions available") end
    lastLocked = locked
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
        local active = not showNetwork and key == currentFilter
        btn:GetFontString():SetTextColor(active and 1 or 0.7, active and 0.82 or 0.7, active and 0 or 0.7)
    end
    networkBtn:GetFontString():SetTextColor(showNetwork and 1 or 0.7, showNetwork and 0.82 or 0.7, showNetwork and 0 or 0.7)
    logFrame:SetShown(not showNetwork)
    netScroll:SetShown(showNetwork)
    if showNetwork then RefreshNetwork() end
end

-- c: activePlayers, applyStyle; panel = the Monitoring tab
function Monitor.Attach(panel, c)
    ctx = c
    local x = 0
    for _, filter in ipairs(FILTERS) do
        local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        btn:SetSize(60, 22)
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -2)
        btn:SetText(filter.label)
        btn:SetScript("OnClick", function() currentFilter = filter.key showNetwork = false Rebuild() end)
        filterButtons[filter.key] = btn
        x = x + 62
    end
    networkBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    networkBtn:SetSize(80, 22)
    networkBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -26)
    networkBtn:SetText("Network")
    networkBtn:SetScript("OnClick", function() showNetwork = true Rebuild() end)
    local clear = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clear:SetSize(50, 22)
    clear:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -26)
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
    logBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -52)
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

    -- Network view: in the same box as the log, a scrolled text that keeps its position on refresh
    netScroll = CreateFrame("ScrollFrame", nil, logBox)
    netScroll:SetPoint("TOPLEFT", logBox, "TOPLEFT", 8, -6)
    netScroll:SetPoint("BOTTOMRIGHT", logBox, "BOTTOMRIGHT", -8, 6)
    netChild = CreateFrame("Frame", nil, netScroll)
    netChild:SetSize(1, 1)
    netScroll:SetScrollChild(netChild)
    netText = netChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    netText:SetPoint("TOPLEFT", netChild, "TOPLEFT", 0, 0)
    netText:SetJustifyH("LEFT")
    netText:SetJustifyV("TOP")
    netScroll:EnableMouseWheel(true)
    netScroll:SetScript("OnMouseWheel", function(self, delta)
        local range = math.max(0, netChild:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40)))
    end)
    Rebuild()

    C_Timer.NewTicker(1, function()
        if panel:IsVisible() then
            statsText:SetText(BuildStats())
            if showNetwork then RefreshNetwork() end
        end
    end)
    C_Timer.NewTicker(CHANNEL_LIST_INTERVAL, function()
        if panel:IsVisible() then addonTable.Most.RefreshChannelList() end
    end)
    panel:HookScript("OnShow", function()
        addonTable.Most.RefreshChannelList()
        statsText:SetText(BuildStats())
        if showNetwork then RefreshNetwork() end
    end)
    C_Timer.NewTicker(WATCH_INTERVAL, WatchLinks)
end
