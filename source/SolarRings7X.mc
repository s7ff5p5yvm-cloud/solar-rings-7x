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

    function getInitialView() {
        return [new SolarRings7XFace()];
    }

    // On-watch settings work even when this app is manually copied via USB.
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
        dc.setPenWidth(1);
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawLine(x1, y, x2, y);
    }

    function sun(dc, x, y, rising) {
        dc.setPenWidth(2);
        dc.setColor(rising ? Gfx.COLOR_YELLOW : Gfx.COLOR_ORANGE, Gfx.COLOR_TRANSPARENT);
        dc.drawArc(x, y, 7, Gfx.ARC_COUNTER_CLOCKWISE, 0, 180);
        dc.drawLine(x - 12, y, x + 12, y);
        dc.drawLine(x, y - 13, x, y - 10);
        dc.drawLine(x - 10, y - 9, x - 8, y - 7);
        dc.drawLine(x + 10, y - 9, x + 8, y - 7);
        dc.setPenWidth(1);
    }

    function cloud(dc, x, y) {
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x + 8, y - 6, 7);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(x - 8, y + 2, 7);
        dc.fillCircle(x + 2, y - 2, 10);
        dc.fillCircle(x + 13, y + 3, 6);
        dc.fillRectangle(x - 14, y + 2, 32, 8);
    }

    function lightning(dc, x, y) {
        // Steady amber icon. No continuous flashing / wasted MIP updates.
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(x + 2, y - 10, x - 3, y);
        dc.drawLine(x - 3, y, x + 3, y);
        dc.drawLine(x + 3, y, x - 3, y + 11);
        dc.setPenWidth(1);
    }

    function clockHeader(dc) {
        var c = System.getClockTime();
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(108, 17, Gfx.FONT_NUMBER_MEDIUM,
                    twoDigits(c.hour) + ":" + twoDigits(c.min), Gfx.TEXT_JUSTIFY_CENTER);
        var d = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var dayNames = ["ND", "PN", "WT", "SR", "CZ", "PT", "SB"];
        var monNames = ["STY", "LUT", "MAR", "KWI", "MAJ", "CZE", "LIP", "SIE", "WRZ", "PAZ", "LIS", "GRU"];
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(199, 24, Gfx.FONT_SMALL, dayNames[d.day_of_week - 1], Gfx.TEXT_JUSTIFY_LEFT);
        dc.drawText(199, 47, Gfx.FONT_XTINY, d.day.toString() + " " + monNames[d.month - 1], Gfx.TEXT_JUSTIFY_LEFT);
        rule(dc, 40, 241, 77);
    }

    function upperField(dc, x, id, info, weather) {
        var f = readField(id, info, weather);
        if (id == 0) { return; }
        if (id == 14 || id == 15) {
            sun(dc, x - 26, 102, id == 14);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(x + 16, 89, Gfx.FONT_TINY, f[1], Gfx.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
            dc.drawText(x, 83, Gfx.FONT_XTINY, f[0], Gfx.TEXT_JUSTIFY_CENTER);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(x, 99, Gfx.FONT_TINY, f[1], Gfx.TEXT_JUSTIFY_CENTER);
        }
    }

    function drawProgress(dc, x, y, color, portion) {
        var r = 27;
        dc.setPenWidth(5);
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(x, y, r);
        if (portion != null) {
            var p = portion.toFloat();
            if (p > 1.0) { p = 1.0; }
            if (p < 0.0) { p = 0.0; }
            if (p >= 0.999) {
                dc.setColor(color, Gfx.COLOR_TRANSPARENT);
                dc.drawCircle(x, y, r);
            } else if (p > 0.0) {
                var endAngle = 90 - (359.0 * p).toNumber();
                if (endAngle < 0) { endAngle += 360; }
                dc.setColor(color, Gfx.COLOR_TRANSPARENT);
                dc.drawArc(x, y, r, Gfx.ARC_CLOCKWISE, 90, endAngle);
            }
        }
        dc.setPenWidth(1);
    }

    function circleField(dc, x, id, colorId, info, weather) {
        var f = readField(id, info, weather);
        var color = ringPalette(colorId);
        drawProgress(dc, x, 151, color, f[2]);
        if (id == 0) { return; }
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, 132, Gfx.FONT_XTINY, f[0], Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        var font = f[1].length() > 5 ? Gfx.FONT_XTINY : Gfx.FONT_TINY;
        dc.drawText(x, 153, font, f[1], Gfx.TEXT_JUSTIFY_CENTER);
    }

    function lowerField(dc, id, info, weather) {
        var f = readField(id, info, weather);
        if (id == 0) { return; }
        if (id == 16) {
            cloud(dc, 70, 215);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(164, 196, Gfx.FONT_MEDIUM, f[1], Gfx.TEXT_JUSTIFY_CENTER);
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(164, 225, Gfx.FONT_XTINY, conditionText(weather), Gfx.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(Gfx.COLOR_CYAN, Gfx.COLOR_TRANSPARENT);
            dc.drawText(91, 209, Gfx.FONT_TINY, f[0], Gfx.TEXT_JUSTIFY_CENTER);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(186, 207, Gfx.FONT_SMALL, f[1], Gfx.TEXT_JUSTIFY_CENTER);
        }
    }

    function miniField(dc, id, info, weather) {
        var f = readField(id, info, weather);
        if (id == 0) { return; }
        if (id == 17) {
            dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
            dc.drawLine(115, 254, 122, 250);
            dc.drawLine(122, 250, 119, 261);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(159, 246, Gfx.FONT_SMALL, f[1], Gfx.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
            dc.drawText(101, 250, Gfx.FONT_XTINY, f[0], Gfx.TEXT_JUSTIFY_CENTER);
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(182, 246, Gfx.FONT_SMALL, f[1], Gfx.TEXT_JUSTIFY_CENTER);
        }
    }

    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();
        clockHeader(dc);
        var info = Monitor.getInfo();
        var w = null;
        try { w = Weather.getCurrentConditions(); } catch (e) { }
        upperField(dc, 85, setting("top1", 14), info, w);
        upperField(dc, 195, setting("top2", 15), info, w);
        rule(dc, 29, 251, 119);
        circleField(dc, 38, setting("ring1", 1), setting("ringColor1", 0), info, w);
        circleField(dc, 106, setting("ring2", 2), setting("ringColor2", 1), info, w);
        circleField(dc, 174, setting("ring3", 3), setting("ringColor3", 2), info, w);
        circleField(dc, 242, setting("ring4", 4), setting("ringColor4", 3), info, w);
        rule(dc, 29, 251, 190);
        lowerField(dc, setting("bottomMain", 16), info, w);
        if (_storm.warning()) { lightning(dc, 235, 213); }
        rule(dc, 85, 195, 243);
        miniField(dc, setting("bottomMini", 17), info, w);
    }
}
