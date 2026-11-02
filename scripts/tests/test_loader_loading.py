"""Host regression for the loader's loading-indicator lifecycle.

The C test compiles the production helpers from loader_is_application_running
up to loader_do_start_by_name unchanged, with a stub Loader and small
substitutes for the GUI layer counts, the view holder, the tick clock, the
hold timer and the log. It needs a host C compiler and fails, rather than
skips, without one. It does not build the loader service or start threads.
"""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_unleashed_integration import ROOT, native_test  # noqa: E402

LOADER = ROOT / "applications/services/loader/loader.c"


def loader_source(start, end):
    # Explicit UTF-8: loader.c carries Chinese dialog text outside this range
    text = LOADER.read_text(encoding="utf-8")
    begin = text.index(start)
    return text[begin : text.index(end, begin)]


# The Loader keeps the fields the helpers touch with the firmware's types, so
# the depth is a byte and the hold start wraps with the tick counter. The view
# holder records what is up, the timer can refuse to start, and it checks that
# a hold never restarts a running timer.
STUBS = r"""
#undef NDEBUG
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#define TAG "Loader"
#define furi_check assert
#define FURI_LOG_E(tag, ...) (errors++)
#define FURI_LOG_W(tag, ...) (warnings++)
typedef struct { int id; } FuriThread;
typedef struct { int id; } View;
typedef struct { int id; } Loading;
typedef struct { int id; } FuriTimer;
typedef enum { FuriStatusOk = 0, FuriStatusError = -1 } FuriStatus;
typedef enum { GuiLayerDesktop, GuiLayerWindow, GuiLayerStatusBarLeft, GuiLayerStatusBarRight,
    GuiLayerFullscreen, GuiLayerMAX } GuiLayer;
typedef struct { size_t counts[GuiLayerMAX]; } Gui;
typedef struct { View* visible; int shows, hides, fronts; } ViewHolder;
typedef struct { FuriThread* thread; bool rpc; } LoaderAppData;
typedef struct {
    LoaderAppData app; Gui* gui; ViewHolder* view_holder; Loading* loading; FuriTimer* loading_timer;
    uint8_t loading_depth; uint32_t loading_hold_start; size_t loading_view_ports_baseline;
    bool loading_held;
} Loader;
static Gui gui; static ViewHolder holder; static Loading loading; static View loading_view;
static FuriTimer hold_timer; static FuriThread real_thread; static Loader ldr;
static struct { uint32_t period; int starts, stops; bool running, fail; } hold;
static uint32_t now; static int errors, warnings;
static uint32_t furi_get_tick(void) { return now; }
static uint32_t furi_ms_to_ticks(uint32_t ms) { return ms; }
static size_t gui_active_view_port_count(Gui* g, GuiLayer layer) { return g->counts[layer]; }
static View* loading_get_view(Loading* l) { assert(l == &loading); return &loading_view; }
static void view_holder_send_to_front(ViewHolder* h) { h->fronts++; }
static void view_holder_set_view(ViewHolder* h, View* view) {
    h->visible = view; if(view) h->shows++; else h->hides++;
}
static FuriStatus furi_timer_start(FuriTimer* t, uint32_t period) {
    assert(t == &hold_timer && !hold.running); hold.starts++; hold.period = period;
    if(hold.fail) return FuriStatusError;
    hold.running = true; return FuriStatusOk;
}
static void furi_timer_stop(FuriTimer* t) { assert(t == &hold_timer); hold.stops++; hold.running = false; }
"""

# Each scenario starts from a fresh loader. expect() checks the depth, the hold
# flag, the view that is up and the timer calls, and that a hold is never
# anything but a ticking timer.
MAIN = r"""
static void reset(void) {
    memset(&gui, 0, sizeof(gui)); memset(&holder, 0, sizeof(holder)); memset(&hold, 0, sizeof(hold));
    memset(&ldr, 0, sizeof(ldr)); errors = warnings = 0; now = 0;
    ldr.gui = &gui; ldr.view_holder = &holder; ldr.loading = &loading; ldr.loading_timer = &hold_timer;
}
static void expect(int depth, bool held, View* visible, int starts, int stops) {
    assert(ldr.loading_depth == depth && ldr.loading_held == held && holder.visible == visible);
    assert(hold.starts == starts && hold.stops == stops && hold.running == held);
}
// Running means a real thread, not the lock's magic value; only the layers an app draws on are
// counted; RPC is exactly the "RPC " prefix
static void predicates(void) {
    reset(); assert(!loader_is_application_running(&ldr));
    ldr.app.thread = (FuriThread*)LOADER_MAGIC_THREAD_VALUE; assert(!loader_is_application_running(&ldr));
    ldr.app.thread = &real_thread; assert(loader_is_application_running(&ldr));
    gui.counts[GuiLayerDesktop] = 1; gui.counts[GuiLayerWindow] = 2; gui.counts[GuiLayerFullscreen] = 4;
    gui.counts[GuiLayerStatusBarLeft] = 8; gui.counts[GuiLayerStatusBarRight] = 16;
    assert(loader_do_count_view_ports(&ldr) == 7);
    assert(loader_do_args_are_rpc("RPC ") && loader_do_args_are_rpc("RPC 1 2"));
    assert(!loader_do_args_are_rpc(NULL) && !loader_do_args_are_rpc("") && !loader_do_args_are_rpc("RPC"));
    assert(!loader_do_args_are_rpc("rpc 1") && !loader_do_args_are_rpc(" RPC 1") && !loader_do_args_are_rpc("XRPC "));
}
// A deferred launch brackets the chain and each start nests inside: the view goes up and to the front
// once at depth 1, the baseline is resampled on every show, inner hides and stray checks do nothing,
// and the outer hide takes the view down when no app runs
static void nested_brackets(void) {
    reset(); gui.counts[GuiLayerWindow] = 1; loader_do_show_loading(&ldr);
    expect(1, false, &loading_view, 0, 0); assert(holder.fronts == 1 && holder.shows == 1);
    assert(ldr.loading_view_ports_baseline == 1);
    gui.counts[GuiLayerWindow] = 2; loader_do_show_loading(&ldr);
    expect(2, false, &loading_view, 0, 0); assert(holder.fronts == 1 && holder.shows == 1);
    assert(ldr.loading_view_ports_baseline == 2);
    loader_do_hide_loading(&ldr); expect(1, false, &loading_view, 0, 0);
    loader_do_check_loading(&ldr); expect(1, false, &loading_view, 0, 0);
    loader_do_hide_loading(&ldr); expect(0, false, NULL, 0, 0);
    assert(holder.hides == 1 && errors == 0 && warnings == 0);
}
// With an app started inside the chain the hold begins when the outer bracket closes, timed from then
static void nested_hold(void) {
    reset(); now = 50; loader_do_show_loading(&ldr); loader_do_show_loading(&ldr);
    ldr.app.thread = &real_thread; loader_do_hide_loading(&ldr); expect(1, false, &loading_view, 0, 0);
    now = 60; loader_do_hide_loading(&ldr); expect(0, true, &loading_view, 1, 0);
    assert(ldr.loading_hold_start == 60 && holder.hides == 0 && holder.shows == 1);
}
// A local app gets a timed hold: status bar icons and a tick short of the cap keep it, the app's
// first view port drops it, and a late tick or drop after that changes nothing
static void local_hold(void) {
    reset(); now = 1000; gui.counts[GuiLayerDesktop] = 1; loader_do_show_loading(&ldr);
    ldr.app.thread = &real_thread; loader_do_hide_loading(&ldr);
    expect(0, true, &loading_view, 1, 0); assert(holder.hides == 0);
    assert(hold.period == furi_ms_to_ticks(LOADER_LOADING_HOLD_PERIOD_MS) && ldr.loading_hold_start == 1000);
    now += LOADER_LOADING_HOLD_MAX_MS - 1; gui.counts[GuiLayerStatusBarRight] = 1;
    loader_do_check_loading(&ldr); expect(0, true, &loading_view, 1, 0);
    gui.counts[GuiLayerWindow] = 1; loader_do_check_loading(&ldr);
    expect(0, false, NULL, 1, 1); assert(holder.hides == 1 && warnings == 0);
    gui.counts[GuiLayerWindow] = 2; now += LOADER_LOADING_HOLD_MAX_MS;
    loader_do_check_loading(&ldr); loader_do_drop_loading(&ldr);
    expect(0, false, NULL, 1, 1); assert(holder.hides == 1 && warnings == 0);
}
// If the hold timer will not start there is no hold: the view comes down at once, the error is
// logged, and the stray check that follows changes nothing
static void timer_failure(void) {
    reset(); hold.fail = true; loader_do_show_loading(&ldr); ldr.app.thread = &real_thread;
    loader_do_hide_loading(&ldr); expect(0, false, NULL, 1, 0); assert(errors == 1 && holder.hides == 1);
    loader_do_check_loading(&ldr); expect(0, false, NULL, 1, 0); assert(holder.hides == 1);
}
// An app started for a remote session may wait for the phone without drawing, so no hold
static void rpc_start(void) {
    reset(); ldr.app.rpc = loader_do_args_are_rpc("RPC 7"); loader_do_show_loading(&ldr);
    ldr.app.thread = &real_thread; loader_do_hide_loading(&ldr);
    expect(0, false, NULL, 0, 0); assert(holder.hides == 1 && errors == 0);
}
// The cap is elapsed time from the hold start, inclusive, and it survives the tick counter wrapping
static void timeout_and_wrap(void) {
    reset(); now = 7; loader_do_show_loading(&ldr); ldr.app.thread = &real_thread; loader_do_hide_loading(&ldr);
    now += LOADER_LOADING_HOLD_MAX_MS; loader_do_check_loading(&ldr);
    expect(0, false, NULL, 1, 1); assert(warnings == 1 && holder.hides == 1);
    reset(); now = UINT32_MAX - 10; loader_do_show_loading(&ldr); ldr.app.thread = &real_thread;
    loader_do_hide_loading(&ldr); assert(ldr.loading_hold_start == UINT32_MAX - 10);
    now = LOADER_LOADING_HOLD_MAX_MS - 12; loader_do_check_loading(&ldr);
    expect(0, true, &loading_view, 1, 0); assert(warnings == 0);
    now++; loader_do_check_loading(&ldr);
    expect(0, false, NULL, 1, 1); assert(warnings == 1 && holder.hides == 1);
}
// A live hold is dropped before a new bracket, which then puts the view back up and re-fronts it;
// a drop while a bracket is open stops the timer but leaves the view to the bracket
static void drop_before_launch(void) {
    reset(); loader_do_show_loading(&ldr); ldr.app.thread = &real_thread; loader_do_hide_loading(&ldr);
    expect(0, true, &loading_view, 1, 0);
    gui.counts[GuiLayerFullscreen] = 3; loader_do_show_loading(&ldr);
    expect(1, false, &loading_view, 1, 1); assert(ldr.loading_view_ports_baseline == 3);
    assert(holder.hides == 1 && holder.shows == 2 && holder.fronts == 2);
    ldr.loading_held = true; loader_do_drop_loading(&ldr);
    expect(1, false, &loading_view, 1, 2); assert(holder.hides == 1);
}
int main(void) {
    predicates(); nested_brackets(); nested_hold(); local_hold(); timer_failure(); rpc_start();
    timeout_and_wrap(); drop_before_launch();
    return 0;
}
"""


class LoaderLoadingTests(unittest.TestCase):
    def test_loading_hold_lifecycle(self):
        constants = loader_source("#define LOADER_MAGIC_THREAD_VALUE", "\n\n// helpers")
        # From loader_is_application_running up to the start-by-name entry point:
        # the view port count, drop, show, RPC check, hide and the timer check
        production = loader_source(
            "static bool loader_is_application_running(",
            "\nstatic LoaderMessageLoaderStatusResult loader_do_start_by_name(",
        )
        native_test(STUBS + constants + "\n" + production + MAIN)


if __name__ == "__main__":
    unittest.main()
