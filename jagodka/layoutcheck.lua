-- ============================================================================
-- layoutcheck.lua (1.2.0): "/jagodka check" - is anything sticking out of the window?
-- ============================================================================
-- User: "chcę, żebyś sprawdził, że w środku zawsze będzie dostosowane, żeby nic na zewnątrz nie wystawało;
-- na streamie u niektórych się zdarzało". What sticks out depends on the player's fonts, UI scale and screen,
-- so the check runs in the player's own game: it opens every tab in turn and looks at everything shown:
--   * anything outside the window (more than 2 px), and the window itself outside the screen;
--   * anything of a tab's panel reaching past the panel's right edge (into the right column).
-- Not counted: the look's own frame art around the window (themes.lua marks it), what a scroll frame clips,
-- hidden or fully transparent parts. Each finding goes to the chat and to the Monitoring log (so it is in the
-- logs). Only reads positions; the tab that was open is opened again at the end.
local addonName, addonTable = ...
local _G = _G
local Check = {}
addonTable.LayoutCheck = Check

local TOL = 2   -- px of tolerance

-- A region's edges on the screen (left, right, top, bottom), or nil when it has no place yet
local function Rect(r)
    local l, b, w, h = r:GetRect()
    if not l or not w or w <= 0 or h <= 0 then return nil end
    local s = (r.GetEffectiveScale and r:GetEffectiveScale()) or (r:GetParent() and r:GetParent():GetEffectiveScale()) or 1
    return l * s, (l + w) * s, (b + h) * s, b * s
end

-- What to call it in the report: its name (or the game's debug name) and its text, if any
local function Label(r)
    local n = (r.GetName and r:GetName()) or (r.GetDebugName and r:GetDebugName()) or r:GetObjectType()
    local t = r.GetText and r:GetText()
    if type(t) == "string" and t ~= "" then
        t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
        if #t > 30 then t = t:sub(1, 30) .. "..." end
        return (n or "?") .. ' "' .. t .. '"'
    end
    return n or "?"
end

local function Shown(r)
    if r.IsVisible and not r:IsVisible() then return false end
    if r.GetAlpha and r:GetAlpha() <= 0.01 then return false end
    if r.GetEffectiveAlpha and r:GetEffectiveAlpha() <= 0.01 then return false end
    return true
end

-- Calls fn for a frame, its regions and its children's, below it (not inside a scroll frame's content)
local function Walk(frame, fn, skipOwnRegions)
    if frame.forestArt then return end
    fn(frame)
    if not skipOwnRegions then
        for _, r in ipairs({ frame:GetRegions() }) do fn(r) end
    end
    if frame:GetObjectType() == "ScrollFrame" then return end
    for _, c in ipairs({ frame:GetChildren() }) do Walk(c, fn) end
end

-- How far past each edge (px), only the edges that are past
local function Past(r, l, rt, t, b)
    local rl, rr, rtop, rb = Rect(r)
    if not rl then return nil end
    local out = {}
    if rl < l - TOL then table.insert(out, "left " .. math.floor(l - rl + 0.5)) end
    if rr > rt + TOL then table.insert(out, "right " .. math.floor(rr - rt + 0.5)) end
    if t and rtop > t + TOL then table.insert(out, "top " .. math.floor(rtop - t + 0.5)) end
    if b and rb < b - TOL then table.insert(out, "bottom " .. math.floor(b - rb + 0.5)) end
    return #out > 0 and table.concat(out, ", ") or nil
end

function Check.Run()
    local UI = addonTable.UI
    local MF = UI and UI.MainFrame
    if not MF then return end
    local out = _G.DEFAULT_CHAT_FRAME
    local function Say(text)
        if out then out:AddMessage("|cffbf40ff[Jagodka]|r " .. text) end
        if addonTable.Monitor and addonTable.Monitor.Note then addonTable.Monitor.Note("Layout check: " .. text) end
    end
    MF:Show()
    -- the tab open now, opened again at the end
    local current
    for i, p in pairs(UI.Panels) do if p:IsShown() then current = i end end
    local tabs = {}
    for i, btn in pairs(UI.menuButtons) do
        if btn:IsShown() and UI.Panels[i] then table.insert(tabs, { i = i, x = btn.x or 0 }) end
    end
    table.sort(tabs, function(a, b) return a.x < b.x end)
    local found, seen = 0, {}
    local function Report(tab, r, where, how)
        local key = Label(r) .. where
        if seen[key] then return end
        seen[key] = true
        found = found + 1
        if found <= 25 then Say(tab .. ": " .. Label(r) .. " sticks out of " .. where .. " (" .. how .. " px)") end
    end
    local function Scan(i)
        local tab = (UI.tabNames and UI.tabNames[i]) or tostring(i)
        local ml, mr, mt, mb = Rect(MF)
        if not ml then return end
        -- everything shown, against the window (its own regions are its look: not counted)
        Walk(MF, function(r)
            if r == MF or not Shown(r) then return end
            local how = Past(r, ml, mr, mt, mb)
            if how then Report(tab, r, "the window", how) end
        end, true)
        -- the tab's panel: nothing past its right edge (the right column is there)
        local p = UI.Panels[i]
        local pl, pr = Rect(p)
        if pl then
            Walk(p, function(r)
                if r == p or not Shown(r) then return end
                local how = Past(r, pl - 10000, pr, nil, nil)
                if how then Report(tab, r, "its panel into the right column", how) end
            end)
        end
    end
    -- the window and the screen
    local sl, sr, st, sb = Rect(_G.UIParent)
    local wl, wr, wt, wb = Rect(MF)
    Say(string.format("Checking the layout: window %d x %d, scale %.2f, screen %d x %d...",
        MF:GetWidth(), MF:GetHeight(), MF:GetScale(), _G.UIParent:GetWidth(), _G.UIParent:GetHeight()))
    if sl and wl and (wl < sl - TOL or wr > sr + TOL or wt > st + TOL or wb < sb - TOL) then
        Say("the window is partly off the screen (moved there, or bigger than the screen)")
    end
    -- one tab after another, a moment each so it can lay itself out
    local k = 0
    local function Next()
        k = k + 1
        local t = tabs[k]
        if not t then
            if current then UI.ShowTab(current) end
            Say(found == 0 and "|cff33ff66nothing sticks out.|r" or ("|cffff5555" .. found .. " found|r" .. (found > 25 and " (first 25 shown)" or "") .. ". Copy the logs (tools\\logs.bat) for the details."))
            return
        end
        UI.ShowTab(t.i)
        _G.C_Timer.After(0.3, function()
            Scan(t.i)
            Next()
        end)
    end
    Next()
end
