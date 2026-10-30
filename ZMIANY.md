# Jagodka – zmiany na `feature/lasarr-1`

| Wersja | Commit | Stan |
|---|---|---|
| 0.7.1 | `65044cb` | wypchnięta, wstępnie przetestowana w grze |
| 0.7.2 | `0992d28` | wypchnięta, przetestowana w grze |
| 0.7.3 | `af508ab` | wypchnięta, częściowo przetestowana w grze (reszta do testu) |
| 0.7.4 | commit „feat(lasarr-1): sync bar, calendar create/invite, v0.7.4” | wypchnięta, do przetestowania w grze |

Wersje są opisane po kolei, każda sekcja zawiera tylko zmiany względem poprzedniej. Wszyscy gracze muszą mieć tę samą wersję, bo addon ostrzega o niezgodności, a 0.7.2 i 0.7.3 zmieniają protokół. Kod sprawdzany jest skryptami struktury (domknięte bloki, brak zmiennych globalnych, limit zmiennych lokalnych), a działanie testujemy w grze.

---

# 0.7.1 – wspólny czat, wydarzenia, wersje (na bazie `5b4b160`)

## Pliki
| Plik | Co |
|---|---|
| `most.lua` (nowy) | Most kanał globalny ↔ `/g`: transport, relay, historia, log czatu |
| `instancje.lua` (nowy) | Lista dungeonów i rajdów Classic Era do wydarzeń |
| `core.lua` | UI + punkty styku z mostem, wydarzenia, wersje, zabezpieczenia |
| `jagodka.toc` | `## Version`, CallbackHandler, nowe pliki, `JagodkiChatDB` |

## Czat globalny
- Ukryty kanał `JagodkaWspolnota` łączy wszystkie gildie z whitelisty; każda wiadomość ma unikalne ID, więc nie ma duplikatów.
- **Relay** to alfabetycznie pierwsza osoba z addonem online w gildii. Przenosi `/g` na kanał, a z kanału wkleja do `/g` jako `[Gildia] Nick: tekst`. Do `/g` trafia tylko zakładka Ogolny.
- **Relay zapasowy:** jeśli relay nie przekaże linii z `/g` w ciągu 2–5 s, robi to inna osoba z addonem. Duplikaty są wycinane po treści (okno 15 s).
- Relay wybierany jest według rostera gildii, odświeżanego co 20 s, więc wylogowany relay od razu przestaje nim być.
- Czat sortowany jest po czasie napisania (czas serwera).
- **Historia:** po zalogowaniu addon dostaje ostatnie 30 wiadomości; log 300 wiadomości zapisuje się w `JagodkiChatDB`.
- Wiadomość od nadawcy, którego meldunek jeszcze nie doszedł, nie jest gubiona; kolejka ponawia wysyłkę ok. 30 s.
- Na kanał addon wchodzi 10 s po zalogowaniu i wraca na niego, gdy zostanie wyrzucony.

## Gracze i gildie
- Meldunek co 60 s; gracze offline znikają z listy (roster albo 150 s bez sygnału).
- Zakładka Gildie pokazuje wszystkie gildie z whitelisty: liczbę osób online i relaya (albo „brak relaya”).
- Wersja addonu jest wysyłana w meldunku; kolumna Wersja w zakładce Członkowie; przy niezgodności pojawia się ostrzeżenie.

## Wydarzenia
- Są wspólne dla wszystkich gildii z whitelisty i pokazują gildię autora.
- Tworzy je oficer; przy każdym jest lista instancji (pogrupowana na dungeony i rajdy). Data (3 tygodnie do przodu) i godzina (00–23, minuty co 15) wybierane są z list.
- Opis jest polem wieloliniowym do 400 bajtów z licznikiem, wysyłanym w częściach (`EV_DESC`); w szczegółach pełny opis pokazuje się po najechaniu myszką.
- Okno tworzenia ma przycisk X i zamyka się klawiszem Esc.
- Każdy odbiorca sam sprawdza uprawnienia: tworzy autor-oficer, maksymalnie 10 wydarzeń na osobę, role tylko Tank/Heal/DPS, każdy zapisuje tylko siebie, usuwa autor albo dowolny oficer z whitelisty.

## Izolacja i zabezpieczenia
- Brak zmiennych globalnych (poza zapisami, nazwanymi ramkami i komendą).
- Główna komenda to `/jagodka`; `/okno` działa jako druga nazwa.
- Ostrzeżenie, gdy nie uda się zarejestrować prefiksu albo kanał jest zablokowany (obce hasło lub ban).
- Kto podaje się za członka twojej gildii, a nie ma go w rosterze, jest ignorowany.

## Poprawione stare błędy
Brak CallbackHandler w `.toc`, ścieżki tekstur z pojedynczym `\`, `:` w polach wydarzeń, niezapisywana pozycja ikony na minimapie, zepsute przewijanie list.

## Czego nie da się zagwarantować
- Gdy w gildii nikt z addonem nie jest online, jej `/g` nie trafia na kanał (i odwrotnie).
- Historia obejmuje tylko 30 ostatnich wiadomości; identyczna linia od tej samej osoby wysłana 2× w ciągu 15 s pokaże się raz.
- W `/g` innych gildii wiadomość wysyła relay, a nie autor; spóźniona linia od relaya zapasowego może tam trafić po nowszej.
- Nie da się zweryfikować członków **innych** gildii, a właściciel kanału może banować.
- W `core.lua` naraz aktywne są maksymalnie 184 zmienne lokalne z limitu 200 w Lua 5.1 (stan na 0.7.4, liczone razem z blokami `do ... end`). Nowe funkcje trzeba dodawać w osobnych plikach albo w osobnych funkcjach, np. `BuildCalendar`, a nie w blokach `do ... end`.

## Do przetestowania
1. Wszyscy na wersji 0.7.1; po zalogowaniu odczekać 10 s; w zakładce Ustawienia kanał powinien być „połączony”, a relay wskazany.
2. `/g` gildii A → widoczne w addonie u wszystkich i w `/g` gildii B.
3. Wiadomość z addonu (zakładka Ogolny) → trafia do `/g` obu gildii.
4. Wylogowanie relaya → rolę przejmuje następna osoba, wiadomości z `/g` nie giną.
5. Wydarzenie z instancją i długim opisem → poprawne u drugiej osoby; zapisy na role; usuwanie przez oficera.
6. Do omówienia później: format wiadomości w czacie jest zbyt „głośny”.

---

# 0.7.2 – roster wszystkich gildii w zakładce Członkowie

- Nowy plik `roster.lua` i nowy zapis `JagodkiRosterDB` (ostatni znany roster każdej gildii).
- Zakładka **Członkowie** pokazuje wszystkich członków gildii z whitelisty, także tych bez addonu.
  - Gracze offline są wyszarzeni. Checkbox „Pokaż offline” przełącza widok na samych online.
  - Kolumna Wersja: `-` oznacza gracza bez addonu.
- Roster gildii wysyła jedna osoba z addonem, **nadawca**. Zmienia się co 5 min, a wybór jest liczony tak samo u wszystkich, więc ruch rozkłada się na całą gildię. Pakiety mają niski priorytet.
  - Zmiana statusu to `+Nick` albo `-Nick`. Pełny wpis `Nick,W603+` (klasa, poziom, ranga, status) idzie tylko przy nowym członku albo zmianie poziomu lub rangi.
  - Pełny roster idzie na prośbę osoby, która się zalogowała i ma dane starsze niż 10 min, oraz raz na 30 min.
  - Zmiany sprawdza co 20 s każdy, ale wysyła tylko nadawca, więc zmiana nadawcy nie wymaga wysyłania całego rostera.
- Gdy z danej gildii nikt z addonem nie jest online, jej członkowie są pokazywani jako offline (dane mogą być nieaktualne).
- Po zalogowaniu addon czeka 40 s, zanim zacznie wysyłać, żeby wcześniej poznać pozostałych.
- Zakładka Gildie nie pokazuje już relaya; jest on widoczny tylko w Ustawieniach.
- Członkowie: sortowanie po kliknięciu w nagłówek kolumny (rosnąco ^, malejąco v, trzecie kliknięcie wraca do domyślnej kolejności: online, gildia, nick) oraz strony po 50 osób z paskiem pod tabelą: `Pokazano 51-100 z 312 (48 online)  [<<] [<] Strona 2 / 7 [>] [>>]`.
- Członkowie: przycisk Reset (wyszukiwarka, „Pokaż offline”, sortowanie, strona 1). Prawy klik na wierszu otwiera menu z „Whisper” i „Invite to group”, a Shift + lewy klik od razu otwiera szept (tylko do graczy online).
- Panel „Aktywni gracze” korzysta z tej samej listy co Członkowie, tylko z graczami online (także bez addonu). Ma te same kliknięcia (menu z „Whisper” i „Invite to group”, Shift + lewy klik) i jest odświeżany najwyżej raz na 0,3 s, tylko przy otwartym oknie.
- Licznik „Online: N” w nagłówku okna liczy to samo co panel: wszystkich online ze wszystkich gildii z whitelisty, z addonem i bez.
- Kanał `JagodkaWspolnota` jest zahasłowany (`COMM_PASSWORD` w `most.lua`). Wszyscy muszą mieć 0.7.2: z hasłem założonego kanału 0.7.1 nie dołączy (WRONG_PASSWORD).
- Interfejs po angielsku, bez polskich liter (zakładki, przyciski, komunikaty, status, ostrzeżenia, `.toc`). Wewnętrzne nazwy w protokole (zakładki czatu `Ogolny`/`Handel`, `Brak`) zostały bez zmian, więc pakiety pozostają zgodne.
- Wydajność: lista członków jest przeliczana tylko przy widocznej zakładce i najwyżej raz na 0,3 s, scroll tylko przerysowuje wiersze, a roster własnej gildii jest odczytywany najwyżej raz na 2 s.

Do przetestowania:
- Lista członków drugiej gildii pojawia się po ok. 15–60 s od zalogowania.
- Wylogowanie gracza z drugiej gildii zostaje zauważone w ciągu ok. 40 s.

---

# 0.7.3 – whitelista, Guilds, Calendar, synchronizacja wydarzeń, okno

- Whitelista: `Jagódki Nadina`, `Jagódki Nadina II`, `III`, `IV` (bazowa nazwa + przyrostki w `core.lua`) oraz `Testowo`. Każda nowa gildia wymaga podbicia wersji.
- Zakładka Guilds pokazuje wszystkie gildie z whitelisty:
  - **aktywne** (ktoś z addonem jest online): `Online: 12 / 87`, „Active”, na górze listy;
  - **nieaktywne**: wyszarzone, z liczbą członków z cache i czasem ostatniej synchronizacji („Inactive (2 h ago)” albo „never synced”).
- Zakładka odświeża się sama, gdy dojdzie roster.
- Po utworzeniu wydarzenia na czat General (kanał globalny i `/g` wszystkich gildii) idzie ogłoszenie: `Event created by Nick -> Nazwa : Instancja 05.11 20:00`.
- Nowa zakładka **Calendar** (między Events a Settings):
  - Siatka miesiąca 7×6 od poniedziałku do niedzieli, przyciski `<` `>` i `Today`. Dzisiejszy dzień ma złotą ramkę, przeszłe dni są ciemniejsze, a dni z sąsiednich miesięcy przygaszone.
  - W każdym dniu mieszczą się 3 wydarzenia `20:00 Nazwa`. Wydarzenia, na które jesteś zapisany, są zielone. Gdy wydarzeń jest więcej, ostatnia linia pokazuje „+N more”.
  - Tooltip pokazuje nazwę, czas, instancję, autora z gildią i liczbę zapisów T/H/D.
  - Kliknięcie otwiera zakładkę Events z tym wydarzeniem i jego zapisami.
- Po usunięciu wydarzenia idzie ogłoszenie na General: `Event removed by Nick -> Nazwa : Instancja 05.11 20:00`.
- **Synchronizacja wydarzeń** (Events i Calendar mają te same dane u wszystkich):
  - Prośba `EV_REQ` idzie po zalogowaniu (ok. 15 s) oraz przy otwarciu Events lub Calendar, nie częściej niż co 5 min.
  - Odpowiada **jedna losowa osoba z addonem**, nie tylko autor. Po 1–4 s wysyła `EV_CLAIM`, a reszta rezygnuje. Wysyłka idzie na kanał z niskim priorytetem, więc korzystają z niej wszyscy.
  - Synchronizowane są też zapisy (`EV_ROS`): dopisywane są tylko brakujące osoby.
  - `EV_ADD` zawiera gildię autora, więc przekazane wydarzenie pokazuje właściwą gildię.
  - Usunięte wydarzenia są pamiętane przez 30 dni, więc nie wracają od kogoś, kto był offline. Wydarzenia starsze niż 2 dni po terminie znikają same.
  - Przekazane wydarzenie (gdy autor jest offline) przyjmujemy od dowolnego znanego gracza z whitelisty. Od samego autora nadal wymagana jest ranga oficera.
- Główne okno:
  - przesuwa się tylko za pasek tytułu (logo i nazwa);
  - uchwytem w prawym dolnym rogu zmienia się rozmiar okna (od 850×620 do 1600×1100), a czcionki zostają bez zmian. Większe okno pokazuje więcej treści: więcej linii czatu i dłuższe pole wpisywania, więcej wierszy w Members, Guilds, na liście wydarzeń, w zapisach i w panelu Online players, a w kalendarzu większe komórki z większą liczbą wydarzeń w dniu;
  - pozycja i rozmiar zapisują się w `JagodkiMinimapDB.window`;
  - `/jagodka reset` przywraca domyślny rozmiar i środek ekranu.
- Na liście wydarzeń „os.” zastąpiono „signed”.
- Panel Online players: paski graczy zajmują całą szerokość panelu (bez suwaka aż do krawędzi), poziom jest wyrównany do prawej, a długi nick z gildią jest ucinany przed poziomem.
- Czat przewija się kółkiem myszy (3 linie, z Shift o stronę, a z Ctrl na początek albo koniec historii) albo paskiem przewijania z prawej (suwak i strzałki). Pasek jest zsynchronizowany z kółkiem i nowymi wiadomościami.
- Nowy plik `zakladka.lua`: dodatkowa zakładka **„Jagodki Nadina - General” w czacie gry**, z tymi samymi wiadomościami co czat General w addonie. Treść wiadomości jest ciemnozielona (`3cb43c`), żeby odróżniała się od `/g`; zakładka utworzona wcześniej jako „Jagodki Nadina” zostaje przemianowana.
  - Tworzy się raz, przy pierwszym zalogowaniu z addonem. Przy domyślnym układzie (General i Combat Log) jest trzecia, a gra sama pamięta ją później.
  - Po zalogowaniu pokazuje ostatnie 30 wiadomości, potem nowe na bieżąco. Nicki są linkami (klik to szept, prawy klik to menu).
  - Służy tylko do czytania: pisze się przez `/g` (relay przenosi to do wszystkich gildii) albo w oknie addonu.
  - Zamknięta przez gracza nie wraca sama; `/jagodka tab` tworzy ją ponownie.

Poprawki błędów:
- Kliknięcie Remove wywoływało błąd `most.lua:240: attempt to compare string with number`. Przyczyna: `GetGuildInfo("player")` jako ostatni argument `Most.Publish` przekazywało też nazwę rangi, która wpadała na miejsce czasu wiadomości. Wywołanie jest teraz w nawiasach, a `Most.Publish` przyjmuje czas tylko jako liczbę (inaczej bierze bieżący czas serwera).

Zgodność: `EV_ADD` ma nowe, 9. pole (gildia autora), doszły pakiety `EV_ROS` i `EV_CLAIM`, a whitelista się zmieniła. Wszyscy muszą mieć 0.7.3.

Do przetestowania:
- Guilds: gildie bez nikogo online są wyszarzone i przechodzą na „Active”, gdy ktoś z nich wejdzie.
- Wydarzenie utworzone, gdy druga osoba jest offline: po jej zalogowaniu pojawia się w Events i Calendar, razem z zapisami, nawet gdy autor jest już offline.
- Usunięcie wydarzenia: znika u wszystkich, wysyła ogłoszenie i nie wraca po synchronizacji.
- Calendar: klik w wydarzenie otwiera Events z jego szczegółami; nawigacja `<` `>` `Today`.
- Okno: przesuwanie tylko za pasek tytułu, uchwyt rozmiaru, zapamiętanie po `/reload`, `/jagodka reset`.

---

# 0.7.4 – pasek synchronizacji

- Nowy plik `synchro.lua`: w nagłówku głównego okna, na lewo od „Online: N”, pojawia się pasek postępu `Syncing: ✓ Channel  ⌛ Chat  ⌛ Events  ✓ Rosters`.
  - Widać go tylko przy otwartym oknie i tylko wtedy, gdy coś się synchronizuje: po zalogowaniu albo przy otwarciu Events lub Calendar, gdy addon prosi o brakujące wydarzenia.
  - Etapy: wejście na kanał, historia czatu, wydarzenia i zapisy, rostery innych gildii. Etap rosterów pojawia się tylko wtedy, gdy cache ma ponad 10 min.
  - Etap kończy się, gdy przez chwilę nic nie przychodzi (3–4 s po ostatnim pakiecie), gdy nikt nie odpowie (ok. 7 s) albo po twardym limicie czasu.
  - Na koniec pasek pokazuje „Synced” przez 4 s i znika.
- Synchronizacja nie została zmieniona; pasek tylko pokazuje, co się dzieje, a dane z cache są dostępne od razu, jak dotąd.
- Members: „Show offline” jest domyślnie **odznaczone**, więc widać tylko graczy online. Reset też wraca do tego ustawienia.
- Calendar: kliknięcie w wolne miejsce dnia (poza wydarzeniem) otwiera menu z „Create event”, które otwiera okno tworzenia z ustawioną datą tego dnia. Opcja jest aktywna tylko dla oficerów i tylko dla dnia dzisiejszego oraz przyszłych; dla przeszłych dni jest wyszarzona.
- Calendar: **prawy klik na wydarzeniu** otwiera menu z „Invite members (N)”, „Open event” i „Cancel”. Lewy klik działa jak dotąd i otwiera wydarzenie.
  - „Invite members” wysyła zaproszenia do grupy wszystkim zapisanym. Pomija ciebie, osoby już w grupie i offline. Na końcu w czacie pojawia się podsumowanie, np. `MC: inviting 12 (already in group: 3, offline: 2)`.
  - Zapraszać może tylko lider grupy, asystent raidu albo ktoś bez grupy.
  - Gdy chętnych jest więcej niż miejsc w party, addon zamienia grupę na raid (od razu albo po pierwszym przyjętym zaproszeniu) i zaprasza resztę, maksymalnie do 40 osób.
- Poprawka techniczna (przyczyna awarii przy pierwszej wersji „Invite members”): Lua 5.1 pozwala na najwyżej **200 zmiennych lokalnych aktywnych naraz** w jednej funkcji, także w głównym pliku. Zmienne w blokach `do ... end` też się do tego liczą, dopóki blok trwa. Pierwsza wersja zaproszeń podniosła `core.lua` do ok. 203, przez co cały plik się nie kompilował i nie działało nic.
  - Kalendarz jest teraz osobną funkcją (`BuildCalendar`), która ma własny limit. Szczyt w `core.lua` spadł ze 193 do 184, a funkcja kalendarza ma 43 zmienne i ok. 26 odwołań do zmiennych spoza siebie (limit 60).
  - Nowy skrypt `luaactive.ps1` liczy najgorszy moment w każdym pliku i jest uruchamiany przed każdą zmianą.
