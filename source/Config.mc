using Toybox.Application.Storage as Storage;
using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;

// All configuration is stored ON THE WATCH. Works for USB sideloads too.
// Field identifiers are stable across versions.
function setting(key, fallback) {
    var value = Storage.getValue(key);
    return value == null ? fallback : value;
}

function fieldName(id) {
    var choices = [
        "Puste", "Tetno", "Kroki", "Body Battery", "Minuty tyg.",
        "Minuty dzis", "Kalorie", "Dystans", "Pietra w gore", "Pietra w dol",
        "Stres", "Pulsoksymetr", "Oddechy/min", "Regeneracja",
        "Wschod slonca", "Zachod slonca", "Pogoda", "Bateria",
        "Temperatura", "Odczuwalna", "Wilgotnosc", "Wiatr",
        "Cisnienie", "Wysokosc", "Cel krokow", "Cel minut",
        "Temp. max", "Temp. min", "Pasek ruchu", "Indeks UV",
        "Szansa deszczu", "Godzina", "Data", "Zachmurzenie"
    ];
    if (id < 0 || id >= choices.size()) { return "Puste"; }
    return choices[id];
}

function optionLabel(key, value) {
    if (key == "alertOn") { return value ? "Wlaczone" : "Wylaczone"; }
    if (key == "alertDrop") { return value.toString() + " hPa / 3h"; }
    if (key == "altFilter") { return value.toString() + " m"; }
    if (key == "ringColor1" || key == "ringColor2" || key == "ringColor3" || key == "ringColor4") {
        var names = ["Czerwony", "Zielony", "Niebieski", "Pomarancz", "Zolty", "Bialy", "Turkus"];
        if (value < 0 || value >= names.size()) { return "Domyslny"; }
        return names[value];
    }
    return fieldName(value);
}

function ringPalette(code) {
    if (code == 0) { return Gfx.COLOR_RED; }
    if (code == 1) { return Gfx.COLOR_GREEN; }
    if (code == 2) { return Gfx.COLOR_BLUE; }
    if (code == 3) { return Gfx.COLOR_ORANGE; }
    if (code == 4) { return Gfx.COLOR_YELLOW; }
    if (code == 5) { return Gfx.COLOR_WHITE; }
    return Gfx.COLOR_CYAN;
}

function addSetting(menu, title, key, fallback) {
    var value = setting(key, fallback);
    menu.addItem(new Ui.MenuItem(title, optionLabel(key, value), key, {}));
}

function makeSettingsMenu() {
    var menu = new Ui.Menu2({:title => "Solar Rings 7X"});
    addSetting(menu, "Gora lewa", "top1", 14);
    addSetting(menu, "Gora prawa", "top2", 15);
    addSetting(menu, "Kolo 1", "ring1", 1);
    addSetting(menu, "Kolo 2", "ring2", 2);
    addSetting(menu, "Kolo 3", "ring3", 3);
    addSetting(menu, "Kolo 4", "ring4", 4);
    addSetting(menu, "Dol - glowne", "bottomMain", 16);
    addSetting(menu, "Dol - pasek", "bottomMini", 17);
    addSetting(menu, "Kolor kola 1", "ringColor1", 0);
    addSetting(menu, "Kolor kola 2", "ringColor2", 1);
    addSetting(menu, "Kolor kola 3", "ringColor3", 2);
    addSetting(menu, "Kolor kola 4", "ringColor4", 3);
    addSetting(menu, "Burza: ikona", "alertOn", true);
    addSetting(menu, "Burza: spadek", "alertDrop", 4);
    addSetting(menu, "Filtr wysokosci", "altFilter", 20);
    return menu;
}

class SolarSettingsDelegate extends Ui.Menu2InputDelegate {
    var _menu;
    function initialize(menu) {
        Menu2InputDelegate.initialize();
        _menu = menu;
    }

    function onSelect(item) {
        var key = item.getId();
        var index = _menu.findItemById(key);
        if (key == "alertOn") {
            var next = !setting("alertOn", true);
            Storage.setValue("alertOn", next);
            item.setSubLabel(optionLabel(key, next));
            _menu.updateItem(item, index);
            return;
        }
        var choices = new Ui.Menu2({:title => "Wybierz wartosc"});
        if (key == "alertDrop") {
            var drops = [2, 3, 4, 5, 6, 8];
            for (var j = 0; j < drops.size(); j++) {
                choices.addItem(new Ui.MenuItem(drops[j].toString() + " hPa", null, drops[j], {}));
            }
        } else if (key == "altFilter") {
            var heights = [10, 15, 20, 30, 50, 75, 100];
            for (var k = 0; k < heights.size(); k++) {
                choices.addItem(new Ui.MenuItem(heights[k].toString() + " m", null, heights[k], {}));
            }
        } else if (key == "ringColor1" || key == "ringColor2" || key == "ringColor3" || key == "ringColor4") {
            for (var c = 0; c < 7; c++) {
                choices.addItem(new Ui.MenuItem(optionLabel(key, c), null, c, {}));
            }
        } else {
            for (var i = 0; i <= 33; i++) {
                choices.addItem(new Ui.MenuItem(fieldName(i), null, i, {}));
            }
        }
        Ui.pushView(choices, new SolarChoiceDelegate(key, _menu, index), Ui.SLIDE_IMMEDIATE);
    }
}

class SolarChoiceDelegate extends Ui.Menu2InputDelegate {
    var _key;
    var _menu;
    var _index;
    function initialize(key, menu, index) {
        Menu2InputDelegate.initialize();
        _key = key;
        _menu = menu;
        _index = index;
    }

    function onSelect(item) {
        var value = item.getId();
        Storage.setValue(_key, value);
        var parentItem = _menu.getItem(_index);
        if (parentItem != null) {
            parentItem.setSubLabel(optionLabel(_key, value));
            _menu.updateItem(parentItem, _index);
        }
        Ui.popView(Ui.SLIDE_IMMEDIATE);
    }
}
