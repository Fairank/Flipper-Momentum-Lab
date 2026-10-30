#undef NDEBUG
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "radar_core.h"
#include "radar_range.h"

static void samples(RadarRange* r, int rssi, uint32_t start, unsigned count) {
    for(unsigned i = 0; i < count; i++)
        radar_range_observe(r, rssi, start + i * 250u);
}
static void manual(RadarRange* r, int rssi, uint32_t start) {
    assert(radar_range_begin_calibration(r, start));
    samples(r, rssi, start, 24);
    radar_range_tick(r, start + 6000);
    assert(r->calibration == RadarRangeCalibrationDone);
}
static void observe(RadarCore* c, const char* id, uint8_t type, int rssi, uint32_t now) {
    assert(radar_observe(c, 'B', id, type, rssi, 0, NULL, 0, now));
}
static void unknown(void) {
    RadarRange r = {0};
    RadarRangeEstimate e = radar_range_estimate(&r, 0, false);
    assert(e.status == RadarRangeStatusCollecting && !e.cm);
    samples(&r, -60, 0, 16);
    e = radar_range_estimate(&r, 4000, false);
    assert(e.status == RadarRangeStatusUncalibrated && e.stable);
    assert(e.reference == RadarRangeReferenceNone && e.proximity == RadarRangeProximityNear);
    assert(!e.cm && !e.lower_cm && !e.upper_cm && e.strength > 0);
    assert(!radar_range_set_beacon_reference(&r, -101));
    assert(!radar_range_set_beacon_reference(&r, -14));
}
static void distance(void) {
    RadarRange r = {0};
    assert(radar_range_set_beacon_reference(&r, -59));
    samples(&r, -59, 0, 16);
    RadarRangeEstimate near = radar_range_estimate(&r, 4000, false);
    assert(near.status == RadarRangeStatusReady && near.cm == 100);
    assert(near.lower_cm < 80 && near.upper_cm > 150);
    samples(&r, -81, 4000, 16);
    RadarRangeEstimate far = radar_range_estimate(&r, 8000, false);
    /* A 22 dB loss gives 10m with the declared nominal n=2.2 model. */
    assert(far.cm >= 950 && far.cm <= 1050 && far.cm > near.cm);
    assert(far.lower_cm < far.cm && far.upper_cm > far.cm);
    samples(&r, -20, 8000, 16);
    RadarRangeEstimate contact = radar_range_estimate(&r, 12000, false);
    assert(contact.cm >= 5 && contact.cm < 100);
    samples(&r, -127, 12000, 16);
    RadarRangeEstimate weak = radar_range_estimate(&r, 16000, false);
    assert(weak.cm <= 30000 && weak.lower_cm <= weak.cm && weak.upper_cm >= weak.cm);
}
static void outliers(void) {
    RadarRange r = {0};
    assert(radar_range_set_beacon_reference(&r, -59));
    for(unsigned i = 0; i < 1000; i++)
        radar_range_observe(&r, -59, 42);
    assert(radar_range_estimate(&r, 42, false).status == RadarRangeStatusCollecting);
    samples(&r, -59, 500, 16);
    RadarRangeEstimate before = radar_range_estimate(&r, 4300, false);
    radar_range_observe(&r, -100, 4500);
    RadarRangeEstimate after = radar_range_estimate(&r, 4500, false);
    assert(after.status == RadarRangeStatusReady && after.cm == before.cm);
    assert(!after.trend);
    for(unsigned i = 0; i < 16; i++)
        radar_range_observe(&r, i % 2 ? -90 : -45, 5000 + i * 250);
    after = radar_range_estimate(&r, 9000, false);
    assert(after.status == RadarRangeStatusUnstable && !after.cm && !after.trend);
}
static void freshness(void) {
    RadarRange r = {0};
    assert(radar_range_set_beacon_reference(&r, -59));
    samples(&r, -70, UINT32_MAX - 4000u, 16);
    RadarRangeEstimate e = radar_range_estimate(&r, 0, false);
    assert(e.status == RadarRangeStatusReady && e.cm);
    e = radar_range_estimate(&r, 2800, false);
    assert(e.status == RadarRangeStatusAging && !e.cm && !e.trend);
    e = radar_range_estimate(&r, 12500, false);
    assert(e.status == RadarRangeStatusLost && !e.cm && !e.strength);
    samples(&r, -59, 13000, 16);
    e = radar_range_estimate(&r, 17000, true);
    assert(e.status == RadarRangeStatusPaused && !e.cm && !e.trend);
    assert(r.reference == RadarRangeReferenceBeacon);
    samples(&r, -50, 40000, 1);
    assert(radar_range_estimate(&r, 40000, false).status == RadarRangeStatusCollecting);
}
static void calibration(void) {
    RadarRange r = {0};
    samples(&r, -90, 0, 16);
    manual(&r, -61, 5000);
    assert(r.reference == RadarRangeReferenceManual && r.reference_rssi == -61);
    assert(radar_range_set_beacon_reference(&r, -45));
    assert(r.reference == RadarRangeReferenceManual && r.reference_rssi == -61);
    samples(&r, -61, 11000, 16);
    assert(radar_range_estimate(&r, 15000, false).cm == 100);
    radar_range_reset_reference(&r);
    assert(r.reference == RadarRangeReferenceNone);
}
static void calibration_failure(void) {
    RadarRange r = {0};
    manual(&r, -60, 0);
    assert(radar_range_begin_calibration(&r, 7000));
    samples(&r, -70, 7000, 1);
    radar_range_tick(&r, 13000);
    assert(r.calibration == RadarRangeCalibrationNoSignal && r.reference_rssi == -60);
    assert(radar_range_begin_calibration(&r, 14000));
    for(unsigned i = 0; i < 24; i++)
        radar_range_observe(&r, i % 2 ? -85 : -45, 14000 + i * 250);
    radar_range_tick(&r, 20000);
    assert(r.calibration == RadarRangeCalibrationUnstable && r.reference_rssi == -60);
    assert(radar_range_begin_calibration(&r, 21000));
    samples(&r, -80, 21000, 16);
    radar_range_cancel_calibration(&r);
    radar_range_tick(&r, 29000);
    assert(r.calibration == RadarRangeCalibrationIdle && r.reference_rssi == -60);
    assert(radar_range_begin_calibration(&r, 30000));
    for(unsigned i = 0; i < 100; i++)
        radar_range_observe(&r, -59, 30000);
    radar_range_tick(&r, 36000);
    assert(r.calibration == RadarRangeCalibrationNoSignal && r.reference_rssi == -60);
}
static void guidance(void) {
    RadarRange r = {0};
    samples(&r, -70, 0, 16);
    RadarRangeEstimate e = radar_range_estimate(&r, 4000, false);
    assert(e.proximity == RadarRangeProximityFar);
    for(unsigned i = 0; i < 16; i++)
        radar_range_observe(&r, i % 2 ? -67 : -69, 4000 + i * 250);
    e = radar_range_estimate(&r, 8000, false);
    assert(e.proximity == RadarRangeProximityFar && !e.trend);
    samples(&r, -60, 8000, 16);
    assert(radar_range_estimate(&r, 12000, false).proximity == RadarRangeProximityNear);
    samples(&r, -45, 12000, 8);
    e = radar_range_estimate(&r, 14000, false);
    /* Movement only becomes actionable once the new window is stable. */
    assert(!e.cm);
    samples(&r, -45, 14000, 8);
    assert(radar_range_estimate(&r, 16000, false).proximity == RadarRangeProximityVeryNear);
}
static void identity(void) {
    RadarCore c;
    radar_init(&c);
    observe(&c, "AABBCCDDEEFF", 0, -60, 0);
    assert(radar_set_beacon_reference(&c, "AABBCCDDEEFF", 0, -59));
    assert(!radar_set_beacon_reference(&c, "AABBCCDDEEFF", 1, -59));
    observe(&c, "AABBCCDDEEFF", 1, -60, 250);
    assert(c.devices[1].range.reference == RadarRangeReferenceNone);
    assert(c.devices[0].range.reference == RadarRangeReferenceBeacon);
    for(unsigned i = 0; i < 32; i++) {
        char id[13];
        snprintf(id, sizeof(id), "%012X", i);
        observe(&c, id, 0, -40, 40000 + i * 250);
    }
    assert(strcmp(c.devices[0].id, "AABBCCDDEEFF"));
    assert(c.devices[0].range.reference == RadarRangeReferenceNone);
    radar_init(&c);
    assert(!radar_set_beacon_reference(&c, "AABBCCDDEEFF", 0, -59));
}
static void sparse(void) {
    RadarRange r = {0};
    assert(radar_range_set_beacon_reference(&r, -59));
    for(unsigned i = 0; i < 24; i++)
        radar_range_observe(&r, -59, i * 1000);
    /* Walking away changes six newest 1Hz points, not a 16-second old median. */
    for(unsigned i = 0; i < 6; i++)
        radar_range_observe(&r, -81, 24000 + i * 1000);
    RadarRangeEstimate e = radar_range_estimate(&r, 29000, false);
    assert(e.status == RadarRangeStatusReady && e.cm >= 950 && e.cm <= 1050);
}
static void reference_change(void) {
    RadarRange r = {0};
    assert(radar_range_set_beacon_reference(&r, -59));
    samples(&r, -59, 0, 16);
    assert(radar_range_estimate(&r, 4000, false).cm == 100);
    assert(radar_range_set_beacon_reference(&r, -59));
    assert(radar_range_estimate(&r, 4000, false).cm == 100);
    assert(radar_range_set_beacon_reference(&r, -69));
    RadarRangeEstimate e = radar_range_estimate(&r, 4000, false);
    assert(e.status == RadarRangeStatusCollecting && !e.cm);
    samples(&r, -69, 5000, 16);
    assert(radar_range_estimate(&r, 9000, false).cm == 100);
}
static void one_hertz_calibration(void) {
    RadarRange r = {0};
    assert(radar_range_begin_calibration(&r, 0));
    for(unsigned i = 0; i < 6; i++)
        radar_range_observe(&r, -60, i * 1000);
    radar_range_tick(&r, 6000);
    assert(r.calibration == RadarRangeCalibrationDone && r.reference_rssi == -60);
    RadarRangeEstimate e = radar_range_estimate(&r, 6000, false);
    assert(e.status == RadarRangeStatusReady && e.cm == 100);
    assert(radar_range_begin_calibration(&r, 7000));
    const unsigned missed[] = {0, 1000, 3000, 4000, 5000};
    for(unsigned i = 0; i < 5; i++)
        radar_range_observe(&r, -62, 7000 + missed[i]);
    radar_range_tick(&r, 13000);
    assert(r.calibration == RadarRangeCalibrationDone && r.reference_rssi == -62);
    assert(radar_range_begin_calibration(&r, 14000));
    const unsigned gap[] = {0, 250, 500, 750, 1000, 4000, 5000};
    for(unsigned i = 0; i < 7; i++)
        radar_range_observe(&r, -70, 14000 + gap[i]);
    radar_range_tick(&r, 20000);
    assert(r.calibration == RadarRangeCalibrationNoSignal && r.reference_rssi == -62);
}
static void relative_proximity(void) {
    RadarRange strong = {0}, weak = {0};
    assert(radar_range_set_beacon_reference(&strong, -40));
    assert(radar_range_set_beacon_reference(&weak, -80));
    samples(&strong, -40, 0, 16);
    samples(&weak, -80, 0, 16);
    RadarRangeEstimate a = radar_range_estimate(&strong, 4000, false);
    RadarRangeEstimate b = radar_range_estimate(&weak, 4000, false);
    assert(a.cm == 100 && b.cm == 100);
    assert(a.proximity == RadarRangeProximityNear && b.proximity == RadarRangeProximityNear);
    samples(&strong, -55, 4000, 16);
    samples(&weak, -95, 4000, 16);
    a = radar_range_estimate(&strong, 8000, false);
    b = radar_range_estimate(&weak, 8000, false);
    assert(a.cm == b.cm && a.proximity == b.proximity);
}
static void one_hertz_outlier(void) {
    RadarRange r = {0};
    assert(radar_range_set_beacon_reference(&r, -59));
    for(unsigned i = 0; i < 5; i++)
        radar_range_observe(&r, -59, i * 1000);
    radar_range_observe(&r, -100, 5000);
    RadarRangeEstimate e = radar_range_estimate(&r, 5000, false);
    assert(e.status == RadarRangeStatusReady && e.cm == 100 && !e.trend);
}
static void two_missed_packets(void) {
    RadarRange r = {0}, dense = {0};
    assert(radar_range_begin_calibration(&r, 0));
    const unsigned received[] = {0, 1000, 3000, 5000};
    for(unsigned i = 0; i < 4; i++)
        radar_range_observe(&r, -60, received[i]);
    radar_range_tick(&r, 6000);
    assert(r.calibration == RadarRangeCalibrationDone && r.reference_rssi == -60);
    RadarRangeEstimate limited = radar_range_estimate(&r, 6000, false);
    assert(limited.status == RadarRangeStatusReady && limited.cm == 100 && !limited.trend);
    assert(radar_range_set_beacon_reference(&dense, -60));
    samples(&dense, -60, 0, 16);
    RadarRangeEstimate many = radar_range_estimate(&dense, 4000, false);
    assert(limited.lower_cm < many.lower_cm && limited.upper_cm > many.upper_cm);
}
static void opposite_outliers(void) {
    RadarRange r = {0};
    assert(radar_range_set_beacon_reference(&r, -60));
    assert(radar_range_begin_calibration(&r, 0));
    radar_range_observe(&r, -90, 0);
    radar_range_observe(&r, -60, 1000);
    radar_range_observe(&r, -60, 3000);
    radar_range_observe(&r, -30, 5000);
    RadarRangeEstimate e = radar_range_estimate(&r, 5000, false);
    assert(e.status == RadarRangeStatusUnstable && !e.cm && !e.trend);
    radar_range_tick(&r, 6000);
    assert(r.calibration == RadarRangeCalibrationUnstable);
    assert(r.reference == RadarRangeReferenceBeacon && r.reference_rssi == -60);
}
int main(int argc, char** argv) {
    assert(setvbuf(stdout, NULL, _IONBF, 0) == 0);
    assert(argc == 2);
    if(!strcmp(argv[1], "unknown"))
        unknown();
    else if(!strcmp(argv[1], "distance"))
        distance();
    else if(!strcmp(argv[1], "outliers"))
        outliers();
    else if(!strcmp(argv[1], "freshness"))
        freshness();
    else if(!strcmp(argv[1], "calibration"))
        calibration();
    else if(!strcmp(argv[1], "calibration-failure"))
        calibration_failure();
    else if(!strcmp(argv[1], "guidance"))
        guidance();
    else if(!strcmp(argv[1], "identity"))
        identity();
    else if(!strcmp(argv[1], "sparse"))
        sparse();
    else if(!strcmp(argv[1], "reference-change"))
        reference_change();
    else if(!strcmp(argv[1], "one-hertz-calibration"))
        one_hertz_calibration();
    else if(!strcmp(argv[1], "relative-proximity"))
        relative_proximity();
    else if(!strcmp(argv[1], "one-hertz-outlier"))
        one_hertz_outlier();
    else if(!strcmp(argv[1], "two-missed-packets"))
        two_missed_packets();
    else if(!strcmp(argv[1], "opposite-outliers"))
        opposite_outliers();
    else
        assert(0);
    puts("Range scenario passed");
    return 0;
}
