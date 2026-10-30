-- ============================================================================
-- 0. IZOLACJA ŚRODOWISKA (GLOBAL SCOPE ISOLATION & UPVALUES)
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local CreateFrame = _G.CreateFrame
local UnitName = _G.UnitName
local UnitLevel = _G.UnitLevel
local UnitClass = _G.UnitClass
local GetGuildInfo = _G.GetGuildInfo
local GetTime = _G.GetTime
local Ambiguate = _G.Ambiguate
local strsplit = _G.strsplit
local select = _G.select
local unpack = _G.unpack
local wipe = _G.wipe
local pairs = _G.pairs
local ipairs = _G.ipairs
local table = _G.table
local string = _G.string
local C_ChatInfo = _G.C_ChatInfo
local LibStub = _G.LibStub
local UIParent = _G.UIParent
local ChatFontNormal = _G.ChatFontNormal
local UIErrorsFrame = _G.UIErrorsFrame
local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
local CLASS_ICON_TCOORDS = _G.CLASS_ICON_TCOORDS
local LOCALIZED_CLASS_NAMES_MALE = _G.LOCALIZED_CLASS_NAMES_MALE
local IsInRaid = _G.IsInRaid
local IsInGroup = _G.IsInGroup
local IsInGuild = _G.IsInGuild
local C_Timer = _G.C_Timer

-- WYMUSZONA REJESTRACJA PREFIKSU NA SAMYM STARCIE PLIKU
-- Klient ma limit zarejestrowanych prefiksow; przy wielu addonach rejestracja moze sie nie udac
do
local result = C_ChatInfo.RegisterAddonMessagePrefix("JagodkaComm")
-- Starsze API zwraca bool, nowsze kod: 0 = OK, 1 = juz zarejestrowany (tez OK), 2+ = blad
if result == false or (type(result) == "number" and result >= 2) then
C_Timer.After(5, function()
if _G.DEFAULT_CHAT_FRAME then _G.DEFAULT_CHAT_FRAME:AddMessage("|cffbf40ff[Jagodka]|r |cffff5555Failed to register the addon prefix (too many addons?) - communication will not work.|r") end
end)
end
end

-- ============================================================================
-- 0B. KONFIGURACJA WSPÓLNEGO KANAŁU I BIAŁEJ LISTY GILDII
-- ============================================================================
local AllowedGuilds = {
    ["Testowo"] = true,
}
-- Gildie wspolnoty: "Jagódki Nadina", "Jagódki Nadina II", "... III", "... IV".
-- Kolejna gildia = kolejny przyrostek (np. " V") i podbicie wersji addonu.
for _, suffix in ipairs({ "", " II", " III", " IV" }) do
    AllowedGuilds["Jagódki Nadina" .. suffix] = true
end

local function IsPlayerGuildAllowed(guildName)
    if not guildName or guildName == "" or guildName == "Brak" then return false end
    return AllowedGuilds[guildName] == true
end

-- ============================================================================
-- 0C. WERSJA ADDONU (z pola "## Version" w .toc, wysylana w kazdym meldunku)
-- ============================================================================
local GetAddOnMetadata = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
local ADDON_VERSION = GetAddOnMetadata(addonName, "Version") or "0"

-- Porownanie "1.2.10" z "1.2.9": -1 gdy a starsza, 0 gdy ta sama, 1 gdy a nowsza
local function CompareVersions(a, b)
    local pa, pb = {}, {}
    for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return (x < y) and -1 or 1 end
    end
    return 0
end

-- ============================================================================
-- 1. KONFIGURACJA GŁÓWNEGO OKNA I PODSTAWOWE FUNKCJE RYSOWANIA
-- ============================================================================
local MainFrame = CreateFrame("Frame", "JagodkiNadinaMainFrame", UIParent, "BackdropTemplate")
MainFrame:SetSize(850, 620)
MainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
MainFrame:Hide()

MainFrame:EnableMouse(true)
MainFrame:SetMovable(true)
MainFrame:SetClampedToScreen(true)
-- Pozycja i rozmiar okna: JagodkiMinimapDB.window (wczytywane po ADDON_LOADED, sekcja 9).
-- Przesuwanie tylko za pasek tytulu, zmiana rozmiaru uchwytem w prawym dolnym rogu.
-- Najmniejszy rozmiar = domyslny (pod niego jest zrobiony uklad), wieksze okno = wiecej tresci.
local WIN_MIN_W, WIN_MIN_H, WIN_MAX_W, WIN_MAX_H = 850, 620, 1600, 1100
MainFrame:SetResizable(true)
if MainFrame.SetResizeBounds then MainFrame:SetResizeBounds(WIN_MIN_W, WIN_MIN_H, WIN_MAX_W, WIN_MAX_H)
else MainFrame:SetMinResize(WIN_MIN_W, WIN_MIN_H) MainFrame:SetMaxResize(WIN_MAX_W, WIN_MAX_H) end
function MainFrame.SaveLayout()
if not _G.JagodkiMinimapDB then return end
_G.JagodkiMinimapDB.window = { w = MainFrame:GetWidth(), h = MainFrame:GetHeight(), left = MainFrame:GetLeft(), top = MainFrame:GetTop() }
end
function MainFrame.ApplyLayout(w, h, left, top)
MainFrame:SetSize(math.min(WIN_MAX_W, math.max(WIN_MIN_W, w or WIN_MIN_W)), math.min(WIN_MAX_H, math.max(WIN_MIN_H, h or WIN_MIN_H)))
MainFrame:ClearAllPoints()
if left and top then MainFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
else MainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
end
-- Ile wierszy listy miesci sie w kontenerze o biezacej wysokosci (przed pierwszym ulozeniem: domyslnie)
function MainFrame.FitRows(container, topOffset, bottomPad, rowHeight, cap, default)
local h = container:GetHeight()
if not h or h <= 0 then return default end
return math.max(1, math.min(cap, math.floor((h - topOffset - bottomPad) / rowHeight)))
end

MainFrame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Buttons\\WHITE8X8", 
    tile = true, tileSize = 16, edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
})
MainFrame:SetBackdropColor(0.05, 0.05, 0.07, 0.95) 
MainFrame:SetBackdropBorderColor(0.15, 0.15, 0.2, 1) 

local HeaderBar = MainFrame:CreateTexture(nil, "BACKGROUND")
HeaderBar:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 1, -1)
HeaderBar:SetPoint("BOTTOMRIGHT", MainFrame, "TOPRIGHT", -1, -35)
HeaderBar:SetColorTexture(0.08, 0.08, 0.11, 1)

local TitleText = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
local WindowLogo = MainFrame:CreateTexture(nil, "OVERLAY")
WindowLogo:SetSize(64, 64) 
WindowLogo:SetPoint("LEFT", HeaderBar, "LEFT", 12, 0)
WindowLogo:SetTexture("Interface\\AddOns\\jagodka\\Media\\jagoda.tga")

TitleText:SetPoint("LEFT", WindowLogo, "RIGHT", 8, 0)
TitleText:SetText("|cffffffffJagodki Nadina|r |cffdecda5-|r Community")

local CloseBtn = CreateFrame("Button", nil, MainFrame, "UIPanelCloseButton")
CloseBtn:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -2, -2)
CloseBtn:SetSize(30, 30)
do
-- Pasek tytulu (logo + nazwa) = jedyne miejsce, za ktore mozna przesuwac okno
local DragBar = CreateFrame("Frame", nil, MainFrame)
DragBar:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 1, -1)
DragBar:SetPoint("BOTTOMRIGHT", MainFrame, "TOPRIGHT", -40, -35)
DragBar:EnableMouse(true)
DragBar:RegisterForDrag("LeftButton")
DragBar:SetScript("OnDragStart", function() MainFrame:StartMoving() end)
DragBar:SetScript("OnDragStop", function() MainFrame:StopMovingOrSizing() MainFrame.SaveLayout() end)
CloseBtn:SetFrameLevel(DragBar:GetFrameLevel() + 2)
-- Uchwyt zmiany rozmiaru: okno robi sie wieksze (czcionki bez zmian), zakladki pokazuja wiecej tresci
local Grip = CreateFrame("Button", nil, MainFrame)
Grip:SetSize(16, 16)
Grip:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", -2, 2)
Grip:SetFrameLevel(MainFrame:GetFrameLevel() + 20)
Grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
Grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
Grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
Grip:SetScript("OnMouseDown", function() MainFrame:StartSizing("BOTTOMRIGHT") end)
Grip:SetScript("OnMouseUp", function() MainFrame:StopMovingOrSizing() MainFrame.SaveLayout() end)
end

local OnlineText = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
OnlineText:SetPoint("RIGHT", CloseBtn, "LEFT", -10, 0)
OnlineText:SetText("Online: |cff00ff000|r")
-- Pasek synchronizacji w naglowku, na lewo od licznika (synchro.lua; widoczny tylko, gdy cos sie dzieje)
addonTable.Sync.Attach(MainFrame, OnlineText)

local Panels = {}
local tabNames = {"Chat", "Members", "Guilds", "Events", "Calendar", "Settings"}

local columns = {
    { name = "Name", width = 110, x = 10, key = "name" },
    { name = "Class", width = 90, x = 125, key = "class" },
    { name = "Lvl", width = 40, x = 220, key = "level" },
    { name = "Guild", width = 140, x = 265, key = "guild" },
    { name = "Rank", width = 65, x = 410, key = "rank" },
    { name = "Version", width = 50, x = 480, key = "version" }
}

local UpdateGuildTable = function() end
local UpdateEventsList = function() end
local UpdateCalendar = function() end
local UpdateMainTable = function() end
local UpdateScrollList = function() end
local UpdateRosterList = function() end
local UpdateEventDetails = function() end

local function ApplyModernStyle(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    frame:SetBackdropColor(0.07, 0.07, 0.09, 0.6)
    frame:SetBackdropBorderColor(0.15, 0.15, 0.2, 0.8)
end

local function CreatePhysicalIconAndText(parent, roleAtlas, xOffset)
    local img = parent:CreateTexture(nil, "OVERLAY")
    img:SetSize(16, 16)
    img:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, 0)
    img:SetAtlas(roleAtlas)
    
    local txt = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("LEFT", img, "RIGHT", 5, 0)
    txt:SetText("0")
    return txt
end

local function CreateLabelAndInput(parentFrame, labelName, yOffset, width, height)
    local lbl = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 20, yOffset) 
    lbl:SetText(labelName)
    local box = CreateFrame("EditBox", nil, parentFrame, "InputBoxTemplate")
    box:SetSize(width, height) 
    box:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 20, yOffset - 15)
    box:SetAutoFocus(false) 
    box:SetFontObject(ChatFontNormal)
    return box
end

-- ============================================================================
-- 1B. FUNKCJE SIECIOWE NA STABILNE KANAŁY BLIZZARDA
-- ============================================================================
-- Transport, kanal globalny i most /g sa w most.lua (wczytywany przed core.lua)
local Most = addonTable.Most
local Roster = addonTable.Roster
local Mute = addonTable.Mute

local function SendJagodkaNetworkPacket(prefixType, dataPayload, priority)
    local myGuild = GetGuildInfo("player")
    if not IsPlayerGuildAllowed(myGuild) then return end
    -- Jedna wysylka na kanal globalny (przed jego dolaczeniem: GUILD), przez kolejke z limitem
    -- priority "low" = synchronizacja (czat ma pierwszenstwo)
    Most.Send(prefixType, dataPayload, priority)
end

-- Kodowanie pol wydarzen, zeby ":" w tekscie (np. godzina 20:00) nie psul pakietu
local EncodeField, DecodeField = Most.EncodeField, Most.DecodeField

-- Wysylka wydarzenia: EV_ADD z poczatkiem opisu, reszta opisu w kolejnych pakietach EV_DESC
-- (pakiet addonu ma limit 255 bajtow, a opis moze miec do EVENT_DESC_MAX_BYTES)
local EVENT_DESC_MAX_BYTES, EVENT_MAX_DESC_PARTS = 400, 10
-- EV_ADD:id:tytul:data:godzina:opis1:autor:instancja:liczbaCzesci:gildiaAutora
local function SendEvent(ev, priority)
    local pre = table.concat({ EncodeField(ev.id), EncodeField(ev.title), EncodeField(ev.date), EncodeField(ev.time) }, ":") .. ":"
    local post = ":" .. EncodeField(ev.creator) .. ":" .. EncodeField(ev.dungeon) .. ":99:" .. EncodeField(ev.guild)
    local descHeader = "EV_DESC:" .. EncodeField(ev.id) .. ":99:"
    local chunks = Most.EncodeChunks(ev.desc, 245 - #"EV_ADD:" - #pre - #post, 245 - #descHeader)
    while #chunks > EVENT_MAX_DESC_PARTS do table.remove(chunks) end
    SendJagodkaNetworkPacket("EV_ADD", pre .. chunks[1] .. ":" .. EncodeField(ev.creator) .. ":" .. EncodeField(ev.dungeon) .. ":" .. #chunks .. ":" .. EncodeField(ev.guild), priority)
    for i = 2, #chunks do
        SendJagodkaNetworkPacket("EV_DESC", EncodeField(ev.id) .. ":" .. i .. ":" .. chunks[i], priority)
    end
end

local function SendStatusPacket(msgType)
    local guildName, rankName, rankIndex = GetGuildInfo("player")
    guildName = guildName or "Brak"
    rankName = rankName or "Brak"
    -- Indeks rangi pozwala innym sprawdzic uprawnienia oficerskie (tworzenie/usuwanie wydarzen)
    SendJagodkaNetworkPacket(msgType, UnitLevel("player") .. ":" .. select(2, UnitClass("player")) .. ":" .. guildName .. ":" .. rankName .. ":" .. ADDON_VERSION .. ":" .. (rankIndex or -1))
end

for i, name in ipairs(tabNames) do
    local p = CreateFrame("Frame", nil, MainFrame)
    -- Rozciaga sie z oknem (przy 850x620: 560x465); po prawej zostaje miejsce na panel graczy
    p:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 20, -135)
    p:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", -270, 20)
    p:Hide()
    Panels[i] = p
end

local menuButtons = {}
local function ShowTab(tabIndex)
    for i, panel in ipairs(Panels) do
        local btn = menuButtons[i]
        if i == tabIndex then 
            panel:Show() 
            if btn then
                btn.bg:SetColorTexture(0.14, 0.14, 0.19, 1)
                btn.line:SetColorTexture(1, 0.82, 0, 1) 
                btn.text:SetTextColor(1, 0.82, 0)
            end
            if i == 2 and UpdateMainTable then UpdateMainTable() end
            if i == 3 and UpdateGuildTable then UpdateGuildTable() end
            if i == 4 and UpdateEventsList then UpdateEventsList() end
            if i == 5 then UpdateCalendar() end
        else 
            panel:Hide() 
            if btn then
                btn.bg:SetColorTexture(0.08, 0.08, 0.11, 0.6)
                btn.line:SetColorTexture(0.15, 0.15, 0.2, 0.4)
                btn.text:SetTextColor(0.7, 0.7, 0.7)
            end
        end
    end
end

for i, name in ipairs(tabNames) do
    local btn = CreateFrame("Button", nil, MainFrame, "BackdropTemplate")
    btn:SetSize(115, 32)
    btn:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 20 + ((i-1) * 120), -50)
    
    btn:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    btn:SetBackdropBorderColor(0.15, 0.15, 0.2, 0.8)
    
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0.08, 0.08, 0.11, 0.6)
    
    btn.line = btn:CreateTexture(nil, "OVERLAY")
    btn.line:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    btn.line:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    btn.line:SetHeight(2)
    btn.line:SetColorTexture(0.15, 0.15, 0.2, 0.4)
    
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.text:SetText(name)
    
    btn:SetScript("OnEnter", function(self)
        local isActive = Panels[i]:IsShown()
        if not isActive then
            self.bg:SetColorTexture(0.12, 0.12, 0.16, 0.9)
            self.text:SetTextColor(1, 1, 1)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        local isActive = Panels[i]:IsShown()
        if not isActive then
            self.bg:SetColorTexture(0.08, 0.08, 0.11, 0.6)
            self.text:SetTextColor(0.7, 0.7, 0.7)
        end
    end)
    
    btn:SetScript("OnClick", function() ShowTab(i) end)
    menuButtons[i] = btn
end

-- ============================================================================
-- 2. BAZA DANYCH GRACZY I POMOCNICZE FUNKCJE RANG / KOLORÓW
-- ============================================================================
local activePlayers = {}
local filteredPlayers = {} 

local eventsList = {}
local selectedEventIndex = nil
local currentRosterFilter = "ALL"

local function GetPlayerIndex(name)
    for idx, player in ipairs(activePlayers) do
        if player.name == name then return idx end
    end
    return nil
end

local function GetColoredName(name)
    local idx = GetPlayerIndex(name)
    if idx then
        local player = activePlayers[idx]
        if player.class and RAID_CLASS_COLORS[player.class] then
local color = RAID_CLASS_COLORS[player.class]
return color:WrapTextInColorCode(name)
end
end
return name
end
local function GetColoredRank(rank)
if not rank or rank == "" or rank == "Brak" then return "|cff808080Member|r" end
local lowerRank = rank:lower()
if lowerRank:find("master") or lowerRank:find("lider") or lowerRank:find("szef") then
return "|cffffd100[" .. rank .. "]|r"
elseif lowerRank:find("oficer") or lowerRank:find("officer") then
return "|cff00ccff[" .. rank .. "]|r"
elseif lowerRank:find("raider") or lowerRank:find("weteran") then
return "|cff9370db[" .. rank .. "]|r"
else
return "|cffffffff[" .. rank .. "]|r"
end
end
-- Oficer = ranga 0/1 w gildii albo nazwa rangi wskazujaca na oficera/lidera (dziala tez dla innych graczy)
local function IsRankOfficer(rankName, rankIndex)
if rankIndex == 0 or rankIndex == 1 then return true end
if not rankName then return false end
local lowerRank = rankName:lower()
return (lowerRank:find("oficer") or lowerRank:find("officer") or lowerRank:find("master") or lowerRank:find("lider")) ~= nil
end
local function IsPlayerOfficer()
if not IsInGuild() then return false end
local _, rankName, rankIndex = GetGuildInfo("player")
return IsRankOfficer(rankName, rankIndex)
end
-- ZASADY WYDARZEN (sprawdzane lokalnie i u kazdego odbiorcy pakietu)
local MAX_EVENTS_PER_CREATOR = 10
local VALID_ROLES = { TANK = true, HEAL = true, DPS = true }
-- Usunac moze autor albo oficer dowolnej gildii z bialej listy
local function CanRemoveEvent(ev, name, guild, isOfficer)
if ev.creator == name then return true end
return isOfficer and IsPlayerGuildAllowed(guild)
end
local function CountEventsBy(creator)
local n = 0
for _, ev in ipairs(eventsList) do if ev.creator == creator then n = n + 1 end end
return n
end
-- Data: DD.MM lub DD.MM.RRRR, godzina: GG:MM
local function IsValidEventDate(s)
local d, m, y = s:match("^(%d%d?)%.(%d%d?)%.?(%d*)$")
d, m = tonumber(d), tonumber(m)
return d ~= nil and d >= 1 and d <= 31 and m >= 1 and m <= 12 and (y == "" or #y == 4)
end
local function IsValidEventTime(s)
local h, mi = s:match("^(%d%d?):(%d%d)$")
h, mi = tonumber(h), tonumber(mi)
return h ~= nil and h <= 23 and mi <= 59
end
local function ShowEventError(text) UIErrorsFrame:AddMessage("Error: " .. text, 1.0, 0.1, 0.1, 1.0, 2) end
-- ============================================================================
-- SYNCHRONIZACJA WYDARZEN (Events i Calendar maja te same dane u wszystkich)
-- ============================================================================
--  * Po zalogowaniu (i przy otwarciu Events/Calendar, najwyzej co 5 min) leci EV_REQ.
--  * Odpowiada JEDNA losowa osoba z addonem (nie tylko autor - autor moze byc offline):
--    po 1-4 s wysyla EV_CLAIM, reszta rezygnuje. Wysylka na kanal, wiec korzystaja wszyscy.
--  * Wysylane sa wydarzenia (EV_ADD/EV_DESC) i zapisy (EV_ROS), z niskim priorytetem.
--  * Usuniete wydarzenia sa pamietane 30 dni (nie wroca od kogos, kto byl offline).
--  * Wydarzenia starsze niz 2 dni po terminie same znikaja.
local EventSync = { pending = {}, lastRequest = 0, lastBroadcast = 0, KEEP_DAYS = 2, TOMBSTONE_DAYS = 30 }
-- Czas wydarzenia (poludnie danego dnia) z "DD.MM.YYYY" albo starego "DD.MM" (biezacy rok)
function EventSync.DayTime(dateText)
local d, m, y = (dateText or ""):match("^(%d%d?)%.(%d%d?)%.?(%d*)$")
if not d then return nil end
return time({ year = tonumber(y) or tonumber(date("%Y")), month = tonumber(m), day = tonumber(d), hour = 12 })
end
function EventSync.IsExpired(dateText)
local t = EventSync.DayTime(dateText)
return t ~= nil and time() - t > EventSync.KEEP_DAYS * 86400
end
-- Znaczniki usuniecia: JagodkiEventsDB.removed[id] = czas (pole poza czescia tablicowa, ipairs go pomija)
function EventSync.Removed()
local db = _G.JagodkiEventsDB
if not db then return {} end
db.removed = db.removed or {}
return db.removed
end
function EventSync.MarkRemoved(id) if id then EventSync.Removed()[id] = time() end end
function EventSync.Prune()
local changed = false
for i = #eventsList, 1, -1 do
if EventSync.IsExpired(eventsList[i].date) then table.remove(eventsList, i) changed = true end
end
if changed then selectedEventIndex = nil end
local removed, now = EventSync.Removed(), time()
for id, t in pairs(removed) do
if now - t > EventSync.TOMBSTONE_DAYS * 86400 then removed[id] = nil end
end
end
-- EV_ROS:id:Nick=TANK,Nick2=HEAL,... (w razie potrzeby kilka pakietow)
function EventSync.SendRoster(ev)
local header, chunk = EncodeField(ev.id) .. ":", ""
for name, role in pairs(ev.roster or {}) do
local entry = name .. "=" .. role
if chunk ~= "" and #header + #chunk + 1 + #entry > 240 then
SendJagodkaNetworkPacket("EV_ROS", header .. chunk, "low")
chunk = ""
end
chunk = (chunk == "") and entry or (chunk .. "," .. entry)
end
if chunk ~= "" then SendJagodkaNetworkPacket("EV_ROS", header .. chunk, "low") end
end
function EventSync.Request(force)
if not force and GetTime() - EventSync.lastRequest < 300 then return end
EventSync.lastRequest = GetTime()
SendJagodkaNetworkPacket("EV_REQ", "ZAPYTANIE")
addonTable.Sync.Start("events")
end
function EventSync.HandleRequest(requester)
if #eventsList == 0 then return end
EventSync.pending[requester] = true
C_Timer.After(1 + math.random() * 3, function()
if not EventSync.pending[requester] then return end
EventSync.pending[requester] = nil
SendJagodkaNetworkPacket("EV_CLAIM", requester)
-- Kilka logowan naraz: jedna wysylka na kanal wystarczy dla wszystkich
if GetTime() - EventSync.lastBroadcast < 15 then return end
EventSync.lastBroadcast = GetTime()
EventSync.Prune()
for _, ev in ipairs(eventsList) do
SendEvent(ev, "low")
EventSync.SendRoster(ev)
end
end)
end
local function AddMyselfToActiveList()
local myName = UnitName("player")
local level = UnitLevel("player")
local _, classFilename = UnitClass("player")
local guildName, rankName, rankIndex = GetGuildInfo("player")
guildName = guildName or "Brak"
rankName = rankName or "Brak"
if not IsPlayerGuildAllowed(guildName) then return end
local existingIndex = GetPlayerIndex(myName)
local playerData = {
name = myName, level = level, class = classFilename, guild = guildName, rank = rankName, rankIndex = rankIndex, version = ADDON_VERSION, lastSeen = GetTime()
}
if existingIndex then activePlayers[existingIndex] = playerData else table.insert(activePlayers, playerData) end
end
-- ============================================================================
-- 3. ZAKŁADKA 1: PANEL CZATU
-- ============================================================================
local ChatPanel = CreateFrame("Frame", nil, Panels[1], "BackdropTemplate")
ChatPanel:SetPoint("TOPLEFT", Panels[1], "TOPLEFT", 0, 0)
ChatPanel:SetPoint("BOTTOMRIGHT", Panels[1], "BOTTOMRIGHT", 0, 30)
ApplyModernStyle(ChatPanel)
local chatDisplay = CreateFrame("ScrollingMessageFrame", nil, ChatPanel)
chatDisplay:SetPoint("TOPLEFT", ChatPanel, "TOPLEFT", 12, -12)
chatDisplay:SetPoint("BOTTOMRIGHT", ChatPanel, "BOTTOMRIGHT", -32, 45)
chatDisplay:SetFontObject(ChatFontNormal)
chatDisplay:SetMaxLines(200)
chatDisplay:SetFading(false)
chatDisplay:SetJustifyH("LEFT")
-- Kolko myszy: 3 linie (Shift = cala strona, Ctrl = poczatek / koniec historii)
chatDisplay:EnableMouseWheel(true)
chatDisplay:SetScript("OnMouseWheel", function(self, delta)
if _G.IsControlKeyDown() then
if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
elseif _G.IsShiftKeyDown() then
if delta > 0 then self:PageUp() else self:PageDown() end
else
for _ = 1, 3 do if delta > 0 then self:ScrollUp() else self:ScrollDown() end end
end
self.SyncBar()
end)
-- Pasek przewijania z prawej (strzalki + suwak), zsynchronizowany z kolkiem i nowymi wiadomosciami.
-- Offset czatu: 0 = najnowsze (dol); suwak: 0 = gora, max = dol.
do
local bar = CreateFrame("Slider", nil, ChatPanel)
bar:SetWidth(16)
bar:SetPoint("TOPRIGHT", ChatPanel, "TOPRIGHT", -9, -28)
bar:SetPoint("BOTTOMRIGHT", ChatPanel, "BOTTOMRIGHT", -9, 61)
bar:SetOrientation("VERTICAL")
bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
bar:GetThumbTexture():SetSize(18, 24)
bar.bg = bar:CreateTexture(nil, "BACKGROUND")
bar.bg:SetAllPoints()
bar.bg:SetColorTexture(0, 0, 0, 0.3)
bar:SetMinMaxValues(0, 0)
bar:SetValueStep(1)
if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end
bar:EnableMouseWheel(true)
bar:SetScript("OnMouseWheel", function(_, delta) chatDisplay:GetScript("OnMouseWheel")(chatDisplay, delta) end)
local up = CreateFrame("Button", nil, ChatPanel, "UIPanelScrollUpButtonTemplate")
up:SetPoint("BOTTOM", bar, "TOP", 0, 0)
local down = CreateFrame("Button", nil, ChatPanel, "UIPanelScrollDownButtonTemplate")
down:SetPoint("TOP", bar, "BOTTOM", 0, 0)
local syncing = false
local function MaxRange()
if chatDisplay.GetMaxScrollRange then return chatDisplay:GetMaxScrollRange() or 0 end
return math.max(0, chatDisplay:GetNumMessages() - 1)
end
chatDisplay.SyncBar = function()
local max, offset = MaxRange(), chatDisplay:GetScrollOffset() or 0
syncing = true
bar:SetMinMaxValues(0, max)
bar:SetValue(max - offset)
syncing = false
up:SetEnabled(offset < max)
down:SetEnabled(offset > 0)
end
bar:SetScript("OnValueChanged", function(_, value)
if syncing or not chatDisplay.SetScrollOffset then return end
chatDisplay:SetScrollOffset(MaxRange() - math.floor(value + 0.5))
chatDisplay.SyncBar()
end)
up:SetScript("OnClick", function() chatDisplay:ScrollUp() chatDisplay.SyncBar() end)
down:SetScript("OnClick", function() chatDisplay:ScrollDown() chatDisplay.SyncBar() end)
if chatDisplay.SetOnScrollChangedCallback then chatDisplay:SetOnScrollChangedCallback(function() chatDisplay.SyncBar() end) end
chatDisplay:HookScript("OnSizeChanged", function() chatDisplay.SyncBar() end)
end
local chatInput = CreateFrame("EditBox", nil, ChatPanel, "InputBoxTemplate")
-- Pole wpisywania rozciaga sie z oknem, przycisk Send zostaje przy prawej krawedzi
chatInput:SetHeight(26)
chatInput:SetPoint("BOTTOMLEFT", ChatPanel, "BOTTOMLEFT", 12, 10)
chatInput:SetPoint("BOTTOMRIGHT", ChatPanel, "BOTTOMRIGHT", -95, 10)
chatInput:SetAutoFocus(false)
chatInput:SetFontObject(ChatFontNormal)
-- Dluzsze wiadomosci most.lua sam dzieli na czesci (limit 255 bajtow na pakiet)
chatInput:SetMaxBytes(255)
-- Shift + klik na przedmiot / zaklecie / profesje wstawia link do pola, gdy to ono jest aktywne
-- (gra wstawia linki tylko do swojego okna czatu)
hooksecurefunc("ChatEdit_InsertLink", function(link) if link and chatInput:HasFocus() then chatInput:Insert(link) end end)
local sendButton = CreateFrame("Button", nil, ChatPanel, "GameMenuButtonTemplate")
sendButton:SetSize(75, 26)
sendButton:SetPoint("LEFT", chatInput, "RIGHT", 8, 0)
sendButton:SetText("Send")
local chatTabs = {"Ogolny", "Handel", "Szukaj grupy"}
local currentChatTab = "Ogolny"
local chatTabButtons = {}
-- Czat pokazuje jeden wspolny log z most.lua (wszystkie gildie, ta sama kolejnosc u kazdego)
local function RefreshChatDisplay()
chatDisplay:Clear()
for _, entry in ipairs(Most.GetLog()) do
-- Nicki jako linki (menu w wyciszenie.lua); wiadomosci wyciszonych ukryte (wracaja po odciszeniu)
if entry.tab == currentChatTab and not Mute.IsMuted(entry.author) then chatDisplay:AddMessage(Most.FormatEntry(entry, true)) end
end
-- Zakres suwaka jest znany dopiero po ulozeniu linii (nastepna klatka)
chatDisplay.SyncBar()
C_Timer.After(0, chatDisplay.SyncBar)
end
local function UpdateChatTabVisuals()
for name, btn in pairs(chatTabButtons) do
if name == currentChatTab then
btn.bg:SetColorTexture(0.14, 0.14, 0.19, 1)
btn.topLine:SetColorTexture(1, 0.82, 0, 1)
btn.text:SetTextColor(1, 0.82, 0)
else
btn.bg:SetColorTexture(0.06, 0.06, 0.08, 0.8)
btn.topLine:SetColorTexture(0.15, 0.15, 0.2, 0.5)
btn.text:SetTextColor(0.6, 0.6, 0.6)
end
end
RefreshChatDisplay()
end
local function OriginalSubmitMessage()
local msg = chatInput:GetText()
if msg and msg ~= "" then
local guildName = GetGuildInfo("player")
if Mute.IsMuted(UnitName("player")) then
chatDisplay:AddMessage("|cffff5555[System]: You are muted on the community chat (by " .. tostring(Mute.MutedBy(UnitName("player"))) .. ") - message not sent.|r")
elseif IsPlayerGuildAllowed(guildName) then
-- Kanal globalny raz; relaye gildii wkleja wiadomosc do swoich /g
Most.Publish(currentChatTab, msg, "A", UnitName("player"), guildName)
else
chatDisplay:AddMessage("|cffff5555[System]: Your guild is not on the Community list - message not sent.|r")
end
chatInput:SetText("")
end
chatInput:ClearFocus()
end
sendButton:SetScript("OnClick", OriginalSubmitMessage)
chatInput:SetScript("OnEnterPressed", OriginalSubmitMessage)
for i, name in ipairs(chatTabs) do
local tBtn = CreateFrame("Button", nil, ChatPanel, "BackdropTemplate")
tBtn:SetSize(100, 22)
tBtn.customXOffset = 10 + ((i-1) * 104)
tBtn:SetPoint("BOTTOMLEFT", ChatPanel, "TOPLEFT", tBtn.customXOffset, 0)
tBtn:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
tBtn:SetBackdropBorderColor(0.15, 0.15, 0.2, 0.8)
tBtn.bg = tBtn:CreateTexture(nil, "BACKGROUND")
tBtn.bg:SetAllPoints()
tBtn.topLine = tBtn:CreateTexture(nil, "OVERLAY")
tBtn.topLine:SetPoint("TOPLEFT", tBtn, "TOPLEFT", 0, 0)
tBtn.topLine:SetPoint("TOPRIGHT", tBtn, "TOPRIGHT", 0, 0)
tBtn.topLine:SetHeight(2)
tBtn.text = tBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
tBtn.text:SetPoint("CENTER", tBtn, "CENTER", 0, 0)
tBtn.text:SetText(({ Ogolny = "General", Handel = "Trade", ["Szukaj grupy"] = "LFG" })[name] or name)
tBtn:SetScript("OnClick", function() currentChatTab = name UpdateChatTabVisuals() end)
chatTabButtons[name] = tBtn
end
-- Podpiecie mostu pod dane i widok czatu z core.lua
Most.Init({
activePlayers = activePlayers,
isGuildAllowed = IsPlayerGuildAllowed,
colorName = GetColoredName,
onChatChanged = function(tab) if tab == currentChatTab then RefreshChatDisplay() end end,
})
Mute.Init({
activePlayers = activePlayers,
isGuildAllowed = IsPlayerGuildAllowed,
isRankOfficer = IsRankOfficer,
isMeOfficer = IsPlayerOfficer,
onChanged = function() RefreshChatDisplay() UpdateMainTable() end,
})
Mute.AttachChat(chatDisplay)
Roster.Init({
activePlayers = activePlayers,
isGuildAllowed = IsPlayerGuildAllowed,
allowedGuilds = AllowedGuilds,
onChanged = function() UpdateMainTable() UpdateScrollList() if Panels[3]:IsVisible() then UpdateGuildTable() end end,
})
-- ============================================================================
-- 4. ZAKŁADKA 2: GŁÓWNA TABELA GRACZY + WYSZUKIWARKA
-- ============================================================================
local TableContainer = CreateFrame("Frame", nil, Panels[2], "BackdropTemplate")
TableContainer:SetPoint("TOPLEFT", Panels[2], "TOPLEFT", 0, -45)
TableContainer:SetPoint("BOTTOMRIGHT", Panels[2], "BOTTOMRIGHT", 0, 30)
ApplyModernStyle(TableContainer)
local SearchEditBox = CreateFrame("EditBox", "JagodkiSearchEditBox", Panels[2], "InputBoxTemplate")
SearchEditBox:SetSize(220, 26)
SearchEditBox:SetPoint("TOPLEFT", Panels[2], "TOPLEFT", 65, -5)
SearchEditBox:SetAutoFocus(false)
SearchEditBox:SetFontObject(ChatFontNormal)
local SearchLabel = Panels[2]:CreateFontString(nil, "OVERLAY", "GameFontNormal")
SearchLabel:SetPoint("RIGHT", SearchEditBox, "LEFT", -8, 0)
SearchLabel:SetText("Search:")
SearchEditBox.Instructions = SearchEditBox:CreateFontString(nil, "ARTWORK", "GameFontDisable")
SearchEditBox.Instructions:SetPoint("LEFT", SearchEditBox, "LEFT", 5, 0)
SearchEditBox.Instructions:SetText("Name, class, guild or rank...")
-- Domyslnie tylko online; zaznaczone = wszyscy czlonkowie gildii z listy (takze offline)
local ShowOfflineCheck = CreateFrame("CheckButton", nil, Panels[2], "UICheckButtonTemplate")
ShowOfflineCheck:SetSize(24, 24)
ShowOfflineCheck:SetPoint("LEFT", SearchEditBox, "RIGHT", 15, 0)
ShowOfflineCheck:SetChecked(false)
ShowOfflineCheck.label = ShowOfflineCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
ShowOfflineCheck.label:SetPoint("LEFT", ShowOfflineCheck, "RIGHT", 2, 0)
ShowOfflineCheck.label:SetText("Show offline")
ShowOfflineCheck:SetScript("OnClick", function() UpdateMainTable() end)
SearchEditBox:SetScript("OnTextChanged", function(self)
if self:GetText() == "" then self.Instructions:Show() else self.Instructions:Hide() end
UpdateMainTable()
end)
-- Sortowanie: klik w naglowek = rosnaco, drugi = malejaco, trzeci = domyslnie (online, gildia, nick)
-- Stronicowanie: MEMBERS_PER_PAGE osob na strone, scroll w obrebie strony
local MEMBERS_PER_PAGE = 50
local membersView = { sortKey = nil, desc = false, page = 1 }
local function UpdateSortHeaders()
for _, col in ipairs(columns) do
local arrow = (membersView.sortKey == col.key) and (membersView.desc and " v" or " ^") or ""
col.header.text:SetText(col.name .. arrow)
if membersView.sortKey == col.key then col.header.text:SetTextColor(1, 1, 1) else col.header.text:SetTextColor(1, 0.82, 0) end
end
end
for _, col in ipairs(columns) do
local h = CreateFrame("Button", nil, TableContainer)
h:SetSize(col.width, 18)
h:SetPoint("TOPLEFT", TableContainer, "TOPLEFT", col.x, -6)
h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
h.text:SetPoint("LEFT", h, "LEFT", 0, 0)
h:SetScript("OnClick", function()
if membersView.sortKey ~= col.key then membersView.sortKey, membersView.desc = col.key, false
elseif not membersView.desc then membersView.desc = true
else membersView.sortKey, membersView.desc = nil, false end
membersView.page = 1
UpdateSortHeaders()
UpdateMainTable()
end)
col.header = h
end
UpdateSortHeaders()
-- Reset: czysci wyszukiwarke, wylacza "Pokaz offline" (domyslnie), przywraca domyslne sortowanie i strone 1
do
local ResetViewBtn = CreateFrame("Button", nil, Panels[2], "UIPanelButtonTemplate")
ResetViewBtn:SetSize(70, 22)
ResetViewBtn:SetPoint("LEFT", ShowOfflineCheck.label, "RIGHT", 15, 0)
ResetViewBtn:SetText("Reset")
ResetViewBtn:SetScript("OnClick", function()
SearchEditBox:SetText("")
SearchEditBox:ClearFocus()
ShowOfflineCheck:SetChecked(false)
membersView.sortKey, membersView.desc, membersView.page = nil, false, 1
UpdateSortHeaders()
UpdateMainTable()
end)
end
local mainScrollFrame = CreateFrame("ScrollFrame", "JagodkiMainTableScrollFrame", TableContainer, "FauxScrollFrameTemplate")
mainScrollFrame:SetPoint("TOPLEFT", TableContainer, "TOPLEFT", 0, -30)
mainScrollFrame:SetPoint("BOTTOMRIGHT", TableContainer, "BOTTOMRIGHT", -26, 6)
local MAIN_ROW_HEIGHT = 22
-- Wierszy tworzymy na zapas (najwyzsze okno); widac tyle, ile miesci sie w tabeli (TableContainer.visibleRows)
local MAX_MAIN_ROWS = 42
local tableRows = {}
for i = 1, MAX_MAIN_ROWS do
local row = CreateFrame("Button", nil, TableContainer)
row:SetHeight(MAIN_ROW_HEIGHT)
row:SetPoint("TOPLEFT", TableContainer, "TOPLEFT", 5, -30 - ((i-1) * MAIN_ROW_HEIGHT))
row:SetPoint("RIGHT", TableContainer, "RIGHT", -25, 0)
local tex = row:CreateTexture(nil, "BACKGROUND")
tex:SetAllPoints()
tex:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.02 or 0.04)
row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
row.nameText:SetPoint("LEFT", row, "LEFT", 10, 0)
row.classIcon = row:CreateTexture(nil, "ARTWORK")
row.classIcon:SetSize(13, 13)
row.classIcon:SetPoint("LEFT", row, "LEFT", 125, 0)
row.classText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
row.classText:SetPoint("LEFT", row.classIcon, "RIGHT", 5, 0)
row.levelText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
row.levelText:SetPoint("LEFT", row, "LEFT", 220, 0)
row.guildText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
row.guildText:SetPoint("LEFT", row, "LEFT", 265, 0)
row.rankText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
row.rankText:SetPoint("LEFT", row, "LEFT", 410, 0)
-- Dluga ranga jest ucinana, zeby nie nachodzila na kolumne wersji
row.rankText:SetWidth(65) row.rankText:SetJustifyH("LEFT") row.rankText:SetWordWrap(false)
row.versionText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
row.versionText:SetPoint("LEFT", row, "LEFT", 480, 0)
tableRows[i] = row
end
-- Klik w wiersz: prawy = menu (Szepnij), Shift + lewy = od razu szept. Szept tylko do graczy online.
do
local MemberMenu = CreateFrame("Frame", "JagodkiMemberMenu", UIParent, "UIDropDownMenuTemplate")
local menuMember = nil
_G.UIDropDownMenu_Initialize(MemberMenu, function(self, level)
if not menuMember then return end
local info = _G.UIDropDownMenu_CreateInfo()
info.text, info.isTitle, info.notCheckable = menuMember.name, true, true
_G.UIDropDownMenu_AddButton(info, level)
info = _G.UIDropDownMenu_CreateInfo()
info.text = menuMember.online and "Whisper" or "Whisper (offline)"
info.disabled = not menuMember.online
info.notCheckable = true
local target = menuMember.name
info.func = function() _G.ChatFrame_SendTell(target) end
_G.UIDropDownMenu_AddButton(info, level)
info = _G.UIDropDownMenu_CreateInfo()
info.text = menuMember.online and "Invite to group" or "Invite to group (offline)"
info.disabled = not menuMember.online
info.notCheckable = true
-- Nowsze klienty maja C_PartyInfo.InviteUnit, starsze tylko InviteUnit
info.func = function()
local invite = (_G.C_PartyInfo and _G.C_PartyInfo.InviteUnit) or _G.InviteUnit
if invite then invite(target) end
end
_G.UIDropDownMenu_AddButton(info, level)
-- Mute / Unmute jak w menu czatu (uprawnienia: wyciszenie.lua)
local muted, me = Mute.IsMuted(target), UnitName("player")
if (muted and Mute.CanUnmute(me)) or (not muted and Mute.CanMute(me, target)) then
info = _G.UIDropDownMenu_CreateInfo()
info.text, info.notCheckable = muted and "Unmute" or "Mute on community chat", true
info.func = function() if muted then Mute.Set(target, false) else Mute.AskReason(target) end end
_G.UIDropDownMenu_AddButton(info, level)
end
info = _G.UIDropDownMenu_CreateInfo()
info.text, info.notCheckable = "Cancel", true
info.func = function() _G.CloseDropDownMenus() end
_G.UIDropDownMenu_AddButton(info, level)
end, "MENU")
-- Wspolne z panelem "Aktywni gracze" (wiersz ma pole member z Roster.BuildList)
membersView.OnRowClick = function(self, button)
local m = self.member
if not m or m.name == UnitName("player") then return end
if button == "RightButton" then
menuMember = m
_G.ToggleDropDownMenu(1, nil, MemberMenu, "cursor", 0, 0)
elseif button == "LeftButton" and _G.IsShiftKeyDown() and m.online then
_G.ChatFrame_SendTell(m.name)
end
end
for _, row in ipairs(tableRows) do
row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
row:SetScript("OnClick", membersView.OnRowClick)
end
end
-- Rysuje wiersze z gotowej listy (scroll nie przelicza listy od nowa)
-- Pasek stron pod tabela: "Pokazano 51-100 z 312 (48 online)   [<<] [<] Strona 2 / 7 [>] [>>]"
local PageNav = CreateFrame("Frame", nil, Panels[2])
PageNav:SetHeight(26)
PageNav:SetPoint("TOPLEFT", TableContainer, "BOTTOMLEFT", 0, -4)
PageNav:SetPoint("TOPRIGHT", TableContainer, "BOTTOMRIGHT", 0, -4)
PageNav.infoText = PageNav:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
PageNav.infoText:SetPoint("LEFT", PageNav, "LEFT", 8, 0)
PageNav.buttons = {}
for i, label in ipairs({ "<<", "<", ">", ">>" }) do
local b = CreateFrame("Button", nil, PageNav, "UIPanelButtonTemplate")
b:SetSize(30, 20)
b:SetText(label)
PageNav.buttons[i] = b
end
PageNav.pageText = PageNav:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
PageNav.pageText:SetWidth(90)
PageNav.buttons[4]:SetPoint("RIGHT", PageNav, "RIGHT", -4, 0)
PageNav.buttons[3]:SetPoint("RIGHT", PageNav.buttons[4], "LEFT", -2, 0)
PageNav.pageText:SetPoint("RIGHT", PageNav.buttons[3], "LEFT", -4, 0)
PageNav.buttons[2]:SetPoint("RIGHT", PageNav.pageText, "LEFT", -4, 0)
PageNav.buttons[1]:SetPoint("RIGHT", PageNav.buttons[2], "LEFT", -2, 0)
local function RenderMainTable()
local total = #filteredPlayers
local pages = math.max(1, math.ceil(total / MEMBERS_PER_PAGE))
if membersView.page > pages then membersView.page = pages end
local page = membersView.page
local first = (page - 1) * MEMBERS_PER_PAGE
local count = math.min(MEMBERS_PER_PAGE, total - first)
PageNav.infoText:SetText(total == 0 and "No players" or ("Showing " .. (first + 1) .. "-" .. (first + count) .. " of " .. total .. " |cff00ff00(" .. (membersView.online or 0) .. " online)|r"))
PageNav.pageText:SetText("Page " .. page .. " / " .. pages)
PageNav.buttons[1]:SetEnabled(page > 1) PageNav.buttons[2]:SetEnabled(page > 1)
PageNav.buttons[3]:SetEnabled(page < pages) PageNav.buttons[4]:SetEnabled(page < pages)
local visible = TableContainer.visibleRows or 16
_G.FauxScrollFrame_Update(mainScrollFrame, count, visible, MAIN_ROW_HEIGHT)
local offset = _G.FauxScrollFrame_GetOffset(mainScrollFrame)
for i = 1, MAX_MAIN_ROWS do
local dataIndex = i + offset local row = tableRows[i]
if i <= visible and dataIndex <= count then
local data = filteredPlayers[first + dataIndex]
row.member = data
local classColor = data.class and RAID_CLASS_COLORS[data.class]
row.nameText:SetText(classColor and classColor:WrapTextInColorCode(data.name) or data.name)
-- Ikonka wyciszenia za nickiem (tooltip z powodem) - wyciszenie.lua
Mute.DecorateName(row, row.nameText, data.name)
row.classText:SetText(classColor and classColor:WrapTextInColorCode(LOCALIZED_CLASS_NAMES_MALE[data.class] or data.class) or "Unknown")
row.levelText:SetText(data.level) row.rankText:SetText(GetColoredRank(data.rank))
-- Zielona = ta sama wersja, czerwona = starsza, zolta = nowsza od mojej
-- Bez wersji = gracz bez addonu (znany tylko z rostera gildii)
if data.version then
local vCmp = CompareVersions(data.version, ADDON_VERSION)
local vColor = (vCmp == 0) and "|cff00ff00" or ((vCmp < 0) and "|cffff5555" or "|cffffd100")
row.versionText:SetText(vColor .. data.version .. "|r")
else row.versionText:SetText("|cff808080-|r") end
-- Offline wyszarzony
row:SetAlpha(data.online and 1 or 0.45)
row.guildText:SetText((data.guild and data.guild ~= "Brak") and ("|cffbf40ff" .. data.guild .. "|r") or "|cff808080No guild|r")
if data.class and CLASS_ICON_TCOORDS[data.class] then
row.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
row.classIcon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[data.class])) row.classIcon:Show()
else row.classIcon:Hide() end
row:Show()
else row:Hide() end
end
end
-- Przeliczenie listy (setki osob): tylko przy widocznej zakladce i najwyzej raz na 0.3 s,
-- nawet gdy naraz przyjdzie wiele meldunkow / pakietow rostera / liter w wyszukiwarce
local mainTablePending = false
local function RebuildMainTable()
mainTablePending = false
if not Panels[2]:IsVisible() then return end
wipe(filteredPlayers)
local filterText = SearchEditBox:GetText():lower()
for _, player in ipairs(Roster.BuildList(ShowOfflineCheck:GetChecked())) do
if filterText == "" then table.insert(filteredPlayers, player)
else
if player.name:lower():find(filterText, 1, true) or (player.class and player.class:lower():find(filterText, 1, true)) or (player.guild and player.guild:lower():find(filterText, 1, true)) or (player.rank and player.rank:lower():find(filterText, 1, true)) then
table.insert(filteredPlayers, player)
end
end
end
-- Nowe wyszukiwanie / przelacznik offline = powrot na pierwsza strone (zwykle odswiezenie zostawia strone)
local filterKey = filterText .. (ShowOfflineCheck:GetChecked() and "|1" or "|0")
if filterKey ~= membersView.filterKey then membersView.filterKey, membersView.page = filterKey, 1 end
local online = 0
for _, p in ipairs(filteredPlayers) do if p.online then online = online + 1 end end
membersView.online = online
-- Bez wybranej kolumny zostaje kolejnosc z Roster.BuildList (online, gildia, nick)
local key, desc = membersView.sortKey, membersView.desc
if key then
table.sort(filteredPlayers, function(a, b)
local va, vb
if key == "level" then va, vb = tonumber(a.level) or 0, tonumber(b.level) or 0
elseif key == "rank" then va, vb = a.rankIndex or 99, b.rankIndex or 99
elseif key == "version" then va, vb = CompareVersions(a.version or "0", b.version or "0"), 0
elseif key == "class" then va, vb = LOCALIZED_CLASS_NAMES_MALE[a.class] or a.class or "", LOCALIZED_CLASS_NAMES_MALE[b.class] or b.class or ""
else va, vb = (a[key] or ""):lower(), (b[key] or ""):lower() end
if va ~= vb then if desc then return va > vb end return va < vb end
if a.online ~= b.online then return a.online end
return a.name < b.name
end)
end
RenderMainTable()
end
-- Przyciski stron: pierwsza, poprzednia, nastepna, ostatnia (scroll wraca na gore strony)
for i, b in ipairs(PageNav.buttons) do
b:SetScript("OnClick", function()
local pages = math.max(1, math.ceil(#filteredPlayers / MEMBERS_PER_PAGE))
local target = ({ 1, membersView.page - 1, membersView.page + 1, pages })[i]
membersView.page = math.max(1, math.min(pages, target))
_G.FauxScrollFrame_SetOffset(mainScrollFrame, 0)
local bar = _G[mainScrollFrame:GetName() .. "ScrollBar"]
if bar then bar:SetValue(0) end
RenderMainTable()
end)
end
UpdateMainTable = function()
if mainTablePending or not Panels[2]:IsVisible() then return end
mainTablePending = true
C_Timer.After(0.3, RebuildMainTable)
end
mainScrollFrame:SetScript("OnVerticalScroll", function(self, offset) _G.FauxScrollFrame_OnVerticalScroll(self, offset, MAIN_ROW_HEIGHT, RenderMainTable) end)
TableContainer:SetScript("OnSizeChanged", function(self)
self.visibleRows = MainFrame.FitRows(self, 30, 6, MAIN_ROW_HEIGHT, MAX_MAIN_ROWS, 16)
if self:IsVisible() then RenderMainTable() end
end)
-- ============================================================================
-- 5. ZAKŁADKA 3: PANEL GILDII
-- ============================================================================
local GuildContainer = CreateFrame("Frame", nil, Panels[3], "BackdropTemplate")
GuildContainer:SetPoint("TOPLEFT", Panels[3], "TOPLEFT", 0, 0)
GuildContainer:SetPoint("BOTTOMRIGHT", Panels[3], "BOTTOMRIGHT", 0, 30)
ApplyModernStyle(GuildContainer)
local GuildTitleText = GuildContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
GuildTitleText:SetPoint("TOPLEFT", GuildContainer, "TOPLEFT", 15, -12)
GuildTitleText:SetText("Community Guilds")
local guildScrollFrame = CreateFrame("ScrollFrame", "JagodkiGuildTableScrollFrame", GuildContainer, "FauxScrollFrameTemplate")
guildScrollFrame:SetPoint("TOPLEFT", GuildContainer, "TOPLEFT", 0, -40)
guildScrollFrame:SetPoint("BOTTOMRIGHT", GuildContainer, "BOTTOMRIGHT", -26, 10)
local GUILD_ROW_HEIGHT = 48
-- Kart na zapas; widac tyle, ile miesci sie w zakladce (GuildContainer.visibleRows)
local MAX_GUILD_ROWS = 18
local guildRows = {}
for i = 1, MAX_GUILD_ROWS do
local card = CreateFrame("Frame", nil, GuildContainer, "BackdropTemplate")
card:SetHeight(GUILD_ROW_HEIGHT - 6)
card:SetPoint("TOPLEFT", GuildContainer, "TOPLEFT", 10, -45 - ((i-1) * GUILD_ROW_HEIGHT))
card:SetPoint("RIGHT", GuildContainer, "RIGHT", -30, 0)
card:SetBackdrop({
bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
insets = { left = 0, right = 0, top = 0, bottom = 0 }
})
card:SetBackdropColor(0.09, 0.09, 0.12, 0.8)
card:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.6)
card.icon = card:CreateTexture(nil, "ARTWORK")
card.icon:SetSize(24, 26)
card.icon:SetPoint("LEFT", card, "LEFT", 15, 0)
card.icon:SetTexture("Interface\\GuildFrame\\GuildFrame")
card.icon:SetTexCoord(0.63, 0.69, 0.60, 0.73)
card.nameText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
card.nameText:SetPoint("LEFT", card.icon, "RIGHT", 15, 1)
card.activeText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
card.activeText:SetPoint("RIGHT", card, "RIGHT", -150, 0)
card.inactiveText = card:CreateFontString(nil, "OVERLAY", "GameFontDisable")
card.inactiveText:SetPoint("RIGHT", card, "RIGHT", -25, 0)
guildRows[i] = card
end
UpdateGuildTable = function()
local guildData, guildOrder = {}, {}
-- Wszystkie gildie z bialej listy sa widoczne zawsze; nieaktywne (nikt z addonem online) sa wyszarzone
for gName in pairs(AllowedGuilds) do guildData[gName] = Roster.GetGuildSummary(gName) table.insert(guildOrder, gName) end
table.sort(guildOrder, function(a, b)
if guildData[a].live ~= guildData[b].live then return guildData[a].live end
return a < b
end)
local visible = GuildContainer.visibleRows or 8
_G.FauxScrollFrame_Update(guildScrollFrame, #guildOrder, visible, GUILD_ROW_HEIGHT)
local offset = _G.FauxScrollFrame_GetOffset(guildScrollFrame)
for i = 1, MAX_GUILD_ROWS do
local idx = i + offset local card = guildRows[i]
if i <= visible and idx <= #guildOrder then
local gName = guildOrder[idx] local stats = guildData[gName]
-- Relay jest szczegolem technicznym (widac go w Ustawieniach), tu go nie pokazujemy
if stats.live then
card:SetAlpha(1)
card.nameText:SetText("|cffffffff" .. gName .. "|r")
card.activeText:SetText("|cff00ff00Online:|r " .. stats.online .. " / " .. stats.total)
card.inactiveText:SetText("|cff00ff00Active|r")
else
card:SetAlpha(0.45)
card.nameText:SetText("|cff808080" .. gName .. "|r")
card.activeText:SetText(stats.total > 0 and ("|cff808080Members:|r " .. stats.total) or "")
-- Kiedy ostatnio przyszly dane tej gildii (z cache), albo jeszcze nigdy
local ago = stats.updated and (GetServerTime() - stats.updated)
local agoText = not ago and "never synced" or (ago < 3600 and (math.floor(ago / 60) .. " min ago") or (ago < 86400 and (math.floor(ago / 3600) .. " h ago") or (math.floor(ago / 86400) .. " d ago")))
card.inactiveText:SetText("Inactive (" .. agoText .. ")")
end
card:Show()
else card:Hide() end
end
end
guildScrollFrame:SetScript("OnVerticalScroll", function(self, offset) _G.FauxScrollFrame_OnVerticalScroll(self, offset, GUILD_ROW_HEIGHT, UpdateGuildTable) end)
GuildContainer:SetScript("OnSizeChanged", function(self)
self.visibleRows = MainFrame.FitRows(self, 45, 10, GUILD_ROW_HEIGHT, MAX_GUILD_ROWS, 8)
if self:IsVisible() then UpdateGuildTable() end
end)
-- ============================================================================
-- 6. ZAKŁADKA 4: PANEL WYDARZEŃ
-- ============================================================================
local ListContainer = CreateFrame("Frame", nil, Panels[4], "BackdropTemplate")
-- Lista: stala szerokosc, wysokosc z oknem. Szczegoly: reszta szerokosci, wysokosc z oknem.
ListContainer:SetWidth(270)
ListContainer:SetPoint("TOPLEFT", Panels[4], "TOPLEFT", 0, 0)
ListContainer:SetPoint("BOTTOMLEFT", Panels[4], "BOTTOMLEFT", 0, 30)
ApplyModernStyle(ListContainer)
local DetailsContainer = CreateFrame("Frame", nil, Panels[4], "BackdropTemplate")
DetailsContainer:SetPoint("TOPLEFT", ListContainer, "TOPRIGHT", 10, -45)
DetailsContainer:SetPoint("BOTTOMRIGHT", Panels[4], "BOTTOMRIGHT", 0, 30)
ApplyModernStyle(DetailsContainer)
local LHeader = ListContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LHeader:SetPoint("TOPLEFT", ListContainer, "TOPLEFT", 12, -12)
LHeader:SetText("Upcoming Events")
local DHeader = DetailsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
DHeader:SetPoint("TOPLEFT", DetailsContainer, "TOPLEFT", 15, -15)
local DDesc = DetailsContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
DDesc:SetPoint("TOPLEFT", DetailsContainer, "TOPLEFT", 15, -45)
DDesc:SetWidth(250)
DDesc:SetJustifyH("LEFT")
-- Dlugi opis jest ucinany, zeby nie spychal listy zapisow; pelny tekst w podpowiedzi po najechaniu
if DDesc.SetMaxLines then DDesc:SetMaxLines(7) end
do
local DescHover = CreateFrame("Frame", nil, DetailsContainer)
DescHover:SetAllPoints(DDesc)
DescHover:EnableMouse(true)
DescHover:SetScript("OnEnter", function(self)
local ev = selectedEventIndex and eventsList[selectedEventIndex]
if not ev or not ev.desc or ev.desc == "" then return end
_G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
_G.GameTooltip:AddLine(ev.title, 1, 0.82, 0)
_G.GameTooltip:AddLine(ev.desc, 1, 1, 1, true)
_G.GameTooltip:Show()
end)
DescHover:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
end
DDesc:SetText("Select an event from the list on the left.")
local CounterFrame = CreateFrame("Frame", nil, DetailsContainer)
CounterFrame:SetSize(250, 45)
CounterFrame:SetPoint("TOPLEFT", DDesc, "BOTTOMLEFT", 0, -10)
local TankCountText = CreatePhysicalIconAndText(CounterFrame, "UI-LFG-RoleIcon-Tank", 5)
local HealCountText = CreatePhysicalIconAndText(CounterFrame, "UI-LFG-RoleIcon-Healer", 65)
local DpsCountText  = CreatePhysicalIconAndText(CounterFrame, "UI-LFG-RoleIcon-DPS", 125)
local TotalCountText = CounterFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
TotalCountText:SetPoint("TOPLEFT", CounterFrame, "TOPLEFT", 180, 0)
TotalCountText:SetText("Total:")
local TotalCountVal = CreateFrame("Frame", nil, CounterFrame):CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
TotalCountVal:SetPoint("LEFT", TotalCountText, "RIGHT", 4, 0)
TotalCountVal:SetText("0")
local RosterContainer = CreateFrame("Frame", nil, DetailsContainer, "BackdropTemplate")
RosterContainer:SetSize(252, 195)
RosterContainer:SetPoint("TOPLEFT", CounterFrame, "BOTTOMLEFT", 0, -5)
ApplyModernStyle(RosterContainer)
local filterButtons = {}
local function CreateRosterFilterButton(label, filterType, xOffset)
local btn = CreateFrame("Button", nil, RosterContainer)
btn:SetSize(55, 18)
btn:SetPoint("BOTTOMLEFT", RosterContainer, "TOPLEFT", xOffset, 2)
btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
btn.text:SetPoint("CENTER", btn, "CENTER", 0, 0)
btn.text:SetText(label)
filterButtons[filterType] = btn
return btn
end
local BtnAll = CreateRosterFilterButton("All", "ALL", 5)
local BtnTank = CreateRosterFilterButton("Tank", "TANK", 65)
local BtnHeal = CreateRosterFilterButton("Heal", "HEAL", 125)
local BtnDps = CreateRosterFilterButton("DPS", "DPS", 185)
local rosterScrollFrame = CreateFrame("ScrollFrame", "JagodkiRosterScrollFrame", RosterContainer, "FauxScrollFrameTemplate")
rosterScrollFrame:SetPoint("TOPLEFT", RosterContainer, "TOPLEFT", 0, -5)
rosterScrollFrame:SetPoint("BOTTOMRIGHT", RosterContainer, "BOTTOMRIGHT", -25, 5)
-- Wierszy zapisow na zapas; widac tyle, ile miesci sie w RosterContainer (visibleRows)
local ROSTER_ROW_HEIGHT, MAX_ROSTER_ROWS, rosterRows = 16, 45, {}
for i = 1, MAX_ROSTER_ROWS do
local row = CreateFrame("Frame", nil, RosterContainer)
row:SetSize(220, ROSTER_ROW_HEIGHT) row:SetPoint("TOPLEFT", RosterContainer, "TOPLEFT", 10, -5 - ((i-1) * ROSTER_ROW_HEIGHT))
row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
row.roleText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") row.roleText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
rosterRows[i] = row
end
UpdateRosterList = function()
if not selectedEventIndex or not eventsList[selectedEventIndex] then return end
local ev = eventsList[selectedEventIndex]
local displayList = {}
for name, role in pairs(ev.roster) do
if currentRosterFilter == "ALL" or role == currentRosterFilter then
table.insert(displayList, { name = name, role = role })
end
end
table.sort(displayList, function(a, b) return a.name < b.name end)
local visible = RosterContainer.visibleRows or 11
_G.FauxScrollFrame_Update(rosterScrollFrame, #displayList, visible, ROSTER_ROW_HEIGHT)
local offset = _G.FauxScrollFrame_GetOffset(rosterScrollFrame)
for i = 1, MAX_ROSTER_ROWS do
local idx = i + offset local row = rosterRows[i]
if i <= visible and idx <= #displayList then
local data = displayList[idx]
row.text:SetText(GetColoredName(data.name))
if data.role == "TANK" then row.roleText:SetText("|cff00ccff[T]|r")
elseif data.role == "HEAL" then row.roleText:SetText("|cff00ff00[H]|r")
else row.roleText:SetText("|cffff4500[D]|r") end
row:Show()
else
row:Hide()
end
end
end
rosterScrollFrame:SetScript("OnVerticalScroll", function(self, offset) _G.FauxScrollFrame_OnVerticalScroll(self, offset, ROSTER_ROW_HEIGHT, UpdateRosterList) end)
-- Wyzsze okno = dluzsza lista zapisow (przy 390 px szczegolow: 195 px, jak dotad)
DetailsContainer:SetScript("OnSizeChanged", function(self, w, h)
if not h or h <= 0 then return end
RosterContainer:SetHeight(math.max(195, h - 195))
RosterContainer.visibleRows = MainFrame.FitRows(RosterContainer, 5, 5, ROSTER_ROW_HEIGHT, MAX_ROSTER_ROWS, 11)
if self:IsVisible() then UpdateRosterList() end
end)
local eventScrollFrame = CreateFrame("ScrollFrame", "JagodkiEventScrollFrame", ListContainer, "FauxScrollFrameTemplate")
eventScrollFrame:SetPoint("TOPLEFT", ListContainer, "TOPLEFT", 0, -35)
eventScrollFrame:SetPoint("BOTTOMRIGHT", ListContainer, "BOTTOMRIGHT", -26, 10)
-- Wierszy na zapas; widac tyle, ile miesci sie w ListContainer (visibleRows)
local EV_ROW_HEIGHT, MAX_EV_ROWS, eventRows = 40, 24, {}
for i = 1, MAX_EV_ROWS do
local btn = CreateFrame("Button", nil, ListContainer, "BackdropTemplate")
btn:SetSize(240, EV_ROW_HEIGHT - 4) btn:SetPoint("TOPLEFT", ListContainer, "TOPLEFT", 8, -35 - ((i-1) * EV_ROW_HEIGHT))
btn:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
btn:SetBackdropColor(0.09, 0.09, 0.12, 0.6) btn:SetBackdropBorderColor(0.15, 0.15, 0.2, 0.6)
btn.title = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") btn.title:SetPoint("TOPLEFT", btn, "TOPLEFT", 8, -4)
btn.time = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") btn.time:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 8, 4)
btn.count = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") btn.count:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
btn:SetScript("OnClick", function() selectedEventIndex = btn.dataIndex UpdateEventDetails() end)
eventRows[i] = btn
end
local JoinTankBtn = CreateFrame("Button", nil, DetailsContainer, "GameMenuButtonTemplate")
JoinTankBtn:SetSize(60, 24) JoinTankBtn:SetPoint("BOTTOMLEFT", DetailsContainer, "BOTTOMLEFT", 10, 15) JoinTankBtn:SetText("Tank") JoinTankBtn:Hide()
local JoinHealBtn = CreateFrame("Button", nil, DetailsContainer, "GameMenuButtonTemplate")
JoinHealBtn:SetSize(60, 24) JoinHealBtn:SetPoint("LEFT", JoinTankBtn, "RIGHT", 4, 0) JoinHealBtn:SetText("Heal") JoinHealBtn:Hide()
local JoinDpsBtn = CreateFrame("Button", nil, DetailsContainer, "GameMenuButtonTemplate")
JoinDpsBtn:SetSize(60, 24) JoinDpsBtn:SetPoint("LEFT", JoinHealBtn, "RIGHT", 4, 0) JoinDpsBtn:SetText("DPS") JoinDpsBtn:Hide()
local RemoveEventBtn = CreateFrame("Button", nil, DetailsContainer, "GameMenuButtonTemplate")
RemoveEventBtn:SetSize(70, 24) RemoveEventBtn:SetPoint("LEFT", JoinDpsBtn, "RIGHT", 6, 0) RemoveEventBtn:SetText("|cffff0000Remove|r") RemoveEventBtn:Hide()
local function UpdateFilterVisuals()
for fType, btn in pairs(filterButtons) do
if fType == currentRosterFilter then btn.text:SetTextColor(1, 0.82, 0) else btn.text:SetTextColor(0.6, 0.6, 0.6) end
end
if UpdateRosterList then UpdateRosterList() end
end
UpdateEventDetails = function()
if not selectedEventIndex or not eventsList[selectedEventIndex] then
DHeader:SetText("Details") DDesc:SetText("Select an event from the list on the left.")
CounterFrame:Hide() RosterContainer:Hide() JoinTankBtn:Hide() JoinHealBtn:Hide() JoinDpsBtn:Hide() RemoveEventBtn:Hide() return
end
local ev = eventsList[selectedEventIndex] DHeader:SetText(ev.title)
local guildStr = ev.guild and (" |cffbf40ff(" .. ev.guild .. ")|r") or ""
local dungeonStr = (ev.dungeon and ev.dungeon ~= "") and ("\n|cffffffffInstance:|r |cffffd100" .. ev.dungeon .. "|r") or ""
DDesc:SetText("|cffffffffAuthor:|r " .. ev.creator .. guildStr .. "  |cffffffffTime:|r " .. ev.date .. " " .. ev.time .. dungeonStr .. "\n|cffdecda5Description:|r " .. (ev.desc or ""))
local t, h, d, total = 0, 0, 0, 0
for _, role in pairs(ev.roster) do total = total + 1 if role == "TANK" then t = t + 1 elseif role == "HEAL" then h = h + 1 else d = d + 1 end end
TankCountText:SetText(t) HealCountText:SetText(h) DpsCountText:SetText(d) TotalCountVal:SetText("|cffffd100" .. total .. "|r")
CounterFrame:Show() RosterContainer:Show() UpdateFilterVisuals() JoinTankBtn:Show() JoinHealBtn:Show() JoinDpsBtn:Show()
if CanRemoveEvent(ev, UnitName("player"), GetGuildInfo("player"), IsPlayerOfficer()) then RemoveEventBtn:Show() else RemoveEventBtn:Hide() end
end
UpdateEventsList = function()
local visible = ListContainer.visibleRows or 10
_G.FauxScrollFrame_Update(eventScrollFrame, #eventsList, visible, EV_ROW_HEIGHT)
local offset = _G.FauxScrollFrame_GetOffset(eventScrollFrame)
for i = 1, MAX_EV_ROWS do
local idx = i + offset local row = eventRows[i]
if i <= visible and idx <= #eventsList then
local ev = eventsList[idx]
row.dataIndex = idx
row.title:SetText("|cffffffff" .. ev.title .. "|r")
row.time:SetText(ev.date .. " at " .. ev.time .. (ev.guild and ("  |cffbf40ff" .. ev.guild .. "|r") or ""))
local totalSigned = 0
for _ in pairs(ev.roster) do totalSigned = totalSigned + 1 end
row.count:SetText(totalSigned .. " signed")
row:Show()
else row:Hide() end
end
-- Kalendarz pokazuje te same wydarzenia (odswiezy sie tylko, gdy jest widoczny)
UpdateCalendar()
end
eventScrollFrame:SetScript("OnVerticalScroll", function(self, offset) _G.FauxScrollFrame_OnVerticalScroll(self, offset, EV_ROW_HEIGHT, UpdateEventsList) end)
ListContainer:SetScript("OnSizeChanged", function(self)
self.visibleRows = MainFrame.FitRows(self, 35, 10, EV_ROW_HEIGHT, MAX_EV_ROWS, 10)
if self:IsVisible() then UpdateEventsList() end
end)
local CreateEventBtn = CreateFrame("Button", nil, Panels[4], "GameMenuButtonTemplate")
CreateEventBtn:SetSize(140, 28) CreateEventBtn:SetPoint("TOPRIGHT", Panels[4], "TOPRIGHT", 0, -5) CreateEventBtn:SetText("Create Event")
local CreatorFrame = CreateFrame("Frame", "JagodkiCreatorFrame", UIParent, "BackdropTemplate")
CreatorFrame:SetSize(320, 450) CreatorFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0) CreatorFrame:Hide()
CreatorFrame:SetFrameLevel(MainFrame:GetFrameLevel() + 20)
ApplyModernStyle(CreatorFrame) CreatorFrame:SetBackdropColor(0.05, 0.05, 0.07, 0.98)
CreatorFrame.TitleText = CreatorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
CreatorFrame.TitleText:SetPoint("TOP", CreatorFrame, "TOP", 0, -10) CreatorFrame.TitleText:SetText("New Event")
local TitleInput = CreateLabelAndInput(CreatorFrame, "Event Name:", -45, 275, 26)
-- DATA I GODZINA Z LIST ROZWIJANYCH (zamiast wpisywania, wiec format jest zawsze poprawny)
-- Wybrane wartosci trzymamy w jednej tabeli, zeby nie zuzywac limitu zmiennych lokalnych pliku
local EventPicker = { date = nil, hour = 20, minute = 0, dungeon = nil }
do
local WEEKDAYS = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
local DAYS_AHEAD = 21
local function NewLabel(text, x, y)
local lbl = CreatorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
lbl:SetPoint("TOPLEFT", CreatorFrame, "TOPLEFT", x, y) lbl:SetText(text)
return lbl
end
local function NewDropDown(name, x, y, width)
local dd = CreateFrame("Frame", name, CreatorFrame, "UIDropDownMenuTemplate")
dd:SetPoint("TOPLEFT", CreatorFrame, "TOPLEFT", x, y)
_G.UIDropDownMenu_SetWidth(dd, width)
return dd
end
NewLabel("Instance:", 20, -95)
NewLabel("Date:", 20, -145)
NewLabel("Time:", 165, -145)
local function DayLabel(t) return WEEKDAYS[tonumber(date("%w", t)) + 1] .. " " .. date("%d.%m", t) end
local DungeonDD = NewDropDown("JagodkiEventDungeonDropDown", 2, -108, 255)
local DateDD = NewDropDown("JagodkiEventDateDropDown", 2, -158, 110)
local HourDD = NewDropDown("JagodkiEventHourDropDown", 147, -158, 40)
local MinuteDD = NewDropDown("JagodkiEventMinuteDropDown", 222, -158, 40)
-- Instancja: "(brak)" + grupy Dungeony / Rajdy z instancje.lua
_G.UIDropDownMenu_Initialize(DungeonDD, function(self, level)
local none = _G.UIDropDownMenu_CreateInfo()
none.text = "(none / other)"
none.checked = (EventPicker.dungeon == nil)
none.func = function() EventPicker.dungeon = nil _G.UIDropDownMenu_SetText(DungeonDD, "(none / other)") end
_G.UIDropDownMenu_AddButton(none, level)
for _, group in ipairs(addonTable.Instances or {}) do
local header = _G.UIDropDownMenu_CreateInfo()
header.text = group.group header.isTitle = true header.notCheckable = true
_G.UIDropDownMenu_AddButton(header, level)
for _, inst in ipairs(group.list) do
local info = _G.UIDropDownMenu_CreateInfo()
info.text = inst.name .. " |cff808080(" .. inst.levels .. ")|r"
info.checked = (EventPicker.dungeon == inst.name)
info.func = function() EventPicker.dungeon = inst.name _G.UIDropDownMenu_SetText(DungeonDD, inst.name) end
_G.UIDropDownMenu_AddButton(info, level)
end
end
end)
-- Data: dzisiaj + kolejne 3 tygodnie, z dniem tygodnia
_G.UIDropDownMenu_Initialize(DateDD, function(self, level)
local now = time()
for i = 0, DAYS_AHEAD - 1 do
local t = now + i * 86400
local value, label = date("%d.%m.%Y", t), DayLabel(t)
local info = _G.UIDropDownMenu_CreateInfo()
info.text = label
info.checked = (EventPicker.date == value)
info.func = function() EventPicker.date = value _G.UIDropDownMenu_SetText(DateDD, label) end
_G.UIDropDownMenu_AddButton(info, level)
end
end)
_G.UIDropDownMenu_Initialize(HourDD, function(self, level)
for h = 0, 23 do
local info = _G.UIDropDownMenu_CreateInfo()
info.text = string.format("%02d", h)
info.checked = (EventPicker.hour == h)
info.func = function() EventPicker.hour = h _G.UIDropDownMenu_SetText(HourDD, string.format("%02d", h)) end
_G.UIDropDownMenu_AddButton(info, level)
end
end)
_G.UIDropDownMenu_Initialize(MinuteDD, function(self, level)
for _, m in ipairs({0, 15, 30, 45}) do
local info = _G.UIDropDownMenu_CreateInfo()
info.text = string.format("%02d", m)
info.checked = (EventPicker.minute == m)
info.func = function() EventPicker.minute = m _G.UIDropDownMenu_SetText(MinuteDD, string.format("%02d", m)) end
_G.UIDropDownMenu_AddButton(info, level)
end
end)
-- Domyslnie: dzisiaj o 20:00 (ustawiane przy kazdym otwarciu okna).
-- EventPicker.presetDay (czas dnia, np. z klikniecia w kalendarzu) = ten dzien zamiast dzisiaj, jednorazowo.
function EventPicker.Reset()
local day = EventPicker.presetDay or time()
EventPicker.presetDay = nil
EventPicker.date, EventPicker.hour, EventPicker.minute, EventPicker.dungeon = date("%d.%m.%Y", day), 20, 0, nil
_G.UIDropDownMenu_SetText(DungeonDD, "(none / other)")
_G.UIDropDownMenu_SetText(DateDD, DayLabel(day))
_G.UIDropDownMenu_SetText(HourDD, "20")
_G.UIDropDownMenu_SetText(MinuteDD, "00")
end
end
-- Przycisk X i zamykanie klawiszem Esc
local CreatorCloseBtn = CreateFrame("Button", nil, CreatorFrame, "UIPanelCloseButton")
CreatorCloseBtn:SetPoint("TOPRIGHT", CreatorFrame, "TOPRIGHT", -2, -2)
table.insert(_G.UISpecialFrames, "JagodkiCreatorFrame")
CreatorFrame:SetScript("OnShow", function() EventPicker.Reset() end)
-- Otwarcie okna tworzenia z gotowa data (kalendarz); okno juz otwarte = tylko zmiana daty
function EventPicker.OpenFor(dayTime)
EventPicker.presetDay = dayTime
if CreatorFrame:IsShown() then EventPicker.Reset() else CreatorFrame:Show() end
end
-- OPIS: pole wieloliniowe z przewijaniem i licznikiem bajtow
local DescInput = CreateFrame("EditBox", nil, CreatorFrame)
do
local DescLabel = CreatorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
DescLabel:SetPoint("TOPLEFT", CreatorFrame, "TOPLEFT", 20, -195) DescLabel:SetText("Description:")
local DescCounter = CreatorFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
DescCounter:SetPoint("TOPRIGHT", CreatorFrame, "TOPRIGHT", -20, -197)
local DescBox = CreateFrame("Frame", nil, CreatorFrame, "BackdropTemplate")
DescBox:SetPoint("TOPLEFT", CreatorFrame, "TOPLEFT", 20, -212)
DescBox:SetPoint("BOTTOMRIGHT", CreatorFrame, "BOTTOMRIGHT", -20, 62)
ApplyModernStyle(DescBox)
local DescScroll = CreateFrame("ScrollFrame", "JagodkiEventDescScroll", DescBox, "UIPanelScrollFrameTemplate")
DescScroll:SetPoint("TOPLEFT", DescBox, "TOPLEFT", 6, -6)
DescScroll:SetPoint("BOTTOMRIGHT", DescBox, "BOTTOMRIGHT", -26, 6)
DescInput:SetParent(DescScroll)
DescInput:SetMultiLine(true) DescInput:SetAutoFocus(false) DescInput:SetFontObject(ChatFontNormal)
DescInput:SetSize(240, 140)
DescInput:SetMaxBytes(EVENT_DESC_MAX_BYTES)
DescScroll:SetScrollChild(DescInput)
DescInput:SetScript("OnEscapePressed", DescInput.ClearFocus)
-- Przewijanie za kursorem (funkcje Blizzarda z UIPanelTemplates)
if _G.ScrollingEdit_OnCursorChanged then DescInput:SetScript("OnCursorChanged", _G.ScrollingEdit_OnCursorChanged) end
if _G.ScrollingEdit_OnUpdate then DescInput:SetScript("OnUpdate", function(self, elapsed) _G.ScrollingEdit_OnUpdate(self, elapsed, DescScroll) end) end
DescInput:SetScript("OnTextChanged", function(self) DescCounter:SetText(#self:GetText() .. "/" .. EVENT_DESC_MAX_BYTES) end)
DescCounter:SetText("0/" .. EVENT_DESC_MAX_BYTES)
-- Klikniecie w dowolne miejsce ramki ustawia kursor w opisie
DescBox:EnableMouse(true) DescBox:SetScript("OnMouseDown", function() DescInput:SetFocus() end)
end
-- Limit nazwy, zeby naglowek EV_ADD zostawil miejsce na poczatek opisu
TitleInput:SetMaxBytes(50)
local SubmitBtn = CreateFrame("Button", nil, CreatorFrame, "GameMenuButtonTemplate")
SubmitBtn:SetSize(120, 30) SubmitBtn:SetPoint("BOTTOM", CreatorFrame, "BOTTOM", 0, 20) SubmitBtn:SetText("Create and Send")
CreateEventBtn:SetScript("OnClick", function() if IsPlayerOfficer() then CreatorFrame:Show() else UIErrorsFrame:AddMessage("Error: Officer rank required!", 1.0, 0.1, 0.1, 1.0, 2) end end)
SubmitBtn:SetScript("OnClick", function()
local title, desc = TitleInput:GetText(), DescInput:GetText()
local eDate, eTime = EventPicker.date or "", string.format("%02d:%02d", EventPicker.hour, EventPicker.minute)
local myName, myGuild = UnitName("player"), GetGuildInfo("player")
if not IsPlayerGuildAllowed(myGuild) or not IsPlayerOfficer() then ShowEventError("Officer rank required!") return end
-- Bez nazwy, ale z wybrana instancja: nazwa = instancja
if title == "" and EventPicker.dungeon then title = EventPicker.dungeon end
if title == "" then ShowEventError("Enter an event name or pick an instance.") return end
if not IsValidEventDate(eDate) then ShowEventError("Date format: DD.MM or DD.MM.YYYY") return end
if not IsValidEventTime(eTime) then ShowEventError("Time format: HH:MM") return end
if CountEventsBy(myName) >= MAX_EVENTS_PER_CREATOR then ShowEventError("You already have " .. MAX_EVENTS_PER_CREATOR .. " events - remove old ones.") return end
local eventID = myName .. "_" .. GetTime()
local newEvent = { id = eventID, title = title, date = eDate, time = eTime, desc = desc, dungeon = EventPicker.dungeon, creator = myName, guild = myGuild, roster = {} }
table.insert(eventsList, newEvent) UpdateEventsList()
SendEvent(newEvent)
-- Ogloszenie na glownym czacie (General -> kanal globalny i /g wszystkich gildii):
-- "Event created by Nick -> Nazwa : Instancja 05.11 20:00"
local where = newEvent.dungeon and (newEvent.dungeon .. " ") or ""
Most.Publish("Ogolny", "Event created by " .. myName .. " -> " .. title .. " : " .. where .. eDate .. " " .. eTime, "A", myName, myGuild)
TitleInput:SetText("") DescInput:SetText("") CreatorFrame:Hide()
end)
local function SetRosterFilter(filterType) currentRosterFilter = filterType UpdateFilterVisuals() end
BtnAll:SetScript("OnClick", function() SetRosterFilter("ALL") end)
BtnTank:SetScript("OnClick", function() SetRosterFilter("TANK") end)
BtnHeal:SetScript("OnClick", function() SetRosterFilter("HEAL") end)
BtnDps:SetScript("OnClick", function() SetRosterFilter("DPS") end)
local function SignUpForEvent(role)
local ev = selectedEventIndex and eventsList[selectedEventIndex]
if not ev or not VALID_ROLES[role] then return end
if not IsPlayerGuildAllowed(GetGuildInfo("player")) then ShowEventError("Your guild is not on the Community list!") return end
ev.roster[UnitName("player")] = role
UpdateEventDetails() UpdateEventsList()
SendJagodkaNetworkPacket("EV_SIGN", ev.id .. ":" .. role)
end
JoinTankBtn:SetScript("OnClick", function() SignUpForEvent("TANK") end)
JoinHealBtn:SetScript("OnClick", function() SignUpForEvent("HEAL") end)
JoinDpsBtn:SetScript("OnClick", function() SignUpForEvent("DPS") end)
RemoveEventBtn:SetScript("OnClick", function()
if not selectedEventIndex or not eventsList[selectedEventIndex] then return end
if not CanRemoveEvent(eventsList[selectedEventIndex], UnitName("player"), GetGuildInfo("player"), IsPlayerOfficer()) then ShowEventError("You can only remove your own events (officers: any).") return end
local removedEv = eventsList[selectedEventIndex]
SendJagodkaNetworkPacket("EV_REM", removedEv.id)
EventSync.MarkRemoved(removedEv.id)
-- Ogloszenie jak przy tworzeniu: "Event removed by Nick -> Nazwa : Instancja 05.11 20:00"
local myName = UnitName("player")
Most.Publish("Ogolny", "Event removed by " .. myName .. " -> " .. removedEv.title .. " : " .. (removedEv.dungeon and (removedEv.dungeon .. " ") or "") .. removedEv.date .. " " .. removedEv.time, "A", myName, (GetGuildInfo("player")))
table.remove(eventsList, selectedEventIndex) selectedEventIndex = nil UpdateEventDetails() UpdateEventsList()
end)
-- ============================================================================
-- 6B. ZAKŁADKA 5: USTAWIENIA
-- ============================================================================
local SettingsInfo = Panels[6]:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
SettingsInfo:SetPoint("TOPLEFT", Panels[6], "TOPLEFT", 10, -10)
SettingsInfo:SetText("Bridge status (global channel <-> /g) - version " .. ADDON_VERSION)
local SettingsStatus = Panels[6]:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
SettingsStatus:SetPoint("TOPLEFT", SettingsInfo, "BOTTOMLEFT", 0, -12)
SettingsStatus:SetJustifyH("LEFT")
-- Szerokosc panelu: dlugie linie diagnostyki zawijaja sie zamiast wychodzic poza okno
SettingsStatus:SetPoint("RIGHT", Panels[6], "RIGHT", -10, 0)
-- Odswiezanie statusu co sekunde, tylko gdy zakladka jest widoczna
C_Timer.NewTicker(1, function() if Panels[6]:IsVisible() then SettingsStatus:SetText(Most.GetStatusText()) end end)
-- ============================================================================
-- 6C. ZAKŁADKA 5: KALENDARZ (miesiac 7x6, poniedzialek-niedziela, wydarzenia z zakladki Events)
-- ============================================================================
-- Osobna funkcja (nie blok do-end): jej zmienne lokalne nie licza sie do limitu 200 glownego pliku
local function BuildCalendar()
local MONTHS = {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"}
local DAYS = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}
-- Rozmiar komorek i liczba linii zaleza od rozmiaru zakladki (LayoutGrid); 80x68 i 3 linie przy 850x620
local CELL_W, CELL_H, GRID_TOP, LINES, MAX_LINES = 80, 68, -52, 3, 10
local today = date("*t")
local view = { year = today.year, month = today.month }
local function DaysIn(y, m)
if m == 2 and (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)) then return 29 end
return ({31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31})[m]
end
-- "DD.MM.YYYY" albo stare "DD.MM" (wtedy biezacy rok) -> klucz RRRRMMDD
local function EventKey(ev)
local d, m, y = (ev.date or ""):match("^(%d%d?)%.(%d%d?)%.?(%d*)$")
if not d then return nil end
return (tonumber(y) or today.year) * 10000 + tonumber(m) * 100 + tonumber(d)
end
-- Klik w wydarzenie: zakladka Events z tym wydarzeniem i jego zapisami
local function OpenEvent(ev)
for idx, e in ipairs(eventsList) do
if e == ev then selectedEventIndex = idx break end
end
ShowTab(4)
UpdateEventDetails()
end
local function ShowEventTooltip(self)
local ev = self.event
if not ev then return end
local t, h, d = 0, 0, 0
for _, role in pairs(ev.roster or {}) do if role == "TANK" then t = t + 1 elseif role == "HEAL" then h = h + 1 else d = d + 1 end end
_G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
_G.GameTooltip:AddLine(ev.title, 1, 0.82, 0)
_G.GameTooltip:AddLine(ev.date .. " " .. ev.time, 1, 1, 1)
if ev.dungeon then _G.GameTooltip:AddLine("Instance: " .. ev.dungeon, 0.8, 0.8, 0.8) end
_G.GameTooltip:AddLine("By: " .. ev.creator .. (ev.guild and (" (" .. ev.guild .. ")") or ""), 0.75, 0.25, 1)
_G.GameTooltip:AddLine("Signed up: " .. (t + h + d) .. "  (T " .. t .. " / H " .. h .. " / D " .. d .. ")", 0, 1, 0)
if self.more then _G.GameTooltip:AddLine(self.more, 0.8, 0.8, 0.8) end
_G.GameTooltip:AddLine("Click to open the event", 0.5, 0.5, 0.5)
_G.GameTooltip:Show()
end
local Cal = Panels[5]
-- Naglowek: [<] [>] [Today]      November 2026
local PrevBtn = CreateFrame("Button", nil, Cal, "UIPanelButtonTemplate")
PrevBtn:SetSize(30, 22) PrevBtn:SetPoint("TOPLEFT", Cal, "TOPLEFT", 0, -6) PrevBtn:SetText("<")
local NextBtn = CreateFrame("Button", nil, Cal, "UIPanelButtonTemplate")
NextBtn:SetSize(30, 22) NextBtn:SetPoint("LEFT", PrevBtn, "RIGHT", 4, 0) NextBtn:SetText(">")
local TodayBtn = CreateFrame("Button", nil, Cal, "UIPanelButtonTemplate")
TodayBtn:SetSize(60, 22) TodayBtn:SetPoint("LEFT", NextBtn, "RIGHT", 8, 0) TodayBtn:SetText("Today")
local MonthText = Cal:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
MonthText:SetPoint("TOP", Cal, "TOP", 0, -9)
local dayHeaders = {}
for i, name in ipairs(DAYS) do
local dayHeader = Cal:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
dayHeader:SetText(name)
if i >= 6 then dayHeader:SetTextColor(1, 0.5, 0.5) end
dayHeaders[i] = dayHeader
end
-- 42 komorki dni, w kazdej do MAX_LINES przyciskow wydarzen (widac LINES)
-- Prawy klik w wydarzenie: menu "Invite members" = zaproszenia do grupy dla wszystkich zapisanych.
-- Pomijamy siebie, osoby juz w grupie i offline. Party ma 5 miejsc: gdy chetnych jest wiecej,
-- grupa jest zamieniana na raid (od razu albo po pierwszym przyjetym zaproszeniu), potem zaproszenia dla reszty.
local EventMenu = CreateFrame("Frame", "JagodkiCalendarEventMenu", UIParent, "UIDropDownMenuTemplate")
local menuEvent, pendingInvites = nil, nil
local function Report(text) if _G.DEFAULT_CHAT_FRAME then _G.DEFAULT_CHAT_FRAME:AddMessage("|cffbf40ff[Jagodka]|r " .. text) end end
local function InviteName(name)
local invite = (_G.C_PartyInfo and _G.C_PartyInfo.InviteUnit) or _G.InviteUnit
if invite then invite(name) end
end
local function MakeRaid()
local convert = (_G.C_PartyInfo and _G.C_PartyInfo.ConvertToRaid) or _G.ConvertToRaid
if convert then convert() end
end
local function InGroup(name) return _G.UnitInParty(name) or _G.UnitInRaid(name) end
local function IsLeader() return _G.UnitIsGroupLeader("player") or (_G.IsInRaid() and _G.UnitIsGroupAssistant("player")) end
local function SignedUpOthers(ev)
local n, me = 0, UnitName("player")
for name in pairs(ev.roster or {}) do if name ~= me then n = n + 1 end end
return n
end
local function InviteSignedUp(ev)
if _G.IsInGroup() and not IsLeader() then Report("|cffff5555Only the group leader (or a raid assistant) can invite.|r") return end
-- Kto jest online: ta sama lista co w Members (gracze z addonem + rostery gildii)
local online = {}
for _, p in ipairs(Roster.BuildList(false)) do online[p.name] = true end
local me, toInvite, already, offline = UnitName("player"), {}, 0, 0
for name in pairs(ev.roster or {}) do
if name ~= me then
if InGroup(name) then already = already + 1
elseif not online[name] then offline = offline + 1
else table.insert(toInvite, name) end
end
end
table.sort(toInvite)
local summary = "(already in group: " .. already .. ", offline: " .. offline .. ")"
if #toInvite == 0 then Report(ev.title .. ": nobody to invite " .. summary) return end
-- Wolne miejsca: raid 40, party / brak grupy 5 (lacznie ze mna)
local size = _G.IsInGroup() and _G.GetNumGroupMembers() or 1
local limit = _G.IsInRaid() and 40 or 5
local rest = {}
for _, name in ipairs(toInvite) do
if size < limit then InviteName(name) size = size + 1 else table.insert(rest, name) end
end
if #rest > 0 and not _G.IsInRaid() then
-- Reszta po zamianie na raid (GROUP_ROSTER_UPDATE ponizej); bez grupy - po pierwszym przyjetym zaproszeniu
pendingInvites = { names = rest, expires = GetTime() + 90 }
if _G.IsInGroup() and _G.UnitIsGroupLeader("player") then MakeRaid() end
Report(ev.title .. ": inviting " .. (#toInvite - #rest) .. " now, " .. #rest .. " more after converting to raid " .. summary)
else
Report(ev.title .. ": inviting " .. #toInvite .. " " .. summary)
end
end
local GroupWatcher = CreateFrame("Frame")
GroupWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
GroupWatcher:SetScript("OnEvent", function()
if not pendingInvites then return end
if GetTime() > pendingInvites.expires then pendingInvites = nil return end
if not _G.IsInGroup() or not _G.UnitIsGroupLeader("player") then return end
if not _G.IsInRaid() then MakeRaid() return end
local names = pendingInvites.names
pendingInvites = nil
local sent = 0
for _, name in ipairs(names) do
if not InGroup(name) and _G.GetNumGroupMembers() + sent < 40 then InviteName(name) sent = sent + 1 end
end
Report("Converted to raid - invited " .. sent .. " more.")
end)
_G.UIDropDownMenu_Initialize(EventMenu, function(self, level)
if not menuEvent then return end
local ev = menuEvent
local info = _G.UIDropDownMenu_CreateInfo()
info.text, info.isTitle, info.notCheckable = ev.title .. "  " .. ev.date .. " " .. ev.time, true, true
_G.UIDropDownMenu_AddButton(info, level)
local n = SignedUpOthers(ev)
info = _G.UIDropDownMenu_CreateInfo()
info.text = (n > 0) and ("Invite members (" .. n .. ")") or "Invite members (no sign-ups)"
info.disabled = (n == 0)
info.notCheckable = true
info.func = function() InviteSignedUp(ev) end
_G.UIDropDownMenu_AddButton(info, level)
info = _G.UIDropDownMenu_CreateInfo()
info.text, info.notCheckable = "Open event", true
info.func = function() OpenEvent(ev) end
_G.UIDropDownMenu_AddButton(info, level)
info = _G.UIDropDownMenu_CreateInfo()
info.text, info.notCheckable = "Cancel", true
info.func = function() _G.CloseDropDownMenus() end
_G.UIDropDownMenu_AddButton(info, level)
end, "MENU")
local cells = {}
-- Klik w wolne miejsce dnia (nie w wydarzenie): menu "Create event" z gotowa data.
-- Tylko oficer (jak przycisk Create Event) i tylko dzisiaj / przyszle dni.
local DayMenu = CreateFrame("Frame", "JagodkiCalendarDayMenu", UIParent, "UIDropDownMenuTemplate")
local menuCell = nil
_G.UIDropDownMenu_Initialize(DayMenu, function(self, level)
if not menuCell then return end
local info = _G.UIDropDownMenu_CreateInfo()
info.text, info.isTitle, info.notCheckable = date("%A %d.%m.%Y", menuCell.dayTime), true, true
_G.UIDropDownMenu_AddButton(info, level)
local canCreate = IsPlayerOfficer() and not menuCell.isPast
info = _G.UIDropDownMenu_CreateInfo()
info.text = canCreate and "Create event" or (menuCell.isPast and "Create event (past day)" or "Create event (officers only)")
info.disabled = not canCreate
info.notCheckable = true
local dayTime = menuCell.dayTime
info.func = function() EventPicker.OpenFor(dayTime) end
_G.UIDropDownMenu_AddButton(info, level)
info = _G.UIDropDownMenu_CreateInfo()
info.text, info.notCheckable = "Cancel", true
info.func = function() _G.CloseDropDownMenus() end
_G.UIDropDownMenu_AddButton(info, level)
end, "MENU")
for k = 1, 42 do
local cell = CreateFrame("Frame", nil, Cal, "BackdropTemplate")
cell:EnableMouse(true)
cell:SetScript("OnMouseUp", function(self)
if not self.dayTime then return end
menuCell = self
_G.ToggleDropDownMenu(1, nil, DayMenu, "cursor", 0, 0)
end)
cell:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
cell.dayText = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
cell.dayText:SetPoint("TOPLEFT", cell, "TOPLEFT", 4, -3)
cell.lines = {}
for l = 1, MAX_LINES do
local b = CreateFrame("Button", nil, cell)
b:SetHeight(14)
b:SetPoint("TOPLEFT", cell, "TOPLEFT", 2, -2 - l * 15)
b:SetPoint("RIGHT", cell, "RIGHT", -2, 0)
b.bg = b:CreateTexture(nil, "BACKGROUND") b.bg:SetAllPoints()
b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
b.text:SetPoint("LEFT", b, "LEFT", 2, 0) b.text:SetPoint("RIGHT", b, "RIGHT", -2, 0) b.text:SetJustifyH("LEFT") b.text:SetWordWrap(false)
b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
-- Lewy = otworz wydarzenie, prawy = menu (Invite members / Open event)
b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
b:SetScript("OnClick", function(self, button)
if not self.event then return end
if button == "RightButton" then
menuEvent = self.event
_G.ToggleDropDownMenu(1, nil, EventMenu, "cursor", 0, 0)
else
OpenEvent(self.event)
end
end)
b:SetScript("OnEnter", ShowEventTooltip)
b:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
cell.lines[l] = b
end
cells[k] = cell
end
-- Ulozenie siatki wg rozmiaru zakladki: szersze okno = szersze komorki (dluzsze nazwy), wyzsze = wiecej linii
local function LayoutGrid(w, h)
if not w or w <= 0 or not h or h <= 0 then w, h = 7 * 80, 52 + 6 * 68 end
CELL_W, CELL_H = math.floor(w / 7), math.floor((h + GRID_TOP) / 6)
LINES = math.max(1, math.min(MAX_LINES, math.floor((CELL_H - 20) / 15)))
for i, dayHeader in ipairs(dayHeaders) do
dayHeader:ClearAllPoints()
dayHeader:SetPoint("TOP", Cal, "TOPLEFT", (i - 1) * CELL_W + CELL_W / 2, -36)
end
for k, cell in ipairs(cells) do
cell:SetSize(CELL_W - 2, CELL_H - 2)
cell:ClearAllPoints()
cell:SetPoint("TOPLEFT", Cal, "TOPLEFT", ((k - 1) % 7) * CELL_W, GRID_TOP - math.floor((k - 1) / 7) * CELL_H)
end
end
LayoutGrid()
Cal:SetScript("OnSizeChanged", function(self, w, h) LayoutGrid(w, h) UpdateCalendar() end)
UpdateCalendar = function()
if not Cal:IsVisible() then return end
today = date("*t")
local y, m = view.year, view.month
MonthText:SetText(MONTHS[m] .. " " .. y)
-- Wydarzenia pogrupowane po dniu, w dniu po godzinie
local byDay = {}
for _, ev in ipairs(eventsList) do
local key = EventKey(ev)
if key then byDay[key] = byDay[key] or {} table.insert(byDay[key], ev) end
end
for _, list in pairs(byDay) do table.sort(list, function(a, b) return (a.time or "") < (b.time or "") end) end
-- Kolumna 1-go dnia miesiaca (wday: 1 = niedziela -> 7, 2 = poniedzialek -> 1)
local first = (date("*t", time({ year = y, month = m, day = 1, hour = 12 })).wday + 5) % 7
local prevY, prevM = (m == 1) and (y - 1) or y, (m == 1) and 12 or (m - 1)
local nextY, nextM = (m == 12) and (y + 1) or y, (m == 12) and 1 or (m + 1)
local todayKey = today.year * 10000 + today.month * 100 + today.day
local myName = UnitName("player")
for k, cell in ipairs(cells) do
local d, cy, cm, inMonth = k - first, y, m, true
if d < 1 then cy, cm, d, inMonth = prevY, prevM, DaysIn(prevY, prevM) + d, false
elseif d > DaysIn(y, m) then cy, cm, d, inMonth = nextY, nextM, d - DaysIn(y, m), false end
local key = cy * 10000 + cm * 100 + d
-- Dla menu "Create event": dzien tej komorki i czy juz minal
cell.dayTime = time({ year = cy, month = cm, day = d, hour = 12 })
cell.isPast = key < todayKey
cell.dayText:SetText(d)
cell:SetAlpha(inMonth and 1 or 0.35)
-- Dzisiaj: zlota ramka; przeszle dni ciemniejsze
if key == todayKey then
cell:SetBackdropColor(0.2, 0.17, 0.05, 0.9) cell:SetBackdropBorderColor(1, 0.82, 0, 1)
elseif key < todayKey then
cell:SetBackdropColor(0.05, 0.05, 0.07, 0.8) cell:SetBackdropBorderColor(0.12, 0.12, 0.15, 0.8)
else
cell:SetBackdropColor(0.09, 0.09, 0.12, 0.8) cell:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.6)
end
local list = byDay[key] or {}
for l, b in ipairs(cell.lines) do
local ev = (l <= LINES) and list[l]
if ev then
b.event = ev
-- Wiecej wydarzen niz linii: ostatnia linia = "+N more" (tooltip i klik = to wydarzenie)
local hidden = (l == LINES) and (#list - LINES) or 0
b.more = hidden > 0 and ("+" .. hidden .. " more on this day") or nil
local signed = ev.roster and ev.roster[myName]
b.text:SetText(hidden > 0 and ("|cffffd100+" .. (hidden + 1) .. " more|r") or ((signed and "|cff00ff00" or "|cffffffff") .. ev.time .. " " .. ev.title .. "|r"))
b.bg:SetColorTexture(0.55, 0.25, 0.8, signed and 0.55 or 0.3)
b:Show()
else
b.event = nil b:Hide()
end
end
end
end
PrevBtn:SetScript("OnClick", function() view.month = view.month - 1 if view.month < 1 then view.month, view.year = 12, view.year - 1 end UpdateCalendar() end)
NextBtn:SetScript("OnClick", function() view.month = view.month + 1 if view.month > 12 then view.month, view.year = 1, view.year + 1 end UpdateCalendar() end)
TodayBtn:SetScript("OnClick", function() local t = date("*t") view.year, view.month = t.year, t.month UpdateCalendar() end)
end
BuildCalendar()
-- ============================================================================
-- 7. PANEL BOCZNY (WIDOCZNY ZAWSZE - PRAWA STRONA)
-- ============================================================================
local RightPanel = CreateFrame("Frame", nil, MainFrame, "BackdropTemplate")
-- Stala szerokosc, wysokosc z oknem (wiecej graczy widocznych naraz)
RightPanel:SetWidth(230)
RightPanel:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -20, -135)
RightPanel:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", -20, 20)
ApplyModernStyle(RightPanel)
local HeaderText = RightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
HeaderText:SetPoint("TOPLEFT", RightPanel, "TOPLEFT", 12, 18)
local scrollFrame = CreateFrame("ScrollFrame", "JagodkiRightListScrollFrame", RightPanel, "FauxScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", RightPanel, "TOPLEFT", 0, -5)
scrollFrame:SetPoint("BOTTOMRIGHT", RightPanel, "BOTTOMRIGHT", -26, 5)
-- Wierszy na zapas; widac tyle, ile miesci sie w panelu (RightPanel.visibleRows)
local ROW_HEIGHT, MAX_ROWS, rows = 26, 38, {}
for i = 1, MAX_ROWS do
local row = CreateFrame("Button", nil, RightPanel)
-- Pasek gracza na cala szerokosc panelu (prawa krawedz ustawiana w RenderScrollList: z suwakiem / bez)
row:SetHeight(ROW_HEIGHT) row:SetPoint("TOPLEFT", RightPanel, "TOPLEFT", 4, -5 - ((i-1) * ROW_HEIGHT))
local rowTex = row:CreateTexture(nil, "BACKGROUND") rowTex:SetAllPoints() rowTex:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.06)
row.classIcon = row:CreateTexture(nil, "ARTWORK") row.classIcon:SetSize(18, 18) row.classIcon:SetPoint("LEFT", row, "LEFT", 6, 0)
-- Poziom wyrownany do prawej krawedzi; nick (z gildia) zajmuje reszte i jest ucinany przed poziomem
row.levelText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") row.levelText:SetPoint("RIGHT", row, "RIGHT", -8, 0) row.levelText:SetJustifyH("RIGHT")
row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") row.nameText:SetPoint("LEFT", row.classIcon, "RIGHT", 6, 0)
row.nameText:SetPoint("RIGHT", row.levelText, "LEFT", -6, 0) row.nameText:SetJustifyH("LEFT") row.nameText:SetWordWrap(false)
rows[i] = row
end
-- Ta sama lista co w zakladce Czlonkowie (Roster.BuildList), tylko gracze online - z addonem i bez
local onlineList, onlineListPending = {}, false
local function RenderScrollList()
HeaderText:SetText("Online players (" .. #onlineList .. ")")
-- Licznik w naglowku okna = ta sama lista (wszyscy online ze wszystkich gildii z listy)
OnlineText:SetText("Online: |cff00ff00" .. #onlineList .. "|r")
local visible = RightPanel.visibleRows or 17
_G.FauxScrollFrame_Update(scrollFrame, #onlineList, visible, ROW_HEIGHT)
local offset = _G.FauxScrollFrame_GetOffset(scrollFrame)
-- Suwak widoczny tylko przy dluzszej liscie: wtedy paski koncza sie przed nim, inaczej przy krawedzi
local scrollBar = _G[scrollFrame:GetName() .. "ScrollBar"]
local rightInset = (#onlineList > visible and scrollBar and scrollBar:IsShown()) and -28 or -4
for i = 1, MAX_ROWS do
local idx = i + offset local row = rows[i]
row:SetPoint("RIGHT", RightPanel, "RIGHT", rightInset, 0)
if i <= visible and idx <= #onlineList then
local data = onlineList[idx] local displayName = data.name
row.member = data
if data.class and RAID_CLASS_COLORS[data.class] then displayName = RAID_CLASS_COLORS[data.class]:WrapTextInColorCode(data.name) end
if data.guild and data.guild ~= "" and data.guild ~= "Brak" then displayName = displayName .. " |cffbf40ff(" .. data.guild .. ")|r" end
row.nameText:SetText(displayName) row.levelText:SetText(data.level)
if data.class and CLASS_ICON_TCOORDS[data.class] then
row.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
row.classIcon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[data.class])) row.classIcon:Show()
else row.classIcon:Hide() end
row:Show()
else row:Hide() end
end
end
-- Jak w tabeli: przeliczenie tylko przy otwartym oknie, najwyzej raz na 0.3 s
UpdateScrollList = function()
if onlineListPending or not RightPanel:IsVisible() then return end
onlineListPending = true
C_Timer.After(0.3, function()
onlineListPending = false
if not RightPanel:IsVisible() then return end
onlineList = Roster.BuildList(false)
RenderScrollList()
end)
end
-- Te same klikniecia co w tabeli Czlonkowie (prawy = menu, Shift + lewy = szept)
for _, row in ipairs(rows) do
row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
row:SetScript("OnClick", membersView.OnRowClick)
end
scrollFrame:SetScript("OnVerticalScroll", function(self, offset) _G.FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, RenderScrollList) end)
RightPanel:SetScript("OnSizeChanged", function(self)
self.visibleRows = MainFrame.FitRows(self, 5, 5, ROW_HEIGHT, MAX_ROWS, 17)
if self:IsVisible() then RenderScrollList() end
end)
-- ============================================================================
-- 8. ODBIORNIK SIECIOWY (STABILNE KANAŁY + BIAŁA LISTA)
-- ============================================================================
local NetworkListener = CreateFrame("Frame")
NetworkListener:RegisterEvent("CHAT_MSG_ADDON")
NetworkListener:RegisterEvent("PLAYER_LOGIN")
NetworkListener:RegisterEvent("ADDON_LOADED")
NetworkListener:RegisterEvent("PLAYER_GUILD_UPDATE")
NetworkListener:RegisterEvent("GUILD_ROSTER_UPDATE")
-- Zaraz po zalogowaniu GetGuildInfo() czesto zwraca nil, wiec PING wysylamy dopiero gdy gildia jest znana
local announced = false
local function TryAnnounce()
if announced then return end
if not IsPlayerGuildAllowed(GetGuildInfo("player")) then return end
announced = true
AddMyselfToActiveList()
SendStatusPacket("PING")
UpdateScrollList()
end
-- Czlonkowie mojej gildii wg rostera Blizzarda: nick -> true (online) / false (offline).
-- Nikt spoza rostera nie podszyje sie pod moja gildie, a wylogowany relay jest od razu pomijany.
local myGuildRoster, myGuildRosterLoaded, spoofWarned = {}, false, {}
local function RefreshMyGuildRoster()
local n = (_G.GetNumGuildMembers and _G.GetNumGuildMembers()) or 0
if n == 0 then return end
wipe(myGuildRoster)
for i = 1, n do
local fullName, _, _, _, _, _, _, _, isOnline = _G.GetGuildRosterInfo(i)
if fullName then myGuildRoster[Ambiguate(fullName, "none")] = isOnline and true or false end
end
myGuildRosterLoaded = true
end
-- Brak w rosterze tez = offline (przy wylaczonym "pokaz offline" wylogowani znikaja z listy)
Most.SetGuildmateOnlineCheck(function(name)
if not myGuildRosterLoaded then return nil end
return myGuildRoster[name] == true
end)
-- Ostrzezenie o innej wersji addonu (raz na gracza i wersje), w czacie addonu i w zwyklym czacie
local warnedVersions = {}
local function CheckPlayerVersion(name, version)
if name == UnitName("player") or warnedVersions[name] == (version or "?") then return end
local cmp = CompareVersions(version or "0", ADDON_VERSION)
if cmp == 0 then return end
warnedVersions[name] = version or "?"
local text
if cmp < 0 then
text = name .. " has an older addon version (" .. (version or "unknown") .. ", yours: " .. ADDON_VERSION .. ") - they need to update."
else
text = name .. " has a newer addon version (" .. version .. ") - please update yours (" .. ADDON_VERSION .. ")."
end
Most.AddSystem(text)
if _G.DEFAULT_CHAT_FRAME then _G.DEFAULT_CHAT_FRAME:AddMessage("|cffbf40ff[Jagodka]|r |cffff5555" .. text .. "|r") end
end
-- Usuwa graczy, ktorzy dawno nie wyslali sygnalu (wylogowani) - lista = naprawde online
local function PruneOfflinePlayers()
local now, myName = GetTime(), UnitName("player")
local changed = false
local myGuild = GetGuildInfo("player")
for i = #activePlayers, 1, -1 do
local p = activePlayers[i]
-- Gildiowicza wylogowanego wg rostera usuwamy od razu, reszte po braku sygnalu
local offlineInRoster = p.guild == myGuild and myGuildRosterLoaded and myGuildRoster[p.name] ~= true
if p.name ~= myName and (offlineInRoster or (now - (p.lastSeen or 0)) > Most.ONLINE_TIMEOUT) then table.remove(activePlayers, i) changed = true end
end
if changed then UpdateScrollList() if MainFrame:IsShown() then UpdateMainTable() UpdateGuildTable() end end
end
-- CHAT_MSG_ADDON: prefix, text, channel, sender, target, zoneChannelID, localID (numer kanalu u nas)
NetworkListener:SetScript("OnEvent", function(self, event, prefix, text, channel, sender, _, _, localID)
if event == "ADDON_LOADED" and prefix == addonName then
_G.JagodkiEventsDB = _G.JagodkiEventsDB or {}
eventsList = _G.JagodkiEventsDB
EventSync.Prune()
return
end
if event == "PLAYER_LOGIN" then
C_ChatInfo.RegisterAddonMessagePrefix("JagodkaComm")
if _G.C_GuildInfo and _G.C_GuildInfo.GuildRoster then _G.C_GuildInfo.GuildRoster() elseif _G.GuildRoster then _G.GuildRoster() end
TryAnnounce()
-- Kanal dolaczamy z opoznieniem, zeby nie zajac numeru /1 przed kanalem General
C_Timer.After(8, function()
Most.JoinChannel()
C_Timer.After(2, function()
-- Ponowny PING juz przez kanal globalny, zeby zobaczyly nas inne gildie, potem prosba o historie
announced = false
TryAnnounce()
if announced then
Most.RequestHistory()
Mute.Request()
-- Wydarzenia i zapisy chwile pozniej, zeby nie wysylac wszystkiego naraz
C_Timer.After(5, function() EventSync.Request(true) end)
end
end)
end)
-- Sygnal "jestem online" co minute (bez odpowiedzi) + sprzatanie wylogowanych
C_Timer.NewTicker(60, function()
if announced then AddMyselfToActiveList() SendStatusPacket("PONG") end
-- Inny addon (lub rozlaczenie) mogl nas wyrzucic z kanalu globalnego - wracamy
if not Most.GetChannelId() then Most.JoinChannel() end
PruneOfflinePlayers()
end)
-- Roster gildii odswiezany co 20 s, zeby szybko wiedziec, kto sie wylogowal (np. relay)
C_Timer.NewTicker(20, function()
if not IsInGuild() then return end
if _G.C_GuildInfo and _G.C_GuildInfo.GuildRoster then _G.C_GuildInfo.GuildRoster() elseif _G.GuildRoster then _G.GuildRoster() end
end)
Most.AddSystem("Jagodka Community ready. The global channel links all listed guilds.")
UpdateChatTabVisuals()
elseif event == "PLAYER_GUILD_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
RefreshMyGuildRoster()
TryAnnounce()
PruneOfflinePlayers()
elseif event == "CHAT_MSG_ADDON" and prefix == "JagodkaComm" then
-- Z kanalow przyjmujemy tylko nasz (ten sam prefiks na obcym kanale = ktos podszywajacy sie)
if channel == "CHANNEL" and not Most.IsOurChannel(localID) then return end
local senderName = Ambiguate(sender, "none")
local myName = UnitName("player")
local pType, payload = strsplit(":", text, 2)
if not pType or not payload then return end
-- Bez kodow formatowania w danych od innych (czat: most.lua zostawia w nim poprawne linki)
if pType ~= "GMSG" and pType ~= "HIST" then payload = Most.Plain(payload) end
-- Wiadomosci czatu i historia: most.lua
if Most.HandlePacket(pType, payload, channel, senderName, sender) then return end
-- Rostery gildii: roster.lua
if Roster.HandlePacket(pType, payload, senderName) then return end
-- Wyciszenia na czacie: wyciszenie.lua
if Mute.HandlePacket(pType, payload, senderName, sender) then return end
if pType == "PING" or pType == "PONG" then
local lvl, cls, gld, rnk, ver, rIdx = strsplit(":", payload, 6)
if not IsPlayerGuildAllowed(gld) then return end
-- Ktos podaje sie za czlonka mojej gildii, a nie ma go w rosterze -> odrzucamy
if gld == GetGuildInfo("player") and senderName ~= myName and myGuildRosterLoaded and myGuildRoster[senderName] == nil then
if not spoofWarned[senderName] then
spoofWarned[senderName] = true
if _G.DEFAULT_CHAT_FRAME then _G.DEFAULT_CHAT_FRAME:AddMessage("|cffbf40ff[Jagodka]|r |cffff5555" .. senderName .. " claims to be in your guild but is not in its roster - ignored.|r") end
end
return
end
CheckPlayerVersion(senderName, ver)
local existingIndex = GetPlayerIndex(senderName)
local playerData = { name = senderName, level = lvl, class = cls, guild = gld or "Brak", rank = rnk or "Brak", rankIndex = tonumber(rIdx), version = ver, lastSeen = GetTime() }
if existingIndex then activePlayers[existingIndex] = playerData else table.insert(activePlayers, playerData) end
UpdateScrollList()
if UpdateMainTable then UpdateMainTable() end
if MainFrame:IsShown() then UpdateGuildTable() end
if pType == "PING" and senderName ~= myName then SendStatusPacket("PONG") end
else
local senderIdx = GetPlayerIndex(senderName)
if not senderIdx and senderName ~= myName then return end
-- Dane nadawcy (gildia, ranga) z jego meldunku - na ich podstawie sprawdzamy uprawnienia
local senderInfo = senderIdx and activePlayers[senderIdx]
local senderGuild = senderInfo and senderInfo.guild or GetGuildInfo("player")
local senderIsOfficer
if senderName == myName then senderIsOfficer = IsPlayerOfficer() else senderIsOfficer = senderInfo ~= nil and IsRankOfficer(senderInfo.rank, senderInfo.rankIndex) end
if pType == "EV_REQ" then
if senderName ~= myName then EventSync.HandleRequest(senderName) end
elseif pType == "EV_CLAIM" then
addonTable.Sync.Activity("events")
-- Ktos inny juz odpowiada na te prosbe
if senderName ~= myName then EventSync.pending[payload] = nil end
elseif pType == "EV_ADD" then
addonTable.Sync.Activity("events")
local evID, title, eDate, eTime, desc, creator, dungeon, parts, evGuild = strsplit(":", payload, 9)
evID, title, eDate, eTime, desc, creator, dungeon, evGuild = DecodeField(evID), DecodeField(title), DecodeField(eDate), DecodeField(eTime), DecodeField(desc) or "", DecodeField(creator) or senderName, DecodeField(dungeon), DecodeField(evGuild)
if dungeon == "" then dungeon = nil end
-- Od autora: musi byc oficerem. Przekazane dalej (synchronizacja, autor moze byc offline):
-- od znanego gracza z bialej listy. Zawsze: limit na autora, bez usunietych i przeterminowanych.
local forwarded = creator ~= senderName
local allowed = (not forwarded and senderIsOfficer) or (forwarded and senderInfo ~= nil and IsPlayerGuildAllowed(senderInfo.guild))
if evID and title and eDate and eTime and allowed and not EventSync.Removed()[evID] and not EventSync.IsExpired(eDate) and CountEventsBy(creator) < MAX_EVENTS_PER_CREATOR then
local exists = false
for _, ev in ipairs(eventsList) do if ev.id == evID then exists = true break end end
if not exists then
-- descParts: kolejne czesci opisu dochodza w pakietach EV_DESC (od tego samego nadawcy)
local total = math.min(tonumber(parts) or 1, EVENT_MAX_DESC_PARTS)
local guild = (not forwarded and senderGuild) or (IsPlayerGuildAllowed(evGuild) and evGuild) or nil
table.insert(eventsList, { id = evID, title = title, date = eDate, time = eTime, desc = desc, descParts = { desc }, descTotal = total, descFrom = senderName, dungeon = dungeon, creator = creator, guild = guild, roster = {} })
if MainFrame:IsShown() then UpdateEventsList() end
end
end
elseif pType == "EV_ROS" then
addonTable.Sync.Activity("events")
-- Zapisy z synchronizacji: dopisujemy tylko brakujace osoby (wlasny zapis kazdy wysyla sam przez EV_SIGN)
local evID, list = strsplit(":", payload, 2)
evID = DecodeField(evID)
for _, ev in ipairs(eventsList) do
if ev.id == evID then
for name, role in (list or ""):gmatch("([^,=]+)=(%u+)") do
if VALID_ROLES[role] and not ev.roster[name] then ev.roster[name] = role end
end
if selectedEventIndex and eventsList[selectedEventIndex] == ev then UpdateEventDetails() end
if MainFrame:IsShown() then UpdateEventsList() end
break
end
end
elseif pType == "EV_DESC" then
local evID, partIdx, chunk = strsplit(":", payload, 3)
evID, partIdx = DecodeField(evID), tonumber(partIdx)
for _, ev in ipairs(eventsList) do
-- Czesc opisu przyjmujemy tylko od autora i tylko dla zapowiedzianej liczby czesci
if ev.id == evID and (ev.creator == senderName or ev.descFrom == senderName) and ev.descParts and partIdx and partIdx >= 2 and partIdx <= (ev.descTotal or 1) then
ev.descParts[partIdx] = DecodeField(chunk) or ""
local full = {}
for i = 1, ev.descTotal do if ev.descParts[i] then table.insert(full, ev.descParts[i]) end end
ev.desc = table.concat(full)
if selectedEventIndex and eventsList[selectedEventIndex] == ev then UpdateEventDetails() end
break
end
end
elseif pType == "EV_SIGN" then
local evID, role = strsplit(":", payload, 2)
-- Tylko znane role; nadawca zapisuje wylacznie siebie (roster[senderName])
if not VALID_ROLES[role] then return end
for _, ev in ipairs(eventsList) do
if ev.id == evID then
ev.roster[senderName] = role
if selectedEventIndex and eventsList[selectedEventIndex].id == evID then UpdateEventDetails() end
if MainFrame:IsShown() then UpdateEventsList() end
break
end
end
elseif pType == "EV_REM" then
-- Nieznane wydarzenie usuniete przez oficera: zapamietujemy, zeby nie przyszlo pozniej z synchronizacji
local known = false
for _, ev in ipairs(eventsList) do if ev.id == payload then known = true break end end
if not known and senderIsOfficer and IsPlayerGuildAllowed(senderGuild) then EventSync.MarkRemoved(payload) end
for idx, ev in ipairs(eventsList) do
if ev.id == payload then
-- Usunac moze autor albo oficer gildii z bialej listy; inne prosby ignorujemy
if not CanRemoveEvent(ev, senderName, senderGuild, senderIsOfficer) then break end
EventSync.MarkRemoved(ev.id)
table.remove(eventsList, idx)
-- Po usunieciu indeksy sie przesuwaja, wiec poprawiamy zaznaczenie
if selectedEventIndex == idx then selectedEventIndex = nil UpdateEventDetails()
elseif selectedEventIndex and selectedEventIndex > idx then selectedEventIndex = selectedEventIndex - 1 end
if MainFrame:IsShown() then UpdateEventsList() end
break
end
end
end
end
end
end)
MainFrame:SetScript("OnShow", function()
AddMyselfToActiveList()
SendStatusPacket("PING")
UpdateScrollList()
if UpdateMainTable then UpdateMainTable() end
UpdateGuildTable()
UpdateEventsList()
end)
-- POPRAWKA: Wskazanie konkretnego, czwartego indeksu z tablicy paneli
Panels[4]:SetScript("OnShow", function()
if _G.JagodkiEventsDB then eventsList = _G.JagodkiEventsDB end
if IsPlayerOfficer() then CreateEventBtn:Enable() else CreateEventBtn:Disable() end
if UpdateEventsList then UpdateEventsList() end
EventSync.Request()
end)
-- Kalendarz korzysta z tych samych wydarzen - tez dociaga brakujace (najwyzej co 5 min)
Panels[5]:HookScript("OnShow", function() EventSync.Request() end)
ShowTab(1)
-- ============================================================================
-- 9. REJESTRACJA KOMENDY CZATU I MINIMAPY (LibDataBroker)
-- ============================================================================
-- "/okno" to popularne slowo i moze go zajac inny addon, wiec glowna komenda to /jagodka
_G.SLASH_JAGODKANADINA1 = "/jagodka"
_G.SLASH_JAGODKANADINA2 = "/okno"
-- "/jagodka reset" = domyslny rozmiar i okno na srodku ekranu
_G.SlashCmdList["JAGODKANADINA"] = function(msg)
if msg and msg:lower():match("^%s*reset%s*$") then
if _G.JagodkiMinimapDB then _G.JagodkiMinimapDB.window = nil end
MainFrame.ApplyLayout()
MainFrame:Show()
return
end
-- "/jagodka tab" = ponownie utworz zakladke "Jagodki Nadina" w czacie gry (zakladka.lua)
if msg and msg:lower():match("^%s*tab%s*$") then
if not addonTable.Zakladka.Recreate() and _G.DEFAULT_CHAT_FRAME then
_G.DEFAULT_CHAT_FRAME:AddMessage("|cffbf40ff[Jagodka]|r |cffff5555Could not create the chat tab (chat window limit reached?).|r")
end
return
end
if MainFrame:IsShown() then MainFrame:Hide() else MainFrame:Show() end
end
local JagodkiLDB = LibStub("LibDataBroker-1.1"):NewDataObject("JagodkiNadina", {
type = "data source",
text = "Jagodki Nadina",
icon = "Interface\\AddOns\\jagodka\\Media\\jagoda.tga",
OnClick = function(self, button)
if button == "LeftButton" then
if MainFrame:IsShown() then MainFrame:Hide() else MainFrame:Show() end
end
end,
OnTooltipShow = function(tooltip)
tooltip:AddLine("Jagodki Nadina")
tooltip:AddLine("|cffffd100Click to open the Community window|r")
end,
})
local icon = LibStub("LibDBIcon-1.0")
-- Rejestracja dopiero po ADDON_LOADED, bo wczesniej SavedVariables nie sa jeszcze wczytane
local MinimapLoader = CreateFrame("Frame")
MinimapLoader:RegisterEvent("ADDON_LOADED")
MinimapLoader:SetScript("OnEvent", function(self, event, loadedName)
if loadedName ~= addonName then return end
_G.JagodkiMinimapDB = _G.JagodkiMinimapDB or {}
_G.JagodkiMinimapDB.minimap = _G.JagodkiMinimapDB.minimap or { hide = false }
-- Zapisana pozycja i skala glownego okna
local win = _G.JagodkiMinimapDB.window
if win and tonumber(win.w) then MainFrame.ApplyLayout(win.w, win.h, win.left, win.top) end
icon:Register("JagodkiNadina", JagodkiLDB, _G.JagodkiMinimapDB.minimap)
self:UnregisterEvent("ADDON_LOADED")
end)
