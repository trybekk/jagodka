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