-- ============================================================================
-- PROFESSIONS: icons and skill levels in the Members table
-- ============================================================================
--  * The game gives skill levels only for your own character, so every addon sends its own.
--  * PROF goes over GUILD and relays at login and after a change (checked once a minute), and by
--    whisper in answer to a PING, so a fresh login gets the data of everyone online.
--  * Format: "A=300/300,H=285/300" with profession codes rather than names, so clients in different
--    languages understand each other; "-" = no professions.
--  * Received data is kept in JagodkiChatDB.professions, so it also shows for offline players.
--    Players without the addon stay unknown.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local GetGuildInfo = _G.GetGuildInfo
local GetServerTime = _G.GetServerTime
local UnitName = _G.UnitName
local date = _G.date
local ipairs, pairs, tonumber = _G.ipairs, _G.pairs, _G.tonumber
local table = _G.table

local Most = addonTable.Most

local CHECK_INTERVAL = 60    -- how often we check our own skills and send changes (s)
local FIRST_SEND_DELAY = 6   -- first send after login (s)
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

local function DisplayName(def) return (_G.GetSpellInfo(def.spell)) or def.name end
local function IconOf(def) return select(3, _G.GetSpellInfo(def.spell)) or UNKNOWN_ICON end

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
local function ScanOwn()
    local map, found, collapsed = NameToCode(), {}, false
    for i = 1, (_G.GetNumSkillLines and _G.GetNumSkillLines() or 0) do
        local name, isHeader, isExpanded, rank, _, _, maxRank = _G.GetSkillLineInfo(i)
        if isHeader then
            if not isExpanded then collapsed = true end
        elseif map[name] then
            found[map[name]] = { rank, maxRank }
        end
    end
    if collapsed then
        local mine = known[UnitName("player")]
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
    known[UnitName("player")] = { p = list, ts = GetServerTime() }
    return Encode(list)
end

local function SendOwnIfChanged()
    if not ctx or not ctx.isGuildAllowed((GetGuildInfo("player"))) then return end
    local payload = SaveOwn()
    if payload ~= lastSent then
        lastSent = payload
        Most.Send("PROF", payload, "low")
        if ctx.onChanged then ctx.onChanged() end
    end
end

-- core.lua calls this when answering a PING
function Professions.SendTo(name)
    Most.Whisper(name, "PROF", SaveOwn(), "low")
end

-- ============================================================================
-- RECEIVING
-- ============================================================================
local function IsAllowedPlayer(name)
    for _, p in ipairs(ctx.activePlayers) do
        if p.name == name then return ctx.isGuildAllowed(p.guild) end
    end
    return false
end

-- Called from core.lua; returns true if the packet was handled
function Professions.HandlePacket(pType, payload, senderName)
    if pType ~= "PROF" then return false end
    if senderName == UnitName("player") or not IsAllowedPlayer(senderName) then return true end
    local valid, list = {}, {}
    for _, def in ipairs(PROFESSIONS) do valid[def.code] = true end
    for code, rank, maxRank in payload:gmatch("(%u)=(%d+)/(%d+)") do
        if valid[code] then list[code] = { tonumber(rank), tonumber(maxRank) } end
    end
    known[senderName] = { p = list, ts = GetServerTime() }
    if ctx.onChanged then ctx.onChanged() end
    return true
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

function Professions.Init(c) ctx = c end

-- ============================================================================
-- EVENTS
-- ============================================================================
local Listener = CreateFrame("Frame")
Listener:RegisterEvent("ADDON_LOADED")
Listener:RegisterEvent("PLAYER_LOGIN")
Listener:RegisterEvent("PLAYER_GUILD_UPDATE")
Listener:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        _G.JagodkiChatDB = _G.JagodkiChatDB or {}
        _G.JagodkiChatDB.professions = _G.JagodkiChatDB.professions or {}
        known = _G.JagodkiChatDB.professions
    elseif event == "PLAYER_LOGIN" then
        C_Timer.After(FIRST_SEND_DELAY, SendOwnIfChanged)
        C_Timer.NewTicker(CHECK_INTERVAL, SendOwnIfChanged)
    elseif event == "PLAYER_GUILD_UPDATE" then
        -- The new guild has not heard our professions yet
        lastSent = nil
    end
end)
