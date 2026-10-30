-- ============================================================================
-- ROSTER: czlonkowie (online i offline) wszystkich gildii z listy
-- ============================================================================
-- Blizzard pokazuje roster tylko wlasnej gildii, wiec:
--  * W kazdej gildii jedna osoba z addonem jest NADAWCA rostera. Co 5 min nadawca sie zmienia
--    (wybor "losowy", ale liczony tak samo u wszystkich), zeby ruch rozlozyl sie na wszystkich.
--  * Kazdy co 20 s porownuje roster swojej gildii z poprzednim; wysyla tylko nadawca.
--    Zmiana statusu to "+Nick" / "-Nick", nowy czlonek / poziom / ranga: "Nick,W603+".
--  * Pelny roster: na prosbe nowo zalogowanego (dane > 10 min) i raz na 30 min.
--  * Pakiety ida z niskim priorytetem (czat ma pierwszenstwo).
--  * Kazdy trzyma ostatni znany roster w JagodkiRosterDB.
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
local pairs, ipairs, tostring, tonumber = _G.pairs, _G.ipairs, _G.tostring, _G.tonumber
local table, math, wipe = _G.table, _G.math, _G.wipe

local Most = addonTable.Most
local Enc, Dec = Most.EncodeField, Most.DecodeField

local MAX_ADDON_BYTES = 250
local FULL_INTERVAL = 1800   -- pelny roster co 30 min
local FULL_COOLDOWN = 60     -- nie czesciej niz raz na minute (kilka logowan naraz = jedna wysylka)
local STALE_AFTER = 600      -- po zalogowaniu prosimy o roster gildii, ktorej dane maja > 10 min
local READY_DELAY = 40       -- po zalogowaniu czekamy, az poznamy pozostalych (inaczej kazdy mysli, ze jest nadawca)
local SENDER_ROTATION = 300  -- co tyle sekund nadawca rostera sie zmienia

local Roster = {}
addonTable.Roster = Roster

-- Kontekst z core.lua: activePlayers, isGuildAllowed, allowedGuilds, onChanged
local ctx = nil
function Roster.Init(c) ctx = c end

-- rosters[gildia] = { members = { nick = { c = klasa, l = poziom, r = ranga, o = online } }, ranks = {...}, updated = czas }
local rosters = {}
local readyAt = math.huge
local lastFull, lastFullSlot, lastSent = 0, nil, {}
local incoming = {} -- gildia -> { id, got = { [idx] = true }, count, total, complete }

local function MyGuild() return (GetGuildInfo("player")) end
local function Changed() if ctx and ctx.onChanged then ctx.onChanged() end end

-- ============================================================================
-- KODOWANIE WPISU
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

-- Dzieli wpisy na kawalki "a;b;c" mieszczace sie w limicie (pierwszy moze miec inny limit)
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
-- MOJA GILDIA (z rostera Blizzarda)
-- ============================================================================
local function RefreshLocal()
    local guild = MyGuild()
    local n = (_G.GetNumGuildMembers and _G.GetNumGuildMembers()) or 0
    if not guild or n == 0 then return end
    -- Przy wylaczonym "pokaz offline" Blizzard zwraca tylko graczy online - wtedy reszte zostawiamy jako offline
    local complete = not (_G.GetGuildRosterShowOffline and not _G.GetGuildRosterShowOffline())
    local old = rosters[guild] and rosters[guild].members or {}
    local members = {}
    if not complete then
        for name, m in pairs(old) do members[name] = { c = m.c, l = m.l, r = m.r, o = false } end
    end
    for i = 1, n do
        local fullName, _, rankIndex, level, _, _, _, _, isOnline, _, classFile = _G.GetGuildRosterInfo(i)
        if fullName then
            members[Ambiguate(fullName, "none")] = { c = classFile, l = level, r = rankIndex, o = isOnline and true or false }
        end
    end
    local ranks = {}
    local numRanks = (_G.GuildControlGetNumRanks and _G.GuildControlGetNumRanks()) or 0
    for i = 1, numRanks do ranks[i] = _G.GuildControlGetRankName(i) end
    rosters[guild] = { members = members, ranks = ranks, updated = GetServerTime(), complete = complete }
    Changed()
end

-- ============================================================================
-- NADAWCA: rotacja co SENDER_ROTATION sekund wsrod graczy z addonem online w mojej gildii
-- ============================================================================
local function IsSender()
    local guild = MyGuild()
    local g = guild and rosters[guild]
    if not g or not ctx or not Most.GetChannelId() then return false end
    local myName, now = UnitName("player"), GetTime()
    local candidates = { myName }
    for _, p in ipairs(ctx.activePlayers) do
        local m = g.members[p.name]
        if p.name ~= myName and p.guild == guild and m and m.o and (now - (p.lastSeen or 0)) < Most.ONLINE_TIMEOUT then
            table.insert(candidates, p.name)
        end
    end
    table.sort(candidates)
    -- Przesuniecie zalezne od nazwy gildii, zeby rozne gildie nie zmienialy nadawcy w tym samym rytmie
    local shift = 0
    for i = 1, #guild do shift = shift + guild:byte(i) end
    local slot = math.floor(GetServerTime() / SENDER_ROTATION)
    return candidates[(slot + shift) % #candidates + 1] == myName
end

-- ============================================================================
-- WYSYLKA (tylko nadawca)
-- ============================================================================
local function SendFull()
    local guild = MyGuild()
    local g = guild and rosters[guild]
    if not g then return end
    lastFull = GetTime()
    wipe(lastSent)
    local entries = {}
    for name, m in pairs(g.members) do
        local e = EncodeEntry(name, m)
        lastSent[name] = e
        table.insert(entries, e)
    end
    local rankParts = {}
    for i, r in ipairs(g.ranks) do rankParts[i] = Enc(((r or ""):gsub(",", " "))) end
    local ranks = table.concat(rankParts, ",")
    local snap = tostring(GetServerTime() % 100000)
    -- RF:gildia:snap:idx:total:pelny:rangi:wpisy  (rangi tylko w pierwszej czesci)
    local header = #"RF:" + #Enc(guild) + 1 + #snap + 1 + 3 + 1 + 3 + 1 + 2 + 1
    local chunks = Chunk(entries, MAX_ADDON_BYTES - header - #ranks, MAX_ADDON_BYTES - header)
    for i, chunk in ipairs(chunks) do
        Most.Send("RF", table.concat({ Enc(guild), snap, i, #chunks, g.complete and "1" or "0", (i == 1) and ranks or "", chunk }, ":"), "low")
    end
end

-- Zmiany od poprzedniego sprawdzenia liczy KAZDY (wszyscy widza ten sam roster), wysyla tylko
-- nadawca - dzieki temu zmiana nadawcy nie wymaga pelnego rostera.
-- Sam status: "+Nick" / "-Nick"; nowy czlonek albo inny poziom/ranga: pelny wpis.
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
        Most.Send("RD", Enc(guild) .. ":" .. chunk, "low")
    end
end

local baselined = false
local function Tick()
    if GetTime() < readyAt then return end
    local fullSlot = math.floor(GetServerTime() / FULL_INTERVAL)
    if not baselined then
        -- Pierwsze sprawdzenie tylko zapamietuje stan, niczego nie wysyla
        baselined, lastFullSlot = true, fullSlot
        SendDelta(false)
        return
    end
    local isSender = IsSender()
    if fullSlot ~= lastFullSlot then
        lastFullSlot = fullSlot
        if isSender and GetTime() - lastFull > FULL_COOLDOWN then SendFull() return end
    end
    SendDelta(isSender)
end

-- Po zalogowaniu: prosba o rostery gildii, o ktorych nie mamy swiezych danych
local function RequestStale()
    if not ctx then return end
    local now, list = GetServerTime(), {}
    for guild in pairs(ctx.allowedGuilds) do
        local g = rosters[guild]
        if guild ~= MyGuild() and (not g or now - (g.updated or 0) > STALE_AFTER) then table.insert(list, Enc(guild)) end
    end
    if #list > 0 then Most.Send("RQ", table.concat(list, ","), "low") end
end

-- ============================================================================
-- ODBIOR
-- ============================================================================
-- Roster innej gildii przyjmujemy tylko od znanego gracza z tej gildii (swoja znamy z gry)
local function AcceptFrom(sender, guild)
    if not ctx or not guild or guild == MyGuild() or not ctx.isGuildAllowed(guild) then return false end
    for _, p in ipairs(ctx.activePlayers) do
        if p.name == sender then return p.guild == guild end
    end
    return false
end

local function Upsert(g, list, snap)
    for e in list:gmatch("[^;]+") do
        local flag, statusName = e:match("^([%+%-])([^,]+)$")
        if flag then
            -- Sama zmiana statusu (nieznanego gracza dopisze nastepny pelny roster)
            local m = g.members[statusName]
            if m then m.o = (flag == "+") end
        else
            local name, m = DecodeEntry(e)
            if name then m.s = snap g.members[name] = m end
        end
    end
end

function Roster.HandlePacket(pType, payload, senderName)
    if pType == "RF" then
        local gEnc, snap, idx, total, complete, ranks, list = strsplit(":", payload, 7)
        local guild = Dec(gEnc)
        idx, total = tonumber(idx), tonumber(total)
        if not idx or not total or not list or not AcceptFrom(senderName, guild) then return true end
        local g = rosters[guild] or { members = {}, ranks = {} }
        rosters[guild] = g
        local inc = incoming[guild]
        if not inc or inc.id ~= snap then
            inc = { id = snap, got = {}, count = 0 }
            incoming[guild] = inc
        end
        if not inc.got[idx] then
            inc.got[idx] = true
            inc.count = inc.count + 1
        end
        if idx == 1 and ranks ~= "" then
            g.ranks = {}
            for r in ranks:gmatch("[^,]+") do table.insert(g.ranks, Dec(r)) end
        end
        Upsert(g, list, snap)
        g.updated = GetServerTime()
        -- Komplet czesci: kogo nie bylo w pelnym rosterze, ten odszedl z gildii (albo jest offline,
        -- gdy nadawca ma wylaczone "pokaz offline")
        if inc.count >= total then
            for name, m in pairs(g.members) do
                if m.s ~= snap then
                    if complete == "1" then g.members[name] = nil else m.o = false end
                end
            end
            incoming[guild] = nil
        end
        Changed()
        return true
    elseif pType == "RD" then
        local gEnc, list = strsplit(":", payload, 2)
        local guild = Dec(gEnc)
        if not list or not AcceptFrom(senderName, guild) then return true end
        local g = rosters[guild] or { members = {}, ranks = {} }
        rosters[guild] = g
        Upsert(g, list, incoming[guild] and incoming[guild].id)
        g.updated = GetServerTime()
        Changed()
        return true
    elseif pType == "RQ" then
        if senderName ~= UnitName("player") and GetTime() >= readyAt and IsSender() then
            for gEnc in payload:gmatch("[^,]+") do
                if Dec(gEnc) == MyGuild() then
                    -- Chwila zwloki: kilka prosb naraz = jedna wysylka (cooldown)
                    C_Timer.After(3, function()
                        if IsSender() and GetTime() - lastFull > FULL_COOLDOWN then SendFull() end
                    end)
                end
            end
        end
        return true
    end
    return false
end

-- ============================================================================
-- LISTA DO ZAKLADKI CZLONKOWIE
-- ============================================================================
-- Gracze z addonem (activePlayers) + roster wszystkich gildii z listy. Status online gildii,
-- w ktorej nikt z addonem nie jest teraz online, jest nieaktualny -> pokazujemy jako offline.
function Roster.BuildList(showOffline)
    local list, seen = {}, {}
    if not ctx then return list end
    local myGuild = MyGuild()
    for _, p in ipairs(ctx.activePlayers) do
        seen[p.name] = true
        table.insert(list, { name = p.name, class = p.class, level = p.level, guild = p.guild, rank = p.rank, rankIndex = tonumber(p.rankIndex), version = p.version, online = true })
    end
    for guild, g in pairs(rosters) do
        if ctx.isGuildAllowed(guild) then
            local live = (guild == myGuild) or Most.GetRelayName(guild) ~= nil
            for name, m in pairs(g.members) do
                local online = m.o and live
                if not seen[name] and (online or showOffline) then
                    seen[name] = true
                    table.insert(list, { name = name, class = m.c, level = m.l, guild = guild, rank = g.ranks[(m.r or 0) + 1] or ("Rank " .. tostring(m.r)), rankIndex = m.r, online = online })
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
-- ZDARZENIA
-- ============================================================================
local Listener = CreateFrame("Frame")
Listener:RegisterEvent("ADDON_LOADED")
Listener:RegisterEvent("PLAYER_LOGIN")
Listener:RegisterEvent("GUILD_ROSTER_UPDATE")
Listener:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        _G.JagodkiRosterDB = _G.JagodkiRosterDB or {}
        rosters = _G.JagodkiRosterDB
    elseif event == "PLAYER_LOGIN" then
        readyAt = GetTime() + READY_DELAY
        -- Kanal globalny jest dolaczany po ok. 10 s (core.lua)
        C_Timer.After(14, RequestStale)
        C_Timer.NewTicker(20, Tick)
    elseif event == "GUILD_ROSTER_UPDATE" then
        -- Blizzard potrafi wyslac to zdarzenie wiele razy pod rzad - przeliczamy raz na 2 s
        if not self.pending then
            self.pending = true
            C_Timer.After(2, function() self.pending = false RefreshLocal() end)
        end
    end
end)
