"""Host regression for deferred launches that open the Apps browser.

Compile the production empty-event/next/deferred helpers and the browser's
actual event callback unchanged. Controlled launch outcomes replace the app
loader, while the fixture records queue ownership, temporary strings and
loading brackets. No threads or sleeps are involved. This checks event
ordering and ownership, not the file browser or physical GUI rendering.
"""

from pathlib import Path
import re
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_unleashed_integration import ROOT, native_test  # noqa: E402


def extract_deferred(text):
    start = text.index("static void loader_do_emit_queue_empty_event(")
    return text[start : text.index("\nstatic void loader_do_app_closed(", start)]


def production_source():
    return extract_deferred(
        (ROOT / "applications/services/loader/loader.c").read_text(encoding="utf-8")
    )


def browser_callback():
    text = (ROOT / "applications/services/loader/loader_applications.c").read_text(
        encoding="utf-8"
    )
    start = text.index("#define APPLICATION_STOP_EVENT")
    return text[
        start : text.index("\nstatic void\n    loader_applications_start_app(", start)
    ]


def production_enums():
    result = []
    for path, name in (
        ("applications/services/loader/loader.h", "LoaderStatus"),
        ("applications/services/loader/loader.h", "LoaderEventType"),
        ("applications/services/loader/loader.h", "LoaderDeferredLaunchFlag"),
        ("applications/services/loader/loader_i.h", "LoaderStatusError"),
    ):
        text = (ROOT / path).read_text(encoding="utf-8")
        match = re.search(r"typedef enum[^{}]*\{[^{}]*\}\s*" + name + r"\s*;", text)
        if match is None:
            raise AssertionError(f"Missing production enum {name}")
        result.append(match.group(0))
    return "\n".join(result)


PREAMBLE = r"""
#undef NDEBUG
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#define TAG "Loader"
#define furi_assert assert
"""

STUBS = r"""
typedef struct { char text[64]; } FuriString;
typedef struct { int id; } FuriThread;
typedef void* FuriThreadId;
typedef struct { int id; } FuriPubSub;
typedef struct { LoaderEventType type; } LoaderEvent;
typedef struct { LoaderStatus value; LoaderStatusError error; } LoaderMessageLoaderStatusResult;
typedef struct { char* name_or_path; char* args; LoaderDeferredLaunchFlag flags; } LoaderDeferredLaunchRecord;
typedef struct { size_t cursor, item_cnt; } LoaderLaunchQueue;
typedef struct {
    struct { FuriThread* thread; } app;
    LoaderLaunchQueue launch_queue;
    FuriPubSub* pubsub;
} Loader;
typedef struct { bool waiting; unsigned wakes; } Browser;
typedef struct {
    char* name;
    char args[16];
    LoaderStatus status;
    bool creates_thread, cleared;
    LoaderDeferredLaunchFlag flags;
} PlannedLaunch;

static Loader loader;
static FuriThread app_thread;
static FuriPubSub pubsub;
static Browser browser;
static struct {
    PlannedLaunch plan[4];
    size_t count, started;
    unsigned pops, clears, strings_live, strings_allocated, strings_freed;
    unsigned depth, max_depth, shows, hides, empty_events, empty_depth, empty_strings;
    unsigned gui_errors;
    const char* gui_error_name;
    LoaderStatus gui_error_status;
} fixture;

static uint32_t furi_thread_flags_set(FuriThreadId thread_id, uint32_t flags) {
    /* The original waiting browser owns this signal, never the launched app. */
    assert(thread_id == &browser && flags == 1 && browser.waiting);
    browser.waiting = false; browser.wakes++; return flags;
}
"""

DEPENDENCIES = r"""
static void host_log(const char* tag, const char* format, ...) { (void)tag; (void)format; }
#define FURI_LOG_I host_log
static bool loader_do_is_locked(Loader* l) { return l->app.thread != NULL; }
static void furi_pubsub_publish(FuriPubSub* p, const LoaderEvent* event) {
    assert(p == &pubsub && event->type == LoaderEventTypeNoMoreAppsInQueue);
    assert(loader.app.thread == NULL && loader.launch_queue.item_cnt == 0);
    fixture.empty_events++; fixture.empty_depth = fixture.depth; fixture.empty_strings = fixture.strings_live;
    loader_pubsub_callback(event, &browser);
}
static FuriString* furi_string_alloc(void) {
    FuriString* s = calloc(1, sizeof(*s)); assert(s);
    fixture.strings_live++; fixture.strings_allocated++; return s;
}
static void furi_string_free(FuriString* s) {
    assert(s && fixture.strings_live); fixture.strings_live--; fixture.strings_freed++; free(s);
}
static void loader_do_show_loading(Loader* l) {
    assert(l == &loader); fixture.shows++; fixture.depth++;
    if(fixture.depth > fixture.max_depth) fixture.max_depth = fixture.depth;
}
static void loader_do_hide_loading(Loader* l) {
    assert(l == &loader && fixture.depth); fixture.hides++; fixture.depth--;
}
static bool loader_queue_pop(LoaderLaunchQueue* q, LoaderDeferredLaunchRecord* record) {
    assert(q == &loader.launch_queue);
    if(!q->item_cnt) return false;
    assert(q->cursor < fixture.count);
    PlannedLaunch* p = &fixture.plan[q->cursor++]; q->item_cnt--; fixture.pops++;
    *record = (LoaderDeferredLaunchRecord){.name_or_path = p->name, .args = p->args, .flags = p->flags};
    return true;
}
static void loader_queue_item_clear(LoaderDeferredLaunchRecord* record) {
    bool found = false;
    for(size_t i = 0; i < fixture.count; i++) {
        PlannedLaunch* p = &fixture.plan[i];
        if(record->args == p->args) {
            assert(!p->cleared && record->name_or_path == p->name);
            p->cleared = true; fixture.clears++; found = true; break;
        }
    }
    assert(found); record->name_or_path = NULL; record->args = NULL;
}
/* Varargs allow the same harness to compile an immutable pre-fix source for
 * local comparison (four arguments) and today's private API (five). The
 * fixture controls launch results, not deferred queue decisions. */
static LoaderMessageLoaderStatusResult loader_do_start_by_name(
    Loader* l, const char* name, const char* args, FuriString* error_message, ...) {
    assert(l == &loader && !loader_do_is_locked(l) && error_message && fixture.depth);
    assert(fixture.started < fixture.count);
    PlannedLaunch* p = &fixture.plan[fixture.started++];
    assert(name == p->name && args == p->args && !p->cleared);
    memcpy(error_message->text, "expected launch result", sizeof("expected launch result"));
    if(p->status == LoaderStatusOk && p->creates_thread) l->app.thread = &app_thread;
    return (LoaderMessageLoaderStatusResult){.value = p->status, .error = LoaderStatusErrorUnknown};
}
static void loader_show_gui_error(LoaderMessageLoaderStatusResult result, const char* name, FuriString* error_message) {
    assert(result.value != LoaderStatusOk && fixture.strings_live && !strcmp(error_message->text, "expected launch result"));
    fixture.gui_errors++; fixture.gui_error_name = name; fixture.gui_error_status = result.value;
}
"""

CASES = r"""
static void reset(void) {
    assert(fixture.strings_live == 0 && fixture.depth == 0);
    memset(&fixture, 0, sizeof(fixture)); memset(&loader, 0, sizeof(loader));
    loader.pubsub = &pubsub; browser = (Browser){.waiting = true};
}
static void enqueue(char* name, LoaderStatus status, bool creates_thread, LoaderDeferredLaunchFlag flags) {
    assert(fixture.count < 4);
    PlannedLaunch* p = &fixture.plan[fixture.count];
    p->name = name; p->status = status; p->creates_thread = creates_thread; p->flags = flags;
    p->args[0] = (char)('a' + fixture.count); p->args[1] = 0;
    fixture.count++; loader.launch_queue.item_cnt++;
}
static void expect_balanced(unsigned launched) {
    assert(fixture.started == launched && fixture.shows == launched && fixture.hides == launched);
    assert(fixture.depth == 0 && fixture.strings_live == 0);
    assert(fixture.strings_allocated == launched && fixture.strings_freed == launched);
    assert(fixture.pops == launched && fixture.clears == launched);
    for(unsigned i = 0; i < launched; i++) assert(fixture.plan[i].cleared);
}
static void expect_completed(bool clean_before_signal) {
    assert(loader.app.thread == NULL && loader.launch_queue.item_cnt == 0);
    assert(fixture.empty_events == 1 && browser.wakes == 1 && !browser.waiting);
    if(clean_before_signal) assert(fixture.empty_depth == 0 && fixture.empty_strings == 0);
}
static void simulate_app_exit(void) {
    /* AppClosed's caller advances the real helpers after releasing its thread.
     * No app-close implementation is copied or claimed to be tested here. */
    assert(loader.app.thread == &app_thread); loader.app.thread = NULL;
    loader_do_next_deferred_launch_if_available(&loader);
}
void apps_completes(void) {
    reset(); LoaderEvent stopped = {.type = LoaderEventTypeApplicationStopped};
    loader_pubsub_callback(&stopped, &browser);
    assert(browser.waiting && browser.wakes == 0);
    enqueue("Apps", LoaderStatusOk, false, LoaderDeferredLaunchFlagGui);
    loader_do_next_deferred_launch_if_available(&loader);
    expect_balanced(1); expect_completed(true); assert(fixture.gui_errors == 0);
}
void apps_then_thread_then_browser(void) {
    reset(); enqueue("Apps", LoaderStatusOk, false, LoaderDeferredLaunchFlagNone);
    enqueue("Lab", LoaderStatusOk, true, LoaderDeferredLaunchFlagGui);
    enqueue("Apps", LoaderStatusOk, false, LoaderDeferredLaunchFlagNone);
    loader_do_next_deferred_launch_if_available(&loader);
    expect_balanced(2); assert(loader.app.thread == &app_thread && loader.launch_queue.item_cnt == 1);
    assert(fixture.empty_events == 0 && browser.waiting && browser.wakes == 0);
    loader_do_emit_queue_empty_event(&loader); assert(fixture.empty_events == 0);
    simulate_app_exit(); expect_balanced(3); expect_completed(true); assert(fixture.gui_errors == 0);
}
void consecutive_browsers(void) {
    reset();
    for(unsigned i = 0; i < 4; i++) enqueue("Apps", LoaderStatusOk, false, LoaderDeferredLaunchFlagNone);
    loader_do_next_deferred_launch_if_available(&loader);
    expect_balanced(4); expect_completed(true); assert(fixture.gui_errors == 0);
}
void thread_waits_for_exit(void) {
    reset(); enqueue("Lab", LoaderStatusOk, true, LoaderDeferredLaunchFlagNone);
    loader_do_next_deferred_launch_if_available(&loader);
    expect_balanced(1); assert(loader.app.thread == &app_thread && loader.launch_queue.item_cnt == 0);
    assert(fixture.empty_events == 0 && browser.waiting && browser.wakes == 0);
    loader_do_emit_queue_empty_event(&loader); assert(fixture.empty_events == 0);
    simulate_app_exit(); expect_completed(true);
}
void failure_continues_and_respects_gui_flag(void) {
    for(unsigned gui = 0; gui < 2; gui++) {
        reset(); enqueue("missing", LoaderStatusErrorUnknownApp, false,
            gui ? LoaderDeferredLaunchFlagGui : LoaderDeferredLaunchFlagNone);
        enqueue("Apps", LoaderStatusOk, false, LoaderDeferredLaunchFlagNone);
        loader_do_next_deferred_launch_if_available(&loader);
        expect_balanced(2); expect_completed(false); assert(fixture.gui_errors == gui);
        if(gui) {
            assert(!strcmp(fixture.gui_error_name, "missing"));
            assert(fixture.gui_error_status == LoaderStatusErrorUnknownApp);
        }
    }
    /* The false return describes this record even when its successor succeeds.
     * Existing failure-path bracketing is deliberately outside the new
     * success-only cleanup-before-notification guarantee. */
    reset(); enqueue("broken", LoaderStatusErrorInternal, false, LoaderDeferredLaunchFlagGui);
    enqueue("Apps", LoaderStatusOk, false, LoaderDeferredLaunchFlagNone);
    LoaderDeferredLaunchRecord first;
    assert(loader_queue_pop(&loader.launch_queue, &first));
    assert(!loader_do_deferred_launch(&loader, &first)); loader_queue_item_clear(&first);
    expect_balanced(2); expect_completed(false); assert(fixture.gui_errors == 1);
}
void failure_then_thread_waits(void) {
    reset(); enqueue("missing", LoaderStatusErrorInternal, false, LoaderDeferredLaunchFlagGui);
    enqueue("Lab", LoaderStatusOk, true, LoaderDeferredLaunchFlagNone);
    loader_do_next_deferred_launch_if_available(&loader);
    expect_balanced(2); assert(fixture.gui_errors == 1 && loader.app.thread == &app_thread);
    assert(fixture.empty_events == 0 && browser.waiting && browser.wakes == 0);
    simulate_app_exit(); expect_completed(true);
}
"""


class LoaderDeferredBrowserTests(unittest.TestCase):
    def run_case(self, name):
        native_test(
            PREAMBLE
            + production_enums()
            + STUBS
            + browser_callback()
            + DEPENDENCIES
            + production_source()
            + CASES
            + f"\nint main(void) {{ {name}(); return 0; }}\n"
        )

    def test_apps_completes_after_loading_and_temporary_cleanup(self):
        self.run_case("apps_completes")

    def test_apps_advances_to_thread_and_waits_before_browser_resume(self):
        self.run_case("apps_then_thread_then_browser")

    def test_multiple_apps_targets_finish_the_queue_once(self):
        self.run_case("consecutive_browsers")

    def test_real_app_waits_for_exit_before_queue_empty(self):
        self.run_case("thread_waits_for_exit")

    def test_failure_continues_and_preserves_gui_error_flag(self):
        self.run_case("failure_continues_and_respects_gui_flag")

    def test_failure_then_thread_does_not_resume_browser_early(self):
        self.run_case("failure_then_thread_waits")


if __name__ == "__main__":
    unittest.main()
