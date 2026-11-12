# Solar Rings 7X PL — kompilacja ONLINE przez GitHub Actions

## Co zawiera ta paczka?
- Nasz oryginalny kod źródłowy tarczy 2.0 (wciąż **nieprzetestowany kompilatorem**).
- `.github/workflows/build-garmin.yml` — automatyczny workflow kompilacji Garmin Connect IQ 9.3.0 dla `fenix7xpro`.
- `manifest.xml` i `monkey.jungle` w **głównym katalogu** projektu.

## 1. Repozytorium GitHub
1. Otwórz https://github.com/new i zaloguj się na swoje osobiste konto GitHub.
2. Nazwa: `solar-rings-7x`.
3. **Visibility: Private** (na czas testowania). Zaznacz `Add a README file` lub utwórz puste repozytorium; obie opcje działają.
4. Wybierz **Create repository**.
5. Rozpakuj tę paczkę na komputerze. Otwórz folder `SolarRings7X_GitHub_Online` i **przeciągnij do GitHuba jego zawartość**, nie sam ZIP i nie dodatkowy katalog nadrzędny. W repozytorium obok siebie powinny być `manifest.xml`, `monkey.jungle`, `source/`, `resources/` i `.github/workflows/build-garmin.yml`.
6. W GitHub: **Add file → Upload files**, przeciągnij wszystkie pliki i foldery z rozpakowanego katalogu. Zatwierdź **Commit changes**.

## 2. Uruchom kompilację
1. Wejdź w **Actions** w repozytorium.
2. Wybierz workflow `Build Garmin Solar Rings 7X`.
3. Naciśnij **Run workflow** → zielony przycisk **Run workflow**. Workflow może też wystartować sam po dodaniu plików (`push` na `main`).
4. Otwórz najnowsze uruchomienie → `Compile for fenix7xpro` i sprawdź kroki kompilacji.
5. Zielony status oznacza, że plik `.PRG` został wygenerowany. Na stronie uruchomienia w sekcji **Artifacts** wybierz `SolarRings7XPro-build` — pobierzesz ZIP zawierający `.PRG`. Nie należy mylić tego ZIP-a z plikiem do wgrania na zegarek.
6. Jeżeli jest czerwony status, otwórz nieudany krok i skopiuj log z liniami `ERROR` oraz ich okolicą. Wyślij je w czacie, aby poprawić kod. Pierwsza kompilacja może wykazać problemy w nieprzetestowanych źródłach.

## 3. Wgranie na Garmin Fenix 7X Pro Solar
- Po **udanej kompilacji** rozpakuj pobrane `SolarRings7XPro-build.zip`, w środku będzie `SolarRings7XPro.prg`.
- Podłącz zegarek do komputera, na którym wolno podłączać urządzenia USB i zapisywać na nich pliki; skopiuj `.prg` do `GARMIN/APPS`. Bezpiecznie odłącz i wybierz tarczę na zegarku.
- Sama poprawna kompilacja nie gwarantuje działania wszystkich danych, menu i ostrzeżenia burzowego — trzeba przetestować zegarek.

## Klucz podpisu — istotne przed publikacją
- Jeśli nie ustawisz `CONNECTIQ_DEVELOPER_KEY_BASE64` w **Settings → Secrets and variables → Actions → New repository secret**, workflow automatycznie tworzy **tymczasowy** klucz do testowego `.PRG` na każde uruchomienie.
- **Nie publikuj** aplikacji do Connect IQ Store z tymczasowym kluczem. Do aktualizowania publikowanej tarczy wymagany jest własny, stały 4096-bitowy klucz prywatny RSA w DER; przechowuj jego kopię poza repozytorium i dodaj jedynie zakodowaną w Base64 zawartość jako GitHub Actions Secret (nie jako plik w repozytorium).
- Gdy skonfigurujesz stały klucz, workflow spróbuje również wygenerować `.IQ` do sklepu. Najpierw popraw kompilację i przetestuj aplikację.

## Ważne
- SDK pobiera z serwerów Garmina działanie społecznościowe `DuckSoft/setup-connectiq-actions@v1`. Przejrzyj jego kod przed użyciem; to **zewnętrzny, nieoficjalny** GitHub Action.
- Uruchamiaj tylko na GitHubie zgodnie z zasadami korzystania z firmowej sieci i urządzeń. Nie wyłączaj zabezpieczeń komputera.
- Akceptacja licencji Garmin Connect IQ SDK jest wymagana: https://developer.garmin.com/connect-iq/sdk/.
