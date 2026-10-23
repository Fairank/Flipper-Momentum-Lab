import Foundation

/// Presentation filters only. These never create a launch path or infer installation.
public enum FunctionCatalogSource: String, CaseIterable, Sendable {
    case all, common, installed

    public var title: String {
        switch self {
        case .all: return "全部"
        case .common: return "常用"
        case .installed: return "已安装"
        }
    }
}

public enum FunctionCatalogCategory: String, CaseIterable, Identifiable, Sendable {
    case wireless, tools, games, media, expansion, system, other
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .wireless: return "无线识别"
        case .tools: return "实用工具"
        case .games: return "游戏"
        case .media: return "媒体"
        case .expansion: return "扩展模块"
        case .system: return "系统"
        case .other: return "其他应用"
        }
    }

    public var symbol: String {
        switch self {
        case .wireless: return "antenna.radiowaves.left.and.right"
        case .tools: return "wrench.and.screwdriver"
        case .games: return "gamecontroller"
        case .media: return "music.note"
        case .expansion: return "cable.connector"
        case .system: return "gearshape"
        case .other: return "square.grid.2x2"
        }
    }

    public static func category(of function: FlipperFunction) -> Self {
        if !function.isInstalledApp {
            if ["gpio", "expansion"].contains(function.id) { return .expansion }
            switch function.category {
            case "无线与识别": return .wireless
            case "工具": return .tools
            case "系统": return .system
            default: return .other
            }
        }
        // Use the already-validated root folder; translated nested folder names are not IDs.
        let folder = function.launchName.split(separator: "/").dropFirst(2).first.map(String.init)
        switch folder {
        case "NFC", "RFID", "Infrared", "Bluetooth", "Sub-GHz", "Sub-Ghz", "iButton": return .wireless
        case "Tools", "USB", "GPS", "Scripts": return .tools
        case "Games": return .games
        case "Media": return .media
        case "GPIO", "ESP", "Hardware", "FlipBoard", "FlipperHTTP", "MALVEKE", "MAYHEM", "NRF24", "Sensors", "VGM": return .expansion
        case "Settings", "Debug": return .system
        default: return .other
        }
    }
}

public struct FunctionCatalogQuery: Equatable, Sendable {
    public var source: FunctionCatalogSource
    public var category: FunctionCatalogCategory?
    public var search: String

    public init(source: FunctionCatalogSource = .all, category: FunctionCatalogCategory? = nil, search: String = "") {
        self.source = source; self.category = category; self.search = search
    }

    /// Whitespace separates terms; every term must match, in any order and case.
    public func matches(text: String) -> Bool {
        search.split(whereSeparator: { $0.isWhitespace }).allSatisfy {
            text.localizedCaseInsensitiveContains(String($0))
        }
    }

    public func includes(_ function: FlipperFunction, ignoringCategory: Bool = false) -> Bool {
        switch source {
        case .all: break
        case .common: if function.isInstalledApp { return false }
        case .installed: if !function.isInstalledApp { return false }
        }
        let group = FunctionCatalogCategory.category(of: function)
        if !ignoringCategory, let category, category != group { return false }
        return matches(text: [function.title, function.summary, function.category, group.title, function.launchName].joined(separator: " "))
    }

    public func filter(_ functions: [FlipperFunction]) -> [FlipperFunction] {
        functions.filter { includes($0) }
    }
}
