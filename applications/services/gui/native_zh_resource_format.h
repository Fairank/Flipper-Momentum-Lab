#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define NATIVE_ZH_RECORD_SIZE      32u
#define NATIVE_ZH_SINGLE_FONT_SIZE 128u

bool native_zh_record_offset(uint16_t code, uint32_t* offset);
bool native_zh_record_font(
    uint16_t code,
    const uint8_t record[NATIVE_ZH_RECORD_SIZE],
    uint8_t font[NATIVE_ZH_SINGLE_FONT_SIZE]);
uint8_t native_zh_glyph_metrics(uint16_t code, uint8_t* extent);
