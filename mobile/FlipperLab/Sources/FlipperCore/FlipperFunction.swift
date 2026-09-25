import Foundation

/// A phone-side entry that opens an existing Flipper application through App.Start RPC.
/// The title and explanation belong to the iPhone UI; execution stays on Flipper.
public struct FlipperFunction: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let category: String
    public let symbol: String
    public let launchName: String
    public let requirement: String
    public let isInstalledApp: Bool

    private init(id: String, title: String, summary: String, category: String,
                 symbol: String, launchName: String, requirement: String,
                 isInstalledApp: Bool = false) {
        self.id = id; self.title = title; self.summary = summary
        self.category = category; self.symbol = symbol; self.launchName = launchName
        self.requirement = requirement; self.isInstalledApp = isInstalledApp
    }

    /// Names match the pinned firmware's application.fam manifests or loader's Apps name.
    /// Apps stored on SD may still be absent from an individual Flipper.
    public static let builtIns: [FlipperFunction] = [
        .init(id: "infrared", title: "红外遥控", summary: "读取、保存并发送红外信号。",
              category: "无线与识别", symbol: "dot.radiowaves.left.and.right", launchName: "Infrared",
              requirement: "让 Flipper 的红外发射端朝向目标设备。"),
        .init(id: "subghz", title: "Sub-GHz", summary: "查看支持的频段、记录并管理无线信号。",
              category: "无线与识别", symbol: "antenna.radiowaves.left.and.right", launchName: "Sub-GHz",
              requirement: "由 Flipper 射频硬件执行；遵守当地频率规定。"),
        .init(id: "nfc", title: "NFC", summary: "读取、保存并管理近场卡片。",
              category: "无线与识别", symbol: "wave.3.right", launchName: "NFC",
              requirement: "将卡片贴近 Flipper 的 NFC 区域。"),
        .init(id: "lfrfid", title: "125 kHz RFID", summary: "管理低频门禁卡记录。",
              category: "无线与识别", symbol: "radiowaves.right", launchName: "125 kHz RFID",
              requirement: "将卡片贴近 Flipper 的低频天线。"),
        .init(id: "ibutton", title: "iButton", summary: "读取、保存并管理接触式钥匙。",
              category: "无线与识别", symbol: "key.horizontal", launchName: "iButton",
              requirement: "需要钥匙与 Flipper 接点直接接触。"),
        .init(id: "gpio", title: "GPIO", summary: "查看引脚与外部电路交互。",
              category: "工具", symbol: "point.3.connected.trianglepath.dotted", launchName: "GPIO",
              requirement: "核对电压、接线和外接模块。"),
        .init(id: "bad_kb", title: "Bad USB", summary: "在 Flipper 上运行已保存的键盘脚本。",
              category: "工具", symbol: "keyboard", launchName: "Bad KB",
              requirement: "目标设备需要连接 Flipper 的 USB。"),
        .init(id: "u2f", title: "U2F 安全密钥", summary: "在 Flipper 上打开双因素认证功能。",
              category: "工具", symbol: "lock.shield", launchName: "U2F",
              requirement: "使用前确认目标设备与 Flipper 的连接方式。"),
        .init(id: "archive", title: "文件归档", summary: "在设备上浏览已保存的记录。",
              category: "工具", symbol: "archivebox", launchName: "Archive",
              requirement: "保存的记录通常需要 SD 卡。"),
        .init(id: "lab", title: "Flipper Lab 中文指南", summary: "在设备上阅读中文说明并进入功能。",
              category: "系统", symbol: "book.closed", launchName: "Flipper Lab",
              requirement: "需要安装本仓库的 Flipper Lab 应用。"),
        .init(id: "apps", title: "设备应用列表", summary: "在 Flipper 上打开已安装应用列表。",
              category: "系统", symbol: "square.grid.2x2", launchName: "Apps",
              requirement: "外部应用需要已安装在设备 SD 卡上。"),
        .init(id: "momentum", title: "Momentum 设置", summary: "调整此固件提供的扩展设置。",
              category: "系统", symbol: "gearshape.2", launchName: "Momentum",
              requirement: "需要安装 Momentum 应用。"),
        .init(id: "bluetooth", title: "蓝牙设置", summary: "在设备上查看配对和连接设置。",
              category: "系统", symbol: "dot.radiowaves.left.and.right", launchName: "Bluetooth",
              requirement: "关闭设备蓝牙会使当前连接断开。"),
        .init(id: "storage", title: "存储设置", summary: "检查 SD 卡和设备存储。",
              category: "系统", symbol: "sdcard", launchName: "Storage",
              requirement: "部分操作需要插入 SD 卡。"),
        .init(id: "power", title: "电源设置", summary: "查看设备电源选项。",
              category: "系统", symbol: "battery.100percent", launchName: "Power",
              requirement: "设备休眠或关机会断开蓝牙。"),
        .init(id: "system_settings", title: "系统设置", summary: "查看固件和系统配置。",
              category: "系统", symbol: "gearshape", launchName: "System",
              requirement: "某些设置可能需要设备重启。"),
        .init(id: "desktop_settings", title: "桌面设置", summary: "调整 Flipper 桌面行为。",
              category: "系统", symbol: "house", launchName: "Desktop",
              requirement: "设置会作用于设备本身。"),
        .init(id: "input_settings", title: "按键设置", summary: "调整设备输入偏好。",
              category: "系统", symbol: "hand.tap", launchName: "Input",
              requirement: "部分操作需要在 Flipper 上确认。"),
        .init(id: "notifications", title: "屏幕与提示", summary: "设置屏幕和通知效果。",
              category: "系统", symbol: "display", launchName: "LCD and Notifications",
              requirement: "屏幕效果由 Flipper 本机呈现。"),
        .init(id: "expansion", title: "扩展模块", summary: "查看扩展模块的连接设置。",
              category: "系统", symbol: "cable.connector", launchName: "Expansion Modules",
              requirement: "需要兼容的外接硬件。"),
        .init(id: "clock", title: "时钟与闹钟", summary: "打开设备的时间工具。",
              category: "系统", symbol: "clock", launchName: "Clock & Alarm",
              requirement: "由 Flipper 本机运行。"),
        .init(id: "passport", title: "海豚档案", summary: "查看设备的海豚状态。",
              category: "系统", symbol: "person.crop.circle", launchName: "Passport",
              requirement: "内容来自设备本机。"),
        .init(id: "about", title: "关于设备", summary: "查看固件与设备信息。",
              category: "系统", symbol: "info.circle", launchName: "About",
              requirement: "信息以 Flipper 实际安装固件为准。"),
    ]

    public static func installed(path: String) -> FlipperFunction? {
        guard path.hasPrefix("/ext/apps/"), path.utf8.count <= 240,
              !path.contains("\\"), !path.contains("\0") else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard (parts.count == 4 || parts.count == 5),
              parts[0].isEmpty, parts[1] == "ext", parts[2] == "apps",
              !parts.dropFirst().contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
        let filename = String(parts[parts.count - 1])
        guard filename.lowercased().hasSuffix(".fap"), filename.count > 4 else { return nil }
        let stem = String(filename.dropLast(4))
        let title = stem.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let category = parts.count == 5 ? String(parts[3]) : "其他应用"
        return .init(id: path, title: title, summary: "已安装在 Flipper 的应用。",
                     category: category, symbol: "app", launchName: path,
                     requirement: "从设备 SD 卡上的应用文件启动。", isInstalledApp: true)
    }
}
