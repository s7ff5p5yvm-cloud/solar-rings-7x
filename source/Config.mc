using Toybox.Application.Properties as Props;
using Toybox.Graphics as Gfx;

// Cache ONLY persisted settings; dynamic device data is never cached here.
// All entries are invalidated on AppBase.onSettingsChanged().
// A 64-entry cap covers every known persisted setting (58) while bounding RAM.
var _srSettingCache = {};
var _srSettingCacheSize = 0;

function srResetSettingsCache() {
    _srSettingCache = {};
    _srSettingCacheSize = 0;
}

// Mobile app settings. All default keys are defined in resources/settings/properties.xml.
// Deliberately use NEW keys so stale v2.x settings cannot unexpectedly override
// the new three-ring layout. All 8 visible slots are selectable from the phone.
function srSetting(key, fallback) {
    // Version 3.18: font controls removed from Connect IQ settings because
    // they were not reliable on the MIP screen. Preserve the accepted layout
    // and ignore values persisted by previous versions of the phone app.
    if (key == "fontClockV31" || key == "fontDateV31" ||
        key == "fontTopV31" || key == "fontRingV31" ||
        key == "fontWeatherV31") { return 2; }
    if (key == "fontFaceV36") { return 0; }
    if (key == "fontExtraV36") { return 1; }
    if (key == "sizeTopLeftV37" || key == "sizeTopMidV37" ||
        key == "sizeTopRightV37" || key == "sizeRingLeftV37" ||
        key == "sizeRingMidV37" || key == "sizeRingRightV37" ||
        key == "sizeWeatherValueV37" || key == "sizeWeatherLabelV37" ||
        key == "sizeFooterV37" || key == "moonFontV38") { return -1; }
    var cached = _srSettingCache[key];
    if (cached != null) { return cached; }
    try {
        var value = Props.getValue(key);
        if (value != null) {
            if (_srSettingCacheSize < 64) {
                _srSettingCache[key] = value;
                _srSettingCacheSize += 1;
            }
            return value;
        }
    } catch (e) { }
    return fallback;
}

function srColor(value) {
    if (value == 0) { return Gfx.COLOR_RED; }
    if (value == 1) { return Gfx.COLOR_GREEN; }
    if (value == 2) { return Gfx.COLOR_BLUE; }
    if (value == 3) { return Gfx.COLOR_ORANGE; }
    if (value == 4) { return Gfx.COLOR_YELLOW; }
    if (value == 5) { return Gfx.COLOR_WHITE; }
    return 0x00FFFF;
}
