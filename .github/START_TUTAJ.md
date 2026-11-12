# Solar Rings 7X 2.3 — poprawka do istniejącego GitHuba

Ta paczka jest aktualizacją projektu, nie aplikacją .IQ ani .PRG. Pozostaw dotychczasowy klucz podpisu w GitHub Secrets i nie pokazuj go nikomu.

1. Otwórz na GitHubie repozytorium `solar-rings-7x` i wykonaj kopię przez Code → Download ZIP.
2. Rozpakuj niniejszy ZIP.
3. W swoim repozytorium usuń **dwa stare pliki**: `resources/settings.xml` oraz `resources/properties.xml` (Code → plik → ... → Delete file → Commit changes). Zostaw resztę zasobów. Te stare definicje są zastępowane przez podfolder `resources/settings/`.
4. W Code → Add file → Upload files przeciągnij zawartość rozpakowanej paczki (zachowaj strukturę folderów). Potwierdź nadpisanie plików `source/`, `resources/`, `tests/` i `manifest.xml` oraz Commit changes. Można to zrobić także przez Git z komputera.
5. Sprawdź, że repozytorium zawiera `resources/settings/settings.xml` i `resources/settings/properties.xml` i NIE zawiera `resources/settings.xml` ani `resources/properties.xml`.
6. Uruchom Actions → Build Garmin Solar Rings 7X. Jeśli czerwony status: otwórz Compile watch face PRG i prześlij log błędu. Jeśli zielony: pobierz nowy `.IQ` z Artifacts.
7. W Garmin Developer przy istniejącej aplikacji wybierz **Upload New Version**, numer `2.3.0` i zaznacz Beta. **Nie dodawaj nowej aplikacji**; poprzedni identyfikator aplikacji pozostał bez zmian. Przesłanie wersji do sklepu musi wykonać uprawniony pełnoletni deweloper.
8. Po aktualizacji na iPhone otwórz Connect IQ → Urządzenie → Moje tarcze → Solar Rings 7X → Ustawienia. To jest lista ZAINSTALOWANYCH tarcz, a nie strona katalogowa sklepu.

## Co naprawiono
- Cztery pierścienie w układzie 2×2 ze zwięzłymi, wektorowymi ikonami i cyframi w ich wnętrzu.
- Kroki 10 000–99 999 wyświetlane w całości, np. `12345`, `25000` (bez `/10k`), postęp wskazuje zapełnienie obwódki.
- Osobne miejsca na górne trzy pola (Księżyc lub puste w środku), pierścienie, pogodę i baterię.
- Ustawienia mobilne mają standardową strukturę `resources/settings/`.
- 35 rodzajów danych na każde z 9 pól oraz kolory czterech pierścieni i filtr alarmu ciśnieniowego.

## Ograniczenia
Kompilacja i test na fizycznym Fenixie 7X Pro Solar są jeszcze wymagane. Testy statyczne i XML nie potwierdzają renderingu ani działania opcji na iPhone. Brak danych czujnika jest pokazywany jako `--`. Wskaźnik burzy nie zastępuje ostrzeżenia meteorologicznego.
