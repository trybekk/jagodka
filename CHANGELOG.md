# Jagodka – changes

# 0.7.1 – shared chat, events, versions (based on `5b4b160`)

## Files
| File | What |
|---|---|
| `most.lua` (new) | Global channel ↔ `/g` bridge: transport, relay, history, chat log |
| `instancje.lua` (new) | List of Classic Era dungeons and raids for events |
| `core.lua` | UI + bridge connection points, events, versions, safeguards |
| `jagodka.toc` | `## Version`, CallbackHandler, new files, `JagodkiChatDB` |

## Global chat
- The hidden `JagodkaWspolnota` channel connects all whitelisted guilds; each message has a unique ID, so there are no duplicates.
- The **relay** is the alphabetically first person with the addon online in a guild. It carries `/g` to the channel and posts from the channel to `/g` as `[Guild] Name: text`. Only the Ogolny tab reaches `/g`.
- **Backup relay:** if the relay does not forward a `/g` line within 2–5 s, another person with the addon does it. Duplicates are removed by content (15 s window).
- The relay is chosen using the guild roster, refreshed every 20 s, so a logged-out relay stops being relay right away.
- Chat is sorted by the time of writing (server time).
- **History:** after login the addon gets the last 30 messages; a log of 300 messages is saved in `JagodkiChatDB`.
- A message from a sender whose status packet has not arrived yet is not lost; the queue retries sending for about 30 s.
- The addon joins the channel 10 s after login and returns if removed.

## Players and guilds
- Status packet every 60 s; offline players leave the list (roster or 150 s without a signal).
- The Guilds tab shows all whitelisted guilds: the number of people online and the relay (or "no relay").
- The addon version is sent in the status packet; there is a Version column in the Members tab, and a warning on mismatch.

## Events
- Shared by all whitelisted guilds, showing the author's guild.
- Created by an officer, with a list of instances (grouped into dungeons and raids). The date (3 weeks ahead) and time (00–23, minutes every 15) are chosen from lists.
- The description is a multiline field of up to 400 bytes with a counter, sent in parts (`EV_DESC`); in the details the full description shows on mouse hover.
- The create window has an X button and closes with Esc.
- Each receiver checks permissions itself: an officer author creates, at most 10 events per person, roles only Tank/Heal/DPS, everyone signs up only themselves, and the author or any whitelisted officer removes.

## Isolation and safeguards
- No global variables (except saved data, named frames and the command).
- The main command is `/jagodka`; `/okno` works as a second name.
- A warning when the prefix cannot be registered or the channel is locked (foreign password or ban).
- Anyone claiming to be in your guild but missing from its roster is ignored.

## Old bugs fixed
Missing CallbackHandler in `.toc`, texture paths with a single `\`, `:` in event fields, unsaved minimap icon position, broken list scrolling.

## What cannot be guaranteed
- When nobody with the addon is online in a guild, its `/g` does not reach the channel (and vice versa).
- History covers only the last 30 messages; an identical line from the same person sent twice within 15 s shows once.
- In `/g` of other guilds the relay sends the message, not the author; a late line from a backup relay can land after a newer one.
- Members of **other** guilds cannot be verified, and the channel owner can ban.
- In `core.lua` at most 184 local variables are active at once out of Lua 5.1's limit of 200 (as of 0.7.4; 185 in 0.7.5, counting `do ... end` blocks). New features must go in separate files or separate functions, e.g. `BuildCalendar`, not in `do ... end` blocks.

---

# 0.7.2 – roster of all guilds in the Members tab

- New file `roster.lua` and new saved data `JagodkiRosterDB` (the last known roster of each guild).
- The **Members** tab shows all members of whitelisted guilds, including those without the addon.
  - Offline players are grayed out. A "Show offline" checkbox switches the view to online only.
  - Version column: `-` means a player without the addon.
- A guild's roster is sent by one person with the addon, the **sender**. The sender changes every 5 min, and the choice is computed the same by everyone, so traffic spreads over the whole guild. Packets have low priority.
  - A status change is `+Name` or `-Name`. A full entry `Name,W603+` (class, level, rank, status) goes only for a new member or a level or rank change.
  - The full roster goes on request from someone who logged in with data older than 10 min, and once per 30 min.
  - Everyone checks for changes every 20 s, but only the sender sends, so changing the sender does not require sending the whole roster.
- When nobody with the addon from a guild is online, its members are shown as offline (the data may be out of date).
- After login the addon waits 40 s before sending, to learn about the others first.
- The Guilds tab no longer shows the relay; it is visible only in Settings.
- Members: sorting by clicking a column header (ascending ^, descending v, a third click returns to the default order: online, guild, name) and pages of 50 people with a bar under the table: `Showing 51-100 of 312 (48 online)  [<<] [<] Page 2 / 7 [>] [>>]`.
- Members: Reset button (search, "Show offline", sorting, page 1). Right-clicking a row opens a menu with "Whisper" and "Invite to group", and Shift + left click opens a whisper at once (online players only).
- The "Online players" panel uses the same list as Members, with online players only (also without the addon). It has the same clicks (menu with "Whisper" and "Invite to group", Shift + left click) and refreshes at most once per 0.3 s, only with the window open.
- The "Online: N" counter in the window header counts the same as the panel: everyone online from all whitelisted guilds, with and without the addon.
- The `JagodkaWspolnota` channel has a password (`COMM_PASSWORD` in `most.lua`). Everyone needs 0.7.2: 0.7.1 cannot join a channel created with the password (WRONG_PASSWORD).
- English interface without Polish letters (tabs, buttons, messages, status, warnings, `.toc`). Internal protocol names (chat tabs `Ogolny`/`Handel`, `Brak`) stay unchanged, so packets remain compatible.
- Performance: the member list is recomputed only with the tab visible and at most once per 0.3 s, scrolling only redraws rows, and your own guild's roster is read at most once per 2 s.

---

# 0.7.3 – whitelist, Guilds, Calendar, event sync, window

- Whitelist: `Jagódki Nadina`, `Jagódki Nadina II`, `III`, `IV` (base name + suffixes in `core.lua`) and `Testowo`. Each new guild requires a version bump.
- The Guilds tab shows all whitelisted guilds:
  - **active** (someone with the addon is online): `Online: 12 / 87`, "Active", at the top of the list;
  - **inactive**: grayed out, with the member count from cache and the time of the last sync ("Inactive (2 h ago)" or "never synced").
- The tab refreshes itself when a roster arrives.
- After creating an event, an announcement goes to General chat (the global channel and `/g` of all guilds): `Event created by Name -> Title : Instance 05.11 20:00`.
- New **Calendar** tab (between Events and Settings):
  - A 7×6 month grid from Monday to Sunday, with `<` `>` and `Today` buttons. Today has a gold border, past days are darker, and days from adjacent months are dimmed.
  - Each day fits 3 events as `20:00 Title`. Events you signed up for are green. When there are more events, the last line shows "+N more".
  - The tooltip shows the title, time, instance, author with guild, and the T/H/D sign-up count.
  - A click opens the Events tab with that event and its sign-ups.
- After removing an event, an announcement goes to General: `Event removed by Name -> Title : Instance 05.11 20:00`.
- **Event sync** (Events and Calendar have the same data for everyone):
  - The `EV_REQ` request goes after login (about 15 s) and when opening Events or Calendar, at most every 5 min.
  - **One random person with the addon** answers, not only the author. After 1–4 s they send `EV_CLAIM`, and the others give up. Data goes to the channel with low priority, so everyone benefits.
  - Sign-ups are also synced (`EV_ROS`): only missing people are added.
  - `EV_ADD` includes the author's guild, so a forwarded event shows the right guild.
  - Removed events are remembered for 30 days, so they do not return from someone who was offline. Events more than 2 days past their date disappear on their own.
  - A forwarded event (when the author is offline) is accepted from any known whitelisted player. The author themselves must still have an officer rank.
- Main window:
  - moves only by the title bar (logo and name);
  - the handle in the bottom right corner resizes the window (from 850×620 to 1600×1100), and fonts stay the same. A larger window shows more content: more chat lines and a longer input field, more rows in Members, Guilds, the event list, sign-ups and the Online players panel, and larger calendar cells with more events per day;
  - position and size are saved in `JagodkiMinimapDB.window`;
  - `/jagodka reset` restores the default size and the center of the screen.
- In the event list "os." was replaced with "signed".
- Online players panel: player bars take the panel's full width (up to the edge without a slider), the level is aligned right, and a long name with guild is cut before the level.
- Chat scrolls with the mouse wheel (3 lines, by page with Shift, to the start or end of history with Ctrl) or with the scroll bar on the right (slider and arrows). The bar is synced with the wheel and new messages.
- New file `zakladka.lua`: an extra **"Jagodki Nadina - General" tab in the game chat**, with the same messages as General chat in the addon. Message text is dark green (`3cb43c`) to stand out from `/g`; a tab created earlier as "Jagodki Nadina" gets renamed.
  - Created once, at the first login with the addon. In the default layout (General and Combat Log) it is third, and the game remembers it afterwards.
  - After login it shows the last 30 messages, then new ones as they arrive. Names are links (click is a whisper, right click is a menu).
  - Read only: write through `/g` (the relay carries it to all guilds) or in the addon window.
  - If the player closes it, it does not return on its own; `/jagodka tab` recreates it.

Bug fixes:
- Clicking Remove caused the error `most.lua:240: attempt to compare string with number`. Cause: `GetGuildInfo("player")` as the last argument of `Most.Publish` also passed the rank name, which landed in place of the message time. The call is now in parentheses, and `Most.Publish` accepts time only as a number (otherwise it uses the current server time).

Compatibility: `EV_ADD` has a new 9th field (author's guild), `EV_ROS` and `EV_CLAIM` packets were added, and the whitelist changed. Everyone needs 0.7.3.

---

# 0.7.4 – sync bar

- New file `synchro.lua`: in the main window header, left of "Online: N", a progress bar appears: `Syncing: ✓ Channel  ⌛ Chat  ⌛ Events  ✓ Rosters`.
  - It shows only with the window open and only while something is syncing: after login or when opening Events or Calendar, when the addon requests missing events.
  - Stages: joining the channel, chat history, events and sign-ups, rosters of other guilds. The roster stage appears only when the cache is more than 10 min old.
  - A stage ends when nothing arrives for a moment (3–4 s after the last packet), when nobody answers (about 7 s), or at a hard time limit.
  - At the end the bar shows "Synced" for 4 s and disappears.
- Sync itself did not change; the bar only shows what is happening, and cached data is available at once, as before.
- Members: "Show offline" is **unchecked** by default, so only online players show. Reset also returns to this setting.
- Calendar: clicking free space in a day (outside an event) opens a menu with "Create event", which opens the create window with that day's date. The option is active only for officers and only for today and future days; for past days it is grayed out.
- Calendar: a **right click on an event** opens a menu with "Invite members (N)", "Open event" and "Cancel". Left click works as before and opens the event.
  - "Invite members" sends group invites to everyone signed up. It skips you, people already in the group and offline ones. At the end a summary appears in chat, e.g. `MC: inviting 12 (already in group: 3, offline: 2)`.
  - Only a group leader, raid assistant or someone without a group can invite.
  - When more people want in than a party has spots, the addon converts the group to a raid (at once or after the first accepted invite) and invites the rest, up to 40 people.
- Technical fix (the cause of the failure in the first "Invite members" version): Lua 5.1 allows at most **200 local variables active at once** in one function, including the main file. Variables in `do ... end` blocks also count while the block lasts. The first version of invites raised `core.lua` to about 203, so the whole file failed to compile and nothing worked.
  - The calendar is now a separate function (`BuildCalendar`) with its own limit. The peak in `core.lua` fell from 193 to 184, and the calendar function has 43 variables and about 26 references to variables outside itself (limit 60).
  - A new script `luaactive.ps1` counts the worst moment in each file and is run before every change.

---

# 0.7.5 – mute on the shared chat

- New file `wyciszenie.lua` with the `Mute` module.
- Names in the addon chat are now links:
  - left click opens a whisper,
  - right click opens a menu with "Whisper", "Invite to group", "Mute on community chat" or "Unmute", and "Cancel".
  - Mute and unmute options are visible only to people entitled to them (rules below). The menu does not open on your own name.
  - In addition, item links in the addon chat show a tooltip (`SetItemRef`).
- Blizzard tab "Jagodki Nadina - General": officers have a new "Jagodka" section with "Mute on community chat" or "Unmute" in the regular game menu on a name (right click).
  - The menu is extended through `Menu.ModifyMenu("MENU_UNIT_FRIEND")`, the official way that does not break the game menu.
  - The section appears only in this tab. If the game does not say which chat window opened the menu, the section shows in every window, still only for officers.
  - If the client does not have this API, the tab keeps the regular game menu.
- Permissions (checked by the muting client and every packet receiver):
  - An officer can **mute**, but not another officer or themselves. The GM (rank 0) can mute anyone except themselves.
  - Any officer can **unmute**.
  - An officer is rank 0 or 1, or a rank whose name contains "oficer", "officer", "master" or "lider"; these are assumptions to be confirmed.
  - The addon takes the muted person's rank from their status packet or from guild rosters, so this also works for offline people (`Roster.GetRank`). When the rank is unknown, the mute is not blocked.
- Reason: "Mute" opens a dialog with a reason field (up to 60 characters). The "Mute" button is active only after a reason is typed; Enter confirms, Esc cancels. The reason is in the packet, in sync, in the chat message and in the tooltip.
- Members: a red icon (✗) appears next to a muted person's name. On hover the tooltip shows who muted them, since when and why. The table refreshes after every mute change.
  - Right-clicking a row in Members (and in the Online players panel) now also has "Unmute" or "Mute on community chat", under the same rules as the chat menu.
- What a mute means:
  - Messages from the muted person's addon window are not sent; they get the message "You are muted ... (by X)".
  - Their `/g` lines reach neither the global channel nor `/g` of other guilds. Their own guild still sees them, because that is regular game chat.
  - Each client rejects their messages itself (`Ingest` in `most.lua`), so it does not matter which relay has an old version.
  - Their earlier messages are hidden in the addon window and the Blizzard tab; they return after unmute.
  - The officer who mutes or unmutes sends a regular message to the community chat (General), e.g. `[Guild] [Officer]: Muted X on the community chat (reason: ...)` or `Unmuted X on the community chat`. It works like "Event created by …": relays also post it to `/g` of all guilds. There is no longer a system message.
- Sync:
  - A `MUTE` packet (name, mute or unmute, time, officer, reason) is accepted only when the sender is entitled to it.
  - After login the addon sends an `MREQ` request and gets missing entries, sent by one random person (`MCLAIM`, the same pattern as chat history). This way mutes also apply to people who were offline.
  - The newer entry wins. An unmute is also an entry and is remembered for 30 days, so an old mute does not return from sync.
  - Data is in `JagodkiChatDB.mutes`.
- Limitations:
  - 0.7.4 clients do not know mutes and keep showing such messages until their users update the addon.
  - A forwarded entry is accepted from any known listed player, the same as with events.
- Limits: `core.lua` peaks at 185/200 active locals (+1 for `local Mute`); `wyciszenie.lua` has 39.

---

# 0.7.6 – chat tabs, Trade in the game chat, links

- Addon window, Chat tab: the **Raid** tab was removed. The order is now General, Trade, LFG.
  - Old Raid messages stay in the saved log but are not shown anywhere.
- **Trade** works like General, only without `/g`:
  - messages go over the global channel to all listed guilds (as they did before);
  - a new game chat tab **"Jagodki Nadina - Trade"** with text color `ffd2a05a` (sand, different from General and `/g`);
  - the tab is created automatically once, at the first login with 0.7.6, and shows the last 30 messages after login;
  - nothing reaches `/g` and nothing from `/g` reaches Trade, so guild chat is not cluttered with trading.
- `zakladka.lua` now handles a list of tabs (`TABS`: General and Trade); another can be added with one entry.
  - `/jagodka tab` recreates missing tabs.
  - The Mute/Unmute name menu works in both tabs (`Zakladka.IsOurFrame`).
- Item, spell, profession etc. links:
  - **Shift + click** on an item in a bag, a spell in the spellbook or a recipe inserts a link into the addon window's input field when that field is active (hook on `ChatEdit_InsertLink`).
  - Clicking a link in the addon window shows a tooltip, as in regular chat (`SetItemRef`, since 0.7.5).
  - The tabs in the game chat handle links themselves.
  - Links pass through the global channel and relay to `/g` unchanged. Splitting long messages never cuts a link.
- Limits: the `core.lua` peak is unchanged, 185/200.

- Diagnostics in Settings (added after 0.7.6, while looking for the bug "addon messages do not arrive, but `/g` ones do"):
  - **sent**: number of packets sent by channel, successes and failures separately (`CHANNEL ok/fail`, `GUILD …`, `WHISPER …`), plus the last API result;
  - **Received**: received packets by channel and type, e.g. `CHANNEL GMSG=3`;
  - **Packets from (5 min)**: who sent any packet in the last 5 minutes;
  - **Chat rejected**: why a chat message was rejected. `duplicate / own echo / muted` is normal, because your own messages come back from the channel.
  - The status wraps to the panel width.

---

# 0.7.7 – global channel fix (addon packets between players)

**Problem found in testing:** diagnostics showed `CHANNEL fail=127` and the last result `CHANNEL=4` (`InvalidChatType`). The game rejected all addon packets sent to the channel.
- Addon messages reached nobody; only `GUILD` got through for a few seconds after login.
- `/g` in the addon window worked, because each client reads `/g` itself.
- The cause assumed at the time: the channel was joined through `JoinTemporaryChannel`, as a temporary channel. **This was wrong:** code 4 remained after this change, and 0.8.0 describes the real cause.
- The assumption that Olympus (same client, `Interface 11509`) sends to its channel without problems was not verified. It joins through `JoinChannelByName`, and otherwise the send path is the same.

**Fixes (`most.lua`, `core.lua`):**
- The channel is joined through `JoinChannelByName(name, password)` under a **new name**, so it is created fresh as a regular channel rather than joining the old temporary one:
  - **`JagodkaNet`** for the Alliance,
  - **`JagodkaNetH`** for the Horde (factions do not connect anyway).
- The password is unchanged. The addon leaves the old `JagodkaWspolnota` channel itself.
- The channel is also hidden from chat windows after the "joined" notice, because the game may add it to a window then.
- **Queue:**
  - a packet is retried only on a temporary server limit (codes 3 and 8, or `false`);
  - a permanent error (e.g. 4) no longer blocks the queue for 30 s;
  - a packet the channel did not accept goes over `GUILD` instead, so your own guild always works. Diagnostics show this as `GUILD fallback`.
- **Security** (modeled on Olympus):
  - `CHANNEL` packets are accepted only from our channel, checked by the `localID` number from `CHAT_MSG_ADDON`;
  - `|` formatting codes are removed from data from other players. Only valid links (items, spells, professions) remain in chat text. Names, guilds and titles cannot contain colors or fake links.
  - Side effect: a link pasted into an event description shows as plain text to others.
- Version 0.7.7. Older versions stay on the old channel and send nothing through it, so everyone must update.
- Limits: `most.lua` 87, `core.lua` 185/200.

---

# 0.7.8 – "Your guild is not on the Community list" despite a listed guild

**Problem found in testing:** a player left Jagódki Nadina, was immediately accepted into `Testowo` (which is listed) and immediately sent a message. They got "Your guild is not on the Community list - message not sent.".
- Cause: `GetGuildInfo("player")` in Classic can briefly return `nil` (after a loading screen, right after joining a guild), and the addon treated `nil` as "guild not on the list".

**Fixes (`most.lua`, `core.lua`):**
- `Most.MyGuild()` remembers the last known guild name and uses it when `GetGuildInfo` briefly returns `nil` (as long as `IsInGuild()` says the player is in a guild). It also asks the game to refresh the roster.
- The relay, `/g` bridge, chat sending and event sign-up use this same function.
- When the guild name is not known yet: the message "Guild info not loaded yet - try again in a moment", and the typed message stays in the field.
- The message about a guild not on the list now gives the name the addon sees, e.g. "Your guild (Xyz) is not on the Community list".
- After a guild change (`PLAYER_GUILD_UPDATE`) the addon forgets the old name and immediately sends another PING with the new guild. Previously others saw the player in the old guild until the next PONG (up to a minute).
- Limits: `most.lua` 88, `core.lua` 186/200.

---

# 0.8.0 – new links between guilds (relays and whispers)

**Problem found in testing:** code 4 (`InvalidChatType`) came back on every character, including high-level ones.
- Cause: since patch 1.13.3 Classic blocks addons from sending packets to players' own channels. In the screenshots all received packets were from `GUILD`, so only your own guild worked.
- **Correction:** the explanations from 0.7.7 (temporary channel) and 0.7.8 (level 1) were wrong.
- Tests before the rebuild: everyone sees each other on `/chatlist JagodkaNetH`, and manual messages on the channel arrive.

**New transport (`most.lua`, `core.lua`):**
- Everyone sends packets over `GUILD`.
- A guild's relay wraps each `GUILD` packet as `FW:sender:packet` and whispers it to the relays of other guilds.
- The receiver handles the packet as sent by the original sender and reposts it to its own `GUILD`. Nobody forwards wrapped packets again, so there are no loops.
- **Chat goes this way too**, rather than as a regular channel message as the first plan assumed. `/g` lines must go by whisper anyway, because an addon cannot post to a channel by itself without the player pressing a key. One path for everything means less code and no chat filters.
- **The channel is only used to find other guilds:** every 30 s the relay reads the member list (`ListChannelByName`) and greets unknown players by whisper. The result of this read does not appear in the chat window.
- A whisper to a logged-out player: the "No player named…" message is hidden and the player leaves the online list at once, so the next person becomes relay of their guild.
- Packets now have at most 225 bytes (room for the `FW:name:` header).
- Settings: a new **Linked guilds** line (guild and its relay) and **members seen** next to the channel. In diagnostics, packets from other guilds have an `FW` prefix, e.g. `FW GMSG=3`.
- Removed from 0.7.7: sending packets to the channel, `GUILD fallback` in diagnostics, and checking the channel number on receipt (`IsOurChannel`).
- Everyone must update; older versions do not understand `FW`.
- Limits: `most.lua` 100, `core.lua` 186/200.

**Limitations:**
- Packets sent to a relay at the moment it logs out may be lost.
- The channel password no longer protects packets, because they do not go through the channel. A whisper is accepted from a sender speaking for themselves or from a known player of a listed guild.
- The queue sends about 1 packet per second (up to 10 at once), and each additional guild means another relay whisper. Heavier traffic may cause delays.

---

# 0.8.1 – chat input keeps focus after sending

- After sending a message (Enter or the Send button) the cursor stays in the field, so you can keep typing at once.
- The field loses focus after a click outside it and on Esc.
- Shift + click on an item or spell does not take focus, so inserting links works as before.
- Limits: the `core.lua` peak is unchanged.

---

# 0.8.2 – faster sync after login, quick relogs

**Reason:** in-game testing of 0.8.0 and 0.8.1 went well, but on relogs sync sometimes took a long time.

**Times after login (from the first PING):**

| What | Before | Now |
|---|---|---|
| Chat history and mutes | 10 s | 2 s |
| Events | 15 s | 4 s |
| Request for other guilds' rosters | 14 s | 6 s |
| Answer to a request (random) | 1–4 s | 0.5–2.5 s |
| A player can be relay | after joining the channel (about 10 s) | after 5 s |
| A player can send the guild roster | 40 s | 15 s |

- Joining the channel stays at 8 s (so it does not take `/1` before General), and looking for other guilds at 10 s. At 14 s a relay that found other guilds repeats its requests; this way it also works for someone alone online in their guild.
- The relay and roster sender no longer depend on the channel, because packets do not go through it.

**Less traffic:**
- One PING at login instead of two.
- The PONG answer goes by whisper only to the greeter, with a random delay of 0.2–1.5 s, and several PINGs from the same person give one answer. Previously everyone answered the whole guild and all relays.
- Events and sign-ups go by whisper only to the requester. Previously each login could send all events to everyone every 15 s.

**Quick relogs (e.g. main and alt):**
- The "X has gone offline" message immediately removes the player from the online list, so the next person becomes relay. Previously a guild could be cut off from others for up to 20 s.
- Bug fixed: after a quick return the guild roster could still say "offline", so the player disappeared from the list for up to a minute. A signal from the last 30 s now beats the roster.
- A fresh login does not treat itself as relay for the first 5 s, so it does not duplicate lines in `/g`.

**Bug from 0.8.0 fixed:** event sign-up packets (`EV_ROS`) could be too long and did not reach other guilds. The limit was lowered from 240 to 215 bytes.

**Limitations:**
- Packets waiting in the queue at logout are lost, because the game gives no time to send them. The last message sent right before logging out may not reach others.
- The game's packet limit (about 1 per second, up to 10 at once) stays unchanged, so the game does not reject packets.
- Chat, events and rosters are saved for the whole account, so an alt sees the main's data, also from another faction.
- Limits: `most.lua` 104, `core.lua` 186/200.

---

# 0.8.3 – one chat command

- The only command is now `/jagodka`, including `/jagodka reset` and `/jagodka tab`. `/okno` no longer works.
- `Testowo` stays on the whitelist for now; remove it just before release.

---

# 0.8.4 – event removals reach people who were offline

**Problem found in code review:** a removal only reached people online at that moment. Removal markers stayed on the clients that had seen the removal and were never synced. Someone who was offline kept the event and could send it to others during sync, so it came back for everyone without a marker.

**Fix (`core.lua`):**
- New `EV_RM` packet (event id and original removal time), sent by whisper to one person.
- Whoever answers `EV_REQ` also sends their removal markers, before the events.
- When someone sends an event we know was removed, we answer with its marker, so the event stops spreading.
- A marker keeps its original time, so passing it on does not extend its 30 days.
- `EV_RM` is accepted from any known whitelisted player, like a forwarded event.

**Limitations:**
- There is no server, so a marker needs someone online who has it. If an officer removes an event alone and logs out, others still see it until they sync with someone holding the marker.
- Any player from a listed guild with a modified addon could remove events this way. The same trust already applies to forwarded events and mutes.
- Everyone needs 0.8.4 for markers to spread; older versions ignore `EV_RM`.

---

# 0.8.5 – cleaner chat format, reliable game chat tabs

**Message format** (time and level are gray, the guild tag is muted purple, and the name uses the real author's class color, not the relay's):

| Where | Format |
|---|---|
| Addon window | `21:05 [JN] [60] Name: text` |
| `/g` with the addon | `[Guild chat] [JN] [60] Name: text` (the game's standard green label first) |
| Game chat tab (General) | `[JN] [60] Name: text` |
| `/g` without the addon | `[Guild chat] [Relay]: [JN] [60] Name: text` |

- Guild tags: `JN`, `JN2`, `JN3`, `JN4` and `TEST`. A guild added to the whitelist needs a tag in `GUILD_TAGS` in `bridge.lua`, otherwise it shows its full name.
- A `/g` message from a player that starts like `[JN] word: ` is treated as a bridged line and is not forwarded to other guilds.

- The `/g` marker is gone. Names stay clickable, and item links work as before.
- Level and class come from the online list and guild rosters. When the level is unknown the brackets are left out, and an unknown class uses the default color. Older messages show the current level.
- `/g` with the addon: a chat filter hides the original bridged line and prints this format. Only lines from a known addon user are changed, so someone without the addon cannot fake another author by typing such a line.
- Regular `/g` messages from your own guild look as they always did.

**Game chat tabs (`chattab.lua`):**
- Only General has a tab in the game chat. The "Jagodki Nadina - Trade" tab is gone, and one left by an older version is closed at login. Trade and LFG stay in the addon window.
- A missing General tab is created at every login, so a tab closed by the player comes back, and a duplicate with the same name is closed. Previously the "already created" flag was shared by the whole account, so alts could never get the tab.
- A closed window no longer counts as an existing tab, and `/jagodka tab` recreates a missing tab without printing the history again into an existing one.

**Limitations:**
- The relay's name cannot be hidden for players without the addon: the server sends the sender separately from the text, and their game adds it.
- Other chat addons (e.g. Prat) may display the changed `/g` lines differently.

---

# 0.8.6 – Members table: column widths and order

- The Lvl column is now before Class. The order is Name, Lvl, Class, Guild, Rank, Version.
- Each column fits its longest text, plus 16 px of padding on the right. Widths come from the whole filtered list rather than the current page, so columns do not jump between pages.
- In a narrow window the padding shrinks first (down to 6 px), and then Rank and Guild are cut.
- Headers now line up exactly with the column text (they were 5 px to the left).

---

# 0.8.7 – public and officer notes in the Members table

- New file `notes.lua` and a new **Note** column between Rank and Version, with a note icon. It is bright when a note is known or can be fetched, and dimmed otherwise. The column cannot be sorted.
- Hovering over the icon shows a small popup under it with the notes, and moving the mouse away hides it. Clicks go through to the row, so its menu also works on the icon.
- **Own guild:** both notes come directly from the game. The officer note shows only with the game's own permission (`CanViewOfficerNote`).
- **Other guilds:** public note only. Hovering whispers `NREQ` to that guild's relay, who answers with `NOTE`, at most once per minute per player. The last known note is saved in `JagodkiChatDB.publicNotes`, so it also shows when nobody from that guild is online.
- **Officer notes are never sent or saved:** a responder could not reliably check who is an officer, and saved data is shared by the whole account. They are also cleared from memory after a guild change.

**Limitations:**
- A new or changed note from another guild shows only after hovering over the icon, and only while someone with the addon from that guild is online.
- An answer needs that guild's relay on 0.8.7; otherwise the popup shows "Not available".
- Without any saved note and with nobody online from that guild, the icon is dimmed.
- Limits: `core.lua` 186/200.

---

# 0.8.8 – professions in the Members table

- New file `professions.lua` and a new **Prof** column between Note and Version, which cannot be sorted. The order is Name, Lvl, Class, Guild, Rank, Note, Prof, Version.
- The column shows icons of up to two main professions. Hovering shows all professions with skill levels, including Cooking, First Aid and Fishing, and the last seen date for offline players.
- The game gives skill levels only for your own character, so every addon sends its own in a new `PROF` packet: over `GUILD` and relays at login and after a change (checked once a minute), and by whisper in answer to a `PING`.
- The packet uses profession codes rather than names, so clients in different languages understand each other.
- Received data is saved in `JagodkiChatDB.professions`, so it also shows for offline players.

**Limitations:**
- Players without the addon show `-`, because their skills cannot be read.
- A new addon user starts with an empty list and fills it by seeing players online. There is no full sync of saved data.
- A section collapsed in the game's Skills window hides its lines, so a level there is not updated until it is expanded.
- Everyone needs 0.8.8 to send and read professions.
- Herbalism is recognized by name in English, German, French, Spanish and Russian clients. Other languages may not detect it.

---

# 0.8.9 – location in the Members table

- A new **Location** column after Class. The order is Name, Lvl, Class, Location, Guild, Rank, Note, Prof, Version. It can be sorted, the search also looks in it, and hovering shows the full name.
- **Own guild:** the location of everyone online comes from the game's roster, also for players without the addon.
- **Other guilds:** players with the addon send their location in the status packet (`PING`/`PONG`, about once a minute), so it can be up to a minute old.
- Players from other guilds without the addon and offline players show `-`.
- In a narrow window Location is cut first, then Rank and Guild.

**Limitations:**
- Zone names come in the language of the sender's client.
- Everyone in the listed guilds with the addon can see your location; there is no option to hide it yet.
- Compatibility: the status packet has a new field. Clients older than 0.8.9 cannot read the rank index from it, and fall back to the rank name for officer checks, so everyone should update.

---

# 0.9.0 – Events tab: table, details window, class-based sign-ups

- **Table:** Upcoming Events is now a table across the whole tab, built like Members. Columns: Date, Time, Event, Instance, Guild, Created by, Signed. Widths fit the content, the nearest event is first, and headers sort. Events you signed up for are green.
- **Details window:** clicking a row opens a separate window that can be dragged, with the description, sign-up list and buttons. It closes with X or Esc, and also when the tab or main window closes or the event is removed.
- **Sign-ups:** you sign up as the logged-in character, and only the roles of your class are offered, with your current role in green. Warrior: Tank, DPS. Paladin and Druid: Tank, Heal, DPS. Priest and Shaman: Heal, DPS. Hunter, Rogue, Mage and Warlock: DPS.
- A received `EV_SIGN` with a role the sender's class cannot play is rejected when the class is known.
- Sign-up lists use class colors also for offline players, from guild rosters.
- **Unchanged:** event packets, saved data, and the Calendar link. Calendar clicks open the same details window.

**Limitations:**
- There is no way to withdraw from an event yet, only to change the role.
- Sign-ups already saved with a role outside these rules stay as they are.
- Limits: `core.lua` 182/200.

---

# 0.9.1 – specs, sign-up icon, wider details, event editing

- **Sign-up by spec:** you can pick any spec of your class, including an off-spec, and the role follows from it. The role still goes in `EV_SIGN`, and the spec in a new `EV_SPEC`. Older versions keep seeing the role.
- **Your sign-up column:** a new column in the events table with a small button: `Sign up`, or your current spec in green with a `v` (e.g. `Protection v`). A click opens a menu of your specs. A sign-up from before 0.9.1 shows its role instead of a spec.
- **Details window:** wider (560 px), and the sign-up list now shows role, name, level, spec, guild, rank and online status. Data comes from the online list and guild rosters. Unknown values show `-`.
- **Editing (officers):** an Edit button in the details window opens the create form with the event's values. Saving sends a new `EV_EDIT` packet and an "Event edited by ..." message on General. The sign-ups are kept.
- **Edit sync:** each edit has a time (`rev`), and the newest one wins. `EV_REQ` answers also include edits, so people who were offline get them. An edit is accepted from the officer who made it, or forwarded by a known whitelisted player, the same trust as `EV_ADD`.

**Limitations:**
- Clients older than 0.9.1 ignore edits and specs, and keep the old event data.
- Sign-ups saved before 0.9.1 have no spec until the player signs up again.
- Limits: `core.lua` 181/200.

---

# 0.9.2 – raid leader mark, player menu and removal on sign-up lists

- **Raid leader:** a signed-up player can mark themselves with "I am the raid leader" in the details window or the sign-up menu, and take it off at any time. Several players can have it. It shows a crown next to the name, and leaders are first on the list. New packet: `EV_RL`.
- **Right click on the sign-up list:** the usual player menu (Whisper, Invite, Mute rules as before).
- **Remove from event (officers):** a new menu entry takes a player off the event, with a new `EV_KICK` packet. The removed player gets a chat message if online, and can sign up again.
- **Sync:** sign-ups now have a time, sent in `EV_ROS` with the spec and leader mark. The newest state wins, so changes reach people who were offline, and a removed player does not return from an old copy. Removals are also sent in answers to `EV_REQ`.

**Limitations:**
- Older versions ignore the leader mark and removals, and can keep showing a removed player.
- Sign-ups saved before 0.9.2 have no time, so any sign-up with a time beats them.
- A removal is accepted when forwarded by any known whitelisted player, the same trust as `EV_ADD`.

**Invite all:** a new Invite column in the events table has an `Invite all` button, visible only to officers and that event's raid leaders, and inactive when nobody else is signed up. It uses the calendar's existing invite logic: it skips you, people in the group and offline players, and converts the group to a raid when needed. "Invite members" in the calendar now follows the same permission. The game still requires the group leader or a raid assistant to invite.

**Details window layout:** the description is as tall as its text, up to 7 lines; a longer one is cut, and hovering shows it in full. The sign-up list takes the remaining space down to a fixed line, so a short description leaves no gap, and the raid leader option and buttons always stay in place.

**Calendar, many events on one day:** the "+N more" line now lists the whole day on hover, and a click opens a small window with all that day's events. Left click opens an event, right click opens its menu. It closes with a click outside, Esc, X or another click on the line.

---

# 0.9.3 – Monitoring tab

- The Settings tab is now **Monitoring**, and only players with an officer rank see it (new file `monitor.lua`). The button appears or disappears when the rank changes.
- **Log:** every addon packet sent and received (`TX` / `RX`), with time, route, packet type and player, plus errors and changes of the relay, linked guilds and channel. It contains no message contents. The last 500 entries are kept for the session, and older ones are overwritten.
- **Log controls:** filters All, Chat, Events, Rosters, Mutes, Presence and Errors; the mouse wheel scrolls 3 lines (Shift = page, Ctrl = start or end); `Latest` jumps to the newest entry; `Clear` empties the log.
- **Statistics under the log, refreshed every second:** channel state and who is on it, guild relay, linked guilds, TX and RX (packets, data, rate per minute, failures, limit hits), queues, chat log size, addon users and versions, uptime, busiest packet types, rejected packets and errors.
- While the tab is open the addon reads the channel member list every 30 s, also for a player who is not the relay.
- The old status text and its diagnostics were removed; the new tab covers them.

**Limitations:**
- The log starts at login and is not saved.
- Hiding the tab is only a client-side view: the data comes from that player's own client and packets are not restricted by it.

---

# 0.9.4 – officer actions wait for the first sync

- After login, creating, editing and removing events, removing players from events, and mute and unmute are unavailable until the first sync ends. This stops actions on old data, such as an old edit form overwriting a newer edit.
- The lock lasts at least 16 s, then until the sync stages finish, and at most 45 s, so it also ends for someone alone online.
- Create Event, Edit and Remove are gray with a hover message. Actions from menus show "Syncing - available in a moment" when clicked.
- Chat, browsing, sign-ups and Monitoring work during the lock. It applies only after login, not to later syncs.

**Limitations:**
- If nobody with newer data is online, the lock ends and the old data stays.
- Two officers editing one event at the same time can still overwrite each other: the later save wins.

# 0.9.5 – more detailed Monitoring

## Log
- Each packet shows its route (relay, repost, greeting, who it came from), what it is about, its size, and how long it waited in the queue with its retries. Message and note contents are still not logged.
- New entries: relay changes in every guild, greetings, whispers to offline players, publishing `/g` lines, backup relay takeovers, dropped duplicates, players appearing on and leaving the online list.
- Sync stages are logged with their time and packet count, or "no answer", as is the moment officer actions become available.
- Packets ignored by `core.lua` (unknown sender, guild not listed, not in the roster) are now logged.
- New `Relay` and `Sync` filters; the log keeps 1000 entries instead of 500.

## Network view
- New `Network` button: relays and online players per guild, your direct traffic with each player, players with version and last signal, channel members who have not answered, sync stages, and traffic per packet type.
- Each client sees only its own links; relays of other guilds come from the rule everyone computes.
- The buttons now take two rows, because they did not fit in the panel.

## Window
- The window title shows the version: `Jagodki Nadina - Community - Alpha-0.9.5`.

# 0.9.6 – faster event sync between guilds

- Relays now forward sign-ups, spec changes, raid leader marks, removals from events, and new, edited and removed events ahead of bulk sync, as they already did for chat. Before, these waited behind rosters and sign-up lists, on both relays.

**Limitations:**
- Both relays need this version, because each one queues forwarded packets by its own rules.
- The send limit stays at about 1 packet per second, so a burst of chat and sign-ups can still take longer.

# 0.9.7 – shared chat separated from guild chat

- **No more syncing with `/g`:** what people write in guild chat stays in their guild, and the shared chat no longer posts to `/g`. The shared chat is written only from the addon, and everyone in listed guilds sees it there.
- **Writing from the chat tab:** `Jagodki Nadina - General` has its own subtle input marked `Jagódki:`, always visible under the window and independent of other chat addons. A click on the input or the tab, or Enter, starts writing, and the message goes to the shared chat. The input keeps focus after sending, until a click elsewhere, Esc or Enter on an empty input. Item links and arrow-key history work. Text starting with `/` moves to the game's input, so `/w`, `/g` and other commands still work.
- **Relays stay:** they still link guilds by carrying addon packets. They no longer handle `/g` lines, and there is no backup relay for them.
- Event and mute announcements appear only on the shared chat.
- Copies of `/g` lines saved in the chat history by older versions are removed at login.
- **Guilds tab:** a guild tabard icon on each card, and the member counts and Active / Inactive statuses line up in columns.
- Messages on the shared chat are limited to 255 bytes, the same as the game's chat, in the addon window and the chat tab. A message that does not fit one packet is sent in parts and put back together by the receiver, also in chat history, so it shows as one message. If a part is missing after 8 s, the message shows what arrived, and a late part gets its own line.

**Limitations:**
- Everyone needs this version. An older relay still copies between `/g` and the shared chat. Its `/g` lines are rejected by this version, but shared chat messages still reach that guild's `/g`.
- Mute no longer stops anything in guild chat, only on the shared chat.
- Older versions show the parts of a long message as separate lines.
- If the tab is selected during combat, Enter opens the normal input until combat ends. Clicking the input still works.

# 0.9.8 – notes, status packets, less roster traffic

- **Notes from other guilds:** the answer now has high priority, a late answer is accepted, and with no answer you can ask again after 10 s instead of 60 s. The popup says whether nobody from that guild is online or there is no answer yet.
- **Status packets:** relays forward `PING` and `PONG` ahead of rosters, so a busy queue does not make players look offline.
- **Full rosters:** a request from a fresh login is answered by whisper to that player, which skips both relays. Three or more requests at once get one send to the guild. The send every 30 minutes stays.
- **Channel list:** names expire after 70 s instead of the list being cleared on each read, so overlapping reads no longer shorten it.
- **Monitoring:** the Network view lists addon players missing from the channel list.

**Limitations:**
- A relay needs this version to forward status packets first, and a roster sender to answer by whisper. Older versions keep the old behavior, and the two work together.
- Each whispered roster is sent separately, so two requests at once cost the sender twice the packets.
- A player who leaves the channel stays on our list for up to 70 s.

# 0.9.9 – safeguards for roster and status traffic

- **Asking again for a roster:** if a requested guild roster has not arrived whole after 70 s and someone from that guild is online, the addon asks again, up to 2 times. A roster still arriving is not asked for again.
- **Online signals:** a forwarded `PONG` still waiting in a relay's queue is replaced by a newer one from the same player, so a busy queue holds at most one per player and destination. `PING` is never replaced, because others answer it.
- **Whispered rosters:** a sender with 60 or more low-priority packets waiting does not add another whispered roster. The player gets it by asking again.
- **Monitoring:** the log shows replaced signals, rosters skipped because of a busy queue, and rosters not received after all retries.

**Limitations:**
- After the second retry the addon stops asking until the next login. The send every 30 minutes can still bring the roster.
- A roster from a guild with nobody online is not requested again until the next login.

# 0.10.0 – saved Monitoring log

- **Preserve logs:** a new button in Monitoring saves everything the log shows, as plain text, in `JagodkiMonitorDB`. It is off by default and stays on after `/reload` and the next login, until it is turned off.
- **Full picture:** while recording, the statistics and the Network view are added every 60 s, including the queue, relays, players and channel. The channel list is also read while the tab is closed.
- **Network view:** times show as minutes and hours instead of seconds, and players no longer on the addon list are marked in the direct traffic list.
- **Guild list:** the test guild `Testowo` is removed, so whoever founds a guild with that name no longer joins the community as an officer.
- **Separate file:** the log is saved per character in `WTF\Account\<account>\<server>\<character>\SavedVariables\jagodka.lua`, without chat history or rosters. `Clear saved` empties it.

**Limitations:**
- The game writes the file only on `/reload`, logout or exit, so a crash loses everything since the last write.
- The log keeps 50,000 entries, and older ones are overwritten.
- The first update needs a full game restart, because the game reads the new `.toc` line only at startup.
- The button is in the Monitoring tab, so only players who can open that tab can record.

# 0.10.1 – update window

- **Outdated addon:** when a player with a newer version is seen, a window in the middle of the screen says the addon is outdated, shows both versions and the download link. A click on the link selects it for Ctrl+C. The chat warning stays.
- **Once per version:** the window shows once per newer version in a session, and in combat it waits until the fight ends. It does not take the keyboard, so movement keys keep working.
- **Preview:** the `Update popup` button in Monitoring shows the same window.
- The link is set in `update.lua` (`DOWNLOAD_URL`).

**Limitations:**
- Only 0.10.1 and newer show the window. Older versions keep only the chat warning.
- The version comes from other players, so a newer one is noticed only when someone who has it is online.

# 0.10.2 – WoW Forever client

- **Forever:** the `.toc` lists `## Interface: 11509, 16001`. Classic Era takes `11509`, and the WoW Forever client (1.60.1) takes `16001`, so it no longer shows the addon as incompatible. The retail number `120100` from 0.10.1 is removed, because the addon is not made for retail.
- **AddOns list:** `## Category: Guild` puts the addon under a Guild header, in clients that show categories. CurseForge categories (Guild, with Chat & Communication as an extra one) are set on the project page, not in the `.toc`.
- **CurseForge:** `## X-Curse-Project-ID: 1775157` links the installed addon with its CurseForge project, so the CurseForge app can recognize and update it.
- **Icon:** the AddOns list shows `Media\blueberry_one.tga` instead of a question mark (`## IconTexture`).

**Limitations:**
- Confirmed only in the AddOns list of the Forever client. Its API may differ from Classic Era 1.15, so Lua errors there are still possible.
- A new Forever patch changes its number, and the `.toc` then needs the new one.

# 0.10.3 – ready for CurseForge

- **Download link:** the update window now points to the CurseForge page, `https://www.curseforge.com/wow/addons/jagodki-nadina-community`.
- **Window title:** shows `v0.10.3` instead of `Alpha-0.10.3`. Whether a version is alpha, beta or a release is now set on CurseForge.
- **License:** `LICENSE.txt` in the addon folder, All Rights Reserved. The bundled libraries keep their own licenses.
- **Upload zip:** `build.ps1` builds `dist\jagodka-<version>.zip` with the `jagodka` folder at its root, from the files committed to git.

**Limitations:**
- Players on 0.10.2 and older still see the GitHub link in their update window, until they update.

# 0.10.4 – guild icon and library cleanup

- **Guilds tab:** each guild card shows the `Media\blueberry_one.tga` icon instead of the guild tabard.
- **Libraries:** unused files removed from `Libs` (a duplicate `LibDataBroker-1.1.lua`, the library's own `.toc` and `.xml` files, readme and changelogs). The four libraries the minimap button needs stay.

# 0.10.5 – officers and guilds checked against the guild rosters

- **Officers by roster:** whether another player is an officer now comes from the guild roster, not from the rank they send in their status packet. For your own guild it is the game's roster, for other guilds the roster their members send. A player missing from the known roster is not an officer. This covers events (create, edit, remove, remove from an event) and mutes. The rank name rules ("oficer", "officer", "master", "lider", ranks 0 and 1) stay, but they are applied to the roster's rank names.
- **Actions passed on during sync:** an event, edit, removal from an event or mute passed on by someone else (the officer may be offline) is accepted only when the officer named in it is an officer by the rosters. Before, any known player of a listed guild could pass one on.
- **Claiming another guild:** a player who says they are in another listed guild, but is missing from that guild's whole roster received in the last 35 minutes, is ignored and taken off the online list. Until now this was checked only for your own guild. Without a recent roster of that guild nothing changes.
- **Forwarded packets:** a relay may pass on only packets of players from its own guild. A packet "from" a player who is not in the relay's guild roster is rejected (`forward of a player outside the relay's guild` in Monitoring).
- **Chat from unknown players:** a chat message from a player not known yet, who claims another listed guild but is missing from its recent roster, is rejected, as it already was for your own guild.
- **Fix:** a sign-up could cause a Lua error when the selected event was no longer on the list.

**Limitations:**
- Without the roster of an officer's guild (a fresh install, before rosters arrive) their events and mutes are not accepted yet. They arrive with the next sync, when the roster is there.
- Events and mutes from officers who have left the listed guilds or lost their rank are no longer passed on to players who do not have them yet.
- A new guild member may be ignored by other guilds until the next roster update of their guild reaches them (at most 30 minutes).
- Event removal markers passed on during sync (`EV_RM`) are still not checked: the packet does not name who removed the event. That needs a change in the packet format.
- Only versions from 0.10.5 check this. Older versions still accept everything as before.

# 0.11.0 – status traffic for large guilds (scaling, stage 1)

- **Status packets stay in the guild:** the relay no longer passes on everyone's PING/PONG to other guilds, only its own. With hundreds of players these packets alone filled the relay's queue (about 1 packet per second), and chat waited behind them. Other guilds know our players from the guild roster instead.
- **Players of other guilds known from the rosters:** a player who is not on the online list (no status packet) is trusted as a member of the listed guild whose roster has them. This applies to chat, events, sign-ups, mutes, notes, professions and rosters. Officer rights still come only from the rosters.
- **Only the relay answers a PING:** a player who logs in gets one answer, from the relay, instead of one from everyone. The rest of the guild is known from the regular status packets within a minute.
- **New relay announces itself:** a player who becomes the relay sends a status packet at once, so other guilds send to them without waiting for the next regular one.
- **Roster sender after login:** a player waits 65 s after login (was 15 s) before acting as their guild's roster sender, because guildmates are now known only from their regular status packets.
- **Greetings on the channel:** the relay greets at most 5 unknown players per read of the channel list, and skips players of guilds it is already linked with.
- **First roster of a guild:** a roster from a sender nobody knows is accepted only while there is no recent whole roster of that guild.

**Limitations:**
- Players of other guilds who are not relays no longer appear on the online list with the addon: no addon version or location for them, and they show from the roster instead.
- The Network view in Monitoring lists only players of other guilds whose status we get (their relays).
- Players on 0.10.5 and older in a guild whose relay has 0.11.0 no longer learn players of other guilds, so they ignore their events, sign-ups and mutes until they update. Chat still works for them.
- A new member of another guild is trusted only after they appear in that guild's roster here.
- Professions of others reach a fresh login from what was saved earlier, and from the relay.
- Only the first stage: sync requests, rosters and the relay's own limit are not changed yet.

# 0.12.0 – shared chat on the global channel

- **Chat on the channel:** a message typed in the addon window or the `Jagódki:` input in the chat tab goes on the global channel (`JagodkaNet` / `JagodkaNetH`) as normal chat. The server delivers it to everyone on the channel, so the chat no longer goes through the relays or waits in the addon queue. This works the same with 20 and with 3000 players.
- **Who is shown:** a channel message shows only from players of the listed guilds (online with the addon or in a guild roster). The guild label comes from there. Muted players stay hidden, as before.
- **Trade and LFG:** messages from these tabs start with `[Trade] ` or `[LFG] ` on the channel, so they are readable without the addon too, and the addon puts them in the right tab.
- **Without the channel:** when the channel is not available (not joined yet, banned, wrong password), messages go through the relays as before.
- **When the game does not let the player speak on the channel:** the server sends our own message back to us. If it does not come back within 5 s (e.g. a low-level or restricted character), the message goes through the relays, and so do all further ones until `/reload`. Monitoring logs it as an error.
- **History:** a fresh login still gets the latest messages from someone online. A message already received from the channel is not added a second time from history (same author, tab and text within 2 minutes).
- **Automatic notices** (event created, edited or removed, mutes) still go through the relays.

**Limitations:**
- Players on 0.11.0 and older do not read the channel, so they do not see messages from players on 0.12.0. Messages from them still reach players on 0.12.0.
- Anyone who knows the channel password can read the channel and write on it. Messages from players outside the listed guilds are not shown in the addon, but they are on the channel.
- A muted player is hidden only in the addon; on the channel itself their messages still go out.
- The game must accept the message from a key press or click; this needs checking in game (the addon sends it right from Enter or the Send button).
- Whether low-level characters may speak on a custom channel needs checking in game; if not, they fall back to the relays as above.
- Whether the server limits the number of players on one custom channel is not known yet.

# 0.12.1 – channel chat during fast typing

- **A lost message does not switch the whole session to the relays:** in 0.12.0 the first own message that did not come back from the channel within 5 s sent all further messages through the relays until `/reload`, so fast typing ended in long delays, also inside one guild. Now all further messages go through the relays only when none of the player's messages has come back this session (e.g. a low-level or restricted character, an error in Monitoring). When the channel already worked, only the lost message is resent through the relays (a note in Monitoring), and the next ones still go on the channel. The wait for the echo is 8 s instead of 5 s.
- **No doubles:** the same message from the same author, once from the channel and once through the relays (a late echo), shows only once. The same line typed twice on the channel still shows twice.

# 0.13.0 – secret chat channel

- **Chat channel from a secret key:** the shared chat moves to a second channel whose name and password come from a secret community key (`key.lua`). The key is not in the addon code, so someone with only the code from CurseForge cannot find the channel, read the chat or take the channel over. The public channel (`JagodkaNet` / `JagodkaNetH`) stays for finding other guilds and for players without the key.
- **No setup by hand:** an officer's client that has no key and has seen none 2 minutes after login creates one by itself. It does not matter which listed guild the officer is in. The key goes to all guilds through GUILD and the relays. If two officers create one at the same time, the newer key wins everywhere.
- **Getting the key:** the key is saved (`JagodkiChatDB.key`, shared by the characters of an account). After login a player asks their guild (`KREQ`, 10 s and 90 s after login), and the relay answers when it has a newer key. The relay also sends the key to everyone every 10 minutes, and at once when it sees an older one. Only a key from an officer by the guild rosters is accepted.
- **New key:** `/jagodka key` (officers) creates a new key, e.g. after someone left a guild. An officer's client also creates one by itself (at most every 10 minutes) when the chat channel's owner is outside the listed guilds (officers read the channel's member list every minute), or on a ban or another password.
- **Reading and writing:** with the key, messages go only on the chat channel, or through the relays when it is not available. Without the key, on the public channel, as in 0.12. Messages from both channels are shown, so messages from 0.12 still arrive.
- **Monitoring, new `Channel` filter:** everything about the channels and the key in one place: which channel each own message went on (chat channel, public channel or the relays, and why), joining and leaving the chat channel, its owner, keys received, created, ignored and sent to someone, a lost echo, bans and wrong passwords. `KEY` and `KREQ` packets show who created the key, never the key itself. The filter buttons are a bit narrower to fit one more.

**Limitations:**
- Players on 0.12.x stay on the public channel and do not see messages from players with the key. Everyone needs 0.13.0.
- The first key appears once an officer with 0.13.0 has been online for 2 minutes. Until then everyone stays on the public channel.
- Someone from our guilds can pass the key on (e.g. a former member). `/jagodka key` then moves everyone to a new channel.
- A player who was offline during a key change is on the old channel for the first seconds after login, until the new key arrives.
- A player of another guild sees a key from an officer only once that officer's guild roster has arrived; until then they stay on the public channel.

# 0.13.1 – guilds joining later (fresh server)

- **Key without a relog:** checks for the key run every minute, not only at login. An officer of a guild created during the session (e.g. on a fresh server) creates the first key 2 minutes after login, without relogging.
- **Joining a guild:** a player who joins a listed guild during the session asks it for the key 5 s later, instead of waiting for the relay's next regular send (up to 10 minutes).
- **Relay passes a new key on at once:** a relay that gets a newer key (e.g. in answer to its own request) sends it to its guild and the other relays right away. Without a key, only the relay asks again every minute; its request also reaches the other guilds.
- **Key from an officer of a guild we do not know yet:** it is remembered, the missing guild rosters are requested at once (at most every 5 minutes), and the key is accepted as soon as that officer is known. Before, this could take until the next full roster (up to 30 minutes), and guilds could stay on different channels meanwhile.
- **Only listed guilds create keys:** an officer of a guild outside the list does not create one.

# 0.13.2 – names with a surname

- **One name per player:** on clients where characters have a surname (WoW Forever), chat events and the guild roster give "Marianek Jagoda", while the game's own name and addon messages give "Marianek". The addon took them for two players. Now every name from the game drops the realm and the surname (`Most.BaseName`): channel messages, the channel member list, the guild roster (own guild, other guilds' rosters, also rosters saved earlier), notes, "has gone offline" messages and the player menu.
- **Fixes what this caused:** own messages from the channel were not recognized, so after 8 s they went through the relays as well and showed twice, and the whole session switched to the relays. Guildmates could be taken for players "not in the guild roster" and ignored.
- **Names shown with the surname:** the chat, the Members tab, the online list and the note popup show the full name (`Most.DisplayName`), learned from the guild rosters and channel messages. Rosters sent to other guilds carry the full name, so they can show it too. Whisper, invite and the player menu use the base name.

# 0.13.3 – first name and surname identify a character (WoW Forever)

- **Full name as the identifier:** on WoW Forever every character has a surname and first names repeat, so only "first name surname" is unique. 0.13.2 cut names to the first name, which mixes up two players with the same first name. Now the addon identifies every character by "Marianek Jagoda" (`Most.PlayerKey`), everywhere: online list, guild rosters, chat, events and sign-ups, mutes, notes, professions, the chat channel key, relays and forwarded packets.
- **Where the surname comes from:** the game keeps it where other clients keep the realm. `UnitName("player")` gives "Marianek", "Jagoda", senders can come as "Marianek-Jagoda", the guild roster and chat as "Marianek Jagoda". All of them become "Marianek Jagoda"; my own name is built from `UnitName` (`Most.MyName`).
- **Whispers, invites, group checks and player links** use the game's form "Marianek-Jagoda" (`Most.GameName`).
- **Members tab:** the Name column fits the longest full name (0.13.2 measured the first name only and showed the full one), with 10 px more room on the right.
- **Classic Era** (no surnames): names stay as before, without the realm.
- Rosters saved by the 0.13.2 test build are keyed by the full name again.

**Limitations:**
- Needs checking in game on Forever: whisper and invite with "Marianek-Jagoda", and that every name in the Monitoring log has the surname.
- Players on older versions identify others differently, so everyone needs 0.13.3. Data saved under first names only (old mutes, sign-ups, professions) does not match the new names.

# 0.13.4 – chat tab writes through the game's input

- **No separate input under the chat tab:** the `Jagódki:` input under "Jagodki Nadina - General" is gone. The game's own chat input showed in the same place and covered it.
- **The game's input writes on the community channel:** while the tab is selected, the game's chat input is set to the community channel (the chat channel from the key, or the public one without a key). Enter opens it as usual and the game sends the message itself; it shows in the tab and the addon window like any channel message. `/s`, `/g`, `/w` and other commands still work, and after another tab is selected the input gets back the chat type it had before. The setting follows the channel number every 5 s (e.g. after a new key) and never changes while the player is typing.
- If the community channel is not joined yet (the first seconds after login), the input stays as it was, and the tab says so once.
- **`Jagódki:` prompt:** the input's header shows `Jagódki:` instead of "[7. Jgdh26g9i7]:" (channel number and the name from the key) whenever it is set to the community channel, also after `/7` typed by hand.
- **No more "older addon version" messages:** a player with an older version is not reported at all (with many players these messages flooded the chat and slowed the game). A newer version is reported once per version, not once per player, with the update window as before.

- **Professions after login:** 10 s after login the addon asks its guild for the professions it does not have yet or has older (`PREQ`, it stays in the guild). One guildmate answers (`PCLAIM` stops the others) by whisper (`PSYNC`) with up to 300 players, the most recently updated first. Before, players who were online before us showed "Unknown - player has no addon data" until they changed a skill or relogged (since 0.11.0 only the relay answers a hello). Older versions ignore these packets.
- **More reliable:** without an answer within 25 s (the answering player logged out, a lost packet) the request is repeated, up to 2 times. 
- **Members tab asks for the shown page:** opening the tab asks at once for the professions of the players on the shown page that we do not have (`PREQN`, stays in the guild, one guildmate answers with what it knows). After a page change the page buttons are grayed out and not clickable for 1 s, and the request goes when they come back, so every page shown gets one request. The same player is asked about at most every 5 minutes, because players without the addon never have data.

**Limitations:**
- From this tab a muted player's messages still go on the channel (others' addons hide them, as before); the separate input used to refuse to send.
- The chat type of the game's input is changed by the addon; if the game ever blocks a slash command typed in this tab (e.g. /cast), switch to another tab for it and report it.

# 0.13.5 – Jagódki: prompt on WoW Forever

- **Prompt hook that works on Forever:** 0.13.4 hooked only the global `ChatEdit_UpdateHeader`, but the Forever client updates the header through each input's own `UpdateHeader` method, so "[7. Jgdh26g9i7]:" stayed. Now both are hooked, plus showing and focusing the input (one frame later, after the game's own update), for every chat window's input.
- **Own professions on newer clients:** reading them used `GetSpellInfo` and `GetSkillLineInfo`, which newer clients may not have (WoW Forever), so it stopped with a silent Lua error and nothing was saved or sent: everyone, also the player themselves, showed "Unknown - player has no addon data". Now `C_Spell.GetSpellInfo` and `GetProfessions` / `GetProfessionInfo` are used when the old functions are missing, a reading error goes to Monitoring (Errors), and the own row shows the own professions also outside a listed guild.
- **Members page buttons:** locked for 1 s after a page change (was 2 s), and the professions request for the page goes after the same 1 s.

# 0.13.6 – full guild rosters also with "show offline" off

- **Rosters with offline members:** the game gives the addon only online players when "Show Offline Members" is off in the guild window. A roster sender with that setting sent other guilds a roster without anyone offline, so they saw too few members and wrong counts (the sender changes every 5 minutes, so the count kept changing). Now the setting is turned on just for reading the roster and back off right after (`ReadGameRoster`), so the roster is always whole. It is not touched while the guild window is open; then, as before, only online players are read and the rest is kept as offline.
- Our own switch of the setting does not start another reading (its roster events are skipped for 3 s).
- **Monitoring:** every full roster sent ("Sent our full roster: N members in P parts") and received ("Full roster of guild from player: N members", with a note when the sender saw only online players).
- **Item links on the shared chat:** links were kept only in the old format (color `|cffRRGGBB`, text `[Name]`). Newer clients (WoW Forever) color links by item quality (`|cnIQ3:`) and can put a quality icon (`|A...|a`) into the link text, so the filter took them for invalid and removed their codes: potions and other items showed as plain text. Now both formats count as valid links (`Most.SanitizeChat`), and long messages are not split inside such a link. Anything else with "|" is still removed.
- **First chat channel key without an officer:** when nobody in the community has a key 2 minutes after login (plus a random 0–90 s), an officer creates one as before, or else the guild's relay creates a member's key (one player per guild), so the chat and its sync no longer wait for an officer to log in.
- **Officer's key beats a member's:** an officer's key always replaces a member's. Between members' keys the older one wins, so a member cannot move everyone to a newer key of their own. An officer who comes online confirms a member's key: the same key signed by the officer, so the channel stays the same and nobody moves. A key from a player not known from the rosters yet is kept and accepted once known, as before.
- `/jagodka key` and the automatic new key (foreign channel owner, ban, wrong password) stay officers only. A relay now also answers a key request when the asker's key differs, and the asker decides which one wins.

**Limitations:**
- Until an officer confirms it, a member's key could be replaced by a member with a modified addon (by backdating a key); the next officer online ends that. Players on 0.13.5 and older accept only officers' keys, so they join a member's key only once an officer confirms it.

# 0.13.7 – less traffic with hundreds of players (from the first big log)

The first 1.5 h log with about 900 players online (240 with the addon in one guild) showed no errors and empty queues, but most of the traffic was repeated requests and claims, and the full roster of the second guild never arrived. Changes:

- **Fewer answerers:** a sync request (chat history, events, mutes, professions) was answered by whoever's random delay ran out first, and with hundreds online dozens answered before the first claim arrived: 13 claims per history request, 21 per professions request, and the history was sent many times. Now only about 4 random guildmates with the addon try (`Most.ShouldAnswer`), and only when they have something to send.
- **Sync requests stay in the guild:** history, events and mutes are the same in every guild, so `HREQ`, `EV_REQ`, `MREQ` and their claims are no longer passed on to other guilds (only a relay's own request is, for a guild with nobody else online), like the professions requests.
- **Rosters of other guilds:** only the relay asks for them (when it has no whole roster of that guild or the last one is older than 65 minutes, at most every 5 minutes per guild, also checked every minute), and the answer always goes to everyone, so the whole guild gets it. Before, every player asked at login and with retries (over 1000 requests in 1.5 h, 2182 in the next 1.5 h), and the rosters were whispered to single players. Small changes alone (RD) no longer make a roster that never arrived whole look fresh, which is why the second guild's roster was never asked for again.
- **One full roster at a time:** a full roster of a big guild is 100+ parts, now sent every 60 minutes (was 30; changes go as deltas in between). The sender waits a random 0–15 s and skips when a guildmate already started sending it; the log showed two senders sending the same roster at once.
- **Smaller saved log:** guildmates' regular online signals are only counted in Monitoring, no longer written one line each (they were almost half of the log, about 270 lines a minute).
- **Fewer greetings:** once linked with another guild, a relay greets at most one unknown player per read of the channel list (was 5), and greets the same player again after 10 minutes (was 2). The second guild's relay had greeted the first guild's players 871 times in 1.5 h, each greeting reposted to the whole guild.
- **Update window:** no link field any more; it says a new version is available on CurseForge (update it in the CurseForge app), and plays the game's raid warning sound twice when it appears, so it is not missed.
- **Esc closes the addon window** (players' request), like the game's own windows. With the chat input focused, the first Esc only leaves the input.
- **Packet size with surnames:** rosters, chat parts and sign-up lists leave room for a relay's header with a long "First Surname" (packets up to 205 bytes instead of 225), so a forwarded packet cannot exceed the game's 255-byte limit.

**Limitations:**
- A player on a fresh install gets other guilds' rosters when their relay asks or with the next full roster (up to 30 minutes).
- Older versions still ask and answer as before until they update.

# 0.13.8 – guild list IV, V, VI; whole rosters through the relays; new members on the chat

- **Guild list:** "Jagódki Nadina", "Jagódki Nadina II", "Jagódki Nadina IV", "Jagódki Nadina V" and "Jagódki Nadina VI". "Jagódki Nadina III" is removed: the game does not allow three identical characters in a row in a guild name, so that guild could not be created and "IV" was founded instead. V and VI are on the list in advance.
- **Chat tags:** JN, JN2, JN4, JN5, JN6.

From the third big log (21:12–02:54, three guilds, 0.13.7 for about half the players at the start and most at the end): requests and claims dropped by a factor of 3–4 and the second guild's full roster finally arrived (997 members), but a big guild's roster (113–128 parts) rarely arrived whole, rosters of the own guild went out about 2.5 times an hour, professions were sent after every skill-up, and new members of the third guild were hidden on the chat.

- **Whole rosters through the relays:** parts are now collected per roster. When two senders' rosters arrive mixed (a big one takes minutes through two relays), neither starts over any more, so both can be completed. A request is answered with a full roster at most every 10 minutes (was 1), and the asking relay waits while parts are still arriving and asks again after 5 minutes (was 70 s).
- **Professions sent less often:** a change of one's own skills goes out at most every 10 minutes (the first one at once; the own row updates at once). On a fresh server skills went up every few minutes and every send reached all guilds through the relays (one player sent 99 times in 5.7 h).
- **New guild members on the chat:** a message on the chat channel from the secret key is shown also from a player not yet in the guild rosters here, with a gray [?] tag instead of the guild. Only community members know that channel. Before, the first messages of someone who had just joined a guild were hidden. The public channel still shows only players of listed guilds.

**Limitations:**
- Players on 0.13.7 and older do not know V and VI. IV was already on the list.
