-- ============================================================================
-- PROFESSIONS: icons and skill levels in the Members table
-- ============================================================================
--  * The game gives skill levels only for your own character, so every addon sends its own.
--  * PROF goes over GUILD and relays at login and after a change (checked once a minute), and by
--    whisper from the relay in answer to a PING. Data of others comes from what was saved earlier and
--    from their next login or change.
--  * Format: "A=300/300,H=285/300" with profession codes rather than names, so clients in different
--    languages understand each other; "-" = no professions.
--  * Received data is kept in JagodkiChatDB.professions, so it also shows for offline players.
--    Players without the addon stay unknown.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_Timer = addonTable.SafeTimer -- protected callbacks (safe.lua)
local CreateFrame = _G.CreateFrame
local GetGuildInfo = _G.GetGuildInfo
local GetServerTime = _G.GetServerTime
local GetTime = _G.GetTime
local UnitName = _G.UnitName
local date = _G.date
local ipairs, pairs, tonumber, tostring, type, pcall, select = _G.ipairs, _G.pairs, _G.tonumber, _G.tostring, _G.type, _G.pcall, _G.select
local table = _G.table

local Most = addonTable.Most

local CHECK_INTERVAL = 60    -- how often we check our own skills (s)
local SEND_INTERVAL = 600    -- a change of our own skills is sent at most this often (s)
local FIRST_SEND_DELAY = 6   -- first send after login (s)
local SYNC_REQUEST_DELAY = 10 -- after login we ask a guildmate for the professions we do not have yet (s)
local SYNC_RETRY_AFTER = 25  -- no answer after this many seconds: we ask again
local SYNC_MAX_RETRIES = 2
local NAME_ASK_COOLDOWN = 300 -- the Members tab asks about the same player at most this often (s)
local SYNC_MAX_ENTRIES = 300 -- at most this many players in one answer (the most recently updated)
local SYNC_PACKET_BYTES = 200 -- entries per PSYNC packet, below the addon packet limit
local MAX_ICONS = 2          -- icons in the column; the rest shows in the tooltip
local ICON_SIZE = 14
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- code, English name, spell (localized name and icon), primary = shown as an icon
local PROFESSIONS = {
    { code = "A", name = "Alchemy", spell = 2259, primary = true },
    { code = "B", name = "Blacksmithing", spell = 2018, primary = true },
    { code = "E", name = "Enchanting", spell = 7411, primary = true },
    { code = "G", name = "Engineering", spell = 4036, primary = true },
    -- The Herbalism spell has another name ("Herb Gathering"), hence the names of other client languages
    { code = "H", name = "Herbalism", spell = 2366, primary = true, also = { "Kräuterkunde", "Herboristerie", "Herboristería", "Травничество" } },
    { code = "L", name = "Leatherworking", spell = 2108, primary = true },
    { code = "M", name = "Mining", spell = 2575, primary = true },
    { code = "S", name = "Skinning", spell = 8613, primary = true },
    { code = "T", name = "Tailoring", spell = 3908, primary = true },
    { code = "C", name = "Cooking", spell = 2550 },
    { code = "F", name = "First Aid", spell = 3273 },
    { code = "X", name = "Fishing", spell = 7620 },
}

local Professions = {}
addonTable.Professions = Professions

-- Context from core.lua: activePlayers, isGuildAllowed, onChanged
local ctx = nil
local known = {}       -- name -> { p = { code = { rank, max } }, ts = time }; JagodkiChatDB.professions
local lastSent = nil   -- the last payload sent over GUILD
local lastError = nil  -- the last error reading own professions, logged once
local lastSentAt = 0   -- when lastSent went out

-- Spell name and icon: GetSpellInfo on older clients, C_Spell.GetSpellInfo (a table) on newer ones (it may
-- be missing on WoW Forever); without either, the English name and a question mark
local function SpellInfo(spell)
    if _G.GetSpellInfo then
        local name, _, icon = _G.GetSpellInfo(spell)
        return name, icon
    end
    local info = _G.C_Spell and _G.C_Spell.GetSpellInfo and _G.C_Spell.GetSpellInfo(spell)
    if type(info) == "table" then return info.name, info.iconID end
    return nil, nil
end
local function DisplayName(def) return (SpellInfo(def.spell)) or def.name end
local function IconOf(def) return select(2, SpellInfo(def.spell)) or UNKNOWN_ICON end

-- Skill line name in the client's language -> code
local function NameToCode()
    local map = {}
    for _, def in ipairs(PROFESSIONS) do
        map[def.name] = def.code
        map[DisplayName(def)] = def.code
        for _, other in ipairs(def.also or {}) do map[other] = def.code end
    end
    return map
end

-- ============================================================================
-- MY OWN SKILLS
-- ============================================================================
-- A collapsed section in the Skills window hides its lines, so professions already known stay then
-- Skill lines: GetSkillLineInfo on older clients; newer ones only have GetProfessions / GetProfessionInfo
local function ScanOwn()
    local map, found, collapsed = NameToCode(), {}, false
    if _G.GetNumSkillLines and _G.GetSkillLineInfo then
        for i = 1, _G.GetNumSkillLines() or 0 do
            local name, isHeader, isExpanded, rank, _, _, maxRank = _G.GetSkillLineInfo(i)
            if isHeader then
                if not isExpanded then collapsed = true end
            elseif map[name] then
                found[map[name]] = { rank, maxRank }
            end
        end
    elseif _G.GetProfessions and _G.GetProfessionInfo then
        -- GetProfessions returns prof1, prof2, archaeology, fishing, cooking (first aid on some clients), any of
        -- them nil when not learned: ipairs stopped at the first nil, so without archaeology fishing and
        -- cooking were never read. Every position is checked instead.
        local indexes = { _G.GetProfessions() }
        for i = 1, _G.select("#", _G.GetProfessions()) do
            local index = indexes[i]
            if index then
                local name, _, rank, maxRank = _G.GetProfessionInfo(index)
                if name and map[name] then found[map[name]] = { rank, maxRank } end
            end
        end
    end
    if collapsed then
        local mine = known[Most.MyName()]
        for code, value in pairs(mine and mine.p or {}) do
            if not found[code] then found[code] = value end
        end
    end
    return found
end

local function Encode(list)
    local parts = {}
    for code, value in pairs(list) do table.insert(parts, code .. "=" .. value[1] .. "/" .. value[2]) end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ",") or "-"
end

local function SaveOwn()
    local list = ScanOwn()
    known[Most.MyName()] = { p = list, ts = GetServerTime() }
    return Encode(list)
end

-- My own row always shows my professions; they are sent only in a listed guild. A failure reading them
-- (a game function missing on this client) goes to Monitoring instead of stopping silently.
local function SendOwnIfChanged()
    if not ctx then return end
    local ok, payload = pcall(SaveOwn)
    if not ok then
        if addonTable.Monitor and payload ~= lastError then addonTable.Monitor.Error("Reading own professions failed: " .. tostring(payload)) end
        lastError = payload
        return
    end
    if not ctx.isGuildAllowed((GetGuildInfo("player"))) then
        if ctx.onChanged then ctx.onChanged() end
        return
    end
    -- A change goes out at most every SEND_INTERVAL (the first one at once): on a fresh server skills go up
    -- every few minutes, and every send reaches all guilds through the relays. My own row updates at once.
    if payload ~= lastSent then
        if ctx.onChanged then ctx.onChanged() end
        if lastSent and GetTime() - lastSentAt < SEND_INTERVAL then return end
        lastSent, lastSentAt = payload, GetTime()
        Most.Send("PROF", payload, "low")
    end
end

-- core.lua calls this when answering a PING
function Professions.SendTo(name)
    Most.Whisper(name, "PROF", SaveOwn(), "low")
end

-- ============================================================================
-- RECEIVING
-- ============================================================================
-- Player of a listed guild (status packet or guild roster, bridge.lua)
local function IsAllowedPlayer(name)
    return Most.FindKnownPlayer(name) ~= nil
end

local function Decode(text)
    local valid, list = {}, {}
    for _, def in ipairs(PROFESSIONS) do valid[def.code] = true end
    for code, rank, maxRank in (text or ""):gmatch("(%u)=(%d+)/(%d+)") do
        if valid[code] then list[code] = { tonumber(rank), tonumber(maxRank) } end
    end
    return list
end

-- ============================================================================
-- SYNC AFTER LOGIN (like the chat history): professions of players who were online before us
-- ============================================================================
-- PREQ:time = "send me what is newer than this"; stays in the guild (bridge.lua, Route), so one guildmate
-- answers: PCLAIM tells the others someone is already answering, PSYNC brings the entries by whisper.
-- PSYNC entries: "Name Surname@time@A=300/300,H=285/300;..." ("@" and ";" are never in names).
local pendingRequests = {}  -- requester -> true until someone else has answered
local answered = false      -- our current request got an answer (PCLAIM for us or PSYNC)
local Request               -- defined below

local function NewestKnown()
    local newest, me = 0, Most.MyName()
    for name, data in pairs(known) do
        if name ~= me and (data.ts or 0) > newest then newest = data.ts end
    end
    return newest
end

-- Sends entries { name, ts, p } to the requester in PSYNC packets
local function SendEntries(requester, entries, priority)
    local chunk = ""
    local function Flush()
        if chunk ~= "" then Most.Whisper(requester, "PSYNC", chunk, priority) end
        chunk = ""
    end
    for _, e in ipairs(entries) do
        local text = e.name .. "@" .. e.ts .. "@" .. Encode(e.p)
        if chunk ~= "" and #chunk + 1 + #text > SYNC_PACKET_BYTES then Flush() end
        chunk = (chunk == "") and text or (chunk .. ";" .. text)
    end
    Flush()
end

-- What we know newer than "since" (PREQ)
local function EntriesSince(requester, since)
    local entries = {}
    for name, data in pairs(known) do
        if name ~= requester and (data.ts or 0) > since then table.insert(entries, { name = name, ts = data.ts, p = data.p }) end
    end
    -- The newest first, at most SYNC_MAX_ENTRIES, so a fresh install does not keep the queue busy for long
    table.sort(entries, function(a, b) return a.ts > b.ts end)
    while #entries > SYNC_MAX_ENTRIES do table.remove(entries) end
    return entries
end

-- Members tab: the players on the shown page whose professions we do not have (core.lua). Each player is
-- asked about at most every NAME_ASK_COOLDOWN, because players without the addon never have any data.
-- PREQN:id:Name;Name;... stays in the guild; one guildmate answers (PCLAIM "requester#id") with what it knows.
local nameRequestSeq, askedAt = 0, {}
function Professions.RequestNames(names)
    if not _G.IsInGuild() then return end
    local me, now, missing = Most.MyName(), GetTime(), {}
    for _, name in ipairs(names) do
        if name ~= me and not known[name] and now - (askedAt[name] or -NAME_ASK_COOLDOWN) >= NAME_ASK_COOLDOWN then
            askedAt[name] = now
            table.insert(missing, name)
        end
    end
    if #missing == 0 then return end
    nameRequestSeq = nameRequestSeq + 1
    local chunk, part = "", 0
    local function Flush()
        if chunk == "" then return end
        part = part + 1
        Most.Send("PREQN", nameRequestSeq .. "." .. part .. ":" .. chunk, "high")
        chunk = ""
    end
    for _, name in ipairs(missing) do
        if chunk ~= "" and #chunk + 1 + #name > SYNC_PACKET_BYTES then Flush() end
        chunk = (chunk == "") and name or (chunk .. ";" .. name)
    end
    Flush()
end

-- What we know about the asked players (PREQN)
local function EntriesFor(requester, list)
    local entries = {}
    for name in list:gmatch("[^;]+") do
        local data = known[name]
        if data and name ~= requester then table.insert(entries, { name = name, ts = data.ts or 0, p = data.p }) end
    end
    return entries
end

-- Asks the guild; without an answer within SYNC_RETRY_AFTER (the answering player logged out, a lost
-- packet) we ask again, up to SYNC_MAX_RETRIES times
Request = function(retry)
    if not _G.IsInGuild() then return end
    answered = false
    Most.Send("PREQ", tostring(NewestKnown()), "low")
    if retry < SYNC_MAX_RETRIES then
        C_Timer.After(SYNC_RETRY_AFTER, function()
            if not answered then Request(retry + 1) end
        end)
    end
end

-- "/jagodka sync" (core.lua): ask the guild again, with the retries
function Professions.Resync() Request(0) end

-- Called from core.lua; returns true if the packet was handled
function Professions.HandlePacket(pType, payload, senderName)
    if pType == "PROF" then
        if senderName == Most.MyName() or not IsAllowedPlayer(senderName) then return true end
        known[senderName] = { p = Decode(payload), ts = GetServerTime() }
        if ctx.onChanged then ctx.onChanged() end
        return true
    elseif pType == "PREQ" then
        -- Only a few random guildmates try (Most.ShouldAnswer), and only with something to send
        if senderName == Most.MyName() or not IsAllowedPlayer(senderName) or not Most.ShouldAnswer() then return true end
        local entries = EntriesSince(senderName, tonumber(payload) or 0)
        if #entries == 0 then return true end
        -- Random delay: one guildmate answers, the others see PCLAIM and give up (Most.ClaimAndAnswer). The claim
        -- goes high: as a low one it waited behind other packets and up to 30 guildmates answered.
        Most.ClaimAndAnswer(pendingRequests, senderName, 0.5 + math.random() * 2.5, function() Most.Send("PCLAIM", senderName, "high") end,
            function() SendEntries(senderName, entries, "low") end)
        return true
    elseif pType == "PREQN" then
        if senderName == Most.MyName() or not IsAllowedPlayer(senderName) or not Most.ShouldAnswer() then return true end
        local id, list = payload:match("^([%d%.]+):(.+)$")
        if not id then return true end
        local entries = EntriesFor(senderName, list)
        if #entries == 0 then return true end
        local key = senderName .. "#" .. id
        -- A short random delay: the one who answers first sends PCLAIM, the others give up
        Most.ClaimAndAnswer(pendingRequests, key, 0.2 + math.random() * 1.3, function() Most.Send("PCLAIM", key, "high") end,
            function() SendEntries(senderName, entries, "high") end)
        return true
    elseif pType == "PCLAIM" then
        if senderName ~= Most.MyName() then Most.ClaimSeen(pendingRequests, payload, senderName) end
        if payload == Most.MyName() then answered = true end
        return true
    elseif pType == "PSYNC" then
        if not IsAllowedPlayer(senderName) then return true end
        answered = true
        local me, changed = Most.MyName(), false
        for entry in payload:gmatch("[^;]+") do
            local name, ts, list = entry:match("^([^@]+)@(%d+)@(.*)$")
            ts = tonumber(ts)
            -- Never about me (my own skills come from the game), and only newer than what we have
            if name and ts and name ~= me and ts <= GetServerTime() + 60 and ts > ((known[name] and known[name].ts) or 0) then
                known[name] = { p = Decode(list), ts = ts }
                changed = true
            end
        end
        if changed and ctx.onChanged then ctx.onChanged() end
        return true
    end
    return false
end

-- ============================================================================
-- ROW IN THE MEMBERS TABLE
-- ============================================================================
local function ShowTooltip(self)
    local member = self.member
    if not member then return end
    local tip = _G.GameTooltip
    tip:SetOwner(self, "ANCHOR_RIGHT")
    tip:AddLine(member.name)
    local data = known[member.name]
    if not data then
        tip:AddLine("Unknown - player has no addon data", 0.6, 0.6, 0.6)
    else
        local any = false
        for _, def in ipairs(PROFESSIONS) do
            local value = data.p[def.code]
            if value then
                any = true
                tip:AddDoubleLine(DisplayName(def), value[1] .. "/" .. value[2], 1, 1, 1, 1, 0.82, 0)
            end
        end
        if not any then tip:AddLine("No professions", 0.6, 0.6, 0.6) end
        if not member.online and data.ts then tip:AddLine("Last seen: " .. date("%d.%m", data.ts), 0.6, 0.6, 0.6) end
    end
    tip:Show()
end

function Professions.AttachRow(row)
    local box = CreateFrame("Frame", nil, row)
    box:SetSize(MAX_ICONS * ICON_SIZE + (MAX_ICONS - 1) * 2, ICON_SIZE)
    box:EnableMouse(true)
    -- Clicks go through to the row, so its menu also works here
    if box.SetMouseClickEnabled then box:SetMouseClickEnabled(false) end
    box.icons = {}
    for i = 1, MAX_ICONS do
        local tex = box:CreateTexture(nil, "ARTWORK")
        tex:SetSize(ICON_SIZE, ICON_SIZE)
        tex:SetPoint("LEFT", box, "LEFT", (i - 1) * (ICON_SIZE + 2), 0)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        box.icons[i] = tex
    end
    box.unknown = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.unknown:SetPoint("LEFT", box, "LEFT", 0, 0)
    box.unknown:SetText("|cff808080-|r")
    box:SetScript("OnEnter", ShowTooltip)
    box:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
    row.profIcons = box
end

-- core.lua calls this when drawing a row
function Professions.UpdateRow(row, member)
    local box = row.profIcons
    box.member = member
    local data = known[member.name]
    local shown = 0
    if data then
        for _, def in ipairs(PROFESSIONS) do
            if def.primary and data.p[def.code] and shown < MAX_ICONS then
                shown = shown + 1
                box.icons[shown]:SetTexture(IconOf(def))
                box.icons[shown]:Show()
            end
        end
    end
    for i = shown + 1, MAX_ICONS do box.icons[i]:Hide() end
    if data then box.unknown:Hide() else box.unknown:Show() end
end

-- A player's known professions in the PROFESSIONS order: { { name, icon, rank, max, primary } }
-- (charcard.lua shows mine)
function Professions.List(name)
    local data, list = known[name], {}
    for _, def in ipairs(PROFESSIONS) do
        local value = data and data.p[def.code]
        if value then
            table.insert(list, { name = DisplayName(def), icon = IconOf(def), rank = value[1], max = value[2], primary = def.primary })
        end
    end
    return list
end

function Professions.Init(c) ctx = c end

-- ============================================================================
-- EVENTS
-- ============================================================================
local Listener = CreateFrame("Frame")
Listener:RegisterEvent("ADDON_LOADED")
Listener:RegisterEvent("PLAYER_LOGIN")
Listener:RegisterEvent("PLAYER_GUILD_UPDATE")
addonTable.SafeScript(Listener, "OnEvent", "professions.lua:431", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        _G.JagodkiChatDB = _G.JagodkiChatDB or {}
        _G.JagodkiChatDB.professions = _G.JagodkiChatDB.professions or {}
        known = _G.JagodkiChatDB.professions
    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(FIRST_SEND_DELAY, SendOwnIfChanged)
        C_Timer.NewTicker(CHECK_INTERVAL, SendOwnIfChanged)
        -- Professions of players who were online before us (only what is newer than what we have)
        C_Timer.After(SYNC_REQUEST_DELAY, function() Request(0) end)
    elseif event == "PLAYER_GUILD_UPDATE" then
        -- The new guild has not heard our professions yet
        lastSent = nil
    end
end)
