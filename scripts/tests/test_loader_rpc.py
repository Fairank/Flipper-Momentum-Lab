"""Compile the real external-app loader to check RPC launch compatibility.

The harness extracts the complete production function, its status helpers and
asset-progress callback. Only platform dependencies are substituted: no loader
decisions are reimplemented here. It cannot validate ELF loading or BLE on a
device. ARM's debugger-only breakpoint is a fail-fast host stub; the simulated
debugger is never active. A missing host compiler is a failure, not a skip.
"""

from pathlib import Path
import re
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_unleashed_integration import ROOT, native_test  # noqa: E402


def production_source():
    text = (ROOT / "applications/services/loader/loader.c").read_text(encoding="utf-8")
    start = text.index("static void loader_log_status_error(")
    return text[start : text.index("\n// process messages", start)]


def production_enum(path, name):
    text = (ROOT / path).read_text(encoding="utf-8")
    match = re.search(r"typedef enum[^{}]*\{[^{}]*\}\s*" + name + r"\s*;", text)
    if match is None:
        raise AssertionError(f"Missing production enum {name}")
    return match.group(0)


PREAMBLE = r"""
#undef NDEBUG
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define FURI_PACKED
#define TAG "Loader"
"""

STUBS = r"""
typedef struct { char text[256]; } FuriString;
typedef struct { int id; } Storage;
typedef struct { int id; } FuriThread;
typedef struct { int id; } FuriPubSub;
typedef struct { float progress; } Loading;
typedef struct { uint16_t api_version_major; } ElfApiInterface;
typedef struct {
    struct { struct { uint16_t major; } api_version; } base;
    FlipperApplicationFlag flags;
} FlipperApplicationManifest;
typedef void (*FlipperApplicationAssetsProgress)(void*, size_t, size_t);
typedef struct {
    FlipperApplicationManifest manifest;
    FlipperApplicationAssetsProgress progress;
    void* progress_context;
} FlipperApplication;
typedef struct {
    FuriThread* thread;
    FlipperApplication* fap;
    bool unloaded_asset_packs;
} LoaderAppData;
typedef struct {
    LoaderAppData app;
    Loading* loading;
    uint8_t loading_depth;
    FuriPubSub* pubsub;
} Loader;
typedef struct { LoaderStatus value; LoaderStatusError error; } LoaderMessageLoaderStatusResult;
typedef struct { LoaderEventType type; } LoaderEvent;
typedef enum { AlignCenter, AlignTop } Align;
typedef enum { DialogMessageButtonLeft, DialogMessageButtonRight } DialogMessageButton;
typedef struct { int id; } DialogMessage;
typedef struct { int id; } DialogsApp;
#define RECORD_DIALOGS "dialogs"

static const ElfApiInterface api = {.api_version_major = 37};
static const ElfApiInterface* firmware_api_interface = &api;
static Storage storage;
static FuriThread thread;
static FuriPubSub pubsub;
static Loading loading;
static Loader loader;
static FlipperApplication application;
static DialogMessage dialog;
static DialogsApp dialogs;
static FuriString error_message;
static const char* const app_path = "/ext/apps/Tools/example.fap";

static struct {
    FlipperApplicationPreloadStatus manifest_status, preload_status;
    FlipperApplicationLoadStatus load_status;
    DialogMessageButton choice;
    bool plugin, fap_live, dialog_live, packs_live;
    unsigned allocations, frees, manifests, preloads, maps, plugin_checks;
    unsigned dialogs_shown, dialog_allocations, dialog_frees, records_opened, records_closed;
    unsigned threads, starts, failed_events, packs_freed, packs_restored, progress_resets;
    unsigned strings_allocated, strings_freed;
    FlipperApplicationFlag started_flags;
    const char* thread_args;
    char appid[32], header[32], dialog_text[96];
} fixture;

static void host_log(const char* tag, const char* format, ...) {
    (void)tag; (void)format;
}
#define FURI_LOG_I host_log
#define FURI_LOG_E host_log
#define FURI_LOG_W host_log

/* The original ARM-only statement remains in the extracted function. On the
 * host it calls this stub; reaching it is an error, never a successful test. */
static void host_arm_instruction(const char* instruction) {
    (void)instruction; assert(!"Unexpected target-only debugger instruction");
}
#define __asm host_arm_instruction
#define volatile(...) (__VA_ARGS__)
static bool furi_hal_debug_is_gdb_session_active(void) { return false; }
static uint32_t furi_get_tick(void) { return 100; }

static FuriString* furi_string_alloc(void) {
    FuriString* s = calloc(1, sizeof(*s)); assert(s);
    fixture.strings_allocated++; return s;
}
static void furi_string_free(FuriString* s) {
    assert(s); fixture.strings_freed++; free(s);
}
static const char* furi_string_get_cstr(const FuriString* s) { return s->text; }
static void furi_string_set(FuriString* s, const char* text) {
    snprintf(s->text, sizeof(s->text), "%s", text);
}
static void furi_string_vprintf(FuriString* s, const char* format, va_list args) {
    vsnprintf(s->text, sizeof(s->text), format, args);
}
static void path_extract_filename_no_ext(const char* path, FuriString* name) {
    const char* base = strrchr(path, '/'); base = base ? base + 1 : path;
    const char* dot = strrchr(base, '.');
    size_t length = dot ? (size_t)(dot - base) : strlen(base);
    assert(length < sizeof(name->text)); memcpy(name->text, base, length); name->text[length] = 0;
}
static FlipperApplication* flipper_application_alloc(Storage* s, const ElfApiInterface* a) {
    assert(s == &storage && a == &api && !fixture.fap_live);
    fixture.allocations++; fixture.fap_live = true; return &application;
}
static void flipper_application_free(FlipperApplication* app) {
    assert(app == &application && fixture.fap_live);
    fixture.frees++; fixture.fap_live = false;
}
static void flipper_application_set_assets_progress_callback(
    FlipperApplication* app, FlipperApplicationAssetsProgress callback, void* context) {
    assert(app == &application && fixture.fap_live && callback && context == &loader);
    app->progress = callback; app->progress_context = context;
}
static FlipperApplicationPreloadStatus flipper_application_preload_manifest(
    FlipperApplication* app, const char* path) {
    assert(app == &application && fixture.fap_live && !strcmp(path, app_path));
    fixture.manifests++; return fixture.manifest_status;
}
static const FlipperApplicationManifest* flipper_application_get_manifest(FlipperApplication* app) {
    assert(app == &application && fixture.fap_live); return &app->manifest;
}
static FlipperApplicationPreloadStatus flipper_application_preload(
    FlipperApplication* app, const char* path) {
    assert(app == &application && fixture.fap_live && !strcmp(path, app_path));
    fixture.preloads++; assert(app->progress);
    app->progress(app->progress_context, 1, 2);
    return fixture.preload_status;
}
static FlipperApplicationLoadStatus flipper_application_map_to_memory(FlipperApplication* app) {
    assert(app == &application && fixture.fap_live); fixture.maps++; return fixture.load_status;
}
static const char* flipper_application_preload_status_to_string(FlipperApplicationPreloadStatus s) {
    (void)s; return "preload status";
}
static const char* flipper_application_load_status_to_string(FlipperApplicationLoadStatus s) {
    (void)s; return "load status";
}
static bool flipper_application_is_plugin(FlipperApplication* app) {
    assert(app == &application && fixture.fap_live); fixture.plugin_checks++; return fixture.plugin;
}
static FuriThread* flipper_application_alloc_thread(FlipperApplication* app, const char* args) {
    assert(app == &application && fixture.fap_live && !fixture.plugin);
    fixture.threads++; fixture.thread_args = args; return &thread;
}
static void furi_thread_set_appid(FuriThread* t, const char* appid) {
    assert(t == &thread); snprintf(fixture.appid, sizeof(fixture.appid), "%s", appid);
}
static void loader_start_app_thread(Loader* l, FlipperApplicationFlag flags) {
    assert(l == &loader && l->app.thread == &thread && fixture.threads == 1);
    fixture.starts++; fixture.started_flags = flags;
}
static void loading_set_progress(Loading* l, float progress) {
    assert(l == &loading); l->progress = progress;
}
static void loading_reset_progress(Loading* l) {
    assert(l == &loading); fixture.progress_resets++; l->progress = 0;
}
static void asset_packs_free(void) {
    assert(fixture.packs_live); fixture.packs_live = false; fixture.packs_freed++;
}
static void asset_packs_init(void) {
    assert(!fixture.packs_live); fixture.packs_live = true; fixture.packs_restored++;
}
static void furi_pubsub_publish(FuriPubSub* p, const LoaderEvent* event) {
    assert(p == &pubsub && event->type == LoaderEventTypeApplicationLoadFailed);
    fixture.failed_events++;
}
static DialogMessage* dialog_message_alloc(void) {
    assert(!fixture.dialog_live); fixture.dialog_live = true; fixture.dialog_allocations++; return &dialog;
}
static void dialog_message_free(DialogMessage* m) {
    assert(m == &dialog && fixture.dialog_live); fixture.dialog_live = false; fixture.dialog_frees++;
}
static void dialog_message_set_header(DialogMessage* m, const char* text, int x, int y, Align a, Align b) {
    assert(m == &dialog && fixture.dialog_live); (void)x; (void)y; (void)a; (void)b;
    snprintf(fixture.header, sizeof(fixture.header), "%s", text);
}
static void dialog_message_set_text(DialogMessage* m, const char* text, int x, int y, Align a, Align b) {
    assert(m == &dialog && fixture.dialog_live); (void)x; (void)y; (void)a; (void)b;
    snprintf(fixture.dialog_text, sizeof(fixture.dialog_text), "%s", text);
}
static void dialog_message_set_buttons(DialogMessage* m, const char* left, const char* center, const char* right) {
    assert(m == &dialog && fixture.dialog_live && !strcmp(left, "Cancel") && center == NULL && !strcmp(right, "Continue"));
}
static void* furi_record_open(const char* record) {
    assert(!strcmp(record, RECORD_DIALOGS)); fixture.records_opened++; return &dialogs;
}
static void furi_record_close(const char* record) {
    assert(!strcmp(record, RECORD_DIALOGS)); fixture.records_closed++;
}
static DialogMessageButton dialog_message_show(DialogsApp* d, DialogMessage* m) {
    assert(d == &dialogs && m == &dialog && fixture.dialog_live);
    fixture.dialogs_shown++; return fixture.choice;
}
"""

CASES = r"""
static void reset(FlipperApplicationFlag flags) {
    assert(!fixture.fap_live && !fixture.dialog_live);
    assert(fixture.strings_allocated == fixture.strings_freed);
    memset(&fixture, 0, sizeof(fixture)); memset(&loader, 0, sizeof(loader));
    memset(&application, 0, sizeof(application)); memset(&error_message, 0, sizeof(error_message));
    fixture.packs_live = true;
    fixture.manifest_status = fixture.preload_status = FlipperApplicationPreloadStatusSuccess;
    fixture.load_status = FlipperApplicationLoadStatusSuccess; fixture.choice = DialogMessageButtonRight;
    application.manifest.flags = flags; application.manifest.base.api_version.major = 37;
    loader.loading = &loading; loader.loading_depth = 1; loader.pubsub = &pubsub;
}
static LoaderMessageLoaderStatusResult run(bool remote, const char* args) {
    return loader_start_external_app(&loader, &storage, app_path, args, &error_message, remote);
}
static void expect_dialogs(unsigned expected) {
    assert(fixture.dialogs_shown == expected && fixture.dialog_allocations == expected);
    assert(fixture.dialog_frees == expected && !fixture.dialog_live);
    assert(fixture.records_opened == expected && fixture.records_closed == expected);
}
static void expect_failure(LoaderMessageLoaderStatusResult r, LoaderStatus status, LoaderStatusError error, bool unloaded) {
    assert(r.value == status && r.error == error && error_message.text[0]);
    assert(fixture.allocations == 1 && fixture.frees == 1 && !fixture.fap_live);
    assert(loader.app.fap == NULL && loader.app.thread == NULL);
    assert(fixture.threads == 0 && fixture.starts == 0 && fixture.failed_events == 1);
    assert(fixture.packs_freed == (unsigned)unloaded && fixture.packs_restored == (unsigned)unloaded);
    assert(fixture.packs_live && loader.app.unloaded_asset_packs == unloaded);
    assert(fixture.progress_resets == 1 && loading.progress == 0);
    assert(fixture.strings_allocated == fixture.strings_freed);
}
static void expect_success(LoaderMessageLoaderStatusResult r, const char* args, FlipperApplicationFlag flags) {
    bool unloaded = (flags & FlipperApplicationFlagUnloadAssetPacks) != 0;
    assert(r.value == LoaderStatusOk && r.error == LoaderStatusErrorUnknown);
    assert(!strcmp(error_message.text, "App started"));
    assert(fixture.allocations == 1 && fixture.frees == 0 && fixture.fap_live);
    assert(loader.app.fap == &application && loader.app.thread == &thread);
    assert(fixture.threads == 1 && fixture.starts == 1 && fixture.failed_events == 0);
    assert(fixture.thread_args == args && fixture.started_flags == flags && !strcmp(fixture.appid, "example"));
    assert(fixture.packs_freed == (unsigned)unloaded && fixture.packs_restored == 0);
    assert(fixture.packs_live == !unloaded && loader.app.unloaded_asset_packs == unloaded);
    assert(fixture.manifests == 1 && fixture.preloads == 1 && fixture.maps == 1 && fixture.plugin_checks == 1);
    assert(fixture.progress_resets == 1 && loading.progress == 0);
    assert(fixture.strings_allocated == 1 && fixture.strings_freed == 1);
    /* Ownership remains with the running app. Fixture cleanup below is not a
     * claim that loader_start_external_app closes successful applications. */
    flipper_application_free(loader.app.fap); loader.app.fap = NULL; loader.app.thread = NULL;
    if(unloaded) asset_packs_init();
}
static const FlipperApplicationPreloadStatus mismatch[] = {
    FlipperApplicationPreloadStatusApiTooOld, FlipperApplicationPreloadStatusApiTooNew,
};
static const LoaderStatusError mismatch_error[] = {
    LoaderStatusErrorOutdatedApp, LoaderStatusErrorOutdatedFirmware,
};

void remote_mismatch(void) {
    for(unsigned unload = 0; unload < 2; unload++) {
        for(unsigned i = 0; i < 2; i++) {
            reset(unload ? FlipperApplicationFlagUnloadAssetPacks : FlipperApplicationFlagDefault);
            fixture.preload_status = mismatch[i];
            LoaderMessageLoaderStatusResult r = run(true, "");
            expect_failure(r, LoaderStatusErrorInternal, mismatch_error[i], unload);
            assert(strstr(error_message.text, "Remote start refused"));
            assert(fixture.manifests == 1 && fixture.preloads == 1 && fixture.maps == 0 && fixture.plugin_checks == 0);
            expect_dialogs(0);
        }
    }
}
void native_mismatch(void) {
    for(unsigned unload = 0; unload < 2; unload++) {
        for(unsigned i = 0; i < 2; i++) {
            for(unsigned proceed = 0; proceed < 2; proceed++) {
                FlipperApplicationFlag flags = unload ? FlipperApplicationFlagUnloadAssetPacks : FlipperApplicationFlagDefault;
                reset(flags); fixture.preload_status = mismatch[i];
                application.manifest.base.api_version.major = i ? 38 : 36;
                fixture.choice = proceed ? DialogMessageButtonRight : DialogMessageButtonLeft;
                LoaderMessageLoaderStatusResult r = run(false, NULL);
                expect_dialogs(1); assert(fixture.maps == 1);
                assert(!strcmp(fixture.header, i ? "App Too New" : "App Too Old"));
                assert(strstr(fixture.dialog_text, i ? "APP:38 > FW:37" : "APP:36 < FW:37"));
                if(proceed) expect_success(r, NULL, flags);
                else {
                    expect_failure(r, LoaderStatusErrorApiMismatchCanceled, mismatch_error[i], unload);
                    assert(fixture.plugin_checks == 0);
                }
            }
        }
    }
}
void compatible_remote(void) {
    const char* args[] = {NULL, "", "RPC 12345678", "saved-file-path"};
    for(unsigned unload = 0; unload < 2; unload++) {
        for(unsigned i = 0; i < sizeof(args) / sizeof(args[0]); i++) {
            FlipperApplicationFlag flags = unload ? FlipperApplicationFlagUnloadAssetPacks : FlipperApplicationFlagDefault;
            reset(flags); LoaderMessageLoaderStatusResult r = run(true, args[i]);
            expect_dialogs(0); expect_success(r, args[i], flags);
        }
    }
}
void preload_failures(void) {
    const FlipperApplicationPreloadStatus statuses[] = {
        FlipperApplicationPreloadStatusInvalidFile, FlipperApplicationPreloadStatusInvalidManifest,
        FlipperApplicationPreloadStatusTargetMismatch, FlipperApplicationPreloadStatusNotEnoughMemory,
    };
    const LoaderStatusError errors[] = {
        LoaderStatusErrorInvalidFile, LoaderStatusErrorInvalidManifest,
        LoaderStatusErrorHWMismatch, LoaderStatusErrorOutOfMemory,
    };
    for(unsigned remote = 0; remote < 2; remote++) {
        for(unsigned unload = 0; unload < 2; unload++) {
            for(unsigned i = 0; i < sizeof(statuses) / sizeof(statuses[0]); i++) {
                reset(unload ? FlipperApplicationFlagUnloadAssetPacks : FlipperApplicationFlagDefault);
                fixture.preload_status = statuses[i];
                expect_failure(run(remote, ""), LoaderStatusErrorInternal, errors[i], unload);
                assert(fixture.preloads == 1 && fixture.maps == 0 && fixture.plugin_checks == 0);
                expect_dialogs(0);
                /* Invalid manifest/file failures can also happen before the
                 * flags or full preload are read. No packs were unloaded. */
                if(i < 2) {
                    reset(FlipperApplicationFlagUnloadAssetPacks); fixture.manifest_status = statuses[i];
                    expect_failure(run(remote, ""), LoaderStatusErrorInternal, errors[i], false);
                    assert(fixture.manifests == 1 && fixture.preloads == 0 && fixture.maps == 0);
                    expect_dialogs(0);
                }
            }
        }
    }
}
void map_failures(void) {
    for(unsigned remote = 0; remote < 2; remote++) {
        for(unsigned unload = 0; unload < 2; unload++) {
            reset(unload ? FlipperApplicationFlagUnloadAssetPacks : FlipperApplicationFlagDefault);
            fixture.load_status = FlipperApplicationLoadStatusMissingImports;
            expect_failure(run(remote, ""), LoaderStatusErrorInternal, LoaderStatusErrorMissingImports, unload);
            assert(fixture.maps == 1 && fixture.plugin_checks == 0); expect_dialogs(0);
        }
    }
    for(unsigned i = 0; i < 2; i++) {
        reset(FlipperApplicationFlagUnloadAssetPacks);
        fixture.preload_status = mismatch[i]; fixture.load_status = FlipperApplicationLoadStatusMissingImports;
        expect_failure(run(false, ""), LoaderStatusErrorInternal, mismatch_error[i], true);
        assert(fixture.maps == 1 && fixture.plugin_checks == 0); expect_dialogs(0);
    }
    reset(FlipperApplicationFlagDefault); fixture.load_status = FlipperApplicationLoadStatusUnspecifiedError;
    expect_failure(run(true, ""), LoaderStatusErrorInternal, LoaderStatusErrorUnknown, false);
    assert(fixture.maps == 1); expect_dialogs(0);
}
void plugins(void) {
    for(unsigned remote = 0; remote < 2; remote++) {
        for(unsigned unload = 0; unload < 2; unload++) {
            reset(unload ? FlipperApplicationFlagUnloadAssetPacks : FlipperApplicationFlagDefault);
            fixture.plugin = true;
            expect_failure(run(remote, ""), LoaderStatusErrorInternal, LoaderStatusErrorUnknown, unload);
            assert(fixture.maps == 1 && fixture.plugin_checks == 1);
            assert(strstr(error_message.text, "not runnable")); expect_dialogs(0);
        }
    }
}
"""


class LoaderRPCTests(unittest.TestCase):
    def run_case(self, name):
        enums = "\n".join(
            production_enum(path, enum)
            for path, enum in (
                ("applications/services/applications.h", "FlipperApplicationFlag"),
                ("applications/services/loader/loader.h", "LoaderStatus"),
                ("applications/services/loader/loader.h", "LoaderEventType"),
                ("applications/services/loader/loader_i.h", "LoaderStatusError"),
                (
                    "lib/flipper_application/flipper_application.h",
                    "FlipperApplicationPreloadStatus",
                ),
                (
                    "lib/flipper_application/flipper_application.h",
                    "FlipperApplicationLoadStatus",
                ),
            )
        )
        native_test(
            PREAMBLE
            + enums
            + STUBS
            + production_source()
            + CASES
            + f"\nint main(void) {{ {name}(); return 0; }}\n"
        )

    def test_remote_api_mismatch_has_no_map_dialog_or_start(self):
        self.run_case("remote_mismatch")

    def test_native_mismatch_preserves_cancel_and_continue(self):
        self.run_case("native_mismatch")

    def test_compatible_remote_preserves_arguments_and_ownership(self):
        self.run_case("compatible_remote")

    def test_preload_failures_release_resources(self):
        self.run_case("preload_failures")

    def test_map_failures_and_native_bypass_failure(self):
        self.run_case("map_failures")

    def test_plugins_are_rejected_and_assets_restored(self):
        self.run_case("plugins")


if __name__ == "__main__":
    unittest.main()
