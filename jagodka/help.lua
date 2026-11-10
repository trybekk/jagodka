-- ============================================================================
-- HELP: the Help tab, a short guide in English and Polish
-- ============================================================================
--  * Topics on the left, the chosen topic on the right (scrolls when long). Officers' topics are listed
--    only to officers (by the guild rank, the same check as everywhere): members never see them.
--  * Language dropdown at the top; the choice is kept in JagodkiChatDB.helpLang. Default: Polish on a
--    Polish client, English otherwise.
--  * Text markup in TOPICS: "# " = heading, "- " = bullet, "1. " = numbered step, *word* = highlighted,
--    "" = empty line.
--  * Text only: nothing is sent.
-- ============================================================================
local addonName, addonTable = ...

local _G = _G
local CreateFrame = _G.CreateFrame
local ipairs, table, math = _G.ipairs, _G.table, _G.math

local Help = {}
addonTable.Help = Help

local ICON_BERRY = "Interface\\AddOns\\jagodka\\Media\\blueberry_one.tga"
-- The game's default font (Friz Quadrata) has no Polish letters (ą, ę, ś, ł...) on English clients; the
-- chat font (Arial Narrow) has them, as in the addon's chat. All Help texts use it.
local FONT = "Fonts\\ARIALN.TTF"
local function UseFont(fontString, size)
    if not fontString:SetFont(FONT, size, "") then fontString:SetFontObject(_G.ChatFontNormal) end
end

-- ============================================================================
-- CONTENT
-- ============================================================================
local TOPICS = {
    {
        key = "start", icon = "Interface\\GossipFrame\\AvailableQuestIcon",
        title = { en = "Getting started", pl = "Pierwsze kroki" },
        en = {
            "The addon connects the guilds of the *Jagódki Nadina* community into one place: a shared chat, one list of all members, events with sign-ups and a calendar. Everyone with the addon sees the same things, whichever of our guilds they are in.",
            "",
            "# Opening the window",
            "- Click the *blueberry* by the minimap, or type */jagodka* in the chat. The same click or command closes it.",
            "- Move the window by dragging its *title bar*, resize it with the *bottom right corner*. The addon remembers both.",
            "- Lost the window or made it odd? */jagodka reset* brings back the default size in the middle of the screen.",
            "- *Esc* closes the window together with everything opened from it (event window, menus, confirmations).",
            "",
            "# What is where",
            "- *Tabs* at the top: Community Chat, Roster (all members), Events, Calendar, LFG, this Help and Settings. Officers also see Monitoring.",
            "- *Right column*, always visible: your character, upcoming events and LFG, officers online, guilds and classes. See the Right column topic.",
            "- *Online* in the top right corner: everyone online from all our guilds.",
            "",
            "# After logging in",
            "- The *bar* in the header shows the sync: joining the chat channel, chat history, events and guild rosters. It takes a few seconds up to a minute, then shows *Synced* and disappears.",
            "- Until then lists may be incomplete. It is normal and fills in by itself.",
            "",
            "# Updates",
            "- Update the addon in the *CurseForge* app, like any other addon.",
            "- When your version is outdated, the addon tells you: a window, or a small note next to the minimap button.",
        },
        pl = {
            "Addon łączy gildie społeczności *Jagódki Nadina* w jedno miejsce: wspólny czat, jedna lista wszystkich członków, wydarzenia z zapisami i kalendarz. Każdy z addonem widzi to samo, niezależnie od tego, w której z naszych gildii jest.",
            "",
            "# Otwieranie okna",
            "- Kliknij *jagódkę* przy minimapie albo wpisz */jagodka* na czacie. To samo kliknięcie lub komenda je zamyka.",
            "- Okno przesuwasz, ciągnąc za *pasek tytułu*, rozmiar zmieniasz *prawym dolnym rogiem*. Addon zapamiętuje jedno i drugie.",
            "- Okno zniknęło albo dziwnie wygląda? */jagodka reset* przywraca domyślny rozmiar na środku ekranu.",
            "- *Esc* zamyka okno razem ze wszystkim, co z niego otworzono (okno wydarzenia, menu, potwierdzenia).",
            "",
            "# Co gdzie jest",
            "- *Zakładki* u góry: Community Chat, Roster (wszyscy członkowie), Events, Calendar, LFG, ta pomoc i Settings. Oficerowie widzą też Monitoring.",
            "- *Prawa kolumna*, zawsze widoczna: twoja postać, najbliższe wydarzenia, oficerowie online, gildie i klasy. Zobacz temat Prawa kolumna.",
            "- *Online* w prawym górnym rogu: wszyscy online ze wszystkich naszych gildii.",
            "",
            "# Po zalogowaniu",
            "- *Pasek* w nagłówku pokazuje synchronizację: dołączenie do kanału czatu, historię czatu, wydarzenia i listy gildii. Trwa od kilku sekund do minuty, potem pokazuje *Synced* i znika.",
            "- Do tego czasu listy mogą być niepełne. To normalne i uzupełnia się samo.",
            "",
            "# Aktualizacje",
            "- Aktualizuj addon w aplikacji *CurseForge*, jak każdy inny addon.",
            "- Gdy twoja wersja jest stara, addon sam to powie: oknem albo małym okienkiem przy przycisku przy minimapie.",
        },
    },
    {
        key = "chat", icon = "Interface\\GossipFrame\\GossipGossipIcon",
        title = { en = "Community Chat", pl = "Czat społeczności" },
        en = {
            "One chat for all our guilds. Messages reach everyone with the addon at once, whichever guild they are in.",
            "",
            "# Channels",
            "- *General*: everyday talk.",
            "- *Trade*: buying, selling, crafting. Messages start with *[Trade]*.",
            "- *LFG*: looking for a group or players. Messages start with *[LFG]*.",
            "- Officers also have the *Officers* chat (see Officer tools).",
            "",
            "# Writing in this window",
            "- Pick the channel with the tabs above the chat, type in the box at the bottom and press *Enter* or *Send*.",
            "- *Shift + click* an item in your bags (or a link in any chat) to put its link in the message.",
            "",
            "# The tab in your game chat",
            "- The community chat is also the *Jagodki Nadina - General* tab in your game chat, so you can follow it without opening this window. Its lines start with the *blueberry*.",
            "- While that tab is selected, what you type in the game's input goes to the community chat: the input shows *Jagódki:*.",
            "- In *Settings > Chats* the tab can also show the community's Trade and LFG, the officers chat (officers), whispers, guild, party and other channels.",
            "- The tab missing? */jagodka tab* creates it again.",
            "",
            "# Chat commands",
            "Four commands, one per community chat:",
            "- */jnglobal*: General.",
            "- */jntrade*: Trade.",
            "- */jnlfg*: LFG.",
            "- */jnofficers*: the officers chat (officers only).",
            "*Switch the input* to a chat: type the command and press *Tab* (or a space). The input shows *Jagódki Trade:* (or LFG, Officers, or just *Jagódki:* for General) and every message goes there until you switch again.",
            "*Send one message* from any chat tab: put the text after the command, e.g. */jntrade WTS Copper Ore 5s* or */jnlfg LF tank RFC*.",
            "- After a */g*, */p* or a whisper from the community tab, the next Enter goes back to the chat you switched to.",
            "- Game commands (*/target*, */w*, */g*...) work as usual in every mode.",
            "",
            "# Who wrote it",
            "- *[JN]*, *[JN2]*, *[JN3]*, *[JN4]*: the author's guild. *[21]*: their level. The name is in the class color.",
            "- *Click a name* to whisper. *Right click* for a menu: whisper or invite to a group.",
            "- An icon by a name means the player is muted on the community chat; hover it for the reason.",
            "",
            "Messages written before you logged in arrive by themselves after login.",
        },
        pl = {
            "Jeden czat dla wszystkich naszych gildii. Wiadomości od razu docierają do wszystkich z addonem, niezależnie od gildii.",
            "",
            "# Kanały",
            "- *General*: codzienne rozmowy.",
            "- *Trade*: kupno, sprzedaż, craftowanie. Wiadomości zaczynają się od *[Trade]*.",
            "- *LFG*: szukanie grupy albo graczy. Wiadomości zaczynają się od *[LFG]*.",
            "- Oficerowie mają też czat *Officers* (zobacz Narzędzia oficera).",
            "",
            "# Pisanie w tym oknie",
            "- Wybierz kanał zakładkami nad czatem, pisz w polu na dole i naciśnij *Enter* albo *Send*.",
            "- *Shift + klik* na przedmiot w torbie (albo link na dowolnym czacie) wstawia jego link do wiadomości.",
            "",
            "# Zakładka w czacie gry",
            "- Czat społeczności to też zakładka *Jagodki Nadina - General* w czacie gry, więc możesz go śledzić bez otwierania tego okna. Jego linie zaczynają się od *jagódki*.",
            "- Gdy ta zakładka jest wybrana, to, co wpiszesz w pole czatu gry, trafia na czat społeczności: pole pokazuje *Jagódki:*.",
            "- W *Settings > Chats* zakładka może też pokazywać Trade i LFG społeczności, czat oficerów (oficerowie), szepty, gildię, grupę i inne kanały.",
            "- Brakuje zakładki? */jagodka tab* tworzy ją od nowa.",
            "",
            "# Komendy czatu",
            "Cztery komendy, po jednej na każdy czat społeczności:",
            "- */jnglobal*: General.",
            "- */jntrade*: Trade.",
            "- */jnlfg*: LFG.",
            "- */jnofficers*: czat oficerów (tylko oficerowie).",
            "*Przełączenie pola* na czat: wpisz komendę i naciśnij *Tab* (albo spację). Pole pokazuje *Jagódki Trade:* (albo LFG, Officers, a dla General samo *Jagódki:*) i każda wiadomość idzie tam, dopóki nie przełączysz dalej.",
            "*Jedna wiadomość* z dowolnej zakładki czatu: tekst po komendzie, np. */jntrade WTS Copper Ore 5s* albo */jnlfg LF tank RFC*.",
            "- Po */g*, */p* albo szepcie z zakładki społeczności następny Enter wraca na czat, na który się przełączyłeś.",
            "- Komendy gry (*/target*, */w*, */g*...) działają normalnie w każdym trybie.",
            "",
            "# Kto napisał",
            "- *[JN]*, *[JN2]*, *[JN3]*, *[JN4]*: gildia autora. *[21]*: jego poziom. Imię jest w kolorze klasy.",
            "- *Klik w imię* otwiera szept. *Prawy klik* otwiera menu: szept albo zaproszenie do grupy.",
            "- Ikonka przy imieniu oznacza, że gracz jest wyciszony na czacie społeczności; najedź na nią, żeby zobaczyć powód.",
            "",
            "Wiadomości napisane przed twoim zalogowaniem przychodzą same po wejściu do gry.",
        },
    },    {
        key = "roster", icon = ICON_BERRY,
        title = { en = "Roster", pl = "Roster (członkowie)" },
        en = {
            "Members of all our guilds in one list, also those without the addon (from the guild rosters). By default only those online.",
            "",
            "# Finding people",
            "- *Search*: type a part of a name, class, location, guild or rank. The list filters as you type.",
            "- *Show offline*: everyone, also offline (grayed out).",
            "- *Click a column header* to sort by it, again for the reverse order, a third time back to the default (online first, then guild and name).",
            "- *Reset* clears the search, Show offline and the sorting.",
            "- *Pages*: 50 people per page; the bar under the list shows how many there are and how many are online, the buttons change the page.",
            "",
            "# Columns",
            "- *Location*: where the player is now; hover a cut name to see it whole.",
            "- *Note*: the player's public guild note; hover the icon to read it (gray = no note).",
            "- *Prof*: their main professions; hover for all of them with skill levels. They load for the shown page, a moment after changing it.",
            "- *Armory*: click, and the link to the character's page on the armory site appears already selected; press *Ctrl+C* to copy it.",
            "- *Version*: their addon. Green = the same as yours, red = older, yellow = newer (then update yours). *-* = no addon.",
            "",
            "# Contacting someone",
            "- *Right click* a row: whisper or invite to a group (online players only).",
            "- *Shift + click* a row whispers at once.",
        },
        pl = {
            "Członkowie wszystkich naszych gildii na jednej liście, także ci bez addonu (z list gildii). Domyślnie tylko ci online.",
            "",
            "# Szukanie",
            "- *Search*: wpisz część imienia, klasy, lokacji, gildii albo rangi. Lista filtruje się w trakcie pisania.",
            "- *Show offline*: wszyscy, także offline (wyszarzeni).",
            "- *Klik w nagłówek kolumny* sortuje według niej, drugi klik odwraca kolejność, trzeci wraca do domyślnej (najpierw online, potem gildia i imię).",
            "- *Reset* czyści wyszukiwanie, Show offline i sortowanie.",
            "- *Strony*: 50 osób na stronę; pasek pod listą pokazuje, ile osób jest w sumie i ile online, a przyciski zmieniają stronę.",
            "",
            "# Kolumny",
            "- *Location*: gdzie gracz teraz jest; najedź na obciętą nazwę, żeby zobaczyć całą.",
            "- *Note*: publiczna notatka gildyjna gracza; najedź na ikonkę, żeby ją przeczytać (szara = brak notatki).",
            "- *Prof*: główne profesje; najedź, żeby zobaczyć wszystkie z poziomami. Wczytują się dla widocznej strony, chwilę po jej zmianie.",
            "- *Armory*: kliknij, a pojawi się zaznaczony link do strony postaci w armory; *Ctrl+C* go kopiuje.",
            "- *Version*: addon gracza. Zielona = taka jak twoja, czerwona = starsza, żółta = nowsza (wtedy zaktualizuj swój). *-* = bez addonu.",
            "",
            "# Kontakt",
            "- *Prawy klik* na wierszu: szept albo zaproszenie do grupy (tylko gracze online).",
            "- *Shift + klik* na wierszu od razu otwiera szept.",
        },
    },
    {
        key = "events", icon = "Interface\\Icons\\INV_Misc_Ticket_Darkmoon_01",
        title = { en = "Events", pl = "Wydarzenia" },
        en = {
            "Dungeons, raids and PvP of all our guilds in one list. Everyone sees every event and can sign up, whichever guild created it, and anyone can organize one.",
            "",
            "# The list",
            "- *Date*, *Time*, *Type* (PVE, PVP or - for other), *Event*, *Instance*, *Guild*, *Created by*, *Signed* (how many, with Tanks / Healers / DPS).",
            "- *Search* by event, instance, guild, creator, date or a signed up player's name: type your own name to see your events.",
            "- *Click a column header* to sort, *Reset* clears it all, 50 events per page.",
            "- *Sync* asks for the latest events and sign-ups, if something seems missing. It is gray while a sync is running and for a minute after a click.",
            "",
            "# Organizing an event",
            "- *Create Event* (or *right click a day* in the Calendar): a name, the *instance* (Dungeons, New dungeons, Raids, PvP; raids not open yet are grayed out with their opening day), the date (up to 3 weeks ahead), the time and a description.",
            "- You can have *one upcoming event* at a time (officers: 5). Once it has started, you can create the next one.",
            "- Your own event you can *edit*, *cancel*, take players off it and *invite all*. A notice goes to the community chat.",
            "- An event disappears by itself *5 hours after its start*.",
            "",
            "# Signing up",
            "- Click *Sign up* in the event's row and pick your *spec*: every spec of your class, so you can also go as an off-spec.",
            "- The button then shows your spec in green; click it again to change it.",
            "- *I am the raid leader* in the same menu, if you lead the group. More than one person can have it.",
            "- Not sure yet? *Maybe*. Cannot come? *Not coming*, so the organizer knows. *Withdraw* removes your sign-up.",
            "- *15 minutes before the start* you get a reminder with a sound (Coming and Maybe).",
            "",
            "# Details",
            "- *Click a row* for the event's window: description, instance, time and the list of who signed up, with role filters (All, Tank, Heal, DPS); *maybe* and *not coming* are marked.",
            "- *Right click* a name in the list to whisper or invite that player.",
            "",
            "# Inviting",
            "- *Invite all* (in the row or the window) invites everyone signed up who is online. Available to the organizer, officers and the event's raid leaders.",
            "- More than 5 people: the group becomes a raid by itself.",
            "",
            "Events you signed up for are green, in the list, the calendar and the right column.",
        },
        pl = {
            "Lochy, rajdy i PvP wszystkich naszych gildii na jednej liście. Każdy widzi każde wydarzenie i może się zapisać, niezależnie od tego, która gildia je utworzyła, a zorganizować wydarzenie może każdy.",
            "",
            "# Lista",
            "- *Date*, *Time*, *Type* (PVE, PVP albo - dla innych), *Event*, *Instance*, *Guild*, *Created by*, *Signed* (ilu zapisanych, z podziałem Tank / Heal / DPS).",
            "- *Search* szuka po wydarzeniu, instancji, gildii, twórcy, dacie albo imieniu zapisanego gracza: wpisz swoje imię, żeby zobaczyć swoje wydarzenia.",
            "- *Klik w nagłówek kolumny* sortuje, *Reset* czyści wszystko, 50 wydarzeń na stronę.",
            "- *Sync* prosi o najnowsze wydarzenia i zapisy, gdy czegoś brakuje. Jest szary w trakcie synchronizacji i przez minutę po kliknięciu.",
            "",
            "# Organizowanie wydarzenia",
            "- *Create Event* (albo *prawy klik na dzień* w kalendarzu): nazwa, *instancja* (Dungeons, New dungeons, Raids, PvP; rajdy jeszcze nieotwarte są szare z dniem otwarcia), data (do 3 tygodni naprzód), godzina i opis.",
            "- Możesz mieć *jedno nadchodzące wydarzenie* naraz (oficerowie: 5). Gdy się zacznie, możesz utworzyć następne.",
            "- Swoje wydarzenie możesz *edytować*, *odwołać*, usuwać z niego graczy i *zaprosić wszystkich*. Informacja idzie na czat społeczności.",
            "- Wydarzenie znika samo *5 godzin po starcie*.",
            "",
            "# Zapisy",
            "- Kliknij *Sign up* w wierszu wydarzenia i wybierz *spec*: każdy spec twojej klasy, więc możesz iść też jako off-spec.",
            "- Przycisk pokazuje wtedy twój spec na zielono; kliknij go jeszcze raz, żeby zmienić.",
            "- *I am the raid leader* w tym samym menu, jeśli prowadzisz grupę. Może to zaznaczyć więcej niż jedna osoba.",
            "- Nie wiesz jeszcze? *Maybe*. Nie dasz rady? *Not coming*, żeby organizator wiedział. *Withdraw* usuwa twój zapis.",
            "- *15 minut przed startem* dostajesz przypomnienie z dźwiękiem (Coming i Maybe).",
            "",
            "# Szczegóły",
            "- *Klik w wiersz* otwiera okno wydarzenia: opis, instancja, czas i lista zapisanych z filtrami ról (All, Tank, Heal, DPS); *maybe* i *not coming* są oznaczone.",
            "- *Prawy klik* na imię na liście: szept albo zaproszenie tego gracza.",
            "",
            "# Zapraszanie",
            "- *Invite all* (w wierszu albo w oknie) zaprasza wszystkich zapisanych, którzy są online. Dostępne dla organizatora, oficerów i raid leaderów wydarzenia.",
            "- Powyżej 5 osób grupa sama zamienia się w rajd.",
            "",
            "Wydarzenia, na które jesteś zapisany, są zielone: na liście, w kalendarzu i w prawej kolumnie.",
        },
    },
    {
        key = "calendar", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
        title = { en = "Calendar", pl = "Kalendarz" },
        en = {
            "The same events as in the Events tab, by day, a whole month at a glance.",
            "",
            "# Moving around",
            "- *<* and *>* change the month, *Today* goes back to the current one.",
            "- Today has a gold frame, past days are darker.",
            "",
            "# Filters",
            "- *Signed up*: events you signed up for. *Other*: all the rest. Untick one to hide those events.",
            "- Both are ticked each time you open the window.",
            "- *Search* (as in the Events tab) looks through all events and ignores the boxes, which turn gray. Clear the search and the boxes work again.",
            "",
            "# Events in a day",
            "- Each line shows the time and the title; yours are green.",
            "- *Hover* a line for the details: date, instance, creator and who signed up.",
            "- *Click* it to open the event. *Right click* for a menu: open the event, or invite its sign-ups (organizer, officers and raid leaders).",
            "- *+N more*: more events than fit the day. Hover for the list, click for a small window with all of them.",
            "",
            "*Right click a day* to create an event on it.",
        },
        pl = {
            "Te same wydarzenia co w zakładce Events, dzień po dniu, cały miesiąc na jednym ekranie.",
            "",
            "# Poruszanie się",
            "- *<* i *>* zmieniają miesiąc, *Today* wraca do bieżącego.",
            "- Dzisiaj ma złotą ramkę, minione dni są ciemniejsze.",
            "",
            "# Filtry",
            "- *Signed up*: wydarzenia, na które jesteś zapisany. *Other*: cała reszta. Odznacz jedno, żeby ukryć te wydarzenia.",
            "- Oba są zaznaczone przy każdym otwarciu okna.",
            "- *Search* (jak w zakładce Events) szuka we wszystkich wydarzeniach i pomija zaznaczenia, które robią się szare. Wyczyść wyszukiwanie, a zaznaczenia znów działają.",
            "",
            "# Wydarzenia w dniu",
            "- Każda linia pokazuje godzinę i tytuł; twoje są zielone.",
            "- *Najedź* na linię po szczegóły: data, instancja, twórca i zapisani.",
            "- *Kliknij*, żeby otworzyć wydarzenie. *Prawy klik* otwiera menu: otwarcie wydarzenia albo zaproszenie zapisanych (organizator, oficerowie i raid leaderzy).",
            "- *+N more*: więcej wydarzeń, niż mieści się w dniu. Najedź po listę, kliknij po okienko ze wszystkimi.",
            "",
            "*Prawy klik na dzień* tworzy wydarzenie na ten dzień.",
        },
    },
    {
        key = "lfg", icon = "Interface\\GroupFrame\\UI-Group-LeaderIcon",
        title = { en = "LFG", pl = "LFG (szukanie grupy)" },
        en = {
            "Looking for a group across all our guilds, like the game's own tool, but for our community.",
            "",
            "# Listing yourself",
            "- *List me* (top right): tick the roles you can play, add up to 4 activities and a short note.",
            "- Activities: any dungeon, raid or battleground from the list (as in Create Event), *Questing* (here, in your current zone, or any zone of the world by continent), or *Anything*.",
            "- Your listing lasts 3 hours and stays over */reload*. *My listing*, a *click* on your own row (edit) or a *right click* on it (edit or remove).",
            "- Listing yourself or changing it also posts a short notice on the community *LFG* chat with an *[Open in LFG]* link: a click opens this tab on your listing.",
            "",
            "# Finding people",
            "- The table shows everyone listed: player, level, guild, roles, what they look for and their note.",
            "- *Search* by name, guild, dungeon, zone or note; click a column to sort.",
            "- *Activity filter*: the same choices as when listing yourself: a whole group (*All: Dungeons*), one dungeon, raid or battleground, questing anywhere, here or in one zone. Players open to *Anything* show under every filter. *Role filter*: Tank, Healer or DPS. *Reset* clears it all.",
            "- Several activities show as the first one *+N*: *hover* a row to see all of them.",
            "- Write on the community chat that you are looking for a group (e.g. *LFG SFK*, *szukam kogoś na DM*): when players are listed in LFG for the same, a hint shows *for you alone* with their names and an *[Open in LFG]* link. Short names work too (DM, SFK, BFD, SM, ZF, BRD, UBRS, Strat, WSG...).",
            "- New listings show up for everyone within seconds. Someone who logs out stays on the list grayed as *(offline)* for 10 minutes (a relog or a reload), then goes. *Sync* (next to My listing) asks for the list again, at most once a minute.",
            "- *Right click* a row: whisper, invite to the group, or *Invite to my event*: pick one of your upcoming events and the player gets a whisper with an *[Open event]* link: it opens the event with the spec menu, so they sign up with one more click. *Shift + click* whispers at once.",
        },
        pl = {
            "Szukanie grupy we wszystkich naszych gildiach, jak narzędzie z gry, ale dla naszej społeczności.",
            "",
            "# Wpisanie się",
            "- *List me* (prawy górny róg): zaznacz role, które możesz grać, dodaj do 4 aktywności i krótką notkę.",
            "- Aktywności: dowolny loch, rajd albo battleground z listy (jak przy Create Event), *Questing* (tutaj, w twojej obecnej strefie, albo dowolna strefa świata według kontynentu) albo *Anything*.",
            "- Wpis trwa 3 godziny i zostaje po */reload*. *My listing*, *klik* na własnym wierszu (edycja) albo *prawy klik* na nim (edycja lub zdjęcie).",
            "- Wpisanie się albo zmiana wpisu wysyła też krótką informację na czat *LFG* społeczności z linkiem *[Open in LFG]*: kliknięcie otwiera tę zakładkę na twoim wpisie.",
            "",
            "# Szukanie ludzi",
            "- Tabela pokazuje wszystkich wpisanych: gracz, poziom, gildia, role, czego szuka i notka.",
            "- *Search* szuka po imieniu, gildii, lochu, strefie albo notce; klik w kolumnę sortuje.",
            "- *Filtr aktywności*: te same wybory co przy wpisywaniu się: cała grupa (*All: Dungeons*), jeden loch, rajd albo battleground, questowanie gdziekolwiek, tutaj albo w jednej strefie. Gracze otwarci na *Anything* pokazują się przy każdym filtrze. *Filtr roli*: Tank, Healer albo DPS. *Reset* czyści wszystko.",
            "- Kilka aktywności widać jako pierwszą *+N*: *najedź* na wiersz, żeby zobaczyć wszystkie.",
            "- Napisz na czacie społeczności, że szukasz grupy (np. *LFG SFK*, *szukam kogoś na DM*): gdy ktoś jest wpisany w LFG na to samo, *tylko ty* zobaczysz podpowiedź z imionami i linkiem *[Open in LFG]*. Działają też skróty (DM, SFK, BFD, SM, ZF, BRD, UBRS, Strat, WSG...).",
            "- Nowe wpisy pojawiają się u wszystkich w kilka sekund. Kto się wyloguje, zostaje na liście wyszarzony jako *(offline)* przez 10 minut (relog albo reload), potem znika. *Sync* (obok My listing) prosi o listę jeszcze raz, najwyżej raz na minutę.",
            "- *Prawy klik* na wierszu: szept, zaproszenie do grupy albo *Invite to my event*: wybierz jedno ze swoich nadchodzących wydarzeń, a gracz dostanie szept z linkiem *[Open event]*: otwiera wydarzenie od razu z menu speców, więc zapisuje się jednym kliknięciem więcej. *Shift + klik*: od razu szept.",
        },
    },    {
        key = "column", icon = "Interface\\GossipFrame\\PetitionGossipIcon",
        title = { en = "Right column", pl = "Prawa kolumna" },
        en = {
            "Always visible, whichever tab is open.",
            "",
            "# Your character",
            "- Portrait, name, level, race and class, guild and rank, and your professions with their skill.",
            "- The thin purple bar along the bottom is your experience (gone at the maximum level).",
            "- *Hover* the card for all the details; *Armory* gives the link to your page (Ctrl+C copies it).",
            "",
            "# Events / LFG",
            "- Three tabs: *Signed* (events you are signed up for), *Other* (other events), nearest first, and *LFG*. Opening the window always shows Signed.",
            "- *LFG*: your listing, one line per activity you are listed for, with how many others (online) are listed for the same in brackets, their names and your roles on hover (the tab shows how many, in green), how long you have waited (*ends Nm* in orange when it is about to end). *Click* any line to edit your listing (or to list yourself): the LFG tab opens with all listings, filters reset. *Right click*: change or remove.",
            "- A line shows the day and time (*Today* in green), the title and how many signed up.",
            "- *Mouse wheel* scrolls when there are more than 4; the thin bar on the right shows where you are.",
            "- *Hover* for the details, *click* to open the event.",
            "",
            "# Officers online",
            "- Officers and guild masters of all our guilds who are online, by guild and rank: who to ask for help.",
            "- *Right click* for a menu, *Shift + click* whispers.",
            "",
            "# Guilds",
            "- Each guild: online / all members, and a bar with the online share.",
            "- *active*: someone with the addon is online there, so its data is current. Gray with a time: when its data last came.",
            "",
            "# Classes",
            "- Members of all our guilds per class, online in green. Hover a class for the numbers.",
        },
        pl = {
            "Zawsze widoczna, niezależnie od otwartej zakładki.",
            "",
            "# Twoja postać",
            "- Portret, imię, poziom, rasa i klasa, gildia i ranga oraz profesje z poziomami umiejętności.",
            "- Cienki fioletowy pasek na dole to doświadczenie (znika na maksymalnym poziomie).",
            "- *Najedź* na kartę po wszystkie szczegóły; *Armory* daje link do twojej strony (Ctrl+C kopiuje).",
            "",
            "# Events / LFG",
            "- Trzy zakładki: *Signed* (wydarzenia, na które się zapisałeś), *Other* (pozostałe wydarzenia), od najbliższego, oraz *LFG*. Po otwarciu okna zawsze jest Signed.",
            "- *LFG*: twój wpis, po jednej linii na każdą aktywność, na którą jesteś wpisany, w nawiasie ilu innych (online) wpisało się na to samo, ich imiona i twoje role po najechaniu (zakładka pokazuje ich liczbę na zielono), jak długo czekasz (*ends Nm* na pomarańczowo, gdy wpis zaraz wygaśnie). *Kliknij* dowolną linię, żeby edytować wpis (albo się wpisać): otworzy się zakładka LFG ze wszystkimi wpisami i wyczyszczonymi filtrami. *Prawy klik*: zmień albo usuń.",
            "- Linia pokazuje dzień i godzinę (*Today* na zielono), tytuł i liczbę zapisanych.",
            "- *Kółko myszy* przewija, gdy jest ich więcej niż 4; cienki pasek po prawej pokazuje, gdzie jesteś.",
            "- *Najedź* po szczegóły, *kliknij*, żeby otworzyć wydarzenie.",
            "",
            "# Officers online",
            "- Oficerowie i Guild Masterzy wszystkich naszych gildii, którzy są online, według gildii i rangi: kogo pytać o pomoc.",
            "- *Prawy klik* otwiera menu, *Shift + klik* szept.",
            "",
            "# Gildie",
            "- Każda gildia: online / wszyscy członkowie i pasek z udziałem osób online.",
            "- *active*: ktoś z addonem jest tam online, więc dane są aktualne. Szara z czasem: kiedy przyszły ostatnie dane.",
            "",
            "# Klasy",
            "- Członkowie wszystkich naszych gildii według klas, online na zielono. Najedź na klasę po liczby.",
        },
    },
    {
        key = "settings", icon = "Interface\\Icons\\INV_Misc_Gear_01",
        title = { en = "Settings", pl = "Ustawienia" },
        en = {
            "Your own choices, saved for each character separately.",
            "",
            "# Chats",
            "- The *Jagodki Nadina - General* tab in your game chat always shows the community chat. In *Settings > Chats* you tick what else it shows, so you can keep just that one tab open.",
            "- *Community chats*: the community's Trade and LFG, and for officers the officers chat, each marked [Trade], [LFG] or [Officers] in its own color.",
            "- *Game messages*: whispers, guild chat (/g), guild officer chat (/o), party, raid, say, yell, emotes, system messages.",
            "- *Game channels*: every channel your character is on right now (General, Trade, LookingForGroup...).",
            "- A tick works at once, no */reload*. Nothing ticked = the tab is as before.",
            "- Community lines start with the *blueberry*; everything else looks as usual in the game (whispers pink, [Guild], [2. Trade]...).",
            "",
            "# Writing in that tab",
            "- What you type goes to the community chat (the input shows *Jagódki:*).",
            "- */g*, */p*, */w* and *R* (reply) work as usual. After such a message, the next one goes back to the community chat you switched to.",
            "- */jnglobal*, */jntrade*, */jnlfg*, */jnofficers* + *Tab* switch the input to that chat; with text after them they send it there from any tab. Details: Community Chat > Chat commands.",
            "",
            "# Profile",
            "- *Discord name*: share it if you like. Players of our guilds then see *Discord: your name* in one small line wherever they hover your name: your character in the world and on unit frames, your name on any chat (also the game's chat windows), LFG, the Roster, Officers online and event sign-ups, and can copy it with *Copy Discord name* in the Roster menu.",
            "- Saved for your account, so all your characters share it. It reaches everyone within minutes and stays; empty + *Save* stops sharing it.",
        },
        pl = {
            "Twoje własne wybory, zapisywane dla każdej postaci osobno.",
            "",
            "# Czaty",
            "- Zakładka *Jagodki Nadina - General* w czacie gry zawsze pokazuje czat społeczności. W *Settings > Chats* zaznaczasz, co jeszcze ma pokazywać, żeby trzymać otwartą tylko tę jedną zakładkę.",
            "- *Community chats*: Trade i LFG społeczności, a dla oficerów czat oficerów, każdy oznaczony [Trade], [LFG] albo [Officers] we własnym kolorze.",
            "- *Game messages*: szepty, czat gildii (/g), czat oficerski gildii (/o), grupa, rajd, say, yell, emotki, komunikaty systemowe.",
            "- *Kanały gry*: każdy kanał, na którym twoja postać teraz jest (General, Trade, LookingForGroup...).",
            "- Zaznaczenie działa od razu, bez */reload*. Nic nie zaznaczone = zakładka jak dotąd.",
            "- Linie czatu społeczności zaczynają się od *jagódki*; reszta wygląda jak zwykle w grze (szepty różowe, [Guild], [2. Trade]...).",
            "",
            "# Pisanie w tej zakładce",
            "- To, co wpisujesz, idzie na czat społeczności (pole pokazuje *Jagódki:*).",
            "- */g*, */p*, */w* i *R* (odpowiedź) działają jak zwykle. Po takiej wiadomości następna wraca na czat społeczności, na który się przełączyłeś.",
            "- */jnglobal*, */jntrade*, */jnlfg*, */jnofficers* + *Tab* przełączają pole na ten czat; z tekstem po nich wysyłają go tam z dowolnej zakładki. Szczegóły: Czat społeczności > Komendy czatu.",
            "",
            "# Profil",
            "- *Discord name*: udostępnij, jeśli chcesz. Gracze naszych gildii zobaczą *Discord: twój nick* w jednej małej linii wszędzie, gdzie najadą na twoje imię: na twoją postać w świecie i na ramkach postaci, na twoje imię na każdym czacie (także w oknach czatu gry), w LFG, w Rosterze, w Officers online i na listach zapisów na wydarzenia i skopiują go przez *Copy Discord name* w menu Rostera.",
            "- Zapisany na całe konto, więc wszystkie twoje postacie go pokazują. Dociera do wszystkich w kilka minut i zostaje; puste pole + *Save* przestaje go udostępniać.",
        },
    },    {
        key = "tips", icon = "Interface\\Icons\\INV_Misc_QuestionMark",
        title = { en = "Tips and problems", pl = "Porady i problemy" },
        en = {
            "# Something is missing",
            "- Right after login: wait for the sync bar in the header to finish.",
            "- Events missing? The *Sync* button in the Events tab.",
            "- Still nothing? */reload* and ask an officer.",
            "",
            "# The chat does not work",
            "- Do not leave the addon's chat channels: the addon joins them by itself for the shared chat.",
            "- Your messages do not show? */reload*.",
            "",
            "# Numbers differ between people",
            "- Lists of other guilds come from their players with the addon. A guild with nobody online with the addon stays gray with its last known data until someone logs in.",
            "",
            "# Commands",
            "- */jagodka*: open or close the window.",
            "- */jagodka tab*: bring back the Jagodki Nadina tab in the game chat.",
            "- */jnglobal*, */jntrade*, */jnlfg*, */jnofficers* (officers): switch the input with Tab, or add text to send it.",
            "- */jagodka reset*: default window size and place.",
            "",
            "# Updates",
            "- A window or a small note by the minimap says your addon is outdated: update it in the *CurseForge* app and */reload*.",
            "- The Roster's *Version* column shows who has which version.",
        },
        pl = {
            "# Czegoś brakuje",
            "- Zaraz po zalogowaniu: poczekaj, aż skończy się pasek synchronizacji w nagłówku.",
            "- Brakuje wydarzeń? Przycisk *Sync* w zakładce Events.",
            "- Dalej nic? */reload* i zapytaj oficera.",
            "",
            "# Czat nie działa",
            "- Nie wychodź z kanałów czatu addonu: addon sam do nich dołącza dla wspólnego czatu.",
            "- Twoje wiadomości się nie pokazują? */reload*.",
            "",
            "# Liczby różnią się u różnych osób",
            "- Listy innych gildii przychodzą od ich graczy z addonem. Gildia bez nikogo online z addonem jest szara i pokazuje ostatnie znane dane, dopóki ktoś się nie zaloguje.",
            "",
            "# Komendy",
            "- */jagodka*: otwiera i zamyka okno.",
            "- */jagodka tab*: przywraca zakładkę Jagodki Nadina w czacie gry.",
            "- */jnglobal*, */jntrade*, */jnlfg*, */jnofficers* (oficerowie): przełączanie pola Tabem albo wysyłka z tekstem.",
            "- */jagodka reset*: domyślny rozmiar i miejsce okna.",
            "",
            "# Aktualizacje",
            "- Okno albo okienko przy minimapie mówi, że addon jest stary: zaktualizuj go w aplikacji *CurseForge* i zrób */reload*.",
            "- Kolumna *Version* w Roster pokazuje, kto ma jaką wersję.",
        },
    },
    {
        key = "steps", icon = "Interface\\GossipFrame\\ActiveQuestIcon",
        title = { en = "Step by step", pl = "Krok po kroku" },
        en = {
            "The most common things, one step at a time.",
            "",
            "# Sign up for a raid or dungeon",
            "1. Open the *Events* tab (or find it in the *Calendar* or under *Upcoming Events* on the right).",
            "2. Type the instance or the event's name in *Search* to find it quickly.",
            "3. Click *Sign up* in its row.",
            "4. Pick your *spec*. The button turns green with your spec: you are signed up.",
            "5. Leading the group? Open the same menu again and tick *I am the raid leader*.",
            "",
            "# Whisper or invite someone from another guild",
            "1. Open *Roster* and type their name in *Search*.",
            "2. *Right click* the row and choose *Whisper* or *Invite to group*.",
            "3. Or *Shift + click* the row to whisper at once.",
            "",
            "# Copy a character's armory link",
            "1. Find the player in *Roster* (for yourself: the *Armory* button on your character card on the right).",
            "2. Click the *Armory* icon in their row. A box with the link opens, already selected.",
            "3. Press *Ctrl+C*. The box closes and the link is copied.",
            "4. Paste it in your browser with *Ctrl+V*.",
            "",
            "# See what is planned this week",
            "1. Open the *Calendar*.",
            "2. Untick *Other* to see only your events, or *Signed up* to see only the ones you are not in yet.",
            "3. Hover an event for the details, click it to open it.",
            "",
            "# The community chat is not showing",
            "1. Wait for the sync bar at the top of the window to finish.",
            "2. No tab in the game chat? Type */jagodka tab*.",
            "3. Still nothing: */reload*, and if it does not help, ask an officer.",
            "",
            "# Update the addon",
            "1. Open the *CurseForge* app and update *Jagodki Nadina - Community*.",
            "2. In the game type */reload* (or log in again).",
            "3. Check: the version in the window's title.",
            "",
            "# Whispers and guild chat in the community tab",
            "1. Open *Settings > Chats*.",
            "2. Tick *Whispers*, *Guild chat (/g)* or anything else you want.",
            "3. They show in the *Jagodki Nadina - General* tab at once; community lines keep the blueberry.",
            "",
            "# Sell something on the community Trade from the game chat",
            "1. Select the *Jagodki Nadina - General* tab in your game chat.",
            "2. Type */jntrade* and press *Tab*: the input shows *Jagódki Trade:*.",
            "3. Write your offer and press *Enter*. Next messages go to Trade too.",
            "4. Back to General: */jnglobal* + *Tab*. One message only: */jntrade WTS ...* from any tab.",
        },
        pl = {
            "Najczęstsze sprawy, krok po kroku.",
            "",
            "# Zapis na rajd albo loch",
            "1. Otwórz zakładkę *Events* (albo znajdź wydarzenie w *Calendar* lub w *Upcoming Events* po prawej).",
            "2. Wpisz instancję albo nazwę wydarzenia w *Search*, żeby szybko je znaleźć.",
            "3. Kliknij *Sign up* w jego wierszu.",
            "4. Wybierz swój *spec*. Przycisk zrobi się zielony z twoim specem: jesteś zapisany.",
            "5. Prowadzisz grupę? Otwórz to samo menu jeszcze raz i zaznacz *I am the raid leader*.",
            "",
            "# Szept albo zaproszenie kogoś z innej gildii",
            "1. Otwórz *Roster* i wpisz jego imię w *Search*.",
            "2. *Prawy klik* na wierszu i wybierz *Whisper* albo *Invite to group*.",
            "3. Albo *Shift + klik* na wierszu, żeby od razu napisać szept.",
            "",
            "# Kopiowanie linku do armory",
            "1. Znajdź gracza w *Roster* (siebie: przycisk *Armory* na karcie postaci po prawej).",
            "2. Kliknij ikonkę *Armory* w jego wierszu. Otworzy się okienko z linkiem, już zaznaczonym.",
            "3. Naciśnij *Ctrl+C*. Okienko się zamknie, a link jest skopiowany.",
            "4. Wklej go w przeglądarce przez *Ctrl+V*.",
            "",
            "# Co jest zaplanowane w tym tygodniu",
            "1. Otwórz *Calendar*.",
            "2. Odznacz *Other*, żeby widzieć tylko swoje wydarzenia, albo *Signed up*, żeby widzieć tylko te, na które jeszcze się nie zapisałeś.",
            "3. Najedź na wydarzenie po szczegóły, kliknij, żeby je otworzyć.",
            "",
            "# Nie widać czatu społeczności",
            "1. Poczekaj, aż skończy się pasek synchronizacji na górze okna.",
            "2. Brak zakładki w czacie gry? Wpisz */jagodka tab*.",
            "3. Dalej nic: */reload*, a jeśli to nie pomoże, zapytaj oficera.",
            "",
            "# Aktualizacja addonu",
            "1. Otwórz aplikację *CurseForge* i zaktualizuj *Jagodki Nadina - Community*.",
            "2. W grze wpisz */reload* (albo zaloguj się jeszcze raz).",
            "3. Sprawdź: wersja jest w tytule okna.",
            "",
            "# Szepty i czat gildii w zakładce społeczności",
            "1. Otwórz *Settings > Chats*.",
            "2. Zaznacz *Whispers*, *Guild chat (/g)* albo cokolwiek innego.",
            "3. Pojawią się od razu w zakładce *Jagodki Nadina - General*; linie społeczności mają jagódkę.",
            "",
            "# Sprzedaż na Trade społeczności z czatu gry",
            "1. Wybierz zakładkę *Jagodki Nadina - General* w czacie gry.",
            "2. Wpisz */jntrade* i naciśnij *Tab*: pole pokazuje *Jagódki Trade:*.",
            "3. Wpisz ofertę i naciśnij *Enter*. Kolejne wiadomości też idą na Trade.",
            "4. Powrót na General: */jnglobal* + *Tab*. Tylko jedna wiadomość: */jntrade WTS ...* z dowolnej zakładki.",
        },
    },
    {
        key = "faq", icon = "Interface\\GossipFrame\\BinderGossipIcon",
        title = { en = "Questions and answers", pl = "Pytania i odpowiedzi" },
        en = {
            "# Can players without the addon read our chat?",
            "No. The chat runs on a secret channel that only the addon knows. Players without it do not see it and cannot write to it.",
            "",
            "# Does the addon read my whispers or other chats?",
            "No. It sends only what you write in the community chat, and data the community uses: your level, class, guild, zone, professions and your sign-ups.",
            "",
            "# Why can I not create another event?",
            "You can have one upcoming event at a time. When it has started, you can create the next one; officers can have up to 5.",
            "",
            "# Why is a guild gray on the right?",
            "Nobody with the addon is online in that guild right now, so its numbers are the last known ones. It becomes active when someone logs in.",
            "",
            "# Why is someone's version red, yellow or -?",
            "Red: their addon is older than yours. Yellow: newer (time to update yours). *-*: they do not have the addon.",
            "",
            "# Why are someone's professions unknown?",
            "Professions come from the players themselves: someone without the addon (or with a very old one) does not send them.",
            "",
            "# Someone is online but missing from the list.",
            "Lists of other guilds come from their players with the addon, a moment after changes. Wait a minute or two.",
            "",
            "# What is a relay?",
            "A player who passes the addon's data (events, lists, professions) between guilds, chosen by the addon itself, one per guild. You do not have to do anything; when they log out, someone else takes over.",
            "",
            "# Does the addon slow the game?",
            "No, it is built to be light: little data, sent in small portions, and the window only does work while it is open.",
            "",
            "# A note by the minimap says my addon is outdated.",
            "An officer reminded everyone with an older version. Update it in the *CurseForge* app and */reload*.",
        },
        pl = {
            "# Czy gracze bez addonu mogą czytać nasz czat?",
            "Nie. Czat działa na tajnym kanale, który zna tylko addon. Gracze bez niego go nie widzą i nie mogą na nim pisać.",
            "",
            "# Czy addon czyta moje szepty albo inne czaty?",
            "Nie. Wysyła tylko to, co piszesz na czacie społeczności, i dane, z których korzysta społeczność: twój poziom, klasę, gildię, lokację, profesje i zapisy.",
            "",
            "# Dlaczego nie mogę utworzyć kolejnego wydarzenia?",
            "Możesz mieć jedno nadchodzące wydarzenie naraz. Gdy się zacznie, możesz utworzyć następne; oficerowie mogą mieć do 5.",
            "",
            "# Dlaczego gildia po prawej jest szara?",
            "W tej gildii nie ma teraz nikogo online z addonem, więc jej liczby są ostatnimi znanymi. Stanie się aktywna, gdy ktoś się zaloguje.",
            "",
            "# Dlaczego czyjaś wersja jest czerwona, żółta albo -?",
            "Czerwona: jego addon jest starszy od twojego. Żółta: nowszy (czas zaktualizować swój). *-*: nie ma addonu.",
            "",
            "# Dlaczego czyjeś profesje są nieznane?",
            "Profesje wysyłają sami gracze: ktoś bez addonu (albo z bardzo starym) ich nie wysyła.",
            "",
            "# Ktoś jest online, ale nie ma go na liście.",
            "Listy innych gildii przychodzą od ich graczy z addonem, chwilę po zmianach. Poczekaj minutę lub dwie.",
            "",
            "# Co to jest relay?",
            "Gracz, który przekazuje dane addonu (wydarzenia, listy, profesje) między gildiami, wybierany przez sam addon, po jednym na gildię. Nic nie musisz robić; gdy się wyloguje, przejmuje to ktoś inny.",
            "",
            "# Czy addon spowalnia grę?",
            "Nie, jest zbudowany tak, żeby był lekki: mało danych, wysyłanych małymi porcjami, a okno pracuje tylko wtedy, gdy jest otwarte.",
            "",
            "# Okienko przy minimapie mówi, że mój addon jest stary.",
            "Oficer przypomniał wszystkim ze starszą wersją. Zaktualizuj addon w aplikacji *CurseForge* i zrób */reload*.",
        },
    },
    {
        key = "officer", officer = true, icon = "Interface\\GroupFrame\\UI-Group-LeaderIcon",
        title = { en = "Officer tools", pl = "Narzędzia oficera" },
        en = {
            "Only officers and guild masters see this topic. The addon checks the rank in the guild rosters, for every officer action.",
            "",
            "# Creating events",
            "- Like everyone: *Create Event* or *right click a day* in the Calendar (see Events).",
            "- A notice goes to the community chat: *Event created by ...*.",
            "- Up to 5 upcoming events at a time (members: 1).",
            "",
            "# Managing events",
            "- *Edit* and *Cancel* in the event's window work on any event (members: only their own).",
            "- Take someone off any event: *right click* their name in its sign-up list, *Remove from event*.",
            "- *Invite all* for any event.",
            "",
            "# Officers chat",
            "- The *Officers* tab in Community Chat, after LFG: a chat only for officers and guild masters of all our guilds. Members do not see the tab and cannot read or write in it.",
            "- It runs on its own secret channel, whose key travels only between officers. When someone loses the officer rank, the addon makes a new key by itself; *New officers key* in Monitoring does it by hand.",
            "- Messages you missed arrive from another officer after login.",
            "- From the game chat: */jnofficers* + *Tab* switches the input to the officers chat, */jnofficers text* sends one message.",
            "- Right after login the channel needs a moment (up to 2 minutes for the very first key). A message that cannot go yet stays in the box with a note; send it again in a moment, or use */jagodka sync*.",
            "- In dungeons and battlegrounds the game blocks addon messages, so the community chat and the lists may stop there. After you leave, the addon catches up by itself within seconds (the same as */jagodka sync*).",
            "- Your messages never go through the relays: without the officers channel they are not sent at all, so nothing reaches members by accident.",
            "",
            "# Muting on the community chat",
            "- *Right click* a name in the chat or the Roster, *Mute on community chat*, and give a *reason*: everyone sees it on the mute icon by the name.",
            "- A muted player's messages are hidden for everyone. The same menu has *Unmute*.",
            "- An officer can be muted only by a guild master.",
            "",
            "# Chat channel key",
            "- The community chat runs on a secret channel, made from a key that only the addon knows.",
            "- *New chat key* (in Monitoring) or */jagodka key* makes a new key: everyone with the addon moves to a new channel within moments.",
            "- Use it when someone unwanted got onto the channel.",
            "",
            "# Updates",
            "- *Remind outdated* (in Monitoring) shows a note by the minimap to everyone with an older addon than yours (once every 5 minutes).",
            "",
            "# Big messages on the screen",
            "- *Officers: promote the addon* (Monitoring): every officer online gets a big red message with a sound, asking to get everyone to install the addon. Members never see it.",
            "- *Global chat test request* (Monitoring): everyone with the addon gets a big message with a sound, asking for a test message on General, Trade and LFG. Handy after an update or a new chat key, to check the chats work for everyone.",
            "- *Announcement* (Monitoring): write your own message (up to 180 characters, a few lines); everyone with the addon sees it as the big message with your name and a sound, and once more in the chat. For news like a raid gathering or a server restart.",
            "- All of them at most once every 5 minutes; nobody sees the same message more than once a minute, even when several officers click.",
            "",
            "Right after login officer actions wait a few seconds for the sync to finish, so nobody acts on old data.",
        },
        pl = {
            "Ten temat widzą tylko oficerowie i Guild Masterzy. Addon sprawdza rangę na listach gildii przy każdej akcji oficera.",
            "",
            "# Tworzenie wydarzeń",
            "- Jak wszyscy: *Create Event* albo *prawy klik na dzień* w kalendarzu (zobacz Wydarzenia).",
            "- Na czat społeczności idzie informacja: *Event created by ...*.",
            "- Do 5 nadchodzących wydarzeń naraz (członkowie: 1).",
            "",
            "# Zarządzanie wydarzeniami",
            "- *Edit* i *Cancel* w oknie wydarzenia działają dla każdego wydarzenia (członkowie: tylko dla swoich).",
            "- Usunięcie kogoś z dowolnego wydarzenia: *prawy klik* na jego imię na liście zapisanych, *Remove from event*.",
            "- *Invite all* dla każdego wydarzenia.",
            "",
            "# Czat oficerów",
            "- Zakładka *Officers* w Community Chat, za LFG: czat tylko dla oficerów i Guild Masterów wszystkich naszych gildii. Członkowie nie widzą zakładki i nie mogą w niej czytać ani pisać.",
            "- Działa na własnym tajnym kanale, którego klucz krąży tylko między oficerami. Gdy ktoś straci rangę oficera, addon sam tworzy nowy klucz; *New officers key* w Monitoringu robi to ręcznie.",
            "- Wiadomości, które przegapiłeś, przychodzą od innego oficera po zalogowaniu.",
            "- Z czatu gry: */jnofficers* + *Tab* przełącza pole na czat oficerów, */jnofficers tekst* wysyła jedną wiadomość.",
            "- Zaraz po zalogowaniu kanał potrzebuje chwili (do 2 minut przy pierwszym kluczu). Wiadomość, której nie da się jeszcze wysłać, zostaje w polu z komunikatem; wyślij ją za chwilę albo użyj */jagodka sync*.",
            "- W dungeonach i na battlegroundach gra blokuje wiadomości addonów, więc czat społeczności i listy mogą tam stanąć. Po wyjściu addon sam nadrabia w kilka sekund (to samo co */jagodka sync*).",
            "- Twoje wiadomości nigdy nie idą przez relaye: bez kanału oficerów w ogóle się nie wysyłają, więc nic nie trafi przypadkiem do członków.",
            "",
            "# Wyciszanie na czacie społeczności",
            "- *Prawy klik* na imię na czacie albo w Roster, *Mute on community chat* i podaj *powód*: wszyscy widzą go na ikonce wyciszenia przy imieniu.",
            "- Wiadomości wyciszonego gracza są ukryte dla wszystkich. To samo menu ma *Unmute*.",
            "- Oficera może wyciszyć tylko Guild Master.",
            "",
            "# Klucz kanału czatu",
            "- Czat społeczności działa na tajnym kanale, utworzonym z klucza, który zna tylko addon.",
            "- *New chat key* (w Monitoringu) albo */jagodka key* tworzy nowy klucz: wszyscy z addonem w kilka chwil przechodzą na nowy kanał.",
            "- Użyj, gdy na kanał dostał się ktoś niepożądany.",
            "",
            "# Aktualizacje",
            "- *Remind outdated* (w Monitoringu) pokazuje okienko przy minimapie wszystkim, którzy mają starszy addon niż ty (raz na 5 minut).",
            "",
            "# Duże napisy na ekranie",
            "- *Officers: promote the addon* (Monitoring): każdy oficer online dostaje duży czerwony napis z dźwiękiem z prośbą o namawianie wszystkich do instalacji addonu. Członkowie go nie widzą.",
            "- *Global chat test request* (Monitoring): każdy z addonem dostaje duży napis z dźwiękiem z prośbą o wiadomość testową na General, Trade i LFG. Przydatne po aktualizacji albo nowym kluczu czatu, żeby sprawdzić, czy czaty działają u wszystkich.",
            "- *Announcement* (Monitoring): wpisz własną wiadomość (do 180 znaków, kilka linii); każdy z addonem zobaczy ją jako duży napis z twoim imieniem i dźwiękiem, a do tego raz w czacie. Na wieści typu zbiórka na raid albo restart serwera.",
            "- Wszystkie najwyżej raz na 5 minut; nikt nie widzi tego samego napisu częściej niż raz na minutę, nawet gdy kliknie kilku oficerów.",
            "",
            "Zaraz po zalogowaniu akcje oficera czekają kilka sekund na koniec synchronizacji, żeby nikt nie działał na starych danych.",
        },
    },
    {
        key = "monitoring", officer = true, icon = "Interface\\Icons\\INV_Misc_Spyglass_02",
        title = { en = "Monitoring", pl = "Monitoring" },
        en = {
            "The addon's traffic and state, for finding problems. Only officers see the tab. It shows names, packet types and event titles, never chat messages or keys.",
            "",
            "# How the addon talks",
            "- The chat goes over a game chat channel, straight to everyone. The officers chat has its own channel, only for officers.",
            "- Everything else (events, rosters, professions, mutes) goes inside each guild, and one player per guild, the *relay*, passes it on to the other guilds. Anyone with the addon can become the relay; when they log out, the next one takes over by itself.",
            "",
            "# The log",
            "- Every packet sent (TX) and received (RX), with its size and route, plus errors and sync stages.",
            "- *Filters*: All, Chat, Channel, Events, Rosters, Mutes, Presence, Relay, Sync, Errors.",
            "- *Latest* jumps to the newest line, *Clear* empties the view.",
            "- *Events* also shows how many changes a sync answer carried (\"answered ... with N changes\").",
            "",
            "# Network view",
            "- The *Network* button opens it, a filter goes back to the log. Guilds and their relays, your direct traffic, your guild's players per addon version, other guilds' players, every guild's roster (members, online, when the last whole roster came, a roster still arriving), strangers on the channels, sync stages and traffic per packet type.",
            "",
            "# The box at the bottom",
            "- The public channel and the chat channel (joined, who made the key, whether an officer confirmed it), the *officers chat* (joined, who made its key, how many messages), the relay, traffic per minute, the queue, versions online, rejected packets and errors.",
            "",
            "# Logs for the addon's authors",
            "- *Preserve logs* records the log into a file (up to 100 000 lines, with the box at the bottom every minute and the Network view every 5 minutes). The game writes the file on */reload*, logout or exit; the path is in the button's tooltip.",
            "- Turning it on starts a new log (the previous one is removed at once). When something does not work: turn it on, play as usual, note the time of the problem, and send the file. *Clear saved* empties it.",
            "",
            "# Actions",
            "- *Sync now*: the sync after login again (once a minute), the same as */jagodka sync*.",
            "- */jagodka perf on*, play a while, then */jagodka perf*: which parts of the addon took the most time and how many frames it slowed down (for reports of stutter); */jagodka perf off* stops it.",
            "- *Remind outdated*: a note by the minimap for everyone with an older addon than yours (once every 5 minutes; reaches players on 0.14.0 or newer).",
            "- *Officers: promote the addon*: a big red message with a sound for every officer online: get everyone to install the addon (once every 5 minutes; members do not see it).",
            "- *Global chat test request*: the same kind of message for everyone with the addon: write a test message on General, Trade and LFG (once every 5 minutes).",
            "- *Update test*: shows the update window, to see what players see.",
            "- *New chat key*: a new chat channel, see Officer tools.",
            "- *New officers key*: a new officers chat channel, see Officer tools.",
        },
        pl = {
            "Ruch i stan addonu, do szukania problemów. Zakładkę widzą tylko oficerowie. Pokazuje imiona, rodzaje pakietów i tytuły wydarzeń, nigdy treści wiadomości czatu ani kluczy.",
            "",
            "# Jak addon się komunikuje",
            "- Czat idzie kanałem czatu gry, od razu do wszystkich. Czat oficerów ma własny kanał, tylko dla oficerów.",
            "- Cała reszta (wydarzenia, listy, profesje, wyciszenia) idzie wewnątrz każdej gildii, a jeden gracz z gildii, *relay*, przekazuje to do pozostałych gildii. Relayem może zostać każdy z addonem; gdy się wyloguje, następny przejmuje to sam.",
            "",
            "# Log",
            "- Każdy wysłany (TX) i odebrany (RX) pakiet z rozmiarem i trasą, do tego błędy i etapy synchronizacji.",
            "- *Filtry*: All, Chat, Channel, Events, Rosters, Mutes, Presence, Relay, Sync, Errors.",
            "- *Latest* skacze do najnowszej linii, *Clear* czyści widok.",
            "- *Events* pokazuje też, ile zmian niosła odpowiedź synchronizacji (\"answered ... with N changes\").",
            "",
            "# Widok Network",
            "- Otwiera go przycisk *Network*, filtr wraca do logu. Gildie i ich relaye, twój bezpośredni ruch, gracze twojej gildii według wersji addonu, gracze innych gildii, lista każdej gildii (członkowie, online, kiedy przyszła ostatnia pełna lista, lista w trakcie przychodzenia), obcy na kanałach, etapy synchronizacji i ruch według rodzaju pakietu.",
            "",
            "# Pole na dole",
            "- Kanał publiczny i kanał czatu (dołączony, kto utworzył klucz, czy oficer go potwierdził), *czat oficerów* (dołączony, kto utworzył jego klucz, ile wiadomości), relay, ruch na minutę, kolejka, wersje online, odrzucone pakiety i błędy.",
            "",
            "# Logi dla autorów addonu",
            "- *Preserve logs* nagrywa log do pliku (do 100 000 linii, z polem z dołu co minutę i widokiem Network co 5 minut). Gra zapisuje plik przy */reload*, wylogowaniu albo wyjściu; ścieżka jest w podpowiedzi przycisku.",
            "- Włączenie zaczyna nowy log (poprzedni jest od razu usuwany). Gdy coś nie działa: włącz, graj normalnie, zanotuj godzinę problemu i wyślij plik. *Clear saved* go czyści.",
            "",
            "# Akcje",
            "- *Sync now*: synchronizacja po zalogowaniu jeszcze raz (raz na minutę), to samo co */jagodka sync*.",
            "- */jagodka perf on*, pograj chwilę, potem */jagodka perf*: które części addonu zajęły najwięcej czasu i ile klatek spowolniły (przy zgłoszeniach przycięć); */jagodka perf off* wyłącza.",
            "- *Remind outdated*: okienko przy minimapie dla wszystkich, którzy mają starszy addon niż ty (raz na 5 minut; dociera do graczy z 0.14.0 lub nowszym).",
            "- *Officers: promote the addon*: duży czerwony napis z dźwiękiem dla wszystkich oficerów online: namawiajcie wszystkich do instalacji addonu (raz na 5 minut; członkowie go nie widzą).",
            "- *Global chat test request*: taki sam napis dla wszystkich z addonem: napiszcie wiadomość testową na General, Trade i LFG (raz na 5 minut).",
            "- *Update test*: pokazuje okno aktualizacji, żeby zobaczyć, co widzą gracze.",
            "- *New chat key*: nowy kanał czatu, patrz Narzędzia oficera.",
            "- *New officers key*: nowy kanał czatu oficerów, patrz Narzędzia oficera.",
        },
    },
}

local LANGUAGES = { { code = "en", label = "English" }, { code = "pl", label = "Polski" } }
local UI = {
    en = { members = "Guide", officers = "Officers", language = "Language:" },
    pl = { members = "Przewodnik", officers = "Oficerowie", language = "Język:" },
}

-- Markup -> colored text: headings gold, bullets with a purple dot, *words* highlighted
local function Format(lines)
    local out = {}
    for _, line in ipairs(lines) do
        line = line:gsub("%*(.-)%*", "|cffffd100%1|r")
        if line:sub(1, 2) == "# " then
            table.insert(out, "|cffffd100" .. line:sub(3) .. "|r")
        elseif line:match("^%d+%. ") then
            -- Numbered step: the number in purple
            local number, rest = line:match("^(%d+%.) (.*)$")
            table.insert(out, "  |cffbf40ff" .. number .. "|r  " .. rest)
        elseif line:sub(1, 2) == "- " then
            table.insert(out, "  |cffbf40ff•|r  " .. line:sub(3))
        else
            table.insert(out, line)
        end
    end
    return table.concat(out, "\n")
end

-- ============================================================================
-- UI
-- ============================================================================
local ctx, panel, nav, content, text, child, scroll, langDD = nil, nil, nil, nil, nil, nil, nil, nil
local measure = nil        -- hidden copy of the text, to find where a heading is (Help.Open)
local goToHeading = nil    -- heading number to scroll to after the next Render
local navItems, selected = {}, "start"

local function Lang()
    local db = _G.JagodkiChatDB
    if db and db.helpLang then return db.helpLang end
    return (_G.GetLocale and _G.GetLocale() == "plPL") and "pl" or "en"
end

local function SetLang(code)
    _G.JagodkiChatDB = _G.JagodkiChatDB or {}
    _G.JagodkiChatDB.helpLang = code
end

local function Render()
    if not panel or not panel:IsVisible() then return end
    local lang, officer = Lang(), ctx.isOfficer()
    -- An officers' topic chosen before the rank changed: back to the first one
    for _, topic in ipairs(TOPICS) do
        if topic.key == selected and topic.officer and not officer then selected = "start" end
    end
    for _, label in ipairs(LANGUAGES) do
        if label.code == lang then _G.UIDropDownMenu_SetText(langDD, label.label) end
    end
    panel.langLabel:SetText(UI[lang].language)
    nav.members:SetText(UI[lang].members)
    nav.officers:SetText(UI[lang].officers)
    -- Topics list: members' topics, then (officers only) the officers' heading and topics
    local y = -30
    for _, item in ipairs(navItems) do
        local topic = item.topic
        if topic.officer and not officer then
            item:Hide()
        else
            if topic.officer and not nav.officersPlaced then
                y = y - 12
                nav.officers:ClearAllPoints()
                nav.officers:SetPoint("TOPLEFT", nav, "TOPLEFT", 12, y)
                y = y - 20
                nav.officersPlaced = true
            end
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT", nav, "TOPLEFT", 4, y)
            item:SetPoint("RIGHT", nav, "RIGHT", -4, 0)
            item.text:SetText(topic.title[lang])
            local active = topic.key == selected
            item.bg:SetColorTexture(active and 0.18 or 1, active and 0.1 or 1, active and 0.24 or 1, active and 0.9 or 0)
            item.bar:SetShown(active)
            item.text:SetTextColor(active and 1 or 0.8, active and 1 or 0.8, active and 1 or 0.8)
            item:Show()
            y = y - 26
        end
    end
    nav.officers:SetShown(officer)
    nav.officersPlaced = nil
    -- The chosen topic
    for _, topic in ipairs(TOPICS) do
        if topic.key == selected then
            content.title:SetText(topic.title[lang])
            text:SetText(Format(topic[lang]))
        end
    end
    local width = scroll:GetWidth()
    child:SetWidth(width)
    text:SetWidth(width - 10)
    child:SetHeight(text:GetStringHeight() + 20)
    -- From a "?" button: scrolled so the chosen heading is at the top (the text before it, measured)
    local target = 0
    if goToHeading then
        for _, topic in ipairs(TOPICS) do
            if topic.key == selected then
                local before, n = {}, 0
                for _, line in ipairs(topic[lang]) do
                    if line:sub(1, 2) == "# " then
                        n = n + 1
                        if n == goToHeading then break end
                    end
                    table.insert(before, line)
                end
                if n == goToHeading and #before > 0 then
                    measure:SetWidth(width - 10)
                    measure:SetText(Format(before))
                    target = measure:GetStringHeight() + 4
                end
            end
        end
        goToHeading = nil
    end
    scroll:SetVerticalScroll(0)
    -- The scroll range is known only after the new text is laid out (next frame)
    if target > 0 then
        addonTable.SafeTimer.After(0, function()
            scroll:UpdateScrollChildRect()
            scroll:SetVerticalScroll(math.max(0, math.min(target, scroll:GetVerticalScrollRange())))
        end)
    end
end

-- Opens the Help tab on a topic, scrolled to its heading number `heading` (the same order in both languages)
function Help.Open(topicKey, heading)
    if not ctx then return end
    selected, goToHeading = topicKey, heading
    -- Opening the tab draws it (OnShow); an already open tab is drawn here
    local wasShown = panel:IsVisible()
    ctx.showTab()
    if wasShown then Render() end
end

-- The help badge: the quest log's yellow question mark on a round dark badge with a thin gold ring.
-- size: an even number, so the ring, the inner circle and the mark stay centered on whole pixels.
-- frameType "Button" for the "?" buttons, "Frame" for the Help tab's icon (core.lua).
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
function Help.Badge(parent, size, frameType)
    local b = CreateFrame(frameType or "Frame", nil, parent)
    b:SetSize(size, size)
    b.ring = b:CreateTexture(nil, "BACKGROUND")
    b.ring:SetAllPoints()
    b.ring:SetTexture(CIRCLE)
    b.ring:SetVertexColor(0.85, 0.65, 0.15, 1)
    b.bg = b:CreateTexture(nil, "BORDER")
    b.bg:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.bg:SetTexture(CIRCLE)
    b.bg:SetVertexColor(0.08, 0.06, 0.03, 1)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetSize(size - 4, size - 4)
    b.tex:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.tex:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
    return b
end

-- A small "?" for a feature: hover = which help, click = that help (90% opaque). The caller places it.
function Help.Button(parent, topicKey, heading, label)
    local b = Help.Badge(parent, 14, "Button")
    b:SetAlpha(0.9)
    b:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        _G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
        _G.GameTooltip:SetText("Help: " .. tostring(label), 1, 0.82, 0)
        _G.GameTooltip:AddLine("Click to read about it", 0.8, 0.8, 0.8)
        _G.GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self:SetAlpha(0.9) _G.GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if self.onClick then self.onClick() else Help.Open(topicKey, heading) end
    end)
    return b
end

-- core.lua: c = { isOfficer = function, applyStyle = function(frame) }
function Help.Attach(p, c)
    panel, ctx = p, c
    -- Language: "Language: [English v]" in the top right corner
    langDD = CreateFrame("Frame", "JagodkaHelpLangDropDown", panel, "UIDropDownMenuTemplate")
    langDD:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 14, 2)
    _G.UIDropDownMenu_SetWidth(langDD, 90)
    _G.UIDropDownMenu_Initialize(langDD, function(_, level)
        for _, label in ipairs(LANGUAGES) do
            local info = _G.UIDropDownMenu_CreateInfo()
            info.text = label.label
            info.checked = Lang() == label.code
            info.func = function() SetLang(label.code) Render() end
            _G.UIDropDownMenu_AddButton(info, level)
        end
    end)
    panel.langLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.langLabel:SetPoint("RIGHT", langDD, "LEFT", 12, 2)
    UseFont(panel.langLabel, 13)
    -- Topics on the left
    nav = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    nav:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -38)
    nav:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    nav:SetWidth(170)
    ctx.applyStyle(nav)
    nav.members = nav:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nav.members:SetPoint("TOPLEFT", nav, "TOPLEFT", 12, -10)
    UseFont(nav.members, 12)
    nav.officers = nav:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nav.officers:SetTextColor(0.75, 0.25, 1)
    UseFont(nav.officers, 12)
    for _, topic in ipairs(TOPICS) do
        local item = CreateFrame("Button", nil, nav)
        item:SetHeight(24)
        item.bg = item:CreateTexture(nil, "BACKGROUND") item.bg:SetAllPoints()
        item.bar = item:CreateTexture(nil, "ARTWORK") item.bar:SetWidth(2)
        item.bar:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 0) item.bar:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0, 0)
        item.bar:SetColorTexture(0.75, 0.25, 1, 1)
        item.icon = item:CreateTexture(nil, "ARTWORK")
        item.icon:SetSize(16, 16) item.icon:SetPoint("LEFT", item, "LEFT", 8, 0)
        item.icon:SetTexture(topic.icon)
        if topic.icon:find("\\Icons\\", 1, true) then item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        item.text = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        item.text:SetPoint("LEFT", item.icon, "RIGHT", 8, 0) item.text:SetPoint("RIGHT", item, "RIGHT", -4, 0)
        item.text:SetJustifyH("LEFT") item.text:SetWordWrap(false)
        UseFont(item.text, 13)
        item:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        item:SetScript("OnClick", function() selected = topic.key Render() end)
        item.topic = topic
        table.insert(navItems, item)
    end
    -- The chosen topic on the right
    content = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    content:SetPoint("TOPLEFT", nav, "TOPRIGHT", 8, 0)
    content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    ctx.applyStyle(content)
    content.title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    content.title:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -14)
    UseFont(content.title, 17)
    content.line = content:CreateTexture(nil, "ARTWORK")
    content.line:SetHeight(1)
    content.line:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -38) content.line:SetPoint("TOPRIGHT", content, "TOPRIGHT", -16, -38)
    content.line:SetColorTexture(0.75, 0.25, 1, 0.5)
    scroll = CreateFrame("ScrollFrame", "JagodkaHelpScroll", content, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -48)
    scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -30, 12)
    child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    text:SetJustifyH("LEFT") text:SetJustifyV("TOP")
    text:SetSpacing(4)
    UseFont(text, 14)
    measure = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    measure:SetJustifyH("LEFT") measure:SetJustifyV("TOP")
    measure:SetSpacing(4)
    UseFont(measure, 14)
    measure:SetAlpha(0)
    measure:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    panel:SetScript("OnShow", Render)
    content:SetScript("OnSizeChanged", function() Render() end)
end
