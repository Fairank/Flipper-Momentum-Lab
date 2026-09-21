/*
 * ravkav.c - Parser for the Israeli "Rav-Kav" transit card.
 *
 * Rav-Kav is a Calypso (ISO 14443 Type B, ISO 7816-4) transit card used across
 * Israel. It exposes the standard Intercode / RTIC transit application, selected
 * by the AID "1TIC.ICA", and stores its data in Elementary Files following the
 * En1545 data model.
 *
 * This parser runs on top of the generic Calypso protocol (see
 * lib/nfc/protocols/calypso), which performs the SELECT + READ RECORD sequence
 * and stores the raw 29-byte records. Here we decode the fields that are safely
 * derivable from the public Intercode/En1545 layout: the card serial number, the
 * environment (country / network / version), and the number of contracts, events
 * and counters present. The full fare/ride semantics of Intercode are network
 * specific and are intentionally shown as raw values rather than guessed.
 *
 * References:
 *  - Intercode / En1545 transit data model (Calypso "1TIC.ICA").
 *  - docs/ravkav-nfc-card-communication.md (reverse-engineering notes).
 */

#include "nfc_supported_card_plugin.h"
#include <flipper_application.h>

#include <lib/nfc/protocols/calypso/calypso.h>

// Intercode short EF identifiers used by Rav-Kav
#define RAVKAV_SFI_ENVIRONMENT (0x07U)
#define RAVKAV_SFI_EVENTS      (0x08U)
#define RAVKAV_SFI_CONTRACTS   (0x09U)
#define RAVKAV_SFI_COUNTERS    (0x1DU)

// Expected AID: ASCII "1TIC.ICA"
static const uint8_t ravkav_aid[] = {0x31, 0x54, 0x49, 0x43, 0x2E, 0x49, 0x43, 0x41};

/**
 * @brief MSB-first bit reader over a record buffer (En1545 encoding).
 */
typedef struct {
    const uint8_t* data;
    size_t size_bits;
    size_t pos;
} RavKavBitReader;

static void ravkav_bit_reader_init(RavKavBitReader* reader, const uint8_t* data, size_t size_bytes) {
    reader->data = data;
    reader->size_bits = size_bytes * 8;
    reader->pos = 0;
}

/**
 * @brief Read up to 32 bits MSB-first, advancing the reader.
 *
 * @returns the value, or 0 if the read would run past the end of the buffer.
 */
static uint32_t ravkav_bit_read(RavKavBitReader* reader, size_t bits) {
    if(bits == 0 || bits > 32) return 0;
    if(reader->pos + bits > reader->size_bits) {
        reader->pos = reader->size_bits;
        return 0;
    }

    uint32_t value = 0;
    for(size_t i = 0; i < bits; i++) {
        const size_t bit_index = reader->pos + i;
        const uint8_t byte = reader->data[bit_index / 8];
        const uint8_t bit = (byte >> (7 - (bit_index % 8))) & 1U;
        value = (value << 1) | bit;
    }
    reader->pos += bits;
    return value;
}

/** Find a stored EF by its SFI (struct access only, no firmware API dependency). */
static const CalypsoFile* ravkav_find_file(const CalypsoApplication* app, uint8_t sfi) {
    for(uint8_t i = 0; i < app->file_count; i++) {
        if(app->files[i].sfi == sfi) return &app->files[i];
    }
    return NULL;
}

/** Decode a big-endian integer of `len` bytes from a record. */
static uint32_t ravkav_be(const uint8_t* p, size_t len) {
    uint32_t v = 0;
    for(size_t i = 0; i < len; i++) {
        v = (v << 8) | p[i];
    }
    return v;
}

static void ravkav_render_country(uint16_t country, FuriString* str) {
    // En1545 country code is BCD-like ISO 3166 numeric; Israel = 376.
    if(country == 376) {
        furi_string_cat_str(str, "Israel");
    } else {
        furi_string_cat_printf(str, "%u", country);
    }
}

static bool ravkav_parse(const NfcDevice* device, FuriString* parsed_data) {
    furi_assert(device);
    furi_assert(parsed_data);

    if(nfc_device_get_protocol(device) != NfcProtocolCalypso) {
        return false;
    }

    const CalypsoData* data = nfc_device_get_data(device, NfcProtocolCalypso);
    const CalypsoApplication* app = &data->application;

    // Confirm this is the Intercode transit application
    if(app->aid_len != sizeof(ravkav_aid) || memcmp(app->aid, ravkav_aid, sizeof(ravkav_aid)) != 0) {
        return false;
    }

    furi_string_cat_str(parsed_data, "\e#Rav-Kav\n");

    // Card serial number: two big-endian uint32s from the SELECT FCI.
    if(app->serial_valid) {
        const uint32_t serial_hi = ravkav_be(&app->serial[0], 4);
        const uint32_t serial_lo = ravkav_be(&app->serial[4], 4);
        furi_string_cat_printf(parsed_data, "Serial: %lu\n", (unsigned long)serial_lo);
        if(serial_hi != 0) {
            furi_string_cat_printf(parsed_data, "Serial (hi): %lu\n", (unsigned long)serial_hi);
        }
    }

    // Environment: version / country / network (En1545 header)
    const CalypsoFile* env = ravkav_find_file(app, RAVKAV_SFI_ENVIRONMENT);
    if(env && env->record_count > 0) {
        RavKavBitReader reader;
        ravkav_bit_reader_init(&reader, env->records[0], CALYPSO_RECORD_SIZE);
        const uint32_t version = ravkav_bit_read(&reader, 6);
        const uint16_t country = ravkav_bit_read(&reader, 12);
        const uint16_t network = ravkav_bit_read(&reader, 12);

        furi_string_cat_str(parsed_data, "Network: ");
        ravkav_render_country(country, parsed_data);
        furi_string_cat_printf(parsed_data, " / %u\n", network);
        furi_string_cat_printf(parsed_data, "App version: %lu\n", (unsigned long)version);
    }

    // Contracts and events counts
    const CalypsoFile* contracts = ravkav_find_file(app, RAVKAV_SFI_CONTRACTS);
    const CalypsoFile* events = ravkav_find_file(app, RAVKAV_SFI_EVENTS);
    furi_string_cat_printf(
        parsed_data, "Contracts: %u\n", contracts ? contracts->record_count : 0);
    furi_string_cat_printf(parsed_data, "Events: %u\n", events ? events->record_count : 0);

    // Counters: Intercode packs 24-bit counters; show them raw as they are
    // network-specific (often remaining rides or a stored-value balance).
    const CalypsoFile* counters = ravkav_find_file(app, RAVKAV_SFI_COUNTERS);
    if(counters && counters->record_count > 0) {
        const uint8_t* rec = counters->records[0];
        for(size_t i = 0; i + 3 <= CALYPSO_RECORD_SIZE; i += 3) {
            const uint32_t value = ravkav_be(&rec[i], 3);
            if(value == 0 || value == 0xFFFFFF) continue;
            furi_string_cat_printf(
                parsed_data, "Counter %u: %lu\n", (unsigned)(i / 3), (unsigned long)value);
        }
    }

    return true;
}

/* Actual implementation of app<>plugin interface */
static const NfcSupportedCardsPlugin ravkav_plugin = {
    .protocol = NfcProtocolCalypso,
    .verify = NULL,
    .read = NULL,
    .parse = ravkav_parse,
};

/* Plugin descriptor to comply with basic plugin specification */
static const FlipperAppPluginDescriptor ravkav_plugin_descriptor = {
    .appid = NFC_SUPPORTED_CARD_PLUGIN_APP_ID,
    .ep_api_version = NFC_SUPPORTED_CARD_PLUGIN_API_VERSION,
    .entry_point = &ravkav_plugin,
};

/* Plugin entry point - must return a pointer to const descriptor */
const FlipperAppPluginDescriptor* ravkav_plugin_ep(void) {
    return &ravkav_plugin_descriptor;
}
