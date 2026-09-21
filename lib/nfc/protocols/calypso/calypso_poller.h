#pragma once

#include "calypso.h"

#include <lib/nfc/protocols/iso14443_4b/iso14443_4b_poller.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief CalypsoPoller opaque type definition.
 */
typedef struct CalypsoPoller CalypsoPoller;

/**
 * @brief Enumeration of possible Calypso poller event types.
 */
typedef enum {
    CalypsoPollerEventTypeReadSuccess, /**< Card was read successfully. */
    CalypsoPollerEventTypeReadFailed, /**< Poller failed to read card. */
} CalypsoPollerEventType;

/**
 * @brief Calypso poller event data.
 */
typedef union {
    CalypsoError error; /**< Error code indicating card reading fail reason. */
} CalypsoPollerEventData;

/**
 * @brief Calypso poller event structure.
 */
typedef struct {
    CalypsoPollerEventType type;
    CalypsoPollerEventData* data;
} CalypsoPollerEvent;

/**
 * @brief Select the Calypso transit application (AID "1TIC.ICA") and parse the FCI.
 *
 * @param[in,out] instance pointer to the poller instance.
 * @returns CalypsoErrorNone on success, an error code otherwise.
 */
CalypsoError calypso_poller_select_application(CalypsoPoller* instance);

/**
 * @brief Read a single record from an Elementary File.
 *
 * @param[in,out] instance pointer to the poller instance.
 * @param[in] sfi short EF identifier.
 * @param[in] record_num 1-based record number.
 * @param[out] out buffer of at least CALYPSO_RECORD_SIZE bytes to receive the record.
 * @param[out] found set to true if the record exists (SW 9000), false otherwise.
 * @returns CalypsoErrorNone on a completed exchange (regardless of `found`), error on RF fault.
 */
CalypsoError calypso_poller_read_record(
    CalypsoPoller* instance,
    uint8_t sfi,
    uint8_t record_num,
    uint8_t* out,
    bool* found);

#ifdef __cplusplus
}
#endif
