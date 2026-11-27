-- ============================================================================
-- EVENTS: data, rules and sync of the events (the Events and Calendar tabs in core.lua show them)
-- ============================================================================
--  * Rules, checked by the author's client AND by every receiver:
--    - any member of a listed guild creates events: a member at most MEMBER_ACTIVE active ones, an officer
--      OFFICER_ACTIVE (active = its start is still ahead);
--    - the author and officers (by the guild rosters) edit, cancel and take players off an event;
--    - everyone signs up only themselves: a spec of their class, status Coming / Maybe / Not coming;
--    - an event disappears by itself LIVE_AFTER_START after its start, the same moment everywhere, no packet.
--  * Every change is one small packet to GUILD (the relays pass it on to other guilds, high priority):
--      EH id:rev:editor:creator:guild:title:date:time:instance:parts   event header (rev = server time)
--      ED id:rev:part:text                                             rest of the description
--      ES id:name:role:spec:status:leader:time                         one player's sign-up
--      EK id:name:time:by                                              a player taken off the event
--      EX id:time:by                                                   event cancelled
--    A live packet must come from the person it names (author, editor, player, remover); a sync answer
--    (whisper) may carry anyone's change, but the rules above still apply to the person it names.
--  * Sync after login (and the Sync button): EQ with the time of the newest change we know (minus a margin).
--    A few random guildmates may answer (never the relay when anyone else can), the first sends EC and
--    whispers ONLY the changes newer than that time, low priority. A player who was online yesterday gets a
--    handful of packets instead of every event and every sign-up. The same asker is answered at most every
--    ANSWER_COOLDOWN seconds.
--  * New packet types: versions before 0.14.0 (EV_*) and this one do not see each other's events.
--  * A reminder REMIND_BEFORE seconds before the start of events I am signed up for (Coming / Maybe).
--  * 1.3.0 WEEKLY EVENTS: the same event every week at the same time, up to about 2 months.
--    - Marked in the id, which never changes: "w" .. occurrences N (2-9) .. the week K (0-7) of the first one
--      after creating it .. the usual id (creation time in hex + 2 random hex digits). No new packet and no new
--      field, so 1.2.3 and older show it as an ordinary event (only its nearest date: they drop it after it is
--      over, as any event).
--    - Each client moves it on by itself, the same moment everywhere, no packet: LIVE_AFTER_START after an
--      occurrence started, its date goes 7 days on and its sign-ups and removals are cleared (a new week).
--      No occurrence starts after creation + (K + N) weeks: after the last one it goes as any event.
--    - K + N <= RECUR_SPAN weeks (9, about 2 months): the last occurrence is at most about 2 months ahead.
--    - Limits on top of the usual ones: a member RECUR_MEMBER weekly event, an officer RECUR_OFFICER. Every
--      receiver checks them (as the usual limits); clients before 1.3.0 count it as an ordinary event.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_Timer = addonTable.SafeTimer -- protected callbacks (safe.lua)
local CreateFrame = _G.CreateFrame
local GetServerTime = _G.GetServerTime
local GetTime = _G.GetTime
local strsplit = _G.strsplit
local ipairs, pairs, tostring, tonumber, type, next = _G.ipairs, _G.pairs, _G.tostring, _G.tonumber, _G.type, _G.next
local table, math, string = _G.table, _G.math, _G.string
local date, time = _G.date, _G.time

local Most = addonTable.Most
local Enc, Dec = Most.EncodeField, Most.DecodeField

local MEMBER_ACTIVE, OFFICER_ACTIVE = 1, 5
local LIVE_AFTER_START = 5 * 3600     -- an event stays this long after its start (fresh players, things run late)
local REMOVED_KEEP = 23 * 86400       -- cancelled ids kept this long (events can be up to 21 days ahead)
local SYNC_MARGIN = 600               -- the sync asks for changes this many seconds before our newest one
local ANSWER_COOLDOWN = 120           -- the same asker gets our answer at most this often (s)
-- 1.3.1 (user: "ludzie nie widzą eventów i się kiepsko synchronizują", JN3)
local HOLD_FOR, HOLD_MAX, HOLD_EXTRA = 600, 30, 60  -- an event whose author is not known yet waits up to HOLD_FOR s (at most HOLD_MAX events, HOLD_EXTRA packets each)
local HOLD_RETRY = 10                 -- held events are tried again this often (s)
local PULL_MIN_VERSION = "1.3.1"      -- only relays with this version or newer know the pull (EG)
local PULL_COOLDOWN = 600             -- a new relay asks the other guilds at most this often (s)
local PULL_ANSWER_COOLDOWN = 300      -- the same relay gets our pull answer at most this often (s)
local PULL_WINDOW = 900               -- the answers to my pull are passed on to my guild this long (s)
local REQUEST_COOLDOWN = 60           -- our own requests at most this often, unless forced (s)
local REMIND_BEFORE = 15 * 60
local DESC_MAX = 400                  -- description bytes
local DESC_PART = 170                 -- encoded description bytes per packet
local TITLE_MAX = 50
local WEEK = 7 * 86400
local RECUR_MEMBER, RECUR_OFFICER = 1, 5   -- weekly events on top of the usual limit (1.3.0)
local RECUR_MIN, RECUR_MAX = 2, 9          -- occurrences of a weekly event
local RECUR_SPAN = 9                       -- weeks from creating it to its last occurrence's week (about 2 months)
local REMOVED_KEEP_WEEKLY = 80 * 86400     -- a cancelled weekly event is remembered longer than it can live

local Events = {}
addonTable.Events = Events
Events.DESC_MAX, Events.TITLE_MAX = DESC_MAX, TITLE_MAX
Events.MEMBER_ACTIVE, Events.OFFICER_ACTIVE = MEMBER_ACTIVE, OFFICER_ACTIVE
Events.RECUR_MEMBER, Events.RECUR_OFFICER, Events.RECUR_MIN, Events.RECUR_MAX = RECUR_MEMBER, RECUR_OFFICER, RECUR_MIN, RECUR_MAX
Events.RECUR_SPAN = RECUR_SPAN
Events.LIVE_AFTER_START, Events.WEEK = LIVE_AFTER_START, WEEK

-- Statuses of a sign-up; X = withdrawn
local STATUSES = { Y = "Coming", M = "Maybe", N = "Not coming" }
Events.STATUSES = STATUSES
local VALID_ROLES = { TANK = true, HEAL = true, DPS = true }

-- Context from core.lua: isMeOfficer(), isKnownOfficer(name), specs (code -> spec), classRoles,
-- onChanged(ev), onRemoved(index)
local ctx = nil
function Events.Init(c) ctx = c end

local db = { removed = {} }   -- JagodkiEventsDB: the events (array part), v = 2, removed = { id -> { ts, by } }
local pending = {}            -- asker -> true while we wait to answer
local answeredAt = {}         -- asker -> when we last answered
local lastRequest = -REQUEST_COOLDOWN
local reminded = {}           -- event id -> true once reminded this session
local unknownNoted = {}       -- event id -> true once its unknown author is in the log (1.3.1)
local held, heldCount, retrying = {}, 0, false   -- 1.3.1: event id -> { creator, rev, payload, sender, live, at, extra = { packets } }
local changes = 0             -- 1.3.1: counts every applied change (Changed, Remove), to see whether a packet changed anything
local pullFrom = {}           -- 1.3.1: relay of another guild -> until when its answers to my pull go on to my guild
local pullAnsweredAt = {}     -- 1.3.1: asking relay -> when we last answered its pull
local lastPull, wasRelay = -PULL_COOLDOWN, false

local function Monitor() return addonTable.Monitor end
local function MyName() return Most.MyName() end
local function Activity() if addonTable.Sync then addonTable.Sync.Activity("events") end end

-- ============================================================================
-- DATA
-- ============================================================================
-- Old events (before 0.14.0) are dropped: they were unused and their rules differ
function Events.Load()
    local saved = _G.JagodkiEventsDB
    if type(saved) ~= "table" or saved.v ~= 2 then saved = { v = 2, removed = {} } end
    saved.removed = saved.removed or {}
    -- 1.3.0: test events from the pre-release test build (/jagodka weeklytest, removed) are dropped
    for i = #saved, 1, -1 do if type(saved[i]) == "table" and saved[i].localTest then table.remove(saved, i) end end
    _G.JagodkiEventsDB = saved
    db = saved
    Events.Prune()
    return db
end

function Events.List() return db end

local function Find(id)
    for i, ev in ipairs(db) do if ev.id == id then return ev, i end end
    return nil
end
Events.Find = Find

-- Start of an event (local time), from "DD.MM.YYYY" and "HH:MM"
function Events.Start(ev)
    local d, m, y = (ev.date or ""):match("^(%d%d?)%.(%d%d?)%.(%d%d%d%d)$")
    local h, mi = (ev.time or ""):match("^(%d%d?):(%d%d)$")
    if not d or not h then return nil end
    return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = tonumber(h), min = tonumber(mi) })
end

local function IsOver(ev)
    local start = Events.Start(ev)
    return start ~= nil and time() > start + LIVE_AFTER_START
end

local function IsActive(ev)
    local start = Events.Start(ev)
    return start ~= nil and start > time()
end

-- 1.3.0 WEEKLY EVENTS (see the top): occurrences N, creation time and the week K of the first occurrence from
-- the id, or nil for an ordinary event
local function Series(id)
    local n, k, hex = tostring(id or ""):match("^w(%d)(%d)(%x+)$")
    n, k = tonumber(n), tonumber(k)
    if not n or not k or n < RECUR_MIN or n > RECUR_MAX or k + n > RECUR_SPAN or #hex < 3 then return nil end
    local created = tonumber(hex:sub(1, -3), 16)
    if not created then return nil end
    return n, created, k
end
function Events.IsWeekly(ev) return ev ~= nil and Series(ev.id) ~= nil end

-- No occurrence of a weekly event starts after this
local function SeriesEnd(id)
    local n, created, k = Series(id)
    return n and (created + (k + n) * WEEK) or nil
end

-- The week (0, 1, 2...) after `created` in which an event starting at `start` falls: (created + K weeks, + K+1]
local function WeekIndex(created, start) return math.max(0, math.ceil((start - created) / WEEK) - 1) end

-- How many times an event starting at `start` (local time) can repeat if created now: 0 = it cannot be weekly
function Events.MaxRepeats(start)
    if not start then return 0 end
    local n = RECUR_SPAN - WeekIndex(GetServerTime(), start)
    return (n >= RECUR_MIN) and math.min(n, RECUR_MAX) or 0
end

-- The same day of the next week ("DD.MM.YYYY")
local function NextDate(eDate)
    local d, m, y = (eDate or ""):match("^(%d%d?)%.(%d%d?)%.(%d%d%d%d)$")
    if not d then return nil end
    return date("%d.%m.%Y", time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) + 7, hour = 12 }))
end

-- The date of the occurrence that is on now or next: the same date, a later one (weekly), or nil when it is over
local function CurrentDate(id, eDate, eTime)
    local probe = { date = eDate, time = eTime }
    if not Events.Start(probe) then return nil end
    local last = SeriesEnd(id)
    for _ = 1, 60 do
        if not IsOver(probe) then return probe.date end
        if not last then return nil end
        probe.date = NextDate(probe.date)
        local start = probe.date and Events.Start(probe)
        if not start or start > last then return nil end
    end
    return nil
end

-- Sign-ups and removals older than this belong to an earlier week of a weekly event (0: none can)
local function WeekFloor(ev)
    local n, created, k = Series(ev.id)
    local start = n and Events.Start(ev)
    -- The first occurrence (in week K) has no week before it
    if not start or start <= created + (k + 1) * WEEK then return 0 end
    return start - WEEK + LIVE_AFTER_START
end

-- Whether a weekly event's new date is whole weeks after its date, at the same time (a skipped week, see
-- Events.SkipWeek): its sign-ups were for another week then
local function WeeksMoved(ev, newDate, newTime)
    if not Series(ev.id) or newTime ~= ev.time then return false end
    local a = Events.Start({ date = ev.date, time = "12:00" })
    local b = Events.Start({ date = newDate, time = "12:00" })
    if not a or not b or b <= a then return false end
    return math.floor((b - a) / 86400 + 0.5) % 7 == 0
end

-- The later occurrences of a weekly event after the current one, as dates ("DD.MM.YYYY"); the calendar shows them
function Events.NextDates(ev)
    local out, last = {}, SeriesEnd(ev and ev.id)
    if not last then return out end
    local probe = { date = ev.date, time = ev.time }
    for _ = 1, RECUR_MAX do
        probe.date = NextDate(probe.date)
        local start = probe.date and Events.Start(probe)
        if not start or start > last then break end
        table.insert(out, probe.date)
    end
    return out
end

-- "Every Tuesday 20:00, last on 20.01" for a weekly event, or nil
local DAY_NAMES = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
function Events.RepeatText(ev)
    if not Events.IsWeekly(ev) then return nil end
    local start = Events.Start(ev)
    if not start then return nil end
    local later = Events.NextDates(ev)
    local lastDate = later[#later] or ev.date
    return "Every " .. DAY_NAMES[tonumber(date("%w", start)) + 1] .. " " .. tostring(ev.time)
        .. ", " .. ((#later == 0) and "last time" or ("last on " .. lastDate:gsub("%.%d%d%d%d$", "")))
end

local function IsOfficer(name)
    if not ctx then return false end
    if name == MyName() then return ctx.isMeOfficer() end
    return ctx.isKnownOfficer(name)
end

-- How many active events the player may have, and how many they have (except the event `except`)
local function ActiveCount(creator, except)
    local n = 0
    for _, ev in ipairs(db) do
        if ev.creator == creator and ev.id ~= except and not Series(ev.id) and IsActive(ev) then n = n + 1 end
    end
    return n
end
local function ActiveLimit(creator) return IsOfficer(creator) and OFFICER_ACTIVE or MEMBER_ACTIVE end

-- 1.3.0: weekly events count apart (all of them, also the one going on now: the series goes on)
local function WeeklyCount(creator, except)
    local n = 0
    for _, ev in ipairs(db) do
        if ev.creator == creator and ev.id ~= except and Series(ev.id) and not ev.localTest then n = n + 1 end
    end
    return n
end
local function WeeklyLimit(creator) return IsOfficer(creator) and RECUR_OFFICER or RECUR_MEMBER end

-- 1.3.1: a signed-up player who is in none of our guilds any more (user: "jak ktoś już nie jest w gildii, to go
-- z automatu wywala z eventów"): on no roster of a listed guild and not online with the addon in one. Only once
-- the rosters are here (mine lists me), so nobody drops out right after login.
local function LeftCommunity(name)
    if not name or name == MyName() or not addonTable.Roster then return false end
    if not addonTable.Roster.FindMember(MyName()) then return false end
    return Most.FindKnownPlayer(name) == nil
end

-- The views the windows use: roster (name -> role, Coming and Maybe), specs, leaders, status (name -> Y/M/N).
-- 1.3.1: without players who left our guilds (LeftCommunity). Their sign-up stays in the data (and in sync
-- answers), so a player back in a guild, or one a late roster brings, shows again.
local function Rebuild(ev)
    ev.roster, ev.specs, ev.leaders, ev.status = {}, {}, {}, {}
    for name, s in pairs(ev.signs or {}) do
        if not LeftCommunity(name) then
            if s.st == "Y" or s.st == "M" then
                ev.roster[name] = s.r
                ev.specs[name] = s.s
                if s.l then ev.leaders[name] = true end
            end
            if s.st ~= "X" then ev.status[name] = s.st end
        end
    end
end

-- 1.3.1: once a minute (Prune): who left our guilds meanwhile drops out of the lists, who came back shows again
local function RebuildIfLeft(ev)
    local before = 0
    for _ in pairs(ev.status or {}) do before = before + 1 end
    Rebuild(ev)
    local after = 0
    for _ in pairs(ev.status) do after = after + 1 end
    return before ~= after
end

local function Changed(ev) changes = changes + 1 if ctx then ctx.onChanged(ev) end end

local function Remove(id, ts, by)
    changes = changes + 1
    db.removed[id] = { ts = ts or GetServerTime(), by = by }
    local _, idx = Find(id)
    if idx then
        table.remove(db, idx)
        if ctx then ctx.onRemoved(idx) end
    end
end

-- Over events (start + LIVE_AFTER_START) and old cancellations go; checked every minute.
-- 1.3.0: a weekly event moves on to its next week instead (sign-ups and removals cleared), until its last one.
function Events.Prune()
    for i = #db, 1, -1 do
        local ev = db[i]
        if IsOver(ev) then
            local current = CurrentDate(ev.id, ev.date, ev.time)
            if current then
                ev.date, ev.signs, ev.kicks = current, {}, {}
                Rebuild(ev)
                Changed(ev)
            else
                table.remove(db, i)
                if ctx then ctx.onRemoved(i) end
            end
        elseif RebuildIfLeft(ev) then
            Changed(ev)
        end
    end
    local now = GetServerTime()
    for id, r in pairs(db.removed) do
        local keep = Series(id) and REMOVED_KEEP_WEEKLY or REMOVED_KEEP
        if type(r) ~= "table" or now - (r.ts or 0) > keep then db.removed[id] = nil end
    end
end

-- ============================================================================
-- PERMISSIONS (the windows use these too)
-- ============================================================================
local function InListedGuild() return Most.IsGuildAllowed(Most.MyGuild()) end

function Events.CanManage(ev) return ev ~= nil and (ev.creator == MyName() or (ctx ~= nil and ctx.isMeOfficer())) end

function Events.CanInvite(ev)
    return Events.CanManage(ev) or (ev ~= nil and ev.leaders and ev.leaders[MyName()] and true or false)
end

-- Whether I can create one more event: ok, or false and the reason. weekly (1.3.0): one more weekly event.
function Events.CanCreate(weekly)
    if not InListedGuild() then return false, "Your guild is not on the Community list." end
    local me = MyName()
    if weekly then
        local wl = WeeklyLimit(me)
        if WeeklyCount(me) >= wl then
            return false, (wl == 1) and "You already have a weekly event (officers: up to 5)." or ("You already have " .. wl .. " weekly events.")
        end
        return true
    end
    local limit = ActiveLimit(me)
    if ActiveCount(me) >= limit then
        return false, (limit == 1) and "You already have an upcoming event. A new one when it has started (officers: up to 5)."
            or ("You already have " .. limit .. " upcoming events.")
    end
    return true
end

-- The creator window opens when either kind can still be made (an ordinary or a weekly event)
function Events.CanCreateAny()
    local ok, why = Events.CanCreate()
    if ok or Events.CanCreate(true) then return true end
    return false, why
end

-- ============================================================================
-- SENDING
-- ============================================================================
local function Out(pType, payload, target, priority)
    if target then Most.Whisper(target, pType, payload, priority or "low")
    elseif InListedGuild() then
        Most.Send(pType, payload, priority or "high")
        -- 1.1.3: also straight to the other guilds' relays (as announcements), so an event does not depend on my
        -- guild's relay (18.11: a JN3 event never reached the other guilds). A second copy is dropped by revision.
        if Most.ToOtherGuilds then Most.ToOtherGuilds(pType, payload) end
    end
end

local function SendHeader(ev, target)
    if ev.localTest then return end   -- a test event of the pre-release build: never sent
    local chunks = Most.EncodeChunks(ev.desc or "", DESC_PART, DESC_PART)
    if #chunks == 1 and chunks[1] == "" then chunks = {} end
    Out("EH", table.concat({ Enc(ev.id), tostring(ev.rev), Enc(ev.editor ~= ev.creator and ev.editor or ""), Enc(ev.creator), Enc(ev.guild),
        Enc(ev.title), Enc(ev.date), Enc(ev.time), Enc(ev.dungeon or ""), tostring(#chunks) }, ":"), target)
    for i, chunk in ipairs(chunks) do Out("ED", Enc(ev.id) .. ":" .. ev.rev .. ":" .. i .. ":" .. chunk, target) end
end

local function SendSign(ev, name, target)
    if ev.localTest then return end
    local s = ev.signs and ev.signs[name]
    if not s then return end
    Out("ES", table.concat({ Enc(ev.id), Enc(name), s.r or "-", s.s or "-", s.st, s.l and "1" or "0", tostring(s.t) }, ":"), target)
end

local function SendKick(ev, name, target)
    if ev.localTest then return end
    local k = ev.kicks and ev.kicks[name]
    if k then Out("EK", table.concat({ Enc(ev.id), Enc(name), tostring(k.ts), Enc(k.by) }, ":"), target) end
end

-- ============================================================================
-- MY CHANGES (windows in core.lua); each returns ok, or false and the reason
-- ============================================================================
local function NewId()
    return string.format("%x%02x", GetServerTime(), math.random(0, 255))
end

local function Valid(title, eDate, eTime)
    if not title or title == "" then return false, "Enter an event name or pick an instance." end
    local ev = { date = eDate, time = eTime }
    local start = Events.Start(ev)
    if not start then return false, "Pick a date and time." end
    if start + LIVE_AFTER_START < time() then return false, "This time has already passed." end
    return true
end

-- weeks (1.3.0): RECUR_MIN..RECUR_MAX = a weekly event with that many occurrences, nil = once
function Events.Create(title, eDate, eTime, dungeon, desc, weeks)
    weeks = tonumber(weeks)
    local weekly = weeks ~= nil and weeks >= RECUR_MIN
    if weekly then weeks = math.min(math.floor(weeks), RECUR_MAX) end
    local ok, why = Events.CanCreate(weekly)
    if not ok then return false, why end
    ok, why = Valid(title, eDate, eTime)
    if not ok then return false, why end
    if not IsActive({ date = eDate, time = eTime }) then return false, "Pick a time in the future." end
    local id = NewId()
    if weekly then
        -- The last time at most about 2 months ahead (RECUR_SPAN weeks from now)
        local start = Events.Start({ date = eDate, time = eTime })
        local most = Events.MaxRepeats(start)
        if most < RECUR_MIN then return false, "This date is too far ahead for a weekly event." end
        if weeks > most then return false, "From this date a weekly event can repeat at most " .. most .. " times (about 2 months ahead)." end
        local created = GetServerTime()
        id = string.format("w%d%d%x%02x", weeks, WeekIndex(created, start), created, math.random(0, 255))
    end
    local me = MyName()
    local ev = { id = id, rev = GetServerTime(), title = title, date = eDate, time = eTime, dungeon = dungeon, desc = desc or "",
        creator = me, editor = me, guild = Most.MyGuild(), signs = {}, kicks = {} }
    Rebuild(ev)
    table.insert(db, ev)
    SendHeader(ev)
    Changed(ev)
    return true, ev
end

function Events.Edit(ev, title, eDate, eTime, dungeon, desc)
    if not Find(ev.id) then return false, "This event no longer exists." end
    if not Events.CanManage(ev) then return false, "Only the author and officers can edit this event." end
    local ok, why = Valid(title, eDate, eTime)
    if not ok then return false, why end
    -- A weekly event moves within its series only: its end stays (it is in the id)
    local last = SeriesEnd(ev.id)
    if last and Events.Start({ date = eDate, time = eTime }) > last then
        return false, "This weekly event can only move up to " .. date("%d.%m", last) .. " (its series ends then)."
    end
    -- Moved by whole weeks: its sign-ups were for another week (every 1.3.0+ client does the same, HandleHeader)
    if WeeksMoved(ev, eDate, eTime) then ev.signs, ev.kicks = {}, {} Rebuild(ev) end
    ev.title, ev.date, ev.time, ev.dungeon, ev.desc = title, eDate, eTime, dungeon, desc or ""
    ev.rev, ev.editor = math.max(GetServerTime(), (ev.rev or 0) + 1), MyName()
    ev.descParts = nil
    SendHeader(ev)
    Changed(ev)
    return true
end

function Events.Cancel(ev)
    if not Find(ev.id) then return false, "This event no longer exists." end
    if not Events.CanManage(ev) then return false, "Only the author and officers can cancel this event." end
    local ts = GetServerTime()
    if ev.localTest then
        -- A test event: gone here only, nothing sent and no cancellation remembered
        local _, idx = Find(ev.id)
        if idx then table.remove(db, idx) if ctx then ctx.onRemoved(idx) end end
        return true
    end
    Out("EX", table.concat({ Enc(ev.id), tostring(ts), Enc(MyName()) }, ":"))
    Remove(ev.id, ts, MyName())
    return true
end

-- 1.3.0: an edit that changes a weekly event's date, time or repeat, or makes an event weekly or not weekly
-- (user: "czemu to jest zablokowane", "jak jest edit ze zmianą daty, to zapisy powinny się wyczyścić"): the id
-- holds the series, so it becomes a new event (same author, guild, title, instance, description; sign-ups start
-- empty) and the old one is cancelled first. Every version gets that (a cancellation and a new event). The
-- author's limits count without the old one. Returns ok, and the new event or the reason.
function Events.Replace(ev, title, eDate, eTime, dungeon, desc, weeks)
    if not Find(ev.id) then return false, "This event no longer exists." end
    if not Events.CanManage(ev) then return false, "Only the author and officers can edit this event." end
    weeks = tonumber(weeks)
    local weekly = weeks ~= nil and weeks >= RECUR_MIN
    if weekly then weeks = math.min(math.floor(weeks), RECUR_MAX) end
    local ok, why = Valid(title, eDate, eTime)
    if not ok then return false, why end
    local start = Events.Start({ date = eDate, time = eTime })
    if start <= time() then return false, "Pick a time in the future." end
    local id = NewId()
    if weekly then
        local most = Events.MaxRepeats(start)
        if most < RECUR_MIN then return false, "This date is too far ahead for a weekly event." end
        if weeks > most then return false, "From this date a weekly event can repeat at most " .. most .. " times (about 2 months ahead)." end
        if not ev.localTest and WeeklyCount(ev.creator, ev.id) >= WeeklyLimit(ev.creator) then
            return false, "The author already has " .. WeeklyLimit(ev.creator) .. " weekly event(s)."
        end
        local created = GetServerTime()
        id = string.format("w%d%d%x%02x", weeks, WeekIndex(created, start), created, math.random(0, 255))
    elseif not ev.localTest and ActiveCount(ev.creator, ev.id) >= ActiveLimit(ev.creator) then
        return false, "The author already has " .. ActiveLimit(ev.creator) .. " upcoming event(s)."
    end
    ok, why = Events.Cancel(ev)
    if not ok then return false, why end
    local new = { id = id, rev = GetServerTime(), title = title, date = eDate, time = eTime, dungeon = dungeon, desc = desc or "",
        creator = ev.creator, editor = MyName(), guild = ev.guild, signs = {}, kicks = {}, localTest = ev.localTest }
    Rebuild(new)
    table.insert(db, new)
    SendHeader(new)
    Changed(new)
    return true, new
end

-- 1.3.0: a weekly event without its nearest week (user: "zapytaj, czy tylko tego razu, czy całej sekwencji, jak
-- w Outlooku"): an ordinary edit that moves it to its next week, so every version gets it (older ones as an
-- edit). Every 1.3.0+ client clears the sign-ups when a weekly event moves by whole weeks (WeeksMoved). Its last
-- week: the whole series is cancelled. Returns ok, why, and "week" or "series".
function Events.SkipWeek(ev)
    if not Find(ev.id) then return false, "This event no longer exists." end
    if not Events.CanManage(ev) then return false, "Only the author and officers can cancel this event." end
    if not Events.IsWeekly(ev) then return false, "This event does not repeat." end
    local nextDate = NextDate(ev.date)
    local last = SeriesEnd(ev.id)
    local start = nextDate and Events.Start({ date = nextDate, time = ev.time })
    if not start or start > last then
        local ok, why = Events.Cancel(ev)
        return ok, why, "series"
    end
    ev.date, ev.signs, ev.kicks = nextDate, {}, {}
    Rebuild(ev)
    ev.rev, ev.editor = math.max(GetServerTime(), (ev.rev or 0) + 1), MyName()
    ev.descParts = nil
    SendHeader(ev)
    Changed(ev)
    return true, nil, "week"
end

-- My sign-up: spec (nil = keep the current one), status Y/M/N/X (nil = keep, Coming when new), leader (nil = keep)
-- 0.15.6: signing up (Coming or Maybe, from not signed up) posts a short notice on the community LFG chat, so
-- everyone sees something is going on: "Signed up for Molten Core (15.11 20:00) as Heal - 12 coming <jn-event:id>".
-- Sent from the menu click (the game wants a click for channel messages); each client turns the marker into an
-- [Open event] link (bridge.lua). At most once per event per SIGN_NOTICE_EVERY, so switching specs is not spam.
local SIGN_NOTICE_EVERY = 600
local signNoticeAt = {}             -- event id -> GetTime()
local function SignNotice(ev, s)
    local Most = addonTable.Most
    local guild = Most and Most.MyGuild()
    if not guild or not Most.IsGuildAllowed(guild) or (addonTable.Mute and addonTable.Mute.IsMuted(MyName())) then return end
    if signNoticeAt[ev.id] and GetTime() - signNoticeAt[ev.id] < SIGN_NOTICE_EVERY then return end
    signNoticeAt[ev.id] = GetTime()
    local coming = 0
    for _, st in pairs(ev.status or {}) do if st == "Y" then coming = coming + 1 end end
    local text = ((s.st == "M") and "Maybe for " or "Signed up for ") .. tostring(ev.title or "an event")
        .. " (" .. tostring(ev.date or "") .. " " .. tostring(ev.time or "") .. ")"
        .. (s.r and (" as " .. tostring(s.r)) or "") .. " - " .. coming .. " coming <jn-event:" .. tostring(ev.id) .. ">"
    Most.PublishTyped("Szukaj grupy", text, MyName(), guild)
end

function Events.Sign(ev, spec, status, leader)
    if not InListedGuild() then return false, "Your guild is not on the Community list." end
    if not Find(ev.id) or IsOver(ev) then return false, "This event is over." end
    local me = MyName()
    ev.signs = ev.signs or {}
    local cur = ev.signs[me] or {}
    -- Picking a spec means coming (or still maybe); otherwise the status stays as it was
    local keep = spec and ((cur.st == "M") and "M" or "Y") or ((cur.st and cur.st ~= "X") and cur.st or "Y")
    local s = { r = spec and spec.role or cur.r, s = spec and spec.code or cur.s, st = status or keep,
        l = (leader == nil) and cur.l or leader }
    if (s.st == "Y" or s.st == "M") and not s.r then return false, "Pick your spec first." end
    if s.st == "N" or s.st == "X" then s.l = false end
    -- Newer than my last change and than any removal of me, so it wins everywhere
    local kick = ev.kicks and ev.kicks[me]
    s.t = math.max(GetServerTime(), (cur.t or 0) + 1, kick and (kick.ts + 1) or 0)
    ev.signs[me] = s
    Rebuild(ev)
    SendSign(ev, me)
    Changed(ev)
    if (s.st == "Y" or s.st == "M") and cur.st ~= "Y" and cur.st ~= "M" and not ev.localTest then addonTable.Safe("events.lua:SignNotice", SignNotice, ev, s) end
    return true
end

function Events.Kick(ev, name)
    if not Events.CanManage(ev) then return false, "Only the author and officers can take players off." end
    local s = ev.signs and ev.signs[name]
    ev.kicks = ev.kicks or {}
    ev.kicks[name] = { ts = math.max(GetServerTime(), s and (s.t + 1) or 0), by = MyName() }
    if ev.signs then ev.signs[name] = nil end
    Rebuild(ev)
    SendKick(ev, name)
    Changed(ev)
    return true
end

-- ============================================================================
-- SYNC
-- ============================================================================
-- The newest change we know (headers, sign-ups, removals, cancellations)
local function Newest()
    local n = 0
    for _, ev in ipairs(db) do
        -- A test event's times are not the community's (pre-release test build)
        if not ev.localTest then n = math.max(n, ev.rev or 0) end
        for _, s in pairs(ev.signs or {}) do n = math.max(n, s.t or 0) end
        for _, k in pairs(ev.kicks or {}) do n = math.max(n, k.ts or 0) end
    end
    for _, r in pairs(db.removed) do n = math.max(n, type(r) == "table" and r.ts or 0) end
    return n
end

function Events.Request(force)
    if not force and GetTime() - lastRequest < REQUEST_COOLDOWN then return end
    lastRequest = GetTime()
    if not InListedGuild() then return end
    local newest = Newest()
    Most.Send("EQ", tostring(newest > 0 and math.max(1, newest - SYNC_MARGIN) or 0), "high")
    if addonTable.Sync then addonTable.Sync.Start("events") end
end

local function Answer(asker, since)
    answeredAt[asker] = GetTime()
    local sent = 0
    for _, ev in ipairs(db) do
        if (ev.rev or 0) > since then SendHeader(ev, asker) sent = sent + 1 end
        for name, s in pairs(ev.signs or {}) do if (s.t or 0) > since then SendSign(ev, name, asker) sent = sent + 1 end end
        for name, k in pairs(ev.kicks or {}) do if (k.ts or 0) > since then SendKick(ev, name, asker) sent = sent + 1 end end
    end
    for id, r in pairs(db.removed) do
        if type(r) == "table" and (r.ts or 0) > since then
            Out("EX", table.concat({ Enc(id), tostring(r.ts), Enc(r.by or "") }, ":"), asker)
            sent = sent + 1
        end
    end
    if Monitor() then Monitor().Note("Events: answered " .. asker .. " with " .. sent .. " changes") end
end

local function HandleRequest(asker, since)
    if asker == MyName() or pending[asker] then return end
    if GetTime() - (answeredAt[asker] or -ANSWER_COOLDOWN) < ANSWER_COOLDOWN then return end
    if not Most.ShouldAnswer() then return end
    -- Nothing newer than what they have: no answer at all
    if Newest() <= since then return end
    Most.ClaimAndAnswer(pending, asker, 0.5 + math.random() * 2, function() Most.Send("EC", Enc(asker), "high") end,
        function() Answer(asker, since) end)
end

-- ============================================================================
-- RECEIVING (core.lua: packets from known players of listed guilds). live = not a sync whisper.
-- ============================================================================
-- 1.3.1: an event whose author is not on the guild rosters known here yet is held instead of dropped (a player
-- logging in gets the events from a guildmate while another guild's roster is still arriving in parts), with its
-- description, sign-ups and removals arriving meanwhile; RetryHeld takes it as soon as the author is known.
local RetryHeld
local function Hold(id, creator, rev, payload, senderName, live)
    local h = held[id]
    if h then
        if rev > h.rev then h.rev, h.payload, h.sender, h.live = rev, payload, senderName, live end
        return
    end
    if heldCount >= HOLD_MAX then return end
    held[id] = { creator = creator, rev = rev, payload = payload, sender = senderName, live = live, at = GetTime(), extra = {} }
    heldCount = heldCount + 1
    if not retrying then
        retrying = true
        C_Timer.After(HOLD_RETRY, function() RetryHeld() end)
    end
end
-- A description part, sign-up or removal for a held event waits with it. Returns true when held.
local function HoldExtra(id, pType, payload, senderName, live)
    local h = id and held[id]
    if not h then return false end
    if #h.extra < HOLD_EXTRA then table.insert(h.extra, { pType = pType, payload = payload, sender = senderName, live = live }) end
    return true
end

local function ApplySign(ev, name, s)
    ev.signs = ev.signs or {}
    local cur = ev.signs[name]
    if cur and (cur.t or 0) >= s.t then return false end
    local kick = ev.kicks and ev.kicks[name]
    if kick and kick.ts >= s.t then return false end
    ev.signs[name] = s
    Rebuild(ev)
    return true
end

local function HandleHeader(payload, senderName, live)
    local id, rev, editor, creator, guild, title, eDate, eTime, dungeon, parts = strsplit(":", payload, 10)
    id, rev = Dec(id), tonumber(rev)
    editor, creator, guild = Dec(editor), Dec(creator), Dec(guild)
    title, eDate, eTime, dungeon = Dec(title), Dec(eDate), Dec(eTime), Dec(dungeon)
    parts = math.min(tonumber(parts) or 0, 5)
    if not (id and rev and creator and title and eDate and eTime) or title == "" or #title > TITLE_MAX * 2 then return end
    if editor == "" then editor = creator end
    if db.removed[id] then return end
    -- 1.3.0: a weekly event from someone who has not moved it on yet: its current week here
    eDate = CurrentDate(id, eDate, eTime)
    if not eDate then return end
    local probe = { date = eDate, time = eTime }
    if live and senderName ~= editor then return end
    if dungeon == "" then dungeon = nil end
    local ev = Find(id)
    if ev then
        if rev <= (ev.rev or 0) then return end
        -- An edit: by the author or an officer
        if editor ~= ev.creator and not IsOfficer(editor) then return end
        -- My copy of a weekly event is still on its past week (moved on within a minute): a new week starts empty
        -- 1.3.0: moved by whole weeks (a skipped week): the same
        if IsOver(ev) or WeeksMoved(ev, eDate, eTime) then ev.signs, ev.kicks = {}, {} Rebuild(ev) end
        ev.title, ev.date, ev.time, ev.dungeon, ev.rev, ev.editor = title, eDate, eTime, dungeon, rev, editor
    else
        -- A new event: its author must be a member of a listed guild and within their limit of active events
        if editor ~= creator and not IsOfficer(editor) then return end
        local author = (creator == MyName()) or Most.FindKnownPlayer(creator)
        if not author then
            -- 1.3.1: in the log, once per event (user: "ludzie nie widzą eventów", JN3): its author is not on the
            -- guild rosters known here yet (e.g. a roster still arriving after login); held, tried again (Hold)
            if Monitor() and not unknownNoted[id] then
                unknownNoted[id] = true
                Monitor().Note("Events: held event " .. title .. " of " .. creator .. " (" .. tostring(guild) .. "), from " .. tostring(senderName) .. (live and "" or " (sync)") .. ": author not known here yet")
            end
            Hold(id, creator, rev, payload, senderName, live)
            return
        end
        if Series(id) then
            -- 1.3.0: a weekly event counts against the weekly limit, not the usual one
            if WeeklyCount(creator, id) >= WeeklyLimit(creator) then
                if Monitor() then Monitor().Note("Events: ignored a new weekly event of " .. creator .. " (over their limit of weekly events)") end
                return
            end
        elseif Events.Start(probe) > time() and ActiveCount(creator, id) >= ActiveLimit(creator) then
            if Monitor() then Monitor().Note("Events: ignored a new event of " .. creator .. " (over their limit of upcoming events)") end
            return
        end
        if not Most.IsGuildAllowed(guild) then guild = type(author) == "table" and author.guild or nil end
        ev = { id = id, rev = rev, editor = editor, creator = creator, guild = guild, title = title, date = eDate, time = eTime, dungeon = dungeon,
            signs = {}, kicks = {} }
        Rebuild(ev)
        table.insert(db, ev)
    end
    ev.desc = ""
    ev.descParts = (parts > 0) and { total = parts, rev = rev } or nil
    Changed(ev)
end

local function HandleDescPart(payload)
    local id, rev, idx, chunk = strsplit(":", payload, 4)
    local ev = Find(Dec(id))
    if not ev and HoldExtra(Dec(id), "ED", payload) then return end
    rev, idx = tonumber(rev), tonumber(idx)
    if not ev or not ev.descParts or ev.descParts.rev ~= rev or not idx or idx < 1 or idx > ev.descParts.total then return end
    ev.descParts[idx] = Dec(chunk) or ""
    local text = {}
    for i = 1, ev.descParts.total do if ev.descParts[i] then table.insert(text, ev.descParts[i]) end end
    ev.desc = table.concat(text)
    Changed(ev)
end

local function HandleSign(payload, senderName, live)
    local id, name, r, s, st, l, t = strsplit(":", payload, 7)
    local ev = Find(Dec(id))
    if not ev and HoldExtra(Dec(id), "ES", payload, senderName, live) then return end
    name, t = Dec(name), tonumber(t)
    if not ev or not name or not t or not (STATUSES[st] or st == "X") or IsOver(ev) then return end
    if live and senderName ~= name then return end
    -- 1.3.0: a sign-up for an earlier week of a weekly event (a late sync answer) does not count
    if t < WeekFloor(ev) then return end
    if r == "-" then r = nil end
    if s == "-" then s = nil end
    if (st == "Y" or st == "M") and not VALID_ROLES[r or ""] then return end
    -- The spec must fit the role, and the player's class when known
    local spec = s and ctx and ctx.specs[s]
    if s and (not spec or spec.role ~= r) then s = nil end
    local p = Most.FindKnownPlayer(name)
    local roles = p and p.class and ctx and ctx.classRoles[p.class]
    if r and roles and not roles[r] then return end
    if spec and p and p.class and spec.class ~= p.class then s = nil end
    if ApplySign(ev, name, { r = r, s = s, st = st, l = (l == "1") and (st == "Y" or st == "M") or false, t = t }) then Changed(ev) end
end

local function HandleKick(payload, senderName, live)
    local id, name, ts, by = strsplit(":", payload, 4)
    local ev = Find(Dec(id))
    if not ev and HoldExtra(Dec(id), "EK", payload, senderName, live) then return end
    name, ts, by = Dec(name), tonumber(ts), Dec(by)
    if not ev or not name or not ts or not by then return end
    if live and senderName ~= by then return end
    if by ~= ev.creator and not IsOfficer(by) then return end
    if ts < WeekFloor(ev) then return end
    ev.kicks = ev.kicks or {}
    if ev.kicks[name] and ev.kicks[name].ts >= ts then return end
    ev.kicks[name] = { ts = ts, by = by }
    local s = ev.signs and ev.signs[name]
    if s and s.t <= ts then
        ev.signs[name] = nil
        Rebuild(ev)
        if name == MyName() and live and _G.DEFAULT_CHAT_FRAME then
            _G.DEFAULT_CHAT_FRAME:AddMessage("|cffbf40ff[Jagodka]|r " .. by .. " took you off the event: " .. tostring(ev.title))
        end
    end
    Changed(ev)
end

local function HandleCancel(payload, senderName, live)
    local id, ts, by = strsplit(":", payload, 3)
    id, ts, by = Dec(id), tonumber(ts), Dec(by)
    if not id or not ts then return end
    if live and senderName ~= by then return end
    local ev = Find(id)
    if ev then
        if by ~= ev.creator and not IsOfficer(by) then return end
    elseif not (by and by ~= "" and (IsOfficer(by) or Most.FindKnownPlayer(by))) then
        return
    end
    if not db.removed[id] then Remove(id, ts, by) end
    if held[id] then held[id] = nil heldCount = heldCount - 1 end
end

-- 1.3.1: held events whose author is known now are taken, with what arrived for them meanwhile
RetryHeld = function()
    local now = GetTime()
    for id, h in pairs(held) do
        if h.creator == MyName() or Most.FindKnownPlayer(h.creator) then
            held[id] = nil
            heldCount = heldCount - 1
            HandleHeader(h.payload, h.sender, h.live)
            if Find(id) then
                if Monitor() then Monitor().Note("Events: took the held event of " .. h.creator .. " after " .. math.floor(now - h.at) .. " s (author known now)") end
                for _, x in ipairs(h.extra) do
                    if x.pType == "ED" then HandleDescPart(x.payload)
                    elseif x.pType == "ES" then HandleSign(x.payload, x.sender, x.live)
                    elseif x.pType == "EK" then HandleKick(x.payload, x.sender, x.live) end
                end
            end
        elseif now - h.at > HOLD_FOR then
            held[id] = nil
            heldCount = heldCount - 1
            if Monitor() then Monitor().Note("Events: dropped the held event of " .. h.creator .. " (author still not known after " .. HOLD_FOR / 60 .. " min)") end
        end
    end
    if heldCount > 0 then C_Timer.After(HOLD_RETRY, function() RetryHeld() end) else retrying = false end
end

-- ============================================================================
-- 1.3.1: A NEW RELAY ASKS THE OTHER GUILDS FOR THEIR EVENTS (EG)
-- ============================================================================
-- Sync after login asks only the own guild (EQ), so an event that never reached a guild live (sent to its
-- relay just as that relay logged out, or made while nobody of the guild was online) was missing there until
-- its author changed it. Now whoever becomes the relay of their guild (also right after login) whispers EG to
-- the relay of every other guild once (at most every PULL_COOLDOWN); each answers with ITS OWN guild's events,
-- sign-ups and cancellations (low priority, as a sync answer). What was new to the asking relay goes on to its
-- guild as a usual repost ("FW:person:packet" on GUILD, as relays do for live packets), so every version there
-- takes it as the person's own change. Versions before 1.3.1 ignore EG; nothing else changes (live packets,
-- relays, queues).
--      EG since                                                       pull request (whisper to a relay)
local function AnswerPull(asker, since)
    pullAnsweredAt[asker] = GetTime()
    local mine, sent = Most.MyGuild(), 0
    -- Also the events of a guild with no relay online now (chat 27.11: "nie widzę tego eventu", an event of JN5,
    -- where only a few have the addon): nobody of that guild could answer. The asker's own guild is left out.
    local linked = Most.OtherGuildRelays and Most.OtherGuildRelays() or {}
    local askerInfo = Most.FindKnownPlayer(asker)
    local askerGuild = askerInfo and askerInfo.guild
    for _, ev in ipairs(db) do
        local fromHere = ev.guild == mine or (ev.guild and ev.guild ~= askerGuild and not linked[ev.guild])
        if fromHere and not ev.localTest then
            if (ev.rev or 0) > since then SendHeader(ev, asker) sent = sent + 1 end
            for name, s in pairs(ev.signs or {}) do if (s.t or 0) > since then SendSign(ev, name, asker) sent = sent + 1 end end
            for name, k in pairs(ev.kicks or {}) do if (k.ts or 0) > since then SendKick(ev, name, asker) sent = sent + 1 end end
        end
    end
    for id, r in pairs(db.removed) do
        local by = type(r) == "table" and r.by and r.by ~= "" and (r.by == MyName() and { guild = mine } or Most.FindKnownPlayer(r.by))
        if by and by.guild == mine and (r.ts or 0) > since then
            Out("EX", table.concat({ Enc(id), tostring(r.ts), Enc(r.by) }, ":"), asker)
            sent = sent + 1
        end
    end
    if Monitor() then Monitor().Note("Events: answered the pull of " .. asker .. " (relay of another guild) with " .. sent .. " changes") end
end

local function HandlePull(asker, since, channel)
    if channel ~= "WHISPER" or asker == MyName() or not InListedGuild() then return end
    local p = Most.FindKnownPlayer(asker)
    if not p or p.guild == Most.MyGuild() then return end
    if GetTime() - (pullAnsweredAt[asker] or -PULL_ANSWER_COOLDOWN) < PULL_ANSWER_COOLDOWN then return end
    AnswerPull(asker, since)
end

-- Every minute: just became my guild's relay -> ask the other guilds' relays
local function PullCheck()
    local isRelay = Most.IsRelay() and true or false
    if isRelay and not wasRelay and InListedGuild() and GetTime() - lastPull >= PULL_COOLDOWN and Most.OtherGuildRelays then
        lastPull = GetTime()
        local asked = {}
        for _, relay in pairs(Most.OtherGuildRelays()) do
            local p = relay and relay ~= MyName() and Most.FindKnownPlayer(relay)
            if p and p.version and Most.AtLeast(p.version, PULL_MIN_VERSION) then
                pullFrom[relay] = GetTime() + PULL_WINDOW
                Most.Whisper(relay, "EG", "0", "high")
                table.insert(asked, relay)
            end
        end
        if Monitor() then Monitor().Note("Events: I am the relay now, asked " .. #asked .. " other guilds' relays for their events" .. (#asked > 0 and (" (" .. table.concat(asked, ", ") .. ")") or " (none with " .. PULL_MIN_VERSION .. "+)")) end
    end
    wasRelay = isRelay
end

-- A change from a pull answer that was new to me goes on to my guild as the person's own packet
local function PassOn(pType, payload)
    local origin
    if pType == "EH" then
        local _, _, editor, creator = strsplit(":", payload, 5)
        editor, creator = Dec(editor), Dec(creator)
        origin = (editor and editor ~= "") and editor or creator
    elseif pType == "ED" then
        local ev = Find(Dec((strsplit(":", payload, 2))))
        origin = ev and (ev.editor or ev.creator)
    elseif pType == "ES" then
        local _, name = strsplit(":", payload, 3)
        origin = Dec(name)
    elseif pType == "EX" then
        local _, _, by = strsplit(":", payload, 3)
        origin = Dec(by)
    end
    if not origin or origin == "" or origin == MyName() then return end
    local text = origin .. ":" .. pType .. ":" .. payload
    if #text + #"FW:" > 255 then return end
    Most.Send("FW", text, "low")
    if Monitor() then Monitor().Note("Events: passed on to my guild a change of " .. origin .. " my guild did not have (" .. pType .. ")") end
end

-- Returns true when the packet is an events packet (handled or ignored)
function Events.HandlePacket(pType, payload, senderName, channel)
    if pType == "EQ" then
        HandleRequest(senderName, tonumber(payload) or 0)
        return true
    elseif pType == "EC" then
        Activity()
        local asker = Dec(payload)
        if senderName ~= MyName() and asker then Most.ClaimSeen(pending, asker, senderName) end
        return true
    elseif pType == "EG" then
        HandlePull(senderName, tonumber(payload) or 0, channel)
        return true
    end
    if pType ~= "EH" and pType ~= "ED" and pType ~= "ES" and pType ~= "EK" and pType ~= "EX" then return false end
    Activity()
    -- Our own packets come back from GUILD: already applied when sent
    if senderName == MyName() then return true end
    local live = channel ~= "WHISPER"
    local before = changes
    if pType == "EH" then HandleHeader(payload, senderName, live)
    elseif pType == "ED" then HandleDescPart(payload)
    elseif pType == "ES" then HandleSign(payload, senderName, live)
    elseif pType == "EK" then HandleKick(payload, senderName, live)
    elseif pType == "EX" then HandleCancel(payload, senderName, live) end
    -- 1.3.1: the answer to my pull (another guild's relay, PullCheck): what was new here goes on to my guild
    if not live and changes ~= before and pullFrom[senderName] and GetTime() < pullFrom[senderName] and Most.IsRelay() then
        PassOn(pType, payload)
    end
    return true
end

-- ============================================================================
-- REMINDER AND CLEANUP
-- ============================================================================
local function CheckReminders()
    local me, now = MyName(), time()
    for _, ev in ipairs(db) do
        local st = ev.status and ev.status[me]
        local start = Events.Start(ev)
        -- Per date: a weekly event reminds again the next week
        local key = tostring(ev.id) .. "@" .. tostring(ev.date)
        if (st == "Y" or st == "M") and start and not reminded[key] and start - now <= REMIND_BEFORE and start - now > -60 then
            reminded[key] = true
            local mins = math.max(0, math.floor((start - now) / 60 + 0.5))
            local text = "|cffbf40ff[Jagodka]|r |cffffd100" .. tostring(ev.title) .. "|r starts in " .. mins .. " min (" .. tostring(ev.time) .. ")" .. (ev.dungeon and (" - " .. ev.dungeon) or "")
            if _G.DEFAULT_CHAT_FRAME then _G.DEFAULT_CHAT_FRAME:AddMessage(text) end
            if _G.RaidNotice_AddMessage and _G.RaidWarningFrame then
                _G.RaidNotice_AddMessage(_G.RaidWarningFrame, tostring(ev.title) .. " starts in " .. mins .. " min", { r = 0.75, g = 0.25, b = 1 })
            end
            if _G.PlaySound then _G.PlaySound((_G.SOUNDKIT and _G.SOUNDKIT.RAID_WARNING) or 8959, "Master") end
        end
    end
end

local Ticker = CreateFrame("Frame")
Ticker:RegisterEvent("PLAYER_LOGIN")
addonTable.SafeScript(Ticker, "OnEvent", "events.lua:527", function()
    C_Timer.NewTicker(60, Events.Prune)
    C_Timer.NewTicker(30, CheckReminders)
    C_Timer.NewTicker(60, PullCheck)   -- 1.3.1
end)
