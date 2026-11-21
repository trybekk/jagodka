-- ============================================================================
-- GUILD CLEANUP (1.1.5): officers only, from Monitoring > Officer actions. A window with the members of the
-- guild the officer is logged in on, the longest offline first, each with a Kick button (after a question).
-- Nothing is sent to anyone: it reads the game's guild roster; Remove is a secure button running "/gremove Name"
-- (1.2.3; the game does not let addon code call GuildUninvite).
-- Another guild = log in there (the game can only remove members from your own guild).
-- The list looks and works like the Roster tab: sortable headers, pages of PER_PAGE, scrolling within the
-- page, striped rows with the hover highlight.
-- ============================================================================
local addonName, addonTable = ...

local GuildCleanup = {}
addonTable.GuildCleanup = GuildCleanup

local ROW_HEIGHT = 22          -- as the Roster tab
local VISIBLE_ROWS = 16
local PER_PAGE = 50            -- as the Roster tab
local LONG_OFFLINE_DAYS = 30   -- the summary counts members offline at least this long; orange from here
local VERY_LONG_OFFLINE_DAYS = 90 -- red from here
local WIN_WIDTH = 850

local win, table_, scroll, rows, summary, nav
local members = {}             -- { name, display, level, classFile, rank, rankIndex, online, hours, note, officerNote }
local view = { sortKey = nil, desc = false, page = 1 }
local myRankIndex = nil
local rereadPending = false
local ignoreEventsUntil = 0    -- our own "show offline" switch fires GUILD_ROSTER_UPDATE: it must not start another reading

-- Columns: x and width inside the row (the Kick button stands at the row's right end)
local COLUMNS = {
    { key = "name", name = "Name", x = 10, width = 140 },
    { key = "level", name = "Lvl", x = 155, width = 35 },
    { key = "rank", name = "Rank", x = 195, width = 100 },
    { key = "hours", name = "Last online", x = 300, width = 85 },
    { key = "note", name = "Note", x = 390, width = 165 },
    { key = "officerNote", name = "Officer note", x = 560, width = 145 },   -- ends before the Guild Kick button
}

-- The game's guild window is open: then we do not touch its "show offline" setting (as roster.lua)
local function GuildWindowOpen()
    return (_G.GuildFrame and _G.GuildFrame:IsShown()) or (_G.CommunitiesFrame and _G.CommunitiesFrame:IsShown()) or false
end

local function OfflineText(m)
    if m.online then return "|cff00ff00online|r" end
    local h = m.hours
    local text
    if h < 1 then text = "< 1 h"
    elseif h < 24 then text = h .. " h"
    else
        local d = math.floor(h / 24)
        local mo = math.floor(d / 30)
        if d < 30 then text = d .. " d"
        elseif mo < 12 then text = mo .. " mo " .. (d % 30) .. " d"
        else text = math.floor(mo / 12) .. " y " .. (mo % 12) .. " mo" end
    end
    if h >= VERY_LONG_OFFLINE_DAYS * 24 then return "|cffff6060" .. text .. "|r" end
    if h >= LONG_OFFLINE_DAYS * 24 then return "|cffff9933" .. text .. "|r" end
    return text
end

local function CanSeeOfficerNotes()
    if _G.C_GuildInfo and _G.C_GuildInfo.CanViewOfficerNote then return _G.C_GuildInfo.CanViewOfficerNote() end
    if _G.CanViewOfficerNote then return _G.CanViewOfficerNote() end
    return true
end

local function CanKick(m)
    if not m or m.name == nil or m.display == _G.UnitName("player") then return false end
    if _G.CanGuildRemove and not _G.CanGuildRemove() then return false end
    -- Only ranks below mine (a higher index); the game refuses the rest anyway
    return myRankIndex ~= nil and m.rankIndex ~= nil and m.rankIndex > myRankIndex
end

-- Default order: the longest offline first, online last; the same time by name
local function DefaultLess(a, b)
    if a.online ~= b.online then return b.online end
    if a.hours ~= b.hours then return a.hours > b.hours end
    return a.display < b.display
end

local function Sort()
    local key, desc = view.sortKey, view.desc
    if not key then table.sort(members, DefaultLess) return end
    table.sort(members, function(a, b)
        local va, vb
        if key == "level" then va, vb = tonumber(a.level) or 0, tonumber(b.level) or 0
        elseif key == "rank" then va, vb = a.rankIndex or 99, b.rankIndex or 99
        elseif key == "hours" then va, vb = a.online and -1 or a.hours, b.online and -1 or b.hours
        elseif key == "name" then va, vb = a.display:lower(), b.display:lower()
        else va, vb = (a[key] or ""):lower(), (b[key] or ""):lower() end
        if va ~= vb then if desc then return va > vb end return va < vb end
        return a.display < b.display
    end)
end

-- Reads the whole roster, offline members too (the "show offline" setting on for the reading only, as roster.lua)
local function ReadRoster()
    wipe(members)
    local _, _, rankIndex = _G.GetGuildInfo("player")
    myRankIndex = rankIndex
    local showOffline = not (_G.GetGuildRosterShowOffline and not _G.GetGuildRosterShowOffline())
    local switched = false
    if not showOffline and _G.SetGuildRosterShowOffline and not GuildWindowOpen() then
        ignoreEventsUntil = GetTime() + 3
        _G.SetGuildRosterShowOffline(true)
        switched = true
    end
    local ok, err = pcall(function()
        for i = 1, (_G.GetNumGuildMembers and _G.GetNumGuildMembers()) or 0 do
            local fullName, rank, rIndex, level, _, _, note, officerNote, isOnline, _, classFile = _G.GetGuildRosterInfo(i)
            if fullName then
                local hours = 0
                if not isOnline and _G.GetGuildRosterLastOnline then
                    local y, mo, d, h = _G.GetGuildRosterLastOnline(i)
                    hours = ((((y or 0) * 12 + (mo or 0)) * 30 + (d or 0)) * 24) + (h or 0)
                end
                table.insert(members, { name = fullName, display = fullName:match("^[^-]+") or fullName, level = level, classFile = classFile,
                    rank = rank, rankIndex = rIndex, online = isOnline and true or false, hours = hours,
                    note = note or "", officerNote = officerNote or "" })
            end
        end
    end)
    if switched then _G.SetGuildRosterShowOffline(false) end
    if not ok and addonTable.Monitor then addonTable.Monitor.Error("Guild cleanup: reading the guild roster failed: " .. tostring(err)) end
    Sort()
    return showOffline or switched
end

local function UpdateHeaders()
    for _, col in ipairs(COLUMNS) do
        local arrow = (view.sortKey == col.key) and (view.desc and " v" or " ^") or ""
        col.header.text:SetText(col.name .. arrow)
        if view.sortKey == col.key then col.header.text:SetTextColor(1, 1, 1) else col.header.text:SetTextColor(1, 0.82, 0) end
    end
end

local function Render()
    if not win then return end
    local total = #members
    local pages = math.max(1, math.ceil(total / PER_PAGE))
    if view.page > pages then view.page = pages end
    local first = (view.page - 1) * PER_PAGE
    local count = math.min(PER_PAGE, total - first)
    local online = 0
    for _, m in ipairs(members) do if m.online then online = online + 1 end end
    nav.info:SetText(total == 0 and "No members" or ("Showing " .. (first + 1) .. "-" .. (first + count) .. " of " .. total .. " |cff00ff00(" .. online .. " online)|r"))
    nav.page:SetText("Page " .. view.page .. " / " .. pages)
    nav.buttons[1]:SetEnabled(view.page > 1) nav.buttons[2]:SetEnabled(view.page > 1)
    nav.buttons[3]:SetEnabled(view.page < pages) nav.buttons[4]:SetEnabled(view.page < pages)
    _G.FauxScrollFrame_Update(scroll, count, VISIBLE_ROWS, ROW_HEIGHT)
    local offset = _G.FauxScrollFrame_GetOffset(scroll)
    local officerNotes = CanSeeOfficerNotes()
    for i = 1, VISIBLE_ROWS do
        local row, index = rows[i], offset + i
        local m = index <= count and members[first + index] or nil
        if m then
            local color = _G.RAID_CLASS_COLORS and m.classFile and _G.RAID_CLASS_COLORS[m.classFile]
            row.name:SetText(m.display)
            if color then row.name:SetTextColor(color.r, color.g, color.b) else row.name:SetTextColor(1, 1, 1) end
            row.level:SetText(m.level or "")
            row.rank:SetText(m.rank or "")
            row.hours:SetText(OfflineText(m))
            row.note:SetText(m.note)
            -- The game gives the officer note only to ranks allowed to see it
            row.officerNote:SetText(officerNotes and m.officerNote or "|cff777777-|r")
            row.member = m
            row.kick:SetEnabled(CanKick(m))
            row:Show()
        else
            row.member = nil
            row:Hide()
        end
    end
end

local function Refresh()
    if not win then return end
    local guild = _G.GetGuildInfo("player")
    win.title:SetText("Guild cleanup: " .. (guild or "no guild"))
    local full = ReadRoster()
    local long = 0
    for _, m in ipairs(members) do
        if not m.online and m.hours >= LONG_OFFLINE_DAYS * 24 then long = long + 1 end
    end
    local text = "|cffff9933" .. long .. " members offline " .. LONG_OFFLINE_DAYS .. "+ days|r (red: " .. VERY_LONG_OFFLINE_DAYS .. "+). Click a column to sort; hover a row for the whole notes."
    if not full then text = text .. "\n|cffff5555Only online members: close the game's guild window and press Refresh.|r" end
    if _G.CanGuildRemove and not _G.CanGuildRemove() then text = text .. "\n|cffff5555Your rank cannot remove members.|r" end
    summary:SetText(text)
    Render()
end

-- The game refreshes the roster in the background: re-read at most twice a second while the window is open
local function RereadSoon()
    if rereadPending or not win or not win:IsShown() or GetTime() < ignoreEventsUntil then return end
    rereadPending = true
    C_Timer.After(0.5, function() rereadPending = false if win and win:IsShown() then Refresh() end end)
end

local function AskRoster()
    if _G.C_GuildInfo and _G.C_GuildInfo.GuildRoster then _G.C_GuildInfo.GuildRoster() elseif _G.GuildRoster then _G.GuildRoster() end
end

-- 1.2.3 (user: "gkick nie może być akcją wykonaną z addona"): the game lets only its own (untainted) code remove a
-- member (C_GuildInfo.RemoveFromGuild: AllowedWhenUntainted), so GuildUninvite from the old popup's Remove did
-- nothing. The game's way for addons: a secure button (SecureActionButtonTemplate) whose click runs the macro
-- "/gremove Name" as if typed (the game has no "/gkick": "Type /help") - every removal is still the officer's own click, nothing is automated.
-- A frame holding a secure button is protected: it is shown, filled and hidden only out of combat (it hides
-- itself when combat starts), it is a child of UIParent (not of the list window, which stays normal) and it is
-- not closed by Escape (that would run in combat too); Cancel closes it.
local confirm
-- The name as the command wants it (user: "/gremove Billie Jagódka działa"): the roster gives "Billie-Jagódka"
-- (the surname in the realm place, WoW: Forever); Most.PlayerKey makes it "Billie Jagódka"
local function KickName(m)
    local Most = addonTable.Most
    return (Most and Most.PlayerKey and Most.PlayerKey(m.name)) or m.name
end
local function BuildConfirm()
    confirm = CreateFrame("Frame", "JagodkaGuildKickConfirm", _G.UIParent, "BackdropTemplate")
    confirm:SetSize(420, 120)
    confirm:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 120)
    confirm:SetFrameStrata("FULLSCREEN_DIALOG")
    confirm:SetToplevel(true)
    confirm:EnableMouse(true)
    confirm:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    confirm:SetBackdropColor(0.07, 0.07, 0.09, 1)
    confirm:SetBackdropBorderColor(1, 0.82, 0.3, 0.9)
    confirm.text = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    confirm.text:SetPoint("TOP", confirm, "TOP", 0, -18)
    confirm.text:SetWidth(390)
    confirm.remove = CreateFrame("Button", "JagodkaGuildKickRemove", confirm, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    confirm.remove:SetSize(120, 24)
    confirm.remove:SetPoint("BOTTOMRIGHT", confirm, "BOTTOM", -66, 14)
    confirm.remove:SetText("Remove")
    confirm.remove:RegisterForClicks("AnyUp", "AnyDown")
    confirm.remove:SetAttribute("type", "macro")
    -- After the game ran the macro (insecure hook, runs after the secure click): note it, close, read again.
    -- Registered for down and up (newer clients run the action on the edge ActionButtonUseKeyDown says, once);
    -- the hook waits for the release, so the window never closes between the press and the action.
    confirm.remove:HookScript("OnClick", function(_, _, down)
        local m = confirm.member
        if down or not m or confirm.done then return end
        confirm.done = true
        if addonTable.Monitor then addonTable.Monitor.Note("Guild cleanup: ran \"" .. tostring(confirm.remove:GetAttribute("macrotext")) .. "\" for " .. m.display .. " (roster name \"" .. tostring(m.name) .. "\", last online: " .. (m.online and "online" or OfflineText(m)) .. ")") end
        if not InCombatLockdown() then confirm:Hide() end
        AskRoster()
        -- The roster event may fall in the ignore window: read again a moment later anyway
        C_Timer.After(1.5, function() if win and win:IsShown() then Refresh() end end)
    end)
    -- The sure way (user: "musimy ten ficzer mieć"): "/gremove Name" typed into the game's chat input for the
    -- officer to send with Enter - exactly the command typed by hand, which the game always accepts. The name is
    -- visible there and can be corrected before Enter.
    local typeIt = CreateFrame("Button", nil, confirm, "UIPanelButtonTemplate")
    typeIt:SetSize(120, 24)
    typeIt:SetPoint("BOTTOM", confirm, "BOTTOM", 0, 14)
    typeIt:SetText("Type in chat")
    typeIt:SetScript("OnClick", function()
        local m = confirm.member
        if not m or not _G.ChatFrame_OpenChat then return end
        if not InCombatLockdown() then confirm:Hide() end
        _G.ChatFrame_OpenChat("/gremove " .. KickName(m))
        if addonTable.Monitor then addonTable.Monitor.Note("Guild cleanup: \"/gremove " .. KickName(m) .. "\" typed into the chat input for " .. m.display .. " (sent when you press Enter)") end
    end)
    typeIt:SetScript("OnEnter", function(self)
        _G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
        _G.GameTooltip:SetText("Puts /gremove with the name into your chat input: press Enter to remove.", 1, 1, 1, 1, true)
        _G.GameTooltip:Show()
    end)
    typeIt:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
    local cancel = CreateFrame("Button", nil, confirm, "UIPanelButtonTemplate")
    cancel:SetSize(120, 24)
    cancel:SetPoint("BOTTOMLEFT", confirm, "BOTTOM", 66, 14)
    cancel:SetText("Cancel")
    cancel:SetScript("OnClick", function() if not InCombatLockdown() then confirm:Hide() end end)
    local combat = CreateFrame("Frame")
    combat:RegisterEvent("PLAYER_REGEN_DISABLED")
    combat:SetScript("OnEvent", function() if confirm:IsShown() then confirm:Hide() end end)
    confirm:Hide()
end

local function AskKick(m)
    if InCombatLockdown() then
        if addonTable.Monitor then addonTable.Monitor.Note("Guild cleanup: not in combat - try again after the fight") end
        if _G.UIErrorsFrame then _G.UIErrorsFrame:AddMessage("Guild Kick: not in combat.", 1, 0.3, 0.3) end
        return
    end
    if not confirm then BuildConfirm() end
    confirm.member, confirm.done = m, false
    confirm.remove:SetAttribute("macrotext", "/gremove " .. KickName(m))
    confirm.text:SetText("Remove |cffffffff" .. KickName(m) .. "|r from the guild?\nLast online: " .. (m.online and "online now" or OfflineText(m)) .. ".")
    confirm:Show()
end

local function SetPage(page)
    view.page = page
    _G.FauxScrollFrame_SetOffset(scroll, 0)
    local bar = _G[scroll:GetName() .. "ScrollBar"]
    if bar then bar:SetValue(0) end
    Render()
end

local function Build(applyStyle)
    win = CreateFrame("Frame", "JagodkaGuildCleanup", _G.UIParent, "BackdropTemplate")
    win:SetSize(WIN_WIDTH, 150 + 30 + VISIBLE_ROWS * ROW_HEIGHT)
    win:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 40)
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    if applyStyle then applyStyle(win) end
    -- Solid background: the addon style is 60% see-through, too busy for a long list over the game
    win:SetBackdropColor(0.07, 0.07, 0.09, 1)
    -- A soft golden glow round the edge, so it stands out over the addon window: a gold border and two faint
    -- rings outside it (only their edges are drawn, outside the window, so nothing covers the list)
    win:SetBackdropBorderColor(1, 0.82, 0.3, 0.9)
    for i, alpha in ipairs({ 0.22, 0.09 }) do
        local ring = CreateFrame("Frame", nil, win, "BackdropTemplate")
        ring:SetPoint("TOPLEFT", win, "TOPLEFT", -4 * i, 4 * i)
        ring:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 4 * i, -4 * i)
        ring:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 4 })
        ring:SetBackdropBorderColor(1, 0.82, 0.3, alpha)
        ring:EnableMouse(false)
    end
    table.insert(_G.UISpecialFrames, "JagodkaGuildCleanup")

    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.title:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -14)
    summary = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -6)
    summary:SetPoint("RIGHT", win, "RIGHT", -16, 0)
    summary:SetJustifyH("LEFT")

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -4)

    -- The table: the Roster tab's box, headers and rows
    table_ = CreateFrame("Frame", nil, win, "BackdropTemplate")
    table_:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -70)
    table_:SetPoint("RIGHT", win, "RIGHT", -16, 0)
    table_:SetHeight(30 + VISIBLE_ROWS * ROW_HEIGHT + 6)
    if applyStyle then applyStyle(table_) end

    for _, col in ipairs(COLUMNS) do
        local h = CreateFrame("Button", nil, table_)
        h:SetSize(col.width, 18)
        h:SetPoint("TOPLEFT", table_, "TOPLEFT", col.x + 5, -6)
        h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h.text:SetPoint("LEFT", h, "LEFT", 0, 0)
        -- Click = ascending, second = descending, third = the default order (as the Roster tab)
        h:SetScript("OnClick", function()
            if view.sortKey ~= col.key then view.sortKey, view.desc = col.key, false
            elseif not view.desc then view.desc = true
            else view.sortKey, view.desc = nil, false end
            UpdateHeaders()
            Sort()
            SetPage(1)
        end)
        col.header = h
    end
    UpdateHeaders()

    scroll = CreateFrame("ScrollFrame", "JagodkaGuildCleanupScroll", table_, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", table_, "TOPLEFT", 0, -30)
    scroll:SetPoint("BOTTOMRIGHT", table_, "BOTTOMRIGHT", -26, 6)
    scroll:SetScript("OnVerticalScroll", function(self, offset) _G.FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, Render) end)

    rows = {}
    for i = 1, VISIBLE_ROWS do
        local row = CreateFrame("Button", nil, table_)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", table_, "TOPLEFT", 5, -30 - (i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", table_, "RIGHT", -25, 0)
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.02 or 0.04)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        for _, col in ipairs(COLUMNS) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", row, "LEFT", col.x, 0)
            fs:SetSize(col.width, ROW_HEIGHT)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            row[col.key] = fs
        end
        row.officerNote:SetTextColor(1, 0.82, 0.5)
        row:SetScript("OnEnter", function(self)
            local m = self.member
            if not m then return end
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            _G.GameTooltip:SetText(m.display, 1, 1, 1)
            _G.GameTooltip:AddLine("Note: " .. (m.note ~= "" and m.note or "-"), 0.9, 0.9, 0.9, true)
            if CanSeeOfficerNotes() then _G.GameTooltip:AddLine("Officer note: " .. (m.officerNote ~= "" and m.officerNote or "-"), 1, 0.82, 0.5, true) end
            _G.GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
        -- The row takes the mouse (tooltip, highlight), so the wheel is passed on to the list
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            local fn = scroll:GetScript("OnMouseWheel")
            if fn then fn(scroll, delta) end
        end)
        row.kick = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.kick:SetSize(76, 18)
        row.kick:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.kick:SetText("Guild Kick")
        row.kick:SetScript("OnClick", function()
            local m = row.member
            if not m or not CanKick(m) then return end
            AskKick(m)
        end)
        rows[i] = row
    end

    -- Page bar under the table, as the Roster tab: "Showing 51-100 of 312 (48 online)   [<<] [<] Page 2 / 7 [>] [>>]"
    nav = CreateFrame("Frame", nil, win)
    nav:SetHeight(26)
    nav:SetPoint("TOPLEFT", table_, "BOTTOMLEFT", 0, -4)
    nav:SetPoint("TOPRIGHT", table_, "BOTTOMRIGHT", 0, -4)
    nav.info = nav:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nav.info:SetPoint("LEFT", nav, "LEFT", 8, 0)
    nav.buttons = {}
    for i, label in ipairs({ "<<", "<", ">", ">>" }) do
        local b = CreateFrame("Button", nil, nav, "UIPanelButtonTemplate")
        b:SetSize(30, 20)
        b:SetText(label)
        b:SetScript("OnClick", function()
            local pages = math.max(1, math.ceil(#members / PER_PAGE))
            local target = ({ 1, view.page - 1, view.page + 1, pages })[i]
            SetPage(math.max(1, math.min(pages, target)))
        end)
        nav.buttons[i] = b
    end
    nav.page = nav:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nav.page:SetWidth(90)
    nav.buttons[4]:SetPoint("RIGHT", nav, "RIGHT", -4, 0)
    nav.buttons[3]:SetPoint("RIGHT", nav.buttons[4], "LEFT", -2, 0)
    nav.page:SetPoint("RIGHT", nav.buttons[3], "LEFT", -4, 0)
    nav.buttons[2]:SetPoint("RIGHT", nav.page, "LEFT", -4, 0)
    nav.buttons[1]:SetPoint("RIGHT", nav.buttons[2], "LEFT", -2, 0)

    local refresh = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    refresh:SetSize(90, 22)
    refresh:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 16, 12)
    refresh:SetText("Refresh")
    refresh:SetScript("OnClick", function() AskRoster() Refresh() end)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", refresh, "RIGHT", 10, 0)
    hint:SetPoint("RIGHT", win, "RIGHT", -16, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Only the guild you are logged in on. For another guild, log in there.")

    win:SetScript("OnShow", function() AskRoster() Refresh() end)
    local events = CreateFrame("Frame")
    events:RegisterEvent("GUILD_ROSTER_UPDATE")
    events:SetScript("OnEvent", RereadSoon)
    win:Hide()
end

-- Opens or closes the window (Monitoring > Officer actions). applyStyle = the addon's window style.
function GuildCleanup.Toggle(applyStyle)
    if not _G.IsInGuild() then
        if addonTable.Monitor then addonTable.Monitor.Note("Guild cleanup: you are not in a guild") end
        return
    end
    if not win then Build(applyStyle) end
    win:SetShown(not win:IsShown())
end
