#if DEBUG
import Foundation
import FlipperCore

// Explicit UI-test fixtures, isolated from the user's on-disk library.
enum PreviewRecords {
    static let samples = [
        CaptureRecord(name: "示例：客厅遥控", kind: .infrared, tags: ["示例", "客厅"],
                      notes: "界面测试样本，并非真实采集；设备未连接。", rawText: """
        Filetype: IR signals file
        Version: 1
        name: Power
        type: raw
        frequency: 38000
        duty_cycle: 0.33
        data: 9000 4500 560 560 560 1690 560 560 560 1690 560 560 560 560 560 1690 560 40000
        """),
        CaptureRecord(name: "示例：设备启动日志", kind: .serial, tags: ["示例", "串口"],
                      notes: "界面测试样本，并非设备实时日志。", rawText: """
        0001 [I][Boot] starting
        0002 [I][Storage] SD ready
        0003 [W][UART] timeout
        0004 [I][UART] connected
        """),
        CaptureRecord(name: "示例：Wi-Fi 扫描", kind: .wifiSurvey, tags: ["示例", "离线分析"],
                      notes: "ESP32 日志格式样本，并非真实扩展板扫描。", rawText: """
        > #scanap
        Starting AP scan. Stop with stopscan
        RSSI: -54 Ch: 6 BSSID: 02:11:22:33:44:55 ESSID: Home
        RSSI: -71 Ch: 11 BSSID: 02:11:22:33:44:66 ESSID: Office Guest
        """)
    ]
}
#endif
