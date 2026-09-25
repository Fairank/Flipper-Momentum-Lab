/**
 * @file utf8_internal.h
 * GUI: internal UTF-8 decoding helper
 */

#pragma once

#include <stddef.h>
#include <stdint.h>

/** Codepoint reported for malformed UTF-8 */
#define GUI_UTF8_REPLACEMENT_CHARACTER (0xFFFDU)

/** Decode the codepoint at the start of a NUL terminated UTF-8 string
 *
 * Only the shortest encoding of U+0001..U+10FFFF, surrogates excluded, is
 * accepted. Anything else consumes exactly one byte and yields
 * GUI_UTF8_REPLACEMENT_CHARACTER, so decoding resumes at the next byte.
 * Continuation bytes are checked one at a time and NUL is never one, so a
 * sequence cut short by the terminator is not read past it.
 *
 * @param      text       pointer into a NUL terminated string
 * @param[out] codepoint  decoded codepoint, 0 at the terminator
 *
 * @return     number of bytes consumed: 0 at the terminator, otherwise 1 to 4
 */
static inline size_t gui_utf8_decode(const char* text, uint32_t* codepoint) {
    const uint8_t* bytes = (const uint8_t*)text;
    uint32_t value;
    uint32_t min_value;
    size_t size;

    if(bytes[0] < 0x80) {
        *codepoint = bytes[0];
        return bytes[0] ? 1 : 0;
    } else if((bytes[0] & 0xE0) == 0xC0) {
        value = bytes[0] & 0x1F;
        min_value = 0x80;
        size = 2;
    } else if((bytes[0] & 0xF0) == 0xE0) {
        value = bytes[0] & 0x0F;
        min_value = 0x800;
        size = 3;
    } else if((bytes[0] & 0xF8) == 0xF0) {
        value = bytes[0] & 0x07;
        min_value = 0x10000;
        size = 4;
    } else {
        // Continuation byte without a lead byte, or 0xF8..0xFF
        *codepoint = GUI_UTF8_REPLACEMENT_CHARACTER;
        return 1;
    }

    for(size_t i = 1; i < size; i++) {
        if((bytes[i] & 0xC0) != 0x80) {
            *codepoint = GUI_UTF8_REPLACEMENT_CHARACTER;
            return 1;
        }
        value = (value << 6) | (bytes[i] & 0x3F);
    }

    // Overlong form, UTF-16 surrogate or beyond U+10FFFF
    if(value < min_value || (value >= 0xD800 && value <= 0xDFFF) || value > 0x10FFFF) {
        *codepoint = GUI_UTF8_REPLACEMENT_CHARACTER;
        return 1;
    }

    *codepoint = value;
    return size;
}
