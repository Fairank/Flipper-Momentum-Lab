#include "infrared_layout.h"
#include <string.h>

size_t infrared_grid_move(size_t selected, size_t count, InfraredDirection direction) {
    if(!count) return 0;
    selected %= count;
    if(direction == InfraredDirectionLeft) return selected ? selected - 1 : count - 1;
    if(direction == InfraredDirectionRight) return (selected + 1) % count;
    const size_t column = selected % 2;
    if(direction == InfraredDirectionUp) {
        if(selected >= 2) return selected - 2;
        const size_t last = count - 1;
        return last % 2 == column ? last : (last ? last - 1 : 0);
    }
    return selected + 2 < count ? selected + 2 : (column < count ? column : 0);
}

InfraredButtonRect infrared_grid_rect(size_t slot, size_t capacity) {
    const bool large = capacity == 4;
    return (InfraredButtonRect){
        .x = 1 + (slot % 2) * 64,
        .y = (large ? 16 : 14) + (slot / 2) * (large ? 21 : 15),
        .width = 61,
        .height = large ? 18 : 13,
    };
}

void infrared_button_label(const char* source, char* destination, size_t capacity) {
    if(!capacity || !destination) return;
    if(!source) source = "";
    static const struct {
        const char* raw;
        const char* display;
    } aliases[] = {
        {"Vol_up", "Vol +"},
        {"Vol_dn", "Vol -"},
        {"Ch_next", "CH +"},
        {"Ch_prev", "CH -"},
        {"Cool_hi", "Cool max"},
        {"Heat_hi", "Heat max"},
        {"Cool_lo", "Cool low"},
        {"Heat_lo", "Heat low"},
        {"Dh", "Dry"},
        {"Brightness_up", "Light +"},
        {"Brightness_dn", "Light -"},
        {"Speed_up", "Speed +"},
        {"Speed_dn", "Speed -"},
        {"Fast_ba", "Rewind"},
        {"Fast_fo", "Forward"},
        {"+", "+ Add"},
    };
    for(size_t i = 0; i < sizeof(aliases) / sizeof(aliases[0]); ++i) {
        if(!strcmp(source, aliases[i].raw)) {
            source = aliases[i].display;
            break;
        }
    }
    size_t used = 0;
    while(*source) {
        const uint8_t c = (uint8_t)*source;
        const size_t length = c < 0x80 ? 1 : (c < 0xE0 ? 2 : (c < 0xF0 ? 3 : 4));
        if(used + length >= capacity) break;
        bool complete = true;
        for(size_t i = 1; i < length; ++i) {
            if(!source[i] || ((uint8_t)source[i] & 0xC0) != 0x80) {
                complete = false;
                break;
            }
        }
        if(!complete) break;
        if(length == 1) {
            destination[used++] = *source == '_' ? ' ' : *source;
        } else {
            memcpy(destination + used, source, length);
            used += length;
        }
        source += length;
    }
    destination[used] = '\0';
}

InfraredButtonAction infrared_button_action(
    InfraredButtonHold* state,
    InfraredButtonInput input,
    bool hold_to_send,
    int32_t id) {
    InfraredButtonAction action = {.type = InfraredActionNone, .id = id};
    if(state->held && (input == InfraredButtonRelease || input == InfraredButtonCancel ||
                       input == InfraredButtonShort)) {
        action.type = InfraredActionRelease;
        action.id = state->id;
        state->held = false;
    } else if(!state->held && hold_to_send && input == InfraredButtonPress) {
        state->held = true;
        state->id = id;
        action.type = InfraredActionPress;
    } else if(!state->held && !hold_to_send && input == InfraredButtonShort) {
        action.type = InfraredActionActivate;
    }
    return action;
}
