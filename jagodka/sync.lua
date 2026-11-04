-- ============================================================================
-- SYNC: sync progress bar in the main window header
-- ============================================================================
--  * Shown only while something is happening (and only with the window open, as it is part of it).
--  * Other files report stages: Sync.Start(stage) -> Sync.Activity(stage) on each packet.
--    A stage is done when nothing arrives for a moment (or nobody answers / the limit passes).
--  * Global channel: checked here directly (whether the addon has joined it yet).
--  * When everything is finished: "Synced" for a few seconds, then the bar disappears.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local GetTime = _G.GetTime
local ipairs, pairs = _G.ipairs, _G.pairs
local table = _G.table

local Sync = {}
addonTable.Sync = Sync

-- Order and names of the stages on the bar
local STAGES = {
    { key = "channel", label = "Channel" },
    { key = "history", label = "Chat" },
    { key = "events", label = "Events" },
    { key = "rosters", label = "Rosters" },
}
-- first = how long to wait for the first answer (responders pick a random 0.5-2.5 s), quiet = silence after the last
-- packet, max = hard limit
local TIMING = {
    channel = { max = 40 },
    history = { first = 7, quiet = 3, max = 20 },
    events = { first = 7, quiet = 3, max = 30 },
    rosters = { first = 8, quiet = 4, max = 40 },
}
local SHOW_DONE_FOR = 4 -- seconds showing "Synced"

local ICON_DONE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t"
local ICON_WAIT = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:12:12|t"

local state = {}      -- stage -> { started, last, done }
local finishedAt = nil
local bar = nil

-- ============================================================================
-- API for other files
-- ============================================================================
function Sync.Start(key)
    local now = GetTime()
    state[key] = { started = now, last = nil, done = false, packets = 0 }
    if addonTable.Monitor then addonTable.Monitor.SyncStage(key, "started") end
    finishedAt = nil
end

function Sync.Activity(key)
    local s = state[key]
    if s and not s.done then s.last = GetTime() s.packets = s.packets + 1 end
end

function Sync.Done(key)
    local s = state[key]
    if s then s.done = true end
end

-- ============================================================================
-- STATE
-- ============================================================================
-- For the Monitoring tab: how a stage ended
local function ReportDone(key, s, now)
    if not addonTable.Monitor then return end
    local took = _G.string.format("%.1f s", now - s.started)
    local text
    if key == "channel" then text = (s.limit and "gave up after " or "joined after ") .. took
    elseif s.packets > 0 then text = "finished after " .. took .. ", " .. s.packets .. " packets" .. (s.limit and " (time limit)" or "")
    else text = "no answer after " .. took end
    addonTable.Monitor.SyncStage(key, text)
end

local function Update()
    local now = GetTime()
    local anyActive, anyStarted = false, false
    for key, s in pairs(state) do
        anyStarted = true
        if not s.done then
            local t = TIMING[key] or {}
            if key == "channel" then
                if addonTable.Most and addonTable.Most.GetChannelId() then s.done = true end
            elseif s.last then
                if now - s.last > (t.quiet or 3) then s.done = true end
            elseif now - s.started > (t.first or 7) then
                -- Nobody answered (e.g. nobody else is online or we already have everything)
                s.done = true
            end
            if not s.done and now - s.started > (t.max or 30) then s.done = true s.limit = true end
            if s.done then ReportDone(key, s, now) else anyActive = true end
        end
    end
    if anyStarted and not anyActive and not finishedAt then finishedAt = now end
    return anyStarted, anyActive
end

-- ============================================================================
-- LOGIN LOCK: officer actions wait for the first sync, so nobody acts on old data
-- ============================================================================
-- At least LOCK_MIN seconds (covers the repeated request for a relay that found other guilds at 14 s), then
-- until the stages finish, and never over LOCK_MAX, so it always ends, also for someone alone online.
local LOCK_MIN, LOCK_MAX = 16, 45
local lockStart = nil

-- From login, and again when the guild becomes known and the first sync really starts
function Sync.StartLoginLock() lockStart = GetTime() end

function Sync.LoginLocked()
    if not lockStart then return false end
    local elapsed = GetTime() - lockStart
    if elapsed >= LOCK_MAX then return false end
    if elapsed < LOCK_MIN then return true end
    local _, anyActive = Update()
    return anyActive
end

-- For officer actions: true = locked, with a message on the screen
function Sync.Blocked()
    if not Sync.LoginLocked() then return false end
    if _G.UIErrorsFrame then _G.UIErrorsFrame:AddMessage("Syncing - available in a moment", 1, 0.82, 0, 1, 2) end
    return true
end

local function Render()
    if not bar then return end
    local anyStarted, anyActive = Update()
    if not anyStarted or (not anyActive and finishedAt and GetTime() - finishedAt > SHOW_DONE_FOR) then
        bar:Hide()
        -- Clear when finished so the next sync starts from zero
        if anyStarted and not anyActive then state = {} finishedAt = nil end
        return
    end
    local total, done, parts = 0, 0, {}
    for _, stage in ipairs(STAGES) do
        local s = state[stage.key]
        if s then
            total = total + 1
            if s.done then done = done + 1 end
            table.insert(parts, (s.done and ICON_DONE or ICON_WAIT) .. " " .. stage.label)
        end
    end
    bar:SetMinMaxValues(0, total)
    bar:SetValue(done)
    if anyActive then
        bar:SetStatusBarColor(0.75, 0.25, 1, 0.8)
        bar.text:SetText("Syncing:  " .. table.concat(parts, "   "))
    else
        bar:SetStatusBarColor(0.2, 0.75, 0.2, 0.8)
        bar.text:SetText(ICON_DONE .. " Synced")
    end
    bar:Show()
end

-- ============================================================================
-- UI: bar in the window header (core.lua calls Sync.Attach after creating the header)
-- ============================================================================
function Sync.Attach(parent, rightOf)
    bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(300, 16)
    bar:SetPoint("RIGHT", rightOf, "LEFT", -20, 0)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.5)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar:Hide()
    -- Refresh only with the window open (the bar is part of the window)
    local elapsedSum = 0
    parent:HookScript("OnUpdate", function(_, elapsed)
        elapsedSum = elapsedSum + elapsed
        if elapsedSum < 0.25 then return end
        elapsedSum = 0
        Render()
    end)
end

-- Global channel: stage from login until joining the channel
local Listener = CreateFrame("Frame")
Listener:RegisterEvent("PLAYER_LOGIN")
Listener:SetScript("OnEvent", function()
    Sync.Start("channel")
    Sync.StartLoginLock()
end)

-- State is also updated with the window closed (cheap, every 1 s), so opening it does not show old stages
C_Timer.NewTicker(1, Update)
