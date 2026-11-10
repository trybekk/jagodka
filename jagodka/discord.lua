-- ============================================================================
-- DISCORD NAMES (0.15.2): a player can share their Discord name, the others see it on hover
-- ============================================================================
--  * Settings > Profile: one field, saved for the account (all my characters share it). Empty = none.
--  * Shown as one compact line at the bottom of tooltips: the game's tooltip of a player (in the world, on
--    unit frames), the LFG tooltips; the Roster menu has "Copy Discord name".
--  * Sync, slow on purpose (nothing here is urgent), and kept for good:
--      DI name:ts:discord   my name, low priority, to GUILD and through the relays: once after saving and once
--                           per session a few minutes after login (empty discord = removed)
--      DQ count             after login, own guild only: "I know this many"; one guildmate who knows more
--                           answers (claim DC, the one-answer rule of bridge.lua) with DL whispers:
--      DL name@ts@discord;...  as many entries as fit one packet, low priority
--    Every client keeps every name it learns (JagodkiChatDB.discord.known, account-wide), the newer one wins.
--  * A live DI is taken only from the player it names; DL only from known players of our guilds.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local GetTime, GetServerTime = _G.GetTime, _G.GetServerTime
local ipairs, pairs, tostring, tonumber, type = _G.ipairs, _G.pairs, _G.tostring, _G.tonumber, _G.type
local table, math, string = _G.table, _G.math, _G.string
local C_Timer = addonTable.SafeTimer

local Discord = {}
addonTable.Discord = Discord

local MAX_LEN = 37            -- Discord names are 2-32 characters; old ones "name#1234"
local MAX_KNOWN = 5000        -- names kept at most (the oldest go first)
local ANSWER_COOLDOWN = 1800  -- the same asker gets our list at most this often (s)
local MAX_PAYLOAD = 200
local COLOR = "ff7289da"      -- Discord's blurple

local function Most() return addonTable.Most end
local function DB()
    _G.JagodkiChatDB = _G.JagodkiChatDB or {}
    local d = _G.JagodkiChatDB.discord
    if type(d) ~= "table" then d = { known = {} } _G.JagodkiChatDB.discord = d end
    d.known = d.known or {}
    return d
end

-- A valid Discord name, or nil ("" = none). Letters, digits, "_" and "."; an old "name#1234" too.
function Discord.Clean(s)
    s = tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return "" end
    if #s > MAX_LEN then return nil end
    if s:match("^[%w_%.]+$") and #s >= 2 then return s end
    if s:match("^[%w_%. ]+#%d%d%d%d$") then return s end
    return nil
end

function Discord.Mine() return DB().mine or "" end

-- Discord name of a player (key "Name Surname"), or nil
function Discord.Get(name)
    if not name then return nil end
    if name == Most().MyName() then local m = DB().mine return (m and m ~= "") and m or nil end
    local e = DB().known[name]
    return e and e.d ~= "" and e.d or nil
end

local function Count()
    local n = 0
    for _ in pairs(DB().known) do n = n + 1 end
    return n
end

local function Store(name, ts, d)
    local known = DB().known
    local old = known[name]
    if old and (old.ts or 0) >= ts then return false end
    known[name] = { d = d, ts = ts }
    -- Keep the list bounded: the oldest entries go
    if not old and Count() > MAX_KNOWN then
        local oldestName, oldestTs = nil, math.huge
        for n, e in pairs(known) do if (e.ts or 0) < oldestTs then oldestName, oldestTs = n, e.ts or 0 end end
        if oldestName then known[oldestName] = nil end
    end
    return true
end

local function InGuild() local M = Most() return M.IsGuildAllowed(M.MyGuild()) end

local function SendMine()
    local d = DB()
    if not InGuild() or not d.mineTs then return end
    local M = Most()
    M.Send("DI", M.EncodeField(M.MyName()) .. ":" .. d.mineTs .. ":" .. M.EncodeField(d.mine or ""), "low")
end

-- Settings: save my Discord name (account-wide) and tell the community. Returns ok, error text.
function Discord.SetMine(text)
    local clean = Discord.Clean(text)
    if not clean then return false, "Discord names are 2-32 letters, digits, _ or . (or the old name#1234)." end
    local d = DB()
    if clean == (d.mine or "") then return true end
    d.mine, d.mineTs = clean, GetServerTime()
    SendMine()
    return true
end

-- ----------------------------------------------------------------------------
-- PACKETS (core.lua: from known players of listed guilds); true when it was ours
-- ----------------------------------------------------------------------------
local pending, answeredAt = {}, {}

local function Answer(asker)
    answeredAt[asker] = GetTime()
    local M = Most()
    local Enc = M.EncodeField
    local chunk, sent = {}, 0
    local size = 0
    local function Flush()
        if #chunk == 0 then return end
        M.Whisper(asker, "DL", table.concat(chunk, ";"), "low")
        sent, chunk, size = sent + 1, {}, 0
    end
    for name, e in pairs(DB().known) do
        if name ~= asker then
            local item = Enc(name):gsub("[@;]", "") .. "@" .. tostring(e.ts) .. "@" .. Enc(e.d):gsub("[@;]", "")
            if size + #item + 1 > MAX_PAYLOAD then Flush() end
            table.insert(chunk, item)
            size = size + #item + 1
        end
    end
    -- Mine too (it is not in "known")
    local d = DB()
    if d.mineTs then
        local item = Enc(M.MyName()) .. "@" .. d.mineTs .. "@" .. Enc(d.mine or "")
        if size + #item + 1 > MAX_PAYLOAD then Flush() end
        table.insert(chunk, item)
    end
    Flush()
    if addonTable.Monitor then addonTable.Monitor.Note("Discord: answered " .. asker .. " with " .. sent .. " packets") end
end

function Discord.HandlePacket(pType, payload, senderName, channel)
    if pType ~= "DI" and pType ~= "DQ" and pType ~= "DC" and pType ~= "DL" then return false end
    local M = Most()
    local me = M.MyName()
    if senderName == me then return true end
    if pType == "DI" then
        local name, ts, d = _G.strsplit(":", payload, 3)
        name, ts = M.Plain(M.DecodeField(name) or ""), tonumber(ts)
        d = Discord.Clean(M.Plain(M.DecodeField(d) or ""))
        -- Live: only from the player it names
        if not ts or not d or name == "" or (channel ~= "WHISPER" and senderName ~= name) then return true end
        Store(name, ts, d)
    elseif pType == "DQ" then
        local theirs = tonumber(payload) or 0
        -- 0.15.3: answered whenever we know more names than the asker (was 6 more: with few names in the
        -- community nobody answered); one guildmate answers (the claim), and the list is small
        if pending[senderName] or Count() <= theirs then return true end
        if GetTime() - (answeredAt[senderName] or -ANSWER_COOLDOWN) < ANSWER_COOLDOWN or not M.ShouldAnswer("0.15.2") then return true end
        M.ClaimAndAnswer(pending, senderName, 1 + math.random() * 3, function() M.Send("DC", M.EncodeField(senderName), "high") end,
            function() Answer(senderName) end)
    elseif pType == "DC" then
        local asker = M.DecodeField(payload)
        if asker then M.ClaimSeen(pending, asker, senderName) end
    elseif pType == "DL" then
        if channel ~= "WHISPER" or not M.FindKnownPlayer(senderName) then return true end
        local now = GetServerTime()
        for item in payload:gmatch("[^;]+") do
            local name, ts, d = item:match("^([^@]+)@(%d+)@(.*)$")
            ts = tonumber(ts)
            name = name and M.Plain(M.DecodeField(name))
            d = d and Discord.Clean(M.Plain(M.DecodeField(d)))
            if name and name ~= "" and name ~= me and ts and ts <= now + 300 and d then Store(name, ts, d) end
        end
    end
    return true
end

-- ----------------------------------------------------------------------------
-- TOOLTIPS AND COPYING
-- ----------------------------------------------------------------------------
-- One line at the bottom of a tooltip for that player (nothing when they shared none)
-- The line everywhere: "Discord: name" (the label in gray, the name in Discord's blurple)
local function LineText(d) return "|cffa0a0a0Discord:|r |c" .. COLOR .. d .. "|r" end

function Discord.AddLine(tip, name)
    local d = Discord.Get(name)
    if not d or not tip then return end
    tip:AddLine(LineText(d))
    tip:Show()
end

-- A small window with the name selected, to copy with Ctrl+C
_G.StaticPopupDialogs["JAGODKA_COPY_DISCORD"] = {
    text = "Discord name of %s (Ctrl+C to copy):",
    button1 = _G.OKAY or "OK",
    hasEditBox = true,
    editBoxWidth = 220,
    OnShow = function(self, data)
        local box = self.editBox or self.EditBox
        if box then box:SetText(data or "") box:HighlightText() box:SetFocus() end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
function Discord.Copy(name)
    local d = Discord.Get(name)
    if d then _G.StaticPopup_Show("JAGODKA_COPY_DISCORD", name, nil, d) end
end

-- A row of the addon's player tables (Roster, Officers online; row.member = { name, ... }): on hover, a small
-- tooltip with the name and the Discord name, only for a player who shared one (other rows show nothing new)
function Discord.AttachRow(row)
    if not row or not row.HookScript then return end
    row:HookScript("OnEnter", function(self)
        local name = (self.member and self.member.name) or self.playerName
        local d = name and Discord.Get(name)
        if not d then return end
        local tip = _G.GameTooltip
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:SetText(name, 1, 1, 1)
        tip:AddLine(LineText(d))
        tip:Show()
        self.discordTip = true
    end)
    row:HookScript("OnLeave", function(self)
        if self.discordTip then self.discordTip = nil _G.GameTooltip:Hide() end
    end)
end

-- A chat window (the game's chat windows and the addon window's chat): hovering a player's name, which is a
-- player link, shows "Discord: name" for a player who shared one; nothing for the others (discreet)
function Discord.AttachChatFrame(frame)
    if not frame or frame.jagodkaDiscord or not frame.HookScript then return end
    frame.jagodkaDiscord = true
    frame:HookScript("OnHyperlinkEnter", function(self, link)
        if type(link) ~= "string" or Most().IsSecret(link) then return end
        local who = link:match("^player:([^:]+)")
        if not who then return end
        local name = Most().PlayerKey(who)
        local d = Discord.Get(name)
        if not d then return end
        local tip = _G.GameTooltip
        tip:SetOwner(self, "ANCHOR_CURSOR")
        tip:SetText(name, 1, 1, 1)
        tip:AddLine(LineText(d))
        tip:Show()
        self.discordTip = true
    end)
    frame:HookScript("OnHyperlinkLeave", function(self)
        if self.discordTip then self.discordTip = nil _G.GameTooltip:Hide() end
    end)
end

-- The game's tooltip of a player (the world, unit frames)
local function OnUnitTooltip(tip)
    if not tip or not tip.GetUnit then return end
    local _, unit = tip:GetUnit()
    if not unit or Most().IsSecret(unit) or not _G.UnitIsPlayer(unit) then return end
    local full = _G.GetUnitName(unit, true)
    if not full or Most().IsSecret(full) then return end
    Discord.AddLine(tip, Most().PlayerKey(full))
end

-- ----------------------------------------------------------------------------
-- START
-- ----------------------------------------------------------------------------
local watch = _G.CreateFrame("Frame")
watch:RegisterEvent("PLAYER_LOGIN")
addonTable.SafeScript(watch, "OnEvent", "discord.lua:login", function()
    -- Newer clients give unit tooltips through TooltipDataProcessor, older ones OnTooltipSetUnit
    local TDP = _G.TooltipDataProcessor
    if TDP and TDP.AddTooltipPostCall and _G.Enum and _G.Enum.TooltipDataType and _G.Enum.TooltipDataType.Unit then
        TDP.AddTooltipPostCall(_G.Enum.TooltipDataType.Unit, function(tip) addonTable.Safe("discord.lua:tooltip", OnUnitTooltip, tip) end)
    elseif _G.GameTooltip and _G.GameTooltip.HookScript then
        _G.GameTooltip:HookScript("OnTooltipSetUnit", function(tip) addonTable.Safe("discord.lua:tooltip", OnUnitTooltip, tip) end)
    end
    -- Every game chat window (the community tab included): names hovered there show the Discord name
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do Discord.AttachChatFrame(_G["ChatFrame" .. i]) end
    -- What others know, after the rest of the login sync; mine a few minutes later (nobody waits for it)
    C_Timer.After(90, function() if InGuild() then Most().Send("DQ", tostring(Count()), "high") end end)
    C_Timer.After(120 + math.random() * 180, SendMine)
end)
