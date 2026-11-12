# Solar Rings 7X 2.3.0 — poprawa układu i konfiguracji

## Co zmieniono
- Nowy układ 2×2; cztery pierścienie mają małe ikony nad dużymi wartościami (bez etykiet przy czterech domyślnych metrykach).
- Dolna sekcja nie ma już dwóch nachodzących na siebie linii pogody; opis jest skracany do dostępnej szerokości.
- Kroki 10000–99999 są wyświetlane w całości. Wartości 1–5 cyfr są rysowane własnymi cyframi pikselowymi, które mieszczą się wewnątrz pierścienia. Dla liczników 100000+ jest skrót k. Inne rodzaje danych dopasowują rozmiar fontu.
- Faza Księżyca (lub Puste / inne dane) pozostaje w górnym środkowym polu.
- 16 ustawień (9 pól + 4 kolory + 3 opcje burzy) pogrupowanych dla iPhone'a przez `resources/settings/settings.xml`.
- Tętno nie rysuje już fałszywego pełnego pierścienia postępu. Dla metryk bez celu widoczna jest neutralna obwódka.
- Próba odczytu ostatniej dostępnej próbki Body Battery w ciągu ostatniej godziny; brak dostępnych danych oznacza `--`.
- Id aplikacji i kluczowe nazwy właściwości zachowane, by aktualizować istniejącą wersję beta.

## Aktualizacja z GitHuba
1. Zrób kopię repozytorium (np. `Code → Download ZIP`).
2. Rozpakuj `SolarRings7X_2_3_PODMIEN_PLIKI.zip`.
3. **Usuń stare pliki z repozytorium GitHub**: `resources/settings.xml` oraz `resources/properties.xml`. W v2.3 zastępują je `resources/settings/settings.xml` i `resources/settings/properties.xml` (poprawny, standardowy katalog ustawień mobilnych).
4. Wgraj foldery `source/`, `resources/`, `tests/` oraz `manifest.xml` do istniejącego repozytorium, z zachowaniem ścieżek. Nie nadpisuj swoich `/.github/workflows` ani nie dodawaj prywatnego klucza do repozytorium.
5. GitHub Actions → Build Garmin Solar Rings 7X → uruchom build na `main` (lub poczekaj na build push). Zobacz wynik; jeżeli jest czerwony — otwórz `Compile watch face PRG`, wklej pełny błąd.
6. Po zielonej kompilacji z `Artifacts` pobierz nowe `.IQ`. W panelu Garmin Developer użyj **Upload New Version** (nie Add App), podaj wersję `2.3.0` i zachowaj status Beta. Publikacja wymaga uprawnionego pełnoletniego właściciela konta deweloperskiego.
7. Zainstaluj aktualizację tarczy w Connect IQ na iPhonie. Po synchronizacji otwórz w aplikacji Connect IQ: **Urządzenie → Moje tarcze → Solar Rings 7X → Ustawienia**, nie stronę sklepu.
8. Uwaga: na starszym instalacyjnym wpisie albo przy problemach z odświeżeniem Connect IQ możesz nie widzieć zmian. Sprawdź w Garmin Developer wersję 2.3.0 i upewnij się, że aktualizacja dotarła na zegarek. Nie usuwaj tarczy przed upewnieniem się, że masz kopię ustawień.

## Uczciwe ograniczenia
- Nowe pliki zostały poddane analizie statycznej i testom XML/układu, lecz nie są lokalnie skompilowane w Garmin SDK i wymagają sprawdzenia przez Actions oraz na urządzeniu.
- MIP ma ograniczone miejsce. Skracanie niektórych wartości/etykiet jest zamierzone. Domyślnie zmieniono tętno na pierścień neutralny bez celu; Body Battery może pokazać `--`, gdy sensor nie udostępnia aktualnej próbki.
- Wskaźnik burzowy jest szacunkowy i nie zastępuje prognozy; nie gwarantuje braku błędów podczas zmiany wysokości.

## Układ i długie liczby
Pierścienie 2×2 są rysowane we własnych, oddzielnych pasach; w środku mają ikonkę i wartość zamiast powtarzanej etykiety. Ikony są wektorowe (serce, ślady stóp, bateria/energia i stoper). Dla pól innych niż cztery domyślne wyświetlany jest skrót nazwy.

Wartości kroków w zakresie od 10 000 do 99 999 nie są skracane do `10k`: np. 12 345 wyświetlane jest jako `12345`. Powyżej 99 999 stosowany jest skrót, aby nie uciąć cyfry. Postęp celów nadal określa obwódka, bez `/10k` w środku.

## WAŻNE: ustawienia w iPhone
W poprzednim wydaniu oba pliki definicji leżały bezpośrednio w `resources/`. W tym wydaniu są w standardowym `resources/settings/`, tj. `resources/settings/settings.xml` i `resources/settings/properties.xml`.

W repozytorium GitHub usuń STARE `resources/settings.xml` i `resources/properties.xml`, gdy wgrasz nowe. Pozostaw tylko wersje z katalogu `resources/settings/`. Unikniesz duplikatów zasobów kompilowanych przez SDK. W aplikacji Connect IQ otwieraj konfigurację przez **Urządzenie → Moje tarcze → Solar Rings 7X → Ustawienia**, a nie przez stronę opisu aplikacji w sklepie. Jeżeli po aktualizacji opcja nie występuje, najpierw zweryfikuj numer wersji aplikacji i powiązanie z instalacją w zegarku; nie można zagwarantować dostępności bez sprawdzenia na iPhonie.
