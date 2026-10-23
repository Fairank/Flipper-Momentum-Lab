/**
 * @file widget_element_i.h
 * GUI: internal Widget Element API
 */

#pragma once

#include <input/input.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    GuiButtonTypeLeft,
    GuiButtonTypeCenter,
    GuiButtonTypeRight,
} GuiButtonType;

typedef void (*ButtonCallback)(GuiButtonType result, InputType type, void* context);

typedef struct WidgetElement WidgetElement;

/** Replace an existing text box's text, including after a worker update. */
void widget_element_text_box_set_text(WidgetElement* element, const char* text);

#ifdef __cplusplus
}
#endif
