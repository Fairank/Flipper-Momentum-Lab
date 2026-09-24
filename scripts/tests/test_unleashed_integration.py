"""Host regressions for the local Unleashed backports.

The C tests compile the production scan and loading-view functions unchanged,
with small storage/display substitutes. They do not replace a firmware build
or tests on a Flipper and its SD card.
"""

import ast
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def source_between(path, start, end=None):
    text = (ROOT / path).read_text()
    begin = text.index(start)
    return text[begin : text.index(end, begin) if end else len(text)]


def native_test(source):
    compiler = shutil.which("cc")
    if compiler is None:
        raise unittest.SkipTest("A host C compiler is required")
    with tempfile.TemporaryDirectory() as folder:
        src = Path(folder) / "regression.c"
        exe = Path(folder) / "regression"
        src.write_text(source)
        try:
            subprocess.run(
                [
                    compiler,
                    "-std=c11",
                    "-Wall",
                    "-Wextra",
                    "-Werror",
                    str(src),
                    "-o",
                    str(exe),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            subprocess.run([str(exe)], check=True, capture_output=True, text=True)
        except subprocess.CalledProcessError as error:
            raise AssertionError(
                f"Native regression failed:\n{error.stdout}\n{error.stderr}"
            ) from error


def gather_result():
    tree = ast.parse((ROOT / "scripts/fbt_tools/sconsrecursiveglob.py").read_text())
    function = next(
        n
        for n in tree.body
        if isinstance(n, ast.FunctionDef) and n.name == "GatherSources"
    )

    def flatten(items):
        return [
            leaf
            for item in items
            for leaf in (flatten(item) if isinstance(item, list) else [item])
        ]

    class Environment:
        def GlobRecursive(self, pattern, node, exclude):
            return [(pattern, node, exclude)]

    namespace = {"Flatten": flatten, "itertools": __import__("itertools")}
    exec(
        compile(ast.Module(body=[function], type_ignores=[]), "GatherSources", "exec"),
        namespace,
    )
    return namespace["GatherSources"](
        Environment(), ["*.c", ["*.cpp", "!lib", "*.c"], "generated.c", "!lib"], "app"
    )


class IntegrationTests(unittest.TestCase):
    def test_source_order_is_independent_of_hash_seed(self):
        expected = [[p, "app", ["lib"]] for p in ("*.c", "*.cpp", "generated.c")]
        for seed in ("0", "1", "7", "42", "random"):
            result = subprocess.check_output(
                [sys.executable, str(Path(__file__).resolve()), "--gather"],
                env={**os.environ, "PYTHONHASHSEED": seed},
                text=True,
            )
            self.assertEqual(json.loads(result), expected, seed)

    def test_plugin_scan_keeps_later_plugins_and_reports_errors(self):
        production = source_between(
            "lib/flipper_application/plugins/plugin_manager.c",
            "PluginManagerError plugin_manager_load_all_prefixed(",
            "\nuint32_t plugin_manager_get_count(",
        )
        native_test(
            r"""
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define furi_check assert
#define FURI_LOG_E(...) ((void)0)
#define FURI_LOG_D(...) ((void)0)
#define FSE_NOT_EXIST 1
typedef enum { PluginManagerErrorNone, PluginManagerErrorLoaderError,
    PluginManagerErrorApplicationIdMismatch, PluginManagerErrorAPIVersionMismatch } PluginManagerError;
typedef struct { void* storage; int attempts; int loaded; } PluginManager;
typedef struct { int index; int error; } File;
typedef struct { char value[512]; } FuriString;
static const char* entries[10];
static bool can_open;
static int fail_at, handles;
static File* storage_file_alloc(void* storage) {
    (void)storage; handles++; return calloc(1, sizeof(File));
}
static bool storage_dir_open(File* f, const char* path) { (void)f; (void)path; return can_open; }
static bool storage_dir_read(File* f, void* info, char* name, size_t size) {
    (void)info;
    if(f->index == fail_at) { f->error = 2; return false; }
    if(!entries[f->index]) { f->error = FSE_NOT_EXIST; return false; }
    snprintf(name, size, "%s", entries[f->index++]); return true;
}
static int storage_file_get_error(File* f) { return f->error; }
static void storage_dir_close(File* f) { (void)f; }
static void storage_file_free(File* f) { handles--; free(f); }
static FuriString* furi_string_alloc(void) { handles++; return calloc(1, sizeof(FuriString)); }
static void furi_string_free(FuriString* s) { handles--; free(s); }
static void furi_string_set(FuriString* s, const char* v) { snprintf(s->value, sizeof(s->value), "%s", v); }
static const char* furi_string_get_cstr(FuriString* s) { return s->value; }
static bool furi_string_end_with_str(FuriString* s, const char* suffix) {
    size_t a = strlen(s->value), b = strlen(suffix);
    return a >= b && strcmp(s->value + a - b, suffix) == 0;
}
static bool furi_string_start_with_str(FuriString* s, const char* prefix) {
    return strncmp(s->value, prefix, strlen(prefix)) == 0;
}
static void path_concat(const char* base, const char* name, FuriString* out) {
    snprintf(out->value, sizeof(out->value), "%s/%s", base, name);
}
static PluginManagerError plugin_manager_load_file(PluginManager* m, const char* path, bool scanning) {
    assert(scanning); m->attempts++;
    if(strstr(path, "foreign")) return PluginManagerErrorApplicationIdMismatch;
    if(strstr(path, "old")) return PluginManagerErrorAPIVersionMismatch;
    if(strstr(path, "bad")) return PluginManagerErrorLoaderError;
    m->loaded++; return PluginManagerErrorNone;
}
"""
            + production
            + r"""
int main(void) {
    can_open = true; fail_at = -1;
    entries[0] = "radio_device_first.fal";
    entries[1] = "radio_device_bad.fal";
    entries[2] = "radio_device_last.fal";
    entries[3] = "unrelated.fal";
    entries[4] = "radio_device_notes.txt";
    entries[5] = "Radio_device_other.fal";
    PluginManager m = {0};
    assert(plugin_manager_load_all_prefixed(&m, "/plugins", "radio_device_") == PluginManagerErrorLoaderError);
    assert(m.attempts == 3 && m.loaded == 2 && handles == 0);

    memset(entries, 0, sizeof(entries)); m = (PluginManager){0};
    entries[0] = "foreign.fal"; entries[1] = "good.fal";
    assert(plugin_manager_load_all(&m, "/plugins") == PluginManagerErrorNone);
    assert(m.attempts == 2 && m.loaded == 1 && handles == 0);

    m = (PluginManager){0}; entries[0] = "old.fal"; entries[1] = "bad.fal"; entries[2] = "good.fal";
    assert(plugin_manager_load_all(&m, "/plugins") == PluginManagerErrorAPIVersionMismatch);
    assert(m.attempts == 3 && m.loaded == 1 && handles == 0);

    m = (PluginManager){0}; entries[0] = "good.fal"; fail_at = 1;
    assert(plugin_manager_load_all(&m, "/plugins") == PluginManagerErrorLoaderError);
    assert(m.loaded == 1 && handles == 0);

    m = (PluginManager){0}; can_open = false;
    assert(plugin_manager_load_all(&m, "/missing") == PluginManagerErrorNone);
    assert(m.attempts == 0 && handles == 0);
    return 0;
}
"""
        )

    def test_loading_progress_clamps_resets_and_keeps_spinner(self):
        path = "applications/services/gui/modules/loading.c"
        model_and_draw = source_between(
            path, "typedef struct {", "\nstatic bool loading_input_callback("
        )
        setters = source_between(path, "void loading_set_progress(")
        native_test(
            r"""
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#define furi_check assert
#define CLAMP(x, high, low) ((x) > (high) ? (high) : (x) < (low) ? (low) : (x))
typedef int IconAnimation;
static const int A_Loading_24 = 0;
typedef struct { int bar_count; int icon_count; int bar_y; int icon_y; float progress; } Canvas;
enum { ColorWhite, ColorBlack };
static int canvas_width(Canvas* c) { (void)c; return 128; }
static int canvas_height(Canvas* c) { (void)c; return 64; }
static void canvas_set_color(Canvas* c, int color) { (void)c; (void)color; }
static void canvas_draw_box(Canvas* c, int x, int y, int w, int h) { (void)c; (void)x; (void)y; (void)w; (void)h; }
static void canvas_draw_icon(Canvas* c, int x, int y, const int* icon) { (void)x; (void)y; (void)icon; (void)c; }
static void canvas_draw_icon_animation(Canvas* c, int x, int y, IconAnimation* icon) {
    (void)x; (void)icon; c->icon_count++; c->icon_y = y;
}
static void elements_progress_bar(Canvas* c, int x, int y, int w, float p) {
    assert(x >= 0 && x + w <= 128 && y >= 0 && y + 9 <= 64);
    c->bar_count++; c->bar_y = y; c->progress = p;
}
"""
            + model_and_draw
            + r"""
typedef struct { LoadingModel model; int redraws; } View;
typedef struct { View* view; } Loading;
#define with_view_model(view, declaration, body, update) do { declaration = &(view)->model; body; (view)->redraws += !!(update); } while(0)
"""
            + setters
            + r"""
int main(void) {
    View view = {0}; Loading loading = {&view}; Canvas canvas = {0};
    loading_draw_callback(&canvas, &view.model);
    assert(canvas.icon_count == 1 && canvas.bar_count == 0 && canvas.icon_y == 20);
    loading_set_progress(&loading, -0.5f);
    assert(view.model.progress_shown && view.model.progress == 0.0f && view.redraws == 1);
    loading_set_progress(&loading, 0.0f);
    assert(view.redraws == 1);
    loading_set_progress(&loading, 0.5f);
    canvas = (Canvas){0}; loading_draw_callback(&canvas, &view.model);
    assert(canvas.icon_count == 1 && canvas.bar_count == 1 && canvas.progress == 0.5f);
    assert(canvas.bar_y >= canvas.icon_y + 24);
    loading_set_progress(&loading, 2.0f);
    assert(view.model.progress == 1.0f);
    loading_reset_progress(&loading);
    assert(!view.model.progress_shown && view.model.progress == 0.0f);
    int redraws = view.redraws; loading_reset_progress(&loading);
    assert(view.redraws == redraws);
    canvas = (Canvas){0}; loading_draw_callback(&canvas, &view.model);
    assert(canvas.icon_count == 1 && canvas.bar_count == 0 && canvas.icon_y == 20);
    return 0;
}
"""
        )


if __name__ == "__main__":
    if "--gather" in sys.argv:
        print(json.dumps(gather_result()))
    else:
        unittest.main()
