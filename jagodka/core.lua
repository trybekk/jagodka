-- ============================================================================
-- 0. GLOBAL SCOPE ISOLATION & UPVALUES
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
local C_Timer = addonTable.SafeTimer -- protected callbacks (safe.lua)

-- FORCED PREFIX REGISTRATION AT THE VERY START OF THE FILE
-- The client limits registered prefixes; with many addons registration can fail
do
local result = C_ChatInfo.RegisterAddonMessagePrefix("JagodkaComm")
-- Older API returns a bool, newer a code: 0 = OK, 1 = already registered (also OK), 2+ = error
if result == false or (type(result) == "number" and result >= 2) then
C_Timer.After(5, function()
if _G.DEFAULT_CHAT_FRAME then _G.DEFAULT_CHAT_FRAME:AddMessage("|cffbf40ff[Jagodka]|r |cffff5555Failed to register the addon prefix (too many addons?) - communication will not work.|r") end
end)
end
end

-- ============================================================================
-- 0B. SHARED CHANNEL AND GUILD WHITELIST CONFIGURATION
-- ============================================================================
local AllowedGuilds = {}
-- Community guilds: "Jagódki Nadina", "... II", "... IIl", "... IV", "... V", "... VI". There is no "III": the
-- game does not allow three identical characters in a row in a guild name, so the third guild is "IIl" (two
-- capital i and a small L, which looks like III; from 0.15.1, tag JN3).
-- Another guild = another suffix and an addon version bump. Chat tags: GUILD_TAGS in bridge.lua.
for _, suffix in ipairs({ "", " II", " IIl", " IV", " V", " VI" }) do
    AllowedGuilds["Jagódki Nadina" .. suffix] = true
end
-- Listed but not created yet: hidden in the Guilds tab and the guilds panel only (still on the list above,
-- so they work at once when founded). Remove a name here once that guild exists.
local GuildsNotShown = { ["Jagódki Nadina V"] = true, ["Jagódki Nadina VI"] = true }

local function IsPlayerGuildAllowed(guildName)
    if not guildName or guildName == "" or guildName == "Brak" then return false end
    return AllowedGuilds[guildName] == true
end
-- ============================================================================
-- 0C. ADDON VERSION (from "## Version" in the .toc, sent in every status packet)
-- ============================================================================
local GetAddOnMetadata = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
local ADDON_VERSION = GetAddOnMetadata(addonName, "Version") or "0"

-- Compares "1.2.10" with "1.2.9": -1 when a is older, 0 when equal, 1 when a is newer
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
-- 1. MAIN WINDOW CONFIGURATION AND BASIC DRAWING FUNCTIONS
-- ============================================================================
local MainFrame = CreateFrame("Frame", "JagodkiNadinaMainFrame", UIParent, "BackdropTemplate")
MainFrame:SetSize(1000, 775)
MainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
MainFrame:Hide()
-- Esc closes the window, like the game's own windows (the first Esc only leaves a focused input)
table.insert(_G.UISpecialFrames, "JagodkiNadinaMainFrame")
-- Above the game's ordinary windows (bags, character, map...); our own popups (event details, creator,
-- calendar day, note), menus, the game's dialogs and tooltips are on higher layers and stay above it.
-- Toplevel: a click brings it to the front among windows of the same layer.
MainFrame:SetFrameStrata("HIGH")
MainFrame:SetToplevel(true)

MainFrame:EnableMouse(true)
MainFrame:SetMovable(true)
MainFrame:SetClampedToScreen(true)
-- Window position and size: JagodkiMinimapDB.window (loaded after ADDON_LOADED, section 9).
-- Moved only by the title bar, resized with the handle in the bottom right corner.
-- Minimum size = default (the layout is built for it), a larger window = more content.
-- Minimum height 775 (735 before 0.15.1, +40 for a fourth guild row): the right column (character card, upcoming events, officers, guilds, classes) needs it; minimum width
-- 1000: the right column is 330 wide, and the character card at its top must not cover the last tab button (Monitoring)
local WIN_MIN_W, WIN_MIN_H, WIN_MAX_W, WIN_MAX_H = 1000, 775, 1600, 1100
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
-- How many list rows fit in a container of the current height (before the first layout: default)
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
WindowLogo:SetTexture("Interface\\AddOns\\jagodka\\Media\\blueberry.tga")

TitleText:SetPoint("LEFT", WindowLogo, "RIGHT", 8, 0)
TitleText:SetText("|cffffffffJagodki Nadina|r |cffdecda5-|r Community |cffdecda5-|r v" .. ADDON_VERSION)

local CloseBtn = CreateFrame("Button", nil, MainFrame, "UIPanelCloseButton")
CloseBtn:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -2, -2)
CloseBtn:SetSize(30, 30)
do
-- Title bar (logo + name) = the only place the window can be dragged by
local DragBar = CreateFrame("Frame", nil, MainFrame)
DragBar:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 1, -1)
DragBar:SetPoint("BOTTOMRIGHT", MainFrame, "TOPRIGHT", -40, -35)
DragBar:EnableMouse(true)
DragBar:RegisterForDrag("LeftButton")
DragBar:SetScript("OnDragStart", function() MainFrame:StartMoving() end)
DragBar:SetScript("OnDragStop", function() MainFrame:StopMovingOrSizing() MainFrame.SaveLayout() end)
CloseBtn:SetFrameLevel(DragBar:GetFrameLevel() + 2)
-- Resize handle: the window gets bigger (fonts unchanged), tabs show more content
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
-- Sync bar in the header, left of the counter (sync.lua; visible only while something is happening)
addonTable.Sync.Attach(MainFrame, OnlineText)

local Panels = {}
-- Tab numbers are used everywhere; Help (7) is shown before Monitoring (TAB_ORDER)
local tabNames = {"Community Chat", "Roster", "Guilds", "Events", "Calendar", "Monitoring", "Help", "Settings", "LFG"}

-- Column order; x and width are starting values, membersView.LayoutColumns fits them to the content.
-- field = the row element placed at the column's position
local columns = {
    { name = "Name", width = 110, x = 10, key = "name", field = "nameText" },
    { name = "Lvl", width = 40, x = 125, key = "level", field = "levelText" },
    { name = "Class", width = 90, x = 170, key = "class", field = "classIcon" },
    { name = "Location", width = 90, x = 265, key = "location", field = "locationBox" },
    { name = "Guild", width = 140, x = 265, key = "guild", field = "guildText" },
    { name = "Rank", width = 65, x = 410, key = "rank", field = "rankText" },
    { name = "Note", width = 30, x = 480, key = "note", field = "noteIcon", noSort = true },
    { name = "Prof", width = 30, x = 480, key = "prof", field = "profIcons", noSort = true },
    { name = "Armory", width = 30, x = 480, key = "armory", field = "armoryBtn", noSort = true, center = 14 },
    { name = "Version", width = 50, x = 480, key = "version", field = "versionText" }
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
-- 1B. NETWORK FUNCTIONS OVER STABLE BLIZZARD CHANNELS
-- ============================================================================
-- Transport, global channel and the shared chat are in bridge.lua (loaded before core.lua)
local Most = addonTable.Most
local Roster = addonTable.Roster
local Mute = addonTable.Mute

local function SendJagodkaNetworkPacket(prefixType, dataPayload, priority)
    local myGuild = GetGuildInfo("player")
    if not IsPlayerGuildAllowed(myGuild) then return end
    -- Sent over GUILD (the relay forwards the packet to other guilds), through the rate-limited queue
    -- priority "low" = sync (chat goes first)
    Most.Send(prefixType, dataPayload, priority)
end

-- Encodes event fields so a ":" in text (e.g. the time 20:00) does not break the packet
local EncodeField, DecodeField = Most.EncodeField, Most.DecodeField

-- Events: data, rules and sync in events.lua (new in 0.14.0); the windows below only show and edit them
local EVENT_DESC_MAX_BYTES = addonTable.Events.DESC_MAX

-- target: whisper to a player from another guild (found on the channel list) or an answer to their PING
local function SendStatusPacket(msgType, target)
    local guildName, rankName, rankIndex = GetGuildInfo("player")
    guildName = guildName or "Brak"
    rankName = rankName or "Brak"
    -- The rank index lets others check officer permissions (creating/removing events)
    local payload = UnitLevel("player") .. ":" .. select(2, UnitClass("player")) .. ":" .. guildName .. ":" .. rankName .. ":" .. ADDON_VERSION .. ":" .. (rankIndex or -1) .. ":" .. EncodeField(_G.GetRealZoneText())
    if target and msgType == "PING" then
        Most.Whisper(target, "FW", Most.MyName() .. ":" .. msgType .. ":" .. payload, "high")
    elseif target then
        Most.Whisper(target, msgType, payload, "high")
    else
        SendJagodkaNetworkPacket(msgType, payload)
    end
end

for i, name in ipairs(tabNames) do
    local p = CreateFrame("Frame", nil, MainFrame)
    -- Stretches with the window (at 850x620: 560x465); room is left on the right for the player panel
    p:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 20, -135)
    p:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", -370, 20)
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

-- Buttons left to right in this order: Help before Monitoring (officers only, last, so hiding it leaves no gap)
-- LFG (9) right after Calendar
for _, i in ipairs({ 1, 2, 3, 4, 5, 9, 7, 8, 6 }) do
    local name = tabNames[i]
    local btn = CreateFrame("Button", nil, MainFrame, "BackdropTemplate")
    btn:SetSize(115, 32)
    -- The Guilds tab (3) has no button any more: the guilds panel in the right column replaced it. Its
    -- panel stays (tab numbers are used everywhere), it just cannot be opened; the next tabs move left.
    -- Placed one after another (MainFrame.tabX), since a long name makes its button wider (below).
    MainFrame.tabX = MainFrame.tabX or 20
    btn:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", MainFrame.tabX, -50)
    if i == 3 then btn:Hide() end
    
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
    -- Icon left of the name, the pair centered on the button. Roster: the addon's blueberry; the rest
    -- from the game's files (Interface\Icons with the frame edge cut off, the gossip speech bubble).
    local TAB_ICONS = {
        "Interface\\GossipFrame\\GossipGossipIcon",
        "Interface\\AddOns\\jagodka\\Media\\blueberry_one.tga",
        nil,
        "Interface\\Icons\\INV_Misc_Ticket_Darkmoon_01",
        "Interface\\Icons\\INV_Misc_PocketWatch_01",
        "Interface\\Icons\\INV_Misc_Spyglass_02",
        "Interface\\Icons\\INV_Misc_QuestionMark",
        "Interface\\Icons\\INV_Misc_Gear_01",
        "Interface\\GroupFrame\\UI-Group-LeaderIcon",
    }
    if i == 7 then
        -- Help: the same round badge as the "?" buttons next to the features (help.lua)
        btn.icon = addonTable.Help.Badge(btn, 16)
        btn.text:ClearAllPoints()
        btn.text:SetPoint("CENTER", btn, "CENTER", 10, 0)
        btn.icon:SetPoint("RIGHT", btn.text, "LEFT", -5, 0)
    elseif TAB_ICONS[i] then
        btn.icon = btn:CreateTexture(nil, "OVERLAY")
        btn.icon:SetSize(16, 16)
        btn.icon:SetTexture(TAB_ICONS[i])
        if TAB_ICONS[i]:find("\\Icons\\", 1, true) then btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        btn.text:ClearAllPoints()
        btn.text:SetPoint("CENTER", btn, "CENTER", 10, 0)
        btn.icon:SetPoint("RIGHT", btn.text, "LEFT", -5, 0)
    end
    -- As wide as the icon and name with 15 px free on each side (at least 80), so all 6 tabs fit next to
    -- the character card
    btn:SetWidth(math.max(64, math.ceil(btn.text:GetStringWidth()) + (btn.icon and 21 or 0) + 2 * 10))
    if i ~= 3 then MainFrame.tabX = MainFrame.tabX + btn:GetWidth() + 5 end

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
-- The character card (330 wide, 20 from the right edge) must start right of the last tab button: a font
-- that makes the tabs wider raises the window's minimum width
do
local need = math.ceil(MainFrame.tabX + 10 + 330 + 20)
if need > WIN_MIN_W then
WIN_MIN_W = need
if MainFrame.SetResizeBounds then MainFrame:SetResizeBounds(WIN_MIN_W, WIN_MIN_H, WIN_MAX_W, WIN_MAX_H) else MainFrame:SetMinResize(WIN_MIN_W, WIN_MIN_H) end
if MainFrame:GetWidth() < WIN_MIN_W then MainFrame:SetWidth(WIN_MIN_W) end
end
end
-- ============================================================================
-- 2. PLAYER DATABASE AND RANK / COLOR HELPER FUNCTIONS
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
    -- Not online with the addon: the class from guild rosters, e.g. for sign-ups of offline players
    if not idx then
        local class = Roster.GetClassLevel(name)
        if class and RAID_CLASS_COLORS[class] then return RAID_CLASS_COLORS[class]:WrapTextInColorCode(name) end
    end
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
-- Officer = rank 0/1 in the guild or a rank name indicating an officer/leader (also works for other players)
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
-- Officer of another player by the guild roster (my guild: the game's, other guilds: sent by their members),
-- never by the rank they send about themselves. Not in a known roster = not an officer.
-- guild (optional): the player's guild, when known.
local function IsKnownOfficer(name, guild)
if name == Most.MyName() then return IsPlayerOfficer() end
local rankName, rankIndex = Roster.GetRank(name, guild)
return rankIndex ~= nil and IsRankOfficer(rankName, rankIndex)
end
-- Date: DD.MM or DD.MM.YYYY, time: HH:MM
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
-- EVENT SYNC (Events and Calendar have the same data for everyone)
-- ============================================================================
--  * Data, rules and sync: events.lua. Here: the specs, and the windows (below).
local EventSync = { pongPending = {} }
-- Specs each class can sign up with, off-specs too. code = capital letters only (EV_SPEC, EV_ROS).
EventSync.CLASS_SPECS = {
WARRIOR = { { code = "ARMS", name = "Arms", role = "DPS" }, { code = "FURY", name = "Fury", role = "DPS" }, { code = "WPROT", name = "Protection", role = "TANK" } },
PALADIN = { { code = "PHOLY", name = "Holy", role = "HEAL" }, { code = "PPROT", name = "Protection", role = "TANK" }, { code = "RET", name = "Retribution", role = "DPS" } },
HUNTER = { { code = "BM", name = "Beast Mastery", role = "DPS" }, { code = "MM", name = "Marksmanship", role = "DPS" }, { code = "SURV", name = "Survival", role = "DPS" } },
ROGUE = { { code = "ASSA", name = "Assassination", role = "DPS" }, { code = "COMBAT", name = "Combat", role = "DPS" }, { code = "SUB", name = "Subtlety", role = "DPS" } },
PRIEST = { { code = "DISC", name = "Discipline", role = "HEAL" }, { code = "PRHOLY", name = "Holy", role = "HEAL" }, { code = "SHADOW", name = "Shadow", role = "DPS" } },
SHAMAN = { { code = "ELE", name = "Elemental", role = "DPS" }, { code = "ENH", name = "Enhancement", role = "DPS" }, { code = "SRESTO", name = "Restoration", role = "HEAL" } },
MAGE = { { code = "ARCANE", name = "Arcane", role = "DPS" }, { code = "FIRE", name = "Fire", role = "DPS" }, { code = "FROST", name = "Frost", role = "DPS" } },
WARLOCK = { { code = "AFFLI", name = "Affliction", role = "DPS" }, { code = "DEMO", name = "Demonology", role = "DPS" }, { code = "DESTRO", name = "Destruction", role = "DPS" } },
DRUID = { { code = "BALANCE", name = "Balance", role = "DPS" }, { code = "FERALT", name = "Feral Tank", role = "TANK" }, { code = "FERALD", name = "Feral DPS", role = "DPS" }, { code = "DRESTO", name = "Restoration", role = "HEAL" } },
}
-- Built from the specs: code -> spec with its class, and class -> roles it can play
EventSync.SPECS, EventSync.CLASS_ROLES = {}, {}
for class, specs in pairs(EventSync.CLASS_SPECS) do
EventSync.CLASS_ROLES[class] = {}
for _, spec in ipairs(specs) do
spec.class = class
EventSync.SPECS[spec.code] = spec
EventSync.CLASS_ROLES[class][spec.role] = true
end
end
-- Event time (noon of that day) from "DD.MM.YYYY" or the old "DD.MM" (current year)
function EventSync.DayTime(dateText)
local d, m, y = (dateText or ""):match("^(%d%d?)%.(%d%d?)%.?(%d*)$")
if not d then return nil end
return time({ year = tonumber(y) or tonumber(date("%Y")), month = tonumber(m), day = tonumber(d), hour = 12 })
end
-- The old event functions now call events.lua
function EventSync.Request(force) addonTable.Events.Request(force) end
function EventSync.CanInvite(ev) return addonTable.Events.CanInvite(ev) end
local function AddMyselfToActiveList()
local myName = Most.MyName()
local level = UnitLevel("player")
local _, classFilename = UnitClass("player")
local guildName, rankName, rankIndex = GetGuildInfo("player")
guildName = guildName or "Brak"
rankName = rankName or "Brak"
if not IsPlayerGuildAllowed(guildName) then return end
local existingIndex = GetPlayerIndex(myName)
local playerData = {
name = myName, level = level, class = classFilename, guild = guildName, rank = rankName, rankIndex = rankIndex, version = ADDON_VERSION, zone = _G.GetRealZoneText(), lastSeen = GetTime()
}
if existingIndex then activePlayers[existingIndex] = playerData else table.insert(activePlayers, playerData) end
end
-- ============================================================================
-- 3. TAB 1: CHAT PANEL
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
-- Mouse wheel: 3 lines (Shift = whole page, Ctrl = start / end of history)
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
-- Scroll bar on the right (arrows + slider), synced with the wheel and new messages.
-- Chat offset: 0 = newest (bottom); slider: 0 = top, max = bottom.
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
-- The input field stretches with the window, the Send button stays at the right edge
chatInput:SetHeight(26)
chatInput:SetPoint("BOTTOMLEFT", ChatPanel, "BOTTOMLEFT", 12, 10)
chatInput:SetPoint("BOTTOMRIGHT", ChatPanel, "BOTTOMRIGHT", -95, 10)
chatInput:SetAutoFocus(false)
chatInput:SetFontObject(ChatFontNormal)
-- The game's own chat limit; bridge.lua splits a message into parts that fit a packet
chatInput:SetMaxBytes(Most.MAX_CHAT_BYTES)
-- Shift + click on an item / spell / profession inserts a link into the field when it is active
-- (the game only inserts links into its own chat window)
hooksecurefunc("ChatEdit_InsertLink", function(link) if link and chatInput:HasFocus() then chatInput:Insert(link) end end)
local sendButton = CreateFrame("Button", nil, ChatPanel, "GameMenuButtonTemplate")
sendButton:SetSize(75, 26)
sendButton:SetPoint("LEFT", chatInput, "RIGHT", 8, 0)
sendButton:SetText("Send")
-- "Oficerowie": the officers chat (officers.lua), its button only for officers (EventSync.UpdateMonitoringTab)
local chatTabs = {"Ogolny", "Handel", "Szukaj grupy", "Oficerowie"}
local currentChatTab = "Ogolny"
local chatTabButtons = {}
-- The chat shows one shared log from bridge.lua (all guilds, the same order for everyone)
local function RefreshChatDisplay()
chatDisplay:Clear()
-- The officers tab has its own log (officers.lua), never part of the shared one
local isOfficersTab = currentChatTab == addonTable.Officers.TAB
for _, entry in ipairs(isOfficersTab and addonTable.Officers.GetLog() or Most.GetLog()) do
-- Names as links (menu in mute.lua); messages of muted players are hidden (they return after unmute)
if entry.tab == currentChatTab and not Mute.IsMuted(entry.author) then chatDisplay:AddMessage(Most.FormatEntry(entry, nil, true)) end
end
-- The slider range is known only after the lines are laid out (next frame)
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
local guildName = Most.MyGuild()
-- Officers chat: only on the officers channel, never through the relays (officers.lua)
if currentChatTab == addonTable.Officers.TAB then
local ok, reason = addonTable.Officers.Say(msg)
if ok then chatInput:SetText("") else chatDisplay:AddMessage("|cffff5555[System]: " .. tostring(reason) .. " - message kept.|r") end
return
end
if Mute.IsMuted(Most.MyName()) then
chatDisplay:AddMessage("|cffff5555[System]: You are muted on the community chat (by " .. tostring(Mute.MutedBy(Most.MyName())) .. ") - message not sent.|r")
elseif IsPlayerGuildAllowed(guildName) then
-- On the global channel (or over GUILD and relays when the channel is not available)
Most.PublishTyped(currentChatTab, msg, Most.MyName(), guildName)
elseif not guildName and IsInGuild() then
chatDisplay:AddMessage("|cffff5555[System]: Guild info not loaded yet - try again in a moment (message kept).|r")
return
else
chatDisplay:AddMessage("|cffff5555[System]: Your guild (" .. tostring(guildName) .. ") is not on the Community list - message not sent.|r")
end
chatInput:SetText("")
end
end
sendButton:SetScript("OnClick", OriginalSubmitMessage)
chatInput:SetScript("OnEnterPressed", OriginalSubmitMessage)
-- The field loses focus only after a click elsewhere (Shift + click inserts a link, so it does not count)
do
local blurWatcher = CreateFrame("Frame")
pcall(blurWatcher.RegisterEvent, blurWatcher, "GLOBAL_MOUSE_DOWN")
addonTable.SafeScript(blurWatcher, "OnEvent", "core.lua:685", function()
if chatInput:HasFocus() and not chatInput:IsMouseOver() and not sendButton:IsMouseOver() and not IsShiftKeyDown() then chatInput:ClearFocus() end
end)
end
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
tBtn.text:SetText(({ Ogolny = "General", Handel = "Trade", ["Szukaj grupy"] = "LFG", Oficerowie = "Officers" })[name] or name)
-- Icon left of the name, from the game's files: a tavern mug (General), gold coins (Trade), the group
-- leader's crown (LFG); Interface\Icons with the frame edge cut off
-- the assistant's mark (Officers)
local chatIcon = ({ Ogolny = "Interface\\Icons\\INV_Drink_04", Handel = "Interface\\Icons\\INV_Misc_Coin_01", ["Szukaj grupy"] = "Interface\\GroupFrame\\UI-Group-LeaderIcon", Oficerowie = "Interface\\GroupFrame\\UI-Group-AssistantIcon" })[name]
if chatIcon then
tBtn.icon = tBtn:CreateTexture(nil, "OVERLAY")
tBtn.icon:SetSize(14, 14)
tBtn.icon:SetTexture(chatIcon)
if chatIcon:find("\\Icons\\", 1, true) then tBtn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
tBtn.text:ClearAllPoints()
tBtn.text:SetPoint("CENTER", tBtn, "CENTER", 9, 0)
tBtn.icon:SetPoint("RIGHT", tBtn.text, "LEFT", -4, 0)
end
tBtn:SetScript("OnClick", function() currentChatTab = name UpdateChatTabVisuals() end)
chatTabButtons[name] = tBtn
end
-- "?" over the chat (help.lua): the chat topic, or the officers chat on the Officers tab
do
local help = addonTable.Help.Button(ChatPanel, "chat", nil, "Community Chat")
help:SetPoint("BOTTOMRIGHT", ChatPanel, "TOPRIGHT", -4, 4)
help.onClick = function()
if currentChatTab == addonTable.Officers.TAB then addonTable.Help.Open("officer", 3) else addonTable.Help.Open("chat") end
end
end
if chatTabButtons.Oficerowie then chatTabButtons.Oficerowie:Hide() end
-- Officers chat (officers.lua): officers by the guild rosters, online officers for the key and history
addonTable.Officers.Init({
isMeOfficer = function() return IsPlayerOfficer() end,
isKnownOfficer = function(name) return IsKnownOfficer(name) end,
onlineOfficers = function()
local names = {}
for _, p in ipairs(Roster.BuildList(false)) do
if IsKnownOfficer(p.name, p.guild) then table.insert(names, p.name) end
end
return names
end,
onChanged = function() if currentChatTab == addonTable.Officers.TAB then RefreshChatDisplay() end end,
})
-- Events (events.lua): rules need the ranks and specs; the windows refresh on changes
addonTable.Events.Init({
isMeOfficer = function() return IsPlayerOfficer() end,
isKnownOfficer = function(name) return IsKnownOfficer(name) end,
specs = EventSync.SPECS, classRoles = EventSync.CLASS_ROLES,
onChanged = function(ev)
if selectedEventIndex and eventsList[selectedEventIndex] == ev then UpdateEventDetails() end
if MainFrame:IsShown() then UpdateEventsList() end
end,
-- An event left the list: the selection follows the indexes
onRemoved = function(idx)
if selectedEventIndex == idx then selectedEventIndex = nil UpdateEventDetails()
elseif selectedEventIndex and selectedEventIndex > idx then selectedEventIndex = selectedEventIndex - 1 end
if MainFrame:IsShown() then UpdateEventsList() end
end,
})
-- Connects the bridge to the data and chat view from core.lua
Most.Init({
activePlayers = activePlayers,
isGuildAllowed = IsPlayerGuildAllowed,
onChatChanged = function(tab) if tab == currentChatTab then RefreshChatDisplay() end end,
sendHello = function(target) SendStatusPacket("PING", target) end,
announce = function() SendStatusPacket("PONG") end,
})
Mute.Init({
activePlayers = activePlayers,
isGuildAllowed = IsPlayerGuildAllowed,
isRankOfficer = IsRankOfficer,
isKnownOfficer = IsKnownOfficer,
isMeOfficer = IsPlayerOfficer,
onChanged = function() RefreshChatDisplay() UpdateMainTable() end,
})
Mute.AttachChat(chatDisplay)
addonTable.Discord.AttachChatFrame(chatDisplay)
addonTable.Notes.Init({ activePlayers = activePlayers, isGuildAllowed = IsPlayerGuildAllowed, parent = Panels[2], onChanged = function() UpdateMainTable() end })
addonTable.Key.Init({ isKnownOfficer = IsKnownOfficer, isMeOfficer = IsPlayerOfficer })
addonTable.Professions.Init({ activePlayers = activePlayers, isGuildAllowed = IsPlayerGuildAllowed, onChanged = function() UpdateMainTable() end })
Roster.Init({
activePlayers = activePlayers,
isGuildAllowed = IsPlayerGuildAllowed,
allowedGuilds = AllowedGuilds,
onChanged = function() UpdateMainTable() UpdateScrollList() if Panels[3]:IsVisible() then UpdateGuildTable() end end,
})
-- ============================================================================
-- 4. TAB 2: MAIN PLAYER TABLE + SEARCH
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
SearchEditBox.Instructions:SetText("Name, class, location, guild or rank...")
-- Online only by default; checked = all members of listed guilds (also offline)
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
-- Sorting: header click = ascending, second = descending, third = default (online, guild, name)
-- Paging: MEMBERS_PER_PAGE people per page, scrolling within the page
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
if col.noSort then return end
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
-- Reset: clears the search, turns off "Show offline" (default), restores the default sorting and page 1
do
local ResetViewBtn = CreateFrame("Button", nil, Panels[2], "UIPanelButtonTemplate")
ResetViewBtn:SetSize(70, 22)
ResetViewBtn:SetPoint("LEFT", ShowOfflineCheck.label, "RIGHT", 15, 0)
ResetViewBtn:SetText("Reset")
addonTable.Help.Button(Panels[2], "roster", nil, "Roster"):SetPoint("LEFT", ResetViewBtn, "RIGHT", 8, 0)
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
-- Rows are created in advance (tallest window); as many show as fit the table (TableContainer.visibleRows)
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
-- Location: a frame around the text, because a long name can be cut and hovering shows it in full
row.locationBox = CreateFrame("Frame", nil, row)
row.locationBox:SetHeight(MAIN_ROW_HEIGHT)
row.locationBox:EnableMouse(true)
if row.locationBox.SetMouseClickEnabled then row.locationBox:SetMouseClickEnabled(false) end
row.locationText = row.locationBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
row.locationText:SetAllPoints()
row.locationText:SetJustifyH("LEFT") row.locationText:SetWordWrap(false)
row.locationBox:SetScript("OnEnter", function(self)
if not self.location then return end
_G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
_G.GameTooltip:SetText(self.location, 1, 1, 1)
_G.GameTooltip:Show()
end)
row.locationBox:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
row.levelText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
row.levelText:SetPoint("LEFT", row, "LEFT", 220, 0)
row.guildText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
row.guildText:SetPoint("LEFT", row, "LEFT", 265, 0)
row.rankText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
row.rankText:SetPoint("LEFT", row, "LEFT", 410, 0)
-- A long rank is cut so it does not overlap the version column
row.rankText:SetWidth(65) row.rankText:SetJustifyH("LEFT") row.rankText:SetWordWrap(false)
row.versionText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
row.versionText:SetPoint("LEFT", row, "LEFT", 480, 0)
addonTable.Notes.AttachRow(row)
addonTable.Professions.AttachRow(row)
addonTable.Armory.AttachRow(row)
addonTable.Discord.AttachRow(row)
tableRows[i] = row
end
-- Row click: right = menu (Whisper), Shift + left = whisper at once. Whisper only to online players.
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
info.func = function() _G.ChatFrame_SendTell(Most.GameName(target)) end
_G.UIDropDownMenu_AddButton(info, level)
info = _G.UIDropDownMenu_CreateInfo()
info.text = menuMember.online and "Invite to group" or "Invite to group (offline)"
info.disabled = not menuMember.online
info.notCheckable = true
-- Newer clients have C_PartyInfo.InviteUnit, older only InviteUnit
info.func = function()
local invite = (_G.C_PartyInfo and _G.C_PartyInfo.InviteUnit) or _G.InviteUnit
if invite then invite(Most.GameName(target)) end
end
_G.UIDropDownMenu_AddButton(info, level)
-- Event sign-up list: an officer can remove the player from that event
if menuMember.event and addonTable.Events.CanManage(menuMember.event) then
local event = menuMember.event
info = _G.UIDropDownMenu_CreateInfo()
info.text, info.notCheckable = "|TInterface\\Buttons\\UI-GroupLoot-Pass-Up:14:14:0:0|t |cffff5555Remove from event|r", true
info.func = function() EventSync.Kick(event, target) end
_G.UIDropDownMenu_AddButton(info, level)
end
-- Their Discord name, when they shared one (discord.lua): a window to copy it
if addonTable.Discord.Get(target) then
info = _G.UIDropDownMenu_CreateInfo()
info.text, info.notCheckable = "Copy Discord name (" .. addonTable.Discord.Get(target) .. ")", true
info.func = function() addonTable.Discord.Copy(target) end
_G.UIDropDownMenu_AddButton(info, level)
end
-- Mute / Unmute as in the chat menu (permissions: mute.lua)
local muted, me = Mute.IsMuted(target), Most.MyName()
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
-- The same menu for a row of an event's sign-up list
membersView.OpenForEvent = function(name, online, event)
menuMember = { name = name, online = online, event = event }
_G.ToggleDropDownMenu(1, nil, MemberMenu, "cursor", 0, 0)
end
-- Shared with the "Online players" panel (the row has a member field from Roster.BuildList)
membersView.OnRowClick = function(self, button)
local m = self.member
if not m or m.name == Most.MyName() then return end
if button == "RightButton" then
menuMember = m
_G.ToggleDropDownMenu(1, nil, MemberMenu, "cursor", 0, 0)
elseif button == "LeftButton" and _G.IsShiftKeyDown() and m.online then
_G.ChatFrame_SendTell(Most.GameName(m.name))
end
end
for _, row in ipairs(tableRows) do
row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
row:SetScript("OnClick", membersView.OnRowClick)
end
end
-- Draws rows from a ready list (scrolling does not recompute the list)
-- Page bar under the table: "Showing 51-100 of 312 (48 online)   [<<] [<] Page 2 / 7 [>] [>>]"
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
-- Column widths from the longest text in the whole filtered list (not just this page, so columns do not
-- jump between pages), plus padding. Too narrow a window: less padding first, then Rank and Guild are cut.
-- Kept in membersView so these helpers do not use up the file's local variable limit.
membersView.textWidths = {}
membersView.measure = TableContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
membersView.measure:SetAlpha(0)
membersView.measure:SetPoint("TOPLEFT", TableContainer, "TOPLEFT", 0, 0)
function membersView.TextWidth(text)
local width = membersView.textWidths[text]
if not width then
membersView.measure:SetText(text)
width = membersView.measure:GetStringWidth()
if width > 0 then membersView.textWidths[text] = width end
end
return width
end
function membersView.LayoutColumns()
local PADDING, MIN_PADDING, ROW_INSET, FIRST_X = 16, 6, 5, 10
local TextWidth = membersView.TextWidth
local widths = {}
-- " ^" = room for the sort arrow in the header
for _, col in ipairs(columns) do widths[col.key] = TextWidth(col.name .. " ^") end
local function Fit(key, text, extra)
widths[key] = math.max(widths[key], TextWidth(text) + (extra or 0))
end
for _, p in ipairs(filteredPlayers) do
Fit("name", p.name, 25) -- room for the mute icon, plus 10 px so a long name does not touch the next column
Fit("level", tostring(p.level or ""))
Fit("class", LOCALIZED_CLASS_NAMES_MALE[p.class] or p.class or "Unknown", 18) -- room for the class icon
Fit("location", p.location or "-")
Fit("guild", p.guild or "No guild")
Fit("rank", GetColoredRank(p.rank))
Fit("version", p.version or "-")
end
local content = 0
for _, col in ipairs(columns) do content = content + widths[col.key] end
local room = TableContainer:GetWidth() - 25 - ROW_INSET - FIRST_X
local padding = math.max(MIN_PADDING, math.min(PADDING, math.floor((room - content) / (#columns - 1))))
local over = content + padding * (#columns - 1) - room
-- Then text is cut, column by column down to a minimum, so the last columns never leave the table
for _, cut in ipairs({ { "location", 60 }, { "rank", 50 }, { "guild", 60 }, { "location", 40 }, { "name", 100 }, { "class", 60 }, { "guild", 40 }, { "rank", 36 } }) do
if over > 0 then
local take = math.min(over, math.max(0, widths[cut[1]] - cut[2]))
widths[cut[1]] = widths[cut[1]] - take
over = over - take
end
end
local x = FIRST_X
for _, col in ipairs(columns) do
col.x, col.width = x, widths[col.key]
col.header:SetSize(col.width, 18)
col.header:ClearAllPoints()
col.header:SetPoint("TOPLEFT", TableContainer, "TOPLEFT", x + ROW_INSET, -6)
col.header.text:SetWidth(col.width) col.header.text:SetJustifyH("LEFT") col.header.text:SetWordWrap(false)
for _, row in ipairs(tableRows) do
row[col.field]:ClearAllPoints()
-- center = the width of an icon centered in its column
row[col.field]:SetPoint("LEFT", row, "LEFT", x + (col.center and math.floor((col.width - col.center) / 2) or 0), 0)
end
x = x + col.width + padding
end
for _, row in ipairs(tableRows) do
-- Name and class are cut too (the name keeps room for the mute icon, the class for its icon)
row.nameText:SetWidth(math.max(20, widths.name - 25)) row.nameText:SetJustifyH("LEFT") row.nameText:SetWordWrap(false)
row.classText:SetWidth(math.max(20, widths.class - 18)) row.classText:SetJustifyH("LEFT") row.classText:SetWordWrap(false)
row.guildText:SetWidth(widths.guild) row.guildText:SetJustifyH("LEFT") row.guildText:SetWordWrap(false)
row.rankText:SetWidth(widths.rank)
row.locationBox:SetWidth(widths.location)
end
end
-- Professions of the players on the shown page (professions.lua): at once when the tab opens, otherwise
-- membersView.PAGE_SWITCH_DELAY after a page change, when the page buttons come back
membersView.profPageKey, membersView.profToken = nil, 0
-- Page buttons are grayed out and not clickable for PAGE_SWITCH_DELAY (1 s) after a page change, the same time
-- the professions request waits, so pages cannot be flipped faster than the requests
membersView.PAGE_SWITCH_DELAY, membersView.navLockedUntil = 1, 0
function membersView.UpdateNavButtons()
local pages = math.max(1, math.ceil(#filteredPlayers / MEMBERS_PER_PAGE))
local page, free = membersView.page, GetTime() >= membersView.navLockedUntil
PageNav.buttons[1]:SetEnabled(free and page > 1) PageNav.buttons[2]:SetEnabled(free and page > 1)
PageNav.buttons[3]:SetEnabled(free and page < pages) PageNav.buttons[4]:SetEnabled(free and page < pages)
end
function membersView.RequestPageProfessions(first, count)
local key = membersView.page .. "/" .. tostring(membersView.filterKey)
if key == membersView.profPageKey then return end
local delay = membersView.profPageKey == nil and 0 or membersView.PAGE_SWITCH_DELAY
membersView.profPageKey = key
membersView.profToken = membersView.profToken + 1
local token, names = membersView.profToken, {}
for i = first + 1, first + count do names[#names + 1] = filteredPlayers[i].name end
C_Timer.After(delay, function()
if token == membersView.profToken and Panels[2]:IsVisible() then addonTable.Professions.RequestNames(names) end
end)
end
local function RenderMainTable()
local total = #filteredPlayers
local pages = math.max(1, math.ceil(total / MEMBERS_PER_PAGE))
if membersView.page > pages then membersView.page = pages end
local page = membersView.page
local first = (page - 1) * MEMBERS_PER_PAGE
local count = math.min(MEMBERS_PER_PAGE, total - first)
PageNav.infoText:SetText(total == 0 and "No players" or ("Showing " .. (first + 1) .. "-" .. (first + count) .. " of " .. total .. " |cff00ff00(" .. (membersView.online or 0) .. " online)|r"))
PageNav.pageText:SetText("Page " .. page .. " / " .. pages)
membersView.UpdateNavButtons()
membersView.RequestPageProfessions(first, count)
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
-- Mute icon after the name (tooltip with the reason), see mute.lua
Mute.DecorateName(row, row.nameText, data.name)
row.classText:SetText(classColor and classColor:WrapTextInColorCode(LOCALIZED_CLASS_NAMES_MALE[data.class] or data.class) or "Unknown")
row.locationBox.location = data.location
row.locationText:SetText(data.location or "|cff808080-|r")
row.levelText:SetText(data.level) row.rankText:SetText(GetColoredRank(data.rank))
addonTable.Notes.UpdateRow(row, data)
addonTable.Professions.UpdateRow(row, data)
addonTable.Armory.UpdateRow(row, data)
-- Green = same version, red = older, yellow = newer than mine
-- No version = player without the addon (known only from a guild roster)
if data.version then
local vCmp = CompareVersions(data.version, ADDON_VERSION)
local vColor = (vCmp == 0) and "|cff00ff00" or ((vCmp < 0) and "|cffff5555" or "|cffffd100")
row.versionText:SetText(vColor .. data.version .. "|r")
else row.versionText:SetText("|cff808080-|r") end
-- Offline is grayed out
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
-- List recomputed (hundreds of people): only with the tab visible and at most once per 0.3 s,
-- even when many status packets / roster packets / search letters arrive at once
local mainTablePending = false
local function RebuildMainTable()
mainTablePending = false
if not Panels[2]:IsVisible() then return end
wipe(filteredPlayers)
local filterText = SearchEditBox:GetText():lower()
for _, player in ipairs(Roster.BuildList(ShowOfflineCheck:GetChecked())) do
if filterText == "" then table.insert(filteredPlayers, player)
else
if player.name:lower():find(filterText, 1, true) or (player.class and player.class:lower():find(filterText, 1, true)) or (player.location and player.location:lower():find(filterText, 1, true)) or (player.guild and player.guild:lower():find(filterText, 1, true)) or (player.rank and player.rank:lower():find(filterText, 1, true)) then
table.insert(filteredPlayers, player)
end
end
end
-- A new search / offline toggle = back to the first page (a regular refresh keeps the page)
local filterKey = filterText .. (ShowOfflineCheck:GetChecked() and "|1" or "|0")
if filterKey ~= membersView.filterKey then membersView.filterKey, membersView.page = filterKey, 1 end
local online = 0
for _, p in ipairs(filteredPlayers) do if p.online then online = online + 1 end end
membersView.online = online
-- With no column selected the order from Roster.BuildList stays (online, guild, name)
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
membersView.LayoutColumns()
RenderMainTable()
end
-- Page buttons: first, previous, next, last (scrolling returns to the top of the page)
for i, b in ipairs(PageNav.buttons) do
b:SetScript("OnClick", function()
local pages = math.max(1, math.ceil(#filteredPlayers / MEMBERS_PER_PAGE))
local target = ({ 1, membersView.page - 1, membersView.page + 1, pages })[i]
membersView.page = math.max(1, math.min(pages, target))
membersView.navLockedUntil = GetTime() + membersView.PAGE_SWITCH_DELAY
C_Timer.After(membersView.PAGE_SWITCH_DELAY, membersView.UpdateNavButtons)
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
if self:IsVisible() then membersView.LayoutColumns() RenderMainTable() end
end)
-- ============================================================================
-- 5. TAB 3: GUILDS PANEL
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
-- Cards in advance; as many show as fit the tab (GuildContainer.visibleRows)
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
card.icon:SetSize(26, 26)
card.icon:SetPoint("LEFT", card, "LEFT", 12, 0)
card.icon:SetTexture("Interface\\AddOns\\jagodka\\Media\\blueberry_one.tga")
card.nameText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
card.nameText:SetPoint("LEFT", card.icon, "RIGHT", 12, 0)
-- Columns start at a fixed distance from the right edge, so they line up between cards
card.activeText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
card.activeText:SetPoint("LEFT", card, "RIGHT", -280, 0)
card.inactiveText = card:CreateFontString(nil, "OVERLAY", "GameFontDisable")
card.inactiveText:SetPoint("LEFT", card, "RIGHT", -155, 0)
guildRows[i] = card
end
UpdateGuildTable = function()
local guildData, guildOrder = {}, {}
-- All whitelisted guilds are always visible; inactive ones (nobody with the addon online) are grayed out
for gName in pairs(AllowedGuilds) do
if not GuildsNotShown[gName] then guildData[gName] = Roster.GetGuildSummary(gName) table.insert(guildOrder, gName) end
end
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
-- The relay is a technical detail (shown in Monitoring), so it is not shown here
if stats.live then
card:SetAlpha(1)
card.nameText:SetText("|cffffffff" .. gName .. "|r")
card.activeText:SetText("|cff00ff00Online:|r " .. stats.online .. " / " .. stats.total)
card.inactiveText:SetText("|cff00ff00Active|r")
else
card:SetAlpha(0.45)
card.nameText:SetText("|cff808080" .. gName .. "|r")
card.activeText:SetText(stats.total > 0 and ("|cff808080Members:|r " .. stats.total) or "")
-- When data for this guild last arrived (from cache), or never
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
-- 6. TAB 4: EVENTS PANEL
-- ============================================================================
local ListContainer = CreateFrame("Frame", nil, Panels[4], "BackdropTemplate")
-- List: a table across the whole tab. Details: a separate window opened by clicking a row.
ListContainer:SetPoint("TOPLEFT", Panels[4], "TOPLEFT", 0, -72)
ListContainer:SetPoint("BOTTOMRIGHT", Panels[4], "BOTTOMRIGHT", 0, 30)
ApplyModernStyle(ListContainer)
local DetailsContainer = CreateFrame("Frame", "JagodkiEventDetails", Panels[4], "BackdropTemplate")
DetailsContainer:SetSize(560, 520)
DetailsContainer:SetPoint("CENTER", Panels[4], "CENTER", 0, 0)
DetailsContainer:SetFrameStrata("DIALOG")
DetailsContainer:SetClampedToScreen(true)
DetailsContainer:SetMovable(true)
DetailsContainer:EnableMouse(true)
DetailsContainer:RegisterForDrag("LeftButton")
DetailsContainer:SetScript("OnDragStart", DetailsContainer.StartMoving)
DetailsContainer:SetScript("OnDragStop", DetailsContainer.StopMovingOrSizing)
ApplyModernStyle(DetailsContainer)
DetailsContainer:SetBackdropColor(0.05, 0.05, 0.07, 0.98)
DetailsContainer:Hide()
-- Esc closes it, and closing (also with the tab) clears the selection
table.insert(_G.UISpecialFrames, "JagodkiEventDetails")
-- Hide(): when the tab or main window closes, the game would otherwise bring this window back with them
DetailsContainer:SetScript("OnHide", function(self) selectedEventIndex = nil self:Hide() end)
do
local CloseDetails = CreateFrame("Button", nil, DetailsContainer, "UIPanelCloseButton")
CloseDetails:SetPoint("TOPRIGHT", DetailsContainer, "TOPRIGHT", 0, 0)
addonTable.Help.Button(DetailsContainer, "events", 3, "Signing up"):SetPoint("RIGHT", CloseDetails, "LEFT", -2, 0)
end
local LHeader = Panels[4]:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LHeader:SetPoint("TOPLEFT", Panels[4], "TOPLEFT", 4, -14)
LHeader:SetText("Upcoming Events")
local DHeader = DetailsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
DHeader:SetPoint("TOPLEFT", DetailsContainer, "TOPLEFT", 15, -15)
local DDesc = DetailsContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
DDesc:SetPoint("TOPLEFT", DetailsContainer, "TOPLEFT", 15, -45)
DDesc:SetWidth(530)
DDesc:SetJustifyH("LEFT")
DDesc:SetSpacing(4)
DDesc:SetJustifyV("TOP")
-- A long description is cut so it does not push the sign-up list; the full text is in a hover tooltip
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
-- From under the counters down to a fixed line above the raid leader option: a short description
-- leaves no empty space, because the list takes it, and a long one cannot push into the buttons
RosterContainer:SetPoint("TOPLEFT", CounterFrame, "BOTTOMLEFT", 0, -5)
RosterContainer:SetPoint("BOTTOMRIGHT", DetailsContainer, "BOTTOMRIGHT", -15, 70)
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
rosterScrollFrame:SetPoint("TOPLEFT", RosterContainer, "TOPLEFT", 0, -22)
rosterScrollFrame:SetPoint("BOTTOMRIGHT", RosterContainer, "BOTTOMRIGHT", -25, 5)
-- Sign-up columns: x in the row, width and the header
local ROSTER_COLUMNS = {
{ field = "roleText", x = 0, width = 24, title = "" },
{ field = "text", x = 26, width = 105, title = "Name" },
{ field = "levelText", x = 134, width = 28, title = "Lvl" },
{ field = "specText", x = 165, width = 90, title = "Spec" },
{ field = "guildText", x = 258, width = 115, title = "Guild" },
{ field = "rankText", x = 376, width = 75, title = "Rank" },
{ field = "statusText", x = 454, width = 45, title = "Status" },
}
for _, col in ipairs(ROSTER_COLUMNS) do
local header = RosterContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
header:SetPoint("TOPLEFT", RosterContainer, "TOPLEFT", 10 + col.x, -6)
header:SetText(col.title)
end
-- Sign-up rows in advance; as many show as fit RosterContainer (visibleRows)
local ROSTER_ROW_HEIGHT, MAX_ROSTER_ROWS, rosterRows = 16, 45, {}
for i = 1, MAX_ROSTER_ROWS do
local row = CreateFrame("Frame", nil, RosterContainer)
row:SetSize(500, ROSTER_ROW_HEIGHT) row:SetPoint("TOPLEFT", RosterContainer, "TOPLEFT", 10, -22 - ((i-1) * ROSTER_ROW_HEIGHT))
for _, col in ipairs(ROSTER_COLUMNS) do
local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
text:SetPoint("LEFT", row, "LEFT", col.x, 0)
text:SetWidth(col.width) text:SetJustifyH("LEFT") text:SetWordWrap(false)
row[col.field] = text
end
-- Right click: the usual player menu, plus removal from the event for officers
row:EnableMouse(true)
row:SetScript("OnMouseUp", function(self, button)
local ev = selectedEventIndex and eventsList[selectedEventIndex]
if button == "RightButton" and ev and self.playerName then membersView.OpenForEvent(self.playerName, self.playerOnline, ev) end
end)
addonTable.Discord.AttachRow(row)
rosterRows[i] = row
end
UpdateRosterList = function()
if not selectedEventIndex or not eventsList[selectedEventIndex] then return end
local ev = eventsList[selectedEventIndex]
-- Everything known about players: online list and guild rosters, the same data as the Members tab
local known = {}
for _, member in ipairs(Roster.BuildList(true)) do known[member.name] = member end
local displayList = {}
-- Everyone with a status: Coming and Maybe by role, Not coming only under "All"
local ORDER = { Y = 1, M = 2, N = 3 }
for name, st in pairs(ev.status or {}) do
local role = ev.roster[name]
if currentRosterFilter == "ALL" or (role and role == currentRosterFilter) then
table.insert(displayList, { name = name, role = role, st = st, spec = EventSync.SPECS[ev.specs and ev.specs[name] or ""], info = known[name] or {} })
end
end
-- Raid leaders first, then Coming, Maybe, Not coming, then by name
local leaders = ev.leaders or {}
table.sort(displayList, function(a, b)
local la, lb = leaders[a.name] and true or false, leaders[b.name] and true or false
if la ~= lb then return la end
if a.st ~= b.st then return (ORDER[a.st] or 9) < (ORDER[b.st] or 9) end
return a.name < b.name
end)
local visible = RosterContainer.visibleRows or 11
_G.FauxScrollFrame_Update(rosterScrollFrame, #displayList, visible, ROSTER_ROW_HEIGHT)
local offset = _G.FauxScrollFrame_GetOffset(rosterScrollFrame)
for i = 1, MAX_ROSTER_ROWS do
local idx = i + offset local row = rosterRows[i]
if i <= visible and idx <= #displayList then
local data = displayList[idx]
row.playerName, row.playerOnline = data.name, data.info.online
local mark = (data.st == "M") and " |cffffd100(maybe)|r" or ((data.st == "N") and " |cff808080(not coming)|r" or "")
row.text:SetText((leaders[data.name] and "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:12:12|t " or "") .. (data.st == "N" and ("|cff808080" .. data.name .. "|r") or GetColoredName(data.name)) .. mark)
if data.st == "N" then row.roleText:SetText("|cff808080[-]|r")
elseif data.role == "TANK" then row.roleText:SetText("|cff00ccff[T]|r")
elseif data.role == "HEAL" then row.roleText:SetText("|cff00ff00[H]|r")
else row.roleText:SetText("|cffff4500[D]|r") end
row.levelText:SetText(data.info.level or "-")
row.specText:SetText(data.spec and data.spec.name or "|cff808080-|r")
row.guildText:SetText(data.info.guild and ("|cffbf40ff" .. data.info.guild .. "|r") or "|cff808080-|r")
row.rankText:SetText(data.info.rank and GetColoredRank(data.info.rank) or "|cff808080-|r")
row.statusText:SetText(data.info.online and "|cff00ff00Online|r" or "|cff808080Offline|r")
row:Show()
else
row:Hide()
end
end
end
rosterScrollFrame:SetScript("OnVerticalScroll", function(self, offset) _G.FauxScrollFrame_OnVerticalScroll(self, offset, ROSTER_ROW_HEIGHT, UpdateRosterList) end)
RosterContainer:SetScript("OnSizeChanged", function(self)
self.visibleRows = MainFrame.FitRows(self, 22, 5, ROSTER_ROW_HEIGHT, MAX_ROSTER_ROWS, 10)
if self:IsVisible() then UpdateRosterList() end
end)
-- One sign-up button per spec of my class (up to 4: Druid)
EventSync.specButtons = {}
for i = 1, 4 do
local join = CreateFrame("Button", nil, DetailsContainer, "GameMenuButtonTemplate")
join:SetSize(90, 24)
join:SetPoint("BOTTOMLEFT", DetailsContainer, "BOTTOMLEFT", 10 + (i - 1) * 93, 15)
join:SetScript("OnClick", function(self)
local ev = selectedEventIndex and eventsList[selectedEventIndex]
if ev then EventSync.SignUp(ev, self.spec) end
end)
join:Hide()
EventSync.specButtons[i] = join
end
-- "I am the raid leader": your own mark, can be taken off at any time; needs a sign-up
EventSync.leaderCheck = CreateFrame("CheckButton", nil, DetailsContainer, "UICheckButtonTemplate")
EventSync.leaderCheck:SetSize(22, 22)
EventSync.leaderCheck:SetPoint("BOTTOMLEFT", DetailsContainer, "BOTTOMLEFT", 10, 42)
EventSync.leaderCheck.label = EventSync.leaderCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
EventSync.leaderCheck.label:SetPoint("LEFT", EventSync.leaderCheck, "RIGHT", 2, 0)
EventSync.leaderCheck.label:SetText("|TInterface\\GroupFrame\\UI-Group-LeaderIcon:12:12|t I am the raid leader")
EventSync.leaderCheck:SetScript("OnClick", function(self)
local ev = selectedEventIndex and eventsList[selectedEventIndex]
if ev then EventSync.SetLeader(ev, self:GetChecked() and true or false) end
end)
-- "Maybe": my sign-up as tentative (status M); unchecked = Coming
EventSync.maybeCheck = CreateFrame("CheckButton", nil, DetailsContainer, "UICheckButtonTemplate")
EventSync.maybeCheck:SetSize(22, 22)
EventSync.maybeCheck:SetPoint("LEFT", EventSync.leaderCheck.label, "RIGHT", 18, 0)
EventSync.maybeCheck.label = EventSync.maybeCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
EventSync.maybeCheck.label:SetPoint("LEFT", EventSync.maybeCheck, "RIGHT", 2, 0)
EventSync.maybeCheck.label:SetText("Maybe")
EventSync.maybeCheck:SetScript("OnClick", function(self)
local ev = selectedEventIndex and eventsList[selectedEventIndex]
if ev then EventSync.SetStatus(ev, self:GetChecked() and "M" or "Y") end
end)
-- "Not coming" and "Withdraw": the organizer sees who will not come; withdraw removes the sign-up
do
local notComing = CreateFrame("Button", nil, DetailsContainer, "UIPanelButtonTemplate")
notComing:SetSize(90, 20)
notComing:SetPoint("LEFT", EventSync.maybeCheck.label, "RIGHT", 18, 0)
notComing:SetText("Not coming")
notComing:SetScript("OnClick", function()
local ev = selectedEventIndex and eventsList[selectedEventIndex]
if ev then EventSync.SetStatus(ev, "N") end
end)
local withdraw = CreateFrame("Button", nil, DetailsContainer, "UIPanelButtonTemplate")
withdraw:SetSize(94, 20)
withdraw:SetPoint("LEFT", notComing, "RIGHT", 4, 0)
withdraw:SetText("|TInterface\\Buttons\\UI-GroupLoot-Pass-Up:14:14:0:0|t Withdraw")
withdraw:SetScript("OnClick", function()
local ev = selectedEventIndex and eventsList[selectedEventIndex]
if ev then EventSync.SetStatus(ev, "X") end
end)
end
local EditEventBtn = CreateFrame("Button", nil, DetailsContainer, "GameMenuButtonTemplate")
EditEventBtn:SetSize(60, 24) EditEventBtn:SetText("Edit") EditEventBtn:Hide()
local RemoveEventBtn = CreateFrame("Button", nil, DetailsContainer, "GameMenuButtonTemplate")
-- Removing buttons: white text with a red X (red text on the red button was hard to read)
RemoveEventBtn:SetSize(90, 24) RemoveEventBtn:SetPoint("BOTTOMRIGHT", DetailsContainer, "BOTTOMRIGHT", -10, 15) RemoveEventBtn:SetText("|TInterface\\Buttons\\UI-GroupLoot-Pass-Up:14:14:0:0|t |cffffffffCancel|r") RemoveEventBtn:Hide()
EditEventBtn:SetPoint("RIGHT", RemoveEventBtn, "LEFT", -4, 0)
local function UpdateFilterVisuals()
for fType, btn in pairs(filterButtons) do
if fType == currentRosterFilter then btn.text:SetTextColor(1, 0.82, 0) else btn.text:SetTextColor(0.6, 0.6, 0.6) end
end
if UpdateRosterList then UpdateRosterList() end
end
UpdateEventDetails = function()
if not selectedEventIndex or not eventsList[selectedEventIndex] then
DetailsContainer:Hide() return
end
DetailsContainer:Show()
local ev = eventsList[selectedEventIndex] DHeader:SetText(ev.title)
local guildStr = ev.guild and (" |cffbf40ff(" .. ev.guild .. ")|r") or ""
local dungeonStr = (ev.dungeon and ev.dungeon ~= "") and ("\n|cffffffffInstance:|r |cffffd100" .. ev.dungeon .. "|r") or ""
DDesc:SetText("|cffffffffAuthor:|r " .. ev.creator .. guildStr .. "  |cffffffffTime:|r " .. ev.date .. " " .. ev.time .. dungeonStr .. "\n|cffdecda5Description:|r " .. (ev.desc or ""))
-- As tall as the text, up to 7 lines (the rest is cut and shown in the tooltip); the list takes what is left
DDesc:SetHeight(0)
DDesc:SetHeight(math.min(DDesc:GetStringHeight(), 115))
local t, h, d, total = 0, 0, 0, 0
for _, role in pairs(ev.roster) do total = total + 1 if role == "TANK" then t = t + 1 elseif role == "HEAL" then h = h + 1 else d = d + 1 end end
TankCountText:SetText(t) HealCountText:SetText(h) DpsCountText:SetText(d) TotalCountVal:SetText("|cffffd100" .. total .. "|r")
CounterFrame:Show() RosterContainer:Show() UpdateFilterVisuals()
-- Sign-up buttons: all specs of my class, the one I chose in green
local mySpecs = EventSync.CLASS_SPECS[select(2, UnitClass("player"))] or {}
local myName = Most.MyName()
local myCode = ev.roster[myName] and ev.specs and ev.specs[myName]
for i, join in ipairs(EventSync.specButtons) do
local spec = mySpecs[i]
join.spec = spec
if spec then
join:SetText(myCode == spec.code and ("|cff00ff00" .. spec.name .. "|r") or spec.name)
join:Show()
else
join:Hide()
end
end
EventSync.leaderCheck:SetChecked(ev.leaders and ev.leaders[myName] and true or false)
if ev.roster[myName] then EventSync.leaderCheck:Enable() else EventSync.leaderCheck:Disable() end
EventSync.leaderCheck.label:SetAlpha(ev.roster[myName] and 1 or 0.45)
-- Edit and cancel: the author and officers (events.lua checks it again, as does every receiver)
if addonTable.Events.CanManage(ev) then EditEventBtn:Show() RemoveEventBtn:Show() else EditEventBtn:Hide() RemoveEventBtn:Hide() end
EventSync.UpdateLockButtons()
-- My status: Maybe, and the start time with the event's end
local myStatus = ev.status and ev.status[myName]
EventSync.maybeCheck:SetChecked(myStatus == "M")
if ev.roster[myName] then EventSync.maybeCheck:Enable() else EventSync.maybeCheck:Disable() end
EventSync.maybeCheck.label:SetAlpha(ev.roster[myName] and 1 or 0.45)
end
-- Events table, in a block so its helpers do not stay in the file's local variable limit.
-- Rows show a sorted copy; row.dataIndex is the event's place in eventsList, which sync and the calendar use.
do
local EV_ROW_HEIGHT, MAX_EV_ROWS, eventRows = 22, 24, {}
local EV_PADDING, EV_MIN_PADDING, EV_ROW_INSET, EV_FIRST_X = 16, 6, 5, 10
local eventColumns = {
{ name = "Date", key = "date", field = "dateText" },
{ name = "Time", key = "time", field = "timeText" },
{ name = "Type", key = "type", field = "typeText" },
{ name = "Event", key = "title", field = "titleText" },
{ name = "Instance", key = "dungeon", field = "dungeonText" },
{ name = "Guild", key = "guild", field = "guildText" },
{ name = "By", key = "creator", field = "creatorText" },
{ name = "Signed", key = "signed", field = "signedText" },
{ name = "You", key = "sign", field = "signBtn", icon = true, noSort = true },
{ name = "Invite", key = "invite", field = "inviteBtn", icon = true, noSort = true },
}
-- Sign-up menu on the row's icon: the specs of my class, the current one checked
local SignMenu = CreateFrame("Frame", "JagodkiSignMenu", UIParent, "UIDropDownMenuTemplate")
EventSync.SignMenu = SignMenu
_G.UIDropDownMenu_Initialize(SignMenu, function(self, level)
local ev = SignMenu.event
if not ev then return end
local info = _G.UIDropDownMenu_CreateInfo()
info.text, info.isTitle, info.notCheckable = ev.title, true, true
_G.UIDropDownMenu_AddButton(info, level)
local myName = Most.MyName()
for _, spec in ipairs(EventSync.CLASS_SPECS[select(2, UnitClass("player"))] or {}) do
info = _G.UIDropDownMenu_CreateInfo()
info.text = spec.name .. " (" .. spec.role .. ")"
info.checked = ev.specs and ev.roster[myName] and ev.specs[myName] == spec.code
info.func = function() EventSync.SignUp(ev, spec) end
_G.UIDropDownMenu_AddButton(info, level)
end
-- Raid leader mark: your own, needs a sign-up
info = _G.UIDropDownMenu_CreateInfo()
info.text = "I am the raid leader"
info.isNotRadio = true
info.checked = ev.leaders and ev.leaders[myName] and true or false
info.disabled = not ev.roster[myName]
info.func = function() EventSync.SetLeader(ev, not (ev.leaders and ev.leaders[myName])) end
_G.UIDropDownMenu_AddButton(info, level)
-- Status: Maybe (needs a spec), Not coming, and withdrawing the sign-up
local st = ev.status and ev.status[myName]
info = _G.UIDropDownMenu_CreateInfo()
info.text, info.isNotRadio, info.checked, info.disabled = "Maybe", true, st == "M", not ev.roster[myName]
info.func = function() EventSync.SetStatus(ev, st == "M" and "Y" or "M") end
_G.UIDropDownMenu_AddButton(info, level)
info = _G.UIDropDownMenu_CreateInfo()
info.text, info.checked = "Not coming", st == "N"
info.func = function() EventSync.SetStatus(ev, "N") end
_G.UIDropDownMenu_AddButton(info, level)
if st then
info = _G.UIDropDownMenu_CreateInfo()
info.text, info.notCheckable = "|TInterface\\Buttons\\UI-GroupLoot-Pass-Up:14:14:0:0|t |cffff5555Withdraw my sign-up|r", true
info.func = function() EventSync.SetStatus(ev, "X") end
_G.UIDropDownMenu_AddButton(info, level)
end
end, "MENU")
-- Default: nearest date first. Header click = ascending, second = descending, third = default.
-- Paging and search as in the Members tab: EVENTS_PER_PAGE events per page, scrolling within the page.
local EVENTS_PER_PAGE = 50
local eventsView = { sortKey = nil, desc = false, page = 1 }
local EventSearch = CreateFrame("EditBox", "JagodkiEventSearchBox", Panels[4], "InputBoxTemplate")
EventSearch:SetSize(195, 26)
-- Under "Upcoming Events", 10 px below it
EventSearch:SetPoint("TOPLEFT", LHeader, "BOTTOMLEFT", 62, -10)
EventSearch:SetAutoFocus(false)
EventSearch:SetFontObject(ChatFontNormal)
EventSearch.label = Panels[4]:CreateFontString(nil, "OVERLAY", "GameFontNormal")
EventSearch.label:SetPoint("RIGHT", EventSearch, "LEFT", -8, 0)
EventSearch.label:SetText("Search:")
EventSearch.Instructions = EventSearch:CreateFontString(nil, "ARTWORK", "GameFontDisable")
EventSearch.Instructions:SetPoint("LEFT", EventSearch, "LEFT", 5, 0)
EventSearch.Instructions:SetText("Event, instance, player...")
EventSearch:SetScript("OnTextChanged", function(self)
if self:GetText() == "" then self.Instructions:Show() else self.Instructions:Hide() end
UpdateEventsList()
end)
EventSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
-- Reset: clears the search, restores the default sorting and page 1 (as in Members)
local EventReset = CreateFrame("Button", nil, Panels[4], "UIPanelButtonTemplate")
EventReset:SetSize(55, 22)
EventReset:SetPoint("LEFT", EventSearch, "RIGHT", 8, 0)
EventReset:SetText("Reset")
-- Page bar under the list: "Showing 51-100 of 120   [<<] [<] Page 2 / 3 [>] [>>]"
local EventPageNav = CreateFrame("Frame", nil, Panels[4])
EventPageNav:SetHeight(26)
EventPageNav:SetPoint("TOPLEFT", ListContainer, "BOTTOMLEFT", 0, -4)
EventPageNav:SetPoint("TOPRIGHT", ListContainer, "BOTTOMRIGHT", 0, -4)
EventPageNav.infoText = EventPageNav:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
EventPageNav.infoText:SetPoint("LEFT", EventPageNav, "LEFT", 8, 0)
EventPageNav.pageText = EventPageNav:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
EventPageNav.pageText:SetWidth(90)
EventPageNav.buttons = {}
for i, label in ipairs({ "<<", "<", ">", ">>" }) do
local b = CreateFrame("Button", nil, EventPageNav, "UIPanelButtonTemplate")
b:SetSize(30, 20)
b:SetText(label)
EventPageNav.buttons[i] = b
end
EventPageNav.buttons[4]:SetPoint("RIGHT", EventPageNav, "RIGHT", -4, 0)
EventPageNav.buttons[3]:SetPoint("RIGHT", EventPageNav.buttons[4], "LEFT", -2, 0)
EventPageNav.pageText:SetPoint("RIGHT", EventPageNav.buttons[3], "LEFT", -4, 0)
EventPageNav.buttons[2]:SetPoint("RIGHT", EventPageNav.pageText, "LEFT", -4, 0)
EventPageNav.buttons[1]:SetPoint("RIGHT", EventPageNav.buttons[2], "LEFT", -2, 0)
local eventScrollFrame = CreateFrame("ScrollFrame", "JagodkiEventScrollFrame", ListContainer, "FauxScrollFrameTemplate")
eventScrollFrame:SetPoint("TOPLEFT", ListContainer, "TOPLEFT", 0, -30)
eventScrollFrame:SetPoint("BOTTOMRIGHT", ListContainer, "BOTTOMRIGHT", -26, 6)
local NoEventsText = ListContainer:CreateFontString(nil, "OVERLAY", "GameFontDisable")
NoEventsText:SetPoint("CENTER", ListContainer, "CENTER", 0, 0)
NoEventsText:SetText("No upcoming events")
-- Rows in advance; as many show as fit ListContainer (visibleRows)
for i = 1, MAX_EV_ROWS do
local row = CreateFrame("Button", nil, ListContainer)
row:SetHeight(EV_ROW_HEIGHT)
row:SetPoint("TOPLEFT", ListContainer, "TOPLEFT", EV_ROW_INSET, -30 - ((i-1) * EV_ROW_HEIGHT))
row:SetPoint("RIGHT", ListContainer, "RIGHT", -25, 0)
local tex = row:CreateTexture(nil, "BACKGROUND")
tex:SetAllPoints()
tex:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.02 or 0.04)
row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
for _, col in ipairs(eventColumns) do
if not col.icon then
local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
text:SetJustifyH("LEFT") text:SetWordWrap(false)
row[col.field] = text
end
end
row:SetScript("OnClick", function(self) selectedEventIndex = self.dataIndex UpdateEventDetails() end)
-- Sign-up button: "Sign up", or the current spec in green; a click opens the spec menu
local signBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
signBtn:SetHeight(EV_ROW_HEIGHT - 3)
signBtn:SetNormalFontObject("GameFontNormalSmall")
signBtn:SetHighlightFontObject("GameFontHighlightSmall")
signBtn:SetScript("OnClick", function(self)
SignMenu.event = self.event
_G.ToggleDropDownMenu(1, nil, SignMenu, "cursor", 0, 0)
end)
row.signBtn = signBtn
-- Invite all: only for officers and this event's raid leaders
local inviteBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
inviteBtn:SetHeight(EV_ROW_HEIGHT - 3)
inviteBtn:SetNormalFontObject("GameFontNormalSmall")
inviteBtn:SetHighlightFontObject("GameFontHighlightSmall")
inviteBtn:SetDisabledFontObject("GameFontDisableSmall")
inviteBtn:SetText("Invite all")
inviteBtn:SetScript("OnClick", function(self) EventSync.InviteAll(self.event) end)
row.inviteBtn = inviteBtn
eventRows[i] = row
end
local function SignedCounts(ev)
local t, h, d = 0, 0, 0
for _, role in pairs(ev.roster or {}) do
if role == "TANK" then t = t + 1 elseif role == "HEAL" then h = h + 1 else d = d + 1 end
end
return t, h, d
end
local function CellText(ev, key)
-- PVE / PVP from the chosen instance (instances.lua), "-" for none / other
if key == "type" then return addonTable.InstanceType(ev.dungeon) end
if key == "signed" then
local t, h, d = SignedCounts(ev)
return (t + h + d) .. " (" .. t .. "/" .. h .. "/" .. d .. ")"
end
-- The date without the year, so the table fits the window (the guild keeps its full name)
if key == "date" then return ((ev.date or "-"):gsub("^(%d+%.%d+)%.%d+$", "%1")) end
return ev[key] or "-"
end
-- Date and time of an event for sorting
local function EventMoment(ev)
local hour, minute = (ev.time or ""):match("^(%d+):(%d+)$")
return (EventSync.DayTime(ev.date) or 0) + (tonumber(hour) or 0) * 3600 + (tonumber(minute) or 0) * 60
end
-- Search: title, instance, guild, creator, date, or a signed-up player's name
local function MatchesSearch(ev, text)
if text == "" then return true end
for _, value in ipairs({ ev.title, ev.dungeon, ev.guild, ev.creator, ev.date }) do
if value and tostring(value):lower():find(text, 1, true) then return true end
end
for name in pairs(ev.roster or {}) do
if name:lower():find(text, 1, true) then return true end
end
return false
end
-- The Calendar's search finds the same (BuildCalendar)
EventSync.MatchesSearch = MatchesSearch
local function SortedEvents()
local list = {}
local text = EventSearch:GetText():lower()
-- A new search = back to the first page (a regular refresh keeps the page)
if text ~= eventsView.filterKey then eventsView.filterKey, eventsView.page = text, 1 end
for idx, ev in ipairs(eventsList) do
if MatchesSearch(ev, text) then table.insert(list, { ev = ev, idx = idx, moment = EventMoment(ev) }) end
end
local key, desc = eventsView.sortKey, eventsView.desc
table.sort(list, function(a, b)
local va, vb = a.moment, b.moment
if key == "signed" then
local at, ah, ad = SignedCounts(a.ev)
local bt, bh, bd = SignedCounts(b.ev)
va, vb = at + ah + ad, bt + bh + bd
elseif key == "type" then
va, vb = addonTable.InstanceType(a.ev.dungeon), addonTable.InstanceType(b.ev.dungeon)
elseif key and key ~= "date" and key ~= "time" then
va, vb = tostring(a.ev[key] or ""):lower(), tostring(b.ev[key] or ""):lower()
end
if va ~= vb then if desc then return va > vb end return va < vb end
if a.moment ~= b.moment then return a.moment < b.moment end
return a.idx < b.idx
end)
return list
end
local function UpdateEventHeaders()
for _, col in ipairs(eventColumns) do
local active = eventsView.sortKey == col.key
col.header.text:SetText(col.name .. (active and (eventsView.desc and " v" or " ^") or ""))
if active then col.header.text:SetTextColor(1, 1, 1) else col.header.text:SetTextColor(1, 0.82, 0) end
end
end
for _, col in ipairs(eventColumns) do
local h = CreateFrame("Button", nil, ListContainer)
h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
h.text:SetPoint("LEFT", h, "LEFT", 0, 0)
h:SetScript("OnClick", function()
if col.noSort then return end
if eventsView.sortKey ~= col.key then eventsView.sortKey, eventsView.desc = col.key, false
elseif not eventsView.desc then eventsView.desc = true
else eventsView.sortKey, eventsView.desc = nil, false end
eventsView.page = 1
UpdateEventHeaders()
UpdateEventsList()
end)
col.header = h
end
UpdateEventHeaders()
EventReset:SetScript("OnClick", function()
EventSearch:SetText("")
EventSearch:ClearFocus()
eventsView.sortKey, eventsView.desc, eventsView.page = nil, false, 1
UpdateEventHeaders()
UpdateEventsList()
end)
-- Each column fits its longest text. The two button columns are fixed; when the window is narrow, the
-- padding goes first, then the text columns are cut down to a minimum, then the sign-up button is narrowed,
-- so nothing ever reaches past the table (it overlapped the right column before).
local MIN_WIDTH = { title = 50, dungeon = 40, creator = 40, guild = 60, signed = 40, date = 34, time = 30, type = 26 }
local function LayoutEventColumns()
local TextWidth = membersView.TextWidth
local widths, content = {}, 0
for _, col in ipairs(eventColumns) do
local width = TextWidth(col.name .. " ^")
if col.key == "invite" then
width = TextWidth("Invite all") + 16
elseif col.icon then
-- Room for the longest text the button can show, plus its edges, at most 100
width = math.max(width, TextWidth("Sign up") + 20)
for _, spec in ipairs(EventSync.CLASS_SPECS[select(2, UnitClass("player"))] or {}) do width = math.max(width, TextWidth(spec.name .. " v") + 20) end
width = math.min(width, 100)
else
for _, ev in ipairs(eventsList) do width = math.max(width, TextWidth(CellText(ev, col.key))) end
end
widths[col.key] = width
content = content + width
end
local room = ListContainer:GetWidth() - 25 - EV_ROW_INSET - EV_FIRST_X
local gaps = #eventColumns - 1
local padding = math.max(EV_MIN_PADDING, math.min(EV_PADDING, math.floor((room - content) / gaps)))
local over = content + padding * gaps - room
-- The guild is cut last: its full name matters more than a long title or instance
for _, key in ipairs({ "title", "dungeon", "creator", "signed", "date", "time", "type", "guild" }) do
if over > 0 then
local take = math.min(over, math.max(0, widths[key] - MIN_WIDTH[key]))
widths[key] = widths[key] - take
over = over - take
end
end
if over > 0 then
local take = math.min(over, math.max(0, widths.sign - 50))
widths.sign = widths.sign - take
end
local x = EV_FIRST_X
for _, col in ipairs(eventColumns) do
local width = widths[col.key]
col.header:SetSize(width, 18)
col.header:ClearAllPoints()
col.header:SetPoint("TOPLEFT", ListContainer, "TOPLEFT", x + EV_ROW_INSET, -6)
-- A cut header ends with "..." instead of running into the next one
col.header.text:SetWidth(width) col.header.text:SetJustifyH("LEFT") col.header.text:SetWordWrap(false)
for _, row in ipairs(eventRows) do
local cell = row[col.field]
cell:ClearAllPoints()
cell:SetPoint("LEFT", row, "LEFT", x, 0)
cell:SetWidth(width)
-- A button's text is cut to the button too
if col.icon and cell.GetFontString and cell:GetFontString() then
local label = cell:GetFontString()
label:SetWidth(width - 10) label:SetWordWrap(false)
end
end
x = x + width + padding
end
end
UpdateEventsList = function()
LayoutEventColumns()
local list = SortedEvents()
local total = #list
local pages = math.max(1, math.ceil(total / EVENTS_PER_PAGE))
if eventsView.page > pages then eventsView.page = pages end
local page = eventsView.page
local first = (page - 1) * EVENTS_PER_PAGE
local count = math.min(EVENTS_PER_PAGE, total - first)
-- The same format as in Members, also shown with no events
EventPageNav.infoText:SetText(total == 0 and "Showing 0 of 0" or ("Showing " .. (first + 1) .. "-" .. (first + count) .. " of " .. total))
EventPageNav.pageText:SetText("Page " .. page .. " / " .. pages)
EventPageNav.buttons[1]:SetEnabled(page > 1) EventPageNav.buttons[2]:SetEnabled(page > 1)
EventPageNav.buttons[3]:SetEnabled(page < pages) EventPageNav.buttons[4]:SetEnabled(page < pages)
local visible = ListContainer.visibleRows or 16
_G.FauxScrollFrame_Update(eventScrollFrame, count, visible, EV_ROW_HEIGHT)
local offset = _G.FauxScrollFrame_GetOffset(eventScrollFrame)
local myName = Most.MyName()
NoEventsText:SetText(#eventsList == 0 and "No upcoming events" or "No events match the search")
if total == 0 then NoEventsText:Show() else NoEventsText:Hide() end
for i = 1, MAX_EV_ROWS do
local item = (i + offset <= count) and list[first + i + offset] local row = eventRows[i]
if i <= visible and item then
local ev = item.ev
row.dataIndex = item.idx
for _, col in ipairs(eventColumns) do
if not col.icon then row[col.field]:SetText(CellText(ev, col.key)) end
end
row.signBtn.event = ev
row.inviteBtn.event = ev
if EventSync.CanInvite(ev) then
-- Inactive when there is nobody but me to invite
local others = false
for name in pairs(ev.roster or {}) do if name ~= myName then others = true break end end
row.inviteBtn:SetEnabled(others)
row.inviteBtn:Show()
else
row.inviteBtn:Hide()
end
local myRole = ev.roster and ev.roster[myName]
if myRole then
-- A sign-up from before 0.9.1 has only a role, until the player picks a spec
local spec = EventSync.SPECS[ev.specs and ev.specs[myName] or ""]
local label = spec and spec.name or ({ TANK = "Tank", HEAL = "Heal", DPS = "DPS" })[myRole] or myRole
row.signBtn:SetText("|cff00ff00" .. label .. " v|r")
else
row.signBtn:SetText("Sign up")
end
-- Events I signed up for are green, as in the calendar
if ev.roster and ev.roster[myName] then row.titleText:SetText("|cff00ff00" .. ev.title .. "|r") end
if ev.guild then row.guildText:SetText("|cffbf40ff" .. ev.guild .. "|r") end
row:Show()
else row:Hide() end
end
-- The calendar shows the same events (it refreshes only when visible), and so does the side panel
UpdateCalendar()
if EventSync.Side then EventSync.Side.Render() end
end
eventScrollFrame:SetScript("OnVerticalScroll", function(self, offset) _G.FauxScrollFrame_OnVerticalScroll(self, offset, EV_ROW_HEIGHT, UpdateEventsList) end)
-- Page buttons: first, previous, next, last (scrolling returns to the top of the page)
for i, b in ipairs(EventPageNav.buttons) do
b:SetScript("OnClick", function()
local pages = math.max(1, math.ceil(#SortedEvents() / EVENTS_PER_PAGE))
eventsView.page = math.max(1, math.min(pages, ({ 1, eventsView.page - 1, eventsView.page + 1, pages })[i]))
_G.FauxScrollFrame_SetOffset(eventScrollFrame, 0)
local bar = _G[eventScrollFrame:GetName() .. "ScrollBar"]
if bar then bar:SetValue(0) end
UpdateEventsList()
end)
end
ListContainer:SetScript("OnSizeChanged", function(self)
self.visibleRows = MainFrame.FitRows(self, 30, 6, EV_ROW_HEIGHT, MAX_EV_ROWS, 16)
if self:IsVisible() then UpdateEventsList() end
end)
end
local CreateEventBtn = CreateFrame("Button", nil, Panels[4], "GameMenuButtonTemplate")
CreateEventBtn:SetSize(110, 28) CreateEventBtn:SetPoint("TOPRIGHT", Panels[4], "TOPRIGHT", 0, -5) CreateEventBtn:SetText("Create Event")
-- "Sync": asks the guild for the events again (EventSync.Request, as after login); then grayed out with a
-- countdown for EventSync.BUTTON_COOLDOWN seconds, so it cannot be clicked into a flood of answers.
-- Also grayed out while a sync shown on the progress bar is going (after login, /jagodka sync, this button).
-- Checked 4 times a second, only while the button is visible (OnUpdate).
EventSync.BUTTON_COOLDOWN = 60
do
local SyncEventsBtn = CreateFrame("Button", nil, Panels[4], "GameMenuButtonTemplate")
SyncEventsBtn:SetSize(70, 28)
SyncEventsBtn:SetPoint("RIGHT", CreateEventBtn, "LEFT", -4, 0)
SyncEventsBtn:SetText("Sync")
if SyncEventsBtn.SetMotionScriptsWhileDisabled then SyncEventsBtn:SetMotionScriptsWhileDisabled(true) end
local readyAt, sinceCheck = 0, 1
local function Refresh(self)
local left = math.ceil(readyAt - GetTime())
if left > 0 then self:SetText("Sync (" .. left .. ")") self:Disable()
elseif addonTable.Sync.Running() then self:SetText("Sync") self:Disable()
else self:SetText("Sync") self:Enable() end
end
addonTable.SafeScript(SyncEventsBtn, "OnUpdate", "core.lua:1980", function(self, elapsed)
sinceCheck = sinceCheck + elapsed
if sinceCheck < 0.25 then return end
sinceCheck = 0
Refresh(self)
end)
SyncEventsBtn:SetScript("OnClick", function(self)
if GetTime() < readyAt or addonTable.Sync.Running() then return end
EventSync.Request(true)
readyAt = GetTime() + EventSync.BUTTON_COOLDOWN
Refresh(self)
end)
SyncEventsBtn:SetScript("OnEnter", function(self)
_G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
local busy = addonTable.Sync.Running() and "\n|cffff9933Sync in progress - available when it finishes.|r" or ""
_G.GameTooltip:SetText("Asks for the latest events and sign-ups, as after login.\nAt most every " .. EventSync.BUTTON_COOLDOWN .. " s." .. busy, 1, 1, 1, 1, true)
_G.GameTooltip:Show()
end)
SyncEventsBtn:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
addonTable.Help.Button(Panels[4], "events", nil, "Events"):SetPoint("RIGHT", SyncEventsBtn, "LEFT", -8, 0)
end
local CreatorFrame = CreateFrame("Frame", "JagodkiCreatorFrame", UIParent, "BackdropTemplate")
CreatorFrame:SetSize(320, 450) CreatorFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0) CreatorFrame:Hide()
-- Above the event details window (DIALOG), below dropdown lists (FULLSCREEN_DIALOG)
CreatorFrame:SetFrameStrata("FULLSCREEN")
CreatorFrame:SetFrameLevel(MainFrame:GetFrameLevel() + 20)
ApplyModernStyle(CreatorFrame) CreatorFrame:SetBackdropColor(0.05, 0.05, 0.07, 0.98)
CreatorFrame.TitleText = CreatorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
CreatorFrame.TitleText:SetPoint("TOP", CreatorFrame, "TOP", 0, -10) CreatorFrame.TitleText:SetText("New Event")
local TitleInput = CreateLabelAndInput(CreatorFrame, "Event Name:", -45, 275, 26)
-- DATE AND TIME FROM DROPDOWNS (instead of typing, so the format is always correct)
-- Selected values are kept in one table so they do not use up the file's local variable limit
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
-- Instance: "(none)" + a submenu per group from instances.lua (this game's list: Classic Era or WoW Forever).
-- An instance not open yet is grayed out, unless the event's date is its opening day or later.
_G.UIDropDownMenu_Initialize(DungeonDD, function(self, level, menuList)
if level == 1 then
local none = _G.UIDropDownMenu_CreateInfo()
none.text = "(none / other)"
none.checked = (EventPicker.dungeon == nil)
none.func = function() EventPicker.dungeon = nil _G.UIDropDownMenu_SetText(DungeonDD, "(none / other)") end
_G.UIDropDownMenu_AddButton(none, level)
for _, group in ipairs(addonTable.InstanceGroups()) do
local sub = _G.UIDropDownMenu_CreateInfo()
sub.text = group.group sub.hasArrow = true sub.notCheckable = true sub.menuList = group.list
_G.UIDropDownMenu_AddButton(sub, level)
end
return
end
local d, m, y = tostring(EventPicker.date or ""):match("^(%d+)%.(%d+)%.(%d+)$")
local eventDay = d and time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }) or time()
for _, inst in ipairs(menuList or {}) do
local info = _G.UIDropDownMenu_CreateInfo()
local closed = inst.opensAt and eventDay < inst.opensAt
info.text = inst.name .. " |cff808080(" .. inst.levels .. ")|r" .. (closed and (" |cff808080- from " .. date("%d.%m", inst.opensAt) .. "|r") or "")
info.disabled = closed
info.checked = (EventPicker.dungeon == inst.name)
info.func = function() EventPicker.dungeon = inst.name _G.UIDropDownMenu_SetText(DungeonDD, inst.name) _G.CloseDropDownMenus() end
_G.UIDropDownMenu_AddButton(info, level)
end
end)
-- Date: today + the next 3 weeks, with the day of the week
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
-- Default: today at 20:00 (set each time the window opens).
-- EventPicker.presetDay (time of a day, e.g. from a calendar click) = that day instead of today, once.
function EventPicker.Reset()
local day = EventPicker.presetDay or time()
EventPicker.presetDay = nil
EventPicker.date, EventPicker.hour, EventPicker.minute, EventPicker.dungeon = date("%d.%m.%Y", day), 20, 0, nil
_G.UIDropDownMenu_SetText(DungeonDD, "(none / other)")
_G.UIDropDownMenu_SetText(DateDD, DayLabel(day))
_G.UIDropDownMenu_SetText(HourDD, "20")
_G.UIDropDownMenu_SetText(MinuteDD, "00")
end
-- Fills the pickers with an existing event's values (editing)
function EventPicker.LoadEvent(ev)
local hour, minute = (ev.time or ""):match("^(%d+):(%d+)$")
EventPicker.date, EventPicker.hour, EventPicker.minute, EventPicker.dungeon = ev.date, tonumber(hour) or 20, tonumber(minute) or 0, ev.dungeon
_G.UIDropDownMenu_SetText(DungeonDD, ev.dungeon or "(none / other)")
local day = EventSync.DayTime(ev.date)
_G.UIDropDownMenu_SetText(DateDD, day and DayLabel(day) or ev.date)
_G.UIDropDownMenu_SetText(HourDD, string.format("%02d", EventPicker.hour))
_G.UIDropDownMenu_SetText(MinuteDD, string.format("%02d", EventPicker.minute))
end
end
-- X button and closing with Esc
local CreatorCloseBtn = CreateFrame("Button", nil, CreatorFrame, "UIPanelCloseButton")
CreatorCloseBtn:SetPoint("TOPRIGHT", CreatorFrame, "TOPRIGHT", -2, -2)
table.insert(_G.UISpecialFrames, "JagodkiCreatorFrame")
-- Closing the main window (X, Esc, /jagodka, minimap) closes every window and menu it opened: the event
-- creator (on UIParent, so it would stay), the event details and calendar day, open dropdown menus and
-- the addon's confirmations (mute reason, new chat key). The "addon outdated" window is not one of them.
MainFrame:HookScript("OnHide", function()
CreatorFrame:Hide()
if _G.JagodkiEventDetails then _G.JagodkiEventDetails:Hide() end
if _G.JagodkiCalendarDay then _G.JagodkiCalendarDay:Hide() end
_G.CloseDropDownMenus()
_G.StaticPopup_Hide("JAGODKA_MUTE_REASON")
_G.StaticPopup_Hide("JAGODKA_NEW_CHAT_KEY")
end)
CreatorFrame:SetScript("OnShow", function() EventPicker.Reset() end)
-- Closing the window ends editing, so the next opening creates a new event
CreatorFrame:SetScript("OnHide", function()
if EventPicker.editing then
EventPicker.editing = nil
EventPicker.ClearForm()
end
end)
-- Opens the create window with a preset date (calendar); if already open, only the date changes
function EventPicker.OpenFor(dayTime)
if addonTable.Sync.Blocked() then return end
-- An edit in progress ends here, so this cannot overwrite that event
if EventPicker.editing then CreatorFrame:Hide() end
EventPicker.presetDay = dayTime
if CreatorFrame:IsShown() then EventPicker.Reset() else CreatorFrame:Show() end
end
-- DESCRIPTION: multiline field with scrolling and a byte counter
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
-- Scrolling follows the cursor (Blizzard functions from UIPanelTemplates)
if _G.ScrollingEdit_OnCursorChanged then DescInput:SetScript("OnCursorChanged", _G.ScrollingEdit_OnCursorChanged) end
if _G.ScrollingEdit_OnUpdate then DescInput:SetScript("OnUpdate", function(self, elapsed) _G.ScrollingEdit_OnUpdate(self, elapsed, DescScroll) end) end
DescInput:SetScript("OnTextChanged", function(self) DescCounter:SetText(#self:GetText() .. "/" .. EVENT_DESC_MAX_BYTES) end)
DescCounter:SetText("0/" .. EVENT_DESC_MAX_BYTES)
-- A click anywhere in the frame puts the cursor in the description
DescBox:EnableMouse(true) DescBox:SetScript("OnMouseDown", function() DescInput:SetFocus() end)
end
-- Name limit, so the event header packet (EH, events.lua) fits
TitleInput:SetMaxBytes(50)
local SubmitBtn = CreateFrame("Button", nil, CreatorFrame, "GameMenuButtonTemplate")
SubmitBtn:SetSize(120, 30) SubmitBtn:SetPoint("BOTTOM", CreatorFrame, "BOTTOM", 0, 20) SubmitBtn:SetText("Create and Send")
-- Any member of a listed guild (events.lua: a member 1 upcoming event, an officer 5)
CreateEventBtn:SetScript("OnClick", function()
if addonTable.Sync.Blocked() then return end
local ok, why = addonTable.Events.CanCreate()
if ok then CreatorFrame:Show() else ShowEventError(why) end
end)
-- Officer buttons are gray until the first sync after login ends, with the reason on hover
function EventSync.UpdateLockButtons()
local locked = addonTable.Sync.LoginLocked()
CreateEventBtn:SetEnabled(IsPlayerGuildAllowed(Most.MyGuild()) and not locked)
EditEventBtn:SetEnabled(not locked)
RemoveEventBtn:SetEnabled(not locked)
end
for _, lockedBtn in ipairs({ CreateEventBtn, EditEventBtn, RemoveEventBtn }) do
lockedBtn:SetMotionScriptsWhileDisabled(true)
lockedBtn:HookScript("OnEnter", function(self)
if not addonTable.Sync.LoginLocked() then return end
_G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
_G.GameTooltip:SetText("Syncing - available in a moment", 1, 0.82, 0)
_G.GameTooltip:Show()
end)
lockedBtn:HookScript("OnLeave", function() _G.GameTooltip:Hide() end)
end
-- Runs for about the longest lock, then the buttons stay as they are
C_Timer.NewTicker(1, EventSync.UpdateLockButtons, 120)
-- Back to an empty "New Event" form
function EventPicker.ClearForm()
TitleInput:SetText("") DescInput:SetText("")
CreatorFrame.TitleText:SetText("New Event")
SubmitBtn:SetText("Create and Send")
end
-- Opens the same form for editing an event (officers)
function EventPicker.OpenEdit(ev)
if addonTable.Sync.Blocked() then return end
if not CreatorFrame:IsShown() then CreatorFrame:Show() end
EventPicker.editing = ev
EventPicker.LoadEvent(ev)
TitleInput:SetText(ev.title or "") DescInput:SetText(ev.desc or "")
CreatorFrame.TitleText:SetText("Edit Event")
SubmitBtn:SetText("Save Changes")
end
SubmitBtn:SetScript("OnClick", function()
local title, desc = TitleInput:GetText(), DescInput:GetText()
local eDate, eTime = EventPicker.date or "", string.format("%02d:%02d", EventPicker.hour, EventPicker.minute)
local myName, myGuild = Most.MyName(), GetGuildInfo("player")
-- No name but an instance is selected: name = instance
if title == "" and EventPicker.dungeon then title = EventPicker.dungeon end
local where = EventPicker.dungeon and (EventPicker.dungeon .. " ") or ""
local editing = EventPicker.editing
if editing then
local ok, why = addonTable.Events.Edit(editing, title, eDate, eTime, EventPicker.dungeon, desc)
if not ok then ShowEventError(why) return end
Most.PublishTyped("Ogolny", "Event edited by " .. myName .. " -> " .. title .. " : " .. where .. eDate .. " " .. eTime, myName, myGuild)
CreatorFrame:Hide()
UpdateEventsList()
if selectedEventIndex and eventsList[selectedEventIndex] == editing then UpdateEventDetails() end
return
end
local ok, why = addonTable.Events.Create(title, eDate, eTime, EventPicker.dungeon, desc)
if not ok then ShowEventError(why) return end
UpdateEventsList()
-- Announcement on the community chat channel as the creator's own message (straight from the click, which the
-- game requires), so every guild sees it at once; through the relays only when the channel is not available:
-- "Event created by Name -> Title : Instance 05.11 20:00"
Most.PublishTyped("Ogolny", "Event created by " .. myName .. " -> " .. title .. " : " .. where .. eDate .. " " .. eTime, myName, myGuild)
TitleInput:SetText("") DescInput:SetText("") CreatorFrame:Hide()
end)local function SetRosterFilter(filterType) currentRosterFilter = filterType UpdateFilterVisuals() end
BtnAll:SetScript("OnClick", function() SetRosterFilter("ALL") end)
BtnTank:SetScript("OnClick", function() SetRosterFilter("TANK") end)
BtnHeal:SetScript("OnClick", function() SetRosterFilter("HEAL") end)
BtnDps:SetScript("OnClick", function() SetRosterFilter("DPS") end)
-- Sign-ups and removals: events.lua checks and sends them; here the windows refresh
local function EventChanged(ok, why)
if not ok and why then ShowEventError(why) end
if selectedEventIndex and eventsList[selectedEventIndex] then UpdateEventDetails() end
UpdateEventsList()
end
-- Sign-up with any spec of my class (keeps my status; Coming when new)
function EventSync.SignUp(ev, spec)
if not ev or not spec then return end
EventChanged(addonTable.Events.Sign(ev, spec))
end
-- My status: Y Coming, M Maybe, N Not coming, X withdrawn
function EventSync.SetStatus(ev, status)
if not ev then return end
EventChanged(addonTable.Events.Sign(ev, nil, status))
end
-- Your own raid leader mark; several people can have it
function EventSync.SetLeader(ev, on)
if not ev or not ev.roster[Most.MyName()] then return end
EventChanged(addonTable.Events.Sign(ev, nil, nil, on and true or false))
end
-- The author or an officer takes a player off an event
function EventSync.Kick(ev, name)
if addonTable.Sync.Blocked() then return end
if not ev then return end
EventChanged(addonTable.Events.Kick(ev, name))
end
EditEventBtn:SetScript("OnClick", function()
local ev = selectedEventIndex and eventsList[selectedEventIndex]
if ev and addonTable.Events.CanManage(ev) then EventPicker.OpenEdit(ev) end
end)
RemoveEventBtn:SetScript("OnClick", function()
if addonTable.Sync.Blocked() then return end
if not selectedEventIndex or not eventsList[selectedEventIndex] then return end
local removedEv = eventsList[selectedEventIndex]
local ok, why = addonTable.Events.Cancel(removedEv)
if not ok then ShowEventError(why) return end
-- Announcement as when creating, on the chat channel straight from the click:
-- "Event cancelled by Name -> Title : Instance 05.11 20:00"
local myName = Most.MyName()
Most.PublishTyped("Ogolny", "Event cancelled by " .. myName .. " -> " .. removedEv.title .. " : " .. (removedEv.dungeon and (removedEv.dungeon .. " ") or "") .. removedEv.date .. " " .. removedEv.time, myName, (GetGuildInfo("player")))
selectedEventIndex = nil UpdateEventDetails() UpdateEventsList()
end)
-- ============================================================================
-- 6B. TAB 6: MONITORING (officers only, monitor.lua)
-- ============================================================================
addonTable.Monitor.Attach(Panels[6], { activePlayers = activePlayers, applyStyle = ApplyModernStyle })
-- Help tab (help.lua): officers' topics only for officers
addonTable.Help.Attach(Panels[7], { isOfficer = IsPlayerOfficer, applyStyle = ApplyModernStyle, showTab = function() ShowTab(7) end })
-- Settings tab (settings.lua)
addonTable.Settings.Attach(Panels[8], { applyStyle = ApplyModernStyle, isOfficer = IsPlayerOfficer })
-- Opens an event in the Events tab by its id ([Open event] links in whispers, lfg.lua); false when unknown here
function addonTable.OpenEvent(id)
for idx, ev in ipairs(eventsList) do
if ev.id == id then
MainFrame:Show()
ShowTab(4)
selectedEventIndex = idx
UpdateEventDetails()
-- From an invitation and not signed up yet: the spec menu opens at once (a sign-up always needs a spec)
local start = addonTable.Events.Start(ev)
if ev.roster and ev.roster[Most.MyName()] then
UIErrorsFrame:AddMessage("You are already signed up for this event", 0.25, 0.85, 0.25, 1, 3)
elseif start and start < time() then
UIErrorsFrame:AddMessage("This event has already started", 1, 0.5, 0.2, 1, 3)
else
UIErrorsFrame:AddMessage("Pick your spec to sign up", 1, 0.82, 0, 1, 3)
EventSync.SignMenu.event = ev
_G.ToggleDropDownMenu(1, nil, EventSync.SignMenu, "cursor", 0, 0)
end
return true
end
end
return false
end
-- LFG tab (lfg.lua): roles per class from the event specs, the Roster's row menu (whisper, invite)
addonTable.LFG.Attach(Panels[9], { applyStyle = ApplyModernStyle, classRoles = EventSync.CLASS_ROLES, onRowClick = membersView.OnRowClick,
open = function() MainFrame:Show() ShowTab(9) end })
-- The rank is known only some time after login and can change, so this runs on guild updates
function EventSync.UpdateMonitoringTab()
if IsPlayerOfficer() then
menuButtons[6]:Show()
chatTabButtons.Oficerowie:Show()
else
menuButtons[6]:Hide()
if Panels[6]:IsShown() then ShowTab(1) end
-- The officers chat tab too; back to General when it was open
chatTabButtons.Oficerowie:Hide()
if currentChatTab == addonTable.Officers.TAB then currentChatTab = "Ogolny" UpdateChatTabVisuals() end
end
end
EventSync.UpdateMonitoringTab()
-- ============================================================================
-- 6C. TAB 5: CALENDAR (month 7x6, Monday-Sunday, events from the Events tab)
-- ============================================================================
-- A separate function (not a do-end block): its locals do not count toward the main file's limit of 200
local function BuildCalendar()
local MONTHS = {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"}
local DAYS = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}
-- Cell size and line count depend on the tab size (LayoutGrid); 80x68 and 3 lines at 850x620
local CELL_W, CELL_H, GRID_TOP, LINES, MAX_LINES = 80, 68, -92, 3, 10
local today = date("*t")
local view = { year = today.year, month = today.month }
local function DaysIn(y, m)
if m == 2 and (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)) then return 29 end
return ({31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31})[m]
end
-- "DD.MM.YYYY" or the old "DD.MM" (then the current year) -> key YYYYMMDD
local function EventKey(ev)
local d, m, y = (ev.date or ""):match("^(%d%d?)%.(%d%d?)%.?(%d*)$")
if not d then return nil end
return (tonumber(y) or today.year) * 10000 + tonumber(m) * 100 + tonumber(d)
end
-- Click on an event: Events tab with that event and its sign-ups
local function OpenEvent(ev)
for idx, e in ipairs(eventsList) do
if e == ev then selectedEventIndex = idx break end
end
ShowTab(4)
UpdateEventDetails()
end
local function ShowEventTooltip(self)
-- The "+N more" line lists the whole day
if self.dayList then
_G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
_G.GameTooltip:AddLine(self.dayLabel, 1, 0.82, 0)
for _, dayEvent in ipairs(self.dayList) do _G.GameTooltip:AddLine(dayEvent.time .. "  " .. dayEvent.title, 1, 1, 1) end
_G.GameTooltip:AddLine("Click to see them all", 0.5, 0.5, 0.5)
_G.GameTooltip:Show()
return
end
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
_G.GameTooltip:AddLine("Click to open the event", 0.5, 0.5, 0.5)
_G.GameTooltip:Show()
end
local Cal = Panels[5]
-- Filters on top (row FILTER_Y), under them, after a gap, the header: [<] [>] [Today]      November 2026
local FILTER_Y, HEADER_Y = -16, -42
local PrevBtn = CreateFrame("Button", nil, Cal, "UIPanelButtonTemplate")
PrevBtn:SetSize(30, 22) PrevBtn:SetPoint("TOPLEFT", Cal, "TOPLEFT", 0, HEADER_Y) PrevBtn:SetText("<")
local NextBtn = CreateFrame("Button", nil, Cal, "UIPanelButtonTemplate")
NextBtn:SetSize(30, 22) NextBtn:SetPoint("LEFT", PrevBtn, "RIGHT", 4, 0) NextBtn:SetText(">")
local TodayBtn = CreateFrame("Button", nil, Cal, "UIPanelButtonTemplate")
TodayBtn:SetSize(60, 22) TodayBtn:SetPoint("LEFT", NextBtn, "RIGHT", 8, 0) TodayBtn:SetText("Today")
addonTable.Help.Button(Cal, "calendar", nil, "Calendar"):SetPoint("LEFT", TodayBtn, "RIGHT", 8, 0)
local MonthText = Cal:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
MonthText:SetPoint("TOP", Cal, "TOP", 0, HEADER_Y - 3)
-- Filters above the header: [x] Signed up  [x] Other      Search: [........]
-- Both checked each time the window opens. A search looks through all events (as in the Events tab) and
-- grays the boxes out; clearing it applies the boxes again.
local filter = {}
local function NewCheck(label, anchor, x)
local check = CreateFrame("CheckButton", nil, Cal, "UICheckButtonTemplate")
check:SetSize(24, 24)
check:SetPoint("LEFT", anchor, anchor == Cal and "TOPLEFT" or "RIGHT", x, anchor == Cal and FILTER_Y or 0)
check:SetChecked(true)
check.label = check:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
check.label:SetText(label)
check:SetScript("OnClick", function() UpdateCalendar() end)
return check
end
filter.mine = NewCheck("Signed up", Cal, 0)
filter.other = NewCheck("Other", filter.mine.label, 14)
filter.search = CreateFrame("EditBox", "JagodkiCalendarSearchBox", Cal, "InputBoxTemplate")
filter.search:SetSize(195, 24)
filter.search:SetPoint("RIGHT", Cal, "TOPRIGHT", -4, FILTER_Y)
filter.search:SetAutoFocus(false)
filter.search:SetFontObject(ChatFontNormal)
filter.search.label = Cal:CreateFontString(nil, "OVERLAY", "GameFontNormal")
filter.search.label:SetPoint("RIGHT", filter.search, "LEFT", -8, 0)
filter.search.label:SetText("Search:")
filter.search.Instructions = filter.search:CreateFontString(nil, "ARTWORK", "GameFontDisable")
filter.search.Instructions:SetPoint("LEFT", filter.search, "LEFT", 5, 0)
filter.search.Instructions:SetText("Event, instance, player...")
filter.search:SetScript("OnTextChanged", function(self)
local searching = self:GetText() ~= ""
self.Instructions:SetShown(not searching)
for _, check in ipairs({ filter.mine, filter.other }) do
check:SetEnabled(not searching)
check.label:SetTextColor(searching and 0.5 or 1, searching and 0.5 or 0.82, searching and 0.5 or 0)
end
UpdateCalendar()
end)
filter.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
MainFrame:HookScript("OnShow", function()
filter.mine:SetChecked(true) filter.other:SetChecked(true)
filter.search:SetText("") filter.search:ClearFocus()
end)
-- Whether the calendar shows an event: the search when there is one, otherwise the boxes
local function Shown(ev, myName)
local text = filter.search:GetText():lower()
if text ~= "" then return EventSync.MatchesSearch(ev, text) end
if ev.roster and ev.roster[myName] then return filter.mine:GetChecked() end
return filter.other:GetChecked()
end
local dayHeaders = {}
for i, name in ipairs(DAYS) do
local dayHeader = Cal:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
dayHeader:SetText(name)
if i >= 6 then dayHeader:SetTextColor(1, 0.5, 0.5) end
dayHeaders[i] = dayHeader
end
-- Small window with all events of a day, opened from the "+N more" line
local DayPopup = CreateFrame("Frame", "JagodkiCalendarDay", Cal, "BackdropTemplate")
DayPopup:SetWidth(240)
DayPopup:SetFrameStrata("DIALOG")
DayPopup:SetClampedToScreen(true)
DayPopup:EnableMouse(true)
DayPopup:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
DayPopup:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
DayPopup:SetBackdropBorderColor(0.3, 0.3, 0.38, 1)
DayPopup:Hide()
table.insert(_G.UISpecialFrames, "JagodkiCalendarDay")
DayPopup.title = DayPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
DayPopup.title:SetPoint("TOPLEFT", DayPopup, "TOPLEFT", 10, -8)
DayPopup.rows = {}
do
local close = CreateFrame("Button", nil, DayPopup, "UIPanelCloseButton")
close:SetSize(22, 22)
close:SetPoint("TOPRIGHT", DayPopup, "TOPRIGHT", 0, 0)
-- A click outside closes it; its own "+N more" line handles the click itself
local watcher = CreateFrame("Frame")
pcall(watcher.RegisterEvent, watcher, "GLOBAL_MOUSE_DOWN")
addonTable.SafeScript(watcher, "OnEvent", "core.lua:2483", function()
if DayPopup:IsShown() and not DayPopup:IsMouseOver() and not (DayPopup.anchor and DayPopup.anchor:IsMouseOver()) then DayPopup:Hide() end
end)
end
function DayPopup:Fill(list, label)
self.title:SetText(label)
local myName = Most.MyName()
for i, ev in ipairs(list) do
local row = self.rows[i]
if not row then
row = CreateFrame("Button", nil, self)
row:SetHeight(18)
row:SetPoint("TOPLEFT", self, "TOPLEFT", 6, -28 - (i - 1) * 19)
row:SetPoint("RIGHT", self, "RIGHT", -6, 0)
row.bg = row:CreateTexture(nil, "BACKGROUND") row.bg:SetAllPoints()
row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
row.text:SetPoint("LEFT", row, "LEFT", 4, 0) row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
row.text:SetJustifyH("LEFT") row.text:SetWordWrap(false)
row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
-- The same as a line in the calendar: left = open, right = menu, hover = tooltip
row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
row:SetScript("OnClick", function(btn, button)
if button == "RightButton" then
DayPopup.OpenMenu(btn.event)
else
DayPopup:Hide()
OpenEvent(btn.event)
end
end)
row:SetScript("OnEnter", ShowEventTooltip)
row:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
self.rows[i] = row
end
local signed = ev.roster and ev.roster[myName]
row.event = ev
row.text:SetText((signed and "|cff00ff00" or "|cffffffff") .. ev.time .. "  " .. ev.title .. "|r")
row.bg:SetColorTexture(0.55, 0.25, 0.8, signed and 0.55 or 0.3)
row:Show()
end
for i = #list + 1, #self.rows do self.rows[i]:Hide() end
self:SetHeight(36 + #list * 19)
end
function DayPopup:Open(line)
self.anchor, self.dayKey = line, line.dayKey
self:Fill(line.dayList, line.dayLabel)
self:ClearAllPoints()
self:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -2)
self:Show()
end
-- 42 day cells, each with up to MAX_LINES event buttons (LINES are visible)
-- Right click on an event: "Invite members" menu = group invites for everyone signed up.
-- We skip ourselves, people already in the group and offline ones. A party has 5 spots: with more people,
-- the group becomes a raid (at once or after the first accepted invite), then the rest are invited.
local EventMenu = CreateFrame("Frame", "JagodkiCalendarEventMenu", UIParent, "UIDropDownMenuTemplate")
local menuEvent, pendingInvites = nil, nil
function DayPopup.OpenMenu(ev)
menuEvent = ev
_G.ToggleDropDownMenu(1, nil, EventMenu, "cursor", 0, 0)
end
local function Report(text) if _G.DEFAULT_CHAT_FRAME then _G.DEFAULT_CHAT_FRAME:AddMessage("|cffbf40ff[Jagodka]|r " .. text) end end
local function InviteName(name)
local invite = (_G.C_PartyInfo and _G.C_PartyInfo.InviteUnit) or _G.InviteUnit
if invite then invite(Most.GameName(name)) end
end
local function MakeRaid()
local convert = (_G.C_PartyInfo and _G.C_PartyInfo.ConvertToRaid) or _G.ConvertToRaid
if convert then convert() end
end
local function InGroup(name) local n = Most.GameName(name) return _G.UnitInParty(n) or _G.UnitInRaid(n) end
local function IsLeader() return _G.UnitIsGroupLeader("player") or (_G.IsInRaid() and _G.UnitIsGroupAssistant("player")) end
local function SignedUpOthers(ev)
local n, me = 0, Most.MyName()
for name in pairs(ev.roster or {}) do if name ~= me then n = n + 1 end end
return n
end
local function InviteSignedUp(ev)
if _G.IsInGroup() and not IsLeader() then Report("|cffff5555Only the group leader (or a raid assistant) can invite.|r") return end
-- Who is online: the same list as in Members (players with the addon + guild rosters)
local online = {}
for _, p in ipairs(Roster.BuildList(false)) do online[p.name] = true end
local me, toInvite, already, offline = Most.MyName(), {}, 0, 0
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
-- Free spots: raid 40, party / no group 5 (including me)
local size = _G.IsInGroup() and _G.GetNumGroupMembers() or 1
local limit = _G.IsInRaid() and 40 or 5
local rest = {}
for _, name in ipairs(toInvite) do
if size < limit then InviteName(name) size = size + 1 else table.insert(rest, name) end
end
if #rest > 0 and not _G.IsInRaid() then
-- The rest after converting to a raid (GROUP_ROSTER_UPDATE below); with no group, after the first accepted invite
pendingInvites = { names = rest, expires = GetTime() + 90 }
if _G.IsInGroup() and _G.UnitIsGroupLeader("player") then MakeRaid() end
Report(ev.title .. ": inviting " .. (#toInvite - #rest) .. " now, " .. #rest .. " more after converting to raid " .. summary)
else
Report(ev.title .. ": inviting " .. #toInvite .. " " .. summary)
end
end
-- Used by the Invite all button in the events table
function EventSync.InviteAll(ev)
if ev and EventSync.CanInvite(ev) then InviteSignedUp(ev) end
end
local GroupWatcher = CreateFrame("Frame")
GroupWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
addonTable.SafeScript(GroupWatcher, "OnEvent", "core.lua:2596", function()
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
if EventSync.CanInvite(ev) then
local n = SignedUpOthers(ev)
info = _G.UIDropDownMenu_CreateInfo()
info.text = (n > 0) and ("Invite members (" .. n .. ")") or "Invite members (no sign-ups)"
info.disabled = (n == 0)
info.notCheckable = true
info.func = function() InviteSignedUp(ev) end
_G.UIDropDownMenu_AddButton(info, level)
end
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
-- Click on free space in a day (not on an event): "Create event" menu with a preset date.
-- Officers only (like the Create Event button) and only today / future days.
local DayMenu = CreateFrame("Frame", "JagodkiCalendarDayMenu", UIParent, "UIDropDownMenuTemplate")
local menuCell = nil
_G.UIDropDownMenu_Initialize(DayMenu, function(self, level)
if not menuCell then return end
local info = _G.UIDropDownMenu_CreateInfo()
info.text, info.isTitle, info.notCheckable = date("%A %d.%m.%Y", menuCell.dayTime), true, true
_G.UIDropDownMenu_AddButton(info, level)
local canCreate = addonTable.Events.CanCreate() and not menuCell.isPast
info = _G.UIDropDownMenu_CreateInfo()
info.text = canCreate and "Create event" or (menuCell.isPast and "Create event (past day)" or "Create event (limit of upcoming events reached)")
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
-- Left = open the event, right = menu (Invite members / Open event)
b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
b:SetScript("OnClick", function(self, button)
if self.dayList then
-- "+N more": the list of the whole day; a second click closes it
if DayPopup:IsShown() and DayPopup.anchor == self then DayPopup:Hide() else DayPopup:Open(self) end
return
end
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
-- Grid layout by tab size: wider window = wider cells (longer names), taller = more lines
local function LayoutGrid(w, h)
if not w or w <= 0 or not h or h <= 0 then w, h = 7 * 80, -GRID_TOP + 6 * 68 end
CELL_W, CELL_H = math.floor(w / 7), math.floor((h + GRID_TOP) / 6)
LINES = math.max(1, math.min(MAX_LINES, math.floor((CELL_H - 20) / 15)))
for i, dayHeader in ipairs(dayHeaders) do
dayHeader:ClearAllPoints()
dayHeader:SetPoint("TOP", Cal, "TOPLEFT", (i - 1) * CELL_W + CELL_W / 2, GRID_TOP + 16)
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
-- Events grouped by day, within a day by time
local byDay = {}
local me = Most.MyName()
for _, ev in ipairs(eventsList) do
local key = Shown(ev, me) and EventKey(ev)
if key then byDay[key] = byDay[key] or {} table.insert(byDay[key], ev) end
end
for _, list in pairs(byDay) do table.sort(list, function(a, b) return (a.time or "") < (b.time or "") end) end
-- Column of the 1st of the month (wday: 1 = Sunday -> 7, 2 = Monday -> 1)
local first = (date("*t", time({ year = y, month = m, day = 1, hour = 12 })).wday + 5) % 7
local prevY, prevM = (m == 1) and (y - 1) or y, (m == 1) and 12 or (m - 1)
local nextY, nextM = (m == 12) and (y + 1) or y, (m == 12) and 1 or (m + 1)
local todayKey = today.year * 10000 + today.month * 100 + today.day
local myName = Most.MyName()
for k, cell in ipairs(cells) do
local d, cy, cm, inMonth = k - first, y, m, true
if d < 1 then cy, cm, d, inMonth = prevY, prevM, DaysIn(prevY, prevM) + d, false
elseif d > DaysIn(y, m) then cy, cm, d, inMonth = nextY, nextM, d - DaysIn(y, m), false end
local key = cy * 10000 + cm * 100 + d
-- For the "Create event" menu: the day of this cell and whether it has passed
cell.dayTime = time({ year = cy, month = cm, day = d, hour = 12 })
cell.isPast = key < todayKey
cell.dayText:SetText(d)
cell:SetAlpha(inMonth and 1 or 0.35)
-- Today: gold border; past days are darker
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
-- More events than lines: the last line = "+N more" (tooltip and click = the whole day)
local hidden = (l == LINES) and (#list - LINES) or 0
b.dayList, b.dayKey, b.dayLabel = nil, nil, nil
if hidden > 0 then
b.dayList, b.dayKey, b.dayLabel = list, key, string.format("Events on %02d.%02d.%d", d, cm, cy)
end
local signed = ev.roster and ev.roster[myName]
b.text:SetText(hidden > 0 and ("|cffffd100+" .. (hidden + 1) .. " more|r") or ((signed and "|cff00ff00" or "|cffffffff") .. ev.time .. " " .. ev.title .. "|r"))
b.bg:SetColorTexture(0.55, 0.25, 0.8, signed and 0.55 or 0.3)
b:Show()
else
b.event, b.dayList = nil, nil b:Hide()
end
end
end
-- An open day window follows changes from sync; it closes when the day has no hidden events to show
if DayPopup:IsShown() then
local anchor = DayPopup.anchor
if anchor and anchor:IsShown() and anchor.dayKey == DayPopup.dayKey and anchor.dayList then
DayPopup:Fill(anchor.dayList, anchor.dayLabel)
else
DayPopup:Hide()
end
end
end
PrevBtn:SetScript("OnClick", function() view.month = view.month - 1 if view.month < 1 then view.month, view.year = 12, view.year - 1 end UpdateCalendar() end)
NextBtn:SetScript("OnClick", function() view.month = view.month + 1 if view.month > 12 then view.month, view.year = 1, view.year + 1 end UpdateCalendar() end)
TodayBtn:SetScript("OnClick", function() local t = date("*t") view.year, view.month = t.year, t.month UpdateCalendar() end)
end
BuildCalendar()
-- ============================================================================
-- 7. SIDE PANEL (ALWAYS VISIBLE, RIGHT SIDE)
-- ============================================================================
-- My character above the column (charcard.lua)
addonTable.CharCard.Attach(MainFrame, ApplyModernStyle)
addonTable.Help.Button(addonTable.CharCard.frame, "column", 1, "Your character"):SetPoint("TOPRIGHT", addonTable.CharCard.frame, "TOPRIGHT", -6, -6)
-- 7a. UPCOMING EVENTS (top of the column): two tabs, "Signed up" (events I am signed up for) and "Other",
-- each sorted from the nearest. 4 rows high; more = mouse wheel, with a thin position bar on the right.
-- Click = the event in the Events tab, hover = its details. Kept in EventSync.Side (no new file locals).
do
local S = { tab = 1, offset = 0, rows = {}, ROWS = 4, ROW_H = 20 }
EventSync.Side = S
S.panel = CreateFrame("Frame", nil, MainFrame, "BackdropTemplate")
S.panel:SetSize(330, 5 + S.ROWS * S.ROW_H + 5)
-- Under the character card, with room for the title and tabs (as between the other panels)
S.panel:SetPoint("TOPRIGHT", addonTable.CharCard.frame, "BOTTOMRIGHT", 0, -28)
ApplyModernStyle(S.panel)
S.panel:EnableMouseWheel(true)
-- Title on the left as over the other panels, the tabs on the same line on the right, in the style of the
-- chat tabs (so the section is no taller)
S.header = S.panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
S.header:SetPoint("BOTTOMLEFT", S.panel, "TOPLEFT", 12, 5)
-- Three tabs: events I am signed up for, other events, and LFG (lfg.lua: my listing, one row per activity)
S.header:SetText("Events / LFG")
addonTable.Help.Button(S.panel, "column", 2, "Events / LFG"):SetPoint("LEFT", S.header, "RIGHT", 6, 0)
S.tabs = {}
for i = 1, 3 do
local t = CreateFrame("Button", nil, S.panel, "BackdropTemplate")
t:SetSize(i == 3 and 62 or 72, 20)
if i == 3 then t:SetPoint("BOTTOMRIGHT", S.panel, "TOPRIGHT", -6, 0) end
t:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
t:SetBackdropBorderColor(0.15, 0.15, 0.2, 0.8)
t.bg = t:CreateTexture(nil, "BACKGROUND") t.bg:SetAllPoints()
t.topLine = t:CreateTexture(nil, "OVERLAY") t.topLine:SetHeight(2)
t.topLine:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0) t.topLine:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, 0)
t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") t.text:SetPoint("CENTER", t, "CENTER", 0, 0)
t:SetScript("OnClick", function() S.tab, S.offset = i, 0 S.Render() end)
S.tabs[i] = t
end
S.tabs[2]:SetPoint("BOTTOMRIGHT", S.tabs[3], "BOTTOMLEFT", -4, 0)
S.tabs[1]:SetPoint("BOTTOMRIGHT", S.tabs[2], "BOTTOMLEFT", -4, 0)
S.empty = S.panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
S.empty:SetPoint("CENTER", S.panel, "CENTER", 0, 0)
-- Thin position bar instead of a slider: only with more than ROWS events
S.track = S.panel:CreateTexture(nil, "ARTWORK")
S.track:SetWidth(2) S.track:SetColorTexture(1, 1, 1, 0.08)
S.track:SetPoint("TOPRIGHT", S.panel, "TOPRIGHT", -4, -5) S.track:SetPoint("BOTTOMRIGHT", S.panel, "BOTTOMRIGHT", -4, 5)
S.thumb = S.panel:CreateTexture(nil, "OVERLAY")
S.thumb:SetWidth(2) S.thumb:SetColorTexture(0.75, 0.25, 1, 0.8)
for i = 1, S.ROWS do
local row = CreateFrame("Button", nil, S.panel)
row:SetHeight(S.ROW_H)
row:SetPoint("TOPLEFT", S.panel, "TOPLEFT", 4, -5 - (i - 1) * S.ROW_H)
row:SetPoint("RIGHT", S.panel, "RIGHT", -10, 0)
local tex = row:CreateTexture(nil, "BACKGROUND") tex:SetAllPoints() tex:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.06)
row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
row.when = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
row.when:SetPoint("LEFT", row, "LEFT", 6, 0) row.when:SetWidth(92) row.when:SetJustifyH("LEFT")
row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
row.count:SetPoint("RIGHT", row, "RIGHT", -4, 0) row.count:SetJustifyH("RIGHT")
row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
row.title:SetPoint("LEFT", row.when, "RIGHT", 4, 0) row.title:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
row.title:SetJustifyH("LEFT") row.title:SetWordWrap(false)
row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
row:SetScript("OnClick", function(self, button) if self.item then addonTable.LFG.SideClick(self, button) elseif button == "LeftButton" then S.Open(self.ev) end end)
row:SetScript("OnEnter", function(self) if self.item then addonTable.LFG.SideTooltip(self) else S.ShowTooltip(self) end end)
row:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
S.rows[i] = row
end
local function Moment(ev)
local h, m = (ev.time or ""):match("^(%d+):(%d+)$")
return (EventSync.DayTime(ev.date) or 0) + (tonumber(h) or 0) * 3600 + (tonumber(m) or 0) * 60
end
-- Both tabs' lists: upcoming only (from the start of the current hour), nearest first
function S.Lists()
local mine, others = {}, {}
local from, me = time() - 3600, Most.MyName()
for _, ev in ipairs(eventsList) do
local at = Moment(ev)
if at >= from then table.insert((ev.roster and ev.roster[me]) and mine or others, { ev = ev, at = at }) end
end
local function Nearest(a, b) return a.at < b.at end
table.sort(mine, Nearest) table.sort(others, Nearest)
return mine, others
end
function S.Render()
if not S.panel:IsVisible() then return end
local mine, others = S.Lists()
local lfgItems, lfgCount = addonTable.LFG.SideItems()
S.tabs[1].text:SetText("Signed (" .. #mine .. ")")
S.tabs[2].text:SetText("Other (" .. #others .. ")")
-- LFG: how many activities I am listed for (green while listed)
S.tabs[3].text:SetText(lfgCount > 0 and ("LFG |cff00ff00(" .. lfgCount .. ")|r") or "LFG (0)")
for i, t in ipairs(S.tabs) do
local active = i == S.tab
t.bg:SetColorTexture(active and 0.18 or 0.08, active and 0.1 or 0.08, active and 0.24 or 0.11, active and 0.9 or 0.6)
t.topLine:SetColorTexture(0.75, 0.25, 1, active and 1 or 0)
t.text:SetTextColor(active and 1 or 0.7, active and 1 or 0.7, active and 1 or 0.7)
end
local list = (S.tab == 1 and mine) or (S.tab == 2 and others) or lfgItems
S.offset = math.max(0, math.min(S.offset, #list - S.ROWS))
S.empty:SetText(S.tab == 1 and "You are not signed up for any event" or "No other upcoming events")
if #list == 0 then S.empty:Show() else S.empty:Hide() end
for i, row in ipairs(S.rows) do
local item = list[i + S.offset]
row.item = nil
row:SetAlpha(1)
if item and S.tab == 3 then
-- LFG: my listing, one row per activity (type, name; roles and the waiting time on the first row)
row.item, row.ev = item, nil
row.when:SetText(item.left)
row.title:SetText(item.mid)
row.count:SetText(item.right)
row:Show()
elseif item then
local ev = item.ev
row.ev = ev
local today = date("%d.%m.%Y") == ev.date
row.when:SetText((today and "|cff00ff00Today|r " or (date("%a %d.%m", item.at) .. " ")) .. (ev.time or ""))
row.title:SetText(ev.title or "?")
local signed = 0
for _ in pairs(ev.roster or {}) do signed = signed + 1 end
row.count:SetText(signed)
row:Show()
else row:Hide() end
end
-- Position bar: thumb as long as the visible share, where the shown rows are
if #list > S.ROWS then
local trackH = S.ROWS * S.ROW_H
local thumbH = math.max(8, math.floor(trackH * S.ROWS / #list))
S.thumb:SetHeight(thumbH)
S.thumb:ClearAllPoints()
S.thumb:SetPoint("TOPRIGHT", S.panel, "TOPRIGHT", -4, -5 - math.floor((trackH - thumbH) * S.offset / (#list - S.ROWS)))
S.track:Show() S.thumb:Show()
else S.track:Hide() S.thumb:Hide() end
end
S.panel:SetScript("OnMouseWheel", function(_, delta) S.offset = S.offset - delta S.Render() end)
-- Each time the window opens: the "Signed up" tab, from the top
S.panel:SetScript("OnShow", function() S.tab, S.offset = 1, 0 S.Render() end)
-- LFG changes redraw the column at once; the minutes count on every 30 s while the LFG tab is shown
addonTable.LFG.SideRender = S.Render
C_Timer.NewTicker(30, function() if S.tab == 3 then S.Render() end end)
function S.ShowTooltip(row)
local ev = row.ev
if not ev then return end
local tip = _G.GameTooltip
tip:SetOwner(row, "ANCHOR_LEFT")
tip:AddLine(ev.title or "?", 1, 1, 1)
tip:AddLine(addonTable.InstanceType(ev.dungeon) .. (ev.dungeon and (" - " .. ev.dungeon) or ""), 1, 0.82, 0)
tip:AddLine((ev.date or "") .. " " .. (ev.time or ""), 0.8, 0.8, 0.8)
tip:AddLine("Created by " .. tostring(ev.creator) .. (ev.guild and (" (" .. Most.GuildTag(ev.guild) .. ")") or ""), 0.8, 0.8, 0.8)
local t, h, d = 0, 0, 0
for _, role in pairs(ev.roster or {}) do
if role == "TANK" then t = t + 1 elseif role == "HEAL" then h = h + 1 else d = d + 1 end
end
tip:AddLine("Signed up: " .. (t + h + d) .. "  (Tanks " .. t .. ", Healers " .. h .. ", DPS " .. d .. ")", 0.8, 0.8, 0.8)
local myRole = ev.roster and ev.roster[Most.MyName()]
if myRole then tip:AddLine("You are signed up (" .. myRole .. ")", 0.25, 0.85, 0.25) end
if ev.desc and ev.desc ~= "" then tip:AddLine(ev.desc, 0.7, 0.7, 0.7, true) end
tip:AddLine("Click to open", 0.5, 0.5, 0.5)
tip:Show()
end
-- Opens the Events tab with the event's details
function S.Open(ev)
ShowTab(4)
if not ev then return end
for idx, e in ipairs(eventsList) do
if e == ev then selectedEventIndex = idx UpdateEventDetails() return end
end
end
end
local RightPanel = CreateFrame("Frame", nil, MainFrame, "BackdropTemplate")
-- Fixed width, 6 rows high (SideGuilds.Layout), under the upcoming events; the guilds and classes below
RightPanel:SetWidth(330)
RightPanel:SetPoint("TOPRIGHT", EventSync.Side.panel, "BOTTOMRIGHT", 0, -28)
ApplyModernStyle(RightPanel)
-- ============================================================================
-- 7b. GUILDS UNDER THE OFFICERS: one row per listed guild (as the Guilds tab, compact)
-- ============================================================================
-- Tag and name, online / all members, a bar with the online share, and "active" or when data last came.
-- Guilds without anyone with the addon online are grayed out. (It replaced the Guilds tab.)
local SideGuilds = { rows = {}, cells = {}, ROW_H = 40, HEADER_GAP = 28, CLASS_ROW_H = 22, SHOWN = 4, offset = 0, -- 4: all our guilds (JN, II, IIl, IV) without scrolling
CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" } }
-- The guilds and classes panels are as tall as their content; the officers list above takes the rest
SideGuilds.panel = CreateFrame("Frame", nil, MainFrame, "BackdropTemplate")
SideGuilds.panel:SetPoint("TOPLEFT", RightPanel, "BOTTOMLEFT", 0, -SideGuilds.HEADER_GAP)
SideGuilds.panel:SetPoint("TOPRIGHT", RightPanel, "BOTTOMRIGHT", 0, -SideGuilds.HEADER_GAP)
ApplyModernStyle(SideGuilds.panel)
SideGuilds.header = SideGuilds.panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
SideGuilds.header:SetPoint("BOTTOMLEFT", SideGuilds.panel, "TOPLEFT", 12, 5)
addonTable.Help.Button(SideGuilds.panel, "column", 4, "Guilds"):SetPoint("LEFT", SideGuilds.header, "RIGHT", 6, 0)
-- Members of all listed guilds per class (the game gives no race or spec in the roster), 3 x 3 grid
SideGuilds.classPanel = CreateFrame("Frame", nil, MainFrame, "BackdropTemplate")
SideGuilds.classPanel:SetPoint("TOPLEFT", SideGuilds.panel, "BOTTOMLEFT", 0, -SideGuilds.HEADER_GAP)
SideGuilds.classPanel:SetPoint("TOPRIGHT", SideGuilds.panel, "BOTTOMRIGHT", 0, -SideGuilds.HEADER_GAP)
ApplyModernStyle(SideGuilds.classPanel)
SideGuilds.classHeader = SideGuilds.classPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
SideGuilds.classHeader:SetPoint("BOTTOMLEFT", SideGuilds.classPanel, "TOPLEFT", 12, 5)
addonTable.Help.Button(SideGuilds.classPanel, "column", 5, "Classes"):SetPoint("LEFT", SideGuilds.classHeader, "RIGHT", 6, 0)
function SideGuilds.Layout()
-- Always SHOWN guild rows high; more guilds = mouse wheel, with a thin position bar (as Upcoming Events)
local guildsH = SideGuilds.SHOWN * SideGuilds.ROW_H + 6
local classH = math.ceil(#SideGuilds.CLASSES / 3) * SideGuilds.CLASS_ROW_H + 10
SideGuilds.panel:SetHeight(guildsH)
SideGuilds.classPanel:SetHeight(classH)
-- The officers list is exactly OFFICERS_SHOWN rows high (5 px above and below the rows, as in its
-- scroll frame); more officers online = the slider appears
local OFFICERS_SHOWN = 6
RightPanel:SetHeight(5 + OFFICERS_SHOWN * 26 + 5)
end
MainFrame:HookScript("OnSizeChanged", SideGuilds.Layout)
SideGuilds.Layout()
local function ShowClassTooltip(cell)
local c = cell.counts or { total = 0, online = 0 }
_G.GameTooltip:SetOwner(cell, "ANCHOR_LEFT")
_G.GameTooltip:AddLine(LOCALIZED_CLASS_NAMES_MALE[cell.class] or cell.class, 1, 1, 1)
_G.GameTooltip:AddLine("Members of all guilds: " .. c.total, 0.8, 0.8, 0.8)
_G.GameTooltip:AddLine("Online: " .. c.online, 0.25, 0.85, 0.25)
_G.GameTooltip:Show()
end
for i, class in ipairs(SideGuilds.CLASSES) do
local col, line = (i - 1) % 3, math.floor((i - 1) / 3)
local cell = CreateFrame("Frame", nil, SideGuilds.classPanel)
cell:SetSize(105, SideGuilds.CLASS_ROW_H)
cell:SetPoint("TOPLEFT", SideGuilds.classPanel, "TOPLEFT", 8 + col * 107, -5 - line * SideGuilds.CLASS_ROW_H)
cell.icon = cell:CreateTexture(nil, "ARTWORK") cell.icon:SetSize(16, 16) cell.icon:SetPoint("LEFT", cell, "LEFT", 0, 0)
cell.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
if CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then cell.icon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class])) end
cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") cell.text:SetPoint("LEFT", cell.icon, "RIGHT", 5, 0)
cell.class = class
cell:EnableMouse(true)
cell:SetScript("OnEnter", ShowClassTooltip)
cell:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
SideGuilds.cells[i] = cell
end
SideGuilds.track = SideGuilds.panel:CreateTexture(nil, "ARTWORK")
SideGuilds.track:SetWidth(2) SideGuilds.track:SetColorTexture(1, 1, 1, 0.08)
SideGuilds.track:SetPoint("TOPRIGHT", SideGuilds.panel, "TOPRIGHT", -4, -4) SideGuilds.track:SetPoint("BOTTOMRIGHT", SideGuilds.panel, "BOTTOMRIGHT", -4, 4)
SideGuilds.thumb = SideGuilds.panel:CreateTexture(nil, "OVERLAY")
SideGuilds.thumb:SetWidth(2) SideGuilds.thumb:SetColorTexture(0.75, 0.25, 1, 0.8)
SideGuilds.panel:EnableMouseWheel(true)
SideGuilds.panel:SetScript("OnMouseWheel", function(_, delta) SideGuilds.offset = SideGuilds.offset - delta SideGuilds.Render() end)
for i = 1, SideGuilds.SHOWN do
local row = CreateFrame("Button", nil, SideGuilds.panel)
local top = -4 - (i - 1) * SideGuilds.ROW_H
row:SetHeight(SideGuilds.ROW_H - 4)
row:SetPoint("TOPLEFT", SideGuilds.panel, "TOPLEFT", 4, top)
row:SetPoint("TOPRIGHT", SideGuilds.panel, "TOPRIGHT", -10, top)
local bg = row:CreateTexture(nil, "BACKGROUND") bg:SetAllPoints() bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.06)
row.icon = row:CreateTexture(nil, "ARTWORK") row.icon:SetSize(22, 22) row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
row.icon:SetTexture("Interface\\AddOns\\jagodka\\Media\\blueberry_one.tga")
row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") row.count:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 3)
row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0) row.name:SetJustifyH("LEFT") row.name:SetWordWrap(false)
row.status = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") row.status:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 4)
row.barBg = row:CreateTexture(nil, "ARTWORK") row.barBg:SetHeight(4) row.barBg:SetColorTexture(0, 0, 0, 0.5)
row.barBg:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1) row.barBg:SetPoint("RIGHT", row, "RIGHT", -75, 0)
row.bar = row:CreateTexture(nil, "OVERLAY") row.bar:SetHeight(4) row.bar:SetColorTexture(0.25, 0.85, 0.25, 0.9)
row.bar:SetPoint("LEFT", row.barBg, "LEFT", 0, 0)
row:Hide()
SideGuilds.rows[i] = row
end
function SideGuilds.Render()
local order, data, active = {}, {}, 0
for gName in pairs(AllowedGuilds) do
if not GuildsNotShown[gName] then
data[gName] = Roster.GetGuildSummary(gName)
table.insert(order, gName)
if data[gName].live then active = active + 1 end
end
end
table.sort(order, function(a, b)
if data[a].live ~= data[b].live then return data[a].live end
return a < b
end)
SideGuilds.header:SetText("Guilds (" .. active .. " active)")
SideGuilds.offset = math.max(0, math.min(SideGuilds.offset, #order - SideGuilds.SHOWN))
if #order > SideGuilds.SHOWN then
local trackH = SideGuilds.SHOWN * SideGuilds.ROW_H - 2
local thumbH = math.max(8, math.floor(trackH * SideGuilds.SHOWN / #order))
SideGuilds.thumb:SetHeight(thumbH)
SideGuilds.thumb:ClearAllPoints()
SideGuilds.thumb:SetPoint("TOPRIGHT", SideGuilds.panel, "TOPRIGHT", -4, -4 - math.floor((trackH - thumbH) * SideGuilds.offset / (#order - SideGuilds.SHOWN)))
SideGuilds.track:Show() SideGuilds.thumb:Show()
else SideGuilds.track:Hide() SideGuilds.thumb:Hide() end
for i, row in ipairs(SideGuilds.rows) do
local gName = order[i + SideGuilds.offset]
if gName then
local s = data[gName]
if s.live then
row.name:SetText("|cffbf40ff" .. Most.GuildTag(gName) .. "|r  |cffffffff" .. gName .. "|r")
row.count:SetText("|cff00ff00" .. s.online .. "|r|cff808080 / " .. s.total .. "|r")
row.status:SetText("|cff00ff00active|r")
else
row.name:SetText("|cff808080" .. Most.GuildTag(gName) .. "  " .. gName .. "|r")
row.count:SetText(s.total > 0 and ("|cff808080" .. s.total .. "|r") or "")
local ago = s.updated and (GetServerTime() - s.updated)
row.status:SetText(not ago and "no data" or (ago < 3600 and (math.floor(ago / 60) .. " min ago") or (math.floor(ago / 3600) .. " h ago")))
end
row.icon:SetDesaturated(not s.live)
local share, width = (s.live and s.total > 0) and (s.online / s.total) or 0, row.barBg:GetWidth()
if share > 0 and width > 0 then row.bar:SetWidth(math.max(1, width * math.min(1, share))) row.bar:Show() else row.bar:Hide() end
row:Show()
else row:Hide() end
end
-- Classes: all members (in the class color) and online (green), totals in the header
local counts, total, online = Roster.ClassCounts(), 0, 0
for _, cell in ipairs(SideGuilds.cells) do
local c = counts[cell.class] or { total = 0, online = 0 }
cell.counts = c
total, online = total + c.total, online + c.online
local color = RAID_CLASS_COLORS[cell.class]
local all = color and color:WrapTextInColorCode(tostring(c.total)) or tostring(c.total)
cell.text:SetText(all .. " |cff00ff00(" .. c.online .. ")|r")
end
SideGuilds.classHeader:SetText("Classes (" .. total .. " members, |cff00ff00" .. online .. " online|r)")
end
SideGuilds.panel:SetScript("OnSizeChanged", function(self) if self:IsVisible() then SideGuilds.Render() end end)
local HeaderText = RightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
HeaderText:SetPoint("TOPLEFT", RightPanel, "TOPLEFT", 12, 18)
addonTable.Help.Button(RightPanel, "column", 3, "Officers online"):SetPoint("LEFT", HeaderText, "RIGHT", 6, 0)
local scrollFrame = CreateFrame("ScrollFrame", "JagodkiRightListScrollFrame", RightPanel, "FauxScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", RightPanel, "TOPLEFT", 0, -5)
scrollFrame:SetPoint("BOTTOMRIGHT", RightPanel, "BOTTOMRIGHT", -26, 5)
-- Rows in advance; as many show as fit the panel (RightPanel.visibleRows)
local ROW_HEIGHT, MAX_ROWS, rows = 26, 38, {}
for i = 1, MAX_ROWS do
local row = CreateFrame("Button", nil, RightPanel)
addonTable.Discord.AttachRow(row)
-- Player bar across the panel's full width (right edge set in RenderScrollList: with / without slider)
row:SetHeight(ROW_HEIGHT) row:SetPoint("TOPLEFT", RightPanel, "TOPLEFT", 4, -5 - ((i-1) * ROW_HEIGHT))
local rowTex = row:CreateTexture(nil, "BACKGROUND") rowTex:SetAllPoints() rowTex:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.06)
row.classIcon = row:CreateTexture(nil, "ARTWORK") row.classIcon:SetSize(18, 18) row.classIcon:SetPoint("LEFT", row, "LEFT", 6, 0)
-- Rank aligned to the right edge (as in the Members table); the name (with guild) takes the rest and is cut before it
row.levelText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") row.levelText:SetPoint("RIGHT", row, "RIGHT", -8, 0) row.levelText:SetJustifyH("RIGHT")
row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") row.nameText:SetPoint("LEFT", row.classIcon, "RIGHT", 6, 0)
row.nameText:SetPoint("RIGHT", row.levelText, "LEFT", -6, 0) row.nameText:SetJustifyH("LEFT") row.nameText:SetWordWrap(false)
rows[i] = row
end
-- Officers online of all listed guilds, guild masters included (officer = by the guild rosters,
-- IsKnownOfficer), with the guild's short tag. From the same list as the Members tab (Roster.BuildList).
local onlineList, onlineListPending = {}, false
local function RenderScrollList()
HeaderText:SetText("Officers online (" .. #onlineList .. ")")
-- The counter in the window header = everyone online from all listed guilds (RightPanel.onlineTotal)
OnlineText:SetText("Online: |cff00ff00" .. (RightPanel.onlineTotal or 0) .. "|r")
local visible = RightPanel.visibleRows or 17
_G.FauxScrollFrame_Update(scrollFrame, #onlineList, visible, ROW_HEIGHT)
local offset = _G.FauxScrollFrame_GetOffset(scrollFrame)
-- Slider visible only with a longer list: then bars end before it, otherwise at the edge
local scrollBar = _G[scrollFrame:GetName() .. "ScrollBar"]
local rightInset = (#onlineList > visible and scrollBar and scrollBar:IsShown()) and -28 or -4
for i = 1, MAX_ROWS do
local idx = i + offset local row = rows[i]
row:SetPoint("RIGHT", RightPanel, "RIGHT", rightInset, 0)
if i <= visible and idx <= #onlineList then
local data = onlineList[idx] local displayName = data.name
row.member = data
if data.class and RAID_CLASS_COLORS[data.class] then displayName = RAID_CLASS_COLORS[data.class]:WrapTextInColorCode(data.name) end
if data.guild and data.guild ~= "" and data.guild ~= "Brak" then displayName = displayName .. " |cffbf40ff(" .. Most.GuildTag(data.guild) .. ")|r" end
-- The rank from the guild roster (officer / guild master), colored as in the Members table
row.nameText:SetText(displayName) row.levelText:SetText(GetColoredRank((Roster.GetRank(data.name, data.guild)) or data.rank))
if data.class and CLASS_ICON_TCOORDS[data.class] then
row.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
row.classIcon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[data.class])) row.classIcon:Show()
else row.classIcon:Hide() end
row:Show()
else row:Hide() end
end
end
-- As in the table: recomputed only with the window open, at most once per 0.3 s
UpdateScrollList = function()
if onlineListPending or not RightPanel:IsVisible() then return end
onlineListPending = true
C_Timer.After(0.3, function()
onlineListPending = false
if not RightPanel:IsVisible() then return end
local all = Roster.BuildList(false)
RightPanel.onlineTotal = #all
onlineList = {}
for _, p in ipairs(all) do
if IsKnownOfficer(p.name, p.guild) then table.insert(onlineList, p) end
end
-- By guild, then guild master first and higher ranks before lower, then by name
table.sort(onlineList, function(a, b)
if a.guild ~= b.guild then return (a.guild or "") < (b.guild or "") end
local ra, rb = tonumber(a.rankIndex) or 99, tonumber(b.rankIndex) or 99
if ra ~= rb then return ra < rb end
return a.name < b.name
end)
RenderScrollList()
SideGuilds.Render()
EventSync.Side.Render()
end)
end
-- The same clicks as in the Members table (right = menu, Shift + left = whisper)
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
-- 8. NETWORK RECEIVER (STABLE CHANNELS + WHITELIST)
-- ============================================================================
local NetworkListener = CreateFrame("Frame")
NetworkListener:RegisterEvent("CHAT_MSG_ADDON")
NetworkListener:RegisterEvent("PLAYER_LOGIN")
NetworkListener:RegisterEvent("ADDON_LOADED")
NetworkListener:RegisterEvent("PLAYER_GUILD_UPDATE")
NetworkListener:RegisterEvent("GUILD_ROSTER_UPDATE")
-- Right after login GetGuildInfo() often returns nil, so we send PING only once the guild is known
local announced, announcedGuild = false, nil
-- Sync after login, once per session, right after the first PING (in steps, so not everything goes at once).
-- After 14 s a repeat for a relay that has only just found other guilds (e.g. alone online in their guild).

function EventSync.LoginSync()
if EventSync.loginSynced then return end
EventSync.loginSynced = true
addonTable.Sync.StartLoginLock()
local function SyncAll()
Most.RequestHistory()
Mute.Request()
C_Timer.After(2, function() EventSync.Request(true) end)
C_Timer.After(4, Roster.RequestStale)
C_Timer.After(6, function() addonTable.LFG.Request(true) end)
end
C_Timer.After(2, SyncAll)
C_Timer.After(14, function()
if Most.IsRelay() and Most.HasLinkedGuilds() then SyncAll() end
end)
end
-- "/jagodka sync": the same requests as after login, by hand (status, chat history, mutes, events, rosters,
-- professions, chat channel key), at most once a minute so it cannot flood the guild
EventSync.lastManualSync = -60
function EventSync.ManualSync()
local wait = 60 - (GetTime() - EventSync.lastManualSync)
if wait > 0 then return false, math.ceil(wait) end
EventSync.lastManualSync = GetTime()
SendStatusPacket("PING")
Most.RequestHistory()
Mute.Request()
C_Timer.After(2, function() EventSync.Request(true) end)
C_Timer.After(4, Roster.RequestStale)
C_Timer.After(6, addonTable.Professions.Resync)
C_Timer.After(8, addonTable.Key.Request)
C_Timer.After(10, addonTable.Officers.Request)
C_Timer.After(12, function() addonTable.LFG.Request(true) end)
return true
end
-- Leaving a dungeon or a battleground: inside, the game blocks addon messages and hides chat text from addons
-- (send result 11, secret values), so whatever came meanwhile was missed. The same sync as "/jagodka sync"
-- (at most once a minute), after a short wait for the world to load, and the channels are checked.
EventSync.instanceWatch = CreateFrame("Frame")
EventSync.instanceWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
addonTable.SafeScript(EventSync.instanceWatch, "OnEvent", "core.lua:3246", function()
local inside = IsInInstance() and true or false
local wasInside = EventSync.wasInInstance
EventSync.wasInInstance = inside
if not wasInside or inside or not EventSync.loginSynced then return end
C_Timer.After(5, function()
if not Most.GetChannelId() or (addonTable.Key.HasKey() and not addonTable.Key.ChannelId()) then Most.JoinChannel() end
local ok = EventSync.ManualSync()
addonTable.Monitor.Note("Left an instance: " .. (ok and "sync started (as /jagodka sync)" or "sync skipped (one ran less than a minute ago)"))
end)
end)
-- The "Sync now" button in Monitoring (monitor.lua) does the same
addonTable.ManualSync = EventSync.ManualSync
-- "Remind outdated" in Monitoring (officers): one UPD packet with my version to all guilds (GUILD, and the
-- relays pass it on like any packet). Receivers show the update note only when their version is older and
-- the sender is an officer by the guild rosters (update.lua). At most every UPDATE_REMIND_COOLDOWN seconds.
EventSync.UPDATE_REMIND_COOLDOWN, EventSync.lastUpdateRemind = 300, -300
-- "Chat test" in Monitoring (officers): one CTEST packet to all guilds (GUILD and the relays); everyone with the
-- addon shows the request to write on each community chat, when it comes from an officer by the rosters.
-- At most every 5 minutes.
EventSync.lastChatTest = -300
function addonTable.SendChatTest()
if not IsPlayerOfficer() then return false end
local wait = 300 - (GetTime() - EventSync.lastChatTest)
if wait > 0 then return false, math.ceil(wait) end
EventSync.lastChatTest = GetTime()
SendJagodkaNetworkPacket("CTEST", "1", "high")
addonTable.Officers.ShowChatTest()
return true
end
-- Announcement (Monitoring, officers; 0.15.2): the officer's own text to everyone with the addon (CANN to GUILD
-- and through the relays, like CTEST), shown as the big message (officers.lua). At most 180 bytes (one packet
-- through the relays), no formatting codes, at most every 5 minutes. Returns ok, wait or error text.
EventSync.ANNOUNCE_MAX, EventSync.lastAnnounce = 180, -300
function addonTable.SendAnnouncement(text)
if not IsPlayerOfficer() then return false, nil, "officers only" end
text = Most.Plain(tostring(text or "")):gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n\n+", "\n")
if text == "" then return false, nil, "write something first" end
if #text > EventSync.ANNOUNCE_MAX then return false, nil, "too long (" .. #text .. " / " .. EventSync.ANNOUNCE_MAX .. " bytes)" end
local wait = 300 - (GetTime() - EventSync.lastAnnounce)
if wait > 0 then return false, math.ceil(wait) end
EventSync.lastAnnounce = GetTime()
SendJagodkaNetworkPacket("CANN", Most.EncodeField(text), "high")
addonTable.Officers.ShowAnnouncement(text, Most.MyName())
return true
end
function addonTable.SendUpdateReminder()
if not IsPlayerOfficer() then return false end
local wait = EventSync.UPDATE_REMIND_COOLDOWN - (GetTime() - EventSync.lastUpdateRemind)
if wait > 0 then return false, math.ceil(wait) end
EventSync.lastUpdateRemind = GetTime()
SendJagodkaNetworkPacket("UPD", ADDON_VERSION, "high")
return true
end
local function TryAnnounce()
if announced then return end
if not IsPlayerGuildAllowed(GetGuildInfo("player")) then return end
announced, announcedGuild = true, GetGuildInfo("player")
AddMyselfToActiveList()
SendStatusPacket("PING")
UpdateScrollList()
EventSync.LoginSync()
end
-- Members of my guild according to Blizzard's roster: name -> true (online) / false (offline).
-- Nobody outside the roster can pose as my guild, and a logged-out relay is skipped at once.
local myGuildRoster, myGuildRosterLoaded, spoofWarned = {}, false, {}
local function RefreshMyGuildRoster()
local n = (_G.GetNumGuildMembers and _G.GetNumGuildMembers()) or 0
if n == 0 then return end
wipe(myGuildRoster)
for i = 1, n do
local fullName, _, _, _, _, _, _, _, isOnline = _G.GetGuildRosterInfo(i)
if fullName then myGuildRoster[Most.PlayerKey(fullName)] = isOnline and true or false end
end
myGuildRosterLoaded = true
end
-- Missing from the roster also = offline (with "show offline" turned off logged-out players leave the list)
Most.SetGuildmateOnlineCheck(function(name)
if not myGuildRosterLoaded then return nil end
return myGuildRoster[name] == true
end)
-- Only a NEWER version is reported: once per version (not per player), with the update window. Players with
-- an older version are not reported at all; with many players it flooded the chat and slowed the game.
local warnedVersions = {}
local function CheckPlayerVersion(name, version)
if name == Most.MyName() or not version or warnedVersions[version] then return end
if CompareVersions(version, ADDON_VERSION) <= 0 then return end
warnedVersions[version] = true
local text = name .. " has a newer addon version (" .. version .. ") - please update yours (" .. ADDON_VERSION .. ")."
addonTable.Update.Show(version)
Most.AddSystem(text)
if _G.DEFAULT_CHAT_FRAME then _G.DEFAULT_CHAT_FRAME:AddMessage("|cffbf40ff[Jagodka]|r |cffff5555" .. text .. "|r") end
end
-- Removes players who have not sent a signal for a long time (logged out), so the list = really online
local function PruneOfflinePlayers()
local now, myName = GetTime(), Most.MyName()
local changed = false
local myGuild = GetGuildInfo("player")
-- Quiet signals (0.15.3): a guildmate who signals every 10 minutes is kept QUIET_KEEP, the guild roster still
-- removes a logged-out one at once; other guilds' players as before
local ownKeep = (myGuildRosterLoaded and Most.QuietAllowed()) and Most.QUIET_KEEP or Most.ONLINE_TIMEOUT
for i = #activePlayers, 1, -1 do
local p = activePlayers[i]
-- A guildmate logged out according to the roster is removed at once, others after no signal
-- A fresh signal beats the roster: after a quick relog the roster may still say "offline"
local offlineInRoster = p.guild == myGuild and myGuildRosterLoaded and myGuildRoster[p.name] ~= true and now - (p.lastSeen or 0) > 30
-- The same for another guild's player (e.g. its relay) once that guild's roster says offline (Roster.IsOnline)
or (p.guild ~= myGuild and Roster.IsOnline(p.name, p.guild) == false and now - (p.lastSeen or 0) > 30)
-- My own other character (the account plays one at a time), e.g. still listed as its guild's relay
or Roster.IsMyOtherCharacter(p.name)
if p.name ~= myName and (offlineInRoster or (now - (p.lastSeen or 0)) > (p.guild == myGuild and ownKeep or Most.ONLINE_TIMEOUT)) then table.remove(activePlayers, i) changed = true end
end
if changed then UpdateScrollList() if MainFrame:IsShown() then UpdateMainTable() UpdateGuildTable() end end
end
-- CHAT_MSG_ADDON: prefix, text, channel, sender
addonTable.SafeScript(NetworkListener, "OnEvent", "core.lua:3342", function(self, event, prefix, text, channel, sender)
if event == "ADDON_LOADED" and prefix == addonName then
-- Events from events.lua (old ones from before 0.14.0 are dropped there)
eventsList = addonTable.Events.Load()
return
end
if event == "PLAYER_LOGIN" then
C_ChatInfo.RegisterAddonMessagePrefix("JagodkaComm")
if _G.C_GuildInfo and _G.C_GuildInfo.GuildRoster then _G.C_GuildInfo.GuildRoster() elseif _G.GuildRoster then _G.GuildRoster() end
TryAnnounce()
-- We join the channel with a delay so it does not take /1 before the General channel
C_Timer.After(8, function()
Most.JoinChannel()
-- The channel is only used to find other guilds
C_Timer.After(2, Most.Discover)
end)
-- "I am online" signal every minute (no answer expected) + cleanup of logged-out players
C_Timer.NewTicker(60, function()
-- Quiet online signals (0.15.3, bridge.lua): most players say it every 10 minutes once nearly all have 0.15.3
if announced then AddMyselfToActiveList() if Most.ShouldSendPong() then SendStatusPacket("PONG") end end
-- Another addon (or a disconnect) may have removed us from the global channel or the chat channel, so we
-- come back. The chat channel is checked on its own: before, it was retried only with the public one.
-- 0.15.4: tries spaced out, 1, 2, 4, 8 and then every 10 minutes (was every minute): after a relog the server
-- sometimes refuses our channels for a while (NOT_ALLOWED_IN_CHANNEL, INVALID_NAME), and asking again every
-- minute may keep that going. Back on both channels = the next problem starts from 1 minute again.
local keyMissing = addonTable.Key.HasKey() and not addonTable.Key.ChannelId()
if not Most.GetChannelId() or keyMissing then
EventSync.joinTries = (EventSync.joinTries or 0) + 1
if GetTime() >= (EventSync.nextJoinAt or 0) then
EventSync.nextJoinAt = GetTime() + math.min(600, 60 * 2 ^ math.min(EventSync.joinTries - 1, 4)) - 5
addonTable.Monitor.Channel("Not on the " .. (keyMissing and "chat" or "public") .. " channel, joining again (try " .. EventSync.joinTries .. "; " .. Most.ChannelListText() .. ")")
Most.JoinChannel()
end
else
EventSync.joinTries, EventSync.nextJoinAt = 0, 0
end
PruneOfflinePlayers()
end)
-- Guild roster refreshed every 20 s to quickly learn who logged out (e.g. the relay)
C_Timer.NewTicker(20, function()
if not IsInGuild() then return end
if _G.C_GuildInfo and _G.C_GuildInfo.GuildRoster then _G.C_GuildInfo.GuildRoster() elseif _G.GuildRoster then _G.GuildRoster() end
end)
Most.AddSystem("Jagodka Community ready. The global channel links all listed guilds.")
UpdateChatTabVisuals()
elseif event == "PLAYER_GUILD_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
if event == "PLAYER_GUILD_UPDATE" then Most.ResetGuild() end
-- Guild change (leaving or new guild): another PING with the new guild, so others know it at once
local g = GetGuildInfo("player")
if announced and g ~= announcedGuild and (g or not IsInGuild()) then announced = false end
RefreshMyGuildRoster()
EventSync.UpdateMonitoringTab()
TryAnnounce()
PruneOfflinePlayers()
elseif event == "CHAT_MSG_ADDON" and not Most.IsSecret(prefix, text, sender) and prefix == "JagodkaComm" then
-- The bridge forwards the packet to other guilds and extracts the real sender from a forwarded one
local senderName = Most.PlayerKey(sender)
text, channel, senderName = Most.Route(text, channel, senderName)
if not text then return end
sender = senderName
local myName = Most.MyName()
local pType, payload = strsplit(":", text, 2)
if not pType or not payload then return end
-- No formatting codes in data from others (chat: bridge.lua keeps valid links in it)
if pType ~= "GMSG" and pType ~= "HIST" then payload = Most.Plain(payload) end
-- Chat messages and history: bridge.lua
if Most.HandlePacket(pType, payload, channel, senderName, sender) then return end
-- Guild rosters: roster.lua
if Roster.HandlePacket(pType, payload, senderName) then return end
-- Chat mutes: mute.lua
if Mute.HandlePacket(pType, payload, senderName, sender) then return end
-- Notes from other guilds: notes.lua
if addonTable.Notes.HandlePacket(pType, payload, senderName) then return end
-- Professions: professions.lua
if addonTable.Professions.HandlePacket(pType, payload, senderName) then return end
-- Chat channel key: key.lua
if addonTable.Key.HandlePacket(pType, payload, senderName) then return end
-- Officers chat key and history, direct whispers between officers only: officers.lua
if addonTable.Officers.HandlePacket(pType, payload, senderName, channel) then return end
if pType == "PING" or pType == "PONG" then
local lvl, cls, gld, rnk, ver, rIdx, zone = strsplit(":", payload, 7)
if not IsPlayerGuildAllowed(gld) then addonTable.Monitor.Note("Ignored " .. pType .. " from " .. senderName .. ": guild not listed (" .. tostring(gld) .. ")") return end
-- Someone claims another listed guild but is not in its recent whole roster -> rejected (and taken off the list)
if gld ~= GetGuildInfo("player") and senderName ~= myName and Roster.IsMember(senderName, gld) == false then
local known = GetPlayerIndex(senderName)
if known then table.remove(activePlayers, known) UpdateScrollList() end
if not spoofWarned[senderName] then
spoofWarned[senderName] = true
addonTable.Monitor.Note("Ignored " .. senderName .. ": claims guild " .. gld .. " but is not in its roster")
end
return
end
-- Someone claims to be in my guild but is not in its roster -> rejected
if gld == GetGuildInfo("player") and senderName ~= myName and myGuildRosterLoaded and myGuildRoster[senderName] == nil then
if not spoofWarned[senderName] then
spoofWarned[senderName] = true
addonTable.Monitor.Note("Ignored " .. senderName .. ": claims your guild but is not in its roster")
if _G.DEFAULT_CHAT_FRAME then _G.DEFAULT_CHAT_FRAME:AddMessage("|cffbf40ff[Jagodka]|r |cffff5555" .. senderName .. " claims to be in your guild but is not in its roster - ignored.|r") end
end
return
end
CheckPlayerVersion(senderName, ver)
local existingIndex = GetPlayerIndex(senderName)
local playerData = { name = senderName, level = lvl, class = cls, guild = gld or "Brak", rank = rnk or "Brak", rankIndex = tonumber(rIdx), version = ver, zone = DecodeField(zone), lastSeen = GetTime() }
-- The regular signal of a player we know with nothing new (most of them, every minute from each player):
-- only the time is kept, no redrawing (with hundreds online the tables were redrawn several times a second)
local old = existingIndex and activePlayers[existingIndex]
local same = old and old.level == playerData.level and old.guild == playerData.guild and old.rank == playerData.rank
and old.rankIndex == playerData.rankIndex and old.version == playerData.version and old.zone == playerData.zone and old.class == playerData.class
if existingIndex then activePlayers[existingIndex] = playerData else table.insert(activePlayers, playerData) end
if not same then
UpdateScrollList()
if UpdateMainTable then UpdateMainTable() end
if MainFrame:IsShown() then UpdateGuildTable() end
end
-- Only the relay answers, by whisper to the greeter (several PINGs during a relog = one answer). With hundreds
-- of players everyone answering would flood the newcomer; they learn the relay at once and the rest from
-- the regular status packets within a minute.
if pType == "PING" and senderName ~= myName and Most.IsRelay() and not EventSync.pongPending[senderName] then
EventSync.pongPending[senderName] = true
C_Timer.After(0.2 + math.random() * 1.3, function()
EventSync.pongPending[senderName] = nil
SendStatusPacket("PONG", senderName)
addonTable.Professions.SendTo(senderName)
end)
end
else
-- Sender from their status packet or, for most players of other guilds, from the guild rosters
local senderInfo = Most.FindKnownPlayer(senderName)
if not senderInfo and senderName ~= myName then addonTable.Monitor.Note("Ignored " .. pType .. " from " .. senderName .. ": sender not known yet") return end
-- Officer by the guild's roster, not by the rank they send
local senderGuild = senderInfo and senderInfo.guild or GetGuildInfo("player")
local senderIsOfficer
if senderName == myName then senderIsOfficer = IsPlayerOfficer() else senderIsOfficer = senderInfo ~= nil and IsKnownOfficer(senderName, senderInfo.guild) end
if pType == "CANN" then
-- An officer's announcement (0.15.2): the big message for everyone, from an officer by the rosters
if senderName ~= myName and senderIsOfficer then addonTable.Officers.ShowAnnouncement(Most.Plain(Most.DecodeField(payload) or ""), senderName) end
elseif pType == "CTEST" then
-- An officer's chat test request: the big message for everyone (officers.lua); mine was shown when sent
if senderName ~= myName and senderIsOfficer then addonTable.Officers.ShowChatTest() end
elseif pType == "UPD" then
-- An officer's reminder to update: only for an older version than theirs (update.lua)
if senderName ~= myName and senderIsOfficer and CompareVersions(ADDON_VERSION, payload) < 0 then addonTable.Update.Remind(payload) end
else
-- Events (EH/ED/ES/EK/EX, sync EQ/EC): events.lua. Old EV_* packets (before 0.14.0) are ignored.
if not addonTable.LFG.HandlePacket(pType, payload, senderName, channel)
and not addonTable.Discord.HandlePacket(pType, payload, senderName, channel) then
addonTable.Events.HandlePacket(pType, payload, senderName, channel)
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
-- FIX: points to the specific fourth index of the panel table
-- Events come live and after login (or the Sync button), so opening the tab asks nothing
Panels[4]:SetScript("OnShow", function()
EventSync.UpdateLockButtons()
if UpdateEventsList then UpdateEventsList() end
end)
-- The Members tab fetches missing professions (at most every 5 min, professions.lua)
-- Opening the tab asks at once for the professions of the shown page (membersView.RequestPageProfessions)
Panels[2]:HookScript("OnShow", function() membersView.profPageKey = nil end)
ShowTab(1)
-- ============================================================================
-- 9. CHAT COMMAND AND MINIMAP REGISTRATION (LibDataBroker)
-- ============================================================================
_G.SLASH_JAGODKANADINA1 = "/jagodka"
-- "/jagodka reset" = default size and the window at the center of the screen
_G.SlashCmdList["JAGODKANADINA"] = function(msg)
if msg and msg:lower():match("^%s*reset%s*$") then
if _G.JagodkiMinimapDB then _G.JagodkiMinimapDB.window = nil end
MainFrame.ApplyLayout()
MainFrame:Show()
return
end
-- "/jagodka sync" = run the sync after login again by hand (EventSync.ManualSync)
if msg and (msg:lower():match("^%s*sync%s*$") or msg:lower():match("^%s*synch%s*$")) then
local ok, wait = EventSync.ManualSync()
local text = ok and "Sync requested: status, chat history, mutes, events, rosters, professions and the chat channel key."
or ("Sync was just requested - try again in " .. wait .. " s.")
if _G.DEFAULT_CHAT_FRAME then _G.DEFAULT_CHAT_FRAME:AddMessage("|cffbf40ff[Jagodka]|r " .. text) end
return
end
-- "/jagodka key" = a new secret key for the chat channel (officers, key.lua), e.g. after someone left
if msg and msg:lower():match("^%s*key%s*$") then
local text = addonTable.Key.Create("/jagodka key", true) and "New chat channel key sent to the community." or "Only officers can create a new chat channel key."
if _G.DEFAULT_CHAT_FRAME then _G.DEFAULT_CHAT_FRAME:AddMessage("|cffbf40ff[Jagodka]|r " .. text) end
return
end
-- "/jagodka perf [on|off|reset]" = the profiler (safe.lua): on / off, and without a word the report
if msg and msg:lower():match("^%s*perf") then
local word = msg:lower():match("^%s*perf%s+(%a+)")
local P = addonTable.Perf
local out = _G.DEFAULT_CHAT_FRAME
if word == "on" or word == "reset" then P.Start() if out then out:AddMessage("|cffbf40ff[Jagodka]|r Profiler on. Play a while, then /jagodka perf for the report, /jagodka perf off to stop.") end
elseif word == "off" then P.stoppedAt = GetTime() P.Stop() if out then out:AddMessage("|cffbf40ff[Jagodka]|r Profiler off. /jagodka perf shows what it measured.") end
elseif out then for _, line in ipairs(P.Report()) do out:AddMessage("|cffbf40ff[Jagodka]|r " .. line) end end
return
end
-- "/jagodka tab" = recreate the "Jagodki Nadina" tab in the game chat (chattab.lua)
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
icon = "Interface\\AddOns\\jagodka\\Media\\blueberry.tga",
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
-- Registered only after ADDON_LOADED, because SavedVariables are not loaded before that
local MinimapLoader = CreateFrame("Frame")
MinimapLoader:RegisterEvent("ADDON_LOADED")
addonTable.SafeScript(MinimapLoader, "OnEvent", "core.lua:3552", function(self, event, loadedName)
if loadedName ~= addonName then return end
_G.JagodkiMinimapDB = _G.JagodkiMinimapDB or {}
_G.JagodkiMinimapDB.minimap = _G.JagodkiMinimapDB.minimap or { hide = false }
-- Saved position and scale of the main window
local win = _G.JagodkiMinimapDB.window
if win and tonumber(win.w) then MainFrame.ApplyLayout(win.w, win.h, win.left, win.top) end
icon:Register("JagodkiNadina", JagodkiLDB, _G.JagodkiMinimapDB.minimap)
self:UnregisterEvent("ADDON_LOADED")
end)
