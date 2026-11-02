/* Exercise the real FatFs implementation on an isolated RAM disk. */
#undef NDEBUG
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ff.h"
#include "diskio.h"

#define SECTORS 131072u
static BYTE* disk;
static FATFS fs;
DSTATUS disk_initialize(BYTE drive) {
    return drive ? STA_NOINIT : 0;
}
DSTATUS disk_status(BYTE drive) {
    return drive ? STA_NOINIT : 0;
}
DRESULT disk_read(BYTE drive, BYTE* out, DWORD sector, UINT count) {
    if(drive || !count || sector >= SECTORS || count > SECTORS - sector) return RES_PARERR;
    memcpy(out, disk + (size_t)sector * 512, (size_t)count * 512);
    return RES_OK;
}
DRESULT disk_write(BYTE drive, const BYTE* in, DWORD sector, UINT count) {
    if(drive || !count || sector >= SECTORS || count > SECTORS - sector) return RES_PARERR;
    memcpy(disk + (size_t)sector * 512, in, (size_t)count * 512);
    return RES_OK;
}
DRESULT disk_ioctl(BYTE drive, BYTE cmd, void* value) {
    if(drive) return RES_PARERR;
    switch(cmd) {
    case CTRL_SYNC:
        return RES_OK;
    case GET_SECTOR_COUNT:
        *(DWORD*)value = SECTORS;
        return RES_OK;
    case GET_SECTOR_SIZE:
        *(WORD*)value = 512;
        return RES_OK;
    case GET_BLOCK_SIZE:
        *(DWORD*)value = 1;
        return RES_OK;
    default:
        return RES_PARERR;
    }
}
void* ff_memalloc(UINT size) {
    return malloc(size);
}
void ff_memfree(void* p) {
    free(p);
}
#define OK(expr)                                                                   \
    do {                                                                           \
        FRESULT r = (expr);                                                        \
        if(r != FR_OK) {                                                           \
            fprintf(stderr, "line %d: %s returned %d\n", __LINE__, #expr, (int)r); \
            exit(1);                                                               \
        }                                                                          \
    } while(0)

static void write_new(const char* name, size_t size) {
    FIL file;
    UINT written;
    BYTE buffer[512];
    memset(buffer, 0x5a, sizeof(buffer));
    OK(f_open(&file, name, FA_CREATE_ALWAYS | FA_WRITE));
    while(size) {
        UINT n = (UINT)(size < sizeof(buffer) ? size : sizeof(buffer));
        OK(f_write(&file, buffer, n, &written));
        assert(written == n);
        size -= n;
    }
    OK(f_close(&file));
}
static void verify(const char* name, size_t size) {
    FILINFO info;
    FIL file;
    BYTE buffer[512];
    UINT got;
    OK(f_stat(name, &info));
    assert(info.fsize == size);
    OK(f_open(&file, name, FA_READ));
    while(size) {
        UINT n = (UINT)(size < sizeof(buffer) ? size : sizeof(buffer));
        OK(f_read(&file, buffer, n, &got));
        assert(got == n);
        for(UINT i = 0; i < got; i++)
            assert(buffer[i] == 0x5a);
        size -= n;
    }
    OK(f_close(&file));
}
static void remount(void) {
    OK(f_mount(NULL, "0:", 0));
    memset(&fs, 0, sizeof(fs));
    OK(f_mount(&fs, "0:", 1));
}
static void directory_growth(bool root) {
    if(!root) OK(f_mkdir("0:/fragmented"));
    char path[100], gap[64];
    /* Interleaved allocations force directory extensions away from their first cluster. */
    for(unsigned i = 0; i < 48; i++) {
        snprintf(gap, sizeof(gap), "0:/gap%03u.bin", i);
        write_new(gap, 512);
        snprintf(
            path,
            sizeof(path),
            "0:/%sentry-%03u-with-a-long-filename.bin",
            root ? "" : "fragmented/",
            i);
        write_new(path, 513 + i);
    }
    remount();
    for(unsigned i = 0; i < 48; i++) {
        snprintf(
            path,
            sizeof(path),
            "0:/%sentry-%03u-with-a-long-filename.bin",
            root ? "" : "fragmented/",
            i);
        verify(path, 513 + i);
    }
}
static void reopen_fragmented(void) {
    write_new("0:/data.bin", 512);
    write_new("0:/between.bin", 512);
    FIL file;
    UINT written;
    BYTE buffer[512];
    memset(buffer, 0x5a, sizeof(buffer));
    OK(f_open(&file, "0:/data.bin", FA_WRITE));
    OK(f_lseek(&file, 512));
    OK(f_write(&file, buffer, sizeof(buffer), &written));
    assert(written == sizeof(buffer));
    OK(f_close(&file));
    remount();
    memset(&file, 0xa5, sizeof(file));
    OK(f_open(&file, "0:/data.bin", FA_WRITE));
    assert(file.obj.n_frag == 0);
    OK(f_lseek(&file, 512));
    OK(f_write(&file, buffer, sizeof(buffer), &written));
    assert(written == sizeof(buffer));
    OK(f_close(&file));
    remount();
    verify("0:/data.bin", 1024);
}
static void truncate_contiguous(void) {
    write_new("0:/data.bin", 1024);
    write_new("0:/between.bin", 512);
    FIL file;
    UINT written;
    BYTE buffer[512];
    memset(buffer, 0x5a, sizeof(buffer));
    OK(f_open(&file, "0:/data.bin", FA_WRITE));
    OK(f_lseek(&file, 1024));
    OK(f_write(&file, buffer, sizeof(buffer), &written));
    OK(f_close(&file));
    remount();
    OK(f_open(&file, "0:/data.bin", FA_WRITE));
    OK(f_lseek(&file, 1024));
    OK(f_truncate(&file));
    assert(file.obj.stat == 2);
    OK(f_close(&file));
    remount();
    verify("0:/data.bin", 1024);
}
int main(int argc, char** argv) {
    assert(setvbuf(stdout, NULL, _IONBF, 0) == 0);
    assert(argc == 2);
    disk = calloc(SECTORS, 512);
    assert(disk);
    BYTE work[4096];
    OK(f_mkfs("0:", FM_EXFAT | FM_SFD, 512, work, sizeof(work)));
    OK(f_mount(&fs, "0:", 1));
    assert(fs.fs_type == FS_EXFAT);
    if(!strcmp(argv[1], "root"))
        directory_growth(true);
    else if(!strcmp(argv[1], "directory"))
        directory_growth(false);
    else if(!strcmp(argv[1], "reopen"))
        reopen_fragmented();
    else if(!strcmp(argv[1], "truncate"))
        truncate_contiguous();
    else
        return 2;
    OK(f_mount(NULL, "0:", 0));
    free(disk);
    puts("FatFs scenario passed");
    return 0;
}
