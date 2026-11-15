using Toybox.Weather as Weather;
using Toybox.Time as Time;

// Read-only Garmin Weather rule engine. This deliberately does NOT call
// network, GPS, background tasks or persistent storage.
// The watch controls when weather is updated; our interval only throttles
// re-evaluation of the already-cached values.
class GarminWeatherWarnings {
    var _lastCheck;
    // Alert code: 1..9 = last current observation (RED),
    //             17..25 = hourly forecast (CYAN).
    // Each weather phenomenon appears only once. A current observation
    // always wins when it is also present in the forecast.
    var _lastKinds;

    function initialize() {
        _lastCheck = 0;
        _lastKinds = [];
    }

    // Codes: 1 wind, 2 rain, 3 snow, 4 storm, 5 freezing rain,
    // 6 fog, 7 ice, 8 hail, 9 UV. A list keeps ALL active warnings.
    // Forecast data stays cached: only the displayed icon rotates every 5 s.
    function warning(current) {
        // Run demonstration modes before the master weather-alert switch.
        // A TEST is always visible, even with real alerts OFF and without
        // current Garmin weather data or hourly forecast availability.
        var preview = srSetting("gwPreviewV324", 0);
        if (preview > 0 && preview <= 9) {
            _lastKinds = [preview];
            _lastCheck = 0;
            return rotatingWarning();
        }
        if (preview == 10) {
            // RED thunderstorm NOW, CYAN forecast wind: alternate every 5s.
            _lastKinds = [4, 17];
            _lastCheck = 0;
            return rotatingWarning();
        }
        if (preview == 11) {
            // SAME thunderstorm present now and in forecast: only one RED.
            _lastKinds = [];
            addAlert(_lastKinds, 20); // forecast storm
            addAlert(_lastKinds, 4);  // currently observed storm wins
            _lastCheck = 0;
            return rotatingWarning();
        }
        if (preview == 12) {
            // One forecast-only thunderstorm: BLUE icon never rotates.
            _lastKinds = [20];
            _lastCheck = 0;
            return rotatingWarning();
        }
        if (preview == 13) {
            // Two current + one forecast condition, all visible by rotation.
            _lastKinds = [5, 4, 17];
            _lastCheck = 0;
            return rotatingWarning();
        }
        // The main switch controls only real-weather warning evaluation.
        // TEST 1..13 above deliberately bypasses it.
        if (!srSetting("gwOnV324", false)) {
            reset();
            return 0;
        }
        var now = Time.now().value();
        var interval = srSetting("gwIntervalV324", 15);
        if (interval < 5) { interval = 5; }
        if (interval > 60) { interval = 60; }
        if (_lastCheck == 0 || now < _lastCheck ||
            now - _lastCheck >= interval * 60) {
            _lastCheck = now;
            _lastKinds = [];
            try { _lastKinds = evaluate(current, now); } catch (e) {
                _lastKinds = [];
            }
        }
        return rotatingWarning();
    }

    // Does NOT touch Garmin Weather or settings. Safe for onPartialUpdate().
    // Every five seconds it selects the next warning in priority order.
    function rotatingWarning() {
        var count = _lastKinds.size();
        if (count == 0) { return 0; }
        if (count == 1) { return _lastKinds[0]; }
        var phase = (Time.now().value() / 5).toNumber();
        return _lastKinds[phase % count];
    }

    function reset() {
        _lastCheck = 0;
        _lastKinds = [];
    }

    function priority(tag) {
        var k = baseKind(tag);
        if (k == 5) { return 90; } // freezing rain
        if (k == 8) { return 85; } // hail
        if (k == 4) { return 80; } // thunder
        if (k == 7) { return 75; } // black ice risk
        if (k == 1) { return 65; } // high wind
        if (k == 3) { return 60; } // snow
        if (k == 2) { return 55; } // rain
        if (k == 6) { return 50; } // fog
        if (k == 9) { return 40; } // UV
        return 0;
    }

    function baseKind(tag) {
        if (tag > 16) { return tag - 16; }
        return tag;
    }

    // Duplicate categories in several hourly slots count as ONE warning.
    // If a category has both sources, keep CURRENT even if forecast was first.
    function addAlert(items, tag) {
        var kind = baseKind(tag);
        for (var i = 0; i < items.size(); i++) {
            if (baseKind(items[i]) == kind) {
                if (items[i] > 16 && tag <= 16) { items[i] = tag; }
                return items;
            }
        }
        items.add(tag);
        return items;
    }

    function mergeAlerts(items, other, isForecast) {
        for (var i = 0; i < other.size(); i++) {
            var tag = other[i];
            if (isForecast) { tag += 16; }
            addAlert(items, tag);
        }
        return items;
    }

    // Priority only controls the cycle order; never drops other hazards.
    function orderAlerts(items) {
        for (var i = 0; i < items.size(); i++) {
            for (var j = i + 1; j < items.size(); j++) {
                if (priority(items[j]) > priority(items[i])) {
                    var tmp = items[i];
                    items[i] = items[j];
                    items[j] = tmp;
                }
            }
        }
        return items;
    }

    // The API has no measurement of forecast rainfall/snowfall in mm/h.
    // Conditions describe the hazard category. precipitationChance is the
    // GENERAL chance of precipitation, not the chance of heavy rain,
    // lightning, hail or freezing rain specifically. Never label it as such.
    function classify(c, chance, wind, temp, visibility, uv, isForecast) {
        if (c == null && wind == null && uv == null && visibility == null) { return []; }
        var k = [];
        var p = chance;
        if (p == null) { p = 0; }
        if (srSetting("gwWindOnV324", true) && wind != null &&
            wind >= srSetting("gwWindV324", 10)) { k = addAlert(k, 1); }
        if (srSetting("gwStormOnV324", true) && c != null &&
            (c == Weather.CONDITION_THUNDERSTORMS ||
             c == Weather.CONDITION_SCATTERED_THUNDERSTORMS ||
             c == Weather.CONDITION_CHANCE_OF_THUNDERSTORMS ||
             c == Weather.CONDITION_TROPICAL_STORM)) {
            // "Chance of thunderstorms" in CurrentConditions is NOT a
            // measured storm. Ignore it there, and use only the separate
            // hourly forecast for a blue predictive warning.
            var stormOnlyChance = c == Weather.CONDITION_CHANCE_OF_THUNDERSTORMS;
            if ((!isForecast && !stormOnlyChance) ||
                (isForecast && chance != null &&
                 p >= srSetting("gwStormChanceV324", 50))) {
                k = addAlert(k, 4);
            }
        }
        if (srSetting("gwFreezeOnV324", true) && c != null &&
            (c == Weather.CONDITION_FREEZING_RAIN ||
             c == Weather.CONDITION_SLEET)) {
            if (!isForecast ||
                (chance != null && p >= srSetting("gwFreezeChanceV324", 40))) {
                k = addAlert(k, 5);
            }
        }
        if (srSetting("gwHailOnV324", true) && c == Weather.CONDITION_HAIL &&
            (!isForecast ||
             (chance != null && p >= srSetting("gwHailChanceV324", 40)))) {
            k = addAlert(k, 8);
        }
        if (srSetting("gwRainOnV324", true) && c != null &&
            (srSetting("gwRainHeavyV324", true) == false ||
             c == Weather.CONDITION_HEAVY_RAIN ||
             c == Weather.CONDITION_HEAVY_SHOWERS) &&
            (c == Weather.CONDITION_RAIN || c == Weather.CONDITION_LIGHT_RAIN ||
             c == Weather.CONDITION_HEAVY_RAIN || c == Weather.CONDITION_SHOWERS ||
             c == Weather.CONDITION_LIGHT_SHOWERS ||
             c == Weather.CONDITION_HEAVY_SHOWERS ||
             c == Weather.CONDITION_SCATTERED_SHOWERS ||
             c == Weather.CONDITION_DRIZZLE ||
             c == Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN ||
             c == Weather.CONDITION_CHANCE_OF_SHOWERS)) {
            var chanceOnlyRain = c == Weather.CONDITION_CHANCE_OF_SHOWERS ||
                                 c == Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN;
            if ((!isForecast && !chanceOnlyRain) ||
                (isForecast && chance != null &&
                 p >= srSetting("gwRainChanceV324", 60))) {
                k = addAlert(k, 2);
            }
        }
        if (srSetting("gwSnowOnV324", true) && c != null &&
            (srSetting("gwSnowHeavyV324", true) == false ||
             c == Weather.CONDITION_HEAVY_SNOW ||
             c == Weather.CONDITION_HEAVY_RAIN_SNOW) &&
            (c == Weather.CONDITION_SNOW || c == Weather.CONDITION_LIGHT_SNOW ||
             c == Weather.CONDITION_HEAVY_SNOW ||
             c == Weather.CONDITION_FLURRIES ||
             c == Weather.CONDITION_CHANCE_OF_SNOW ||
             c == Weather.CONDITION_CLOUDY_CHANCE_OF_SNOW ||
             c == Weather.CONDITION_HEAVY_RAIN_SNOW ||
             c == Weather.CONDITION_ICE_SNOW)) {
            var chanceOnlySnow = c == Weather.CONDITION_CHANCE_OF_SNOW ||
                                 c == Weather.CONDITION_CLOUDY_CHANCE_OF_SNOW;
            if ((!isForecast && !chanceOnlySnow) ||
                (isForecast && chance != null &&
                 p >= srSetting("gwSnowChanceV324", 60))) {
                k = addAlert(k, 3);
            }
        }
        if (srSetting("gwFogOnV324", true)) {
            if (!isForecast && visibility != null &&
                visibility <= srSetting("gwFogMetersV324", 500)) {
                k = addAlert(k, 6);
            } else if (isForecast && c == Weather.CONDITION_FOG) {
                // HourlyForecast has no visibility measurement, so forecast
                // fog can only be identified from the provider's category.
                k = addAlert(k, 6);
            } else if (!isForecast && c == Weather.CONDITION_FOG &&
                       visibility == null) {
                // Explicit observed fog with no distance measurement.
                k = addAlert(k, 6);
            }
        }
        if (srSetting("gwIceOnV324", true) && c != null) {
            var iceCondition = c == Weather.CONDITION_ICE ||
                               c == Weather.CONDITION_ICE_SNOW;
            // Risk estimate requires forecast/current precipitation AND low
            // temperature. This is not a road-surface ice measurement.
            var wet = c == Weather.CONDITION_RAIN ||
                      c == Weather.CONDITION_SNOW ||
                      c == Weather.CONDITION_RAIN_SNOW ||
                      c == Weather.CONDITION_WINTRY_MIX ||
                      c == Weather.CONDITION_HEAVY_RAIN_SNOW;
            if (iceCondition ||
                (wet && temp != null &&
                 temp <= srSetting("gwIceTempV324", 1) &&
                 (!isForecast ||
                  (chance != null && p >= srSetting("gwIceChanceV324", 50))))) {
                k = addAlert(k, 7);
            }
        }
        if (srSetting("gwUvOnV324", false) && uv != null &&
            uv >= srSetting("gwUvV324", 7)) { k = addAlert(k, 9); }
        return k;
    }

    function evaluate(current, now) {
        var matched = [];
        if (current != null && current.observationTime != null) {
            var secondsOld = now - current.observationTime.value();
            // Use only recent observations (<=45 min). If too old,
            // a red "happening now" icon would be misleading.
            if (secondsOld >= -300 && secondsOld <= 2700) {
                matched = mergeAlerts(matched, classify(current.condition,
                                   current.precipitationChance,
                                   current.windSpeed, current.temperature,
                                   current.visibility, current.uvIndex, false),
                                   false);
            }
        }
        if (!srSetting("gwForecastV324", true)) { return orderAlerts(matched); }
        var hourly = null;
        try { hourly = Weather.getHourlyForecast(); } catch (e) { return orderAlerts(matched); }
        if (hourly == null) { return orderAlerts(matched); }
        // HourlyForecast.forecastTime is the time a prediction is valid.
        // Include at most the current hour and only the requested future
        // horizon. A forecast for the current hour is still a prediction
        // (CYAN), never an observed condition (RED).
        // Never retain the array on the watch face between refresh checks.
        var horizon = srSetting("gwHorizonV324", 1);
        if (horizon < 1) { horizon = 1; }
        if (horizon > 3) { horizon = 3; }
        var count = hourly.size();
        if (count > 8) { count = 8; }
        for (var i = 0; i < count; i++) {
            try {
                var h = hourly[i];
                if (h == null || h.forecastTime == null) { continue; }
                var dt = h.forecastTime.value() - now;
                if (dt <= -3600 || dt > horizon * 3600) { continue; }
                matched = mergeAlerts(matched, classify(h.condition,
                        h.precipitationChance, h.windSpeed, h.temperature,
                        null, h.uvIndex, true), true);
            } catch (e) { /* Broken record must not crash the watch face. */ }
        }
        return orderAlerts(matched);
    }
}
