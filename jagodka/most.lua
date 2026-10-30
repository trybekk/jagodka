-- ============================================================================
-- MOST: wspolny czat addonu <-> czaty gildyjne (/g) wszystkich gildii z listy
-- ============================================================================
-- Zasady:
--  * Kazda wiadomosc ma unikalne ID, wiec duplikaty sa odrzucane u odbiorcy.
--  * W kazdej gildii jedna osoba z addonem jest RELAYEM (alfabetycznie pierwszy nick
--    sposrod graczy online z addonem). Relay przenosi /g <-> addon i laczy gildie:
--    pakiety z GUILD szepcze relayom innych gildii, a oni wklejaja je do swoich GUILD.
--  * Wiadomosci z innych gildii relay wkleja do /g swojej gildii (z kolejki, po kolei).
--  * Nowy gracz po zalogowaniu dostaje historie od kogos, kto jest online.
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
-- Kanal zwykly (JoinChannelByName), osobny dla kazdej frakcji. Classic nie wpuszcza pakietow addonu
-- na kanaly graczy (SendAddonMessage zwraca 4 = InvalidChatType), wiec kanal sluzy tylko do
-- znajdowania graczy z innych gildii. Pakiety ida przez GUILD i szepty miedzy relayami (Route).
local COMM_CHANNEL_ALLIANCE, COMM_CHANNEL_HORDE = "JagodkaNet", "JagodkaNetH"
local OLD_COMM_CHANNEL = "JagodkaWspolnota" -- opuszczany przy wejsciu na nowy kanal
-- Haslo kanalu: obcy gracz nie wejdzie przez /join i nie trafi na liste, z ktorej relaye sie znajduja.
-- Jest jawne w kodzie addonu, wiec chroni przed przypadkowymi osobami, nie przed kims, kto ma addon.
local COMM_PASSWORD = "jgdk7Wsp0lnota"
local ONLINE_TIMEOUT = 150            -- sekundy bez sygnalu, po ktorych gracz jest offline
local BRIDGED_TABS = { ["Ogolny"] = true } -- zakladki addonu polaczone z /g (Handel itp. zostaja w addonie)
local MAX_LOG = 300                   -- ile wiadomosci trzymamy (pamiec + SavedVariables)
local HISTORY_SYNC_MAX = 30           -- ile ostatnich wiadomosci wysylamy nowemu graczowi
local CONTENT_DEDUP_WINDOW = 15       -- okno (s): ta sama linia z /g od dwoch przekazujacych = jedna wiadomosc
local BACKUP_MIN_DELAY, BACKUP_MAX_DELAY = 2, 5 -- relay zapasowy czeka losowo tyle sekund na glownego
local MAX_ADDON_BYTES = 225           -- limit pakietu addonu to 255 bajtow, zapas na naglowek "FW:nick:"
local DISCOVER_INTERVAL, HELLO_RETRY = 30, 120 -- co ile relay czyta liste kanalu i ponawia powitanie (s)
local RELAY_READY_DELAY = 5           -- po zalogowaniu czekamy na odpowiedzi innych, zanim uznamy sie za relaya
local MAX_GUILD_LINE_BYTES = 250      -- limit linii /g to 255 bajtow

local Most = {}
addonTable.Most = Most
Most.ONLINE_TIMEOUT = ONLINE_TIMEOUT

-- Kontekst z core.lua: activePlayers, isGuildAllowed, colorName, onChatChanged
local ctx = nil
function Most.Init(c) ctx = c end

-- Sprawdzenie z rostera gildii, czy gildiowicz jest online (true/false, nil = nie wiadomo).
-- Pozwala od razu wykluczyc wylogowanego relaya, bez czekania na limit ONLINE_TIMEOUT.
local guildmateOnlineCheck = nil
function Most.SetGuildmateOnlineCheck(fn) guildmateOnlineCheck = fn end

local channelProblem = nil -- opis problemu z kanalem globalnym (obce haslo / ban), widoczny w statusie

local function MyName() return UnitName("player") end
-- GetGuildInfo() potrafi chwilowo zwracac nil (po loadingu, po dolaczeniu do gildii),
-- wiec pamietamy ostatnia znana nazwe; IsInGuild() pilnuje, zeby po wyjsciu z gildii jej nie uzywac
local lastGuildName = nil
local function MyGuild()
    local g = GetGuildInfo("player")
    if g and g ~= "" then lastGuildName = g return g end
    if not IsInGuild() then lastGuildName = nil return nil end
    if _G.C_GuildInfo and _G.C_GuildInfo.GuildRoster then _G.C_GuildInfo.GuildRoster() elseif _G.GuildRoster then _G.GuildRoster() end
    return lastGuildName
end
Most.MyGuild = MyGuild
-- Zmiana gildii (wyjscie / nowa gildia): zapomniana nazwa nie moze trafic do nowej gildii
function Most.ResetGuild() lastGuildName = nil end

-- ============================================================================
-- KODOWANIE POL (":" jest separatorem pakietu)
-- ============================================================================
function Most.EncodeField(s)
    return (tostring(s or ""):gsub("%%", "%%25"):gsub(":", "%%3A"):gsub("\n", "%%0A"))
end

function Most.DecodeField(s)
    if not s then return nil end
    return (s:gsub("%%0A", "\n"):gsub("%%3A", ":"):gsub("%%25", "%%"))
end
local Enc, Dec = Most.EncodeField, Most.DecodeField

-- Tekst od innych graczy bez kodow formatowania ("|"): nikt nie wstawi nam kolorow, tekstur
-- ani podrobionych linkow w nick, gildie, tytul wydarzenia itp.
function Most.Plain(s)
    return s and (s:gsub("|", ""))
end

-- Tresc wiadomosci czatu: zostaja tylko poprawne linki (przedmioty, zaklecia, profesje...),
-- kazdy inny "|" jest usuwany
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

-- Koduje tekst i dzieli go na kawalki o dlugosci liczonej PO zakodowaniu,
-- nie przecinajac znakow UTF-8 (pierwszy kawalek moze miec inny limit niz kolejne)
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
-- KANAL GLOBALNY
-- ============================================================================
-- Horda i Przymierze maja osobne kanaly (gra i tak nie laczy frakcji)
local function ChannelName()
    return (_G.UnitFactionGroup("player") == "Horde") and COMM_CHANNEL_HORDE or COMM_CHANNEL_ALLIANCE
end
Most.ChannelName = ChannelName

function Most.GetChannelId()
    local id = GetChannelName(ChannelName())
    if id and id > 0 then return id end
    return nil
end

-- Ukrycie kanalu z okien czatu, zeby nie zasmiecal czatu
local function HideFromChat(name)
    if not _G.ChatFrame_RemoveChannel then return end
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf then _G.ChatFrame_RemoveChannel(cf, name) end
    end
end

function Most.JoinChannel()
    -- Stary kanal tymczasowy (do 0.7.6) nic juz nie daje - wychodzimy z niego
    if (GetChannelName(OLD_COMM_CHANNEL) or 0) > 0 and _G.LeaveChannelByName then _G.LeaveChannelByName(OLD_COMM_CHANNEL) end
    local name = ChannelName()
    if not Most.GetChannelId() then _G.JoinChannelByName(name, COMM_PASSWORD) end
    HideFromChat(name)
end

-- ============================================================================
-- KOLEJKA WYSYLKI (zachowuje kolejnosc i nie przekracza limitow Blizzarda)
-- ============================================================================
-- DIAGNOSTYKA (zakladka Settings): wyniki wysylania, odebrane pakiety, odrzucone wiadomosci
local debug = { sent = {}, recv = {}, rejected = {}, senders = {}, lastResult = {} }
local function Count(t, key) t[key] = (t[key] or 0) + 1 end

local highQueue, lowQueue = {}, {}  -- high: biezace wiadomosci, low: historia
local guildLineQueue = {}           -- linie do wklejenia w /g (tylko relay)
local postedLines = {}              -- linie wklejone przez nas w /g -> czas (ochrona przed petla)
local tokens, MAX_TOKENS, TOKENS_PER_SEC = 10, 10, 1
local whisperedAt = {}              -- nick -> czas ostatniego szeptu addonu (rozpoznanie "gracz offline")

function Most.Send(pType, payload, priority)
    local item = { msg = pType .. ":" .. payload, tries = 0 }
    table.insert(priority == "low" and lowQueue or highQueue, item)
end

function Most.Whisper(target, pType, payload, priority)
    table.insert(priority == "high" and highQueue or lowQueue, { msg = pType .. ":" .. payload, target = target, tries = 0 })
end

-- Starsze API zwraca bool, nowsze kod Enum.SendAddonMessageResult (0 = sukces)
local function IsOk(result) return result == nil or result == true or result == 0 end
-- Chwilowy limit (3 = AddonMessageThrottle, 8 = ChannelThrottle; false = starsze API) - warto ponowic.
-- Inne kody (np. 4 = InvalidChatType) sa trwale: ponawianie tylko blokowaloby kolejke.
local function IsThrottle(result) return result == false or result == 3 or result == 8 end

-- Zwraca wynik API i rodzaj kanalu (do diagnostyki)
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
    Count(debug.sent, kind .. (ok and " ok" or " fail"))
    debug.lastResult[kind] = tostring(result)
    -- Przy chwilowym limicie serwera ponawiamy dlugo (ok. 30 s), zeby wiadomosc nie przepadla
    if ok or not IsThrottle(result) or item.tries >= 30 then
        table.remove(queue, 1)
        tokens = tokens - 1
    else
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
-- DZIELENIE TEKSTU (UTF-8 i linki przedmiotow nie moga byc przeciete)
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
    -- Tokeny: link z kolorem jako calosc, reszta tekstu po slowach
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
            -- Pojedyncze bardzo dlugie slowo tniemy na granicy znaku UTF-8
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
-- LOG WIADOMOSCI (jedno zrodlo prawdy dla widoku "Wspolny")
-- ============================================================================
local chatLog = {}       -- { id, ts, guild, author, tab, src ("G" z /g, "A" z addonu, "S" systemowa), text }
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

-- Historie wstawiamy wg czasu serwera; biezace wiadomosci dopisujemy w kolejnosci dotarcia
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

-- linkName: nick jako link gracza (klik = szept, prawy klik = menu) - dla okien czatu Blizzarda
-- textColor: kolor tresci, np. "ff3cb43c" (po linkach przedmiotow kolor jest przywracany)
function Most.FormatEntry(e, linkName, textColor)
    if e.src == "S" then return "|cff00ccff[System]: " .. e.text .. "|r" end
    local name = (ctx and ctx.colorName) and ctx.colorName(e.author) or e.author
    local via = (e.src == "G") and "|cff40c040/g|r " or ""
    local shown = "[" .. name .. "]"
    if linkName then shown = "|Hplayer:" .. e.author .. "|h" .. shown .. "|h" end
    local text = e.text
    if textColor then text = "|c" .. textColor .. text:gsub("|r", "|r|c" .. textColor) .. "|r" end
    return string.format("|cff808080%s|r |cffbf40ff[%s]|r %s%s: %s", date("%H:%M", e.ts), e.guild, via, shown, text)
end

-- Sluchacze nowych wiadomosci (np. zakladka w czacie Blizzarda): fn(entry, live)
local entryListeners = {}
function Most.OnNewEntry(fn) table.insert(entryListeners, fn) end

-- ============================================================================
-- RELAY: jedna osoba z addonem na gildie przenosi wiadomosci /g <-> addon
-- ============================================================================
-- Relay dowolnej gildii (ta sama regula liczona u kazdego, wiec wszyscy widza to samo)
function Most.GetRelayName(guild)
    guild = guild or MyGuild()
    if not guild or not ctx then return nil end
    local best = (guild == MyGuild()) and MyName() or nil
    local now = GetTime()
    local isMyGuild = (guild == MyGuild())
    for _, p in ipairs(ctx.activePlayers) do
        -- Gildiowicz wylogowany wg rostera nie moze byc relayem, nawet jesli jeszcze nie minal timeout
        local offlineInRoster = isMyGuild and guildmateOnlineCheck ~= nil and guildmateOnlineCheck(p.name) == false
        if p.guild == guild and not offlineInRoster and (now - (p.lastSeen or 0)) < ONLINE_TIMEOUT and (not best or p.name < best) then
            best = p.name
        end
    end
    return best
end

-- Czy moge przekazywac wiadomosci (jestem w gildii z listy i minela chwila od zalogowania).
-- Bez tej chwili nowo zalogowany nie zna jeszcze innych, uwaza sie za relaya i dubluje linie w /g.
local relayReadyAt = math.huge
local function CanForward()
    if not ctx or GetTime() < relayReadyAt or not IsInGuild() then return false end
    return ctx.isGuildAllowed(MyGuild())
end

function Most.IsRelay()
    return CanForward() and Most.GetRelayName() == MyName()
end

local function BridgePrefix(guild, author)
    return "[" .. guild .. "] " .. author .. ": "
end

-- Wiadomosc ze wspolnego czatu -> /g mojej gildii (tylko relay, tylko mostkowane zakladki)
local function BridgeToGuild(e)
    if not BRIDGED_TABS[e.tab] or not Most.IsRelay() then return end
    -- Wiadomosc z /g mojej gildii juz tam jest
    if e.src == "G" and e.guild == MyGuild() then return end
    local line = BridgePrefix(e.guild, e.author) .. e.text
    if #line > 255 then line = Utf8Cut(line, 255) end
    table.insert(guildLineQueue, line)
end

-- Czy linia w /g to wiadomosc wklejona przez most (a nie napisana przez gracza)
local function IsBridgeLine(text, author)
    if author == MyName() and postedLines[text] then return true end
    local tagGuild = text:match("^%[(.-)%] [^:]+: ")
    return tagGuild ~= nil and ctx ~= nil and ctx.isGuildAllowed(tagGuild)
end

-- ============================================================================
-- PRZYJMOWANIE WIADOMOSCI (deduplikacja po ID)
-- ============================================================================
-- Czy w logu jest juz ta sama linia z /g (gildia + autor + tekst) z podobnego czasu.
-- Lapie duplikaty, gdy te sama linie przekazal relay i relay zapasowy (rozne ID, ta sama tresc).
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
    -- Wyciszony gracz (wyciszenie.lua): jego wiadomosci nie trafiaja do logu ani do /g innych gildii
    if addonTable.Mute and addonTable.Mute.IsMuted(e.author) then return false end
    seenIds[e.id] = true
    -- Dotyczy biezacych i historii, wiec duplikat nie wroci tez przy synchronizacji
    if e.src == "G" and HasRecentGuildLine(e.guild, e.author, e.text, e.ts) then return false end
    -- Zawsze wg czasu napisania, wiec spozniona wiadomosc (np. od relaya zapasowego) wskakuje na swoje miejsce
    InsertByTime(e)
    TrimLog()
    -- Historia nigdy nie trafia ponownie do /g, tylko biezace wiadomosci
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

-- Podzial tresci na czesci. Nie zalezy od nicku wysylajacego (stala dlugosc w naglowku),
-- wiec relay i relay zapasowy dziela te sama linie identycznie - wazne dla wykrywania duplikatow.
local function SplitForPublish(text, guild, author, tab, src)
    local header = string.format("GMSG:%s.ffffffff.ffff:%d:%s:%s:%s:%s:", string.rep("x", 24), 2000000000, Enc(guild), Enc(author), Enc(tab), src)
    local maxText = math.min(MAX_ADDON_BYTES - #header, MAX_GUILD_LINE_BYTES - #BridgePrefix(guild, author))
    return SplitText(text, maxText)
end

-- Publikacja nowej wiadomosci na wspolny czat (z addonu lub z /g przez relaya)
function Most.Publish(tab, text, src, author, guild, ts)
    if not text or text == "" or not guild then return end
    -- Czas musi byc liczba (sortowanie logu); cokolwiek innego = teraz
    ts = tonumber(ts) or GetServerTime()
    for _, part in ipairs(SplitForPublish(text, guild, author, tab, src)) do
        local e = { id = NewMessageId(), ts = ts, guild = guild, author = author, tab = tab, src = src, text = part }
        -- Gdy ta sama linia jest juz w logu (przekazal ja ktos inny), nie wysylamy jej drugi raz
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
-- SYNCHRONIZACJA HISTORII
-- ============================================================================
local pendingHistory = {} -- requester -> true, dopoki nikt inny nie odpowiedzial

function Most.RequestHistory()
    local newest = 0
    for _, e in ipairs(chatLog) do
        if e.src ~= "S" and e.ts > newest then newest = e.ts end
    end
    Most.Send("HREQ", tostring(newest), "high")
    addonTable.Sync.Start("history") -- pasek synchronizacji (synchro.lua)
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
    -- Losowe opoznienie: odpowiada jedna osoba, reszta widzi HCLAIM i rezygnuje
    C_Timer.After(0.5 + math.random() * 2, function()
        if not pendingHistory[sender] then return end
        pendingHistory[sender] = nil
        Most.Send("HCLAIM", sender, "high")
        for _, e in ipairs(list) do Most.Whisper(rawSender, "HIST", EncodeMessage(e)) end
    end)
end

-- ============================================================================
-- OBSLUGA PAKIETOW (wywolywane z core.lua); zwraca true, jesli pakiet obsluzony
-- ============================================================================
function Most.HandlePacket(pType, payload, channel, senderName, rawSender)
    -- Diagnostyka: kazdy odebrany pakiet (rodzaj kanalu + typ) i ostatni nadawcy
    Count(debug.recv, tostring(channel) .. " " .. pType)
    debug.senders[senderName] = GetTime()
    if pType == "GMSG" or pType == "HIST" then
        if pType == "HIST" then addonTable.Sync.Activity("history") end
        local senderInfo = IsKnownAllowedSender(senderName)
        local e = DecodeMessage(payload)
        if not e then Count(debug.rejected, "bad format") return true end
        if not ctx.isGuildAllowed(e.guild) then Count(debug.rejected, "guild not listed: " .. tostring(e.guild)) return true end
        if pType == "GMSG" then
            -- Z addonu pisze tylko autor; z /g przekazuje tylko ktos z tej samej gildii
            if e.src == "A" and e.author ~= senderName then Count(debug.rejected, "author ~= sender") return true end
            if senderInfo and senderInfo.guild ~= e.guild then Count(debug.rejected, "sender guild mismatch") return true end
            -- Nadawca jeszcze nieznany (jego meldunek nie doszedl): wiadomosci NIE gubimy.
            -- Ufamy mu tak samo jak meldunkowi - podaje gildie z listy; jesli twierdzi, ze jest
            -- z mojej gildii, musi byc w rosterze.
            if not senderInfo and senderName ~= MyName() and e.guild == MyGuild()
                and guildmateOnlineCheck ~= nil and guildmateOnlineCheck(senderName) == false then
                Count(debug.rejected, "not in guild roster")
                return true
            end
        elseif not senderInfo and senderName ~= MyName() then
            -- Historie przyjmujemy tylko od znanego gracza (odpowiedzial na nasz meldunek)
            Count(debug.rejected, "history from unknown")
            return true
        end
        -- Wlasne wiadomosci wracaja z GUILD i tez tu trafiaja
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
-- LACZNOSC MIEDZY GILDIAMI: relay gildii <-> relaye innych gildii (szept addonu)
-- ============================================================================
-- Pakiet z GUILD relay opakowuje w "FW:nadawca:pakiet" i szepcze relayom innych gildii.
-- Odbiorca wkleja go do GUILD swojej gildii bez zmian. Opakowanych nikt nie przekazuje dalej.
local function ForwardPriority(text)
    return text:sub(1, 5) == "GMSG:" and "high" or "low"
end

-- Relaye innych gildii wg listy graczy online: gildia -> nick
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

-- Wywolywane dla kazdego pakietu przed jego obsluga. Zwraca tresc, rodzaj kanalu i prawdziwego
-- nadawce albo nil, gdy pakietu nie nalezy obslugiwac.
function Most.Route(text, channel, senderName)
    local pType, rest = strsplit(":", text, 2)
    if pType ~= "FW" then
        -- Tez wlasne pakiety: gra odsyla nam je z GUILD, wiec jest jedna droga dla wszystkich
        if channel == "GUILD" and Most.IsRelay() then ForwardToOtherGuilds(senderName, text) end
        return text, channel, senderName
    end
    -- Nasz wlasny pakiet wklejony do GUILD: juz go obsluzylismy przy odbiorze szeptu
    if senderName == MyName() then return nil end
    local origin, inner = strsplit(":", rest or "", 2)
    origin = Most.Plain(origin)
    if not origin or origin == "" or not inner or origin == MyName() then return nil end
    if channel == "WHISPER" then
        -- Za innych moze mowic tylko znany gracz z gildii z listy, za siebie kazdy (powitanie)
        if origin ~= senderName and not IsKnownAllowedSender(senderName) then
            Count(debug.rejected, "forward from unknown")
            return nil
        end
        table.insert(ForwardPriority(inner) == "high" and highQueue or lowQueue, { msg = text, tries = 0 })
    elseif channel ~= "GUILD" then
        return nil
    end
    return inner, "FW", origin
end

-- Szukanie innych gildii: relay czyta liste czlonkow kanalu i wita sie z nieznanymi graczami.
-- Powitany gracz wkleja PING do swojej gildii, a jej relay od tej chwili zna nas i przesyla pakiety.
local listAskedAt, helloAt, channelMembers = 0, {}, 0

function Most.HasLinkedGuilds()
    return ctx ~= nil and _G.next(OtherGuildRelays()) ~= nil
end

function Most.Discover()
    if not _G.ListChannelByName or not Most.GetChannelId() or not Most.IsRelay() then return end
    listAskedAt = GetTime()
    _G.ListChannelByName(ChannelName())
end

local function IsActivePlayer(name)
    for _, p in ipairs(ctx.activePlayers) do
        if p.name == name then return true end
    end
    return false
end

local function HandleChannelList(list)
    if not ctx or not Most.IsRelay() then return end
    local now, count = GetTime(), 0
    for raw in tostring(list or ""):gmatch("[^,]+") do
        -- Na liscie wlasciciel ma "*", a moderator "@"
        local name = Ambiguate((raw:gsub("[%s%*@%+]", "")), "none")
        count = count + 1
        local isGuildmate = guildmateOnlineCheck ~= nil and guildmateOnlineCheck(name) == true
        if name ~= "" and name ~= MyName() and not isGuildmate and not IsActivePlayer(name)
            and now - (helloAt[name] or -HELLO_RETRY) >= HELLO_RETRY and ctx.sendHello then
            helloAt[name] = now
            ctx.sendHello(name)
        end
    end
    channelMembers = count
end

local function NameFromSystemMessage(pattern, message)
    return pattern and message:match("^" .. pattern:gsub("%%s", "(.+)") .. "$")
end

local function RemoveActivePlayer(name)
    for i = #ctx.activePlayers, 1, -1 do
        if ctx.activePlayers[i].name == name then table.remove(ctx.activePlayers, i) end
    end
end

-- Szept do wylogowanego gracza daje komunikat systemowy: chowamy go i od razu usuwamy gracza
-- z listy online, dzieki czemu relayem tej gildii zostaje nastepna osoba
local function HandlePlayerNotFound(message)
    if not ctx then return false end
    local name = NameFromSystemMessage(_G.ERR_CHAT_PLAYER_NOT_FOUND_S, message)
    if not name or GetTime() - (whisperedAt[name] or -10) >= 10 then return false end
    RemoveActivePlayer(name)
    return true
end

if _G.ChatFrame_AddMessageEventFilter then
    _G.ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_LIST", function(_, _, ...)
        if select(9, ...) == ChannelName() and GetTime() - listAskedAt < 2 then return true end
    end)
    _G.ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, message)
        if HandlePlayerNotFound(message) then return true end
    end)
end

-- ============================================================================
-- STATUS (zakladka Ustawienia)
-- ============================================================================
function Most.GetStatusText()
    local channelId = Most.GetChannelId()
    local linked = {}
    if ctx then
        for guild, relay in pairs(OtherGuildRelays()) do table.insert(linked, guild .. " (" .. relay .. ")") end
        table.sort(linked)
    end
    local lines = {
        "Global channel: " .. (channelId and ("|cff00ff00connected|r (" .. ChannelName() .. ", /" .. channelId .. ", members seen: " .. channelMembers .. ")") or ("|cffff5555not connected|r" .. (channelProblem and (" - " .. channelProblem) or ""))),
        "Your guild relay: " .. (Most.GetRelayName() or "-") .. (Most.IsRelay() and " |cff00ff00(you)|r" or ""),
        "Linked guilds: " .. (#linked > 0 and table.concat(linked, ", ") or "-"),
        "Packet queue: " .. (#highQueue + #lowQueue) .. "   /g queue: " .. #guildLineQueue,
        "Messages in history: " .. #chatLog,
    }
    -- Diagnostyka: "klucz=liczba" posortowane, nadawcy z ostatnich 5 minut
    local function Pairs(t)
        local out = {}
        for k, v in pairs(t) do table.insert(out, k .. "=" .. v) end
        table.sort(out)
        return #out > 0 and table.concat(out, ", ") or "-"
    end
    local recent, now = {}, GetTime()
    for name, t in pairs(debug.senders) do
        if now - t < 300 then table.insert(recent, name) end
    end
    table.sort(recent)
    table.insert(lines, "|cffffd100Debug|r  sent: " .. Pairs(debug.sent) .. "  (last result: " .. Pairs(debug.lastResult) .. ")")
    table.insert(lines, "Received: " .. Pairs(debug.recv))
    table.insert(lines, "Packets from (5 min): " .. (#recent > 0 and table.concat(recent, ", ") or "-"))
    table.insert(lines, "Chat rejected: " .. Pairs(debug.rejected))
    return table.concat(lines, "\n")
end

-- ============================================================================
-- ZDARZENIA: wczytanie historii, przechwytywanie /g, sprzatanie
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
        -- "X has gone offline": wylogowany (np. przelaczenie na inna postac) od razu traci role relaya
        local name = NameFromSystemMessage(_G.ERR_FRIEND_OFFLINE_S, arg1 or "")
        if name and ctx then RemoveActivePlayer(Ambiguate(name, "none")) end
        return
    end
    if event == "CHAT_MSG_CHANNEL_LIST" then
        if select(7, ...) == ChannelName() then HandleChannelList(arg1) end
        return
    end
    if event == "CHAT_MSG_CHANNEL_NOTICE" then
        -- arg1 = typ komunikatu, 7. dodatkowy argument (arg9) = nazwa kanalu bez numeru
        local channelBaseName = select(7, ...)
        if channelBaseName ~= ChannelName() then return end
        if arg1 == "WRONG_PASSWORD" or arg1 == "BANNED" then
            -- Ktos przejal kanal (haslo) albo nas zbanowal - nie probujemy w kolko, tylko informujemy
            channelProblem = (arg1 == "BANNED") and "banned from the channel" or "the channel has a different password"
            Warn("Global channel unavailable: " .. channelProblem .. ". Report this to an officer.")
        elseif arg1 == "YOU_LEFT" and not channelProblem then
            -- Inny addon (np. porzadkujacy kanaly) nas wypisal - wracamy po chwili
            C_Timer.After(5, Most.JoinChannel)
        elseif arg1 == "YOU_JOINED" or arg1 == "YOU_CHANGED" then
            channelProblem = nil
            -- Gra mogla dopisac kanal do okna czatu przy wejsciu
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
            -- Inny relay juz wkleil te linie -> nie wklejamy jej drugi raz
            if author ~= MyName() then
                for i = #guildLineQueue, 1, -1 do
                    if guildLineQueue[i] == text then table.remove(guildLineQueue, i) end
                end
            end
            return
        end
        if Most.IsRelay() then
            Most.Publish("Ogolny", text, "G", author, MyGuild())
        elseif CanForward() then
            -- RELAY ZAPASOWY: jesli glowny relay nie przekaze tej linii w ciagu kilku sekund
            -- (wylogowal sie, jeszcze nie wszedl na kanal itp.), przekazujemy ja sami.
            -- Kto zdazy pierwszy, ten wysyla; reszta widzi linie w logu i rezygnuje.
            local guild, ts = MyGuild(), GetServerTime()
            local firstPart = SplitForPublish(text, guild, author, "Ogolny", "G")[1]
            C_Timer.After(BACKUP_MIN_DELAY + math.random() * (BACKUP_MAX_DELAY - BACKUP_MIN_DELAY), function()
                if CanForward() and not HasRecentGuildLine(guild, author, firstPart, ts) then
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
