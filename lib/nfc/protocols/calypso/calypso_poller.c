#include "calypso_poller_i.h"

#include <nfc/protocols/nfc_poller_base.h>

#include <furi.h>

#define TAG "CalypsoPoller"

/**
 * Short EF identifiers scanned when reading a Calypso transit card.
 * This matches the Intercode / RTIC layout used by RavKav (Environment,
 * Event log, Contracts, Contract list, Counters and special events).
 * Each EF is read record-by-record until the card reports "record not found".
 */
static const uint8_t calypso_read_plan_sfi[] = {
    0x07, // Environment / Holder
    0x08, // Event log
    0x09, // Contracts
    0x19, // Contract list / counters pointer
    0x1D, // Counters / special events
    0x1E, // Counters / special events
};

typedef NfcCommand (*CalypsoPollerReadHandler)(CalypsoPoller* instance);

static CalypsoPoller* calypso_poller_alloc(Iso14443_4bPoller* iso14443_4b_poller) {
    CalypsoPoller* instance = malloc(sizeof(CalypsoPoller));
    instance->iso14443_4b_poller = iso14443_4b_poller;
    instance->data = calypso_alloc();
    instance->tx_buffer = bit_buffer_alloc(CALYPSO_POLLER_BUF_SIZE);
    instance->rx_buffer = bit_buffer_alloc(CALYPSO_POLLER_BUF_SIZE);

    instance->state = CalypsoPollerStateIdle;

    instance->calypso_event.data = &instance->calypso_event_data;

    instance->general_event.protocol = NfcProtocolCalypso;
    instance->general_event.event_data = &instance->calypso_event;
    instance->general_event.instance = instance;

    return instance;
}

static void calypso_poller_free(CalypsoPoller* instance) {
    furi_assert(instance);

    calypso_free(instance->data);
    bit_buffer_free(instance->tx_buffer);
    bit_buffer_free(instance->rx_buffer);
    free(instance);
}

static NfcCommand calypso_poller_handler_idle(CalypsoPoller* instance) {
    bit_buffer_reset(instance->tx_buffer);
    bit_buffer_reset(instance->rx_buffer);

    iso14443_4b_copy(
        instance->data->iso14443_4b_data,
        iso14443_4b_poller_get_data(instance->iso14443_4b_poller));

    instance->state = CalypsoPollerStateSelectApplication;
    return NfcCommandContinue;
}

static NfcCommand calypso_poller_handler_select_application(CalypsoPoller* instance) {
    instance->error = calypso_poller_select_application(instance);

    if(instance->error == CalypsoErrorNone) {
        FURI_LOG_D(TAG, "Select application success");
        instance->state = CalypsoPollerStateReadFiles;
    } else {
        FURI_LOG_E(TAG, "Failed to select application");
        instance->state = CalypsoPollerStateReadFailed;
    }

    return NfcCommandContinue;
}

static NfcCommand calypso_poller_handler_read_files(CalypsoPoller* instance) {
    uint8_t record[CALYPSO_RECORD_SIZE];

    for(size_t i = 0; i < COUNT_OF(calypso_read_plan_sfi); i++) {
        const uint8_t sfi = calypso_read_plan_sfi[i];
        CalypsoFile* file = NULL;

        for(uint8_t rec = 1; rec <= CALYPSO_MAX_RECORDS; rec++) {
            bool found = false;
            CalypsoError error = calypso_poller_read_record(instance, sfi, rec, record, &found);

            if(error != CalypsoErrorNone) {
                // A real RF error aborts the whole read
                instance->error = error;
                instance->state = CalypsoPollerStateReadFailed;
                return NfcCommandContinue;
            }
            if(!found) break; // end of this EF

            if(file == NULL) {
                file = calypso_get_or_add_file(instance->data, sfi);
                if(file == NULL) break; // no free slot, skip rest of file
            }
            if(file->record_count >= CALYPSO_MAX_RECORDS) break;

            memcpy(file->records[file->record_count], record, CALYPSO_RECORD_SIZE);
            file->record_count++;
        }
    }

    instance->state = CalypsoPollerStateReadSuccess;
    return NfcCommandContinue;
}

static NfcCommand calypso_poller_handler_read_fail(CalypsoPoller* instance) {
    FURI_LOG_D(TAG, "Read failed");
    iso14443_4b_poller_halt(instance->iso14443_4b_poller);
    instance->calypso_event.type = CalypsoPollerEventTypeReadFailed;
    instance->calypso_event.data->error = instance->error;
    NfcCommand command = instance->callback(instance->general_event, instance->context);
    instance->state = CalypsoPollerStateIdle;
    return command;
}

static NfcCommand calypso_poller_handler_read_success(CalypsoPoller* instance) {
    FURI_LOG_D(TAG, "Read success");
    iso14443_4b_poller_halt(instance->iso14443_4b_poller);
    instance->calypso_event.type = CalypsoPollerEventTypeReadSuccess;
    NfcCommand command = instance->callback(instance->general_event, instance->context);
    return command;
}

static const CalypsoPollerReadHandler calypso_poller_read_handler[CalypsoPollerStateNum] = {
    [CalypsoPollerStateIdle] = calypso_poller_handler_idle,
    [CalypsoPollerStateSelectApplication] = calypso_poller_handler_select_application,
    [CalypsoPollerStateReadFiles] = calypso_poller_handler_read_files,
    [CalypsoPollerStateReadFailed] = calypso_poller_handler_read_fail,
    [CalypsoPollerStateReadSuccess] = calypso_poller_handler_read_success,
};

static void calypso_poller_set_callback(
    CalypsoPoller* instance,
    NfcGenericCallback callback,
    void* context) {
    furi_assert(instance);
    furi_assert(callback);

    instance->callback = callback;
    instance->context = context;
}

static NfcCommand calypso_poller_run(NfcGenericEvent event, void* context) {
    furi_assert(event.protocol == NfcProtocolIso14443_4b);

    CalypsoPoller* instance = context;
    furi_assert(instance);
    furi_assert(instance->callback);

    const Iso14443_4bPollerEvent* iso14443_4b_event = event.event_data;
    furi_assert(iso14443_4b_event);

    NfcCommand command = NfcCommandContinue;

    if(iso14443_4b_event->type == Iso14443_4bPollerEventTypeReady) {
        command = calypso_poller_read_handler[instance->state](instance);
    } else if(iso14443_4b_event->type == Iso14443_4bPollerEventTypeError) {
        instance->calypso_event.type = CalypsoPollerEventTypeReadFailed;
        instance->calypso_event.data->error = CalypsoErrorNotPresent;
        command = instance->callback(instance->general_event, instance->context);
    }

    return command;
}

static bool calypso_poller_detect(NfcGenericEvent event, void* context) {
    furi_assert(event.protocol == NfcProtocolIso14443_4b);

    CalypsoPoller* instance = context;
    furi_assert(instance);

    const Iso14443_4bPollerEvent* iso14443_4b_event = event.event_data;
    furi_assert(iso14443_4b_event);

    bool protocol_detected = false;

    if(iso14443_4b_event->type == Iso14443_4bPollerEventTypeReady) {
        iso14443_4b_copy(
            instance->data->iso14443_4b_data,
            iso14443_4b_poller_get_data(instance->iso14443_4b_poller));
        const CalypsoError error = calypso_poller_select_application(instance);
        protocol_detected = (error == CalypsoErrorNone);
    }

    return protocol_detected;
}

const NfcPollerBase calypso_poller = {
    .alloc = (NfcPollerAlloc)calypso_poller_alloc,
    .free = (NfcPollerFree)calypso_poller_free,
    .set_callback = (NfcPollerSetCallback)calypso_poller_set_callback,
    .run = (NfcPollerRun)calypso_poller_run,
    .detect = (NfcPollerDetect)calypso_poller_detect,
    .get_data = (NfcPollerGetData)calypso_poller_get_data,
};
