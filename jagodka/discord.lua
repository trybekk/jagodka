-- ============================================================================
-- DISCORD NAMES (0.15.2) AND BATTLETAGS (1.1.5): a player can share them, the others see them on hover
-- ============================================================================
--  * Settings > Profile: two optional fields, saved for the account (all my characters share them). Empty = none.
--  * Shown as one compact line at the bottom of tooltips ("Discord: name  BattleTag: Name#1234", only what was
--    shared): the game's tooltip of a player (in the world, on unit frames), chat names, the LFG tooltips; the
--    Roster menu has "Copy Discord name" / "Copy BattleTag".
--  * Sync, slow on purpose (nothing here is urgent), and kept for good. One set of packets per kind:
--      Discord:   DI / DQ / DC / DL (since 0.15.2, unchanged, so older versions keep reading Discord names)
--      BattleTag: BI / BQ / BC / BL (1.1.5; older versions ignore these packet types)
--      xI name:ts:value       my value, low priority, to GUILD and through the relays: once after saving and once
--                             per session a few minutes after login (empty value = removed)
--      xQ count               after login, own guild only: "I know this many"; one guildmate who knows more
--                             answers (claim xC, the one-answer rule of bridge.lua) with xL whispers:
--      xL name@ts@value;...   as many entries as fit one packet, low priority
--    Every client keeps every value it learns (JagodkiChatDB.discord.known / .btags, account-wide), the newer wins.
--  * A live xI is taken only from the player it names; xL only from known players of our guilds.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local GetTime, GetServerTime = _G.GetTime, _G.GetServerTime
local ipairs, pairs, tostring, tonumber, type = _G.ipairs, _G.pairs, _G.tostring, _G.tonumber, _G.type
local table, math, string = _G.table, _G.math, _G.string
local C_Timer = addonTable.SafeTimer

local Discord = {}
addonTable.Discord = Discord

local MAX_KNOWN = 5000        -- values kept at most per kind (the oldest go first)
local ANSWER_COOLDOWN = 1800  -- the same asker gets our list at most this often (s)
local MAX_PAYLOAD = 200

local function Most() return addonTable.Most end
local function DB()
    _G.JagodkiChatDB = _G.JagodkiChatDB or {}
    local d = _G.JagodkiChatDB.discord
    if type(d) ~= "table" then d = { known = {} } _G.JagodkiChatDB.discord = d end
    d.known = d.known or {}
    d.btags = d.btags or {}
    return d
end

-- A valid Discord name, or nil ("" = none). Letters, digits, "_" and "."; an old "name#1234" too.
function Discord.Clean(s)
    s = tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return "" end
    if #s > 37 then return nil end
    if s:match("^[%w_%.]+$") and #s >= 2 then return s end
    if s:match("^[%w_%. ]+#%d%d%d%d$") then return s end
    return nil
end

-- A valid BattleTag, or nil ("" = none): "Name#1234" (the name 2-12 letters, also Polish ones, then 4-7 digits)
function Discord.CleanBTag(s)
    s = tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return "" end
    if #s > 40 then return nil end
    local name = s:match("^([^%s#:@;|%%%p]+)#%d%d%d%d%d?%d?%d?$")
    if not name or #name < 2 then return nil end
    return s
end

-- The two kinds: packet types, where they are kept, which version understands them
local KINDS = {
    discord = { info = "DI", query = "DQ", claim = "DC", list = "DL", minVersion = "0.15.2", store = "known",
        mine = "mine", mineTs = "mineTs", clean = Discord.Clean, label = "Discord", color = "ff7289da" },   -- Discord's blurple
    btag = { info = "BI", query = "BQ", claim = "BC", list = "BL", minVersion = "1.1.5", store = "btags",
        mine = "mineB", mineTs = "mineBTs", clean = Discord.CleanBTag, label = "BattleTag", color = "ff00aeff" },  -- Battle.net blue
}
local BY_PACKET = {}
for _, k in pairs(KINDS) do BY_PACKET[k.info], BY_PACKET[k.query], BY_PACKET[k.claim], BY_PACKET[k.list] = k, k, k, k end

local function MineOf(kind) return DB()[kind.mine] or "" end
local function GetOf(kind, name)
    if not name then return nil end
    if name == Most().MyName() then local m = DB()[kind.mine] return (m and m ~= "") and m or nil end
    local e = DB()[kind.store][name]
    return e and e.d ~= "" and e.d or nil
end

function Discord.Mine() return MineOf(KINDS.discord) end
function Discord.MineBTag() return MineOf(KINDS.btag) end
-- Discord name / BattleTag of a player (key "Name Surname"), or nil
function Discord.Get(name) return GetOf(KINDS.discord, name) end
function Discord.GetBTag(name) return GetOf(KINDS.btag, name) end

local function Count(kind)
    local n = 0
    for _ in pairs(DB()[kind.store]) do n = n + 1 end
    return n
end

local function Store(kind, name, ts, d)
    local known = DB()[kind.store]
    local old = known[name]
    if old and (old.ts or 0) >= ts then return false end
    known[name] = { d = d, ts = ts }
    -- Keep the list bounded: the oldest entries go
    if not old and Count(kind) > MAX_KNOWN then
        local oldestName, oldestTs = nil, math.huge
        for n, e in pairs(known) do if (e.ts or 0) < oldestTs then oldestName, oldestTs = n, e.ts or 0 end end
        if oldestName then known[oldestName] = nil end
    end
    return true
end

local function InGuild() local M = Most() return M.IsGuildAllowed(M.MyGuild()) end

local function SendMine(kind)
    local d = DB()
    if not InGuild() or not d[kind.mineTs] then return end
    local M = Most()
    M.Send(kind.info, M.EncodeField(M.MyName()) .. ":" .. d[kind.mineTs] .. ":" .. M.EncodeField(d[kind.mine] or ""), "low")
end

local function SetMineOf(kind, text, why)
    local clean = kind.clean(text)
    if not clean then return false, why end
    local d = DB()
    if clean == (d[kind.mine] or "") then return true end
    d[kind.mine], d[kind.mineTs] = clean, GetServerTime()
    SendMine(kind)
    return true
end

-- Settings: save my Discord name / BattleTag (account-wide) and tell the community. Returns ok, error text.
function Discord.SetMine(text)
    return SetMineOf(KINDS.discord, text, "Discord names are 2-32 letters, digits, _ or . (or the old name#1234).")
end
function Discord.SetMineBTag(text)
    return SetMineOf(KINDS.btag, text, "A BattleTag looks like Name#1234 (the name, # and the digits).")
end

-- ----------------------------------------------------------------------------
-- PACKETS (core.lua: from known players of listed guilds); true when it was ours
-- ----------------------------------------------------------------------------
local pending, answeredAt = {}, {}   -- keyed by kind.query .. asker

local function Answer(kind, asker)
    answeredAt[kind.query .. asker] = GetTime()
    local M = Most()
    local Enc = M.EncodeField
    local chunk, sent = {}, 0
    local size = 0
    local function Flush()
        if #chunk == 0 then return end
        M.Whisper(asker, kind.list, table.concat(chunk, ";"), "low")
        sent, chunk, size = sent + 1, {}, 0
    end
    for name, e in pairs(DB()[kind.store]) do
        if name ~= asker then
            local item = Enc(name):gsub("[@;]", "") .. "@" .. tostring(e.ts) .. "@" .. Enc(e.d):gsub("[@;]", "")
            if size + #item + 1 > MAX_PAYLOAD then Flush() end
            table.insert(chunk, item)
            size = size + #item + 1
        end
    end
    -- Mine too (it is not in the store)
    local d = DB()
    if d[kind.mineTs] then
        local item = Enc(M.MyName()) .. "@" .. d[kind.mineTs] .. "@" .. Enc(d[kind.mine] or "")
        if size + #item + 1 > MAX_PAYLOAD then Flush() end
        table.insert(chunk, item)
    end
    Flush()
    if addonTable.Monitor then addonTable.Monitor.Note(kind.label .. ": answered " .. asker .. " with " .. sent .. " packets") end
end

function Discord.HandlePacket(pType, payload, senderName, channel)
    local kind = BY_PACKET[pType]
    if not kind then return false end
    local M = Most()
    local me = M.MyName()
    if senderName == me then return true end
    if pType == kind.info then
        local name, ts, d = _G.strsplit(":", payload, 3)
        name, ts = M.Plain(M.DecodeField(name) or ""), tonumber(ts)
        d = kind.clean(M.Plain(M.DecodeField(d) or ""))
        -- Live: only from the player it names
        if not ts or not d or name == "" or (channel ~= "WHISPER" and senderName ~= name) then return true end
        Store(kind, name, ts, d)
    elseif pType == kind.query then
        local theirs = tonumber(payload) or 0
        local key = kind.query .. senderName
        -- Answered whenever we know more than the asker; one guildmate answers (the claim), and the list is small
        if pending[key] or Count(kind) <= theirs then return true end
        if GetTime() - (answeredAt[key] or -ANSWER_COOLDOWN) < ANSWER_COOLDOWN or not M.ShouldAnswer(kind.minVersion) then return true end
        M.ClaimAndAnswer(pending, key, 1 + math.random() * 3, function() M.Send(kind.claim, M.EncodeField(senderName), "high") end,
            function() Answer(kind, senderName) end)
    elseif pType == kind.claim then
        local asker = M.DecodeField(payload)
        if asker then M.ClaimSeen(pending, kind.query .. asker, senderName) end
    elseif pType == kind.list then
        if channel ~= "WHISPER" or not M.FindKnownPlayer(senderName) then return true end
        local now = GetServerTime()
        for item in payload:gmatch("[^;]+") do
            local name, ts, d = item:match("^([^@]+)@(%d+)@(.*)$")
            ts = tonumber(ts)
            name = name and M.Plain(M.DecodeField(name))
            d = d and kind.clean(M.Plain(M.DecodeField(d)))
            if name and name ~= "" and name ~= me and ts and ts <= now + 300 and d then Store(kind, name, ts, d) end
        end
    end
    return true
end

-- ----------------------------------------------------------------------------
-- TOOLTIPS AND COPYING
-- ----------------------------------------------------------------------------
-- One compact line for a player: "Discord: name  BattleTag: Name#1234" (labels in gray, values in their colors),
-- only what they shared; nil when they shared nothing
function Discord.Line(name)
    local parts = {}
    for _, kind in ipairs({ KINDS.discord, KINDS.btag }) do
        local v = GetOf(kind, name)
        if v then table.insert(parts, "|cffa0a0a0" .. kind.label .. ":|r |c" .. kind.color .. v .. "|r") end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "   ")
end

-- One line at the bottom of a tooltip for that player (nothing when they shared none)
function Discord.AddLine(tip, name)
    local line = Discord.Line(name)
    if not line or not tip then return end
    tip:AddLine(line)
    tip:Show()
end

-- A small window with the value selected, to copy with Ctrl+C
_G.StaticPopupDialogs["JAGODKA_COPY_DISCORD"] = {
    text = "%s (Ctrl+C to copy):",
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
    if d then _G.StaticPopup_Show("JAGODKA_COPY_DISCORD", "Discord name of " .. name, nil, d) end
end
function Discord.CopyBTag(name)
    local b = Discord.GetBTag(name)
    if b then _G.StaticPopup_Show("JAGODKA_COPY_DISCORD", "BattleTag of " .. name, nil, b) end
end

-- A row of the addon's player tables (Roster, Officers online; row.member = { name, ... }): on hover, a small
-- tooltip with the name and the shared line, only for a player who shared something (other rows show nothing new)
function Discord.AttachRow(row)
    if not row or not row.HookScript then return end
    row:HookScript("OnEnter", function(self)
        local name = (self.member and self.member.name) or self.playerName
        local line = name and Discord.Line(name)
        if not line then return end
        local tip = _G.GameTooltip
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:SetText(name, 1, 1, 1)
        tip:AddLine(line)
        tip:Show()
        self.discordTip = true
    end)
    row:HookScript("OnLeave", function(self)
        if self.discordTip then self.discordTip = nil _G.GameTooltip:Hide() end
    end)
end

-- A chat window (the game's chat windows and the addon window's chat): hovering a player's name, which is a
-- player link, shows the shared line; nothing for the others (discreet)
function Discord.AttachChatFrame(frame)
    if not frame or frame.jagodkaDiscord or not frame.HookScript then return end
    frame.jagodkaDiscord = true
    frame:HookScript("OnHyperlinkEnter", function(self, link)
        if type(link) ~= "string" or Most().IsSecret(link) then return end
        local who = link:match("^player:([^:]+)")
        if not who then return end
        local name = Most().PlayerKey(who)
        local line = Discord.Line(name)
        if not line then return end
        local tip = _G.GameTooltip
        tip:SetOwner(self, "ANCHOR_CURSOR")
        tip:SetText(name, 1, 1, 1)
        tip:AddLine(line)
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
    -- Every game chat window (the community tab included): names hovered there show the shared line
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do Discord.AttachChatFrame(_G["ChatFrame" .. i]) end
    -- What others know, after the rest of the login sync; mine a few minutes later (nobody waits for it).
    -- BattleTags a little after the Discord names, so the two answers do not come at once.
    C_Timer.After(90, function() if InGuild() then Most().Send("DQ", tostring(Count(KINDS.discord)), "high") end end)
    C_Timer.After(100, function() if InGuild() then Most().Send("BQ", tostring(Count(KINDS.btag)), "high") end end)
    C_Timer.After(120 + math.random() * 180, function() SendMine(KINDS.discord) end)
    C_Timer.After(130 + math.random() * 180, function() SendMine(KINDS.btag) end)
end)
