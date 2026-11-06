-- ============================================================================
-- ROSTER: members (online and offline) of all listed guilds
-- ============================================================================
-- Blizzard only shows the roster of your own guild, so:
--  * In each guild one person with the addon is the roster SENDER. The sender changes every 5 min
--    (a "random" choice, but computed the same by everyone) to spread the traffic over everyone.
--  * Everyone compares their guild's roster with the previous one every 20 s; only the sender sends.
--    A status change is "+Name" / "-Name"; a new member / level / rank: "Name,W603+".
--  * Full roster: once per 60 min to everyone, and to everyone (at most once a minute) when the relay of
--    another guild asks for it (RQ). Only relays ask, when they have no whole roster of that guild or it is
--    older than FRESH_FOR.
--  * Full rosters have low priority; changes (RD, who logged in or out) high, so they arrive within seconds.
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
local pairs, ipairs, tostring, tonumber, pcall = _G.pairs, _G.ipairs, _G.tostring, _G.tonumber, _G.pcall
local table, math, wipe = _G.table, _G.math, _G.wipe

local Most = addonTable.Most
local Enc, Dec = Most.EncodeField, Most.DecodeField

local MAX_ADDON_BYTES = 205  -- below the 255-byte limit with room for the relay's "FW:First Surname:" header
local FULL_INTERVAL = 3600   -- full roster every 60 min (changes go as deltas in between); a big guild's is 100+ parts
local FULL_COOLDOWN = 60     -- a full roster at most once per minute
local ASK_COOLDOWN = 300     -- the relay asks for the same guild's roster at most this often (s)
local ANSWER_COOLDOWN = 600  -- requests are answered with a full roster at most this often (a big one takes minutes)
local RETRY_AFTER = 300      -- after this many seconds we ask again for a roster that did not arrive whole
local MAX_RETRIES = 2        -- how many times we ask again
local STILL_ARRIVING = 60    -- a roster with a part newer than this many seconds is still on its way
local SNAP_KEEP = 600        -- parts of an unfinished full roster are kept this long (s)
local ONLINE_INFO_FOR = 600  -- another guild's roster tells who is online only if it changed within this many seconds
local READY_DELAY = 65       -- after login we wait until we know the others (otherwise everyone thinks they are the sender);
                             -- only the relay answers a PING, the rest is known from their regular status packet (every 60 s)
local SENDER_ROTATION = 300  -- the roster sender changes every this many seconds
local FRESH_FOR = FULL_INTERVAL + 300 -- a whole roster this old still decides who is a member (one full roster + 5 min)

local Roster = {}
addonTable.Roster = Roster

-- Context from core.lua: activePlayers, isGuildAllowed, allowedGuilds, onChanged
local ctx = nil
function Roster.Init(c) ctx = c end

-- rosters[guild] = { members = { name = { c = class, l = level, r = rank, o = online } }, ranks = {...}, updated = time }
local rosters = {}
local readyAt = math.huge
local lastFull, lastFullSlot, lastSent = 0, nil, {}
-- When a guildmate last started sending our guild's full roster: the senders' views of who is online can
-- differ for a moment, and two of them sent the same 100+ part roster at once
local lastOwnFullAt = -math.huge
local OWN_FULL_WAIT = 15     -- the sender waits a random 0..this many seconds and skips if someone else started
local incoming = {} -- guild -> { last = time of the last part, snaps = { [snap] = { got = { [idx] = true }, count, names, last } } }

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
-- The game's guild window is open: then we do not touch its "show offline" setting
local function GuildWindowOpen()
    return (_G.GuildFrame and _G.GuildFrame:IsShown()) or (_G.CommunitiesFrame and _G.CommunitiesFrame:IsShown()) or false
end

-- Reads the game's roster. With "show offline" turned off the game gives only online players, so a player
-- with that setting would send other guilds a roster without anyone offline (wrong member counts). The
-- setting is turned on for the reading only and back off right after, unless the guild window is open.
local ignoreRosterEventsUntil = 0
local function ReadGameRoster(members)
    local showOffline = not (_G.GetGuildRosterShowOffline and not _G.GetGuildRosterShowOffline())
    local switched = false
    if not showOffline and _G.SetGuildRosterShowOffline and not GuildWindowOpen() then
        -- Our own switch fires GUILD_ROSTER_UPDATE; it must not start another reading
        ignoreRosterEventsUntil = GetTime() + 3
        _G.SetGuildRosterShowOffline(true)
        switched = true
    end
    local ok, err = pcall(function()
        for i = 1, (_G.GetNumGuildMembers and _G.GetNumGuildMembers()) or 0 do
            local fullName, _, rankIndex, level, _, zone, _, _, isOnline, _, classFile = _G.GetGuildRosterInfo(i)
            if fullName then
                -- z = location: own guild only, not part of the entries sent to other guilds.
                -- Keyed by the player name with the surname where the client has one (Most.PlayerKey)
                members[Most.PlayerKey(fullName)] = { c = classFile, l = level, r = rankIndex, o = isOnline and true or false, z = zone }
            end
        end
    end)
    -- Always back as the player had it, even after an error
    if switched then _G.SetGuildRosterShowOffline(false) end
    if not ok and addonTable.Monitor then addonTable.Monitor.Error("Reading the guild roster failed: " .. tostring(err)) end
    return showOffline or switched
end

local function RefreshLocal()
    local guild = MyGuild()
    if not guild or ((_G.GetNumGuildMembers and _G.GetNumGuildMembers()) or 0) == 0 then return end
    local old = rosters[guild] and rosters[guild].members or {}
    local members = {}
    local complete = ReadGameRoster(members)
    if not complete then
        -- Only online players were given (guild window open with "show offline" off): the rest stays, as offline
        for name, m in pairs(old) do
            if not members[name] then members[name] = { c = m.c, l = m.l, r = m.r, o = false } end
        end
    end
    local ranks = {}
    local numRanks = (_G.GuildControlGetNumRanks and _G.GuildControlGetNumRanks()) or 0
    for i = 1, numRanks do ranks[i] = _G.GuildControlGetRankName(i) end
    rosters[guild] = { members = members, ranks = ranks, updated = GetServerTime(), fullAt = GetServerTime(), complete = complete }
    Changed()
end

-- ============================================================================
-- SENDER: rotates every SENDER_ROTATION seconds among online players with the addon in my guild
-- ============================================================================
local function IsSender()
    local guild = MyGuild()
    local g = guild and rosters[guild]
    if not g or not ctx then return false end
    local myName, now = Most.MyName(), GetTime()
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
-- target: whisper to one player. It does not count as the regular send, so the change tracking stays as it is.
local function SendFull(target)
    local guild = MyGuild()
    local g = guild and rosters[guild]
    if not g then return end
    if not target then
        lastFull = GetTime()
        wipe(lastSent)
    end
    local entries = {}
    for name, m in pairs(g.members) do
        local e = EncodeEntry(name, m)
        if not target then lastSent[name] = e end
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
        local payload = table.concat({ Enc(guild), snap, i, #chunks, g.complete and "1" or "0", (i == 1) and ranks or "", chunk }, ":")
        if target then Most.Whisper(target, "RF", payload, "low") else Most.Send("RF", payload, "low") end
    end
    if addonTable.Monitor then
        addonTable.Monitor.Note("Sent our full roster" .. (target and (" to " .. target) or "") .. ": " .. #entries .. " members in "
            .. #chunks .. " parts" .. (g.complete and "" or " (only online players: guild window open with show offline off)"))
    end
end

-- Requests for our guild's full roster, answered together after a short delay, always to everyone: the
-- requests come from the relays of other guilds, and one roster sent to everyone reaches their whole guild
-- (whispered rosters reached only the asker, so everyone in that guild kept asking)
local requestsPending = false

local function AnswerRequests()
    requestsPending = false
    -- A big guild's roster takes minutes to reach other guilds, so requests are answered at most every
    -- ANSWER_COOLDOWN; the asking relays wait for parts that are still arriving
    if IsSender() and GetTime() - lastFull > ANSWER_COOLDOWN and GetTime() - lastOwnFullAt > ANSWER_COOLDOWN then SendFull() end
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
        -- High priority: logins and logouts reach the other guilds within seconds, not behind full rosters
        Most.Send("RD", Enc(guild) .. ":" .. chunk, "high")
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
        if isSender and GetTime() - lastFull > FULL_COOLDOWN then
            C_Timer.After(math.random(0, OWN_FULL_WAIT), function()
                if GetTime() - lastOwnFullAt > FULL_COOLDOWN and GetTime() - lastFull > FULL_COOLDOWN then SendFull() end
            end)
            return
        end
    end
    SendDelta(isSender)
end

-- Guilds we asked for a roster: guild -> time of the first request. A guild leaves when its whole roster
-- arrives, or at a retry when nobody from it is online. Parts can be lost or rejected (sender not known yet),
-- and one part already makes the data look fresh, so the check needs a whole roster (fullAt).
local asked, retries, retryPending = {}, 0, false
local RetryRequests

local function ScheduleRetry()
    if retryPending then return end
    retryPending = true
    C_Timer.After(RETRY_AFTER, RetryRequests)
end

RetryRequests = function()
    retryPending = false
    local list, waiting = {}, false
    for guild, askedAt in pairs(asked) do
        local g, inc = rosters[guild], incoming[guild]
        if (g and (g.fullAt or 0) >= askedAt) or not Most.GetRelayName(guild) then
            asked[guild] = nil
        elseif inc and GetTime() - (inc.last or 0) < STILL_ARRIVING then
            -- Parts are still coming: wait instead of asking again
            waiting = true
        else
            table.insert(list, guild)
        end
    end
    if #list > 0 and retries >= MAX_RETRIES then
        for _, guild in ipairs(list) do asked[guild] = nil end
        if addonTable.Monitor then addonTable.Monitor.Note("Roster not received after " .. MAX_RETRIES .. " retries: " .. table.concat(list, ", ")) end
    elseif #list > 0 and Most.IsRelay() then
        retries = retries + 1
        for i, guild in ipairs(list) do list[i] = Enc(guild) end
        Most.Send("RQ", table.concat(list, ","), "low")
        waiting = true
    end
    if waiting then ScheduleRetry() end
end

-- Requests rosters of linked guilds we have no fresh data for. Only the relay asks: the answer goes to
-- everyone, so the whole guild gets it (with hundreds of players everyone asking flooded both relays).
-- Called after login and from Tick, at most every ASK_COOLDOWN per guild.
local lastAskedAt = {}
local function RequestStale()
    if not ctx or not Most.IsRelay() then return end
    local now, list = GetServerTime(), {}
    for guild in pairs(ctx.allowedGuilds) do
        local g = rosters[guild]
        -- No whole roster yet, or the last whole one is older than a full interval: changes alone (RD) also
        -- make "updated" fresh, but they never add the members that did not change
        local arriving = incoming[guild] and GetTime() - (incoming[guild].last or 0) < STILL_ARRIVING
        if guild ~= MyGuild() and (not g or not g.fullAt or now - g.fullAt > FRESH_FOR) and Most.GetRelayName(guild)
            and not arriving and now - (lastAskedAt[guild] or 0) >= ASK_COOLDOWN then
            lastAskedAt[guild] = now
            table.insert(list, Enc(guild))
            asked[guild] = asked[guild] or now
        end
    end
    if #list > 0 then
        Most.Send("RQ", table.concat(list, ","), "low")
        addonTable.Sync.Start("rosters") -- sync bar (sync.lua)
        ScheduleRetry()
    end
end
Roster.RequestStale = RequestStale

-- ============================================================================
-- RECEIVING
-- ============================================================================
-- Another guild's roster is accepted only from a player of that guild (we know our own from the game):
-- online with the addon or in its roster. A sender nobody knows is accepted only while we have no
-- recent whole roster of that guild, so the first roster can arrive.
local function AcceptFrom(sender, guild)
    if not ctx or not guild or guild == MyGuild() or not ctx.isGuildAllowed(guild) then return false end
    local p = Most.FindKnownPlayer(sender)
    if p then return p.guild == guild end
    return Roster.IsMember(sender, guild) == nil
end

-- names (optional): the set of players seen in this full roster, to find who is no longer in the guild
local function Upsert(g, list, names)
    for e in list:gmatch("[^;]+") do
        local flag, statusName = e:match("^([%+%-])([^,]+)$")
        if flag then
            -- Status change only (the next full roster adds an unknown player)
            local m = g.members[Most.PlayerKey(statusName)]
            if m then m.o = (flag == "+") end
        else
            -- Keyed by the player name with the surname where the client has one (Most.PlayerKey)
            local name, m = DecodeEntry(e)
            if name then
                local key = Most.PlayerKey(name)
                g.members[key] = m
                if names then names[key] = true end
            end
        end
    end
end

function Roster.HandlePacket(pType, payload, senderName)
    if pType == "RF" or pType == "RD" then addonTable.Sync.Activity("rosters") end
    if pType == "RF" then
        local gEnc, snap, idx, total, complete, ranks, list = strsplit(":", payload, 7)
        local guild = Dec(gEnc)
        idx, total = tonumber(idx), tonumber(total)
        -- Our own guild's roster from a guildmate: we have it from the game, we only note that one is on its way
        if guild == MyGuild() and senderName ~= Most.MyName() then lastOwnFullAt = GetTime() return true end
        if not idx or not total or not list or not AcceptFrom(senderName, guild) then return true end
        local g = rosters[guild] or { members = {}, ranks = {} }
        rosters[guild] = g
        -- Parts are collected per roster (snap). Two senders' rosters can arrive mixed (a big guild's roster
        -- takes minutes through the relays); before, every switch started over and none was ever complete.
        local inc = incoming[guild] or { snaps = {} }
        incoming[guild] = inc
        inc.last = GetTime()
        for id, s in pairs(inc.snaps) do
            if GetTime() - s.last > SNAP_KEEP then inc.snaps[id] = nil end
        end
        local s = inc.snaps[snap]
        if not s then
            s = { got = {}, count = 0, names = {} }
            inc.snaps[snap] = s
        end
        s.last, s.total = GetTime(), total
        if not s.got[idx] then
            s.got[idx] = true
            s.count = s.count + 1
        end
        if idx == 1 and ranks ~= "" then
            g.ranks = {}
            for r in ranks:gmatch("[^,]+") do table.insert(g.ranks, Dec(r)) end
        end
        Upsert(g, list, s.names)
        g.updated = GetServerTime()
        -- All parts received: anyone missing from the full roster left the guild (or is offline,
        -- when the sender has "show offline" turned off)
        if s.count >= total then
            for name, m in pairs(g.members) do
                if not s.names[name] then
                    if complete == "1" then g.members[name] = nil else m.o = false end
                end
            end
            inc.snaps[snap] = nil
            g.fullAt = GetServerTime()
            if addonTable.Monitor then
                local count = 0
                for _ in pairs(g.members) do count = count + 1 end
                addonTable.Monitor.Note("Full roster of " .. guild .. " from " .. senderName .. ": " .. count .. " members"
                    .. (complete == "1" and "" or " (sender sees only online players, offline ones kept from before)"))
            end
        end
        Changed()
        return true
    elseif pType == "RD" then
        local gEnc, list = strsplit(":", payload, 2)
        local guild = Dec(gEnc)
        if not list or not AcceptFrom(senderName, guild) then return true end
        local g = rosters[guild] or { members = {}, ranks = {} }
        rosters[guild] = g
        -- Players added by a change while a full roster is arriving count as seen in it, so its end does not remove them
        local added = {}
        Upsert(g, list, added)
        for _, s in pairs(incoming[guild] and incoming[guild].snaps or {}) do
            for name in pairs(added) do s.names[name] = true end
        end
        g.updated = GetServerTime()
        Changed()
        return true
    elseif pType == "RQ" then
        if senderName ~= Most.MyName() and GetTime() >= readyAt and IsSender() then
            for gEnc in payload:gmatch("[^,]+") do
                if Dec(gEnc) == MyGuild() then
                    -- A short delay collects requests made at the same moment
                    if not requestsPending then
                        requestsPending = true
                        C_Timer.After(3, AnswerRequests)
                    end
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
-- Live = someone with the addon from this guild is online now (its relay is known), or it is my guild; only
-- then is its online status current. When its relay logs out, the next one is known a moment later, so a
-- guild stays live for LIVE_GRACE after it was last seen live, with its last known statuses, instead of
-- going gray for that moment.
local LIVE_GRACE = 180
local lastLiveAt = {}
local function IsLive(guild)
    if guild == MyGuild() then return true end
    if Most.GetRelayName(guild) ~= nil then
        lastLiveAt[guild] = GetTime()
        return true
    end
    return lastLiveAt[guild] ~= nil and GetTime() - lastLiveAt[guild] < LIVE_GRACE
end
Roster.IsLive = IsLive

function Roster.GetGuildSummary(guild)
    local g = rosters[guild]
    local live = IsLive(guild)
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

-- Whether the player is in the guild's roster: true / false, or nil when we have no whole roster of that
-- guild from the last FRESH_FOR seconds (a new member may not be in an old one). My guild: the game's roster.
function Roster.IsMember(name, guild)
    local g = guild and rosters[guild]
    if not g or not g.fullAt or GetServerTime() - g.fullAt > FRESH_FOR then return nil end
    return g.members[name] ~= nil
end

-- Player's rank from rosters of listed guilds (name, index) or nil, e.g. permissions in mute.lua and core.lua.
-- The roster comes from the game (my guild) or from that guild's members, not from what the player says
-- about themselves. guild (optional): the guild from the player's status packet; when we have its roster,
-- only that roster counts, so a rank from another guild's old roster does not carry over.
function Roster.GetRank(name, guild)
    local own = guild and rosters[guild]
    if own and ctx and ctx.isGuildAllowed(guild) then
        local m = own.members[name]
        if not m then return nil, nil end
        return own.ranks[(m.r or 0) + 1], m.r
    end
    for guild, g in pairs(rosters) do
        local m = g.members[name]
        if m and ctx and ctx.isGuildAllowed(guild) then return g.ranks[(m.r or 0) + 1], m.r end
    end
    return nil, nil
end

-- For Monitoring: per listed guild { guild, members, online, fullAt, updated, parts = "got/total" of a roster
-- still arriving, or nil }. Times are server times.
function Roster.GetMonitorInfo()
    local list = {}
    if not ctx then return list end
    for guild in pairs(ctx.allowedGuilds) do
        local g, inc = rosters[guild], incoming[guild]
        local members, online = 0, 0
        for _, m in pairs(g and g.members or {}) do
            members = members + 1
            if m.o then online = online + 1 end
        end
        local parts
        for _, s in pairs(inc and inc.snaps or {}) do
            if GetTime() - s.last < STILL_ARRIVING then parts = s.count .. "/" .. tostring(s.total) end
        end
        table.insert(list, { guild = guild, members = members, online = online, fullAt = g and g.fullAt, updated = g and g.updated, parts = parts })
    end
    table.sort(list, function(a, b) return a.guild < b.guild end)
    return list
end

-- Whether another guild's roster says the player is online: true / false, or nil when we do not know
-- (not in that roster, or no change or full roster from that guild for ONLINE_INFO_FOR seconds)
function Roster.IsOnline(name, guild)
    local g = guild and rosters[guild]
    local m = g and g.members[name]
    if not m or GetServerTime() - (g.updated or 0) > ONLINE_INFO_FOR then return nil end
    return m.o == true
end

-- Members of all listed guilds per class (the class panel in core.lua): class -> { total, online }.
-- The game gives the class (not the race or spec) in the roster, also for offline members.
function Roster.ClassCounts()
    local counts, seen, myGuild = {}, {}, MyGuild()
    if not ctx then return counts end
    for guild, g in pairs(rosters) do
        if ctx.isGuildAllowed(guild) then
            -- The online status of a guild with nobody with the addon online is out of date (as in BuildList)
            local live = IsLive(guild)
            for name, m in pairs(g.members) do
                if m.c and not seen[name] then
                    seen[name] = true
                    local c = counts[m.c] or { total = 0, online = 0 }
                    counts[m.c] = c
                    c.total = c.total + 1
                    if live and m.o then c.online = c.online + 1 end
                end
            end
        end
    end
    return counts
end

-- Listed guild whose roster has the player, and their entry (guild, member), or nil. When the player is in
-- more than one roster (moved to another guild), the most recently updated roster wins.
function Roster.FindMember(name)
    local bestGuild, best, bestAt = nil, nil, -1
    for guild, g in pairs(rosters) do
        local m = g.members[name]
        if m and ctx and ctx.isGuildAllowed(guild) and (g.updated or 0) > bestAt then
            bestGuild, best, bestAt = guild, m, g.updated or 0
        end
    end
    return bestGuild, best
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
        -- Another guild's player whose roster already says offline (e.g. a relay who just logged out) is
        -- taken from the roster below instead, as offline, without waiting for the online timeout
        if p.guild == myGuild or Roster.IsOnline(p.name, p.guild) ~= false or GetTime() - (p.lastSeen or 0) <= 30 then
            seen[p.name] = true
            -- Location: the game's roster for my guild (fresher), otherwise what the player sent
            local own = p.guild == myGuild and rosters[myGuild] and rosters[myGuild].members[p.name]
            local location = (own and own.z) or p.zone
            table.insert(list, { name = p.name, class = p.class, level = p.level, guild = p.guild, rank = p.rank, rankIndex = tonumber(p.rankIndex), version = p.version, location = (location ~= "") and location or nil, online = true })
        end
    end
    for guild, g in pairs(rosters) do
        if ctx.isGuildAllowed(guild) then
            local live = IsLive(guild)
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
-- A guildmate logged in or out (the game's "has come online" / "has gone offline" message): the roster
-- sender reads the roster again at once and sends the change, instead of waiting for its next check (20 s)
local function ToPattern(format)
    if not format then return nil end
    local marked = format:gsub("%%s", "\1")
    return "^" .. marked:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("\1", ".+") .. "$"
end
local ONLINE_PATTERN, OFFLINE_PATTERN = ToPattern(_G.ERR_FRIEND_ONLINE_SS), ToPattern(_G.ERR_FRIEND_OFFLINE_S)
local QUICK_DELTA_COOLDOWN = 5   -- at most one such extra reading per this many seconds (several logouts go together)
local quickDelta, lastQuickAt = false, -QUICK_DELTA_COOLDOWN

local function OnGuildmateStatusMessage(message)
    if not message or not baselined or not IsSender() then return end
    local hit = (ONLINE_PATTERN and message:find(ONLINE_PATTERN)) or (OFFLINE_PATTERN and message:find(OFFLINE_PATTERN))
    if not hit then return end
    quickDelta = true
    if GetTime() - lastQuickAt < QUICK_DELTA_COOLDOWN then return end
    lastQuickAt = GetTime()
    -- The game's roster refresh fires GUILD_ROSTER_UPDATE; the reading after it sends the change (Listener)
    if _G.C_GuildInfo and _G.C_GuildInfo.GuildRoster then _G.C_GuildInfo.GuildRoster() elseif _G.GuildRoster then _G.GuildRoster() end
end

local Listener = CreateFrame("Frame")
Listener:RegisterEvent("ADDON_LOADED")
Listener:RegisterEvent("PLAYER_LOGIN")
Listener:RegisterEvent("GUILD_ROSTER_UPDATE")
Listener:RegisterEvent("CHAT_MSG_SYSTEM")
Listener:SetScript("OnEvent", function(self, event, arg1)
    if event == "CHAT_MSG_SYSTEM" then OnGuildmateStatusMessage(arg1) return end
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        _G.JagodkiRosterDB = _G.JagodkiRosterDB or {}
        rosters = _G.JagodkiRosterDB
        -- Rosters saved by the test build of 0.13.2 were keyed by the first name only, with the full name in n:
        -- back to the full name, the key used everywhere now
        for _, g in pairs(rosters) do
            local fixed = {}
            for name, m in pairs(g.members or {}) do
                fixed[m.n or name] = m
                m.n = nil
            end
            g.members = fixed
        end
    elseif event == "PLAYER_LOGIN" then
        readyAt = GetTime() + READY_DELAY
        -- core.lua sends the roster request after login (EventSync.LoginSync); the relay also asks every
        -- minute for linked guilds whose roster is missing or old (RequestStale keeps its own cooldown)
        C_Timer.NewTicker(20, Tick)
        C_Timer.NewTicker(60, RequestStale)
    elseif event == "GUILD_ROSTER_UPDATE" then
        -- Blizzard can fire this event many times in a row, so we recompute once per 2 s.
        -- Events from our own "show offline" switch (ReadGameRoster) are skipped.
        if GetTime() < ignoreRosterEventsUntil then return end
        if not self.pending then
            self.pending = true
            C_Timer.After(2, function()
                self.pending = false
                RefreshLocal()
                -- After a guildmate's login or logout: the change goes out now (OnGuildmateStatusMessage)
                if quickDelta then
                    quickDelta = false
                    if baselined and IsSender() then SendDelta(true) end
                end
            end)
        end
    end
end)
