-- ============================================================================
-- LFG: looking for group across all our guilds (the LFG tab, after Calendar)
-- ============================================================================
--  * Everyone with the addon can list themselves: roles (those of their class), up to MAX_ACTIVITIES
--    activities (dungeons, raids, PvP from instances.lua, questing in a zone, or anything) and a short note.
--    One listing per player; it lasts LISTING_FOR, can be renewed, and is removed by hand.
--  * The tab: a table as in Roster and Events (pages, search, filters by activity type and role, sorting),
--    the activities shown compactly (the first one + "+N", all of them on hover), right click = the usual
--    player menu (whisper, invite), Shift + click = whisper.
--  * Sync (from 0.15.0): my listing is one LF packet to GUILD (the relays pass it on, high priority), its
--    removal LX; after login and with the Sync button an LQ request inside the own guild, answered by one
--    guildmate (never the relay when anyone else can, LC claim) with the current listings by whisper, low
--    priority, at most every ANSWER_COOLDOWN per asker. A live packet must come from the player it names.
--  * Cleanup: a listing goes after LISTING_FOR (3 h), at once when its player is offline by the guild rosters
--    (or is one of my own other characters), or when not heard of for STALE_AFTER: every listed player sends
--    theirs again every HEARTBEAT (one small packet), so a player who left without anyone reporting it goes
--    within 40 minutes. Offline by the rosters: the listing stays, grayed, for OFFLINE_GRACE (10 min: a relog or
--    a reload), and goes only when they are not back by then. My listing is kept per character over /reload.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local CreateFrame = _G.CreateFrame
local GetTime, GetServerTime = _G.GetTime, _G.GetServerTime
local ipairs, pairs, tostring, tonumber, type = _G.ipairs, _G.pairs, _G.tostring, _G.tonumber, _G.type
local table, math, string = _G.table, _G.math, _G.string

local LFG = {}
addonTable.LFG = LFG

local LISTING_FOR = 3 * 3600     -- a listing lasts this long unless renewed (s)
local HEARTBEAT = 600            -- my listing is sent again this often while it is on (s)
local STALE_AFTER = 2400         -- a listing not heard of for this long goes (its player is gone) (s); 40 min, as
                                 -- relays on older versions held the 10-minute signals of other guilds back (0.15.0 log)
local removedAt = {}             -- name -> time of their listing they removed (LX): an older copy never comes back
local OFFLINE_GRACE = 600        -- a player offline by the rosters keeps the listing this long (a relog, a reload) (s)
local MAX_ACTIVITIES = 4
local NOTE_MAX = 60
local PER_PAGE = 50
local ROW_H = 22

-- Activity types: key, label, color, the instances.lua groups that belong to it
local TYPES = {
    { key = "dungeon", label = "Dungeon", short = "D", color = "6cc4e6", groups = { ["Dungeons"] = true, ["New dungeons (Forever)"] = true } },
    { key = "raid", label = "Raid", short = "R", color = "d58cff", groups = { ["Raids"] = true } },
    { key = "pvp", label = "PvP", short = "P", color = "ff6060", groups = { ["PvP"] = true } },
    { key = "quest", label = "Questing", short = "Q", color = "ffd100" },
    { key = "other", label = "Anything", short = "A", color = "c0c0c0" },
}
local TYPE_BY_KEY = {}
for _, t in ipairs(TYPES) do TYPE_BY_KEY[t.key] = t end
local ROLE_ICON = { TANK = "|A:UI-LFG-RoleIcon-Tank:14:14|a", HEAL = "|A:UI-LFG-RoleIcon-Healer:14:14|a", DPS = "|A:UI-LFG-RoleIcon-DPS:14:14|a" }
local ROLE_ORDER = { "TANK", "HEAL", "DPS" }

-- Context from core.lua: applyStyle, classRoles (class -> roles it can play), onRowClick (the Roster menu)
local ctx = nil
local listings = {}   -- { name, class, level, guild, roles = { TANK = true }, acts = { { t, n } }, note, ts }
local mine = nil      -- my listing (also in listings)

-- ============================================================================
-- DATA
-- ============================================================================
local function All()
    local list = {}
    for _, l in ipairs(listings) do table.insert(list, l) end
    return list
end
-- Old listings go (also mine), and those of players offline by the guild rosters (or my own other characters,
-- the account plays one at a time); checked every minute and before drawing
local function Prune()
    local now, Roster = GetServerTime(), addonTable.Roster
    for i = #listings, 1, -1 do
        local l = listings[i]
        local gone = now - (l.ts or 0) > LISTING_FOR
        if not gone and l ~= mine then
            -- Offline by the rosters: shown grayed for OFFLINE_GRACE (a relog or a reload), then gone; back online
            -- or a new packet from them ends it
            if Roster and Roster.IsOnline(l.name, l.guild) == false then l.offlineSince = l.offlineSince or GetTime()
            else l.offlineSince = nil end
            -- Not heard of for STALE_AFTER: the player is gone even when nobody of their guild reported it
            gone = GetTime() - (l.seen or 0) > STALE_AFTER
                or (l.offlineSince ~= nil and GetTime() - l.offlineSince > OFFLINE_GRACE)
                or (Roster and Roster.IsMyOtherCharacter(l.name))
        end
        if gone then
            if l == mine then mine = nil end
            table.remove(listings, i)
            if addonTable.Monitor then
                local why = (now - (l.ts or 0) > LISTING_FOR) and "3 h passed" or (l.offlineSince and "offline 10 min")
                    or (GetTime() - (l.seen or 0) > STALE_AFTER and "not heard of for 40 min") or "my other character"
                addonTable.Monitor.Note("LFG: " .. tostring(l.name) .. " removed (" .. why .. ")")
            end
        end
    end
end

local function TypeOfInstance(name)
    for _, group in ipairs(addonTable.InstanceGroups and addonTable.InstanceGroups() or {}) do
        for _, inst in ipairs(group.list) do
            if inst.name == name then
                for _, t in ipairs(TYPES) do if t.groups and t.groups[group.group] then return t.key end end
            end
        end
    end
    return "other"
end

local function ActLabel(a, withColor)
    local t = TYPE_BY_KEY[a.t] or TYPE_BY_KEY.other
    local text = (a.t == "quest") and ("Questing: " .. tostring(a.n)) or tostring(a.n)
    return withColor and ("|cff" .. t.color .. text .. "|r") or text
end

local function RolesText(roles)
    local out = {}
    for _, role in ipairs(ROLE_ORDER) do if roles and roles[role] then table.insert(out, ROLE_ICON[role]) end end
    return table.concat(out, "")
end

local function Ago(ts)
    local m = math.max(0, math.floor((GetServerTime() - (ts or 0)) / 60))
    if m < 60 then return m .. " min" end
    return math.floor(m / 60) .. " h " .. (m % 60) .. " min"
end

-- ============================================================================
-- SYNC
-- ============================================================================
local ANSWER_COOLDOWN = 120      -- the same asker gets our answer at most this often (s)
local REQUEST_COOLDOWN = 60      -- our own requests (Sync button) at most this often (s)
local MAX_PAYLOAD = 195          -- under the packet limit with room for the relay's header
local TYPE_CODE = { dungeon = "D", raid = "R", pvp = "P", quest = "Q", other = "A" }
local CODE_TYPE = {}
for k, v in pairs(TYPE_CODE) do CODE_TYPE[v] = k end
local ROLE_CODE = { TANK = "T", HEAL = "H", DPS = "D" }
local pendingAnswer, answeredAt, lastRequest = {}, {}, -REQUEST_COOLDOWN
LFG.REQUEST_COOLDOWN = REQUEST_COOLDOWN

local function Most() return addonTable.Most end
-- The table redraws itself (only while the tab is open)
local function Changed()
    if LFG.Render then LFG.Render() end
    if LFG.SideRender then LFG.SideRender() end
end

-- LF: name:ts:class:level:roles:acts:note. Activities "<type letter><name>" joined by ";"; a too long note is
-- shortened, then the last activities dropped, so it always fits one packet.
local function Encode(l)
    local Enc = Most().EncodeField
    local roles = {}
    for _, role in ipairs(ROLE_ORDER) do if l.roles[role] then table.insert(roles, ROLE_CODE[role]) end end
    local acts = {}
    for _, a in ipairs(l.acts) do table.insert(acts, (TYPE_CODE[a.t] or "A") .. Enc(a.n)) end
    local note = l.note or ""
    local function Build()
        return table.concat({ Enc(l.name), tostring(l.ts), Enc(l.class or ""), tostring(l.level or 0), table.concat(roles), table.concat(acts, ";"), Enc(note) }, ":")
    end
    local payload = Build()
    while #payload > MAX_PAYLOAD and #note > 0 do note = note:sub(1, -2):gsub("[\192-\255][\128-\191]*$", "") payload = Build() end
    while #payload > MAX_PAYLOAD and #acts > 1 do table.remove(acts) payload = Build() end
    return payload
end

local function Decode(payload)
    local Dec, Plain = Most().DecodeField, Most().Plain
    local name, ts, class, level, roles, acts, note = _G.strsplit(":", payload, 7)
    name, ts = Plain(Dec(name) or ""), tonumber(ts)
    if not name or name == "" or not ts or not roles or not acts then return nil end
    local l = { name = name, ts = ts, class = Plain(Dec(class) or ""), level = tonumber(level), roles = {}, acts = {}, note = Plain(Dec(note) or "") }
    for code in roles:gmatch("[THD]") do
        for role, c in pairs(ROLE_CODE) do if c == code then l.roles[role] = true end end
    end
    for item in acts:gmatch("[^;]+") do
        local t = CODE_TYPE[item:sub(1, 1)]
        local n = Plain(Dec(item:sub(2)) or "")
        if t and n ~= "" and #l.acts < MAX_ACTIVITIES then table.insert(l.acts, { t = t, n = n }) end
    end
    if #l.acts == 0 then return nil end
    if #l.note > NOTE_MAX * 2 then l.note = l.note:sub(1, NOTE_MAX * 2) end
    return l
end

local function InGuild() local M = Most() return M.IsGuildAllowed(M.MyGuild()) end

local function SendMine(target)
    if not mine or not InGuild() then return end
    if target then Most().Whisper(target, "LF", Encode(mine), "low") else Most().Send("LF", Encode(mine), "high") end
end

local function SaveMineToDB()
    -- In the account's data under my name (settings.lua, 0.15.4), not the character's folder
    addonTable.Settings.CharStore().lfg = mine and { roles = mine.roles, acts = mine.acts, note = mine.note, ts = mine.ts } or nil
end

-- Request after login and with the Sync button (own guild only; bridge.lua keeps LQ in the guild)
function LFG.Request(force)
    if not force and GetTime() - lastRequest < REQUEST_COOLDOWN then return end
    lastRequest = GetTime()
    if not InGuild() then return end
    Most().Send("LQ", "1", "high")
    -- The sync bar's LFG stage: done when the answer stops coming (or nobody answers: no listings)
    if addonTable.Sync then addonTable.Sync.Start("lfg") end
end

local function Answer(asker)
    answeredAt[asker] = GetTime()
    local sent = 0
    for _, l in ipairs(listings) do
        if l.name ~= asker then Most().Whisper(asker, "LF", Encode(l), "low") sent = sent + 1 end
    end
    -- Recent removals too, so an asker who got an older copy elsewhere drops it
    local now = GetServerTime()
    for name, ts in pairs(removedAt) do
        if now - ts < LISTING_FOR and name ~= asker then Most().Whisper(asker, "LX", Most().EncodeField(name) .. ":" .. ts, "low") sent = sent + 1 end
    end
    if addonTable.Monitor then addonTable.Monitor.Note("LFG: answered " .. asker .. " with " .. sent .. " listings") end
end

-- Packets from known players of listed guilds (core.lua); true when it was an LFG packet
function LFG.HandlePacket(pType, payload, senderName, channel)
    if pType ~= "LF" and pType ~= "LX" and pType ~= "LQ" and pType ~= "LC" then return false end
    local M = Most()
    local me = M.MyName()
    if pType == "LQ" then
        if senderName == me or pendingAnswer[senderName] or #listings == 0 then return true end
        if GetTime() - (answeredAt[senderName] or -ANSWER_COOLDOWN) < ANSWER_COOLDOWN or not M.ShouldAnswer("0.15.0") then return true end
        M.ClaimAndAnswer(pendingAnswer, senderName, 0.5 + math.random() * 2, function() M.Send("LC", M.EncodeField(senderName), "high") end,
            function() Answer(senderName) end)
        return true
    elseif pType == "LC" then
        if addonTable.Sync then addonTable.Sync.Activity("lfg") end
        local asker = M.DecodeField(payload)
        if senderName ~= me and asker then M.ClaimSeen(pendingAnswer, asker, senderName) end
        return true
    end
    if senderName == me then return true end
    local live = channel ~= "WHISPER"
    if not live and addonTable.Sync then addonTable.Sync.Activity("lfg") end
    if pType == "LX" then
        local name, ts = _G.strsplit(":", payload, 2)
        name, ts = M.Plain(M.DecodeField(name) or ""), tonumber(ts) or 0
        if live and senderName ~= name then return true end
        -- Remembered, so a guildmate's older copy (a sync answer) does not bring it back (0.15.0 log)
        if ts > (removedAt[name] or 0) then removedAt[name] = ts end
        for i, l in ipairs(listings) do
            if l.name == name and l ~= mine and (l.ts or 0) <= ts then table.remove(listings, i) break end
        end
        Changed()
        return true
    end
    -- LF
    local l = Decode(payload)
    if not l or l.name == me then return true end
    if live and senderName ~= l.name then return true end
    local now = GetServerTime()
    if now - l.ts > LISTING_FOR or l.ts > now + 300 then return true end
    -- Removed by its player after this copy was made
    if l.ts <= (removedAt[l.name] or 0) then return true end
    -- Only players of the listed guilds; the guild from the rosters or their status, never from the packet
    local p = M.FindKnownPlayer(l.name)
    if not p then
        if addonTable.Monitor then addonTable.Monitor.Note("LFG: listing of " .. l.name .. " ignored (not known from the rosters yet)") end
        return true
    end
    l.guild = p.guild
    l.seen = GetTime()
    if (not l.class or l.class == "") and p.class then l.class = p.class end
    for i, old in ipairs(listings) do
        if old.name == l.name then
            if (old.ts or 0) > l.ts then return true end
            listings[i] = l
            Changed()
            return true
        end
    end
    table.insert(listings, l)
    Changed()
    return true
end

-- ============================================================================
-- MY LISTING (the editor window)
-- ============================================================================
local editor = nil
local draft = nil   -- { roles, acts, note } being edited

local function MyClass() return select(2, _G.UnitClass("player")) end

function LFG.SaveMine()
    if not draft then return false, "Nothing to list." end
    local anyRole = false
    for _ in pairs(draft.roles) do anyRole = true end
    if not anyRole then return false, "Pick at least one role." end
    if #draft.acts == 0 then return false, "Add at least one activity." end
    local Most = addonTable.Most
    if not mine then
        mine = {}
        table.insert(listings, mine)
    end
    mine.name, mine.class, mine.level, mine.guild = Most.MyName(), MyClass(), _G.UnitLevel("player"), Most.MyGuild()
    mine.roles, mine.acts, mine.note, mine.ts = draft.roles, draft.acts, draft.note or "", GetServerTime()
    SaveMineToDB()
    SendMine()
    return true
end

-- The notice on the community LFG chat when I list myself or change my listing (from the click, which the
-- game requires for channel messages). Compact: "!lfg Tank/Heal: Shadowfang Keep, Blackfathom Deeps "note"";
-- every client shows the "!lfg " marker as an [Open in LFG] link (bridge.lua). At most every ANNOUNCE_EVERY.
local ANNOUNCE_EVERY = 20   -- only against quick double clicks: every save and update is posted
local lastAnnounce = -ANNOUNCE_EVERY
local ROLE_WORD = { TANK = "Tank", HEAL = "Heal", DPS = "DPS" }
-- isNew: a new listing ("Just listed") or a changed one ("Updated listing")
function LFG.Announce(isNew)
    if not mine then return end
    if GetTime() - lastAnnounce < ANNOUNCE_EVERY then
        _G.UIErrorsFrame:AddMessage("Listing saved - the LFG chat notice waits a few seconds between posts", 1, 0.82, 0, 1, 2)
        return
    end
    local Most = addonTable.Most
    local guild = Most.MyGuild()
    if not guild or not Most.IsGuildAllowed(guild) or addonTable.Mute.IsMuted(Most.MyName()) then return end
    lastAnnounce = GetTime()
    local roles, acts = {}, {}
    for _, role in ipairs(ROLE_ORDER) do if mine.roles[role] then table.insert(roles, ROLE_WORD[role]) end end
    for _, a in ipairs(mine.acts) do table.insert(acts, (a.t == "quest") and ("questing " .. a.n) or a.n) end
    local text = "!lfg " .. (isNew and "Just listed - " or "Updated listing - ") .. table.concat(roles, "/") .. ": " .. table.concat(acts, ", ") .. ((mine.note ~= "") and (' "' .. mine.note .. '"') or "")
    Most.PublishTyped("Szukaj grupy", text, Most.MyName(), guild)
end

-- For Monitoring: counts and one line per listing (names, guilds, times; never the note)
function LFG.GetMonitorInfo()
    local rows, offline = {}, 0
    for _, l in ipairs(listings) do
        if l.offlineSince then offline = offline + 1 end
        table.insert(rows, string.format("%s |cff808080%s|r: %d activities, listed %s ago%s%s", l.name, tostring(l.guild), #l.acts, Ago(l.ts),
            l.seen and (", heard " .. math.floor((GetTime() - l.seen) / 60) .. " min ago") or "",
            l.offlineSince and (" |cffff9933offline " .. math.floor((GetTime() - l.offlineSince) / 60) .. " min|r") or ""))
    end
    return { total = #listings, offline = offline, mine = mine ~= nil, rows = rows }
end

-- My upcoming events (I created them, not over yet), nearest first: for "Invite to my event"
function LFG.MyUpcomingEvents()
    local list, me, Ev = {}, addonTable.Most.MyName(), addonTable.Events
    if not Ev then return list end
    local now = _G.time()
    for _, ev in ipairs(Ev.List()) do
        local start = Ev.Start(ev)
        if ev.creator == me and start and start > now - 3600 then table.insert(list, ev) end
    end
    table.sort(list, function(a, b) return (Ev.Start(a) or 0) < (Ev.Start(b) or 0) end)
    return list
end

-- A whisper inviting a player to my event. The marker <jn-event:id> becomes an [Open event] link for players
-- with the addon (a chat filter below, on their side): a link cannot be typed into a message itself.
function LFG.InviteToEvent(name, ev)
    local Most = addonTable.Most
    local when = tostring(ev.date):gsub("^(%d+%.%d+)%.%d+$", "%1") .. " " .. tostring(ev.time)
    local text = "Hi! I'd like you in my event: " .. tostring(ev.title) .. (ev.dungeon and (" (" .. ev.dungeon .. ")") or "") .. ", " .. when
        .. ". Sign up here: <jn-event:" .. tostring(ev.id) .. ">"
    _G.SendChatMessage(text, "WHISPER", nil, Most.GameName(name))
end

-- ============================================================================
-- "LOOKING FOR..." ON THE COMMUNITY CHAT (0.15.2)
-- ============================================================================
-- When I write on the community General or LFG chat that I am looking for a group for something ("szukam
-- kogos na DM", "LFG SFK", "lfm strat") and players are listed in LFG for the same activity, a hint shows
-- for me alone, with their names and an [Open in LFG] link. Nothing is sent: the game lets the addon write
-- on a channel only from a key press or a click, and an automatic answer from hundreds of clients would be
-- spam. The same activity is hinted at most every HINT_AGAIN.
local HINT_AGAIN = 300
local hintedAt = {}
local SEEK_WORDS = { "lfg", "lfm", "lf", "lf1m", "lf2m", "lf3m", "lf4m", "szukam", "szuka", "szukamy", "szukacie", "kto na", "ktos na",
    "ktos idzie", "kto idzie", "chetni", "chetny", "kto do", "ktos do", "zbieram", "zbieramy", "lecimy na", "idziemy na", "wbije ktos", "need", "potrzebny", "potrzebna", "potrzebuje", "brakuje", "wbijam", "ide na" }
-- Short names players use; one may mean several (DM: the Deadmines at low level, Dire Maul at 60)
local ALIASES = {
    rfc = { "Ragefire Chasm" }, wc = { "Wailing Caverns" }, dm = { "The Deadmines", "Dire Maul" }, vc = { "The Deadmines" },
    deadmines = { "The Deadmines" }, sfk = { "Shadowfang Keep" }, bfd = { "Blackfathom Deeps" }, stocks = { "The Stockade" },
    stockade = { "The Stockade" }, gnomer = { "Gnomeregan" }, rfk = { "Razorfen Kraul" }, sm = { "Scarlet Monastery" },
    cath = { "Scarlet Monastery" }, rfd = { "Razorfen Downs" }, ulda = { "Uldaman" }, uld = { "Uldaman" }, zf = { "Zul'Farrak" },
    mara = { "Maraudon" }, st = { "Sunken Temple" }, brd = { "Blackrock Depths" }, lbrs = { "Lower Blackrock Spire" },
    ubrs = { "Upper Blackrock Spire" }, strat = { "Stratholme" }, strath = { "Stratholme" }, scholo = { "Scholomance" },
    scholo2 = { "Scholomance" }, zg = { "Zul'Gurub" }, aq20 = { "Ruins of Ahn'Qiraj" }, mc = { "Molten Core" }, ony = { "Onyxia's Lair" },
    onyxia = { "Onyxia's Lair" }, bwl = { "Blackwing Lair" }, aq40 = { "Temple of Ahn'Qiraj" }, naxx = { "Naxxramas" },
    wsg = { "Warsong Gulch" }, ab = { "Arathi Basin" }, av = { "Alterac Valley" },
}
-- Lower case, Polish letters without accents, only letters / digits / spaces, with a space on both ends
local PL = { ["ą"] = "a", ["ć"] = "c", ["ę"] = "e", ["ł"] = "l", ["ń"] = "n", ["ó"] = "o", ["ś"] = "s", ["ź"] = "z", ["ż"] = "z",
    ["Ą"] = "a", ["Ć"] = "c", ["Ę"] = "e", ["Ł"] = "l", ["Ń"] = "n", ["Ó"] = "o", ["Ś"] = "s", ["Ź"] = "z", ["Ż"] = "z" }
local function Norm(s)
    s = tostring(s or ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("[\196\197\195][\128-\191]", function(ch) return PL[ch] or ch end):lower()
    s = s:gsub("'", ""):gsub("[^%w]+", " ")
    return " " .. s .. " "
end
local function NormName(n) return Norm(n):gsub("^ the ", " ") end

-- The activities my message names, as listing activity names (only those someone is listed for count later)
local function NamedActivities(text)
    local msg = Norm(text)
    local seeking = false
    for _, w in ipairs(SEEK_WORDS) do if msg:find(" " .. w .. " ", 1, true) then seeking = true break end end
    -- Also any "LF<n>M" (lf5m, lf10m...) and a role right after LF / LFM ("lftank", "lfmheal", "lfdps")
    if not seeking then
        for word in msg:gmatch("%S+") do
            if word:match("^lf%d+m$") or word:match("^lfm?tanka?$") or word:match("^lfm?heal") or word:match("^lfm?dps$") then seeking = true break end
        end
    end
    if not seeking then return nil end
    local names = {}
    for word in msg:gmatch("%S+") do
        for _, n in ipairs(ALIASES[word] or {}) do names[n] = true end
    end
    -- Full names (and zones for questing) of what is listed right now
    for _, l in ipairs(listings) do
        for _, a in ipairs(l.acts) do
            local n = NormName(a.n)
            if #n > 4 and msg:find(n, 1, true) then names[a.n] = true end
        end
    end
    return names
end

function LFG.CheckOwnMessage(text)
    local names = NamedActivities(text)
    if not names then return end
    local me = Most().MyName()
    for name in pairs(names) do
        if GetTime() - (hintedAt[name] or -HINT_AGAIN) >= HINT_AGAIN then
            local who = {}
            for _, l in ipairs(listings) do
                if l ~= mine and l.name ~= me and not l.offlineSince then
                    for _, a in ipairs(l.acts) do
                        if a.n == name then table.insert(who, l.name) break end
                    end
                end
            end
            if #who > 0 then
                hintedAt[name] = GetTime()
                local shown = {}
                for i = 1, math.min(5, #who) do shown[i] = who[i] end
                local text = (#who == 1 and "1 player is" or (#who .. " players are")) .. " looking for |cffffd100" .. name .. "|r in LFG right now: "
                    .. table.concat(shown, ", ") .. (#who > 5 and (" and " .. (#who - 5) .. " more") or "") .. ". "
                    .. "|cff6cc4e6|Hgarrmission:jagodkalfg:" .. name .. "|h[Open in LFG]|h|r" .. (mine and "" or " - or list yourself there.")
                local frame = (addonTable.Zakladka and addonTable.Zakladka.Frame and addonTable.Zakladka.Frame()) or _G.DEFAULT_CHAT_FRAME
                if frame then frame:AddMessage("|cffbf40ff[Jagodka]|r " .. text) end
                -- And in the addon window's chat (a line for me alone, never sent)
                addonTable.Most.AddSystem(text)
                if addonTable.Monitor then addonTable.Monitor.Note("LFG: hint for my message about " .. name .. " (" .. #who .. " listed)") end
            end
        end
    end
end

-- My own messages on the community General and LFG chats (bridge.lua's log; not my own LFG notice)
addonTable.Most.OnNewEntry(function(e, live)
    if not live or e.src ~= "A" or e.author ~= addonTable.Most.MyName() then return end
    if e.tab ~= "Ogolny" and e.tab ~= "Szukaj grupy" then return end
    if type(e.text) ~= "string" or e.text:find("^!lfg ") or e.text:find("<jn%-event:%w+>$") then return end
    local text = e.text
    -- A moment later, so the hint shows under my message
    addonTable.SafeTimer.After(0.3, function() LFG.CheckOwnMessage(text) end)
end)

-- A click on [Open in LFG] in any chat: the addon window on the LFG tab, searching for that player
function LFG.Open(name)
    if not ctx or not ctx.open then return end
    ctx.open()
    -- Filters left from before (activity, role) could hide the listing: they are cleared, then the search shows
    -- just that player. The view is made later (Attach), so it is reached through LFG.
    if LFG.ResetView then LFG.ResetView(name) end
end

function LFG.RemoveMine()
    if mine and InGuild() then Most().Send("LX", Most().EncodeField(mine.name) .. ":" .. GetServerTime(), "high") end
    for i, l in ipairs(listings) do if l == mine then table.remove(listings, i) break end end
    mine = nil
    SaveMineToDB()
end

-- After login: my listing from before (/reload, relog) comes back while it is still valid, and goes out again
local function RestoreMine()
    local saved = addonTable.Settings.CharStore().lfg
    if type(saved) ~= "table" or not saved.ts or GetServerTime() - saved.ts > LISTING_FOR or type(saved.acts) ~= "table" then return end
    local M = Most()
    mine = { name = M.MyName(), class = MyClass(), level = _G.UnitLevel("player"), guild = M.MyGuild(), roles = saved.roles or {}, acts = saved.acts, note = saved.note or "", ts = saved.ts }
    table.insert(listings, mine)
    SendMine()
    Changed()
end

local function CopyDraft()
    draft = { roles = {}, acts = {}, note = mine and mine.note or "" }
    if mine then
        for k in pairs(mine.roles) do draft.roles[k] = true end
        for _, a in ipairs(mine.acts) do table.insert(draft.acts, { t = a.t, n = a.n }) end
    end
end

local RenderList   -- defined below

local function RenderEditor()
    if not editor or not editor:IsShown() then return end
    local roles = ctx.classRoles[MyClass()] or { TANK = true, HEAL = true, DPS = true }
    for role, check in pairs(editor.roleChecks) do
        local allowed = roles[role]
        check:SetEnabled(allowed and true or false)
        check.label:SetAlpha(allowed and 1 or 0.4)
        check:SetChecked(allowed and draft.roles[role] or false)
    end
    for i, chip in ipairs(editor.chips) do
        local a = draft.acts[i]
        if a then chip.text:SetText(ActLabel(a, true)) chip:Show() else chip:Hide() end
    end
    editor.addBtn:SetEnabled(#draft.acts < MAX_ACTIVITIES)
    editor.status:SetText(mine and ("|cff00ff00Listed|r " .. Ago(mine.ts) .. " ago, ends in " .. Ago(GetServerTime() - (LISTING_FOR - (GetServerTime() - mine.ts)))) or "|cff808080Not listed|r")
    editor.save:SetText(mine and "Update listing" or "List me")
    editor.remove:SetShown(mine ~= nil)
end

local function AddActivity(t, n)
    if #draft.acts >= MAX_ACTIVITIES then return end
    for _, a in ipairs(draft.acts) do if a.t == t and a.n == n then return end end
    table.insert(draft.acts, { t = t, n = n })
    RenderEditor()
end

-- Zones of the world by continent, from the game's map data (so WoW Forever's new zones are there too):
-- { { name = continent, zones = { "Ashenvale", ... } } }, sorted; read once, when the menu first opens
local worldZones = nil
local function WorldZones()
    if worldZones then return worldZones end
    worldZones = {}
    local C_Map, Enum = _G.C_Map, _G.Enum
    if not (C_Map and C_Map.GetMapChildrenInfo and Enum and Enum.UIMapType) then return worldZones end
    local AZEROTH = 947
    local continents = C_Map.GetMapChildrenInfo(AZEROTH, Enum.UIMapType.Continent) or {}
    -- Classic Era's continents when the world map gives none
    if #continents == 0 then continents = { { mapID = 1414, name = "Kalimdor" }, { mapID = 1415, name = "Eastern Kingdoms" } } end
    for _, cont in ipairs(continents) do
        local names, seen = {}, {}
        for _, z in ipairs(C_Map.GetMapChildrenInfo(cont.mapID, Enum.UIMapType.Zone, true) or {}) do
            if z.name and not seen[z.name] then seen[z.name] = true table.insert(names, z.name) end
        end
        table.sort(names)
        if #names > 0 then table.insert(worldZones, { name = cont.name or tostring(cont.mapID), zones = names }) end
    end
    table.sort(worldZones, function(a, b) return a.name < b.name end)
    return worldZones
end

local function BuildEditor(parent)
    editor = CreateFrame("Frame", "JagodkaLFGEditor", parent, "BackdropTemplate")
    editor:SetSize(340, 330)
    editor:SetPoint("CENTER", parent, "CENTER", 0, 0)
    editor:SetFrameStrata("DIALOG")
    editor:EnableMouse(true)
    editor:SetMovable(true)
    editor:RegisterForDrag("LeftButton")
    editor:SetScript("OnDragStart", editor.StartMoving)
    editor:SetScript("OnDragStop", editor.StopMovingOrSizing)
    ctx.applyStyle(editor)
    editor:SetBackdropColor(0.05, 0.05, 0.07, 0.98)
    editor:Hide()
    table.insert(_G.UISpecialFrames, "JagodkaLFGEditor")
    local close = CreateFrame("Button", nil, editor, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", editor, "TOPRIGHT", 0, 0)
    local title = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -14)
    title:SetText("My LFG listing")
    local function Label(text, y)
        local l = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        l:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, y)
        l:SetText(text)
        return l
    end
    -- Roles: only those of my class
    Label("I can play", -46)
    editor.roleChecks = {}
    for i, role in ipairs(ROLE_ORDER) do
        local c = CreateFrame("CheckButton", nil, editor, "UICheckButtonTemplate")
        c:SetSize(24, 24)
        c:SetPoint("TOPLEFT", editor, "TOPLEFT", 14 + (i - 1) * 100, -62)
        c.label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
        c.label:SetText(ROLE_ICON[role] .. " " .. ({ TANK = "Tank", HEAL = "Healer", DPS = "DPS" })[role])
        c:SetScript("OnClick", function(self) draft.roles[role] = self:GetChecked() and true or nil end)
        editor.roleChecks[role] = c
    end
    -- Activities: chips with an X, and the add menu
    Label("Looking for (up to " .. MAX_ACTIVITIES .. ")", -96)
    editor.chips = {}
    for i = 1, MAX_ACTIVITIES do
        local chip = CreateFrame("Frame", nil, editor, "BackdropTemplate")
        chip:SetSize(300, 20)
        chip:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -114 - (i - 1) * 22)
        chip:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        chip:SetBackdropColor(1, 1, 1, 0.05)
        chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        chip.text:SetPoint("LEFT", chip, "LEFT", 6, 0)
        local x = CreateFrame("Button", nil, chip, "UIPanelCloseButton")
        x:SetSize(20, 20)
        x:SetPoint("RIGHT", chip, "RIGHT", 2, 0)
        x:SetScript("OnClick", function() table.remove(draft.acts, i) RenderEditor() end)
        editor.chips[i] = chip
    end
    -- Add menu: the instances (as in Create Event), questing in my zone, or anything
    local menu = CreateFrame("Frame", "JagodkaLFGActivityMenu", _G.UIParent, "UIDropDownMenuTemplate")
    -- Questing: "here" (the current zone) at once, or any zone of the world by continent
    local QUESTING = { questing = true }
    _G.UIDropDownMenu_Initialize(menu, function(_, level, menuList)
        if level == 1 then
            for _, group in ipairs(addonTable.InstanceGroups()) do
                local info = _G.UIDropDownMenu_CreateInfo()
                info.text, info.hasArrow, info.notCheckable, info.menuList = group.group, true, true, group.list
                _G.UIDropDownMenu_AddButton(info, level)
            end
            local info = _G.UIDropDownMenu_CreateInfo()
            info.text, info.hasArrow, info.notCheckable, info.menuList = "|cffffd100Questing|r", true, true, QUESTING
            _G.UIDropDownMenu_AddButton(info, level)
            info = _G.UIDropDownMenu_CreateInfo()
            info.text, info.notCheckable = "Anything", true
            info.func = function() AddActivity("other", "Anything") _G.CloseDropDownMenus() end
            _G.UIDropDownMenu_AddButton(info, level)
            return
        end
        if menuList == QUESTING then
            local zone = _G.GetRealZoneText() or ""
            local info = _G.UIDropDownMenu_CreateInfo()
            info.text, info.notCheckable = "|cff00ff00Here:|r " .. zone, true
            info.func = function() AddActivity("quest", zone) _G.CloseDropDownMenus() end
            _G.UIDropDownMenu_AddButton(info, level)
            for _, cont in ipairs(WorldZones()) do
                info = _G.UIDropDownMenu_CreateInfo()
                info.text, info.hasArrow, info.notCheckable, info.menuList = cont.name, true, true, { zones = cont.zones }
                _G.UIDropDownMenu_AddButton(info, level)
            end
            return
        end
        if menuList and menuList.zones then
            for _, zone in ipairs(menuList.zones) do
                local info = _G.UIDropDownMenu_CreateInfo()
                info.text, info.notCheckable = zone, true
                info.func = function() AddActivity("quest", zone) _G.CloseDropDownMenus() end
                _G.UIDropDownMenu_AddButton(info, level)
            end
            return
        end
        for _, inst in ipairs(menuList or {}) do
            local info = _G.UIDropDownMenu_CreateInfo()
            info.text = inst.name .. " |cff808080(" .. inst.levels .. ")|r"
            info.notCheckable = true
            info.disabled = inst.opensAt and _G.time() < inst.opensAt
            info.func = function() AddActivity(TypeOfInstance(inst.name), inst.name) _G.CloseDropDownMenus() end
            _G.UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")
    editor.addBtn = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    editor.addBtn:SetSize(120, 22)
    editor.addBtn:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -206)
    editor.addBtn:SetText("+ Add activity")
    editor.addBtn:SetScript("OnClick", function(self) _G.ToggleDropDownMenu(1, nil, menu, self, 0, 0) end)
    -- Note
    Label("Note", -238)
    editor.note = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    editor.note:SetSize(300, 22)
    editor.note:SetPoint("TOPLEFT", editor, "TOPLEFT", 22, -254)
    editor.note:SetAutoFocus(false)
    editor.note:SetFontObject(_G.ChatFontNormal)
    editor.note:SetMaxBytes(NOTE_MAX)
    editor.note:SetScript("OnTextChanged", function(self) if draft then draft.note = self:GetText() end end)
    editor.note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Buttons and state
    editor.status = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    editor.status:SetPoint("BOTTOMLEFT", editor, "BOTTOMLEFT", 16, 44)
    editor.save = CreateFrame("Button", nil, editor, "GameMenuButtonTemplate")
    editor.save:SetSize(130, 26)
    editor.save:SetPoint("BOTTOMLEFT", editor, "BOTTOMLEFT", 14, 12)
    editor.save:SetScript("OnClick", function()
        local isNew = mine == nil
        local ok, why = LFG.SaveMine()
        if not ok then _G.UIErrorsFrame:AddMessage(why, 1, 0.1, 0.1, 1, 2) return end
        LFG.Announce(isNew)
        editor:Hide()
        RenderList()
    end)
    editor.remove = CreateFrame("Button", nil, editor, "GameMenuButtonTemplate")
    editor.remove:SetSize(130, 26)
    editor.remove:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -14, 12)
    -- White text with a red X, like every removing button (red text on the red button was hard to read)
    editor.remove:SetText("|TInterface\\Buttons\\UI-GroupLoot-Pass-Up:14:14:0:0|t |cffffffffRemove listing|r")
    editor.remove:SetScript("OnClick", function() LFG.RemoveMine() editor:Hide() RenderList() end)
    editor:SetScript("OnShow", function()
        CopyDraft()
        editor.note:SetText(draft.note or "")
        RenderEditor()
    end)
end

-- ============================================================================
-- THE TAB
-- ============================================================================
-- 0.15.6: roles and guilds are sets (tick several: { key = true }), class one class; nil = any
local panel, rows, scroll, view = nil, {}, nil, { page = 1, actFilter = nil, roles = nil, guilds = nil, class = nil, sortKey = nil, desc = false }
local search, nav, empty, columns = nil, nil, nil, nil

local function Matches(l, text)
    -- Activity filter (the same choices as the add menu): a type, a set of instance names, or one activity
    local f = view.actFilter
    if f then
        local any = false
        for _, a in ipairs(l.acts) do
            -- "Anything" means open to everything: such a player fits every activity filter
            if a.t == "other" or ((not f.t or a.t == f.t) and (not f.n or a.n == f.n) and (not f.names or f.names[a.n])) then any = true end
        end
        if not any then return false end
    end
    -- Roles: a player with any of the ticked roles passes
    if view.roles then
        local any = false
        for role in pairs(view.roles) do if l.roles[role] then any = true end end
        if not any then return false end
    end
    if view.guilds and not view.guilds[l.guild or ""] then return false end
    if view.class and l.class ~= view.class then return false end
    -- 0.15.6: the search box looks at the player's name and the note (activity, guild and role have filters)
    if text == "" then return true end
    for _, v in ipairs({ l.name, l.note }) do if v and tostring(v):lower():find(text, 1, true) then return true end end
    return false
end

local function Sorted()
    local text = search:GetText():lower()
    local list = {}
    for _, l in ipairs(All()) do if Matches(l, text) then table.insert(list, l) end end
    local key, desc = view.sortKey, view.desc
    table.sort(list, function(a, b)
        -- Offline (relog, reload) after everyone online, whatever the sorting
        if (a.offlineSince ~= nil) ~= (b.offlineSince ~= nil) then return a.offlineSince == nil end
        local va, vb
        if key == "name" then va, vb = a.name, b.name
        elseif key == "level" then va, vb = tonumber(a.level) or 0, tonumber(b.level) or 0
        elseif key == "guild" then va, vb = a.guild or "", b.guild or ""
        else va, vb = b.ts or 0, a.ts or 0 end   -- default: newest first
        if va ~= vb then if desc then return va > vb end return va < vb end
        return a.name < b.name
    end)
    return list
end

local function ShowTooltip(row, anchor)
    local l = row.listing
    if not l then return end
    local tip = _G.GameTooltip
    tip:SetOwner(row, anchor or "ANCHOR_RIGHT")
    local color = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[l.class]
    tip:AddLine(color and color:WrapTextInColorCode(l.name) or l.name)
    tip:AddLine("Level " .. tostring(l.level) .. " " .. tostring(_G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[l.class] or l.class) .. ", " .. tostring(l.guild), 0.8, 0.8, 0.8)
    tip:AddLine("Roles: " .. RolesText(l.roles), 1, 1, 1)
    if addonTable.Discord then addonTable.Discord.AddLine(tip, l.name) end
    tip:AddLine(" ")
    for _, a in ipairs(l.acts) do
        local t = TYPE_BY_KEY[a.t] or TYPE_BY_KEY.other
        tip:AddDoubleLine(ActLabel(a, true), t.label, 1, 1, 1, 0.6, 0.6, 0.6)
    end
    if l.note and l.note ~= "" then tip:AddLine(" ") tip:AddLine('"' .. l.note .. '"', 1, 0.82, 0, true) end
    tip:AddLine(" ")
    tip:AddLine("Listed " .. Ago(l.ts) .. " ago", 0.5, 0.5, 0.5)
    if l == mine then
        local left = math.max(0, LISTING_FOR - (GetServerTime() - (l.ts or 0)))
        tip:AddLine("Ends in " .. math.floor(left / 3600) .. " h " .. math.floor(left % 3600 / 60) .. " min (saving it again renews it)", 0.5, 0.5, 0.5)
    end
    if l.offlineSince then
        local away = math.floor((GetTime() - l.offlineSince) / 60)
        tip:AddLine("Offline for " .. away .. " min - removed in " .. math.max(0, math.ceil((OFFLINE_GRACE - (GetTime() - l.offlineSince)) / 60)) .. " min if not back", 1, 0.6, 0.2)
    end
    if l == mine then if anchor ~= "ANCHOR_LEFT" then tip:AddLine("Click: edit your listing   Right click: change or remove it", 0.5, 0.5, 0.5) end
    else tip:AddLine("Right click: whisper / invite   Shift + click: whisper", 0.5, 0.5, 0.5) end
    tip:Show()
end

-- ============================================================================
-- THE RIGHT COLUMN (core.lua's "Events / LFG" section, tab LFG): only my listing, one row per activity
-- ============================================================================
-- Rows for the column: one per activity of my listing { left, mid, right, listing }, or one "not listed" row;
-- and the count for the tab (my activities)
function LFG.SideItems()
    local my = mine
    if not my then
        return { { left = "|cff808080-|r", mid = "|cff808080Not listed - click to list yourself|r", right = "" } }, 0
    end
    local items = {}
    local m = math.max(0, math.floor((GetServerTime() - (my.ts or 0)) / 60))
    local left = LISTING_FOR - (GetServerTime() - (my.ts or 0))
    -- How long I have waited (orange "ends Nm" in the last 15 minutes), on the first row
    local wait = (left < 900) and ("|cffff9933ends " .. math.max(0, math.floor(left / 60)) .. "m|r")
        or (m < 60 and (m .. "m") or (math.floor(m / 60) .. "h " .. m % 60 .. "m"))
    for i, a in ipairs(my.acts) do
        local t = TYPE_BY_KEY[a.t] or TYPE_BY_KEY.other
        -- Others listed for the same activity (online; the same type and name), in brackets after it
        local same = {}
        for _, l in ipairs(listings) do
            if l ~= mine and not l.offlineSince then
                for _, b in ipairs(l.acts) do
                    if b.t == a.t and b.n == a.n then table.insert(same, l.name) break end
                end
            end
        end

        table.insert(items, { listing = my, same = same, act = a, left = "|cff" .. t.color .. t.label .. "|r",
            -- Roles only in the tooltip (ShowTooltip: "Roles: ..."), the line stays short
            mid = tostring(a.n) .. " " .. (#same > 0 and ("|cff00ff00(" .. #same .. ")|r") or "|cff808080(0)|r"), right = i == 1 and wait or "" })
    end
    return items, #my.acts
end

-- Click on any row: the LFG tab with every listing (filters reset) and my listing's editor
function LFG.EditMine()
    if ctx and ctx.open then ctx.open() end
    if LFG.ResetView then LFG.ResetView() end
    if editor then editor:Show() end
end

function LFG.SideClick(row, button)
    if button == "RightButton" and mine and panel and panel.myMenu then
        _G.ToggleDropDownMenu(1, nil, panel.myMenu, "cursor", 0, 0)
    else
        LFG.EditMine()
    end
end

function LFG.SideTooltip(row)
    local item = row.item
    if not item then return end
    local tip = _G.GameTooltip
    if not item.listing then
        tip:SetOwner(row, "ANCHOR_LEFT")
        tip:AddLine("You are not listed", 1, 1, 1)
        tip:AddLine("Click to list yourself: roles, up to " .. MAX_ACTIVITIES .. " activities and a note.", 0.8, 0.8, 0.8, true)
        tip:Show()
        return
    end
    row.listing = item.listing
    ShowTooltip(row, "ANCHOR_LEFT")
    -- Who else is listed for this activity
    tip:AddLine(" ")
    if #item.same > 0 then
        tip:AddLine("Also looking for " .. ActLabel(item.act) .. " (" .. #item.same .. "):", 0.25, 0.85, 0.25)
        for _, n in ipairs(item.same) do tip:AddLine("  " .. n, 1, 1, 1) end
    else
        tip:AddLine("Nobody else is listed for " .. ActLabel(item.act) .. " right now", 0.6, 0.6, 0.6)
    end
    tip:AddLine("Click: edit your listing   Right click: change or remove", 0.5, 0.5, 0.5)
    tip:Show()
end
-- Columns: fixed ones, and "Looking for" and "Note" sharing the rest (60 / 40)
local function Layout()
    local width = panel.list:GetWidth() - 30
    local fixed = { name = 130, level = 30, guild = 110, roles = 50, since = 60 }
    local flex = math.max(120, width - (fixed.name + fixed.level + fixed.guild + fixed.roles + fixed.since) - 6 * 6)
    local widths = { name = fixed.name, level = fixed.level, guild = fixed.guild, roles = fixed.roles, acts = math.floor(flex * 0.6), note = math.floor(flex * 0.4), since = fixed.since }
    local x = 8
    for _, col in ipairs(columns) do
        local w = widths[col.key]
        col.header:ClearAllPoints()
        col.header:SetPoint("TOPLEFT", panel.list, "TOPLEFT", x, -6)
        col.header:SetSize(w, 18)
        for _, row in ipairs(rows) do
            local cell = row[col.key]
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", row, "LEFT", x - 4, 0)
            cell:SetWidth(w)
        end
        x = x + w + 6
    end
end

RenderList = function()
    if not panel or not panel:IsVisible() then return end
    Prune()
    local list = Sorted()
    local total = #list
    local pages = math.max(1, math.ceil(total / PER_PAGE))
    if view.page > pages then view.page = pages end
    local first = (view.page - 1) * PER_PAGE
    local count = math.min(PER_PAGE, total - first)
    nav.info:SetText(total == 0 and "Showing 0 of 0" or ("Showing " .. (first + 1) .. "-" .. (first + count) .. " of " .. total))
    nav.page:SetText("Page " .. view.page .. " / " .. pages)
    nav.buttons[1]:SetEnabled(view.page > 1) nav.buttons[2]:SetEnabled(view.page > 1)
    nav.buttons[3]:SetEnabled(view.page < pages) nav.buttons[4]:SetEnabled(view.page < pages)
    empty:SetShown(total == 0)
    local visible = panel.list.visibleRows or 16
    _G.FauxScrollFrame_Update(scroll, count, visible, ROW_H)
    local offset = _G.FauxScrollFrame_GetOffset(scroll)
    local me = addonTable.Most.MyName()
    for i, row in ipairs(rows) do
        local l = (i <= visible and i + offset <= count) and list[first + i + offset]
        if l then
            row.listing = l
            row.member = { name = l.name, online = true }
            local color = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[l.class]
            row.name:SetText((color and color:WrapTextInColorCode(l.name) or l.name) .. (l.name == me and " |cff00ff00(you)|r" or "")
                .. (l.offlineSince and " |cff808080(offline)|r" or ""))
            -- Offline (relog, reload): grayed until they are back or the grace time ends
            row:SetAlpha(l.offlineSince and 0.5 or 1)
            row.level:SetText(l.level)
            row.guild:SetText("|cffbf40ff" .. tostring(l.guild) .. "|r")
            row.roles:SetText(RolesText(l.roles))
            row.acts:SetText(ActLabel(l.acts[1] or { t = "other", n = "-" }, true) .. ((#l.acts > 1) and (" |cff808080+" .. (#l.acts - 1) .. "|r") or ""))
            row.note:SetText(l.note ~= "" and ("|cffd0d0d0" .. l.note .. "|r") or "|cff808080-|r")
            row.since:SetText("|cff808080" .. Ago(l.ts) .. "|r")
            row:Show()
        else
            row.listing, row.member = nil, nil
            row:Hide()
        end
    end
    panel.myBtn:SetText(mine and "My listing" or "List me")
end
LFG.Render = function() RenderList() end


-- core.lua: c = { applyStyle, classRoles, onRowClick }
function LFG.Attach(p, c)
    panel, ctx = p, c
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -14)
    title:SetText("Looking for group")
    if addonTable.Help then addonTable.Help.Button(panel, "lfg", nil, "LFG"):SetPoint("LEFT", title, "RIGHT", 8, 0) end
    panel.myBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    panel.myBtn:SetSize(120, 28)
    panel.myBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -5)
    panel.myBtn:SetScript("OnClick", function() if editor:IsShown() then editor:Hide() else editor:Show() end end)
    -- Search and filters
    search = CreateFrame("EditBox", "JagodkaLFGSearch", panel, "InputBoxTemplate")
    search:SetSize(150, 24)
    search:SetPoint("TOPLEFT", panel, "TOPLEFT", 62, -40)
    search:SetAutoFocus(false)
    search:SetFontObject(_G.ChatFontNormal)
    local sLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sLabel:SetPoint("RIGHT", search, "LEFT", -8, 0)
    sLabel:SetText("Search:")
    search.hint = search:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    search.hint:SetPoint("LEFT", search, "LEFT", 5, 0)
    search.hint:SetText("Player name or note...")
    search:SetScript("OnTextChanged", function(self) self.hint:SetShown(self:GetText() == "") view.page = 1 RenderList() end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    LFG.searchBox = search
    -- Activity filter: the same menu as adding an activity, one to one: a whole group ("All dungeons"), one
    -- instance, questing anywhere / here / in one zone, or anything
    local typeDD = CreateFrame("Frame", "JagodkaLFGTypeFilter", panel, "UIDropDownMenuTemplate")
    _G.UIDropDownMenu_SetWidth(typeDD, 120)
    local function Pick(filter, label)
        view.actFilter, view.page = filter, 1
        _G.UIDropDownMenu_SetText(typeDD, label)
        _G.CloseDropDownMenus()
        RenderList()
    end
    local QUESTS = { quests = true }
    _G.UIDropDownMenu_Initialize(typeDD, function(_, level, menuList)
        local function Add(text, func, arrow, list)
            local info = _G.UIDropDownMenu_CreateInfo()
            info.text, info.notCheckable, info.func, info.hasArrow, info.menuList = text, true, func, arrow, list
            _G.UIDropDownMenu_AddButton(info, level)
        end
        if level == 1 then
            Add("Any activity", function() Pick(nil, "Activity") end)
            for _, group in ipairs(addonTable.InstanceGroups()) do Add(group.group, nil, true, group) end
            Add("|cffffd100Questing|r", nil, true, QUESTS)
            -- No "Anything" here: players open to anything already show under every filter
            return
        end
        if menuList == QUESTS then
            Add("Any questing", function() Pick({ t = "quest" }, "Questing") end)
            local zone = _G.GetRealZoneText() or ""
            Add("|cff00ff00Here:|r " .. zone, function() Pick({ t = "quest", n = zone }, zone) end)
            for _, cont in ipairs(WorldZones()) do Add(cont.name, nil, true, { zones = cont.zones }) end
            return
        end
        if menuList and menuList.zones then
            for _, zone in ipairs(menuList.zones) do Add(zone, function() Pick({ t = "quest", n = zone }, zone) end) end
            return
        end
        if menuList and menuList.list then
            -- A group: all of it, then each instance
            local names = {}
            for _, inst in ipairs(menuList.list) do names[inst.name] = true end
            Add("|cffffd100All:|r " .. menuList.group, function() Pick({ names = names }, menuList.group) end)
            for _, inst in ipairs(menuList.list) do
                Add(inst.name .. " |cff808080(" .. inst.levels .. ")|r", function() Pick({ n = inst.name }, inst.name) end)
            end
        end
    end)
    _G.UIDropDownMenu_SetText(typeDD, "Activity")
    -- 0.15.6: one row of filters under the search, as in Members and Events: activity, role (tick several),
    -- guild (tick several, the guilds on the board with counts), class
    _G.UIDropDownMenu_SetWidth(typeDD, 115)
    typeDD:SetPoint("TOPLEFT", panel, "TOPLEFT", -14, -68)
    -- A filter where several can be ticked: get() / set(table or nil) the set, choices() = { { value, text } }
    local function MultiDropdown(name, width, label, many, anyText, choices, get, set)
        local dd = CreateFrame("Frame", name, panel, "UIDropDownMenuTemplate")
        _G.UIDropDownMenu_SetWidth(dd, width)
        dd.Refresh = function()
            local picked, one, chosen = 0, nil, get()
            for _, it in ipairs(choices()) do if chosen and chosen[it.value] then picked, one = picked + 1, it.short or it.text end end
            _G.UIDropDownMenu_SetText(dd, picked == 0 and label or (picked == 1 and one or (many .. picked)))
        end
        _G.UIDropDownMenu_Initialize(dd, function(_, level)
            local info = _G.UIDropDownMenu_CreateInfo()
            info.text, info.notCheckable = anyText, true
            info.func = function() set(nil) view.page = 1 dd.Refresh() RenderList() end
            _G.UIDropDownMenu_AddButton(info, level)
            for _, it in ipairs(choices()) do
                info = _G.UIDropDownMenu_CreateInfo()
                info.text, info.isNotRadio, info.keepShownOnClick = it.text, true, true
                info.checked = get() and get()[it.value] or false
                info.func = function()
                    local s = get() or {}
                    s[it.value] = (not s[it.value]) or nil
                    set(next(s) and s or nil)
                    view.page = 1
                    dd.Refresh() RenderList()
                end
                _G.UIDropDownMenu_AddButton(info, level)
            end
        end)
        dd.Refresh()
        return dd
    end
    local roleDD = MultiDropdown("JagodkaLFGRoleFilter", 70, "Role", "Roles: ", "Any role",
        function() return { { value = "TANK", text = "Tank" }, { value = "HEAL", text = "Healer" }, { value = "DPS", text = "DPS" } } end,
        function() return view.roles end, function(s) view.roles = s end)
    roleDD:SetPoint("LEFT", typeDD, "RIGHT", -28, 0)
    -- The guilds of the players on the board now, in the order of the guild tags, by the full name
    local guildDD = MultiDropdown("JagodkaLFGGuildFilter", 105, "Guild", "Guilds: ", "All guilds",
        function()
            local count, names, out = {}, {}, {}
            for _, l in ipairs(All()) do
                if l.guild then
                    if not count[l.guild] then table.insert(names, l.guild) end
                    count[l.guild] = (count[l.guild] or 0) + 1
                end
            end
            local Most = addonTable.Most
            table.sort(names, function(a, b)
                local ta, tb = Most.GuildTag(a) or a, Most.GuildTag(b) or b
                if #ta ~= #tb then return #ta < #tb end
                if ta ~= tb then return ta < tb end
                return a < b
            end)
            for _, g in ipairs(names) do table.insert(out, { value = g, text = g .. " |cff808080(" .. count[g] .. ")|r", short = g }) end
            return out
        end,
        function() return view.guilds end, function(s) view.guilds = s end)
    guildDD:SetPoint("LEFT", roleDD, "RIGHT", -28, 0)
    -- Class: one class, in the class color
    local classDD = CreateFrame("Frame", "JagodkaLFGClassFilter", panel, "UIDropDownMenuTemplate")
    _G.UIDropDownMenu_SetWidth(classDD, 75)
    local CLASSES = _G.CLASS_SORT_ORDER or { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
    local function ClassText(c)
        local name = _G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[c] or c
        local color = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[c]
        return color and color.colorStr and ("|c" .. color.colorStr .. name .. "|r") or name
    end
    classDD.Refresh = function() _G.UIDropDownMenu_SetText(classDD, view.class and ClassText(view.class) or "Class") end
    _G.UIDropDownMenu_Initialize(classDD, function(_, level)
        local info = _G.UIDropDownMenu_CreateInfo()
        info.text, info.checked = "Any class", view.class == nil
        info.func = function() view.class, view.page = nil, 1 classDD.Refresh() RenderList() end
        _G.UIDropDownMenu_AddButton(info, level)
        for _, c in ipairs(CLASSES) do
            if c ~= "DEATHKNIGHT" and c ~= "MONK" and c ~= "DEMONHUNTER" and c ~= "EVOKER" then
                info = _G.UIDropDownMenu_CreateInfo()
                info.text, info.checked = ClassText(c), view.class == c
                info.func = function() view.class, view.page = c, 1 classDD.Refresh() RenderList() end
                _G.UIDropDownMenu_AddButton(info, level)
            end
        end
    end)
    classDD.Refresh()
    classDD:SetPoint("LEFT", guildDD, "RIGHT", -28, 0)
    -- Reset: search, the filters, sorting and page (as in Members and Events), next to the search
    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(55, 22)
    reset:SetPoint("LEFT", search, "RIGHT", 8, 0)
    reset:SetText("Reset")
    -- searchText: what goes in the search box afterwards ([Open in LFG] links), or nothing
    function LFG.ResetView(searchText)
        view.actFilter, view.roles, view.guilds, view.class, view.sortKey, view.desc, view.page = nil, nil, nil, nil, nil, false, 1
        _G.UIDropDownMenu_SetText(typeDD, "Activity")
        roleDD.Refresh() guildDD.Refresh() classDD.Refresh()
        search:SetText(searchText or "")
        search:ClearFocus()
        _G.FauxScrollFrame_SetOffset(scroll, 0)
        RenderList()
    end
    reset:SetScript("OnClick", function() LFG.ResetView() end)
    -- The table
    panel.list = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    panel.list:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -100)   -- 0.15.6: room for the filter row
    panel.list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 30)
    ctx.applyStyle(panel.list)
    empty = panel.list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("CENTER", panel.list, "CENTER", 0, 0)
    empty:SetText("Nobody is looking for a group right now")
    columns = {
        { key = "name", title = "Player", sort = "name" }, { key = "level", title = "Lvl", sort = "level" }, { key = "guild", title = "Guild", sort = "guild" },
        { key = "roles", title = "Roles" }, { key = "acts", title = "Looking for" }, { key = "note", title = "Note" }, { key = "since", title = "Listed", sort = "since" },
    }
    for _, col in ipairs(columns) do
        local h = CreateFrame("Button", nil, panel.list)
        h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h.text:SetPoint("LEFT", h, "LEFT", 0, 0)
        h.text:SetText(col.title)
        h:SetScript("OnClick", function()
            if not col.sort then return end
            if view.sortKey ~= col.sort then view.sortKey, view.desc = col.sort, false
            elseif not view.desc then view.desc = true
            else view.sortKey, view.desc = nil, false end
            RenderList()
        end)
        col.header = h
    end
    scroll = CreateFrame("ScrollFrame", "JagodkaLFGScroll", panel.list, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel.list, "TOPLEFT", 0, -28)
    scroll:SetPoint("BOTTOMRIGHT", panel.list, "BOTTOMRIGHT", -26, 6)
    scroll:SetScript("OnVerticalScroll", function(self, off) _G.FauxScrollFrame_OnVerticalScroll(self, off, ROW_H, RenderList) end)
    for i = 1, 24 do
        local row = CreateFrame("Button", nil, panel.list)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", panel.list, "TOPLEFT", 5, -28 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", panel.list, "RIGHT", -25, 0)
        local bg = row:CreateTexture(nil, "BACKGROUND") bg:SetAllPoints() bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.02 or 0.04)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        for _, col in ipairs(columns) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetJustifyH("LEFT") fs:SetWordWrap(false)
            row[col.key] = fs
        end
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self, button)
            -- My own row: my listing's menu (change it or take it down); others: the Roster's menu
            if self.listing and self.listing == mine and button == "LeftButton" then
                -- Left click on my own row: edit my listing
                editor:Show()
            elseif button == "RightButton" and self.listing and self.listing == mine then
                _G.ToggleDropDownMenu(1, nil, panel.myMenu, "cursor", 0, 0)
            elseif button == "RightButton" and self.listing then
                -- Someone else: whisper, invite to the group, or invite to one of my events
                panel.otherMenu.target = self.listing
                _G.ToggleDropDownMenu(1, nil, panel.otherMenu, "cursor", 0, 0)
            elseif ctx.onRowClick then
                ctx.onRowClick(self, button)
            end
        end)
        row:SetScript("OnEnter", ShowTooltip)
        row:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
        rows[i] = row
    end
    -- Page bar as in Roster and Events
    nav = CreateFrame("Frame", nil, panel)
    nav:SetHeight(26)
    nav:SetPoint("TOPLEFT", panel.list, "BOTTOMLEFT", 0, -4)
    nav:SetPoint("TOPRIGHT", panel.list, "BOTTOMRIGHT", 0, -4)
    nav.info = nav:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nav.info:SetPoint("LEFT", nav, "LEFT", 8, 0)
    nav.page = nav:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nav.page:SetWidth(90)
    nav.buttons = {}
    for i, label in ipairs({ "<<", "<", ">", ">>" }) do
        local b = CreateFrame("Button", nil, nav, "UIPanelButtonTemplate")
        b:SetSize(30, 20)
        b:SetText(label)
        b:SetScript("OnClick", function()
            local pages = math.max(1, math.ceil(#Sorted() / PER_PAGE))
            view.page = math.max(1, math.min(pages, ({ 1, view.page - 1, view.page + 1, pages })[i]))
            _G.FauxScrollFrame_SetOffset(scroll, 0)
            RenderList()
        end)
        nav.buttons[i] = b
    end
    nav.buttons[4]:SetPoint("RIGHT", nav, "RIGHT", -4, 0)
    nav.buttons[3]:SetPoint("RIGHT", nav.buttons[4], "LEFT", -2, 0)
    nav.page:SetPoint("RIGHT", nav.buttons[3], "LEFT", -4, 0)
    nav.buttons[2]:SetPoint("RIGHT", nav.page, "LEFT", -4, 0)
    nav.buttons[1]:SetPoint("RIGHT", nav.buttons[2], "LEFT", -2, 0)
    panel.list:SetScript("OnSizeChanged", function(self)
        self.visibleRows = math.max(1, math.min(24, math.floor((self:GetHeight() - 34) / ROW_H)))
        Layout()
        RenderList()
    end)
    BuildEditor(panel)
    -- Right click on someone else's row: whisper, group invite, and "Invite to my event" (my upcoming events):
    -- a whisper with an [Open event] link, so they sign up themselves (only players sign up themselves)
    panel.otherMenu = CreateFrame("Frame", "JagodkaLFGOtherMenu", _G.UIParent, "UIDropDownMenuTemplate")
    _G.UIDropDownMenu_Initialize(panel.otherMenu, function(_, level, menuList)
        local target = panel.otherMenu.target
        if not target then return end
        local Most = addonTable.Most
        local function Add(text, func, extra)
            local info = _G.UIDropDownMenu_CreateInfo()
            info.text, info.notCheckable, info.func = text, true, func
            for k, v in pairs(extra or {}) do info[k] = v end
            _G.UIDropDownMenu_AddButton(info, level)
        end
        if level == 2 then
            for _, ev in ipairs(menuList or {}) do
                Add(ev.title .. " |cff808080" .. tostring(ev.date):gsub("^(%d+%.%d+)%.%d+$", "%1") .. " " .. tostring(ev.time) .. "|r", function()
                    LFG.InviteToEvent(target.name, ev)
                    _G.CloseDropDownMenus()
                end)
            end
            return
        end
        Add(target.name, nil, { isTitle = true })
        -- Offline (relog, reload): whisper and invites wait until they are back
        local offline = target.offlineSince ~= nil
        Add(offline and "Whisper (offline)" or "Whisper", function() _G.ChatFrame_SendTell(Most.GameName(target.name)) end, { disabled = offline })
        Add(offline and "Invite to group (offline)" or "Invite to group", function()
            local invite = (_G.C_PartyInfo and _G.C_PartyInfo.InviteUnit) or _G.InviteUnit
            if invite then invite(Most.GameName(target.name)) end
        end, { disabled = offline })
        local mineEvents = LFG.MyUpcomingEvents()
        if offline then
            Add("Invite to my event |cff808080(offline)|r", nil, { disabled = true })
        elseif #mineEvents > 0 then
            Add("Invite to my event", nil, { hasArrow = true, menuList = mineEvents })
        else
            Add("Invite to my event |cff808080(you have none)|r", nil, { disabled = true })
        end
        Add("Cancel", function() _G.CloseDropDownMenus() end)
    end, "MENU")
    -- Right click on my own row
    panel.myMenu = CreateFrame("Frame", "JagodkaLFGMyMenu", _G.UIParent, "UIDropDownMenuTemplate")
    _G.UIDropDownMenu_Initialize(panel.myMenu, function(_, level)
        local info = _G.UIDropDownMenu_CreateInfo()
        info.text, info.isTitle, info.notCheckable = "My listing", true, true
        _G.UIDropDownMenu_AddButton(info, level)
        info = _G.UIDropDownMenu_CreateInfo()
        info.text, info.notCheckable = "Change my listing", true
        info.func = function() editor:Show() end
        _G.UIDropDownMenu_AddButton(info, level)
        info = _G.UIDropDownMenu_CreateInfo()
        info.text, info.notCheckable = "|TInterface\\Buttons\\UI-GroupLoot-Pass-Up:14:14:0:0|t Remove my listing", true
        info.func = function() LFG.RemoveMine() editor:Hide() RenderList() end
        _G.UIDropDownMenu_AddButton(info, level)
        info = _G.UIDropDownMenu_CreateInfo()
        info.text, info.notCheckable = "Cancel", true
        info.func = function() _G.CloseDropDownMenus() end
        _G.UIDropDownMenu_AddButton(info, level)
    end, "MENU")
    panel:SetScript("OnShow", function() Layout() RenderList() end)
    -- [Open in LFG] links (bridge.lua builds them): the game hands every link click to SetItemRef; the
    -- "garrmission" type is one the game ignores by itself, so only this hook reacts to it
    _G.hooksecurefunc("SetItemRef", function(link)
        if type(link) ~= "string" then return end
        local name = link:match("^garrmission:jagodkalfg:(.+)$")
        if name then LFG.Open(name) return end
        -- [Open event] from an event invitation whisper
        local id = link:match("^garrmission:jagodkaev:(.+)$")
        if id and addonTable.OpenEvent and not addonTable.OpenEvent(id) and _G.DEFAULT_CHAT_FRAME then
            _G.DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[Jagodka]: This event is not in your list yet - wait a moment for the sync, or use Sync in the Events tab.|r")
        end
    end)
    -- Event invitation whispers (both received and sent): the marker becomes the [Open event] link
    if _G.ChatFrame_AddMessageEventFilter then
        local function EventLinks(_, _, msg, ...)
            if addonTable.Most.IsSecret(msg) or type(msg) ~= "string" or not msg:find("<jn%-event:", 1) then return false end
            local text = msg:gsub("<jn%-event:([%w]+)>", function(id) return "|cff6cc4e6|Hgarrmission:jagodkaev:" .. id .. "|h[Open event]|h|r" end)
            return false, text, ...
        end
        _G.ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", EventLinks)
        _G.ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", EventLinks)
    end
    -- Sync: asks the guild for the current listings (as after login); gray for REQUEST_COOLDOWN after a click
    local syncBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    syncBtn:SetSize(70, 28)
    syncBtn:SetPoint("RIGHT", panel.myBtn, "LEFT", -4, 0)
    syncBtn:SetText("Sync")
    local syncReadyAt = 0
    syncBtn:SetScript("OnClick", function(self)
        if GetTime() < syncReadyAt then return end
        LFG.Request(true)
        syncReadyAt = GetTime() + REQUEST_COOLDOWN
    end)
    addonTable.SafeScript(syncBtn, "OnUpdate", "lfg.lua:1110", function(self)
        local left = math.ceil(syncReadyAt - GetTime())
        if left > 0 then self:SetText("Sync (" .. left .. ")") self:Disable() else self:SetText("Sync") self:Enable() end
    end)
    if syncBtn.SetMotionScriptsWhileDisabled then syncBtn:SetMotionScriptsWhileDisabled(true) end
    syncBtn:SetScript("OnEnter", function(self)
        _G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
        _G.GameTooltip:SetText("Asks for the current LFG listings, as after login.\nAt most once a minute.", 1, 1, 1, 1, true)
        _G.GameTooltip:Show()
    end)
    syncBtn:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
    -- After login: the request (core.lua's login sync calls LFG.Request) and my listing from before
    local loginWatch = CreateFrame("Frame")
    loginWatch:RegisterEvent("PLAYER_LOGIN")
    addonTable.SafeScript(loginWatch, "OnEvent", "lfg.lua:1124", function()
        -- The guild is known a moment after login; without it the listing cannot go out yet, so it waits
        local tries = 0
        local function Try()
            tries = tries + 1
            if InGuild() or tries >= 6 then RestoreMine() else addonTable.SafeTimer.After(10, Try) end
        end
        addonTable.SafeTimer.After(20, Try)
    end)
    addonTable.SafeTimer.NewTicker(60, function() Prune() end)
    -- Heartbeat: my listing again every HEARTBEAT, the same one (same time), so the others keep it
    addonTable.SafeTimer.NewTicker(HEARTBEAT, function() if mine then SendMine() end end)
    -- "Listed N min" keeps counting while the tab is open
    addonTable.SafeTimer.NewTicker(30, function() if panel:IsVisible() then RenderList() end end)
end
