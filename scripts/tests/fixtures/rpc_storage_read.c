/* Platform substitutes record the real handler's output and allocation cleanup. */
#undef NDEBUG
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#define furi_assert                       assert
#define FURI_LOG_D(...)                   ((void)0)
#define TAG                               "RpcStorage"
#define MIN(a, b)                         ((a) < (b) ? (a) : (b))
#define PB_Main_storage_read_request_tag  9
#define PB_Main_storage_read_response_tag 10
#define PB_CommandStatus_OK               0
#define FSAM_READ                         0
#define FSOM_OPEN_EXISTING                0
static const size_t MAX_DATA_SIZE = 512;
typedef struct {
    uint16_t size;
    uint8_t bytes[1];
} Blob;
#define PB_BYTES_ARRAY_T_ALLOCSIZE(n) (sizeof(Blob) + (n))
typedef struct {
    int unused;
} RpcSession;
typedef struct {
    size_t pos;
} File;
typedef struct {
    RpcSession* session;
    void* api;
} RpcStorageSystem;
typedef struct {
    uint32_t command_id, which_content, command_status;
    bool has_next;
    union {
        struct {
            const char* path;
            uint32_t offset, size;
        } storage_read_request;
        struct {
            bool has_file;
            struct {
                Blob* data;
            } file;
            bool ranged;
        } storage_read_response;
    } content;
} PB_Main;
static const int PB_Main_msg = 0;
static File file;
static size_t file_size, received, allocations, freed, frames, errors, closes, reads, seeks;
static bool open_error, seek_error, short_read, finished;
static uint8_t output[4096];
static void* tracked_malloc(size_t n) {
    void* p = calloc(1, n);
    assert(p);
    allocations++;
    return p;
}
static void tracked_free(void* p) {
    if(p) {
        freed++;
        free(p);
    }
}
#define malloc tracked_malloc
#define free   tracked_free
static File* storage_file_alloc(void* api) {
    (void)api;
    file.pos = 0;
    return &file;
}
static bool storage_file_open(File* f, const char* path, int mode, int openmode) {
    (void)mode;
    (void)openmode;
    assert(f == &file && !strcmp(path, "/ext/test.bin"));
    return !open_error;
}
static size_t storage_file_size(File* f) {
    assert(f == &file);
    return file_size;
}
bool storage_file_seek(File* f, size_t off, bool from_start) {
    assert(f == &file && from_start && off <= file_size);
    seeks++;
    if(seek_error) return false;
    f->pos = off;
    return true;
}
static uint16_t storage_file_read(File* f, void* out, size_t n) {
    assert(f == &file && n <= file_size - f->pos && n <= 512);
    reads++;
    if(short_read && n) n--;
    for(size_t i = 0; i < n; i++)
        ((uint8_t*)out)[i] = (uint8_t)((f->pos + i) * 37 + 11);
    f->pos += n;
    return (uint16_t)n;
}
static void storage_file_close(File* f) {
    assert(f == &file);
    closes++;
}
static void storage_file_free(File* f) {
    assert(f == &file);
}
static void rpc_system_storage_reset_state(RpcStorageSystem* s, RpcSession* r, bool send_error) {
    assert(s->session == r && send_error);
}
static int rpc_system_storage_get_file_error(File* f) {
    assert(f == &file);
    return 7;
}
static void pb_release(const int* fields, PB_Main* p) {
    assert(fields == &PB_Main_msg);
    if(p->which_content == PB_Main_storage_read_response_tag) {
        free(p->content.storage_read_response.file.data);
        p->content.storage_read_response.file.data = NULL;
    }
}
static void rpc_send_and_release(RpcSession* s, PB_Main* p) {
    (void)s;
    assert(!finished && p->command_id == 41 && p->command_status == PB_CommandStatus_OK);
    assert(
        p->which_content == PB_Main_storage_read_response_tag &&
        p->content.storage_read_response.ranged);
    assert(p->content.storage_read_response.has_file);
    Blob* b = p->content.storage_read_response.file.data;
    assert(b && received + b->size <= sizeof(output));
    memcpy(output + received, b->bytes, b->size);
    received += b->size;
    frames++;
    finished = !p->has_next;
    pb_release(&PB_Main_msg, p);
}
static void rpc_send_and_release_empty(RpcSession* s, uint32_t id, int status) {
    (void)s;
    assert(id == 41 && status == 7);
    errors++;
}
/* PRODUCTION_HANDLER */
int main(int argc, char** argv) {
    assert(setvbuf(stdout, NULL, _IONBF, 0) == 0);
    assert(argc == 2);
    unsigned c = (unsigned)atoi(argv[1]);
    uint32_t offset = 0, size = 0;
    file_size = 2049;
    switch(c) {
    case 0:
        break;
    case 1:
        offset = 510;
        size = 700;
        break;
    case 2:
        offset = 1900;
        size = 1000;
        break;
    case 3:
        offset = 2049;
        size = 1;
        break;
    case 4:
        offset = UINT32_MAX;
        size = UINT32_MAX;
        break;
    case 5:
        file_size = 0;
        break;
    case 6:
        offset = 513;
        break;
    case 7:
        size = 1;
        break;
    case 8:
        open_error = true;
        break;
    case 9:
        offset = 1;
        seek_error = true;
        break;
    case 10:
        short_read = true;
        break;
    case 11:
        offset = 1;
        size = UINT32_MAX;
        break;
    default:
        return 2;
    }
    RpcSession session = {0};
    RpcStorageSystem storage = {.session = &session};
    PB_Main req = {
        .command_id = 41,
        .which_content = PB_Main_storage_read_request_tag,
        .content.storage_read_request = {.path = "/ext/test.bin", .offset = offset, .size = size}};
    rpc_system_storage_read_process(&req, &storage);
    assert(closes == 1 && allocations == freed);
    if(open_error || seek_error || short_read) {
        assert(errors == 1 && !frames);
    } else {
        size_t start = offset > file_size ? file_size : offset, expected = file_size - start;
        if(size && size < expected) expected = size;
        assert(
            !errors && finished && received == expected &&
            frames == (expected ? (expected + 511) / 512 : 1));
        for(size_t i = 0; i < received; i++)
            assert(output[i] == (uint8_t)((start + i) * 37 + 11));
        assert(reads == (expected ? (expected + 511) / 512 : 0));
    }
    puts("RPC read scenario passed");
    return 0;
}
