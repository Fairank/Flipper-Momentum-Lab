#pragma once
#include "radar_core.h"

/* Passive legacy AD parsing; exact iBeacon measured power may provide an
 * advertised 1m reference. Ordinary Tx Power is not a distance calibration. */
bool radar_ble_observe(
    RadarCore* core,
    const uint8_t address[6],
    uint8_t address_type,
    int rssi,
    const uint8_t* data,
    size_t size,
    uint32_t now);
