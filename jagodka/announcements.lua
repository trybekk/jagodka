-- ============================================================================
-- ANNOUNCEMENTS: guild announcements for all our guilds (the Announcements tab), like a small blog
-- ============================================================================
--  * Only officers (by the guild rosters): they post; the author or an officer of the post's guild edits, pins and deletes (an author who lost the rank cannot).
--    Everyone with the addon in every listed guild reads them. Rules checked by the author AND every receiver.
--  * A post: tag (General / Important / Raid / Event), title, text (a few paragraphs), pinned or not.
--    Pinned posts stay on top, the rest newest first. A post goes by itself KEEP days after it was written.
--  * Packets (to GUILD; the relays pass them on to other guilds with high priority, like events):
--      AH id:rev:editor:author:guild:created:tag:pin:title:parts   header (rev = server time of the change)
--      AB id:rev:part:text                                         part of the text
--      AX id:time:by                                               post deleted
--    A live packet must come from the person it names (editor, remover); a sync answer may carry anyone's.
--  * Sync after login (and the Sync button), like events: AQ with the time of the newest change we know,
--    one guildmate claims it (AC) and whispers only newer changes, low priority. AQ/AC stay in the guild.
--  * Unread: posts newer than the last time the tab was open get a NEW mark and a count on the tab.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_Timer = addonTable.SafeTimer -- protected callbacks (safe.lua)
local CreateFrame = _G.CreateFrame
local GetServerTime = _G.GetServerTime
local GetTime = _G.GetTime
local strsplit = _G.strsplit
local ipairs, pairs, tostring, tonumber, type = _G.ipairs, _G.pairs, _G.tostring, _G.tonumber, _G.type
local table, math, string = _G.table, _G.math, _G.string
local date = _G.date

local Most = addonTable.Most
local Enc, Dec = Most.EncodeField, Most.DecodeField

local TITLE_MAX = 60                  -- title bytes (the header packet must fit when forwarded)
local BODY_MAX = 1200                 -- text bytes
local BODY_PART = 170                 -- encoded text bytes per packet
local MAX_PARTS = 10
local KEEP = 60 * 86400               -- a post goes this long after it was written
local REMOVED_KEEP = 70 * 86400       -- deleted ids kept this long
local MAX_POSTS = 40                  -- the oldest unpinned posts go beyond this
local PER_DAY = 6                     -- new posts of one author per 24 h, more are ignored
local SYNC_MARGIN = 600
local ANSWER_COOLDOWN = 120
local REQUEST_COOLDOWN = 60
local MIN_VERSION = "1.1.0"           -- only guildmates who know announcements answer the sync

local Announcements = {}
addonTable.Announcements = Announcements
Announcements.TITLE_MAX, Announcements.BODY_MAX = TITLE_MAX, BODY_MAX

-- Tags: code in packets, name, color
local TAGS = {
    { code = "N", label = "General", r = 1, g = 0.82, b = 0 },
    { code = "I", label = "Important", r = 1, g = 0.45, b = 0.1 },
    { code = "R", label = "Raid", r = 0.95, g = 0.3, b = 0.3 },
    { code = "E", label = "Event", r = 0.75, g = 0.25, b = 1 },
}
local TAG_BY_CODE = {}
for _, t in ipairs(TAGS) do TAG_BY_CODE[t.code] = t end
Announcements.TAGS = TAGS

-- Context from core.lua: isMeOfficer(), isKnownOfficer(name), colorName(name, class), setBadge(n), onChanged()
local ctx = nil
function Announcements.Init(c) ctx = c end

local db = { posts = {}, removed = {}, seen = 0 }
local pending, answeredAt = {}, {}
local lastRequest = -REQUEST_COOLDOWN
local lastAnswerAt = -1        -- when a sync answer (whisper) last arrived
local OTHERS_AFTER = 9         -- seconds without an answer from my guild before the other guilds are asked (AO)
-- 1.1.2: every BEACON_EVERY one player of each guild (the first-named with 1.1.2) tells all guilds the newest
-- change it knows (AV, one small packet); whoever has less asks for the rest. So a post reaches players who were
-- offline when it was posted within minutes, even where few have the addon version that knows announcements.
local BEACON_EVERY = 600
local BEACON_MIN = "1.1.2"

local function Monitor() return addonTable.Monitor end
local function MyName() return Most.MyName() end
local function Activity() if addonTable.Sync then addonTable.Sync.Activity("announcements") end end
local function InListedGuild() return Most.IsGuildAllowed(Most.MyGuild()) end

local function Find(id)
    for i, p in ipairs(db.posts) do if p.id == id then return p, i end end
    return nil
end
Announcements.Find = Find

local function IsOfficer(name)
    if not ctx then return false end
    if name == MyName() then return ctx.isMeOfficer() end
    return ctx.isKnownOfficer(name)
end

local function GuildOf(name)
    if name == MyName() then return Most.MyGuild() end
    local p = Most.FindKnownPlayer(name)
    return p and p.guild or nil
end

-- May this person change (edit, pin, delete) the post: ONLY an officer right now (by the guild rosters), and
-- either its author or an officer of the post's guild. An author who is no longer an officer cannot change it.
local function MayManage(name, post)
    if not name or not post or not IsOfficer(name) then return false end
    return name == post.author or GuildOf(name) == post.guild
end

local function Changed()
    if ctx and ctx.onChanged then ctx.onChanged() end
    if Announcements.Refresh then Announcements.Refresh() end
end

-- ============================================================================
-- DATA
-- ============================================================================
local function Sort()
    table.sort(db.posts, function(a, b)
        if (a.pin and true or false) ~= (b.pin and true or false) then return a.pin and true or false end
        return (a.created or 0) > (b.created or 0)
    end)
end

function Announcements.Prune()
    local now = GetServerTime()
    for i = #db.posts, 1, -1 do
        local p = db.posts[i]
        if now - (p.created or 0) > KEEP then table.remove(db.posts, i) end
    end
    Sort()
    -- Over the cap: the oldest unpinned go first
    local count = #db.posts
    for i = #db.posts, 1, -1 do
        if count <= MAX_POSTS then break end
        local p = db.posts[i]
        if not p.pin then table.remove(db.posts, i) count = count - 1 end
    end
    for id, r in pairs(db.removed) do
        if type(r) ~= "table" or now - (r.ts or 0) > REMOVED_KEEP then db.removed[id] = nil end
    end
end

function Announcements.Load()
    _G.JagodkiChatDB = _G.JagodkiChatDB or {}
    local saved = _G.JagodkiChatDB.announcements
    if type(saved) ~= "table" or type(saved.posts) ~= "table" then saved = { posts = {}, removed = {}, seen = 0 } end
    saved.removed = type(saved.removed) == "table" and saved.removed or {}
    saved.seen = tonumber(saved.seen) or 0
    for i = #saved.posts, 1, -1 do
        if type(saved.posts[i]) ~= "table" then table.remove(saved.posts, i) end
    end
    _G.JagodkiChatDB.announcements = saved
    db = saved
    Announcements.Prune()
    Announcements.UpdateBadge()
    return db
end

function Announcements.List() return db.posts end

function Announcements.UnreadCount()
    local n = 0
    for _, p in ipairs(db.posts) do
        if (p.created or 0) > db.seen and p.author ~= MyName() then n = n + 1 end
    end
    return n
end

function Announcements.IsUnread(p) return (p.created or 0) > db.seen and p.author ~= MyName() end

function Announcements.UpdateBadge()
    if ctx and ctx.setBadge then ctx.setBadge(Announcements.UnreadCount()) end
end

-- The tab was looked at: everything up to now is read (the NEW marks stay until the tab is opened again)
function Announcements.MarkSeen()
    local newest = db.seen
    for _, p in ipairs(db.posts) do newest = math.max(newest, p.created or 0) end
    db.seen = newest
    Announcements.UpdateBadge()
end

-- ============================================================================
-- PERMISSIONS (the tab uses these too)
-- ============================================================================
function Announcements.CanPost()
    if not InListedGuild() then return false, "Your guild is not on the Community list." end
    if not (ctx and ctx.isMeOfficer()) then return false, "Only officers can post announcements." end
    return true
end

function Announcements.CanManage(post)
    if not post then return false end
    return InListedGuild() and MayManage(MyName(), post)
end

-- ============================================================================
-- SENDING
-- ============================================================================
local function Out(pType, payload, target, priority)
    if target then Most.Whisper(target, pType, payload, priority or "low")
    elseif InListedGuild() then
        Most.Send(pType, payload, priority or "high")
        -- 1.1.1: also straight to the other guilds' relays, not only through my guild's relay (bridge.lua)
        if Most.ToOtherGuilds then Most.ToOtherGuilds(pType, payload) end
    end
end

local function SendPost(p, target)
    local chunks = Most.EncodeChunks(p.body or "", BODY_PART, BODY_PART)
    if #chunks == 1 and chunks[1] == "" then chunks = {} end
    Out("AH", table.concat({ Enc(p.id), tostring(p.rev), Enc((p.editor and p.editor ~= p.author) and p.editor or ""), Enc(p.author),
        Enc(p.guild or ""), tostring(p.created), p.tag or "N", p.pin and "1" or "0", Enc(p.title), tostring(#chunks) }, ":"), target)
    for i, chunk in ipairs(chunks) do Out("AB", Enc(p.id) .. ":" .. p.rev .. ":" .. i .. ":" .. chunk, target) end
end

-- ============================================================================
-- MY CHANGES (the tab); each returns ok, or false and the reason
-- ============================================================================
local function Valid(title, body, tag)
    if not title or title:gsub("%s", "") == "" then return false, "Give the announcement a title." end
    -- Also counted encoded (":" takes 3 bytes in a packet), so the header fits when forwarded to other guilds
    if #title > TITLE_MAX or #Enc(title) > TITLE_MAX + 20 then return false, "The title is too long." end
    if not body or body:gsub("%s", "") == "" then return false, "Write the text of the announcement." end
    if #body > BODY_MAX then return false, "The text is too long." end
    if not TAG_BY_CODE[tag or ""] then return false, "Pick a tag." end
    return true
end

local function Clean(s) return (Most.Plain(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

function Announcements.Create(title, body, tag, pin)
    local ok, why = Announcements.CanPost()
    if not ok then return false, why end
    title, body = Clean(title), Clean(body)
    ok, why = Valid(title, body, tag)
    if not ok then return false, why end
    local now = GetServerTime()
    local p = { id = string.format("%x%02x", now, math.random(0, 255)), rev = now, created = now, author = MyName(),
        guild = Most.MyGuild(), tag = tag, pin = pin and true or false, title = title, body = body }
    table.insert(db.posts, p)
    SendPost(p)
    Announcements.Prune()
    Changed()
    -- A short note on the community General chat, so everyone online sees it at once. Sent from the Publish
    -- click (the game wants a click for channel messages). Clients from 1.1.0 turn the ending into an
    -- [Open announcement] link (bridge.lua ANN_NOTE); older ones show the plain text.
    if not (addonTable.Mute and addonTable.Mute.IsMuted(MyName())) then
        local t = TAG_BY_CODE[tag]
        addonTable.Safe("announcements.lua:Note", Most.PublishTyped, "Ogolny",
            "New announcement: " .. title .. " [" .. t.label .. "] " .. Most.ANN_NOTE_END, MyName(), p.guild)
    end
    return true, p
end

function Announcements.Edit(p, title, body, tag, pin)
    if not Find(p.id) then return false, "This announcement no longer exists." end
    if not Announcements.CanManage(p) then return false, "Only officers can change announcements (the author or an officer of its guild)." end
    title, body = Clean(title), Clean(body)
    local ok, why = Valid(title, body, tag)
    if not ok then return false, why end
    p.title, p.body, p.tag, p.pin = title, body, tag, pin and true or false
    p.rev, p.editor, p.bodyParts = math.max(GetServerTime(), (p.rev or 0) + 1), MyName(), nil
    SendPost(p)
    Sort()
    Changed()
    return true
end

function Announcements.TogglePin(p)
    return Announcements.Edit(p, p.title, p.body, p.tag, not p.pin)
end

function Announcements.Delete(p)
    local _, idx = Find(p.id)
    if not idx then return false, "This announcement no longer exists." end
    if not Announcements.CanManage(p) then return false, "Only officers can delete announcements (the author or an officer of its guild)." end
    table.remove(db.posts, idx)
    local ts = math.max(GetServerTime(), (p.rev or 0) + 1)
    db.removed[p.id] = { ts = ts, by = MyName() }
    Out("AX", table.concat({ Enc(p.id), tostring(ts), Enc(MyName()) }, ":"))
    Changed()
    return true
end

-- ============================================================================
-- SYNC
-- ============================================================================
local function Newest()
    local n = 0
    for _, p in ipairs(db.posts) do n = math.max(n, p.rev or 0) end
    for _, r in pairs(db.removed) do n = math.max(n, type(r) == "table" and r.ts or 0) end
    return n
end

function Announcements.Request(force)
    if not force and GetTime() - lastRequest < REQUEST_COOLDOWN then return end
    lastRequest = GetTime()
    if not InListedGuild() then return end
    local newest = Newest()
    local since = newest > 0 and math.max(1, newest - SYNC_MARGIN) or 0
    -- A post whose text did not fully arrive: ask from before it, so its parts come again
    for _, p in ipairs(db.posts) do
        if p.bodyParts and (p.rev or 0) > 0 then since = math.min(since, math.max(0, p.rev - 1)) end
    end
    Most.Send("AQ", tostring(since), "high")
    if addonTable.Sync then addonTable.Sync.Start("announcements") end
    -- 1.1.1: nobody of my guild answered within OTHERS_AFTER (nobody here has them yet, e.g. few have updated):
    -- the same request straight to the other guilds' relays, as AO (1.1.0 and older ignore that type, so only
    -- players who can answer across guilds see it). Their answer comes by whisper.
    local askedAt = GetTime()
    C_Timer.After(OTHERS_AFTER, function()
        if lastAnswerAt >= askedAt or not Most.ToOtherGuilds then return end
        local n = Most.ToOtherGuilds("AO", tostring(since), true)
        if n > 0 and Monitor() then Monitor().Note("Announcements: no answer from my guild, asked " .. n .. " other guild" .. (n == 1 and "" or "s")) end
        if n > 0 and addonTable.Sync then addonTable.Sync.Start("announcements") end
    end)
end

local function Answer(asker, since)
    answeredAt[asker] = GetTime()
    local sent = 0
    for _, p in ipairs(db.posts) do
        if (p.rev or 0) > since then SendPost(p, asker) sent = sent + 1 end
    end
    for id, r in pairs(db.removed) do
        if type(r) == "table" and (r.ts or 0) > since then
            Out("AX", table.concat({ Enc(id), tostring(r.ts), Enc(r.by or "") }, ":"), asker)
            sent = sent + 1
        end
    end
    if Monitor() then Monitor().Note("Announcements: answered " .. asker .. " with " .. sent .. " changes") end
end

local function HandleRequest(asker, since, minVersion)
    if asker == MyName() or pending[asker] then return end
    if GetTime() - (answeredAt[asker] or -ANSWER_COOLDOWN) < ANSWER_COOLDOWN then return end
    if not Most.ShouldAnswer(minVersion or MIN_VERSION) then return end
    if Newest() <= since then return end
    Most.ClaimAndAnswer(pending, asker, 0.5 + math.random() * 2, function() Most.Send("AC", Enc(asker), "high") end,
        function() Answer(asker, since) end)
end

-- ============================================================================
-- RECEIVING (core.lua: packets from known players of listed guilds). live = not a sync whisper.
-- ============================================================================
local function PostsOfLastDay(author, except)
    local n, now = 0, GetServerTime()
    for _, p in ipairs(db.posts) do
        if p.author == author and p.id ~= except and now - (p.created or 0) < 86400 then n = n + 1 end
    end
    return n
end

local function HandleHeader(payload, senderName, live)
    local id, rev, editor, author, guild, created, tag, pin, title, parts = strsplit(":", payload, 10)
    id, rev, created = Dec(id), tonumber(rev), tonumber(created)
    editor, author, guild, title = Dec(editor), Dec(author), Dec(guild), Dec(title)
    parts = math.min(tonumber(parts) or 0, MAX_PARTS)
    if not (id and rev and created and author and title) or title == "" or #title > TITLE_MAX * 2 or not TAG_BY_CODE[tag or ""] then return end
    if editor == "" then editor = author end
    if db.removed[id] then return end
    local now = GetServerTime()
    if now - created > KEEP or created > now + 600 then return end
    if live and senderName ~= editor then return end
    local p = Find(id)
    local isNew = false
    if p then
        if rev <= (p.rev or 0) then return end
        if not MayManage(editor, p) then return end
    else
        -- A new post: written by an officer of a listed guild, within the daily limit
        if not IsOfficer(author) then
            if Monitor() then Monitor().Note("Announcements: ignored a post of " .. author .. " (not an officer by the rosters)") end
            return
        end
        if editor ~= author and not MayManage(editor, { author = author, guild = guild }) then return end
        if PostsOfLastDay(author, id) >= PER_DAY then
            if Monitor() then Monitor().Note("Announcements: ignored a post of " .. author .. " (over " .. PER_DAY .. " a day)") end
            return
        end
        local authorGuild = GuildOf(author)
        if not Most.IsGuildAllowed(guild) then guild = authorGuild end
        if not guild then return end
        p = { id = id, author = author, guild = guild, created = created }
        table.insert(db.posts, p)
        isNew = true
    end
    p.rev, p.editor, p.tag, p.pin, p.title = rev, (editor ~= author) and editor or nil, tag, pin == "1", title
    p.body = ""
    p.bodyParts = (parts > 0) and { total = parts, rev = rev } or nil
    Announcements.Prune()
    -- (A new post is announced on the community General chat by its author: Announcements.Create)
    Announcements.UpdateBadge()
    Changed()
end

local function HandleBody(payload)
    local id, rev, idx, chunk = strsplit(":", payload, 4)
    local p = Find(Dec(id))
    rev, idx = tonumber(rev), tonumber(idx)
    if not p or not p.bodyParts or p.bodyParts.rev ~= rev or not idx or idx < 1 or idx > p.bodyParts.total then return end
    p.bodyParts[idx] = Dec(chunk) or ""
    local text = {}
    for i = 1, p.bodyParts.total do if p.bodyParts[i] then table.insert(text, p.bodyParts[i]) end end
    p.body = table.concat(text)
    -- All parts here: the helper table is not needed (nor saved)
    local done = true
    for i = 1, p.bodyParts.total do if not p.bodyParts[i] then done = false break end end
    if done then p.bodyParts = nil end
    Changed()
end

local function HandleDelete(payload, senderName, live)
    local id, ts, by = strsplit(":", payload, 3)
    id, ts, by = Dec(id), tonumber(ts), Dec(by)
    if not id or not ts or not by or by == "" then return end
    if live and senderName ~= by then return end
    if db.removed[id] then return end
    local p, idx = Find(id)
    if p then
        if not MayManage(by, p) then return end
        table.remove(db.posts, idx)
    elseif not IsOfficer(by) then
        return
    end
    db.removed[id] = { ts = ts, by = by }
    Announcements.UpdateBadge()
    Changed()
end

-- Returns true when the packet is an announcements packet (handled or ignored)
function Announcements.HandlePacket(pType, payload, senderName, channel)
    -- Sync requests and claims only straight from my own guild: relays of older versions do not know AQ/AC stay
    -- in the guild and would pass them to other guilds, whose players would answer too
    if (pType == "AQ" or pType == "AC") and channel ~= "GUILD" then return true end
    if pType == "AQ" then
        HandleRequest(senderName, tonumber(payload) or 0)
        return true
    elseif pType == "AO" then
        -- 1.1.1: a player of another guild whose own guild could not answer (sent straight to our relay, which
        -- reposted it here); answered like AQ, the claim (AC) in my guild keeps it to one of us.
        -- 1.1.2: also a player not known yet (not in our copy of their guild's roster, core.lua lets AO through):
        -- announcements are public, and each asker is answered at most every ANSWER_COOLDOWN. Only 1.1.2 does
        -- that, so the answer chance counts only 1.1.2 guildmates then.
        if senderName ~= MyName() and channel ~= "WHISPER" then
            HandleRequest(senderName, tonumber(payload) or 0, Most.FindKnownPlayer(senderName) and "1.1.1" or BEACON_MIN)
        end
        return true
    elseif pType == "AV" then
        -- 1.1.2: someone has newer announcements than me: ask (my guild first, then the others, Request)
        local newest = tonumber(payload) or 0
        if senderName ~= MyName() and newest > Newest() and InListedGuild() then
            if Monitor() then Monitor().Note("Announcements: " .. senderName .. " has newer ones, asking") end
            Announcements.Request()
        end
        return true
    elseif pType == "AC" then
        Activity()
        local asker = Dec(payload)
        if senderName ~= MyName() and asker then Most.ClaimSeen(pending, asker, senderName) end
        return true
    end
    if pType ~= "AH" and pType ~= "AB" and pType ~= "AX" then return false end
    Activity()
    if senderName == MyName() then return true end
    local live = channel ~= "WHISPER"
    if not live then lastAnswerAt = GetTime() end
    if pType == "AH" then HandleHeader(payload, senderName, live)
    elseif pType == "AB" then HandleBody(payload)
    else HandleDelete(payload, senderName, live) end
    return true
end

-- [Open announcement] links (bridge.lua builds them from the note on the chat): "garrmission" is a link type
-- the game ignores by itself, so only this hook reacts (the same way as lfg.lua's links)
_G.hooksecurefunc("SetItemRef", function(link)
    if type(link) == "string" and link:find("^garrmission:jagodkaann:") and addonTable.OpenAnnouncements then
        addonTable.Safe("announcements.lua:OpenLink", addonTable.OpenAnnouncements)
    end
end)

local Ticker = CreateFrame("Frame")
Ticker:RegisterEvent("PLAYER_LOGIN")
addonTable.SafeScript(Ticker, "OnEvent", "announcements.lua:Ticker", function()
    C_Timer.NewTicker(300, function() Announcements.Prune() Announcements.UpdateBadge() if Announcements.Refresh then Announcements.Refresh() end end)
    -- 1.1.2: the newest change I know, to all guilds (AV, see BEACON_EVERY); nothing when I know none
    C_Timer.NewTicker(BEACON_EVERY, function()
        local newest = Newest()
        if newest > 0 and InListedGuild() and Most.IsFirstWith(BEACON_MIN) then Out("AV", tostring(newest)) end
    end)
end)

-- ============================================================================
-- THE TAB: a feed of cards, newest first (pinned on top), and the editor
-- ============================================================================
local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }

-- "17 November 2026, 20:15 (3 h ago)"
local function When(ts)
    local t = date("*t", ts)
    local text = t.day .. " " .. MONTHS[t.month] .. " " .. t.year .. ", " .. string.format("%02d:%02d", t.hour, t.min)
    local ago = GetServerTime() - ts
    if ago < 60 then return text .. " (just now)"
    elseif ago < 3600 then return text .. " (" .. math.floor(ago / 60) .. " min ago)"
    elseif ago < 86400 then return text .. " (" .. math.floor(ago / 3600) .. " h ago)"
    elseif ago < 7 * 86400 then
        local d = math.floor(ago / 86400)
        return text .. " (" .. d .. (d == 1 and " day ago)" or " days ago)")
    end
    return text
end

local function TextButton(parent, label, onClick)
    local b = CreateFrame("Button", nil, parent)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetTextColor(0.6, 0.6, 0.65)
    b:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 0.82, 0) end)
    b:SetScript("OnLeave", function(self) self.text:SetTextColor(0.6, 0.6, 0.65) end)
    b:SetScript("OnClick", onClick)
    function b.SetLabel(_, s)
        b.text:SetText(s)
        b:SetSize(math.ceil(b.text:GetStringWidth()) + 8, 16)
    end
    b:SetLabel(label)
    return b
end

_G.StaticPopupDialogs["JAGODKA_ANNOUNCEMENT_DELETE"] = {
    text = "Delete this announcement?\n\n%s\n\nIt disappears for everyone.",
    button1 = "Delete",
    button2 = "Cancel",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(_, data)
        if data then Announcements.Delete(data) end
    end,
}

function Announcements.Attach(panel, c)
    c = c or {}
    local cards, editor = {}, nil
    local filter = nil   -- tag code or nil = all
    local PAGE_SIZE, page = 10, 1

    -- Header: title, short description, tag filter, the post button (officers)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -14)
    title:SetText("Announcements")
    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("LEFT", title, "RIGHT", 10, 0)
    sub:SetText("announcements from the officers of all our guilds")
    if addonTable.Help then addonTable.Help.Button(panel, "announcements", nil, "Announcements"):SetPoint("LEFT", sub, "RIGHT", 8, 0) end

    -- 1.1.1: Sync asks for the announcements again (as after login; the other guilds too when mine has none),
    -- then grays out for a minute, like the Sync buttons of Events and LFG
    local syncBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    syncBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -8)
    syncBtn:SetText("Sync")
    syncBtn:SetSize(math.ceil(syncBtn:GetFontString():GetStringWidth()) + 20, 24)
    syncBtn:SetScript("OnClick", function(self)
        Announcements.Request(true)
        self:Disable()
        C_Timer.After(REQUEST_COOLDOWN, function() self:Enable() end)
    end)
    syncBtn:SetScript("OnEnter", function(self)
        _G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
        _G.GameTooltip:SetText("Ask again for announcements you may have missed (once a minute).", 1, 1, 1, 1, true)
        _G.GameTooltip:Show()
    end)
    syncBtn:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)

    local newBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    newBtn:SetPoint("RIGHT", syncBtn, "LEFT", -6, 0)
    newBtn:SetText("+ New announcement")
    -- As wide as its text with 10 px on each side
    newBtn:SetSize(math.ceil(newBtn:GetFontString():GetStringWidth()) + 20, 24)

    local chips = {}
    local function UpdateChips()
        for _, chip in ipairs(chips) do
            local on = chip.code == filter
            chip.bg:SetColorTexture(chip.r, chip.g, chip.b, on and 0.35 or 0.08)
            chip.text:SetTextColor(on and 1 or chip.r * 0.8 + 0.2, on and 1 or chip.g * 0.8 + 0.2, on and 1 or chip.b * 0.8 + 0.2)
        end
    end
    local chipX = 4
    local chipDefs = { { code = nil, label = "All", r = 0.7, g = 0.7, b = 0.75 } }
    for _, t in ipairs(TAGS) do table.insert(chipDefs, t) end
    for _, def in ipairs(chipDefs) do
        local chip = CreateFrame("Button", nil, panel)
        chip.code, chip.r, chip.g, chip.b = def.code, def.r, def.g, def.b
        chip.bg = chip:CreateTexture(nil, "BACKGROUND")
        chip.bg:SetAllPoints()
        chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        chip.text:SetPoint("CENTER")
        chip.text:SetText(def.label)
        chip:SetSize(math.ceil(chip.text:GetStringWidth()) + 16, 18)
        chip:SetPoint("TOPLEFT", panel, "TOPLEFT", chipX, -36)
        chipX = chipX + chip:GetWidth() + 4
        chip:SetScript("OnClick", function(self) filter = self.code page = 1 UpdateChips() Announcements.Refresh() end)
        table.insert(chips, chip)
    end

    local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -60)
    box:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    if c.applyStyle then c.applyStyle(box) end
    local scroll = CreateFrame("ScrollFrame", "JagodkaAnnouncementsScroll", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -28, 6)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(10, 10)
    scroll:SetScrollChild(content)

    -- Pager under the list: < Page 1 of 3 (24) >; a new page starts at the top
    local pager = CreateFrame("Frame", nil, panel)
    pager:SetSize(260, 24)
    pager:SetPoint("BOTTOM", panel, "BOTTOM", 0, 2)
    pager:Hide()
    pager.text = pager:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pager.text:SetPoint("CENTER")
    local function Turn(delta)
        page = page + delta
        Announcements.Refresh()
        scroll:SetVerticalScroll(0)
    end
    pager.prev = CreateFrame("Button", nil, pager, "GameMenuButtonTemplate")
    pager.prev:SetSize(70, 22)
    pager.prev:SetPoint("LEFT", pager, "LEFT", 0, 0)
    pager.prev:SetText("< Prev")
    pager.prev:SetScript("OnClick", function() Turn(-1) end)
    pager.next = CreateFrame("Button", nil, pager, "GameMenuButtonTemplate")
    pager.next:SetSize(70, 22)
    pager.next:SetPoint("RIGHT", pager, "RIGHT", 0, 0)
    pager.next:SetText("Next >")
    pager.next:SetScript("OnClick", function() Turn(1) end)

    -- Nothing to show: a blueberry and a line
    local empty = CreateFrame("Frame", nil, box)
    empty:SetSize(300, 110)
    empty:SetPoint("CENTER", box, "CENTER", 0, 10)
    empty.icon = empty:CreateTexture(nil, "ARTWORK")
    empty.icon:SetSize(48, 48)
    empty.icon:SetPoint("TOP")
    empty.icon:SetTexture("Interface\\AddOns\\jagodka\\Media\\blueberry_one.tga")
    empty.icon:SetAlpha(0.6)
    empty.text = empty:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    empty.text:SetPoint("TOP", empty.icon, "BOTTOM", 0, -10)
    empty.text:SetTextColor(0.7, 0.7, 0.75)
    empty.sub = empty:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty.sub:SetPoint("TOP", empty.text, "BOTTOM", 0, -6)

    -- One card per post (reused)
    local function MakeCard()
        local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
        card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        card.accent = card:CreateTexture(nil, "ARTWORK")
        card.accent:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
        card.accent:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 1, 1)
        card.accent:SetWidth(3)
        card.tagBg = card:CreateTexture(nil, "ARTWORK")
        card.tag = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        card.tag:SetPoint("TOPLEFT", card, "TOPLEFT", 20, -12)
        card.tagBg:SetPoint("TOPLEFT", card.tag, "TOPLEFT", -6, 3)
        card.tagBg:SetPoint("BOTTOMRIGHT", card.tag, "BOTTOMRIGHT", 6, -3)
        card.marks = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        card.marks:SetPoint("LEFT", card.tag, "RIGHT", 12, 0)
        card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        card.title:SetJustifyH("LEFT")
        card.title:SetTextColor(1, 1, 1)
        card.meta = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.meta:SetJustifyH("LEFT")
        card.meta:SetTextColor(0.6, 0.6, 0.65)
        card.line = card:CreateTexture(nil, "ARTWORK")
        card.line:SetHeight(1)
        card.line:SetColorTexture(1, 1, 1, 0.07)
        card.body = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        card.body:SetJustifyH("LEFT")
        card.body:SetJustifyV("TOP")
        card.body:SetSpacing(3)
        card.body:SetTextColor(0.88, 0.88, 0.9)
        card.del = TextButton(card, "Delete", function()
            local d = _G.StaticPopup_Show("JAGODKA_ANNOUNCEMENT_DELETE", card.post and card.post.title or "")
            if d then d.data = card.post end
        end)
        card.del:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -9)
        card.pinBtn = TextButton(card, "Pin", function() if card.post then Announcements.TogglePin(card.post) end end)
        card.pinBtn:SetPoint("RIGHT", card.del, "LEFT", -4, 0)
        card.edit = TextButton(card, "Edit", function() if card.post and Announcements.OpenEditor then Announcements.OpenEditor(card.post) end end)
        card.edit:SetPoint("RIGHT", card.pinBtn, "LEFT", -4, 0)
        return card
    end

    local laidOutWidth = nil
    function Announcements.Refresh()
        if not panel:IsShown() then return end
        local width = math.floor(scroll:GetWidth())
        if width < 100 then return end
        laidOutWidth = width
        content:SetWidth(width)
        -- PAGE_SIZE posts a page; the pager under the list only when there is more than one page
        local list = {}
        for _, p in ipairs(db.posts) do if not filter or p.tag == filter then table.insert(list, p) end end
        local pages = math.max(1, math.ceil(#list / PAGE_SIZE))
        page = math.min(math.max(page, 1), pages)
        pager.text:SetText("Page " .. page .. " of " .. pages .. "  |cff808080(" .. #list .. ")|r")
        pager.prev:SetEnabled(page > 1)
        pager.next:SetEnabled(page < pages)
        pager:SetShown(pages > 1)
        box:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, (pages > 1) and 32 or 0)
        local y, shown = 4, 0
        for i = (page - 1) * PAGE_SIZE + 1, math.min(#list, page * PAGE_SIZE) do
            local p = list[i]
            if p then
                shown = shown + 1
                local card = cards[shown] or MakeCard()
                cards[shown] = card
                card.post = p
                local t = TAG_BY_CODE[p.tag] or TAGS[1]
                card:ClearAllPoints()
                card:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -y)
                card:SetWidth(width - 6)
                card:SetBackdropColor(0.10, 0.10, 0.13, 0.92)
                if p.pin then card:SetBackdropBorderColor(1, 0.82, 0, 0.45) else card:SetBackdropBorderColor(0.18, 0.18, 0.24, 0.9) end
                card.accent:SetColorTexture(t.r, t.g, t.b, 0.9)
                card.tag:SetText(t.label:upper())
                card.tag:SetTextColor(t.r, t.g, t.b)
                card.tagBg:SetColorTexture(t.r, t.g, t.b, 0.15)
                local marks = {}
                if p.pin then table.insert(marks, "|cffffd100Pinned|r") end
                if Announcements.IsUnread(p) then table.insert(marks, "|cff33ff66NEW|r") end
                card.marks:SetText(table.concat(marks, "  "))
                local inner = width - 6 - 36
                card.title:ClearAllPoints()
                card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 20, -34)
                card.title:SetWidth(inner)
                card.title:SetText(p.title or "")
                local name = c.colorName and c.colorName(p.author) or p.author
                local meta = name .. "  |cff808080·|r  |cff808080[|r|cff9d7fc0" .. Most.GuildTag(p.guild) .. "|r|cff808080]|r  |cff808080·|r  " .. When(p.created or 0)
                if p.editor and p.editor ~= p.author then meta = meta .. "  |cff808080·  edited by " .. p.editor .. "|r" end
                card.meta:ClearAllPoints()
                card.meta:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -5)
                card.meta:SetWidth(inner)
                card.meta:SetText(meta)
                card.line:ClearAllPoints()
                card.line:SetPoint("TOPLEFT", card.meta, "BOTTOMLEFT", 0, -9)
                card.line:SetWidth(inner)
                card.body:ClearAllPoints()
                card.body:SetPoint("TOPLEFT", card.line, "BOTTOMLEFT", 0, -9)
                card.body:SetWidth(inner)
                card.body:SetText((p.body and p.body ~= "") and p.body or "|cff808080(the text is still arriving...)|r")
                local manage = Announcements.CanManage(p)
                card.edit:SetShown(manage) card.del:SetShown(manage) card.pinBtn:SetShown(manage)
                card.pinBtn:SetLabel(p.pin and "Unpin" or "Pin")
                local h = 34 + card.title:GetStringHeight() + 5 + card.meta:GetStringHeight() + 19 + card.body:GetStringHeight() + 16
                card:SetHeight(math.floor(h + 0.5))
                card:Show()
                y = y + card:GetHeight() + 10
            end
        end
        for i = shown + 1, #cards do cards[i]:Hide() end
        content:SetHeight(y + 6)
        if shown == 0 then
            empty.text:SetText(filter and "Nothing with this tag" or "No announcements yet")
            empty.sub:SetText(filter and "Pick another tag above." or "Officers post announcements for all our guilds here.")
            empty:Show()
        else
            empty:Hide()
        end
        newBtn:SetShown(Announcements.CanPost() and true or false)
    end

    -- ========================================================================
    -- EDITOR (over the feed): tag, title, text, pinned
    -- ========================================================================
    editor = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    editor:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -36)
    editor:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    editor:SetFrameLevel(panel:GetFrameLevel() + 20)
    editor:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    editor:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
    editor:SetBackdropBorderColor(0.75, 0.25, 1, 0.6)
    editor:EnableMouse(true)
    editor:Hide()
    editor.head = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    editor.head:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -14)

    local tagLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tagLabel:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -46)
    tagLabel:SetText("Tag:")
    editor.tags = {}
    local tx = 60
    for _, t in ipairs(TAGS) do
        local b = CreateFrame("Button", nil, editor)
        b.t = t
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.text:SetPoint("CENTER")
        b.text:SetText(t.label:upper())
        b:SetSize(math.ceil(b.text:GetStringWidth()) + 18, 20)
        b:SetPoint("LEFT", tagLabel, "LEFT", tx - 16, 0)
        tx = tx + b:GetWidth() + 6
        b:SetScript("OnClick", function(self) editor.tag = self.t.code editor.UpdateTags() end)
        table.insert(editor.tags, b)
    end
    function editor.UpdateTags()
        for _, b in ipairs(editor.tags) do
            local on = b.t.code == editor.tag
            b.bg:SetColorTexture(b.t.r, b.t.g, b.t.b, on and 0.45 or 0.1)
            b.text:SetTextColor(on and 1 or b.t.r, on and 1 or b.t.g, on and 1 or b.t.b)
        end
    end

    editor.pin = CreateFrame("CheckButton", nil, editor, "UICheckButtonTemplate")
    editor.pin:SetSize(24, 24)
    editor.pin:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -110, -40)
    editor.pinText = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    editor.pinText:SetPoint("LEFT", editor.pin, "RIGHT", 2, 0)
    editor.pinText:SetText("Pin to the top")

    local titleLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLabel:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -78)
    titleLabel:SetText("Title:")
    editor.titleCount = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    editor.titleCount:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -16, -80)
    editor.titleBox = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    editor.titleBox:SetHeight(24)
    editor.titleBox:SetPoint("TOPLEFT", editor, "TOPLEFT", 22, -94)
    editor.titleBox:SetPoint("RIGHT", editor, "RIGHT", -16, 0)
    editor.titleBox:SetAutoFocus(false)
    editor.titleBox:SetFontObject(_G.ChatFontNormal)
    editor.titleBox:SetMaxBytes(TITLE_MAX + 1)
    editor.titleBox:SetScript("OnTextChanged", function(self) editor.titleCount:SetText(#(self:GetText() or "") .. "/" .. TITLE_MAX) end)
    editor.titleBox:SetScript("OnEscapePressed", editor.titleBox.ClearFocus)

    local bodyLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bodyLabel:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -128)
    bodyLabel:SetText("Text:")
    editor.bodyCount = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    editor.bodyCount:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -16, -130)
    local bodyBox = CreateFrame("Frame", nil, editor, "BackdropTemplate")
    bodyBox:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -146)
    bodyBox:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -16, 52)
    bodyBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    bodyBox:SetBackdropColor(0, 0, 0, 0.5)
    bodyBox:SetBackdropBorderColor(0.3, 0.3, 0.38, 0.8)
    local bodyScroll = CreateFrame("ScrollFrame", "JagodkaAnnouncementsBodyScroll", bodyBox, "UIPanelScrollFrameTemplate")
    bodyScroll:SetPoint("TOPLEFT", bodyBox, "TOPLEFT", 6, -6)
    bodyScroll:SetPoint("BOTTOMRIGHT", bodyBox, "BOTTOMRIGHT", -26, 6)
    editor.bodyBox = CreateFrame("EditBox", nil, bodyScroll)
    editor.bodyBox:SetMultiLine(true)
    editor.bodyBox:SetAutoFocus(false)
    editor.bodyBox:SetFontObject(_G.ChatFontNormal)
    editor.bodyBox:SetSize(300, 120)
    editor.bodyBox:SetMaxBytes(BODY_MAX + 1)
    bodyScroll:SetScrollChild(editor.bodyBox)
    bodyScroll:HookScript("OnSizeChanged", function(self, w) editor.bodyBox:SetWidth(math.max(50, w)) end)
    editor.bodyBox:SetScript("OnEscapePressed", editor.bodyBox.ClearFocus)
    if _G.ScrollingEdit_OnCursorChanged then editor.bodyBox:SetScript("OnCursorChanged", _G.ScrollingEdit_OnCursorChanged) end
    if _G.ScrollingEdit_OnUpdate then editor.bodyBox:SetScript("OnUpdate", function(self, elapsed) _G.ScrollingEdit_OnUpdate(self, elapsed, bodyScroll) end) end
    editor.bodyBox:SetScript("OnTextChanged", function(self) editor.bodyCount:SetText(#(self:GetText() or "") .. "/" .. BODY_MAX) end)
    bodyBox:EnableMouse(true)
    bodyBox:SetScript("OnMouseDown", function() editor.bodyBox:SetFocus() end)

    editor.status = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    editor.status:SetPoint("BOTTOMLEFT", editor, "BOTTOMLEFT", 16, 22)
    editor.status:SetJustifyH("LEFT")
    editor.cancel = CreateFrame("Button", nil, editor, "GameMenuButtonTemplate")
    editor.cancel:SetSize(100, 26)
    editor.cancel:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -16, 14)
    editor.cancel:SetText("Cancel")
    editor.cancel:SetScript("OnClick", function() editor:Hide() end)
    editor.publish = CreateFrame("Button", nil, editor, "GameMenuButtonTemplate")
    editor.publish:SetSize(110, 26)
    editor.publish:SetPoint("RIGHT", editor.cancel, "LEFT", -8, 0)
    editor.publish:SetScript("OnClick", function()
        local ok, why
        if editor.post then
            ok, why = Announcements.Edit(editor.post, editor.titleBox:GetText(), editor.bodyBox:GetText(), editor.tag, editor.pin:GetChecked())
        else
            ok, why = Announcements.Create(editor.titleBox:GetText(), editor.bodyBox:GetText(), editor.tag, editor.pin:GetChecked())
        end
        if ok then editor:Hide() Announcements.Refresh()
        else editor.status:SetText("|cffff5555" .. tostring(why) .. "|r") end
    end)

    -- post = nil: a new announcement
    function Announcements.OpenEditor(post)
        if not post then
            local ok, why = Announcements.CanPost()
            if not ok then _G.UIErrorsFrame:AddMessage(why, 1, 0.1, 0.1, 1) return end
        end
        editor.post = post
        editor.head:SetText(post and "Edit announcement" or "New announcement")
        editor.publish:SetText(post and "Save" or "Publish")
        editor.tag = post and post.tag or "N"
        editor.UpdateTags()
        editor.pin:SetChecked(post and post.pin or false)
        editor.titleBox:SetText(post and post.title or "")
        editor.bodyBox:SetText(post and post.body or "")
        editor.status:SetText("")
        editor:Show()
        editor.titleBox:SetFocus()
    end
    newBtn:SetScript("OnClick", function() Announcements.OpenEditor(nil) end)

    UpdateChips()
    panel:HookScript("OnShow", function()
        laidOutWidth = nil
        Announcements.Refresh()
        -- The NEW marks stay while the tab is open; the count on the tab goes
        Announcements.MarkSeen()
    end)
    panel:HookScript("OnHide", function() editor:Hide() end)
    scroll:HookScript("OnSizeChanged", function() if panel:IsShown() and math.floor(scroll:GetWidth()) ~= laidOutWidth then Announcements.Refresh() end end)
end
