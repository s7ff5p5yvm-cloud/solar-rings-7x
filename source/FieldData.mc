using Toybox.SensorHistory as History;
using Toybox.Activity as Activity;
using Toybox.ActivityMonitor as Monitor;
using Toybox.System as System;
using Toybox.Weather as Weather;
using Toybox.Time as Time;
using Toybox.Time.Gregorian as Gregorian;

// Bounded caches: one entry per history type (<= 6) and per solar event.
// Never cache phone connection, steps, live pulse, weather warning status,
// battery or battery charging: those still reflect every face refresh.
var _srHistorySamples = {};
var _srSolarTimes = {};
// One short-lived cache for the nearest next solar event. Expiration happens
// at the event instant itself, so crossing sunrise/sunset is never delayed.
var _srNextSunEvent = null;
// The moon phase changes imperceptibly over one minute. This avoids repeated
// floating point astronomical work across high-power 1 Hz screen redraws.
var _srMoonSample = null;

// Shared only while onUpdate() draws one frame. Never retain the last charge
// or battery level between redraws. Null outside rendering falls back to SDK.
var _srFrameSystemStats = null;
function srSystemStatsForFrame() {
    if (_srFrameSystemStats != null) { return _srFrameSystemStats; }
    return System.getSystemStats();
}

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
    var key = type.toString();
    var now = Time.now().value();
    var cached = _srHistorySamples[key];
    // History data normally changes much more slowly than high-power 1Hz
    // watch-face redraws. 30s TTL also avoids repeating the same history
    // query in multiple fields on the same screen.
    if (cached != null && now >= cached[0] && now - cached[0] < 30) {
        return cached[1];
    }
    var value = null;
    try {
        var it = null;
        var opt = { :period => new Time.Duration(3600), :order => History.ORDER_NEWEST_FIRST };
        if (type == 1) { it = History.getHeartRateHistory(opt); }
        else if (type == 3) { it = History.getBodyBatteryHistory(opt); }
        else if (type == 11) { it = History.getOxygenSaturationHistory(opt); }
        else if (type == 22) { it = History.getPressureHistory(opt); }
        else if (type == 23) { it = History.getElevationHistory(opt); }
        else if (type == 10) { it = History.getStressHistory(opt); }
        if (it != null) {
            var item = it.next();
            var inspected = 0;
            while (item != null && inspected < 24) {
                if (item.data != null) { value = item.data; break; }
                item = it.next();
                inspected++;
            }
        }
    } catch (e) { }
    _srHistorySamples[key] = [now, value];
    return value;
}

// Prefer the newest *valid* activity-monitor pulse sample, which can be
// fresher than the historical SensorHistory series. Watch faces cannot use
// Toybox.Sensor for continuous live HR; MIP rendering still refreshes slowly.
// Current heart rate from the optical sensor, not old history.
// A missing measurement (e.g. after removing the watch) is displayed as "--".
// Do NOT use the last valid historical sample as a live heart rate.
function recentHeartRate() {
    try {
        var activity = Activity.getActivityInfo();
        if (activity == null) { return null; }
        var hr = activity.currentHeartRate;
        if (hr != null && hr > 0 && hr < 255) { return hr; }
    } catch (e) { }
    return null;
}

function sunClock(isRise, w) {
    var now = Time.now();
    var nowSeconds = now.value();
    var day = Gregorian.info(now, Time.FORMAT_SHORT);
    var dayKey = day.year * 10000 + day.month * 100 + day.day;
    var observation = 0;
    try {
        if (w != null && w.observationTime != null) {
            observation = w.observationTime.value();
        }
    } catch (e) { }
    var key = isRise ? "rise" : "set";
    var cached = _srSolarTimes[key];
    // The solar time for the same day/location is stable. Re-evaluate if
    // the weather observation changes, midnight passes, or after 90 seconds.
    if (cached != null && cached[1] == dayKey && cached[2] == observation &&
        nowSeconds >= cached[0] && nowSeconds - cached[0] < 90) {
        return cached[3];
    }
    var result = "--:--";
    var location = null;
    if (w != null) { location = w.observationLocationPosition; }
    if (location == null) {
        try {
            var info = Activity.getActivityInfo();
            if (info != null) { location = info.currentLocation; }
        } catch (e) { }
    }
    if (location != null) {
        try {
            var moment = isRise ? Weather.getSunrise(location, now)
                                : Weather.getSunset(location, now);
            if (moment != null) {
                var g = Gregorian.info(moment, Time.FORMAT_SHORT);
                result = twoDigits(g.hour) + ":" + twoDigits(g.min);
            }
        } catch (e) { }
    }
    _srSolarTimes[key] = [nowSeconds, dayKey, observation, result];
    return result;
}

// Upcoming solar event. Re-evaluated on every onUpdate() call so that
// the selected field switches after sunrise/sunset and updates on new days.
// [true => sunrise, false => sunset, formatted LOCAL hour].
// Uses the same weather-location/GPS fallback as the separate solar fields.
// Null means the device has no location or Garmin cannot calculate solar times.
function nextSunEvent(w) {
    var now = Time.now();
    var nowSeconds = now.value();
    var observation = 0;
    try {
        if (w != null && w.observationTime != null) {
            observation = w.observationTime.value();
        }
    } catch (e) { }
    var cached = _srNextSunEvent;
    if (cached != null && cached[1] == observation &&
        nowSeconds >= cached[0] &&
        nowSeconds - cached[0] < (cached[3] == null ? 30 : 120) &&
        (cached[2] == 0 || nowSeconds < cached[2])) {
        return cached[3];
    }
    var location = null;
    try {
        if (w != null) { location = w.observationLocationPosition; }
    } catch (e) { }
    if (location == null) {
        try {
            var info = Activity.getActivityInfo();
            if (info != null) { location = info.currentLocation; }
        } catch (e) { }
    }
    if (location == null) {
        _srNextSunEvent = [nowSeconds, observation, 0, null];
        return null;
    }
    try {
        var rise = Weather.getSunrise(location, now);
        var set = Weather.getSunset(location, now);
        var selected = null;
        var isRise = true;
        // Use absolute Instants; never compare local HH:MM strings.
        if (rise != null && rise.value() > now.value()) {
            selected = rise;
            isRise = true;
        }
        if (set != null && set.value() > now.value()) {
            if (selected == null || set.value() < selected.value()) {
                selected = set;
                isRise = false;
            }
        }
        // After sunset the next relevant event is tomorrow's sunrise.
        if (selected == null) {
            var tomorrow = now.add(new Time.Duration(86400));
            var tomorrowRise = Weather.getSunrise(location, tomorrow);
            if (tomorrowRise != null && tomorrowRise.value() > now.value()) {
                selected = tomorrowRise;
                isRise = true;
            }
        }
        if (selected == null) {
            _srNextSunEvent = [nowSeconds, observation, 0, null];
            return null;
        }
        var localTime = Gregorian.info(selected, Time.FORMAT_SHORT);
        var result = [isRise, twoDigits(localTime.hour) + ":" + twoDigits(localTime.min)];
        _srNextSunEvent = [nowSeconds, observation, selected.value(), result];
        return result;
    } catch (e) { }
    _srNextSunEvent = [nowSeconds, observation, 0, null];
    return null;
}

function conditionText(w) {
    if (w == null || w.condition == null) { return "BRAK DANYCH"; }
    var c = w.condition;
    if (c == Weather.CONDITION_CLEAR || c == Weather.CONDITION_FAIR ||
        c == Weather.CONDITION_MOSTLY_CLEAR) { return "SLONECZNIE"; }
    if (c == Weather.CONDITION_PARTLY_CLOUDY || c == Weather.CONDITION_PARTLY_CLEAR ||
        c == Weather.CONDITION_THIN_CLOUDS) { return "CZ. ZACHM."; }
    if (c == Weather.CONDITION_RAIN || c == Weather.CONDITION_LIGHT_RAIN ||
        c == Weather.CONDITION_HEAVY_RAIN || c == Weather.CONDITION_DRIZZLE ||
        c == Weather.CONDITION_SCATTERED_SHOWERS || c == Weather.CONDITION_SHOWERS ||
        c == Weather.CONDITION_LIGHT_SHOWERS || c == Weather.CONDITION_HEAVY_SHOWERS ||
        c == Weather.CONDITION_CHANCE_OF_SHOWERS ||
        c == Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN ||
        c == Weather.CONDITION_UNKNOWN_PRECIPITATION) { return "DESZCZ"; }
    if (c == Weather.CONDITION_THUNDERSTORMS ||
        c == Weather.CONDITION_SCATTERED_THUNDERSTORMS ||
        c == Weather.CONDITION_CHANCE_OF_THUNDERSTORMS ||
        c == Weather.CONDITION_TROPICAL_STORM) { return "BURZA"; }
    if (c == Weather.CONDITION_SNOW || c == Weather.CONDITION_LIGHT_SNOW ||
        c == Weather.CONDITION_HEAVY_SNOW || c == Weather.CONDITION_FLURRIES ||
        c == Weather.CONDITION_CHANCE_OF_SNOW || c == Weather.CONDITION_WINTRY_MIX ||
        c == Weather.CONDITION_RAIN_SNOW || c == Weather.CONDITION_ICE_SNOW ||
        c == Weather.CONDITION_LIGHT_RAIN_SNOW || c == Weather.CONDITION_HEAVY_RAIN_SNOW ||
        c == Weather.CONDITION_FREEZING_RAIN || c == Weather.CONDITION_SLEET ||
        c == Weather.CONDITION_CLOUDY_CHANCE_OF_SNOW ||
        c == Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN_SNOW) { return "SNIEG"; }
    if (c == Weather.CONDITION_FOG || c == Weather.CONDITION_MIST ||
        c == Weather.CONDITION_HAZY || c == Weather.CONDITION_HAZE) { return "MGLA"; }
    if (c == Weather.CONDITION_WINDY || c == Weather.CONDITION_SQUALL) { return "WIATR"; }
    return "POCHMURNIE";
}


// Approximate lunar phase, based on synodic month. Does not access the network.
// This is an indicative phase label, not a precise astronomical ephemeris.
function moonFraction() {
    var seconds = Time.now().value();
    var minute = (seconds / 60).toNumber();
    if (_srMoonSample != null && _srMoonSample[0] == minute) {
        return _srMoonSample[1];
    }
    var cycles = (seconds.toFloat() - 947182440.0) / 2551443.0;
    var phase = cycles - cycles.toNumber();
    _srMoonSample = [minute, phase];
    return phase;
}

function moonPhaseLabel() {
    var p = moonFraction();
    if (p < 0.055 || p >= 0.945) { return "NOW"; }
    if (p < 0.195) { return "PRZYB."; }
    if (p < 0.305) { return "I KW."; }
    if (p < 0.445) { return "GAR.+"; }
    if (p < 0.555) { return "PEL."; }
    if (p < 0.695) { return "GAR.-"; }
    if (p < 0.805) { return "III KW."; }
    return "UBYW.";
}

// Each field is [short label, displayed value, ratio or null].
// No invented goals: non-goal metrics have a neutral, unfilled ring.
function readField(id, info, w) {
    var x = null;
    var goal = null;
    if (id == 0) { return ["", "", null]; }
    if (id == 1) {
        x = recentHeartRate();
        return ["PULS", numeric(x), null];
    }
    if (id == 2) {
        x = info.steps;
        goal = info.stepGoal;
        return ["KROKI", x == null ? "--" : (x < 1000000 ? x.toString() : compact(x)), (x != null && goal != null && goal > 0) ? x.toFloat() / goal : null];
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
    if (id == 35) {
        var event = nextSunEvent(w);
        if (event == null) { return ["SLONCE", "--:--", null]; }
        return [event[0] ? "WSCHOD" : "ZACHOD", event[1], null];
    }
    if (id == 16) { return ["POGODA", w == null ? "--" : numeric(w.temperature) + "°C", null]; }
    if (id == 17) {
        x = srSystemStatsForFrame().battery;
        return ["BAT", numeric(x) + "%", x.toFloat() / 100.0];
    }
    if (id == 18) { return ["TEMP", w == null ? "--" : numeric(w.temperature) + "°C", null]; }
    if (id == 19) { return ["ODCZUW", w == null ? "--" : numeric(w.feelsLikeTemperature) + "°C", null]; }
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
    if (id == 26) { return ["MAX", w == null ? "--" : numeric(w.highTemperature) + "°C", null]; }
    if (id == 27) { return ["MIN", w == null ? "--" : numeric(w.lowTemperature) + "°C", null]; }
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
    if (id == 34) { return ["KSIEZYC", moonPhaseLabel(), null]; }
    if (id == 33) {
        x = w == null ? null : w.cloudCover;
        return ["CHMURY", x == null ? "--" : numeric(x) + "%", x == null ? null : x.toFloat() / 100.0];
    }
    return ["", "--", null];
}


// Concise 280px-friendly names, used by the optional moon phase panel.
// Astronomical approximation based on synodic month (not an ephemeris).
function moonPhaseCompactLabel() {
    var p = moonFraction();
    if (p < 0.055 || p >= 0.945) { return "NOW"; }
    if (p < 0.195) { return "PRZYBYWA"; }
    if (p < 0.305) { return "I KWADRA"; }
    if (p < 0.445) { return "GARBATY +"; }
    if (p < 0.555) { return "PELNIA"; }
    if (p < 0.695) { return "GARBATY -"; }
    if (p < 0.805) { return "III KWADRA"; }
    return "UBYWA";
}

function moonPhaseExtendedLabel() {
    var p = moonFraction();
    if (p < 0.055 || p >= 0.945) { return "NOW KSIEZYCA"; }
    if (p < 0.195) { return "SIERP PRZYBYW."; }
    if (p < 0.305) { return "PIERWSZA KWADRA"; }
    if (p < 0.445) { return "GARBATY PRZYBYW."; }
    if (p < 0.555) { return "PELNIA KSIEZYCA"; }
    if (p < 0.695) { return "GARBATY UBYW."; }
    if (p < 0.805) { return "OSTATNIA KWADRA"; }
    return "SIERP UBYW.";
}
