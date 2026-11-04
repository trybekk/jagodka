-- ============================================================================
-- UPDATE: window telling the player their addon is outdated, with the download link
-- ============================================================================
--  * Shown when a player with a newer version is seen (core.lua, CheckPlayerVersion), once per
--    newer version per session, and only out of combat. The chat warning stays as well.
--  * The game cannot open links, so the link is in a text field: a click selects it for Ctrl+C.
--    The field does not take the keyboard by itself, so the window never blocks movement keys.
--  * Our own window rather than a game popup, because a popup is too narrow for the link.
--  * Monitoring has a button that shows the same window as a preview.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local GetAddOnMetadata = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
local tostring = _G.tostring
local table = _G.table

-- Change here when the download moves
local DOWNLOAD_URL = "https://github.com/trybekk/jagodka/archive/refs/heads/feature/lasarr-1.zip"
local WIDTH, HEIGHT = 500, 200

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
message:SetPoint("TOP", title, "BOTTOM", 0, -10)
message:SetWidth(WIDTH - 40)
message:SetJustifyH("CENTER")

local link = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
link:SetSize(WIDTH - 60, 20)
link:SetPoint("TOP", message, "BOTTOM", 0, -10)
link:SetAutoFocus(false)
link:SetFontObject("GameFontHighlightSmall")
-- The field always holds the link, so typing in it changes nothing
link:SetScript("OnTextChanged", function(self, userInput)
    if userInput and self:GetText() ~= DOWNLOAD_URL then
        self:SetText(DOWNLOAD_URL)
        self:HighlightText()
    end
end)
-- Also on mouse up, because the click itself places the cursor after the focus selected the text
link:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
link:SetScript("OnMouseUp", function(self) self:HighlightText() end)
link:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
link:SetScript("OnEnterPressed", function() frame:Hide() end)
link:SetScript("OnEscapePressed", function() frame:Hide() end)

local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
close:SetSize(100, 22)
close:SetPoint("BOTTOM", 0, 18)
close:SetText("Close")
close:SetScript("OnClick", function() frame:Hide() end)

frame:SetScript("OnHide", function() link:ClearFocus() end)

local function Open(newest)
    message:SetText("|cffff5555Your addon is outdated.|r\nYour version: " .. (GetAddOnMetadata(addonName, "Version") or "?")
        .. ", newest seen: " .. newest .. "\n\nDownload the new version (click the link, then Ctrl+C):")
    link:SetText(DOWNLOAD_URL)
    link:SetCursorPosition(0)
    frame:Show()
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
