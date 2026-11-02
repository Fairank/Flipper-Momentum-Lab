#pragma once
#include <stddef.h>
#include <string.h>

/* Device UI uses canonical English labels. Keep the old display metadata for
 * source compatibility; the iPhone owns Chinese labels and descriptions. */
static inline const char* locale_ui_label(const char* canonical) {
    static const struct {
        const char* canonical;
        const char* chinese;
    } labels[] = {
        {"Flipper Lab", "功能指南"},
        {"Lab Bridge", "扩展板串口"},
        {"Apps", "应用"},
        {"Settings", "设置"},
        {"Bluetooth", "蓝牙"},
        {"Infrared", "红外遥控"},
        {"125 kHz RFID", "低频 RFID"},
        {"GPIO", "扩展接口"},
        {"Archive", "文件管理"},
        {"Desktop", "桌面"},
        {"System", "系统"},
        {"Storage", "存储"},
        {"Power", "电源"},
        {"LCD and Notifications", "显示与通知"},
        {"Input", "按键"},
        {"Expansion Modules", "扩展模块"},
        {"Clock & Alarm", "时钟与闹钟"},
        {"Clock", "时钟"},
        {"Apps Menu", "应用菜单"},
        {"Device Info", "设备信息"},
        {"Lock Menu", "锁定菜单"},
        {"Lock Keypad", "按键锁定"},
        {"Lock with PIN", "PIN 码锁定"},
        {"Passport", "海豚档案"},
        {"About", "关于设备"},
        {"About Internal Storage", "内部存储信息"},
        {"About SD Card", "SD 卡信息"},
        {"Unmount SD Card", "卸载 SD 卡"},
        {"Mount SD Card", "挂载 SD 卡"},
        {"Format SD Card", "格式化 SD 卡"},
        {"Benchmark SD Card", "SD 卡测速"},
        {"Factory Reset", "恢复出厂设置"},
        {"Wipe Device", "清除设备数据"},
        {"Search for files", "搜索文件"},
        {"U2F Token", "U2F 令牌"},
        {"FindMy Flipper", "查找设备"},
        {"USB Remote", "USB 遥控"},
        {"Bluetooth Remote", "蓝牙遥控"},
    };
    if(!canonical) return NULL;
    for(size_t i = 0; i < sizeof(labels) / sizeof(labels[0]); ++i) {
        if(strcmp(canonical, labels[i].canonical) == 0) return labels[i].canonical;
    }
    return canonical;
}

/* Keep the device's storage errors in canonical English, including UI sites. */
static inline const char* locale_ui_storage_error(const char* error) {
    static const struct {
        const char* source;
        const char* label;
    } errors[] = {
        {"OK", "成功"},
        {"filesystem not ready", "文件系统\n未就绪"},
        {"file/dir already exist", "文件或目录\n已存在"},
        {"file/dir not exist", "文件或目录\n不存在"},
        {"invalid parameter", "参数无效"},
        {"access denied", "拒绝访问"},
        {"invalid name/path", "名称或路径\n无效"},
        {"internal error", "内部错误"},
        {"function not implemented", "功能未实现"},
        {"file is already open", "文件已打开"},
        {"unknown error", "未知错误"},
    };
    if(!error) return NULL;
    for(size_t i = 0; i < sizeof(errors) / sizeof(errors[0]); ++i) {
        if(strcmp(error, errors[i].source) == 0) return errors[i].source;
    }
    return error;
}
