#pragma once

#include <nfc/protocols/nfc_device_base_i.h>
#include <lib/nfc/protocols/iso14443_4b/iso14443_4b.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @file calypso.h
 * @brief Calypso transit card protocol (ISO 14443-4 Type B, ISO 7816-4 file system).
 *
 * Calypso is the smart-card standard used by many transit networks (Intercode / RTIC).
 * The card exposes an ISO 7816-4 application selected by a DF name (AID) which in turn
 * contains a set of Elementary Files (EFs) addressed by a Short EF Identifier (SFI).
 * Each EF holds one or more fixed-size records read with the READ RECORD command.
 *
 * This implementation is intentionally generic: it stores whatever records were read
 * verbatim, and leaves interpretation of the Intercode data model to a supported-card
 * plugin (see plugins/supported_cards/ravkav.c for the Israeli RavKav card).
 *
 * @note Calypso runs on ISO 14443 Type B, which the Flipper NFC hardware can only poll,
 *       not emulate. Therefore no listener is provided and full RF emulation is not
 *       possible; reading and saving ("copying") to a .nfc file are supported.
 */

/** Standard Calypso/Intercode record size (READ RECORD Le). */
#define CALYPSO_RECORD_SIZE (0x1DU) // 29 bytes

/** Maximum AID length (ISO 7816-4 DF name). */
#define CALYPSO_AID_MAX_LEN (16U)

/** Maximum number of distinct EFs (SFIs) stored per card. */
#define CALYPSO_MAX_FILES (12U)

/** Maximum number of records stored per EF. */
#define CALYPSO_MAX_RECORDS (16U)

typedef enum {
    CalypsoErrorNone = 0,
    CalypsoErrorNotPresent,
    CalypsoErrorProtocol,
    CalypsoErrorTimeout,
} CalypsoError;

typedef struct {
    uint8_t sfi; /**< Short EF identifier. */
    uint8_t record_count; /**< Number of valid records stored below. */
    uint8_t records[CALYPSO_MAX_RECORDS][CALYPSO_RECORD_SIZE];
} CalypsoFile;

typedef struct {
    uint8_t aid[CALYPSO_AID_MAX_LEN];
    uint8_t aid_len;
    /**
     * Card serial number as returned in the SELECT FCI (Intercode places it at
     * offset 0x13..0x1A, two big-endian uint32s). Stored raw here.
     */
    uint8_t serial[8];
    bool serial_valid;
    uint8_t file_count;
    CalypsoFile files[CALYPSO_MAX_FILES];
} CalypsoApplication;

typedef struct {
    Iso14443_4bData* iso14443_4b_data;
    CalypsoApplication application;
} CalypsoData;

extern const NfcDeviceBase nfc_device_calypso;

// Virtual methods

CalypsoData* calypso_alloc(void);

void calypso_free(CalypsoData* data);

void calypso_reset(CalypsoData* data);

void calypso_copy(CalypsoData* data, const CalypsoData* other);

bool calypso_verify(CalypsoData* data, const FuriString* device_type);

bool calypso_load(CalypsoData* data, FlipperFormat* ff, uint32_t version);

bool calypso_save(const CalypsoData* data, FlipperFormat* ff);

bool calypso_is_equal(const CalypsoData* data, const CalypsoData* other);

const char* calypso_get_device_name(const CalypsoData* data, NfcDeviceNameType name_type);

const uint8_t* calypso_get_uid(const CalypsoData* data, size_t* uid_len);

bool calypso_set_uid(CalypsoData* data, const uint8_t* uid, size_t uid_len);

Iso14443_4bData* calypso_get_base_data(const CalypsoData* data);

// Getters

/**
 * @brief Find a stored EF by its SFI.
 *
 * @param[in] data pointer to the Calypso data instance.
 * @param[in] sfi short EF identifier to look up.
 * @returns pointer to the file if present, NULL otherwise.
 */
const CalypsoFile* calypso_get_file(const CalypsoData* data, uint8_t sfi);

/**
 * @brief Get a mutable EF by its SFI, allocating a new slot if needed.
 *
 * @param[in,out] data pointer to the Calypso data instance.
 * @param[in] sfi short EF identifier.
 * @returns pointer to the file, or NULL if no free slot is available.
 */
CalypsoFile* calypso_get_or_add_file(CalypsoData* data, uint8_t sfi);

#ifdef __cplusplus
}
#endif
