using Toybox.SensorHistory as History;
using Toybox.ActivityMonitor as Monitor;
using Toybox.System as System;
using Toybox.Weather as Weather;
using Toybox.Time as Time;
using Toybox.Time.Gregorian as Gregorian;
using Toybox.Position as Position;

function twoDigits(n) {
    return (n < 10 ? "0" : "") + n.toString();
}

function compact(n) {
    if (n >= 1000000) { return (n.toFloat() / 1000000.0).format("%.1f") + "m"; }
    if (n >= 10000) { return (n.toFloat() / 1000.0).format("%.1f") + "k"; }
    return n.toString();
}

function numeric(x) {
    if (x == null) { return "--"; }
    return x.toNumber().toString();
}

function sampleValue(type) {
    try {
        var it = null;
        var opt = { :period => 1, :order => History.ORDER_NEWEST_FIRST };
        if (type == 1) { it = History.getHeartRateHistory(opt); }
        else if (type == 3) { it = History.getBodyBatteryHistory(opt); }
        else if (type == 11) { it = History.getOxygenSaturationHistory(opt); }
        else if (type == 22) { it = History.getPressureHistory(opt); }
        else if (type == 23) { it = History.getElevationHistory(opt); }
        else if (type == 10) { it = History.getStressHistory(opt); }
        if (it != null) {
            var item = it.next();
            if (item != null && item.data != null) { return item.data; }
        }
    } catch (e) { }
    return null;
}

function sunClock(isRise, w) {
    var location = null;
    if (w != null) { location = w.observationLocationPosition; }
    if (location == null) {
        try {
            var pos = Position.getInfo();
            if (pos != null) { location = pos.position; }
        } catch (e) { }
    }
    if (location == null) { return "--:--"; }
    try {
        var moment = isRise ? Weather.getSunrise(location, Time.now())
                            : Weather.getSunset(location, Time.now());
        if (moment != null) {
            var g = Gregorian.info(moment, Time.FORMAT_SHORT);
            return twoDigits(g.hour) + ":" + twoDigits(g.min);
        }
    } catch (e) { }
    return "--:--";
}

function conditionText(w) {
    if (w == null || w.condition == null) { return "BRAK DANYCH"; }
    var c = w.condition;
    if (c == Weather.CONDITION_CLEAR || c == Weather.CONDITION_FAIR) { return "SLONECZNIE"; }
    if (c == Weather.CONDITION_PARTLY_CLOUDY) { return "CZ. ZACHM."; }
    if (c == Weather.CONDITION_MOSTLY_CLOUDY) { return "ZACHMURZENIE"; }
    if (c == Weather.CONDITION_RAIN || c == Weather.CONDITION_DRIZZLE || c == Weather.CONDITION_SCATTERED_SHOWERS) { return "DESZCZ"; }
    if (c == Weather.CONDITION_THUNDERSTORMS) { return "BURZA"; }
    if (c == Weather.CONDITION_SNOW) { return "SNIEG"; }
    if (c == Weather.CONDITION_FOG || c == Weather.CONDITION_MIST) { return "MGLA"; }
    if (c == Weather.CONDITION_WINDY) { return "WIATR"; }
    return "POCHMURNIE";
}

// Each field is [short label, displayed value, ratio or null].
// No invented goals: non-goal metrics have a neutral, unfilled ring.
function readField(id, info, w) {
    var x = null;
    var goal = null;
    if (id == 0) { return ["", "", null]; }
    if (id == 1) {
        x = sampleValue(1);
        return ["PULS", numeric(x), x == null ? null : 1.0];
    }
    if (id == 2) {
        x = info.steps;
        goal = info.stepGoal;
        return ["KROKI", x == null ? "--" : compact(x), (x != null && goal != null && goal > 0) ? x.toFloat() / goal : null];
    }
    if (id == 3) {
        x = sampleValue(3);
        return ["BODY", numeric(x), x == null ? null : x.toFloat() / 100.0];
    }
    if (id == 4) {
        goal = info.activeMinutesWeekGoal;
        x = info.activeMinutesWeek == null ? null : info.activeMinutesWeek.total;
        return ["MIN/T", numeric(x), (x != null && goal != null && goal > 0) ? x.toFloat() / goal : null];
    }
    if (id == 5) {
        x = info.activeMinutesDay == null ? null : info.activeMinutesDay.total;
        return ["MIN/D", numeric(x), null];
    }
    if (id == 6) { return ["KCAL", numeric(info.calories), null]; }
    if (id == 7) {
        x = info.distance;
        return ["DYST", x == null ? "--" : (x.toFloat() / 100000.0).format("%.1f") + "km", null];
    }
    if (id == 8) {
        x = info.floorsClimbed;
        goal = info.floorsClimbedGoal;
        return ["PIETRA", numeric(x), (x != null && goal != null && goal > 0) ? x.toFloat() / goal : null];
    }
    if (id == 9) { return ["W DOL", numeric(info.floorsDescended), null]; }
    if (id == 10) {
        x = sampleValue(10);
        if (x == null) { x = info.stressScore; }
        return ["STRES", numeric(x), x == null ? null : x.toFloat() / 100.0];
    }
    if (id == 11) {
        x = sampleValue(11);
        return ["SPO2", x == null ? "--" : numeric(x) + "%", x == null ? null : x.toFloat() / 100.0];
    }
    if (id == 12) { return ["ODDECH", numeric(info.respirationRate), null]; }
    if (id == 13) { return ["REGEN", info.timeToRecovery == null ? "--" : numeric(info.timeToRecovery) + "h", null]; }
    if (id == 14) { return ["WSCHOD", sunClock(true, w), null]; }
    if (id == 15) { return ["ZACHOD", sunClock(false, w), null]; }
    if (id == 16) { return ["POGODA", w == null ? "--" : numeric(w.temperature) + "C", null]; }
    if (id == 17) {
        x = System.getSystemStats().battery;
        return ["BAT", numeric(x) + "%", x.toFloat() / 100.0];
    }
    if (id == 18) { return ["TEMP", w == null ? "--" : numeric(w.temperature) + "C", null]; }
    if (id == 19) { return ["ODCZUW", w == null ? "--" : numeric(w.feelsLikeTemperature) + "C", null]; }
    if (id == 20) {
        x = w == null ? null : w.relativeHumidity;
        return ["WILGOT", x == null ? "--" : numeric(x) + "%", x == null ? null : x.toFloat() / 100.0];
    }
    if (id == 21) { return ["WIATR", w == null || w.windSpeed == null ? "--" : w.windSpeed.format("%.1f") + "m/s", null]; }
    if (id == 22) {
        x = sampleValue(22);
        return ["hPa", x == null ? "--" : (x.toFloat() / 100.0).format("%.0f"), null];
    }
    if (id == 23) {
        x = sampleValue(23);
        return ["WYS", x == null ? "--" : numeric(x) + "m", null];
    }
    if (id == 24) { return ["CEL KR", info.stepGoal == null ? "--" : compact(info.stepGoal), null]; }
    if (id == 25) { return ["CEL MIN", numeric(info.activeMinutesWeekGoal), null]; }
    if (id == 26) { return ["MAX", w == null ? "--" : numeric(w.highTemperature) + "C", null]; }
    if (id == 27) { return ["MIN", w == null ? "--" : numeric(w.lowTemperature) + "C", null]; }
    if (id == 28) { return ["RUCH", numeric(info.moveBarLevel), null]; }
    if (id == 29) { return ["UV", w == null ? "--" : numeric(w.uvIndex), null]; }
    if (id == 30) {
        x = w == null ? null : w.precipitationChance;
        return ["OPADY", x == null ? "--" : numeric(x) + "%", x == null ? null : x.toFloat() / 100.0];
    }
    if (id == 31) {
        var c = System.getClockTime();
        return ["CZAS", twoDigits(c.hour) + ":" + twoDigits(c.min), null];
    }
    if (id == 32) {
        var d = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return ["DATA", twoDigits(d.day) + "." + twoDigits(d.month), null];
    }
    if (id == 33) {
        x = w == null ? null : w.cloudCover;
        return ["CHMURY", x == null ? "--" : numeric(x) + "%", x == null ? null : x.toFloat() / 100.0];
    }
    return ["", "--", null];
}
