-- ============================================================================
-- LOOKS (1.2.0): the window's look can be switched in Settings > Appearance. Only the look: the layout is the
-- same as the classic one (tabs on top, the same panels in the same places, the right column) and every frame
-- keeps doing exactly what it did (the same data, the same functions, nothing sent). Loaded after core.lua.
--  * "classic": the addon as it always looked. Nothing in this file runs for it.
--  * "forest" (Forest Berry, in Polish Leśna Jagoda): a textured dark plum window in a gold frame, a title plaque with the wolf crest,
--    purple tabs, panels in thin gold frames, banners and berries. Art: Media\forest (made with
--    tools\png2tga.ps1 from the user's PNGs in ui-concept, which is not part of the addon).
--  * The choice is kept for the account (JagodkiMinimapDB.theme) and takes effect after /reload: restyling the
--    hundreds of frames on the fly would risk leaving half of them in the old look.
--  * Every ornament is a texture of the window itself, so all buttons and panels stay above it (nothing gets
--    covered or stops taking clicks); outside the window's edge the ornaments show in full.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local CreateFrame = _G.CreateFrame
local ipairs, pairs, type, pcall = _G.ipairs, _G.pairs, _G.type, _G.pcall

local Theme = {}
addonTable.Theme = Theme

local MEDIA = "Interface\\AddOns\\jagodka\\Media\\forest\\"
local TITLE_FONT = "Fonts\\FRIZQT__.TTF"

Theme.LIST = {
    { key = "classic", name = "Jagódki (classic)", desc = "The addon as you know it: dark and plain." },
    -- Names and texts in the game's UI font, which has no Polish letters except ó (ś, ł, ą... show as garbage)
    { key = "forest", name = "Forest Berry", desc = "A painted wooden frame with vines, berries and the wolf crest, purple tabs. The same layout. New, in testing." },
}

-- The saved choice (what the next /reload uses) and the one in use now (fixed at login)
local active = "classic"
function Theme.Saved()
    local db = _G.JagodkiMinimapDB
    local key = type(db) == "table" and db.theme or nil
    for _, t in ipairs(Theme.LIST) do if t.key == key then return key end end
    return "classic"
end
function Theme.Active() return active end
function Theme.Set(key)
    _G.JagodkiMinimapDB = _G.JagodkiMinimapDB or {}
    _G.JagodkiMinimapDB.theme = key
end
function Theme.Name(key)
    for _, t in ipairs(Theme.LIST) do if t.key == key then return t.name end end
    return key
end

-- ----------------------------------------------------------------------------
-- LEŚNA JAGODA
-- ----------------------------------------------------------------------------
local C = {
    panel = { 0.07, 0.045, 0.085, 0.82 },
    gold = { 0.95, 0.80, 0.48 },
    purple = { 0.56, 0.27, 0.93 },
    purpleDeep = { 0.24, 0.09, 0.40 },
    text = { 0.82, 0.78, 0.86 },
}
Theme.colors = C

local function Color(c, a) return c[1], c[2], c[3], a or c[4] or 1 end

-- A gradient on a texture (newer clients: SetGradient with colors; older: SetGradientAlpha), plain color otherwise
local function Gradient(tex, orientation, c1, a1, c2, a2)
    tex:SetColorTexture(1, 1, 1, 1)
    if _G.CreateColor and pcall(tex.SetGradient, tex, orientation, _G.CreateColor(c1[1], c1[2], c1[3], a1), _G.CreateColor(c2[1], c2[2], c2[3], a2)) then return end
    if tex.SetGradientAlpha and pcall(tex.SetGradientAlpha, tex, orientation, c1[1], c1[2], c1[3], a1, c2[1], c2[2], c2[3], a2) then return end
    tex:SetColorTexture(c1[1], c1[2], c1[3], a1)
end

-- A texture from Media\forest; l, r, t, b = the part of the file to show (texture coordinates)
local function Tex(parent, layer, sub, file, l, r, t, b)
    local x = parent:CreateTexture(nil, layer, nil, sub or 0)
    x:SetTexture(MEDIA .. file)
    x:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
    return x
end

-- A label above a panel (a FontString anchored to the panel's top left from above, as core.lua places the right
-- column's "Events / LFG", "Officers online", "Guilds"...): gold, with a thin gold line from after its help "?"
-- to the panel's right edge, fading out, so the label heads its panel. It stays in the gap between the panels
-- (a tab under the label filled that gap and glued the sections together).
-- center = how high the label's middle is above the panel's top edge (the line runs at that height)
local function LabelLine(fs, owner, frame, center)
    if fs.forestLine then return end
    fs.forestLine = true
    fs:SetTextColor(Color(C.gold))
    local line = owner:CreateTexture(nil, "ARTWORK", nil, 1)
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 30, 0)
    line:SetPoint("RIGHT", frame, "TOPRIGHT", -8, center)
    Gradient(line, "HORIZONTAL", C.gold, 0.55, C.gold, 0)
end
local function FindLabels(frame)
    local function Scan(owner, ...)
        for i = 1, select("#", ...) do
            local r = select(i, ...)
            if r and r.GetObjectType and r:GetObjectType() == "FontString" and r.GetNumPoints and r:GetNumPoints() == 1 then
                local point, rel, relPoint, _, y = r:GetPoint(1)
                if rel == frame and relPoint == "TOPLEFT" and (point == "BOTTOMLEFT" or (point == "TOPLEFT" and (y or 0) > 0)) then
                    local _, size = r:GetFont()
                    local half = (size or 12) / 2
                    LabelLine(r, owner, frame, point == "BOTTOMLEFT" and (y or 0) + half or (y or 0) - half)
                end
            end
        end
    end
    Scan(frame, frame:GetRegions())
    local parent = frame:GetParent()
    if parent and parent.GetRegions then Scan(parent, parent:GetRegions()) end
end

-- Every panel of the addon (core.lua ApplyModernStyle): a rounded panel, plum inside, a muted bronze rim with
-- a warm highlight on top (tools\make-panel-art.ps1 draws the 16 px pieces, so they join exactly)
local function StylePanel(frame)
    if not frame or not frame.SetBackdropColor then return end
    frame:SetBackdropColor(0, 0, 0, 0)
    frame:SetBackdropBorderColor(0, 0, 0, 0)
    if frame.forestFrame or not frame.CreateTexture then return end
    frame.forestFrame = true
    local function P(file, p1, p2)
        local t = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
        t:SetTexture(MEDIA .. file)
        t:SetPoint(p1[1], frame, p1[2], p1[3], p1[4])
        if p2 then t:SetPoint(p2[1], frame, p2[2], p2[3], p2[4]) end
        return t
    end
    P("panel_tl", { "TOPLEFT", "TOPLEFT", 0, 0 }):SetSize(16, 16)
    P("panel_tr", { "TOPRIGHT", "TOPRIGHT", 0, 0 }):SetSize(16, 16)
    P("panel_bl", { "BOTTOMLEFT", "BOTTOMLEFT", 0, 0 }):SetSize(16, 16)
    P("panel_br", { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 }):SetSize(16, 16)
    P("panel_top", { "TOPLEFT", "TOPLEFT", 16, 0 }, { "TOPRIGHT", "TOPRIGHT", -16, 0 }):SetHeight(16)
    P("panel_bottom", { "BOTTOMLEFT", "BOTTOMLEFT", 16, 0 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", -16, 0 }):SetHeight(16)
    P("panel_left", { "TOPLEFT", "TOPLEFT", 0, -16 }, { "BOTTOMLEFT", "BOTTOMLEFT", 0, 16 }):SetWidth(16)
    P("panel_right", { "TOPRIGHT", "TOPRIGHT", 0, -16 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 16 }):SetWidth(16)
    local fill = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    fill:SetColorTexture(22 / 255, 15 / 255, 28 / 255, 222 / 255)
    fill:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
    fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
    -- labels may be made right after the panel: look for them a moment later too
    FindLabels(frame)
    _G.C_Timer.After(0, function() FindLabels(frame) end)
end

-- The tab buttons in the same row: purple 3-part textures (normal, hover, chosen) and gold icons.
-- The classic look's textures stay (core.lua keeps coloring them on every tab change), only unseen.
local TAB_ICONS = { [1] = "icon_chat", [11] = "icon_announcements", [2] = "icon_roster", [4] = "icon_events", [5] = "icon_calendar",
    [9] = "icon_lfg", [7] = "icon_help", [8] = "icon_settings", [6] = "icon_monitoring", [10] = "icon_release_notes" }
local TAB_DIM = { 0.74, 0.66, 0.84 }
local TAB_GOLD = { 1, 0.86, 0.47 }

-- The chosen plate (the purple plate with cut corners, tabplate_l/m/r: art 24 + stretch + 24 on 59 px), `grow`
-- px bigger than the button all round, under its icon and text
local function TabPlate(btn, grow)
    local ph = btn:GetHeight() + 2 * grow
    local cap = math.floor(ph * 24 / 59 + 0.5)
    local pl = Tex(btn, "BACKGROUND", 2, "tabplate_l", 0, 24 / 32, 0, 59 / 64)
    pl:SetPoint("TOPLEFT", btn, "TOPLEFT", -grow, grow) pl:SetSize(cap, ph)
    local pr = Tex(btn, "BACKGROUND", 2, "tabplate_r", 0, 24 / 32, 0, 59 / 64)
    pr:SetPoint("TOPRIGHT", btn, "TOPRIGHT", grow, grow) pr:SetSize(cap, ph)
    local pm = Tex(btn, "BACKGROUND", 2, "tabplate_m", 0, 1, 0, 59 / 64)
    pm:SetPoint("TOPLEFT", pl, "TOPRIGHT") pm:SetPoint("BOTTOMRIGHT", pr, "BOTTOMLEFT")
    return { pl, pm, pr }
end
-- The hover glow: purple, rising from the bottom
local function TabGlow(btn)
    local g = Tex(btn, "BACKGROUND", 1, "tabglow")
    g:SetBlendMode("ADD")
    g:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    g:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, -3)
    return g
end
-- A thin gold divider in the gap left of the button (`gap` = the space between two buttons)
local function TabDivider(btn, gap, inset)
    local d = btn:CreateTexture(nil, "BACKGROUND", nil, 0)
    d:SetWidth(1)
    d:SetPoint("TOP", btn, "TOPLEFT", -gap / 2, -inset)
    d:SetPoint("BOTTOM", btn, "BOTTOMLEFT", -gap / 2, inset)
    Gradient(d, "VERTICAL", C.gold, 0.1, C.gold, 0.55)
    return d
end
-- The dark carved bar behind a row of tabs, on `owner` (a frame under the buttons): its fill, a gold top edge, a
-- bronze bottom edge and a gold diamond with a purple heart at each end (gem = their size, 0 for none).
-- Returns Place(l, r, top, bottom, rel, relPoint [, relR, relPointR]): lays it out, in px from rel's relPoint
-- (the right end from relR's relPointR when given). opts (a table instead of gem): gem, noBottom = no bottom edge
-- (the bar sits on a panel whose gold rim is that edge, so the two lines are one), fadeLeft = px over which its
-- left end fades out (instead of a diamond).
local function TabRail(owner, gem)
    local opts = type(gem) == "table" and gem or { gem = gem }
    gem = opts.gem or 0
    local parts = {}
    local function T(sub)
        local t = owner:CreateTexture(nil, "ARTWORK", nil, sub)
        return t
    end
    -- sublevels 2-6: above a label's gold line (LabelLine, sublevel 1), which the bar covers where they meet
    parts.fill = T(2)
    Gradient(parts.fill, "VERTICAL", { 0.11, 0.05, 0.15 }, 0.95, { 0.04, 0.02, 0.05 }, 0.95)
    parts.top = T(3) Gradient(parts.top, "HORIZONTAL", C.gold, 0.25, C.gold, 0.6)
    parts.topDark = T(3) parts.topDark:SetColorTexture(0, 0, 0, 0.6)
    parts.bottom = T(3) parts.bottom:SetColorTexture(0.62, 0.45, 0.22, 0.95)
    parts.bottomHi = T(4) parts.bottomHi:SetColorTexture(TAB_GOLD[1], TAB_GOLD[2], TAB_GOLD[3], 0.45)
    local gems = {}
    if gem > 0 then
        for k = 1, 2 do
            local g = T(5) g:SetColorTexture(Color(C.gold)) g:SetSize(gem, gem)
            local gi = T(6) gi:SetColorTexture(Color(C.purple)) gi:SetSize(math.max(2, gem - 5), math.max(2, gem - 5))
            if g.SetRotation then g:SetRotation(math.rad(45)) gi:SetRotation(math.rad(45)) end
            gems[k] = { g, gi }
        end
    end
    local bottomW = gem >= 9 and 2 or 1
    if opts.noBottom then parts.bottom:Hide() parts.bottomHi:Hide() end
    local fade = opts.fadeLeft or 0
    if fade > 0 then
        -- the left end: the fill and the top edge fading in from nothing
        parts.fadeFill = T(2)
        Gradient(parts.fadeFill, "HORIZONTAL", { 0.07, 0.03, 0.10 }, 0, { 0.07, 0.03, 0.10 }, 0.95)
        parts.fadeTop = T(3)
        Gradient(parts.fadeTop, "HORIZONTAL", C.gold, 0, C.gold, 0.25)
    end
    return function(l, r, top, bottom, rel, relPoint, relR, relPointR)
        relR, relPointR = relR or rel, relPointR or relPoint
        local function Span(t, y1, y2, x1, x2)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", rel, relPoint, x1 or (l + fade), y1)
            if x2 then t:SetPoint("BOTTOMRIGHT", rel, relPoint, x2, y2)
            else t:SetPoint("BOTTOMRIGHT", relR, relPointR, r, y2) end
        end
        Span(parts.fill, top, bottom)
        Span(parts.top, top, top - 1)
        Span(parts.topDark, top - 1, top - 2)
        Span(parts.bottom, bottom + bottomW, bottom)
        Span(parts.bottomHi, bottom + bottomW + 1, bottom + bottomW)
        if fade > 0 then
            Span(parts.fadeFill, top, bottom, l, l + fade)
            Span(parts.fadeTop, top, top - 1, l, l + fade)
        end
        for k, x in ipairs({ l, r }) do
            for _, t in ipairs(gems[k] or {}) do
                t:ClearAllPoints()
                t:SetPoint("CENTER", k == 1 and rel or relR, k == 1 and relPoint or relPointR, x, (top + bottom) / 2)
            end
        end
    end
end

-- A row of small tabs (the chat's General / Trade / LFG / Officers, the right column's Signed / Other / LFG), in
-- the same look as the main tabs, smaller: the carved bar behind the row, gold dividers, lavender names; the
-- chosen one on the purple plate with a gold name and a small gold flourish under it; hover: gold name and glow.
-- core.lua marks the chosen one by its text color (white or gold, the others gray), so a hook on that call picks
-- the state; the classic textures stay, unseen. `row` = the buttons left to right; the bar spans the shown ones.
-- Both rows stand on their panel's top edge, so the bar sits on the panel: no bottom edge of its own (the panel's
-- gold rim is that line, one straight line; user's chat-taby.png: the two lines were 3 px apart) and no diamonds.
-- mode "full" (the chat): the bar runs the panel's whole width, a strip on top of it. Otherwise (the right
-- column, whose label "Events / LFG" is left of the buttons): from the first button, its left end fading out, to
-- the panel's right edge (the last button is 6 px in from it).
local function StyleSubTabRow(row, mode)
    if #row == 0 then return end
    local owner = row[1]:GetParent()
    local full = mode == "full"
    local FADE = 24
    local Place = TabRail(owner, { gem = 0, noBottom = true, fadeLeft = full and 0 or FADE })
    local function LayoutRail()
        local first, last
        for _, b in ipairs(row) do
            if b:IsShown() then first = first or b last = b end
        end
        if not first then return end
        local h = first:GetHeight()
        if full then
            Place(0, 0, h + 3, 0, owner, "TOPLEFT", owner, "TOPRIGHT")
        else
            Place(-8 - FADE, 6, 3, -h, first, "TOPLEFT", last, "TOPRIGHT")
        end
    end
    for idx, btn in ipairs(row) do
        if not btn.forestSub and btn.text then
            btn.forestSub = true
            if btn.bg then btn.bg:SetAlpha(0) end
            if btn.topLine then btn.topLine:SetAlpha(0) end
            if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(0, 0, 0, 0) end
            btn.fplate = TabPlate(btn, 2)
            btn.fglow = TabGlow(btn)
            btn.fflourish = Tex(btn, "OVERLAY", 3, "tabflourish")
            btn.fflourish:SetSize(math.min(110, btn:GetWidth()), 10)
            btn.fflourish:SetPoint("CENTER", btn, "BOTTOM", 0, -3)
            if idx > 1 then TabDivider(btn, 4, 4) end
            btn.text:SetShadowColor(0, 0, 0, 1) btn.text:SetShadowOffset(1, -1)
            local busy = false
            local function Show()
                local on, hov = btn.fon, btn.fhovered
                for _, t in ipairs(btn.fplate) do t:SetShown(on) end
                btn.fflourish:SetShown(on)
                btn.fglow:SetShown(hov and not on)
                busy = true
                btn.text:SetTextColor(Color((on or hov) and TAB_GOLD or TAB_DIM))
                busy = false
                if btn.icon and btn.icon.SetAlpha then btn.icon:SetAlpha((on or hov) and 1 or 0.7) end
            end
            _G.hooksecurefunc(btn.text, "SetTextColor", function(_, r)
                if busy then return end
                btn.fon = (r or 0) >= 0.95
                Show()
            end)
            btn:HookScript("OnEnter", function() btn.fhovered = true Show() end)
            btn:HookScript("OnLeave", function() btn.fhovered = nil Show() end)
            -- Officers shows only for officers: the bar follows
            btn:HookScript("OnShow", LayoutRail)
            btn:HookScript("OnHide", LayoutRail)
            btn.fon = ((btn.text:GetTextColor()) or 0) >= 0.95
            Show()
        end
    end
    owner:HookScript("OnShow", LayoutRail)
    LayoutRail()
end

-- The main tabs on one carved bar (user: "zreworkować główne taby... coś drastycznie fajnego"; chosen: the carved
-- bar, as the LFG tabs in expected1.png): a dark bar behind the whole row with gold edges and a gold diamond at
-- each end, thin gold dividers between the tabs, the tabs themselves without frames (icon + lavender name). The
-- chosen one: the purple plate with cut corners and a gold rim (ui-concept 14_purple_button, cut into
-- tabplate_l/m/r), a gold name, a gold flourish with a diamond under it. Hover: gold name and a purple glow
-- rising from the bottom. The buttons, their places and their clicks stay core.lua's.
local function StyleTabs(UI)
    local MF = UI.MainFrame
    local tabs = {}
    -- THE BAR, on the window itself (under every button), laid out over the shown buttons
    local RAIL_PAD, RAIL_TOP, RAIL_BOTTOM = 10, -45, -87   -- the buttons: y -50 to -82
    local Place = TabRail(MF, 9)
    local function LayoutRail()
        local minX, maxX
        for _, btn in pairs(tabs) do
            if btn:IsShown() and btn:GetNumPoints() > 0 then
                local _, _, _, x = btn:GetPoint(1)
                x = x or 0
                if not minX or x < minX then minX = x end
                if not maxX or x + btn:GetWidth() > maxX then maxX = x + btn:GetWidth() end
            end
        end
        if minX then Place(minX - RAIL_PAD, maxX + RAIL_PAD, RAIL_TOP, RAIL_BOTTOM, MF, "TOPLEFT") end
    end

    local function Refresh()
        for i, btn in pairs(tabs) do
            local on = UI.Panels[i] and UI.Panels[i]:IsShown()
            for _, t in ipairs(btn.fplate) do t:SetShown(on) end
            btn.fflourish:SetShown(on)
            btn.fglow:SetShown(btn.fhovered and not on)
            btn.ftext:SetTextColor(Color((on or btn.fhovered) and TAB_GOLD or TAB_DIM))
            if btn.ficon then btn.ficon:SetAlpha((on or btn.fhovered) and 1 or 0.7) end
        end
        LayoutRail()
    end
    for i, btn in pairs(UI.menuButtons) do
        tabs[i] = btn
        btn.bg:SetAlpha(0)
        btn.line:SetAlpha(0)
        btn.text:SetAlpha(0)
        if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(0, 0, 0, 0) end
        -- the chosen plate, 3 px bigger than the button all round
        btn.fplate = TabPlate(btn, 3)
        -- the gold flourish under the chosen one, on the bar's bottom edge
        btn.fflourish = Tex(btn, "OVERLAY", 3, "tabflourish")
        btn.fflourish:SetSize(math.min(128, btn:GetWidth() + 10), 16)
        btn.fflourish:SetPoint("CENTER", btn, "BOTTOM", 0, -5)
        btn.fglow = TabGlow(btn)
        -- a thin gold divider in the gap before the button (gaps of 5 px; none before the first one)
        if (btn.x or 0) > 20 then TabDivider(btn, 5, 6) end
        -- Gold icons: in place of the classic icon (Help's was a badge frame: hidden, a texture instead)
        if TAB_ICONS[i] and btn.icon then
            local icon = btn.icon
            if not icon.SetTexture then
                icon:Hide()
                local t = btn:CreateTexture(nil, "OVERLAY")
                t:SetSize(16, 16)
                t:SetPoint("RIGHT", btn.text, "LEFT", -5, 0)
                icon = t
            end
            icon:SetTexture(MEDIA .. TAB_ICONS[i])
            icon:SetTexCoord(0, 1, 0, 1)
            icon:SetSize(17, 17)
            icon:SetDrawLayer("OVERLAY", 2)
            btn.ficon = icon
        end
        -- Our label exactly where the classic one is (icon and name stay centered as before)
        btn.ftext = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.ftext:SetPoint("CENTER", btn.text, "CENTER", 0, 0)
        btn.ftext:SetText(btn.text:GetText())
        btn.ftext:SetShadowColor(0, 0, 0, 1) btn.ftext:SetShadowOffset(1, -1)
        btn:HookScript("OnEnter", function(self) self.fhovered = true Refresh() end)
        btn:HookScript("OnLeave", function(self) self.fhovered = nil Refresh() end)
        -- Monitoring shows only for officers, and Release Notes moves into its place: the bar follows
        btn:HookScript("OnShow", LayoutRail)
        btn:HookScript("OnHide", LayoutRail)
        if UI.Panels[i] then
            UI.Panels[i]:HookScript("OnShow", Refresh)
            UI.Panels[i]:HookScript("OnHide", Refresh)
        end
    end
    if UI.EventSync and UI.EventSync.UpdateMonitoringTab then
        _G.hooksecurefunc(UI.EventSync, "UpdateMonitoringTab", LayoutRail)
    end
    Refresh()
end

-- A small plaque behind something on the bottom beam: the panel art (plum, bronze rim) at half size, `out` px
-- around the frame f, under its own textures
local function Plaque(f, out)
    local function P(file, p1, p2)
        local t = f:CreateTexture(nil, "BACKGROUND", nil, -3)
        t:SetTexture(MEDIA .. file)
        t:SetPoint(p1[1], f, p1[2], p1[3], p1[4])
        if p2 then t:SetPoint(p2[1], f, p2[2], p2[3], p2[4]) end
        return t
    end
    local k = 8
    P("panel_tl", { "TOPLEFT", "TOPLEFT", -out, out }):SetSize(k, k)
    P("panel_tr", { "TOPRIGHT", "TOPRIGHT", out, out }):SetSize(k, k)
    P("panel_bl", { "BOTTOMLEFT", "BOTTOMLEFT", -out, -out }):SetSize(k, k)
    P("panel_br", { "BOTTOMRIGHT", "BOTTOMRIGHT", out, -out }):SetSize(k, k)
    P("panel_top", { "TOPLEFT", "TOPLEFT", k - out, out }, { "BOTTOMRIGHT", "TOPRIGHT", out - k, out - k })
    P("panel_bottom", { "TOPLEFT", "BOTTOMLEFT", k - out, k - out }, { "BOTTOMRIGHT", "BOTTOMRIGHT", out - k, -out })
    P("panel_left", { "TOPLEFT", "TOPLEFT", -out, out - k }, { "BOTTOMRIGHT", "BOTTOMLEFT", k - out, k - out })
    P("panel_right", { "TOPLEFT", "TOPRIGHT", out - k, out - k }, { "BOTTOMRIGHT", "BOTTOMRIGHT", out, k - out })
    local fill = f:CreateTexture(nil, "BACKGROUND", nil, -4)
    fill:SetPoint("TOPLEFT", f, "TOPLEFT", 2 - out, out - 2)
    fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", out - 2, 2 - out)
    fill:SetColorTexture(22 / 255, 15 / 255, 28 / 255, 0.92)
end

-- The header's sync bar, Online and CPU/RAM, each centered in a free field of the header row (user's pomysl.png):
-- the sync bar between "Community vX" and the crest, Online + CPU/RAM between the crest and X. The fields run
-- from under the top beam to the tabs (HEAD_Y is their middle). Nothing in sync.lua or core.lua changes: the bar
-- (sync.lua makes it, a StatusBar child of the window) is only moved and restyled, and the header's Online text
-- is hidden and copied to a plaque each time core sets it.
local HEAD_Y = -29     -- the middle of the free fields, from the window's top edge (beam ~ -8, tabs at -50)
local TITLE_Y = -18    -- the middle of "Community vX" (the header bar, -1 to -35)
local CREST_HALF = 150 -- half the crest's plate with its berries
local function StatusInHeader(UI, MF)
    local left = CreateFrame("Frame", nil, MF)
    left:SetPoint("TOPLEFT", UI.TitleText, "RIGHT", 15, HEAD_Y - TITLE_Y + 10)
    left:SetPoint("BOTTOMRIGHT", MF, "TOP", -CREST_HALF, HEAD_Y - 10)
    local right = CreateFrame("Frame", nil, MF)
    right:SetPoint("TOPLEFT", MF, "TOP", CREST_HALF, HEAD_Y + 10)
    right:SetPoint("BOTTOMRIGHT", MF, "TOPRIGHT", -50, HEAD_Y - 10)

    -- SYNC BAR, in the middle of the left field, up to 300 px wide
    local bar
    for _, c in ipairs({ MF:GetChildren() }) do
        if c.GetObjectType and c:GetObjectType() == "StatusBar" and c.text and c.bg then bar = c end
    end
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", left, "CENTER", 0, 0)
        bar:SetSize(math.min(300, math.max(60, left:GetWidth() - 16)), 12)
        left:SetScript("OnSizeChanged", function(self, w) bar:SetWidth(math.min(300, math.max(60, (w or self:GetWidth()) - 16))) end)
        bar:SetFrameLevel(MF:GetFrameLevel() + 5)
        bar.bg:SetColorTexture(0.05, 0.02, 0.07, 0.9)
        Plaque(bar, 4)
        -- The six stages do not fit the shorter bar: "Syncing 3/6 - Rosters" (the first one still waiting)
        bar.text:SetFontObject("GameFontHighlightSmall")
        local busy
        _G.hooksecurefunc(bar.text, "SetText", function(self, s)
            if busy or type(s) ~= "string" or not s:find("Syncing") then return end
            local _, done = s:gsub("ReadyCheck%-Ready", "")
            local _, wait = s:gsub("ReadyCheck%-Waiting", "")
            local now = s:match("ReadyCheck%-Waiting[^|]*|t%s*(%a+)")
            busy = true
            self:SetText(string.format("Syncing  %d/%d%s", done, done + wait, now and ("  -  " .. now) or ""))
            busy = false
        end)
    end

    -- ONLINE + CPU/RAM, on a plaque in the middle of the right field
    local info = CreateFrame("Frame", nil, MF)
    info:SetFrameLevel(MF:GetFrameLevel() + 5)
    info:SetHeight(14)
    info:SetPoint("CENTER", right, "CENTER", 0, 0)
    Plaque(info, 4)
    local dot = info:CreateTexture(nil, "ARTWORK")
    dot:SetTexture("Interface\\COMMON\\Indicator-Green")
    dot:SetSize(12, 12)
    dot:SetPoint("LEFT", info, "LEFT", 4, 0)
    local text = info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", dot, "RIGHT", 3, 0)
    local function Copy(s)
        if type(s) ~= "string" then return end
        local online = s:match("Online:%s*|c%x%x%x%x%x%x%x%x(%d+)") or s:match("Online:%s*(%d+)") or "0"
        local perf = s:match("^|c%x%x%x%x%x%x%x%x(.-)|r")
        if perf and perf:find("Online") then perf = nil end
        text:SetText("|cffd9c48aOnline|r  |cffffffff" .. online .. "|r" .. (perf and perf ~= "" and ("     |cff9a8aa8" .. perf .. "|r") or ""))
        info:SetWidth(text:GetStringWidth() + 26)
    end
    UI.OnlineText:SetAlpha(0)
    _G.hooksecurefunc(UI.OnlineText, "SetText", function(_, s) Copy(s) end)
    Copy(UI.OnlineText:GetText())
end

-- ANNOUNCEMENTS (user: "fajnie dostosować w nowym theme to, co w tabie Announcements"): announcements.lua is not
-- changed; its frames are found (the feed's scroll has a global name, the rest hangs off it) and restyled.
-- A row of tag chips (the feed's filter, the editor's tag choice) as the small tabs: the carved bar, dividers,
-- the chosen one on the purple plate with a gold name; the others keep their tag's color. announcements.lua marks
-- the chosen chip by its background's alpha (0.35 / 0.45, the others 0.08 / 0.1): a hook on that call picks it.
local function StyleChipRow(chips, gap, firstOn)
    if #chips == 0 then return end
    local Place = TabRail(chips[1]:GetParent(), 7)
    local w = 0
    for i, b in ipairs(chips) do w = w + b:GetWidth() + (i < #chips and gap or 0) end
    Place(-8, w + 8, 3, -chips[1]:GetHeight() - 3, chips[1], "TOPLEFT")
    for i, chip in ipairs(chips) do
        if chip.bg and chip.text and not chip.forestChip then
            chip.forestChip = true
            chip.bg:SetAlpha(0)
            chip.fplate = TabPlate(chip, 1)
            chip.fglow = TabGlow(chip)
            if i > 1 then TabDivider(chip, gap, 3) end
            chip.text:SetShadowColor(0, 0, 0, 1) chip.text:SetShadowOffset(1, -1)
            chip.fcolor = { chip.text:GetTextColor() }
            local busy = false
            local function Show()
                local on, hov = chip.fon, chip.fhovered
                for _, t in ipairs(chip.fplate) do t:SetShown(on) end
                chip.fglow:SetShown(hov and not on)
                busy = true
                if on or hov then chip.text:SetTextColor(Color(TAB_GOLD)) else chip.text:SetTextColor(unpack(chip.fcolor)) end
                busy = false
            end
            _G.hooksecurefunc(chip.bg, "SetColorTexture", function(_, _, _, _, a) chip.fon = (a or 0) >= 0.3 Show() end)
            _G.hooksecurefunc(chip.text, "SetTextColor", function(_, r, g, b)
                if busy then return end
                -- the tag's own color (the chosen one's white is not kept)
                if not ((r or 0) >= 0.99 and (g or 0) >= 0.99 and (b or 0) >= 0.99) then chip.fcolor = { r, g, b } end
                Show()
            end)
            chip:HookScript("OnEnter", function() chip.fhovered = true Show() end)
            chip:HookScript("OnLeave", function() chip.fhovered = nil Show() end)
            chip.fon = firstOn and i == 1 or false
            Show()
        end
    end
end

-- A card (one post): the panel art instead of its flat box (announcements.lua colors the box on every refresh,
-- so this runs after each one), the tag's color bar inside the rim, a gold title, a fading gold line under the
-- author line, warm text; a pinned post gets a soft gold glow along its top and a gold diamond on its top edge
local function StyleCard(card)
    StylePanel(card)
    if not card.forestCard then
        card.forestCard = true
        card.accent:ClearAllPoints()
        card.accent:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -10)
        card.accent:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 6, 10)
        card.title:SetTextColor(Color(TAB_GOLD))
        card.title:SetShadowColor(0, 0, 0, 1) card.title:SetShadowOffset(1, -1)
        card.meta:SetTextColor(Color(TAB_DIM))
        Gradient(card.line, "HORIZONTAL", C.gold, 0.5, C.gold, 0)
        card.body:SetTextColor(0.91, 0.88, 0.84)
        card.pinGlow = card:CreateTexture(nil, "BACKGROUND", nil, 3)
        card.pinGlow:SetPoint("TOPLEFT", card, "TOPLEFT", 4, -3)
        card.pinGlow:SetPoint("TOPRIGHT", card, "TOPRIGHT", -4, -3)
        card.pinGlow:SetHeight(26)
        Gradient(card.pinGlow, "VERTICAL", C.gold, 0, C.gold, 0.16)
        card.pinGem = card:CreateTexture(nil, "OVERLAY", nil, 5)
        card.pinGem:SetColorTexture(Color(C.gold))
        card.pinGem:SetSize(9, 9)
        card.pinGem:SetPoint("CENTER", card, "TOP", 0, -1)
        card.pinHeart = card:CreateTexture(nil, "OVERLAY", nil, 6)
        card.pinHeart:SetColorTexture(Color(C.purple))
        card.pinHeart:SetSize(4, 4)
        card.pinHeart:SetPoint("CENTER", card.pinGem, "CENTER", 0, 0)
        if card.pinGem.SetRotation then card.pinGem:SetRotation(math.rad(45)) card.pinHeart:SetRotation(math.rad(45)) end
    end
    local pinned = card.post and card.post.pin and true or false
    card.pinGlow:SetShown(pinned)
    card.pinGem:SetShown(pinned)
    card.pinHeart:SetShown(pinned)
end

local function StyleAnnouncements()
    local A = addonTable.Announcements
    local scroll = _G.JagodkaAnnouncementsScroll
    if not (A and A.Refresh and scroll) then return end
    local box = scroll:GetParent()
    local panel = box and box:GetParent()
    if not panel then return end
    -- the header: gold title, lavender subtitle
    for _, r in ipairs({ panel:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "FontString" then
            local s = r:GetText()
            if s == "Announcements" then
                r:SetFontObject("GameFontNormalLarge")
                r:SetTextColor(Color(TAB_GOLD))
                r:SetShadowColor(0, 0, 0, 1) r:SetShadowOffset(1, -1)
            elseif s and s:find("^announcements from") then
                r:SetTextColor(Color(TAB_DIM))
            end
        end
    end
    -- the filter chips (All first, chosen at the start) and the editor (over the feed: .head and .tags)
    local chips, editor = {}, nil
    for _, ch in ipairs({ panel:GetChildren() }) do
        if ch.bg and ch.text and ch.r and ch.g and ch.b and ch.GetObjectType and ch:GetObjectType() == "Button" then
            table.insert(chips, ch)
        elseif ch.head and ch.tags then
            editor = ch
        end
    end
    table.sort(chips, function(a, b) return (select(4, a:GetPoint(1)) or 0) < (select(4, b:GetPoint(1)) or 0) end)
    StyleChipRow(chips, 4, true)
    if editor then
        StylePanel(editor)
        -- the editor covers the feed: a solid layer under its (slightly see-through) panel art
        local solid = editor:CreateTexture(nil, "BACKGROUND", nil, 1)
        solid:SetPoint("TOPLEFT", editor, "TOPLEFT", 4, -4)
        solid:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -4, 4)
        solid:SetColorTexture(0.06, 0.04, 0.08, 1)
        editor.head:SetTextColor(Color(TAB_GOLD))
        editor.head:SetShadowColor(0, 0, 0, 1) editor.head:SetShadowOffset(1, -1)
        StyleChipRow(editor.tags, 6, false)
        -- the text box inside: the panel art too
        for _, ch in ipairs({ editor:GetChildren() }) do
            if ch.SetBackdropColor and ch:GetObjectType() == "Frame" and not ch.tags then StylePanel(ch) end
        end
    end
    -- the cards, after every refresh (new ones are made as needed)
    local function Cards()
        local content = scroll:GetScrollChild()
        if not content then return end
        for _, card in ipairs({ content:GetChildren() }) do
            if card.accent and card.title and card.body then StyleCard(card) end
        end
    end
    _G.hooksecurefunc(A, "Refresh", Cards)
    Cards()
end

-- BUTTONS (user: "buttony dostosuj do wszystkich w theme 2, jak zrobiłeś dla X"): every game panel button in the
-- window (UIPanelButtonTemplate / GameMenuButtonTemplate: Send, Armory, Sync, + New announcement, Officer
-- actions, the page buttons...) in the X's style: a gold rim with a dark outline, a plum middle with a soft shine
-- (Media\forest\button_l/m/r, 12 + stretch + 12 on 32 px); hover: lighter rim and middle (button_hover_*);
-- pressed: a little darker; disabled: gray and faded. The template's own red parts (Left, Middle, Right) and its
-- highlight are only hidden; its clicks and texts stay.
local function StyleButton(b)
    if b.forestBtn or not (b.Left and b.Middle and b.Right) then return end
    b.forestBtn = true
    b.Left:SetAlpha(0) b.Middle:SetAlpha(0) b.Right:SetAlpha(0)
    local hl = b.GetHighlightTexture and b:GetHighlightTexture()
    if hl then hl:SetAlpha(0) end
    local h = b:GetHeight()
    if not h or h < 8 then h = 22 end
    local cap = math.max(6, math.floor(h * 12 / 32 + 0.5))
    local function Set(prefix)
        local l = Tex(b, "BACKGROUND", 3, prefix .. "_l", 0, 12 / 16, 0, 1)
        l:SetPoint("TOPLEFT") l:SetPoint("BOTTOMLEFT") l:SetWidth(cap)
        local r = Tex(b, "BACKGROUND", 3, prefix .. "_r", 0, 12 / 16, 0, 1)
        r:SetPoint("TOPRIGHT") r:SetPoint("BOTTOMRIGHT") r:SetWidth(cap)
        local m = Tex(b, "BACKGROUND", 3, prefix .. "_m")
        m:SetPoint("TOPLEFT", l, "TOPRIGHT") m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
        return { l, m, r }
    end
    local normal, hover = Set("button"), Set("button_hover")
    local function Paint()
        local enabled = not b.IsEnabled or b:IsEnabled()
        local over = enabled and b.forestOver
        local k = (enabled and b.forestDown) and 0.72 or 1
        for _, t in ipairs(normal) do
            t:SetShown(not over)
            t:SetDesaturated(not enabled)
            t:SetVertexColor(k, k, k, enabled and 1 or 0.55)
        end
        for _, t in ipairs(hover) do
            t:SetShown(over and true or false)
            t:SetVertexColor(k, k, k, 1)
        end
    end
    b:HookScript("OnEnter", function() b.forestOver = true Paint() end)
    b:HookScript("OnLeave", function() b.forestOver = nil b.forestDown = nil Paint() end)
    b:HookScript("OnMouseDown", function() b.forestDown = true Paint() end)
    b:HookScript("OnMouseUp", function() b.forestDown = nil Paint() end)
    b:HookScript("OnDisable", Paint)
    b:HookScript("OnEnable", Paint)
    -- the template puts its red parts back on some state changes in some clients: keep them hidden
    _G.hooksecurefunc(b.Left, "SetAlpha", function(t, a) if a ~= 0 then t:SetAlpha(0) end end)
    _G.hooksecurefunc(b.Middle, "SetAlpha", function(t, a) if a ~= 0 then t:SetAlpha(0) end end)
    _G.hooksecurefunc(b.Right, "SetAlpha", function(t, a) if a ~= 0 then t:SetAlpha(0) end end)
    Paint()
end
-- DROPDOWNS (user: "a dla dropdown nie dałoby rady? tych wszystkich w filtrach itd"): every dropdown of the
-- addon (UIDropDownMenuTemplate; all named "Jagodk..."): its box in the buttons' style (the template's own parts
-- Left / Middle / Right only hidden; the visible box of the template is ~16 px in from its sides, 2-28 px from its
-- top), lighter while the arrow is under the mouse. The text, the arrow and what it does stay.
local function IsOurs(f)
    local n = f and f.GetName and f:GetName()
    return n and n:find("^Jagodk") and true or false
end
local function StyleDropDown(dd)
    if dd.forestDD or not IsOurs(dd) then return end
    local n = dd:GetName()
    local l, m, r = dd.Left or _G[n .. "Left"], dd.Middle or _G[n .. "Middle"], dd.Right or _G[n .. "Right"]
    local arrow = dd.Button or _G[n .. "Button"]
    if not (l and m and r) then return end
    dd.forestDD = true
    l:SetAlpha(0) m:SetAlpha(0) r:SetAlpha(0)
    local cap = 10
    local function Set(prefix)
        local a = Tex(dd, "BACKGROUND", 3, prefix .. "_l", 0, 12 / 16, 0, 1)
        a:SetPoint("TOPLEFT", dd, "TOPLEFT", 16, -2) a:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, -28) a:SetWidth(cap)
        local c = Tex(dd, "BACKGROUND", 3, prefix .. "_r", 0, 12 / 16, 0, 1)
        c:SetPoint("TOPRIGHT", dd, "TOPRIGHT", -16, -2) c:SetPoint("BOTTOMRIGHT", dd, "TOPRIGHT", -16, -28) c:SetWidth(cap)
        local b = Tex(dd, "BACKGROUND", 3, prefix .. "_m")
        b:SetPoint("TOPLEFT", a, "TOPRIGHT") b:SetPoint("BOTTOMRIGHT", c, "BOTTOMLEFT")
        return { a, b, c }
    end
    local normal, hover = Set("button"), Set("button_hover")
    -- The arrow (user's dropdown.png: the game's yellow square sat on the rim, off-center): the same button, so
    -- the same place to click, now centered in the box's right end (box middle 15 px down), its game look hidden;
    -- a gold chevron in it (Media\forest\arrow_down, light on hover, 1 px lower while pressed, gray when off) and
    -- a thin gold divider between the text and it
    local chevron, divider
    if arrow then
        arrow:ClearAllPoints()
        arrow:SetPoint("CENTER", dd, "TOPRIGHT", -16 - 13, -15)
        arrow:SetSize(22, 22)
        for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
            local t = arrow[get] and arrow[get](arrow)
            if t then t:SetAlpha(0) end
        end
        chevron = arrow:CreateTexture(nil, "OVERLAY", nil, 2)
        chevron:SetSize(14, 14)
        chevron:SetPoint("CENTER", arrow, "CENTER", 0, -1)
        -- the label (user's dropdown-teksty.png: it sat ~3 px above the arrow): its middle level with the
        -- chevron's, right before the divider; the template keeps its width and right alignment. The game may
        -- place it again (UIDropDownMenu_JustifyText): put back after that (HookDropDownLists).
        local label = dd.Text or _G[n .. "Text"]
        if label then
            dd.forestPlaceText = function()
                label:ClearAllPoints()
                label:SetPoint("RIGHT", arrow, "LEFT", -6, -1)
            end
            dd.forestPlaceText()
        end
        divider = dd:CreateTexture(nil, "ARTWORK", nil, 2)
        divider:SetWidth(1)
        divider:SetPoint("TOP", arrow, "TOPLEFT", -1, -4)
        divider:SetPoint("BOTTOM", arrow, "BOTTOMLEFT", -1, 4)
        Gradient(divider, "VERTICAL", C.gold, 0.15, C.gold, 0.6)
    end
    local over, down = false, false
    local function Paint()
        for _, t in ipairs(normal) do t:SetShown(not over) end
        for _, t in ipairs(hover) do t:SetShown(over) end
        if chevron then
            local enabled = not arrow.IsEnabled or arrow:IsEnabled()
            chevron:SetTexture(MEDIA .. ((over and enabled) and "arrow_down_hover" or "arrow_down"))
            chevron:SetDesaturated(not enabled)
            chevron:SetAlpha(enabled and 1 or 0.5)
            chevron:SetPoint("CENTER", arrow, "CENTER", 0, down and -2 or -1)
        end
    end
    if arrow then
        arrow:HookScript("OnEnter", function() over = true Paint() end)
        arrow:HookScript("OnLeave", function() over, down = false, false Paint() end)
        arrow:HookScript("OnMouseDown", function() down = true Paint() end)
        arrow:HookScript("OnMouseUp", function() down = false Paint() end)
        arrow:HookScript("OnDisable", Paint)
        arrow:HookScript("OnEnable", Paint)
    end
    Paint()
end
-- The open list (the game's DropDownList1, 2...: shared with the whole UI and other addons): the panel art only
-- while one of OUR dropdowns or menus has it open; anyone else's opens it in the game's look, and it goes back to
-- that look when it closes. Its own backdrops are only made invisible meanwhile.
local function SkinList(list, on)
    if not list then return end
    local n = list:GetName() or ""
    for _, b in ipairs({ list.Backdrop or _G[n .. "Backdrop"], list.MenuBackdrop or _G[n .. "MenuBackdrop"] }) do
        if b and b.SetAlpha then b:SetAlpha(on and 0 or 1) end
    end
    if on and not list.forestSkin then
        local parts = {}
        local function P(file, p1, p2)
            local t = list:CreateTexture(nil, "BACKGROUND", nil, 2)
            t:SetTexture(MEDIA .. file)
            t:SetPoint(p1[1], list, p1[2], p1[3], p1[4])
            if p2 then t:SetPoint(p2[1], list, p2[2], p2[3], p2[4]) end
            table.insert(parts, t)
            return t
        end
        P("panel_tl", { "TOPLEFT", "TOPLEFT", 0, 0 }):SetSize(16, 16)
        P("panel_tr", { "TOPRIGHT", "TOPRIGHT", 0, 0 }):SetSize(16, 16)
        P("panel_bl", { "BOTTOMLEFT", "BOTTOMLEFT", 0, 0 }):SetSize(16, 16)
        P("panel_br", { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 }):SetSize(16, 16)
        P("panel_top", { "TOPLEFT", "TOPLEFT", 16, 0 }, { "TOPRIGHT", "TOPRIGHT", -16, 0 }):SetHeight(16)
        P("panel_bottom", { "BOTTOMLEFT", "BOTTOMLEFT", 16, 0 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", -16, 0 }):SetHeight(16)
        P("panel_left", { "TOPLEFT", "TOPLEFT", 0, -16 }, { "BOTTOMLEFT", "BOTTOMLEFT", 0, 16 }):SetWidth(16)
        P("panel_right", { "TOPRIGHT", "TOPRIGHT", 0, -16 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 16 }):SetWidth(16)
        local fill = list:CreateTexture(nil, "BACKGROUND", nil, 1)
        fill:SetPoint("TOPLEFT", list, "TOPLEFT", 3, -3)
        fill:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -3, 3)
        fill:SetColorTexture(0.06, 0.04, 0.08, 0.97)
        table.insert(parts, fill)
        list.forestSkin = parts
    end
    for _, t in ipairs(list.forestSkin or {}) do t:SetShown(on) end
end
local function HookDropDownLists()
    if _G.UIDropDownMenu_JustifyText then
        _G.hooksecurefunc("UIDropDownMenu_JustifyText", function(frame)
            if frame and frame.forestPlaceText then frame.forestPlaceText() end
        end)
    end
    if not _G.ToggleDropDownMenu then return end
    _G.hooksecurefunc("ToggleDropDownMenu", function(level, _, dropDownFrame)
        local list = _G["DropDownList" .. (level or 1)]
        if list and list:IsShown() then
            SkinList(list, IsOurs(dropDownFrame or _G.UIDROPDOWNMENU_OPEN_MENU))
        end
    end)
    for i = 1, (_G.UIDROPDOWNMENU_MAXLEVELS or 3) do
        local list = _G["DropDownList" .. i]
        if list then list:HookScript("OnHide", function(self) SkinList(self, false) end) end
    end
end

-- X BUTTONS (user: "sprawdź też resztę X przy zamykaniu okienek, żeby były takie same jak główny, i padding top
-- i right z 3 px"): the round gold medallion of the main X (close_normal / close_hover, pressed darker). The
-- others are the game's close buttons, found by the game's close look (CLOSE_SIG, remembered from the main X
-- before it changed); one in its window's top right corner moves 3 px in from both edges.
local CLOSE_SIG = nil
local function StyleClose(b)
    if b.forestClose then return end
    b.forestClose = true
    b:SetNormalTexture(MEDIA .. "close_normal")
    b:SetPushedTexture(MEDIA .. "close_normal")
    b:SetHighlightTexture(MEDIA .. "close_hover")
    for _, t in ipairs({ b:GetNormalTexture(), b:GetPushedTexture(), b:GetHighlightTexture() }) do
        if t then t:SetTexCoord(0, 1, 0, 1) t:ClearAllPoints() t:SetAllPoints(b) end
    end
    if b:GetPushedTexture() then b:GetPushedTexture():SetVertexColor(0.7, 0.7, 0.7) end
    if b:GetHighlightTexture() then b:GetHighlightTexture():SetBlendMode("BLEND") end
    if b.GetDisabledTexture and b:GetDisabledTexture() then b:GetDisabledTexture():SetAlpha(0) end
end
local function IsClose(b)
    if b.forestClose or not CLOSE_SIG or b.Left then return false end
    local t = b.GetNormalTexture and b:GetNormalTexture()
    if not t then return false end
    if CLOSE_SIG.atlas and t.GetAtlas and t:GetAtlas() == CLOSE_SIG.atlas then return true end
    return CLOSE_SIG.tex ~= nil and t:GetTexture() == CLOSE_SIG.tex
end
local function StyleOtherClose(b)
    StyleClose(b)
    if b:GetNumPoints() == 1 then
        local point, rel, relPoint = b:GetPoint(1)
        if point == "TOPRIGHT" and relPoint == "TOPRIGHT" and rel == b:GetParent() then
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", rel, "TOPRIGHT", -3, -3)
        end
    end
end

-- UNREAD BADGES (user: "kółko z ilością wiadomości bardziej pod theme, nie takie zielone"): core.lua's green
-- circle on the chat tabs, the Community Chat and the Announcements tab becomes a berry: a gold ring with a dark
-- outline, a blueberry purple middle with a small shine (Media\forest\badge), 2 px bigger, a warm white number.
-- core.lua hands each new badge here (addonTable.ThemeBadge); its place and number stay core.lua's.
local function StyleBadge(b)
    if not b or b.forestBadge or not b.bg then return end
    b.forestBadge = true
    b:SetSize(18, 18)
    b.bg:SetTexture(MEDIA .. "badge")
    b.bg:SetTexCoord(0, 1, 0, 1)
    b.bg:SetVertexColor(1, 1, 1, 1)
    if b.text then
        b.text:SetTextColor(1, 0.95, 0.82)
        b.text:SetShadowColor(0, 0, 0, 1) b.text:SetShadowOffset(1, -1)
    end
end

-- INPUTS (user: "z inputami coś, żeby bardziej odpowiadały theme"): every game text box (InputBoxTemplate: the
-- chat input, the searches, the announcement title, Discord / BattleTag...) becomes a recessed field: a dark plum
-- middle, darker at the top, in a thin bronze rim (Media\forest\input_l/m/r); while typing in it the rim turns
-- gold with a soft purple glow (input_focus_*). The template's own border parts (Left, Middle, Right; it draws
-- them from 5 px left of the box to its right edge) are only hidden; the text and what it does stay.
local function StyleInput(e)
    if e.forestInput then return end
    local n = e:GetName()
    local l, m, r = e.Left or (n and _G[n .. "Left"]), e.Middle or (n and _G[n .. "Middle"]), e.Right or (n and _G[n .. "Right"])
    if not (l and m and r) then return end
    e.forestInput = true
    l:SetAlpha(0) m:SetAlpha(0) r:SetAlpha(0)
    local h = e:GetHeight()
    if not h or h < 8 then h = 20 end
    local cap = math.max(6, math.floor(h * 12 / 32 + 0.5))
    local function Set(prefix)
        local a = Tex(e, "BACKGROUND", 3, prefix .. "_l", 0, 12 / 16, 0, 1)
        a:SetPoint("TOPLEFT", e, "TOPLEFT", -6, 0) a:SetPoint("BOTTOMLEFT", e, "BOTTOMLEFT", -6, 0) a:SetWidth(cap)
        local c = Tex(e, "BACKGROUND", 3, prefix .. "_r", 0, 12 / 16, 0, 1)
        c:SetPoint("TOPRIGHT", e, "TOPRIGHT", 1, 0) c:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", 1, 0) c:SetWidth(cap)
        local b = Tex(e, "BACKGROUND", 3, prefix .. "_m")
        b:SetPoint("TOPLEFT", a, "TOPRIGHT") b:SetPoint("BOTTOMRIGHT", c, "BOTTOMLEFT")
        return { a, b, c }
    end
    local normal, focus = Set("input"), Set("input_focus")
    local function Paint()
        local on = e:HasFocus()
        for _, t in ipairs(normal) do t:SetShown(not on) end
        for _, t in ipairs(focus) do t:SetShown(on) end
    end
    e:HookScript("OnEditFocusGained", Paint)
    e:HookScript("OnEditFocusLost", Paint)
    Paint()
end

-- All the buttons in a frame and below it (made so far; StyleAllButtons runs again when a tab opens, for the
-- ones made later)
local function StyleAllButtons(f)
    for _, c in ipairs({ f:GetChildren() }) do
        local kind = c.GetObjectType and c:GetObjectType()
        if kind == "Button" then
            if IsClose(c) then StyleOtherClose(c) else StyleButton(c) end
        elseif kind == "EditBox" then StyleInput(c)
        elseif kind == "Frame" and IsOurs(c) then StyleDropDown(c) end
        StyleAllButtons(c)
    end
end

local function ApplyForest(UI)
    local MF = UI.MainFrame

    -- WINDOW: the painted dark plum interior
    MF:SetBackdrop({ bgFile = MEDIA .. "interior" })
    MF:SetBackdropColor(1, 1, 1, 1)
    Gradient(UI.HeaderBar, "VERTICAL", { 0.02, 0.01, 0.03 }, 0.55, C.purpleDeep, 0.25)

    -- FRAME: one painting of the whole frame (2000 x 1550, transparent inside; its inner edge at x 83-1916,
    -- y 230-1441) cut into 14 pieces shown at 0.55 (tools\png2tga.ps1 -Crop). The window sits in the frame's
    -- opening (source 80,226 - 1920,1445), so the frame is outside the window and only the title plate dips
    -- into the header. The ornamented pieces keep their size; the plain vine pieces between them stretch with
    -- the window. Each: file, its art's size on its power-of-two canvas.
    local function Piece(file, w, h, cw, ch)
        local t = Tex(MF, "BORDER", 2, file, 0, w / cw, 0, h / ch)
        t:SetSize(w, h)
        return t
    end
    local tl = Piece("fr_tl", 176, 198, 256, 256)
    tl:SetPoint("TOPLEFT", MF, "TOPLEFT", -44, 124)
    local tr = Piece("fr_tr", 176, 220, 256, 256)
    tr:SetPoint("TOPRIGHT", MF, "TOPRIGHT", 44, 124)
    local crest = Piece("fr_crest", 330, 170, 512, 256)
    crest:SetPoint("TOP", MF, "TOP", 0, 124)
    crest:SetDrawLayer("BORDER", 4)
    local bl = Piece("fr_bl", 242, 193, 256, 256)
    bl:SetPoint("BOTTOMLEFT", MF, "BOTTOMLEFT", -44, -58)
    local br = Piece("fr_br", 242, 193, 256, 256)
    br:SetPoint("BOTTOMRIGHT", MF, "BOTTOMRIGHT", 44, -58)
    local bmid = Piece("fr_bottom_mid", 154, 116, 256, 128)
    bmid:SetPoint("BOTTOM", MF, "BOTTOM", 0, -58)
    bmid:SetDrawLayer("BORDER", 4)
    -- The bottom berries over the inner panels (user: "żeby jagódki z ramki nachodziły na wewnętrzną ramkę"):
    -- the three bottom ornaments go to a frame above the panels. It takes no mouse, so clicks pass through.
    -- The top ones stay under (the X button and the guild name sit there).
    local over = CreateFrame("Frame", nil, MF)
    over.forestArt = true   -- the frame's art: /jagodka check does not count it (layoutcheck.lua)
    over:SetAllPoints(MF)
    over:SetFrameLevel(MF:GetFrameLevel() + 30)
    over:EnableMouse(false)
    for _, t in ipairs({ bl, br, bmid }) do t:SetParent(over) end
    -- the resize grip (core.lua: a 16 x 16 button in the bottom right corner) stays above the berries
    for _, c in ipairs({ MF:GetChildren() }) do
        if c.GetObjectType and c:GetObjectType() == "Button" and c:GetNumPoints() == 1 then
            local point, rel = c:GetPoint(1)
            local w, h = c:GetSize()
            if point == "BOTTOMRIGHT" and rel == MF and math.floor(w + 0.5) == 16 and math.floor(h + 0.5) == 16 then
                c:SetFrameLevel(over:GetFrameLevel() + 1)
            end
        end
    end
    -- Exceptions, so the berries cover nothing you use (user: "input w chatach niech wyjątkowo będzie widoczny
    -- nad"): the chat input boxes (edit boxes anchored at their panel's bottom) go above the berries, and the
    -- "Showing 51-100 of 312" text of the Roster's and Events' page bars moves right, past the corner berries.
    local function Walk(f)
        for _, c in ipairs({ f:GetChildren() }) do
            local kind = c.GetObjectType and c:GetObjectType()
            if kind == "EditBox" and c:GetNumPoints() > 0 and tostring((c:GetPoint(1))):find("^BOTTOM") then
                c:SetFrameLevel(over:GetFrameLevel() + 2)
            elseif c.buttons and ((c.infoText and c.pageText) or (c.info and c.page)) then
                -- core.lua's bars (Roster, Events): infoText / pageText; lfg.lua's (LFG): info / page
                local info = c.infoText or c.info
                if info.SetPoint then
                    info:ClearAllPoints()
                    info:SetPoint("LEFT", c, "LEFT", 70, 0)
                end
            end
            Walk(c)
        end
    end
    Walk(MF)
    local bannerL = Piece("fr_left_banner", 61, 143, 64, 256)
    bannerL:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
    local bannerR = Piece("fr_right_banner", 66, 121, 128, 128)
    bannerR:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT")

    -- RUNS: the plain vine pieces between the ornaments are repeated, not stretched: as many copies as fit at
    -- about their own size, each a little wider or narrower to fill the gap. So the frame looks painted at any
    -- window size (one piece stretched 2.5 times looked smeared in a big window). The rail runs at the same
    -- height in every copy, so copies join cleanly. A run: its piece, and where it lies for a window W x H
    -- (start, length along it; its fixed side), worked out from the fixed pieces above.
    local runs = {
        { file = "fr_top_a", w = 209, h = 143, cw = 256, ch = 256, edge = "top",
          span = function(W) return 132, W / 2 - 165 - 132 end },          -- from the top left corner to the crest
        { file = "fr_top_b", w = 209, h = 143, cw = 256, ch = 256, edge = "top",
          span = function(W) return W / 2 + 165, W - 132 - (W / 2 + 165) end },
        { file = "fr_bottom_a", w = 231, h = 82, cw = 256, ch = 128, edge = "bottom",
          span = function(W) return 198, W / 2 - 77 - 198 end },           -- from the bottom left corner to the middle
        { file = "fr_bottom_b", w = 231, h = 82, cw = 256, ch = 128, edge = "bottom",
          span = function(W) return W / 2 + 77, W - 198 - (W / 2 + 77) end },
        { file = "fr_left", w = 61, h = 319, cw = 64, ch = 512, edge = "left",
          span = function(_, H) return 217, H - 217 - 135 end },           -- under the banner to the bottom left corner
        { file = "fr_right", w = 66, h = 319, cw = 128, ch = 512, edge = "right",
          span = function(_, H) return 217, H - 217 - 135 end },
    }
    local function LayoutRuns()
        local W, H = MF:GetWidth(), MF:GetHeight()
        if not W or W <= 0 then return end
        for _, run in ipairs(runs) do
            local start, len = run.span(W, H)
            local vertical = run.edge == "left" or run.edge == "right"
            local natural = vertical and run.h or run.w
            local count = math.max(1, math.floor(len / natural + 0.5))
            local each = len / count
            run.pool = run.pool or {}
            for i = 1, math.max(count, #run.pool) do
                local t = run.pool[i]
                if i <= count then
                    if not t then
                        t = Tex(MF, "BORDER", 1, run.file, 0, run.w / run.cw, 0, run.h / run.ch)
                        run.pool[i] = t
                    end
                    t:ClearAllPoints()
                    local at = start + (i - 1) * each
                    if run.edge == "top" then t:SetSize(each, run.h) t:SetPoint("TOPLEFT", MF, "TOPLEFT", at, 124)
                    elseif run.edge == "bottom" then t:SetSize(each, run.h) t:SetPoint("BOTTOMLEFT", MF, "BOTTOMLEFT", at, -58)
                    elseif run.edge == "left" then t:SetSize(run.w, each) t:SetPoint("TOPLEFT", MF, "TOPLEFT", -44, -at)
                    else t:SetSize(run.w, each) t:SetPoint("TOPRIGHT", MF, "TOPRIGHT", 44, -at) end
                    t:Show()
                elseif t then
                    t:Hide()
                end
            end
        end
    end
    MF:HookScript("OnSizeChanged", LayoutRuns)
    LayoutRuns()
    -- Off the screen's edges: core.lua (MainFrame.KeepOnScreen) lets the window go off left, right and down in
    -- both looks, and up only to its own top edge, so here the crest above it simply goes off the top too
    -- (user: "ten kawałek z wilkiem można w górę przesuwać, żeby się chował"). Nothing to set.
    -- The whole top of the frame (the corners, the vines, the wolf and the plate, above the window) drags the
    -- window like the title bar does (user: "żeby okienko było przeciągalne na całym tym obszarze")
    local grab = CreateFrame("Frame", nil, MF)
    grab.forestArt = true   -- the drag area over the frame's top art, outside the window by design
    grab:SetPoint("TOPLEFT", MF, "TOPLEFT", -44, 124)
    grab:SetPoint("BOTTOMRIGHT", MF, "TOPRIGHT", 44, 0)
    grab:SetFrameLevel(MF:GetFrameLevel() + 1)
    grab:EnableMouse(true)
    grab:RegisterForDrag("LeftButton")
    grab:SetScript("OnDragStart", function() MF:SetAlpha(0.5) MF:StartMoving() end)
    grab:SetScript("OnDragStop", function() MF:StopMovingOrSizing() MF:SetAlpha(1) if MF.SaveLayout then MF.SaveLayout() end end)

    -- The name of the player's guild on the crest's plate (its middle 9 px above the window's top edge), engraved
    -- gold: a pale copy 1 px up gives the lit edge, the gold text on top, a deep brown shadow below; a small gold
    -- diamond and a short fading line on each side. Long names get a smaller font so they stay on the plate.
    -- the text's room on the plate: the berries are ~105 px from the middle and the diamond + line take 32 px past
    -- the text on each side ("Jagódki Nadina" at 16 is ~113 px; longer names like "... Nadina 2" or "... III" shrink)
    local TEXT_MAX = 125
    local lit = MF:CreateFontString(nil, "OVERLAY", nil, 1)
    local title = MF:CreateFontString(nil, "OVERLAY", nil, 2)
    lit:SetPoint("CENTER", MF, "TOP", 0, 10)
    title:SetPoint("CENTER", MF, "TOP", 0, 9)
    lit:SetTextColor(1, 0.96, 0.78, 0.9)
    title:SetTextColor(Color(C.gold))
    title:SetShadowColor(0.12, 0.05, 0.02, 1) title:SetShadowOffset(1, -2)
    local ornaments = {}
    for _, side in ipairs({ -1, 1 }) do
        local gem = MF:CreateTexture(nil, "OVERLAY", nil, 2)
        gem:SetColorTexture(Color(C.gold))
        gem:SetSize(5, 5)
        if gem.SetRotation then gem:SetRotation(math.rad(45)) end
        local line = MF:CreateTexture(nil, "OVERLAY", nil, 1)
        line:SetColorTexture(1, 1, 1, 1)
        line:SetSize(18, 1)
        local a, b = { C.gold[1], C.gold[2], C.gold[3], 0.9 }, { C.gold[1], C.gold[2], C.gold[3], 0 }
        if side > 0 then a, b = b, a end
        if line.SetGradient and _G.CreateColor then
            line:SetGradient("HORIZONTAL", _G.CreateColor(b[1], b[2], b[3], b[4]), _G.CreateColor(a[1], a[2], a[3], a[4]))
        else
            line:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 0.6)
        end
        ornaments[side] = { gem = gem, line = line }
    end
    local function ShowGuildName()
        local name = _G.IsInGuild and _G.IsInGuild() and _G.GetGuildInfo and _G.GetGuildInfo("player") or nil
        if not name or name == "" then name = "Jagódki" end
        if name == title.shown then return end
        title.shown = name
        -- The game's UI font has no Polish letters except ó: other non-ASCII names use the chat font
        local font = TITLE_FONT
        if name:gsub("\195\179", ""):gsub("\195\147", ""):find("[\128-\255]") then
            font = (_G.ChatFontNormal and _G.ChatFontNormal:GetFont()) or TITLE_FONT
        end
        local size = 16
        repeat
            title:SetFont(font, size, "OUTLINE") lit:SetFont(font, size, "OUTLINE")
            title:SetText(name) lit:SetText(name)
            size = size - 1
        until size < 10 or title:GetStringWidth() <= TEXT_MAX
        local half = title:GetStringWidth() / 2
        for side, o in pairs(ornaments) do
            o.gem:ClearAllPoints() o.gem:SetPoint("CENTER", MF, "TOP", side * (half + 9), 9)
            o.line:ClearAllPoints() o.line:SetPoint("CENTER", MF, "TOP", side * (half + 23), 9)
        end
    end
    if not pcall(ShowGuildName) then title:SetFontObject("GameFontNormalLarge") title:SetText("Jagódki") end
    -- The guild info arrives a moment after login and changes on join/leave
    local guildWatch = CreateFrame("Frame")
    guildWatch:RegisterEvent("PLAYER_GUILD_UPDATE")
    guildWatch:RegisterEvent("GUILD_ROSTER_UPDATE")
    guildWatch:SetScript("OnEvent", function() pcall(ShowGuildName) end)

    -- X (user: "ten X od zamykania 10 px wyżej, dostosujmy do wyglądu, ale żeby był widoczny"): a round gold
    -- medallion with a plum middle and a gold X (Media\forest\close_normal), on hover a red-purple glow and a
    -- light X (close_hover), pressed: a little darker. 10 px higher, above the drag area over the frame's top.
    local X = UI.CloseBtn
    -- the game's close button look, remembered before it changes: the other X buttons are found by it
    local nt = X:GetNormalTexture()
    if nt then CLOSE_SIG = { tex = nt:GetTexture(), atlas = nt.GetAtlas and nt:GetAtlas() or nil } end
    X:ClearAllPoints()
    X:SetPoint("TOPRIGHT", MF, "TOPRIGHT", -2, 8)
    X:SetSize(30, 30)
    X:SetFrameLevel(MF:GetFrameLevel() + 10)
    StyleClose(X)
    X.forestArt = true   -- 8 px above the window by design: /jagodka check does not count it

    -- Left of the header: the berry medallion and "Community · vX" (the classic title, smaller)
    UI.WindowLogo:SetTexture(MEDIA .. "medallion.tga")
    UI.WindowLogo:SetTexCoord(0, 1, 0, 1)
    UI.WindowLogo:SetSize(28, 28)
    UI.WindowLogo:ClearAllPoints()
    UI.WindowLogo:SetPoint("LEFT", UI.HeaderBar, "LEFT", 16, 0)
    UI.TitleText:SetFontObject("GameFontHighlightSmall")
    local meta = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    UI.TitleText:SetText("|cffa89bb5Community|r  |cff7d6f8av" .. ((meta and meta(addonName, "Version")) or "") .. "|r")

    -- TABS: the same buttons in the same row, new look
    StyleTabs(UI)
    -- the small tabs: the right column's Signed / Other / LFG and the chat's channels
    local side = UI.EventSync and UI.EventSync.Side
    StyleSubTabRow(side and side.tabs or {})
    -- the chat's buttons are kept by name: left to right by their place (customXOffset)
    local chatRow = {}
    for _, t in pairs(UI.chatTabButtons or {}) do table.insert(chatRow, t) end
    table.sort(chatRow, function(a, b) return (a.customXOffset or 0) < (b.customXOffset or 0) end)
    StyleSubTabRow(chatRow, "full")
    -- the Announcements tab: tag chips, cards, editor
    StyleAnnouncements()

    -- EVERY PANEL: the ones made so far now, the later ones as they are made (core.lua ApplyModernStyle)
    for _, f in ipairs(addonTable.styledFrames or {}) do StylePanel(f) end
    addonTable.ThemeStyle = StylePanel

    -- The status in the header's free fields left and right of the crest (user's pomysl.png)
    StatusInHeader(UI, MF)

    -- BUTTONS, X BUTTONS and DROPDOWNS: the window's now, the ones made later when a tab opens (a moment after,
    -- once the tab has built them), and the addon's own windows outside it the moment they show, in the same
    -- frame, so they never appear in the old look (user: "po zmianie theme chciałem nowy event zrobić, theme się
    -- zmienił dopiero po jakiejś 1 s": they were checked once a second): the event creator on its OnShow, Guild
    -- cleanup (made when first opened) right after GuildCleanup.Toggle. Done ones are skipped.
    StyleAllButtons(MF)
    HookDropDownLists()
    -- unread badges: the ones made from now on (core.lua calls ThemeBadge), and any made before this ran
    addonTable.ThemeBadge = StyleBadge
    for _, list in ipairs({ UI.menuButtons or {}, UI.chatTabButtons or {} }) do
        for _, btn in pairs(list) do
            StyleBadge(btn.unreadBadge)
            StyleBadge(btn.badge)
        end
    end
    for _, p in pairs(UI.Panels or {}) do
        p:HookScript("OnShow", function(self) _G.C_Timer.After(0, function() StyleAllButtons(self) end) end)
    end
    if _G.JagodkiCreatorFrame then
        _G.JagodkiCreatorFrame:HookScript("OnShow", function(self) StyleAllButtons(self) end)
    end
    local GC = addonTable.GuildCleanup
    if GC and GC.Toggle then
        _G.hooksecurefunc(GC, "Toggle", function()
            local w = _G.JagodkaGuildCleanup
            if w then StyleAllButtons(w) end
        end)
    end
end

-- At login (after the saved choice and the window's saved size are loaded)
local starter = CreateFrame("Frame")
starter:RegisterEvent("PLAYER_LOGIN")
starter:SetScript("OnEvent", function()
    active = Theme.Saved()
    if active == "forest" and addonTable.UI then
        local ok, err = pcall(ApplyForest, addonTable.UI)
        if not ok and addonTable.Monitor then addonTable.Monitor.Error("Look 'Forest Berry' failed: " .. tostring(err)) end
    end
    -- After a reload for a look (user: "jak ktoś kliknie i będzie reload, to otwórz addon; to samo po reload w
    -- Settings"): the window opens by itself a moment after login, in the look now in use. "window": from
    -- What's new's "Try it now" (update.lua); "look": from Settings > Appearance's "Reload now", which opens on
    -- Appearance again. Once: the mark is cleared.
    local db = _G.JagodkiMinimapDB
    local open = type(db) == "table" and db.openAfterReload or nil
    if open and addonTable.UI then
        db.openAfterReload = nil
        _G.C_Timer.After(1, function()
            local UI = addonTable.UI
            UI.MainFrame:Show()
            if open == "look" and UI.ShowTab then
                UI.ShowTab(8)
                if addonTable.Settings and addonTable.Settings.Open then addonTable.Settings.Open("look") end
            end
        end)
    end
end)
