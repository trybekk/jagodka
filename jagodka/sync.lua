-- ============================================================================
-- SYNCHRO: pasek postepu synchronizacji w naglowku glownego okna
-- ============================================================================
--  * Pokazuje sie tylko, gdy cos sie dzieje (i tylko przy otwartym oknie - jest jego czescia).
--  * Etapy zglaszaja inne pliki: Sync.Start(etap) -> Sync.Activity(etap) przy kazdym pakiecie.
--    Etap jest gotowy, gdy przez chwile nic nie przychodzi (albo nikt nie odpowiada / minie limit).
--  * Kanal globalny: sprawdzany sam (czy addon juz na nim jest).
--  * Po zakonczeniu wszystkiego: "Synced" przez kilka sekund, potem pasek znika.
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

-- Kolejnosc i nazwy etapow na pasku
local STAGES = {
    { key = "channel", label = "Channel" },
    { key = "history", label = "Chat" },
    { key = "events", label = "Events" },
    { key = "rosters", label = "Rosters" },
}
-- first = ile czekamy na pierwsza odpowiedz (odpowiadajacy losuja 1-4 s), quiet = cisza po ostatnim
-- pakiecie, max = twardy limit
local TIMING = {
    channel = { max = 40 },
    history = { first = 7, quiet = 3, max = 20 },
    events = { first = 7, quiet = 3, max = 30 },
    rosters = { first = 8, quiet = 4, max = 40 },
}
local SHOW_DONE_FOR = 4 -- s z napisem "Synced"

local ICON_DONE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t"
local ICON_WAIT = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:12:12|t"

local state = {}      -- etap -> { started, last, done }
local finishedAt = nil
local bar = nil

-- ============================================================================
-- API dla innych plikow
-- ============================================================================
function Sync.Start(key)
    local now = GetTime()
    state[key] = { started = now, last = nil, done = false }
    finishedAt = nil
end

function Sync.Activity(key)
    local s = state[key]
    if s and not s.done then s.last = GetTime() end
end

function Sync.Done(key)
    local s = state[key]
    if s then s.done = true end
end

-- ============================================================================
-- STAN
-- ============================================================================
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
                -- Nikt nie odpowiedzial (np. nikogo innego online albo wszystko juz mamy)
                s.done = true
            end
            if not s.done and now - s.started > (t.max or 30) then s.done = true end
            if not s.done then anyActive = true end
        end
    end
    if anyStarted and not anyActive and not finishedAt then finishedAt = now end
    return anyStarted, anyActive
end

local function Render()
    if not bar then return end
    local anyStarted, anyActive = Update()
    if not anyStarted or (not anyActive and finishedAt and GetTime() - finishedAt > SHOW_DONE_FOR) then
        bar:Hide()
        -- Po zakonczeniu czyscimy, zeby kolejna synchronizacja zaczela od zera
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
-- UI: pasek w naglowku okna (core.lua wywoluje Sync.Attach po utworzeniu naglowka)
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
    -- Odswiezanie tylko przy otwartym oknie (pasek jest czescia okna)
    local elapsedSum = 0
    parent:HookScript("OnUpdate", function(_, elapsed)
        elapsedSum = elapsedSum + elapsed
        if elapsedSum < 0.25 then return end
        elapsedSum = 0
        Render()
    end)
end

-- Kanal globalny: etap od zalogowania do wejscia na kanal
local Listener = CreateFrame("Frame")
Listener:RegisterEvent("PLAYER_LOGIN")
Listener:SetScript("OnEvent", function() Sync.Start("channel") end)

-- Stan przelicza sie tez przy zamknietym oknie (lekko, co 1 s), zeby po otwarciu nie pokazac starych etapow
C_Timer.NewTicker(1, Update)
