#include "calypso_render.h"

void nfc_render_calypso_info(
    const CalypsoData* data,
    NfcProtocolFormatType format_type,
    FuriString* str) {
    const CalypsoApplication* app = &data->application;

    furi_string_cat_printf(str, "\e#Calypso card\n");

    if(app->serial_valid) {
        furi_string_cat_printf(str, "Serial:");
        for(size_t i = 0; i < sizeof(app->serial); i++) {
            furi_string_cat_printf(str, " %02X", app->serial[i]);
        }
        furi_string_cat_printf(str, "\n");
    }

    size_t total_records = 0;
    for(uint8_t i = 0; i < app->file_count; i++) {
        total_records += app->files[i].record_count;
    }
    furi_string_cat_printf(
        str, "Files: %u, records: %zu\n", app->file_count, total_records);

    if(format_type == NfcProtocolFormatTypeShort) {
        return;
    }

    for(uint8_t i = 0; i < app->file_count; i++) {
        const CalypsoFile* file = &app->files[i];
        furi_string_cat_printf(str, "\e*SFI %02X (%u rec)\n", file->sfi, file->record_count);
        for(uint8_t r = 0; r < file->record_count; r++) {
            furi_string_cat_printf(str, "%u:", r + 1);
            for(uint8_t b = 0; b < CALYPSO_RECORD_SIZE; b++) {
                furi_string_cat_printf(str, "%02X", file->records[r][b]);
            }
            furi_string_cat_printf(str, "\n");
        }
    }
}
