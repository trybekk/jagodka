-- ============================================================================
-- SETTINGS: the Settings tab (sections on the left, as in Help)
-- ============================================================================
--  * Section "Chats": which other messages also show in the "Jagodki Nadina - General" tab of the game's
--    chat (chattab.lua), next to the community chat that is always there: whispers, guild, officer, party,
--    raid, say, yell, emotes, system messages, and the game channels the character is on (General, Trade...).
--  * Saved per character (JagodkiCharDB, SavedVariablesPerCharacter). Nothing is applied until the player
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

local function DB()
    _G.JagodkiCharDB = _G.JagodkiCharDB or {}
    local db = _G.JagodkiCharDB
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

-- Applies the choices to the community tab of the game's chat. frame: that tab (chattab.lua).
function Settings.ApplyChatTab(frame)
    local cfg = DB()
    if not frame or not cfg.set then return end
    if _G.ChatFrame_RemoveAllMessageGroups then _G.ChatFrame_RemoveAllMessageGroups(frame) end
    for _, g in ipairs(CHAT_GROUPS) do
        if cfg.groups[g.key] and _G.ChatFrame_AddMessageGroup then
            for _, group in ipairs(g.groups) do
                if _G.ChatTypeGroup and _G.ChatTypeGroup[group] then _G.ChatFrame_AddMessageGroup(frame, group) end
            end
        end
    end
    for _, name in ipairs(GameChannels()) do
        if cfg.channels[name] then
            if _G.ChatFrame_AddChannel then _G.ChatFrame_AddChannel(frame, name) end
        elseif _G.ChatFrame_RemoveChannel then
            _G.ChatFrame_RemoveChannel(frame, name)
        end
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
    profile.intro:SetText("Share your Discord name with the community, if you like: players of our guilds see it in one small line when they hover any of your characters, and can copy it from the Roster menu. It reaches everyone within minutes and stays. Saved for your account (all your characters). Leave it empty and save to stop sharing it.")
    profile.label = profile:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    profile.label:SetPoint("TOPLEFT", profile.intro, "BOTTOMLEFT", 0, -18)
    profile.label:SetText("Discord name")
    profile.box = CreateFrame("EditBox", nil, profile, "InputBoxTemplate")
    profile.box:SetSize(220, 26)
    profile.box:SetPoint("TOPLEFT", profile.label, "BOTTOMLEFT", 6, -6)
    profile.box:SetAutoFocus(false)
    profile.box:SetMaxLetters(37)
    profile.status = profile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profile.status:SetPoint("TOPLEFT", profile.box, "BOTTOMLEFT", -6, -10)
    profile.status:SetPoint("RIGHT", profile, "RIGHT", -16, 0)
    profile.status:SetJustifyH("LEFT")
    local function SaveDiscord()
        if not addonTable.Discord then return end
        local ok, why = addonTable.Discord.SetMine(profile.box:GetText())
        profile.box:ClearFocus()
        if ok then
            local mine = addonTable.Discord.Mine()
            profile.status:SetText(mine ~= "" and ("|cff00ff00Saved.|r Others see: |cffa0a0a0Discord:|r |cff7289da" .. mine .. "|r")
                or "|cff00ff00Saved.|r You are not sharing a Discord name.")
        else
            profile.status:SetText("|cffff5555" .. why .. "|r")
        end
    end
    profile.save = CreateFrame("Button", nil, profile, "GameMenuButtonTemplate")
    profile.save:SetSize(90, 26)
    profile.save:SetPoint("LEFT", profile.box, "RIGHT", 10, 0)
    profile.save:SetText("Save")
    profile.save:SetScript("OnClick", SaveDiscord)
    profile.box:SetScript("OnEnterPressed", SaveDiscord)
    profile.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
end
