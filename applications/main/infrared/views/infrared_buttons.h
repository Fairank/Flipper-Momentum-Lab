#pragma once

#include <gui/view.h>

/** App-local landscape controls. No GUI module ABI or firmware change is needed. */
typedef struct InfraredButtons InfraredButtons;
typedef void (*InfraredButtonCallback)(void* context, int32_t id, InputType type);

InfraredButtons* infrared_buttons_alloc(size_t page_size);
void infrared_buttons_free(InfraredButtons* buttons);
View* infrared_buttons_get_view(InfraredButtons* buttons);
void infrared_buttons_reset(InfraredButtons* buttons);
void infrared_buttons_set_header(InfraredButtons* buttons, const char* title);
void infrared_buttons_set_selected(InfraredButtons* buttons, int32_t id);
void infrared_buttons_add(
    InfraredButtons* buttons,
    const char* label,
    int32_t id,
    bool hold_to_send,
    InfraredButtonCallback callback,
    void* context);
void infrared_buttons_set_hint(
    InfraredButtons* buttons,
    int32_t id,
    const char* hint,
    bool enabled);
