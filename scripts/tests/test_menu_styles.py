"""Host regressions for the Grid, Macintosh and 3D main menu styles.

The C test compiles the navigation helpers of the GUI Menu module unchanged, with
the InputKey and MenuStyle enumerations and the MIN macro from the firmware
headers, and presses every direction in menus of 0 to 7 items and in larger ones
whose last page, row or column is partial. The Python tests read the MenuStyle
enumeration and the names the settings screen shows for it. They do not replace a
firmware build or a check on a Flipper.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MENU_C = "applications/services/gui/modules/menu.c"
SETTINGS_H = "lib/momentum/settings.h"
SETTINGS_C = "lib/momentum/settings.c"
NAMES_C = (
    "applications/main/momentum_app/scenes/momentum_app_scene_interface_mainmenu.c"
)
INPUT_KEYS_H = "targets/f7/furi_hal/furi_hal_resources.h"
CORE_DEFINES_H = "furi/core/core_defines.h"

# The styles in the order their stored numbers give them; the last three are the ported ones
STYLES = [
    "MenuStyleList",
    "MenuStyleWii",
    "MenuStyleDsi",
    "MenuStylePs4",
    "MenuStyleVertical",
    "MenuStyleC64",
    "MenuStyleCompact",
    "MenuStyleMNTM",
    "MenuStyleCoverFlow",
    "MenuStyleGrid",
    "MenuStyleMacintosh",
    "MenuStyleThreeD",
]
NAMES = [
    "列表",
    "Wii",
    "DSi",
    "PS4",
    "纵向",
    "C64",
    "紧凑",
    "MNTM",
    "封面流",
    "网格",
    "经典桌面",
    "立体",
]

# Firmware definitions the helpers use: file, start, text right after it
DECLARATIONS = [
    (CORE_DEFINES_H, "#ifndef MAX", "\n#ifndef ABS"),
    (CORE_DEFINES_H, "#ifndef COUNT_OF", "\n#ifndef FURI_SWAP"),
    (INPUT_KEYS_H, "/* Input Keys */", "\n/* Light */"),
    (
        SETTINGS_H,
        "typedef enum {\n    MenuStyleList,",
        "\ntypedef enum {\n    SpiDefault",
    ),
    (MENU_C, "#define MENU_GRID_COLS", "\nstatic void menu_draw_callback("),
]

GRID, MAC, RING = "MenuStyleGrid", "MenuStyleMacintosh", "MenuStyleThreeD"
UP, DOWN, LEFT, RIGHT = "InputKeyUp", "InputKeyDown", "InputKeyLeft", "InputKeyRight"

# Style, items, position, key, position after the key
STEPS = [
    # Grid: pages of 5 x 3. An empty or single item menu stays put
    (GRID, 0, 0, UP, 0),
    (GRID, 0, 0, DOWN, 0),
    (GRID, 0, 0, LEFT, 0),
    (GRID, 0, 0, RIGHT, 0),
    (GRID, 1, 0, UP, 0),
    (GRID, 1, 0, DOWN, 0),
    (GRID, 1, 0, LEFT, 0),
    (GRID, 1, 0, RIGHT, 0),
    # Two items: Left and Right wrap, Up and Down have no other row
    (GRID, 2, 0, RIGHT, 1),
    (GRID, 2, 0, LEFT, 1),
    (GRID, 2, 1, RIGHT, 0),
    (GRID, 2, 1, LEFT, 0),
    (GRID, 2, 0, DOWN, 0),
    (GRID, 2, 1, UP, 1),
    # One full row
    (GRID, 5, 3, DOWN, 3),
    (GRID, 5, 3, UP, 3),
    (GRID, 5, 4, RIGHT, 0),
    (GRID, 5, 0, LEFT, 4),
    # A second row of one: only column 0 has two rows to cycle
    (GRID, 6, 0, DOWN, 5),
    (GRID, 6, 5, DOWN, 0),
    (GRID, 6, 5, UP, 0),
    (GRID, 6, 0, UP, 5),
    (GRID, 6, 1, DOWN, 1),
    (GRID, 6, 1, UP, 1),
    (GRID, 6, 4, DOWN, 4),
    (GRID, 6, 5, RIGHT, 0),
    (GRID, 6, 0, LEFT, 5),
    # A second row of two
    (GRID, 7, 1, DOWN, 6),
    (GRID, 7, 6, DOWN, 1),
    (GRID, 7, 6, UP, 1),
    (GRID, 7, 1, UP, 6),
    (GRID, 7, 2, DOWN, 2),
    (GRID, 7, 2, UP, 2),
    (GRID, 7, 6, RIGHT, 0),
    (GRID, 7, 0, LEFT, 6),
    # A second page of one item: Up and Down stay on the page, Left and Right cross it
    (GRID, 16, 14, RIGHT, 15),
    (GRID, 16, 15, RIGHT, 0),
    (GRID, 16, 15, LEFT, 14),
    (GRID, 16, 0, LEFT, 15),
    (GRID, 16, 15, DOWN, 15),
    (GRID, 16, 15, UP, 15),
    (GRID, 16, 10, DOWN, 0),
    (GRID, 16, 12, DOWN, 2),
    (GRID, 16, 12, UP, 7),
    (GRID, 16, 3, UP, 13),
    # A third page of one item after a full second page
    (GRID, 31, 30, DOWN, 30),
    (GRID, 31, 30, UP, 30),
    (GRID, 31, 30, LEFT, 29),
    (GRID, 31, 30, RIGHT, 0),
    (GRID, 31, 29, DOWN, 19),
    (GRID, 31, 29, UP, 24),
    (GRID, 31, 19, UP, 29),
    # Macintosh: rows of 3, Up and Down cycle the whole column
    (MAC, 0, 0, UP, 0),
    (MAC, 0, 0, DOWN, 0),
    (MAC, 0, 0, LEFT, 0),
    (MAC, 0, 0, RIGHT, 0),
    (MAC, 1, 0, UP, 0),
    (MAC, 1, 0, DOWN, 0),
    (MAC, 1, 0, LEFT, 0),
    (MAC, 1, 0, RIGHT, 0),
    (MAC, 2, 0, DOWN, 0),
    (MAC, 2, 0, UP, 0),
    (MAC, 2, 0, RIGHT, 1),
    (MAC, 2, 0, LEFT, 1),
    (MAC, 2, 1, DOWN, 1),
    (MAC, 2, 1, UP, 1),
    (MAC, 2, 1, RIGHT, 0),
    (MAC, 2, 1, LEFT, 0),
    # Five items: the last column has one row, the others two
    (MAC, 5, 2, DOWN, 2),
    (MAC, 5, 2, UP, 2),
    (MAC, 5, 1, DOWN, 4),
    (MAC, 5, 4, DOWN, 1),
    (MAC, 5, 4, UP, 1),
    (MAC, 5, 1, UP, 4),
    (MAC, 5, 4, RIGHT, 0),
    (MAC, 5, 0, LEFT, 4),
    # Six items fill two rows
    (MAC, 6, 0, DOWN, 3),
    (MAC, 6, 3, DOWN, 0),
    (MAC, 6, 0, UP, 3),
    (MAC, 6, 5, DOWN, 2),
    (MAC, 6, 2, UP, 5),
    (MAC, 6, 5, RIGHT, 0),
    # Seven items: a third row of one, past what the window shows at once
    (MAC, 7, 6, DOWN, 0),
    (MAC, 7, 6, UP, 3),
    (MAC, 7, 3, DOWN, 6),
    (MAC, 7, 0, UP, 6),
    (MAC, 7, 4, DOWN, 1),
    (MAC, 7, 1, UP, 4),
    (MAC, 7, 5, DOWN, 2),
    (MAC, 7, 6, RIGHT, 0),
    (MAC, 7, 0, LEFT, 6),
    (MAC, 9, 8, DOWN, 2),
    (MAC, 9, 2, UP, 8),
    # 3D: Up and Left turn back, Down and Right turn forward, around the end
    (RING, 0, 0, UP, 0),
    (RING, 0, 0, DOWN, 0),
    (RING, 0, 0, LEFT, 0),
    (RING, 0, 0, RIGHT, 0),
    (RING, 1, 0, UP, 0),
    (RING, 1, 0, DOWN, 0),
    (RING, 1, 0, LEFT, 0),
    (RING, 1, 0, RIGHT, 0),
    (RING, 2, 0, UP, 1),
    (RING, 2, 0, DOWN, 1),
    (RING, 2, 0, LEFT, 1),
    (RING, 2, 0, RIGHT, 1),
    (RING, 2, 1, UP, 0),
    (RING, 2, 1, DOWN, 0),
    (RING, 5, 0, UP, 4),
    (RING, 5, 0, DOWN, 1),
    (RING, 5, 4, DOWN, 0),
    (RING, 5, 4, RIGHT, 0),
    (RING, 5, 4, LEFT, 3),
    (RING, 7, 6, RIGHT, 0),
    (RING, 7, 0, LEFT, 6),
    (RING, 7, 3, UP, 2),
    (RING, 7, 3, DOWN, 4),
]


def source_between(path, start, end=None):
    text = (ROOT / path).read_text(encoding="utf-8")
    begin = text.index(start)
    return text[begin : text.index(end, begin) if end else len(text)]


def c_step(style, count, position, key, expected):
    return f"    {{{style}, {count}, {position}, {key}, {expected}}},\n"


def native_test(source):
    compiler = next(
        (found for found in map(shutil.which, ("cc", "gcc", "clang")) if found), None
    )
    if compiler is None:
        raise AssertionError("A host C compiler is required")
    with tempfile.TemporaryDirectory() as folder:
        src = Path(folder) / "regression.c"
        exe = Path(folder) / ("regression.exe" if os.name == "nt" else "regression")
        src.write_text(source, encoding="utf-8")
        command = [compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", "-I."]
        if sys.platform.startswith("linux"):
            # A sanitizer report ends the run instead of passing unseen in stderr
            command += [
                "-fsanitize=address,undefined",
                "-fno-sanitize-recover=all",
                "-fno-omit-frame-pointer",
                "-O1",
            ]
        command += [str(src), "-o", str(exe)]
        # Run from the repository root so the production sources resolve
        build = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        if build.returncode != 0:
            raise AssertionError(f"Native regression failed to build:\n{build.stderr}")
        result = subprocess.run([str(exe)], capture_output=True, text=True, timeout=120)
        if result.returncode != 0:
            raise AssertionError(
                f"Native regression returned {result.returncode}:\n"
                f"{result.stdout}{result.stderr}"
            )


INCLUDES = r"""
#undef NDEBUG
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
"""

HARNESS = r"""
typedef struct {
    MenuStyle style;
    size_t count;
    size_t position;
    InputKey key;
    size_t expected;
} Step;

static const char* style_name(MenuStyle style) {
    switch(style) {
    case MenuStyleGrid:
        return "Grid";
    case MenuStyleMacintosh:
        return "Macintosh";
    case MenuStyleThreeD:
        return "3D";
    default:
        return "other";
    }
}

static const char* key_name(InputKey key) {
    switch(key) {
    case InputKeyUp:
        return "Up";
    case InputKeyDown:
        return "Down";
    case InputKeyLeft:
        return "Left";
    case InputKeyRight:
        return "Right";
    default:
        return "other";
    }
}

static size_t press(MenuStyle style, size_t count, size_t position, InputKey key) {
    return menu_ported_style_navigate(style, position, count, key);
}

// The position after the key, which must be the expected one
static void check(MenuStyle style, size_t count, size_t position, InputKey key, size_t expected) {
    size_t got = press(style, count, position, key);
    if(got != expected) {
        fprintf(
            stderr,
            "%s, %u items: %s from %u went to %u, expected %u\n",
            style_name(style),
            (unsigned)count,
            key_name(key),
            (unsigned)position,
            (unsigned)got,
            (unsigned)expected);
        abort();
    }
}

static const Step steps[] = {
"""

MAIN = r"""
};

int main(void) {
    for(size_t i = 0; i < COUNT_OF(steps); i++) {
        check(steps[i].style, steps[i].count, steps[i].position, steps[i].key, steps[i].expected);
    }

    // In menus of up to 64 items every key lands on an item, an empty menu keeps its
    // position, Left undoes Right and Up undoes Down: a row cycles its column
    static const MenuStyle styles[] = {MenuStyleGrid, MenuStyleMacintosh, MenuStyleThreeD};
    static const InputKey keys[] = {InputKeyUp, InputKeyDown, InputKeyLeft, InputKeyRight};
    for(size_t s = 0; s < COUNT_OF(styles); s++) {
        for(size_t count = 0; count <= 64; count++) {
            for(size_t position = 0; position < (count ? count : 1); position++) {
                for(size_t k = 0; k < COUNT_OF(keys); k++) {
                    size_t got = press(styles[s], count, position, keys[k]);
                    if(count == 0) {
                        check(styles[s], count, position, keys[k], position);
                    } else if(got >= count) {
                        fprintf(
                            stderr,
                            "%s, %u items: %s from %u went out of range to %u\n",
                            style_name(styles[s]),
                            (unsigned)count,
                            key_name(keys[k]),
                            (unsigned)position,
                            (unsigned)got);
                        abort();
                    }
                }
                if(count) {
                    size_t right = press(styles[s], count, position, InputKeyRight);
                    check(styles[s], count, right, InputKeyLeft, position);
                    size_t down = press(styles[s], count, position, InputKeyDown);
                    check(styles[s], count, down, InputKeyUp, position);
                }
            }
        }
    }

    // The helper leaves the other styles to their own handlers
    assert(press(MenuStyleDsi, 7, 3, InputKeyDown) == 3);
    assert(press(MenuStyleList, 7, 3, InputKeyRight) == 3);
    return 0;
}
"""


class MenuStyleNavigationTests(unittest.TestCase):
    def test_ported_styles_step_within_partial_pages_rows_and_columns(self):
        native_test(
            INCLUDES
            + "\n".join(source_between(*part) for part in DECLARATIONS)
            + HARNESS
            + "".join(c_step(*step) for step in STEPS)
            + MAIN
        )


class MenuStyleSettingsTests(unittest.TestCase):
    def test_enumeration_keeps_stored_numbers_and_appends_the_ported_styles(self):
        body = source_between(
            SETTINGS_H, "typedef enum {\n    MenuStyleList,", "} MenuStyle;"
        )
        # Values stay implicit, so the existing styles keep the numbers settings files hold
        self.assertNotIn("=", body)
        self.assertEqual(
            re.findall(r"^\s*(MenuStyle\w+),", body, re.M), STYLES + ["MenuStyleCount"]
        )

    def test_settings_screen_names_follow_the_enumeration(self):
        body = source_between(NAMES_C, "menu_style_names[MenuStyleCount] = {", "};")
        self.assertEqual(re.findall(r'"([^"]*)"', body), NAMES)

    def test_default_style_stays_dsi(self):
        settings = (ROOT / SETTINGS_C).read_text(encoding="utf-8")
        self.assertIn(".menu_style = MenuStyleDsi", settings)


if __name__ == "__main__":
    unittest.main()
