-- ============================================================================
-- SETTINGS: the Settings tab (sections on the left, as in Help)
-- ============================================================================
--  * Section "Chats": which other messages also show in the "Jagodki Nadina - General" tab of the game's
--    chat (chattab.lua), next to the community chat that is always there: whispers, guild, officer, party,
--    raid, say, yell, emotes, system messages, and the game channels the character is on (General, Trade...).
--  * Saved per character, in the account's data under the character's name (Settings.CharStore; from 0.15.4). Nothing is applied until the player
--    changes something here, so a tab set up by hand in the game's own tab settings stays as it is.
--  * Display only, in the player's own game chat: nothing is sent.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local CreateFrame = _G.CreateFrame
local ipairs, pairs, type, tostring = _G.ipairs, _G.pairs, _G.type, _G.tostring
local table, math = _G.table, _G.math

local Settings = {}
addonTable.Settings = Settings

-- Message groups of the game (ChatTypeGroup); a group this client does not have is skipped
local CHAT_GROUPS = {
    { key = "WHISPER", label = "Whispers", groups = { "WHISPER", "BN_WHISPER" } },
    { key = "GUILD", label = "Guild chat (/g)", groups = { "GUILD" } },
    { key = "OFFICER", label = "Guild officer chat (/o)", groups = { "OFFICER" } },
    { key = "PARTY", label = "Party", groups = { "PARTY", "PARTY_LEADER" } },
    { key = "RAID", label = "Raid and raid warnings", groups = { "RAID", "RAID_LEADER", "RAID_WARNING" } },
    { key = "SAY", label = "Say", groups = { "SAY" } },
    { key = "YELL", label = "Yell", groups = { "YELL" } },
    { key = "EMOTE", label = "Emotes", groups = { "EMOTE" } },
    { key = "SYSTEM", label = "System messages", groups = { "SYSTEM" } },
}

-- The addon's own channels never show here (public, chat key, officers)
local function IsOurChannel(name)
    return name:find("^JagodkaNet") ~= nil or name:find("^Jgd") ~= nil or name:find("^Jgo") ~= nil
end

-- 0.15.4: a character's own settings live in the ACCOUNT's saved data (JagodkiChatDB.chars["First Surname"]), not
-- in the character's folder (JagodkiCharDB): the game keeps that folder under the server's name, and when WoW:
-- Forever moved a character under another server name the character came back with empty settings ("the
-- checkboxes are not saved", 10.11). What was in JagodkiCharDB is moved over once. Also used by lfg.lua.
local scratch = {}   -- before the character's name is known (never saved)
function Settings.CharStore()
    local me = addonTable.Most and addonTable.Most.MyName()
    if not me then return scratch end
    _G.JagodkiChatDB = _G.JagodkiChatDB or {}
    local all = _G.JagodkiChatDB.chars
    if type(all) ~= "table" then all = {} _G.JagodkiChatDB.chars = all end
    local s = all[me]
    if type(s) ~= "table" then
        s = {}
        all[me] = s
        local old = _G.JagodkiCharDB
        if type(old) == "table" then s.chatTab, s.lfg = old.chatTab, old.lfg end
    end
    return s
end

local function DB()
    local db = Settings.CharStore()
    db.chatTab = db.chatTab or { set = false, groups = {}, channels = {} }
    db.chatTab.community = db.chatTab.community or {}
    return db.chatTab
end

-- The community's other chats that can also show in that tab (chattab.lua prints them): addon chat tab key,
-- label, officers only
local COMMUNITY = {
    { tab = "Handel", label = "Community Trade" },
    { tab = "Szukaj grupy", label = "Community LFG" },
    { tab = "Oficerowie", label = "Officers chat", officers = true },
}

-- Whether the community tab of the game chat also shows this addon chat tab ("Handel", "Szukaj grupy", "Oficerowie")
function Settings.ShowsCommunity(tab)
    return DB().community[tab] == true
end

-- The game channels this character is on: { name } (GetChannelList gives id, name[, disabled] in a row)
local function GameChannels()
    local list, values = {}, { _G.GetChannelList() }
    for i = 1, #values do
        local v = values[i]
        if type(v) == "string" and type(values[i - 1]) == "number" and not IsOurChannel(v) then table.insert(list, v) end
    end
    return list
end

-- 1.1.5: the chat window's own method (frame:AddChannel...), else the old global (ChatFrame_AddChannel(frame...)).
-- The Forever client has no ChatFrame_AddChannel at all, so the ticked game channels (General, Trade...) never
-- showed in the tab; the other old globals exist there only as deprecated aliases (Blizzard_DeprecatedChatInfo).
local function ChatCall(frame, method, ...)
    if type(frame[method]) == "function" then return frame[method](frame, ...) end
    local old = _G["ChatFrame_" .. method]
    if type(old) == "function" then return old(frame, ...) end
end

-- Applies the choices to the community tab of the game's chat. frame: that tab (chattab.lua).
-- Only the game's own message types and channels: the community chat itself is printed by the addon
-- (chattab.lua), and our channels are never offered here (IsOurChannel), so it is never touched.
function Settings.ApplyChatTab(frame)
    local cfg = DB()
    if not frame or not cfg.set then return end
    ChatCall(frame, "RemoveAllMessageGroups")
    for _, g in ipairs(CHAT_GROUPS) do
        if cfg.groups[g.key] then
            for _, group in ipairs(g.groups) do
                if _G.ChatTypeGroup and _G.ChatTypeGroup[group] then ChatCall(frame, "AddMessageGroup", group) end
            end
        end
    end
    for _, name in ipairs(GameChannels()) do
        if not cfg.channels[name] then ChatCall(frame, "RemoveChannel", name)
        -- Already there (applied again after login): adding twice would list it twice
        elseif not ChatCall(frame, "ContainsChannel", name) then ChatCall(frame, "AddChannel", name) end
    end
end

local function ApplyNow()
    local Z = addonTable.Zakladka
    if Z and Z.Frame then Settings.ApplyChatTab(Z.Frame()) end
end

-- ============================================================================
-- UI
-- ============================================================================
local SECTIONS = {
    { key = "chats", title = "Chats", icon = "Interface\\GossipFrame\\GossipGossipIcon" },
    { key = "profile", title = "Profile", icon = "Interface\\FriendsFrame\\UI-Toast-ChatInviteIcon" },
}

local panel, ctx, nav, content, selected = nil, nil, nil, nil, "chats"
local profile = nil   -- the Profile section (Discord name, discord.lua)
local checks, channelChecks = {}, {}

local function NewCheck(parent, label, onClick)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check.label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    check.label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    check.label:SetText(label)
    check:SetScript("OnClick", onClick)
    return check
end

local function Render()
    if not panel or not panel:IsVisible() then return end
    local cfg = DB()
    for _, item in ipairs(nav.items) do
        local active = item.key == selected
        item.bg:SetColorTexture(active and 0.18 or 1, active and 0.1 or 1, active and 0.24 or 1, active and 0.9 or 0)
        item.bar:SetShown(active)
    end
    -- One section at a time: Chats (content) or Profile
    content:SetShown(selected == "chats")
    if profile then
        profile:SetShown(selected == "profile")
        if selected == "profile" and not profile.box:HasFocus() then profile.box:SetText(addonTable.Discord and addonTable.Discord.Mine() or "") end
        if selected == "profile" and not profile.btag:HasFocus() then profile.btag:SetText(addonTable.Discord and addonTable.Discord.MineBTag() or "") end
        if selected == "profile" then profile.UpdatePreview() end
    end
    for _, c in ipairs(checks) do c:SetChecked(cfg.groups[c.key] and true or false) end
    -- The officers chat only for officers
    for _, c in ipairs(content.communityChecks) do
        c:SetChecked(cfg.community[c.tab] and true or false)
        c:SetShown(not c.officers or (ctx.isOfficer and ctx.isOfficer()))
    end
    -- Channels: those this character is on now, two columns under "Game channels"
    for _, c in ipairs(channelChecks) do c:Hide() end
    local channels = GameChannels()
    for i, name in ipairs(channels) do
        local c = channelChecks[i]
        if not c then
            c = NewCheck(content, "", function(self)
                local d = DB()
                d.set = true
                d.channels[self.channel] = self:GetChecked() and true or nil
                ApplyNow()
            end)
            channelChecks[i] = c
        end
        c.channel = name
        c.label:SetText(name)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", content.channelsHeader, "BOTTOMLEFT", ((i - 1) % 2) * 220, -6 - math.floor((i - 1) / 2) * 26)
        c:SetChecked(cfg.channels[name] and true or false)
        c:Show()
    end
    content.noChannels:SetShown(#channels == 0)
end

-- core.lua: c = { applyStyle = function(frame) }
function Settings.Attach(p, c)
    panel, ctx = p, c
    nav = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    nav:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -38)
    nav:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    nav:SetWidth(170)
    ctx.applyStyle(nav)
    nav.items = {}
    for i, s in ipairs(SECTIONS) do
        local item = CreateFrame("Button", nil, nav)
        item:SetHeight(24)
        item:SetPoint("TOPLEFT", nav, "TOPLEFT", 4, -10 - (i - 1) * 26)
        item:SetPoint("RIGHT", nav, "RIGHT", -4, 0)
        item.bg = item:CreateTexture(nil, "BACKGROUND") item.bg:SetAllPoints()
        item.bar = item:CreateTexture(nil, "ARTWORK") item.bar:SetWidth(2)
        item.bar:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 0) item.bar:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0, 0)
        item.bar:SetColorTexture(0.75, 0.25, 1, 1)
        item.icon = item:CreateTexture(nil, "ARTWORK")
        item.icon:SetSize(16, 16) item.icon:SetPoint("LEFT", item, "LEFT", 8, 0)
        item.icon:SetTexture(s.icon)
        item.text = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        item.text:SetPoint("LEFT", item.icon, "RIGHT", 8, 0)
        item.text:SetText(s.title)
        item:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        item:SetScript("OnClick", function() selected = s.key Render() end)
        item.key = s.key
        table.insert(nav.items, item)
    end
    content = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    content:SetPoint("TOPLEFT", nav, "TOPRIGHT", 8, 0)
    content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    ctx.applyStyle(content)
    content.title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    content.title:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -14)
    content.title:SetText("Chats")
    if addonTable.Help then addonTable.Help.Button(content, "settings", 1, "Settings"):SetPoint("LEFT", content.title, "RIGHT", 8, 0) end
    content.line = content:CreateTexture(nil, "ARTWORK")
    content.line:SetHeight(1)
    content.line:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -38) content.line:SetPoint("TOPRIGHT", content, "TOPRIGHT", -16, -38)
    content.line:SetColorTexture(0.75, 0.25, 1, 0.5)
    content.intro = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    content.intro:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -48)
    content.intro:SetPoint("RIGHT", content, "RIGHT", -16, 0)
    content.intro:SetJustifyH("LEFT")
    content.intro:SetText("The |cffffd100Jagodki Nadina - General|r tab in your game chat always shows the community chat, each line starting with the |TInterface\\AddOns\\jagodka\\Media\\blueberry_one.tga:14:14|t blueberry. Tick what else it should show, so you can keep just that tab open: it shows up at once, with the game's usual look. Saved for this character.")
    -- The community's other chats (Trade, LFG, officers), marked with their name in that tab
    content.communityHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    content.communityHeader:SetPoint("TOPLEFT", content.intro, "BOTTOMLEFT", 0, -14)
    content.communityHeader:SetText("Community chats")
    content.communityChecks = {}
    for i, def in ipairs(COMMUNITY) do
        local c = NewCheck(content, def.label, function(self)
            DB().community[self.tab] = self:GetChecked() and true or nil
        end)
        c.tab, c.officers = def.tab, def.officers
        c:SetPoint("TOPLEFT", content.communityHeader, "BOTTOMLEFT", ((i - 1) % 2) * 220, -6 - math.floor((i - 1) / 2) * 26)
        content.communityChecks[i] = c
    end
    content.groupsHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    content.groupsHeader:SetPoint("TOPLEFT", content.communityHeader, "BOTTOMLEFT", 0, -6 - math.ceil(#COMMUNITY / 2) * 26 - 14)
    content.groupsHeader:SetText("Game messages")
    for i, g in ipairs(CHAT_GROUPS) do
        local c = NewCheck(content, g.label, function(self)
            local d = DB()
            d.set = true
            d.groups[self.key] = self:GetChecked() and true or nil
            ApplyNow()
        end)
        c.key = g.key
        c:SetPoint("TOPLEFT", content.groupsHeader, "BOTTOMLEFT", ((i - 1) % 2) * 220, -6 - math.floor((i - 1) / 2) * 26)
        checks[i] = c
    end
    content.channelsHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    content.channelsHeader:SetPoint("TOPLEFT", content.groupsHeader, "BOTTOMLEFT", 0, -6 - math.ceil(#CHAT_GROUPS / 2) * 26 - 14)
    content.channelsHeader:SetText("Game channels")
    content.noChannels = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    content.noChannels:SetPoint("TOPLEFT", content.channelsHeader, "BOTTOMLEFT", 0, -8)
    content.noChannels:SetText("You are not on any game channel right now.")
    panel:SetScript("OnShow", Render)

    -- PROFILE: the Discord name others see on hover (discord.lua); saved for the account
    profile = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    profile:SetPoint("TOPLEFT", nav, "TOPRIGHT", 8, 0)
    profile:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    ctx.applyStyle(profile)
    profile:Hide()
    profile.title = profile:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    profile.title:SetPoint("TOPLEFT", profile, "TOPLEFT", 16, -14)
    profile.title:SetText("Profile")
    if addonTable.Help then addonTable.Help.Button(profile, "settings", 1, "Settings"):SetPoint("LEFT", profile.title, "RIGHT", 8, 0) end
    profile.line = profile:CreateTexture(nil, "ARTWORK")
    profile.line:SetHeight(1)
    profile.line:SetPoint("TOPLEFT", profile, "TOPLEFT", 16, -38) profile.line:SetPoint("TOPRIGHT", profile, "TOPRIGHT", -16, -38)
    profile.line:SetColorTexture(0.75, 0.25, 1, 0.5)
    profile.intro = profile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profile.intro:SetPoint("TOPLEFT", profile, "TOPLEFT", 16, -48)
    profile.intro:SetPoint("RIGHT", profile, "RIGHT", -16, 0)
    profile.intro:SetJustifyH("LEFT")
    profile.intro:SetText("Share your Discord name and your BattleTag with the community, if you like. Both are optional. Players of our guilds see them in one small line when they hover any of your characters, and can copy them from the Roster menu. They reach everyone within minutes and stay. Saved for your account (all your characters). Leave a field empty and save to stop sharing it.")
    -- 1.1.5: two optional fields (Discord name, BattleTag), each with its icon and a hint, one Save for both
    local function Field(labelText, icon, hint, maxLetters, anchor, gap)
        local label = profile:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, gap)
        label:SetText("|T" .. icon .. ":16:16:0:0|t " .. labelText .. " |cff808080(optional)|r")
        local box = CreateFrame("EditBox", nil, profile, "InputBoxTemplate")
        box:SetSize(240, 26)
        box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 6, -6)
        box:SetAutoFocus(false)
        box:SetMaxLetters(maxLetters)
        local tip = profile:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        tip:SetPoint("LEFT", box, "RIGHT", 12, 0)
        tip:SetText(hint)
        return label, box
    end
    profile.label, profile.box = Field("Discord name", "Interface\\FriendsFrame\\UI-Toast-ChatInviteIcon",
        "e.g. jagodka_fan", 37, profile.intro, -18)
    profile.btagLabel, profile.btag = Field("BattleTag", "Interface\\FriendsFrame\\Battlenet-Battleneticon",
        "e.g. Jagodka#2137", 40, profile.box, -14)
    profile.btagLabel:ClearAllPoints()
    profile.btagLabel:SetPoint("TOPLEFT", profile.box, "BOTTOMLEFT", -6, -14)
    profile.save = CreateFrame("Button", nil, profile, "GameMenuButtonTemplate")
    profile.save:SetSize(110, 26)
    profile.save:SetPoint("TOPLEFT", profile.btag, "BOTTOMLEFT", -6, -14)
    profile.save:SetText("Save")
    -- What others see: the same compact line as in their tooltips
    profile.previewLabel = profile:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    profile.previewLabel:SetPoint("TOPLEFT", profile.save, "BOTTOMLEFT", 0, -18)
    profile.previewLabel:SetText("Others see when they hover you")
    profile.preview = CreateFrame("Frame", nil, profile, "BackdropTemplate")
    profile.preview:SetPoint("TOPLEFT", profile.previewLabel, "BOTTOMLEFT", 0, -6)
    profile.preview:SetSize(420, 46)
    profile.preview:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    profile.preview:SetBackdropColor(0, 0, 0, 0.6)
    profile.preview:SetBackdropBorderColor(0.4, 0.4, 0.45, 0.8)
    profile.preview.name = profile.preview:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    profile.preview.name:SetPoint("TOPLEFT", profile.preview, "TOPLEFT", 8, -7)
    profile.preview.line = profile.preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profile.preview.line:SetPoint("TOPLEFT", profile.preview.name, "BOTTOMLEFT", 0, -4)
    profile.status = profile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profile.status:SetPoint("TOPLEFT", profile.preview, "BOTTOMLEFT", 0, -10)
    profile.status:SetPoint("RIGHT", profile, "RIGHT", -16, 0)
    profile.status:SetJustifyH("LEFT")
    function profile.UpdatePreview()
        local me = addonTable.Most and addonTable.Most.MyName() or "You"
        local line = addonTable.Discord and addonTable.Discord.Line(me)
        profile.preview.name:SetText(me)
        profile.preview.line:SetText(line or "|cff808080Nothing: you are not sharing either.|r")
    end
    local function SaveProfile()
        if not addonTable.Discord then return end
        local okD, whyD = addonTable.Discord.SetMine(profile.box:GetText())
        local okB, whyB = addonTable.Discord.SetMineBTag(profile.btag:GetText())
        profile.box:ClearFocus()
        profile.btag:ClearFocus()
        profile.UpdatePreview()
        if okD and okB then
            profile.status:SetText("|cff00ff00Saved.|r")
        else
            local errors = {}
            if not okD then table.insert(errors, whyD) end
            if not okB then table.insert(errors, whyB) end
            profile.status:SetText("|cffff5555" .. table.concat(errors, " ") .. "|r" .. ((okD or okB) and " |cff00ff00The other field was saved.|r" or ""))
        end
    end
    profile.save:SetScript("OnClick", SaveProfile)
    for _, box in ipairs({ profile.box, profile.btag }) do
        box:SetScript("OnEnterPressed", SaveProfile)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    end
    -- Tab moves between the two fields
    profile.box:SetScript("OnTabPressed", function() profile.btag:SetFocus() end)
    profile.btag:SetScript("OnTabPressed", function() profile.box:SetFocus() end)
end
