#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define RADAR_CAPACITY  32
#define RADAR_LINE_SIZE 160
#define RADAR_STALE_MS  12000u
typedef struct {
    char kind;
    char id[13];
    char name[33];
    int16_t average_q4;
    int16_t anchor_q4;
    int8_t rssi;
    int8_t trend;
    uint8_t channel;
    uint32_t seen;
    uint32_t anchor_time;
    bool used;
} RadarDevice;
typedef struct {
    RadarDevice devices[RADAR_CAPACITY];
    char line[RADAR_LINE_SIZE];
    size_t line_size;
    bool overflow;
    int8_t pinned;
    uint32_t malformed;
    uint32_t full;
    uint32_t last_frame;
    bool ready;
    bool running;
} RadarCore;
void radar_init(RadarCore* core);
/* Returns true only for a validated frame from the matching companion protocol. */
bool radar_feed(RadarCore* core, uint8_t byte, uint32_t now);
size_t radar_visible(
    const RadarCore* core,
    const char* filter,
    char kind,
    uint32_t now,
    uint8_t indices[RADAR_CAPACITY]);
bool radar_stale(const RadarDevice* device, uint32_t now);
unsigned radar_radius(const RadarDevice* device);
