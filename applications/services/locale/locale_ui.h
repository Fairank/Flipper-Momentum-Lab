#pragma once
#include <stddef.h>
#include <string.h>

/* Display aliases only. Keep canonical launch names and saved favorite keys unchanged. */
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
    };
    if(!canonical) return NULL;
    for(size_t i = 0; i < sizeof(labels) / sizeof(labels[0]); ++i) {
        if(strcmp(canonical, labels[i].canonical) == 0) return labels[i].chinese;
    }
    return canonical;
}
