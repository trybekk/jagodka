-- ============================================================================
-- BRIDGE: shared addon chat <-> guild chats (/g) of all listed guilds
-- ============================================================================
-- Rules:
--  * Every message has a unique ID, so the receiver drops duplicates.
--  * In each guild one person with the addon is the RELAY (the alphabetically first name
--    among online players with the addon). The relay carries /g <-> addon and links guilds:
--    it whispers GUILD packets to the relays of other guilds, who repost them to their GUILD.
--  * The relay posts messages from other guilds to its own /g (from a queue, one by one).
--  * A new player gets the history from someone online after logging in.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_ChatInfo = _G.C_ChatInfo
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local GetChannelName = _G.GetChannelName
local GetGuildInfo = _G.GetGuildInfo
local GetServerTime = _G.GetServerTime
local GetTime = _G.GetTime
local UnitName = _G.UnitName
local Ambiguate = _G.Ambiguate
local SendChatMessage = _G.SendChatMessage
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
local BRIDGED_TABS = { ["Ogolny"] = true } -- addon tabs linked to /g (Handel etc. stay in the addon)
local MAX_LOG = 300                   -- how many messages we keep (memory + SavedVariables)
local HISTORY_SYNC_MAX = 30           -- how many of the latest messages we send to a new player
local CONTENT_DEDUP_WINDOW = 15       -- window (s): the same /g line from two forwarders = one message
local BACKUP_MIN_DELAY, BACKUP_MAX_DELAY = 2, 5 -- the backup relay waits a random number of seconds in this range for the main one
local MAX_ADDON_BYTES = 225           -- addon packet limit is 255 bytes, this leaves room for the "FW:name:" header
local DISCOVER_INTERVAL, HELLO_RETRY = 30, 120 -- how often the relay reads the channel list and repeats a greeting (s)
local RELAY_READY_DELAY = 5           -- after login we wait for answers from others before treating ourselves as relay
local MAX_GUILD_LINE_BYTES = 250      -- /g line limit is 255 bytes

local Most = {}
addonTable.Most = Most
Most.ONLINE_TIMEOUT = ONLINE_TIMEOUT

-- Context from core.lua: activePlayers, isGuildAllowed, onChatChanged, sendHello
local ctx = nil
function Most.Init(c) ctx = c end

-- Check against the guild roster whether a guildmate is online (true/false, nil = unknown).
-- Lets us exclude a logged-out relay at once, without waiting for ONLINE_TIMEOUT.
local guildmateOnlineCheck = nil
function Most.SetGuildmateOnlineCheck(fn) guildmateOnlineCheck = fn end

local channelProblem = nil -- description of a global channel problem (foreign password / ban), shown in the status

local function MyName() return UnitName("player") end
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
-- FIELD ENCODING (":" is the packet separator)
-- ============================================================================
function Most.EncodeField(s)
    return (tostring(s or ""):gsub("%%", "%%25"):gsub(":", "%%3A"):gsub("\n", "%%0A"))
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

-- Chat message text: only valid links remain (items, spells, professions...),
-- every other "|" is removed
local LINK_PATTERN = "|c%x%x%x%x%x%x%x%x|H[^|]+|h%[[^|]*%]|h|r"
function Most.SanitizeChat(text)
    local out, pos = {}, 1
    while true do
        local s, e = text:find(LINK_PATTERN, pos)
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

function Most.JoinChannel()
    -- The old temporary channel (up to 0.7.6) is no longer useful, so we leave it
    if (GetChannelName(OLD_COMM_CHANNEL) or 0) > 0 and _G.LeaveChannelByName then _G.LeaveChannelByName(OLD_COMM_CHANNEL) end
    local name = ChannelName()
    if not Most.GetChannelId() then _G.JoinChannelByName(name, COMM_PASSWORD) end
    HideFromChat(name)
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
local guildLineQueue = {}           -- lines to post to /g (relay only)
local postedLines = {}              -- lines we posted to /g -> time (loop protection)
local tokens, MAX_TOKENS, TOKENS_PER_SEC = 10, 10, 1
local whisperedAt = {}              -- name -> time of the last addon whisper (to recognize "player offline")

function Most.Send(pType, payload, priority)
    local item = { msg = pType .. ":" .. payload, tries = 0, queued = GetTime() }
    table.insert(priority == "low" and lowQueue or highQueue, item)
end

function Most.Whisper(target, pType, payload, priority)
    table.insert(priority == "high" and highQueue or lowQueue, { msg = pType .. ":" .. payload, target = target, tries = 0, queued = GetTime() })
end

-- Older API returns a bool, newer a code from Enum.SendAddonMessageResult (0 = success)
local function IsOk(result) return result == nil or result == true or result == 0 end
-- Temporary limit (3 = AddonMessageThrottle, 8 = ChannelThrottle; false = older API): worth retrying.
-- Other codes (e.g. 4 = InvalidChatType) are permanent: retrying would only block the queue.
local function IsThrottle(result) return result == false or result == 3 or result == 8 end

-- Returns the API result and the channel kind (for diagnostics)
local function SendRaw(item)
    if item.target then
        whisperedAt[item.target] = GetTime()
        return C_ChatInfo.SendAddonMessage(PREFIX, item.msg, "WHISPER", item.target), "WHISPER"
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

local function PumpGuildLines()
    local line = table.remove(guildLineQueue, 1)
    if not line then return end
    postedLines[line] = GetTime()
    SendChatMessage(line, "GUILD")
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

local function SplitText(text, maxBytes)
    if #text <= maxBytes then return { text } end
    -- Tokens: a colored link as a whole, the rest of the text by words
    local parts = {}
    local pos = 1
    while pos <= #text do
        local s, e = text:find("|c%x%x%x%x%x%x%x%x|H.-|h.-|h|r", pos)
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
local chatLog = {}       -- { id, ts, guild, author, tab, src ("G" from /g, "A" from the addon, "S" system), text }
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
    ["Jagódki Nadina III"] = "JN3",
    ["Jagódki Nadina IV"] = "JN4",
    ["Testowo"] = "TEST",
}
local TAG_GUILDS = {}
for guild, tag in pairs(GUILD_TAGS) do TAG_GUILDS[tag] = guild end

-- "[JN]" with a gray bracket and a muted purple tag
local function GuildLabel(guild)
    return "|cff808080[|r|cff9d7fc0" .. (GUILD_TAGS[guild] or guild) .. "|r|cff808080]|r"
end

-- "[60] Name" with a gray level and the name in the class color, as a player link (click = whisper,
-- right click = menu). level: the level from a /g line; without it the known level, and without that no brackets.
local function AuthorLabel(name, level)
    local class, knownLevel = AuthorInfo(name)
    level = level or knownLevel
    local color = class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
    local label = color and color:WrapTextInColorCode(name) or name
    if level then label = "|cff808080[" .. level .. "]|r " .. label end
    return "|Hplayer:" .. name .. "|h" .. label .. "|h"
end

-- "[JN] [60] Name: text"; addon window: "21:05 [JN] [60] Name: text" (showTime)
-- textColor: text color, e.g. "ff3cb43c" (the color is restored after item links)
function Most.FormatEntry(e, textColor, showTime)
    if e.src == "S" then return "|cff00ccff[System]: " .. e.text .. "|r" end
    local text = e.text
    if textColor then text = "|c" .. textColor .. text:gsub("|r", "|r|c" .. textColor) .. "|r" end
    local time = showTime and ("|cff808080" .. date("%H:%M", e.ts) .. "|r ") or ""
    return string.format("%s%s %s: %s", time, GuildLabel(e.guild), AuthorLabel(e.author), text)
end

-- Listeners for new messages (e.g. the tab in Blizzard chat): fn(entry, live)
local entryListeners = {}
function Most.OnNewEntry(fn) table.insert(entryListeners, fn) end

-- ============================================================================
-- RELAY: one person with the addon per guild carries messages /g <-> addon
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
-- Without this delay a fresh login knows nobody yet, treats itself as relay and duplicates lines in /g.
local relayReadyAt = math.huge
local function CanForward()
    if not ctx or GetTime() < relayReadyAt or not IsInGuild() then return false end
    return ctx.isGuildAllowed(MyGuild())
end

function Most.IsRelay()
    return CanForward() and Most.GetRelayName() == MyName()
end

local function BridgePrefix(guild, author, level)
    return "[" .. (GUILD_TAGS[guild] or guild) .. "] " .. (level and ("[" .. level .. "] ") or "") .. author .. ": "
end

-- A /g line posted by the bridge: guild, author, level (nil when absent), text.
-- The last pattern is the format of versions before 0.8.5.
local function ParseBridgeLine(text)
    local guild, level, author, body = text:match("^%[(.-)%] %[(%d+)%] ([^%s:]+): (.*)$")
    if not guild then guild, author, body = text:match("^%[(.-)%] ([^%s:]+): (.*)$") end
    return TAG_GUILDS[guild] or guild, author, tonumber(level), body
end

-- Message from the shared chat -> /g of my guild (relay only, bridged tabs only)
local function BridgeToGuild(e)
    if not BRIDGED_TABS[e.tab] or not Most.IsRelay() then return end
    -- A message from /g of my guild is already there
    if e.src == "G" and e.guild == MyGuild() then return end
    local _, level = AuthorInfo(e.author)
    local line = BridgePrefix(e.guild, e.author, level) .. e.text
    if #line > 255 then line = Utf8Cut(line, 255) end
    table.insert(guildLineQueue, line)
    if addonTable.Monitor then addonTable.Monitor.Relay("Queued for my /g: line from " .. e.author .. " (" .. tostring(e.guild) .. ")") end
end

-- Whether a /g line was posted by the bridge (rather than written by a player)
local function IsBridgeLine(text, author)
    if author == MyName() and postedLines[text] then return true end
    local tagGuild = text:match("^%[(.-)%] [^:]+: ")
    return tagGuild ~= nil and ctx ~= nil and ctx.isGuildAllowed(TAG_GUILDS[tagGuild] or tagGuild)
end

-- ============================================================================
-- RECEIVING MESSAGES (deduplication by ID)
-- ============================================================================
-- Whether the log already has the same /g line (guild + author + text) from around the same time.
-- Catches duplicates when the relay and a backup relay forwarded the same line (different ID, same text).
local function HasRecentGuildLine(guild, author, text, ts)
    for i = #chatLog, math.max(1, #chatLog - 60), -1 do
        local e = chatLog[i]
        if e.src == "G" and e.guild == guild and e.author == author and e.text == text and math.abs((e.ts or 0) - ts) <= CONTENT_DEDUP_WINDOW then
            return true
        end
    end
    return false
end

local function Ingest(e, live)
    if seenIds[e.id] then return false end
    -- Muted player (mute.lua): their messages reach neither the log nor /g of other guilds
    if addonTable.Mute and addonTable.Mute.IsMuted(e.author) then return false end
    seenIds[e.id] = true
    -- Applies to current messages and history, so a duplicate does not return through sync either
    if e.src == "G" and HasRecentGuildLine(e.guild, e.author, e.text, e.ts) then return false end
    -- Always by time written, so a late message (e.g. from a backup relay) lands in its proper place
    InsertByTime(e)
    TrimLog()
    -- History never goes to /g again, only current messages do
    if live then BridgeToGuild(e) end
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

-- Splits the text into parts. Does not depend on the sender's name (fixed header length),
-- so the relay and backup relay split a line identically, which matters for detecting duplicates.
local function SplitForPublish(text, guild, author, tab, src)
    local header = string.format("GMSG:%s.ffffffff.ffff:%d:%s:%s:%s:%s:", string.rep("x", 24), 2000000000, Enc(guild), Enc(author), Enc(tab), src)
    local maxText = math.min(MAX_ADDON_BYTES - #header, MAX_GUILD_LINE_BYTES - #BridgePrefix(guild, author, 60))
    return SplitText(text, maxText)
end

-- Publishes a new message to the shared chat (from the addon or from /g through the relay)
function Most.Publish(tab, text, src, author, guild, ts)
    if not text or text == "" or not guild then return end
    -- Time must be a number (log sorting); anything else = now
    ts = tonumber(ts) or GetServerTime()
    for _, part in ipairs(SplitForPublish(text, guild, author, tab, src)) do
        local e = { id = NewMessageId(), ts = ts, guild = guild, author = author, tab = tab, src = src, text = part }
        -- If the same line is already in the log (someone else forwarded it), we do not send it again
        if Ingest(e, true) then Most.Send("GMSG", EncodeMessage(e), "high") end
    end
end

local function IsKnownAllowedSender(name)
    if not ctx then return nil end
    for _, p in ipairs(ctx.activePlayers) do
        if p.name == name and ctx.isGuildAllowed(p.guild) then return p end
    end
    return nil
end

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

local function HandleHistoryRequest(sender, rawSender, since)
    since = tonumber(since) or 0
    local list = {}
    for _, e in ipairs(chatLog) do
        if e.src ~= "S" and e.ts > since then table.insert(list, e) end
    end
    if #list == 0 then return end
    while #list > HISTORY_SYNC_MAX do table.remove(list, 1) end
    pendingHistory[sender] = true
    -- Random delay: one person answers, the others see HCLAIM and give up
    C_Timer.After(0.5 + math.random() * 2, function()
        if not pendingHistory[sender] then return end
        pendingHistory[sender] = nil
        Most.Send("HCLAIM", sender, "high")
        for _, e in ipairs(list) do Most.Whisper(rawSender, "HIST", EncodeMessage(e)) end
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
        if pType == "GMSG" then
            -- From the addon only the author writes; from /g only someone from the same guild forwards
            if e.src == "A" and e.author ~= senderName then Count(debug.rejected, "author ~= sender") return true end
            if senderInfo and senderInfo.guild ~= e.guild then Count(debug.rejected, "sender guild mismatch") return true end
            -- Sender still unknown (their status packet has not arrived): we do NOT lose the message.
            -- We trust it as much as a status packet: it names a listed guild; if it claims to be
            -- from my guild, the sender must be in the roster.
            if not senderInfo and senderName ~= MyName() and e.guild == MyGuild()
                and guildmateOnlineCheck ~= nil and guildmateOnlineCheck(senderName) == false then
                Count(debug.rejected, "not in guild roster")
                return true
            end
        elseif not senderInfo and senderName ~= MyName() then
            -- History is accepted only from a known player (who answered our status packet)
            Count(debug.rejected, "history from unknown")
            return true
        end
        -- Our own messages come back from GUILD and also end up here
        if not Ingest(e, pType == "GMSG") then Count(debug.rejected, "duplicate / own echo / muted") end
        return true
    elseif pType == "HREQ" then
        if senderName ~= MyName() and IsKnownAllowedSender(senderName) then
            HandleHistoryRequest(senderName, rawSender, payload)
        end
        return true
    elseif pType == "HCLAIM" then
        if senderName ~= MyName() then pendingHistory[payload] = nil end
        return true
    end
    return false
end

-- ============================================================================
-- LINKS BETWEEN GUILDS: guild relay <-> relays of other guilds (addon whisper)
-- ============================================================================
-- The relay wraps a GUILD packet as "FW:sender:packet" and whispers it to relays of other guilds.
-- The receiver reposts it unchanged to its own GUILD. Nobody forwards wrapped packets again.
local function ForwardPriority(text)
    return text:sub(1, 5) == "GMSG:" and "high" or "low"
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

local function ForwardToOtherGuilds(origin, text)
    local payload = origin .. ":" .. text
    if #payload + #"FW:" > 255 then Count(debug.rejected, "too long to forward") return end
    for _, relay in pairs(OtherGuildRelays()) do
        Most.Whisper(relay, "FW", payload, ForwardPriority(text))
    end
end

-- Called for every packet before it is handled. Returns the content, channel kind and real
-- sender, or nil when the packet should not be handled.
function Most.Route(text, channel, senderName)
    local pType, rest = strsplit(":", text, 2)
    if pType ~= "FW" then
        -- Our own packets too: the game echoes them from GUILD, so there is one path for everyone
        if channel == "GUILD" and Most.IsRelay() then ForwardToOtherGuilds(senderName, text) end
        -- Our own echo was already logged when sent
        if senderName ~= MyName() and addonTable.Monitor then addonTable.Monitor.RX(text, channel, senderName) end
        return text, channel, senderName
    end
    -- Our own packet reposted to GUILD: we already handled it when the whisper arrived
    if senderName == MyName() then return nil end
    local origin, inner = strsplit(":", rest or "", 2)
    origin = Most.Plain(origin)
    if not origin or origin == "" or not inner or origin == MyName() then return nil end
    if channel == "WHISPER" then
        -- Only a known player from a listed guild may speak for others; anyone may speak for themselves (greeting)
        if origin ~= senderName and not IsKnownAllowedSender(senderName) then
            Count(debug.rejected, "forward from unknown")
            return nil
        end
        table.insert(ForwardPriority(inner) == "high" and highQueue or lowQueue, { msg = text, tries = 0, queued = GetTime() })
    elseif channel ~= "GUILD" then
        return nil
    end
    if addonTable.Monitor then addonTable.Monitor.RX(inner, "FW", origin, senderName, channel) end
    return inner, "FW", origin
end

-- Finding other guilds: the relay reads the channel member list and greets unknown players.
-- The greeted player reposts the PING to their guild, and its relay then knows us and forwards packets.
local listAskedAt, helloAt, channelMembers = 0, {}, {}

function Most.HasLinkedGuilds()
    return ctx ~= nil and _G.next(OtherGuildRelays()) ~= nil
end

function Most.Discover()
    if not _G.ListChannelByName or not Most.GetChannelId() or not Most.IsRelay() then return end
    listAskedAt = GetTime()
    wipe(channelMembers)
    _G.ListChannelByName(ChannelName())
end

-- For the Monitoring tab, also when we are not the relay; the answer stays out of the chat
function Most.RefreshChannelList()
    if not _G.ListChannelByName or not Most.GetChannelId() then return end
    listAskedAt = GetTime()
    wipe(channelMembers)
    _G.ListChannelByName(ChannelName())
end

local function IsActivePlayer(name)
    for _, p in ipairs(ctx.activePlayers) do
        if p.name == name then return true end
    end
    return false
end

local function HandleChannelList(list)
    if not ctx then return end
    local now, isRelay = GetTime(), Most.IsRelay()
    for raw in tostring(list or ""):gmatch("[^,]+") do
        -- On the list the owner has "*" and a moderator "@"
        local name = Ambiguate((raw:gsub("[%s%*@%+]", "")), "none")
        if name ~= "" then channelMembers[name] = true end
        local isGuildmate = guildmateOnlineCheck ~= nil and guildmateOnlineCheck(name) == true
        if isRelay and name ~= "" and name ~= MyName() and not isGuildmate and not IsActivePlayer(name)
            and now - (helloAt[name] or -HELLO_RETRY) >= HELLO_RETRY and ctx.sendHello then
            helloAt[name] = now
            if addonTable.Monitor then addonTable.Monitor.Relay("On the channel but unknown, greeting " .. name) end
            ctx.sendHello(name)
        end
    end
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
    if not name or GetTime() - (whisperedAt[name] or -10) >= 10 then return false end
    RemoveActivePlayer(name)
    if addonTable.Monitor then addonTable.Monitor.Relay("Whisper to " .. name .. " failed: player offline, removed from the list") end
    return true
end

if _G.ChatFrame_AddMessageEventFilter then
    _G.ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_LIST", function(_, _, ...)
        if select(9, ...) == ChannelName() and GetTime() - listAskedAt < 2 then return true end
    end)
    _G.ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, message)
        if HandlePlayerNotFound(message) then return true end
    end)
    -- A bridged /g line without the relay's name: the game adds that name outside the text, so we
    -- hide the original and print our own. Only from a known addon user: a line typed by hand to look
    -- like this from someone without the addon keeps its real sender, so nobody can fake another author.
    _G.ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", function(frame, _, message, sender)
        if not ctx then return end
        local guild, author, level, text = ParseBridgeLine(message)
        if not guild or not ctx.isGuildAllowed(guild) or not IsKnownAllowedSender(Ambiguate(sender or "", "none")) then return end
        -- The game's own "[Guild]" label (localized, clickable), in the guild chat color passed below
        local label = _G.CHAT_GUILD_GET and _G.CHAT_GUILD_GET:match("^(.-)%s*%%s") or "[Guild]"
        local line = label .. " " .. GuildLabel(guild) .. " " .. AuthorLabel(author, level) .. ": " .. text
        -- The game's own timestamps (Interface options) are added only to messages it prints itself
        local stamp = _G.GetCVar("showTimestamps")
        if stamp and stamp ~= "none" and _G.BetterDate then line = _G.BetterDate(stamp, _G.time()) .. line end
        local info = _G.ChatTypeInfo and _G.ChatTypeInfo.GUILD
        frame:AddMessage(line, info and info.r, info and info.g, info and info.b)
        return true
    end)
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
    for name in pairs(channelMembers) do table.insert(members, name) end
    table.sort(members)
    return {
        channelId = Most.GetChannelId(), channelName = ChannelName(), channelProblem = channelProblem, channelMembers = members,
        relay = Most.GetRelayName(), isRelay = Most.IsRelay(), linked = linked, rejected = debug.rejected,
        queueHigh = #highQueue, queueLow = #lowQueue, queueGuild = #guildLineQueue, history = #chatLog,
        queueOldest = (highQueue[1] or lowQueue[1]) and GetTime() - (highQueue[1] or lowQueue[1]).queued or nil,
        relayReadyIn = (relayReadyAt ~= math.huge and GetTime() < relayReadyAt) and relayReadyAt - GetTime() or nil,
        greeted = helloAt, helloRetry = HELLO_RETRY, listAskedAt = (listAskedAt > 0) and listAskedAt or nil,
    }
end

-- ============================================================================
-- EVENTS: loading history, capturing /g, cleanup
-- ============================================================================
local function Warn(text)
    if _G.DEFAULT_CHAT_FRAME then _G.DEFAULT_CHAT_FRAME:AddMessage("|cffbf40ff[Jagodka]|r |cffff5555" .. text .. "|r") end
end

local Listener = CreateFrame("Frame")
Listener:RegisterEvent("ADDON_LOADED")
Listener:RegisterEvent("CHAT_MSG_GUILD")
Listener:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
Listener:RegisterEvent("CHAT_MSG_CHANNEL_LIST")
Listener:RegisterEvent("CHAT_MSG_SYSTEM")
Listener:RegisterEvent("PLAYER_LOGIN")
Listener:SetScript("OnEvent", function(self, event, arg1, arg2, ...)
    if event == "PLAYER_LOGIN" then
        relayReadyAt = GetTime() + RELAY_READY_DELAY
        return
    end
    if event == "CHAT_MSG_SYSTEM" then
        -- "X has gone offline": a logged-out player (e.g. switching characters) loses the relay role at once
        local name = NameFromSystemMessage(_G.ERR_FRIEND_OFFLINE_S, arg1 or "")
        if name and ctx then RemoveActivePlayer(Ambiguate(name, "none")) end
        return
    end
    if event == "CHAT_MSG_CHANNEL_LIST" then
        if select(7, ...) == ChannelName() then HandleChannelList(arg1) end
        return
    end
    if event == "CHAT_MSG_CHANNEL_NOTICE" then
        -- arg1 = notice type, 7th extra argument (arg9) = channel name without number
        local channelBaseName = select(7, ...)
        if channelBaseName ~= ChannelName() then return end
        if arg1 == "WRONG_PASSWORD" or arg1 == "BANNED" then
            -- Someone took over the channel (password) or banned us: we do not keep retrying, we just report it
            channelProblem = (arg1 == "BANNED") and "banned from the channel" or "the channel has a different password"
            Warn("Global channel unavailable: " .. channelProblem .. ". Report this to an officer.")
            if addonTable.Monitor then addonTable.Monitor.Error("Global channel unavailable: " .. channelProblem) end
        elseif arg1 == "YOU_LEFT" and not channelProblem then
            -- Another addon (e.g. one tidying channels) removed us: we come back after a moment
            C_Timer.After(5, Most.JoinChannel)
        elseif arg1 == "YOU_JOINED" or arg1 == "YOU_CHANGED" then
            channelProblem = nil
            if addonTable.Monitor then addonTable.Monitor.Note("Joined the global channel") end
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
            if e.src ~= "S" and e.id and not seenIds[e.id] then
                seenIds[e.id] = true
                table.insert(chatLog, e)
            end
        end
        TrimLog()
        _G.JagodkiChatDB.log = chatLog
    elseif event == "CHAT_MSG_GUILD" then
        local text, author = arg1, Ambiguate(arg2 or "", "none")
        if IsBridgeLine(text, author) then
            -- Another relay already posted this line -> we do not post it again
            if author ~= MyName() then
                for i = #guildLineQueue, 1, -1 do
                    if guildLineQueue[i] == text then
                        table.remove(guildLineQueue, i)
                        if addonTable.Monitor then addonTable.Monitor.Relay(author .. " already posted this /g line, ours dropped") end
                    end
                end
            end
            return
        end
        if Most.IsRelay() then
            if addonTable.Monitor then addonTable.Monitor.Relay("Publishing a /g line from " .. author .. " (you are the relay)") end
            Most.Publish("Ogolny", text, "G", author, MyGuild())
        elseif CanForward() then
            -- BACKUP RELAY: if the main relay does not forward this line within a few seconds
            -- (it logged out, has not finished logging in, etc.), we forward it ourselves.
            -- Whoever is first sends it; the others see the line in the log and give up.
            local guild, ts = MyGuild(), GetServerTime()
            local firstPart = SplitForPublish(text, guild, author, "Ogolny", "G")[1]
            C_Timer.After(BACKUP_MIN_DELAY + math.random() * (BACKUP_MAX_DELAY - BACKUP_MIN_DELAY), function()
                if CanForward() and not HasRecentGuildLine(guild, author, firstPart, ts) then
                    if addonTable.Monitor then addonTable.Monitor.Relay("Backup relay: the main relay did not publish a /g line from " .. author .. ", publishing it") end
                    Most.Publish("Ogolny", text, "G", author, guild, ts)
                end
            end)
        end
    end
end)

C_Timer.NewTicker(0.2, PumpAddonQueue)
C_Timer.NewTicker(0.8, PumpGuildLines)
C_Timer.NewTicker(DISCOVER_INTERVAL, Most.Discover)
C_Timer.NewTicker(10, function()
    local now = GetTime()
    for k, t in pairs(postedLines) do
        if now - t > 60 then postedLines[k] = nil end
    end
end)
