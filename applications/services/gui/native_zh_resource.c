#ifndef FURI_RAM_EXEC
#include "native_zh_resource.h"
#include "native_zh_resource_data.h"
#include <furi.h>
#include <storage/storage.h>
#include <string.h>

#define NATIVE_ZH_CACHE_COUNT 96
#define NATIVE_ZH_QUEUE_COUNT 64

typedef enum {
    GlyphEmpty,
    GlyphPending,
    GlyphReady,
    GlyphMissing
} GlyphState;
typedef struct {
    uint16_t code;
    GlyphState state;
    uint32_t age;
    uint8_t font[NATIVE_ZH_SINGLE_FONT_SIZE];
} GlyphEntry;

typedef struct {
    FuriMutex* mutex;
    FuriMessageQueue* requests;
    GlyphEntry entries[NATIVE_ZH_CACHE_COUNT];
    uint32_t age;
    bool reload;
    void (*redraw)(void*);
    void* context;
} NativeZhResource;

// A service-lifetime cache, bounded independently of the number of SD glyphs.
static NativeZhResource* resource;

static void native_zh_storage_event(const void* event, void* context) {
    const StorageEvent* storage_event = event;
    if(storage_event->type != StorageEventTypeCardMount &&
       storage_event->type != StorageEventTypeCardUnmount &&
       storage_event->type != StorageEventTypeCardMountError)
        return;
    NativeZhResource* instance = context;
    furi_mutex_acquire(instance->mutex, FuriWaitForever);
    instance->reload = true;
    furi_mutex_release(instance->mutex);
    const uint16_t wake = 0;
    // A full queue already guarantees the worker will observe reload.
    furi_message_queue_put(instance->requests, &wake, 0);
}

static bool native_zh_open(File* file) {
    static const uint8_t expected[64] = NATIVE_ZH_RESOURCE_HEADER;
    uint8_t header[64];
    bool valid =
        storage_file_open(file, EXT_PATH("locale/zh_cn.glyphs"), FSAM_READ, FSOM_OPEN_EXISTING);
    if(valid) {
        valid = storage_file_size(file) == NATIVE_ZH_RESOURCE_SIZE &&
                storage_file_read(file, header, sizeof(header)) == sizeof(header) &&
                memcmp(header, expected, sizeof(header)) == 0;
    }
    if(!valid) storage_file_close(file);
    return valid;
}

static int32_t native_zh_worker(void* context) {
    NativeZhResource* instance = context;
    Storage* storage = furi_record_open(RECORD_STORAGE);
    File* file = storage_file_alloc(storage);
    // Service and subscription live for the entire GUI service lifetime.
    furi_pubsub_subscribe(storage_get_pubsub(storage), native_zh_storage_event, instance);
    bool attempted_open = false;
    bool valid_file = false;
    while(true) {
        uint16_t code;
        furi_message_queue_get(instance->requests, &code, FuriWaitForever);
        furi_mutex_acquire(instance->mutex, FuriWaitForever);
        bool reload = instance->reload;
        instance->reload = false;
        if(reload) {
            for(size_t i = 0; i < NATIVE_ZH_CACHE_COUNT; ++i) {
                if(instance->entries[i].state == GlyphMissing)
                    instance->entries[i].state = GlyphEmpty;
            }
        }
        furi_mutex_release(instance->mutex);
        if(reload) {
            if(valid_file) storage_file_close(file);
            valid_file = attempted_open = false;
            instance->redraw(instance->context);
        }
        if(code == 0) continue;
        if(!attempted_open) {
            valid_file = native_zh_open(file);
            attempted_open = true;
        }
        uint32_t offset;
        uint8_t record[NATIVE_ZH_RECORD_SIZE];
        uint8_t font[NATIVE_ZH_SINGLE_FONT_SIZE];
        bool valid = valid_file && native_zh_record_offset(code, &offset) &&
                     storage_file_seek(file, offset, true) &&
                     storage_file_read(file, record, sizeof(record)) == sizeof(record) &&
                     native_zh_record_font(code, record, font);
        furi_mutex_acquire(instance->mutex, FuriWaitForever);
        for(size_t i = 0; i < NATIVE_ZH_CACHE_COUNT; ++i) {
            GlyphEntry* entry = &instance->entries[i];
            if(entry->state == GlyphPending && entry->code == code) {
                if(valid) memcpy(entry->font, font, sizeof(font));
                entry->state = valid ? GlyphReady : GlyphMissing;
                break;
            }
        }
        furi_mutex_release(instance->mutex);
        if(valid) instance->redraw(instance->context);
    }
    return 0;
}

void native_zh_resource_start(void (*redraw)(void*), void* context) {
    furi_check(!resource && redraw);
    NativeZhResource* instance = calloc(1, sizeof(NativeZhResource));
    instance->mutex = furi_mutex_alloc(FuriMutexTypeNormal);
    instance->requests = furi_message_queue_alloc(NATIVE_ZH_QUEUE_COUNT, sizeof(uint16_t));
    instance->redraw = redraw;
    instance->context = context;
    resource = instance;
    FuriThread* thread = furi_thread_alloc_ex("ZhGlyphs", 2048, native_zh_worker, instance);
    furi_thread_start(thread);
}

bool native_zh_resource_copy(uint16_t code, uint8_t font[NATIVE_ZH_SINGLE_FONT_SIZE]) {
    NativeZhResource* instance = resource;
    if(!instance) return false;
    furi_mutex_acquire(instance->mutex, FuriWaitForever);
    GlyphEntry* victim = NULL;
    uint32_t oldest = 0;
    ++instance->age;
    for(size_t i = 0; i < NATIVE_ZH_CACHE_COUNT; ++i) {
        GlyphEntry* entry = &instance->entries[i];
        if(entry->state != GlyphEmpty && entry->code == code) {
            entry->age = instance->age;
            bool ready = entry->state == GlyphReady;
            if(ready) memcpy(font, entry->font, NATIVE_ZH_SINGLE_FONT_SIZE);
            furi_mutex_release(instance->mutex);
            return ready;
        }
        uint32_t age = instance->age - entry->age;
        if(entry->state != GlyphPending && (!victim || entry->state == GlyphEmpty ||
                                            (victim->state != GlyphEmpty && age > oldest))) {
            victim = entry;
            oldest = age;
        }
    }
    if(victim && furi_message_queue_put(instance->requests, &code, 0) == FuriStatusOk) {
        victim->code = code;
        victim->age = instance->age;
        victim->state = GlyphPending;
    }
    furi_mutex_release(instance->mutex);
    return false;
}

void native_zh_placeholder(uint16_t code, uint8_t font[NATIVE_ZH_SINGLE_FONT_SIZE]) {
    uint8_t record[NATIVE_ZH_RECORD_SIZE] = {0};
    record[0] = code >> 8;
    record[1] = code;
    record[2] = 10;
    record[3] = 10;
    record[4] = 129;
    record[5] = 127;
    record[6] = 140;
    for(size_t y = 0; y < 10; ++y) {
        for(size_t x = 0; x < 10; ++x) {
            if(x == 0 || x == 9 || y == 0 || y == 9) {
                size_t bit = y * 10 + x;
                record[8 + bit / 8] |= 1u << (bit % 8);
            }
        }
    }
    furi_check(native_zh_record_font(code, record, font));
}
#endif
