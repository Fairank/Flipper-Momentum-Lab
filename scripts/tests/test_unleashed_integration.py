"""Host regressions for the local Unleashed backports.

The C tests compile the production scan and loading-view functions unchanged,
with small storage/display substitutes. They need a host C compiler and fail,
rather than skip, without one. They do not replace a firmware build or tests
on a Flipper and its SD card.
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
    # A missing compiler fails the test rather than skipping it: nothing else
    # checks the C. MinGW and LLVM installs often have no "cc" alias.
    compiler = None
    for name in ("cc", "gcc", "clang"):
        compiler = shutil.which(name)
        if compiler:
            break
    if compiler is None:
        raise AssertionError("A host C compiler (cc, gcc or clang) is needed on PATH")
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


# Display and string substitutes for the loading view. FuriString copies like the
# real one and the multiline text element records what it is asked to draw, so
# text that followed the caller's buffer, or was drawn out of place, shows up.
LOADING_DISPLAY = r"""
#undef NDEBUG
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define furi_check assert
#define CLAMP(x, high, low) ((x) > (high) ? (high) : (x) < (low) ? (low) : (x))
typedef int IconAnimation;
static const int A_Loading_24 = 0;
typedef struct { char data[64]; size_t size; } FuriString;
static bool furi_string_empty(const FuriString* s) { return s->size == 0; }
static const char* furi_string_get_cstr(const FuriString* s) { return s->data; }
static bool furi_string_equal_str(const FuriString* s, const char other[]) {
    assert(other); return strcmp(s->data, other) == 0;
}
static void furi_string_set_str(FuriString* s, const char source[]) {
    assert(source); size_t size = strlen(source); assert(size < sizeof(s->data));
    memcpy(s->data, source, size + 1); s->size = size;
}
typedef enum { AlignLeft, AlignRight, AlignTop, AlignBottom, AlignCenter } Align;
typedef struct {
    int icon_count, icon_x, icon_y, bar_count, bar_x, bar_y; float progress; int font;
    int text_count, text_font, text_x, text_y; Align text_horizontal, text_vertical;
    const char* text_source; char text[64];
} Canvas;
enum { ColorWhite, ColorBlack };
typedef enum { FontPrimary, FontSecondary } Font;
static int canvas_width(Canvas* c) { (void)c; return 128; }
static int canvas_height(Canvas* c) { (void)c; return 64; }
static void canvas_set_color(Canvas* c, int color) { (void)c; (void)color; }
static void canvas_set_font(Canvas* c, Font font) { c->font = font; }
static void canvas_draw_box(Canvas* c, int x, int y, int w, int h) { (void)c; (void)x; (void)y; (void)w; (void)h; }
static void canvas_draw_icon(Canvas* c, int x, int y, const int* icon) { (void)x; (void)y; (void)icon; (void)c; }
static void canvas_draw_icon_animation(Canvas* c, int x, int y, IconAnimation* icon) {
    (void)icon; c->icon_count++; c->icon_x = x; c->icon_y = y;
}
static void elements_progress_bar(Canvas* c, int x, int y, int w, float p) {
    assert(x >= 0 && x + w <= 128 && y >= 0 && y + 9 <= 64);
    c->bar_count++; c->bar_x = x; c->bar_y = y; c->progress = p;
}
// The real element splits at "\n", wraps to the space around x and draws CJK;
// here the whole string is kept, so the view has to hand it over as given
static void elements_multiline_text_aligned(
    Canvas* c, int32_t x, int32_t y, Align horizontal, Align vertical, const char* text) {
    assert(text && x >= 0 && x <= 128 && y >= 0 && y <= 64);
    c->text_count++; c->text_font = c->font; c->text_x = x; c->text_y = y;
    c->text_horizontal = horizontal; c->text_vertical = vertical; c->text_source = text;
    snprintf(c->text, sizeof(c->text), "%s", text);
}
"""

# View, icon animation and FuriString lifetimes, to build all of loading.c. The
# model starts as junk, so alloc has to set what the view reads, and the model
# lock checks that every view_get_model() is followed by view_commit_model().
LOADING_VIEW = r"""
#define furi_assert assert
#define UNUSED(x) ((void)(x))
typedef struct { int type; } InputEvent;
typedef void (*ViewDrawCallback)(Canvas* canvas, void* model);
typedef bool (*ViewInputCallback)(InputEvent* event, void* context);
typedef void (*ViewCallback)(void* context);
typedef enum { ViewModelTypeLocking } ViewModelType;
typedef struct {
    void* model; bool locked; int redraws; void* context; IconAnimation* tied;
    ViewDrawCallback draw; ViewInputCallback input; ViewCallback enter, leave;
} View;
static int views, models, icons, strings;
static bool animating;
static View* view_alloc(void) { views++; return calloc(1, sizeof(View)); }
static void view_allocate_model(View* v, ViewModelType type, size_t size) {
    assert(type == ViewModelTypeLocking && !v->model);
    v->model = malloc(size); assert(v->model); memset(v->model, 0xA5, size); models++;
}
static void* view_get_model(View* v) { assert(!v->locked); v->locked = true; return v->model; }
static void view_commit_model(View* v, bool update) {
    assert(v->locked); v->locked = false; v->redraws += update;
}
static void view_free(View* v) { assert(!v->locked); free(v->model); models--; free(v); views--; }
static void view_tie_icon_animation(View* v, IconAnimation* icon) { v->tied = icon; }
static void view_set_context(View* v, void* context) { v->context = context; }
static void view_set_draw_callback(View* v, ViewDrawCallback callback) { v->draw = callback; }
static void view_set_input_callback(View* v, ViewInputCallback callback) { v->input = callback; }
static void view_set_enter_callback(View* v, ViewCallback callback) { v->enter = callback; }
static void view_set_exit_callback(View* v, ViewCallback callback) { v->leave = callback; }
static IconAnimation* icon_animation_alloc(const int* icon) {
    (void)icon; icons++; return calloc(1, sizeof(IconAnimation));
}
static void icon_animation_free(IconAnimation* icon) { free(icon); icons--; }
static void icon_animation_start(IconAnimation* icon) { (void)icon; animating = true; }
static void icon_animation_stop(IconAnimation* icon) { (void)icon; animating = false; }
static FuriString* furi_string_alloc(void) { strings++; return calloc(1, sizeof(FuriString)); }
static void furi_string_free(FuriString* s) { free(s); strings--; }
"""


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
        # From loading_set_progress to the end, so loading_set_text is built too
        setters = source_between(path, "void loading_set_progress(")
        native_test(
            LOADING_DISPLAY
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
    FuriString text = {0}; view.model.text = &text;
    loading_draw_callback(&canvas, &view.model);
    assert(canvas.icon_count == 1 && canvas.bar_count == 0 && canvas.icon_y == 20);
    assert(canvas.icon_x == 52 && canvas.text_count == 0);
    loading_set_progress(&loading, -0.5f);
    assert(view.model.progress_shown && view.model.progress == 0.0f && view.redraws == 1);
    loading_set_progress(&loading, 0.0f);
    assert(view.redraws == 1);
    loading_set_progress(&loading, 0.5f);
    canvas = (Canvas){0}; loading_draw_callback(&canvas, &view.model);
    assert(canvas.icon_count == 1 && canvas.bar_count == 1 && canvas.progress == 0.5f);
    assert(canvas.bar_y >= canvas.icon_y + 24);
    // Without text the block sits exactly where it did before text existed
    assert(canvas.icon_y == 14 && canvas.bar_x == 32 && canvas.bar_y == 42 && canvas.text_count == 0);
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

    def test_loading_text_is_owned_cleared_and_stacked_with_progress(self):
        path = "applications/services/gui/modules/loading.c"
        # The header's prototypes come first, so a definition that disagrees fails
        header = source_between(
            "applications/services/gui/modules/loading.h",
            "/** Loading anonymous structure */",
            "\n#ifdef __cplusplus\n}",
        )
        with_view_model = source_between(
            "applications/services/gui/view.h",
            "#define with_view_model(view, type, code, update)",
            "\n#endif",
        )
        # All of loading.c after its includes: model, layout, callbacks, lifecycle
        production = source_between(path, "struct Loading {")
        native_test(
            LOADING_DISPLAY
            + LOADING_VIEW
            + with_view_model
            + "\n"
            + header
            + production
            + r"""
// Upstream layout with text: the 24 px animation at x 12, the text centered in
// the space to its right (two FontPrimary lines, 10 px above and below its
// middle), and the 64 x 9 bar 4 px under the text
enum { SCREEN_WIDTH = 128, SCREEN_HEIGHT = 64, ICON_SIZE = 24, TEXT_ICON_X = 12,
       TEXT_HALF_HEIGHT = 10, BAR_WIDTH = 64, BAR_HEIGHT = 9, BAR_GAP = 4 };

static Canvas draw(Loading* loading) {
    View* view = loading_get_view(loading);
    Canvas canvas = {0};
    view->draw(&canvas, view->model);
    return canvas;
}

static bool same_layout(const Canvas* a, const Canvas* b) {
    return a->icon_count == b->icon_count && a->icon_x == b->icon_x && a->icon_y == b->icon_y &&
           a->bar_count == b->bar_count && a->bar_x == b->bar_x && a->bar_y == b->bar_y &&
           a->progress == b->progress && a->text_count == b->text_count &&
           a->text_x == b->text_x && a->text_y == b->text_y && a->text_font == b->text_font &&
           a->text_horizontal == b->text_horizontal && a->text_vertical == b->text_vertical &&
           strcmp(a->text, b->text) == 0;
}

// Animation on the left and `text`, whole and bold, centered in the space to its
// right; with the bar, text and bar stack there as one block as far from the top
// as from the bottom
static void check_text(const Canvas* c, const char* text) {
    assert(c->icon_count == 1 && c->icon_x == TEXT_ICON_X);
    assert(c->icon_y == (SCREEN_HEIGHT - ICON_SIZE) / 2);
    assert(c->text_count == 1 && strcmp(c->text, text) == 0);
    assert(c->text_font == FontPrimary);
    assert(c->text_horizontal == AlignCenter && c->text_vertical == AlignCenter);
    assert(c->text_x == (TEXT_ICON_X + ICON_SIZE + SCREEN_WIDTH) / 2);
    int top = c->text_y - TEXT_HALF_HEIGHT, bottom;
    if(c->bar_count) {
        assert(c->bar_count == 1 && c->bar_x + BAR_WIDTH / 2 == c->text_x);
        assert(c->bar_y >= c->text_y + TEXT_HALF_HEIGHT + BAR_GAP);
        bottom = SCREEN_HEIGHT - (c->bar_y + BAR_HEIGHT);
    } else {
        assert(c->text_y == SCREEN_HEIGHT / 2);
        bottom = SCREEN_HEIGHT - (c->text_y + TEXT_HALF_HEIGHT);
    }
    assert(top >= 0 && bottom >= 0 && top - bottom <= 1 && bottom - top <= 1);
}

int main(void) {
    Loading* loading = loading_alloc();
    View* view = loading_get_view(loading);
    LoadingModel* model = view->model;
    assert(views == 1 && models == 1 && icons == 1 && strings == 1 && !view->locked);
    assert(view->context == loading && view->tied == model->icon);
    assert(furi_string_empty(model->text) && !model->progress_shown && model->progress == 0.0f);

    // Without text the animation and bar are where they were before text existed
    const Canvas plain = draw(loading);
    assert(plain.icon_x == 52 && plain.icon_y == 20 && plain.bar_count == 0);
    assert(plain.text_count == 0);
    loading_set_progress(loading, 0.5f);
    const Canvas plain_bar = draw(loading);
    assert(plain_bar.icon_y == 14 && plain_bar.bar_count == 1 && plain_bar.bar_x == 32);
    assert(plain_bar.bar_y == 42 && plain_bar.text_count == 0);
    loading_reset_progress(loading);

    // The view keeps its own copy, so the caller's buffer can change right away
    char text[] = "Unpacking";
    int redraws = view->redraws;
    loading_set_text(loading, text);
    assert(view->redraws == redraws + 1 && !view->locked);
    strcpy(text, "Replaced");
    assert(furi_string_equal_str(model->text, "Unpacking"));
    const Canvas labelled = draw(loading);
    check_text(&labelled, "Unpacking");
    assert(labelled.text_source == furi_string_get_cstr(model->text));
    // Animation at x 12, text centered at x 82 on the screen's middle row
    assert(labelled.icon_x == 12 && labelled.icon_y == 20 && labelled.bar_count == 0);
    assert(labelled.text_x == 82 && labelled.text_y == 32);

    // The same text again, from another buffer, does not redraw; new text does
    char same[] = "Unpacking";
    redraws = view->redraws;
    loading_set_text(loading, same);
    assert(view->redraws == redraws);
    loading_set_text(loading, "Starting");
    assert(view->redraws == redraws + 1 && furi_string_equal_str(model->text, "Starting"));

    // Two lines, as NFC names cards, reach the element whole for it to lay out
    loading_set_text(loading, "Reading\nMIFARE Classic");
    const Canvas two_lines = draw(loading);
    check_text(&two_lines, "Reading\nMIFARE Classic");
    assert(two_lines.text_x == labelled.text_x && two_lines.text_y == labelled.text_y);
    loading_set_text(loading, "Unpacking");

    // Progress goes under the text, centered with it right of the animation,
    // which stays put; resetting the progress keeps the text
    loading_set_progress(loading, 0.25f);
    const Canvas both = draw(loading);
    check_text(&both, "Unpacking");
    assert(both.bar_count == 1 && both.progress == 0.25f);
    assert(both.icon_x == 12 && both.icon_y == 20 && both.text_x == 82);
    assert(both.text_y == 26 && both.bar_x == 50 && both.bar_y == 40);
    loading_reset_progress(loading);
    assert(!model->progress_shown && furi_string_equal_str(model->text, "Unpacking"));
    const Canvas relabelled = draw(loading);
    assert(same_layout(&relabelled, &labelled));

    // NULL clears the text like "": one redraw, then the layout without text
    redraws = view->redraws;
    loading_set_text(loading, NULL);
    assert(view->redraws == redraws + 1 && furi_string_empty(model->text));
    const Canvas cleared = draw(loading);
    assert(same_layout(&cleared, &plain));
    loading_set_text(loading, NULL);
    loading_set_text(loading, "");
    assert(view->redraws == redraws + 1);

    // Clearing the text while progress shows leaves the progress as it was
    loading_set_progress(loading, 0.5f);
    loading_set_text(loading, "Unpacking");
    loading_set_text(loading, "");
    assert(model->progress_shown && model->progress == 0.5f && furi_string_empty(model->text));
    const Canvas bar_again = draw(loading);
    assert(same_layout(&bar_again, &plain_bar));

    // Entering and leaving the view keep the text; freeing releases it
    loading_set_text(loading, "Unpacking");
    view->enter(view->context);
    assert(animating && view->tied == model->icon && !view->locked);
    view->leave(view->context);
    assert(!animating && !view->locked && furi_string_equal_str(model->text, "Unpacking"));
    loading_free(loading);
    assert(views == 0 && models == 0 && icons == 0 && strings == 0);
    return 0;
}
"""
        )


if __name__ == "__main__":
    if "--gather" in sys.argv:
        print(json.dumps(gather_result()))
    else:
        unittest.main()
