using Toybox.SensorHistory as History;
using Toybox.Time as Time;

// Barometric pressure TENDENCY indicator. NOT a certified weather warning.
// Two independent windows: 1 hour (optional early warning) and 3 hours.
// Elevation derived from barometric pressure can also drift during weather;
// filtering it reduces movement-induced false alarms but may hide genuine
// pressure changes. Never treat this indicator as a primary storm warning.
class StormGuard {
    var _lastCheck;
    var _lastResult;

    function initialize() {
        _lastCheck = 0;
        _lastResult = false;
    }

    function warning() {
        if (!srSetting("stormOnV3", false)) { return false; }
        var now = Time.now().value();
        if (_lastCheck != 0 && now - _lastCheck < 300) { return _lastResult; }
        _lastCheck = now;
        _lastResult = evaluate();
        return _lastResult;
    }

    function evaluate() {
        // 1h alert is independently enabled; insufficient data fails closed.
        if (srSetting("stormFastV310", true) &&
            pressureTrend(3600, 3000, srSetting("stormFastDropV310", 2))) {
            return true;
        }
        return pressureTrend(10800, 9000, srSetting("stormDropV3", 4));
    }

    function pressureTrend(windowSeconds, minimumSeconds, thresholdHpa) {
        try {
            var now = Time.now().value();
            var iter = History.getPressureHistory({
                :period => new Time.Duration(windowSeconds),
                :order => History.ORDER_NEWEST_FIRST
            });
            if (iter == null) { return false; }
            var sample = iter.next();
            var newestPa = null;
            var oldestPa = null;
            var newestAt = null;
            var oldestAt = null;
            var n = 0;
            while (sample != null && n < 400) {
                if (sample.data != null && sample.when != null) {
                    if (newestPa == null) {
                        newestPa = sample.data.toFloat();
                        newestAt = sample.when.value();
                    }
                    oldestPa = sample.data.toFloat();
                    oldestAt = sample.when.value();
                    n++;
                }
                sample = iter.next();
            }
            if (n < 5 || newestAt == null || oldestAt == null) { return false; }
            if (now - newestAt > 900 || newestAt - oldestAt < minimumSeconds) { return false; }
            // Pressure samples are in Pa. Positive => pressure is falling.
            var dropHpa = (oldestPa - newestPa) / 100.0;
            if (dropHpa < thresholdHpa) { return false; }
            return stableElevation(windowSeconds, minimumSeconds, now);
        } catch (e) { return false; }
    }

    function stableElevation(windowSeconds, minimumSeconds, now) {
        try {
            var iter = History.getElevationHistory({
                :period => new Time.Duration(windowSeconds),
                :order => History.ORDER_NEWEST_FIRST
            });
            if (iter == null) { return false; }
            var item = iter.next();
            var minAlt = 100000.0;
            var maxAlt = -100000.0;
            var newestAt = null;
            var oldestAt = null;
            var n = 0;
            while (item != null && n < 400) {
                if (item.data != null && item.when != null) {
                    var altitude = item.data.toFloat();
                    if (altitude < minAlt) { minAlt = altitude; }
                    if (altitude > maxAlt) { maxAlt = altitude; }
                    if (newestAt == null) { newestAt = item.when.value(); }
                    oldestAt = item.when.value();
                    n++;
                }
                item = iter.next();
            }
            if (n < 5 || newestAt == null || oldestAt == null) { return false; }
            if (now - newestAt > 900 || newestAt - oldestAt < minimumSeconds) { return false; }
            return maxAlt - minAlt < srSetting("stormAltitudeV3", 20);
        } catch (e) { return false; }
    }
}
