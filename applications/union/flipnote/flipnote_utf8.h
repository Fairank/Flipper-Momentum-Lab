#pragma once

#include <stdint.h>
#include <string.h>

// Local to the FAP: the GUI's internal UTF-8 helpers are not SDK headers.
// Like gui_utf8_decode, malformed sequences consume one byte without changing it.
static inline size_t flipnote_utf8_next(const char* text, size_t offset) {
    size_t length = strlen(text);
    if(offset >= length) return length;
    const uint8_t* bytes = (const uint8_t*)text + offset;
    size_t count;
    uint32_t value, minimum;
    if(bytes[0] < 0x80) return offset + 1;
    if((bytes[0] & 0xE0) == 0xC0) {
        count = 2;
        value = bytes[0] & 0x1F;
        minimum = 0x80;
    } else if((bytes[0] & 0xF0) == 0xE0) {
        count = 3;
        value = bytes[0] & 0x0F;
        minimum = 0x800;
    } else if((bytes[0] & 0xF8) == 0xF0) {
        count = 4;
        value = bytes[0] & 7;
        minimum = 0x10000;
    } else {
        return offset + 1;
    }
    if(count > length - offset) return offset + 1;
    for(size_t i = 1; i < count; i++) {
        if((bytes[i] & 0xC0) != 0x80) return offset + 1;
        value = (value << 6) | (bytes[i] & 0x3F);
    }
    if(value < minimum || value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF))
        return offset + 1;
    return offset + count;
}

static inline size_t flipnote_utf8_floor(const char* text, size_t limit) {
    size_t offset = 0;
    while(text[offset]) {
        size_t next = flipnote_utf8_next(text, offset);
        if(next > limit) break;
        offset = next;
    }
    return offset;
}

static inline size_t flipnote_utf8_prev(const char* text, size_t offset) {
    return offset ? flipnote_utf8_floor(text, offset - 1) : 0;
}
