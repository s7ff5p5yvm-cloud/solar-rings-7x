using Toybox.SensorHistory as History;
using Toybox.Time as Time;

// Conservative storm *indicator*, NOT a weather forecast and NOT a system alert.
// Sensor altitude is barometric, so atmospheric changes can also move it.
// To avoid false positives while climbing/descending, we SUPPRESS alerts if
// altitude varied significantly or when required history is not available.
class StormGuard {
    var _lastCheck;
    var _lastWarning;

    function initialize() {
        _lastCheck = 0;
        _lastWarning = false;
    }

    function warning() {
        if (!setting("alertOn", false)) { return false; }
        var now = Time.now().value();
        if (_lastCheck != 0 && now - _lastCheck < 300) { return _lastWarning; }
        _lastCheck = now;
        _lastWarning = evaluate();
        return _lastWarning;
    }

    function evaluate() {
        try {
            var now = Time.now().value();
            var readings = History.getPressureHistory({
                :period => new Time.Duration(10800),
                :order => History.ORDER_NEWEST_FIRST
            });
            var sample = readings.next();
            var newestTime = null;
            var oldestTime = null;
            var newPa = 0.0;
            var oldPa = 0.0;
            var count = 0;

            while (sample != null && count < 400) {
                if (sample.data != null) {
                    if (newestTime == null) {
                        newestTime = sample.when.value();
                        newPa = sample.data.toFloat();
                    }
                    oldestTime = sample.when.value();
                    oldPa = sample.data.toFloat();
                    count++;
                }
                sample = readings.next();
            }
            // At least 2.5 h of fresh pressure history, not a 10-minute spike.
            if (count < 5 || newestTime == null || oldestTime == null) { return false; }
            if ((now - newestTime) > 1200) { return false; }
            if ((newestTime - oldestTime) < 9000) { return false; }
            var dropHpa = (oldPa - newPa) / 100.0;
            if (dropHpa < setting("alertDrop", 4)) { return false; }

            var alts = History.getElevationHistory({
                :period => new Time.Duration(10800),
                :order => History.ORDER_NEWEST_FIRST
            });
            var altitude = alts.next();
            var minAlt = 100000.0;
            var maxAlt = -100000.0;
            var altCount = 0;
            var newestAltTime = null;
            var oldestAltTime = null;
            while (altitude != null && altCount < 400) {
                if (altitude.data != null) {
                    var alt = altitude.data.toFloat();
                    if (alt < minAlt) { minAlt = alt; }
                    if (alt > maxAlt) { maxAlt = alt; }
                    if (newestAltTime == null) { newestAltTime = altitude.when.value(); }
                    oldestAltTime = altitude.when.value();
                    altCount++;
                }
                altitude = alts.next();
            }
            // Fail closed if altitude history cannot verify a stable location.
            if (altCount < 5 || newestAltTime == null || oldestAltTime == null) { return false; }
            if ((now - newestAltTime) > 1200) { return false; }
            if ((newestAltTime - oldestAltTime) < 9000) { return false; }
            if ((maxAlt - minAlt) >= setting("altFilter", 20)) { return false; }
            return true;
        } catch (e) {
            // Permission denied, sensor not available, reset history, etc.
            return false;
        }
    }
}
