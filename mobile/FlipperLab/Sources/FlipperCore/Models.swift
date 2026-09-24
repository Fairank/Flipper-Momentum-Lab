import Foundation

public enum RecordKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case infrared, subGHz, nfc, rfid, iButton, serial
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .infrared: return "红外遥控"
        case .subGHz: return "Sub-GHz 记录"
        case .nfc: return "NFC 标签"
        case .rfid: return "低频 RFID"
        case .iButton: return "iButton"
        case .serial: return "串口日志"
        }
    }
    public var fileExtension: String {
        switch self {
        case .infrared: return "ir"
        case .subGHz: return "sub"
        case .nfc: return "nfc"
        case .rfid: return "rfid"
        case .iButton: return "ibtn"
        case .serial: return "txt"
        }
    }
    public var deviceDirectory: String? {
        switch self {
        case .infrared: return "/ext/infrared"
        case .subGHz: return "/ext/subghz"
        case .nfc: return "/ext/nfc"
        case .rfid: return "/ext/lfrfid"
        case .iButton: return "/ext/ibutton"
        case .serial: return nil
        }
    }
}

public struct CaptureRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public let kind: RecordKind
    public let createdAt: Date
    public var sourcePath: String?
    public var tags: [String]
    public var notes: String
    public let rawText: String

    public init(id: UUID = UUID(), name: String, kind: RecordKind, createdAt: Date = Date(),
                sourcePath: String? = nil, tags: [String] = [], notes: String = "", rawText: String) {
        self.id = id
        self.name = name
        self.kind = kind
        self.createdAt = createdAt
        self.sourcePath = sourcePath
        self.tags = tags
        self.notes = notes
        self.rawText = rawText
    }
}

public struct AnalysisFact: Equatable, Sendable {
    public let title: String
    public let value: String
    public init(_ title: String, _ value: String) { self.title = title; self.value = value }
}

public struct AnalysisReport: Equatable, Sendable {
    public var facts: [AnalysisFact]
    public var notes: [String]
    public var buttons: [String]
    public var pulseDurations: [Double]
    public init(facts: [AnalysisFact] = [], notes: [String] = [], buttons: [String] = [], pulseDurations: [Double] = []) {
        self.facts = facts; self.notes = notes; self.buttons = buttons; self.pulseDurations = pulseDurations
    }
}
