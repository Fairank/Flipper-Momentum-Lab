"""Run FlipNote's actual C indexing, buffering and staged-save functions.

Written by a collaborating assistant and reviewed by the primary assistant.

The in-memory file service models EOF separately from failed reads, partial
writes, sync/close failures and no-overwrite rename. It is a host regression,
not evidence of SD-card reliability or hardware acceptance.
"""

from pathlib import Path
import re
import unittest

from test_unleashed_integration import native_test

ROOT = Path(__file__).resolve().parents[2]


def c_function(source, name):
    """Extract one unchanged C function, ignoring quoted/commented braces."""
    match = re.search(r"^static\s+(?:void|bool|int)\s+" + name + r"\(", source, re.M)
    if not match:
        raise AssertionError("Production function missing: " + name)
    begin = match.start()
    pos = source.index("{", match.end())
    depth = 0
    state = "code"
    while pos < len(source):
        char = source[pos]
        following = source[pos : pos + 2]
        if state == "line":
            if char == "\n":
                state = "code"
        elif state == "block":
            if following == "*/":
                state = "code"
                pos += 1
        elif state in ('"', "'"):
            if char == "\\":
                pos += 1
            elif char == state:
                state = "code"
        elif following == "//":
            state = "line"
            pos += 1
        elif following == "/*":
            state = "block"
            pos += 1
        elif char in ('"', "'"):
            state = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[begin : pos + 1] + "\n"
        pos += 1
    raise AssertionError("Unterminated production function: " + name)


STORAGE = r"""
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define RECORD_STORAGE "storage"
#define MOCK_FILES 16
#define MOCK_CAPACITY 65536
typedef int EdMode;
typedef enum {FSE_OK, FSE_NOT_EXIST, FSE_EXIST, FSE_INTERNAL} FS_Error;
enum {FSAM_READ, FSAM_WRITE, FSOM_OPEN_EXISTING, FSOM_CREATE_ALWAYS};
typedef struct {bool is_dir; size_t size;} FileInfo;
typedef struct {int unused;} Storage;
typedef struct {
    bool exists, is_dir;
    char path[512];
    unsigned char bytes[MOCK_CAPACITY];
    size_t size;
    unsigned open_count;
} Node;
typedef struct {
    Node* node;
    size_t pos;
    int access;
    bool opened;
    FS_Error error;
} File;
typedef struct {
    const char *open_path, *read_path, *seek_path, *close_path, *stat_path;
    size_t read_after;
    int short_write_call, sync_call;
    unsigned rename_fail_mask;
} Fault;
static Node nodes[MOCK_FILES];
static Storage storage;
static Fault fault;
static int records, handles, writes, syncs, renames;

static Node* lookup(const char* path) {
    for(size_t i=0;i<MOCK_FILES;i++)
        if(nodes[i].exists && strcmp(nodes[i].path,path)==0) return &nodes[i];
    return NULL;
}
static Node* create_node(const char* path) {
    Node* found=lookup(path);
    if(found) return found;
    assert(strlen(path)<sizeof(nodes[0].path));
    for(size_t i=0;i<MOCK_FILES;i++) if(!nodes[i].exists) {
        memset(&nodes[i],0,sizeof(nodes[i]));
        nodes[i].exists=true;
        strcpy(nodes[i].path,path);
        return &nodes[i];
    }
    assert(!"Mock filesystem exhausted");
    return NULL;
}
static void put_bytes(const char* path,const void* bytes,size_t size) {
    Node* node=create_node(path);
    assert(!node->open_count && size<=MOCK_CAPACITY);
    if(size) memcpy(node->bytes,bytes,size);
    node->size=size;
}
static void expect_bytes(const char* path,const void* bytes,size_t size) {
    Node* node=lookup(path);
    assert(node && node->size==size);
    if(size) assert(memcmp(node->bytes,bytes,size)==0);
}
static void* furi_record_open(const char* record) {
    assert(strcmp(record,RECORD_STORAGE)==0);
    records++;
    return &storage;
}
static void furi_record_close(const char* record) {
    assert(strcmp(record,RECORD_STORAGE)==0 && records>0);
    records--;
}
static File* storage_file_alloc(Storage* owner) {
    assert(owner==&storage);
    File* file=calloc(1,sizeof(File));
    assert(file); handles++;
    return file;
}
static bool storage_file_open(File* file,const char* path,int access,int mode) {
    assert(!file->opened);
    if(fault.open_path && strcmp(path,fault.open_path)==0) {
        file->error=FSE_INTERNAL; return false;
    }
    Node* node=lookup(path);
    if(mode==FSOM_CREATE_ALWAYS) {
        node=create_node(path); node->size=0;
    }
    if(!node || node->is_dir) {file->error=FSE_NOT_EXIST;return false;}
    file->node=node; file->pos=0; file->access=access; file->opened=true;
    file->error=FSE_OK; node->open_count++;
    return true;
}
static size_t storage_file_read(File* file,void* bytes,size_t count) {
    assert(file->opened && file->access==FSAM_READ);
    if(fault.read_path && strcmp(file->node->path,fault.read_path)==0 &&
       file->pos>=fault.read_after) {file->error=FSE_INTERNAL;return 0;}
    size_t available=file->node->size-file->pos;
    if(count>available) count=available;
    if(fault.read_path && strcmp(file->node->path,fault.read_path)==0 &&
       file->pos<fault.read_after && count>fault.read_after-file->pos)
        count=fault.read_after-file->pos;
    if(count) memcpy(bytes,file->node->bytes+file->pos,count);
    file->pos+=count;
    return count; /* EOF leaves FSE_OK; a later failed call sets FSE_INTERNAL. */
}
static size_t storage_file_write(File* file,const void* bytes,size_t count) {
    assert(file->opened && file->access==FSAM_WRITE);
    writes++;
    if(writes==fault.short_write_call) {
        if(count) count--;
        file->error=FSE_INTERNAL;
    }
    assert(file->pos+count<=MOCK_CAPACITY);
    if(count) memcpy(file->node->bytes+file->pos,bytes,count);
    file->pos+=count;
    if(file->pos>file->node->size) file->node->size=file->pos;
    return count;
}
static bool storage_file_seek(File* file,uint32_t offset,bool from_start) {
    assert(file->opened);
    if(fault.seek_path && strcmp(file->node->path,fault.seek_path)==0) {
        file->error=FSE_INTERNAL; return false;
    }
    size_t target=from_start?offset:file->pos+offset;
    if(target>file->node->size) {file->error=FSE_INTERNAL;return false;}
    file->pos=target; return true;
}
static FS_Error storage_file_get_error(File* file) {return file->error;}
static bool storage_file_sync(File* file) {
    assert(file->opened && file->access==FSAM_WRITE);
    syncs++;
    if(syncs==fault.sync_call) {file->error=FSE_INTERNAL;return false;}
    return true;
}
static bool storage_file_close(File* file) {
    bool fail=file->opened && fault.close_path &&
        strcmp(file->node->path,fault.close_path)==0;
    if(file->opened) {assert(file->node->open_count);file->node->open_count--;}
    file->opened=false;
    if(fail) file->error=FSE_INTERNAL;
    return !fail;
}
static void storage_file_free(File* file) {
    assert(!file->opened && handles>0); handles--; free(file);
}
static FS_Error storage_common_stat(Storage* owner,const char* path,FileInfo* info) {
    assert(owner==&storage);
    if(fault.stat_path && strcmp(path,fault.stat_path)==0) return FSE_INTERNAL;
    Node* node=lookup(path);
    if(!node) return FSE_NOT_EXIST;
    info->is_dir=node->is_dir;info->size=node->size;return FSE_OK;
}
static bool file_info_is_dir(const FileInfo* info) {return info->is_dir;}
static FS_Error storage_common_rename_safe(Storage* owner,const char* from,const char* to) {
    assert(owner==&storage);
    renames++;
    if(fault.rename_fail_mask & (1u<<(renames-1))) return FSE_INTERNAL;
    Node* node=lookup(from);
    if(!node) return FSE_NOT_EXIST;
    assert(!node->open_count);
    if(strcmp(from,to)==0) return FSE_OK;
    if(lookup(to)) return FSE_EXIST; /* the actual API promises no overwrite */
    assert(strlen(to)<sizeof(node->path));strcpy(node->path,to);return FSE_OK;
}
static FS_Error storage_common_remove(Storage* owner,const char* path) {
    assert(owner==&storage);
    Node* node=lookup(path);
    if(!node) return FSE_NOT_EXIST;
    assert(!node->open_count);node->exists=false;return FSE_OK;
}
"""


def production():
    source = (ROOT / "applications/union/flipnote/flipnote.c").read_text(
        encoding="utf-8"
    )
    defines = "\n".join(re.findall(r"^#define .*$", source, re.M))
    scales_begin = source.index("static const float SCALES[")
    scales = source[scales_begin : source.index(";", scales_begin) + 1]
    model_begin = source.index("typedef struct {")
    model = source[
        model_begin : source.index("} Model;", model_begin) + len("} Model;")
    ]
    names = (
        "lh",
        "vis",
        "fix_scroll",
        "index_file",
        "load_buf",
        "commit_staged",
        "save_virtual",
        "flush_and_reload",
        "insert_line_below",
        "delete_line",
    )
    functions = "\n".join(c_function(source, name) for name in names)
    utf8 = (ROOT / "applications/union/flipnote/flipnote_utf8.h").read_text(
        encoding="utf-8"
    )
    retained = "\n".join("(void)" + name + ";" for name in names)
    return (
        STORAGE
        + defines
        + "\n"
        + scales
        + "\n"
        + model
        + "\n"
        + utf8.replace("#pragma once", "")
        + functions
        + r"""
static void reset_case(void) {
    assert(records==0 && handles==0);
    memset(nodes,0,sizeof(nodes));memset(&fault,0,sizeof(fault));
    writes=syncs=renames=0;
"""
        + retained
        + r"""
    (void)put_bytes;(void)expect_bytes;
    (void)flipnote_utf8_next;(void)flipnote_utf8_floor;(void)flipnote_utf8_prev;
    assert(TOTAL_MAX_LINES==2000 && MAX_LINE==128 && BUFFER_LINES==80);
}
static void load_model(Model* m,const char* path,int start) {
    memset(m,0,sizeof(*m));
    assert(strlen(path)<sizeof(m->filename));strcpy(m->filename,path);
    m->scale=3;index_file(m,path);load_buf(m,path,start);m->cursor=start;
}
static void make_lines(char* target,size_t capacity,int count) {
    size_t pos=0;
    for(int i=0;i<count;i++) {
        int n=snprintf(target+pos,capacity-pos,"L%03d\n",i);
        assert(n>0 && (size_t)n<capacity-pos);pos+=(size_t)n;
    }
}
static void resources_closed(void) {assert(records==0 && handles==0);}
"""
    )


class FlipNoteStorageTests(unittest.TestCase):
    def run_c(self, body):
        # Reference helper entry points so per-test unused static code remains
        # checked by the compiler without changing or suppressing its warnings.
        native_test(
            production()
            + "\nint main(void) {\nreset_case();\n(void)load_model;(void)make_lines;\n"
            + body
            + "\nresources_closed();return 0;\n}\n"
        )

    def test_index_empty_unterminated_crlf_and_capacity(self):
        self.run_c(
            r"""
Model m={0};
put_bytes("/ext/a","",0);index_file(&m,"/ext/a");
assert(m.total==1 && m.source_total==1 && !m.read_only && m.offsets[0]==0);
load_buf(&m,"/ext/a",0);assert(m.buf_count==1 && m.buf[0][0]==0);
const char* values[]={"first","first\n","first\nlast","first\r\nlast\r\n"};
const int expected[]={1,1,2,2};
for(int i=0;i<4;i++) {
    put_bytes("/ext/a",values[i],strlen(values[i]));index_file(&m,"/ext/a");
    assert(m.total==expected[i] && m.source_total==expected[i] && !m.read_only);
    if(i==3) {assert(m.offsets[1]==7);load_buf(&m,"/ext/a",1);assert(strcmp(m.buf[0],"last")==0);}
}
char lines[4003];
for(int i=0;i<2001;i++) {lines[2*i]='x';lines[2*i+1]='\n';}
put_bytes("/ext/a",lines,4000);index_file(&m,"/ext/a");
assert(m.total==2000 && m.source_total==2000 && !m.read_only && m.offsets[1999]==3998);
load_buf(&m,"/ext/a",1999);assert(m.buf_count==1 && strcmp(m.buf[0],"x")==0);
put_bytes("/ext/a",lines,4001);index_file(&m,"/ext/a");
assert(m.total==2000 && m.read_only); /* unterminated 2001st line */
put_bytes("/ext/a",lines,4002);index_file(&m,"/ext/a");assert(m.total==2000 && m.read_only);
char fit[129];memset(fit,'a',127);fit[127]='\n';
put_bytes("/ext/a",fit,128);index_file(&m,"/ext/a");assert(!m.read_only);
fit[127]='a';fit[128]='\n';put_bytes("/ext/a",fit,129);index_file(&m,"/ext/a");assert(m.read_only);
const char binary[]={'a',0,'b','\n'};put_bytes("/ext/a",binary,sizeof(binary));
index_file(&m,"/ext/a");assert(m.read_only);
"""
        )

    def test_long_utf8_consumes_whole_line_and_readonly_blocks_mutation(self):
        self.run_c(
            r"""
char bytes[400];size_t n=0;
for(int i=0;i<42;i++){memcpy(bytes+n,"\xe4\xb8\xad",3);n+=3;}
memcpy(bytes+n,"\xf0\x9f\x98\x80",4);n+=4;
memcpy(bytes+n,"\xe6\x96\x87\nnext\n",9);n+=9;
put_bytes("/ext/a",bytes,n);
Model m;load_model(&m,"/ext/a",0);
assert(m.read_only && m.total==2 && m.buf_count==2);
assert(strlen(m.buf[0])==126 && memcmp(m.buf[0],bytes,126)==0);
assert(flipnote_utf8_floor(m.buf[0],strlen(m.buf[0]))==126);
assert(strcmp(m.buf[1],"next")==0);
m.dirty=true;Model before=m;insert_line_below(&m);delete_line(&m);
assert(memcmp(&m,&before,sizeof(m))==0);
assert(!save_virtual(&m,"/ext/a"));expect_bytes("/ext/a",bytes,n);
assert(m.dirty && !lookup(TMP_FILE));
"""
        )

    def test_virtual_insert_delete_keeps_unloaded_prefix_and_tail(self):
        self.run_c(
            r"""
char input[1000],expected[1000];make_lines(input,sizeof(input),120);
put_bytes("/ext/a",input,strlen(input));Model m;load_model(&m,"/ext/a",20);
assert(m.buf_count==80 && m.orig_end==100 && m.source_total==120);
m.cursor=30;delete_line(&m);assert(m.total==119 && m.buf_count==79);
m.cursor=40;insert_line_below(&m);strcpy(m.buf[m.cursor-m.buf_start],"\xe6\x96\xb0\xe8\xa1\x8c");
assert(m.total==120 && m.buf_count==80 && m.orig_end==100 && m.source_total==120);
size_t pos=0;
for(int i=0;i<120;i++) {
    if(i==30)continue;
    int wrote=snprintf(expected+pos,sizeof(expected)-pos,"L%03d\n",i);
    assert(wrote>0);pos+=(size_t)wrote;
    if(i==41){memcpy(expected+pos,"\xe6\x96\xb0\xe8\xa1\x8c\n",7);pos+=7;}
}
assert(save_virtual(&m,"/ext/a"));expect_bytes("/ext/a",expected,pos);
assert(!m.dirty && !m.save_failed && !m.is_new && !lookup("/ext/a.flipnote.bak"));
/* A net deletion changes total but the original tail still starts at orig_end. */
reset_case();make_lines(input,sizeof(input),102);
put_bytes("/ext/a",input,strlen(input));load_model(&m,"/ext/a",20);
m.cursor=22;delete_line(&m);delete_line(&m);
assert(m.total==100 && m.source_total==102 && m.orig_end==100);
pos=0;for(int i=0;i<102;i++)if(i!=22 && i!=23){
    int wrote=snprintf(expected+pos,sizeof(expected)-pos,"L%03d\n",i);assert(wrote>0);pos+=(size_t)wrote;
}
assert(save_virtual(&m,"/ext/a"));expect_bytes("/ext/a",expected,pos);assert(m.total==100);
"""
        )

    def test_save_as_and_new_file_preserve_source_and_state(self):
        self.run_c(
            r"""
const char original[]="\xe5\x8e\x9f\xe6\x96\x87\nlast";
put_bytes("/ext/a",original,sizeof(original)-1);Model m;load_model(&m,"/ext/a",0);
strcpy(m.buf[0],"changed");m.dirty=true;
assert(save_virtual(&m,"/ext/copy"));expect_bytes("/ext/a",original,sizeof(original)-1);
expect_bytes("/ext/copy","changed\nlast\n",13);
assert(strcmp(m.filename,"/ext/copy")==0 && !m.dirty && !m.is_new);
reset_case();memset(&m,0,sizeof(m));m.is_new=true;m.dirty=true;m.buf_count=1;m.total=1;
strcpy(m.buf[0],"new");assert(save_virtual(&m,"/ext/new"));
expect_bytes("/ext/new","new\n",4);assert(!m.is_new && !m.dirty && !m.save_failed);
"""
        )

    def test_save_io_faults_preserve_original_dirty_and_filename(self):
        self.run_c(
            r"""
char input[1000];make_lines(input,sizeof(input),120);
for(int kind=0;kind<10;kind++) {
    reset_case();put_bytes("/ext/a",input,strlen(input));Model m;load_model(&m,"/ext/a",20);
    strcpy(m.buf[0],"edit");m.dirty=true;
    Model before=m;
    switch(kind){
    case 0:fault.open_path="/ext/a";break;
    case 1:fault.open_path=TMP_FILE;break;
    case 2:fault.read_path="/ext/a";fault.read_after=30;break;
    case 3:fault.read_path="/ext/a";fault.read_after=m.offsets[100]+7;break;
    case 4:fault.short_write_call=1;break;
    case 5:fault.short_write_call=4;break;
    case 6:fault.sync_call=1;break;
    case 7:fault.close_path=TMP_FILE;break;
    case 8:fault.close_path="/ext/a";break;
    case 9:fault.seek_path="/ext/a";break;
    }
    assert(!save_virtual(&m,"/ext/a"));expect_bytes("/ext/a",input,strlen(input));
    assert(m.dirty && m.save_failed && !m.is_new);
    assert(strcmp(m.filename,before.filename)==0 && m.total==before.total && m.source_total==before.source_total);
    assert(m.buf_count==before.buf_count && memcmp(m.buf,before.buf,sizeof(m.buf))==0);
    assert(renames==0);resources_closed();
}
/* Failed save-as of a new note must retain its unsaved model state. */
reset_case();Model fresh={0};fresh.is_new=true;fresh.dirty=true;fresh.buf_count=1;fresh.total=1;
strcpy(fresh.filename,"unsaved");strcpy(fresh.buf[0],"keep");fault.sync_call=1;
assert(!save_virtual(&fresh,"/ext/new"));assert(!lookup("/ext/new"));
assert(fresh.is_new && fresh.dirty && fresh.save_failed && strcmp(fresh.filename,"unsaved")==0);
"""
        )

    def test_commit_existing_backup_rollback_and_recoverable_rollback_failure(self):
        self.run_c(
            r"""
put_bytes("/ext/a","original",8);put_bytes(TMP_FILE,"edited",6);
put_bytes("/ext/a.flipnote.bak","previous backup",15);
assert(!commit_staged(&storage,"/ext/a"));expect_bytes("/ext/a","original",8);
expect_bytes("/ext/a.flipnote.bak","previous backup",15);expect_bytes(TMP_FILE,"edited",6);
const unsigned masks[]={1,2,6}; /* backup move; install; install + rollback */
for(size_t i=0;i<sizeof(masks)/sizeof(masks[0]);i++) {
    unsigned mask=masks[i];
    reset_case();put_bytes("/ext/a","original",8);put_bytes(TMP_FILE,"edited",6);
    fault.rename_fail_mask=mask;
    assert(!commit_staged(&storage,"/ext/a"));expect_bytes(TMP_FILE,"edited",6);
    if(mask==6){assert(!lookup("/ext/a"));expect_bytes("/ext/a.flipnote.bak","original",8);}
    else{expect_bytes("/ext/a","original",8);assert(!lookup("/ext/a.flipnote.bak"));}
}
reset_case();put_bytes("/ext/a","original",8);put_bytes(TMP_FILE,"edited",6);
assert(commit_staged(&storage,"/ext/a"));expect_bytes("/ext/a","edited",6);
assert(!lookup(TMP_FILE) && !lookup("/ext/a.flipnote.bak"));
reset_case();put_bytes(TMP_FILE,"new",3);assert(commit_staged(&storage,"/ext/new"));
expect_bytes("/ext/new","new",3);assert(!lookup(TMP_FILE));
reset_case();put_bytes(TMP_FILE,"new",3);fault.stat_path="/ext/new";
assert(!commit_staged(&storage,"/ext/new"));assert(!lookup("/ext/new"));expect_bytes(TMP_FILE,"new",3);
"""
        )

    def test_save_rename_failure_keeps_dirty_and_recovery_bytes(self):
        self.run_c(
            r"""
const unsigned masks[]={1,2,6};
for(size_t i=0;i<sizeof(masks)/sizeof(masks[0]);i++) {
    unsigned mask=masks[i];
    reset_case();put_bytes("/ext/a","original\n",9);Model m;load_model(&m,"/ext/a",0);
    strcpy(m.buf[0],"edited");m.dirty=true;fault.rename_fail_mask=mask;
    assert(!save_virtual(&m,"/ext/a"));assert(m.dirty && m.save_failed && !m.is_new);
    assert(strcmp(m.filename,"/ext/a")==0 && strcmp(m.buf[0],"edited")==0);
    if(mask==6){assert(!lookup("/ext/a"));expect_bytes("/ext/a.flipnote.bak","original\n",9);}
    else expect_bytes("/ext/a","original\n",9);
}
reset_case();put_bytes("/ext/a","original\n",9);put_bytes("/ext/a.flipnote.bak","old",3);
Model m;load_model(&m,"/ext/a",0);strcpy(m.buf[0],"edited");m.dirty=true;
assert(!save_virtual(&m,"/ext/a"));assert(m.dirty && m.save_failed);
expect_bytes("/ext/a","original\n",9);expect_bytes("/ext/a.flipnote.bak","old",3);
"""
        )

    def test_load_and_index_read_failures_are_readonly_and_flush_failure_retains_buffer(
        self,
    ):
        self.run_c(
            r"""
put_bytes("/ext/a","one\ntwo\n",8);Model m={0};
fault.read_path="/ext/a";fault.read_after=4;index_file(&m,"/ext/a");assert(m.read_only);
memset(&fault,0,sizeof(fault));index_file(&m,"/ext/a");
fault.read_path="/ext/a";fault.read_after=5;load_buf(&m,"/ext/a",0);assert(m.read_only);
memset(&fault,0,sizeof(fault));load_model(&m,"/ext/a",0);fault.seek_path="/ext/a";
load_buf(&m,"/ext/a",1);assert(m.read_only && m.buf_count==1 && m.buf[0][0]==0);
memset(&fault,0,sizeof(fault));load_model(&m,"/ext/a",0);m.dirty=true;strcpy(m.buf[0],"edited");
m.cursor=100;fault.sync_call=1;assert(!flush_and_reload(&m,100));
assert(m.dirty && m.save_failed && m.buf_start==0 && m.buf_count==2 && m.cursor==1);
assert(strcmp(m.buf[0],"edited")==0);expect_bytes("/ext/a","one\ntwo\n",8);
"""
        )

    def test_utf8_navigation_and_invalid_bytes_use_actual_header(self):
        self.run_c(
            r"""
const char text[]="A\xe4\xb8\xad\xf0\x9f\x98\x80";
assert(strlen(text)==8);
assert(flipnote_utf8_next(text,0)==1 && flipnote_utf8_next(text,1)==4);
assert(flipnote_utf8_next(text,4)==8 && flipnote_utf8_next(text,8)==8);
assert(flipnote_utf8_floor(text,3)==1 && flipnote_utf8_floor(text,7)==4);
assert(flipnote_utf8_prev(text,8)==4 && flipnote_utf8_prev(text,4)==1 && flipnote_utf8_prev(text,1)==0);
const char malformed[]={'a',(char)0xc0,(char)0xaf,(char)0xe4,(char)0xb8,0};
for(size_t i=0;i<5;i++)assert(flipnote_utf8_next(malformed,i)==i+1);
for(size_t i=0;i<=5;i++)assert(flipnote_utf8_floor(malformed,i)==i);
"""
        )


if __name__ == "__main__":
    unittest.main()
