-- ============================================================================
-- CHARACTER CARD: the logged-in character, top right of the main window (above Upcoming Events)
-- ============================================================================
--  * Portrait; "First Surname" (the whole width, long names too) in the class color; "Level 21 Human Warrior"; guild tag and guild;
--    the guild rank; every profession as an icon with its skill; an Armory button (the same link box
--    as in the Roster tab, armory.lua); a thin experience bar along the bottom (hidden at max level).
--  * Hover: the same in a tooltip, with the professions' names and maximum skill and the experience.
--  * Only the game's data about my own character: nothing is sent.
--  * Refreshed when the window opens and on the game's events (level, experience, guild, skills,
--    portrait), only while the window is open.
--  * core.lua puts the right column (Upcoming Events and below) under it: CharCard.frame.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local CreateFrame = _G.CreateFrame
local C_Timer = _G.C_Timer
local UnitLevel, UnitRace, UnitClass, UnitXP, UnitXPMax = _G.UnitLevel, _G.UnitRace, _G.UnitClass, _G.UnitXP, _G.UnitXPMax
local GetGuildInfo = _G.GetGuildInfo
local ipairs, math, string, table, tostring = _G.ipairs, _G.math, _G.string, _G.table, _G.tostring

local CharCard = {}
addonTable.CharCard = CharCard

local WIDTH, HEIGHT, PORTRAIT = 330, 96, 52
local MAX_PROFS = 6   -- profession icons in the bottom row (5 exist per character at most: 2 + 3)

local card = nil

-- My professions: primary first, then cooking, first aid, fishing
local function MyProfessions()
    local Most, Professions = addonTable.Most, addonTable.Professions
    if not (Most and Professions and Professions.List) then return {} end
    local primary, other = {}, {}
    for _, p in ipairs(Professions.List(Most.MyName())) do table.insert(p.primary and primary or other, p) end
    for _, p in ipairs(other) do table.insert(primary, p) end
    return primary
end

local function MaxLevel() return _G.GetMaxPlayerLevel and _G.GetMaxPlayerLevel() or 60 end

local function Render()
    if not card or not card:IsVisible() then return end
    local Most = addonTable.Most
    _G.SetPortraitTexture(card.portrait, "player")
    local className, class = UnitClass("player")
    local color = class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
    local name = Most and Most.MyName() or _G.UnitName("player")
    card.name:SetText(color and color:WrapTextInColorCode(name) or name)
    local level = UnitLevel("player")
    card.info:SetText("Level |cffffffff" .. tostring(level) .. "|r " .. tostring((UnitRace("player"))) .. " " .. tostring(className))
    local guild, rank = GetGuildInfo("player")
    if guild then
        local tag = Most and Most.GuildTag and Most.GuildTag(guild) or guild
        card.guild:SetText("|cffbf40ff" .. tag .. "|r  |cffd0b0ff" .. guild .. "|r")
        card.rank:SetText("|cff808080Rank:|r |cffffd100" .. tostring(rank) .. "|r")
    else
        card.guild:SetText("|cff808080No guild|r")
        card.rank:SetText("")
    end
    -- Armory: only characters with a surname (WoW Forever) have a page
    card.armory.name = name
    if addonTable.Armory and addonTable.Armory.Url(name) then card.armory:Show() else card.armory:Hide() end
    -- Professions: icon and skill, one after another
    local profs = MyProfessions()
    for i, item in ipairs(card.profs) do
        local p = profs[i]
        if p then
            item.icon:SetTexture(p.icon)
            item.text:SetText(p.rank)
            item:SetWidth(16 + 4 + math.ceil(item.text:GetStringWidth()))
            item:Show()
        else
            item:Hide()
        end
    end
    if #profs == 0 then card.noProfs:Show() else card.noProfs:Hide() end
    -- Experience: hidden at the maximum level (no experience to gain)
    local xp, xpMax = UnitXP("player") or 0, UnitXPMax("player") or 0
    if xpMax > 0 and level < MaxLevel() then
        card.xp:SetWidth(math.max(1, math.floor((WIDTH - 2) * xp / xpMax)))
        card.xp:Show() card.xpBack:Show()
    else
        card.xp:Hide() card.xpBack:Hide()
    end
end

local function ShowTooltip(self)
    local tip = _G.GameTooltip
    tip:SetOwner(self, "ANCHOR_LEFT")
    tip:AddLine(card.name:GetText() or "")
    tip:AddLine(card.info:GetText() or "", 0.8, 0.8, 0.8)
    tip:AddLine(card.guild:GetText() or "", 1, 1, 1)
    if card.rank:GetText() and card.rank:GetText() ~= "" then tip:AddLine(card.rank:GetText(), 1, 1, 1) end
    local xpMax = UnitXPMax("player") or 0
    if xpMax > 0 and UnitLevel("player") < MaxLevel() then
        local xp = UnitXP("player") or 0
        tip:AddLine(string.format("Experience: %d / %d (%d%%)", xp, xpMax, math.floor(xp * 100 / xpMax)), 0.75, 0.5, 1)
    end
    local profs = MyProfessions()
    if #profs > 0 then
        tip:AddLine(" ")
        for _, p in ipairs(profs) do
            tip:AddDoubleLine("|T" .. tostring(p.icon) .. ":14:14|t " .. p.name, p.rank .. "/" .. p.max, 1, 1, 1, 1, 0.82, 0)
        end
    end
    tip:Show()
end

-- core.lua: the card in the top right corner of the main window
function CharCard.Attach(parent, applyStyle)
    card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    CharCard.frame = card
    card:SetSize(WIDTH, HEIGHT)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -20, -46)
    applyStyle(card)
    card:EnableMouse(true)
    card:SetScript("OnEnter", ShowTooltip)
    card:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
    card.portrait = card:CreateTexture(nil, "ARTWORK")
    card.portrait:SetSize(PORTRAIT, PORTRAIT)
    card.portrait:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -8)
    -- Armory button in the bottom right corner, next to the professions, so long names have the whole
    -- width; its link box opens to the left (the window's edge is right)
    local armory = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    armory:SetText("Armory")
    local label = armory:GetFontString()
    armory:SetSize((label and math.ceil(label:GetStringWidth()) or 40) + 20, 20)
    armory:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -6, 7)
    armory.alignRight = true
    armory:SetScript("OnClick", function(self) if addonTable.Armory then addonTable.Armory.Open(self) end end)
    card.armory = armory
    card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.name:SetPoint("TOPLEFT", card.portrait, "TOPRIGHT", 10, -1)
    card.name:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.info = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.info:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
    card.info:SetTextColor(0.8, 0.8, 0.8)
    card.guild = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.guild:SetPoint("TOPLEFT", card.info, "BOTTOMLEFT", 0, -3)
    card.rank = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.rank:SetPoint("TOPLEFT", card.guild, "BOTTOMLEFT", 0, -3)
    for _, fs in ipairs({ card.info, card.guild, card.rank }) do fs:SetPoint("RIGHT", card, "RIGHT", -8, 0) end
    for _, fs in ipairs({ card.name, card.info, card.guild, card.rank }) do fs:SetJustifyH("LEFT") fs:SetWordWrap(false) end
    -- Professions in a row under the portrait
    card.profs = {}
    for i = 1, MAX_PROFS do
        local item = CreateFrame("Frame", nil, card)
        item:SetSize(40, 16)
        if i == 1 then item:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 8, 9)
        else item:SetPoint("LEFT", card.profs[i - 1], "RIGHT", 12, 0) end
        item.icon = item:CreateTexture(nil, "ARTWORK")
        item.icon:SetSize(16, 16) item.icon:SetPoint("LEFT", item, "LEFT", 0, 0)
        item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        item.text = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        item.text:SetPoint("LEFT", item.icon, "RIGHT", 4, 0)
        card.profs[i] = item
    end
    card.noProfs = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.noProfs:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 11)
    card.noProfs:SetText("No professions yet")
    -- Thin experience bar along the bottom edge
    card.xpBack = card:CreateTexture(nil, "BORDER")
    card.xpBack:SetHeight(2)
    card.xpBack:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 1, 1) card.xpBack:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -1, 1)
    card.xpBack:SetColorTexture(1, 1, 1, 0.06)
    card.xp = card:CreateTexture(nil, "ARTWORK")
    card.xp:SetHeight(2)
    card.xp:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 1, 1)
    card.xp:SetColorTexture(0.75, 0.25, 1, 0.9)
    card:SetScript("OnShow", Render)
    -- The game's changes; several at once (login, guild roster) = one refresh a moment later
    local pending = false
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE",
        "SKILL_LINES_CHANGED", "UNIT_PORTRAIT_UPDATE", "PLAYER_ENTERING_WORLD" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_PORTRAIT_UPDATE" and unit ~= "player" then return end
        if pending or not card:IsVisible() then return end
        pending = true
        C_Timer.After(1, function() pending = false Render() end)
    end)
end
