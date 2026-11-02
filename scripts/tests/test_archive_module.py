"""The SD Archive UI keeps the desktop context and fails without dangling code."""

from pathlib import Path
import re
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_unleashed_integration import ROOT, native_test


class ArchiveModuleTests(unittest.TestCase):
    def test_context_failure_and_module_lifetime(self):
        source = (ROOT / "applications/main/archive/archive_loader.c").read_text()
        source = re.sub(r"^#include[^\n]*\n", "", source, flags=re.M)
        native_test(
            r"""
#undef NDEBUG
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef struct {int live;}PluginManager;
typedef struct {int unused;}DialogsApp;
typedef int32_t(*FlipperApplicationEntryPoint)(void*);
enum{PluginManagerErrorNone};
#define RECORD_DIALOGS "dialogs"
static PluginManager instance;
static DialogsApp dialogs;
static const void*firmware_api_interface=&instance;
static int error,empty,shown,called,opened;
static void*expected;
static PluginManager*plugin_manager_alloc(const char*id,int version,const void*api){
assert(!instance.live&&!strcmp(id,"archive_ui")&&version==1&&api==firmware_api_interface);instance.live=1;return &instance;}
static int plugin_manager_load_single(PluginManager*m,const char*path){
assert(m==&instance&&instance.live&&!strcmp(path,"/ext/apps_data/archive/plugins/archive_ui.fal"));return error;}
static int32_t entry(void*ctx){assert(instance.live&&ctx==expected);called++;return 17;}
static const void*plugin_manager_get_ep(PluginManager*m,int index){assert(m==&instance&&!index&&!error);return empty?NULL:(const void*)entry;}
static void plugin_manager_free(PluginManager*m){assert(m==&instance&&instance.live);instance.live=0;}
static DialogsApp*furi_record_open(const char*name){assert(!strcmp(name,RECORD_DIALOGS)&&!opened++);return &dialogs;}
static void dialog_message_show_storage_error(DialogsApp*d,const char*text){assert(d==&dialogs&&strstr(text,"Archive module")&&instance.live);shown++;}
static void furi_record_close(const char*name){assert(!strcmp(name,RECORD_DIALOGS)&&opened--==1);}
"""
            + source
            + r"""
int main(void){char context[64]="/ext/nfc";expected=context;
for(int i=0;i<6;i++)assert(archive_app(context)==17&&!instance.live&&!opened);
assert(called==6&&!shown);
error=1;assert(archive_app(context)==-1&&shown==1&&called==6&&!instance.live&&!opened);
error=0;empty=1;assert(archive_app(context)==-1&&shown==2&&called==6&&!instance.live&&!opened);
empty=0;expected=NULL;assert(archive_app(NULL)==17&&called==7&&!instance.live&&!opened);
return 0;}
"""
        )
