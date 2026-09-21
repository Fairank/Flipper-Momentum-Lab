#pragma once

#include "calypso_poller.h"

#include <lib/nfc/protocols/iso14443_4b/iso14443_4b_poller_i.h>

#ifdef __cplusplus
extern "C" {
#endif

// MAX Le is 255 bytes + 2 for SW
#define CALYPSO_POLLER_BUF_SIZE (512U)

typedef enum {
    CalypsoPollerStateIdle,
    CalypsoPollerStateSelectApplication,
    CalypsoPollerStateReadFiles,
    CalypsoPollerStateReadFailed,
    CalypsoPollerStateReadSuccess,

    CalypsoPollerStateNum,
} CalypsoPollerState;

typedef enum {
    CalypsoPollerSessionStateIdle,
    CalypsoPollerSessionStateActive,
    CalypsoPollerSessionStateStopRequest,
} CalypsoPollerSessionState;

struct CalypsoPoller {
    Iso14443_4bPoller* iso14443_4b_poller;
    CalypsoPollerSessionState session_state;
    CalypsoPollerState state;
    CalypsoError error;
    CalypsoData* data;
    BitBuffer* tx_buffer;
    BitBuffer* rx_buffer;
    CalypsoPollerEventData calypso_event_data;
    CalypsoPollerEvent calypso_event;
    NfcGenericEvent general_event;
    NfcGenericCallback callback;
    void* context;
};

CalypsoError calypso_process_error(Iso14443_4bError error);

const CalypsoData* calypso_poller_get_data(CalypsoPoller* instance);

#ifdef __cplusplus
}
#endif
