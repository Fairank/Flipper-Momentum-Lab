# AIO Board 1.4：已知信息与验收状态

用户确认扩展板名称为 **AIO Board 1.4**，但暂时无法确认厂商、ESP32 芯片丝印或当前固件。因此，项目按板卡名称登记，不把任何卖家版本直接认定为用户手中的实物。

## 可核实的参考资料

- [SecureTechware 的 3 合 1 AIO 板仓库](https://github.com/SecureTechware/3in1-AIO-Expansion-Board-FlipperZero)列出 ESP32、CC1101 与 nRF24 模块；其 [V1.4 安装说明](https://github.com/SecureTechware/3in1-AIO-Expansion-Board-FlipperZero/blob/main/INSTALLATION.md)将该卖家版本的 ESP32 芯片写为 ESP32-S2。这只能证明该版本的文档，不能确认用户的板卡也是同一芯片。
- [Flipper Marauder 上游的一份 AIO BOARD V1.4 报告](https://github.com/0xchocolate/flipperzero-wifi-marauder/issues/62)也描述了 ESP32、nRF24、CC1101 与 SD 卡，但报告者当时尚未使其正常工作。它说明同名板的兼容性需要实物和固件验证。

用户之前把 nRF24 记作 `nrf244`；本项目按参考资料中的 **nRF24** 展示，并保留实物核对要求。CC1101 与 nRF24 是独立模块，不等于 ESP32 的 Wi‑Fi 功能。

## 当前软件能做什么

Flipper 固件源码内已有 `[ESP32] WiFi Marauder` 伴侣应用。iPhone App 可从文件或 Flipper SD 卡导入**已保存**的 ESP32 接入点扫描 `.log`，离线查看 SSID、BSSID、信道、RSSI；日志未提供的安全类型会显示为“未记录”。详情见 [扫描记录说明](WIFI_SURVEY.zh-CN.md)。

这条文件导入链路的解析、模拟器界面和固件构建已在 GitHub CI 验证，但**用户实物板卡与 Flipper 的通信、现装 ESP32 固件、板上 SD 卡保存、iPhone 蓝牙传输均未真机验证**。手机的“扩展板”页面只展示参考信息，不显示虚构的在线状态，也不发送扩展板指令。

## 真机验收需要记录

1. 板卡正反面的厂商与芯片丝印，以及课程或卖家提供的固件版本。
2. Flipper 当前固件版本、SD 卡状态，以及该板接入后能否从现有应用读取设备信息。
3. 已保存的接入点扫描日志能否经 Flipper 文件浏览或 iPhone 文件 App 导入，并在手机端正确显示字段。

这些项目未完成前，不能宣称 AIO Board 1.4 已在本项目中即插即用。仓库没有新增定向 Wi‑Fi 断链控制功能。
