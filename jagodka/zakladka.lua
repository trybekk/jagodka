-- ============================================================================
-- ZAKLADKA W CZACIE BLIZZARDA: "Jagodki Nadina" = czat General wspolnoty
-- ============================================================================
--  * Dodatkowo do okna addonu: te same wiadomosci, w zwyklym oknie czatu gry.
--  * Tworzona raz (pierwsze zalogowanie z addonem); gra sama pamieta okna czatu.
--    Zamknieta przez gracza nie wraca sama - "/jagodka tab" tworzy ja ponownie.
--  * Tylko do czytania: pisze sie przez /g (relay przenosi do wszystkich gildii)
--    albo w oknie addonu. Nicki sa linkami (klik = szept, prawy klik = menu).
--  * Po zalogowaniu pokazuje ostatnie wiadomosci z historii, potem nowe na biezaco.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local ipairs = _G.ipairs
local table, math = _G.table, _G.math

local Most = addonTable.Most

local TAB_NAME = "Jagodki Nadina - General"
local OLD_TAB_NAMES = { ["Jagodki Nadina"] = true } -- wczesniejsza nazwa: zakladka zostaje przemianowana
local TEXT_COLOR = "ff3cb43c"  -- ciemniejsza zielen, zeby odroznic od /g (jasnozielony)
local BRIDGED_TAB = "Ogolny"  -- zakladka czatu addonu pokazywana w oknie gry (General)
local REPLAY_COUNT = 30       -- ile ostatnich wiadomosci pokazac po zalogowaniu
local REPLAY_DELAY = 15       -- s po zalogowaniu (po synchronizacji historii)

local Zakladka = {}
addonTable.Zakladka = Zakladka

local tabFrame = nil
local lastShownTs = nil -- nil = historia jeszcze nie pokazana (do tego czasu nic nie wypisujemy)

local function FindTab()
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local name = _G.GetChatWindowInfo(i)
        if name == TAB_NAME then return _G["ChatFrame" .. i] end
        -- Zakladka utworzona pod stara nazwa: przemianowujemy zamiast tworzyc druga
        if OLD_TAB_NAMES[name] then
            local frame = _G["ChatFrame" .. i]
            if _G.FCF_SetWindowName then _G.FCF_SetWindowName(frame, TAB_NAME) end
            return frame
        end
    end
    return nil
end

local function CreateTab()
    if not _G.FCF_OpenNewWindow then return nil end
    -- Nowe okno dokuje sie na koncu (przy domyslnym czacie: General, Combat Log, Jagodki Nadina)
    _G.FCF_OpenNewWindow(TAB_NAME, true)
    local frame = FindTab()
    if not frame then return nil end -- limit okien czatu
    -- Zadnych zwyklych kanalow ani typow wiadomosci - tylko to, co wypisze addon
    if _G.ChatFrame_RemoveAllMessageGroups then _G.ChatFrame_RemoveAllMessageGroups(frame) end
    if _G.ChatFrame_RemoveAllChannels then _G.ChatFrame_RemoveAllChannels(frame) end
    -- Nowe okno samo sie zaznacza - wracamy na General
    if _G.FCF_SelectDockFrame and _G.DEFAULT_CHAT_FRAME then _G.FCF_SelectDockFrame(_G.DEFAULT_CHAT_FRAME) end
    return frame
end

local function Print(e)
    if tabFrame and e.tab == BRIDGED_TAB and e.src ~= "S" and not addonTable.Mute.IsMuted(e.author) then
        tabFrame:AddMessage(Most.FormatEntry(e, true, TEXT_COLOR))
        if not lastShownTs or e.ts > lastShownTs then lastShownTs = e.ts end
    end
end

local function Replay()
    if not tabFrame then return end
    local log, list = Most.GetLog(), {}
    for _, e in ipairs(log) do
        if e.tab == BRIDGED_TAB and e.src ~= "S" then table.insert(list, e) end
    end
    local first = math.max(1, #list - REPLAY_COUNT + 1)
    tabFrame:AddMessage("|cff808080--- " .. TAB_NAME .. ": last messages ---|r")
    lastShownTs = 0
    for i = first, #list do Print(list[i]) end
end

-- Nowe wiadomosci: biezace zawsze, z historii tylko nowsze od ostatnio pokazanej
-- (okno czatu gry dopisuje tylko na koncu, starsze zaburzylyby kolejnosc)
Most.OnNewEntry(function(e, live)
    if lastShownTs == nil then return end
    if live or e.ts > lastShownTs then Print(e) end
end)

local function Setup(force)
    local db = _G.JagodkiChatDB
    if not db then return end
    tabFrame = FindTab()
    if not tabFrame and (force or not db.blizzTabCreated) then
        tabFrame = CreateTab()
        if tabFrame then db.blizzTabCreated = true end
    end
end

-- Okno zakladki (albo nil) - np. dla menu na nicku w wyciszenie.lua
function Zakladka.GetFrame() return tabFrame end

-- "/jagodka tab": ponowne utworzenie zakladki (np. po zamknieciu)
function Zakladka.Recreate()
    Setup(true)
    if tabFrame then
        Replay()
        return true
    end
    return false
end

local Listener = CreateFrame("Frame")
Listener:RegisterEvent("PLAYER_LOGIN")
Listener:SetScript("OnEvent", function()
    -- Okna czatu sa gotowe chwile po zalogowaniu
    C_Timer.After(3, function() Setup(false) end)
    C_Timer.After(REPLAY_DELAY, Replay)
end)
