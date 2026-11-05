-- ============================================================================
-- UPDATE: window telling the player their addon is outdated
-- ============================================================================
--  * Shown when a player with a newer version is seen (core.lua, CheckPlayerVersion), once per
--    newer version per session, and only out of combat. The chat line stays as well.
--  * It says the new version is on CurseForge (the CurseForge app updates it), and plays the game's
--    raid warning sound twice, so it is not missed.
--  * Our own window rather than a game popup, so it fits the text and does not take the keyboard.
--  * Monitoring has a button that shows the same window as a preview.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local GetAddOnMetadata = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
local tostring = _G.tostring
local table = _G.table

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
CombatWatcher:SetScript("OnEvent", function(self)
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