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

    function getInitialView() {
        return [new SolarRings7XFace()];
    }

    // Available on the device. Phone settings come from settings.xml.
    function getSettingsView() {
        var menu = makeSettingsMenu();
        return [menu, new SolarSettingsDelegate(menu)];
    }

    function onSettingsChanged() {
        Ui.requestUpdate();
    }
}

class SolarRings7XFace extends Ui.WatchFace {
    var _storm;
    function initialize() {
        WatchFace.initialize();
        _storm = new StormGuard();
    }

    function rule(dc, x1, x2, y) {
        dc.setColor(0x606060, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(x1, y, x2, y);
    }

    function sun(dc, x, y, rising) {
        dc.setColor(rising ? Gfx.COLOR_YELLOW : Gfx.COLOR_ORANGE, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawArc(x, y, 6, Gfx.ARC_COUNTER_CLOCKWISE, 0, 180);
        dc.drawLine(x - 11, y, x + 11, y);
        dc.drawLine(x, y - 11, x, y - 8);
        dc.drawLine(x - 9, y - 8, x - 7, y - 6);
        dc.drawLine(x + 9, y - 8, x + 7, y - 6);
        dc.setPenWidth(1);
    }

    function smallMoon(dc, x, y) {
        var p = moonFraction();
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, 5);
        if (p < 0.07 || p >= 0.93) {
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, 5);
        } else if (p < 0.44 || p > 0.56) {
            // Simple crescent illustration, not an astronomical projection.
            dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
            dc.fillCircle(x + (p < 0.5 ? -3 : 3), y, 4);
        }
    }

    function smallCloud(dc, x, y) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x - 7, y + 2, 5);
        dc.fillCircle(x + 1, y - 2, 7);
        dc.fillCircle(x + 9, y + 3, 5);
        dc.fillRectangle(x - 11, y + 3, 24, 5);
    }

    function lightning(dc, x, y) {
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(x + 3, y - 9, x - 3, y);
        dc.drawLine(x - 3, y, x + 3, y);
        dc.drawLine(x + 3, y, x - 2, y + 9);
        dc.setPenWidth(1);
    }

    function drawHeader(dc) {
        var c = System.getClockTime();
        var date = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var weekday = ["ND", "PN", "WT", "SR", "CZ", "PT", "SB"];
        var month = ["STY", "LUT", "MAR", "KWI", "MAJ", "CZE", "LIP", "SIE", "WRZ", "PAZ", "LIS", "GRU"];
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(110, 18, Gfx.FONT_NUMBER_MEDIUM,
                    twoDigits(c.hour) + ":" + twoDigits(c.min), Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(205, 23, Gfx.FONT_SMALL, weekday[date.day_of_week - 1], Gfx.TEXT_JUSTIFY_LEFT);
        dc.drawText(205, 47, Gfx.FONT_XTINY,
                    date.day.toString() + " " + month[date.month - 1], Gfx.TEXT_JUSTIFY_LEFT);
        rule(dc, 35, 245, 77);
    }

    function topField(dc, x, id, info, conditions, side) {
        if (id == 0) { return; }
        var data = readField(id, info, conditions);
        if (id == 14 || id == 15) {
            sun(dc, x - 19, 102, id == 14);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(x + 13, 94, Gfx.FONT_TINY, data[1], Gfx.TEXT_JUSTIFY_CENTER);
            return;
        }
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, 81, Gfx.FONT_XTINY, data[0], Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, 97, Gfx.FONT_TINY, data[1], Gfx.TEXT_JUSTIFY_CENTER);
    }

    function middleField(dc, id, info, conditions) {
        if (id == 0) { return; }
        var data = readField(id, info, conditions);
        if (id == 34) {
            smallMoon(dc, 140, 88);
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(140, 100, Gfx.FONT_XTINY, data[1], Gfx.TEXT_JUSTIFY_CENTER);
            return;
        }
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.drawText(140, 80, Gfx.FONT_XTINY, data[0], Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(140, 96, Gfx.FONT_TINY, data[1], Gfx.TEXT_JUSTIFY_CENTER);
    }

    function progressRing(dc, x, y, color, ratio) {
        var r = 27;
        dc.setPenWidth(5);
        dc.setColor(0x505050, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(x, y, r);
        if (ratio != null) {
            var p = ratio.toFloat();
            if (p < 0.0) { p = 0.0; }
            if (p > 1.0) { p = 1.0; }
            if (p >= 0.999) {
                dc.setColor(color, Gfx.COLOR_TRANSPARENT);
                dc.drawCircle(x, y, r);
            } else if (p > 0.001) {
                var end = 90 - (359.0 * p).toNumber();
                if (end < 0) { end += 360; }
                dc.setColor(color, Gfx.COLOR_TRANSPARENT);
                dc.drawArc(x, y, r, Gfx.ARC_CLOCKWISE, 90, end);
            }
        }
        dc.setPenWidth(1);
    }

    function ringField(dc, x, y, id, palette, info, conditions) {
        var data = readField(id, info, conditions);
        var color = ringPalette(palette);
        if (id == 0) { return; }
        progressRing(dc, x, y, color, data[2]);
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        var label = data[0];
        if (label.length() > 9) { label = label.substring(0, 9); }
        dc.drawText(x, y - 17, Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        var value = data[1];
        var f = value.length() > 5 ? Gfx.FONT_XTINY : Gfx.FONT_SMALL;
        dc.drawText(x, y + 1, f, value, Gfx.TEXT_JUSTIFY_CENTER);
    }

    function bottomWeather(dc, id, info, conditions) {
        if (id == 0) { return; }
        var data = readField(id, info, conditions);
        if (id == 16) {
            smallCloud(dc, 65, 249);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(165, 237, Gfx.FONT_SMALL, data[1], Gfx.TEXT_JUSTIFY_CENTER);
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(165, 254, Gfx.FONT_XTINY, conditionText(conditions), Gfx.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(0x00FFFF, Gfx.COLOR_TRANSPARENT);
            dc.drawText(83, 241, Gfx.FONT_XTINY, data[0], Gfx.TEXT_JUSTIFY_CENTER);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(181, 241, Gfx.FONT_SMALL, data[1], Gfx.TEXT_JUSTIFY_CENTER);
        }
    }

    function bottomMini(dc, id, info, conditions) {
        if (id == 0) { return; }
        var data = readField(id, info, conditions);
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        if (id == 17) {
            lightning(dc, 108, 268);
        } else {
            dc.drawText(109, 265, Gfx.FONT_XTINY, data[0], Gfx.TEXT_JUSTIFY_CENTER);
        }
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(163, 263, Gfx.FONT_SMALL, data[1], Gfx.TEXT_JUSTIFY_CENTER);
    }

    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();
        drawHeader(dc);
        var info = Monitor.getInfo();
        var conditions = null;
        try { conditions = Weather.getCurrentConditions(); } catch (e) { }

        topField(dc, 63, setting("top1", 14), info, conditions, true);
        middleField(dc, setting("topMid", 34), info, conditions);
        topField(dc, 216, setting("top2", 15), info, conditions, false);
        rule(dc, 28, 252, 119);

        // The 2 x 2 layout gives every metric its own readable 54px diameter.
        ringField(dc, 85, 151, setting("ring1", 1), setting("ringColor1", 0), info, conditions);
        ringField(dc, 195, 151, setting("ring2", 2), setting("ringColor2", 1), info, conditions);
        ringField(dc, 85, 208, setting("ring3", 3), setting("ringColor3", 6), info, conditions);
        ringField(dc, 195, 208, setting("ring4", 4), setting("ringColor4", 3), info, conditions);

        // Weather and battery preserved from v1, adapted to fit 280x280 MIP.
        bottomWeather(dc, setting("bottomMain", 16), info, conditions);
        if (_storm.warning()) { lightning(dc, 235, 248); }
        bottomMini(dc, setting("bottomMini", 17), info, conditions);
    }
}
