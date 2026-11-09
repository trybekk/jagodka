-- ============================================================================
-- SAFE CALLS (from 0.15.1): every event handler, OnUpdate and timer of the addon runs protected
-- ============================================================================
--  * One error (e.g. a secret value in a dungeon) used to stop only that call, but in a ticker it could
--    stop a repeating job (the online signal, rejoining the channels, cleanup) until /reload: players
--    reported "the addon often stops working". Now the error is caught, written to Monitoring
--    (Errors, with where it happened) and everything goes on. The idea is Olympus's ns.SafeCall.
--  * addonTable.SafeTimer: C_Timer with protected callbacks (After, NewTicker, NewTimer); every file
--    uses it as its C_Timer. addonTable.SafeScript(frame, "OnEvent", where, fn): SetScript with a
--    protected handler.
--  * The same error from the same place is logged at most once a minute (the rest only counted), so a
--    repeating error cannot fill the log. Loaded first (.toc), uses nothing of the addon at load time.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local pcall, tostring, type, pairs = _G.pcall, _G.tostring, _G.type, _G.pairs
local table, math, string = _G.table, _G.math, _G.string
local GetTime = _G.GetTime
local RealTimer = _G.C_Timer

local LOG_AGAIN = 60     -- the same error from the same place is logged again only after this (s)
local lastLogged = {}    -- "where|error" -> GetTime() of the last log line
local counts = {}        -- "where|error" -> how many times it happened

local function Report(where, err)
    local text = tostring(err)
    local key = where .. "|" .. text
    counts[key] = (counts[key] or 0) + 1
    if GetTime() - (lastLogged[key] or -LOG_AGAIN) < LOG_AGAIN then return end
    lastLogged[key] = GetTime()
    local Monitor = addonTable.Monitor
    local line = "Lua error in " .. where .. ": " .. text .. (counts[key] > 1 and (" (" .. counts[key] .. "x)") or "")
    if Monitor and Monitor.Error then
        pcall(Monitor.Error, line)
    elseif _G.DEFAULT_CHAT_FRAME then
        _G.DEFAULT_CHAT_FRAME:AddMessage("|cffbf40ff[Jagodka]|r |cffff5555" .. line .. "|r")
    end
end

-- ----------------------------------------------------------------------------
-- PROFILER (0.15.2, "/jagodka perf"): while on, every protected call is timed by its place (file:line);
-- the report shows the places that took the most time, the slowest single calls and how many frames
-- had 30 ms or more of the addon's work. Off (the default) it costs nothing. Not saved.
-- ----------------------------------------------------------------------------
local perf = { on = false, places = {}, frameMs = 0, heavyFrames = 0, frames = 0, since = 0 }
addonTable.Perf = perf
local debugprofilestop = _G.debugprofilestop
local perfFrame = _G.CreateFrame("Frame")
perfFrame:Hide()
perfFrame:SetScript("OnUpdate", function()
    perf.frames = perf.frames + 1
    if perf.frameMs >= 30 then perf.heavyFrames = perf.heavyFrames + 1 end
    perf.frameMs = 0
end)

function perf.Start()
    perf.on, perf.places, perf.frameMs, perf.heavyFrames, perf.frames, perf.since = true, {}, 0, 0, 0, GetTime()
    perfFrame:Show()
end
function perf.Stop() perf.on = false perfFrame:Hide() end

-- Report lines: the 10 places with the most time, each with calls, total and slowest call
function perf.Report()
    local list = {}
    for where, p in pairs(perf.places) do table.insert(list, { where = where, n = p.n, total = p.total, max = p.max }) end
    table.sort(list, function(a, b) return a.total > b.total end)
    local lines = { string.format("Profiler: %s, %.0f s measured, %d frames, %d with 30 ms or more of the addon's work",
        perf.on and "on" or "off", (perf.on and GetTime() or perf.stoppedAt or GetTime()) - perf.since, perf.frames, perf.heavyFrames) }
    for i = 1, math.min(10, #list) do
        local p = list[i]
        table.insert(lines, string.format("%d. %s: %d calls, %.1f ms total, slowest %.1f ms", i, p.where, p.n, p.total, p.max))
    end
    if #list == 0 then table.insert(lines, "Nothing measured yet.") end
    return lines
end

local function Timed(where, fn, ...)
    local start = debugprofilestop()
    local result = { pcall(fn, ...) }
    local ms = debugprofilestop() - start
    local p = perf.places[where]
    if not p then p = { n = 0, total = 0, max = 0 } perf.places[where] = p end
    p.n, p.total = p.n + 1, p.total + ms
    if ms > p.max then p.max = ms end
    perf.frameMs = perf.frameMs + ms
    return result
end

-- Calls fn(...) protected; returns what fn returns, or nothing after an error
function addonTable.Safe(where, fn, ...)
    local result = (perf.on and debugprofilestop) and Timed(where, fn, ...) or { pcall(fn, ...) }
    if not result[1] then Report(where, result[2]) return end
    return _G.unpack(result, 2)
end
local Safe = addonTable.Safe

-- frame:SetScript(script, fn) with fn protected
function addonTable.SafeScript(frame, script, where, fn)
    frame:SetScript(script, function(...) return Safe(where, fn, ...) end)
end

-- C_Timer with protected callbacks; the tickers and timers it returns are the game's own (Cancel works)
local function Where(level)
    local info = _G.debugstack and _G.debugstack(level, 1, 0)
    return info and (info:match("([%w_]+%.lua:%d+)")) or "timer"
end
addonTable.SafeTimer = {
    After = function(seconds, fn)
        local where = Where(3)
        return RealTimer.After(seconds, function(...) return Safe(where, fn, ...) end)
    end,
    -- 0.15.2: a repeating ticker of 10 s or more starts after a random part of its period (at most 60 s), so
    -- the dozen tickers started at login do not all run in the same frame every minute (a hitch; the idea is
    -- Olympus's ns.Every). Fast tickers (the send queue, the UI) and counted ones start at once, as before.
    -- The handle's Cancel works before and after the start.
    NewTicker = function(seconds, fn, iterations)
        local where = Where(3)
        local function Tick(...) return Safe(where, fn, ...) end
        if seconds < 10 or iterations then return RealTimer.NewTicker(seconds, Tick, iterations) end
        local handle, ticker, cancelled = {}, nil, false
        function handle.Cancel() cancelled = true if ticker then ticker:Cancel() end end
        function handle:IsCancelled() return cancelled end
        RealTimer.After(math.random() * math.min(seconds, 60), function()
            if not cancelled then ticker = RealTimer.NewTicker(seconds, Tick) end
        end)
        return handle
    end,
    NewTimer = function(seconds, fn)
        local where = Where(3)
        return RealTimer.NewTimer(seconds, function(...) return Safe(where, fn, ...) end)
    end,
}
