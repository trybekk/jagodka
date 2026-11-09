-- ============================================================================
-- OFFICERS CHAT: a chat tab only for officers and guild masters of the listed guilds
-- ============================================================================
--  * Its own secret channel, from its own officers' key, so members (and their addons) never get its
--    messages: unlike General / Trade / LFG, which everyone with the addon receives.
--  * The officers' key { k, ts, by } (JagodkiChatDB.officerKey) travels ONLY by direct addon whisper
--    between officers by the guild rosters (OKEY), also between guilds: never over GUILD or the relays,
--    where members would see it. Forwarded packets (FW) are ignored here. The newer key wins.
--  * After login an officer asks a few online officers for the key (OKREQ); when nobody has one after
--    KEY_WAIT (+ a random wait), the officer creates it and whispers it to all online officers.
--  * A new key (everyone moves to a new channel): "New officers key" in Monitoring, or by itself when
--    someone on the channel is known from the rosters but is not an officer (e.g. a demoted officer).
--  * Messages live on the channel; missed ones come by whisper from another officer after login
--    (OHREQ / OHIST). Their log is separate from the shared chat's (JagodkiChatDB.officerLog), so the
--    shared chat's history sync never sends them. No fallback through the relays: without the channel a
--    message is not sent at all.
--  * A player who stops being an officer forgets the key and the log, and leaves the channel.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_Timer = addonTable.SafeTimer -- protected callbacks (safe.lua)
local CreateFrame = _G.CreateFrame
local GetChannelName = _G.GetChannelName
local GetServerTime = _G.GetServerTime
local GetTime = _G.GetTime
local strsplit = _G.strsplit
local ipairs, pairs, tostring, tonumber, type = _G.ipairs, _G.pairs, _G.tostring, _G.tonumber, _G.type
local table, math, string = _G.table, _G.math, _G.string

local Most = addonTable.Most
local Enc, Dec = Most.EncodeField, Most.DecodeField

local TAB = "Oficerowie"            -- the chat tab's key (core.lua)
local KEY_LENGTH = 16
local CHARS = "abcdefghijklmnopqrstuvwxyz0123456789"
local REQUEST_DELAYS = { 15, 75 }   -- seconds after login when we ask officers for the key and history
local ASK_OFFICERS = 3              -- how many online officers we ask
local KEY_WAIT = 120                -- without a key after this (+ jitter), an officer creates one (s)
local KEY_CREATE_JITTER = 60
local CHECK_INTERVAL = 60           -- key / channel / rank check (s)
local LIST_INTERVAL = 120           -- how often an officer reads the channel's member list (s)
local ROTATE_COOLDOWN = 600         -- a new key by itself at most this often (s)
local ANSWER_COOLDOWN = 60          -- the same officer gets our key / history at most this often (s)
local LOG_MAX = 300                 -- messages kept
local HISTORY_MAX = 50              -- messages sent to an officer who asks
local HISTORY_PART_BYTES = 150      -- text bytes per history whisper
local SAME_MESSAGE_WINDOW = 120     -- the same author and text within this many seconds = the same message
local RALLY_COOLDOWN = 300                 -- the button sends at most this often (s)
local RALLY_SHOW_AGAIN = 60                -- a receiver shows it at most this often, also from several officers (s)
local lastRallySent, lastRallyShown = -RALLY_COOLDOWN, -RALLY_SHOW_AGAIN

local Officers = {}
addonTable.Officers = Officers
Officers.TAB = TAB

-- Context from core.lua: isMeOfficer(), isKnownOfficer(name), onlineOfficers() -> names, onChanged()
local ctx = nil
function Officers.Init(c) ctx = c end

local current = nil       -- { k, ts, by }
local joinedName = nil
local log = {}            -- { id, ts, guild, author, tab, src, text, via }
local keySeen = false
local loginAt = math.huge
local lastRotation = -ROTATE_COOLDOWN
local answeredAt = {}     -- officer -> when we last sent them the key
local historyAt = {}      -- officer -> when we last sent them history
local partial = {}        -- history parts: "ts|author" -> { got, count, total, guild }
local createJitter = math.random(0, KEY_CREATE_JITTER)
local lineSeq = 0

local function Monitor() return addonTable.Monitor end
local function Note(text, isError) if Monitor() then Monitor().Channel("Officers chat: " .. text, isError) end end
local function IsMeOfficer() return ctx ~= nil and ctx.isMeOfficer() end
local function IsOfficer(name) return ctx ~= nil and (name == Most.MyName() and ctx.isMeOfficer() or ctx.isKnownOfficer(name)) end

-- ============================================================================
-- CHANNEL FROM THE KEY (another hash than the shared chat's, so the two never meet)
-- ============================================================================
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

local function Derive(k)
    local faction = (_G.UnitFactionGroup("player") == "Horde") and "h" or "a"
    local name = "Jgo" .. faction .. Base36(Hash(k .. "o" .. faction, 7919), 6)
    local password = Base36(Hash(k, 15485863), 6) .. Base36(Hash(k .. "p", 32452843), 6)
    return name, password
end

function Officers.ChannelName()
    return current and (Derive(current.k)) or nil
end

function Officers.ChannelId()
    local name = Officers.ChannelName()
    if not name then return nil end
    local id = GetChannelName(name)
    return (id and id > 0) and id or nil
end

local function Join()
    if not current or not IsMeOfficer() then return end
    local name, password = Derive(current.k)
    if joinedName and joinedName ~= name and _G.LeaveChannelByName then _G.LeaveChannelByName(joinedName) end
    joinedName = name
    if not Officers.ChannelId() then _G.JoinChannelByName(name, password) end
    Most.HideFromChat(name)
end

-- ============================================================================
-- THE KEY
-- ============================================================================
local function Save()
    _G.JagodkiChatDB = _G.JagodkiChatDB or {}
    _G.JagodkiChatDB.officerKey = current
end

-- The newer key wins; at the same time the smaller one
local function Wins(k, ts)
    if not current then return true end
    if ts ~= current.ts then return ts > (current.ts or 0) end
    return k < current.k
end

local function Apply(k, ts, by)
    if not Wins(k, ts) then return false end
    current = { k = k, ts = ts, by = by }
    Save()
    Note("key from " .. tostring(by))
    Join()
    return true
end

local function Payload() return table.concat({ Enc(current.k), tostring(current.ts), Enc(current.by) }, ":") end

local function SendKey(target)
    if not current or target == Most.MyName() then return end
    answeredAt[target] = GetTime()
    Most.Whisper(target, "OKEY", Payload(), "high")
end

local function OnlineOfficers()
    local list = {}
    for _, name in ipairs(ctx and ctx.onlineOfficers() or {}) do
        if name ~= Most.MyName() then table.insert(list, name) end
    end
    return list
end

-- A few online officers at random
local function SomeOfficers(n)
    local list, picked = OnlineOfficers(), {}
    while #list > 0 and #picked < n do table.insert(picked, table.remove(list, math.random(#list))) end
    return picked
end

local function NewKeyText()
    local seed = Hash(Most.MyName() .. tostring(GetTime()) .. tostring(GetServerTime()) .. tostring(math.random()), 5381)
    local out = {}
    for i = 1, KEY_LENGTH do
        local d = (math.random(0, 35) + seed) % 36
        out[i] = CHARS:sub(d + 1, d + 1)
        seed = math.floor(seed / 36) + math.random(0, 9999)
    end
    return table.concat(out)
end

-- A new officers' key, whispered to every online officer. force: by hand (no cooldown).
function Officers.Create(reason, force)
    if not IsMeOfficer() then return false end
    if not force and GetTime() - lastRotation < ROTATE_COOLDOWN then return false end
    lastRotation = GetTime()
    Apply(NewKeyText(), math.max(GetServerTime(), ((current and current.ts) or 0) + 1), Most.MyName())
    for _, name in ipairs(OnlineOfficers()) do SendKey(name) end
    Note("new key: " .. reason)
    return true
end

local function Forget(reason)
    if current or #log > 0 then Note("key and messages forgotten: " .. reason) end
    if joinedName and _G.LeaveChannelByName then _G.LeaveChannelByName(joinedName) end
    current, joinedName = nil, nil
    Save()
    for i = #log, 1, -1 do log[i] = nil end
    if ctx then ctx.onChanged() end
end

-- ============================================================================
-- MESSAGES
-- ============================================================================
function Officers.GetLog() return log end

local function HasSame(e)
    for i = #log, math.max(1, #log - 100), -1 do
        local o = log[i]
        if o.author == e.author and o.text == e.text and math.abs((o.ts or 0) - (e.ts or 0)) <= SAME_MESSAGE_WINDOW then return true end
    end
    return false
end

-- Listeners for new officers' messages (the game chat tab, chattab.lua): fn(entry, live)
local listeners = {}
function Officers.OnNewMessage(fn) table.insert(listeners, fn) end

-- live: from the channel now (not history from another officer)
local function Add(e, live)
    if HasSame(e) then return end
    local i = #log
    while i > 0 and (log[i].ts or 0) > e.ts do i = i - 1 end
    table.insert(log, i + 1, e)
    while #log > LOG_MAX do table.remove(log, 1) end
    if ctx then ctx.onChanged() end
    for _, fn in ipairs(listeners) do fn(e, live) end
end

-- Sub-realms (0.15.2): the officers channel, like every channel made by players, exists once per WoW: Forever
-- sub-realm. Officers online who are not on my copy of it (by its member list, read every few minutes) get my
-- message as a direct whisper (OMSG), which reaches every sub-realm; nothing goes through GUILD or a relay.
local onChannel = {}            -- officer -> when last seen on my officers channel's member list
local DIRECT_PART_BYTES = 200
function Officers.SendDirect(text)
    if not IsMeOfficer() or not text or text == "" then return end
    local now, missing = GetTime(), {}
    for _, name in ipairs(OnlineOfficers()) do
        if name ~= Most.MyName() and now - (onChannel[name] or -math.huge) > 600 then table.insert(missing, name) end
    end
    if #missing == 0 then return end
    local ts = GetServerTime()
    for _, part in ipairs(Most.SplitText(text, DIRECT_PART_BYTES)) do
        for _, name in ipairs(missing) do Most.Whisper(name, "OMSG", ts .. ":" .. part, "high") end
    end
    Note("message also whispered to " .. #missing .. " officers not on my officers channel (another sub-realm)")
end

-- From core.lua (the input, a hardware event): true when sent; otherwise false and the reason
function Officers.Say(text)
    if not IsMeOfficer() then return false, "only officers can write here" end
    local id = Officers.ChannelId()
    if not id then return false, current and "joining the officers channel, try again in a moment" or "no officers key yet, wait a moment (or /jagodka sync)" end
    for _, part in ipairs(Most.SplitText(text, Most.MAX_CHAT_BYTES)) do _G.SendChatMessage(part, "CHANNEL", nil, id) end
    Officers.SendDirect(text)
    return true
end

-- A message on the officers channel (bridge.lua): only from officers by the rosters
function Officers.HandleMessage(text, playerName, lineID)
    if not IsMeOfficer() or not text or not playerName then return end
    local author = Most.PlayerKey(playerName)
    if not IsOfficer(author) then
        Note("message from " .. author .. ", who is not an officer by the rosters, hidden", true)
        return
    end
    text = Most.SanitizeChat(text)
    if text == "" then return end
    local p = Most.FindKnownPlayer(author)
    local ts = GetServerTime()
    lineSeq = lineSeq + 1
    Add({ id = string.format("O.%s.%x.%s", author, ts, tostring(lineID or lineSeq)), ts = ts, guild = (p and p.guild) or Most.MyGuild() or "?",
        author = author, tab = TAB, src = "A", text = text, via = "C" }, true)
end

-- ============================================================================
-- HISTORY BETWEEN OFFICERS (whispers only)
-- ============================================================================
local function Newest()
    local n = 0
    for _, e in ipairs(log) do if (e.ts or 0) > n then n = e.ts end end
    return n
end

local function SendHistory(target, since)
    if GetTime() - (historyAt[target] or -ANSWER_COOLDOWN) < ANSWER_COOLDOWN then return end
    local list = {}
    for _, e in ipairs(log) do if e.ts > since then table.insert(list, e) end end
    if #list == 0 then return end
    historyAt[target] = GetTime()
    while #list > HISTORY_MAX do table.remove(list, 1) end
    for _, e in ipairs(list) do
        local parts = Most.SplitText(e.text, HISTORY_PART_BYTES)
        for i, part in ipairs(parts) do
            Most.Whisper(target, "OHIST", table.concat({ tostring(e.ts), Enc(e.author), Enc(e.guild), tostring(i), tostring(#parts), part }, ":"), "low")
        end
    end
end

local function HandleHistoryPart(payload)
    local ts, author, guild, idx, total, text = strsplit(":", payload, 6)
    ts, idx, total = tonumber(ts), tonumber(idx), tonumber(total)
    author, guild = Most.Plain(Dec(author)), Most.Plain(Dec(guild))
    if not (ts and idx and total and author and text) or total < 1 or total > 10 or idx < 1 or idx > total then return end
    if not IsOfficer(author) then return end
    local key = ts .. "|" .. author
    local p = partial[key] or { got = {}, count = 0, total = total, guild = guild, at = GetTime() }
    partial[key] = p
    if not p.got[idx] then p.got[idx] = text p.count = p.count + 1 end
    if p.count < p.total then return end
    partial[key] = nil
    text = Most.SanitizeChat(table.concat(p.got))
    if text ~= "" then Add({ id = "OH." .. key, ts = ts, guild = p.guild or "?", author = author, tab = TAB, src = "A", text = text, via = "H" }) end
end

-- ============================================================================
-- PACKETS (core.lua); only direct whispers from officers count. Returns true if handled.
-- ============================================================================
function Officers.HandlePacket(pType, payload, senderName, channel)
    if pType ~= "OKEY" and pType ~= "OKREQ" and pType ~= "OHREQ" and pType ~= "OHIST" and pType ~= "ORALLY" and pType ~= "OMSG" then return false end
    -- Never through GUILD or a relay (FW): the key and the messages must not pass through members' clients
    if channel ~= "WHISPER" or senderName == Most.MyName() or not IsMeOfficer() or not IsOfficer(senderName) then return true end
    if pType == "OKEY" then
        local kEnc, ts, byEnc = strsplit(":", payload, 3)
        local k, by = Dec(kEnc), Most.Plain(Dec(byEnc))
        ts = tonumber(ts)
        if not (k and ts and by) or #k ~= KEY_LENGTH or k:find("[^a-z0-9]") or not IsOfficer(by) then return true end
        keySeen = true
        if not Apply(k, ts, by) and current and current.k ~= k and GetTime() - (answeredAt[senderName] or -ANSWER_COOLDOWN) >= ANSWER_COOLDOWN then
            -- Theirs loses to ours: they get ours
            SendKey(senderName)
        end
    elseif pType == "OKREQ" then
        local theirs = tonumber(payload) or 0
        if current and current.ts ~= theirs and GetTime() - (answeredAt[senderName] or -ANSWER_COOLDOWN) >= ANSWER_COOLDOWN then
            if theirs > (current.ts or 0) then
                -- Theirs is newer: we ask for it
                Most.Whisper(senderName, "OKREQ", tostring(current.ts), "high")
            else
                SendKey(senderName)
            end
        elseif not current and theirs > 0 then
            Most.Whisper(senderName, "OKREQ", "0", "high")
        end
    elseif pType == "OHREQ" then
        SendHistory(senderName, tonumber(payload) or 0)
    elseif pType == "OHIST" then
        HandleHistoryPart(payload)
    elseif pType == "OMSG" then
        -- An officer on another sub-realm (Officers.SendDirect): shown like a line from the channel
        local ts, text = strsplit(":", payload, 2)
        ts = tonumber(ts)
        text = text and Most.SanitizeChat(text)
        if ts and text and text ~= "" then
            local p = Most.FindKnownPlayer(senderName)
            Add({ id = string.format("OW.%s.%x.%d", senderName, ts, math.random(0, 99999)), ts = ts, guild = (p and p.guild) or "?",
                author = senderName, tab = TAB, src = "A", text = text, via = "W" }, true)
        end
    elseif pType == "ORALLY" then
        if GetTime() - lastRallyShown >= RALLY_SHOW_AGAIN then
            lastRallyShown = GetTime()
            Officers.ShowRally()
            Note("rally from " .. senderName)
        end
    end
    return true
end

-- After login and "/jagodka sync": the key and the missed messages from a few online officers
function Officers.Request()
    if not IsMeOfficer() then return end
    for _, name in ipairs(SomeOfficers(ASK_OFFICERS)) do
        Most.Whisper(name, "OKREQ", tostring((current and current.ts) or 0), "high")
    end
    for _, name in ipairs(SomeOfficers(2)) do Most.Whisper(name, "OHREQ", tostring(Newest()), "low") end
end

-- ============================================================================
-- CHANNEL WATCH (bridge.lua calls these)
-- ============================================================================
-- Member list of the officers channel: someone known from the rosters who is not an officer = a new key
function Officers.HandleList(list)
    if not IsMeOfficer() then return end
    for raw in tostring(list or ""):gmatch("[^,]+") do
        local name = Most.PlayerKey((raw:gsub("^%s+", ""):gsub("^[%*@%+]+", "")))
        if name and name ~= "" then onChannel[name] = GetTime() end
        if name and name ~= "" and name ~= Most.MyName() and not IsOfficer(name) then
            -- Only a rank known from the rosters counts (a player whose roster has not come yet is not a reason)
            local _, rankIndex = addonTable.Roster.GetRank(name)
            if rankIndex ~= nil then
                Note(name .. " is on the officers channel but is not an officer", true)
                Officers.Create(name .. " on the channel is not an officer")
                return
            end
            Note(name .. " is on the officers channel, rank not known from the rosters yet", true)
        end
    end
end

function Officers.OnNotice(notice)
    if notice == "WRONG_PASSWORD" or notice == "BANNED" then
        Note((notice == "BANNED") and "banned from the officers channel" or "the officers channel has another password", true)
        Officers.Create("officers channel unavailable")
    elseif notice == "YOU_LEFT" then
        if current and IsMeOfficer() then C_Timer.After(5, Join) end
    elseif notice == "YOU_JOINED" or notice == "YOU_CHANGED" then
        local name = Officers.ChannelName()
        if name then Most.HideFromChat(name) end
    end
end

-- ============================================================================
-- RALLY: a big red message in the middle of the screen with a sound, for officers (Monitoring button)
-- ============================================================================
-- The button whispers ORALLY to every online officer (direct whispers only, as the key; members never get
-- it), at most every RALLY_COOLDOWN. A receiver shows it for an officer by the rosters, at most every RALLY_SHOW_AGAIN.
local RALLY_TEXT = "OFICEROWIE!\nNamawiajcie wszystkich do instalacji addonu\nJagodki Nadina - Community!"
local RALLY_FOR, RALLY_FADE = 3, 0.6       -- seconds shown, then fading out
local rally = nil

local function RallyFrame()
    if rally then return rally end
    rally = CreateFrame("Frame", nil, _G.UIParent)
    rally:SetSize(900, 160)
    rally:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 180)
    rally:SetFrameStrata("FULLSCREEN_DIALOG")
    rally.text = rally:CreateFontString(nil, "OVERLAY")
    rally.text:SetFont("Fonts\\FRIZQT__.TTF", 34, "THICKOUTLINE")
    rally.text:SetTextColor(1, 0.1, 0.1)
    rally.text:SetShadowOffset(2, -2)
    rally.text:SetAllPoints()
    rally.text:SetJustifyH("CENTER")
    rally:Hide()
    addonTable.SafeScript(rally, "OnUpdate", "officers.lua:403", function(self, elapsed)
        self.age = self.age + elapsed
        local showFor = self.showFor or RALLY_FOR
        if self.age > showFor + RALLY_FADE then self:Hide() return end
        self:SetAlpha(self.age > showFor and (1 - (self.age - showFor) / RALLY_FADE) or 1)
    end)
    return rally
end

-- The same big message for other uses (the chat test request): text, seconds shown, and the chat font, which
-- has the Polish letters the big game font lacks
function Officers.ShowBanner(text, seconds, chatFont)
    local f = RallyFrame()
    f.text:SetFont(chatFont and "Fonts\\ARIALN.TTF" or "Fonts\\FRIZQT__.TTF", chatFont and 30 or 34, "THICKOUTLINE")
    f.text:SetText(text)
    f.showFor = seconds or RALLY_FOR
    f.age = 0
    f:SetAlpha(1)
    f:Show()
    if _G.PlaySound then _G.PlaySound((_G.SOUNDKIT and _G.SOUNDKIT.RAID_WARNING) or 8959, "Master") end
end

-- Chat test request (core.lua sends CTEST to everyone; an officer by the rosters asks): the big message for
-- everyone, at most once a minute also when several officers ask
local CHAT_TEST_TEXT = "TEST CZATÓW!\nNapisz krótką wiadomość testową na każdym czacie społeczności:\nGeneral (/jnglobal), Trade (/jntrade) i LFG (/jnlfg)"
local lastChatTestShown = -60
function Officers.ShowChatTest()
    if GetTime() - lastChatTestShown < 60 then return end
    lastChatTestShown = GetTime()
    Officers.ShowBanner(CHAT_TEST_TEXT, 6, true)
    Note("global chat test request shown")
end

function Officers.ShowRally()
    local f = RallyFrame()
    f.text:SetFont("Fonts\\FRIZQT__.TTF", 34, "THICKOUTLINE")
    f.showFor = RALLY_FOR
    f.text:SetText(RALLY_TEXT)
    f.age = 0
    f:SetAlpha(1)
    f:Show()
    -- Played once: the same raid warning sound as the update reminder (update.lua)
    if _G.PlaySound then _G.PlaySound((_G.SOUNDKIT and _G.SOUNDKIT.RAID_WARNING) or 8959, "Master") end
end

-- Monitoring button: to every online officer and to me. Returns ok, or false and seconds to wait / nil (not an officer)
function Officers.SendRally()
    if not IsMeOfficer() then return false end
    local wait = RALLY_COOLDOWN - (GetTime() - lastRallySent)
    if wait > 0 then return false, math.ceil(wait) end
    lastRallySent = GetTime()
    local sent = 0
    for _, name in ipairs(OnlineOfficers()) do
        Most.Whisper(name, "ORALLY", "1", "high")
        sent = sent + 1
    end
    lastRallyShown = GetTime()
    Officers.ShowRally()
    return true, sent
end

-- For Monitoring: the state, never the key or the channel name
function Officers.GetMonitorInfo()
    return { hasKey = current ~= nil, channelId = Officers.ChannelId(), by = current and current.by, messages = #log }
end

-- ============================================================================
-- EVENTS
-- ============================================================================
local notOfficerChecks = 0
local function Check()
    if not ctx then return end
    if not IsMeOfficer() then
        -- Only once we know the guild and rank (both come a moment after login), and twice in a row, so a
        -- moment without the rank (loading) does not wipe the officers' messages
        notOfficerChecks = notOfficerChecks + 1
        if notOfficerChecks >= 2 and _G.IsInGuild() and Most.MyGuild() and (current or #log > 0) then Forget("no longer an officer") end
        return
    end
    notOfficerChecks = 0
    if current then
        if not Officers.ChannelId() then Join() end
        return
    end
    if keySeen or GetTime() - loginAt < KEY_WAIT + createJitter then return end
    Officers.Create("no officers key yet")
end

local Listener = CreateFrame("Frame")
Listener:RegisterEvent("ADDON_LOADED")
Listener:RegisterEvent("PLAYER_LOGIN")
addonTable.SafeScript(Listener, "OnEvent", "officers.lua:494", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        _G.JagodkiChatDB = _G.JagodkiChatDB or {}
        local saved = _G.JagodkiChatDB.officerKey
        if type(saved) == "table" and type(saved.k) == "string" and #saved.k == KEY_LENGTH and tonumber(saved.ts) then current = saved end
        local savedLog = _G.JagodkiChatDB.officerLog
        if type(savedLog) == "table" then log = savedLog end
        _G.JagodkiChatDB.officerLog = log
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        loginAt = GetTime()
        for _, delay in ipairs(REQUEST_DELAYS) do C_Timer.After(delay, Officers.Request) end
        -- Join only when the rank is known (Check), never before
        C_Timer.NewTicker(CHECK_INTERVAL, Check)
        C_Timer.After(20, Check)
        C_Timer.NewTicker(LIST_INTERVAL, function()
            if IsMeOfficer() and Officers.ChannelId() then Most.ListChannel(Officers.ChannelName()) end
        end)
        -- Unfinished history parts are dropped after a while
        C_Timer.NewTicker(60, function()
            for key, p in pairs(partial) do if GetTime() - p.at > 60 then partial[key] = nil end end
        end)
    end
end)
