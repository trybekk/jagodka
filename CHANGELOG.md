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
