#pragma once
#include "radar_core.h"

bool radar_ble_observe(
    RadarCore* core,
    const uint8_t address[6],
    uint8_t address_type,
    int rssi,
    const uint8_t* data,
    size_t size,
    uint32_t now);
