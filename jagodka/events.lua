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
local REQUEST_COOLDOWN = 60           -- our own requests at most this often, unless forced (s)
local REMIND_BEFORE = 15 * 60
local DESC_MAX = 400                  -- description bytes
local DESC_PART = 170                 -- encoded description bytes per packet
local TITLE_MAX = 50

local Events = {}
addonTable.Events = Events
Events.DESC_MAX, Events.TITLE_MAX = DESC_MAX, TITLE_MAX
Events.MEMBER_ACTIVE, Events.OFFICER_ACTIVE = MEMBER_ACTIVE, OFFICER_ACTIVE

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

local function IsOfficer(name)
    if not ctx then return false end
    if name == MyName() then return ctx.isMeOfficer() end
    return ctx.isKnownOfficer(name)
end

-- How many active events the player may have, and how many they have (except the event `except`)
local function ActiveCount(creator, except)
    local n = 0
    for _, ev in ipairs(db) do
        if ev.creator == creator and ev.id ~= except and IsActive(ev) then n = n + 1 end
    end
    return n
end
local function ActiveLimit(creator) return IsOfficer(creator) and OFFICER_ACTIVE or MEMBER_ACTIVE end

-- The views the windows use: roster (name -> role, Coming and Maybe), specs, leaders, status (name -> Y/M/N)
local function Rebuild(ev)
    ev.roster, ev.specs, ev.leaders, ev.status = {}, {}, {}, {}
    for name, s in pairs(ev.signs or {}) do
        if s.st == "Y" or s.st == "M" then
            ev.roster[name] = s.r
            ev.specs[name] = s.s
            if s.l then ev.leaders[name] = true end
        end
        if s.st ~= "X" then ev.status[name] = s.st end
    end
end

local function Changed(ev) if ctx then ctx.onChanged(ev) end end

local function Remove(id, ts, by)
    db.removed[id] = { ts = ts or GetServerTime(), by = by }
    local _, idx = Find(id)
    if idx then
        table.remove(db, idx)
        if ctx then ctx.onRemoved(idx) end
    end
end

-- Over events (start + LIVE_AFTER_START) and old cancellations go; checked every minute
function Events.Prune()
    for i = #db, 1, -1 do
        if IsOver(db[i]) then
            table.remove(db, i)
            if ctx then ctx.onRemoved(i) end
        end
    end
    local now = GetServerTime()
    for id, r in pairs(db.removed) do
        if type(r) ~= "table" or now - (r.ts or 0) > REMOVED_KEEP then db.removed[id] = nil end
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

-- Whether I can create one more event: ok, or false and the reason
function Events.CanCreate()
    if not InListedGuild() then return false, "Your guild is not on the Community list." end
    local me = MyName()
    local limit = ActiveLimit(me)
    if ActiveCount(me) >= limit then
        return false, (limit == 1) and "You already have an upcoming event. A new one when it has started (officers: up to 5)."
            or ("You already have " .. limit .. " upcoming events.")
    end
    return true
end

-- ============================================================================
-- SENDING
-- ============================================================================
local function Out(pType, payload, target, priority)
    if target then Most.Whisper(target, pType, payload, priority or "low")
    elseif InListedGuild() then Most.Send(pType, payload, priority or "high") end
end

local function SendHeader(ev, target)
    local chunks = Most.EncodeChunks(ev.desc or "", DESC_PART, DESC_PART)
    if #chunks == 1 and chunks[1] == "" then chunks = {} end
    Out("EH", table.concat({ Enc(ev.id), tostring(ev.rev), Enc(ev.editor ~= ev.creator and ev.editor or ""), Enc(ev.creator), Enc(ev.guild),
        Enc(ev.title), Enc(ev.date), Enc(ev.time), Enc(ev.dungeon or ""), tostring(#chunks) }, ":"), target)
    for i, chunk in ipairs(chunks) do Out("ED", Enc(ev.id) .. ":" .. ev.rev .. ":" .. i .. ":" .. chunk, target) end
end

local function SendSign(ev, name, target)
    local s = ev.signs and ev.signs[name]
    if not s then return end
    Out("ES", table.concat({ Enc(ev.id), Enc(name), s.r or "-", s.s or "-", s.st, s.l and "1" or "0", tostring(s.t) }, ":"), target)
end

local function SendKick(ev, name, target)
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

function Events.Create(title, eDate, eTime, dungeon, desc)
    local ok, why = Events.CanCreate()
    if not ok then return false, why end
    ok, why = Valid(title, eDate, eTime)
    if not ok then return false, why end
    if not IsActive({ date = eDate, time = eTime }) then return false, "Pick a time in the future." end
    local me = MyName()
    local ev = { id = NewId(), rev = GetServerTime(), title = title, date = eDate, time = eTime, dungeon = dungeon, desc = desc or "",
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
    Out("EX", table.concat({ Enc(ev.id), tostring(ts), Enc(MyName()) }, ":"))
    Remove(ev.id, ts, MyName())
    return true
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
    if (s.st == "Y" or s.st == "M") and cur.st ~= "Y" and cur.st ~= "M" then addonTable.Safe("events.lua:SignNotice", SignNotice, ev, s) end
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
        n = math.max(n, ev.rev or 0)
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
    local probe = { date = eDate, time = eTime }
    if not Events.Start(probe) or IsOver(probe) then return end
    if live and senderName ~= editor then return end
    if dungeon == "" then dungeon = nil end
    local ev = Find(id)
    if ev then
        if rev <= (ev.rev or 0) then return end
        -- An edit: by the author or an officer
        if editor ~= ev.creator and not IsOfficer(editor) then return end
        ev.title, ev.date, ev.time, ev.dungeon, ev.rev, ev.editor = title, eDate, eTime, dungeon, rev, editor
    else
        -- A new event: its author must be a member of a listed guild and within their limit of active events
        if editor ~= creator and not IsOfficer(editor) then return end
        local author = (creator == MyName()) or Most.FindKnownPlayer(creator)
        if not author then return end
        if Events.Start(probe) > time() and ActiveCount(creator, id) >= ActiveLimit(creator) then
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
    name, t = Dec(name), tonumber(t)
    if not ev or not name or not t or not (STATUSES[st] or st == "X") or IsOver(ev) then return end
    if live and senderName ~= name then return end
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
    name, ts, by = Dec(name), tonumber(ts), Dec(by)
    if not ev or not name or not ts or not by then return end
    if live and senderName ~= by then return end
    if by ~= ev.creator and not IsOfficer(by) then return end
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
    end
    if pType ~= "EH" and pType ~= "ED" and pType ~= "ES" and pType ~= "EK" and pType ~= "EX" then return false end
    Activity()
    -- Our own packets come back from GUILD: already applied when sent
    if senderName == MyName() then return true end
    local live = channel ~= "WHISPER"
    if pType == "EH" then HandleHeader(payload, senderName, live)
    elseif pType == "ED" then HandleDescPart(payload)
    elseif pType == "ES" then HandleSign(payload, senderName, live)
    elseif pType == "EK" then HandleKick(payload, senderName, live)
    elseif pType == "EX" then HandleCancel(payload, senderName, live) end
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
        if (st == "Y" or st == "M") and start and not reminded[ev.id] and start - now <= REMIND_BEFORE and start - now > -60 then
            reminded[ev.id] = true
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
end)
