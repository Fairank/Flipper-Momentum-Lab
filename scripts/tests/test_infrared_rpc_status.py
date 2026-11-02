"""The real RPC load completion must expose a ready view without entering TX state."""

from pathlib import Path
import subprocess
import tempfile
import unittest

from scripts.tests.test_storage_upgrade import build

ROOT = Path(__file__).resolve().parents[2]


class InfraredRpcStatusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = (
            ROOT / "applications/main/infrared/scenes/infrared_scene_rpc.c"
        ).read_text(encoding="utf-8")
        states = source[source.index("typedef enum") : source.index("static int32_t")]
        show = source[
            source.index("static void infrared_scene_rpc_show") : source.index(
                "bool infrared_scene_rpc_on_event"
            )
        ]
        start = source.index("            const InfraredErrorCode task_error =")
        end = source.index("        } else if(", start)
        finish = source[start:end]
        temporary = tempfile.TemporaryDirectory(prefix="ir-rpc-status-")
        cls.addClassCleanup(temporary.cleanup)
        folder = Path(temporary.name)
        fixture = r"""
#undef NDEBUG
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
typedef struct { char text[256]; } Popup;
typedef struct { char text[256]; } FuriString;
typedef int InfraredErrorCode;
typedef struct {
    Popup* popup; int* view_dispatcher; int* scene_manager; const char* remote;
    bool* rpc_ctx; FuriString* file_path; char text_store[2][256];
} InfraredApp;
enum { InfraredSceneRpc, InfraredViewPopup=7, RpcAppSystemErrorCodeParseFile=3 };
static int task_error, error_code;
#define INFRARED_ERROR_PRESENT(e) ((e)!=0)
#define popup_set_header(...) ((void)0)
#define popup_set_icon(...) ((void)0)
#define popup_set_context(...) ((void)0)
#define popup_set_callback(...) ((void)0)
#define notification_message(...) ((void)0)
#define popup_set_text(p,t,...) snprintf((p)->text,sizeof((p)->text),"%s",t)
static void view_dispatcher_switch_to_view(int* view,int id) { *view=id; }
static void scene_manager_set_scene_state(int* state,int scene,int value) { (void)scene;*state=value; }
static int infrared_blocking_task_finalize(InfraredApp* app) { (void)app;return task_error; }
static const char* infrared_remote_get_name(const char* remote) { return remote; }
static void infrared_text_store_set(InfraredApp* app,int bank,const char* format,...) {
    va_list args;va_start(args,format);vsnprintf(app->text_store[bank],256,format,args);va_end(args);
}
static FuriString* furi_string_alloc(void) { return calloc(1,sizeof(FuriString)); }
static void furi_string_printf(FuriString* s,const char* format,...) {
    va_list args;va_start(args,format);vsnprintf(s->text,256,format,args);va_end(args);
}
static const char* furi_string_get_cstr(FuriString* s) { return s->text; }
static void furi_string_free(FuriString* s) { free(s); }
static void rpc_system_app_set_error_code(bool* ctx,int code) { (void)ctx;error_code=code; }
static void rpc_system_app_set_error_text(bool* ctx,const char* text) { (void)ctx;assert(strstr(text,"Failed to load")); }
static void rpc_system_app_confirm(bool* confirmed,bool result) { *confirmed=result; }
/* STATES */
/* SHOW */
static void finished(InfraredApp* infrared) {
/* FINISH */
}
int main(int argc,char** argv) {
    assert(argc==2);task_error=atoi(argv[1]);
    int state=InfraredRpcStateIdle,view=0;bool confirmed=false;Popup popup={0};FuriString path={"/ext/infrared/test.ir"};
    InfraredApp app={.popup=&popup,.view_dispatcher=&view,.scene_manager=&state,
        .remote="TCL_32S327",.rpc_ctx=&confirmed,.file_path=&path};
    (void)infrared_scene_rpc_show;
    finished(&app);
    if(!task_error) {
        assert(confirmed && state==InfraredRpcStateLoaded);
        assert(view==InfraredViewPopup && !strcmp(popup.text,"loaded\nTCL_32S327"));
    } else {
        assert(!confirmed && state==InfraredRpcStateIdle && view==0);
        assert(error_code==RpcAppSystemErrorCodeParseFile);
    }
    return 0;
}
"""
        fixture = (
            fixture.replace("/* STATES */", states)
            .replace("/* SHOW */", show)
            .replace("/* FINISH */", finish)
        )
        path = folder / "ir_rpc_status.c"
        path.write_text(fixture, encoding="utf-8")
        cls.exe = build(
            folder, [path], "ir_rpc_status", ["-Wall", "-Wextra", "-Werror"]
        )

    def scenario(self, error):
        result = subprocess.run(
            [str(self.exe), str(error)], capture_output=True, timeout=20
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_successful_load_shows_model_and_keeps_remote_ready(self):
        self.scenario(0)

    def test_failed_load_is_not_presented_as_ready(self):
        self.scenario(1)
