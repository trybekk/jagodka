-- ============================================================================
-- ARMORY: link to a character's page on the WoW Forever armory (Roster tab, "Armory" column)
-- ============================================================================
--  * An icon in each row; a click opens a small box under it with the link, already selected, so
--    Ctrl+C copies it (the game does not let addons put anything on the clipboard themselves).
--    After Ctrl+C the box closes; Esc, the X or another click on the icon close it too.
--  * Link: BASE_URL .. "First-Surname". Characters with no surname (Classic Era) have no armory page,
--    so their icon is hidden.
--  * The name is percent-encoded (UTF-8 bytes), so letters like "ó", spaces, apostrophes or anything
--    else cannot break the link or turn it into a different address.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local CreateFrame = _G.CreateFrame
local C_Timer = addonTable.SafeTimer -- protected callbacks (safe.lua)
local string, table, type = _G.string, _G.table, _G.type

local Armory = {}
addonTable.Armory = Armory

-- 0.15.6+: Sixty Upgrades' armory (before: armorywowforever.com/c/forever/eu/pvp/)
local BASE_URL = "https://sixtyupgrades.com/forever/armory/eu/pvp/"
local ICON = "Interface\\Icons\\INV_Chest_Plate01"

local box = nil

-- "Marianek Jagoda" -> "Marianek-Jagoda"; nil for a name without a surname
local function Slug(name)
    if type(name) ~= "string" then return nil end
    local parts = {}
    for part in name:gmatch("[^%s%-]+") do parts[#parts + 1] = part end
    if #parts < 2 then return nil end
    -- Only letters, digits and "-" stay as they are; every other byte is encoded
    local slug = table.concat(parts, "-")
    return (slug:gsub("[^%w%-]", function(c) return string.format("%%%02X", c:byte()) end))
end

function Armory.Url(name)
    local slug = Slug(name)
    return slug and (BASE_URL .. slug) or nil
end

local function CreateBox(parent)
    box = CreateFrame("Frame", "JagodkaArmoryBox", parent, "BackdropTemplate")
    box:SetSize(380, 30)
    box:SetFrameStrata("DIALOG")
    box:SetClampedToScreen(true)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    box:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
    box:SetBackdropBorderColor(0.75, 0.25, 1, 0.8)
    box:EnableMouse(true)
    box:Hide()
    local close = CreateFrame("Button", nil, box, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("LEFT", box, "LEFT", 2, 0)
    box.hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    box.hint:SetPoint("LEFT", close, "RIGHT", 2, 0)
    box.hint:SetText("Ctrl+C")
    local input = CreateFrame("EditBox", "JagodkaArmoryInput", box, "InputBoxTemplate")
    input:SetHeight(20)
    input:SetPoint("LEFT", box.hint, "RIGHT", 12, 0)
    input:SetPoint("RIGHT", box, "RIGHT", -8, 0)
    input:SetAutoFocus(false)
    input:SetFontObject(_G.ChatFontSmall or _G.ChatFontNormal)
    -- Read only: typing puts the link back, selected again
    input:SetScript("OnTextChanged", function(self, userInput)
        if userInput and box.url then self:SetText(box.url) self:HighlightText() end
    end)
    input:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    input:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    input:SetScript("OnEscapePressed", function() box:Hide() end)
    input:SetScript("OnEnterPressed", function() box:Hide() end)
    -- The copy itself is the game's own Ctrl+C; afterwards the box closes
    input:SetScript("OnKeyDown", function(_, key)
        if key == "C" and _G.IsControlKeyDown() then
            C_Timer.After(0.1, function()
                box:Hide()
                if _G.UIErrorsFrame then _G.UIErrorsFrame:AddMessage(box.copiedText or "Copied", 0.75, 0.25, 1, 1, 2) end
            end)
        end
    end)
    box:SetScript("OnHide", function() input:ClearFocus() box.anchor = nil end)
    box.input = input
end

-- The box with any text, selected for Ctrl+C. anchor: the frame it opens under (nil = at the mouse);
-- copied: the message after Ctrl+C; width: of the box (default 380)
local function ShowBox(anchor, text, copied, width, alignRight)
    -- In the main window (not a tab), so it works from the Roster rows and from the character card
    if not box then CreateBox(_G.JagodkiNadinaMainFrame or _G.UIParent) end
    box.url, box.anchor, box.copiedText = text, anchor, copied
    box:SetWidth(width or 380)
    box:ClearAllPoints()
    -- Opens to the right of the icon: X, "Ctrl+C", the text; alignRight (character card, at the
    -- window's right edge) = to the left of it
    if not anchor then
        local x, y = _G.GetCursorPosition()
        local scale = _G.UIParent:GetEffectiveScale()
        box:SetPoint("TOPLEFT", _G.UIParent, "BOTTOMLEFT", x / scale - 8, y / scale - 4)
    elseif alignRight then box:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    else box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -8, -2) end
    box:Show()
    box.input:SetText(text)
    box.input:SetCursorPosition(0)
    box.input:SetFocus()
    box.input:HighlightText()
end

local function Open(button)
    local url = Armory.Url(button.name)
    if not url then return end
    if box and box:IsShown() and box.anchor == button then box:Hide() return end
    ShowBox(button, url, "Armory link copied", nil, button.alignRight)
end

-- 0.15.6+: a player's name ("First Surname") in the same box, for Ctrl+C (Roster menu: "Copy name").
-- anchor: the row (the box opens under it), or nil = at the mouse
function Armory.CopyName(name, anchor)
    if type(name) ~= "string" or name == "" then return end
    ShowBox(anchor, name, "Name copied", 260)
end

-- For other buttons (charcard.lua): button.name = the character
Armory.Open = Open

-- core.lua: one icon per Roster row (row.armoryBtn)
function Armory.AttachRow(row)
    local button = CreateFrame("Button", nil, row)
    button:SetSize(14, 14)
    button.tex = button:CreateTexture(nil, "ARTWORK")
    button.tex:SetAllPoints()
    button.tex:SetTexture(ICON)
    button.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnClick", Open)
    button:SetScript("OnEnter", function(self)
        _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        _G.GameTooltip:SetText("Armory", 1, 1, 1)
        _G.GameTooltip:AddLine("Click for the link to copy.", 0.8, 0.8, 0.8)
        _G.GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
    row.armoryBtn = button
end

-- core.lua calls this when drawing a row
function Armory.UpdateRow(row, member)
    local button = row.armoryBtn
    button.name = member.name
    if Slug(member.name) then button:Show() else button:Hide() end
    -- Scrolling or paging can put someone else in this row
    if box and box:IsShown() and box.anchor == button and box.url ~= Armory.Url(member.name) then box:Hide() end
end
