-- ============================================================================
-- NOTES: public and officer notes from the guild roster (Members tab)
-- ============================================================================
--  * Own guild: both notes come straight from the game. The officer note shows only with the game's
--    own permission (CanViewOfficerNote) and is never saved, because saved data is shared by the account.
--  * Other guilds: public note only, the game does not give their notes. Hovering over the icon whispers
--    NREQ to that guild's relay, who answers with NOTE. The last known note is kept in
--    JagodkiChatDB.publicNotes, so it also shows when nobody from that guild is online.
--  * Officer notes are never sent: a responder could not reliably check who is really an officer.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local GetGuildInfo = _G.GetGuildInfo
local GetServerTime = _G.GetServerTime
local UnitName = _G.UnitName
local Ambiguate = _G.Ambiguate
local strsplit = _G.strsplit
local ipairs = _G.ipairs
local wipe = _G.wipe

local Most = addonTable.Most
local Enc, Dec = Most.EncodeField, Most.DecodeField

local ICON = "Interface\\Icons\\INV_Misc_Note_01"
local REQUEST_COOLDOWN = 60  -- how often we ask about the same player (s)
local ANSWER_TIMEOUT = 4     -- how long the popup shows "Loading..." (s)
local POPUP_WIDTH = 260

local Notes = {}
addonTable.Notes = Notes

-- Context from core.lua: activePlayers, isGuildAllowed, parent, onChanged
local ctx = nil
local ownNotes = {}        -- own guild: name -> { public, officer }; memory only
local savedNotes = {}      -- other guilds: name -> { t = public note, ts = time }; JagodkiChatDB.publicNotes
local pending = {}         -- name -> guild of an unanswered request
local requestedAt = {}     -- name -> time of the last request
local popup = nil

local function MyGuild() return (GetGuildInfo("player")) end

local function CanViewOfficerNotes()
    local check = (_G.C_GuildInfo and _G.C_GuildInfo.CanViewOfficerNote) or _G.CanViewOfficerNote
    return check ~= nil and check() and true or false
end

local function FindPlayer(name)
    for _, p in ipairs(ctx.activePlayers) do
        if p.name == name then return p end
    end
    return nil
end

-- Offline members can be missing when "show offline" is off, so entries are overwritten, not cleared
local function RefreshOwnNotes()
    local count = (_G.GetNumGuildMembers and _G.GetNumGuildMembers()) or 0
    for i = 1, count do
        local fullName, _, _, _, _, _, public, officer = _G.GetGuildRosterInfo(i)
        if fullName then ownNotes[Ambiguate(fullName, "none")] = { public = public or "", officer = officer or "" } end
    end
end

local function HasOwnNote(name)
    local n = ownNotes[name]
    if not n then return false end
    return n.public ~= "" or (n.officer ~= "" and CanViewOfficerNotes())
end

-- Whether the icon looks active: a known note, or a chance to fetch one from another guild
local function LooksActive(member)
    if member.guild == MyGuild() then return HasOwnNote(member.name) end
    local saved = savedNotes[member.name]
    if saved then return saved.t ~= "" end
    return member.guild ~= nil and Most.GetRelayName(member.guild) ~= nil
end

-- ============================================================================
-- REQUESTS (other guilds)
-- ============================================================================
local function RequestNote(member)
    local name, guild, now = member.name, member.guild, GetServerTime()
    if not guild or not ctx.isGuildAllowed(guild) or now - (requestedAt[name] or 0) < REQUEST_COOLDOWN then return end
    local relay = Most.GetRelayName(guild)
    if not relay or relay == UnitName("player") then return end
    requestedAt[name], pending[name] = now, guild
    Most.Whisper(relay, "NREQ", Enc(name), "high")
    C_Timer.After(ANSWER_TIMEOUT, function()
        if pending[name] then
            pending[name] = nil
            if popup and popup:IsShown() and popup.member and popup.member.name == name then popup:Fill() end
        end
    end)
end

-- Called from core.lua; returns true if the packet was handled
function Notes.HandlePacket(pType, payload, senderName)
    if pType == "NREQ" then
        local sender = FindPlayer(senderName)
        local name = Dec(payload)
        local own = name and ownNotes[name]
        if sender and ctx.isGuildAllowed(sender.guild) and own then
            Most.Whisper(senderName, "NOTE", Enc(name) .. ":" .. Enc(own.public), "low")
        end
        return true
    elseif pType == "NOTE" then
        local nameEnc, textEnc = strsplit(":", payload, 2)
        local name, text = Dec(nameEnc), Dec(textEnc)
        local sender = FindPlayer(senderName)
        -- Only an answer we asked for, from someone in that guild
        if name and text and pending[name] and sender and sender.guild == pending[name] then
            pending[name] = nil
            savedNotes[name] = { t = text, ts = GetServerTime() }
            if popup and popup:IsShown() and popup.member and popup.member.name == name then popup:Fill() end
            if ctx.onChanged then ctx.onChanged() end
        end
        return true
    end
    return false
end

-- ============================================================================
-- POPUP
-- ============================================================================
local function NoteText(text)
    if not text or text == "" then return "|cff808080(empty)|r" end
    return Most.Plain(text)
end

local function PublicText(member)
    if member.guild == MyGuild() then
        local own = ownNotes[member.name]
        return own and NoteText(own.public) or "|cff808080No data|r"
    end
    local saved = savedNotes[member.name]
    if saved then return NoteText(saved.t) .. (pending[member.name] and " |cff808080(refreshing...)|r" or "") end
    if pending[member.name] then return "|cff808080Loading...|r" end
    return "|cff808080Not available - nobody from this guild answered|r"
end

local function BuildPopup()
    local f = CreateFrame("Frame", nil, ctx.parent, "BackdropTemplate")
    f:SetWidth(POPUP_WIDTH)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
    f:SetBackdropBorderColor(0.3, 0.3, 0.38, 1)
    f:Hide()
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -9)
    f.public = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.public:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -7)
    f.public:SetWidth(POPUP_WIDTH - 20)
    f.public:SetJustifyH("LEFT")
    f.officer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.officer:SetPoint("TOPLEFT", f.public, "BOTTOMLEFT", 0, -6)
    f.officer:SetWidth(POPUP_WIDTH - 20)
    f.officer:SetJustifyH("LEFT")

    function f:Fill()
        local member = self.member
        if not member then return end
        self.title:SetText(member.name)
        self.public:SetText("|cffffd100Public note:|r " .. PublicText(member))
        local height = 16 + self.title:GetStringHeight() + 7 + self.public:GetStringHeight()
        -- Own guild only, and only with the game's permission
        local own = member.guild == MyGuild() and ownNotes[member.name]
        if own and CanViewOfficerNotes() then
            self.officer:SetText("|cff00ccffOfficer note:|r " .. NoteText(own.officer))
            self.officer:Show()
            height = height + 6 + self.officer:GetStringHeight()
        else
            self.officer:Hide()
        end
        self:SetHeight(height)
    end
    return f
end

local function ShowFor(icon)
    local member = icon.member
    if not member then return end
    popup = popup or BuildPopup()
    popup.member, popup.anchor = member, icon
    if member.guild ~= MyGuild() then RequestNote(member) end
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -2)
    popup:Fill()
    popup:Show()
end

-- ============================================================================
-- ICON IN A MEMBERS ROW
-- ============================================================================
function Notes.AttachRow(row)
    local icon = CreateFrame("Frame", nil, row)
    icon:SetSize(14, 14)
    icon:EnableMouse(true)
    -- Clicks go through to the row, so its menu also works on the icon
    if icon.SetMouseClickEnabled then icon:SetMouseClickEnabled(false) end
    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints()
    icon.tex:SetTexture(ICON)
    icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetScript("OnEnter", ShowFor)
    icon:SetScript("OnLeave", function() if popup then popup:Hide() end end)
    row.noteIcon = icon
end

-- core.lua calls this when drawing a row
function Notes.UpdateRow(row, member)
    local icon = row.noteIcon
    icon.member = member
    local active = LooksActive(member)
    icon.tex:SetDesaturated(not active)
    icon.tex:SetAlpha(active and 1 or 0.3)
    -- Scrolling or paging can put someone else under the mouse
    if popup and popup:IsShown() and popup.anchor == icon and popup.member.name ~= member.name then ShowFor(icon) end
end

function Notes.Init(c) ctx = c end

-- ============================================================================
-- EVENTS
-- ============================================================================
local Listener = CreateFrame("Frame")
Listener:RegisterEvent("ADDON_LOADED")
Listener:RegisterEvent("GUILD_ROSTER_UPDATE")
Listener:RegisterEvent("PLAYER_GUILD_UPDATE")
Listener:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        _G.JagodkiChatDB = _G.JagodkiChatDB or {}
        _G.JagodkiChatDB.publicNotes = _G.JagodkiChatDB.publicNotes or {}
        savedNotes = _G.JagodkiChatDB.publicNotes
    elseif event == "PLAYER_GUILD_UPDATE" then
        -- Notes of the old guild, especially officer notes, must not stay after a guild change
        wipe(ownNotes)
    elseif not self.pending then
        -- The game can fire this event many times in a row, so we read the roster once per 2 s
        self.pending = true
        C_Timer.After(2, function() self.pending = false RefreshOwnNotes() end)
    end
end)
