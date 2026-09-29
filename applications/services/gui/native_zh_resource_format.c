#include "native_zh_resource_format.h"
#define NATIVE_ZH_INCLUDE_METRICS
#include "native_zh_resource_data.h"
#include <string.h>

static const uint8_t native_zh_single_header[23] = NATIVE_ZH_SINGLE_HEADER;

bool native_zh_record_offset(uint16_t code, uint32_t* offset) {
    if(!offset) return false;
    if(code >= 0x3000 && code <= 0x9fff) {
        *offset = 64u + ((uint32_t)code - 0x3000u) * NATIVE_ZH_RECORD_SIZE;
    } else if(code >= 0xff01 && code <= 0xffef) {
        *offset = 64u + (0x7000u + (uint32_t)code - 0xff01u) * NATIVE_ZH_RECORD_SIZE;
    } else {
        return false;
    }
    return true;
}

static void native_zh_bits(uint8_t* output, size_t* bit, uint8_t value, uint8_t count) {
    for(uint8_t i = 0; i < count; ++i, ++*bit) {
        if(value & (1u << i)) output[*bit / 8u] |= 1u << (*bit % 8u);
    }
}

bool native_zh_record_font(
    uint16_t code,
    const uint8_t record[NATIVE_ZH_RECORD_SIZE],
    uint8_t font[NATIVE_ZH_SINGLE_FONT_SIZE]) {
    if(!record || !font || code <= 255 || (((uint16_t)record[0] << 8) | record[1]) != code)
        return false;
    const uint8_t width = record[2], height = record[3];
    const int16_t x = (int16_t)record[4] - 128;
    const int16_t y = (int16_t)record[5] - 128;
    const int16_t advance = (int16_t)record[6] - 128;
    if(width > 12 || height > 12 || x < -16 || x > 15 || y < -16 || y > 15 || advance < 0 ||
       advance > 31 || record[7] != 0 || ((width == 0) != (height == 0)))
        return false;
    for(size_t i = 26; i < NATIVE_ZH_RECORD_SIZE; ++i) {
        if(record[i] != 0) return false;
    }
    memset(font, 0, NATIVE_ZH_SINGLE_FONT_SIZE);
    memcpy(font, native_zh_single_header, 23);
    // Empty ASCII table, one Unicode block, one glyph and a trailing sentinel.
    font[25] = 0;
    font[26] = 4;
    font[27] = 0xff;
    font[28] = 0xff;
    font[29] = (uint8_t)(code >> 8);
    font[30] = (uint8_t)code;
    uint8_t* payload = font + 32;
    size_t bit = 0;
    native_zh_bits(payload, &bit, width, 4);
    native_zh_bits(payload, &bit, height, 4);
    native_zh_bits(payload, &bit, (uint8_t)(x + 16), 5);
    native_zh_bits(payload, &bit, (uint8_t)(y + 16), 5);
    native_zh_bits(payload, &bit, (uint8_t)(advance + 32), 6);
    const size_t count = (size_t)width * height;
    size_t position = 0;
    while(position < count) {
        uint8_t zeros = 0, ones = 0;
        while(position < count && zeros < 15 &&
              !(record[8 + position / 8] & (1u << (position % 8)))) {
            ++zeros;
            ++position;
        }
        while(position < count && ones < 15 &&
              (record[8 + position / 8] & (1u << (position % 8)))) {
            ++ones;
            ++position;
        }
        native_zh_bits(payload, &bit, zeros, 4);
        native_zh_bits(payload, &bit, ones, 4);
        native_zh_bits(payload, &bit, 0, 1); // do not repeat this run pair
    }
    // At most 73 run pairs for 144 pixels: 24 + 73*9 = 681 bits.
    // The fixed font buffer also holds its header/table and two sentinel bytes.
    size_t size = (bit + 7u) / 8u;
    if(32u + size + 2u > NATIVE_ZH_SINGLE_FONT_SIZE) return false;
    font[31] = (uint8_t)(3u + size);
    return true;
}

uint8_t native_zh_glyph_metrics(uint16_t code, uint8_t* extent) {
    size_t low = 0, high = sizeof(native_zh_metrics) / sizeof(native_zh_metrics[0]);
    while(low < high) {
        size_t middle = low + (high - low) / 2;
        if(native_zh_metrics[middle].code < code)
            low = middle + 1;
        else
            high = middle;
    }
    if(low < sizeof(native_zh_metrics) / sizeof(native_zh_metrics[0]) &&
       native_zh_metrics[low].code == code) {
        if(extent) *extent = native_zh_metrics[low].extent;
        return native_zh_metrics[low].advance;
    }
    if(extent) *extent = 11;
    return 12;
}
