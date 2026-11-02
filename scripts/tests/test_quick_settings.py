"""Exercise the actual quick-settings input state machine and corrupt values."""

from pathlib import Path
import re
import unittest

from test_unleashed_integration import native_test, source_between

ROOT = Path(__file__).resolve().parents[2]
VIEW = "applications/services/desktop/views/desktop_view_quick_settings.c"


class QuickSettingsTests(unittest.TestCase):
    def test_levels_navigation_edit_save_and_callback_unlock(self):
        declarations = "\n".join(
            (ROOT / name).read_text(encoding="utf-8")
            for name in (
                "applications/services/desktop/views/desktop_events.h",
                "applications/services/desktop/views/desktop_view_quick_settings.h",
            )
        )
        declarations = re.sub(
            r"^#(?:pragma|include)[^\n]*", "", declarations, flags=re.M
        )
        native_test(
            r"""
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <math.h>
#define furi_assert assert
#define CLAMP(x, hi, lo) ((x) < (lo) ? (lo) : ((x) > (hi) ? (hi) : (x)))
typedef struct { void* model; } View;
typedef enum { InputKeyUp, InputKeyDown, InputKeyLeft, InputKeyRight, InputKeyOk, InputKeyBack } InputKey;
typedef enum { InputTypePress, InputTypeRelease, InputTypeShort, InputTypeLong, InputTypeRepeat } InputType;
typedef struct { InputKey key; InputType type; } InputEvent;
static unsigned locks;
#define with_view_model(view, declaration, code, update) do { \
    declaration = (view)->model; ++locks; code; --locks; (void)(update); \
} while(0)
"""
            + declarations
            + source_between(VIEW, "typedef enum {", "\nstatic const char* const")
            + source_between(
                VIEW,
                "static uint8_t desktop_quick_settings_level_from_value(",
                "\nvoid desktop_quick_settings_set_callback(",
            )
            + source_between(
                VIEW,
                "static bool desktop_quick_settings_input_callback(",
                "\nDesktopQuickSettingsView* desktop_quick_settings_alloc(",
            )
            + r"""
static unsigned notifications;
static DesktopEvent last;
static void changed(DesktopEvent event, void* context) {
    assert(locks == 0); assert(context == &notifications);
    ++notifications; last = event;
}
static bool press(DesktopQuickSettingsView* view, InputKey key, InputType type) {
    InputEvent event = {.key = key, .type = type};
    return desktop_quick_settings_input_callback(&event, view);
}
int main(void) {
    assert(desktop_quick_settings_level_from_value(NAN) == 0);
    assert(desktop_quick_settings_level_from_value(-INFINITY) == 0);
    assert(desktop_quick_settings_level_from_value(INFINITY) == 20);
    assert(desktop_quick_settings_level_from_value(-0.1f) == 0);
    assert(desktop_quick_settings_level_from_value(1.1f) == 20);
    for(unsigned i = 0; i <= 20; ++i) {
        assert(desktop_quick_settings_level_from_value(desktop_quick_settings_value_from_level(i)) == i);
    }
    DesktopQuickSettingsViewModel model = {0};
    View view = {.model = &model};
    DesktopQuickSettingsView settings = {.view = &view, .callback = changed, .context = &notifications};
    assert(!press(&settings, InputKeyBack, InputTypeShort));
    assert(press(&settings, InputKeyRight, InputTypeShort));
    assert(last == DesktopQuickSettingsEventClose);
    assert(press(&settings, InputKeyOk, InputTypeShort));
    assert(model.editing);
    for(unsigned i = 0; i < 25; ++i) assert(press(&settings, InputKeyRight, InputTypeRepeat));
    assert(model.brightness == 20 && last == DesktopQuickSettingsEventBrightnessChanged);
    unsigned before = notifications;
    assert(press(&settings, InputKeyRight, InputTypeRepeat));
    assert(notifications == before);
    assert(press(&settings, InputKeyDown, InputTypeShort));
    assert(model.idx == 0);
    assert(press(&settings, InputKeyBack, InputTypeShort));
    assert(!model.editing && last == DesktopQuickSettingsEventSave);
    assert(press(&settings, InputKeyDown, InputTypeShort));
    assert(model.idx == 1);
    assert(press(&settings, InputKeyOk, InputTypeShort));
    before = notifications;
    assert(press(&settings, InputKeyLeft, InputTypeRepeat));
    assert(model.volume == 0 && notifications == before);
    assert(press(&settings, InputKeyRight, InputTypeShort));
    assert(model.volume == 1 && last == DesktopQuickSettingsEventVolumeChanged);
    assert(press(&settings, InputKeyOk, InputTypeShort));
    assert(!model.editing && last == DesktopQuickSettingsEventSave);
    assert(press(&settings, InputKeyDown, InputTypeShort));
    assert(model.idx == 2);
    assert(press(&settings, InputKeyOk, InputTypeShort));
    assert(model.vibro && !model.editing && last == DesktopQuickSettingsEventVibroChanged);
    assert(press(&settings, InputKeyDown, InputTypeRepeat));
    assert(model.idx == 0);
    assert(press(&settings, InputKeyUp, InputTypeRepeat));
    assert(model.idx == 2);
    assert(!press(&settings, InputKeyOk, InputTypeRelease));
    assert(!press(&settings, InputKeyBack, InputTypeShort));
    return 0;
}
"""
        )
