# Jagodka – zmiany na `feature/lasarr-1` (wersja 0.7.1)

Wszystko niżej leży niezacommitowane, na bazie commita `5b4b160`. Nic nie było jeszcze testowane w grze; sprawdzono tylko strukturę kodu (domknięte bloki, brak zmiennych globalnych, limit zmiennych lokalnych).

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
- `core.lua` ma 165 zmiennych lokalnych z limitu 200 w Lua 5.1, więc nowe funkcje lepiej dodawać w osobnych plikach.

## Do przetestowania
1. Wszyscy na wersji 0.7.1; po zalogowaniu odczekać 10 s; w zakładce Ustawienia kanał powinien być „połączony”, a relay wskazany.
2. `/g` gildii A → widoczne w addonie u wszystkich i w `/g` gildii B.
3. Wiadomość z addonu (zakładka Ogolny) → trafia do `/g` obu gildii.
4. Wylogowanie relaya → rolę przejmuje następna osoba, wiadomości z `/g` nie giną.
5. Wydarzenie z instancją i długim opisem → poprawne u drugiej osoby; zapisy na role; usuwanie przez oficera.
6. Do omówienia później: format wiadomości w czacie jest zbyt „głośny”.
