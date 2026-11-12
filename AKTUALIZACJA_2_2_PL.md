# Solar Rings 7X - aktualizacja 2.2.0 (Fenix 7X Pro Solar MIP)

Co nowego:
- Ustawienia w Connect IQ na iPhone: 9 pol (w tym nowe gorne srodkowe), 35 typow danych w kazdym,
  4 kolory pierscieni, alarm spadku cisnienia i filtr wysokosci.
- NOWE pole na gorze, miedzy wschodem a zachodem: domyslnie faza Ksiezyca,
  moze tez pokazywac dowolna dana lub byc PUSTE (0).
- 4 pierscienie w ukl. 2 x 2 (wieksze napisy, czytelne wartosci), pod spodem pogoda i bateria.
- Zachowuje ID aplikacji i klucz deweloperski w GitHub Secrets.

## Aktualizacja istniejacego repozytorium GitHub
1. Najprosciej pobierz patch SolarRings7X_2_2_PODMIEN_PLIKI.zip.
2. Na GitHubie wejdz w Code > Add file > Upload files i wrzuc ROZPAKOWANA zawartosc patcha.
   Pilnuj, by zostaly sciezki source/..., resources/..., manifest.xml, bez dodatkowego folderu.
3. Zatwierdz Commit changes. Powinna wystartowac akcja Build Garmin Solar Rings 7X.
4. Po ZIELONYM wyniku pobierz Artifacts > SolarRings7XPro-build i wyjmij plik .IQ.
5. Garmin Developer > Solar Rings 7X > Upload New Version (nie tworz nowej aplikacji).
   Przeslij .IQ, wersja 2.2.0, pozostaw Beta.
6. iPhone Connect IQ > Urzadzenie > Moje tarcze > Solar Rings 7X > Update.
7. Po synchronizacji wejdź do Ustawienia (Settings) tarczy w Connect IQ.

Uwaga: czesc numerow i poziomow sensorow Garmin moze zwracac --.
Faza Ksiezyca jest przyblizona i wyznaczana lokalnie. Wskaznik burz nie jest prognoza.
Kompilacja aktualizacji wymaga GitHub Actions; sam kod nie zostal zweryfikowany
lokalnym kompilatorem Garmin. Jesli build bedzie czerwony, przekaz LOG bledu.
