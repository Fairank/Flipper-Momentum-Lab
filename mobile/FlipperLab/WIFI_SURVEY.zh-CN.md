# Wi‑Fi 扫描记录：手机端离线分析

Flipper Lab 在 iPhone 上分析**已保存的扫描结果**。一份记录可以包含多个接入点；手机展示网络名称、BSSID、信道、接收信号强度和安全类型，并统计信道分布。分析留在手机本地，不连接这些网络，也不发送无线管理帧。

## 导入格式

可以直接导入本仓库 `[ESP32] WiFi Marauder` 伴侣应用保存的接入点扫描 `.log`。手机只识别含有扫描开始标记及接入点行的日志，例如：

```text
> #scanap
Starting AP scan. Stop with stopscan
RSSI: -54 Ch: 6 BSSID: 02:11:22:33:44:55 ESSID: Home
```

重复出现的 BSSID 与信道组合保留较强的一次 RSSI。此类日志没有可靠的安全类型字段，页面显示“未记录”，不能据此判断网络开放与否。其他控制台日志仍作为普通日志导入；`.pcap` 二进制文件不属于此功能。日志格式可能随 ESP32 固件版本改变，当前支持的行式样本见 [ESP32 Marauder 项目中的报告](https://github.com/justcallmekoko/ESP32Marauder/issues/1049)。

也可将 UTF‑8 文本保存为 `.wscan` 文件。第一行和第二行必须如下；后续每行表示一个接入点：

```text
# Flipper Lab WiFi Survey v1
ssid,bssid,channel,rssi,security
Home,02:11:22:33:44:55,6,-54,WPA2
"Office, Guest",02:11:22:33:44:66,11,-71,WPA3
```

SSID 含逗号时用双引号包围，SSID 内的双引号写成两个双引号。隐藏网络的 SSID 可留空。文件最多 2 MiB、512 个接入点；BSSID 与信道的组合不能重复。记录不包含密码、密钥或客户端身份信息。导入前可从文件来源核对这些字段，避免把含密码的扩展板配置文件误当扫描结果。

在“资料库”选择“导入文件”即可从 iPhone 导入；如果扫描文件或日志已保存到 Flipper 的 SD 卡，可以先连接 Flipper，再从“资料库”的“从 Flipper 导入”浏览该文件。现有伴侣应用可选择将控制台日志保存到 SD 卡，但是否成功取决于板卡与固件；参考[仓库中的保存逻辑](https://github.com/Fairank/Flipper-Momentum-Lab/blob/codex/iphone-zh-architecture/applications/external/wifi_marauder_companion/scenes/wifi_marauder_scene_console_output.c)。当前三合一扩展板的 ESP32 型号、接线与固件尚未确认，因此**实时扫描、自动生成 `.wscan` 文件、直接控制扩展板仍未适配或真机验证**。

此功能仅做接收信号和配置概览。距离不能从一个 RSSI 数字可靠换算；需要明确板卡型号、天线、室内外环境后，才能在真机上测量可扫描范围。经典 ESP32 的 Wi‑Fi 为 2.4 GHz；若板卡使用其他 ESP32 变种，以实际芯片规格为准。

参考：[Espressif ESP32 Wi‑Fi 扫描 API](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/network/esp_wifi.html)、[经典 ESP32 数据手册](https://documentation.espressif.com/esp32_datasheet_en.pdf)。
