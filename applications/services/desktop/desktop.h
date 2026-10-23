#pragma once

#include <furi.h>

#include "desktop_settings.h"

#ifdef __cplusplus
extern "C" {
#endif

#define RECORD_DESKTOP "desktop"

typedef struct Desktop Desktop;

typedef struct {
    bool locked;
} DesktopStatus;

bool desktop_api_is_locked(Desktop* instance);

void desktop_api_unlock(Desktop* instance);

FuriPubSub* desktop_api_get_status_pubsub(Desktop* instance);

void desktop_api_get_settings(Desktop* instance, DesktopSettings* settings);

void desktop_api_set_settings(Desktop* instance, const DesktopSettings* settings);

/** Open the file manager at a directory using the normal desktop entry. */
void desktop_launch_archive(Desktop* desktop, const char* open_dir);

#ifdef __cplusplus
}
#endif
