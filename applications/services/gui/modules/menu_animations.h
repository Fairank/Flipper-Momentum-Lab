#pragma once
#include <stdint.h>

// Ring coordinates from Unleashed's three_d.c, ported by @apfxtech from
// @upiir's MIT-licensed arduino_3d_menu_oled. Kept as integer geometry so
// drawing uses Momentum's canvas, orientation and Chinese text paths.
#define MENU_RING_STEP_MS   320U
#define MENU_WINDOW_OPEN_MS 384U

typedef struct {
    int16_t x;
    int16_t y;
    uint16_t scale;
} MenuRingPoint;

static inline int32_t menu_ring_phase(int32_t direction, uint32_t elapsed_ms) {
    if(elapsed_ms >= MENU_RING_STEP_MS) return 0;
    return direction * (int32_t)(30U * (MENU_RING_STEP_MS - elapsed_ms) / MENU_RING_STEP_MS);
}

static inline MenuRingPoint menu_ring_point(int32_t slot, int32_t phase) {
    static const uint8_t path[][2] = {
        {64, 37}, {64, 37}, {64, 37}, {63, 37}, {63, 37}, {62, 37}, {61, 37}, {60, 37}, {59, 37},
        {57, 37}, {55, 37}, {52, 37}, {49, 36}, {46, 35}, {43, 35}, {39, 33}, {36, 32}, {34, 31},
        {32, 30}, {31, 29}, {30, 28}, {29, 27}, {29, 26}, {28, 26}, {28, 26}, {28, 25}, {28, 25},
        {28, 25}, {28, 25}, {28, 25}, {28, 25}, {28, 25}, {28, 25}, {28, 24}, {28, 24}, {28, 24},
        {27, 24}, {27, 23}, {27, 23}, {27, 22}, {28, 22}, {28, 21}, {28, 20}, {29, 18}, {30, 17},
        {32, 16}, {33, 15}, {35, 14}, {37, 13}, {39, 12}, {40, 12}, {41, 11}, {42, 11}, {43, 11},
        {44, 10}, {44, 10}, {45, 10}, {45, 10}, {45, 10}, {45, 10}, {46, 10}, {46, 10}, {46, 10},
        {46, 10}, {46, 10}, {47, 10}, {47, 10}, {48, 9},  {49, 9},  {50, 9},  {51, 9},  {53, 9},
        {55, 8},  {58, 8},  {61, 8},  {64, 8},
    };
    _Static_assert(sizeof(path) / sizeof(path[0]) == 76, "half-ring path length");
    int32_t frame = (150 - 30 * slot - phase) % 150;
    if(frame < 0) frame += 150;
    int32_t distance = frame < 75 ? frame : 150 - frame;
    const uint8_t* point = path[distance];
    return (MenuRingPoint){
        .x = frame > 75 ? 128 - point[0] : point[0],
        .y = point[1],
        .scale = distance < 18 ? 100 + 100 * (18 - distance) / 18 : 100,
    };
}

static inline uint32_t menu_window_frame(uint32_t elapsed_ms) {
    return elapsed_ms < MENU_WINDOW_OPEN_MS ? elapsed_ms / 48U : 8U;
}
