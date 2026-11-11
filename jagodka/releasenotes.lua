-- ============================================================================
-- RELEASE NOTES: every version's notes for players (the same words as RELEASE_NOTES.md on CurseForge)
-- ============================================================================
--  * One source for the "Release Notes" tab (every version listed here, newest first) and the
--    "what's new" window after an update (update.lua: ReleaseNotes.Get).
--  * An entry: { version, lines, title }; the title shows next to the version in the tab.
--  * Lines: a plain line is a point (a small berry before it, its lines indented); "# Heading" is a section
--    heading; "! text" is an important line (orange, no berry), e.g. "Everyone should update".
--  * With every release: add the version's section here, copied from RELEASE_NOTES.md.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local CreateFrame = _G.CreateFrame
local GetAddOnMetadata = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
local ipairs, tonumber, tostring = _G.ipairs, _G.tonumber, _G.tostring
local table, math = _G.table, _G.math

local ReleaseNotes = {}
addonTable.ReleaseNotes = ReleaseNotes

-- Newest first: { version, lines, title }
local LIST = {
    { "1.0.1", {
        "# Security",
        "Only characters in our guilds are on the community chat: an alt outside our guilds no longer gets onto the chat channel, so it can neither read nor write there.",
        "Messages on the community chat from players who are not in any of our guilds are no longer shown at all.",
        "New members of our guilds are still seen at once: their messages also go through the guilds, and their names reach everyone's lists within minutes.",
    }, "community chat only for our guilds" },
    { "1.0.0", {
        "# New",
        "Armory links now open Sixty Upgrades, the armory most of us use.",
        "Copy name: right click a player in the Roster and copy their \"First Surname\" in one click - handy for invites, trades and Discord.",
        "After every update a small window shows what is new, once, with a little fanfare.",
        "New Release Notes tab: the notes of every version since the very first one.",
        "# Under the hood",
        "Version lists between guilds take half the packets: players are grouped by version, about 11 per packet instead of 6.",
    }, "out of beta" },
    { "0.15.6", {
        "# New",
        "Filters in the Roster: guild and professions (tick several), rank, class, location and addon version; the search box looks at names.",
        "Filters in Events: guild, type (PvE / PvP), instance, when (today, tomorrow, next 7 days) and your own sign-ups.",
        "Filters in LFG: activity, role (tick several), guild and class.",
        "Signing up for an event posts a short note on the community LFG chat, with an [Open event] link, so everyone sees something is going on.",
        "Whisper someone from a guild where nobody with the addon is online, and they show online in your Roster for 20 minutes, marked (whisper).",
        "Help: two new step-by-step guides (find someone with a profession; find a group in LFG) and every section brought up to date.",
        "# Under the hood",
        "Addon versions of all our guilds now really reach the Roster: any player with this version sends their guild's list - only the changes, every 3 minutes, behind the chat.",
        "# Officers",
        "Monitoring counts only real problems as errors; the server's INVALID_NAME after login no longer counts.",
        "The log shows the version lists sent and received, to check them against the Roster.",
    }, "filters everywhere, sign-ups on the LFG chat" },
    { "0.15.5", {
        "# New",
        "The chat tabs show how many players read them, e.g. \"General (287)\"; hover a tab for details.",
        "The Roster shows the addon version of players in all our guilds, not only your own.",
        "Hover a guild in the right column to see how many there have the addon, and which versions.",
        "A short note after updating tells you what is new.",
        "Help: a new FAQ entry about the chat channel.",
        "# Under the hood",
        "Calmer chat channel joins when the server refuses them: after 1, 2, 4 and 8 minutes, then every half hour.",
        "# Officers",
        "One \"Officer actions...\" menu instead of six buttons, grouped and with a tooltip on each.",
        "A list of players with an outdated addon, by guild, so you can ask them by name to update.",
        "Fewer false alarms: chat channel refusals are treated as information and reported every 30 minutes.",
    }, "reader counts, versions of all guilds" },
    { "0.15.4", {
        "! Everyone should update: WoW Forever keeps players on different parts of the server, and the community chat now reaches all of them.",
        "# Fixes",
        "Your messages on the community chat (General, Trade, LFG) now reach everyone, whichever part of the server they are on: every message also goes through the guilds, and nobody sees it twice. The officers chat too.",
        "Your chat settings (Settings > Chats) and your LFG listing are no longer lost after logging out: they are kept by character name for the whole account.",
        "When the server does not let you onto the chat channel for a while, the addon tries again calmly instead of every minute; your messages reach everyone meanwhile.",
        "# Officers",
        "Monitoring shows who cannot get onto the chat channel right now, reported by their own addon.",
    }, "chat across all of WoW Forever, settings kept" },
    { "0.15.3", {
        "# Under the hood",
        "Less traffic: once nearly everyone in a guild has 0.15.3, most players send the \"I am online\" signal every 10 minutes instead of every minute - about 60% less addon traffic. Chat, events, LFG, logins and logouts stay instant.",
        "Discord names reach everyone sooner after login.",
        "Lighter saved logs for officers.",
        "# Fixes",
        "Fewer false alarms in Monitoring when the chat channel changes its owner.",
        "\"Discord: name\" shows wherever you hover a player's name, also on the chat.",
    }, "quiet online signals" },
    { "0.15.2", {
        "! Everyone should update: players whose messages nobody could see on 0.15.1 are visible again.",
        "# New",
        "Discord name: share yours in Settings > Profile. Players of our guilds see \"Discord: your name\" wherever they hover your name: your character, the chat, LFG, the Roster, Officers online and event sign-ups; they can copy it from the Roster menu.",
        "LFG hints: write on the community chat that you are looking for a group (\"LFG SFK\", \"LFM DM\", \"szukam kogoś na DM\", \"ktoś chętny na...\") and, if players are listed in LFG for the same, you see who they are with an [Open in LFG] link (only you see it).",
        "/jagodka perf: measures how much time the addon takes, for reports of stutter.",
        "# Fixes",
        "Some players' messages on the community chat were hidden from everyone on 0.15.1. Fixed.",
        "Messages typed in the community tab of your game chat now reach everyone even when the chat channel does not take them (they go through the guilds instead).",
        "A guild never shows more than 1000 members.",
        "Less stutter: the addon's timers no longer all run in the same moment.",
        "# Officers",
        "Announcement: write your own message in Monitoring; everyone with the addon sees it as a big message in the middle of the screen, with your name and a sound.",
        "Monitoring records moderation on our chat channels (mutes, kicks, moderators, owner changes).",
    }, "Discord names, LFG hints, announcements" },
    { "0.15.1", {
        "# New guild",
        "Jagódki Nadina IIl (tag [JN3]) joins the community, and the Guilds panel shows all four guilds.",
        "# Fixes",
        "Dungeons and battlegrounds: no more Lua errors (\"secret string value\"); messages the game holds back for a moment are sent again instead of lost, and after you leave the addon catches up by itself within seconds.",
        "The addon keeps working after an unexpected error: every part of it is protected, so one error no longer stops the online signal, the chat channels or the lists until /reload.",
        "A removed LFG listing no longer comes back; listings of other guilds no longer disappear while their players are still looking; the LFG Sync gets an answer more reliably.",
        "# Under the hood",
        "Rosters of the other guilds arrive faster and more often whole: they go straight to the other guilds.",
        "# Officers",
        "Every error is recorded in Monitoring with the file and line, so it can be fixed quickly.",
    }, "fixes from the first LFG week, a new guild" },
    { "0.15.0", {
        "# LFG",
        "New LFG tab: list yourself with your roles, up to 4 activities (dungeons, raids, PvP, questing in any zone, or anything) and a note. Everyone in our guilds sees it within seconds.",
        "Search, filters by activity and role, sorting and pages. Right click a player: whisper, invite to the group, or invite to one of your events.",
        "Listing yourself or changing your listing posts a short note on the community LFG chat with an [Open in LFG] link.",
        "Event invitations come as a whisper with an [Open event] link: it opens the event with the spec menu, so signing up takes one click.",
        "A listing lasts 3 hours, stays over /reload, and stays grayed for 10 minutes after its player logs out (a relog keeps it).",
        "Sync button in the LFG tab, and an LFG step on the sync bar.",
        "# Chat",
        "The community tab in your game chat can be your only chat tab: in the new Settings tab choose what else shows there - whispers, guild, officer, party, raid, say, yell, emotes, system messages and any game channel.",
        "The community Trade, LFG and officers chats can show in that tab too, live, marked [Trade], [LFG] and [Officers] in their own colors; after login or /reload their latest messages come back.",
        "Every community message in that tab starts with a blueberry, so you always see which lines are the community and which are the game's.",
        "Chat commands /jnglobal, /jntrade, /jnlfg and /jnofficers switch what you write to and it stays there; with text after them they send one message from any chat tab. Tab completes them.",
        "After a /g, a party message or a whisper, the input goes back to the community chat you chose.",
        "Works alongside other chat addons: nothing of the game's chat is replaced.",
        "# Window",
        "Right column: Events / LFG with three tabs: Signed, Other and LFG (your activities, how many others are listed for the same, how long you have waited; click to edit).",
        "New Settings tab, and small \"?\" buttons next to the features that open the right page of Help.",
        "Tables always fit the window, even with long names; remove buttons show a red X.",
        "# Under the hood",
        "Sync requests are answered by one player instead of several, and the lists redraw only when something really changed - less work with hundreds online.",
        "The community chat channel is joined again by itself when it drops.",
        "# Officers",
        "\"Officers: promote the addon\" and \"Global chat test request\": a big message with a sound on everyone's screen.",
    }, "LFG across our guilds, Settings, chat commands" },
    { "0.14.1", {
        "Your other characters show offline at once while you play this one (e.g. in Officers online).",
        "Guild member counts no longer go over 1000: players who leave a guild are removed at once.",
        "# Under the hood",
        "Much less traffic from the rosters of big guilds: parts lost on the way are asked for again instead of the whole roster; other guilds' rosters arrive faster.",
        "# Officers",
        "Turning on Preserve logs starts a fresh log at once.",
    }, "your other characters offline at once" },
    { "0.14.0", {
        "! Everyone should update: events from 0.14.0 are not visible to older versions (and old events are cleared).",
        "# Events",
        "Events rebuilt from scratch: anyone can organize an event - members 1 upcoming event at a time, officers 5. The organizer and officers edit, cancel and manage it.",
        "Sign up as Coming, Maybe or Not coming, or withdraw; a reminder with a sound 15 minutes before the start.",
        "Events disappear 5 hours after their start.",
        "The Events tab has pages, search, a Type column (PVE / PVP) and a Sync button.",
        "Instances for WoW Forever: the new dungeons, the December raids grayed out until they open, and a PvP list (battlegrounds, World PvP, Stormwind raid).",
        "The Calendar has filters (Signed up / Other) and a search.",
        "# Window",
        "Your character card at the top right: portrait, level, guild, rank, professions, experience and an Armory link.",
        "Right column: Upcoming Events, Officers online, Guilds and Classes - the whole community at a glance.",
        "New Help tab in English and Polish.",
        "Tabs renamed (Community Chat, Roster, Events, Calendar, Help) with icons; chat tabs have icons too.",
        "Roster: Armory column with a link to copy.",
        "The window stays above the game's other windows; Esc and closing the window close everything it opened.",
        "# Under the hood",
        "Much lighter sync: after login only the changes are sent.",
        "Logins and logouts of players in other guilds show within seconds; /jagodka sync runs the after-login sync again by hand.",
        "# Officers",
        "Officers chat: a new tab only for officers of all our guilds, on its own secret channel.",
        "Monitoring: Sync now, Remind outdated (a note by the minimap for players with an older addon), New chat key, New officers key, and much more detail for finding problems.",
        "# Fixes",
        "WoW Forever: fishing and cooking are read again.",
        "Players of other guilds who log out disappear from the lists at once; guilds no longer go gray for a moment.",
        "Polish letters in Help.",
    }, "events rebuilt, a whole new window" },
    { "0.13.8", {
        "Guild list: Jagódki Nadina, II, IV, V and VI.",
        "New guild members show on the shared chat at once, with a gray [?] tag until their guild's roster arrives.",
        "# Under the hood",
        "Rosters of big guilds arrive whole through the relays, so member counts of other guilds are right.",
        "Less addon traffic from professions: a change of your skills goes out at most every 10 minutes.",
    }, "guild list, whole rosters" },
    { "0.13.7", {
        "Esc closes the addon window (players asked for it).",
        "The update window points to CurseForge and plays a sound.",
        "# Under the hood",
        "Much less addon traffic with hundreds of players online: one player answers each sync request instead of dozens, and sync requests stay inside each guild.",
        "Guild rosters of other guilds arrive reliably: only the relay asks for them, and big rosters go one at a time.",
        "Long \"First Surname\" names no longer break packets on their way between guilds.",
    }, "less traffic with hundreds of players" },
    { "0.13.6", {
        "Item links (potions etc.) work on the shared chat on WoW Forever.",
        "# Under the hood",
        "Guild rosters are sent with all members, even when \"Show Offline Members\" is off in the guild window, so member counts of other guilds are right.",
        "The secret chat channel starts without an officer online; an officer confirms it later.",
    }, "whole rosters, item links" },
    { "0.13.5", {
        "The chat tab writes through the game's own chat input, with a \"Jagódki:\" prompt - no separate input that other chat addons could cover.",
        "Professions work on WoW Forever and sync faster: after login and for the page shown in Members.",
        "No more chat messages about players with an older addon version (with many players they flooded the chat).",
    }, "Jagódki: prompt on WoW Forever" },
    { "0.13.3", {
        "WoW Forever: characters are identified by first name and surname, so players with the same first name are no longer mixed up; no doubled messages, guildmates are recognized.",
        "Names show with the surname everywhere: the chat, Members, the online list and the notes.",
        "Whispers, invites and player links use the full name.",
        "Guilds created or joined during the session get the secret chat channel without a relog.",
    }, "first name and surname" },
    { "0.13.0", {
        "The shared chat moves to a secret channel that only members of our guilds can find, so it cannot be read or taken over by outsiders.",
        "No setup by hand: an officer's addon creates the secret key by itself and passes it to everyone.",
        "Officers can move everyone to a new secret channel with /jagodka key.",
        "# Officers",
        "Monitoring has a Channel filter: everything about the channels and the key in one place.",
    }, "secret chat channel" },
    { "0.12.1", {
        "The shared chat goes over the community channel straight to everyone, so it works with any number of players and no longer waits in a queue.",
        "Trade and LFG messages are marked, so they land in the right tab.",
        "No doubled messages, and one lost message no longer slows the rest of the session.",
        "Players on older versions do not see messages from 0.12, so please update.",
    }, "shared chat on the channel" },
    { "0.11.0", {
        "# Under the hood",
        "Much less addon traffic between guilds, so the shared chat keeps up with large guilds: the \"I am online\" signals stay inside each guild.",
        "Players of other guilds are recognized from the guild rosters.",
        "A player who logs in gets one answer instead of one from everyone, and a new relay announces itself at once.",
    }, "ready for large guilds" },
    { "0.10.5", {
        "# Security",
        "Officer rights are checked against the guild rosters, not the rank a player reports about themselves.",
        "Players who pretend to be in another guild are ignored, and a guild's relay may pass on only its own guild's packets.",
        "# Fixes",
        "Fixed a rare error when signing up for an event.",
    }, "officers checked against the rosters" },
    { "0.10.4", { "A new guild icon in the Guilds tab, and a tidier addon folder." }, "guild icon" },
    { "0.10.3", {
        "The update window links to the CurseForge page.",
        "The window title shows the version without \"Alpha\".",
        "Added a license file.",
    }, "ready for CurseForge" },
    { "0.10.2", {
        "Support for the WoW Forever client.",
        "The addon is listed under Guild in the AddOns list, with its own icon, and the CurseForge app recognizes it.",
    }, "WoW Forever client" },
    { "0.10.1", {
        "A window tells you when your addon is outdated, with a link to download the new version.",
        "It shows once per newer version and waits until the end of a fight.",
    }, "update window" },
    { "0.10.0", {
        "# Officers",
        "Monitoring can save its log to a file (Preserve logs), so problems can be found later, with the statistics and the Network view every minute.",
        "Clearer times and player status in the Network view.",
        "The test guild was removed from the guild list.",
    }, "saved Monitoring log" },
    { "0.9.9", {
        "Guild rosters are requested again if they did not arrive in full.",
        "Fewer delays on busy connections between guilds: an online signal waiting in a queue is replaced by a newer one.",
    }, "safeguards for busy connections" },
    { "0.9.8", {
        "Notes of players from other guilds load faster and more reliably.",
        "Players no longer drop off the online list while a busy connection catches up.",
        "Guild rosters arrive faster after login.",
    }, "notes, faster rosters" },
    { "0.9.7", {
        "The shared chat is separate from guild chat: nothing is copied between /g and the community chat.",
        "New \"Jagódki:\" input in the chat tab, to write to the community chat.",
        "Messages up to 255 bytes, like in the game's own chat; long messages arrive whole.",
        "Tidier Guilds tab with guild icons.",
    }, "shared chat separated from guild chat" },
    { "0.9.6", { "Sign-ups and event changes reach other guilds within seconds: they go ahead of bulk sync." }, "faster event sync" },
    { "0.9.5", {
        "# Officers",
        "More detailed Monitoring log: each packet's route, size and waiting time, relay changes, greetings and sync stages.",
        "A new Network view: relays and players per guild, your direct traffic and traffic per packet type.",
        "The window title shows the addon version.",
    }, "more detailed Monitoring" },
    { "0.9.4", { "Officer actions (events, mutes) wait until the first sync after login ends, so they never work on old data." }, "safe officer actions" },
    { "0.9.3", {
        "# Officers",
        "New Monitoring tab for officers: a log of every addon packet with filters, and statistics refreshed every second.",
    }, "Monitoring tab" },
    { "0.9.2", {
        "Raid leader mark on sign-ups.",
        "Player menu on sign-up lists; officers can remove a player from an event.",
        "Invite all button for officers and raid leaders.",
        "The calendar lists all events of a busy day.",
    }, "raid leaders, invite all" },
    { "0.9.1", {
        "Sign up by spec, including off-specs.",
        "Sign-up button right in the events table.",
        "Wider event details: role, name, level, spec, guild, rank and online status of each player.",
        "Officers can edit events; the newest edit wins everywhere.",
    }, "specs and event editing" },
    { "0.9.0", {
        "New events table across the whole tab and a separate event details window that can be dragged.",
        "Only the roles your class can play are offered when signing up, and sign-up lists use class colors.",
    }, "Events tab rebuilt" },
    { "0.8.9", { "Location column in the Members table: where everyone is right now, also for players without the addon in your guild." }, "location" },
    { "0.8.8", { "Professions column in the Members table, with skill levels on hover; understood in every client language and remembered for offline players." }, "professions" },
    { "0.8.7", { "Notes column in the Members table: public notes, and officer notes of your own guild for those allowed to see them." }, "notes" },
    { "0.8.6", { "Members table columns fit their content, and headers line up with the text." }, "Members table" },
    { "0.8.5", {
        "Cleaner chat format with guild tags, levels and class colors.",
        "The game chat tab is created reliably on every character, and comes back if closed.",
    }, "cleaner chat" },
    { "0.8.4", { "Removed events no longer come back from players who were offline when they were removed." }, "removed events stay removed" },
    { "0.8.3", { "One chat command: /jagodka (also /jagodka reset and /jagodka tab)." }, "one command" },
    { "0.8.2", {
        "Much faster sync after login and after quick relogs.",
        "Chat, events and rosters are shared by all characters of your account.",
    }, "faster sync" },
    { "0.8.1", { "The chat input keeps focus after sending, so you can keep typing." }, "chat input" },
    { "0.8.0", {
        "New, reliable connection between guilds: one player per guild, the relay, links it with the others.",
        "Logged-out players leave the lists at once, and the next player takes over as relay.",
    }, "new links between guilds" },
    { "0.7.8", { "Fixed \"Your guild is not on the Community list\" right after joining a guild or a loading screen." }, "guild check fix" },
    { "0.7.7", { "Fixed messages between guilds not arriving, and made the send queue safer." }, "connection fix" },
    { "0.7.6", { "Trade tab in the game chat; Shift + click inserts item, spell and profession links into the addon chat." }, "Trade and links" },
    { "0.7.5", {
        "Officers can mute players on the community chat, with a reason, synced across all guilds.",
        "Names in the addon chat are clickable.",
    }, "mutes" },
    { "0.7.4", {
        "Sync progress bar in the window header.",
        "Create events from the calendar, and invite everyone signed up with one click.",
    }, "sync bar" },
    { "0.7.3", {
        "Guilds tab with all community guilds.",
        "New Calendar tab.",
        "Events and sign-ups sync between all players.",
        "The main window can be resized, and the chat scrolls with the mouse wheel.",
        "Community chat tab in the game chat.",
    }, "guilds, calendar, event sync" },
    { "0.7.2", {
        "The Members tab shows all members of the community guilds, also offline and without the addon.",
        "Sorting, pages, search and a player menu in the Members tab.",
    }, "every member of every guild" },
    { "0.7.1", {
        "The beginning: a shared chat for all Jagódki Nadina guilds, with history after login.",
        "Events with sign-ups.",
        "Version check between players.",
    }, "the first version" },
}

-- "0.15.6" -> 15006, for comparing versions
local function Number(version)
    local a, b, c = tostring(version or ""):match("^(%d+)%.(%d+)%.(%d+)")
    if not a then return 0 end
    return tonumber(a) * 1000000 + tonumber(b) * 1000 + tonumber(c)
end

-- The lines of one version, or nil
function ReleaseNotes.Get(version)
    for _, e in ipairs(LIST) do
        if e[1] == version then return e[2] end
    end
    return nil
end

-- ============================================================================
-- DRAWING (the tab and the what's new window): paragraphs with a berry, hanging indent, headings
-- ============================================================================
local BERRY_ICON = "Interface\\AddOns\\jagodka\\Media\\blueberry_one.tga"
local BERRY = 18   -- a point's text starts this far right of a heading

-- Draws lines into parent from y (distance below parent's top) at x, width wide, reusing pool (a table kept by
-- the caller); first: the gap before the first line. Returns the y below the last line and how many rows it used.
function ReleaseNotes.Draw(parent, pool, lines, x, y, width, first, startAt)
    local n = startAt or 0
    for i, l in ipairs(lines) do
        n = n + 1
        local r = pool[n]
        if not r then
            r = { text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), icon = parent:CreateTexture(nil, "OVERLAY") }
            r.text:SetJustifyH("LEFT")
            r.text:SetSpacing(2)
            r.icon:SetSize(12, 12)
            r.icon:SetTexture(BERRY_ICON)
            pool[n] = r
        end
        local heading, important = l:match("^# (.+)$"), l:match("^! (.+)$")
        y = y + ((i == 1) and (first or 12) or (heading and 12 or 6))
        r.text:ClearAllPoints()
        r.icon:Hide()
        if heading then
            r.text:SetFontObject("GameFontNormal")
            r.text:SetWidth(width)
            r.text:SetText(heading)
            r.text:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        elseif important then
            r.text:SetFontObject("GameFontNormalSmall")
            r.text:SetWidth(width)
            r.text:SetText("|cffff9933" .. important .. "|r")
            r.text:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        else
            r.text:SetFontObject("GameFontHighlightSmall")
            r.text:SetWidth(width - BERRY)
            r.text:SetText(l)
            r.text:SetPoint("TOPLEFT", parent, "TOPLEFT", x + BERRY, -y)
            r.icon:ClearAllPoints()
            r.icon:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 1, -y + 1)
            r.icon:Show()
        end
        r.text:Show()
        y = y + r.text:GetStringHeight()
    end
    return y, n
end

-- Hides the pool's rows from index from (default: all)
function ReleaseNotes.HideRows(pool, from)
    for i = from or 1, #pool do pool[i].text:Hide() pool[i].icon:Hide() end
end

-- ============================================================================
-- THE TAB: every version listed here, newest first, in a scrolling list
-- ============================================================================
-- core.lua: c = { applyStyle }
function ReleaseNotes.Attach(panel, c)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -14)
    title:SetText("Release Notes")
    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("LEFT", title, "RIGHT", 10, 0)
    sub:SetText("what changed in each version, newest first")
    local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -40)
    box:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    if c and c.applyStyle then c.applyStyle(box) end
    local scroll = CreateFrame("ScrollFrame", "JagodkaReleaseNotesScroll", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -28, 6)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(10, 10)
    scroll:SetScrollChild(content)
    local pool, heads = {}, {}
    local laidOutWidth = nil
    local function Layout()
        local width = math.floor(scroll:GetWidth())
        if width < 100 or width == laidOutWidth then return end
        laidOutWidth = width
        content:SetWidth(width)
        -- Every entry: a version's entry is added with its release, so the list is what players have (and the
        -- upcoming release can be previewed before the .toc changes)
        local y, used, shown = 0, 0, 0
        for _, e in ipairs(LIST) do
            if Number(e[1]) > 0 then
                shown = shown + 1
                local h = heads[shown]
                if not h then
                    h = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                    h:SetJustifyH("LEFT")
                    heads[shown] = h
                end
                y = y + ((shown == 1) and 8 or 22)
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -y)
                -- "0.15.6  filters everywhere, ..." : the version in purple, its title in gray
                h:SetWidth(width - 24)
                h:SetText("|cffbf40ff" .. e[1] .. "|r" .. (e[3] and ("  |cffa0a0a0" .. e[3] .. "|r") or ""))
                h:Show()
                y = y + h:GetStringHeight()
                y, used = ReleaseNotes.Draw(content, pool, e[2], 14, y, width - 28, 8, used)
            end
        end
        for i = shown + 1, #heads do heads[i]:Hide() end
        ReleaseNotes.HideRows(pool, used + 1)
        content:SetHeight(y + 16)
    end
    -- Built when the tab is first shown, again when the window's width changes
    panel:HookScript("OnShow", function() laidOutWidth = nil Layout() end)
    scroll:HookScript("OnSizeChanged", function() if panel:IsShown() then Layout() end end)
end
