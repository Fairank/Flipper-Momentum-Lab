"""Host regression for the SD glyph cache of the GUI service.

applications/services/gui/native_zh_resource.c is compiled unchanged and linked
with the record format next to it. The test calls its real entry points and runs
its real worker function. What cannot run on a host is replaced by the stubs
below: Furi mutex, message queue, thread, record and pubsub, and the storage
service, which serves a synthetic resource file. Their prototypes come from the
real firmware headers, so a stub that drifts from the API does not compile.

One thread of control. The simulated threads take turns where the worker waits
for a request, the only place where it sleeps, and longjmp() ends the worker
when the script of a scenario is over. This shows what the code does for a given
order of events. It does not show the absence of races, and it says nothing
about timing, stack use, FreeRTOS or FatFs. It replaces neither a firmware build
nor a look at a device.
"""

from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from generate_lab_font import Glyph, decode_glyph, parse_font

GUI = "applications/services/gui"
FORMAT_C = f"{GUI}/native_zh_resource_format.c"
SOURCE_NAME = "zh_cache.c"

# Scenarios of the C harness that a test below runs. One process per scenario:
# a scenario is one life of the GUI service.
RUN_SCENARIOS = []


def scenario(name):
    """Decorator of a test: runs one scenario and passes on what it printed."""

    def decorate(method):
        def test(self):
            output = self.run_harness(name)
            self.assertIn(f"PASS {name}", output.splitlines())
            method(self, output)

        test.__name__ = method.__name__
        test.__qualname__ = method.__qualname__
        test.__doc__ = method.__doc__
        RUN_SCENARIOS.append(name)
        return test

    return decorate


# Headers the production file asks for with <...>. They hold no declaration of
# their own for anything the production code calls: those come from the real
# headers included here.
STUB_HEADERS = {
    "furi.h": r"""/* TEST STUB written by scripts/tests/test_zh_cache.py: host stand-in for furi/furi.h.
 * Types and prototypes are the real ones; the test fakes the functions behind them. */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "furi/core/base.h"
#include "furi/core/message_queue.h"
#include "furi/core/mutex.h"
#include "furi/core/pubsub.h"
#include "furi/core/record.h"
#include "furi/core/thread.h"

/* storage.h names this type; its definition in furi/core/string.h needs m-string */
typedef struct FuriString FuriString;

/* furi/core/check.h reports through ARM registers. Same contract as the real macro: the
 * condition is evaluated once, a message may follow it, a failure does not return. */
_Noreturn void fake_check_failed(const char* condition, const char* file, int line);
#define FAKE_CHECK_CONDITION(condition, ...) (condition)
#define furi_check(...)                         \
    (FAKE_CHECK_CONDITION(__VA_ARGS__, 0) ?     \
         (void)0 :                              \
         fake_check_failed(#__VA_ARGS__, __FILE__, __LINE__))
""",
    "furi_config.h": r"""/* TEST STUB written by scripts/tests/test_zh_cache.py: the header of the f7 target */
#pragma once
#include "targets/f7/inc/furi_config.h"
""",
    "cmsis_compiler.h": r"""/* TEST STUB written by scripts/tests/test_zh_cache.py: CMSIS is ARM only.
 * furi/core/common_defines.h takes the fixed width integer types from it. */
#pragma once
#include <stdint.h>
""",
    "storage/storage.h": r"""/* TEST STUB written by scripts/tests/test_zh_cache.py: the real service header */
#pragma once
#include "applications/services/storage/storage.h"
""",
}

PRELUDE = r"""/* Host regression for applications/services/gui/native_zh_resource.c.
 * Written by scripts/tests/test_zh_cache.py: change it there. */
#undef NDEBUG
#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Test stubs of these names (STUB_HEADERS); they include the real Furi and storage headers */
#include <furi.h>
#include <storage/storage.h>

/* Generated description of the resource file, and the record format */
#include "applications/services/gui/native_zh_resource_data.h"
#include "applications/services/gui/native_zh_resource_format.h"

static const char* test_scenario = "";
static const char* test_note = "";
static unsigned test_phase;

static _Noreturn void fail_at(const char* file, int line, const char* format, ...)
    __attribute__((format(printf, 3, 4)));

static _Noreturn void fail_at(const char* file, int line, const char* format, ...) {
    va_list arguments;
    fflush(stdout);
    fprintf(stderr, "%s:%d: scenario %s, phase %u", file, line, test_scenario, test_phase);
    if(test_note[0] != '\0') fprintf(stderr, " (%s)", test_note);
    fputs(": ", stderr);
    va_start(arguments, format);
    vfprintf(stderr, format, arguments);
    va_end(arguments);
    fputc('\n', stderr);
    abort();
}

#define FAIL(...) fail_at(__FILE__, __LINE__, __VA_ARGS__)
#define CHECK(condition) ((condition) ? (void)0 : FAIL("CHECK(%s) failed", #condition))

static void check_equal_at(
    const char* file,
    int line,
    const char* what,
    long long actual,
    long long expected) {
    if(actual != expected) {
        fail_at(file, line, "%s is %lld, expected %lld", what, actual, expected);
    }
}

#define CHECK_EQUAL(actual, expected) \
    check_equal_at(__FILE__, __LINE__, #actual, (long long)(actual), (long long)(expected))
"""

FIXTURE = r"""
/* ===================================================================================
 * FIXTURE: a synthetic resource file on a synthetic card
 * =================================================================================== */

/* Layout written by scripts/generate_zh_resource.py: a 64 byte header, then one 32 byte
 * record for every code of U+3000..U+9FFF, then one for every code of U+FF01..U+FFEF */
#define FIXTURE_PATH "/ext/locale/zh_cn.glyphs"
#define FIXTURE_HEADER_SIZE 64u
#define FIXTURE_RECORD_SIZE 32u
#define FIXTURE_CJK_SLOTS 0x7000u
#define FIXTURE_SLOTS (FIXTURE_CJK_SLOTS + 0xEFu)
#define FIXTURE_FILE_SIZE (FIXTURE_HEADER_SIZE + FIXTURE_SLOTS * FIXTURE_RECORD_SIZE)
#define FONT_SIZE NATIVE_ZH_SINGLE_FONT_SIZE
#define NOWHERE UINT64_MAX

_Static_assert(FIXTURE_RECORD_SIZE == NATIVE_ZH_RECORD_SIZE, "record size of the file format");
_Static_assert(FIXTURE_FILE_SIZE == NATIVE_ZH_RESOURCE_SIZE, "size of the generated resource");

static const uint8_t fixture_header[FIXTURE_HEADER_SIZE] = NATIVE_ZH_RESOURCE_HEADER;

static bool fixture_has_slot(uint16_t code) {
    const uint32_t value = code;
    return (value >= 0x3000u && value <= 0x9FFFu) || (value >= 0xFF01u && value <= 0xFFEFu);
}

/* Where the record of a code is, by the layout above and not by the production code */
static uint64_t fixture_offset(uint16_t code) {
    const uint32_t value = code;
    if(!fixture_has_slot(code)) FAIL("U+%04X has no record in the resource file", (unsigned)value);
    const uint32_t slot = value >= 0xFF01u ? FIXTURE_CJK_SLOTS + (value - 0xFF01u) :
                                             value - 0x3000u;
    return FIXTURE_HEADER_SIZE + (uint64_t)slot * FIXTURE_RECORD_SIZE;
}

static uint16_t fixture_slot_code(uint32_t slot) {
    return (uint16_t)(slot < FIXTURE_CJK_SLOTS ? 0x3000u + slot :
                                                 0xFF01u + (slot - FIXTURE_CJK_SLOTS));
}

/* A glyph that differs for every code: size, offsets and pixels follow from the code.
 * synthetic_glyph() in the Python part of this test describes the same glyph. */
static void fixture_record(uint16_t code, uint8_t record[FIXTURE_RECORD_SIZE]) {
    const unsigned value = code;
    const unsigned width = 5u + value % 8u;
    const unsigned height = 6u + value / 8u % 7u;
    memset(record, 0, FIXTURE_RECORD_SIZE);
    record[0] = (uint8_t)(value >> 8);
    record[1] = (uint8_t)(value & 0xFFu);
    record[2] = (uint8_t)width;
    record[3] = (uint8_t)height;
    record[4] = (uint8_t)(128u + value % 3u);
    record[5] = (uint8_t)(126u + value % 2u);
    record[6] = (uint8_t)(128u + 12u);
    for(unsigned bit = 0; bit < width * height; ++bit) {
        if((bit * 7u + value) % 5u < 2u) {
            record[8u + bit / 8u] = (uint8_t)(record[8u + bit / 8u] | (1u << (bit % 8u)));
        }
    }
}

/* The font the cache has to hand out for a code of the synthetic file */
static void fixture_font(uint16_t code, uint8_t font[FONT_SIZE]) {
    uint8_t record[FIXTURE_RECORD_SIZE] = {0};
    fixture_record(code, record);
    if(!native_zh_record_font(code, record, font)) {
        FAIL("the fixture record of U+%04X is not valid", (unsigned)code);
    }
}

typedef struct {
    uint64_t offset;
    uint8_t bytes[FIXTURE_RECORD_SIZE];
} CardRecord;

#define CARD_RECORDS 24u

static struct {
    bool present; /* the resource file can be opened */
    uint64_t size;
    uint8_t header[FIXTURE_HEADER_SIZE];
    uint64_t short_read_at; /* a read that starts here returns one byte less than it could */
    uint64_t seek_fails_at; /* a seek to this place fails */
    CardRecord records[CARD_RECORDS]; /* records in place of the synthetic ones */
    unsigned record_count;
} card;

static void card_insert_intact(void) {
    memset(&card, 0, sizeof(card));
    card.present = true;
    card.size = FIXTURE_FILE_SIZE;
    memcpy(card.header, fixture_header, sizeof(card.header));
    card.short_read_at = NOWHERE;
    card.seek_fails_at = NOWHERE;
}

/* Puts a copy of the synthetic record on the card, for the caller to damage */
static CardRecord* card_replace_record(uint16_t code) {
    if(card.record_count == CARD_RECORDS) FAIL("more replaced records than the card holds");
    CardRecord* record = &card.records[card.record_count++];
    record->offset = fixture_offset(code);
    fixture_record(code, record->bytes);
    return record;
}

static void card_read_record(uint64_t slot, uint8_t record[FIXTURE_RECORD_SIZE]) {
    const uint64_t offset = FIXTURE_HEADER_SIZE + slot * FIXTURE_RECORD_SIZE;
    for(unsigned i = 0; i < card.record_count; ++i) {
        if(card.records[i].offset == offset) {
            memcpy(record, card.records[i].bytes, FIXTURE_RECORD_SIZE);
            return;
        }
    }
    if(slot < FIXTURE_SLOTS) {
        fixture_record(fixture_slot_code((uint32_t)slot), record);
    } else {
        memset(record, 0, FIXTURE_RECORD_SIZE);
    }
}
"""

PLATFORM_STUBS = r"""
/* ===================================================================================
 * PLATFORM STUBS: fake Furi and fake storage service
 *
 * Everything from here to the production code stands in for firmware that cannot run on
 * a host. The prototypes are those of the real headers.
 *
 * One thread of control. The worker runs until it waits for a request while the queue is
 * empty. There the script of the scenario acts for the GUI thread and for the storage
 * service, then the worker goes on. When the script is over, longjmp() leaves the worker,
 * which has no other way out of its loop. A storage event reaches the subscriber at once
 * and on the thread that publishes it, as with furi_pubsub_publish().
 * =================================================================================== */

typedef enum {
    ThreadTest, /* the test, outside of any firmware thread */
    ThreadGui, /* GUI service: starts the glyph service and draws */
    ThreadWorker, /* glyph worker of the production code */
    ThreadStorage, /* publisher of storage events */
} FakeThread;

static FakeThread fake_thread = ThreadTest;

static const char* fake_thread_name(void) {
    switch(fake_thread) {
    case ThreadGui:
        return "GUI";
    case ThreadWorker:
        return "worker";
    case ThreadStorage:
        return "storage event";
    default:
        return "test";
    }
}

static struct {
    unsigned mutex_acquires;
    unsigned queue_puts; /* calls of furi_message_queue_put() */
    unsigned queue_full; /* ... that a full queue turned away */
    unsigned queue_gets;
    uint32_t longest_put_timeout;
    unsigned record_opens;
    unsigned file_allocs;
    unsigned subscriptions;
    unsigned thread_starts;
} fake;

/* ---- furi/core/check.h ---- */

_Noreturn void fake_check_failed(const char* condition, const char* file, int line) {
    fail_at(file, line, "furi_check(%s) failed in the production code", condition);
}

/* ---- furi/core/mutex.h ---- */

struct FuriMutex {
    FuriMutexType type;
    bool held;
    FakeThread owner;
};

static struct FuriMutex fake_mutexes[2];
static unsigned fake_mutex_count;

static bool fake_mutex_held(void) {
    for(unsigned i = 0; i < fake_mutex_count; ++i) {
        if(fake_mutexes[i].held) return true;
    }
    return false;
}

FuriMutex* furi_mutex_alloc(FuriMutexType type) {
    if(fake_mutex_count == sizeof(fake_mutexes) / sizeof(fake_mutexes[0])) {
        FAIL("more mutexes than the stub provides");
    }
    FuriMutex* mutex = &fake_mutexes[fake_mutex_count++];
    mutex->type = type;
    mutex->held = false;
    mutex->owner = ThreadTest;
    return mutex;
}

FuriStatus furi_mutex_acquire(FuriMutex* instance, uint32_t timeout) {
    (void)timeout;
    if(instance == NULL) FAIL("furi_mutex_acquire() without mutex");
    /* The threads only take turns while no mutex is held, so a mutex that is held here was
     * taken by the thread that asks for it, which would wait for itself */
    if(instance->held) {
        FAIL("the %s thread acquires a mutex that is held already", fake_thread_name());
    }
    instance->held = true;
    instance->owner = fake_thread;
    fake.mutex_acquires++;
    return FuriStatusOk;
}

FuriStatus furi_mutex_release(FuriMutex* instance) {
    if(instance == NULL || !instance->held || instance->owner != fake_thread) {
        FAIL("the %s thread releases a mutex it does not hold", fake_thread_name());
    }
    instance->held = false;
    return FuriStatusOk;
}

/* ---- furi/core/message_queue.h ---- */

struct FuriMessageQueue {
    uint32_t capacity;
    uint32_t message_size;
    uint32_t count;
    uint32_t first;
    uint8_t bytes[1024];
};

static struct FuriMessageQueue fake_queues[1];
static unsigned fake_queue_count;

static jmp_buf fake_worker_exit;
/* Lets the other threads run while the worker sleeps; false when they have nothing left to do */
static bool (*fake_worker_sleeps)(void);

FuriMessageQueue* furi_message_queue_alloc(uint32_t msg_count, uint32_t msg_size) {
    if(msg_count == 0 || msg_size == 0) FAIL("furi_message_queue_alloc() of an empty queue");
    if(fake_queue_count == sizeof(fake_queues) / sizeof(fake_queues[0]) ||
       (uint64_t)msg_count * msg_size > sizeof(fake_queues[0].bytes)) {
        FAIL("more message queue than the stub provides");
    }
    FuriMessageQueue* queue = &fake_queues[fake_queue_count++];
    memset(queue, 0, sizeof(*queue));
    queue->capacity = msg_count;
    queue->message_size = msg_size;
    return queue;
}

/* Status codes as in furi/core/message_queue.c */
FuriStatus
    furi_message_queue_put(FuriMessageQueue* instance, const void* msg_ptr, uint32_t timeout) {
    if(instance == NULL) FAIL("furi_message_queue_put() without queue");
    if(msg_ptr == NULL) return FuriStatusErrorParameter;
    /* A draw and a storage event must not wait for room, nor may anyone who holds a mutex */
    if(timeout != 0 && (fake_thread != ThreadWorker || fake_mutex_held())) {
        FAIL("the %s thread would wait for room in the queue", fake_thread_name());
    }
    if(timeout > fake.longest_put_timeout) fake.longest_put_timeout = timeout;
    fake.queue_puts++;
    if(instance->count == instance->capacity) {
        fake.queue_full++;
        return timeout != 0 ? FuriStatusErrorTimeout : FuriStatusErrorResource;
    }
    const uint32_t slot = (instance->first + instance->count) % instance->capacity;
    memcpy(&instance->bytes[slot * instance->message_size], msg_ptr, instance->message_size);
    instance->count++;
    return FuriStatusOk;
}

FuriStatus furi_message_queue_get(FuriMessageQueue* instance, void* msg_ptr, uint32_t timeout) {
    if(instance == NULL || msg_ptr == NULL) FAIL("furi_message_queue_get() without queue or buffer");
    if(fake_thread != ThreadWorker) {
        FAIL("the %s thread waits for glyph requests", fake_thread_name());
    }
    if(fake_mutex_held()) FAIL("the worker waits for a request while it holds a mutex");
    if(timeout != FuriWaitForever) {
        FAIL("the stub models a worker that waits for requests without a time limit");
    }
    if(++fake.queue_gets > 100000u) FAIL("the worker does not come to rest");
    while(instance->count == 0) {
        /* The worker sleeps: the other threads have their turn */
        fake_thread = ThreadTest;
        const bool more = fake_worker_sleeps != NULL && fake_worker_sleeps();
        fake_thread = ThreadWorker;
        /* Nothing will arrive any more */
        if(!more) longjmp(fake_worker_exit, 1);
    }
    memcpy(
        msg_ptr, &instance->bytes[instance->first * instance->message_size], instance->message_size);
    instance->first = (instance->first + 1) % instance->capacity;
    instance->count--;
    return FuriStatusOk;
}

/* ---- furi/core/thread.h ---- */

struct FuriThread {
    const char* name;
    uint32_t stack_size;
    FuriThreadCallback callback;
    void* context;
    bool started;
};

static struct FuriThread fake_worker;
static unsigned fake_thread_allocs;

FuriThread* furi_thread_alloc_ex(
    const char* name,
    uint32_t stack_size,
    FuriThreadCallback callback,
    void* context) {
    if(fake_thread_allocs++ != 0) FAIL("a second thread is created");
    if(callback == NULL) FAIL("furi_thread_alloc_ex() without callback");
    fake_worker.name = name;
    fake_worker.stack_size = stack_size;
    fake_worker.callback = callback;
    fake_worker.context = context;
    fake_worker.started = false;
    return &fake_worker;
}

/* The thread does not run here: the test runs its callback when the scenario says so */
void furi_thread_start(FuriThread* thread) {
    if(thread != &fake_worker || thread->started) {
        FAIL("furi_thread_start() of a thread that is not new");
    }
    thread->started = true;
    fake.thread_starts++;
}

/* ---- furi/core/record.h, furi/core/pubsub.h, storage/storage.h ---- */

struct Storage {
    unsigned users;
};

struct FuriPubSub {
    unsigned subscribers;
};

struct FuriPubSubSubscription {
    FuriPubSubCallback callback;
    void* context;
};

struct File {
    bool allocated;
    bool open;
    bool close_owed; /* storage.h: storage_file_close() has to follow a failed open as well */
    uint64_t position;
};

static struct Storage fake_storage;
static struct FuriPubSub fake_pubsub;
static struct FuriPubSubSubscription fake_subscription;
static struct File fake_file;

typedef enum { IoOpen, IoClose, IoSize, IoSeek, IoRead, IoKinds } IoKind;

typedef struct {
    IoKind kind;
    uint64_t position; /* IoSeek: where to, IoRead: where the read started */
    uint64_t length; /* IoRead: bytes asked for */
    uint64_t result; /* success, size of the file or bytes read */
} IoCall;

#define IO_LOG_SIZE 4096u

static IoCall io_log[IO_LOG_SIZE]; /* every call of a file function, in order */
static unsigned io_count;
static unsigned io_calls[IoKinds];
static const char* const io_names[IoKinds] = {"open", "close", "size", "seek", "read"};

static void io_note(IoKind kind, uint64_t position, uint64_t length, uint64_t result) {
    if(io_count == IO_LOG_SIZE) FAIL("more than %u storage calls", IO_LOG_SIZE);
    io_log[io_count].kind = kind;
    io_log[io_count].position = position;
    io_log[io_count].length = length;
    io_log[io_count].result = result;
    io_count++;
    io_calls[kind]++;
}

/* Calls that wait for the storage service, or for a lock that is held while storage events
 * are delivered: for the worker only, and not with a mutex held. A storage event comes
 * from the thread these calls wait for, and a draw must not wait for the card. */
static void fake_waiting_call(const char* function) {
    if(fake_thread != ThreadWorker) {
        FAIL("%s() on the %s thread; only the worker may wait for storage", function,
             fake_thread_name());
    }
    if(fake_mutex_held()) FAIL("%s() while a mutex is held", function);
}

static void fake_file_call(const char* function, const File* file) {
    fake_waiting_call(function);
    if(file != &fake_file || !fake_file.allocated) {
        FAIL("%s() with a file that storage_file_alloc() did not return", function);
    }
}

void* furi_record_open(const char* name) {
    fake_waiting_call("furi_record_open");
    if(name == NULL || strcmp(name, RECORD_STORAGE) != 0) {
        FAIL("furi_record_open() of a record other than the storage service");
    }
    fake.record_opens++;
    fake_storage.users++;
    return &fake_storage;
}

FuriPubSub* storage_get_pubsub(Storage* storage) {
    if(storage != &fake_storage) FAIL("storage_get_pubsub() without the storage record");
    return &fake_pubsub;
}

FuriPubSubSubscription*
    furi_pubsub_subscribe(FuriPubSub* pubsub, FuriPubSubCallback callback, void* callback_context) {
    fake_waiting_call("furi_pubsub_subscribe");
    if(pubsub != &fake_pubsub || callback == NULL) {
        FAIL("furi_pubsub_subscribe() without the storage pubsub or without callback");
    }
    if(fake.subscriptions++ != 0) FAIL("a second subscription to storage events");
    fake_pubsub.subscribers++;
    fake_subscription.callback = callback;
    fake_subscription.context = callback_context;
    return &fake_subscription;
}

/* What furi_pubsub_publish() does for the storage service: the subscriber runs on the
 * thread that publishes */
static void fake_publish(StorageEventType type) {
    if(fake_subscription.callback == NULL) FAIL("a storage event without subscriber");
    const FakeThread publisher = fake_thread;
    const unsigned calls = io_count;
    StorageEvent event = {.type = type};
    fake_thread = ThreadStorage;
    fake_subscription.callback(&event, fake_subscription.context);
    fake_thread = publisher;
    if(fake_mutex_held()) FAIL("the storage event handler returned with a mutex held");
    if(io_count != calls) FAIL("the storage event handler called the storage service");
}

File* storage_file_alloc(Storage* storage) {
    fake_waiting_call("storage_file_alloc");
    if(storage != &fake_storage || fake_file.allocated) {
        FAIL("storage_file_alloc(): the stub has one file, for the storage record");
    }
    fake_file.allocated = true;
    fake.file_allocs++;
    return &fake_file;
}

bool storage_file_open(
    File* file,
    const char* path,
    FS_AccessMode access_mode,
    FS_OpenMode open_mode) {
    fake_file_call("storage_file_open", file);
    if(file->open) {
        FAIL("storage_file_open() of an open file; the real call waits until it is closed");
    }
    if(file->close_owed) FAIL("storage_file_open() after a failed open that was not closed");
    if(path == NULL || strcmp(path, FIXTURE_PATH) != 0) {
        FAIL("storage_file_open(\"%s\"), expected " FIXTURE_PATH, path != NULL ? path : "");
    }
    if(access_mode != FSAM_READ || open_mode != FSOM_OPEN_EXISTING) {
        FAIL("the resource file is opened to be written or created");
    }
    file->open = card.present;
    file->close_owed = !card.present;
    file->position = 0;
    io_note(IoOpen, 0, 0, file->open);
    return file->open;
}

bool storage_file_close(File* file) {
    fake_file_call("storage_file_close", file);
    const bool was_open = file->open;
    file->open = false;
    file->close_owed = false;
    io_note(IoClose, 0, 0, was_open);
    /* storage_process_file_close() tells every subscriber, while the caller waits */
    if(was_open && fake_subscription.callback != NULL) fake_publish(StorageEventTypeFileClose);
    return was_open;
}

uint64_t storage_file_size(File* file) {
    fake_file_call("storage_file_size", file);
    const uint64_t size = file->open && card.present ? card.size : 0;
    io_note(IoSize, 0, 0, size);
    return size;
}

bool storage_file_seek(File* file, uint32_t offset, bool from_start) {
    fake_file_call("storage_file_seek", file);
    const uint64_t target = from_start ? offset : file->position + offset;
    const bool moved = file->open && card.present && target != card.seek_fails_at;
    /* FatFs ends a seek in a file that is open for reading at the end of the file */
    if(moved) file->position = target < card.size ? target : card.size;
    io_note(IoSeek, target, 0, moved);
    return moved;
}

size_t storage_file_read(File* file, void* buff, size_t bytes_to_read) {
    fake_file_call("storage_file_read", file);
    if(buff == NULL) FAIL("storage_file_read() without buffer");
    const uint64_t start = file->position;
    size_t readable = 0;
    if(file->open && card.present && start < card.size) {
        readable = bytes_to_read;
        if(card.size - start < readable) readable = (size_t)(card.size - start);
        if(start == card.short_read_at && readable > 0) readable--;
    }
    uint8_t* bytes = buff;
    uint8_t record[FIXTURE_RECORD_SIZE] = {0};
    uint64_t record_slot = NOWHERE;
    /* What a read does not deliver is neither zero nor what the buffer held before */
    memset(bytes, 0xEE, bytes_to_read);
    for(size_t i = 0; i < readable; ++i) {
        const uint64_t position = start + i;
        if(position < FIXTURE_HEADER_SIZE) {
            bytes[i] = card.header[position];
        } else {
            const uint64_t slot = (position - FIXTURE_HEADER_SIZE) / FIXTURE_RECORD_SIZE;
            if(slot != record_slot) {
                card_read_record(slot, record);
                record_slot = slot;
            }
            bytes[i] = record[(position - FIXTURE_HEADER_SIZE) % FIXTURE_RECORD_SIZE];
        }
    }
    file->position = start + readable;
    io_note(IoRead, start, bytes_to_read, readable);
    return readable;
}
"""

PRODUCTION = r"""
/* ===================================================================================
 * PRODUCTION CODE, compiled as it is
 * =================================================================================== */
#include "applications/services/gui/native_zh_resource.c"
"""

HARNESS = r"""
/* ===================================================================================
 * TEST HARNESS
 * =================================================================================== */

#define CACHE_ENTRIES ((unsigned)NATIVE_ZH_CACHE_COUNT)
#define QUEUE_ENTRIES ((unsigned)NATIVE_ZH_QUEUE_COUNT)
#define UNTOUCHED 0xA5

/* More entries than requests: a request always finds an entry that is not waiting. The
 * scenarios fill the cache in two rounds of requests. */
_Static_assert(NATIVE_ZH_QUEUE_COUNT < NATIVE_ZH_CACHE_COUNT, "queue smaller than the cache");
_Static_assert(NATIVE_ZH_CACHE_COUNT <= 2 * NATIVE_ZH_QUEUE_COUNT, "cache filled in two rounds");

static int gui_token; /* stands for the Gui that gui_srv() passes */
static unsigned redraws;
static unsigned redraw_io[256]; /* storage calls made before each of the first redraws */

/* Stand-in for gui_zh_redraw() of gui.c */
static void redraw_stub(void* context) {
    if(context != &gui_token) FAIL("redraw with a context other than the one given at start");
    if(fake_thread == ThreadGui) FAIL("a draw asks for a redraw: every frame would cause one");
    if(fake_mutex_held()) FAIL("a redraw is asked for while a mutex is held");
    if(redraws < sizeof(redraw_io) / sizeof(redraw_io[0])) redraw_io[redraws] = io_count;
    redraws++;
}

/* ---- The cache of the production code; the test only reads it ---- */

static const GlyphEntry* cache_find(uint16_t code) {
    const GlyphEntry* found = NULL;
    for(size_t i = 0; i < NATIVE_ZH_CACHE_COUNT; ++i) {
        const GlyphEntry* entry = &resource->entries[i];
        if(entry->state == GlyphEmpty || entry->code != code) continue;
        if(found != NULL) FAIL("U+%04X has two cache entries", (unsigned)code);
        found = entry;
    }
    return found;
}

static GlyphState cache_state(uint16_t code) {
    const GlyphEntry* entry = cache_find(code);
    if(entry == NULL) FAIL("U+%04X has no cache entry", (unsigned)code);
    return entry->state;
}

static unsigned cache_count(GlyphState state) {
    unsigned count = 0;
    for(size_t i = 0; i < NATIVE_ZH_CACHE_COUNT; ++i) {
        if(resource->entries[i].state == state) count++;
    }
    return count;
}

static uint16_t queue_code(const FuriMessageQueue* queue, uint32_t index) {
    uint16_t code = 0;
    const uint32_t slot = (queue->first + index) % queue->capacity;
    memcpy(&code, &queue->bytes[slot * queue->message_size], sizeof(code));
    return code;
}

/* A request in the queue for every entry that waits and the other way round, none twice.
 * An entry without request would wait for ever; a request without entry is wasted. */
static void check_requests_match_pending(void) {
    const FuriMessageQueue* queue = resource->requests;
    unsigned requests = 0;
    CHECK_EQUAL(queue->message_size, sizeof(uint16_t));
    for(uint32_t i = 0; i < queue->count; ++i) {
        const uint16_t code = queue_code(queue, i);
        if(code == 0) continue; /* wake message of a storage event */
        const GlyphEntry* entry = cache_find(code);
        if(entry == NULL || entry->state != GlyphPending) {
            FAIL("the request for U+%04X has no waiting cache entry", (unsigned)code);
        }
        for(uint32_t k = 0; k < i; ++k) {
            if(queue_code(queue, k) == code) FAIL("U+%04X was queued twice", (unsigned)code);
        }
        requests++;
    }
    CHECK_EQUAL(cache_count(GlyphPending), requests);
}

/* ---- Drawing ---- */

typedef enum { DrawReady, DrawQueued, DrawTurnedAway, DrawQuiet } Draw;

static const char* const draw_names[] = {
    "glyph copied",
    "nothing copied, request queued",
    "nothing copied, request turned away by the full queue",
    "nothing copied, nothing requested",
};

/* native_zh_resource_copy() as the GUI thread calls it while it draws */
static Draw draw_into(uint16_t code, uint8_t font[FONT_SIZE]) {
    const FakeThread caller = fake_thread;
    const unsigned calls = io_count, gets = fake.queue_gets, puts = fake.queue_puts;
    const unsigned full = fake.queue_full, asked = redraws;
    const uint32_t waiting = resource != NULL ? resource->requests->count : 0;
    fake_thread = ThreadGui;
    const bool ready = native_zh_resource_copy(code, font);
    fake_thread = caller;
    /* A draw does not call the storage service, does not wait and does not cause a redraw */
    CHECK_EQUAL(io_count, calls);
    CHECK_EQUAL(fake.queue_gets, gets);
    CHECK_EQUAL(fake.longest_put_timeout, 0);
    CHECK_EQUAL(redraws, asked);
    CHECK(!fake_mutex_held());
    if(resource != NULL) check_requests_match_pending();
    if(ready) {
        CHECK_EQUAL(fake.queue_puts, puts);
        return DrawReady;
    }
    if(fake.queue_puts == puts) return DrawQuiet;
    CHECK_EQUAL(fake.queue_puts, puts + 1);
    if(fake.queue_full != full) {
        CHECK_EQUAL(resource->requests->count, waiting);
        return DrawTurnedAway;
    }
    CHECK_EQUAL(resource->requests->count, waiting + 1);
    return DrawQueued;
}

static void expect_draw_at(const char* file, int line, uint16_t code, Draw expected) {
    uint8_t font[FONT_SIZE], glyph[FONT_SIZE] = {0};
    memset(font, UNTOUCHED, sizeof(font));
    const Draw outcome = draw_into(code, font);
    if(outcome != expected) {
        fail_at(
            file,
            line,
            "draw of U+%04X: %s; expected: %s",
            (unsigned)code,
            draw_names[outcome],
            draw_names[expected]);
    }
    if(outcome == DrawReady) {
        fixture_font(code, glyph);
        if(memcmp(font, glyph, sizeof(font)) != 0) {
            fail_at(file, line, "U+%04X: the copy is not the glyph of the file", (unsigned)code);
        }
        return;
    }
    for(size_t i = 0; i < sizeof(font); ++i) {
        if(font[i] != UNTOUCHED) {
            fail_at(file, line, "U+%04X: nothing was copied, yet the buffer changed",
                    (unsigned)code);
        }
    }
}

#define EXPECT_READY(code) expect_draw_at(__FILE__, __LINE__, code, DrawReady)
#define EXPECT_QUEUED(code) expect_draw_at(__FILE__, __LINE__, code, DrawQueued)
#define EXPECT_TURNED_AWAY(code) expect_draw_at(__FILE__, __LINE__, code, DrawTurnedAway)
#define EXPECT_QUIET(code) expect_draw_at(__FILE__, __LINE__, code, DrawQuiet)

/* native_zh_placeholder() needs no lock, no queue and no card */
static void make_placeholder(uint16_t code, uint8_t font[FONT_SIZE]) {
    const FakeThread caller = fake_thread;
    const unsigned calls = io_count, locks = fake.mutex_acquires, puts = fake.queue_puts;
    fake_thread = ThreadGui;
    native_zh_placeholder(code, font);
    fake_thread = caller;
    CHECK_EQUAL(io_count, calls);
    CHECK_EQUAL(fake.mutex_acquires, locks);
    CHECK_EQUAL(fake.queue_puts, puts);
    CHECK_EQUAL(font[29], code >> 8);
    CHECK_EQUAL(font[30], code & 0xFF);
}

/* One frame of a screen with `count` glyphs, drawn like canvas_glyph_draw() in canvas.c.
 * Returns how many of them were drawn as placeholder. */
static unsigned draw_frame(uint16_t first, unsigned count) {
    unsigned placeholders = 0;
    for(unsigned i = 0; i < count; ++i) {
        const uint16_t code = (uint16_t)(first + i);
        uint8_t font[FONT_SIZE];
        memset(font, UNTOUCHED, sizeof(font));
        if(draw_into(code, font) != DrawReady) {
            make_placeholder(code, font);
            placeholders++;
        }
    }
    return placeholders;
}

/* For the Python part of this test, which decodes fonts without the production code */
static void print_font(const char* label, uint16_t code, const uint8_t font[FONT_SIZE]) {
    printf("%s %04X ", label, (unsigned)code);
    for(size_t i = 0; i < FONT_SIZE; ++i) printf("%02x", (unsigned)font[i]);
    printf("\n");
}

/* ---- Storage calls ---- */

static void expect_io_at(
    const char* file,
    int line,
    unsigned index,
    IoKind kind,
    uint64_t position,
    uint64_t length,
    uint64_t result) {
    if(index >= io_count) {
        fail_at(file, line, "storage call %u was not made, there were %u", index, io_count);
    }
    const IoCall* call = &io_log[index];
    if(call->kind != kind || call->position != position || call->length != length ||
       call->result != result) {
        fail_at(
            file,
            line,
            "storage call %u is %s at %llu, length %llu, result %llu; expected %s at %llu, "
            "length %llu, result %llu",
            index,
            io_names[call->kind],
            (unsigned long long)call->position,
            (unsigned long long)call->length,
            (unsigned long long)call->result,
            io_names[kind],
            (unsigned long long)position,
            (unsigned long long)length,
            (unsigned long long)result);
    }
}

#define EXPECT_IO(index, kind, position, length, result) \
    expect_io_at(__FILE__, __LINE__, index, kind, position, length, result)

/* Reads of glyph records, as opposed to reads of the header */
static unsigned records_read(void) {
    unsigned count = 0;
    for(unsigned i = 0; i < io_count; ++i) {
        if(io_log[i].kind == IoRead && io_log[i].position >= FIXTURE_HEADER_SIZE) count++;
    }
    return count;
}

/* The file was opened and, before anything else, checked: its size and its whole header */
static void expect_checked_open(unsigned first) {
    CHECK(io_count >= first + 3);
    EXPECT_IO(first, IoOpen, 0, 0, 1);
    const unsigned size = io_log[first + 1].kind == IoSize ? first + 1 : first + 2;
    const unsigned header = size == first + 1 ? first + 2 : first + 1;
    EXPECT_IO(size, IoSize, 0, 0, FIXTURE_FILE_SIZE);
    EXPECT_IO(header, IoRead, 0, FIXTURE_HEADER_SIZE, FIXTURE_HEADER_SIZE);
}

static void expect_record_read(unsigned first, uint16_t code) {
    EXPECT_IO(first, IoSeek, fixture_offset(code), 0, 1);
    EXPECT_IO(first + 1, IoRead, fixture_offset(code), FIXTURE_RECORD_SIZE, FIXTURE_RECORD_SIZE);
}

/* ---- One life of the service ---- */

typedef struct {
    const char* name;
    void (*before_start)(void); /* the card, and whatever else happens before the service */
    void (*before_worker)(void); /* what the GUI does before the new thread runs */
    bool (*script)(unsigned phase);
    unsigned phases;
} Scenario;

static const Scenario* scenario;

static void start_service(void) {
    fake_thread = ThreadGui;
    native_zh_resource_start(redraw_stub, &gui_token);
    fake_thread = ThreadTest;
    CHECK(resource != NULL);
    CHECK_EQUAL(fake_mutex_count, 1);
    CHECK_EQUAL(fake_mutexes[0].type, FuriMutexTypeNormal);
    CHECK(!fake_mutex_held());
    CHECK_EQUAL(fake_queue_count, 1);
    CHECK_EQUAL(fake_queues[0].capacity, NATIVE_ZH_QUEUE_COUNT);
    CHECK_EQUAL(fake_queues[0].message_size, sizeof(uint16_t));
    CHECK_EQUAL(fake_thread_allocs, 1);
    CHECK_EQUAL(fake.thread_starts, 1);
    CHECK(fake_worker.context != NULL && fake_worker.stack_size > 0);
    /* The GUI service does not wait for the storage service or for the card to start */
    CHECK_EQUAL(fake.record_opens + fake.file_allocs + fake.subscriptions, 0);
    CHECK_EQUAL(fake.queue_puts + fake.queue_gets, 0);
    CHECK_EQUAL(io_count, 0);
}

/* The worker rests: every request was answered, every card event was seen, nothing is held */
static bool worker_sleeps(void) {
    CHECK(!fake_mutex_held());
    CHECK_EQUAL(resource->requests->count, 0);
    CHECK_EQUAL(cache_count(GlyphPending), 0);
    CHECK(!resource->reload);
    CHECK(!fake_file.close_owed);
    if(!scenario->script(test_phase)) return false;
    test_phase++;
    return true;
}

/* No variable of this function may change between setjmp() and longjmp(): it has none */
static void run_worker(void) {
    if(setjmp(fake_worker_exit) == 0) {
        fake_thread = ThreadWorker;
        fake_worker.callback(fake_worker.context);
        FAIL("the worker returned; nobody would answer requests any more");
    }
    fake_thread = ThreadTest;
}
"""

SCENARIO_CODE = r"""
/* ===================================================================================
 * SCENARIOS
 *
 * A script is what the other threads do while the worker sleeps: phase 0 when it first
 * comes to rest, the next phase when it has answered all that the phase before asked for.
 * =================================================================================== */

#define ZHONG 0x4E2D
#define WEN 0x6587

static void no_card(void) {
    card.present = false;
}

/* ---- lifecycle: start of the service and of its worker ---- */

static void lifecycle_before_start(void) {
    uint8_t font[FONT_SIZE];
    memset(font, UNTOUCHED, sizeof(font));
    /* A draw before the service exists gets nothing and touches nothing */
    CHECK(resource == NULL);
    CHECK_EQUAL(draw_into(ZHONG, font), DrawQuiet);
    for(size_t i = 0; i < sizeof(font); ++i) CHECK(font[i] == UNTOUCHED);
    CHECK_EQUAL(fake.mutex_acquires, 0);
    CHECK_EQUAL(fake_mutex_count + fake_queue_count + fake_thread_allocs, 0);
}

static void lifecycle_before_worker(void) {
    /* The GUI may draw before the new thread ran for the first time */
    EXPECT_QUEUED(ZHONG);
    EXPECT_QUIET(ZHONG);
    CHECK_EQUAL(fake.record_opens, 0);
    CHECK_EQUAL(io_count, 0);
}

static bool lifecycle_script(unsigned phase) {
    switch(phase) {
    case 0:
        /* The worker set itself up, then answered the request that was waiting */
        CHECK_EQUAL(fake.record_opens, 1);
        CHECK_EQUAL(fake.file_allocs, 1);
        CHECK_EQUAL(fake.subscriptions, 1);
        CHECK_EQUAL(redraws, 1);
        EXPECT_READY(ZHONG);
        return true;
    default:
        return false;
    }
}

/* ---- read_path: an intact file, from the open to the copy ---- */

static bool read_path_script(unsigned phase) {
    static const uint16_t edges[] = {0x3000, 0x9FFF, 0xFF01, 0xFFEF};
    const unsigned edge_count = sizeof(edges) / sizeof(edges[0]);
    uint8_t font[FONT_SIZE] = {0};
    switch(phase) {
    case 0:
        /* Nothing was asked for yet: the card has not been touched */
        CHECK_EQUAL(io_count, 0);
        EXPECT_QUEUED(ZHONG);
        return true;
    case 1:
        CHECK_EQUAL(io_count, 5);
        expect_checked_open(0);
        expect_record_read(3, ZHONG);
        CHECK_EQUAL(redraws, 1);
        EXPECT_READY(ZHONG);
        EXPECT_QUEUED(WEN);
        return true;
    case 2:
        /* The file stays open: another glyph costs one seek and one read */
        CHECK_EQUAL(io_count, 7);
        expect_record_read(5, WEN);
        CHECK_EQUAL(redraws, 2);
        EXPECT_READY(WEN);
        EXPECT_READY(ZHONG);
        for(unsigned i = 0; i < edge_count; ++i) EXPECT_QUEUED(edges[i]);
        return true;
    case 3:
        /* First and last record of both ranges; the very last one ends with the file */
        CHECK_EQUAL(io_count, 7 + 2 * edge_count);
        CHECK_EQUAL(fixture_offset(0x3000), FIXTURE_HEADER_SIZE);
        CHECK_EQUAL(fixture_offset(0xFFEF) + FIXTURE_RECORD_SIZE, NATIVE_ZH_RESOURCE_SIZE);
        for(unsigned i = 0; i < edge_count; ++i) {
            expect_record_read(7 + 2 * i, edges[i]);
            EXPECT_READY(edges[i]);
        }
        CHECK_EQUAL(redraws, 2 + edge_count);
        CHECK_EQUAL(io_calls[IoOpen], 1);
        CHECK_EQUAL(io_calls[IoClose], 0);
        /* For the Python part: the file as the worker wants it, and the fonts it handed out */
        printf("RESOURCE %s %llu ", FIXTURE_PATH, (unsigned long long)NATIVE_ZH_RESOURCE_SIZE);
        for(size_t i = 0; i < FIXTURE_HEADER_SIZE; ++i) printf("%02x", (unsigned)fixture_header[i]);
        printf("\n");
        CHECK_EQUAL(draw_into(ZHONG, font), DrawReady);
        print_font("GLYPH", ZHONG, font);
        CHECK_EQUAL(draw_into(WEN, font), DrawReady);
        print_font("GLYPH", WEN, font);
        for(unsigned i = 0; i < edge_count; ++i) {
            CHECK_EQUAL(draw_into(edges[i], font), DrawReady);
            print_font("GLYPH", edges[i], font);
        }
        return true;
    default:
        return false;
    }
}

/* ---- coalesce: a glyph that is on its way is not asked for again ---- */

static bool coalesce_script(unsigned phase) {
    switch(phase) {
    case 0:
        EXPECT_QUEUED(ZHONG);
        /* Frames drawn while the glyph is on its way */
        for(unsigned frame = 0; frame < 50; ++frame) EXPECT_QUIET(ZHONG);
        EXPECT_QUEUED(WEN);
        for(unsigned frame = 0; frame < 50; ++frame) {
            EXPECT_QUIET(ZHONG);
            EXPECT_QUIET(WEN);
        }
        CHECK_EQUAL(resource->requests->count, 2);
        CHECK_EQUAL(cache_count(GlyphPending), 2);
        CHECK_EQUAL(fake.queue_puts, 2);
        return true;
    case 1:
        /* One read per glyph, however often it was drawn in the meantime */
        CHECK_EQUAL(records_read(), 2);
        CHECK_EQUAL(redraws, 2);
        for(unsigned frame = 0; frame < 50; ++frame) {
            EXPECT_READY(ZHONG);
            EXPECT_READY(WEN);
        }
        CHECK_EQUAL(fake.queue_puts, 2);
        CHECK_EQUAL(records_read(), 2);
        return true;
    default:
        return false;
    }
}

/* ---- queue_bound: more requests than the queue holds ---- */

#define BOUND_QUEUED 0x4E00u
#define BOUND_EXTRA 0x5E00u
#define BOUND_EXTRAS 10u

static bool queue_bound_script(unsigned phase) {
    switch(phase) {
    case 0:
        for(unsigned i = 0; i < QUEUE_ENTRIES; ++i) EXPECT_QUEUED(BOUND_QUEUED + i);
        CHECK_EQUAL(resource->requests->count, QUEUE_ENTRIES);
        /* No room: the draw comes back at once and empty handed */
        for(unsigned i = 0; i < BOUND_EXTRAS; ++i) EXPECT_TURNED_AWAY(BOUND_EXTRA + i);
        CHECK_EQUAL(fake.queue_full, BOUND_EXTRAS);
        CHECK_EQUAL(fake.longest_put_timeout, 0);
        /* A request that was turned away left no entry behind that nobody would fill */
        CHECK_EQUAL(cache_count(GlyphPending), QUEUE_ENTRIES);
        for(unsigned i = 0; i < BOUND_EXTRAS; ++i) {
            CHECK(cache_find((uint16_t)(BOUND_EXTRA + i)) == NULL);
        }
        EXPECT_QUIET(BOUND_QUEUED);
        return true;
    case 1:
        for(unsigned i = 0; i < QUEUE_ENTRIES; ++i) EXPECT_READY(BOUND_QUEUED + i);
        /* The next frame asks again for what was turned away */
        for(unsigned i = 0; i < BOUND_EXTRAS; ++i) EXPECT_QUEUED(BOUND_EXTRA + i);
        return true;
    case 2:
        for(unsigned i = 0; i < BOUND_EXTRAS; ++i) EXPECT_READY(BOUND_EXTRA + i);
        for(unsigned i = 0; i < QUEUE_ENTRIES; ++i) EXPECT_READY(BOUND_QUEUED + i);
        CHECK_EQUAL(records_read(), QUEUE_ENTRIES + BOUND_EXTRAS);
        CHECK_EQUAL(redraws, QUEUE_ENTRIES + BOUND_EXTRAS);
        return true;
    default:
        return false;
    }
}

/* ---- lru: which glyph makes room ---- */

#define LRU_FIRST 0x4E00u
#define LRU_FRESH 0x6000u

static bool lru_script(unsigned phase) {
    switch(phase) {
    case 0:
        for(unsigned i = 0; i < QUEUE_ENTRIES; ++i) EXPECT_QUEUED(LRU_FIRST + i);
        return true;
    case 1:
        for(unsigned i = QUEUE_ENTRIES; i < CACHE_ENTRIES; ++i) EXPECT_QUEUED(LRU_FIRST + i);
        return true;
    case 2:
        /* Free entries were taken before anything was replaced: all glyphs are there */
        CHECK_EQUAL(cache_count(GlyphReady), CACHE_ENTRIES);
        /* Use them in order and the first one once more. The second is used least recently */
        for(unsigned i = 0; i < CACHE_ENTRIES; ++i) EXPECT_READY(LRU_FIRST + i);
        EXPECT_READY(LRU_FIRST);
        EXPECT_QUEUED(LRU_FRESH);
        CHECK(cache_find(LRU_FIRST + 1u) == NULL);
        CHECK_EQUAL(cache_count(GlyphReady), CACHE_ENTRIES - 1);
        CHECK_EQUAL(cache_state(LRU_FRESH), GlyphPending);
        /* Use all others again: the entry that waits for its glyph is the oldest one now */
        for(unsigned i = 2; i < CACHE_ENTRIES; ++i) EXPECT_READY(LRU_FIRST + i);
        EXPECT_READY(LRU_FIRST);
        EXPECT_QUEUED(LRU_FRESH + 1u);
        /* It is kept. The glyph used least recently makes room */
        CHECK_EQUAL(cache_state(LRU_FRESH), GlyphPending);
        CHECK_EQUAL(cache_state(LRU_FRESH + 1u), GlyphPending);
        CHECK(cache_find(LRU_FIRST + 2u) == NULL);
        CHECK_EQUAL(cache_count(GlyphReady), CACHE_ENTRIES - 2);
        return true;
    case 3:
        /* Both requests were answered, and nothing else was replaced */
        EXPECT_READY(LRU_FRESH);
        EXPECT_READY(LRU_FRESH + 1u);
        EXPECT_READY(LRU_FIRST);
        for(unsigned i = 3; i < CACHE_ENTRIES; ++i) EXPECT_READY(LRU_FIRST + i);
        /* What was replaced is loaded again when it is drawn again */
        EXPECT_QUEUED(LRU_FIRST + 1u);
        EXPECT_QUEUED(LRU_FIRST + 2u);
        return true;
    case 4:
        EXPECT_READY(LRU_FIRST + 1u);
        EXPECT_READY(LRU_FIRST + 2u);
        CHECK_EQUAL(cache_count(GlyphReady), CACHE_ENTRIES);
        return true;
    default:
        return false;
    }
}

/* ---- copy_isolation: a copy belongs to the caller ---- */

#define ISOLATION_OTHERS 0x5000u

static uint8_t isolation_asked[FONT_SIZE]; /* buffer of the draw that asked for the glyph */
static uint8_t isolation_copy[FONT_SIZE]; /* copy taken while the glyph was in the cache */
static size_t isolation_entry;

static bool copy_isolation_script(unsigned phase) {
    uint8_t glyph[FONT_SIZE] = {0}, scratch[FONT_SIZE];
    fixture_font(ZHONG, glyph);
    memset(scratch, UNTOUCHED, sizeof(scratch));
    switch(phase) {
    case 0:
        memset(isolation_asked, UNTOUCHED, sizeof(isolation_asked));
        CHECK_EQUAL(draw_into(ZHONG, isolation_asked), DrawQueued);
        return true;
    case 1:
        /* The glyph went into the cache, not into the buffer of the draw that asked */
        for(size_t i = 0; i < FONT_SIZE; ++i) CHECK(isolation_asked[i] == UNTOUCHED);
        CHECK_EQUAL(draw_into(ZHONG, scratch), DrawReady);
        CHECK(memcmp(scratch, glyph, FONT_SIZE) == 0);
        /* What a caller does to its copy does not reach the cache */
        memset(scratch, 0xFF, sizeof(scratch));
        CHECK_EQUAL(draw_into(ZHONG, isolation_copy), DrawReady);
        CHECK(memcmp(isolation_copy, glyph, FONT_SIZE) == 0);
        isolation_entry = (size_t)(cache_find(ZHONG) - resource->entries);
        /* Other glyphs fill the cache, in two rounds, until this one has to go */
        for(unsigned i = 0; i < QUEUE_ENTRIES; ++i) EXPECT_QUEUED(ISOLATION_OTHERS + i);
        return true;
    case 2:
        CHECK_EQUAL(cache_state(ZHONG), GlyphReady);
        for(unsigned i = QUEUE_ENTRIES; i < CACHE_ENTRIES; ++i) {
            EXPECT_QUEUED(ISOLATION_OTHERS + i);
        }
        return true;
    case 3: {
        /* Its entry holds another glyph now ... */
        const GlyphEntry* entry = &resource->entries[isolation_entry];
        CHECK(cache_find(ZHONG) == NULL);
        CHECK(entry->state == GlyphReady && entry->code != ZHONG);
        CHECK(memcmp(entry->font, glyph, FONT_SIZE) != 0);
        /* ... and the copy is still the glyph it was */
        CHECK(memcmp(isolation_copy, glyph, FONT_SIZE) == 0);
        for(size_t i = 0; i < FONT_SIZE; ++i) CHECK(isolation_asked[i] == UNTOUCHED);
        return true;
    }
    default:
        return false;
    }
}

/* ---- missing_resource: no file, placeholders, and no storm of retries ---- */

#define SCREEN_FIRST 0x4E00
#define SCREEN_GLYPHS 20u

static bool missing_resource_script(unsigned phase) {
    uint8_t font[FONT_SIZE] = {0};
    switch(phase) {
    case 0:
        /* First frame of a screen: every glyph is asked for and drawn as placeholder */
        CHECK_EQUAL(draw_frame(SCREEN_FIRST, SCREEN_GLYPHS), SCREEN_GLYPHS);
        CHECK_EQUAL(fake.queue_puts, SCREEN_GLYPHS);
        return true;
    case 1:
        /* One attempt to open the file served the whole screen. It was closed, as
         * storage.h demands after a failed open, and nothing asked for a redraw */
        CHECK_EQUAL(io_count, 2);
        EXPECT_IO(0, IoOpen, 0, 0, 0);
        EXPECT_IO(1, IoClose, 0, 0, 0);
        CHECK_EQUAL(redraws, 0);
        CHECK_EQUAL(cache_count(GlyphMissing), SCREEN_GLYPHS);
        /* The screen is drawn again and again: no request and no card access come of it */
        for(unsigned frame = 0; frame < 100; ++frame) {
            CHECK_EQUAL(draw_frame(SCREEN_FIRST, SCREEN_GLYPHS), SCREEN_GLYPHS);
        }
        CHECK_EQUAL(fake.queue_puts, SCREEN_GLYPHS);
        CHECK_EQUAL(resource->requests->count, 0);
        CHECK_EQUAL(io_count, 2);
        /* A glyph that was not on the screen before */
        EXPECT_QUEUED(WEN);
        return true;
    case 2:
        /* It is settled without another look at the card */
        CHECK_EQUAL(io_count, 2);
        CHECK_EQUAL(redraws, 0);
        EXPECT_QUIET(WEN);
        make_placeholder(WEN, font);
        print_font("PLACEHOLDER", WEN, font);
        make_placeholder(0xFF01, font);
        print_font("PLACEHOLDER", 0xFF01, font);
        return true;
    default:
        return false;
    }
}

/* ---- remount: card events make the worker look again ---- */

static bool remount_script(unsigned phase) {
    const uint16_t late = 0x5B57; /* first drawn when the card is out again */
    switch(phase) {
    case 0:
        EXPECT_QUEUED(ZHONG);
        EXPECT_QUEUED(WEN);
        return true;
    case 1:
        CHECK_EQUAL(io_calls[IoOpen], 1);
        EXPECT_QUIET(ZHONG);
        EXPECT_QUIET(WEN);
        /* A card with the resource file is inserted */
        card.present = true;
        fake_publish(StorageEventTypeCardMount);
        CHECK_EQUAL(resource->requests->count, 1);
        /* Nothing changes for the GUI until the worker has seen the event */
        EXPECT_QUIET(ZHONG);
        return true;
    case 2:
        /* The worker asked for a redraw, and that redraw asks for the glyphs again */
        CHECK_EQUAL(redraws, 1);
        CHECK_EQUAL(cache_count(GlyphMissing), 0);
        CHECK_EQUAL(io_calls[IoOpen], 1); /* no glyph was wanted yet */
        EXPECT_QUEUED(ZHONG);
        EXPECT_QUEUED(WEN);
        return true;
    case 3:
        CHECK_EQUAL(io_calls[IoOpen], 2);
        CHECK_EQUAL(records_read(), 2);
        CHECK_EQUAL(redraws, 3);
        EXPECT_READY(ZHONG);
        EXPECT_READY(WEN);
        /* The card is pulled out */
        card.present = false;
        fake_publish(StorageEventTypeCardUnmount);
        return true;
    case 4:
        /* The worker let go of the file. What was loaded is still there */
        CHECK_EQUAL(io_calls[IoClose], 2);
        CHECK(!fake_file.open);
        CHECK_EQUAL(redraws, 4);
        EXPECT_READY(ZHONG);
        EXPECT_READY(WEN);
        EXPECT_QUEUED(late);
        return true;
    case 5:
        CHECK_EQUAL(io_calls[IoOpen], 3);
        CHECK_EQUAL(io_calls[IoClose], 3);
        CHECK_EQUAL(redraws, 4);
        EXPECT_QUIET(late);
        /* A card that cannot be mounted is a reason to look again as well */
        fake_publish(StorageEventTypeCardMountError);
        return true;
    case 6:
        CHECK_EQUAL(redraws, 5);
        EXPECT_QUEUED(late);
        return true;
    case 7:
        CHECK_EQUAL(io_calls[IoOpen], 4);
        EXPECT_QUIET(late);
        /* Files and directories are closed all the time: no reason to try again */
        fake_publish(StorageEventTypeFileClose);
        fake_publish(StorageEventTypeDirClose);
        CHECK_EQUAL(resource->requests->count, 0);
        CHECK(!resource->reload);
        EXPECT_QUIET(late);
        EXPECT_READY(ZHONG);
        return true;
    default:
        return false;
    }
}

/* ---- invalid_file: a file that is not the generated resource ---- */

typedef struct {
    const char* what;
    void (*damage)(void);
} Damage;

static void damage_one_byte_short(void) {
    card.size = FIXTURE_FILE_SIZE - 1u;
}

static void damage_one_byte_long(void) {
    card.size = FIXTURE_FILE_SIZE + 1u;
}

static void damage_empty(void) {
    card.size = 0;
}

static void damage_header_only(void) {
    card.size = FIXTURE_HEADER_SIZE;
}

static void damage_size_beyond_32_bits(void) {
    card.size = (UINT64_C(1) << 32) + FIXTURE_FILE_SIZE;
}

static void damage_magic(void) {
    card.header[0] ^= 0x01;
}

static void damage_format_version(void) {
    card.header[5] = '1';
}

static void damage_source_hash(void) {
    card.header[39] ^= 0x80;
}

static void damage_record_size(void) {
    card.header[40] = 16;
}

static void damage_slot_count(void) {
    card.header[44] ^= 0x01;
}

static void damage_last_header_byte(void) {
    card.header[63] = 1;
}

static void damage_header_read(void) {
    card.short_read_at = 0;
}

static const Damage damages[] = {
    {"file one byte short", damage_one_byte_short},
    {"file one byte long", damage_one_byte_long},
    {"empty file", damage_empty},
    {"file that ends after the header", damage_header_only},
    {"size that is right in its low 32 bits only", damage_size_beyond_32_bits},
    {"other magic", damage_magic},
    {"other format version", damage_format_version},
    {"hash of another font", damage_source_hash},
    {"other record size", damage_record_size},
    {"other number of records", damage_slot_count},
    {"last header byte set", damage_last_header_byte},
    {"header read that ends early", damage_header_read},
};

#define DAMAGES ((unsigned)(sizeof(damages) / sizeof(damages[0])))
#define INVALID_FILE_ROUNDS (DAMAGES + 1u) /* every damaged file, then the intact one */

/* A round is one card: an even phase inserts it, the odd one after it draws */
static bool invalid_file_script(unsigned phase) {
    const unsigned round = phase / 2;
    if(phase > 2 * INVALID_FILE_ROUNDS) return false;
    if(phase % 2 == 1) {
        /* The worker forgot what it knew about the card and asked for a redraw, which
         * asks for the glyph again */
        CHECK_EQUAL(redraws, round + 1);
        EXPECT_QUEUED(ZHONG);
        return true;
    }
    if(round == INVALID_FILE_ROUNDS) {
        /* The intact file was accepted after all the others */
        EXPECT_READY(ZHONG);
        CHECK_EQUAL(io_calls[IoOpen], INVALID_FILE_ROUNDS);
        CHECK_EQUAL(io_calls[IoClose], DAMAGES);
        CHECK(fake_file.open);
        CHECK_EQUAL(records_read(), 1);
        CHECK_EQUAL(redraws, INVALID_FILE_ROUNDS + 1);
        return true;
    }
    if(round > 0) {
        /* The file of the round before was refused and closed; no record was read from it */
        test_note = damages[round - 1].what;
        EXPECT_QUIET(ZHONG);
        CHECK_EQUAL(cache_state(ZHONG), GlyphMissing);
        CHECK_EQUAL(io_calls[IoOpen], round);
        CHECK_EQUAL(io_calls[IoClose], round);
        CHECK(!fake_file.open);
        CHECK_EQUAL(io_calls[IoSeek], 0);
        CHECK_EQUAL(records_read(), 0);
        CHECK_EQUAL(redraws, round);
        test_note = "";
    }
    card_insert_intact();
    if(round < DAMAGES) damages[round].damage();
    fake_publish(StorageEventTypeCardMount);
    return true;
}

/* ---- malformed_records: an intact file with records that are not glyphs ---- */

typedef struct {
    const char* what;
    void (*damage)(CardRecord* record);
} BadRecord;

static void bad_other_glyph(CardRecord* record) {
    record->bytes[1] ^= 0x01;
}

static void bad_empty_slot(CardRecord* record) {
    memset(record->bytes, 0, sizeof(record->bytes));
}

static void bad_width(CardRecord* record) {
    record->bytes[2] = 13;
}

static void bad_height(CardRecord* record) {
    record->bytes[3] = 13;
}

static void bad_width_without_height(CardRecord* record) {
    record->bytes[3] = 0;
}

static void bad_height_without_width(CardRecord* record) {
    record->bytes[2] = 0;
}

static void bad_x_high(CardRecord* record) {
    record->bytes[4] = 128 + 16;
}

static void bad_x_low(CardRecord* record) {
    record->bytes[4] = 128 - 17;
}

static void bad_y_high(CardRecord* record) {
    record->bytes[5] = 128 + 16;
}

static void bad_y_low(CardRecord* record) {
    record->bytes[5] = 128 - 17;
}

static void bad_advance_low(CardRecord* record) {
    record->bytes[6] = 128 - 1;
}

static void bad_advance_high(CardRecord* record) {
    record->bytes[6] = 128 + 32;
}

static void bad_reserved_byte(CardRecord* record) {
    record->bytes[7] = 1;
}

static void bad_first_padding_byte(CardRecord* record) {
    record->bytes[26] = 1;
}

static void bad_last_padding_byte(CardRecord* record) {
    record->bytes[31] = 0x80;
}

static void bad_short_read(CardRecord* record) {
    card.short_read_at = record->offset;
}

static void bad_seek(CardRecord* record) {
    card.seek_fails_at = record->offset;
}

static const BadRecord bad_records[] = {
    {"record of another glyph", bad_other_glyph},
    {"empty slot", bad_empty_slot},
    {"width 13", bad_width},
    {"height 13", bad_height},
    {"width without height", bad_width_without_height},
    {"height without width", bad_height_without_width},
    {"x offset 16", bad_x_high},
    {"x offset -17", bad_x_low},
    {"y offset 16", bad_y_high},
    {"y offset -17", bad_y_low},
    {"advance -1", bad_advance_low},
    {"advance 32", bad_advance_high},
    {"reserved byte set", bad_reserved_byte},
    {"first padding byte set", bad_first_padding_byte},
    {"last padding byte set", bad_last_padding_byte},
    {"read that ends early", bad_short_read},
    {"seek that fails", bad_seek},
};

#define BAD_RECORDS ((unsigned)(sizeof(bad_records) / sizeof(bad_records[0])))
#define BAD_FIRST 0x5001u
#define GOOD_BEFORE (BAD_FIRST - 1u)
#define GOOD_AFTER (BAD_FIRST + BAD_RECORDS)

_Static_assert(sizeof(bad_records) / sizeof(bad_records[0]) <= CARD_RECORDS, "room on the card");

static void malformed_before_start(void) {
    for(unsigned i = 0; i < BAD_RECORDS; ++i) {
        bad_records[i].damage(card_replace_record((uint16_t)(BAD_FIRST + i)));
    }
}

static bool malformed_records_script(unsigned phase) {
    static const uint16_t outside[] = {0x00E9, 0x2FFF, 0xA000, 0xFF00, 0xFFF0};
    const unsigned outside_count = sizeof(outside) / sizeof(outside[0]);
    static unsigned calls;
    switch(phase) {
    case 0:
        /* A good glyph, the bad ones, and a good one after them */
        EXPECT_QUEUED(GOOD_BEFORE);
        for(unsigned i = 0; i < BAD_RECORDS; ++i) EXPECT_QUEUED(BAD_FIRST + i);
        EXPECT_QUEUED(GOOD_AFTER);
        return true;
    case 1:
        for(unsigned i = 0; i < BAD_RECORDS; ++i) {
            test_note = bad_records[i].what;
            EXPECT_QUIET(BAD_FIRST + i);
            CHECK_EQUAL(cache_state((uint16_t)(BAD_FIRST + i)), GlyphMissing);
        }
        test_note = "";
        /* The file is in order: it was not given up, and the good glyphs were loaded */
        EXPECT_READY(GOOD_BEFORE);
        EXPECT_READY(GOOD_AFTER);
        CHECK_EQUAL(redraws, 2);
        CHECK_EQUAL(io_calls[IoOpen], 1);
        CHECK_EQUAL(io_calls[IoClose], 0);
        /* Every record was looked for once. The one that could not be reached was not
         * read from wherever the file stood */
        CHECK_EQUAL(io_calls[IoSeek], BAD_RECORDS + 2);
        CHECK_EQUAL(records_read(), BAD_RECORDS + 1);
        calls = io_count;
        for(unsigned i = 0; i < outside_count; ++i) EXPECT_QUEUED(outside[i]);
        return true;
    case 2:
        /* Codes the file has no place for are settled without the card */
        CHECK_EQUAL(io_count, calls);
        for(unsigned i = 0; i < outside_count; ++i) {
            EXPECT_QUIET(outside[i]);
            CHECK_EQUAL(cache_state(outside[i]), GlyphMissing);
        }
        CHECK_EQUAL(redraws, 2);
        return true;
    default:
        return false;
    }
}

/* ---- storage_events: what the subscriber does on the thread of the storage service ---- */

static bool storage_events_script(unsigned phase) {
    switch(phase) {
    case 0:
        /* Files are closed all the time: nothing the worker has to know */
        fake_publish(StorageEventTypeFileClose);
        fake_publish(StorageEventTypeDirClose);
        CHECK_EQUAL(fake.queue_puts, 0);
        CHECK(!resource->reload);
        /* A card event wakes the worker with one message */
        fake_publish(StorageEventTypeCardMount);
        CHECK(resource->reload);
        CHECK_EQUAL(fake.queue_puts, 1);
        CHECK_EQUAL(resource->requests->count, 1);
        CHECK_EQUAL(fake.longest_put_timeout, 0);
        return true;
    case 1:
        CHECK_EQUAL(redraws, 1);
        CHECK_EQUAL(io_count, 0); /* no glyph is wanted, so the card is left alone */
        /* The card changes while the queue is full */
        for(unsigned i = 0; i < QUEUE_ENTRIES; ++i) EXPECT_QUEUED(0x4E00u + i);
        fake_publish(StorageEventTypeCardUnmount);
        CHECK_EQUAL(fake.queue_full, 1); /* no room for the wake message, no waiting for it */
        CHECK_EQUAL(fake.longest_put_timeout, 0);
        CHECK(resource->reload);
        CHECK_EQUAL(resource->requests->count, QUEUE_ENTRIES);
        return true;
    case 2:
        /* With the first request it took, and before it read anything, the worker looked
         * at the card anew */
        CHECK_EQUAL(redraws, 2 + QUEUE_ENTRIES);
        CHECK_EQUAL(redraw_io[1], 0);
        CHECK_EQUAL(io_calls[IoOpen], 1);
        for(unsigned i = 0; i < QUEUE_ENTRIES; ++i) EXPECT_READY(0x4E00u + i);
        return true;
    default:
        return false;
    }
}
"""

MAIN = r"""
/* ===================================================================================
 * One scenario per process: the production code keeps its service for good
 * =================================================================================== */

static const Scenario scenarios[] = {
    {"lifecycle", lifecycle_before_start, lifecycle_before_worker, lifecycle_script, 1},
    {"read_path", NULL, NULL, read_path_script, 4},
    {"coalesce", NULL, NULL, coalesce_script, 2},
    {"queue_bound", NULL, NULL, queue_bound_script, 3},
    {"lru", NULL, NULL, lru_script, 5},
    {"copy_isolation", NULL, NULL, copy_isolation_script, 4},
    {"missing_resource", no_card, NULL, missing_resource_script, 3},
    {"remount", no_card, NULL, remount_script, 8},
    {"invalid_file", NULL, NULL, invalid_file_script, 2 * INVALID_FILE_ROUNDS + 1},
    {"malformed_records", malformed_before_start, NULL, malformed_records_script, 3},
    {"storage_events", NULL, NULL, storage_events_script, 3},
};

int main(int argc, char** argv) {
    /* Windows host runs lost buffered stdout at exit, even for --list; explicit
     * flush/unbuffered probes passed. Keep PASS and font bytes observable. */
    CHECK(setvbuf(stdout, NULL, _IONBF, 0) == 0);
    const size_t count = sizeof(scenarios) / sizeof(scenarios[0]);
    if(argc == 2 && strcmp(argv[1], "--list") == 0) {
        for(size_t i = 0; i < count; ++i) printf("%s\n", scenarios[i].name);
        return 0;
    }
    for(size_t i = 0; argc == 2 && i < count; ++i) {
        if(strcmp(argv[1], scenarios[i].name) == 0) scenario = &scenarios[i];
    }
    if(scenario == NULL) {
        fprintf(stderr, "usage: %s --list | SCENARIO\n", argc > 0 ? argv[0] : "zh_cache");
        return 2;
    }
    test_scenario = scenario->name;

    card_insert_intact();
    if(scenario->before_start != NULL) scenario->before_start();
    start_service();
    if(scenario->before_worker != NULL) scenario->before_worker();
    fake_worker_sleeps = worker_sleeps;
    run_worker();

    /* The script ran to its end, and the service is set up once for its whole life */
    CHECK_EQUAL(test_phase, scenario->phases);
    CHECK_EQUAL(fake.record_opens, 1);
    CHECK_EQUAL(fake.file_allocs, 1);
    CHECK_EQUAL(fake.subscriptions, 1);
    CHECK_EQUAL(fake.thread_starts, 1);
    CHECK_EQUAL(fake_mutex_count, 1);
    CHECK_EQUAL(fake_queue_count, 1);
    CHECK_EQUAL(fake.longest_put_timeout, 0);
    CHECK(!fake_mutex_held());
    printf("PASS %s\n", scenario->name);
    return 0;
}
"""

SOURCE = (
    PRELUDE + FIXTURE + PLATFORM_STUBS + PRODUCTION + HARNESS + SCENARIO_CODE + MAIN
)


def synthetic_glyph(code):
    """The glyph fixture_record() of the C harness puts into the file for `code`."""
    width, height = 5 + code % 8, 6 + code // 8 % 7
    pixels = frozenset(
        (bit % width, bit // width)
        for bit in range(width * height)
        if (bit * 7 + code) % 5 < 2
    )
    return Glyph(width, height, code % 3, code % 2 - 2, 12, pixels, 0)


def placeholder_glyph():
    """The box native_zh_placeholder() draws: 10 x 10 pixels, one pixel thick."""
    pixels = frozenset(
        (x, y) for x in range(10) for y in range(10) if x in (0, 9) or y in (0, 9)
    )
    return Glyph(10, 10, 1, -1, 12, pixels, 0)


def printed_fonts(output, label):
    """{code: font bytes} of the lines the harness printed with `label`."""
    fonts = {}
    for line in output.splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[0] == label:
            fonts[int(fields[1], 16)] = bytes.fromhex(fields[2])
    return fonts


class ZhCacheTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = shutil.which("cc")
        if compiler is None:
            raise unittest.SkipTest("A host C compiler is required")
        directory = tempfile.TemporaryDirectory()
        cls.addClassCleanup(directory.cleanup)
        folder = Path(directory.name)
        stubs = folder / "stubs"
        for name, text in STUB_HEADERS.items():
            header = stubs / name
            header.parent.mkdir(parents=True, exist_ok=True)
            header.write_text(text, encoding="utf-8")
        source = folder / SOURCE_NAME
        source.write_text(SOURCE, encoding="utf-8")
        cls.executable = folder / "zh_cache"
        command = [compiler, "-std=c11", "-Wall", "-Wextra", "-Werror"]
        # The stubs first: <furi.h> and <storage/storage.h> must not come from elsewhere
        command += [f"-I{stubs}", "-I."]
        if sys.platform.startswith("linux"):
            command += [
                "-fsanitize=address,undefined",
                "-fno-sanitize-recover=all",
                "-fno-omit-frame-pointer",
                "-O1",
            ]
        # The record format is its own translation unit, as in the firmware
        command += [str(source), FORMAT_C, "-o", str(cls.executable)]
        # Run from the repository root so the production sources resolve
        build = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        if build.returncode != 0:
            raise AssertionError(
                f"Native regression failed to build:\n{build.stderr}"
                + cls.quoted_lines(build.stderr)
            )

    @staticmethod
    def quoted_lines(text):
        """The lines of the generated C source that compiler or harness point at."""
        lines = SOURCE.splitlines()
        numbers = sorted(
            {int(n) for n in re.findall(re.escape(SOURCE_NAME) + r":(\d+)", text)}
        )
        quoted = [
            f"{SOURCE_NAME}:{number}: {lines[number - 1].strip()}"
            for number in numbers
            if 0 < number <= len(lines)
        ]
        return "\n" + "\n".join(quoted) if quoted else ""

    def run_harness(self, argument):
        result = subprocess.run(
            [str(self.executable), argument],
            capture_output=True,
            text=True,
            timeout=120,
        )
        # The sanitizers stop at the first finding; their report must not get lost either
        if result.returncode != 0 or "runtime error" in result.stderr:
            self.fail(
                f"{argument} returned {result.returncode}:\n"
                f"{result.stdout}{result.stderr}" + self.quoted_lines(result.stderr)
            )
        return result.stdout

    def decoded(self, code, packed):
        """What u8g2 draws from the 128 byte font of one glyph, without the bit count."""
        self.assertEqual(len(packed), 128)
        size = 31 + packed[31]
        self.assertLessEqual(size, len(packed))
        self.assertFalse(any(packed[size:]), "bytes behind the font are not zero")
        font = parse_font(packed[:size])
        self.assertEqual((sorted(font.ascii), sorted(font.unicode)), ([], [code]))
        return decode_glyph(font.params, font.payload(code))._replace(bits=0)

    def test_every_scenario_of_the_harness_has_a_test(self):
        listed = self.run_harness("--list").split()
        self.assertEqual(sorted(listed), sorted(RUN_SCENARIOS))

    @scenario("lifecycle")
    def test_service_starts_without_waiting_for_storage(self, output):
        """Start allocates lock, queue and thread; only the worker turns to storage.

        A draw before the start gets nothing. A draw before the worker ran is
        queued and answered once the worker has set itself up.
        """

    @scenario("read_path")
    def test_intact_file_is_checked_read_and_handed_out(self, output):
        """Open, size and header check, one seek and one read per glyph, exact copy.

        The fonts handed out are decoded here without the production code.
        """
        fonts = printed_fonts(output, "GLYPH")
        self.assertEqual(
            sorted(fonts), sorted([0x4E2D, 0x6587, 0x3000, 0x9FFF, 0xFF01, 0xFFEF])
        )
        for code, packed in fonts.items():
            with self.subTest(f"U+{code:04X}"):
                self.assertEqual(self.decoded(code, packed), synthetic_glyph(code))
        # The file the worker opens and accepts is the one the GUI service ships
        described = [
            line.split() for line in output.splitlines() if line.startswith("RESOURCE ")
        ]
        self.assertEqual(len(described), 1)
        _, path, size, header = described[0]
        self.assertTrue(path.startswith("/ext/"), path)
        shipped = ROOT / GUI / "resources" / path[len("/ext/") :]
        self.assertTrue(shipped.is_file(), f"{shipped} is not shipped")
        self.assertEqual(shipped.stat().st_size, int(size))
        with shipped.open("rb") as file:
            self.assertEqual(file.read(64).hex(), header)

    @scenario("coalesce")
    def test_glyph_on_its_way_is_requested_once(self, output):
        """Draws of a pending glyph queue nothing; the glyph is read once."""

    @scenario("queue_bound")
    def test_full_queue_turns_requests_away_without_waiting(self, output):
        """A full queue refuses at once, leaves no entry behind, and recovers."""

    @scenario("lru")
    def test_least_recently_used_glyph_makes_room_and_waiting_ones_stay(self, output):
        """Free entries first, then the least recently used; never a pending one."""

    @scenario("copy_isolation")
    def test_copies_do_not_change_with_the_cache(self, output):
        """A copy survives the reuse of its entry; a caller's buffer is its own."""

    @scenario("missing_resource")
    def test_missing_file_gives_placeholders_without_retries(self, output):
        """One open attempt for any number of glyphs and frames, and no redraw.

        The placeholder is decoded here without the production code.
        """
        fonts = printed_fonts(output, "PLACEHOLDER")
        self.assertEqual(sorted(fonts), [0x6587, 0xFF01])
        for code, packed in fonts.items():
            with self.subTest(f"U+{code:04X}"):
                self.assertEqual(self.decoded(code, packed), placeholder_glyph())

    @scenario("remount")
    def test_card_events_make_missing_glyphs_retry(self, output):
        """Mount, unmount and mount error reset missing glyphs; close events do not."""

    @scenario("invalid_file")
    def test_file_with_wrong_size_or_header_is_refused(self, output):
        """Every damaged file is refused and closed; the intact one is accepted."""

    @scenario("malformed_records")
    def test_malformed_records_are_refused(self, output):
        """Bad records and failed reads give no glyph and do not cost the file."""

    @scenario("storage_events")
    def test_storage_events_flag_and_wake_without_storage_calls(self, output):
        """The subscriber never waits or calls storage, also with a full queue."""


if __name__ == "__main__":
    unittest.main()
