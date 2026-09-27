/**
 * @file utf8_internal.h
 * GUI: internal UTF-8 decoding helpers and the metrics of the native Chinese font
 */

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/** Codepoint reported for malformed UTF-8 */
#define GUI_UTF8_REPLACEMENT_CHARACTER (0xFFFDU)

/** Rows the glyphs of native_zh_font.h (WenQuanYi 12 px) use around the baseline.
 * Ideographs cover 10 rows above the baseline and the baseline row itself;
 * fullwidth brackets reach one row higher. */
#define GUI_CJK_GLYPH_ASCENT  (11)
#define GUI_CJK_GLYPH_DESCENT (1)

/** Smallest row spacing at which two rows of those glyphs never overlap */
#define GUI_CJK_LINE_HEIGHT (12)

/** Row spacing that leaves a blank row between two lines of Chinese text */
#define GUI_CJK_LINE_LEADING (13)

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

/** True when every byte of a NUL terminated string is 7-bit ASCII
 *
 * Such strings take the unchanged u8g2 text paths.
 */
static inline bool gui_utf8_is_ascii(const char* text) {
    for(const uint8_t* bytes = (const uint8_t*)text; *bytes; bytes++) {
        if(*bytes >= 0x80) return false;
    }
    return true;
}

/** True for the codepoints scripts/generate_native_zh_font.py puts into
 * native_zh_font.h: CJK punctuation, kana and ideographs, and fullwidth forms
 */
static inline bool gui_utf8_is_cjk(uint32_t codepoint) {
    return (codepoint >= 0x3000 && codepoint <= 0x9FFF) ||
           (codepoint >= 0xFF01 && codepoint <= 0xFFEF);
}

/** True when a NUL terminated string holds a codepoint gui_utf8_is_cjk() accepts */
static inline bool gui_utf8_has_cjk(const char* text) {
    uint32_t codepoint;
    size_t size;
    while((size = gui_utf8_decode(text, &codepoint)) > 0) {
        if(gui_utf8_is_cjk(codepoint)) return true;
        text += size;
    }
    return false;
}

/** Largest byte offset not above `offset` that does not fall inside a UTF-8 sequence
 *
 * @param      text    NUL terminated string
 * @param      offset  byte offset, at most the length of the string
 */
static inline size_t gui_utf8_floor(const char* text, size_t offset) {
    const uint8_t* bytes = (const uint8_t*)text;
    while(offset > 0 && (bytes[offset] & 0xC0) == 0x80) {
        offset--;
    }
    return offset;
}

/** Byte offset where the codepoint ending right before `offset` starts, 0 for 0
 *
 * Used to drop the last character of a string without splitting a sequence.
 */
static inline size_t gui_utf8_prev_start(const char* text, size_t offset) {
    return offset ? gui_utf8_floor(text, offset - 1) : 0;
}

/** Byte offset of the codepoint with the given index, or the string length
 * when the string has fewer codepoints
 */
static inline size_t gui_utf8_offset(const char* text, size_t index) {
    size_t offset = 0;
    uint32_t codepoint;
    size_t size;
    while(index > 0 && (size = gui_utf8_decode(&text[offset], &codepoint)) > 0) {
        offset += size;
        index--;
    }
    return offset;
}

/** Row spacing for a block of text
 *
 * The font's own height for text the selected fonts can draw, and no less than
 * GUI_CJK_LINE_HEIGHT once the text needs glyphs of the native Chinese font.
 */
static inline size_t gui_utf8_line_height(size_t font_height, const char* text) {
    if(font_height < (size_t)GUI_CJK_LINE_HEIGHT && gui_utf8_has_cjk(text)) {
        return (size_t)GUI_CJK_LINE_HEIGHT;
    }
    return font_height;
}
