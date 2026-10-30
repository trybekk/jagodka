-- ============================================================================
-- INSTANCJE CLASSIC ERA (lista do wyboru przy tworzeniu wydarzenia)
-- ============================================================================
-- Nazwy angielskie (takie jak w kliencie EU), w nawiasie zakres poziomow.
-- Zeby dodac nowa instancje, wystarczy dopisac ja do odpowiedniej grupy.
local addonName, addonTable = ...

addonTable.Instances = {
    {
        group = "Dungeony",
        list = {
            { name = "Ragefire Chasm", levels = "13-18" },
            { name = "Wailing Caverns", levels = "17-24" },
            { name = "The Deadmines", levels = "17-26" },
            { name = "Shadowfang Keep", levels = "22-30" },
            { name = "Blackfathom Deeps", levels = "24-32" },
            { name = "The Stockade", levels = "24-32" },
            { name = "Gnomeregan", levels = "29-38" },
            { name = "Razorfen Kraul", levels = "29-38" },
            { name = "Scarlet Monastery", levels = "34-45" },
            { name = "Razorfen Downs", levels = "37-46" },
            { name = "Uldaman", levels = "41-51" },
            { name = "Zul'Farrak", levels = "42-46" },
            { name = "Maraudon", levels = "46-55" },
            { name = "Sunken Temple", levels = "50-56" },
            { name = "Blackrock Depths", levels = "52-60" },
            { name = "Lower Blackrock Spire", levels = "55-60" },
            { name = "Upper Blackrock Spire", levels = "55-60" },
            { name = "Dire Maul", levels = "55-60" },
            { name = "Stratholme", levels = "58-60" },
            { name = "Scholomance", levels = "58-60" },
        },
    },
    {
        group = "Rajdy",
        list = {
            { name = "Zul'Gurub", levels = "20 os." },
            { name = "Ruins of Ahn'Qiraj", levels = "20 os." },
            { name = "Molten Core", levels = "40 os." },
            { name = "Onyxia's Lair", levels = "40 os." },
            { name = "Blackwing Lair", levels = "40 os." },
            { name = "Temple of Ahn'Qiraj", levels = "40 os." },
            { name = "Naxxramas", levels = "40 os." },
        },
    },
}
