# doc – wiedza o API WoW Forever (interface 16001)

**Dla człowieka:** otwórz `doc/index.html` w przeglądarce. Zakładki: Notatki, API (całe API gry z sygnaturami), Społeczność (notatki autorów addonów), Źródła i Aktualizacja. Wyszukiwarka jest na górze (skrót `/`). Link z gotowym wyszukiwaniem: `index.html?q=GetGuildRosterInfo#api`.
**Odświeżenie:** dwuklik w `doc\update.bat`.

**Dokumentacja samej Jagodki:** `doc/jagodka.html` (link też na górze `index.html`). Opisuje:
- moduły i drogi komunikacji,
- relay i synchronizację po logowaniu,
- czat i słownik wszystkich pakietów (format payloadu),
- klucze, rostery, wydarzenia i LFG,
- bezpieczeństwo, timery, SavedVariables i komendy,
- logi do analizy: `tools\logs.bat` kopiuje je z gry do `logs\`, a analizy są w `analysis\` (sekcja 21, „Logi do analizy”).

Jest pisana ręcznie z kodu wersji 1.1.1. Przy zmianie protokołu poprawić ją razem z CHANGELOG.

**Dla Claude (jak z tego korzystać przy pracy nad addonem):**

1. **Najpierw notatki:** `doc/data/notes.js` zawiera to, co już wiemy i co dotyczy Jagodki. Każda notatka ma status: `u-nas` (z naszych logów), `blizzard`, `spolecznosc` (niesprawdzone przez nas) albo `nieaktualne`.

2. **Całe API klienta z sygnaturami:** `doc/data/api.tsv`, ok. 11,7 tys. pozycji: funkcje `C_*`, metody ramek (`Widget:Method`), eventy, enumy, struktury i stałe.
   - Linia pozycji ma pola: nazwa, rodzaj, flagi, plik źródłowy, opis.
   - Pod nią są wcięte linie `arg` / `ret` / `payload` / `field` z typem (`?` = może być nil) i uwagami, np. wartością enuma.
   - Przykłady:
     `grep -A20 -P "^C_ChatInfo.SendAddonMessage\t" doc/data/api.tsv`
     `grep -A25 "^GetGuildRosterInfo" doc/data/api.tsv`
     `grep -i "ListChannel\|InChatMessagingLockdown" doc/data/api.tsv`
   - Linie `used jagodka/plik.lua:linia  kod` pokazują, gdzie Jagodka używa danej funkcji albo eventu (do 12 miejsc, potem łączna liczba). Szukanie wszystkiego, czego używamy: `grep -B1 "^    used" doc/data/api.tsv`. Te linie odświeża `update.ps1`, więc trzeba go uruchomić po zmianach w kodzie.
   - Typ, który jest strukturą (np. `ChatChannelInfo`), ma własną pozycję z polami `field`.
   - Flagi warte uwagi:
     - `SecretInChatMessagingLockdown`, `SecretArguments=…`, `SecretReturns…`: sekrety;
     - `HasRestrictions`, `IsProtectedFunction`: bywa blokowana;
     - `MayReturnNothing`: może nic nie zwrócić;
     - `ForeverAPI-restrictions`: gra ją zablokowała w teście ForeverAPI.
   - Rodzaj `global` to starsza funkcja, którą gra ma, a dokumentacja Blizzarda nie opisuje. Jej sygnatura (`wiki signature`) pochodzi z Warcraft Wiki przez Ketho/vscode-wow-api. Ok. 230 takich funkcji nie ma żadnej sygnatury; przed użyciem trzeba je sprawdzić w grze.

3. **Oryginały:**
   - Blizzard: `doc/.cache/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated/<plik z kolumny 4>`;
   - notatki społeczności jako `.md`: `doc/.cache/community/`, do grepowania.
   Katalog `.cache` jest lokalny; jeśli go nie ma, uruchom update.

4. **Gdzie szukać dalej:** `doc/data/sources.js` (linki z opisem i zaufaniem). Kolejność:
   1. kod Blizzarda (gałąź `forever`),
   2. Warcraft Wiki (opisy retail = Mainline),
   3. ForeverAPI, ForeverPlusPlus, forever-addon-kit.
   Fanowskie strony traktuj tylko orientacyjnie.

5. **Odświeżenie:** `powershell -ExecutionPolicy Bypass -File doc\update.ps1` albo `doc\update.bat`. Potrzebny jest tylko git (Pythona i Node nie ma). Skrypt pobiera:
   - najnowszy build Blizzarda (Gethe/wow-ui-source, gałąź `forever`),
   - listy ForeverAPI,
   - Wiki.lua z vscode-wow-api,
   - notatki społeczności (lista `$community` w skrypcie: żeby dodać nowy dokument, dopisz tam wpis).

6. **Po każdej analizie logów albo nowym znalezisku** dopisz albo popraw notatkę w `notes.js` (status, data, źródła, nazwy API). Nowe źródło dopisz do `sources.js`.

Zasada: nie zgadujemy API. Jeśli funkcji nie ma w `api.tsv`, nie ma jej sygnatury albo notatka ma status `spolecznosc`, przed budowaniem funkcji robimy małą sondę w grze.

## Pliki

| Plik | Co | Kto zmienia |
|---|---|---|
| `index.html` | strona z wyszukiwarką | ręcznie |
| `data/notes.js` | notatki dla Jagodki | ręcznie |
| `data/sources.js` | źródła | ręcznie |
| `data/api.js` | całe API z sygnaturami, dla strony | `update.ps1` |
| `data/api.tsv` | to samo do grepowania | `update.ps1` |
| `data/community.js` | notatki społeczności dla strony | `update.ps1` |
| `update.ps1`, `update.bat` | pobranie źródeł i budowa indeksu | ręcznie |
| `.cache/` | pobrane repozytoria i dokumenty (ignorowane przez git) | `update.ps1` |

Licencje: ForeverAPI (docs), vscode-wow-api, ForeverPlusPlus i forever-addon-kit są na licencji MIT. Kod UI Blizzarda należy do Blizzarda i trzymamy go tylko lokalnie w `.cache`; do repo trafia wyłącznie nasz indeks.
