-- ============================================================================
-- MUTE: mute on the shared chat (officers and GMs of listed guilds)
-- ============================================================================
--  * A muted player cannot write on the community chat (addon window), and their /g lines
--    are not carried to other guilds. Each client rejects their messages on its own
--    (bridge.lua, Ingest), so this does not depend on who the relay is.
--  * Permissions: mute - officer (cannot mute another officer or themselves), GM - anyone
--    except themselves; unmute - any officer. Checked locally and by every packet receiver.
--  * Mute requires a reason (dialog with a text field); the reason shows in the icon tooltip
--    next to the name in the Members tab and in the chat notice.
--  * State: JagodkiChatDB.mutes[name] = { m = true/false, ts = server time, by = officer, r = reason }.
--    An unmute is also an entry (m = false), so an older mute does not return through sync.
--    The entry with the newer time wins.
--  * Packets: MUTE (a change, over GUILD and relays, or by whisper during sync),
--    MREQ (request after login), MCLAIM (someone is already answering the request).
--  * Right click on a name in the addon chat: Whisper, Invite to group, Mute / Unmute.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local GetServerTime = _G.GetServerTime
local GetGuildInfo = _G.GetGuildInfo
local UnitName = _G.UnitName
local strsplit = _G.strsplit
local date = _G.date
local pairs, ipairs, tostring, tonumber = _G.pairs, _G.ipairs, _G.tostring, _G.tonumber
local table, math = _G.table, _G.math

local Most = addonTable.Most
local Enc, Dec = Most.EncodeField, Most.DecodeField

local UNMUTE_KEEP_DAYS = 30 -- an unmute entry is removed after this many days
local REASON_MAX_LETTERS = 60 -- the reason fits in one packet (255 bytes) even with Polish characters
local ICON = "Interface\\RaidFrame\\ReadyCheck-NotReady"

local Mute = {}
addonTable.Mute = Mute

-- Context from core.lua: activePlayers, isGuildAllowed, isRankOfficer, isMeOfficer, onChanged
local ctx = nil
function Mute.Init(c) ctx = c end

local mutes = {} -- replaced with JagodkiChatDB.mutes after the addon loads

local function MyName() return UnitName("player") end

function Mute.IsMuted(name)
    local m = name and mutes[name]
    return m ~= nil and m.m == true
end

-- Mute entry ({ by, ts, r }) or nil when the player is not muted
function Mute.Info(name)
    return Mute.IsMuted(name) and mutes[name] or nil
end

-- ============================================================================
-- PERMISSIONS
-- ============================================================================
-- Player from the online list (their status packet) or nil
local function FindPlayer(name)
    if not ctx then return nil end
    for _, p in ipairs(ctx.activePlayers) do
        if p.name == name and ctx.isGuildAllowed(p.guild) then return p end
    end
    return nil
end

-- Player's rank (name, index): me, online players with the addon, then guild rosters (also offline)
local function RankOf(name)
    if name == MyName() then
        local _, rankName, rankIndex = GetGuildInfo("player")
        return rankName, rankIndex
    end
    local p = FindPlayer(name)
    if p then return p.rank, tonumber(p.rankIndex) end
    if addonTable.Roster then return addonTable.Roster.GetRank(name) end
    return nil, nil
end

-- Officer or GM of a listed guild. The acting officer must be online (their status packet).
function Mute.IsOfficer(name)
    if not ctx then return false end
    if name == MyName() then return ctx.isMeOfficer() end
    local p = FindPlayer(name)
    return p ~= nil and ctx.isRankOfficer(p.rank, tonumber(p.rankIndex))
end

local function IsGM(name)
    local _, rankIndex = RankOf(name)
    return rankIndex == 0 and Mute.IsOfficer(name)
end

-- The target's rank may be unknown (guild without a synced roster), in which case we do not block
local function IsTargetOfficer(name)
    local rankName, rankIndex = RankOf(name)
    if not rankName and not rankIndex then return false end
    return ctx ~= nil and ctx.isRankOfficer(rankName, rankIndex)
end

function Mute.CanMute(by, target)
    if not target or by == target or not Mute.IsOfficer(by) then return false end
    return IsGM(by) or not IsTargetOfficer(target)
end

function Mute.CanUnmute(by)
    return Mute.IsOfficer(by)
end

-- ============================================================================
-- CHANGES
-- ============================================================================
-- Reason: without formatting codes or the packet separator
local function CleanReason(text)
    return ((text or ""):gsub("[|:\n]", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Saves the entry if it is newer than the known one
local function Apply(name, on, ts, by, reason)
    local cur = mutes[name]
    if cur and (cur.ts or 0) >= ts then return false end
    mutes[name] = { m = on, ts = ts, by = by, r = on and reason or nil }
    if ctx and ctx.onChanged then ctx.onChanged() end
    return true
end

local function Encode(name, m)
    return table.concat({ Enc(name), m.m and "1" or "0", tostring(m.ts), Enc(m.by), Enc(m.r or "") }, ":")
end

-- Mute / unmute (checks permissions locally; receivers check them again)
function Mute.Set(name, on, reason)
    if addonTable.Sync.Blocked() then return end
    local me = MyName()
    reason = CleanReason(reason)
    if on and (reason == "" or not Mute.CanMute(me, name)) then return end
    if not on and not Mute.CanUnmute(me) then return end
    -- Time at least 1 s newer than the known entry, so the change wins even with fast clicking
    local ts = math.max(GetServerTime(), ((mutes[name] and mutes[name].ts) or 0) + 1)
    if not Apply(name, on, ts, me, reason) then return end
    Most.Send("MUTE", Encode(name, mutes[name]), "high")
    -- A regular message on the community chat (like "Event created by ..."), relays also post it to /g
    local text = on and ("Muted " .. name .. " on the community chat (reason: " .. reason .. ")")
        or ("Unmuted " .. name .. " on the community chat")
    Most.Publish("Ogolny", text, "A", me, (GetGuildInfo("player")))
end

-- Reason dialog; mute only after OK (button active when the reason is not empty)
_G.StaticPopupDialogs["JAGODKA_MUTE_REASON"] = {
    text = "Mute %s on the community chat?\nReason:",
    button1 = "Mute",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = REASON_MAX_LETTERS,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self)
        local edit = self.editBox or self.EditBox
        edit:SetText("")
        edit:SetFocus()
        local ok = self.button1 or self.Button1
        if ok then ok:Disable() end
    end,
    EditBoxOnTextChanged = function(self)
        local ok = self:GetParent().button1 or self:GetParent().Button1
        if ok then ok:SetEnabled(CleanReason(self:GetText()) ~= "") end
    end,
    OnAccept = function(self, data)
        Mute.Set(data, true, (self.editBox or self.EditBox):GetText())
    end,
    EditBoxOnEnterPressed = function(self, data)
        if CleanReason(self:GetText()) == "" then return end
        Mute.Set(data, true, self:GetText())
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

function Mute.AskReason(name)
    if addonTable.Sync.Blocked() then return end
    _G.StaticPopup_Show("JAGODKA_MUTE_REASON", name, nil, name)
end

-- ============================================================================
-- SYNC (same pattern as chat history: one random person answers)
-- ============================================================================
local pendingRequests = {} -- requester -> true until someone else has answered

function Mute.Request()
    local newest = 0
    for _, m in pairs(mutes) do
        if (m.ts or 0) > newest then newest = m.ts end
    end
    Most.Send("MREQ", tostring(newest), "low")
end

local function HandleRequest(sender, rawSender, since)
    since = tonumber(since) or 0
    local list = {}
    for name, m in pairs(mutes) do
        if (m.ts or 0) > since then table.insert(list, Encode(name, m)) end
    end
    if #list == 0 then return end
    pendingRequests[sender] = true
    C_Timer.After(0.5 + math.random() * 2, function()
        if not pendingRequests[sender] then return end
        pendingRequests[sender] = nil
        Most.Send("MCLAIM", sender, "low")
        for _, payload in ipairs(list) do Most.Whisper(rawSender, "MUTE", payload) end
    end)
end

-- Called from core.lua; returns true if the packet was handled
function Mute.HandlePacket(pType, payload, senderName, rawSender)
    if pType == "MUTE" then
        local name, flag, ts, by, reason = strsplit(":", payload, 5)
        name, ts, by, reason = Dec(name), tonumber(ts), Dec(by), CleanReason(Dec(reason))
        if not (name and ts and by) or (flag ~= "1" and flag ~= "0") then return true end
        local on = flag == "1"
        if senderName == by then
            -- From the officer who changed the mute: the same rules as in the menu
            if (on and Mute.CanMute(senderName, name)) or (not on and Mute.CanUnmute(senderName)) then
                Apply(name, on, ts, by, reason)
            end
        elseif FindPlayer(senderName) then
            -- Forwarded during sync (the officer may be offline): from a known listed player
            Apply(name, on, ts, by, reason)
        end
        return true
    elseif pType == "MREQ" then
        if senderName ~= MyName() and FindPlayer(senderName) then HandleRequest(senderName, rawSender, payload) end
        return true
    elseif pType == "MCLAIM" then
        if senderName ~= MyName() then pendingRequests[payload] = nil end
        return true
    end
    return false
end

-- ============================================================================
-- ICON NEXT TO THE NAME (Members tab), tooltip with the reason
-- ============================================================================
local function ShowIconTooltip(icon)
    local m = Mute.Info(icon.name)
    if not m then return end
    local tip = _G.GameTooltip
    tip:SetOwner(icon, "ANCHOR_RIGHT")
    tip:AddLine("Muted on the community chat", 1, 0.33, 0.33)
    tip:AddLine("By: " .. tostring(m.by), 1, 1, 1)
    if m.ts then tip:AddLine("Since: " .. date("%Y-%m-%d %H:%M", m.ts), 0.7, 0.7, 0.7) end
    tip:AddLine("Reason: " .. (m.r or "-"), 1, 0.82, 0, true)
    tip:Show()
end

-- core.lua calls this when drawing a row: icon right after the name, for muted players only
function Mute.DecorateName(row, nameText, name)
    local icon = row.muteIcon
    if not Mute.IsMuted(name) then
        if icon then icon:Hide() end
        return
    end
    if not icon then
        icon = CreateFrame("Frame", nil, row)
        icon:SetSize(12, 12)
        icon.tex = icon:CreateTexture(nil, "OVERLAY")
        icon.tex:SetAllPoints()
        icon.tex:SetTexture(ICON)
        icon:EnableMouse(true)
        icon:SetScript("OnEnter", ShowIconTooltip)
        icon:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
        row.muteIcon = icon
    end
    icon.name = name
    icon:ClearAllPoints()
    icon:SetPoint("LEFT", nameText, "LEFT", nameText:GetStringWidth() + 3, 0)
    icon:Show()
end

-- ============================================================================
-- MENU ON A NAME IN THE ADDON CHAT (right click; left click = whisper)
-- ============================================================================
local NameMenu = CreateFrame("Frame", "JagodkiChatNameMenu", _G.UIParent, "UIDropDownMenuTemplate")
local menuName = nil
_G.UIDropDownMenu_Initialize(NameMenu, function(self, level)
    if not menuName then return end
    local target, me = menuName, MyName()
    local muted = Mute.IsMuted(target)
    local info = _G.UIDropDownMenu_CreateInfo()
    info.text = muted and (target .. " |cffff5555(muted)|r") or target
    info.isTitle, info.notCheckable = true, true
    _G.UIDropDownMenu_AddButton(info, level)
    info = _G.UIDropDownMenu_CreateInfo()
    info.text, info.notCheckable = "Whisper", true
    info.func = function() _G.ChatFrame_SendTell(target) end
    _G.UIDropDownMenu_AddButton(info, level)
    info = _G.UIDropDownMenu_CreateInfo()
    info.text, info.notCheckable = "Invite to group", true
    -- Newer clients have C_PartyInfo.InviteUnit, older only InviteUnit (as in the Members menu)
    info.func = function()
        local invite = (_G.C_PartyInfo and _G.C_PartyInfo.InviteUnit) or _G.InviteUnit
        if invite then invite(target) end
    end
    _G.UIDropDownMenu_AddButton(info, level)
    if (muted and Mute.CanUnmute(me)) or (not muted and Mute.CanMute(me, target)) then
        info = _G.UIDropDownMenu_CreateInfo()
        info.text, info.notCheckable = muted and "Unmute" or "Mute on community chat", true
        info.func = function()
            if muted then Mute.Set(target, false) else Mute.AskReason(target) end
        end
        _G.UIDropDownMenu_AddButton(info, level)
    end
    info = _G.UIDropDownMenu_CreateInfo()
    info.text, info.notCheckable = "Cancel", true
    info.func = function() _G.CloseDropDownMenus() end
    _G.UIDropDownMenu_AddButton(info, level)
end, "MENU")

-- core.lua attaches the addon chat window (names are links from Most.FormatEntry)
function Mute.AttachChat(frame)
    frame:EnableMouse(true)
    if frame.SetHyperlinksEnabled then frame:SetHyperlinksEnabled(true) end
    frame:SetScript("OnHyperlinkClick", function(self, link, text, button)
        local kind, rest = strsplit(":", link, 2)
        if kind ~= "player" then
            -- Item, spell etc. links: the game's default handling (tooltip)
            if _G.SetItemRef then _G.SetItemRef(link, text, button, self) end
            return
        end
        local name = strsplit(":", rest or "")
        if not name or name == "" or name == MyName() then return end
        if button == "RightButton" then
            menuName = name
            _G.ToggleDropDownMenu(1, nil, NameMenu, "cursor", 0, 0)
        else
            _G.ChatFrame_SendTell(name)
        end
    end)
end

-- Game menu on a name (right click) in the "Jagodki Nadina - General" tab: we add Mute / Unmute.
-- New menu API (Menu.ModifyMenu); on a client without it the tab has only the regular game menu.
if _G.Menu and _G.Menu.ModifyMenu then
    _G.Menu.ModifyMenu("MENU_UNIT_FRIEND", function(owner, rootDescription, contextData)
        local name = contextData and contextData.name
        if not name then return end
        name = _G.Ambiguate(name, "none")
        -- Only in our tabs (when the game does not give the chat window, we show it everywhere, still officers only)
        if contextData.chatFrame and not addonTable.Zakladka.IsOurFrame(contextData.chatFrame) then return end
        local me, muted = MyName(), Mute.IsMuted(name)
        if muted and not Mute.CanUnmute(me) then return end
        if not muted and not Mute.CanMute(me, name) then return end
        rootDescription:CreateDivider()
        rootDescription:CreateTitle("Jagodka")
        rootDescription:CreateButton(muted and "Unmute" or "Mute on community chat", function()
            if muted then Mute.Set(name, false) else Mute.AskReason(name) end
        end)
    end)
end

-- ============================================================================
-- LOADING (SavedVariables)
-- ============================================================================
local Listener = CreateFrame("Frame")
Listener:RegisterEvent("ADDON_LOADED")
Listener:SetScript("OnEvent", function(self, event, arg1)
    if arg1 ~= addonName then return end
    _G.JagodkiChatDB = _G.JagodkiChatDB or {}
    _G.JagodkiChatDB.mutes = _G.JagodkiChatDB.mutes or {}
    mutes = _G.JagodkiChatDB.mutes
    -- Old unmute entries are no longer needed
    local cutoff = GetServerTime() - UNMUTE_KEEP_DAYS * 86400
    for name, m in pairs(mutes) do
        if not m.m and (m.ts or 0) < cutoff then mutes[name] = nil end
    end
    self:UnregisterEvent("ADDON_LOADED")
end)
