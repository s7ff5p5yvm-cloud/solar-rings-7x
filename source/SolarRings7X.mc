using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as System;
using Toybox.Time as Time;
using Toybox.Time.Gregorian as Gregorian;
using Toybox.Weather as Weather;
using Toybox.ActivityMonitor as Monitor;
using Toybox.Math as Math;

// Immutable labels: avoid two new arrays on every high-power redraw.
var _srDays = ["ND", "PN", "WT", "SR", "CZ", "PT", "SB"];
var _srMonths = ["STY", "LUT", "MAR", "KWI", "MAJ", "CZE",
                 "LIP", "SIE", "WRZ", "PAZ", "LIS", "GRU"];

var _srMoonExtents7 = [0.000000000000000, 3.605551275463989, 4.898979485566356, 5.744562646538029, 6.324555320336759, 6.708203932499369, 6.928203230275509, 7.000000000000000, 6.928203230275509, 6.708203932499369, 6.324555320336759, 5.744562646538029, 4.898979485566356, 3.605551275463989, 0.000000000000000];
var _srMoonExtents12 = [0.000000000000000, 4.795831523312719, 6.633249580710800, 7.937253933193772, 8.944271909999159, 9.746794344808963, 10.392304845413264, 10.908712114635714, 11.313708498984761, 11.618950038622250, 11.832159566199232, 11.958260743101398, 12.000000000000000, 11.958260743101398, 11.832159566199232, 11.618950038622250, 11.313708498984761, 10.908712114635714, 10.392304845413264, 9.746794344808963, 8.944271909999159, 7.937253933193772, 6.633249580710800, 4.795831523312719, 0.000000000000000];

// Core watch-face application. No network requests or background tasks.
class SolarRings7XApp extends App.AppBase {
    var _face;
    function initialize() { AppBase.initialize(); _face = null; }

    function getInitialView() {
        _face = new SolarRingsFaceV3();
        return [_face];
    }

    function onStart(state) { AppBase.onStart(state); }

    function onSettingsChanged() {
        try {
            srResetSettingsCache();
            if (_face != null) {
                _face.resetWeatherWarningCache();
                _face.resetPerformanceCaches();
            }
            Ui.requestUpdate();
        } catch (e) { }
    }
}

class SolarRingsFaceV3 extends Ui.WatchFace {
    var _storm;
    var _weatherWarnings;
    var _weatherWarningVisible;
    var _lastDrawnWeatherWarning;
    var _fontCache;
    var _fontCacheCount;
    var _lowMemory;
    var _sizedFitCache;
    var _sizedFitCacheSize;
    var _clockFitCache;
    var _tempFitCache;
    var _cachedWeather;
    var _cachedWeatherAt;
    var _moonCosCache;
    var _frameFieldResults;
    var _frameEpoch;
    var _dateTextCache;
    var _ageTextCache;
    var _clockTextCache;

    function initialize() {
        WatchFace.initialize();
        _storm = new StormGuard();
        _weatherWarnings = new GarminWeatherWarnings();
        _weatherWarningVisible = false;
        _lastDrawnWeatherWarning = 0;
        _fontCache = {};
        _fontCacheCount = 0;
        _lowMemory = false;
        resetPerformanceCaches();
    }

    function resetPerformanceCaches() {
        _sizedFitCache = {};
        _sizedFitCacheSize = 0;
        _clockFitCache = null;
        _tempFitCache = null;
        _cachedWeather = null;
        _cachedWeatherAt = 0;
        _moonCosCache = null;
        _frameFieldResults = {};
        _frameEpoch = 0;
        _dateTextCache = null;
        _ageTextCache = null;
        _clockTextCache = null;
    }

    // Read a selected field at most once per render. The generation number
    // changes for EVERY full update (even in 1 Hz high-power mode): HR, steps,
    // battery and goals are not cached between redraws. Reuse small storage
    // instead of building a new Dictionary on each wrist gesture.
    function frameField(id, monitor, weather) {
        var entry = _frameFieldResults[id];
        if (entry != null && entry[0] == _frameEpoch) { return entry[1]; }
        var result = readField(id, monitor, weather);
        if (entry == null) {
            _frameFieldResults[id] = [_frameEpoch, result];
        } else {
            entry[0] = _frameEpoch;
            entry[1] = result;
        }
        return result;
    }

    // The weather object is the last observation already held by Garmin,
    // not a direct network download. 10s caching avoids asking the SDK for
    // the same object on every high-power redraw; every minute still refreshes.
    function getCachedConditions() {
        var now = Time.now().value();
        if (_cachedWeatherAt != 0 && now >= _cachedWeatherAt &&
            now - _cachedWeatherAt < 10) { return _cachedWeather; }
        _cachedWeatherAt = now;
        try { _cachedWeather = Weather.getCurrentConditions(); }
        catch (e) { _cachedWeather = null; }
        return _cachedWeather;
    }

    function resetWeatherWarningCache() {
        if (_weatherWarnings != null) { _weatherWarnings.reset(); }
        _weatherWarningVisible = false;
        _lastDrawnWeatherWarning = 0;
    }

    // Select genuinely different font sizes for SMALL / NORMAL / LARGE.
    // Always fit the selected font to a reserved box; never draw outside it.
    // IMPORTANT: using a single dynamic largest-fit list made small and
    // large look identical in v3.1. This implementation uses distinct caps.
    // 3.5: native Garmin text throughout. Earlier versions drew clock and
    // ring numbers one bitmap rectangle at a time and sometimes showed NO
    // values on the real MIP screen. One Dc.drawText per value avoids it.
    // This renderer NEVER changes the clip region and always has a fallback.
    function fitScaled(dc, value, x, top, width, height, color, numeric, scale) {
        if (value == null || width <= 0 || height <= 0) { return; }
        var str = value.toString();
        if (str.length() == 0) { return; }
        var numberOnly = numeric;
        if (numberOnly) {
            for (var i = 0; i < str.length(); i++) {
                var c = str.substring(i, i + 1);
                if ("0123456789:".find(c) == null) {
                    numberOnly = false;
                    break;
                }
            }
        }
        var fonts;
        if (numberOnly) {
            if (scale <= 0) {
                fonts = [Gfx.FONT_SMALL, Gfx.FONT_TINY, Gfx.FONT_XTINY];
            } else if (scale == 1) {
                fonts = [Gfx.FONT_NUMBER_MILD, Gfx.FONT_SMALL,
                         Gfx.FONT_TINY, Gfx.FONT_XTINY];
            } else {
                fonts = [Gfx.FONT_NUMBER_HOT, Gfx.FONT_NUMBER_MEDIUM,
                         Gfx.FONT_NUMBER_MILD, Gfx.FONT_MEDIUM,
                         Gfx.FONT_SMALL, Gfx.FONT_TINY, Gfx.FONT_XTINY];
            }
        } else {
            if (scale <= 0) {
                fonts = [Gfx.FONT_SMALL, Gfx.FONT_TINY, Gfx.FONT_XTINY];
            } else if (scale == 1) {
                fonts = [Gfx.FONT_MEDIUM, Gfx.FONT_SMALL,
                         Gfx.FONT_TINY, Gfx.FONT_XTINY];
            } else {
                fonts = [Gfx.FONT_LARGE, Gfx.FONT_MEDIUM,
                         Gfx.FONT_SMALL, Gfx.FONT_TINY, Gfx.FONT_XTINY];
            }
        }
        var chosen = Gfx.FONT_XTINY;
        var textH = dc.getFontHeight(chosen);
        for (var j = 0; j < fonts.size(); j++) {
            var dim = dc.getTextDimensions(str, fonts[j]);
            if (dim[0] <= width && dim[1] <= height) {
                chosen = fonts[j];
                textH = dim[1];
                break;
            }
        }
        // No pixel rectangles and NO setClip(): every field is visible.
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        var yy = top + ((height - textH) / 2).toNumber();
        dc.drawText(x, yy, chosen, str, Gfx.TEXT_JUSTIFY_CENTER);
    }

    // NEW v3.6: scalable fonts available on Fenix 7X Pro (Connect IQ 4.2.2+).
    // RobotoCondensedBold is an installed system face, NOT a bundled font file.
    // The optional style and increase settings affect every visible data field.
    function desiredPixels(settingKey, normalSize, increment) {
        var level = srSetting(settingKey, 2);
        if (level < 0) { level = 0; }
        if (level > 2) { level = 2; }
        return normalSize + (level - 1) * increment +
               (srSetting("fontExtraV36", 1) * 2);
    }

    // v3.7: Independent field size controls, with backwards-compatible group
    // settings as defaults. -1 means inherit the existing group setting.
    // 0..4 map to XS / Small / Medium / Large / XL.
    function fieldPixels(fieldKey, groupKey, normalSize, step) {
        var chosen = srSetting(fieldKey, -1);
        if (chosen == -1) {
            var groupLevel = srSetting(groupKey, 2);
            if (groupLevel < 0) { groupLevel = 0; }
            if (groupLevel > 2) { groupLevel = 2; }
            chosen = groupLevel * 2;
        }
        if (chosen < 0) { chosen = 0; }
        if (chosen > 4) { chosen = 4; }
        return normalSize + (chosen - 2) * step +
               (srSetting("fontExtraV36", 1) * 2);
    }

    function fieldScale(fieldKey, groupKey) {
        var level = srSetting(fieldKey, -1);
        if (level < 0) { return srSetting(groupKey, 2); }
        if (level <= 1) { return 0; }
        if (level == 2) { return 1; }
        return 2;
    }

    function vectorFontFor(pixels, digits) {
        var style = srSetting("fontFaceV36", 0);
        if (style == 4) { return null; } // Garmin native-only fallback
        var face = "RobotoCondensedBold";
        if (style == 1) { face = "RobotoCondensedRegular"; }
        else if (style == 2) { face = "ExoSemiBold"; }
        else if (style == 3 && digits) { face = "BionicBold"; }
        var key = face + ":" + pixels.toString();
        var cached = _fontCache[key];
        if (cached != null) { return cached; }
        var found = null;
        try { found = Gfx.getVectorFont({:face => face, :size => pixels}); }
        catch (e) { }
        // Avoid retaining an unbounded number of vector font handles.
        // Garmin watch faces have a strict memory budget.
        if (found != null && _fontCacheCount < 20) {
            _fontCache[key] = found;
            _fontCacheCount += 1;
        }
        return found;
    }

    // v3.24.20: test the requested font first (fast path), then binary-search
    // the largest size that actually fits. Previously we constructed/measured
    // every intermediate 1px font on long values and on each wrist gesture.
    // Rendering, bounds, fonts and the smallest 10px fallback are unchanged.
    function drawSized(dc, value, x, top, width, height, color, digits, sizePixels, fallbackScale) {
        if (value == null || width <= 0 || height <= 0) { return; }
        var str = value.toString();
        if (str.length() == 0) { return; }
        if (_lowMemory) {
            fitScaled(dc, str, x, top, width, height, color, digits, fallbackScale);
            return;
        }
        // x and top are 0..279 in this 280px design; numeric keys avoid
        // creating temporary concatenated strings on every screen redraw.
        var slotKey = x * 512 + top;
        var cached = _sizedFitCache[slotKey];
        var selected = null;
        var selectedDimensions = null;
        var canReuse = cached != null && cached[0] == str &&
                       cached[1] == sizePixels && cached[2] == digits &&
                       cached[6] == width && cached[7] == height;
        if (canReuse) {
            selected = cached[4];
            selectedDimensions = cached[5];
        }
        if (!canReuse) { try {
            var requestedFont = vectorFontFor(sizePixels, digits);
            if (requestedFont != null) {
                var dim = dc.getTextDimensions(str, requestedFont);
                if (dim[0] <= width && dim[1] <= height) {
                    selected = requestedFont;
                    selectedDimensions = dim;
                } else {
                    var low = 10;
                    var high = sizePixels - 1;
                    while (low <= high) {
                        var mid = ((low + high) / 2).toNumber();
                        var font = vectorFontFor(mid, digits);
                        if (font == null) { break; }
                        dim = dc.getTextDimensions(str, font);
                        if (dim[0] <= width && dim[1] <= height) {
                            selected = font;
                            selectedDimensions = dim;
                            low = mid + 1;
                        } else {
                            high = mid - 1;
                        }
                    }
                }
            }
        } catch (e) {
            selected = null;
        }
            // Cache the fit (including a failed fit) for the exact slot/value.
            // Later value changes and font settings automatically invalidate it.
            if (selected != null && (cached != null || _sizedFitCacheSize < 16)) {
                if (cached == null) { _sizedFitCacheSize += 1; }
                _sizedFitCache[slotKey] = [str, sizePixels, digits,
                                         0, selected, selectedDimensions,
                                         width, height];
            } else if (cached != null && selected == null) {
                _sizedFitCache.remove(slotKey);
                _sizedFitCacheSize -= 1;
            }
        }
        if (selected != null) {
            dc.setColor(color, Gfx.COLOR_TRANSPARENT);
            var yy = top + ((height - selectedDimensions[1]) / 2).toNumber();
            dc.drawText(x, yy, selected, str, Gfx.TEXT_JUSTIFY_CENTER);
            return;
        }
        fitScaled(dc, str, x, top, width, height, color, digits, fallbackScale);
    }

    function fit(dc, value, x, top, width, height, color, numeric) {
        fitScaled(dc, value, x, top, width, height, color, numeric, 1);
    }


    // Truly visible large clock. Font sizes are measured on the actual device,
    // so changing small/medium/large in the iPhone app changes the candidate
    // set and still fits the reserved 145 x 53 px area.
    // v3.12: wider 164px bold clock, still separate from the unchanged date.
    // Distinct target sizes (small/medium/large) avoid prior settings collapsing
    // to one size. Actual glyph bounds are measured before drawing.
    function clockBoldFont(pixels) {
        var key = "CLOCKB:" + pixels.toString();
        var cached = _fontCache[key];
        if (cached != null) { return cached; }
        var font = Gfx.getVectorFont({:face => "RobotoCondensedBold", :size => pixels});
        if (font != null && _fontCacheCount < 20) {
            _fontCache[key] = font;
            _fontCacheCount += 1;
        }
        return font;
    }

    function drawClock(dc, clock) {
        // Only the formatted text is reused during high-power 1Hz redraws.
        // Clock state and its font settings are still evaluated on every frame.
        var minuteOfDay = clock.hour * 60 + clock.min;
        var value = null;
        if (_clockTextCache != null && _clockTextCache[0] == minuteOfDay) {
            value = _clockTextCache[1];
        } else {
            value = twoDigits(clock.hour) + ":" + twoDigits(clock.min);
            _clockTextCache = [minuteOfDay, value];
        }
        var pref = srSetting("fontClockV31", 2);
        var requested = 62;
        if (pref <= 0) { requested = 46; }
        else if (pref == 1) { requested = 54; }
        requested += srSetting("fontExtraV36", 1) * 2;
        // Horizontal position is deliberately separated from the date box.
        // 77..129 is the full vertical band between the rules at 76 and 130.
        var cx = 97;
        var top = 77;
        var slotW = 164;
        var slotH = 52;
        if (_lowMemory) {
            fitScaled(dc, value, cx, top, slotW, slotH,
                      Gfx.COLOR_WHITE, true, pref);
            return;
        }
        // Keep the existing double-stroke clock, but avoid checking every
        // intermediate font size on each high-power 1 Hz redraw.
        var chosenFont = null;
        var chosenDimensions = null;
        var clockCached = _clockFitCache;
        var clockMatch = clockCached != null &&
                         clockCached[0] == value && clockCached[1] == requested;
        if (clockMatch) {
            chosenFont = clockCached[2];
            chosenDimensions = clockCached[3];
        }
        if (!clockMatch) { try {
            var first = clockBoldFont(requested);
            if (first != null) {
                var dim = dc.getTextDimensions(value, first);
                if (dim[0] + 3 <= slotW && dim[1] <= slotH) {
                    chosenFont = first;
                    chosenDimensions = dim;
                } else {
                    var low = 32;
                    var high = requested - 1;
                    while (low <= high) {
                        var mid = ((low + high) / 2).toNumber();
                        var probe = clockBoldFont(mid);
                        if (probe == null) { break; }
                        dim = dc.getTextDimensions(value, probe);
                        if (dim[0] + 3 <= slotW && dim[1] <= slotH) {
                            chosenFont = probe;
                            chosenDimensions = dim;
                            low = mid + 1;
                        } else {
                            high = mid - 1;
                        }
                    }
                }
            }
        } catch (e) { chosenFont = null; }
            // A transient vector-font failure must not be cached forever.
            _clockFitCache = chosenFont == null ? null :
                             [value, requested, chosenFont, chosenDimensions];
        }
        if (chosenFont != null) {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            var yy = top + ((slotH - chosenDimensions[1]) / 2).toNumber();
            dc.drawText(cx, yy, chosenFont, value, Gfx.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx + 1, yy, chosenFont, value, Gfx.TEXT_JUSTIFY_CENTER);
            return;
        }
        // Fallback on devices that cannot render the vector typeface.
        drawSized(dc, value, cx, top, slotW, slotH, Gfx.COLOR_WHITE, true,
                  requested, pref);
    }

    // Mini digits for compact times and symbols are kept below.

    function miniGlyph(ch) {
        if (ch == "0") { return ["111","101","101","101","101","101","111"]; }
        if (ch == "1") { return ["010","110","010","010","010","010","111"]; }
        if (ch == "2") { return ["111","001","001","111","100","100","111"]; }
        if (ch == "3") { return ["111","001","001","111","001","001","111"]; }
        if (ch == "4") { return ["101","101","101","111","001","001","001"]; }
        if (ch == "5") { return ["111","100","100","111","001","001","111"]; }
        if (ch == "6") { return ["111","100","100","111","101","101","111"]; }
        if (ch == "7") { return ["111","001","001","010","010","010","010"]; }
        if (ch == "8") { return ["111","101","101","111","101","101","111"]; }
        if (ch == "9") { return ["111","101","101","111","001","001","111"]; }
        if (ch == ":") { return ["0","1","1","0","1","1","0"]; }
        return ["000","000","000","000","000","000","000"];
    }

    // Fixed-width 3x7 glyphs. All writes are confined to the intended
    // region; use only filled rectangles so this works without font assets.
    function drawPixelDigits(dc, value, centerX, top, pixel, color) {
        if (value == null || value.length() == 0) { return; }
        var units = 0;
        for (var i = 0; i < value.length(); i++) {
            var g = miniGlyph(value.substring(i, i + 1));
            units += g[0].length() + 1;
        }
        units -= 1;
        var x = (centerX - (units * pixel) / 2).toNumber();
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        for (var k = 0; k < value.length(); k++) {
            var glyph = miniGlyph(value.substring(k, k + 1));
            for (var row = 0; row < 7; row++) {
                var bits = glyph[row];
                for (var col = 0; col < bits.length(); col++) {
                    if (bits.substring(col, col + 1) == "1") {
                        dc.fillRectangle(x + col * pixel, top + row * pixel,
                                         pixel, pixel);
                    }
                }
            }
            x += (glyph[0].length() + 1) * pixel;
        }
    }

    function onlyDigits(str) {
        if (str == null || str.length() == 0) { return false; }
        for (var i = 0; i < str.length(); i++) {
            if ("0123456789".find(str.substring(i, i + 1)) == null) {
                return false;
            }
        }
        return true;
    }
    // Sunrise and sunset times use a larger measured Garmin font.
    function drawTopClock(dc, value, center, sizeKey, slotWidth) {
        drawSized(dc, value, center, 50, slotWidth, 23,
                  Gfx.COLOR_WHITE, true,
                  fieldPixels(sizeKey, "fontTopV31", 21, 2),
                  fieldScale(sizeKey, "fontTopV31"));
    }

    // Date is on the right of the clock; the two lines are individually
    // fitted to 72px. No clips which can hide the clock or ring values.
    function drawDate(dc, dayLabel, dateLabel) {
        var settingSize = srSetting("fontDateV31", 2);
        // Move date just 5px left, preserving its original font settings.
        // Clock position and font remain completely unchanged.
        drawSized(dc, dayLabel, 197, 80, 58, 23,
                  Gfx.COLOR_WHITE, false,
                  desiredPixels("fontDateV31", 27, 3), settingSize);
        drawSized(dc, dateLabel, 197, 104, 58, 25,
                  Gfx.COLOR_WHITE, false,
                  desiredPixels("fontDateV31", 24, 3), settingSize);
    }

    // Connection status as reported by the Garmin device (not internet reachability).
    // True: green Bluetooth; false: red Bluetooth with an oblique strike.
    // No network calls, no new permissions, no separate settings required.
    function drawPhoneBluetooth(dc) {
        var connected = false;
        try {
            connected = System.getDeviceSettings().phoneConnected;
        } catch (e) { connected = false; }

        var btColor = connected ? 0x00DD77 : 0xFF5555;
        dc.setColor(btColor, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);

        // Standard angular Bluetooth rune, centered at (234, 116).
        // Coordinates stay inside x=229..239 and y=108..124.
        dc.drawLine(234, 108, 234, 124);
        dc.drawLine(234, 108, 239, 112);
        dc.drawLine(239, 112, 229, 120);
        dc.drawLine(229, 112, 239, 120);
        dc.drawLine(239, 120, 234, 124);

        if (!connected) {
            // Contrast outline keeps the red slash visible across the rune.
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(3);
            dc.drawLine(229, 124, 239, 108);
            dc.setColor(btColor, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawLine(229, 124, 239, 108);
        }
        dc.setPenWidth(1);
    }

    // Observation age supplied by Garmin Weather. This does not trigger
    // any additional network requests or change the existing alert logic.
    function drawWeatherAge(dc, current) {
        var ageLabel = "--";
        var ageColor = 0xFF5555;
        try {
            if (current != null && current.observationTime != null) {
                var seconds = Time.now().value() - current.observationTime.value();
                if (seconds >= 0) {
                    var minutes = (seconds / 60).toNumber();
                    if (_ageTextCache != null && _ageTextCache[0] == minutes) {
                        ageLabel = _ageTextCache[1];
                        ageColor = _ageTextCache[2];
                    } else {
                        if (minutes < 50) {
                            ageLabel = minutes.toString() + "m";
                        } else if (minutes < 60) {
                            // User preference: switch to 1h at 50 minutes.
                            ageLabel = "1h";
                        } else {
                            var hours = (minutes / 60).toNumber();
                            var remainingMinutes = minutes - (hours * 60);
                            if (remainingMinutes == 0 || hours >= 10) {
                                // Abbreviate extremely old observations to stay readable.
                                ageLabel = hours.toString() + "h";
                            } else {
                                ageLabel = hours.toString() + "h" + remainingMinutes.toString() + "m";
                            }
                        }
                        if (minutes <= 30) { ageColor = 0x00DD77; }
                        else if (minutes <= 60) { ageColor = 0xFFCC33; }
                        _ageTextCache = [minutes, ageLabel, ageColor];
                    }
                }
            }
        } catch (e) { ageLabel = "--"; ageColor = 0xFF5555; }

        // The icon now represents the REAL phone connection state, independent
        // of the age/color of the Garmin Weather observation.
        // Reserved space: icon x=229..239, number x=242..278.
        // Never move/resize the actual clock or date for this icon.
        drawPhoneBluetooth(dc);

        // Long values (for example 1h30m, 9h59m) resize only this label.
        // Date and main clock retain their original font sizes.
        drawSized(dc, ageLabel, 260, 104, 36, 24, ageColor, false, 16, 0);
    }

    // Native 1px separators, including the two vertical ones requested
    // between the sunrise / moon / sunset fields.
    function rule(dc, y) {
        dc.setColor(0x696969, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        if (y == 250) {
            dc.drawLine(100, y, 190, y);
        } else if (y == 163) {
            // Short separator leaves the moon symbol and the outer rim clear.
            dc.drawLine(99, y, 242, y);
        } else {
            dc.drawLine(28, y, 252, y);
        }
    }

    function topDividers(dc) {
        dc.setColor(0x888888, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(107, 29, 107, 70);
        dc.drawLine(163, 29, 163, 70);
    }

    function weatherDivider(dc) {
        dc.setColor(0xAAAAAA, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(109, 220, 109, 245);
    }

    // Different shapes for sunrise and sunset, not just different colors.
    // Both icons fit within x-12..x+15, y-9..y+8 on the 280px face.
    // Sunrise: arrow UP. Sunset: arrow DOWN.
    function sunIcon(dc, x, y, isRise) {
        dc.setColor(isRise ? 0xFFE8A0 : 0xFF7799, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawArc(x - 2, y + 6, 6, Gfx.ARC_COUNTER_CLOCKWISE, 0, 180);
        dc.drawLine(x - 12, y + 7, x + 9, y + 7);
        dc.setPenWidth(1);
        dc.drawLine(x - 2, y - 4, x - 2, y - 6);
        dc.drawLine(x - 10, y, x - 8, y + 1);
        dc.drawLine(x + 5, y, x + 7, y + 1);
        // The arrow is separate from the sun, so its direction is obvious.
        dc.setPenWidth(2);
        dc.drawLine(x + 13, y - 8, x + 13, y + 1);
        if (isRise) {
            dc.drawLine(x + 10, y - 5, x + 13, y - 8);
            dc.drawLine(x + 13, y - 8, x + 16, y - 5);
        } else {
            dc.drawLine(x + 10, y - 2, x + 13, y + 1);
            dc.drawLine(x + 13, y + 1, x + 16, y - 2);
        }
        dc.setPenWidth(1);
    }

    // Solid, symmetrical heart similar to the clear heart from Garmin Connect.
    // Pixel-width fill makes it readable even at the MIP capsule's icon size.
    // Extents x-8..x+8, y-8..y+8.
    function heart(dc, x, y, color) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x - 4, y - 4, 4);
        dc.fillCircle(x + 4, y - 4, 4);
        dc.fillRectangle(x - 8, y - 4, 16, 4);
        for (var row = 0; row <= 8; row++) {
            var halfWidth = 8 - row;
            dc.drawLine(x - halfWidth, y + row, x + halfWidth, y + row);
        }
    }

    function footprints(dc, x, y, color) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x - 5, y - 4, 3);
        dc.fillRectangle(x - 8, y, 5, 8);
        dc.fillCircle(x + 5, y - 2, 3);
        dc.fillRectangle(x + 3, y + 2, 5, 8);
    }

    function batteryIcon(dc, x, y, color) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRectangle(x - 9, y - 6, 17, 12);
        dc.fillRectangle(x + 8, y - 2, 3, 4);
        dc.fillRectangle(x - 6, y - 3, 9, 6);
        dc.setPenWidth(1);
    }

    // v3.24.19: use a bolt inside the existing 17x12 battery outline
    // when connected to a USB charger. Same bounds as batteryIcon();
    // no extra space and no changes to the percent display or other fields.
    function chargingBatteryIcon(dc, x, y, color) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRectangle(x - 9, y - 6, 17, 12);
        dc.fillRectangle(x + 8, y - 2, 3, 4);
        // Bright bolt instead of the normal battery fill, readable on MIP.
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.drawLine(x + 2, y - 4, x - 4, y + 1);
        dc.drawLine(x - 4, y + 1, x + 1, y + 1);
        dc.drawLine(x + 1, y + 1, x - 2, y + 5);
        dc.setPenWidth(1);
    }

    // Garmin Connect inspired Body Battery pictogram. Three segmented energy
    // arcs and one central circular node; vector geometry, no external assets.
    // Bounds x +/-10, y +/-10: safe even in the 64px side capsules.
    function bodyBatteryIcon(dc, x, y, color) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawArc(x, y, 10, Gfx.ARC_CLOCKWISE, 35, 142);
        dc.drawArc(x, y, 10, Gfx.ARC_CLOCKWISE, 158, 252);
        dc.drawArc(x, y, 10, Gfx.ARC_CLOCKWISE, 269, 342);
        dc.setPenWidth(1);
        dc.drawCircle(x, y - 2, 3);
        dc.fillCircle(x, y - 2, 2);
        dc.setPenWidth(2);
        dc.drawLine(x, y + 2, x, y + 7);
        dc.drawLine(x - 4, y + 2, x, y + 5);
        dc.drawLine(x + 4, y + 2, x, y + 5);
        dc.setPenWidth(1);
    }

    // Intensywne minuty: a fast stopwatch with three speed lines, clearly
    // distinct from the simple top-row stopwatch icon.
    // Bounds x-14..x+10, y-11..y+10.
    function intensityTimerIcon(dc, x, y, color) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(x + 1, y + 1, 8);
        dc.drawLine(x + 1, y - 8, x + 1, y - 11);
        dc.drawLine(x - 2, y - 11, x + 4, y - 11);
        dc.drawLine(x + 1, y + 1, x + 4, y + 4);
        dc.drawLine(x + 1, y + 1, x + 1, y - 3);
        dc.drawLine(x - 14, y - 4, x - 9, y - 4);
        dc.drawLine(x - 14, y, x - 10, y);
        dc.drawLine(x - 14, y + 4, x - 9, y + 4);
        dc.setPenWidth(1);
    }

    function stopwatch(dc, x, y, color) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(x, y + 2, 8);
        dc.drawLine(x, y - 7, x, y - 11);
        dc.drawLine(x - 3, y - 11, x + 3, y - 11);
        dc.drawLine(x, y + 2, x + 4, y - 2);
        dc.setPenWidth(1);
    }

    function moon(dc, x, y) {
        drawLunarDisk(dc, x, y, 7);
    }

    function cloud(dc, x, y) {
        // More pronounced partly-cloudy icon, drawn without external fonts.
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawArc(x - 10, y - 7, 8, Gfx.ARC_COUNTER_CLOCKWISE, 0, 180);
        dc.drawLine(x - 10, y - 18, x - 10, y - 16);
        dc.drawLine(x - 21, y - 8, x - 19, y - 8);
        dc.setPenWidth(1);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x - 6, y + 2, 6);
        dc.fillCircle(x + 3, y - 1, 9);
        dc.fillCircle(x + 13, y + 3, 6);
        dc.fillRectangle(x - 12, y + 3, 30, 7);
    }

    

    // Weather symbols follow the Garmin cached condition. Unlike the
    // independent pressure-warning bolt, they describe present weather.
    function weatherSymbol(dc, x, y, weather) {
        if (weather == null || weather.condition == null) {
            // Missing weather: neutral outline, no invented condition.
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawCircle(x, y, 8);
            dc.drawLine(x, y - 4, x, y + 1);
            dc.drawCircle(x, y + 5, 1);
            dc.setPenWidth(1);
            return;
        }
        var c = weather.condition;
        // Pure sunshine.
        if (c == Weather.CONDITION_CLEAR || c == Weather.CONDITION_FAIR ||
            c == Weather.CONDITION_MOSTLY_CLEAR) {
            dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawCircle(x, y - 2, 10);
            dc.drawLine(x, y - 19, x, y - 15);
            dc.drawLine(x, y + 11, x, y + 16);
            dc.drawLine(x - 18, y - 2, x - 14, y - 2);
            dc.drawLine(x + 14, y - 2, x + 18, y - 2);
            dc.drawLine(x - 13, y - 15, x - 10, y - 12);
            dc.drawLine(x + 10, y + 8, x + 13, y + 11);
            dc.drawLine(x + 12, y - 15, x + 9, y - 12);
            dc.drawLine(x - 9, y + 8, x - 12, y + 11);
            dc.setPenWidth(1);
            return;
        }
        // Cloud with some sun.
        if (c == Weather.CONDITION_PARTLY_CLOUDY ||
            c == Weather.CONDITION_PARTLY_CLEAR ||
            c == Weather.CONDITION_THIN_CLOUDS) {
            cloud(dc, x, y);
            return;
        }
        // Cloud and precipitation.
        if (c == Weather.CONDITION_RAIN || c == Weather.CONDITION_LIGHT_RAIN ||
            c == Weather.CONDITION_HEAVY_RAIN || c == Weather.CONDITION_DRIZZLE ||
            c == Weather.CONDITION_SCATTERED_SHOWERS || c == Weather.CONDITION_SHOWERS ||
            c == Weather.CONDITION_LIGHT_SHOWERS || c == Weather.CONDITION_HEAVY_SHOWERS ||
            c == Weather.CONDITION_CHANCE_OF_SHOWERS ||
            c == Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN ||
            c == Weather.CONDITION_UNKNOWN_PRECIPITATION) {
            simpleCloud(dc, x, y - 5);
            dc.setColor(0x00AAFF, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(x - 10, y + 12, x - 13, y + 18);
            dc.drawLine(x, y + 12, x - 3, y + 18);
            dc.drawLine(x + 10, y + 12, x + 7, y + 18);
            dc.setPenWidth(1);
            return;
        }
        // Snow / wintry conditions.
        if (c == Weather.CONDITION_SNOW || c == Weather.CONDITION_LIGHT_SNOW ||
            c == Weather.CONDITION_HEAVY_SNOW || c == Weather.CONDITION_FLURRIES ||
            c == Weather.CONDITION_CHANCE_OF_SNOW || c == Weather.CONDITION_WINTRY_MIX ||
            c == Weather.CONDITION_RAIN_SNOW || c == Weather.CONDITION_ICE_SNOW ||
            c == Weather.CONDITION_LIGHT_RAIN_SNOW || c == Weather.CONDITION_HEAVY_RAIN_SNOW ||
            c == Weather.CONDITION_FREEZING_RAIN || c == Weather.CONDITION_SLEET ||
            c == Weather.CONDITION_CLOUDY_CHANCE_OF_SNOW ||
            c == Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN_SNOW) {
            simpleCloud(dc, x, y - 5);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(x - 10, y + 11, x - 10, y + 19);
            dc.drawLine(x - 14, y + 15, x - 6, y + 15);
            dc.drawLine(x + 7, y + 11, x + 7, y + 19);
            dc.drawLine(x + 3, y + 15, x + 11, y + 15);
            dc.setPenWidth(1);
            return;
        }
        if (c == Weather.CONDITION_THUNDERSTORMS ||
            c == Weather.CONDITION_SCATTERED_THUNDERSTORMS ||
            c == Weather.CONDITION_CHANCE_OF_THUNDERSTORMS ||
            c == Weather.CONDITION_TROPICAL_STORM) {
            simpleCloud(dc, x, y - 6);
            stormBolt(dc, x + 2, y + 13);
            return;
        }
        if (c == Weather.CONDITION_FOG || c == Weather.CONDITION_MIST ||
            c == Weather.CONDITION_HAZY || c == Weather.CONDITION_HAZE) {
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(x - 20, y - 9, x + 16, y - 9);
            dc.drawLine(x - 16, y - 2, x + 20, y - 2);
            dc.drawLine(x - 20, y + 5, x + 15, y + 5);
            dc.drawLine(x - 13, y + 12, x + 20, y + 12);
            dc.setPenWidth(1);
            return;
        }
        if (c == Weather.CONDITION_WINDY || c == Weather.CONDITION_SQUALL) {
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(x - 22, y - 5, x + 12, y - 5);
            dc.drawLine(x - 12, y + 3, x + 19, y + 3);
            dc.drawLine(x - 19, y + 11, x + 10, y + 11);
            dc.setPenWidth(1);
            return;
        }
        // Overcast / unclassified present weather.
        simpleCloud(dc, x, y);
    }

    function simpleCloud(dc, x, y) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x - 11, y + 2, 8);
        dc.fillCircle(x + 1, y - 4, 11);
        dc.fillCircle(x + 14, y + 3, 8);
        dc.fillRectangle(x - 17, y + 3, 38, 9);
    }

    function genericIcon(dc, x, y, color) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(x, y, 5);
        dc.drawLine(x - 3, y, x + 3, y);
        dc.setPenWidth(1);
    }

    // Only the existing pictogram changes color when an optional threshold is
    // crossed. This adds no icons/lines and preserves the approved geometry.
    // d[2] is a 0..1 ratio, not a percent; null means no dependable data.
    function statusIconColor(id, ratio, normalColor) {
        if (!srSetting("statusColorsV315", true) || ratio == null) {
            return normalColor;
        }
        var percent = ratio.toFloat() * 100.0;
        if (id == 17) {
            if (percent <= srSetting("batteryCriticalV315", 10)) { return Gfx.COLOR_RED; }
            if (percent <= srSetting("batteryLowV315", 20)) { return Gfx.COLOR_YELLOW; }
        }
        // Body Battery: a bright yellow warning and red critical icon are
        // easier to distinguish than orange/red on the Fenix 7X MIP.
        if (id == 3) {
            var bodyLow = srSetting("bodyLowV315", 20);
            if (percent <= 10) { return Gfx.COLOR_RED; }
            if (percent <= bodyLow) { return Gfx.COLOR_YELLOW; }
        }
        if (id == 10 && percent >= srSetting("stressHighV315", 80)) {
            return Gfx.COLOR_ORANGE;
        }
        return normalColor;
    }

    function drawIcon(dc, x, y, id, color) {
        if (id == 0) { return; }
        if (id == 14 || id == 15) { sunIcon(dc, x, y, id == 14); }
        else if (id == 34) { moon(dc, x, y); }
        else if (id == 35) {
            // Reuse the same Garmin observation already obtained by the face.
            var event = nextSunEvent(getCachedConditions());
            if (event != null) { sunIcon(dc, x, y, event[0]); }
            else { genericIcon(dc, x, y, Gfx.COLOR_LT_GRAY); }
        }
        else if (id == 1) { heart(dc, x, y, color); }
        else if (id == 2) { footprints(dc, x, y, color); }
        else if (id == 3) { bodyBatteryIcon(dc, x, y, color); }
        else if (id == 17) { batteryIcon(dc, x, y, color); }
        else if (id == 4 || id == 5) { intensityTimerIcon(dc, x, y, color); }
        else if (id == 16 || id == 18) { cloud(dc, x, y); }
        else { genericIcon(dc, x, y, color); }
    }

    function stormBolt(dc, x, y) {
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(x + 3, y - 8, x - 3, y);
        dc.drawLine(x - 3, y, x + 3, y);
        dc.drawLine(x + 3, y, x - 2, y + 8);
        dc.setPenWidth(1);
    }


    // Lunar phase illustration: illuminated fraction changes as the synodic
    // cycle progresses. It is intentionally simple for low-color MIP displays.
    function drawLunarDisk(dc, x, y, r) {
        var phase = moonFraction();
        if (phase < 0.0) { phase += 1.0; }
        dc.setColor(0x303044, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, r);
        dc.setColor(0xEEEEFF, Gfx.COLOR_TRANSPARENT);
        var cosPhase = null;
        var minute = (Time.now().value() / 60).toNumber();
        if (_moonCosCache != null && _moonCosCache[0] == minute) {
            cosPhase = _moonCosCache[1];
        } else {
            cosPhase = Math.cos(2.0 * Math.PI * phase);
            _moonCosCache = [minute, cosPhase];
        }
        for (var row = -r; row <= r; row++) {
            // The actual moon is always drawn with r=12. Cache the 25
            // constant square roots rather than repeating them each second.
            var extent = r == 12 ? _srMoonExtents12[row + 12]
                       : r == 7 ? _srMoonExtents7[row + 7]
                                : Math.sqrt((r * r - row * row).toFloat());
            var leftEdge = x - extent.toNumber();
            var rightEdge = x + extent.toNumber();
            if (phase < 0.5) {
                var startX = x + (extent * cosPhase).toNumber();
                if (startX <= rightEdge) {
                    dc.drawLine(startX, y + row, rightEdge, y + row);
                }
            } else {
                var endX = x - (extent * cosPhase).toNumber();
                if (leftEdge <= endX) {
                    dc.drawLine(leftEdge, y + row, endX, y + row);
                }
            }
        }
        dc.setColor(0x9999BB, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(x, y, r);
    }

    // Independent, optional lunar panel with its own mobile font control.
    // Short labels are deliberately preferred to unreadably small long names.
    function drawMoonPanel(dc) {
        if (!srSetting("moonPanelV38", true)) { return; }
        // Warning appears ONLY after a qualified pressure trend.
        // Dedicated left gutter ensures it cannot collide with lunar graphic.
        if (_storm.warning()) { stormBolt(dc, 46, 147); }
        drawLunarDisk(dc, 76, 147, 12);
        dc.setColor(0x999999, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(101, 135, 101, 158);
        var mode = srSetting("moonLabelV38", 0);
        var value = mode == 0 ? moonPhaseCompactLabel() : moonPhaseExtendedLabel();
        drawSized(dc, value, 182, 135, 136, 24,
                  Gfx.COLOR_WHITE, false,
                  fieldPixels("moonFontV38", "fontWeatherV31", 19, 2),
                  fieldScale("moonFontV38", "fontWeatherV31"));
    }

    function topSlot(dc, x, id, sizeKey, monitor, weather) {
        if (id == 0) { return; }
        var d = frameField(id, monitor, weather);
        if (id == 35) {
            // readField() has already resolved the next event for this frame.
            if (d[1] != "--:--") { sunIcon(dc, x, 36, d[0] == "WSCHOD"); }
            else { genericIcon(dc, x, 36, Gfx.COLOR_LT_GRAY); }
        } else {
            drawIcon(dc, x, 36, id, 0x00CCFF);
        }
        var v = d[1];
        var boxWidth = x == 134 ? 45 : 66;
        if (id == 14 || id == 15 || id == 35) {
            drawTopClock(dc, v, x, sizeKey, boxWidth);
        } else {
            drawSized(dc, v, x, 49, boxWidth, 24,
                      Gfx.COLOR_WHITE, false,
                      fieldPixels(sizeKey, "fontTopV31", 19, 2),
                      fieldScale(sizeKey, "fontTopV31"));
        }
    }

    // v3.12: Three capsules with independent safe lanes for icon, number and
    // progress. Works for any selectable metric with or without a ratio.
    // Border y=167..211; icon center y=182; text y=171..191;
    // progress track y=196..199. The separator is below at y=215.
    function capsuleTrack(dc, left, top, width, ratio, color, stepsReached, showDone) {
        if (ratio == null) { return; }
        var p = ratio.toFloat();
        if (p < 0.0) { p = 0.0; }
        if (p > 1.0) { p = 1.0; }
        var bx = left + 10;
        // Raised a little and made thicker for better visibility.
        var by = top + 29;
        var barH = 4;
        var barWidth = width - 20;
        // At 100% steps the check has its OWN 12px lane at track's right;
        // no check mark is ever painted on top of a filled progress bar.
        if (showDone) { barWidth -= 12; }
        dc.setColor(0x283144, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(bx, by, barWidth, barH, 2);
        var fill = (p * barWidth.toFloat()).toNumber();
        if (fill >= 2) {
            dc.setColor(stepsReached ? Gfx.COLOR_GREEN : color, Gfx.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(bx, by, fill, barH, 2);
        }
        if (showDone) {
            // An outlined green DONE circle occupies x=right-20..right-10.
            // Text is in y=171..191; this icon is in y=193..203.
            dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            var cx = left + width - 15;
            var cy = by + 2;
            dc.drawCircle(cx, cy, 5);
            dc.drawLine(cx - 3, cy, cx - 1, cy + 2);
            dc.drawLine(cx - 1, cy + 2, cx + 3, cy - 2);
        }
    }

    function capsule(dc, left, width, id, colorCode, sizeKey, monitor, weather, isCenter) {
        if (id == 0) { return; }
        var d = frameField(id, monitor, weather);
        var col = srColor(colorCode);
        var top = 167;
        dc.setPenWidth(3);
        dc.setColor(col, Gfx.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(left, top, width, 44, 19);
        dc.setPenWidth(1);
        // Icon occupies x=left+6..+28, number starts at x=left+30.
        // Lowest icon point at y=192, below top border and above track.
        var iconX = left + 17;
        // Alert only recolors the existing icon; capsule border stays themed.
        drawIcon(dc, iconX, 182, id, statusIconColor(id, d[2], col));
        var value = d[1];
        var stepsReached = false;
        if (id == 2) {
            if (monitor.steps != null && monitor.stepGoal != null &&
                monitor.stepGoal > 0 && monitor.steps >= monitor.stepGoal) {
                stepsReached = true;
            }
            if (monitor.steps != null) {
                var steps = monitor.steps;
                if (isCenter && srSetting("capsuleStepsModeV39", 0) == 1 &&
                    monitor.stepGoal != null && monitor.stepGoal > 0) {
                    steps = monitor.stepGoal - steps;
                    if (steps < 0) { steps = 0; }
                }
                value = steps < 1000000 ? steps.toString() : compact(steps);
            }
        }
        // Optional dual-line steps display in the CENTER capsule only.
        // Modes 0 and 1 retain their original rendering path unchanged.
        if (id == 2 && isCenter && srSetting("capsuleStepsModeV39", 0) == 2 &&
            monitor.steps != null && monitor.stepGoal != null && monitor.stepGoal > 0) {
            var doneSteps = monitor.steps;
            var remainingSteps = monitor.stepGoal - doneSteps;
            // Signed difference: positive before goal, zero at goal, negative above goal.
            // Keep the exact number (including the minus sign), never compact it.
            // drawSized measures the text and reduces font size to fit its slot.
            var doneText = doneSteps < 1000000 ? doneSteps.toString() : compact(doneSteps);
            var remainingText = remainingSteps.toString();
            var dualWidth = width - 35;
            var dualCenter = left + 30 + (dualWidth / 2).toNumber();
            // Two separate measured text slots, safely inside the 44px capsule.
            // No progress track or DONE badge is rendered in this mode.
            drawSized(dc, doneText, dualCenter, 169, dualWidth, 19,
                      Gfx.COLOR_WHITE, onlyDigits(doneText),
                      fieldPixels(sizeKey, "fontRingV31", 19, 1),
                      fieldScale(sizeKey, "fontRingV31"));
            drawSized(dc, remainingText, dualCenter, 190, dualWidth, 17,
                      Gfx.COLOR_WHITE, onlyDigits(remainingText),
                      fieldPixels(sizeKey, "fontRingV31", 15, 1),
                      fieldScale(sizeKey, "fontRingV31"));
            return;
        }
        var valueW = width - 35;
        var valueCenter = left + 30 + (valueW / 2).toNumber();
        drawSized(dc, value, valueCenter, 171, valueW, 20,
                  Gfx.COLOR_WHITE, onlyDigits(value),
                  fieldPixels(sizeKey, "fontRingV31", isCenter ? 23 : 21, 2),
                  fieldScale(sizeKey, "fontRingV31"));
        var showDone = stepsReached && srSetting("stepDoneV314", true);
        capsuleTrack(dc, left, top, width, d[2], col, stepsReached, showDone);
    }

    // A single thermometer glyph for both temperature warnings. The narrow
    // 14x17px icon fits between the weather divider and temperature text on
    // the 280x280 MIP display, without touching the captions underneath.
    // The entire symbol changes color rather than adding extra UI elements.
    function warningThermometer(dc, x, y, color) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        // Outline, mercury column and filled round bulb.
        // Bounds x-4..x+4, y-8..y+9.
        dc.drawRoundedRectangle(x - 3, y - 8, 6, 13, 2);
        dc.fillRectangle(x - 1, y - 5, 2, 10);
        dc.fillCircle(x, y + 5, 4);
        dc.setPenWidth(1);
    }

    // Displays ONLY when weather temperature crosses a configured threshold.
    // We deliberately reuse v3.12 property IDs so current iPhone settings and
    // saved threshold preferences stay compatible across updates.
    function temperatureMarker(dc, w, x, y) {
        if (!srSetting("tempAlertsV312", true) || w == null ||
            w.temperature == null) { return; }
        var temp = w.temperature;
        var hot = srSetting("tempHotV312", 30);
        var cold = srSetting("tempColdV312", 0);
        if (temp > hot) {
            // Orange/red tone: over the hot threshold (e.g. >30C).
            warningThermometer(dc, x, y, Gfx.COLOR_ORANGE);
        } else if (temp < cold) {
            // Bright cold blue: below the cold threshold (e.g. <0C).
            warningThermometer(dc, x, y, 0x00CCFF);
        }
    }

    // Small, independent weather warning symbol. The existing temperature
    // thermometer occupies the first slot; this occupies the second.
    // RED (fresh Garmin current conditions) or CYAN (hourly prediction).
    // The symbol is a local Garmin-Weather indicator, NOT an official alert.
    // v3.24.10: nine distinct, small-screen MIP glyphs. All fit x +/-9,
    // y +/-9. The thermometer is deliberately unchanged.
    function warningCloud(dc, x, y) {
        // A compact rounded cloud silhouette, open at its base for precipitation.
        dc.drawLine(x-8,y+2,x-8,y-1);
        dc.drawLine(x-8,y-1,x-6,y-4);
        dc.drawLine(x-6,y-4,x-3,y-4);
        dc.drawLine(x-3,y-4,x-1,y-7);
        dc.drawLine(x-1,y-7,x+3,y-7);
        dc.drawLine(x+3,y-7,x+6,y-4);
        dc.drawLine(x+6,y-4,x+8,y-2);
        dc.drawLine(x+8,y-2,x+8,y+2);
        dc.drawLine(x-8,y+2,x+8,y+2);
    }

    function drawGarminWarningIcon(dc, x, y, alertTag) {
        var kind = alertTag;
        var color = Gfx.COLOR_RED;
        if (alertTag > 16) {
            kind = alertTag - 16;
            color = 0x00FFFF;
        }
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        if (kind == 1) {
            // Wind: three swept streams with short angled tails.
            dc.drawLine(x-8,y-5,x+5,y-5);
            dc.drawLine(x+5,y-5,x+8,y-7);
            dc.drawLine(x-6,y,x+8,y);
            dc.drawLine(x-8,y+5,x+4,y+5);
            dc.drawLine(x+4,y+5,x+7,y+3);
        } else if (kind == 2) {
            // Heavy rain: cloud + three diagonal rain streaks.
            warningCloud(dc,x,y-2);
            dc.drawLine(x-6,y+4,x-8,y+8);
            dc.drawLine(x,y+4,x-2,y+8);
            dc.drawLine(x+6,y+4,x+4,y+8);
        } else if (kind == 3) {
            // Heavy snow: cloud + three distinct round snow dots.
            warningCloud(dc,x,y-2);
            dc.fillCircle(x-6,y+7,1);
            dc.fillCircle(x,y+7,1);
            dc.fillCircle(x+6,y+7,1);
        } else if (kind == 4) {
            // Thunder: cloud with a clearly visible central lightning bolt.
            warningCloud(dc,x,y-3);
            dc.drawLine(x+1,y+2,x-3,y+6);
            dc.drawLine(x-3,y+6,x+2,y+6);
            dc.drawLine(x+2,y+6,x-1,y+9);
        } else if (kind == 5) {
            // Freezing rain: CIRCLE + diagonal streaks, NO lightning/snowflake.
            dc.drawCircle(x,y,9);
            dc.drawLine(x-3,y-5,x-6,y+1);
            dc.drawLine(x+3,y-5,x,y+1);
            dc.drawLine(x+5,y+1,x+2,y+6);
        } else if (kind == 6) {
            // Fog: cloud + horizontal fog bands below it.
            warningCloud(dc,x,y-3);
            dc.drawLine(x-7,y+4,x+7,y+4);
            dc.drawLine(x-5,y+8,x+5,y+8);
        } else if (kind == 7) {
            // Ice: standalone six-arm snowflake (different from snow dots).
            dc.drawLine(x-8,y,x+8,y);
            dc.drawLine(x,y-8,x,y+8);
            dc.drawLine(x-6,y-6,x+6,y+6);
            dc.drawLine(x-6,y+6,x+6,y-6);
        } else if (kind == 8) {
            // Hail: CIRCLE + three solid round pellets, NO streaks.
            dc.drawCircle(x,y,9);
            dc.fillCircle(x-4,y-2,2);
            dc.fillCircle(x+4,y-2,2);
            dc.fillCircle(x,y+4,2);
        } else if (kind == 9) {
            // High UV: compact sun and rays, legible at 20px.
            dc.drawCircle(x,y,4);
            dc.drawLine(x,y-9,x,y-6);
            dc.drawLine(x,y+6,x,y+9);
            dc.drawLine(x-9,y,x-6,y);
            dc.drawLine(x+6,y,x+9,y);
            dc.drawLine(x-7,y-7,x-5,y-5);
            dc.drawLine(x+7,y-7,x+5,y-5);
            dc.drawLine(x-7,y+7,x-5,y+5);
            dc.drawLine(x+7,y+7,x+5,y+5);
        }
        dc.setPenWidth(1);
    }

    // v3.24.11: left-anchored temperature in a fixed, protected lane.
    // Returns the actual text centre so the feels-like line can follow it.
    function drawWeatherTemperature(dc, value, left, right) {
        var str = value == null ? "--" : value.toString();
        var width = right - left;
        var pixels = fieldPixels("sizeWeatherValueV37", "fontWeatherV31", 27, 2);
        var scale = fieldScale("sizeWeatherValueV37", "fontWeatherV31");
        if (!_lowMemory) {
            var cached = _tempFitCache;
            var match = cached != null && cached[0] == str &&
                        cached[1] == pixels && cached[2] == width;
            var selected = match ? cached[3] : null;
            var chosenDim = match ? cached[4] : null;
            if (!match) {
                try {
                    var requested = vectorFontFor(pixels, false);
                    if (requested != null) {
                        var dim = dc.getTextDimensions(str, requested);
                        if (dim[0] <= width && dim[1] <= 22) {
                            selected = requested;
                            chosenDim = dim;
                        } else {
                            var low = 10;
                            var high = pixels - 1;
                            while (low <= high) {
                                var mid = ((low + high) / 2).toNumber();
                                var probe = vectorFontFor(mid, false);
                                if (probe == null) { break; }
                                dim = dc.getTextDimensions(str, probe);
                                if (dim[0] <= width && dim[1] <= 22) {
                                    selected = probe;
                                    chosenDim = dim;
                                    low = mid + 1;
                                } else { high = mid - 1; }
                            }
                        }
                    }
                } catch (e) { selected = null; }
                _tempFitCache = selected == null ? null :
                                [str, pixels, width, selected, chosenDim];
            }
            if (selected != null) {
                var center = left + (chosenDim[0] / 2).toNumber();
                dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
                dc.drawText(center, 215 + ((22 - chosenDim[1]) / 2).toNumber(),
                            selected, str, Gfx.TEXT_JUSTIFY_CENTER);
                return center;
            }
        }
        // Native font fallback: measure before drawing and keep the same
        // left alignment. The existing fit routine handles the final fallback.
        var fonts = [Gfx.FONT_LARGE, Gfx.FONT_MEDIUM, Gfx.FONT_SMALL,
                     Gfx.FONT_TINY, Gfx.FONT_XTINY];
        for (var i = 0; i < fonts.size(); i++) {
            try {
                var dim2 = dc.getTextDimensions(str, fonts[i]);
                if (dim2[0] <= width && dim2[1] <= 22) {
                    var center2 = left + (dim2[0] / 2).toNumber();
                    dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
                    dc.drawText(center2, 215 + ((22 - dim2[1]) / 2).toNumber(),
                                fonts[i], str, Gfx.TEXT_JUSTIFY_CENTER);
                    return center2;
                }
            } catch (e) { }
        }
        drawSized(dc, str, left + width / 2, 215, width, 22,
                  Gfx.COLOR_WHITE, false, pixels, scale);
        return left + width / 2;
    }

    // Weather glyph on left. Thermometer + rotating Garmin warning appear
    // DIRECTLY LEFT OF THE TEMPERATURE VALUE, on the same horizontal line.
    // Weather description/feels-like stays on its own line below.
    function drawWeather(dc, monitor, weather) {
        var id = srSetting("slotLowerV3", 16);
        _weatherWarningVisible = false;
        _lastDrawnWeatherWarning = 0;
        if (id == 0) { return; }
        var d = frameField(id, monitor, weather);
        // Also show both weather markers with the optional felt-temperature
        // field (id 19), not only ordinary temperature / weather (16/18).
        var isTemp = (id == 16 || id == 18 || id == 19);
        var hasThermometer = false;
        if (isTemp && srSetting("tempAlertsV312", true) && weather != null &&
            weather.temperature != null) {
            var hot = srSetting("tempHotV312", 30);
            var cold = srSetting("tempColdV312", 0);
            hasThermometer = weather.temperature > hot || weather.temperature < cold;
        }
        var warning = 0;
        if (isTemp) {
            try { warning = _weatherWarnings.warning(weather); } catch (e) { warning = 0; }
        }
        if (id == 16) {
            weatherSymbol(dc, 74, 235, weather);
        } else {
            drawIcon(dc, 74, 235, id, 0x00CCFF);
        }
        // v3.24.8: swap the two marker slots as requested.
        // Weather warning comes FIRST (left, close to the separator), while
        // the temperature thermometer sits SECOND, closer to the value.
        // Warning uses x=120. Thermometer uses x=140 when both are visible,
        // or x=136 when it is the only marker. This keeps every glyph clear
        // of the separator while maximising free space on the right.
        // v3.24.11: retain the 80px safe lane when markers are shown.
        // Short values start 4px after the thermometer and grow RIGHT,
        // rather than being centred in a mostly empty lane.
        // At -13°C, font measurements enforce the right edge <= 227.
        var hasMarkers = hasThermometer || warning != 0;
        var tempLeft = hasMarkers ? 148 : 147;
        var tempRight = hasMarkers ? 227 : 227;
        // Diagnostic override changes display text only, never live weather logic.
        var diagnosticTemp = srSetting("tempLayoutTestV32412", 0);
        var shownTemp = d[1];
        if (isTemp && diagnosticTemp == 1) { shownTemp = "-35°C"; }
        if (isTemp && diagnosticTemp == 2) { shownTemp = "-99°C"; }
        var actualTempCenter = drawWeatherTemperature(dc, shownTemp, tempLeft, tempRight);

        if (hasThermometer) {
            temperatureMarker(dc, weather, warning != 0 ? 140 : 136, 227);
        }
        if (warning != 0) {
            drawGarminWarningIcon(dc, 123, 227, warning);
            _weatherWarningVisible = true;
            _lastDrawnWeatherWarning = warning;
        }

        var lowerLabel = id == 16 ? conditionText(weather) : d[0];
        var lowerColor = id == 16 ? Gfx.COLOR_WHITE : Gfx.COLOR_LT_GRAY;
        if (isTemp && srSetting("showFeelsLikeV319", false) && weather != null &&
            weather.feelsLikeTemperature != null) {
            lowerLabel = "ODCZ. " + weather.feelsLikeTemperature.format("%.0f") + "°C";
            lowerColor = Gfx.COLOR_WHITE;
        }
        if (isTemp && diagnosticTemp == 1) {
            lowerLabel = "ODCZ. -45°C";
            lowerColor = Gfx.COLOR_WHITE;
        } else if (isTemp && diagnosticTemp == 2) {
            lowerLabel = "ODCZ. -99°C";
            lowerColor = Gfx.COLOR_WHITE;
        }
        // Follow the upper temperature's measured centre, within a safe
        // range for the long ODCZ. -18°C label and the curved screen edge.
        // No change to the lower font, line height, or weather icon positions.
        var lowerCenter = actualTempCenter;
        if (lowerCenter < 166) { lowerCenter = 166; }
        if (lowerCenter > 174) { lowerCenter = 174; }
        drawSized(dc, lowerLabel, lowerCenter, 234, 105, 16, lowerColor, false,
                  fieldPixels("sizeWeatherLabelV37", "fontWeatherV31", 17, 2),
                  fieldScale("sizeWeatherLabelV37", "fontWeatherV31"));
    }

    // Battery footer resides inside the circle at Y=251..267 and cannot
    // touch the outer progress ring. All contents stay in a 76px box.
    // Battery is separate from the outer ring and weather description.
    function drawBattery(dc, monitor, weather) {
        var id = srSetting("slotFooterV3", 17);
        if (id == 0) { return; }
        var d = frameField(id, monitor, weather);
        var footerColor = statusIconColor(id, d[2], Gfx.COLOR_GREEN);
        var charging = false;
        if (id == 17) { // Footer displays the watch battery.
            // Connect IQ System.Stats.charging is TRUE while USB is plugged in,
            // including after reaching 100%. Safe fallback: normal icon.
            try { charging = srSystemStatsForFrame().charging; }
            catch (e) { charging = false; }
        }
        if (id == 17 && charging) {
            chargingBatteryIcon(dc, 117, 261, Gfx.COLOR_GREEN);
        } else {
            // All other footer selections and unplugged battery unchanged.
            drawIcon(dc, 117, 261, id, footerColor);
        }
        drawSized(dc, d[1], 165, 251, 60, 20,
                  Gfx.COLOR_WHITE, false,
                  fieldPixels("sizeFooterV37", "fontWeatherV31", 22, 2),
                  fieldScale("sizeFooterV37", "fontWeatherV31"));
    }

    function outerProgressRing(dc, monitor, weather, clock) {
        var mode = srSetting("outerRingV31", 1);
        if (mode == 0) { return; }
        var ratio = null;
        if (mode == 1) {
            ratio = (clock.hour * 60.0 + clock.min) / 1440.0;
        } else {
            var dataId = 0;
            if (mode == 2) { dataId = 10; } // Stress
            if (mode == 3) { dataId = 2; }  // Steps / daily goal
            if (mode == 4) { dataId = 3; }  // Body Battery
            if (mode == 5) { dataId = 17; } // Watch battery
            if (mode == 6) { dataId = 4; }  // Weekly intensity minutes
            if (dataId != 0) {
                var field = frameField(dataId, monitor, weather);
                ratio = field[2];
            }
        }
        var x = 140;
        var y = 140;
        var radius = 131;
        dc.setPenWidth(3);
        dc.setColor(0x343434, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(x, y, radius);
        if (ratio != null) {
            var p = ratio.toFloat();
            if (p < 0) { p = 0.0; }
            if (p > 1) { p = 1.0; }
            dc.setColor(srColor(srSetting("outerColorV31", 6)),
                        Gfx.COLOR_TRANSPARENT);
            if (p >= 0.999) {
                dc.drawCircle(x, y, radius);
            } else if (p > 0.004) {
                var end = 90 - (p * 359.0).toNumber();
                if (end < 0) { end += 360; }
                dc.drawArc(x, y, radius, Gfx.ARC_CLOCKWISE, 90, end);
            }
        }
        dc.setPenWidth(1);
    }

    

    // MIP watches such as fenix 7X Pro support 1 Hz partial updates in
    // low-power mode, subject to Garmin's strict screen/power budget.
    // Only a 20x22px icon cell changes; we never repaint the entire face.
    // If Garmin suspends partial updates, onUpdate() still rotates the icon
    // whenever it is called (typically once/minute in low power mode).
    function onPartialUpdate(dc) {
        if (!_weatherWarningVisible) { return; }
        var nextKind = _lastDrawnWeatherWarning;
        try { nextKind = _weatherWarnings.rotatingWarning(); }
        catch (e) { return; }
        if (nextKind == _lastDrawnWeatherWarning) { return; }
        try {
            dc.setClip(113, 216, 20, 22);
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
            dc.fillRectangle(113, 216, 20, 22);
            if (nextKind != 0) {
                drawGarminWarningIcon(dc, 123, 227, nextKind);
            }
            dc.clearClip();
            _lastDrawnWeatherWarning = nextKind;
        } catch (e) {
            try { dc.clearClip(); } catch (ee) { }
        }
    }

    function onUpdate(dc) {
        // One snapshot for memory, battery percentage and charging status.
        // Obtained anew on EVERY onUpdate, never reused on a later frame.
        var stats = null;
        try { stats = System.getSystemStats(); } catch (e) { }
        _srFrameSystemStats = stats;
        _frameEpoch += 1;
        // One-way low-memory fallback avoids repeated vector font allocations.
        if (!_lowMemory && stats != null) {
            try {
                if (stats.freeMemory < 18000) {
                    _lowMemory = true;
                    _fontCache = {};
                    _fontCacheCount = 0;
                    _sizedFitCache = {};
                    _sizedFitCacheSize = 0;
                    _clockFitCache = null;
                    _tempFitCache = null;
                    _moonCosCache = null;
                }
            } catch (e) { }
        }
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();
        var clock = System.getClockTime();
        var date = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var monitor = Monitor.getInfo();
        var w = getCachedConditions();

        outerProgressRing(dc, monitor, w, clock);
        topSlot(dc, 73, srSetting("slotTop1V3", 14), "sizeTopLeftV37", monitor, w);
        topSlot(dc, 134, srSetting("slotTop2V3", 34), "sizeTopMidV37", monitor, w);
        topSlot(dc, 195, srSetting("slotTop3V3", 15), "sizeTopRightV37", monitor, w);
        topDividers(dc);
        rule(dc, 76);

        drawClock(dc, clock);
        // Calendar values still come from Gregorian on every full update;
        // only the identical day/month label is memoized until it changes.
        var dayMonthKey = date.month * 32 + date.day;
        var dayMonthText = null;
        if (_dateTextCache != null && _dateTextCache[0] == dayMonthKey) {
            dayMonthText = _dateTextCache[1];
        } else {
            dayMonthText = date.day.toString() + " " + _srMonths[date.month - 1];
            _dateTextCache = [dayMonthKey, dayMonthText];
        }
        drawDate(dc, _srDays[date.day_of_week - 1], dayMonthText);
        drawWeatherAge(dc, w);
        rule(dc, 130);

        drawMoonPanel(dc);
        rule(dc, 163);

        capsule(dc, 32, 64, srSetting("slotRing1V3", 1),
                srSetting("colorRing1V3", 0), "sizeRingLeftV37", monitor, w, false);
        capsule(dc, 99, 83, srSetting("slotRing2V3", 2),
                srSetting("colorRing2V3", 2), "sizeRingMidV37", monitor, w, true);
        capsule(dc, 185, 64, srSetting("slotRing3V3", 3),
                srSetting("colorRing3V3", 6), "sizeRingRightV37", monitor, w, false);
        rule(dc, 215);

        // Weather API failures must not interrupt the time and other fields.
        _weatherWarningVisible = false;
        try { drawWeather(dc, monitor, w); } catch (e) { }
        weatherDivider(dc);
        rule(dc, 250);
        drawBattery(dc, monitor, w);

        if (!srSetting("moonPanelV38", true) && _storm.warning()) { stormBolt(dc, 46, 147); }
        // No stale System.Stats can survive a successfully completed render.
        _srFrameSystemStats = null;
    }

    
}
