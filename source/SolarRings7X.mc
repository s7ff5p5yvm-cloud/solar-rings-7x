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
    function getSettingsView() {
        var m = makeSettingsMenu();
        return [m, new SolarSettingsDelegate(m)];
    }
    function onSettingsChanged() { Ui.requestUpdate(); }
}

// EXACT 280x280 layout. No Graphics.FONT_* on the face: all text uses
// fixed 3x5 pixel glyphs. Measured, nonoverlapping bounding boxes:
// time/date 25-60, sun fields 77-101, rings 117-230,
// weather 240-251, battery 256-268.
class SolarRings7XFace extends Ui.WatchFace {
    var _storm;
    function initialize() {
        WatchFace.initialize();
        _storm = new StormGuard();
    }

    function glyph(ch) {
        if (ch == "0") { return ["111","101","101","101","111"]; }
        if (ch == "1") { return ["010","110","010","010","111"]; }
        if (ch == "2") { return ["111","001","111","100","111"]; }
        if (ch == "3") { return ["111","001","111","001","111"]; }
        if (ch == "4") { return ["101","101","111","001","001"]; }
        if (ch == "5") { return ["111","100","111","001","111"]; }
        if (ch == "6") { return ["111","100","111","101","111"]; }
        if (ch == "7") { return ["111","001","001","001","001"]; }
        if (ch == "8") { return ["111","101","111","101","111"]; }
        if (ch == "9") { return ["111","101","111","001","111"]; }
        if (ch == ":") { return ["000","010","000","010","000"]; }
        if (ch == ".") { return ["000","000","000","000","010"]; }
        if (ch == "-") { return ["000","000","111","000","000"]; }
        if (ch == "/") { return ["001","001","010","100","100"]; }
        if (ch == "%") { return ["101","001","010","100","101"]; }
        if (ch == "+") { return ["000","010","111","010","000"]; }
        if (ch == " ") { return ["000","000","000","000","000"]; }
        if (ch == "A" || ch == "a") { return ["010","101","111","101","101"]; }
        if (ch == "B" || ch == "b") { return ["110","101","110","101","110"]; }
        if (ch == "C" || ch == "c") { return ["011","100","100","100","011"]; }
        if (ch == "D" || ch == "d") { return ["110","101","101","101","110"]; }
        if (ch == "E" || ch == "e") { return ["111","100","110","100","111"]; }
        if (ch == "F" || ch == "f") { return ["111","100","110","100","100"]; }
        if (ch == "G" || ch == "g") { return ["011","100","101","101","011"]; }
        if (ch == "H" || ch == "h") { return ["101","101","111","101","101"]; }
        if (ch == "I" || ch == "i") { return ["111","010","010","010","111"]; }
        if (ch == "J" || ch == "j") { return ["001","001","001","101","010"]; }
        if (ch == "K" || ch == "k") { return ["101","101","110","101","101"]; }
        if (ch == "L" || ch == "l") { return ["100","100","100","100","111"]; }
        if (ch == "M" || ch == "m") { return ["101","111","111","101","101"]; }
        if (ch == "N" || ch == "n") { return ["101","111","111","111","101"]; }
        if (ch == "O" || ch == "o") { return ["010","101","101","101","010"]; }
        if (ch == "P" || ch == "p") { return ["110","101","110","100","100"]; }
        if (ch == "Q" || ch == "q") { return ["010","101","101","111","011"]; }
        if (ch == "R" || ch == "r") { return ["110","101","110","101","101"]; }
        if (ch == "S" || ch == "s") { return ["011","100","010","001","110"]; }
        if (ch == "T" || ch == "t") { return ["111","010","010","010","010"]; }
        if (ch == "U" || ch == "u") { return ["101","101","101","101","111"]; }
        if (ch == "V" || ch == "v") { return ["101","101","101","101","010"]; }
        if (ch == "W" || ch == "w") { return ["101","101","111","111","101"]; }
        if (ch == "X" || ch == "x") { return ["101","101","010","101","101"]; }
        if (ch == "Y" || ch == "y") { return ["101","101","010","010","010"]; }
        if (ch == "Z" || ch == "z") { return ["111","001","010","100","111"]; }
        return ["000","000","000","000","000"];
    }

    // This renderer NEVER draws beyond the declared width or height.
    // A 6-digit value remains visible in a 48px ring at scale=2 (46px).
    function pixelText(dc, centerX, topY, value, width, preferredScale, color) {
        if (value == null) { return; }
        var label = value.toString();
        var n = label.length();
        var scale = preferredScale;
        if (scale < 1) { scale = 1; }
        while (scale > 1 && (n * 4 - 1) * scale > width) { scale--; }
        while (label.length() > 1 && (label.length() * 4 - 1) * scale > width) {
            label = label.substring(0, label.length() - 1);
        }
        var lengthPx = (label.length() * 4 - 1) * scale;
        var left = centerX - (lengthPx / 2).toNumber();
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        for (var k = 0; k < label.length(); k++) {
            var shape = glyph(label.substring(k, k + 1));
            for (var r = 0; r < 5; r++) {
                for (var c = 0; c < 3; c++) {
                    if (shape[r].substring(c, c + 1) == "1") {
                        dc.fillRectangle(left + (k * 4 + c) * scale,
                            topY + r * scale, scale, scale);
                    }
                }
            }
        }
    }

    function line(dc, x1, x2, y) {
        dc.setColor(0x555555, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(x1, y, x2, y);
    }

    function iconSun(dc, x, y, rising) {
        dc.setColor(rising ? Gfx.COLOR_YELLOW : Gfx.COLOR_ORANGE, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawArc(x, y, 5, Gfx.ARC_COUNTER_CLOCKWISE, 0, 180);
        dc.drawLine(x-8, y, x+8, y);
        dc.drawLine(x, y-9, x, y-7);
        dc.setPenWidth(1);
    }
    function iconMoon(dc, x, y) {
        var phase = moonFraction();
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, 6);
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        if (phase < 0.07 || phase > 0.93) { dc.fillCircle(x, y, 6); }
        else if (phase < 0.43 || phase > 0.57) {
            dc.fillCircle(x + (phase < 0.5 ? -3 : 3), y, 5);
        }
    }
    function iconCloud(dc, x, y) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x-5, y+1, 4);
        dc.fillCircle(x+1, y-2, 6);
        dc.fillCircle(x+7, y+2, 4);
        dc.fillRectangle(x-8, y+1, 18, 5);
    }
    function iconBattery(dc, x, y) {
        dc.setColor(0x00CC66, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRectangle(x-11, y-6, 20, 12);
        dc.fillRectangle(x+10, y-2, 3, 4);
        dc.setPenWidth(1);
    }
    function iconStorm(dc, x, y) {
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(x+3, y-7, x-2, y);
        dc.drawLine(x-2, y, x+2, y);
        dc.drawLine(x+2, y, x-3, y+7);
        dc.setPenWidth(1);
    }
    function iconMetric(dc, cx, cy, id, color, label) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        if (id == 1) {
            dc.fillCircle(cx-4, cy-2, 4); dc.fillCircle(cx+4, cy-2, 4);
            dc.drawLine(cx-8, cy, cx, cy+7); dc.drawLine(cx, cy+7, cx+8, cy);
        } else if (id == 2) {
            dc.fillCircle(cx-4, cy-2, 3); dc.fillCircle(cx+4, cy+2, 3);
            dc.drawLine(cx-5, cy-5, cx-3, cy-8);
        } else if (id == 3) {
            dc.drawRectangle(cx-9, cy-6, 17, 12);
            dc.fillRectangle(cx+8, cy-3, 3, 6);
            dc.drawLine(cx+1, cy-5, cx-3, cy+1);
            dc.drawLine(cx-3, cy+1, cx+2, cy+1);
        } else if (id == 4 || id == 5) {
            dc.drawCircle(cx, cy, 6); dc.drawLine(cx, cy, cx+4, cy-3);
            dc.fillRectangle(cx-2, cy-10, 4, 3);
        } else if (id == 17) {
            iconBattery(dc, cx, cy);
        } else {
            // For any of 35 configurable data types, a short label acts as icon.
            var shortName = label;
            if (shortName.length() > 3) { shortName = shortName.substring(0, 3); }
            pixelText(dc, cx, cy-5, shortName, 22, 1, color);
        }
        dc.setPenWidth(1);
    }

    function header(dc) {
        var c = System.getClockTime();
        var d = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var weekdays = ["ND","PN","WT","SR","CZ","PT","SB"];
        var months = ["STY","LUT","MAR","KWI","MAJ","CZE","LIP","SIE","WRZ","PAZ","LIS","GRU"];
        // Time 43..157 horizontal, 24..53 vertical; date 199..245.
        pixelText(dc, 104, 27, twoDigits(c.hour) + ":" + twoDigits(c.min), 114, 6, Gfx.COLOR_WHITE);
        pixelText(dc, 218, 31, weekdays[d.day_of_week-1], 32, 3, Gfx.COLOR_WHITE);
        pixelText(dc, 218, 51, d.day.toString() + " " + months[d.month-1], 53, 2, Gfx.COLOR_LT_GRAY);
        line(dc, 37, 243, 69);
    }

    function topLeftRight(dc, id, labelX, iconX, left, info, weather) {
        if (id == 0) { return; }
        var data = readField(id, info, weather);
        if (id == 14 || id == 15) {
            iconSun(dc, iconX, 89, id == 14);
            pixelText(dc, labelX, 83, data[1], 45, 2, Gfx.COLOR_WHITE);
        } else {
            pixelText(dc, labelX, 75, data[0], 52, 1, Gfx.COLOR_YELLOW);
            pixelText(dc, labelX, 88, data[1], 52, 2, Gfx.COLOR_WHITE);
        }
    }
    function topMiddle(dc, id, info, weather) {
        if (id == 0) { return; }
        var data = readField(id, info, weather);
        if (id == 34) { iconMoon(dc, 140, 89); }
        else { pixelText(dc, 140, 84, data[1], 43, 2, Gfx.COLOR_WHITE); }
    }

    function progress(dc, x, y, color, fraction) {
        dc.setColor(0x484848, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(4);
        dc.drawCircle(x, y, 26);
        if (fraction != null) {
            var p = fraction.toFloat();
            if (p < 0.0) { p = 0.0; }
            if (p > 1.0) { p = 1.0; }
            dc.setColor(color, Gfx.COLOR_TRANSPARENT);
            if (p >= 0.999) { dc.drawCircle(x, y, 26); }
            else if (p > 0.001) {
                var endAngle = 90 - (359.0 * p).toNumber();
                if (endAngle < 0) { endAngle += 360; }
                dc.drawArc(x, y, 26, Gfx.ARC_CLOCKWISE, 90, endAngle);
            }
        }
        dc.setPenWidth(1);
    }

    function ring(dc, cx, cy, id, palette, info, weather) {
        if (id == 0) { return; }
        var data = readField(id, info, weather);
        var color = ringPalette(palette);
        progress(dc, cx, cy, color, data[2]);
        iconMetric(dc, cx, cy-12, id, color, data[0]);
        var value = data[1];
        // 6 digits (999999) fit; no '10k' truncation for common step counts.
        pixelText(dc, cx, cy+2, value, 47, value.length() <= 3 ? 4 : 3, Gfx.COLOR_WHITE);
    }

    function footer(dc, mainId, minorId, info, weather) {
        line(dc, 45, 235, 235);
        var main = readField(mainId, info, weather);
        if (mainId == 16) {
            iconCloud(dc, 60, 245);
            pixelText(dc, 107, 239, main[1], 52, 2, Gfx.COLOR_WHITE);
            pixelText(dc, 188, 242, conditionText(weather), 96, 1, Gfx.COLOR_LT_GRAY);
        } else if (mainId != 0) {
            pixelText(dc, 91, 240, main[0], 65, 1, 0x00FFFF);
            pixelText(dc, 184, 239, main[1], 87, 2, Gfx.COLOR_WHITE);
        }
        if (minorId != 0) {
            var minor = readField(minorId, info, weather);
            if (minorId == 17) {
                iconBattery(dc, 112, 263);
                pixelText(dc, 157, 258, minor[1], 58, 2, Gfx.COLOR_WHITE);
            } else {
                pixelText(dc, 140, 258, minor[0] + " " + minor[1], 136, 2, Gfx.COLOR_WHITE);
            }
        }
        // A storm ⚡ is never used as the battery icon.
        if (setting("alertOn", false) && _storm.warning()) { iconStorm(dc, 203, 262); }
    }

    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();
        var info = Monitor.getInfo();
        var weather = null;
        try { weather = Weather.getCurrentConditions(); } catch (e) { }
        header(dc);
        topLeftRight(dc, setting("top1", 14), 91, 54, true, info, weather);
        topMiddle(dc, setting("topMid", 34), info, weather);
        topLeftRight(dc, setting("top2", 15), 211, 171, false, info, weather);
        line(dc, 32, 248, 108);
        ring(dc, 86, 145, setting("ring1", 1), setting("ringColor1", 0), info, weather);
        ring(dc, 194, 145, setting("ring2", 2), setting("ringColor2", 2), info, weather);
        ring(dc, 86, 203, setting("ring3", 3), setting("ringColor3", 6), info, weather);
        ring(dc, 194, 203, setting("ring4", 4), setting("ringColor4", 3), info, weather);
        footer(dc, setting("bottomMain", 16), setting("bottomMini", 17), info, weather);
    }
}
