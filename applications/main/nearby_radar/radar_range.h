#pragma once
#include <stdbool.h>
#include <stdint.h>

#define RADAR_RANGE_WINDOW              16u
#define RADAR_RANGE_CALIBRATION_SAMPLES 24u
#define RADAR_RANGE_CALIBRATION_MS      6000u

typedef enum {
    RadarRangeReferenceNone,
    RadarRangeReferenceBeacon,
    RadarRangeReferenceManual,
} RadarRangeReference;
typedef enum {
    RadarRangeStatusCollecting,
    RadarRangeStatusUncalibrated,
    RadarRangeStatusReady,
    RadarRangeStatusUnstable,
    RadarRangeStatusAging,
    RadarRangeStatusLost,
    RadarRangeStatusPaused,
} RadarRangeStatus;
typedef enum {
    RadarRangeProximityUnknown,
    RadarRangeProximityFar,
    RadarRangeProximityNear,
    RadarRangeProximityVeryNear,
} RadarRangeProximity;
typedef enum {
    RadarRangeCalibrationIdle,
    RadarRangeCalibrationCollecting,
    RadarRangeCalibrationDone,
    RadarRangeCalibrationNoSignal,
    RadarRangeCalibrationUnstable,
} RadarRangeCalibration;
/* Zero-initialize per target. References are session-scoped RSSI at one meter,
 * never the advertisement's generic transmit-power field. */
typedef struct {
    int8_t samples[RADAR_RANGE_WINDOW];
    uint32_t times[RADAR_RANGE_WINDOW];
    uint32_t seen;
    uint32_t accepted_at;
    uint8_t count;
    uint8_t next;
    RadarRangeProximity proximity;
    RadarRangeReference reference;
    int8_t reference_rssi;
    RadarRangeCalibration calibration;
    uint32_t calibration_started;
    uint32_t calibration_last;
    uint32_t calibration_first;
    int8_t calibration_samples[RADAR_RANGE_CALIBRATION_SAMPLES];
    uint8_t calibration_count;
    bool calibration_gap;
} RadarRange;
typedef struct {
    RadarRangeStatus status;
    RadarRangeProximity proximity;
    RadarRangeReference reference;
    /* Nonzero only when Ready. Endpoints describe a model envelope, not an
     * experimentally validated confidence or accuracy interval. */
    uint16_t cm;
    uint16_t lower_cm;
    uint16_t upper_cm;
    int8_t trend;
    uint8_t strength;
    bool stable;
} RadarRangeEstimate;

void radar_range_observe(RadarRange* range, int rssi, uint32_t now);
RadarRangeEstimate radar_range_estimate(const RadarRange* range, uint32_t now, bool paused);
bool radar_range_set_beacon_reference(RadarRange* range, int rssi_1m);
bool radar_range_begin_calibration(RadarRange* range, uint32_t now);
void radar_range_tick(RadarRange* range, uint32_t now);
void radar_range_cancel_calibration(RadarRange* range);
void radar_range_reset_reference(RadarRange* range);
