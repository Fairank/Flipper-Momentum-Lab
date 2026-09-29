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

    /// Display metadata only. An entry appears after SD discovery confirms its path;
    /// its Chinese title never replaces the path sent to App.Start.
    private static let installedDescriptions: [String: (title: String, summary: String, symbol: String)] = [
        "/ext/apps/Tools/clock.fap": ("床头时钟", "显示时间、设置闹钟并使用秒表。", "clock"),
        "/ext/apps/Tools/analog_clock.fap": ("指针时钟", "在 Flipper 屏幕上显示指针时钟。", "clock"),
        "/ext/apps/Tools/segment_clock.fap": ("数码管时钟", "显示数字时间，设置闹钟与屏幕亮度。", "clock"),
        "/ext/apps/Tools/pomodoro_timer.fap": ("番茄钟", "用专注与休息计时安排学习或工作。", "timer"),
        "/ext/apps/Tools/calendar.fap": ("日历", "选择年份与月份，查看完整月历。", "calendar"),
        "/ext/apps/Tools/net_calculator.fap": ("子网计算器", "离线计算 IPv4 网段及不同主机数量的子网划分。", "network"),
        "/ext/apps/Tools/multi_counter.fap": ("多人计数器", "使用四个独立计数器记录分数或次数。", "number"),
        "/ext/apps/Tools/sd_info.fap": ("SD 卡信息", "查看存储卡信息并在设备上进行读写测试。", "sdcard"),
        "/ext/apps/Tools/flipper_chronometer.fap": ("秒表", "在 Flipper 上记录经过的时间。", "stopwatch"),
        "/ext/apps/Tools/trackerflipx.fap": ("任务计时器", "记录任务用时并保存为 CSV 文件。", "checklist"),
        "/ext/apps/Tools/flipnote.fap": ("FlipNote 记事本", "打开、编辑和保存设备上的文本文件。", "note.text"),
        "/ext/apps/Tools/gps_rpc.fap": ("手机 GPS", "显示手机共享的经纬度、速度、方向和精度；先开启设备页的定位共享。", "location"),
        "/ext/apps/Tools/example_network.fap": ("手机联网测试", "开启网络共享后，在设备上按确定键请求示例网页并保存至应用目录。", "network"),
        "/ext/apps/Tools/brainfuck.fap": ("Brainfuck 解释器", "在设备上运行 Brainfuck 程序并查看输出。", "terminal"),
        "/ext/apps/Games/chess_clock.fap": ("棋钟", "为对弈双方分别计时。", "clock"),
        "/ext/apps/Games/dice_app.fap": ("桌游骰子", "选择不同面数的骰子，生成投掷结果。", "dice"),
        "/ext/apps/Games/reaction.fap": ("反应测试", "按屏幕提示测量按键反应时间。", "hand.tap"),
        "/ext/apps/Games/mandelbrotset.fap": ("曼德勃罗分形", "浏览和缩放数学分形。", "square.grid.3x3"),
        "/ext/apps/Games/montyhall.fap": ("三门问题", "用选门游戏体验概率问题。", "door.left.hand.open"),
        "/ext/apps/Games/racegame.fap": ("赛车", "在 Flipper 上玩赛车游戏。", "car"),
        "/ext/apps/Media/ocarina.fap": ("陶笛", "使用设备按键演奏音符。", "music.note"),
        "/ext/apps/Infrared/pause_timer.fap": ("红外暂停定时器", "学习暂停按键的红外信号，并在倒计时结束时发送。", "timer"),
        "/ext/apps/Bluetooth/hid_ble.fap": ("蓝牙遥控器", "将 Flipper 用作键盘、鼠标或演示遥控器；切换连接可能断开当前 App。", "keyboard"),
        "/ext/apps/USB/hid_usb.fap": ("USB 遥控器", "通过 Flipper 的 USB 连接控制电脑键盘、鼠标或演示。", "keyboard"),
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
        let folder = parts.count == 5 ? String(parts[3]) : "其他应用"
        let category = ["Tools": "工具", "Games": "游戏", "Bluetooth": "蓝牙",
                        "Infrared": "红外", "Media": "媒体", "Misc": "其他"][folder] ?? folder
        if let description = installedDescriptions[path] {
            return .init(id: path, title: description.title, summary: description.summary,
                         category: category,
                         symbol: description.symbol, launchName: path,
                         requirement: "已发现 SD 卡应用；在 Flipper 本机执行。", isInstalledApp: true)
        }
        return .init(id: path, title: title, summary: "已安装在 Flipper 的应用。",
                     category: category, symbol: "app", launchName: path,
                     requirement: "从设备 SD 卡上的应用文件启动。", isInstalledApp: true)
    }
}
