-- ============================================================================
-- ROSTER: members (online and offline) of all listed guilds
-- ============================================================================
-- Blizzard only shows the roster of your own guild, so:
--  * In each guild one person with the addon is the roster SENDER. The sender changes every 5 min
--    (a "random" choice, but computed the same by everyone) to spread the traffic over everyone.
--  * Everyone compares their guild's roster with the previous one every 20 s; only the sender sends.
--    A status change is "+Name" / "-Name"; a new member / level / rank: "Name,W603+".
--  * Full roster: on request from a fresh login (data > 10 min old) and once per 30 min.
--  * Packets have low priority (chat goes first).
--  * Everyone keeps the last known roster in JagodkiRosterDB.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local GetGuildInfo = _G.GetGuildInfo
local GetServerTime = _G.GetServerTime
local GetTime = _G.GetTime
local UnitName = _G.UnitName
local Ambiguate = _G.Ambiguate
local strsplit = _G.strsplit
local pairs, ipairs, tostring, tonumber = _G.pairs, _G.ipairs, _G.tostring, _G.tonumber
local table, math, wipe = _G.table, _G.math, _G.wipe

local Most = addonTable.Most
local Enc, Dec = Most.EncodeField, Most.DecodeField

local MAX_ADDON_BYTES = 225
local FULL_INTERVAL = 1800   -- full roster every 30 min
local FULL_COOLDOWN = 60     -- at most once per minute (several logins at once = one send)
local STALE_AFTER = 600      -- after login we request the roster of a guild whose data is > 10 min old
local READY_DELAY = 15       -- after login we wait until we know the others (otherwise everyone thinks they are the sender)
local SENDER_ROTATION = 300  -- the roster sender changes every this many seconds

local Roster = {}
addonTable.Roster = Roster

-- Context from core.lua: activePlayers, isGuildAllowed, allowedGuilds, onChanged
local ctx = nil
function Roster.Init(c) ctx = c end

-- rosters[guild] = { members = { name = { c = class, l = level, r = rank, o = online } }, ranks = {...}, updated = time }
local rosters = {}
local readyAt = math.huge
local lastFull, lastFullSlot, lastSent = 0, nil, {}
local incoming = {} -- guild -> { id, got = { [idx] = true }, count, total, complete }

local function MyGuild() return (GetGuildInfo("player")) end
local function Changed() if ctx and ctx.onChanged then ctx.onChanged() end end

-- ============================================================================
-- ENTRY ENCODING
-- ============================================================================
local CLASS_CODE = { WARRIOR = "W", PALADIN = "P", HUNTER = "H", ROGUE = "R", PRIEST = "I", SHAMAN = "S", MAGE = "M", WARLOCK = "L", DRUID = "D" }
local CODE_CLASS = {}
for k, v in pairs(CLASS_CODE) do CODE_CLASS[v] = k end

local function EncodeEntry(name, m)
    return name .. "," .. (CLASS_CODE[m.c] or "X") .. (m.l or 1) .. math.min(math.max(m.r or 9, 0), 9) .. (m.o and "+" or "-")
end

local function DecodeEntry(s)
    local name, c, l, r, o = s:match("^([^,]+),(%u)(%d+)(%d)([%+%-])$")
    if not name then return nil end
    return name, { c = CODE_CLASS[c], l = tonumber(l), r = tonumber(r), o = (o == "+") }
end

-- Splits entries into "a;b;c" chunks that fit the limit (the first may have a different limit)
local function Chunk(entries, firstMax, restMax)
    local chunks, current, limit = {}, "", firstMax
    for _, e in ipairs(entries) do
        if current ~= "" and #current + 1 + #e > limit then
            table.insert(chunks, current)
            current, limit = "", restMax
        end
        current = (current == "") and e or (current .. ";" .. e)
    end
    if current ~= "" or #chunks == 0 then table.insert(chunks, current) end
    return chunks
end

-- ============================================================================
-- MY GUILD (from Blizzard's roster)
-- ============================================================================
local function RefreshLocal()
    local guild = MyGuild()
    local n = (_G.GetNumGuildMembers and _G.GetNumGuildMembers()) or 0
    if not guild or n == 0 then return end
    -- With "show offline" turned off Blizzard returns only online players, so we keep the rest as offline
    local complete = not (_G.GetGuildRosterShowOffline and not _G.GetGuildRosterShowOffline())
    local old = rosters[guild] and rosters[guild].members or {}
    local members = {}
    if not complete then
        for name, m in pairs(old) do members[name] = { c = m.c, l = m.l, r = m.r, o = false } end
    end
    for i = 1, n do
        local fullName, _, rankIndex, level, _, zone, _, _, isOnline, _, classFile = _G.GetGuildRosterInfo(i)
        if fullName then
            -- z = location: own guild only, not part of the entries sent to other guilds
            members[Ambiguate(fullName, "none")] = { c = classFile, l = level, r = rankIndex, o = isOnline and true or false, z = zone }
        end
    end
    local ranks = {}
    local numRanks = (_G.GuildControlGetNumRanks and _G.GuildControlGetNumRanks()) or 0
    for i = 1, numRanks do ranks[i] = _G.GuildControlGetRankName(i) end
    rosters[guild] = { members = members, ranks = ranks, updated = GetServerTime(), complete = complete }
    Changed()
end

-- ============================================================================
-- SENDER: rotates every SENDER_ROTATION seconds among online players with the addon in my guild
-- ============================================================================
local function IsSender()
    local guild = MyGuild()
    local g = guild and rosters[guild]
    if not g or not ctx then return false end
    local myName, now = UnitName("player"), GetTime()
    local candidates = { myName }
    for _, p in ipairs(ctx.activePlayers) do
        local m = g.members[p.name]
        if p.name ~= myName and p.guild == guild and m and m.o and (now - (p.lastSeen or 0)) < Most.ONLINE_TIMEOUT then
            table.insert(candidates, p.name)
        end
    end
    table.sort(candidates)
    -- Shift based on the guild name, so different guilds do not change senders at the same moment
    local shift = 0
    for i = 1, #guild do shift = shift + guild:byte(i) end
    local slot = math.floor(GetServerTime() / SENDER_ROTATION)
    return candidates[(slot + shift) % #candidates + 1] == myName
end

-- ============================================================================
-- SENDING (sender only)
-- ============================================================================
local function SendFull()
    local guild = MyGuild()
    local g = guild and rosters[guild]
    if not g then return end
    lastFull = GetTime()
    wipe(lastSent)
    local entries = {}
    for name, m in pairs(g.members) do
        local e = EncodeEntry(name, m)
        lastSent[name] = e
        table.insert(entries, e)
    end
    local rankParts = {}
    for i, r in ipairs(g.ranks) do rankParts[i] = Enc(((r or ""):gsub(",", " "))) end
    local ranks = table.concat(rankParts, ",")
    local snap = tostring(GetServerTime() % 100000)
    -- RF:guild:snap:idx:total:full:ranks:entries  (ranks only in the first part)
    local header = #"RF:" + #Enc(guild) + 1 + #snap + 1 + 3 + 1 + 3 + 1 + 2 + 1
    local chunks = Chunk(entries, MAX_ADDON_BYTES - header - #ranks, MAX_ADDON_BYTES - header)
    for i, chunk in ipairs(chunks) do
        Most.Send("RF", table.concat({ Enc(guild), snap, i, #chunks, g.complete and "1" or "0", (i == 1) and ranks or "", chunk }, ":"), "low")
    end
end

-- EVERYONE computes changes since the previous check (everyone sees the same roster), only the
-- sender sends them, so changing the sender does not require a full roster.
-- Status only: "+Name" / "-Name"; new member or different level/rank: full entry.
local function SendDelta(send)
    local guild = MyGuild()
    local g = guild and rosters[guild]
    if not g then return end
    local entries = {}
    for name, m in pairs(g.members) do
        local e, old = EncodeEntry(name, m), lastSent[name]
        if old ~= e then
            lastSent[name] = e
            if old and old:sub(1, -2) == e:sub(1, -2) then
                table.insert(entries, (m.o and "+" or "-") .. name)
            else
                table.insert(entries, e)
            end
        end
    end
    if not send or #entries == 0 then return end
    local header = #"RD:" + #Enc(guild) + 1
    for _, chunk in ipairs(Chunk(entries, MAX_ADDON_BYTES - header, MAX_ADDON_BYTES - header)) do
        Most.Send("RD", Enc(guild) .. ":" .. chunk, "low")
    end
end

local baselined = false
local function Tick()
    if GetTime() < readyAt then return end
    local fullSlot = math.floor(GetServerTime() / FULL_INTERVAL)
    if not baselined then
        -- The first check only remembers the state and sends nothing
        baselined, lastFullSlot = true, fullSlot
        SendDelta(false)
        return
    end
    local isSender = IsSender()
    if fullSlot ~= lastFullSlot then
        lastFullSlot = fullSlot
        if isSender and GetTime() - lastFull > FULL_COOLDOWN then SendFull() return end
    end
    SendDelta(isSender)
end

-- After login: request rosters of guilds we have no fresh data for
local function RequestStale()
    if not ctx then return end
    local now, list = GetServerTime(), {}
    for guild in pairs(ctx.allowedGuilds) do
        local g = rosters[guild]
        if guild ~= MyGuild() and (not g or now - (g.updated or 0) > STALE_AFTER) then table.insert(list, Enc(guild)) end
    end
    if #list > 0 then
        Most.Send("RQ", table.concat(list, ","), "low")
        addonTable.Sync.Start("rosters") -- sync bar (sync.lua)
    end
end
Roster.RequestStale = RequestStale

-- ============================================================================
-- RECEIVING
-- ============================================================================
-- Another guild's roster is accepted only from a known player of that guild (we know our own from the game)
local function AcceptFrom(sender, guild)
    if not ctx or not guild or guild == MyGuild() or not ctx.isGuildAllowed(guild) then return false end
    for _, p in ipairs(ctx.activePlayers) do
        if p.name == sender then return p.guild == guild end
    end
    return false
end

local function Upsert(g, list, snap)
    for e in list:gmatch("[^;]+") do
        local flag, statusName = e:match("^([%+%-])([^,]+)$")
        if flag then
            -- Status change only (the next full roster adds an unknown player)
            local m = g.members[statusName]
            if m then m.o = (flag == "+") end
        else
            local name, m = DecodeEntry(e)
            if name then m.s = snap g.members[name] = m end
        end
    end
end

function Roster.HandlePacket(pType, payload, senderName)
    if pType == "RF" or pType == "RD" then addonTable.Sync.Activity("rosters") end
    if pType == "RF" then
        local gEnc, snap, idx, total, complete, ranks, list = strsplit(":", payload, 7)
        local guild = Dec(gEnc)
        idx, total = tonumber(idx), tonumber(total)
        if not idx or not total or not list or not AcceptFrom(senderName, guild) then return true end
        local g = rosters[guild] or { members = {}, ranks = {} }
        rosters[guild] = g
        local inc = incoming[guild]
        if not inc or inc.id ~= snap then
            inc = { id = snap, got = {}, count = 0 }
            incoming[guild] = inc
        end
        if not inc.got[idx] then
            inc.got[idx] = true
            inc.count = inc.count + 1
        end
        if idx == 1 and ranks ~= "" then
            g.ranks = {}
            for r in ranks:gmatch("[^,]+") do table.insert(g.ranks, Dec(r)) end
        end
        Upsert(g, list, snap)
        g.updated = GetServerTime()
        -- All parts received: anyone missing from the full roster left the guild (or is offline,
        -- when the sender has "show offline" turned off)
        if inc.count >= total then
            for name, m in pairs(g.members) do
                if m.s ~= snap then
                    if complete == "1" then g.members[name] = nil else m.o = false end
                end
            end
            incoming[guild] = nil
        end
        Changed()
        return true
    elseif pType == "RD" then
        local gEnc, list = strsplit(":", payload, 2)
        local guild = Dec(gEnc)
        if not list or not AcceptFrom(senderName, guild) then return true end
        local g = rosters[guild] or { members = {}, ranks = {} }
        rosters[guild] = g
        Upsert(g, list, incoming[guild] and incoming[guild].id)
        g.updated = GetServerTime()
        Changed()
        return true
    elseif pType == "RQ" then
        if senderName ~= UnitName("player") and GetTime() >= readyAt and IsSender() then
            for gEnc in payload:gmatch("[^,]+") do
                if Dec(gEnc) == MyGuild() then
                    -- A short delay: several requests at once = one send (cooldown)
                    C_Timer.After(3, function()
                        if IsSender() and GetTime() - lastFull > FULL_COOLDOWN then SendFull() end
                    end)
                end
            end
        end
        return true
    end
    return false
end

-- ============================================================================
-- GUILD SUMMARY (Guilds tab)
-- ============================================================================
-- live = someone with the addon from this guild is online now (or it is my guild); only then is the status current
function Roster.GetGuildSummary(guild)
    local g = rosters[guild]
    local live = (guild == MyGuild()) or Most.GetRelayName(guild) ~= nil
    local total, online, seen = 0, 0, {}
    if g then
        for name, m in pairs(g.members) do
            seen[name] = true
            total = total + 1
            if live and m.o then online = online + 1 end
        end
    end
    -- Players with the addon whose roster has not arrived yet
    if ctx then
        for _, p in ipairs(ctx.activePlayers) do
            if p.guild == guild and not seen[p.name] then
                total, online = total + 1, online + 1
            end
        end
    end
    return { live = live, total = total, online = online, updated = g and g.updated }
end

-- Player's rank from rosters of listed guilds (name, index) or nil, e.g. permissions in mute.lua
function Roster.GetRank(name)
    for guild, g in pairs(rosters) do
        local m = g.members[name]
        if m and ctx and ctx.isGuildAllowed(guild) then return g.ranks[(m.r or 0) + 1], m.r end
    end
    return nil, nil
end

-- Player's class and level from rosters of listed guilds, or nil (chat format in bridge.lua)
function Roster.GetClassLevel(name)
    for guild, g in pairs(rosters) do
        local m = g.members[name]
        if m and ctx and ctx.isGuildAllowed(guild) then return m.c, m.l end
    end
    return nil, nil
end

-- ============================================================================
-- LIST FOR THE MEMBERS TAB
-- ============================================================================
-- Players with the addon (activePlayers) + rosters of all listed guilds. The online status of a guild
-- with nobody with the addon online now is out of date -> we show them as offline.
function Roster.BuildList(showOffline)
    local list, seen = {}, {}
    if not ctx then return list end
    local myGuild = MyGuild()
    for _, p in ipairs(ctx.activePlayers) do
        seen[p.name] = true
        -- Location: the game's roster for my guild (fresher), otherwise what the player sent
        local own = p.guild == myGuild and rosters[myGuild] and rosters[myGuild].members[p.name]
        local location = (own and own.z) or p.zone
        table.insert(list, { name = p.name, class = p.class, level = p.level, guild = p.guild, rank = p.rank, rankIndex = tonumber(p.rankIndex), version = p.version, location = (location ~= "") and location or nil, online = true })
    end
    for guild, g in pairs(rosters) do
        if ctx.isGuildAllowed(guild) then
            local live = (guild == myGuild) or Most.GetRelayName(guild) ~= nil
            for name, m in pairs(g.members) do
                local online = m.o and live
                if not seen[name] and (online or showOffline) then
                    seen[name] = true
                    table.insert(list, { name = name, class = m.c, level = m.l, guild = guild, rank = g.ranks[(m.r or 0) + 1] or ("Rank " .. tostring(m.r)), rankIndex = m.r, location = (online and guild == myGuild and m.z ~= "") and m.z or nil, online = online })
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end
        if a.guild ~= b.guild then return (a.guild or "") < (b.guild or "") end
        return a.name < b.name
    end)
    return list
end

-- ============================================================================
-- EVENTS
-- ============================================================================
local Listener = CreateFrame("Frame")
Listener:RegisterEvent("ADDON_LOADED")
Listener:RegisterEvent("PLAYER_LOGIN")
Listener:RegisterEvent("GUILD_ROSTER_UPDATE")
Listener:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        _G.JagodkiRosterDB = _G.JagodkiRosterDB or {}
        rosters = _G.JagodkiRosterDB
    elseif event == "PLAYER_LOGIN" then
        readyAt = GetTime() + READY_DELAY
        -- core.lua sends the roster request (EventSync.LoginSync)
        C_Timer.NewTicker(20, Tick)
    elseif event == "GUILD_ROSTER_UPDATE" then
        -- Blizzard can fire this event many times in a row, so we recompute once per 2 s
        if not self.pending then
            self.pending = true
            C_Timer.After(2, function() self.pending = false RefreshLocal() end)
        end
    end
end)
