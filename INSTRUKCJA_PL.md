# Solar Rings 7X PL — wersja 2.0 (kod źródłowy)

**Urządzenie:** Garmin fēnix 7X Pro Solar, MIP 280×280, 64 kolory.
**Status:** kompletny projekt źródłowy do kompilacji w Connect IQ SDK. Nie jest to gotowy, skompilowany `.PRG`; kod nie został uruchomiony w oficjalnym symulatorze ani na zegarku. Nie ma w tym środowisku Garmin SDK. Jeśli podczas kompilacji pojawi się błąd, należy go poprawić i przetestować projekt przed instalacją.

## Wygląd — bez zmian względem ustaleń

- Nagłówek: czas oraz data.
- Dwa pola górne: domyślnie **wschód słońca** i **zachód słońca**.
- Cztery kolorowe pierścienie: domyślnie **tętno, kroki, Body Battery, tygodniowe minuty intensywności**.
- Pole dolne: domyślnie **pogoda + temperatura**.
- Dolny pasek: domyślnie **bateria zegarka**.
- Dodatkowa **błyskawica** przy dolnej sekcji: ostrzeżenie o dużym spadku ciśnienia.
- Nic nie wyświetla `/10k`, `/150` ani `/100`; informację o postępie pokazuje zapełnienie pierścienia.

## 8 pól konfigurowalnych

Każde z 8 pól (2 górne + 4 pierścienie + pogoda/środek-dół + dolny pasek) można niezależnie przełączyć na **dowolne z 34 źródeł** w menu tarczy. Można również wyłączyć pole. Dodatkowo można ustawić osobny kolor każdego pierścienia.

### Wszystkie 34 opcje

1. Puste
2. Tętno (z historii sensora)
3. Kroki
4. Body Battery
5. Minuty intensywne — tydzień
6. Minuty intensywne — dzisiaj
7. Kalorie
8. Dystans dzienny
9. Piętra w górę
10. Piętra w dół
11. Stres
12. SpO₂ / pulsoksymetr
13. Częstotliwość oddechu
14. Czas regeneracji
15. Wschód słońca
16. Zachód słońca
17. Pogoda
18. Bateria zegarka
19. Temperatura
20. Temperatura odczuwalna
21. Wilgotność
22. Prędkość wiatru
23. Ciśnienie atmosferyczne
24. Wysokość
25. Cel kroków
26. Cel minut intensywnych
27. Temperatura maksymalna
28. Temperatura minimalna
29. Pasek ruchu
30. Indeks UV
31. Prawdopodobieństwo opadów
32. Godzina
33. Data
34. Zachmurzenie (%)

**Ważne o pierścieniach:** prawdziwy postęp względem celu pochodzi z Garmina dla kroków, pięter i tygodniowych minut intensywności. Dla Body Battery, baterii, SpO₂, stresu, wilgotności, szansy opadów i zachmurzenia wypełnienie odpowiada wartości w skali 0–100 — nie zawsze jest to „cel”. Puls ma pełną obwódkę, gdy pomiar jest dostępny, ponieważ puls nie ma celu; inne dane bez sensownego celu mają szarą obwódkę. Po przekroczeniu celu postęp zatrzymuje się na 100%, a liczba nadal pokazuje rzeczywisty wynik. Brak danych oznaczamy `--`.

**Źródła danych:** zegarek udostępnia część wyników stale, a część tylko wtedy, gdy istnieje historia sensora, włączony pomiar lub aktualne dane Garmin Weather. SpO₂/Body Battery/pogoda i niektóre inne dane mogą być chwilowo niedostępne. Słońce opiera się na ostatniej dostępnej lokalizacji pogodowej, a w razie braku na ostatniej lokalizacji z systemu. Nie podajemy sztucznych wartości.

## Ustawianie bezpośrednio na zegarku

Po zainstalowaniu tarczy: przytrzymaj **MENU → Tarcza zegarka → Solar Rings 7X PL → Dostosuj → Ustawienia** (nazwy mogą być inne w zależności od wersji firmware). Na zegarku pojawi się lista:

- `Gora lewa`, `Gora prawa`
- `Kolo 1`, `Kolo 2`, `Kolo 3`, `Kolo 4`
- `Dol - glowne`, `Dol - pasek`
- `Kolor kola 1–4`
- `Burza: ikona` (włącz/wyłącz)
- `Burza: spadek` (2, 3, 4, 5, 6, 8 hPa / ~3 godz.)
- `Filtr wysokosci` (10, 15, 20, 30, 50, 75, 100 m)

Zapisane ustawienia korzystają z `Application.Storage` i **działają także przy ręcznym wgraniu `.PRG`** (bez sklepu Connect IQ). Ustawienia *przez telefon* po ręcznym sideloadzie nie są tutaj implementowane — nie obiecujemy tego. W obecnym projekcie zmiany można robić na zegarku.

## Wykrywanie podejrzanego spadku ciśnienia

**Domyślne:** włączona żółta, stała błyskawica, jeżeli ciśnienie **spadło o ≥4 hPa w ok. 3 godziny**. Skrypt:

- wymaga świeżej historii ciśnienia obejmującej co najmniej 2,5 godziny;
- wymaga również świeżej historii wysokości z tego okresu;
- jeśli zakres zmiany wskazywanej wysokości wyniesie **20 metrów lub więcej**, **nie pokazuje ostrzeżenia**;
- jeśli którejkolwiek historii brak, nie pokazuje ostrzeżenia (strategia konserwatywna);
- sprawdza wynik maksymalnie raz na 5 minut, bez migania i bez dodatkowego ciągłego odświeżania ekranu.

**Ograniczenie fizyczne:** wysokość odczytywana z zegarkowego wysokościomierza również może być wyznaczana na podstawie ciśnienia. Dlatego nawet ta metoda **nie potrafi niezawodnie rozróżnić pogody od zmiany wysokości**, czasem stłumi prawdziwy sygnał, a czasem dopuści fałszywy. To **wskaźnik pomocniczy, nie prognoza burzy ani niezawodny alert bezpieczeństwa**. Nie zastępuje alertów pogodowych. Algorytm nie uwzględnia niezależnego pomiaru wysokości GPS historycznego. Do celów bezpieczeństwa korzystaj z prognoz i ostrzeżeń meteorologicznych.

## Jak skompilować i wgrać przez Windows

1. Zainstaluj **Visual Studio Code**: https://code.visualstudio.com/
2. Zainstaluj **Garmin Connect IQ SDK Manager** i pobierz SDK: https://developer.garmin.com/connect-iq/sdk/
3. Zainstaluj w VS Code rozszerzenie **Monkey C** firmy Garmin.
4. Rozpakuj ZIP, otwórz w VS Code folder `SolarRings7XPro_2_0` (musi w nim być `manifest.xml`).
5. W razie potrzeby `Ctrl+Shift+P` → `Monkey C: Verify Installation`; wygeneruj własny klucz deweloperski, jeśli jeszcze go nie masz: `Monkey C: Generate a Developer Key`.
6. `Ctrl+Shift+P` → `Monkey C: Build Current Project` — testuj dla **fenix7xpro**, a jeśli trzeba dla **fenix7xpronowifi**. Uruchom w symulatorze i sprawdź wszystkie pozycje menu. **Jeżeli kompilacja zgłosi błędy, popraw je przed instalacją.**
7. `Ctrl+Shift+P` → `Monkey C: Build for Device`. Wybierz właściwy wariant zegarka, zapisz `.PRG`.
8. Podłącz Fenix 7X Pro Solar przewodem USB i skopiuj `.PRG` do `GARMIN/APPS` (nie ZIP).
9. Bezpiecznie odłącz zegarek i wybierz **Tarcza zegarka → Solar Rings 7X PL → Zastosuj**.
10. Wejdź w **Dostosuj / Ustawienia** tarczy i wybierz pola. Zmiany zostają zapisane lokalnie na zegarku.

Uwaga: przy aktualizacji wersji tej samej tarczy możliwe jest, że trzeba będzie odłączyć/podłączyć zegarek albo wybrać ponownie tarczę. Jeśli masz działającą poprzednią wersję, wykonaj kopię pliku przed podmianą.

## Struktura kodu

- `manifest.xml` — identyfikator projektu i zgodne modele.
- `monkey.jungle` — wskazanie katalogów źródeł i zasobów.
- `resources/strings.xml` — nazwa tarczy.
- `source/SolarRings7X.mc` — rysowanie tarczy i miejsca na pola.
- `source/Config.mc` — katalog danych, ustawienia na zegarku, menu wyboru.
- `source/FieldData.mc` — odczyty rzeczywistych danych i wyznaczanie zapełnienia pierścieni.
- `source/StormGuard.mc` — analityka spadku ciśnienia i konserwatywny filtr wysokości.

### Oficjalna dokumentacja

- https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityMonitor/Info.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/SensorHistory.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Weather.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AppBase.html
- https://developer.garmin.com/connect-iq/articles/user-experience-guidelines/Watch_Faces.html
