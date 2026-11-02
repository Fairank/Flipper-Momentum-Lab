#pragma once
#include "native_zh_resource_format.h"

// Main firmware only. Drawing never performs storage operations or waits for I/O.
void native_zh_resource_start(void (*redraw)(void*), void* context);
bool native_zh_resource_copy(uint16_t code, uint8_t font[NATIVE_ZH_SINGLE_FONT_SIZE]);
void native_zh_placeholder(uint16_t code, uint8_t font[NATIVE_ZH_SINGLE_FONT_SIZE]);
