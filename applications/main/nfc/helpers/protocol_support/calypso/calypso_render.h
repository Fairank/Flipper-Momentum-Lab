#pragma once

#include <nfc/protocols/calypso/calypso.h>

#include "../nfc_protocol_support_render_common.h"

void nfc_render_calypso_info(
    const CalypsoData* data,
    NfcProtocolFormatType format_type,
    FuriString* str);
