#include "calypso_poller_i.h"

#include <furi.h>

#define TAG "CalypsoPoller"

// SELECT by DF name: AID = "1TIC.ICA" (standard Calypso / Intercode transit application)
static const uint8_t calypso_select_app_cmd[] = {
    0x00,
    0xA4, // SELECT
    0x04,
    0x00, // P1: by DF name, P2: first or only occurrence, return FCI
    0x08, // Lc
    0x31,
    0x54,
    0x49,
    0x43,
    0x2E,
    0x49,
    0x43,
    0x41, // "1TIC.ICA"
};

// Offset of the card serial number inside the SELECT FCI response
#define CALYPSO_FCI_SERIAL_OFFSET (0x13U)
#define CALYPSO_FCI_SERIAL_LEN    (8U)

CalypsoError calypso_process_error(Iso14443_4bError error) {
    switch(error) {
    case Iso14443_4bErrorNone:
        return CalypsoErrorNone;
    case Iso14443_4bErrorNotPresent:
        return CalypsoErrorNotPresent;
    case Iso14443_4bErrorTimeout:
        return CalypsoErrorTimeout;
    default:
        return CalypsoErrorProtocol;
    }
}

static void calypso_trace(CalypsoPoller* instance, const char* message) {
    if(furi_log_get_level() == FuriLogLevelTrace) {
        FURI_LOG_T(TAG, "%s", message);

        printf("TX: ");
        size_t size = bit_buffer_get_size_bytes(instance->tx_buffer);
        for(size_t i = 0; i < size; i++) {
            printf("%02X ", bit_buffer_get_byte(instance->tx_buffer, i));
        }
        printf("\r\nRX: ");
        size = bit_buffer_get_size_bytes(instance->rx_buffer);
        for(size_t i = 0; i < size; i++) {
            printf("%02X ", bit_buffer_get_byte(instance->rx_buffer, i));
        }
        printf("\r\n");
    }
}

/**
 * @brief Exchange one APDU and split off the trailing status word.
 *
 * @param[out] sw receives the 16-bit status word (SW1 << 8 | SW2), 0 if no SW present.
 * @returns Calypso error resulting from the RF exchange (not from the SW value).
 */
static CalypsoError calypso_poller_send_apdu(CalypsoPoller* instance, uint16_t* sw) {
    *sw = 0;

    Iso14443_4bError error = iso14443_4b_poller_send_block(
        instance->iso14443_4b_poller, instance->tx_buffer, instance->rx_buffer);
    if(error != Iso14443_4bErrorNone) {
        return calypso_process_error(error);
    }

    const size_t rx_size = bit_buffer_get_size_bytes(instance->rx_buffer);
    if(rx_size < 2) {
        // A valid ISO 7816-4 response must carry at least a status word
        return CalypsoErrorProtocol;
    }

    *sw = ((uint16_t)bit_buffer_get_byte(instance->rx_buffer, rx_size - 2) << 8) |
          bit_buffer_get_byte(instance->rx_buffer, rx_size - 1);
    return CalypsoErrorNone;
}

CalypsoError calypso_poller_select_application(CalypsoPoller* instance) {
    bit_buffer_reset(instance->tx_buffer);
    bit_buffer_reset(instance->rx_buffer);
    bit_buffer_copy_bytes(
        instance->tx_buffer, calypso_select_app_cmd, sizeof(calypso_select_app_cmd));

    uint16_t sw = 0;
    CalypsoError error = calypso_poller_send_apdu(instance, &sw);
    calypso_trace(instance, "SELECT 1TIC.ICA answer:");

    if(error != CalypsoErrorNone) {
        FURI_LOG_E(TAG, "SELECT application RF error %u", error);
        return error;
    }

    if(sw != 0x9000) {
        // 6A82 (not found) / 6283 (invalidated) => not a Calypso/RavKav card
        FURI_LOG_D(TAG, "SELECT application returned SW %04X", sw);
        return CalypsoErrorProtocol;
    }

    CalypsoApplication* app = &instance->data->application;
    app->aid_len = sizeof(calypso_select_app_cmd) - 5;
    memcpy(app->aid, &calypso_select_app_cmd[5], app->aid_len);

    // Parse the card serial from the FCI (data = response without the 2 SW bytes)
    const size_t fci_len = bit_buffer_get_size_bytes(instance->rx_buffer) - 2;
    if(fci_len >= CALYPSO_FCI_SERIAL_OFFSET + CALYPSO_FCI_SERIAL_LEN) {
        const uint8_t* fci = bit_buffer_get_data(instance->rx_buffer);
        memcpy(app->serial, &fci[CALYPSO_FCI_SERIAL_OFFSET], CALYPSO_FCI_SERIAL_LEN);
        app->serial_valid = true;
    }

    return CalypsoErrorNone;
}

CalypsoError calypso_poller_read_record(
    CalypsoPoller* instance,
    uint8_t sfi,
    uint8_t record_num,
    uint8_t* out,
    bool* found) {
    furi_assert(out);
    furi_assert(found);

    *found = false;

    const uint8_t read_record_cmd[] = {
        0x00,
        0xB2, // READ RECORD
        record_num, // P1: record number (1-based)
        (uint8_t)((sfi << 3) | 0x04), // P2: read record #P1 from EF with short id SFI
        CALYPSO_RECORD_SIZE, // Le
    };

    bit_buffer_reset(instance->tx_buffer);
    bit_buffer_reset(instance->rx_buffer);
    bit_buffer_copy_bytes(instance->tx_buffer, read_record_cmd, sizeof(read_record_cmd));

    uint16_t sw = 0;
    CalypsoError error = calypso_poller_send_apdu(instance, &sw);
    if(error != CalypsoErrorNone) {
        FURI_LOG_E(TAG, "READ RECORD SFI %02X rec %u RF error %u", sfi, record_num, error);
        return error;
    }

    // Wrong Le: re-issue with the length the card asks for
    if((sw >> 8) == 0x6C) {
        const uint8_t le = sw & 0xFF;
        uint8_t retry_cmd[sizeof(read_record_cmd)];
        memcpy(retry_cmd, read_record_cmd, sizeof(read_record_cmd));
        retry_cmd[4] = le;

        bit_buffer_reset(instance->tx_buffer);
        bit_buffer_reset(instance->rx_buffer);
        bit_buffer_copy_bytes(instance->tx_buffer, retry_cmd, sizeof(retry_cmd));

        error = calypso_poller_send_apdu(instance, &sw);
        if(error != CalypsoErrorNone) return error;
    }

    if(sw != 0x9000) {
        // 6A83 record not found is the normal end-of-file marker
        FURI_LOG_T(TAG, "READ RECORD SFI %02X rec %u SW %04X", sfi, record_num, sw);
        return CalypsoErrorNone;
    }

    const size_t rx_size = bit_buffer_get_size_bytes(instance->rx_buffer);
    const size_t data_len = rx_size - 2;
    const size_t copy_len = MIN(data_len, (size_t)CALYPSO_RECORD_SIZE);

    memset(out, 0, CALYPSO_RECORD_SIZE);
    if(copy_len) {
        memcpy(out, bit_buffer_get_data(instance->rx_buffer), copy_len);
    }
    *found = true;

    return CalypsoErrorNone;
}

const CalypsoData* calypso_poller_get_data(CalypsoPoller* instance) {
    furi_assert(instance);
    return instance->data;
}
