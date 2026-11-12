# Solar Rings 7X v2.5 — aktualizacja

- Cała tarcza używa kontrolowanej czcionki pikselowej zamiast systemowej, żeby elementy nie nakładały się na siebie.
- Duże cyfry wewnątrz 4 kółek 2x2; do 6 cyfr kroków bez ucinania (12 345, 99 999, 999 999).
- Wschód + opcjonalny Księżyc + zachód; osobna pogoda i bateria.
- Bateria ma ikonę akumulatora, a nie błyskawicę; ostrzeżenie burzowe wyłączone przy pierwszym uruchomieniu tej wersji.
- 16 ustawień mobilnych: dziewięć wybieranych pól, cztery kolory i trzy ustawienia burzy; bez problematycznego grupowania.
- Build GitHub Actions sprawdza, czy .IQ zawiera rzeczywisty JSON ustawień mobilnych.

**Bardzo ważne**: skopiowanie .PRG przez USB nie daje ustawień w Connect IQ na iPhonie. Po udanym buildzie .IQ i teście obecności JSON ustawień zainstaluj aktualizację ze sklepu Connect IQ (beta). Usuń starszą kopię wgraną ręcznie, aby nie mieć dwóch różnych instalacji.

Podgląd PNG to schemat rozkładu, nie zrzut z symulatora. W lokalnym środowisku nie ma Garmin SDK; przed użyciem wymagane są test kompilacji i test na zegarku.
