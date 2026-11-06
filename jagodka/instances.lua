-- ============================================================================
-- INSTANCES (list to choose from when creating an event)
-- ============================================================================
-- English names (as in the EU client). Each entry has its level range (or raid size) per game:
--   era     = Classic Era (1.15), forever = WoW Forever (1.60); an entry without one is not in that game.
--   opens   = { year, month, day }: on WoW Forever not open yet before that day. Such an instance is still
--             listed, grayed out, and can be chosen for an event on that day or later.
-- WoW Forever data from Blizzard's announcements (20.10.2026): the original dungeons at Forever's own
-- minimum levels, 9 new dungeons, and from 09.12.2026 the raids Barrow Deeps, Hyjal Summit and Onyxia's Lair.
-- Molten Core, Blackwing Lair, Zul'Gurub, Ahn'Qiraj and Naxxramas are not announced for Forever.
-- To add a new instance, just add it to the right group.
local addonName, addonTable = ...

local FOREVER_RAIDS_OPEN = { 2026, 12, 9 }

local GROUPS = {
    {
        group = "Dungeons",
        list = {
            { name = "Ragefire Chasm", era = "13-18", forever = "13+" },
            { name = "Wailing Caverns", era = "17-24", forever = "17+" },
            { name = "The Deadmines", era = "17-26", forever = "16+" },
            { name = "Shadowfang Keep", era = "22-30", forever = "18+" },
            { name = "Blackfathom Deeps", era = "24-32", forever = "22+" },
            { name = "The Stockade", era = "24-32", forever = "23+" },
            { name = "Gnomeregan", era = "29-38", forever = "25+" },
            { name = "Razorfen Kraul", era = "29-38", forever = "24+" },
            { name = "Scarlet Monastery", era = "34-45", forever = "30+" },
            { name = "Razorfen Downs", era = "37-46", forever = "34+" },
            { name = "Uldaman", era = "41-51", forever = "35+" },
            { name = "Zul'Farrak", era = "42-46", forever = "42+" },
            { name = "Maraudon", era = "46-55", forever = "42+" },
            { name = "Sunken Temple", era = "50-56", forever = "45+" },
            { name = "Blackrock Depths", era = "52-60", forever = "48+" },
            { name = "Lower Blackrock Spire", era = "55-60", forever = "53+" },
            { name = "Upper Blackrock Spire", era = "55-60", forever = "?" }, -- in Forever, level not announced
            { name = "Dire Maul", era = "55-60", forever = "54+" },
            { name = "Stratholme", era = "58-60", forever = "55+" },
            { name = "Scholomance", era = "58-60", forever = "57+" },
        },
    },
    {
        group = "New dungeons (Forever)",
        list = {
            { name = "The Hall of Thanes", forever = "13-18" },
            { name = "Ruins of Lordaeron", forever = "15-20" },
            { name = "Excavation Site: Wetlands", forever = "24-29" },
            { name = "City of Dalaran", forever = "28-33" },
            { name = "The Drowned City", forever = "35-40" },
            { name = "Krol'dok Stronghold", forever = "40-45" },
            { name = "Alcaz Prison", forever = "48-53" },
            { name = "Blackmaw Hold", forever = "55-60" },
            { name = "Shaper's Terrace", forever = "58-60" },
        },
    },
    {
        group = "Raids",
        list = {
            { name = "Barrow Deeps", forever = "10-man", opens = FOREVER_RAIDS_OPEN },
            { name = "Hyjal Summit", forever = "20-man", opens = FOREVER_RAIDS_OPEN },
            { name = "Zul'Gurub", era = "20-man" },
            { name = "Ruins of Ahn'Qiraj", era = "20-man" },
            { name = "Molten Core", era = "40-man" },
            { name = "Onyxia's Lair", era = "40-man", forever = "40-man", opens = FOREVER_RAIDS_OPEN },
            { name = "Blackwing Lair", era = "40-man" },
            { name = "Temple of Ahn'Qiraj", era = "40-man" },
            { name = "Naxxramas", era = "40-man" },
        },
    },
    {
        -- Battlegrounds of each game (Darkspear Islands is new in WoW Forever), plus two for spontaneous PvP
        group = "PvP",
        list = {
            { name = "Warsong Gulch", era = "10v10", forever = "10v10" },
            { name = "Arathi Basin", era = "15v15", forever = "15v15" },
            { name = "Darkspear Islands", forever = "15v15" },
            { name = "Alterac Valley", era = "40v40", forever = "40v40" },
            { name = "World PvP", era = "open world", forever = "open world" },
            { name = "Stormwind raid", era = "open world", forever = "open world" },
        },
    },
}

-- "PVP" for an instance in the PvP group, "PVE" for any other listed one, "-" for none / other (Events table).
-- Looks through both games' entries, so an event created on the other game's client still gets its type.
local instanceTypes = {}
for _, g in ipairs(GROUPS) do
    for _, inst in ipairs(g.list) do instanceTypes[inst.name] = (g.group == "PvP") and "PVP" or "PVE" end
end
function addonTable.InstanceType(name)
    return name and instanceTypes[name] or "-"
end

-- WoW Forever is game version 1.60 and newer, Classic Era 1.15
local function IsForever()
    local minor = tonumber((tostring((_G.GetBuildInfo())):match("^1%.(%d+)")))
    return minor ~= nil and minor >= 60
end

-- The groups for this game: { { group, list = { { name, levels, opensAt } } } }, empty groups left out.
-- opensAt (local time of that day's start) only for an instance that is not open yet on WoW Forever.
function addonTable.InstanceGroups()
    local forever = IsForever()
    local result = {}
    for _, g in ipairs(GROUPS) do
        local list = {}
        for _, inst in ipairs(g.list) do
            local levels = forever and inst.forever or (not forever and inst.era)
            if levels then
                local opensAt = forever and inst.opens and time({ year = inst.opens[1], month = inst.opens[2], day = inst.opens[3], hour = 0 })
                table.insert(list, { name = inst.name, levels = levels, opensAt = opensAt })
            end
        end
        if #list > 0 then table.insert(result, { group = g.group, list = list }) end
    end
    return result
end
