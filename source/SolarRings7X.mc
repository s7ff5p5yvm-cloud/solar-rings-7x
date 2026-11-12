using Toybox.Application as Application;
using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as System;
using Toybox.Time as Time;
using Toybox.Time.Gregorian as Gregorian;
using Toybox.Weather as Weather;
using Toybox.ActivityMonitor as Monitor;

class SolarRings7XApp extends Application.AppBase {
    function initialize() { AppBase.initialize(); }

    function onStart(state) {
        AppBase.onStart(state);
        migrateOldSettings();
    }

    function getInitialView() { return [new SolarRings7XFace()]; }

    // On-watch configuration; phone configuration is resources/settings.xml.
    function getSettingsView() {
        var menu = makeSettingsMenu();
        return [menu, new SolarSettingsDelegate(menu)];
    }

    function onSettingsChanged() { Ui.requestUpdate(); }
}

class SolarRings7XFace extends Ui.WatchFace {
    var _storm;

    function initialize() {
        WatchFace.initialize();
        _storm = new StormGuard();
    }

    // Always keep text within an explicitly allocated width.
    // The smallest standard font is used only when necessary.
    function drawFitted(dc, x, y, value, maxW, font1, font2, color) {
        var textValue = value;
        var font = font1;
        if (dc.getTextWidthInPixels(textValue, font) > maxW) { font = font2; }
        if (dc.getTextWidthInPixels(textValue, font) > maxW) { font = Gfx.FONT_XTINY; }
        var cut = false;
        while (textValue.length() > 2 && dc.getTextWidthInPixels(textValue, font) > maxW) {
            textValue = textValue.substring(0, textValue.length() - 1);
            cut = true;
        }
        if (cut && textValue.length() > 2) {
            textValue = textValue.substring(0, textValue.length() - 1) + ".";
        }
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, textValue, Gfx.TEXT_JUSTIFY_CENTER);
    }

    function separator(dc, x1, x2, y) {
        dc.setColor(0x666666, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(x1, y, x2, y);
    }

    function drawSun(dc, x, y, rising) {
        dc.setColor(rising ? Gfx.COLOR_YELLOW : Gfx.COLOR_ORANGE, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawArc(x, y, 5, Gfx.ARC_COUNTER_CLOCKWISE, 0, 180);
        dc.drawLine(x - 9, y, x + 9, y);
        dc.drawLine(x, y - 10, x, y - 8);
        dc.setPenWidth(1);
    }

    function drawMoon(dc, x, y) {
        var phase = moonFraction();
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, 5);
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        if (phase < 0.07 || phase > 0.93) {
            dc.fillCircle(x, y, 5);
        } else if (phase < 0.43 || phase > 0.57) {
            dc.fillCircle(x + (phase < 0.5 ? -3 : 3), y, 4);
        }
    }

    function drawCloud(dc, x, y) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x - 6, y + 1, 4);
        dc.fillCircle(x + 1, y - 2, 6);
        dc.fillCircle(x + 8, y + 2, 4);
        dc.fillRectangle(x - 9, y + 1, 20, 5);
    }

    function drawBolt(dc, x, y) {
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(x + 2, y - 6, x - 2, y);
        dc.drawLine(x - 2, y, x + 3, y);
        dc.drawLine(x + 3, y, x - 1, y + 6);
        dc.setPenWidth(1);
    }

    function drawHeader(dc) {
        var clock = System.getClockTime();
        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var weekdays = ["ND", "PN", "WT", "SR", "CZ", "PT", "SB"];
        var months = ["STY", "LUT", "MAR", "KWI", "MAJ", "CZE", "LIP", "SIE", "WRZ", "PAZ", "LIS", "GRU"];
        // Header: y=18..75; clock on the left, date on the right.
        drawFitted(dc, 108, 17, twoDigits(clock.hour) + ":" + twoDigits(clock.min),
                   153, Gfx.FONT_NUMBER_MEDIUM, Gfx.FONT_NUMBER_MILD, Gfx.COLOR_WHITE);
        drawFitted(dc, 211, 25, weekdays[today.day_of_week - 1],
                   58, Gfx.FONT_SMALL, Gfx.FONT_TINY, Gfx.COLOR_WHITE);
        drawFitted(dc, 211, 47, today.day.toString() + " " + months[today.month - 1],
                   63, Gfx.FONT_TINY, Gfx.FONT_XTINY, Gfx.COLOR_LT_GRAY);
        separator(dc, 38, 242, 77);
    }

    function topSide(dc, x, id, info, w, leftSide) {
        if (id == 0) { return; }
        var item = readField(id, info, w);
        if (id == 14 || id == 15) {
            drawSun(dc, leftSide ? 40 : 179, 99, id == 14);
            drawFitted(dc, leftSide ? 81 : 220, 91, item[1],
                       55, Gfx.FONT_TINY, Gfx.FONT_XTINY, Gfx.COLOR_WHITE);
            return;
        }
        drawFitted(dc, x, 83, item[0], 63, Gfx.FONT_XTINY, Gfx.FONT_XTINY, Gfx.COLOR_YELLOW);
        drawFitted(dc, x, 97, item[1], 65, Gfx.FONT_TINY, Gfx.FONT_XTINY, Gfx.COLOR_WHITE);
    }

    function topCenter(dc, id, info, w) {
        if (id == 0) { return; }
        var item = readField(id, info, w);
        if (id == 34) {
            drawMoon(dc, 140, 90);
            drawFitted(dc, 140, 102, item[1], 50,
                       Gfx.FONT_XTINY, Gfx.FONT_XTINY, Gfx.COLOR_LT_GRAY);
            return;
        }
        drawFitted(dc, 140, 83, item[0], 49,
                   Gfx.FONT_XTINY, Gfx.FONT_XTINY, Gfx.COLOR_YELLOW);
        drawFitted(dc, 140, 99, item[1], 50,
                   Gfx.FONT_XTINY, Gfx.FONT_XTINY, Gfx.COLOR_WHITE);
    }

    // Four compact 2x2 rings. The center belongs to the *value*,
    // not to text labels; the top of each circle has a metric icon.
    function ring(dc, cx, cy, color, ratio) {
        var radius = 23;
        dc.setPenWidth(4);
        dc.setColor(0x484848, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, radius);
        if (ratio != null) {
            var p = ratio.toFloat();
            if (p < 0.0) { p = 0.0; }
            if (p > 1.0) { p = 1.0; }
            dc.setColor(color, Gfx.COLOR_TRANSPARENT);
            if (p >= 0.999) {
                dc.drawCircle(cx, cy, radius);
            } else if (p > 0.005) {
                var endAngle = 90 - (359.0 * p).toNumber();
                if (endAngle < 0) { endAngle += 360; }
                dc.drawArc(cx, cy, radius, Gfx.ARC_CLOCKWISE, 90, endAngle);
            }
        }
        dc.setPenWidth(1);
    }

    // Minimal vector icons, designed for the 280px MIP screen.
    // They avoid dependence on external fonts / emoji.
    function metricIcon(dc, cx, cy, id, color, label) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        if (id == 1) { // Heart
            dc.fillCircle(cx - 4, cy - 2, 4);
            dc.fillCircle(cx + 4, cy - 2, 4);
            dc.drawLine(cx - 8, cy, cx, cy + 7);
            dc.drawLine(cx, cy + 7, cx + 8, cy);
        } else if (id == 2) { // Footprints
            dc.fillCircle(cx - 4, cy - 4, 3);
            dc.fillCircle(cx + 4, cy + 2, 3);
            dc.drawLine(cx - 5, cy - 7, cx - 3, cy - 9);
            dc.drawLine(cx + 3, cy - 1, cx + 5, cy - 3);
        } else if (id == 3) { // Body Battery
            dc.drawRectangle(cx - 8, cy - 6, 15, 11);
            dc.fillRectangle(cx + 7, cy - 2, 2, 4);
            dc.drawLine(cx + 1, cy - 5, cx - 3, cy);
            dc.drawLine(cx - 3, cy, cx + 2, cy);
            dc.drawLine(cx + 2, cy, cx - 2, cy + 4);
        } else if (id == 4 || id == 5) { // Intensity / stopwatch
            dc.drawCircle(cx, cy, 6);
            dc.drawLine(cx, cy, cx + 3, cy - 3);
            dc.fillRectangle(cx - 2, cy - 10, 4, 3);
        } else {
            dc.setPenWidth(1);
            var shortName = label;
            if (shortName.length() > 6) { shortName = shortName.substring(0, 6); }
            drawFitted(dc, cx, cy - 8, shortName, 39,
                       Gfx.FONT_XTINY, Gfx.FONT_XTINY, color);
        }
        dc.setPenWidth(1);
    }

    // Pixel digits guarantee full 5-digit step values, e.g. 12345 and 25000.
    // No ellipsis, no /10000 suffix and no invented numerical goal.
    function digitRows(ch) {
        if (ch == "0") { return ["111", "101", "101", "101", "111"]; }
        if (ch == "1") { return ["010", "110", "010", "010", "111"]; }
        if (ch == "2") { return ["111", "001", "111", "100", "111"]; }
        if (ch == "3") { return ["111", "001", "111", "001", "111"]; }
        if (ch == "4") { return ["101", "101", "111", "001", "001"]; }
        if (ch == "5") { return ["111", "100", "111", "001", "111"]; }
        if (ch == "6") { return ["111", "100", "111", "101", "111"]; }
        if (ch == "7") { return ["111", "001", "001", "001", "001"]; }
        if (ch == "8") { return ["111", "101", "111", "101", "111"]; }
        if (ch == "9") { return ["111", "101", "111", "001", "111"]; }
        return null;
    }

    function isDigits(value) {
        if (value.length() < 1 || value.length() > 5) { return false; }
        for (var i = 0; i < value.length(); i++) {
            if (digitRows(value.substring(i, i + 1)) == null) { return false; }
        }
        return true;
    }

    function drawDigitalValue(dc, x, y, value) {
        var n = value.length();
        // Large digits for 1-2 characters; five-digit counts use compact 2px cells.
        var scale = n <= 2 ? 3 : (n <= 4 ? 2 : 2);
        var total = (n * 4 - 1) * scale;
        var left = x - (total / 2).toNumber();
        var top = y + (n <= 2 ? -1 : 3);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        for (var d = 0; d < n; d++) {
            var rows = digitRows(value.substring(d, d + 1));
            for (var r = 0; r < 5; r++) {
                for (var c = 0; c < 3; c++) {
                    if (rows[r].substring(c, c + 1) == "1") {
                        dc.fillRectangle(left + d * 4 * scale + c * scale,
                                         top + r * scale, scale, scale);
                    }
                }
            }
        }
    }

    function ringData(dc, cx, cy, fieldId, paletteCode, info, w) {
        if (fieldId == 0) { return; }
        var item = readField(fieldId, info, w);
        var color = ringPalette(paletteCode);
        ring(dc, cx, cy, color, item[2]);
        metricIcon(dc, cx, cy - 13, fieldId, color, item[0]);
        var value = item[1];
        if (isDigits(value)) {
            drawDigitalValue(dc, cx, cy, value);
        } else {
            drawFitted(dc, cx, cy + 1, value, 43,
                       Gfx.FONT_TINY, Gfx.FONT_XTINY, Gfx.COLOR_WHITE);
        }
    }

    function weatherFooter(dc, id, info, w) {
        if (id == 0) { return; }
        var item = readField(id, info, w);
        if (id == 16) {
            drawCloud(dc, 82, 227);
            drawFitted(dc, 155, 217, item[1], 105,
                       Gfx.FONT_SMALL, Gfx.FONT_TINY, Gfx.COLOR_WHITE);
            drawFitted(dc, 155, 235, conditionText(w), 126,
                       Gfx.FONT_XTINY, Gfx.FONT_XTINY, Gfx.COLOR_LT_GRAY);
        } else {
            drawFitted(dc, 82, 219, item[0], 70,
                       Gfx.FONT_XTINY, Gfx.FONT_XTINY, 0x00FFFF);
            drawFitted(dc, 174, 218, item[1], 99,
                       Gfx.FONT_TINY, Gfx.FONT_XTINY, Gfx.COLOR_WHITE);
        }
    }

    function batteryFooter(dc, id, info, w) {
        if (id == 0) { return; }
        var item = readField(id, info, w);
        var label = (id == 17) ? item[1] : item[0] + " " + item[1];
        if (id == 17) {
            // Tiny bolt to the left of the battery percentage.
            drawBolt(dc, 120, 253);
            drawFitted(dc, 151, 245, label, 50,
                       Gfx.FONT_TINY, Gfx.FONT_XTINY, Gfx.COLOR_WHITE);
        } else {
            drawFitted(dc, 140, 245, label, 104,
                       Gfx.FONT_XTINY, Gfx.FONT_XTINY, Gfx.COLOR_WHITE);
        }
    }

    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();
        var monitor = Monitor.getInfo();
        var w = null;
        try { w = Weather.getCurrentConditions(); } catch (e) { }

        drawHeader(dc);
        // Top strip: 78..113, with independent left, center and right slots.
        topSide(dc, 82, setting("top1", 14), monitor, w, true);
        topCenter(dc, setting("topMid", 34), monitor, w);
        topSide(dc, 217, setting("top2", 15), monitor, w, false);
        separator(dc, 33, 247, 113);

        // Pixel areas (280x280): circles top 115..161 and bottom 167..213.
        // Three separate footer lines start at 217, 235 and 245.
        ringData(dc, 89, 138, setting("ring1", 1), setting("ringColor1", 0), monitor, w);
        ringData(dc, 191, 138, setting("ring2", 2), setting("ringColor2", 1), monitor, w);
        ringData(dc, 89, 190, setting("ring3", 3), setting("ringColor3", 6), monitor, w);
        ringData(dc, 191, 190, setting("ring4", 4), setting("ringColor4", 3), monitor, w);

        // Compact footer: temperature, conditions and battery never share a baseline.
        weatherFooter(dc, setting("bottomMain", 16), monitor, w);
        batteryFooter(dc, setting("bottomMini", 17), monitor, w);
        if (_storm.warning()) { drawBolt(dc, 231, 227); }
    }
}
