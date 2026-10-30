#include "radar_range.h"
#include <stddef.h>
#include <string.h>

#define SAMPLE_SPACING_MS 250u
#define RANGE_FRESH_MS    2500u
#define RANGE_LOST_MS     12000u
#define MIN_SAMPLES       4u
#define WINDOW_MAX_AGE_MS 5000u

static void sort(int8_t* values, unsigned count) {
    for(unsigned i = 1; i < count; i++) {
        int8_t value = values[i];
        unsigned j = i;
        while(j && values[j - 1] > value) {
            values[j] = values[j - 1];
            --j;
        }
        values[j] = value;
    }
}
static int median(const int8_t* values, unsigned count) {
    int8_t sorted[RADAR_RANGE_CALIBRATION_SAMPLES];
    memcpy(sorted, values, count);
    sort(sorted, count);
    return count & 1 ? sorted[count / 2] : ((int)sorted[count / 2 - 1] + sorted[count / 2]) / 2;
}
static unsigned spread(const int8_t* values, unsigned count) {
    int8_t sorted[RADAR_RANGE_CALIBRATION_SAMPLES];
    memcpy(sorted, values, count);
    sort(sorted, count);
    unsigned trim = count / 10;
    if(!trim) trim = 1;
    return (unsigned)((int)sorted[count - 1 - trim] - sorted[trim]);
}
static bool too_many_outliers(const int8_t* values, unsigned count) {
    int center = median(values, count);
    unsigned outliers = 0;
    for(unsigned i = 0; i < count; i++) {
        int difference = (int)values[i] - center;
        if(difference > 12 || difference < -12) ++outliers;
    }
    return outliers * 4 > count;
}
static unsigned chronological(const RadarRange* range, int8_t* values) {
    unsigned start = (range->next + RADAR_RANGE_WINDOW - range->count) % RADAR_RANGE_WINDOW;
    for(unsigned i = 0; i < range->count; i++)
        values[i] = range->samples[(start + i) % RADAR_RANGE_WINDOW];
    return start;
}
static bool sufficient(const RadarRange* range) {
    unsigned first = (range->next + RADAR_RANGE_WINDOW - range->count) % RADAR_RANGE_WINDOW;
    return range->count >= MIN_SAMPLES &&
           (uint32_t)(range->accepted_at - range->times[first]) >= 1750u;
}
static RadarRangeProximity proximity(RadarRangeProximity previous, int rssi) {
    if(previous == RadarRangeProximityFar && rssi < -65) return previous;
    if(previous == RadarRangeProximityVeryNear && rssi >= -53) return previous;
    if(previous == RadarRangeProximityNear) {
        if(rssi >= -47) return RadarRangeProximityVeryNear;
        return rssi < -71 ? RadarRangeProximityFar : RadarRangeProximityNear;
    }
    return rssi >= -50 ? RadarRangeProximityVeryNear :
           rssi >= -68 ? RadarRangeProximityNear :
                         RadarRangeProximityFar;
}
static RadarRangeProximity distance_proximity(RadarRangeProximity previous, uint16_t cm) {
    if(previous == RadarRangeProximityFar && cm > 400) return previous;
    if(previous == RadarRangeProximityVeryNear && cm <= 100) return previous;
    if(previous == RadarRangeProximityNear) {
        if(cm <= 60) return RadarRangeProximityVeryNear;
        return cm > 650 ? RadarRangeProximityFar : RadarRangeProximityNear;
    }
    return cm <= 75  ? RadarRangeProximityVeryNear :
           cm <= 500 ? RadarRangeProximityNear :
                       RadarRangeProximityFar;
}

/* Fixed-point log-distance model. The three per-dB ratios correspond to path
 * loss exponents 2.2 (nominal), 1.8 and 3.2 (model envelope). They are not RF
 * accuracy guarantees. No default transmitter reference is invented.
 * Units are 1/100cm internally; bounded multiplication remains below UINT32_MAX.
 */
static uint16_t distance(int delta, unsigned ratio) {
    uint32_t value = 10000u;
    while(delta > 0) {
        value = (value * ratio + 500u) / 1000u;
        if(value > 3000000u) value = 3000000u;
        --delta;
    }
    while(delta < 0) {
        value = (value * 1000u + ratio / 2) / ratio;
        if(value < 500u) value = 500u;
        ++delta;
    }
    return (uint16_t)((value + 50u) / 100u);
}
bool radar_range_set_beacon_reference(RadarRange* range, int rssi_1m) {
    if(!range || rssi_1m < -100 || rssi_1m > -15) return false;
    if(range->reference != RadarRangeReferenceManual) {
        if(range->reference == RadarRangeReferenceBeacon && range->reference_rssi != rssi_1m) {
            range->count = range->next = 0;
        }
        if(range->reference != RadarRangeReferenceBeacon || range->reference_rssi != rssi_1m)
            range->proximity = RadarRangeProximityUnknown;
        range->reference = RadarRangeReferenceBeacon;
        range->reference_rssi = (int8_t)rssi_1m;
    }
    return true;
}
bool radar_range_begin_calibration(RadarRange* range, uint32_t now) {
    if(!range || range->calibration == RadarRangeCalibrationCollecting) return false;
    range->calibration = RadarRangeCalibrationCollecting;
    range->calibration_started = now;
    range->calibration_count = 0;
    range->calibration_gap = false;
    return true;
}
void radar_range_tick(RadarRange* range, uint32_t now) {
    if(!range || range->calibration != RadarRangeCalibrationCollecting ||
       (uint32_t)(now - range->calibration_started) < RADAR_RANGE_CALIBRATION_MS)
        return;
    if(range->calibration_count < MIN_SAMPLES || range->calibration_gap ||
       (uint32_t)(range->calibration_last - range->calibration_first) < 3000u ||
       (uint32_t)(now - range->calibration_last) > 1500u) {
        range->calibration = RadarRangeCalibrationNoSignal;
        return;
    }
    int reference = median(range->calibration_samples, range->calibration_count);
    if(spread(range->calibration_samples, range->calibration_count) > 6 ||
       too_many_outliers(range->calibration_samples, range->calibration_count) ||
       reference < -100 || reference > -15) {
        range->calibration = RadarRangeCalibrationUnstable;
        return;
    }
    range->reference = RadarRangeReferenceManual;
    range->reference_rssi = (int8_t)reference;
    range->calibration = RadarRangeCalibrationDone;
    range->proximity = RadarRangeProximityUnknown;
}
void radar_range_cancel_calibration(RadarRange* range) {
    if(range) range->calibration = RadarRangeCalibrationIdle;
}
void radar_range_reset_reference(RadarRange* range) {
    if(!range) return;
    range->reference = RadarRangeReferenceNone;
    range->reference_rssi = 0;
    range->proximity = RadarRangeProximityUnknown;
    radar_range_cancel_calibration(range);
}
void radar_range_observe(RadarRange* range, int rssi, uint32_t now) {
    if(!range || rssi < -127 || rssi > 20) return;
    radar_range_tick(range, now);
    if(range->calibration == RadarRangeCalibrationCollecting &&
       (!range->calibration_count ||
        (uint32_t)(now - range->calibration_last) >= SAMPLE_SPACING_MS)) {
        if(range->calibration_count && (uint32_t)(now - range->calibration_last) > 2500u)
            range->calibration_gap = true;
        if(!range->calibration_count) range->calibration_first = now;
        if(range->calibration_count < RADAR_RANGE_CALIBRATION_SAMPLES)
            range->calibration_samples[range->calibration_count++] = (int8_t)rssi;
        range->calibration_last = now;
    }
    if(range->count && (uint32_t)(now - range->seen) > RANGE_FRESH_MS) {
        range->count = range->next = 0;
        range->proximity = RadarRangeProximityUnknown;
    }
    range->seen = now;
    while(range->count) {
        unsigned first = (range->next + RADAR_RANGE_WINDOW - range->count) % RADAR_RANGE_WINDOW;
        if((uint32_t)(now - range->times[first]) <= WINDOW_MAX_AGE_MS) break;
        --range->count;
    }
    if(!range->count) range->proximity = RadarRangeProximityUnknown;
    if(range->count && (uint32_t)(now - range->accepted_at) < SAMPLE_SPACING_MS) return;
    range->samples[range->next] = (int8_t)rssi;
    range->times[range->next] = now;
    range->next = (range->next + 1) % RADAR_RANGE_WINDOW;
    if(range->count < RADAR_RANGE_WINDOW) ++range->count;
    range->accepted_at = now;
    int8_t values[RADAR_RANGE_WINDOW];
    chronological(range, values);
    if(sufficient(range) && spread(values, range->count) <= 8 &&
       !too_many_outliers(values, range->count)) {
        int signal = median(values, range->count);
        range->proximity =
            range->reference == RadarRangeReferenceNone ?
                proximity(range->proximity, signal) :
                distance_proximity(
                    range->proximity, distance(range->reference_rssi - signal, 1110));
    }
}
RadarRangeEstimate radar_range_estimate(const RadarRange* range, uint32_t now, bool paused) {
    RadarRangeEstimate estimate = {.status = RadarRangeStatusCollecting};
    if(!range) return estimate;
    estimate.reference = range->reference;
    if(paused) {
        estimate.status = RadarRangeStatusPaused;
        return estimate;
    }
    if(!range->count) return estimate;
    uint32_t age = now - range->seen;
    if(age > RANGE_LOST_MS) {
        estimate.status = RadarRangeStatusLost;
        return estimate;
    }
    if(age > RANGE_FRESH_MS) {
        estimate.status = RadarRangeStatusAging;
        return estimate;
    }
    if(!sufficient(range)) return estimate;
    int8_t values[RADAR_RANGE_WINDOW];
    chronological(range, values);
    unsigned variation = spread(values, range->count);
    if(variation > 8 || too_many_outliers(values, range->count)) {
        estimate.status = RadarRangeStatusUnstable;
        return estimate;
    }
    estimate.stable = true;
    int signal = median(values, range->count);
    estimate.strength = signal >= -60 ? 4 : signal >= -75 ? 3 : signal >= -90 ? 2 : 1;
    unsigned half = range->count / 2;
    if(half >= 3) {
        int movement = median(values + range->count - half, half) - median(values, half);
        estimate.trend = movement >= 3 ? 1 : movement <= -3 ? -1 : 0;
    }
    if(range->reference == RadarRangeReferenceNone) {
        estimate.status = RadarRangeStatusUncalibrated;
        estimate.proximity = proximity(range->proximity, signal);
        return estimate;
    }
    estimate.status = RadarRangeStatusReady;
    int delta = range->reference_rssi - signal;
    estimate.cm = distance(delta, 1110);
    estimate.proximity = distance_proximity(range->proximity, estimate.cm);
    unsigned error = 4 + variation / 2 + (range->count < 8 ? 2 : 0);
    uint16_t bounds[] = {
        distance(delta - (int)error, 1136),
        distance(delta - (int)error, 1075),
        distance(delta + (int)error, 1136),
        distance(delta + (int)error, 1075)};
    estimate.lower_cm = estimate.upper_cm = estimate.cm;
    for(unsigned i = 0; i < sizeof(bounds) / sizeof(bounds[0]); i++) {
        if(bounds[i] < estimate.lower_cm) estimate.lower_cm = bounds[i];
        if(bounds[i] > estimate.upper_cm) estimate.upper_cm = bounds[i];
    }
    return estimate;
}
