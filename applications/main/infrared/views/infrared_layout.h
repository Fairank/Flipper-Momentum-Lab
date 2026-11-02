#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum {
    InfraredDirectionLeft,
    InfraredDirectionRight,
    InfraredDirectionUp,
    InfraredDirectionDown,
} InfraredDirection;

typedef struct {
    uint8_t x, y, width, height;
} InfraredButtonRect;

size_t infrared_grid_move(size_t selected, size_t count, InfraredDirection direction);
InfraredButtonRect infrared_grid_rect(size_t slot, size_t capacity);
void infrared_button_label(const char* source, char* destination, size_t capacity);

typedef enum {
    InfraredButtonPress,
    InfraredButtonRelease,
    InfraredButtonShort,
    InfraredButtonCancel,
} InfraredButtonInput;

typedef enum {
    InfraredActionNone,
    InfraredActionPress,
    InfraredActionRelease,
    InfraredActionActivate,
} InfraredActionType;

typedef struct {
    bool held;
    int32_t id;
} InfraredButtonHold;

typedef struct {
    InfraredActionType type;
    int32_t id;
} InfraredButtonAction;

InfraredButtonAction infrared_button_action(
    InfraredButtonHold* state,
    InfraredButtonInput input,
    bool hold_to_send,
    int32_t id);
