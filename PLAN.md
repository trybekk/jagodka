# Jagodka – reported problems and sync plan

Steps 1 and 2 are implemented in v0.9.8 and not tested in game yet. The causes come from reading the code and are not confirmed in game. The numbers and the problem list below describe the state at v0.9.6.

## Reported problems

Test on 2026-10-31: guild 1 with 17 players online, guild 2 with 6 online. Only one player had a real problem so far.

| # | Problem | Status | Suspected cause |
|---|---|---|---|
| 1 | Notes from a friendly guild show `Not available - nobody from this guild answered` | Open | The answer is late or missing, see below |
| 2 | Only 8 players on the `JagodkaNetH` list in Monitoring | Open, cause unknown | Players not joined, or our reading of the list. The channel is only used by relays to find other guilds, so this alone should not break sync |
| 3 | Location missing for some players | Open, partly by design | Rosters carry no location, so players from other guilds without the addon have none. A player with the addon has none if they dropped off the online list |
| 4 | Rosters update slowly | Open | Relay queue overload, see below |

### Notes (problem 1)

Possible causes:
- **Late answer (main suspect):** the relay sends `NOTE` with low priority, the client waits 4 s and then rejects a later answer.
- **60 s limit:** a second hover within a minute sends no request and shows the message at once.
- **Relay does not know the requester:** their status packet has not arrived, so the request is skipped silently.
- **Relay has no such player:** for example, its guild roster has not loaded yet. It does not answer.
- **No relay known:** nobody from that guild is on the online list, so no request goes out.

### Relay queue (problems 3 and 4)

A relay sends about 1 packet per second, so about 60 per minute. Everything from another guild passes through two relays.
- Status packets alone take about 24 of those 60 for each relay at 23 players.
- A full roster of a 500-member guild is about 45 packets. It is sent to the whole guild, then forwarded and reposted, which makes about 90 packets per minute on a relay when it repeats every minute.
- Status packets wait in the same low-priority queue. After 150 s without a signal a player drops off the online list and loses their version and location, and their packets are ignored.

## Plan

### Step 1: small fixes (done in 0.9.8)

1. **Notes:** send `NOTE` with high priority, accept late answers, and ask again after 10 s instead of 60 s.
2. **Status packets:** forward `PING` and `PONG` ahead of rosters.
3. **Channel list:** names expire after a time, instead of the list being cleared on every read.
4. **Monitoring:** the Network view lists addon players missing from the channel.

### Step 2: less roster traffic (done in 0.9.8)

Answer a roster request with a whisper to the player who asked, instead of sending it to the whole guild. This bypasses both relays and should be the biggest gain. Three or more requests at once still get one send to the guild.

Safeguards added in 0.9.9: a player asks again for a roster that did not arrive whole, a forwarded online signal replaces an older one still queued, and a sender with a long low-priority queue does not add a whispered roster.

### Step 3: measure

Repeat the test with a similar number of players and read `Queue` on the relays. Since 0.10.0, record the session with `Preserve logs` and analyze the saved file.

### Step 4: only if the low queue keeps growing

Split traffic between several relays in each guild, chosen from the packet's sender, so each carries a different part.
- Plain backup relays do not help: the next relay already takes over automatically, and the limit still applies to the one sending.
- Risks: clients can briefly disagree on the relays, which can duplicate or lose packets; everyone needs the new version; a full roster from one sender still uses a single relay.

## Security problems (reported 2026-11-03)

Confirmed by reading the code at 0.10.0. Fixed one step at a time, each tested with a recorded log before the next.

| # | Problem | Status |
|---|---|---|
| S1 | A relay on 0.9.6 posts shared chat to /g as its own character | Fixed in 0.9.7, not released yet |
| S2 | A relay's queue has no limit; anyone can whisper it packets signed with their own name | Open, stage 2 |
| S3 | `Testowo` is on the guild list; whoever founds it becomes an officer of the community | Fixed in 0.10.0 |
| S4 | Rank comes from the player's own status packet, also in our own guild; rank names with "master", "officer", "oficer" or "lider" count as officers | Open, stage 3 |
| S5 | A stranger can claim another listed guild, become its relay for us and get the shared chat, history, rosters and notes | Open, stage 4. The game gives no way to check another guild's members, except maybe `/who` |
| S6 | Forwarded mutes, event edits, removals and kicks are accepted from any known member, whoever they name as the author | Open, stage 4 |

Stages: 1 test and release 0.10.0; 2 S2 (low risk); 3 S4 (medium risk); 4 S5 and S6, each separately (high risk: they can break guild discovery and sync).

## Test plan for 0.10.0 (stage 1)

Goal: confirm the untested changes from 0.9.7 to 0.10.0 before release, and record the first logs.

### Before the test
- Testers get 0.10.0 (commit and push, or the files directly) and **restart the game**, because the `.toc` has a new line.
- As many players as possible on 0.10.0, in both guilds. A relay on 0.9.6 still posts shared chat to /g, and the relay is whoever is first alphabetically, so it cannot be chosen.
- Recording: you, plus an officer of the other guild if possible. Turn on `Preserve logs` right after login.
- About 2-3 h at a busy time, with `/reload` once an hour.

### What to check
| # | Area | How | Expected |
|---|---|---|---|
| 1 | Chat | Write in the addon tab and in the `Jagódki:` input | The message reaches the other guild |
| 2 | Long message | A message over about 135 characters | It arrives whole in the other guild, also in history after `/reload` |
| 3 | /g | Write on /g, and on the shared chat | Nothing passes between /g and the shared chat in either direction |
| 4 | Notes | Hover a member of the other guild | The note appears within a few seconds |
| 5 | Online list | Watch the Network view during the test | Nobody still playing turns orange or drops off |
| 6 | Rosters | A player logs in or does `/reload` | The other guild's roster arrives within about 1-2 min |
| 7 | Events | Sign up for an event | The other guild sees it within about 5 s |
| 8 | Monitoring | Network view, Preserve logs | Times in minutes and hours, the button counts entries |

### Write down
- The time of each problem and who had it, e.g. "21:40 Kapucyn no note from Bezimienny".
- Messages in Monitoring: `Roster not received after 2 retries`, `Queue busy`, `still queued, replaced`.

### Afterwards
Turn off recording, `/reload`, and send `WTF\Account\<account>\<server>\<character>\SavedVariables\jagodka.lua` with the notes. Release 0.10.0 if the analysis finds nothing blocking.

## Feedback to collect

For each problem:
- The addon version of the affected player.
- The `Queue` line from Monitoring on the relay. A `low` value in the tens or hundreds with a high `oldest` confirms overload.
- Log entries `Ignored ... sender not known yet`, and `No longer online` for players who are still in game.
- For a player missing from the channel list: the result of `/dump GetChannelName("JagodkaNetH")`. `0` means not joined. A higher number means they joined, so the problem is in how we read the list.

For a missing note, compare the `Presence` log of the asking player and of the other guild's relay (its name is in the Network view):

| In the log | Meaning |
|---|---|
| No `TX ... note request` from the asking player | The request was not sent (60 s limit or no relay known) |
| No `RX ... note request` on the relay | The request did not arrive, for example the relay is out of date |
| `RX` on the relay, but no `TX ... public note` | The relay does not know the requester or has no such player |
| `TX ... public note` on the relay, and `RX` over 4 s after the request | Late answer |
