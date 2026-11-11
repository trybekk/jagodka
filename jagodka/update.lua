-- ============================================================================
-- UPDATE: window telling the player their addon is outdated
-- ============================================================================
--  * Shown when a player with a newer version is seen (core.lua, CheckPlayerVersion), once per
--    newer version per session, and only out of combat. The chat line stays as well.
--  * It says the new version is on CurseForge (the CurseForge app updates it), and plays the game's
--    raid warning sound twice, so it is not missed.
--  * Our own window rather than a game popup, so it fits the text and does not take the keyboard.
--  * Monitoring has a button that shows the same window as a preview, and officers' "Remind outdated"
--    (UPD packet) shows a small note next to the minimap button to everyone with an older version.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_Timer = addonTable.SafeTimer -- protected callbacks (safe.lua)
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local GetAddOnMetadata = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
local tostring = _G.tostring
local table, math = _G.table, _G.math

local WIDTH, HEIGHT = 460, 175
-- The game's raid warning sound, as an alert addon would play it; twice, 0.6 s apart
local ALERT_SOUND = (_G.SOUNDKIT and _G.SOUNDKIT.RAID_WARNING) or 8959
local ALERT_GAP = 0.6

local Update = {}
addonTable.Update = Update

local shown = {}       -- newer version -> true once its window was shown this session
local pending = nil    -- newer version seen in combat, shown after it

-- ============================================================================
-- WINDOW
-- ============================================================================
local frame = CreateFrame("Frame", "JagodkaUpdateFrame", _G.UIParent, "BackdropTemplate")
frame:SetSize(WIDTH, HEIGHT)
frame:SetPoint("CENTER", 0, 120)
frame:SetFrameStrata("DIALOG")
frame:EnableMouse(true)
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
frame:Hide()
-- Esc closes it, like the game's own windows
table.insert(_G.UISpecialFrames, "JagodkaUpdateFrame")

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -20)
title:SetText("|cffbf40ffJagodki Nadina - Community|r")

local message = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
message:SetPoint("TOP", title, "BOTTOM", 0, -12)
message:SetWidth(WIDTH - 40)
message:SetJustifyH("CENTER")

local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
close:SetSize(100, 22)
close:SetPoint("BOTTOM", 0, 18)
close:SetText("Close")
close:SetScript("OnClick", function() frame:Hide() end)

local function PlayAlert()
    if not _G.PlaySound then return end
    _G.PlaySound(ALERT_SOUND, "Master")
    C_Timer.After(ALERT_GAP, function() _G.PlaySound(ALERT_SOUND, "Master") end)
end

local function Open(newest)
    message:SetText("|cffff5555Your addon is outdated.|r\nYour version: " .. (GetAddOnMetadata(addonName, "Version") or "?")
        .. ", newest seen: " .. newest .. "\n\nA new version is available on |cffffd100CurseForge|r:\nupdate it in the CurseForge app.")
    frame:Show()
    PlayAlert()
end

-- ============================================================================
-- WHEN TO SHOW
-- ============================================================================
local CombatWatcher = CreateFrame("Frame")
addonTable.SafeScript(CombatWatcher, "OnEvent", "update.lua:83", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local version = pending
    pending = nil
    if version then Update.Show(version) end
end)

-- newerVersion: the version seen at another player
function Update.Show(newerVersion)
    newerVersion = tostring(newerVersion)
    if shown[newerVersion] then return end
    if InCombatLockdown() then
        pending = newerVersion
        CombatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    shown[newerVersion] = true
    Open(newerVersion)
end

-- Monitoring: the same window, without marking anything as shown
function Update.Preview()
    Open("(preview)")
end

-- ============================================================================
-- REMINDER NEXT TO THE MINIMAP BUTTON (officers' "Remind outdated" in Monitoring)
-- ============================================================================
-- A small note beside the addon's minimap button (or the minimap, when the button is hidden), on the
-- side towards the middle of the screen, with the alert sound. It closes by itself after TOAST_FOR
-- seconds, with its X, or by a click on it. It takes no keyboard and does not stop the game.
local TOAST_FOR = 25
local TOAST_PADDING = 15  -- space between the note's edge and its contents
local toast = CreateFrame("Frame", "JagodkaUpdateToast", _G.UIParent, "BackdropTemplate")
toast:SetSize(290, 80)
toast:SetFrameStrata("DIALOG")
toast:SetClampedToScreen(true)
toast:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
toast:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
toast:SetBackdropBorderColor(0.75, 0.25, 1, 0.9)
toast:EnableMouse(true)
toast:Hide()
toast.icon = toast:CreateTexture(nil, "ARTWORK")
toast.icon:SetSize(30, 30)
toast.icon:SetPoint("LEFT", toast, "LEFT", TOAST_PADDING, 0)
toast.icon:SetTexture("Interface\\AddOns\\jagodka\\Media\\blueberry_one.tga")
toast.title = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
toast.title:SetPoint("TOPLEFT", toast, "TOPLEFT", TOAST_PADDING + 30 + 10, -TOAST_PADDING)
toast.title:SetText("|cffbf40ffJagodka|r - update available")
toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
toast.text:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -3)
toast.text:SetPoint("RIGHT", toast, "RIGHT", -TOAST_PADDING, 0)
toast.text:SetJustifyH("LEFT")
local toastClose = CreateFrame("Button", nil, toast, "UIPanelCloseButton")
toastClose:SetSize(20, 20)
toastClose:SetPoint("TOPRIGHT", toast, "TOPRIGHT", -3, -3)
toast:SetScript("OnMouseUp", function(self) self:Hide() end)
local toastToken = 0

local function PlaceToast()
    local button = _G.LibDBIcon10_JagodkiNadina
    local anchor = (button and button:IsVisible()) and button or _G.Minimap
    toast:ClearAllPoints()
    local x = anchor:GetCenter()
    if x and x > _G.UIParent:GetWidth() / 2 then
        toast:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
    else
        toast:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    end
end

-- newest: the version the reminder names
local function ShowToast(newest)
    toast.text:SetText("Your version " .. (GetAddOnMetadata(addonName, "Version") or "?") .. " is outdated (newest " .. tostring(newest)
        .. ").\nUpdate it in the |cffffd100CurseForge|r app.")
    -- As tall as its text, with TOAST_PADDING above and below
    toast:SetHeight(math.max(30, toast.title:GetStringHeight() + 3 + toast.text:GetStringHeight()) + 2 * TOAST_PADDING)
    PlaceToast()
    toast:Show()
    PlayAlert()
    toastToken = toastToken + 1
    local token = toastToken
    C_Timer.After(TOAST_FOR, function() if token == toastToken then toast:Hide() end end)
end

-- An officer's reminder (UPD packet, core.lua checks the officer and that my version is older): once per
-- newer version per REMIND_AGAIN_AFTER seconds, and after combat when it comes during one
local REMIND_AGAIN_AFTER = 1800
local remindedAt, remindPending = {}, nil
local RemindCombatWatcher = CreateFrame("Frame")
addonTable.SafeScript(RemindCombatWatcher, "OnEvent", "update.lua:173", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local version = remindPending
    remindPending = nil
    if version then Update.Remind(version) end
end)
function Update.Remind(newest)
    newest = tostring(newest)
    if remindedAt[newest] and _G.GetTime() - remindedAt[newest] < REMIND_AGAIN_AFTER then return end
    if InCombatLockdown() then
        remindPending = newest
        RemindCombatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    remindedAt[newest] = _G.GetTime()
    ShowToast(newest)
end

-- ============================================================================
-- WHAT'S NEW: a small window in the middle with the release notes of this version, and a sound
-- ============================================================================
--  * Shown once per version on each account, 25 s after the first login with it (core.lua calls
--    Update.ShowWhatsNewOnce), after combat when it comes during one. No notes for a version = the old chat
--    line instead (core.lua).
--  * A version in SPECIAL (1.0.0: out of beta) gets the festive look: a gold frame, the berry, a headline,
--    a thank-you line, and a short fanfare (about 3 s).
--  * Monitoring has temporary buttons that show both, to see them before a release.
-- The notes of a version come from releasenotes.lua (the same as the Release Notes tab and RELEASE_NOTES.md)
local function NotesFor(version) return addonTable.ReleaseNotes and addonTable.ReleaseNotes.Get(version) end
-- Festive shows by MINOR version ("1.0" = every 1.0.x): each account sees it once, with the first version of
-- that line it runs (JagodkiChatDB.festiveSeen), so players who update later see it too
local SPECIAL = {
    ["1.0"] = {
        headline = "Out of beta!",
        intro = "Thank you to everyone who tested the beta, reported problems and shared ideas. Jagodka is now 1.0.0: one community for all our guilds.",
        -- The authors' thanks, in the game's standard yellow (the font's own color), bigger
        -- Under the thank-you: the authors in the game's standard yellow, then their "Thank you!" in big red
        sign = "Lasarr & Trybekk",
        thanks = "Thank you!",
    },
}
-- A gentle sound for a regular update (the game's level-up fanfare)
local NEWS_SOUND = 888
-- The festive fanfare: the level-up fanfare, then the game's PvP victory music of your faction, which fades
-- out after FANFARE_FOR seconds
local FANFARE = { Alliance = 8455, Horde = 8454 }
local FANFARE_AFTER, FANFARE_FOR = 1.2, 6
-- The festive animation: berries rising behind the notes like confetti, a turning glow behind the big berry,
-- the headline pulsing; new berries for FX_FOR seconds, then the last ones float away
local FX_BERRIES, FX_FOR = 18, 9
local FX_GLOW = "Interface\\Cooldown\\star4"
local NEWS_WIDTH, SPECIAL_WIDTH = 440, 460
local REGULAR_BORDER, GOLD_BORDER = "Interface\\DialogFrame\\UI-DialogBox-Border", "Interface\\DialogFrame\\UI-DialogBox-Gold-Border"

local news = CreateFrame("Frame", "JagodkaWhatsNewFrame", _G.UIParent, "BackdropTemplate")
news:SetPoint("CENTER", 0, 80)
news:SetFrameStrata("FULLSCREEN_DIALOG")   -- above the fireworks and the addon window
news:EnableMouse(true)
news:Hide()
table.insert(_G.UISpecialFrames, "JagodkaWhatsNewFrame")

news.icon = news:CreateTexture(nil, "ARTWORK")
news.icon:SetSize(48, 48)
news.icon:SetTexture("Interface\\AddOns\\jagodka\\Media\\blueberry_one.tga")
news.headline = news:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
news.headline:SetTextColor(1, 0.82, 0)
news.title = news:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
news.sub = news:CreateFontString(nil, "OVERLAY", "GameFontNormal")
news.intro = news:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
news.intro:SetJustifyH("CENTER")
-- The thank-you (festive) bigger than the game's normal text, easy to read
news.intro:SetFont((news.intro:GetFont()), 15, "")
news.intro:SetSpacing(3)
-- The signature under the thank-you (festive): GameFontNormalHuge is the game's standard yellow
news.sign = news:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
news.sign:Hide()
-- Under the thank-you: "Lasarr & Trybekk thank you!" (festive), big, red with the names in yellow
news.thanks = news:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
news.thanks:SetTextColor(1, 0.25, 0.25)
news.thanks:SetFont(news.thanks:GetFont(), 28, "OUTLINE")
news.thanks:Hide()
news.body = news:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
news.body:SetJustifyH("LEFT")
news.body:SetSpacing(3)
news.ok = CreateFrame("Button", nil, news, "UIPanelButtonTemplate")
news.ok:SetSize(110, 22)
news.ok:SetPoint("BOTTOM", 0, 16)
news.ok:SetScript("OnClick", function() news:Hide() end)
news.help = news:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
news.help:SetPoint("BOTTOM", news.ok, "TOP", 0, 6)
news.help:SetText("More in Help (the ? buttons in the addon window)")

local function PlayFanfare()
    if not _G.PlaySound then return end
    pcall(_G.PlaySound, NEWS_SOUND, "Master")
    local id = FANFARE[(_G.UnitFactionGroup and _G.UnitFactionGroup("player")) or ""] or FANFARE.Alliance
    C_Timer.After(FANFARE_AFTER, function()
        if not news:IsShown() then return end
        local ok, willPlay, handle = pcall(_G.PlaySound, id, "Master")
        if ok and willPlay and handle and _G.StopSound then
            C_Timer.After(FANFARE_FOR, function() pcall(_G.StopSound, handle, 1500) end)
        end
    end)
end

-- The festive animation (only while the window shows; textures of the window itself, under its text)
local fx = { berries = {}, time = 0 }
fx.glow = news:CreateTexture(nil, "BORDER")
fx.glow:SetSize(130, 130)
fx.glow:SetTexture(FX_GLOW)
fx.glow:SetBlendMode("ADD")
fx.glow:SetVertexColor(0.75, 0.45, 1)
fx.glow:SetPoint("CENTER", news.icon, "CENTER")
fx.glow:Hide()
for i = 1, FX_BERRIES do
    local b = news:CreateTexture(nil, "BORDER")
    b:SetTexture("Interface\\AddOns\\jagodka\\Media\\blueberry_one.tga")
    b:Hide()
    fx.berries[i] = b
end
-- A berry starts at the bottom at a random place and size, rises with a sway, turns, and fades near the top
local function Launch(b, delay)
    b.size = math.random(12, 26)
    b:SetSize(b.size, b.size)
    b.x = math.random(20, math.max(21, math.floor(news:GetWidth()) - 20))
    b.age = -(delay or 0)
    b.life = 3 + math.random() * 2.5
    b.sway = 6 + math.random() * 12
    b.spin = (math.random() - 0.5) * 3
    b.phase = math.random() * 6.28
    b:Hide()
end
local function StopFX()
    news:SetScript("OnUpdate", nil)
    fx.glow:Hide()
    for _, b in ipairs(fx.berries) do b:Hide() end
    news.headline:SetAlpha(1)
end
-- festive: also the glow behind the big berry and the pulsing headline (1.0.0); a regular window has the berries
local function StartFX(festive)
    fx.time = 0
    for i, b in ipairs(fx.berries) do Launch(b, (i - 1) * 0.25) end
    fx.glow:SetShown(festive and true or false)
    -- Protected (safe.lua): an error is logged instead of repeating every frame
    addonTable.SafeScript(news, "OnUpdate", "update.lua:fx", function(_, elapsed)
        fx.time = fx.time + elapsed
        local height = news:GetHeight()
        local alive = false
        for _, b in ipairs(fx.berries) do
            b.age = b.age + elapsed
            if b.age >= 0 and b.age <= b.life then
                alive = true
                local p = b.age / b.life
                b:ClearAllPoints()
                b:SetPoint("CENTER", news, "BOTTOMLEFT", b.x + math.sin(b.phase + b.age * 2) * b.sway, 18 + p * (height - 36))
                b:SetAlpha(math.min(1, p * 4, (1 - p) * 3) * 0.45)
                if b.SetRotation then b:SetRotation(b.phase + b.age * b.spin) end
                b:Show()
            elseif b.age > b.life then
                b:Hide()
                -- New berries only for FX_FOR seconds; afterwards the last ones float away
                if fx.time < FX_FOR then Launch(b) alive = true end
            else
                alive = true
            end
        end
        if festive then
            if fx.glow.SetRotation then fx.glow:SetRotation(fx.time * 0.4) end
            fx.glow:SetAlpha(0.35 + 0.25 * math.sin(fx.time * 2.2))
            news.headline:SetAlpha(0.75 + 0.25 * math.sin(fx.time * 3))
        end
        if not alive and fx.time >= FX_FOR then
            for _, b in ipairs(fx.berries) do b:Hide() end
        end
    end)
end

-- ============================================================================
-- FIREWORKS (1.0.0): over the whole screen, behind the window, never taking the mouse
-- ============================================================================
-- Rockets rise from the bottom at random places and burst into sparks of one color, which spread, fall a little
-- and fade, with a bright flash at the burst. Textures come from a pool, at most FW_POOL at once.
-- One-time show for leaving the beta: while the window shows, a steady background show (a rocket every 0.08-0.2 s,
-- sometimes two; FW_MAX at most); the window's button (or Esc) fires the grand finale, FW_FINALE_PER rockets
-- every 0.1 s for FW_FINALE_FOR seconds with big bursts (more and faster sparks, a bigger flash, a ring of white
-- crackle), then the last sparks fade.
local FW_MAX, FW_POOL, FW_SPARKS = 300, 3600, 44
local FW_GRAVITY = 70
local FW_FINALE_FOR, FW_FINALE_PER, FW_BIG_SPARKS = 2, 4, 70
local FW_COLORS = {
    { 1, 0.3, 0.3 }, { 1, 0.82, 0.1 }, { 0.4, 1, 0.45 }, { 0.4, 0.7, 1 },
    { 0.8, 0.45, 1 }, { 1, 0.5, 0.9 }, { 1, 1, 1 },
}
local fw = CreateFrame("Frame", nil, _G.UIParent)
fw:SetAllPoints(_G.UIParent)
fw:SetFrameStrata("FULLSCREEN")   -- above the addon window (HIGH) and its popups, under the what's new window
fw:EnableMouse(false)
fw:Hide()
fw.pool, fw.live, fw.count = {}, {}, 0

local function FwTexture()
    local t = table.remove(fw.pool)
    if not t then
        if fw.count >= FW_POOL then return nil end
        fw.count = fw.count + 1
        t = fw:CreateTexture(nil, "OVERLAY")
        t:SetTexture(FX_GLOW)
        t:SetBlendMode("ADD")
    end
    return t
end

local function FwAdd(p)
    p.tex = FwTexture()
    if not p.tex then return end
    p.tex:SetVertexColor(p.r, p.g, p.b)
    p.age = 0
    table.insert(fw.live, p)
end

-- big: a finale rocket (a big burst, rising faster)
local function FwRocket(big)
    local w, h = fw:GetWidth(), fw:GetHeight()
    local c = FW_COLORS[math.random(#FW_COLORS)]
    FwAdd({ kind = "rocket", x = w * (0.05 + math.random() * 0.9), y = 0, vx = (math.random() - 0.5) * 40,
        vy = h * (big and (0.8 + math.random() * 0.3) or (0.55 + math.random() * 0.2)), top = h * (0.4 + math.random() * 0.5),
        size = big and 18 or 14, life = 4, r = 1, g = 0.9, b = 0.7, color = c, big = big })
end

local function FwBurst(x, y, c, big)
    FwAdd({ kind = "flash", x = x, y = y, vx = 0, vy = 0, size = big and 260 or 140, life = big and 0.55 or 0.4, r = c[1], g = c[2], b = c[3] })
    -- Big or small at random; sometimes a second color in the middle (always in a big one)
    local speed = big and (220 + math.random() * 140) or (90 + math.random() * 140)
    local c2 = (big or math.random() < 0.35) and FW_COLORS[math.random(#FW_COLORS)] or c
    local count = big and FW_BIG_SPARKS or FW_SPARKS
    for i = 1, count do
        local a = (i / count) * 6.283 + math.random() * 0.2
        local inner = i % 3 == 0
        local s = speed * (inner and 0.45 or 1) * (0.75 + math.random() * 0.45)
        local cc = inner and c2 or c
        FwAdd({ kind = "spark", x = x, y = y, vx = math.cos(a) * s, vy = math.sin(a) * s, size = (big and 12 or 9) + math.random() * 7,
            life = (big and 1.8 or 1.3) + math.random() * 0.9, r = cc[1], g = cc[2], b = cc[3] })
    end
    -- A big one also crackles: a quick ring of small white sparks
    if big then
        for i = 1, 16 do
            local a = (i / 16) * 6.283
            local s = speed * 1.25
            FwAdd({ kind = "spark", x = x, y = y, vx = math.cos(a) * s, vy = math.sin(a) * s, size = 7, life = 0.7, r = 1, g = 1, b = 1 })
        end
    end
end

local function FwStop()
    fw:SetScript("OnUpdate", nil)
    for _, p in ipairs(fw.live) do p.tex:Hide() table.insert(fw.pool, p.tex) end
    wipe(fw.live)
    fw:Hide()
end

local function FwStart()
    FwStop()
    fw.time, fw.nextAt, fw.stopping, fw.finaleUntil = 0, 0, false, nil
    fw:Show()
    addonTable.SafeScript(fw, "OnUpdate", "update.lua:fireworks", function(_, elapsed)
        fw.time = fw.time + elapsed
        if fw.finaleUntil then
            -- The grand finale: salvo after salvo across the screen, then no more rockets
            if fw.time < fw.finaleUntil and fw.time >= fw.nextAt then
                for _ = 1, FW_FINALE_PER do FwRocket(true) end
                fw.nextAt = fw.time + 0.1
            elseif fw.time >= fw.finaleUntil then
                fw.stopping = true
            end
        elseif not fw.stopping and fw.time < FW_MAX and fw.time >= fw.nextAt then
            FwRocket()
            -- Often two or three at once
            if math.random() < 0.3 then FwRocket() end
            fw.nextAt = fw.time + 0.08 + math.random() * 0.12
        end
        for i = #fw.live, 1, -1 do
            local p = fw.live[i]
            p.age = p.age + elapsed
            local done = p.age >= p.life
            if p.kind == "rocket" then
                p.x, p.y = p.x + p.vx * elapsed, p.y + p.vy * elapsed
                if p.y >= p.top then FwBurst(p.x, p.y, p.color, p.big) done = true end
            elseif p.kind == "spark" then
                p.vy = p.vy - FW_GRAVITY * elapsed
                p.vx, p.vy = p.vx * (1 - 0.6 * elapsed), p.vy * (1 - 0.6 * elapsed)
                p.x, p.y = p.x + p.vx * elapsed, p.y + p.vy * elapsed
            end
            if done then
                p.tex:Hide()
                table.insert(fw.pool, p.tex)
                table.remove(fw.live, i)
            else
                local fade = 1 - p.age / p.life
                local size = p.size
                if p.kind == "spark" then size = size * (0.5 + 0.5 * fade) end
                if p.kind == "flash" then size = size * (0.6 + 0.4 * (1 - fade)) end
                p.tex:SetSize(size, size)
                p.tex:ClearAllPoints()
                p.tex:SetPoint("CENTER", fw, "BOTTOMLEFT", p.x, p.y)
                p.tex:SetAlpha(p.kind == "rocket" and 1 or (fade * fade))
                p.tex:Show()
            end
        end
        if #fw.live == 0 and (fw.stopping or fw.time >= FW_MAX) then FwStop() end
    end)
end

-- ============================================================================
-- SHAKE (1.0.0): "Let's go!" in the festive window opens the addon window and shakes it for SHAKE_FOR seconds,
-- stronger at first, calming down; then it is back exactly where it was (also when closed during the shake)
-- ============================================================================
local SHAKE_FOR, SHAKE_PX = 2, 14
local shaker = CreateFrame("Frame")
local function ShakeMainWindow()
    local f = _G.JagodkiNadinaMainFrame
    if not f then return end
    -- On the community chat, General tab (core.lua)
    if addonTable.OpenCommunityChat then addonTable.OpenCommunityChat() else f:Show() end
    if shaker.active then return end
    local point, rel, relPoint, x, y = f:GetPoint(1)
    if not point then return end
    shaker.active, shaker.t = true, 0
    local function Done()
        shaker:SetScript("OnUpdate", nil)
        shaker.active = false
        f:ClearAllPoints()
        f:SetPoint(point, rel, relPoint, x, y)
    end
    addonTable.SafeScript(shaker, "OnUpdate", "update.lua:shake", function(self, elapsed)
        self.t = self.t + elapsed
        local left = 1 - self.t / SHAKE_FOR
        if left <= 0 or not f:IsShown() then Done() return end
        local a = SHAKE_PX * left
        f:ClearAllPoints()
        f:SetPoint(point, rel, relPoint, x + (math.random() * 2 - 1) * a, y + (math.random() * 2 - 1) * a)
    end)
end

news.ok:SetScript("OnClick", function() news:Hide() end)

-- Monitoring's simulation of the first festive login: the addon window closes, the show starts a moment later,
-- and closing it opens the window on the chat with the shake, as players will see it
function Update.SimulateFestive()
    if _G.JagodkiNadinaMainFrame then _G.JagodkiNadinaMainFrame:Hide() end
    C_Timer.After(0.6, function() Update.ShowWhatsNew("1.0.0", true) end)
end

-- Closing the window ("Let's go!" or Esc): the grand finale while the show runs, then it ends; the festive one
-- also opens the addon window on the community chat and shakes it
news:SetScript("OnHide", function()
    StopFX()
    if fw:IsShown() and not fw.stopping and not fw.finaleUntil then
        fw.finaleUntil, fw.nextAt = fw.time + FW_FINALE_FOR, fw.time
    end
    if news.festive then
        news.festive = false
        -- A moment later: Esc closes every window on the game's list in one go, and the addon window comes after
        -- this one there, so opening it at once got it closed by the same Esc
        C_Timer.After(0.05, ShakeMainWindow)
    end
end)

-- "1.0.3" -> "1.0"
local function MinorOf(version) return tostring(version or ""):match("^(%d+%.%d+)") end

-- version: whose notes (default: this addon's version); festive: the festive show of its minor version, with
-- the notes of this version or, when it has none, of the line's first one ("1.0.0"). False = nothing to show.
function Update.ShowWhatsNew(version, festive)
    version = version or GetAddOnMetadata(addonName, "Version") or "?"
    local special = festive and SPECIAL[MinorOf(version) or ""] or nil
    -- The festive window lists no changes (they are in the Release Notes tab): only the thank-you and signature
    local lines = NotesFor(version)
    if not lines and not special then return false end
    local width = special and SPECIAL_WIDTH or NEWS_WIDTH
    news:SetWidth(width)
    news:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = special and GOLD_BORDER or REGULAR_BORDER,
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    -- Top to bottom: [berry, headline,] title, "What's new", [thank-you,] the notes
    local top = nil
    local function Place(fs, gap)
        fs:ClearAllPoints()
        if not top then fs:SetPoint("TOP", news, "TOP", 0, -20) else fs:SetPoint("TOP", top, "BOTTOM", 0, -gap) end
        top = fs
    end
    news.icon:SetShown(special ~= nil)
    news.headline:SetShown(special ~= nil)
    news.intro:SetShown(special ~= nil)
    if special then
        news.icon:ClearAllPoints()
        news.icon:SetPoint("TOP", news, "TOP", 0, -18)
        top = news.icon
        news.headline:SetText(special.headline)
        Place(news.headline, 6)
    end
    news.title:SetText("|cffbf40ffJagodki Nadina - Community|r |cffffffff" .. version .. "|r")
    Place(news.title, 6)
    news.sub:SetShown(special == nil)
    news.sign:SetShown(special ~= nil)
    news.thanks:SetShown(special ~= nil)
    news.body:Hide()
    news.rows = news.rows or {}
    local RN = addonTable.ReleaseNotes
    RN.HideRows(news.rows)
    local y
    if special then
        -- Festive: the thank-you, signed by the authors in the game's standard yellow, a bigger font
        news.intro:SetWidth(width - 56)
        news.intro:SetText(special.intro)
        Place(news.intro, 14)
        news.sign:SetText(special.sign or "")
        Place(news.sign, 14)
        news.thanks:SetText(special.thanks or "")
        Place(news.thanks, 8)
        y = 20 + 48 + 6 + news.headline:GetStringHeight() + 6 + news.title:GetStringHeight() + 14
            + news.intro:GetStringHeight() + 14 + news.sign:GetStringHeight() + 8 + news.thanks:GetStringHeight() + 10
        news.help:SetText("Everything new is in the |cffffd100Release Notes|r tab")
    else
        news.sub:SetText("What's new")
        Place(news.sub, 4)
        -- The notes, drawn by releasenotes.lua the same way as the Release Notes tab: a berry before each point,
        -- its lines indented, gold section headings (24 px from the edge)
        local above = 20 + news.title:GetStringHeight() + 4 + news.sub:GetStringHeight()
        y = RN.Draw(news, news.rows, lines, 24, above, width - 48, 12)
        news.help:SetText("More in Help (the ? buttons in the addon window)")
    end
    news.ok:SetText(special and "Let's go!" or "OK")
    news.festive = special ~= nil
    -- Height: the content ends at y, then the hint and the button
    news:SetHeight(y + 64)
    StopFX()
    news:Show()
    StartFX(special ~= nil)
    if special then PlayFanfare() FwStart()
    elseif _G.PlaySound then pcall(_G.PlaySound, NEWS_SOUND, "Master") end
    return true
end

-- Once per version on this account (JagodkiChatDB.whatsNewSeen, core.lua); out of combat. Returns false
-- when this version has no notes (core.lua then writes its chat line).
-- Shows it and only then marks it seen on this account (whatsNewSeen for the version, festiveSeen for the 1.0
-- line), so a show that never got on screen (e.g. logging out during the fight it waited for) comes next time
local function ShowAndMark(version, festive)
    local db = _G.JagodkiChatDB
    if not Update.ShowWhatsNew(version, festive) then return false end
    db.whatsNewSeen = version
    if festive then
        db.festiveSeen = db.festiveSeen or {}
        db.festiveSeen[MinorOf(version)] = true
    end
    return true
end
local newsPending = nil
local NewsCombatWatcher = CreateFrame("Frame")
addonTable.SafeScript(NewsCombatWatcher, "OnEvent", "update.lua:news", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local pending = newsPending
    newsPending = nil
    if pending then ShowAndMark(pending.version, pending.festive) end
end)
-- The festive show the first time this account runs a version of a festive line (1.0.x, also on a fresh
-- install), otherwise the regular notes of this version (after an update or a fresh install alike). Exactly
-- once: core.lua calls it only while whatsNewSeen is not this version, and it is marked when shown.
-- Returns false when there is nothing to show (core.lua then writes its chat line and marks the version).
function Update.ShowWhatsNewOnce(version)
    local minor = MinorOf(version)
    _G.JagodkiChatDB = _G.JagodkiChatDB or {}
    local db = _G.JagodkiChatDB
    local festive = minor ~= nil and SPECIAL[minor] ~= nil and not (db.festiveSeen and db.festiveSeen[minor])
    if not festive and not NotesFor(version) then return false end
    if InCombatLockdown() then
        newsPending = { version = version, festive = festive }
        NewsCombatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        return true
    end
    return ShowAndMark(version, festive)
end

-- Monitoring: the newest notes as a regular window (temporary test button), and the festive show with the
-- fireworks (the permanent "Fireworks" button, for occasions)
-- The regular window of the installed version (0.15.6 now), as players will see it after this update
function Update.PreviewWhatsNew()
    local version = GetAddOnMetadata(addonName, "Version") or "?"
    if not Update.ShowWhatsNew(version) and _G.UIErrorsFrame then
        _G.UIErrorsFrame:AddMessage("No what's new notes for " .. version .. " in update.lua", 1, 0.3, 0.3, 1, 3)
    end
end
function Update.PreviewSpecial() Update.ShowWhatsNew("1.0.0", true) end
