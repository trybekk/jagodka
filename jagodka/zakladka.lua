-- ============================================================================
-- ZAKLADKI W CZACIE BLIZZARDA: General i Trade wspolnoty
-- ============================================================================
--  * Dodatkowo do okna addonu: te same wiadomosci, w zwyklym oknie czatu gry.
--    "Jagodki Nadina - General" = zakladka General addonu (polaczona z /g),
--    "Jagodki Nadina - Trade" = zakladka Trade addonu (tylko addon, bez /g).
--  * Tworzone raz (pierwsze zalogowanie z addonem); gra sama pamieta okna czatu.
--    Zamknieta przez gracza nie wraca sama - "/jagodka tab" tworzy brakujace ponownie.
--  * Tylko do czytania: General pisze sie przez /g albo w oknie addonu, Trade w oknie addonu.
--    Nicki sa linkami (klik = szept, prawy klik = menu), linki przedmiotow dzialaja jak w grze.
--  * Po zalogowaniu pokazuje ostatnie wiadomosci z historii, potem nowe na biezaco.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local ipairs = _G.ipairs
local table, math = _G.table, _G.math

local Most = addonTable.Most

local REPLAY_COUNT = 30       -- ile ostatnich wiadomosci pokazac po zalogowaniu
local REPLAY_DELAY = 15       -- s po zalogowaniu (po synchronizacji historii)

-- tab = zakladka czatu addonu, flag = znacznik w JagodkiChatDB (zakladka juz raz utworzona),
-- color = kolor tresci (rozny od /g i od siebie), old = wczesniejsze nazwy (przemianowywane)
local TABS = {
    { name = "Jagodki Nadina - General", tab = "Ogolny", flag = "blizzTabCreated", color = "ff3cb43c", old = { ["Jagodki Nadina"] = true } },
    { name = "Jagodki Nadina - Trade", tab = "Handel", flag = "blizzTradeTabCreated", color = "ffd2a05a", old = {} },
}

local Zakladka = {}
addonTable.Zakladka = Zakladka

-- Stan kazdej zakladki trzymamy w jej wpisie TABS: frame, lastShownTs
-- (lastShownTs = nil -> historia jeszcze nie pokazana, do tego czasu nic nie wypisujemy)

local function FindTab(def)
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local name = _G.GetChatWindowInfo(i)
        if name == def.name then return _G["ChatFrame" .. i] end
        -- Zakladka utworzona pod stara nazwa: przemianowujemy zamiast tworzyc druga
        if def.old[name] then
            local frame = _G["ChatFrame" .. i]
            if _G.FCF_SetWindowName then _G.FCF_SetWindowName(frame, def.name) end
            return frame
        end
    end
    return nil
end

local function CreateTab(def)
    if not _G.FCF_OpenNewWindow then return nil end
    -- Nowe okno dokuje sie na koncu (przy domyslnym czacie: General, Combat Log, nasze zakladki)
    _G.FCF_OpenNewWindow(def.name, true)
    local frame = FindTab(def)
    if not frame then return nil end -- limit okien czatu
    -- Zadnych zwyklych kanalow ani typow wiadomosci - tylko to, co wypisze addon
    if _G.ChatFrame_RemoveAllMessageGroups then _G.ChatFrame_RemoveAllMessageGroups(frame) end
    if _G.ChatFrame_RemoveAllChannels then _G.ChatFrame_RemoveAllChannels(frame) end
    -- Nowe okno samo sie zaznacza - wracamy na General
    if _G.FCF_SelectDockFrame and _G.DEFAULT_CHAT_FRAME then _G.FCF_SelectDockFrame(_G.DEFAULT_CHAT_FRAME) end
    return frame
end

local function DefFor(tab)
    for _, def in ipairs(TABS) do
        if def.tab == tab then return def end
    end
    return nil
end

local function Print(def, e)
    if def.frame and e.src ~= "S" and not addonTable.Mute.IsMuted(e.author) then
        def.frame:AddMessage(Most.FormatEntry(e, true, def.color))
        if not def.lastShownTs or e.ts > def.lastShownTs then def.lastShownTs = e.ts end
    end
end

local function Replay(def)
    if not def.frame then return end
    local list = {}
    for _, e in ipairs(Most.GetLog()) do
        if e.tab == def.tab and e.src ~= "S" then table.insert(list, e) end
    end
    local first = math.max(1, #list - REPLAY_COUNT + 1)
    def.frame:AddMessage("|cff808080--- " .. def.name .. ": last messages ---|r")
    def.lastShownTs = 0
    for i = first, #list do Print(def, list[i]) end
end

local function ReplayAll()
    for _, def in ipairs(TABS) do Replay(def) end
end

-- Nowe wiadomosci: biezace zawsze, z historii tylko nowsze od ostatnio pokazanej
-- (okno czatu gry dopisuje tylko na koncu, starsze zaburzylyby kolejnosc)
Most.OnNewEntry(function(e, live)
    local def = DefFor(e.tab)
    if not def or def.lastShownTs == nil then return end
    if live or e.ts > def.lastShownTs then Print(def, e) end
end)

local function Setup(force)
    local db = _G.JagodkiChatDB
    if not db then return end
    for _, def in ipairs(TABS) do
        def.frame = FindTab(def)
        if not def.frame and (force or not db[def.flag]) then
            def.frame = CreateTab(def)
            if def.frame then db[def.flag] = true end
        end
    end
end

-- Czy to okno czatu jest jedna z naszych zakladek (np. menu na nicku w wyciszenie.lua)
function Zakladka.IsOurFrame(frame)
    for _, def in ipairs(TABS) do
        if frame and def.frame == frame then return true end
    end
    return false
end

-- "/jagodka tab": ponowne utworzenie brakujacych zakladek (np. po zamknieciu)
function Zakladka.Recreate()
    Setup(true)
    local any = false
    for _, def in ipairs(TABS) do
        if def.frame then
            Replay(def)
            any = true
        end
    end
    return any
end

local Listener = CreateFrame("Frame")
Listener:RegisterEvent("PLAYER_LOGIN")
Listener:SetScript("OnEvent", function()
    -- Okna czatu sa gotowe chwile po zalogowaniu
    C_Timer.After(3, function() Setup(false) end)
    C_Timer.After(REPLAY_DELAY, ReplayAll)
end)
