#pragma once
#include "loader.h"

/** Firmware-internal RPC entry point; deliberately excluded from the FAP SDK.
 * Refuses an incompatible external application without a blocking device dialog.
 * RPC-mode arguments and ordinary GUI application arguments keep their usual meaning.
 */
LoaderStatus loader_start_from_rpc(
    Loader* loader,
    const char* name,
    const char* args,
    FuriString* error_message);
