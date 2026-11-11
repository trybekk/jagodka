-- ============================================================================
-- BRIDGE: transport of addon packets and the shared addon chat of all listed guilds
-- ============================================================================
-- Rules:
--  * Every message has a unique ID, so the receiver drops duplicates.
--  * In each guild one person with the addon is the RELAY (the alphabetically first name
--    among online players with the addon). The relay links guilds: it whispers GUILD packets
--    to the relays of other guilds, who repost them to their GUILD. Status packets (PING/PONG) are
--    passed on only for the relay itself; other guilds know the rest of our players from the roster.
--  * The shared chat is written only from the addon (window or chat tab). Guild chat (/g) stays
--    in its own guild: nothing is carried between /g and the shared chat.
--  * From 0.12.0 typed messages go on the global channel as normal chat (SayOnChannel), so they
--    do not use the relays. Messages from older versions still arrive through the relays (GMSG).
--  * A new player gets the history from someone online after logging in.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_ChatInfo = _G.C_ChatInfo
local C_Timer = addonTable.SafeTimer -- protected callbacks (safe.lua)
local CreateFrame = _G.CreateFrame
local GetChannelName = _G.GetChannelName
local GetGuildInfo = _G.GetGuildInfo
local GetServerTime = _G.GetServerTime
local GetTime = _G.GetTime
local UnitName = _G.UnitName
local Ambiguate = _G.Ambiguate
local IsInGuild = _G.IsInGuild
local strsplit = _G.strsplit
local date = _G.date
local select = _G.select
local pairs, ipairs, tostring, tonumber = _G.pairs, _G.ipairs, _G.tostring, _G.tonumber
local table, string, math = _G.table, _G.string, _G.math

local PREFIX = "JagodkaComm"
-- Regular channel (JoinChannelByName), separate for each faction. Classic blocks addon packets
-- on player channels (SendAddonMessage returns 4 = InvalidChatType), so the channel is only used to
-- find players from other guilds. Packets go over GUILD and whispers between relays (Route).
local COMM_CHANNEL_ALLIANCE, COMM_CHANNEL_HORDE = "JagodkaNet", "JagodkaNetH"
local OLD_COMM_CHANNEL = "JagodkaWspolnota" -- left when joining the new channel
-- Channel password: an outsider cannot /join and get on the list that relays use to find each other.
-- It is visible in the addon code, so it stops random people, not someone who has the addon.
local COMM_PASSWORD = "jgdk7Wsp0lnota"
local ONLINE_TIMEOUT = 150            -- seconds without a signal after which a player is offline
local MAX_LOG = 300                   -- how many messages we keep (memory + SavedVariables)
local HISTORY_SYNC_MAX = 30           -- how many of the latest messages we send to a new player
local MAX_ADDON_BYTES = 205           -- addon packet limit is 255 bytes, this leaves room for the "FW:First Surname:" header
local DISCOVER_INTERVAL, HELLO_RETRY = 30, 600 -- how often the relay reads the channel list and repeats a greeting (s)
local CHANNEL_MEMBER_TTL = 70         -- seconds a name stays on our channel list without being seen again (lists are read every 30 s)
local RELAY_READY_DELAY = 5           -- after login we wait for answers from others before treating ourselves as relay
local MAX_GREETINGS = 5               -- greetings per read of the channel list (1 once linked), so a fresh install does not whisper everyone at once
local RELAY_CHECK_INTERVAL = 5        -- how often we check whether we just became the relay (s)

local Most = {}
addonTable.Most = Most
Most.ONLINE_TIMEOUT = ONLINE_TIMEOUT
Most.MAX_CHAT_BYTES = 255             -- message limit on the shared chat, the same as the game's chat
local MAX_MESSAGE_PARTS = 10          -- a message in more parts is rejected by the receiver
local PARTS_WAIT = 8                  -- how long the receiver waits for all parts of a message (s)

-- Context from core.lua: activePlayers, isGuildAllowed, onChatChanged, sendHello, announce
local ctx = nil
function Most.Init(c) ctx = c end
function Most.IsGuildAllowed(guild) return ctx ~= nil and ctx.isGuildAllowed(guild) end

-- Check against the guild roster whether a guildmate is online (true/false, nil = unknown).
-- Lets us exclude a logged-out relay at once, without waiting for ONLINE_TIMEOUT.
local guildmateOnlineCheck = nil
function Most.SetGuildmateOnlineCheck(fn) guildmateOnlineCheck = fn end

local channelProblem = nil -- description of a global channel problem (foreign password / ban), shown in the status

local function MyName() return Most.MyName() end
-- GetGuildInfo() can briefly return nil (after a loading screen, after joining a guild),
-- so we remember the last known name; IsInGuild() makes sure it is not used after leaving the guild
local lastGuildName = nil
local function MyGuild()
    local g = GetGuildInfo("player")
    if g and g ~= "" then lastGuildName = g return g end
    if not IsInGuild() then lastGuildName = nil return nil end
    if _G.C_GuildInfo and _G.C_GuildInfo.GuildRoster then _G.C_GuildInfo.GuildRoster() elseif _G.GuildRoster then _G.GuildRoster() end
    return lastGuildName
end
Most.MyGuild = MyGuild
-- Guild change (leaving / new guild): the remembered name must not carry over to the new guild
function Most.ResetGuild() lastGuildName = nil end

-- ============================================================================
-- SECRET VALUES
-- ============================================================================
-- In dungeons (and encounters) the game can hand addons chat text as "secret values": they may be passed on,
-- but reading them (match, find, sub, comparing) is an error ("attempt to index local 'message' (a secret
-- string value ...)", seen in a dungeon on 0.15.0). Every chat event handler checks its strings first and
-- skips the event when one is secret; the game's own chat still shows the line.
local issecretvalue = _G.issecretvalue
function Most.IsSecret(...)
    if not issecretvalue then return false end
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then return true end
    end
    return false
end

-- ============================================================================
-- FIELD ENCODING (":" is the packet separator)
-- ============================================================================
function Most.EncodeField(s)
    return (tostring(s or ""):gsub("%%", "%%25"):gsub(":", "%%3A"):gsub("\n", "%%0A"))
end

-- ============================================================================
-- PLAYER NAMES
-- ============================================================================
-- On WoW Forever every character has a surname, and first names repeat: only "first name surname" is
-- unique. The game keeps the surname where other clients keep the realm: UnitName("player") returns
-- "Marianek", "Jagoda", senders can come as "Marianek-Jagoda", the guild roster and chat as
-- "Marianek Jagoda". The addon identifies a character by "Marianek Jagoda" (one space) everywhere.
-- On a client without surnames (Classic Era) the name stays as before: without the realm.
-- Checked each time (cheap), because the player's data may not be ready while the addon loads
local function HasSurnames()
    local _, surname = UnitName("player")
    return surname ~= nil and surname ~= ""
end

-- Every name taken from the game goes through this, so one character is one name
function Most.PlayerKey(name)
    if not name or name == "" then return name end
    if not HasSurnames() then return Ambiguate(name, "none") end
    -- "Name-Surname" (the realm place) and "Name Surname" give the same key
    return (name:gsub("%-", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- Name for the game's own functions (whisper, invite, group check, player links): "Marianek-Jagoda",
-- the surname in the realm place, as the game gives it. Without surnames the name as it is.
function Most.GameName(key)
    if not key or not HasSurnames() then return key end
    return (key:gsub(" ", "-"))
end

-- My own name in the same form ("Marianek Jagoda" on Forever)
function Most.MyName()
    local first, surname = UnitName("player")
    if surname and surname ~= "" then return first .. " " .. surname end
    return first
end

function Most.DecodeField(s)
    if not s then return nil end
    return (s:gsub("%%0A", "\n"):gsub("%%3A", ":"):gsub("%%25", "%%"))
end
local Enc, Dec = Most.EncodeField, Most.DecodeField

-- Text from other players without formatting codes ("|"): nobody can inject colors, textures
-- or fake links into a name, guild, event title, etc.
function Most.Plain(s)
    return s and (s:gsub("|", ""))
end

-- Chat message text: only valid links remain (items, spells, professions...), every other "|" is removed.
-- A link: color, "|H...|h", the visible text, "|h|r". The color is "|cffRRGGBB" on older clients and
-- "|cnIQ3:" (item quality) on newer ones (WoW Forever); the visible text may hold a quality icon
-- ("|A...|a"), but nothing else with "|".
local LINK_CANDIDATE = "|c[^|]*|H[^|]+|h.-|h|r"
local function IsValidLink(link)
    local color, inner = link:match("^|c([^|]*)|H[^|]+|h(.-)|h|r$")
    if not color then return false end
    if not (color:match("^%x%x%x%x%x%x%x%x$") or color:match("^n[%w_]+:$")) then return false end
    return not inner:gsub("|A[^|]*|a", ""):find("|", 1, true)
end
Most.LINK_CANDIDATE = LINK_CANDIDATE

function Most.SanitizeChat(text)
    local out, pos = {}, 1
    while true do
        local s, e = text:find(LINK_CANDIDATE, pos)
        -- A candidate that is not a valid link is treated as plain text
        while s and not IsValidLink(text:sub(s, e)) do s, e = text:find(LINK_CANDIDATE, s + 1) end
        table.insert(out, (text:sub(pos, s and (s - 1) or #text):gsub("|", "")))
        if not s then break end
        table.insert(out, text:sub(s, e))
        pos = e + 1
    end
    return table.concat(out)
end

-- Encodes text and splits it into chunks whose length is counted AFTER encoding,
-- without cutting UTF-8 characters (the first chunk may have a different limit than the rest)
function Most.EncodeChunks(text, firstMax, restMax)
    local chunks, current, limit = {}, "", firstMax
    for ch in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local enc = Enc(ch)
        if #current + #enc > limit then
            table.insert(chunks, current)
            current, limit = "", restMax
        end
        current = current .. enc
    end
    table.insert(chunks, current)
    return chunks
end

-- ============================================================================
-- GLOBAL CHANNEL
-- ============================================================================
-- Horde and Alliance have separate channels (the game does not connect factions anyway)
local function ChannelName()
    return (_G.UnitFactionGroup("player") == "Horde") and COMM_CHANNEL_HORDE or COMM_CHANNEL_ALLIANCE
end
Most.ChannelName = ChannelName

function Most.GetChannelId()
    local id = GetChannelName(ChannelName())
    if id and id > 0 then return id end
    return nil
end

-- Hide the channel from chat windows so it does not clutter the chat
local function HideFromChat(name)
    if not _G.ChatFrame_RemoveChannel then return end
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf then _G.ChatFrame_RemoveChannel(cf, name) end
    end
end
Most.HideFromChat = HideFromChat

function Most.JoinChannel()
    -- The old temporary channel (up to 0.7.6) is no longer useful, so we leave it
    if (GetChannelName(OLD_COMM_CHANNEL) or 0) > 0 and _G.LeaveChannelByName then _G.LeaveChannelByName(OLD_COMM_CHANNEL) end
    local name = ChannelName()
    if not Most.GetChannelId() then _G.JoinChannelByName(name, COMM_PASSWORD) end
    HideFromChat(name)
    -- The chat channel from the secret key (key.lua), when we have one
    if addonTable.Key then addonTable.Key.Join() end
end

-- Name of the chat channel from the secret key (key.lua), or nil
local function KeyChannelName()
    return addonTable.Key and addonTable.Key.ChannelName()
end

-- For Monitoring when joining fails: the channels we are on, ours named by their role (never the secret names),
-- so the game's channel limit or another addon's channels show in the log
function Most.ChannelListText()
    local list, out = { _G.GetChannelList() }, {}
    local keyName = KeyChannelName()
    local offName = addonTable.Officers and addonTable.Officers.ChannelName()
    for i = 1, #list, 3 do
        local id, name = list[i], list[i + 1]
        if type(name) == "string" then
            local low = name:lower()
            if keyName and low == keyName:lower() then name = "Jagodka chat"
            elseif offName and low == offName:lower() then name = "Jagodka officers" end
        end
        table.insert(out, tostring(id) .. " " .. tostring(name))
    end
    return #out .. " channels: " .. (#out > 0 and table.concat(out, ", ") or "-")
end

-- ============================================================================
-- SEND QUEUE (keeps the order and stays within Blizzard's limits)
-- ============================================================================
-- DIAGNOSTICS (Monitoring tab): rejected messages by reason
local debug = { rejected = {} }
local function Count(t, key)
    t[key] = (t[key] or 0) + 1
    -- A duplicate is normal, because our own messages come back; anything else goes to the log
    if addonTable.Monitor and not key:find("duplicate", 1, true) then addonTable.Monitor.Note("Rejected: " .. key) end
end

local highQueue, lowQueue = {}, {}  -- high: current messages, low: history
local tokens, MAX_TOKENS, TOKENS_PER_SEC = 10, 10, 1
local whisperedAt = {}              -- name -> time of the last addon whisper (to recognize "player offline")

function Most.Send(pType, payload, priority)
    local item = { msg = pType .. ":" .. payload, tries = 0, queued = GetTime() }
    table.insert(priority == "low" and lowQueue or highQueue, item)
end

function Most.Whisper(target, pType, payload, priority)
    table.insert(priority == "high" and highQueue or lowQueue, { msg = pType .. ":" .. payload, target = target, tries = 0, queued = GetTime() })
end

function Most.GetLowQueueSize() return #lowQueue end

-- Older API returns a bool, newer a code from Enum.SendAddonMessageResult (0 = success)
local function IsOk(result) return result == nil or result == true or result == 0 end
-- Temporary limit (3 = AddonMessageThrottle, 8 = ChannelThrottle; false = older API): worth retrying.
-- 9 (GeneralError) and 11 (AddOnMessageLockdown) are temporary too: in the 0.15.0 log single GUILD packets got
-- 11 for a moment (7 times in 2 h; the next packet a second later went fine), and were lost.
-- Other codes (e.g. 4 = InvalidChatType) are permanent: retrying would only block the queue.
local function IsThrottle(result) return result == false or result == 3 or result == 8 or result == 9 or result == 11 end

-- Returns the API result and the channel kind (for diagnostics)
local function SendRaw(item)
    if item.target then
        -- Keyed by the base name ("player not found" check), sent to the full name
        whisperedAt[Most.PlayerKey(item.target)] = GetTime()
        return C_ChatInfo.SendAddonMessage(PREFIX, item.msg, "WHISPER", Most.GameName(Most.PlayerKey(item.target))), "WHISPER"
    end
    if IsInGuild() then
        return C_ChatInfo.SendAddonMessage(PREFIX, item.msg, "GUILD"), "GUILD"
    end
    return true, "NONE"
end

local function PumpAddonQueue()
    tokens = math.min(MAX_TOKENS, tokens + TOKENS_PER_SEC * 0.2)
    if tokens < 1 then return end
    local queue = (#highQueue > 0) and highQueue or lowQueue
    local item = queue[1]
    if not item then return end
    local result, kind = SendRaw(item)
    local ok = IsOk(result)
    -- On a temporary server limit we retry for a long time (about 30 s) so the message is not lost
    if ok or not IsThrottle(result) or item.tries >= 30 then
        if addonTable.Monitor then addonTable.Monitor.TX(item.msg, kind, item.target, ok, result, GetTime() - item.queued, item.tries) end
        table.remove(queue, 1)
        tokens = tokens - 1
    else
        if item.tries == 0 and addonTable.Monitor then addonTable.Monitor.Throttled(item.msg) end
        item.tries = item.tries + 1
        tokens = 0
    end
end

-- ============================================================================
-- TEXT SPLITTING (UTF-8 characters and item links must not be cut)
-- ============================================================================
local function Utf8Cut(s, maxBytes)
    local cut = maxBytes
    while cut > 1 do
        local b = s:byte(cut + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        cut = cut - 1
    end
    return s:sub(1, cut), s:sub(cut + 1)
end

local SplitText
-- Also for the officers chat (officers.lua)
function Most.SplitText(text, maxBytes) return SplitText(text, maxBytes) end
SplitText = function(text, maxBytes)
    if #text <= maxBytes then return { text } end
    -- Tokens: a colored link as a whole, the rest of the text by words
    local parts = {}
    local pos = 1
    while pos <= #text do
        local s, e = text:find(LINK_CANDIDATE, pos)
        local plainEnd = s and (s - 1) or #text
        if plainEnd >= pos then
            for word in text:sub(pos, plainEnd):gmatch("[^ ]* *") do
                if word ~= "" then table.insert(parts, word) end
            end
        end
        if not s then break end
        table.insert(parts, text:sub(s, e))
        pos = e + 1
    end
    local chunks, current = {}, ""
    for _, tok in ipairs(parts) do
        if #current + #tok <= maxBytes then
            current = current .. tok
        else
            if current ~= "" then table.insert(chunks, current) current = "" end
            -- A single very long word is cut at a UTF-8 character boundary
            while #tok > maxBytes and not tok:find("^|c") do
                local head, rest = Utf8Cut(tok, maxBytes)
                table.insert(chunks, head)
                tok = rest
            end
            current = tok
        end
    end
    if current ~= "" then table.insert(chunks, current) end
    return chunks
end

-- ============================================================================
-- MESSAGE LOG (single source of truth for the shared chat view)
-- ============================================================================
local chatLog = {}       -- { id, ts, guild, author, tab, src ("A" from the addon, "S" system), text }
local seenIds = {}
local msgSeq = 0

local function NewMessageId()
    msgSeq = msgSeq + 1
    return string.format("%s.%x.%x", MyName(), GetServerTime(), msgSeq)
end

function Most.GetLog() return chatLog end

local function TrimLog()
    while #chatLog > MAX_LOG do table.remove(chatLog, 1) end
end

-- History is inserted by server time; current messages are appended in order of arrival
local function InsertByTime(entry)
    local i = #chatLog
    while i > 0 and (chatLog[i].ts or 0) > entry.ts do i = i - 1 end
    table.insert(chatLog, i + 1, entry)
end

local function NotifyChat(tab)
    if ctx and ctx.onChatChanged then ctx.onChatChanged(tab) end
end

function Most.AddSystem(text)
    table.insert(chatLog, { id = "sys", ts = GetServerTime(), tab = "Ogolny", src = "S", text = text })
    NotifyChat("Ogolny")
end

-- Author's class and level: online players with the addon, then guild rosters (nil when unknown)
local function AuthorInfo(name)
    if ctx then
        for _, p in ipairs(ctx.activePlayers) do
            if p.name == name then return p.class, tonumber(p.level) end
        end
    end
    if addonTable.Roster then return addonTable.Roster.GetClassLevel(name) end
    return nil, nil
end

-- Short guild names in chat; a guild missing here shows its full name
local GUILD_TAGS = {
    ["Jagódki Nadina"] = "JN",
    ["Jagódki Nadina II"] = "JN2",
    ["Jagódki Nadina IIl"] = "JN3",   -- the third guild ("III" is not allowed by the game)
    ["Jagódki Nadina IV"] = "JN4",
    ["Jagódki Nadina V"] = "JN5",
    ["Jagódki Nadina VI"] = "JN6",
}
-- Short tag of a guild ("JN2"), its full name when it has none (e.g. the officers panel in core.lua)
function Most.GuildTag(guild)
    return guild and (GUILD_TAGS[guild] or guild) or "?"
end

-- Guild of a chat channel author not known from the rosters yet (HandleChannelMessage)
local UNKNOWN_GUILD = "?"

-- "[JN]" with a gray bracket and a muted purple tag; "[?]" in gray for a guild not known yet
local function GuildLabel(guild)
    if not guild or guild == UNKNOWN_GUILD then return "|cff808080[?]|r" end
    return "|cff808080[|r|cff9d7fc0" .. (GUILD_TAGS[guild] or guild) .. "|r|cff808080]|r"
end

-- "[60] Name" with the brackets in the game's gold, the level in white and the name in the class color, as a player link (click = whisper,
-- right click = menu). Without a known level, no brackets.
local function AuthorLabel(name)
    local class, level = AuthorInfo(name)
    local color = class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
    local label = color and color:WrapTextInColorCode(name) or name
    if level then label = "|cffffd100[|r|cffffffff" .. level .. "|r|cffffd100]|r " .. label end
    -- The link carries the game's form of the name, so the game's own whisper works on it too
    return "|Hplayer:" .. Most.GameName(name) .. "|h" .. label .. "|h"
end

-- "[JN] [60] Name: text"; addon window: "21:05 [JN] [60] Name: text" (showTime)
-- textColor: text color, e.g. "ff3cb43c" (the color is restored after item links)
-- An LFG listing notice (lfg.lua sends "!lfg ..." on the LFG chat): the marker becomes a link that opens the
-- author's listing in the LFG tab. The link is built here, by each client, never sent: a link typed into a
-- chat message would be refused by the game.
local LFG_MARK = "!lfg "
local function LfgLink(author) return "|cff6cc4e6|Hgarrmission:jagodkalfg:" .. tostring(author) .. "|h[Open in LFG]|h|r" end

function Most.FormatEntry(e, textColor, showTime)
    if e.src == "S" then return "|cff00ccff[System]: " .. e.text .. "|r" end
    local text = e.text
    local lfg = text:sub(1, #LFG_MARK) == LFG_MARK
    if lfg then text = text:sub(#LFG_MARK + 1) end
    -- 0.15.6: a sign-up notice (events.lua) ends with <jn-event:id>: an [Open event] link, built here
    local eventId = text:match(" <jn%-event:(%w+)>$")
    if eventId then text = text:gsub(" <jn%-event:%w+>$", "") end
    if textColor then text = "|c" .. textColor .. text:gsub("|r", "|r|c" .. textColor) .. "|r" end
    if lfg then text = text .. " " .. LfgLink(e.author) end
    if eventId then text = text .. " |cff6cc4e6|Hgarrmission:jagodkaev:" .. eventId .. "|h[Open event]|h|r" end
    local time = showTime and ("|cff808080" .. date("%H:%M", e.ts) .. "|r ") or ""
    return string.format("%s%s %s: %s", time, GuildLabel(e.guild), AuthorLabel(e.author), text)
end

-- Listeners for new messages (e.g. the tab in Blizzard chat): fn(entry, live)
local entryListeners = {}
function Most.OnNewEntry(fn) table.insert(entryListeners, fn) end

-- ============================================================================
-- RELAY: one person with the addon per guild links it to other guilds
-- ============================================================================
-- Relay of any guild (the same rule is computed by everyone, so everyone sees the same result)
function Most.GetRelayName(guild)
    guild = guild or MyGuild()
    if not guild or not ctx then return nil end
    local best = (guild == MyGuild()) and MyName() or nil
    local now = GetTime()
    local isMyGuild = (guild == MyGuild())
    for _, p in ipairs(ctx.activePlayers) do
        -- A guildmate logged out according to the roster cannot be relay, even before the timeout passes
        local offlineInRoster = isMyGuild and guildmateOnlineCheck ~= nil and guildmateOnlineCheck(p.name) == false
        if p.guild == guild and not offlineInRoster and (now - (p.lastSeen or 0)) < ONLINE_TIMEOUT and (not best or p.name < best) then
            best = p.name
        end
    end
    return best
end

-- Whether I can forward messages (I am in a listed guild and a moment has passed since login).
-- Without this delay a fresh login knows nobody yet, treats itself as relay and forwards packets needlessly.
local relayReadyAt = math.huge
local function CanForward()
    if not ctx or GetTime() < relayReadyAt or not IsInGuild() then return false end
    return ctx.isGuildAllowed(MyGuild())
end

function Most.IsRelay()
    return CanForward() and Most.GetRelayName() == MyName()
end

-- ============================================================================
-- RECEIVING MESSAGES (deduplication by ID)
-- ============================================================================
-- A channel message has a different ID on every client, so history from someone else can bring back one we
-- already have, and a message sent through the relays after its channel echo was late arrives both ways:
-- the same author, tab and text within two minutes counts as the same message. A live message only matches
-- one that came the other way (channel = via "C"), so a player repeating a line on the channel still shows twice.
local SAME_MESSAGE_WINDOW = 120
local function HasSameMessage(e, live)
    for i = #chatLog, math.max(1, #chatLog - 100), -1 do
        local o = chatLog[i]
        if o.author == e.author and o.tab == e.tab and o.text == e.text and math.abs((o.ts or 0) - (e.ts or 0)) <= SAME_MESSAGE_WINDOW
            and (not live or (o.via == "C") ~= (e.via == "C")) then return true end
    end
    return false
end

local function Ingest(e, live)
    if seenIds[e.id] then return false end
    if e.src == "A" and HasSameMessage(e, live) then
        seenIds[e.id] = true
        return false
    end
    -- Muted player (mute.lua): their messages do not reach the log
    if addonTable.Mute and addonTable.Mute.IsMuted(e.author) then return false end
    seenIds[e.id] = true
    -- Always by time written, so a late message (e.g. from a backup relay) lands in its proper place
    InsertByTime(e)
    TrimLog()
    NotifyChat(e.tab)
    for _, fn in ipairs(entryListeners) do fn(e, live) end
    return true
end

local function EncodeMessage(e)
    return table.concat({ Enc(e.id), tostring(e.ts), Enc(e.guild), Enc(e.author), Enc(e.tab), e.src, e.text }, ":")
end

local function DecodeMessage(payload)
    local id, ts, guild, author, tab, src, text = strsplit(":", payload, 7)
    if not (id and ts and guild and author and tab and src and text) then return nil end
    if src ~= "G" and src ~= "A" then return nil end
    local P = Most.Plain
    return { id = P(Dec(id)), ts = tonumber(ts) or 0, guild = P(Dec(guild)), author = P(Dec(author)), tab = P(Dec(tab)), src = src, text = Most.SanitizeChat(text) }
end

-- Packets of one message. Text that does not fit one packet goes in parts with the ID "id#part/total",
-- which the receiver puts back together (AcceptPacket). The header is counted at its longest.
local function EncodeParts(e)
    local header = string.format("GMSG:%s.ffffffff.ffff#10/10:%d:%s:%s:%s:%s:", string.rep("x", 24), 2000000000, Enc(e.guild), Enc(e.author), Enc(e.tab), e.src)
    local parts, packets = SplitText(e.text, MAX_ADDON_BYTES - #header), {}
    for i, part in ipairs(parts) do
        local id = (#parts > 1) and (e.id .. "#" .. i .. "/" .. #parts) or e.id
        packets[i] = EncodeMessage({ id = id, ts = e.ts, guild = e.guild, author = e.author, tab = e.tab, src = e.src, text = part })
    end
    return packets
end

-- Parts of messages still being received: id -> { author, guild, tab, src, ts, live, total, count, got = { part -> text } }
local partial = {}
-- Messages shown without all their parts: id -> { part -> true }. A late part is then shown on its own line.
local shownIncomplete = {}

local function FinishParts(id)
    local p = partial[id]
    if not p then return end
    partial[id] = nil
    local text = {}
    for i = 1, p.total do
        if p.got[i] then table.insert(text, p.got[i]) end
    end
    if p.count < p.total then
        shownIncomplete[id] = {}
        for i in pairs(p.got) do shownIncomplete[id][i] = true end
        if addonTable.Monitor then addonTable.Monitor.Note("Message from " .. p.author .. " shown without all parts (" .. p.count .. "/" .. p.total .. ")") end
    end
    Ingest({ id = id, ts = p.ts, guild = p.guild, author = p.author, tab = p.tab, src = p.src, text = table.concat(text) }, p.live)
end

-- A received packet: a whole message goes straight to the log, a part waits for the rest.
-- Returns false for a duplicate or a part that does not fit.
local function AcceptPacket(e, live)
    local id, part, total = e.id:match("^(.+)#(%d+)/(%d+)$")
    if not id then return Ingest(e, live) end
    part, total = tonumber(part), tonumber(total)
    if part < 1 or part > total or total > MAX_MESSAGE_PARTS then return false end
    if shownIncomplete[id] then
        if shownIncomplete[id][part] then return false end
        shownIncomplete[id][part] = true
        return Ingest(e, live)
    end
    if seenIds[id] then return false end
    local p = partial[id]
    if not p then
        p = { author = e.author, guild = e.guild, tab = e.tab, src = e.src, ts = e.ts, live = live, total = total, count = 0, got = {} }
        partial[id] = p
        C_Timer.After(PARTS_WAIT, function() FinishParts(id) end)
    elseif p.author ~= e.author or p.guild ~= e.guild or p.tab ~= e.tab or p.total ~= total then
        return false
    end
    if p.got[part] then return false end
    p.got[part] = e.text
    p.count = p.count + 1
    if p.count >= total then FinishParts(id) end
    return true
end

-- Publishes a new message to the shared chat
function Most.Publish(tab, text, src, author, guild, ts)
    if not text or text == "" or not guild then return end
    -- Time must be a number (log sorting); anything else = now
    ts = tonumber(ts) or GetServerTime()
    local e = { id = NewMessageId(), ts = ts, guild = guild, author = author, tab = tab, src = src, text = text }
    if Ingest(e, true) then
        for _, packet in ipairs(EncodeParts(e)) do Most.Send("GMSG", packet, "high") end
    end
end

-- ============================================================================
-- SHARED CHAT ON THE CHANNEL (from 0.12.0)
-- ============================================================================
-- Messages typed by players go on the global channel as normal chat: the server delivers them to everyone
-- on it, without relays and without the addon queue, so the chat keeps up with any number of players.
-- Each client puts what arrives into the log (HandleChannelMessage). Trade and LFG start with a tag,
-- which is also readable without the addon. Automatic notices (events, mutes) still go through the relays.
local TAB_TAGS = { Handel = "[Trade] ", ["Szukaj grupy"] = "[LFG] " }

-- The server sends our own channel message back to us. When it does not come back, the message goes through
-- the relays. If no message of ours has come back this session (e.g. the game does not let a low-level or
-- restricted character speak on channels), all further ones go through the relays until /reload, so the
-- player does not wait each time. Once the channel worked, a lost message (e.g. the server's flood limit
-- during fast typing) is only resent itself, and the next ones still go on the channel.
local ECHO_WAIT = 8        -- seconds we wait for our own message to come back from the channel
local awaitingEcho = {}    -- messages sent on the channel without their echo yet, oldest first: { tab, text, guild, parts }
local AlsoThroughGuilds    -- defined below (0.15.4)
local channelChatBlocked = false
local channelEchoSeen = false

local function OwnEchoArrived()
    channelEchoSeen = true
    local rec = awaitingEcho[1]
    if not rec then return end
    if rec.fromGameTab and addonTable.Monitor then addonTable.Monitor.Channel("Own message from the game chat tab came back from the chat channel") end
    rec.parts = rec.parts - 1
    if rec.parts <= 0 then table.remove(awaitingEcho, 1) end
end

-- ============================================================================
-- EVERY OWN MESSAGE THROUGH THE GUILDS TOO (0.15.4): WoW: Forever keeps players on several sub-realms, and a
-- channel made by players works within one of them only (10.11: the user on CAMWOWEU5Realm8PvP, others on other
-- sub-realms, "nobody sees my messages"; a new key helped only until the next relog). The guild and the relays
-- reach every sub-realm, so each message typed on General, Trade or LFG also goes as GMSG (the path older
-- versions always used and still read); a reader who gets both copies shows one (HasSameMessage). The channel
-- stays for speed on the own sub-realm. Chat is a few messages a minute, a small share of the guild traffic.
-- ============================================================================
AlsoThroughGuilds = function(rec)
    if not rec or rec.published or not rec.text or rec.text == "" then return end
    rec.published = true
    if rec.guild and Most.IsGuildAllowed(rec.guild) then Most.Publish(rec.tab, rec.text, "A", MyName(), rec.guild) end
end

-- Sends a typed message on the channel. The game allows channel messages only right after a key press or
-- click, so this must be called straight from the input's handler. Returns false when the channel is not
-- available; the caller then publishes through the relays as before.
function Most.SayOnChannel(tab, text)
    -- With the secret key only its chat channel (key.lua); the public channel only without a key
    local channelId
    if addonTable.Key and addonTable.Key.HasKey() then
        channelId = addonTable.Key.ChannelId()
    elseif not channelProblem then
        channelId = Most.GetChannelId()
    end
    if channelChatBlocked or not channelId or not _G.SendChatMessage or not text or text == "" then return false end
    local tag = TAB_TAGS[tab] or ""
    local parts = SplitText(text, Most.MAX_CHAT_BYTES - #tag)
    for _, part in ipairs(parts) do
        _G.SendChatMessage(tag .. part, "CHANNEL", nil, channelId)
    end
    local rec = { tab = tab, text = text, guild = MyGuild(), parts = #parts }
    table.insert(awaitingEcho, rec)
    -- 0.15.4: always through the guilds too (see AlsoThroughGuilds): the echo check below only logs now
    AlsoThroughGuilds(rec)
    C_Timer.After(ECHO_WAIT, function()
        if rec.parts <= 0 then return end
        for i, r in ipairs(awaitingEcho) do
            if r == rec then table.remove(awaitingEcho, i) break end
        end
        if channelEchoSeen then
            if addonTable.Monitor then addonTable.Monitor.Channel("Own message did not come back from the channel (server limit?); it went through the guilds") end
        else
            channelChatBlocked = true
            if addonTable.Monitor then addonTable.Monitor.Channel("Own message did not come back from the channel, chat goes through the guilds until /reload") end
        end
    end)
    if addonTable.Monitor then
        local which = (addonTable.Key and addonTable.Key.HasKey()) and "the chat channel (key)" or "the public channel"
        addonTable.Monitor.Channel("Own message sent on " .. which .. (#parts > 1 and (", " .. #parts .. " parts") or ""))
    end
    return true
end

-- A message typed in the community tab of the game chat: the game sends it on the chat channel itself (chattab.lua
-- calls this right before). It gets the same check as the addon window's: when it does not come back from the
-- channel within ECHO_WAIT, it goes through the relays. Before 0.15.2 such messages had no check at all, so
-- when the channel did not take them (the server refused them, e.g. a channel set to moderated) nobody saw them
-- and nothing showed in the log (a report of 09.11: "nobody sees my messages, I see theirs").
local lastExpected = { text = nil, at = 0 }
function Most.ExpectEcho(tab, text)
    if not text or text == "" then return end
    -- The game's input may run its parse hook twice for one message (the global function and the input's
    -- own method): one check per message
    if lastExpected.text == text and GetTime() - lastExpected.at < 1 then return end
    lastExpected.text, lastExpected.at = text, GetTime()
    local rec = { tab = tab, text = text, guild = MyGuild(), parts = 1, fromGameTab = true }
    table.insert(awaitingEcho, rec)
    if addonTable.Monitor then addonTable.Monitor.Channel("Own message sent on the chat channel from the game chat tab") end
    AlsoThroughGuilds(rec)
    C_Timer.After(ECHO_WAIT, function()
        if rec.parts <= 0 then return end
        for i, r in ipairs(awaitingEcho) do
            if r == rec then table.remove(awaitingEcho, i) break end
        end
        if addonTable.Monitor then addonTable.Monitor.Channel("Own message from the game chat tab did not come back from the channel; it went through the guilds") end
    end)
end

-- Publishes a message typed by the player: on the channel, or through the relays when there is no channel
function Most.PublishTyped(tab, text, author, guild)
    if Most.SayOnChannel(tab, text) then return end
    local reason = channelChatBlocked and "the channel did not take our messages this session"
        or ((addonTable.Key and addonTable.Key.HasKey()) and "not on the chat channel yet" or "no public channel")
    if addonTable.Monitor then addonTable.Monitor.Channel("Own message sent through the relays: " .. reason) end
    Most.Publish(tab, text, "A", author, guild)
end

-- A player we trust as a member of a listed guild: online with the addon (their status packet), or in a
-- guild roster. Relays do not pass on everyone's status packets to other guilds (only their own), so most
-- players of other guilds are known from the rosters. For them a stand-in entry with the roster data is returned.
function Most.FindKnownPlayer(name)
    if not ctx or not name then return nil end
    for _, p in ipairs(ctx.activePlayers) do
        if p.name == name then return ctx.isGuildAllowed(p.guild) and p or nil end
    end
    local guild, m = nil, nil
    if addonTable.Roster then guild, m = addonTable.Roster.FindMember(name) end
    if not guild then return nil end
    return { name = name, guild = guild, class = m.c, level = m.l, rankIndex = m.r, fromRoster = true }
end
local IsKnownAllowedSender = Most.FindKnownPlayer

-- ============================================================================
-- HISTORY SYNC
-- ============================================================================
local pendingHistory = {} -- requester -> true until someone else has answered

function Most.RequestHistory()
    local newest = 0
    for _, e in ipairs(chatLog) do
        if e.src ~= "S" and e.ts > newest then newest = e.ts end
    end
    Most.Send("HREQ", tostring(newest), "high")
    addonTable.Sync.Start("history") -- sync bar (sync.lua)
end

-- Sync requests answered by "one guildmate" (history, events, mutes, professions): with hundreds online,
-- everyone scheduling an answer sent dozens of claims (and answers) before the first claim arrived. Now only
-- about ANSWERERS of the guild's online players with the addon try at all, picked at random each time.
local ANSWERERS = 4

-- One answer per sync request. Before, guildmates whose random waits ended within a second of each other all
-- answered (the 0.14.1 log: about half the requests got 2 to 30 answers). Now after the wait we send the claim
-- and wait CLAIM_CONFIRM more: a claim from someone else cancels ours when it came before ours, or when both
-- were sent and their name sorts first. tbl[key] is a token while we wait, so "if tbl[key]" checks still work.
local CLAIM_CONFIRM = 1.5
function Most.ClaimAndAnswer(tbl, key, delay, sendClaim, answer)
    local token = { claimed = false }
    tbl[key] = token
    C_Timer.After(delay, function()
        if tbl[key] ~= token then return end
        token.claimed = true
        sendClaim()
        C_Timer.After(CLAIM_CONFIRM, function()
            if tbl[key] ~= token then return end
            tbl[key] = nil
            answer()
        end)
    end)
end

-- Someone else's claim for the same request (callers skip their own)
function Most.ClaimSeen(tbl, key, claimer)
    local token = tbl[key]
    if not token then return end
    if type(token) ~= "table" or not token.claimed or tostring(claimer) < MyName() then tbl[key] = nil end
end
-- The relay never answers when anyone else of the guild can: its queue also carries every packet between
-- guilds, and a long answer there delayed rosters and changes for the other guilds.
-- "0.15.0" >= "0.14.1"; a missing or odd version counts as old
local function AtLeast(version, min)
    local a = { tostring(version or ""):match("^(%d+)%.(%d+)%.(%d+)") }
    local b = { min:match("^(%d+)%.(%d+)%.(%d+)") }
    if not a[1] then return false end
    for i = 1, 3 do
        local x, y = tonumber(a[i]), tonumber(b[i])
        if x ~= y then return x > y end
    end
    return true
end

Most.AtLeast = AtLeast

-- ============================================================================
-- QUIET ONLINE SIGNALS (0.15.3; the idea is Olympus's hello): the "I am online" signal (PONG) every minute from
-- every player was about 70% of all traffic (logs of 07-10.11). Now only the first QUIET_FAST names of the guild's
-- online addon players (those who can become the relay) say it every minute; the others every QUIET_EVERY, and
-- newer clients keep a guildmate for QUIET_KEEP (the game's guild roster still says at once who logged out).
-- Older versions drop a quiet guildmate after 150 s (only their counts of addon players are lower), so it is on
-- only while at most QUIET_OLD_SHARE of the guild's online addon players run an older version.
-- ============================================================================
local QUIET_MIN_VERSION, QUIET_FAST, QUIET_EVERY, QUIET_OLD_SHARE = "0.15.3", 5, 600, 0.1
Most.QUIET_KEEP = 720
local lastPongAt, quietLogged = -math.huge, nil

-- Whether quiet signals are on in my guild now
function Most.QuietAllowed()
    if not ctx then return false end
    local myGuild, total, old = MyGuild(), 0, 0
    for _, p in ipairs(ctx.activePlayers) do
        if p.guild == myGuild then
            total = total + 1
            if not AtLeast(p.version, QUIET_MIN_VERSION) and p.name ~= MyName() then old = old + 1 end
        end
    end
    return total > 0 and old <= total * QUIET_OLD_SHARE
end

-- Called every minute (core.lua): true = send my PONG now
function Most.ShouldSendPong()
    local now, quiet = GetTime(), Most.QuietAllowed()
    if quiet ~= quietLogged then
        quietLogged = quiet
        if addonTable.Monitor then addonTable.Monitor.Note(quiet and "Quiet online signals on: only the first " .. QUIET_FAST .. " names of the guild signal every minute, the rest every " .. (QUIET_EVERY / 60) .. " min"
            or "Quiet online signals off (older versions online in the guild): everyone signals every minute") end
    end
    local send = true
    if quiet and now - lastPongAt < QUIET_EVERY then
        -- Am I among the first QUIET_FAST names of my guild's online addon players?
        local names, myGuild, me = {}, MyGuild(), MyName()
        for _, p in ipairs(ctx.activePlayers) do
            if p.guild == myGuild and (p.name == me or now - (p.lastSeen or 0) < Most.QUIET_KEEP) then table.insert(names, p.name) end
        end
        table.sort(names)
        send = false
        for i = 1, math.min(QUIET_FAST, #names) do if names[i] == me then send = true break end end
    end
    if send then lastPongAt = now end
    return send
end

-- minVersion: only guildmates with at least this version can answer (a new kind of request): counting the
-- older ones too made nobody answer about a third of the time while few had updated (0.15.0 log, LFG)
function Most.ShouldAnswer(minVersion)
    if not ctx then return false end
    local n, myGuild = 0, MyGuild()
    for _, p in ipairs(ctx.activePlayers) do
        if p.guild == myGuild and (not minVersion or p.name == MyName() or AtLeast(p.version, minVersion)) then n = n + 1 end
    end
    if n > 1 and Most.IsRelay() then return false end
    return n <= ANSWERERS or math.random() < ANSWERERS / n
end

local function HandleHistoryRequest(sender, rawSender, since)
    if not Most.ShouldAnswer() then return end
    since = tonumber(since) or 0
    local list = {}
    for _, e in ipairs(chatLog) do
        if e.src ~= "S" and e.ts > since then table.insert(list, e) end
    end
    if #list == 0 then return end
    while #list > HISTORY_SYNC_MAX do table.remove(list, 1) end
    -- Random delay: one person answers, the others see HCLAIM and give up (Most.ClaimAndAnswer)
    Most.ClaimAndAnswer(pendingHistory, sender, 0.5 + math.random() * 2, function() Most.Send("HCLAIM", sender, "high") end, function()
        for _, e in ipairs(list) do
            for _, packet in ipairs(EncodeParts(e)) do Most.Whisper(rawSender, "HIST", packet) end
        end
    end)
end

-- ============================================================================
-- PACKET HANDLING (called from core.lua); returns true if the packet was handled
-- ============================================================================
function Most.HandlePacket(pType, payload, channel, senderName, rawSender)
    if pType == "GMSG" or pType == "HIST" then
        if pType == "HIST" then addonTable.Sync.Activity("history") end
        local senderInfo = IsKnownAllowedSender(senderName)
        local e = DecodeMessage(payload)
        if not e then Count(debug.rejected, "bad format") return true end
        if not ctx.isGuildAllowed(e.guild) then Count(debug.rejected, "guild not listed: " .. tostring(e.guild)) return true end
        -- A /g line carried by an older version: guild chat no longer reaches the shared chat
        if e.src ~= "A" then Count(debug.rejected, "/g line from an older version") return true end
        if pType == "GMSG" then
            -- Only the author writes their own message
            if e.author ~= senderName then Count(debug.rejected, "author ~= sender") return true end
            if senderInfo and senderInfo.guild ~= e.guild then Count(debug.rejected, "sender guild mismatch") return true end
            -- Sender still unknown (their status packet has not arrived): we do NOT lose the message.
            -- We trust it as much as a status packet: it names a listed guild; if it claims to be
            -- from my guild, the sender must be in the roster.
            if not senderInfo and senderName ~= MyName() and e.guild == MyGuild()
                and guildmateOnlineCheck ~= nil and guildmateOnlineCheck(senderName) == false then
                Count(debug.rejected, "not in guild roster")
                return true
            end
            -- The same for another listed guild, when we have its recent whole roster
            if not senderInfo and senderName ~= MyName() and e.guild ~= MyGuild()
                and addonTable.Roster and addonTable.Roster.IsMember(senderName, e.guild) == false then
                Count(debug.rejected, "not in guild roster")
                return true
            end
        elseif not senderInfo and senderName ~= MyName() then
            -- History is accepted only from a known player (who answered our status packet)
            Count(debug.rejected, "history from unknown")
            return true
        end
        -- Our own messages come back from GUILD and also end up here
        if not AcceptPacket(e, pType == "GMSG") then Count(debug.rejected, "duplicate / own echo / muted") end
        return true
    elseif pType == "HREQ" then
        if senderName ~= MyName() and IsKnownAllowedSender(senderName) then
            HandleHistoryRequest(senderName, rawSender, payload)
        end
        return true
    elseif pType == "HCLAIM" then
        if senderName ~= MyName() then Most.ClaimSeen(pendingHistory, payload, senderName) end
        return true
    end
    return false
end

-- ============================================================================
-- LINKS BETWEEN GUILDS: guild relay <-> relays of other guilds (addon whisper)
-- ============================================================================
-- The relay wraps a GUILD packet as "FW:sender:packet" and whispers it to relays of other guilds.
-- The receiver reposts it unchanged to its own GUILD. Nobody forwards wrapped packets again.
-- Things people do right now go ahead of bulk sync (rosters, sign-up lists), so they arrive within seconds
local LIVE_PACKETS = {
    GMSG = true, EV_ADD = true, EV_DESC = true, EV_EDIT = true, EV_REM = true,
    EV_SIGN = true, EV_SPEC = true, EV_RL = true, EV_KICK = true,
    -- Events from 0.14.0 (events.lua)
    EH = true, ED = true, ES = true, EK = true, EX = true,
    -- LFG listings (lfg.lua)
    LF = true, LX = true,
    -- Officers' big messages for everyone (core.lua): announcements and chat test requests
    CANN = true, CTEST = true,
    -- A delayed status packet would make the player look offline, and their packets would be ignored
    PING = true, PONG = true,
    -- Roster changes (who logged in or out): small and rare, but behind a big guild's full roster they
    -- waited minutes, so a logged-out player of another guild still showed online
    RD = true,
}
local function ForwardPriority(text)
    return LIVE_PACKETS[(strsplit(":", text, 2))] and "high" or "low"
end

-- A forwarded online signal (PONG) still waiting in the queue is replaced by a newer one from the same player:
-- only the latest matters, so a busy queue holds at most one per player. A PING is never replaced,
-- because others answer it. target = nil for a repost to our guild.
local function ReplaceQueuedStatus(msg, target)
    local origin = msg:match("^FW:([^:]+):PONG:")
    if not origin then return false end
    local prefix = "FW:" .. origin .. ":PONG:"
    for _, item in ipairs(highQueue) do
        if item.target == target and item.msg:sub(1, #prefix) == prefix then
            item.msg = msg
            if addonTable.Monitor then addonTable.Monitor.Relay("Online signal of " .. origin .. " still queued, replaced by a newer one") end
            return true
        end
    end
    return false
end

-- Relays of other guilds from the online player list: guild -> name
local function OtherGuildRelays()
    local relays, mine = {}, MyGuild()
    for _, p in ipairs(ctx.activePlayers) do
        if p.guild ~= mine and not relays[p.guild] and ctx.isGuildAllowed(p.guild) then
            relays[p.guild] = Most.GetRelayName(p.guild)
        end
    end
    return relays
end
-- For roster.lua: full rosters go straight to the other guilds' relays (guild -> relay name)
Most.OtherGuildRelays = OtherGuildRelays

local function ForwardToOtherGuilds(origin, text)
    local payload = origin .. ":" .. text
    if #payload + #"FW:" > 255 then Count(debug.rejected, "too long to forward") return end
    for _, relay in pairs(OtherGuildRelays()) do
        if not ReplaceQueuedStatus("FW:" .. payload, relay) then Most.Whisper(relay, "FW", payload, ForwardPriority(text)) end
    end
end

-- Called for every packet before it is handled. Returns the content, channel kind and real
-- sender, or nil when the packet should not be handled.
-- Packet types the relay does not pass on to other guilds, except its own (Route)
local OWN_GUILD_ONLY = {
    PING = true, PONG = true, KREQ = true,
    HREQ = true, HCLAIM = true, EV_REQ = true, EV_CLAIM = true, MREQ = true, MCLAIM = true, EQ = true, EC = true, LQ = true, LC = true,
    PREQ = true, PREQN = true, PCLAIM = true,
    DQ = true, DC = true,   -- Discord names (discord.lua)
}

function Most.Route(text, channel, senderName)
    local pType, rest = strsplit(":", text, 2)
    if pType ~= "FW" then
        -- Our own packets too: the game echoes them from GUILD, so there is one path for everyone.
        -- Status packets (PING/PONG) of others stay in the guild: with hundreds of players they would fill
        -- the relay's queue (about 1 packet per second). Other guilds know our players from the roster
        -- and only need the relay's own status, to know whom to send to.
        -- A request for the chat channel key (KREQ, key.lua) is answered by our relay, so it stays in the guild,
        -- except the relay's own (then nobody else from the guild is there to answer).
        -- The same for the sync requests after login and their claims (history, events, mutes, professions):
        -- every guild has the same data, so the own guild answers.
        local isOwnOnly = OWN_GUILD_ONLY[pType]
        if channel == "GUILD" and Most.IsRelay() and (not isOwnOnly or senderName == MyName()) then ForwardToOtherGuilds(senderName, text) end
        -- Our own echo was already logged when sent
        if senderName ~= MyName() and addonTable.Monitor then addonTable.Monitor.RX(text, channel, senderName) end
        return text, channel, senderName
    end
    -- Our own packet reposted to GUILD: we already handled it when the whisper arrived
    if senderName == MyName() then return nil end
    local origin, inner = strsplit(":", rest or "", 2)
    origin = Most.PlayerKey(Most.Plain(origin))
    if not origin or origin == "" or not inner or origin == MyName() then return nil end
    if channel == "WHISPER" then
        -- Only a known player from a listed guild may speak for others; anyone may speak for themselves (greeting)
        if origin ~= senderName then
            local relay = IsKnownAllowedSender(senderName)
            if not relay then
                Count(debug.rejected, "forward from unknown")
                return nil
            end
            -- A relay passes on only its own guild's packets, so the origin must be in that guild's roster (when we have it)
            if addonTable.Roster and addonTable.Roster.IsMember(origin, relay.guild) == false then
                Count(debug.rejected, "forward of a player outside the relay's guild")
                return nil
            end
        end
        if not ReplaceQueuedStatus(text, nil) then
            table.insert(ForwardPriority(inner) == "high" and highQueue or lowQueue, { msg = text, tries = 0, queued = GetTime() })
        end
    elseif channel ~= "GUILD" then
        return nil
    end
    if addonTable.Monitor then addonTable.Monitor.RX(inner, "FW", origin, senderName, channel) end
    return inner, "FW", origin
end

-- Finding other guilds: the relay reads the channel member list and greets unknown players.
-- The greeted player reposts the PING to their guild, and its relay then knows us and forwards packets.
-- channelMembers: name -> when last seen on the list. A name expires by time instead of the list being
-- cleared on each read, because the answer can come in parts and reads can overlap.
local listAskedAt, helloAt, channelMembers = 0, {}, {}
local keyListAt, keyListCount = -math.huge, 0   -- the chat channel's last member list: when read, how many names
-- Players on the chat channel by its last member list, and how many seconds ago it was read (nil = never)
function Most.KeyChannelCount()
    if keyListAt == -math.huge then return nil end
    return keyListCount, GetTime() - keyListAt
end

function Most.HasLinkedGuilds()
    return ctx ~= nil and _G.next(OtherGuildRelays()) ~= nil
end

-- Reads the member list of a channel; the answer stays out of the chat (filter below)
function Most.ListChannel(name)
    if not _G.ListChannelByName or not name then return end
    listAskedAt = GetTime()
    _G.ListChannelByName(name)
end

-- Both channels: the public one and the chat channel from the key (where all players with the key are)
local function ListBoth()
    if Most.GetChannelId() then Most.ListChannel(ChannelName()) end
    if addonTable.Key and addonTable.Key.ChannelId() then Most.ListChannel(KeyChannelName()) end
end

function Most.Discover()
    if not Most.IsRelay() then return end
    ListBoth()
end

-- For the Monitoring tab, also when we are not the relay
function Most.RefreshChannelList()
    ListBoth()
end

local function IsActivePlayer(name)
    for _, p in ipairs(ctx.activePlayers) do
        if p.name == name then return true end
    end
    return false
end

-- A player of a guild we are already linked with (from the rosters) needs no greeting
local function IsLinked(name)
    local p = Most.FindKnownPlayer(name)
    return p ~= nil and p.guild ~= MyGuild() and Most.GetRelayName(p.guild) ~= nil
end

-- isKeyChannel: the list of the chat channel from the key, whose owner is checked (key.lua)
local function HandleChannelList(list, isKeyChannel)
    if not ctx then return end
    local now, isRelay, greeted = GetTime(), Most.IsRelay(), 0
    -- Already linked with another guild: one greeting per read is enough to find a guild that is still missing
    -- (without the other guild's roster every one of its players looks unknown, and each greeting is reposted
    -- to that whole guild)
    local maxGreetings = Most.HasLinkedGuilds() and 1 or MAX_GREETINGS
    for raw in tostring(list or ""):gmatch("[^,]+") do
        -- On the list the owner has "*" and a moderator "@"
        local name = Most.PlayerKey((raw:gsub("^%s+", ""):gsub("^[%*@%+]+", ""))) or ""
        if name ~= "" then channelMembers[name] = now end
        if isKeyChannel and name ~= "" and raw:find("*", 1, true) then addonTable.Key.CheckOwner(name) end
        -- 0.15.5: how many are on the chat channel (my sub-realm's players; the chat tab tooltips in core.lua)
        if isKeyChannel and name ~= "" then
            if now - keyListAt > 3 then keyListAt, keyListCount = now, 0 end
            keyListCount = keyListCount + 1
        end
        local isGuildmate = guildmateOnlineCheck ~= nil and guildmateOnlineCheck(name) == true
        if isRelay and greeted < maxGreetings and name ~= "" and name ~= MyName() and not isGuildmate and not IsActivePlayer(name)
            and now - (helloAt[name] or -HELLO_RETRY) >= HELLO_RETRY and ctx.sendHello and not IsLinked(name) then
            helloAt[name] = now
            greeted = greeted + 1
            if addonTable.Monitor then addonTable.Monitor.Relay("On the channel but unknown, greeting " .. name) end
            ctx.sendHello(name)
        end
    end
end

-- A message on the channel (shared chat from 0.12.0): from players of listed guilds (status packet or roster);
-- the guild comes from there, not from the message. 1.0.1: a player not known from our guilds is no longer shown
-- with a gray [?] (0.13.8), also on the chat channel from the secret key: the key is saved for the whole account,
-- so an alt outside our guilds knew the channel and could write to everyone. A player who has just joined one of
-- our guilds is seen anyway: since 0.15.4 every own message also goes through the guilds, and their name reaches
-- the rosters within minutes.
local function HandleChannelMessage(text, playerName, lineID, isKeyChannel)
    if not ctx or not text or not playerName then return end
    local author = Most.PlayerKey(playerName)
    if author == MyName() then OwnEchoArrived() end
    local p = Most.FindKnownPlayer(author)
    if not p then Count(debug.rejected, "channel message from a player not in the listed guilds") return end
    local tab = "Ogolny"
    for t, tag in pairs(TAB_TAGS) do
        if text:sub(1, #tag) == tag then tab, text = t, text:sub(#tag + 1) break end
    end
    text = Most.SanitizeChat(text)
    if text == "" then return end
    local ts = GetServerTime()
    Ingest({ id = string.format("C.%s.%x.%s", author, ts, tostring(lineID)), ts = ts, guild = p.guild, author = author, tab = tab, src = "A", text = text, via = "C" }, true)
end

local function NameFromSystemMessage(pattern, message)
    return pattern and message:match("^" .. pattern:gsub("%%s", "(.+)") .. "$")
end

local function RemoveActivePlayer(name)
    for i = #ctx.activePlayers, 1, -1 do
        if ctx.activePlayers[i].name == name then table.remove(ctx.activePlayers, i) end
    end
end

-- A whisper to a logged-out player gives a system message: we hide it and immediately remove the player
-- from the online list, so the next person becomes relay of that guild
local function HandlePlayerNotFound(message)
    if not ctx then return false end
    local name = NameFromSystemMessage(_G.ERR_CHAT_PLAYER_NOT_FOUND_S, message)
    name = name and Most.PlayerKey(name)
    if not name or GetTime() - (whisperedAt[name] or -10) >= 10 then return false end
    RemoveActivePlayer(name)
    if addonTable.Monitor then addonTable.Monitor.Relay("Whisper to " .. name .. " failed: player offline, removed from the list") end
    return true
end

if _G.ChatFrame_AddMessageEventFilter then
    _G.ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_LIST", function(_, _, ...)
        local name = select(9, ...)
        if Most.IsSecret(name) then return false end
        local officers = addonTable.Officers and addonTable.Officers.ChannelName()
        if (name == ChannelName() or (name ~= nil and (name == KeyChannelName() or name == officers))) and GetTime() - listAskedAt < 2 then return true end
    end)
    _G.ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, message)
        if Most.IsSecret(message) then return false end
        if HandlePlayerNotFound(message) then return true end
    end)
end

-- ============================================================================
-- CHAT CHANNEL REFUSALS SEEN BY EVERYONE (0.15.4): when the server refuses me the chat channel (Forever's
-- sub-realms: NOT_ALLOWED_IN_CHANNEL, INVALID_NAME; or a wrong password, a ban), my addon tells the community
-- in one small CREF packet (low priority, to GUILD and through the relays, at most every REFUSAL_REPORT_EVERY
-- while it lasts) with my sub-realm, and once more when I am back on the channel. Officers see in Monitoring who
-- cannot get onto the chat channel and on which sub-realm. Nothing is sent while all is well.
--   CREF:1:<reason>:<tries>:<sub-realm>   refused        CREF:0:ok:<tries>:<sub-realm>   back on the channel
-- ============================================================================
local REFUSAL_REPORT_EVERY = 1800   -- 0.15.5: every 30 min while it lasts (was 10; a refused player is still fine, the chat goes through the guilds)
local myRefusal = nil        -- { reason, tries, since, reportedAt }
local refusals = {}          -- other players: name -> { guild, reason, tries, realm, at }

local function SendRefusal(refused, reason, tries)
    local guild = MyGuild()
    if not guild or not Most.IsGuildAllowed(guild) then return end
    local realm = _G.GetNormalizedRealmName and _G.GetNormalizedRealmName() or "?"
    Most.Send("CREF", table.concat({ refused and "1" or "0", Enc(reason or "?"), tostring(tries or 0), Enc(realm) }, ":"), "low")
end

-- From the channel notices below: a refusal of the chat channel (reason) or being on it (reason = nil)
local function NoteChatChannel(reason)
    if reason then
        myRefusal = myRefusal or { tries = 0, since = GetTime(), reportedAt = -REFUSAL_REPORT_EVERY }
        myRefusal.tries, myRefusal.reason = myRefusal.tries + 1, reason
        if GetTime() - myRefusal.reportedAt >= REFUSAL_REPORT_EVERY then
            myRefusal.reportedAt = GetTime()
            SendRefusal(true, reason, myRefusal.tries)
        end
    elseif myRefusal then
        SendRefusal(false, "ok", myRefusal.tries)
        myRefusal = nil
    end
end

-- core.lua: CREF from a known player of a listed guild; true when it was one
function Most.HandleRefusal(pType, payload, senderName)
    if pType ~= "CREF" then return false end
    if senderName == MyName() then return true end
    local flag, reason, tries, realm = strsplit(":", payload, 4)
    reason, realm, tries = Most.Plain(Dec(reason) or "?"), Most.Plain(Dec(realm) or "?"), tonumber(tries) or 0
    local p = Most.FindKnownPlayer(senderName)
    local guild = p and p.guild or "?"
    if flag == "1" then
        refusals[senderName] = { guild = guild, reason = reason, tries = tries, realm = realm, at = GetTime() }
        -- Information, not an error (0.15.5): since 0.15.4 their chat goes through the guilds anyway
        if addonTable.Monitor then addonTable.Monitor.Channel("Chat channel refused for " .. senderName .. " (" .. Most.GuildTag(guild) .. ", " .. realm .. "): " .. reason .. ", " .. tries .. " tries") end
    else
        refusals[senderName] = nil
        if addonTable.Monitor then addonTable.Monitor.Channel(senderName .. " (" .. Most.GuildTag(guild) .. ", " .. realm .. ") is back on the chat channel after " .. tries .. " refused tries") end
    end
    return true
end

-- Monitoring: who cannot get onto the chat channel now (reported in the last 30 minutes), mine included
function Most.RefusalLines()
    local lines, now = {}, GetTime()
    if myRefusal then
        table.insert(lines, MyName() .. " (me, " .. tostring(_G.GetNormalizedRealmName and _G.GetNormalizedRealmName()) .. "): " .. tostring(myRefusal.reason) .. ", " .. myRefusal.tries .. " tries, " .. math.floor((now - myRefusal.since) / 60) .. " min")
    end
    for name, r in pairs(refusals) do
        if now - r.at > 1800 then refusals[name] = nil
        else table.insert(lines, name .. " (" .. Most.GuildTag(r.guild) .. ", " .. r.realm .. "): " .. r.reason .. ", " .. r.tries .. " tries, reported " .. math.floor((now - r.at) / 60) .. " min ago") end
    end
    table.sort(lines)
    return lines
end

-- ============================================================================
-- STATUS (Monitoring tab, monitor.lua)
-- ============================================================================
function Most.GetMonitorInfo()
    local linked, members = {}, {}
    if ctx then
        for guild, relay in pairs(OtherGuildRelays()) do table.insert(linked, guild .. " (" .. relay .. ")") end
        table.sort(linked)
    end
    local now = GetTime()
    for name, seenAt in pairs(channelMembers) do
        if now - seenAt <= CHANNEL_MEMBER_TTL then table.insert(members, name) end
    end
    table.sort(members)
    return {
        channelId = Most.GetChannelId(), channelName = ChannelName(), channelProblem = channelProblem, channelMembers = members,
        relay = Most.GetRelayName(), isRelay = Most.IsRelay(), linked = linked, rejected = debug.rejected,
        queueHigh = #highQueue, queueLow = #lowQueue, history = #chatLog,
        queueOldest = (highQueue[1] or lowQueue[1]) and GetTime() - (highQueue[1] or lowQueue[1]).queued or nil,
        relayReadyIn = (relayReadyAt ~= math.huge and GetTime() < relayReadyAt) and relayReadyAt - GetTime() or nil,
        greeted = helloAt, helloRetry = HELLO_RETRY, listAskedAt = (listAskedAt > 0) and listAskedAt or nil,
    }
end

-- ============================================================================
-- EVENTS: loading history, channel state
-- ============================================================================
local function Warn(text)
    if _G.DEFAULT_CHAT_FRAME then _G.DEFAULT_CHAT_FRAME:AddMessage("|cffbf40ff[Jagodka]|r |cffff5555" .. text .. "|r") end
end

local Listener = CreateFrame("Frame")
Listener:RegisterEvent("ADDON_LOADED")
Listener:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
Listener:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE_USER")
Listener:RegisterEvent("CHAT_MSG_CHANNEL_LIST")
Listener:RegisterEvent("CHAT_MSG_CHANNEL")
Listener:RegisterEvent("CHAT_MSG_SYSTEM")
Listener:RegisterEvent("PLAYER_LOGIN")
addonTable.SafeScript(Listener, "OnEvent", "bridge.lua:1138", function(self, event, arg1, arg2, ...)
    if event == "PLAYER_LOGIN" then
        relayReadyAt = GetTime() + RELAY_READY_DELAY
        return
    end
    -- Chat events with secret text (dungeons): skipped, see Most.IsSecret. Only what we read is checked: the
    -- text, the author, the channel name (9th) and the line ID (11th). 0.15.1 checked every argument, the
    -- sender's GUID and flags included, which the addon never reads; when one of them was secret for the
    -- reader (e.g. a player of another sub-realm on WoW: Forever) the whole message was dropped, so a player
    -- whose messages everyone had seen on 0.15.0 was seen by nobody on 0.15.1 (report of 09.11).
    if event ~= "ADDON_LOADED" and Most.IsSecret(arg1, arg2, (select(7, ...)), (select(9, ...))) then return end
    if event == "CHAT_MSG_SYSTEM" then
        -- "X has gone offline": a logged-out player (e.g. switching characters) loses the relay role at once
        local name = NameFromSystemMessage(_G.ERR_FRIEND_OFFLINE_S, arg1 or "")
        if name and ctx then RemoveActivePlayer(Most.PlayerKey(name)) end
        return
    end
    if event == "CHAT_MSG_CHANNEL" then
        -- 9th argument = channel name without number, 11th = line ID. Both channels: the public one still
        -- carries messages from versions before 0.13.0 and from players without the key.
        local name = select(7, ...)
        if name == ChannelName() then
            HandleChannelMessage(arg1, arg2, select(9, ...), false)
        elseif name ~= nil and name == KeyChannelName() then
            HandleChannelMessage(arg1, arg2, select(9, ...), true)
        elseif name ~= nil and addonTable.Officers and name == addonTable.Officers.ChannelName() then
            -- The officers chat: its own log, never the shared one (officers.lua)
            addonTable.Officers.HandleMessage(arg1, arg2, select(9, ...))
        end
        return
    end
    if event == "CHAT_MSG_CHANNEL_LIST" then
        local name = select(7, ...)
        if name == ChannelName() then HandleChannelList(arg1)
        elseif name ~= nil and name == KeyChannelName() then HandleChannelList(arg1, true)
        elseif name ~= nil and addonTable.Officers and name == addonTable.Officers.ChannelName() then addonTable.Officers.HandleList(arg1) end
        return
    end
    -- Moderation on our channels (0.15.2): mutes, kicks, bans, moderators, owner changes, a channel set to
    -- moderated (then only moderators may speak). Logged, so a chat that stops for some players shows why.
    if event == "CHAT_MSG_CHANNEL_NOTICE_USER" then
        local base = select(7, ...)
        if addonTable.Monitor and type(base) == "string" then
            local low, keyName, offName = base:lower(), KeyChannelName(), addonTable.Officers and addonTable.Officers.ChannelName()
            local which = (low == ChannelName():lower() and "public") or (keyName and low == keyName:lower() and "chat")
                or (offName and low == offName:lower() and "officers") or nil
            local actor = select(3, ...)
            -- 0.15.3: the game passes ownership and the moderator mark on by itself when the owner logs out, so
            -- those are information; mutes, kicks, bans and the moderated mode are errors
            local routine = arg1 == "OWNER_CHANGED" or arg1 == "SET_MODERATOR" or arg1 == "UNSET_MODERATOR" or arg1 == "CHANNEL_OWNER"
                -- 0.15.6: INVALID_NAME (Forever refusing a channel for a moment, on the chat and on the public one after
                -- login) is information; a refused chat channel is reported as a refusal
                or arg1 == "INVALID_NAME"
            if which == "chat" and arg1 == "INVALID_NAME" then NoteChatChannel("INVALID_NAME") end
            if which then addonTable.Monitor.Channel("Channel event (" .. which .. "): " .. tostring(arg1) .. " " .. tostring(arg2 or "")
                .. ((actor and actor ~= "") and (" by " .. tostring(actor)) or ""), not routine) end
        end
        return
    end
    if event == "CHAT_MSG_CHANNEL_NOTICE" then
        -- arg1 = notice type, 7th extra argument (arg9) = channel name without number
        local channelBaseName = select(7, ...)
        -- Every notice about our channels goes to the log (joins, leaves, wrong password, throttling...)
        if addonTable.Monitor and type(channelBaseName) == "string" then
            local low, keyName, offName = channelBaseName:lower(), KeyChannelName(), addonTable.Officers and addonTable.Officers.ChannelName()
            local which = (low == ChannelName():lower() and "public") or (keyName and low == keyName:lower() and "chat")
                or (offName and low == offName:lower() and "officers") or nil
            if which then addonTable.Monitor.Channel("Channel notice (" .. which .. "): " .. tostring(arg1)) end
        end
        if channelBaseName ~= nil and channelBaseName == KeyChannelName() then
            -- Refused or back on it (CREF reports, above)
            if arg1 == "NOT_ALLOWED_IN_CHANNEL" or arg1 == "WRONG_PASSWORD" or arg1 == "BANNED" then NoteChatChannel(arg1)
            elseif arg1 == "YOU_JOINED" or arg1 == "YOU_CHANGED" then NoteChatChannel(nil) end
            addonTable.Key.OnNotice(arg1)
            return
        end
        if channelBaseName ~= nil and addonTable.Officers and channelBaseName == addonTable.Officers.ChannelName() then addonTable.Officers.OnNotice(arg1) return end
        if channelBaseName ~= ChannelName() then return end
        if arg1 == "WRONG_PASSWORD" or arg1 == "BANNED" then
            -- Someone took over the channel (password) or banned us: we do not keep retrying, we just report it
            channelProblem = (arg1 == "BANNED") and "banned from the channel" or "the channel has a different password"
            Warn("Global channel unavailable: " .. channelProblem .. ". Report this to an officer.")
            if addonTable.Monitor then addonTable.Monitor.Channel("Public channel unavailable: " .. channelProblem, true) end
        elseif arg1 == "YOU_LEFT" and not channelProblem then
            -- Another addon (e.g. one tidying channels) removed us: we come back after a moment. Logged, so a
            -- channel that keeps dropping shows in Monitoring (Channel filter) with its time.
            if addonTable.Monitor then addonTable.Monitor.Channel("Left the public channel (by the game or another addon), joining again in 5 s") end
            C_Timer.After(5, Most.JoinChannel)
        elseif arg1 == "YOU_JOINED" or arg1 == "YOU_CHANGED" then
            channelProblem = nil
            if addonTable.Monitor then addonTable.Monitor.Channel("Joined the public channel") end
            -- The game may have added the channel to a chat window on join
            HideFromChat(channelBaseName)
        end
        return
    end
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        _G.JagodkiChatDB = _G.JagodkiChatDB or {}
        local saved = _G.JagodkiChatDB.log or {}
        chatLog = {}
        for _, e in ipairs(saved) do
            -- Copies of /g lines saved by older versions are dropped: they do not belong on the shared chat
            if e.src == "A" and e.id and not seenIds[e.id] then
                seenIds[e.id] = true
                table.insert(chatLog, e)
            end
        end
        TrimLog()
        _G.JagodkiChatDB.log = chatLog
    end
end)

C_Timer.NewTicker(0.2, PumpAddonQueue)
C_Timer.NewTicker(DISCOVER_INTERVAL, Most.Discover)

-- A new relay sends its status at once: other guilds know only the relays, so without it they would wait
-- up to a minute (the next regular status packet) before sending to us again
local wasRelay = false
C_Timer.NewTicker(RELAY_CHECK_INTERVAL, function()
    local isRelay = Most.IsRelay()
    if isRelay and not wasRelay and ctx and ctx.announce then
        if addonTable.Monitor then addonTable.Monitor.Relay("Became the relay, announcing to other guilds") end
        ctx.announce()
    end
    wasRelay = isRelay
end)
