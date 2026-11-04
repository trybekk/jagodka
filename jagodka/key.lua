-- ============================================================================
-- KEY: secret community key -> name and password of the chat channel
-- ============================================================================
--  * The public channel (bridge.lua, its name and password are in this code) is only for finding other
--    guilds and for players without the key. The shared chat goes on a second channel whose name and
--    password come from a secret key, so someone with only the addon code cannot find it, read it or
--    take it over.
--  * The key is kept in JagodkiChatDB.key = { k = key, ts = server time, by = officer }. It travels only
--    over GUILD and relay whispers (KEY) and is accepted only from officers by the guild rosters.
--    The newer key (ts) wins.
--  * After login we ask our guild (KREQ; passed on to other guilds only when we are our guild's relay);
--    a relay answers when it has a newer key. An officer who still has no key and has seen none after
--    KEY_WAIT seconds creates one, so nobody has to do it by hand.
--  * The relay sends the key to everyone every KEY_SHARE_INTERVAL, and at once when it sees an older one,
--    so guilds whose officers created a key at the same time end up with the newer one.
--  * A new key: "/jagodka key" (officers), or by itself in an officer's client when the chat channel has
--    an owner from outside the listed guilds, bans us or has another password.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local GetChannelName = _G.GetChannelName
local GetServerTime = _G.GetServerTime
local GetTime = _G.GetTime
local UnitName = _G.UnitName
local strsplit = _G.strsplit
local date = _G.date
local ipairs, tostring, tonumber, type = _G.ipairs, _G.tostring, _G.tonumber, _G.type
local table, math = _G.table, _G.math

local Most = addonTable.Most
local Enc, Dec = Most.EncodeField, Most.DecodeField

local KEY_WAIT = 120            -- seconds after login before an officer without a key creates one
local REQUEST_DELAYS = { 10, 90 } -- seconds after login when we ask our guild for the key
local KEY_SHARE_INTERVAL = 600  -- how often the relay sends the key to everyone (s)
local ANSWER_COOLDOWN = 60      -- at most this often the relay sends the key again to someone with an older one (s)
local ROTATE_COOLDOWN = 600     -- an officer's client creates a new key by itself at most this often (s)
local OWNER_CHECK_INTERVAL = 60 -- how often an officer reads the chat channel's member list (s)
local KEYLESS_CHECK_INTERVAL = 60 -- without a key: how often we ask our guild again and check whether to create one (s)
local GUILD_JOIN_DELAY = 5      -- after joining a guild, seconds before we ask it for the key
local ROSTER_ASK_COOLDOWN = 300 -- at most this often a key from an unknown officer makes us ask for rosters (s)
local KEY_LENGTH = 16
local CHARS = "abcdefghijklmnopqrstuvwxyz0123456789"

local Key = {}
addonTable.Key = Key

-- Context from core.lua: isKnownOfficer, isMeOfficer
local ctx = nil
function Key.Init(c) ctx = c end

local current = nil      -- { k, ts, by }
local joinedName = nil   -- chat channel we joined, left after a key change
local lastRotation = -ROTATE_COOLDOWN
local lastShared = -ANSWER_COOLDOWN
local warned = false
local keySeen = false    -- a KEY packet arrived (accepted or not)
local lastOwner = nil    -- chat channel owner last written to the log
local loginAt = math.huge
local KeylessCheck       -- defined below, run every minute
local KeepPending        -- defined below, used when a key from an unknown officer arrives

local function MyName() return UnitName("player") end
local function Monitor() return addonTable.Monitor end

-- ============================================================================
-- CHANNEL NAME AND PASSWORD FROM THE KEY
-- ============================================================================
-- Simple string hash (djb2), kept below 2^31
local function Hash(s, seed)
    local h = seed
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

local function Base36(n, len)
    local out = {}
    for i = 1, len do
        local d = n % 36
        out[i] = CHARS:sub(d + 1, d + 1)
        n = math.floor(n / 36)
    end
    return table.concat(out)
end

-- Separate channel for each faction, like the public one
local function Derive(k)
    local faction = (_G.UnitFactionGroup("player") == "Horde") and "h" or "a"
    local name = "Jgd" .. faction .. Base36(Hash(k .. faction, 5381), 6)
    local password = Base36(Hash(k, 52711), 6) .. Base36(Hash(k, 104729), 6)
    return name, password
end

-- Name of the chat channel, or nil without a key
function Key.ChannelName()
    if not current then return nil end
    return (Derive(current.k))
end

-- Number of the chat channel when we are on it, or nil
function Key.ChannelId()
    local name = Key.ChannelName()
    if not name then return nil end
    local id = GetChannelName(name)
    if id and id > 0 then return id end
    return nil
end

-- Whether we have a key; then the shared chat goes only on the chat channel (or through the relays)
function Key.HasKey() return current ~= nil end

function Key.Join()
    if not current then return end
    local name, password = Derive(current.k)
    if joinedName and joinedName ~= name and _G.LeaveChannelByName then
        _G.LeaveChannelByName(joinedName)
        if Monitor() then Monitor().Channel("Left the old chat channel (key changed)") end
    end
    joinedName = name
    if not Key.ChannelId() then
        _G.JoinChannelByName(name, password)
        if Monitor() then Monitor().Channel("Joining the chat channel (key by " .. tostring(current.by) .. ")") end
    end
    Most.HideFromChat(name)
end

-- ============================================================================
-- KEY CHANGES
-- ============================================================================
local function Save()
    _G.JagodkiChatDB = _G.JagodkiChatDB or {}
    _G.JagodkiChatDB.key = current
end

-- Takes the key if it is newer than ours
local function Apply(k, ts, by)
    if current and (current.ts or 0) >= ts then return false end
    current = { k = k, ts = ts, by = by }
    Save()
    warned = false
    if Monitor() then Monitor().Channel("Chat channel key from " .. tostring(by) .. " (" .. date("%d.%m %H:%M", ts) .. ")") end
    Key.Join()
    return true
end

local function Payload()
    return table.concat({ Enc(current.k), tostring(current.ts), Enc(current.by) }, ":")
end

-- target: whisper to one player; nil: to everyone (GUILD and relays)
local function Share(target)
    if not current then return end
    lastShared = GetTime()
    if target then Most.Whisper(target, "KEY", Payload(), "high") else Most.Send("KEY", Payload(), "high") end
end

local function NewKeyText()
    local seed = Hash(MyName() .. tostring(GetTime()) .. tostring(GetServerTime()) .. tostring(math.random()), 5381)
    local out = {}
    for i = 1, KEY_LENGTH do
        local d = (math.random(0, 35) + seed) % 36
        out[i] = CHARS:sub(d + 1, d + 1)
        seed = math.floor(seed / 36) + math.random(0, 9999)
    end
    return table.concat(out)
end

-- A new key from this officer's client. force: "/jagodka key", without the cooldown.
function Key.Create(reason, force)
    if not ctx or not ctx.isMeOfficer() or not Most.IsGuildAllowed(Most.MyGuild()) then return false end
    if not force and GetTime() - lastRotation < ROTATE_COOLDOWN then return false end
    lastRotation = GetTime()
    local ts = math.max(GetServerTime(), ((current and current.ts) or 0) + 1)
    Apply(NewKeyText(), ts, MyName())
    Share()
    if Monitor() then Monitor().Channel("New chat channel key: " .. reason) end
    return true
end

-- ============================================================================
-- PACKETS (called from core.lua); returns true if the packet was handled
-- ============================================================================
function Key.HandlePacket(pType, payload, senderName)
    if pType == "KEY" then
        local kEnc, ts, byEnc = strsplit(":", payload, 3)
        local k, by = Dec(kEnc), Dec(byEnc)
        ts = tonumber(ts)
        if not (k and ts and by) or #k ~= KEY_LENGTH or k:find("[^a-z0-9]") then return true end
        -- Some key exists in the community, even if we cannot accept it yet (e.g. its officer's roster has
        -- not arrived): an officer does not create a competing one
        keySeen = true
        -- From the officer who created it, or passed on by a known player; the officer must be one by the rosters
        local fromKnown = senderName == by or Most.FindKnownPlayer(senderName) ~= nil
        if not (fromKnown and ctx and ctx.isKnownOfficer(by)) then
            if Monitor() then Monitor().Channel("Ignored a chat channel key from " .. senderName .. ": " .. by .. " is not an officer by the rosters (kept, rosters requested)") end
            if fromKnown or not current then KeepPending(k, ts, by) end
            return true
        end
        if Apply(k, ts, by) then
            -- The relay passes a new key on at once (to its guild and the other relays), e.g. one it got by whisper
            if Most.IsRelay() and senderName ~= MyName() then Share() end
        elseif current and current.ts > ts and Most.IsRelay() and GetTime() - lastShared >= ANSWER_COOLDOWN then
            -- Someone still has an older key: we send ours to everyone
            Share()
            if Monitor() then Monitor().Channel(senderName .. " sent an older chat channel key, ours sent to everyone") end
        end
        return true
    elseif pType == "KREQ" then
        local theirs = tonumber(payload) or 0
        if senderName ~= MyName() and current and current.ts > theirs and Most.IsRelay() and Most.FindKnownPlayer(senderName) then
            Share(senderName)
            if Monitor() then Monitor().Channel("Sent the chat channel key to " .. senderName .. " (they asked, theirs was older)") end
        end
        return true
    end
    return false
end

-- ============================================================================
-- PROTECTION OF THE CHAT CHANNEL (bridge.lua calls these)
-- ============================================================================
-- Owner of the chat channel from its member list ("*" before the name)
function Key.CheckOwner(owner)
    if not owner or not current then return end
    local known = Most.FindKnownPlayer(owner) ~= nil
    -- Logged when the owner changes, so the log shows who holds the channel
    if owner ~= lastOwner then
        lastOwner = owner
        if Monitor() then Monitor().Channel("Chat channel owner: " .. owner .. (known and "" or " (outside the listed guilds)")) end
    end
    if known then return end
    if Monitor() then Monitor().Channel("Chat channel owned by " .. owner .. ", who is outside the listed guilds", true) end
    Key.Create("channel owner " .. owner .. " is outside the listed guilds")
end

-- Channel notice about the chat channel (arg1 of CHAT_MSG_CHANNEL_NOTICE)
function Key.OnNotice(notice)
    if notice == "WRONG_PASSWORD" or notice == "BANNED" then
        local reason = (notice == "BANNED") and "banned from the chat channel" or "the chat channel has another password"
        if Monitor() then Monitor().Channel(reason, true) end
        if not Key.Create(reason) and not warned and _G.DEFAULT_CHAT_FRAME then
            warned = true
            _G.DEFAULT_CHAT_FRAME:AddMessage("|cffbf40ff[Jagodka]|r |cffff5555Chat channel unavailable (" .. reason .. "). An officer can create a new one with /jagodka key.|r")
        end
    elseif notice == "YOU_LEFT" then
        -- Another addon (e.g. one tidying channels) removed us: we come back after a moment
        if Monitor() then Monitor().Channel("Removed from the chat channel, joining again in 5 s") end
        C_Timer.After(5, Key.Join)
    elseif notice == "YOU_JOINED" or notice == "YOU_CHANGED" then
        local name = Key.ChannelName()
        if name then Most.HideFromChat(name) end
        if notice == "YOU_JOINED" and Monitor() then Monitor().Channel("Joined the chat channel") end
    end
end

-- ============================================================================
-- WITHOUT A KEY (checked every minute, not only at login, so guilds created later on a fresh server work too)
-- ============================================================================
-- A key we could not accept yet, because its officer's guild roster has not arrived: { k, ts, by }
local pendingKey = nil
local lastRosterAsk = -ROSTER_ASK_COOLDOWN

-- Called when a key from an unknown officer arrives: we remember it and ask for the missing rosters,
-- so it is accepted within a minute instead of after the next full roster (up to 30 min)
KeepPending = function(k, ts, by)
    if not pendingKey or ts > pendingKey.ts then pendingKey = { k = k, ts = ts, by = by } end
    if GetTime() - lastRosterAsk >= ROSTER_ASK_COOLDOWN and addonTable.Roster then
        lastRosterAsk = GetTime()
        addonTable.Roster.RequestStale()
    end
end

KeylessCheck = function()
    -- The remembered key, once its officer is known from the rosters
    if pendingKey and ctx and ctx.isKnownOfficer(pendingKey.by) then
        local p = pendingKey
        pendingKey = nil
        if Apply(p.k, p.ts, p.by) then
            if Monitor() then Monitor().Channel("Accepted the remembered chat channel key: " .. p.by .. " is now known as an officer") end
            if Most.IsRelay() then Share() end
        end
    end
    if current or not _G.IsInGuild() or not Most.IsGuildAllowed(Most.MyGuild()) then return end
    -- Only the relay asks again (its request also reaches other guilds); the rest of the guild gets the key
    -- from the relay as soon as it has one (HandlePacket)
    if Most.IsRelay() then Most.Send("KREQ", "0", "high") end
    -- Nobody in the community has a key yet: an officer creates one
    if not keySeen and GetTime() - loginAt >= KEY_WAIT then Key.Create("no key in the community yet") end
end

-- ============================================================================
-- EVENTS
-- ============================================================================
local Listener = CreateFrame("Frame")
Listener:RegisterEvent("ADDON_LOADED")
Listener:RegisterEvent("PLAYER_LOGIN")
Listener:RegisterEvent("PLAYER_GUILD_UPDATE")
Listener:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        _G.JagodkiChatDB = _G.JagodkiChatDB or {}
        local saved = _G.JagodkiChatDB.key
        if type(saved) == "table" and type(saved.k) == "string" and #saved.k == KEY_LENGTH and tonumber(saved.ts) then current = saved end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        -- Joining the chat channel itself comes with the public one (Most.JoinChannel, 8 s after login)
        -- Asked twice: the second time the rosters have arrived, so a key from an officer of another guild,
        -- not known at the first answer, is accepted then
        for _, delay in ipairs(REQUEST_DELAYS) do
            C_Timer.After(delay, function() Most.Send("KREQ", tostring((current and current.ts) or 0), "high") end)
        end
        loginAt = GetTime()
        C_Timer.NewTicker(KEYLESS_CHECK_INTERVAL, KeylessCheck)
        C_Timer.NewTicker(KEY_SHARE_INTERVAL, function()
            if Most.IsRelay() then Share() end
        end)
        -- Officers read the chat channel's member list, so a foreign owner is noticed (Key.CheckOwner)
        C_Timer.NewTicker(OWNER_CHECK_INTERVAL, function()
            if ctx and ctx.isMeOfficer() and Key.ChannelId() then Most.ListChannel(Key.ChannelName()) end
        end)
    elseif event == "PLAYER_GUILD_UPDATE" then
        -- Joined a guild during the session (e.g. a guild just created on a fresh server): ask it for the key
        -- at once instead of waiting for the relay's next regular send
        if not current and _G.IsInGuild() then
            C_Timer.After(GUILD_JOIN_DELAY, function()
                if not current and _G.IsInGuild() then Most.Send("KREQ", "0", "high") end
            end)
        end
    end
end)
