#include "calypso.h"

#include "flipper_format.h"
#include <nfc/protocols/nfc_device_base_i.h>
#include <furi.h>
#include <stdlib.h>
#include <string.h>

#define CALYPSO_PROTOCOL_NAME "Calypso"

const NfcDeviceBase nfc_device_calypso = {
    .protocol_name = CALYPSO_PROTOCOL_NAME,
    .alloc = (NfcDeviceAlloc)calypso_alloc,
    .free = (NfcDeviceFree)calypso_free,
    .reset = (NfcDeviceReset)calypso_reset,
    .copy = (NfcDeviceCopy)calypso_copy,
    .verify = (NfcDeviceVerify)calypso_verify,
    .load = (NfcDeviceLoad)calypso_load,
    .save = (NfcDeviceSave)calypso_save,
    .is_equal = (NfcDeviceEqual)calypso_is_equal,
    .get_name = (NfcDeviceGetName)calypso_get_device_name,
    .get_uid = (NfcDeviceGetUid)calypso_get_uid,
    .set_uid = (NfcDeviceSetUid)calypso_set_uid,
    .get_base_data = (NfcDeviceGetBaseData)calypso_get_base_data,
};

CalypsoData* calypso_alloc(void) {
    CalypsoData* data = malloc(sizeof(CalypsoData));
    data->iso14443_4b_data = iso14443_4b_alloc();
    memset(&data->application, 0, sizeof(CalypsoApplication));
    return data;
}

void calypso_free(CalypsoData* data) {
    furi_assert(data);

    iso14443_4b_free(data->iso14443_4b_data);
    free(data);
}

void calypso_reset(CalypsoData* data) {
    furi_assert(data);

    iso14443_4b_reset(data->iso14443_4b_data);
    memset(&data->application, 0, sizeof(CalypsoApplication));
}

void calypso_copy(CalypsoData* destination, const CalypsoData* source) {
    furi_assert(destination);
    furi_assert(source);

    iso14443_4b_copy(destination->iso14443_4b_data, source->iso14443_4b_data);
    destination->application = source->application;
}

bool calypso_verify(CalypsoData* data, const FuriString* device_type) {
    UNUSED(data);
    return furi_string_equal_str(device_type, CALYPSO_PROTOCOL_NAME);
}

bool calypso_load(CalypsoData* data, FlipperFormat* ff, uint32_t version) {
    furi_assert(data);

    FuriString* key = furi_string_alloc();
    bool parsed = false;

    do {
        if(!iso14443_4b_load(data->iso14443_4b_data, ff, version)) break;

        CalypsoApplication* app = &data->application;

        uint32_t aid_len = 0;
        if(!flipper_format_read_uint32(ff, "AID length", &aid_len, 1)) break;
        if(aid_len > CALYPSO_AID_MAX_LEN) break;
        app->aid_len = aid_len;
        if(aid_len && !flipper_format_read_hex(ff, "AID", app->aid, aid_len)) break;

        uint32_t serial_valid = 0;
        if(!flipper_format_read_uint32(ff, "Serial valid", &serial_valid, 1)) break;
        app->serial_valid = serial_valid;
        if(app->serial_valid) {
            if(!flipper_format_read_hex(ff, "Serial", app->serial, sizeof(app->serial))) break;
        }

        uint32_t file_count = 0;
        if(!flipper_format_read_uint32(ff, "File count", &file_count, 1)) break;
        if(file_count > CALYPSO_MAX_FILES) break;
        app->file_count = file_count;

        bool files_ok = true;
        for(uint8_t i = 0; i < app->file_count; i++) {
            CalypsoFile* file = &app->files[i];

            furi_string_printf(key, "File %u SFI", i);
            uint32_t sfi = 0;
            if(!flipper_format_read_uint32(ff, furi_string_get_cstr(key), &sfi, 1)) {
                files_ok = false;
                break;
            }
            file->sfi = sfi;

            furi_string_printf(key, "File %u record count", i);
            uint32_t record_count = 0;
            if(!flipper_format_read_uint32(ff, furi_string_get_cstr(key), &record_count, 1)) {
                files_ok = false;
                break;
            }
            if(record_count > CALYPSO_MAX_RECORDS) {
                files_ok = false;
                break;
            }
            file->record_count = record_count;

            furi_string_printf(key, "File %u data", i);
            if(record_count &&
               !flipper_format_read_hex(
                   ff,
                   furi_string_get_cstr(key),
                   (uint8_t*)file->records,
                   record_count * CALYPSO_RECORD_SIZE)) {
                files_ok = false;
                break;
            }
        }
        if(!files_ok) break;

        parsed = true;
    } while(false);

    furi_string_free(key);
    return parsed;
}

bool calypso_save(const CalypsoData* data, FlipperFormat* ff) {
    furi_assert(data);

    FuriString* key = furi_string_alloc();
    bool saved = false;

    do {
        if(!iso14443_4b_save(data->iso14443_4b_data, ff)) break;

        if(!flipper_format_write_comment_cstr(ff, "Calypso specific data:")) break;

        const CalypsoApplication* app = &data->application;

        uint32_t aid_len = app->aid_len;
        if(!flipper_format_write_uint32(ff, "AID length", &aid_len, 1)) break;
        if(aid_len && !flipper_format_write_hex(ff, "AID", app->aid, aid_len)) break;

        uint32_t serial_valid = app->serial_valid ? 1 : 0;
        if(!flipper_format_write_uint32(ff, "Serial valid", &serial_valid, 1)) break;
        if(app->serial_valid) {
            if(!flipper_format_write_hex(ff, "Serial", app->serial, sizeof(app->serial))) break;
        }

        uint32_t file_count = app->file_count;
        if(!flipper_format_write_uint32(ff, "File count", &file_count, 1)) break;

        bool files_ok = true;
        for(uint8_t i = 0; i < app->file_count; i++) {
            const CalypsoFile* file = &app->files[i];

            furi_string_printf(key, "File %u SFI", i);
            uint32_t sfi = file->sfi;
            if(!flipper_format_write_uint32(ff, furi_string_get_cstr(key), &sfi, 1)) {
                files_ok = false;
                break;
            }

            furi_string_printf(key, "File %u record count", i);
            uint32_t record_count = file->record_count;
            if(!flipper_format_write_uint32(ff, furi_string_get_cstr(key), &record_count, 1)) {
                files_ok = false;
                break;
            }

            furi_string_printf(key, "File %u data", i);
            if(record_count &&
               !flipper_format_write_hex(
                   ff,
                   furi_string_get_cstr(key),
                   (const uint8_t*)file->records,
                   record_count * CALYPSO_RECORD_SIZE)) {
                files_ok = false;
                break;
            }
        }
        if(!files_ok) break;

        saved = true;
    } while(false);

    furi_string_free(key);
    return saved;
}

bool calypso_is_equal(const CalypsoData* data, const CalypsoData* other) {
    furi_assert(data);
    furi_assert(other);

    return iso14443_4b_is_equal(data->iso14443_4b_data, other->iso14443_4b_data) &&
           memcmp(&data->application, &other->application, sizeof(CalypsoApplication)) == 0;
}

const char* calypso_get_device_name(const CalypsoData* data, NfcDeviceNameType name_type) {
    UNUSED(data);
    UNUSED(name_type);
    return CALYPSO_PROTOCOL_NAME;
}

const uint8_t* calypso_get_uid(const CalypsoData* data, size_t* uid_len) {
    furi_assert(data);
    return iso14443_4b_get_uid(data->iso14443_4b_data, uid_len);
}

bool calypso_set_uid(CalypsoData* data, const uint8_t* uid, size_t uid_len) {
    furi_assert(data);
    return iso14443_4b_set_uid(data->iso14443_4b_data, uid, uid_len);
}

Iso14443_4bData* calypso_get_base_data(const CalypsoData* data) {
    furi_assert(data);
    return data->iso14443_4b_data;
}

const CalypsoFile* calypso_get_file(const CalypsoData* data, uint8_t sfi) {
    furi_assert(data);

    for(uint8_t i = 0; i < data->application.file_count; i++) {
        if(data->application.files[i].sfi == sfi) {
            return &data->application.files[i];
        }
    }
    return NULL;
}

CalypsoFile* calypso_get_or_add_file(CalypsoData* data, uint8_t sfi) {
    furi_assert(data);

    for(uint8_t i = 0; i < data->application.file_count; i++) {
        if(data->application.files[i].sfi == sfi) {
            return &data->application.files[i];
        }
    }

    if(data->application.file_count >= CALYPSO_MAX_FILES) {
        return NULL;
    }

    CalypsoFile* file = &data->application.files[data->application.file_count++];
    memset(file, 0, sizeof(CalypsoFile));
    file->sfi = sfi;
    return file;
}
