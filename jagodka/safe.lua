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
local pcall, tostring, type = _G.pcall, _G.tostring, _G.type
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

-- Calls fn(...) protected; returns what fn returns, or nothing after an error
function addonTable.Safe(where, fn, ...)
    local result = { pcall(fn, ...) }
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
    NewTicker = function(seconds, fn, iterations)
        local where = Where(3)
        return RealTimer.NewTicker(seconds, function(...) return Safe(where, fn, ...) end, iterations)
    end,
    NewTimer = function(seconds, fn)
        local where = Where(3)
        return RealTimer.NewTimer(seconds, function(...) return Safe(where, fn, ...) end)
    end,
}
