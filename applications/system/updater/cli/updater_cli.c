
#include <furi.h>
#include <furi_hal.h>
#include <toolbox/cli/cli_command.h>
#include <cli/cli_main_commands.h>
#include <storage/storage.h>
#include <loader/loader.h>
#include <toolbox/path.h>
#include <toolbox/tar/tar_archive.h>
#include <toolbox/args.h>
#include <toolbox/pipe.h>
#include <update_util/update_manifest.h>
#include <update_util/int_backup.h>
#include <update_util/update_operation.h>
#include <ble_glue.h>

typedef void (*cmd_handler)(FuriString* args);
typedef struct {
    const char* command;
    const cmd_handler handler;
    bool requires_arg;
} CliSubcommand;

static void updater_cli_install(FuriString* manifest_path) {
    printf("Verifying update package at '%s'\r\n", furi_string_get_cstr(manifest_path));

    UpdatePrepareResult result = update_operation_prepare(furi_string_get_cstr(manifest_path));
    if(result != UpdatePrepareResultOK) {
        printf(
            "Error: %s. Stopping update.\r\n",
            update_operation_describe_preparation_result(result));
        return;
    }
    printf("OK.\r\nRestarting to apply update. BRB\r\n");
    furi_delay_ms(100);
    furi_hal_power_reset();
}

static void updater_cli_backup(FuriString* args) {
    printf("Backup /int to '%s'\r\n", furi_string_get_cstr(args));
    Storage* storage = furi_record_open(RECORD_STORAGE);
    bool success = int_backup_create(storage, furi_string_get_cstr(args));
    furi_record_close(RECORD_STORAGE);
    printf("Result: %s\r\n", success ? "OK" : "FAIL");
}

static void updater_cli_restore(FuriString* args) {
    printf("Restore /int from '%s'\r\n", furi_string_get_cstr(args));
    Storage* storage = furi_record_open(RECORD_STORAGE);
    bool success = int_backup_unpack(storage, furi_string_get_cstr(args));
    furi_record_close(RECORD_STORAGE);
    printf("Result: %s\r\n", success ? "OK" : "FAIL");
}

static void updater_cli_fus_status(FuriString* args) {
    if(!furi_string_empty(args)) {
        printf("Usage: update fus-status\r\n");
        return;
    }
    if(!furi_hal_bt_is_alive()) {
        printf("FUS query refused: Core2 is not ready\r\n");
        return;
    }

    furi_hal_bt_lock_core2();
    if(!furi_hal_bt_is_alive()) {
        furi_hal_bt_unlock_core2();
        printf("FUS query refused: Core2 is not ready\r\n");
        return;
    }
    const BleGlueC2Info* info = ble_glue_get_c2_info();
    if(!info || info->mode != BleGlueC2ModeFUS) {
        furi_hal_bt_unlock_core2();
        printf("FUS query refused: Core2 is not in FUS mode\r\n");
        return;
    }

    // A repeated GET_STATE in Stack mode can start FUS. Never retry this query.
    uint8_t state = 0;
    uint8_t error = 0;
    bool read = ble_glue_fus_read_status(&state, &error);
    furi_hal_bt_unlock_core2();
    if(!read) {
        printf("FUS query refused: Core2 is no longer ready in FUS mode\r\n");
        return;
    }
    printf("FUS state: 0x%02X, error: 0x%02X\r\n", (unsigned)state, (unsigned)error);
}

static void updater_cli_help(FuriString* args) {
    UNUSED(args);
    printf("Commands:\r\n"
           "\tinstall /ext/path/to/update.fuf - verify & apply update package\r\n"
           "\tbackup /ext/path/to/backup.tar - create internal storage backup\r\n"
           "\trestore /ext/path/to/backup.tar - restore internal storage backup\r\n"
           "\tfus-status - read FUS state once, only while Core2 is in FUS mode\r\n");
}

static const CliSubcommand update_cli_subcommands[] = {
    {.command = "install", .handler = updater_cli_install, .requires_arg = true},
    {.command = "backup", .handler = updater_cli_backup, .requires_arg = true},
    {.command = "restore", .handler = updater_cli_restore, .requires_arg = true},
    {.command = "fus-status", .handler = updater_cli_fus_status},
    {.command = "help", .handler = updater_cli_help},
};

static void updater_cli_ep(PipeSide* pipe, FuriString* args, void* context) {
    UNUSED(pipe);
    UNUSED(context);
    FuriString* subcommand;
    subcommand = furi_string_alloc();
    if(!args_read_string_and_trim(args, subcommand)) {
        updater_cli_help(args);
        furi_string_free(subcommand);
        return;
    }
    for(size_t idx = 0; idx < COUNT_OF(update_cli_subcommands); ++idx) {
        const CliSubcommand* subcmd_def = &update_cli_subcommands[idx];
        if(furi_string_cmp_str(subcommand, subcmd_def->command) == 0) {
            if(subcmd_def->requires_arg && furi_string_empty(args)) {
                updater_cli_help(args);
            } else {
                subcmd_def->handler(args);
            }
            furi_string_free(subcommand);
            return;
        }
    }
    furi_string_free(subcommand);
    updater_cli_help(args);
}

static void updater_start_app(void* context, uint32_t arg) {
    UNUSED(context);
    UNUSED(arg);

    FuriHalRtcBootMode mode = furi_hal_rtc_get_boot_mode();
    if((mode != FuriHalRtcBootModePreUpdate) && (mode != FuriHalRtcBootModePostUpdate)) {
        return;
    }

    /* We need to spawn a separate thread, because these callbacks are executed 
     * inside loader process, at startup. 
     * So, accessing its record would cause a deadlock 
     */
    Loader* loader = furi_record_open(RECORD_LOADER);
    loader_start(loader, "UpdaterApp", NULL, NULL);
    furi_record_close(RECORD_LOADER);
}

void updater_on_system_start(void) {
#ifdef SRV_CLI
    CliRegistry* registry = furi_record_open(RECORD_CLI);
    cli_registry_add_command(registry, "update", CliCommandFlagDefault, updater_cli_ep, NULL);
    furi_record_close(RECORD_CLI);
#else
    UNUSED(updater_cli_ep);
#endif
#ifndef FURI_RAM_EXEC
    furi_timer_pending_callback(updater_start_app, NULL, 0);
#else
    UNUSED(updater_start_app);
#endif
}
