# Wi‑Fi 扫描记录：手机端离线分析

Flipper Lab 在 iPhone 上分析**已保存的扫描结果**。一份记录可以包含多个接入点；手机展示网络名称、BSSID、信道、接收信号强度和安全类型，并统计信道分布。分析留在手机本地，不连接这些网络，也不发送无线管理帧。

## 导入格式

将 UTF‑8 文本保存为 `.wscan` 文件。第一行和第二行必须如下；后续每行表示一个接入点：

```text
# Flipper Lab WiFi Survey v1
ssid,bssid,channel,rssi,security
Home,02:11:22:33:44:55,6,-54,WPA2
"Office, Guest",02:11:22:33:44:66,11,-71,WPA3
```

SSID 含逗号时用双引号包围，SSID 内的双引号写成两个双引号。隐藏网络的 SSID 可留空。文件最多 2 MiB、512 个接入点；BSSID 与信道的组合不能重复。记录不包含密码、密钥或客户端身份信息。导入前可从文件来源核对这些字段，避免把含密码的扩展板配置文件误当扫描结果。

在“资料库”选择“导入文件”即可从 iPhone 导入；如果扫描文件已由兼容应用保存到 Flipper 的 SD 卡，可以先连接 Flipper，再从“资料库”的“从 Flipper 导入”浏览该文件。当前三合一扩展板的 ESP32 型号、接线与固件尚未确认，因此**实时扫描、自动生成该文件、直接控制扩展板仍未适配或真机验证**。

此功能仅做接收信号和配置概览。距离不能从一个 RSSI 数字可靠换算；需要明确板卡型号、天线、室内外环境后，才能在真机上测量可扫描范围。经典 ESP32 的 Wi‑Fi 为 2.4 GHz；若板卡使用其他 ESP32 变种，以实际芯片规格为准。

参考：[Espressif ESP32 Wi‑Fi 扫描 API](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/network/esp_wifi.html)、[经典 ESP32 数据手册](https://documentation.espressif.com/esp32_datasheet_en.pdf)。
