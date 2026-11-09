# Jagodka: plan kolejnych wersji

Plan na podstawie logów z 7–8.11 i przeglądu addonu Olympus (szczegóły i porównanie: `OLYMPUS_REVIEW.md`).

Zasady bez zmian:
- jedna wersja = jeden temat, a przed następną log z gry (Preserve logs),
- nic nie psujemy: zgodność ze starszymi wersjami albo jawny okres przejściowy,
- każda zmiana ma ślad w Monitoringu, żeby log pokazał, czy działa,
- `.toc` zostaje na ostatniej wydanej wersji, dopóki testujemy.

---

## 0.15.1: poprawki po wydaniu 0.15.0 (gotowe, czeka na test i wydanie)

- **LFG:**
  - zdjęte wpisy pamiętane, więc stare kopie nie wracają,
  - wpis znika po 40 minutach bez sygnału,
  - na Sync LFG odpowiadają tylko gracze na 0.15.0 i nowszych,
  - log wpisów od nieznanych graczy.
- **Szybsze listy innych gildii:** pełna lista idzie szeptem prosto do relayów innych gildii.
- **Wysyłanie:** kody 9 i 11 („result 11”) są ponawiane przez ok. 30 s zamiast przepadać.
- **Dungeony:**
  - sekretne teksty pomijane bez błędów Lua,
  - synchronizacja i sprawdzenie kanałów po wyjściu z instancji.
- **Ochrona przed błędami (`safe.lua`):** każdy handler zdarzeń, OnUpdate i timer działa w `pcall`. Błąd trafia do Monitoringu („Lua error in plik:linia”), a reszta działa dalej.

**Do sprawdzenia w logu:**
- linie „Lua error in …”: gdzie i jak często, teraz to pierwsze źródło wiedzy o błędach,
- czas pełnych list innych gildii (punkt odniesienia: 12–16 minut na 130 części),
- „Limit reached, retrying” zamiast „Send failed … result 11”,
- „Left an instance: sync started”.

---

## 0.15.2: stabilność i płynność (wydana razem z poprawką czatu, nickami Discorda i podpowiedziami LFG)

1. **Poprawki błędów, które pokaże `safe.lua`.** Pierwszy log z 0.15.1 powie, co naprawdę się wysypuje.
2. **Rozłożone tickery:** każdy cykliczny timer startuje z losowym opóźnieniem (do 60 s), żeby kilkanaście tickerów nie ruszało w tej samej klatce. To mniej przycięć co minutę. Zmiana w jednym miejscu (`SafeTimer.NewTicker`).
3. **Profiler `/jagodka perf`** (opcjonalnie): na bazie `safe.lua` mierzy czas każdego handlera i timera i pokazuje najwolniejsze miejsca oraz klatki powyżej 30 ms. Wyłączony nic nie kosztuje. Pomoże przy zgłoszeniach „gra przycina z addonem”.

**Zgodność:** pełna, bez zmian w pakietach.

---

## 0.16.0: kolejka i sygnały „jestem online” (średnie ryzyko)

### A. Kolejka wysyłania
- **Zastępowanie po kluczu:** nowa wiadomość tego samego rodzaju (mój PONG, sygnał LFG, profesje) zastępuje czekającą w kolejce, zamiast stawać na końcu.
- **Wygasanie czatu:** wiadomość czatu idąca przez relay starsza niż ok. 60 s jest porzucana; historia czatu i tak ją uzupełni.
- **Wstrzymanie w blokadzie:** w instancji i w walce kolejka czeka, a nie próbuje wysyłać. Wiadomości starsze niż 10 minut są porzucane. Po wyjściu idzie synchronizacja (jest od 0.15.1).
- **Sloty:** duże transfery (pełne listy, odpowiedzi na Sync) przeplatane w stałym rytmie z bieżącymi wiadomościami, żeby lista nie blokowała czatu i zmian.
- **Limit kolejki:** zbyt długa kolejka niskiego priorytetu porzuca najstarsze wiadomości z wpisem w logu, zamiast rosnąć bez końca.

**W logu:** czekanie w kolejce (średnie i najdłuższe), liczba zastąpionych i porzuconych wiadomości.

### B. Cichsze sygnały „jestem online”
- **Kto mówi co minutę:** tylko kilku kandydatów na relaya (np. 5 pierwszych alfabetycznie wśród graczy z addonem w gildii). Pozostali mówią raz na 10 minut.
- **Liczenie graczy:** nowa wersja liczy gracza 12 minut od ostatniego sygnału, o ile lista gildii pokazuje go online.
- **Zysk:** ok. 8 razy mniej PONG. PONG to dziś 3/4 całego ruchu.
- **Zgodność:** wybór relaya się nie zmienia. Starsze wersje zaniżą „Addon users online”, bo cisi gracze wypadną im po 150 s. Wprowadzać, gdy większość ma 0.16.0, albo zaakceptować zaniżony licznik u starszych wersji.

**W logu:** liczba PONG na minutę przed i po, wybory relaya bez zmian.

---

## 0.17.0: dane innych gildii (większa zmiana)

- **Zamiast pełnej listy co godzinę:**
  - **podsumowanie gildii** co kilka minut, w jednej lub dwóch wiadomościach: członkowie, online, klasy, poziomy, wersje addonu. Wystarczy na panele Guilds i Classes.
  - **lista osób online** przy zmianach (ok. 150 osób zamiast 1000): weryfikacja nadawców, Officers online, LFG, wydarzenia.
  - **pełna lista** tylko na żądanie (Roster z innymi gildiami) albo rzadko (np. co 6 godzin).
- **Okres przejściowy:** stare wersje potrzebują pełnych list, więc przez jakiś czas wysyłamy oba rodzaje. Pełne listy wyłączamy, gdy starych wersji praktycznie nie będzie.
- **Do ustalenia przed startem:** co w zakładce Roster pokazujemy z offline członków innych gildii, jak weryfikujemy członkostwo bez pełnej listy, jak liczymy panele.

**W logu:** ruch list innych gildii przed i po, świeżość danych (minuty od ostatniej zmiany).

---

## Poza planem, do decyzji później

- **Limit czatu na odbiorze:** wiadro tokenów na nadawcę i licznik na kanał, ochrona przed zalewem bez czekania na oficera.
- **Dosyłanie brakujących części pełnej listy** (tylko gdyby po 0.15.1 części dalej ginęły).
- **Zewnętrzna aplikacja gildii:** czytanie SavedVariables i logu czatu (z gry do aplikacji); w drugą stronę tylko przez `/reload`.
