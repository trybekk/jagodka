-- ============================================================================
-- 1. KONFIGURACJA GŁÓWNEGO OKNA I PODSTAWOWE FUNKCJE RYSOWANIA
-- ============================================================================
local MainFrame = CreateFrame("Frame", "JagodkiNadinaMainFrame", UIParent, "BackdropTemplate")
MainFrame:SetSize(850, 620)
MainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
MainFrame:Hide()

MainFrame:EnableMouse(true)
MainFrame:SetMovable(true)
MainFrame:RegisterForDrag("LeftButton")
MainFrame:SetScript("OnDragStart", MainFrame.StartMoving)
MainFrame:SetScript("OnDragStop", MainFrame.StopMovingOrSizing)

-- STYLIZACJA GŁÓWNEGO OKNA
MainFrame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Buttons\\WHITE8X8", 
    tile = true, tileSize = 16, edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
})
MainFrame:SetBackdropColor(0.05, 0.05, 0.07, 0.95) 
MainFrame:SetBackdropBorderColor(0.15, 0.15, 0.2, 1) 

-- Pasek nagłówka (Górna belka okna)
local HeaderBar = MainFrame:CreateTexture(nil, "BACKGROUND")
HeaderBar:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 1, -1)
HeaderBar:SetPoint("BOTTOMRIGHT", MainFrame, "TOPRIGHT", -1, -35)
HeaderBar:SetColorTexture(0.08, 0.08, 0.11, 1)

local TitleText = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
-- LOGO Z JAGODAMI W OKNIE GŁÓWNYM
local WindowLogo = MainFrame:CreateTexture(nil, "OVERLAY")
WindowLogo:SetSize(64, 64) 
WindowLogo:SetPoint("LEFT", HeaderBar, "LEFT", 12, 0)
WindowLogo:SetTexture("Interface\\AddOns\\jagodka\\Media\\jagoda.tga")

-- Przesunięcie tytułu tekstowego, aby nie nachodził na logo
TitleText:SetPoint("LEFT", WindowLogo, "RIGHT", 8, 0)
TitleText:SetText("|cffffffffJag\195\179dki Nadina|r |cffdecda5-|r Wsp\195\179lnota")

-- Przycisk Zamknij (X) w stylu minimalistycznym
local CloseBtn = CreateFrame("Button", nil, MainFrame, "UIPanelCloseButton")
CloseBtn:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -2, -2)
CloseBtn:SetSize(30, 30)

-- LICZNIK ONLINE 
local OnlineText = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
OnlineText:SetPoint("RIGHT", CloseBtn, "LEFT", -10, 0)
OnlineText:SetText("Online: |cff00ff000|r")

local Panels = {}
-- Zabezpieczone "ł" w słowie Członkowie
local tabNames = {"Czat", "Cz\197\130onkowie", "Gildie", "Wydarzenia", "Ustawienia"}

-- Konfiguracja kolumn tabeli graczy
local columns = {
    { name = "Nazwa", width = 110, x = 10 },
    { name = "Klasa", width = 90, x = 125 },
    { name = "Poz.", width = 40, x = 220 },
    { name = "Gildia", width = 140, x = 265 },
    { name = "Ranga", width = 130, x = 410 }
}

-- PANCERNE DEKLARACJE FUNKCJI AKTUALIZACJI
local UpdateGuildTable = function() end
local UpdateEventsList = function() end
local UpdateMainTable = function() end
local UpdateScrollList = function() end
local UpdateRosterList = function() end

-- FUNKCJE POMOCNICZE UI
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
-- 1B. FUNKCJE SIECIOWE 
-- ============================================================================
local function SendJagodkaNetworkPacket(prefixType, dataPayload)
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or (IsInGuild() and "GUILD" or nil))
    if channel then C_ChatInfo.SendAddonMessage("JagodkaComm", prefixType .. ":" .. dataPayload, channel) end
end

local function SendStatusPacket(msgType)
    local guildName, rankName = GetGuildInfo("player")
    guildName = guildName or "Brak"
    rankName = rankName or "Brak"
    SendJagodkaNetworkPacket(msgType, UnitLevel("player") .. ":" .. select(2, UnitClass("player")) .. ":" .. guildName .. ":" .. rankName)
end

-- Tworzenie ramek (Paneli) dla każdej zakładki
for i, name in ipairs(tabNames) do
    local p = CreateFrame("Frame", nil, MainFrame)
    p:SetSize(560, 465)
    p:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 20, -135)
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

-- Tworzenie przycisków nawigacyjnych menu
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
local chatHistories = {
    ["Ogolny"] = {},
    ["Raid"] = {},
    ["Handel"] = {},
    ["Szukaj grupy"] = {}
}

JagodkiEventsDB = JagodkiEventsDB or {}
local eventsList = JagodkiEventsDB
local selectedEventIndex = nil

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
    if not rank or rank == "" or rank == "Brak" then return "|cff808080Gracz|r" end
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

local function IsPlayerOfficer()
    if not IsInGuild() then return false end
    local _, rankName, rankIndex = GetGuildInfo("player")
    if not rankName then return false end
    local lowerRank = rankName:lower()
    if rankIndex == 0 or rankIndex == 1 or lowerRank:find("oficer") or lowerRank:find("officer") or lowerRank:find("master") or lowerRank:find("lider") then
        return true
    end
    return false
end

local function AddMyselfToActiveList()
    local myName = UnitName("player")
    local level = UnitLevel("player")
    local _, classFilename = UnitClass("player")
    local guildName, rankName = GetGuildInfo("player")
guildName = guildName or "Brak"
rankName = rankName or "Brak"
local existingIndex = GetPlayerIndex(myName)
local playerData = {
name = myName, level = level, class = classFilename, guild = guildName, rank = rankName, lastSeen = GetTime()
}
if existingIndex then activePlayers[existingIndex] = playerData else table.insert(activePlayers, playerData) end
end
-- ============================================================================
-- 3. ZAKŁADKA 1: PANEL CZATU
-- ============================================================================
local ChatPanel = CreateFrame("Frame", nil, Panels[1], "BackdropTemplate")
ChatPanel:SetSize(560, 435)
ChatPanel:SetPoint("TOPLEFT", Panels[1], "TOPLEFT", 0, 0)
ApplyModernStyle(ChatPanel)
local chatDisplay = CreateFrame("ScrollingMessageFrame", nil, ChatPanel)
chatDisplay:SetPoint("TOPLEFT", ChatPanel, "TOPLEFT", 12, -12)
chatDisplay:SetPoint("BOTTOMRIGHT", ChatPanel, "BOTTOMRIGHT", -12, 45)
chatDisplay:SetFontObject(ChatFontNormal)
chatDisplay:SetMaxLines(200)
chatDisplay:SetFading(false)
chatDisplay:SetJustifyH("LEFT")
local chatInput = CreateFrame("EditBox", nil, ChatPanel, "InputBoxTemplate")
chatInput:SetSize(440, 26)
chatInput:SetPoint("BOTTOMLEFT", ChatPanel, "BOTTOMLEFT", 12, 10)
chatInput:SetAutoFocus(false)
chatInput:SetFontObject(ChatFontNormal)
local sendButton = CreateFrame("Button", nil, ChatPanel, "GameMenuButtonTemplate")
sendButton:SetSize(75, 26)
sendButton:SetPoint("LEFT", chatInput, "RIGHT", 8, 0)
-- NAPRAWIONE: "ś" zakodowane systemowo jako uniwersalny kod \197\155
sendButton:SetText("Wy\197\155lij")
local chatTabs = {"Ogolny", "Raid", "Handel", "Szukaj grupy"}
local currentChatTab = "Ogolny"
local chatTabButtons = {}
local function RefreshChatDisplay()
chatDisplay:Clear()
local messages = chatHistories[currentChatTab]
if messages then for _, msg in ipairs(messages) do chatDisplay:AddMessage(msg) end end
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
-- WYSYŁANIE WIADOMOŚCI
local function OriginalSubmitMessage()
local msg = chatInput:GetText()
if msg and msg ~= "" then
SendJagodkaNetworkPacket("CHAT", currentChatTab .. ":" .. msg)
local myName = UnitName("player")
local _, rankName = GetGuildInfo("player")
local rankStr = (rankName and rankName ~= "Brak") and (GetColoredRank(rankName) .. " ") or ""
table.insert(chatHistories[currentChatTab], rankStr .. "[" .. GetColoredName(myName) .. "]: " .. msg)
RefreshChatDisplay()
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
tBtn:SetBackdrop({ edgeFile = "Interface\Buttons\WHITE8X8", edgeSize = 1 })
tBtn:SetBackdropBorderColor(0.15, 0.15, 0.2, 0.8)
tBtn.bg = tBtn:CreateTexture(nil, "BACKGROUND")
tBtn.bg:SetAllPoints()
tBtn.topLine = tBtn:CreateTexture(nil, "OVERLAY")
tBtn.topLine:SetPoint("TOPLEFT", tBtn, "TOPLEFT", 0, 0)
tBtn.topLine:SetPoint("TOPRIGHT", tBtn, "TOPRIGHT", 0, 0)
tBtn.topLine:SetHeight(2)
tBtn.text = tBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
tBtn.text:SetPoint("CENTER", tBtn, "CENTER", 0, 0)
tBtn.text:SetText(name)
tBtn:SetScript("OnClick", function() currentChatTab = name UpdateChatTabVisuals() end)
chatTabButtons[name] = tBtn
end
-- ============================================================================
-- 4. ZAKŁADKA 2: GŁÓWNA TABELA GRACZY + WYSZUKIWARKA
-- ============================================================================
local TableContainer = CreateFrame("Frame", nil, Panels[2], "BackdropTemplate")
TableContainer:SetSize(560, 420)
TableContainer:SetPoint("TOPLEFT", Panels[2], "TOPLEFT", 0, -45)
ApplyModernStyle(TableContainer)
local SearchEditBox = CreateFrame("EditBox", "JagodkiSearchEditBox", Panels[2], "InputBoxTemplate")
SearchEditBox:SetSize(220, 26)
SearchEditBox:SetPoint("TOPLEFT", Panels[2], "TOPLEFT", 65, -5)
SearchEditBox:SetAutoFocus(false)
SearchEditBox:SetFontObject(ChatFontNormal)
local SearchLabel = Panels[2]:CreateFontString(nil, "OVERLAY", "GameFontNormal")
SearchLabel:SetPoint("RIGHT", SearchEditBox, "LEFT", -8, 0)
SearchLabel:SetText("Szukaj:")
SearchEditBox.Instructions = SearchEditBox:CreateFontString(nil, "ARTWORK", "GameFontDisable")
SearchEditBox.Instructions:SetPoint("LEFT", SearchEditBox, "LEFT", 5, 0)
SearchEditBox.Instructions:SetText("Wpisz nick, klase lub gildie...")
SearchEditBox:SetScript("OnTextChanged", function(self)
if self:GetText() == "" then self.Instructions:Show() else self.Instructions:Hide() end
UpdateMainTable()
end)
for _, col in ipairs(columns) do
local h = TableContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
h:SetPoint("TOPLEFT", TableContainer, "TOPLEFT", col.x, -10)
h:SetText(col.name)
end
local mainScrollFrame = CreateFrame("ScrollFrame", "JagodkiMainTableScrollFrame", TableContainer, "FauxScrollFrameTemplate")
mainScrollFrame:SetPoint("TOPLEFT", TableContainer, "TOPLEFT", 0, -30)
mainScrollFrame:SetPoint("BOTTOMRIGHT", TableContainer, "BOTTOMRIGHT", -26, 10)
local MAIN_ROW_HEIGHT = 22
local MAX_MAIN_ROWS = 17
local tableRows = {}
for i = 1, MAX_MAIN_ROWS do
local row = CreateFrame("Button", nil, TableContainer)
row:SetSize(530, MAIN_ROW_HEIGHT)
row:SetPoint("TOPLEFT", TableContainer, "TOPLEFT", 5, -30 - ((i-1) * MAIN_ROW_HEIGHT))
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
tableRows[i] = row
end
function UpdateMainTable()
-- Dynamiczne odświeżanie licznika z czystym tekstem (bez kwadratów)
OnlineText:SetText("Online: |cff00ff00" .. #activePlayers .. "|r")
wipe(filteredPlayers)
local filterText = SearchEditBox:GetText():lower()
for _, player in ipairs(activePlayers) do
if filterText == "" then table.insert(filteredPlayers, player)
else
if player.name:lower():find(filterText, 1, true) or (player.class and player.class:lower():find(filterText, 1, true)) or (player.guild and player.guild:lower():find(filterText, 1, true)) or (player.rank and player.rank:lower():find(filterText, 1, true)) then
table.insert(filteredPlayers, player)
end
end
end
FauxScrollFrame_Update(mainScrollFrame, #filteredPlayers, MAX_MAIN_ROWS, MAIN_ROW_HEIGHT)
local offset = FauxScrollFrame_GetOffset(mainScrollFrame)
for i = 1, MAX_MAIN_ROWS do
local dataIndex = i + offset local row = tableRows[i]
if dataIndex <= #filteredPlayers then
local data = filteredPlayers[dataIndex]
local classColor = data.class and RAID_CLASS_COLORS[data.class]
row.nameText:SetText(classColor and classColor:WrapTextInColorCode(data.name) or data.name)
row.classText:SetText(classColor and classColor:WrapTextInColorCode(LOCALIZED_CLASS_NAMES_MALE[data.class] or data.class) or "Nieznana")
row.levelText:SetText(data.level) row.rankText:SetText(GetColoredRank(data.rank))
row.guildText:SetText((data.guild and data.guild ~= "Brak") and ("|cffbf40ff" .. data.guild .. "|r") or "|cff808080Brak gildii|r")
if data.class and CLASS_ICON_TCOORDS[data.class] then
row.classIcon:SetTexture("Interface\GLUES\CHARACTERCREATE\UI-CHARACTERCREATE-CLASSES")
row.classIcon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[data.class])) row.classIcon:Show()
else row.classIcon:Hide() end
row:Show()
else row:Hide() end
end
end
mainScrollFrame:SetScript("OnVerticalScroll", function(self, offset) FauxScrollFrame_OnVerticalScroll(self, offset, MAIN_ROW_HEIGHT, UpdateMainTable) end)
-- ============================================================================
-- 5. ZAKŁADKA 3: PANEL GILDII
-- ============================================================================
local GuildContainer = CreateFrame("Frame", nil, Panels[3], "BackdropTemplate")
GuildContainer:SetSize(560, 435)
GuildContainer:SetPoint("TOPLEFT", Panels[3], "TOPLEFT", 0, 0)
ApplyModernStyle(GuildContainer)
local GuildTitleText = GuildContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
GuildTitleText:SetPoint("TOPLEFT", GuildContainer, "TOPLEFT", 15, -12)
GuildTitleText:SetText("Wykryte Wspolnoty i Gildie")
local guildScrollFrame = CreateFrame("ScrollFrame", "JagodkiGuildTableScrollFrame", GuildContainer, "FauxScrollFrameTemplate")
guildScrollFrame:SetPoint("TOPLEFT", GuildContainer, "TOPLEFT", 0, -40)
guildScrollFrame:SetPoint("BOTTOMRIGHT", GuildContainer, "BOTTOMRIGHT", -26, 10)
local GUILD_ROW_HEIGHT = 48
local MAX_GUILD_ROWS = 8
local guildRows = {}
for i = 1, MAX_GUILD_ROWS do
local card = CreateFrame("Frame", nil, GuildContainer, "BackdropTemplate")
card:SetSize(520, GUILD_ROW_HEIGHT - 6)
card:SetPoint("TOPLEFT", GuildContainer, "TOPLEFT", 10, -45 - ((i-1) * GUILD_ROW_HEIGHT))
card:SetBackdrop({
bgFile = "Interface\ChatFrame\ChatFrameBackground",
edgeFile = "Interface\Buttons\WHITE8X8", edgeSize = 1,
insets = { left = 0, right = 0, top = 0, bottom = 0 }
})
card:SetBackdropColor(0.09, 0.09, 0.12, 0.8)
card:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.6)
card.icon = card:CreateTexture(nil, "ARTWORK")
card.icon:SetSize(24, 26)
card.icon:SetPoint("LEFT", card, "LEFT", 15, 0)
card.icon:SetTexture("Interface\GuildFrame\GuildFrame")
card.icon:SetTexCoord(0.63, 0.69, 0.60, 0.73)
card.nameText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
card.nameText:SetPoint("LEFT", card.icon, "RIGHT", 15, 1)
card.activeText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
card.activeText:SetPoint("RIGHT", card, "RIGHT", -150, 0)
card.inactiveText = card:CreateFontString(nil, "OVERLAY", "GameFontDisable")
card.inactiveText:SetPoint("RIGHT", card, "RIGHT", -25, 0)
guildRows[i] = card
end
function UpdateGuildTable()
local guildData, guildOrder, currentTime = {}, {}, GetTime()
for _, player in ipairs(activePlayers) do
local gName = player.guild
if gName and gName ~= "" and gName ~= "Brak" then
if not guildData[gName] then guildData[gName] = { active = 0, inactive = 0 } table.insert(guildOrder, gName) end
if (currentTime - (player.lastSeen or currentTime)) < 180 then guildData[gName].active = guildData[gName].active + 1 else guildData[gName].inactive = guildData[gName].inactive + 1 end
end
end
table.sort(guildOrder, function(a, b) return guildData[a].active > guildData[b].active end)
FauxScrollFrame_Update(guildScrollFrame, #guildOrder, MAX_GUILD_ROWS, GUILD_ROW_HEIGHT)
local offset = FauxScrollFrame_GetOffset(guildScrollFrame)
for i = 1, MAX_GUILD_ROWS do
local idx = i + offset local card = guildRows[i]
if idx <= #guildOrder then
local gName = guildOrder[idx] local stats = guildData[gName]
card.nameText:SetText("|cffffffff" .. gName .. "|r")
card.activeText:SetText("|cff00ff00● Aktywni:|r " .. stats.active)
card.inactiveText:SetText("|cff808080O Nieaktywni:|r " .. stats.inactive) card:Show()
else card:Hide() end
end
end
guildScrollFrame:SetScript("OnVerticalScroll", function(self, offset) FauxScrollFrame_OnVerticalScroll(self, offset, GUILD_ROW_HEIGHT, UpdateGuildTable) end)
-- ============================================================================
-- 6. ZAKŁADKA 4: PANEL WYDARZEŃ
-- ============================================================================
local ListContainer = CreateFrame("Frame", nil, Panels[4], "BackdropTemplate")
ListContainer:SetSize(270, 435)
ListContainer:SetPoint("TOPLEFT", Panels[4], "TOPLEFT", 0, 0)
ApplyModernStyle(ListContainer)
local DetailsContainer = CreateFrame("Frame", nil, Panels[4], "BackdropTemplate")
DetailsContainer:SetSize(280, 390)
DetailsContainer:SetPoint("TOPRIGHT", Panels[4], "TOPRIGHT", 0, -45)
ApplyModernStyle(DetailsContainer)
local LHeader = ListContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LHeader:SetPoint("TOPLEFT", ListContainer, "TOPLEFT", 12, -12)
LHeader:SetText("Dostepne Wydarzenia")
local DHeader = DetailsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
DHeader:SetPoint("TOPLEFT", DetailsContainer, "TOPLEFT", 15, -15)
local DDesc = DetailsContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
DDesc:SetPoint("TOPLEFT", DetailsContainer, "TOPLEFT", 15, -45)
DDesc:SetWidth(250)
DDesc:SetJustifyH("LEFT")
DDesc:SetText("Wybierz wydarzenie z listy po lewej stronie.")
local CounterFrame = CreateFrame("Frame", nil, DetailsContainer)
CounterFrame:SetSize(250, 45)
CounterFrame:SetPoint("TOPLEFT", DDesc, "BOTTOMLEFT", 0, -10)
local TankCountText = CreatePhysicalIconAndText(CounterFrame, "UI-LFG-RoleIcon-Tank", 5)
local HealCountText = CreatePhysicalIconAndText(CounterFrame, "UI-LFG-RoleIcon-Healer", 65)
local DpsCountText  = CreatePhysicalIconAndText(CounterFrame, "UI-LFG-RoleIcon-DPS", 125)
local TotalCountText = CounterFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
TotalCountText:SetPoint("TOPLEFT", CounterFrame, "TOPLEFT", 180, 0)
TotalCountText:SetText("Razem:")
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
local BtnAll = CreateRosterFilterButton("Wszyscy", "ALL", 5)
local BtnTank = CreateRosterFilterButton("Tank", "TANK", 65)
local BtnHeal = CreateRosterFilterButton("Heal", "HEAL", 125)
local BtnDps = CreateRosterFilterButton("DPS", "DPS", 185)
local rosterScrollFrame = CreateFrame("ScrollFrame", "JagodkiRosterScrollFrame", RosterContainer, "FauxScrollFrameTemplate")
rosterScrollFrame:SetPoint("TOPLEFT", RosterContainer, "TOPLEFT", 0, -5)
rosterScrollFrame:SetPoint("BOTTOMRIGHT", RosterContainer, "BOTTOMRIGHT", -25, 5)
local ROSTER_ROW_HEIGHT, MAX_ROSTER_ROWS, rosterRows = 16, 11, {}
for i = 1, MAX_ROSTER_ROWS do
local row = CreateFrame("Frame", nil, RosterContainer)
row:SetSize(220, ROSTER_ROW_HEIGHT) row:SetPoint("TOPLEFT", RosterContainer, "TOPLEFT", 10, -5 - ((i-1) * ROSTER_ROW_HEIGHT))
row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
row.roleText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") row.roleText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
rosterRows[i] = row
end
function UpdateRosterList()
if not selectedEventIndex or not eventsList[selectedEventIndex] then return end
local ev = eventsList[selectedEventIndex]
local displayList = {}
for name, role in pairs(ev.roster) do
if currentRosterFilter == "ALL" or role == currentRosterFilter then
table.insert(displayList, { name = name, role = role })
end
end
table.sort(displayList, function(a, b) return a.name < b.name end)
FauxScrollFrame_Update(rosterScrollFrame, #displayList, MAX_ROSTER_ROWS, ROSTER_ROW_HEIGHT)
local offset = FauxScrollFrame_GetOffset(rosterScrollFrame)
for i = 1, MAX_ROSTER_ROWS do
local idx = i + offset local row = rosterRows[i]
if idx <= #displayList then
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
rosterScrollFrame:SetScript("OnVerticalScroll", function(self, offset) FauxScrollFrame_OnVerticalScroll(self, offset, ROSTER_ROW_HEIGHT, UpdateRosterList) end)
local eventScrollFrame = CreateFrame("ScrollFrame", "JagodkiEventScrollFrame", ListContainer, "FauxScrollFrameTemplate")
eventScrollFrame:SetPoint("TOPLEFT", ListContainer, "TOPLEFT", 0, -35)
eventScrollFrame:SetPoint("BOTTOMRIGHT", ListContainer, "BOTTOMRIGHT", -26, 10)
local EV_ROW_HEIGHT, MAX_EV_ROWS, eventRows = 40, 10, {}
for i = 1, MAX_EV_ROWS do
local btn = CreateFrame("Button", nil, ListContainer, "BackdropTemplate")
btn:SetSize(240, EV_ROW_HEIGHT - 4) btn:SetPoint("TOPLEFT", ListContainer, "TOPLEFT", 8, -35 - ((i-1) * EV_ROW_HEIGHT))
btn:SetBackdrop({ bgFile = "Interface\ChatFrame\ChatFrameBackground", edgeFile = "Interface\Buttons\WHITE8X8", edgeSize = 1 })
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
RemoveEventBtn:SetSize(70, 24) RemoveEventBtn:SetPoint("LEFT", JoinDpsBtn, "RIGHT", 6, 0) RemoveEventBtn:SetText("|cffff0000Usun|r") RemoveEventBtn:Hide()
local function UpdateFilterVisuals()
for fType, btn in pairs(filterButtons) do
if fType == currentRosterFilter then btn.text:SetTextColor(1, 0.82, 0) else btn.text:SetTextColor(0.6, 0.6, 0.6) end
end
if UpdateRosterList then UpdateRosterList() end
end
function UpdateEventDetails()
if not selectedEventIndex or not eventsList[selectedEventIndex] then
DHeader:SetText("Szczegoly") DDesc:SetText("Wybierz wydarzenie z listy po lewej stronie.")
CounterFrame:Hide() RosterContainer:Hide() JoinTankBtn:Hide() JoinHealBtn:Hide() JoinDpsBtn:Hide() RemoveEventBtn:Hide() return
end
local ev = eventsList[selectedEventIndex] DHeader:SetText(ev.title)
DDesc:SetText("|cffffffffAutor:|r " .. ev.creator .. "  |cffffffffCzas:|r " .. ev.date .. " " .. ev.time .. "\n|cffdecda5Opis:|r " .. ev.desc)
local t, h, d, total = 0, 0, 0, 0
for _, role in pairs(ev.roster) do total = total + 1 if role == "TANK" then t = t + 1 elseif role == "HEAL" then h = h + 1 else d = d + 1 end end
TankCountText:SetText(t) HealCountText:SetText(h) DpsCountText:SetText(d) TotalCountVal:SetText("|cffffd100" .. total .. "|r")
CounterFrame:Show() RosterContainer:Show() UpdateFilterVisuals() JoinTankBtn:Show() JoinHealBtn:Show() JoinDpsBtn:Show()
if ev.creator == UnitName("player") or IsPlayerOfficer() then RemoveEventBtn:Show() else RemoveEventBtn:Hide() end
end
function UpdateEventsList()
FauxScrollFrame_Update(eventScrollFrame, #eventsList, MAX_EV_ROWS, EV_ROW_HEIGHT)
local offset = FauxScrollFrame_GetOffset(eventScrollFrame)
for i = 1, MAX_EV_ROWS do
local idx = i + offset local row = eventRows[i]
if idx <= #eventsList then
local ev = eventsList[idx]
row.dataIndex = idx
row.title:SetText("|cffffffff" .. ev.title .. "|r")
row.time:SetText(ev.date .. " o " .. ev.time)
local totalSigned = 0
for _ in pairs(ev.roster) do totalSigned = totalSigned + 1 end
row.count:SetText(totalSigned .. " os.")
row:Show()
else row:Hide() end
end
end
local CreateEventBtn = CreateFrame("Button", nil, Panels[4], "GameMenuButtonTemplate")
CreateEventBtn:SetSize(140, 28) CreateEventBtn:SetPoint("TOPRIGHT", Panels[4], "TOPRIGHT", 0, -5) CreateEventBtn:SetText("Stworz Wydarzenie")
local CreatorFrame = CreateFrame("Frame", "JagodkiCreatorFrame", UIParent, "BackdropTemplate")
CreatorFrame:SetSize(320, 340) CreatorFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0) CreatorFrame:Hide()
CreatorFrame:SetFrameLevel(MainFrame:GetFrameLevel() + 20)
ApplyModernStyle(CreatorFrame) CreatorFrame:SetBackdropColor(0.05, 0.05, 0.07, 0.98)
CreatorFrame.TitleText = CreatorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
CreatorFrame.TitleText:SetPoint("TOP", CreatorFrame, "TOP", 0, -10) CreatorFrame.TitleText:SetText("Nowe Wydarzenie")
local TitleInput = CreateLabelAndInput(CreatorFrame, "Nazwa Wydarzenia:", -45, 275, 26)
local DateInput = CreateLabelAndInput(CreatorFrame, "Data:", -105, 130, 26)
local TimeInput = CreateLabelAndInput(CreatorFrame, "Godzina:", -105, 130, 26)
TimeInput:ClearAllPoints() TimeInput:SetPoint("TOPLEFT", CreatorFrame, "TOPLEFT", 165, -120)
local TimeLabel = CreatorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
TimeLabel:SetPoint("TOPLEFT", CreatorFrame, "TOPLEFT", 165, -105) TimeLabel:SetText("Godzina:")
local DescInput = CreateLabelAndInput(CreatorFrame, "Krotki opis:", -165, 275, 26)
local SubmitBtn = CreateFrame("Button", nil, CreatorFrame, "GameMenuButtonTemplate")
SubmitBtn:SetSize(120, 30) SubmitBtn:SetPoint("BOTTOM", CreatorFrame, "BOTTOM", 0, 20) SubmitBtn:SetText("Dodaj i Rozeslij")
CreateEventBtn:SetScript("OnClick", function() if IsPlayerOfficer() then CreatorFrame:Show() else UIErrorsFrame:AddMessage("Blad: Brak uprawnien oficerskich!", 1.0, 0.1, 0.1, 1.0, 2) end end)
SubmitBtn:SetScript("OnClick", function()
local title, eDate, eTime, desc = TitleInput:GetText(), DateInput:GetText(), TimeInput:GetText(), DescInput:GetText()
if title ~= "" and eDate ~= "" and eTime ~= "" then
local myName = UnitName("player") local eventID = myName .. "_" .. GetTime()
table.insert(eventsList, { id = eventID, title = title, date = eDate, time = eTime, desc = desc, creator = myName, roster = {} }) UpdateEventsList()
SendJagodkaNetworkPacket("EV_ADD", string.format("%s:%s:%s:%s:%s:%s", eventID, title, eDate, eTime, desc, myName))
TitleInput:SetText("") DateInput:SetText("") TimeInput:SetText("") DescInput:SetText("") CreatorFrame:Hide()
end
end)
local function SetRosterFilter(filterType) currentRosterFilter = filterType UpdateFilterVisuals() end
BtnAll:SetScript("OnClick", function() SetRosterFilter("ALL") end)
BtnTank:SetScript("OnClick", function() SetRosterFilter("TANK") end)
BtnHeal:SetScript("OnClick", function() SetRosterFilter("HEAL") end)
BtnDps:SetScript("OnClick", function() SetRosterFilter("DPS") end)
JoinTankBtn:SetScript("OnClick", function() if selectedEventIndex and eventsList[selectedEventIndex] then eventsList[selectedEventIndex].roster[UnitName("player")] = "TANK" UpdateEventDetails() UpdateEventsList() SendJagodkaNetworkPacket("EV_SIGN", eventsList[selectedEventIndex].id .. ":TANK") end end)
JoinHealBtn:SetScript("OnClick", function() if selectedEventIndex and eventsList[selectedEventIndex] then eventsList[selectedEventIndex].roster[UnitName("player")] = "HEAL" UpdateEventDetails() UpdateEventsList() SendJagodkaNetworkPacket("EV_SIGN", eventsList[selectedEventIndex].id .. ":HEAL") end end)
JoinDpsBtn:SetScript("OnClick", function() if selectedEventIndex and eventsList[selectedEventIndex] then eventsList[selectedEventIndex].roster[UnitName("player")] = "DPS" UpdateEventDetails() UpdateEventsList() SendJagodkaNetworkPacket("EV_SIGN", eventsList[selectedEventIndex].id .. ":DPS") end end)
RemoveEventBtn:SetScript("OnClick", function()
if not selectedEventIndex or not eventsList[selectedEventIndex] then return end
SendJagodkaNetworkPacket("EV_REM", eventsList[selectedEventIndex].id)
table.remove(eventsList, selectedEventIndex) selectedEventIndex = nil UpdateEventDetails() UpdateEventsList()
end)
-- ============================================================================
-- 6B. ZAKŁADKA 5: USTAWIENIA
-- ============================================================================
-- NAPRAWIONE: Tekst tworzony bezpośrednio na piątym indeksie tablicy paneli
local SettingsInfo = Panels[5]:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
SettingsInfo:SetPoint("CENTER", Panels[5], "CENTER", 0, 0)
SettingsInfo:SetText("Modul Konfiguracji i Filtrow w przygotowaniu...")
-- ============================================================================
-- 7. PANEL BOCZNY (WIDOCZNY ZAWSZE - PRAWA STRONA)
-- ============================================================================
local RightPanel = CreateFrame("Frame", nil, MainFrame, "BackdropTemplate")
RightPanel:SetSize(230, 465)
RightPanel:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -20, -135)
ApplyModernStyle(RightPanel)
local HeaderText = RightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
HeaderText:SetPoint("TOPLEFT", RightPanel, "TOPLEFT", 12, 18)
local scrollFrame = CreateFrame("ScrollFrame", "JagodkiRightListScrollFrame", RightPanel, "FauxScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", RightPanel, "TOPLEFT", 0, -5)
scrollFrame:SetPoint("BOTTOMRIGHT", RightPanel, "BOTTOMRIGHT", -26, 5)
local ROW_HEIGHT, MAX_ROWS, rows = 26, 17, {}
for i = 1, MAX_ROWS do
local row = CreateFrame("Button", nil, RightPanel)
row:SetSize(195, ROW_HEIGHT) row:SetPoint("TOPLEFT", RightPanel, "TOPLEFT", 5, -5 - ((i-1) * ROW_HEIGHT))
local rowTex = row:CreateTexture(nil, "BACKGROUND") rowTex:SetAllPoints() rowTex:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.01 or 0.03)
row.classIcon = row:CreateTexture(nil, "ARTWORK") row.classIcon:SetSize(18, 18) row.classIcon:SetPoint("LEFT", row, "LEFT", 8, 0)
row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") row.nameText:SetPoint("LEFT", row.classIcon, "RIGHT", 8, 0)
row.levelText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") row.levelText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
rows[i] = row
end
function UpdateScrollList()
HeaderText:SetText("Aktywni gracze (" .. #activePlayers .. ")")
FauxScrollFrame_Update(scrollFrame, #activePlayers, MAX_ROWS, ROW_HEIGHT)
local offset = FauxScrollFrame_GetOffset(scrollFrame)
for i = 1, MAX_ROWS do
local idx = i + offset local row = rows[i]
if idx <= #activePlayers then
local data = activePlayers[idx] local displayName = data.name
if data.class and RAID_CLASS_COLORS[data.class] then displayName = RAID_CLASS_COLORS[data.class]:WrapTextInColorCode(data.name) end
if data.guild and data.guild ~= "" and data.guild ~= "Brak" then displayName = displayName .. " |cffbf40ff(" .. data.guild .. ")|r" end
row.nameText:SetText(displayName) row.levelText:SetText(data.level)
if data.class and CLASS_ICON_TCOORDS[data.class] then
row.classIcon:SetTexture("Interface\GLUES\CHARACTERCREATE\UI-CHARACTERCREATE-CLASSES")
row.classIcon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[data.class])) row.classIcon:Show()
else row.classIcon:Hide() end
row:Show()
else row:Hide() end
end
end
scrollFrame:SetScript("OnVerticalScroll", function(self, offset) FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UpdateScrollList) end)
-- ============================================================================
-- 8. ODBIORNIK SIECIOWY (LISTENERY I SYNCHRONIZACJA)
-- ============================================================================
local NetworkListener = CreateFrame("Frame")
NetworkListener:RegisterEvent("CHAT_MSG_ADDON")
NetworkListener:RegisterEvent("PLAYER_LOGIN")
NetworkListener:RegisterEvent("ADDON_LOADED")
NetworkListener:SetScript("OnEvent", function(self, event, prefix, text, channel, sender)
if event == "ADDON_LOADED" and prefix == "jagodka" then
JagodkiEventsDB = JagodkiEventsDB or {} eventsList = JagodkiEventsDB return
end
if event == "PLAYER_LOGIN" then
-- NAPRAWIONE: Bez rejestracji prefiksu WoW blokował wymianę danych między graczami
C_ChatInfo.RegisterAddonMessagePrefix("JagodkaComm")
AddMyselfToActiveList() SendStatusPacket("PING")
table.insert(chatHistories["Ogolny"], "|cff00ccff[System]: Polaczono z kanalem Jagodka.|r") UpdateChatTabVisuals()
elseif event == "CHAT_MSG_ADDON" and prefix == "JagodkaComm" then
-- NAPRAWIONE: Usunięto błąd składniowy (słowo 'American')
local senderName = Ambiguate(sender, "none")
local pType, payload = strsplit(":", text, 2)
if pType == "CHAT" and payload then
local targetTab, msgContent = strsplit(":", payload, 2)
if targetTab and msgContent and chatHistories[targetTab] then
-- NAPRAWIONE: Warunek blokuje wyświetlanie własnych wiadomości z serwera (brak efektu echo/dubla)
if senderName ~= UnitName("player") then
local idx = GetPlayerIndex(senderName)
local rankStr = (idx and activePlayers[idx].rank and activePlayers[idx].rank ~= "Brak") and (GetColoredRank(activePlayers[idx].rank) .. " ") or ""
table.insert(chatHistories[targetTab], rankStr .. "[" .. GetColoredName(senderName) .. "]: " .. msgContent)
if targetTab == currentChatTab then RefreshChatDisplay() end
end
end
elseif pType == "PING" or pType == "PONG" then
if payload then
local lvl, cls, gld, rnk = strsplit(":", payload, 4)
local existingIndex = GetPlayerIndex(senderName)
local playerData = { name = senderName, level = lvl, class = cls, guild = gld or "Brak", rank = rnk or "Brak", lastSeen = GetTime() }
if existingIndex then activePlayers[existingIndex] = playerData else table.insert(activePlayers, playerData) end
UpdateScrollList() if UpdateMainTable then UpdateMainTable() end if MainFrame:IsShown() then UpdateGuildTable() end
if pType == "PING" then SendStatusPacket("PONG") end
end
elseif pType == "EV_REQ" then
local myName = UnitName("player")
for _, ev in ipairs(eventsList) do if ev.creator == myName then SendJagodkaNetworkPacket("EV_ADD", string.format("%s:%s:%s:%s:%s:%s", ev.id, ev.title, ev.date, ev.time, ev.desc, ev.creator)) end end
elseif pType == "EV_ADD" and payload then
local evID, title, eDate, eTime, desc, creator = strsplit(":", payload, 6)
if evID and title then
local exists = false for _, ev in ipairs(eventsList) do if ev.id == evID then exists = true break end end
if not exists then table.insert(eventsList, { id = evID, title = title, date = eDate, time = eTime, desc = desc, creator = creator, roster = {} }) if MainFrame:IsShown() then UpdateEventsList() end end
end
elseif pType == "EV_SIGN" and payload then
local evID, role = strsplit(":", payload, 2)
for _, ev in ipairs(eventsList) do if ev.id == evID then ev.roster[senderName] = role if selectedEventIndex and eventsList[selectedEventIndex].id == evID then UpdateEventDetails() end if MainFrame:IsShown() then UpdateEventsList() end break end end
elseif pType == "EV_REM" and payload then
for idx, ev in ipairs(eventsList) do if ev.id == payload then if selectedEventIndex and eventsList[selectedEventIndex].id == payload then selectedEventIndex = nil UpdateEventDetails() end table.remove(eventsList, idx) if MainFrame:IsShown() then UpdateEventsList() end break end end
end
end
end)
MainFrame:SetScript("OnShow", function()
AddMyselfToActiveList() SendStatusPacket("PING") UpdateScrollList() if UpdateMainTable then UpdateMainTable() end
UpdateGuildTable()
UpdateEventsList()
end)
-- Poprawne bicie skryptu OnShow bezpośrednio do czwartej ramki z tablicy indeksów (Wydarzenia)
Panels[4]:SetScript("OnShow", function()
if JagodkiEventsDB then eventsList = JagodkiEventsDB end
if IsPlayerOfficer() then CreateEventBtn:Enable() else CreateEventBtn:Disable() end
if UpdateEventsList then UpdateEventsList() end
SendJagodkaNetworkPacket("EV_REQ", "ZAPYTANIE")
end)
-- Defaultowo przy starcie pokazujemy pierwszą zakładkę
ShowTab(1)
-- ============================================================================
-- 9. REJESTRACJA KOMENDY CZATU I MINIMAPY (LibDataBroker)
-- ============================================================================
SLASH_JAGODKI1 = "/okno"
SlashCmdList["JAGODKI"] = function() if MainFrame:IsShown() then MainFrame:Hide() else MainFrame:Show() end end
-- Rejestracja obiektu danych w LibDataBroker (LDB)
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
tooltip:AddLine("|cffffd100Kliknij, aby otworzyć okno Wspólnoty|r")
end,
})
-- Rejestracja pozycji przycisku na minimapie za pomocą LibDBIcon
local icon = LibStub("LibDBIcon-1.0")
JagodkiMinimapDB = JagodkiMinimapDB or { minimap = { hide = false } }
icon:Register("JagodkiNadina", JagodkiLDB, JagodkiMinimapDB.minimap)
