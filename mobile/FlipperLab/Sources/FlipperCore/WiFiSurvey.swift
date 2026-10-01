import Foundation

/// A single access point in a saved Wi-Fi scan. No password or client data is stored.
public struct WiFiAccessPoint: Equatable, Sendable, Identifiable {
    public let ssid: String
    public let bssid: String
    public let channel: Int
    public let rssi: Int
    public let security: String

    public var id: String { bssid + ":\(channel)" }
}

public enum WiFiSurveyError: Error, Equatable, Sendable {
    case tooLarge
    case invalidHeader
    case invalidColumns
    case malformedRow(line: Int, reason: String)
    case tooManyNetworks
    case duplicateNetwork(line: Int)
}

extension WiFiSurveyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .tooLarge:
            return "Wi-Fi 扫描文件超过 2 MiB，未导入。"
        case .invalidHeader:
            return "未找到受支持的 Wi-Fi 扫描文件头或 ESP32 扫描日志。"
        case .invalidColumns:
            return "扫描文件第二行应为 ssid,bssid,channel,rssi,security。"
        case let .malformedRow(line, reason):
            return "扫描文件第 \(line) 行无效：\(reason)。"
        case .tooManyNetworks:
            return "扫描文件超过 512 个接入点，未导入。"
        case let .duplicateNetwork(line):
            return "扫描文件第 \(line) 行的 BSSID 和信道组合重复。"
        }
    }
}

/// Bounded, offline parser for saved AP surveys and ESP32 scan console logs.
public struct WiFiSurvey: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case flipperLabFile
        case marauderScanLog

        public var title: String {
            switch self {
            case .flipperLabFile: return "Flipper Lab 扫描文件"
            case .marauderScanLog: return "ESP32 扫描日志"
            }
        }
    }

    public static let marker = "# Flipper Lab WiFi Survey v1"
    public static let columns = "ssid,bssid,channel,rssi,security"
    public static let maxBytes = 2 * 1024 * 1024
    public static let maxAccessPoints = 512

    public let accessPoints: [WiFiAccessPoint]
    public let source: Source

    public var uniqueSSIDCount: Int {
        Set(accessPoints.map(\.ssid).filter { !$0.isEmpty }).count
    }

    public var channelCounts: [Int: Int] {
        var counts: [Int: Int] = [:]
        for point in accessPoints { counts[point.channel, default: 0] += 1 }
        return counts
    }

    public var strongestFirst: [WiFiAccessPoint] {
        accessPoints.sorted {
            if $0.rssi != $1.rssi { return $0.rssi > $1.rssi }
            if $0.channel != $1.channel { return $0.channel < $1.channel }
            return $0.bssid < $1.bssid
        }
    }

    public static func parse(_ text: String) throws -> WiFiSurvey {
        guard text.utf8.count <= maxBytes else { throw WiFiSurveyError.tooLarge }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        guard let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              lines[first].replacingOccurrences(of: "\u{FEFF}", with: "") == marker else {
            return try parseMarauderLog(lines)
        }
        guard first + 1 < lines.count, lines[first + 1] == columns else {
            throw WiFiSurveyError.invalidColumns
        }

        var points: [WiFiAccessPoint] = []
        points.reserveCapacity(min(lines.count - first - 2, maxAccessPoints))
        var seen: Set<String> = []
        if first + 2 < lines.count {
            for index in (first + 2)..<lines.count {
                let line = lines[index]
                if line.isEmpty { continue }
                guard points.count < maxAccessPoints else { throw WiFiSurveyError.tooManyNetworks }
                let fields = try parseCSVRow(line, lineNumber: index + 1)
                guard fields.count == 5 else {
                    throw WiFiSurveyError.malformedRow(line: index + 1, reason: "应有 5 列")
                }
                let ssid = fields[0]
                let security = fields[4]
                guard ssid.utf8.count <= 128, !ssid.contains("\u{FFFD}"),
                      !ssid.unicodeScalars.contains(where: { $0.value < 32 }) else {
                    throw WiFiSurveyError.malformedRow(line: index + 1, reason: "网络名称含无效字符或过长")
                }
                guard !security.isEmpty, security.utf8.count <= 64, !security.contains("\u{FFFD}"),
                      !security.unicodeScalars.contains(where: { $0.value < 32 }) else {
                    throw WiFiSurveyError.malformedRow(line: index + 1, reason: "安全类型为空、过长或含无效字符")
                }
                guard let bssid = normalizedBSSID(fields[1]) else {
                    throw WiFiSurveyError.malformedRow(line: index + 1, reason: "BSSID 应为六组十六进制字节")
                }
                guard let channel = Int(fields[2]), (1...196).contains(channel) else {
                    throw WiFiSurveyError.malformedRow(line: index + 1, reason: "信道必须为 1 至 196 的整数")
                }
                guard let rssi = Int(fields[3]), (-127...0).contains(rssi) else {
                    throw WiFiSurveyError.malformedRow(line: index + 1, reason: "RSSI 必须为 -127 至 0 dBm 的整数")
                }
                let identity = bssid + ":\(channel)"
                guard seen.insert(identity).inserted else {
                    throw WiFiSurveyError.duplicateNetwork(line: index + 1)
                }
                points.append(WiFiAccessPoint(ssid: ssid, bssid: bssid, channel: channel,
                                              rssi: rssi, security: security))
            }
        }
        return WiFiSurvey(accessPoints: points, source: .flipperLabFile)
    }

    /// Recognize saved AP scan output from the bundled ESP32 companion app. Other
    /// console logs remain serial records, even if they mention RSSI elsewhere.
    public static func looksLikeMarauderScanLog(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
        let started = lines.prefix(128).contains { line in
            line.contains("Starting AP scan") || line.contains("#scanap")
        }
        return started && lines.contains { line in
            line.contains("RSSI:") && line.contains("Ch:") &&
                line.contains("BSSID:") && line.contains("ESSID:")
        }
    }

    private static func parseMarauderLog(_ lines: [String]) throws -> WiFiSurvey {
        guard looksLikeMarauderScanLog(lines.joined(separator: "\n")) else {
            throw WiFiSurveyError.invalidHeader
        }
        var points: [WiFiAccessPoint] = []
        var positions: [String: Int] = [:]
        for (index, line) in lines.enumerated() {
            guard line.contains("RSSI:"), line.contains("Ch:"),
                  line.contains("BSSID:"), line.contains("ESSID:") else { continue }
            let row = line.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "> ", with: "", options: .anchored)
            guard row.hasPrefix("RSSI:"),
                  let (rssiField, restAfterRssi) = splitOnce(String(row.dropFirst(5)), at: "Ch:"),
                  let (channelField, restAfterChannel) = splitOnce(restAfterRssi, at: "BSSID:"),
                  let (bssidField, ssidField) = splitOnce(restAfterChannel, at: "ESSID:"),
                  let rssi = Int(rssiField.trimmingCharacters(in: .whitespaces)),
                  (-127...0).contains(rssi),
                  let channel = Int(channelField.trimmingCharacters(in: .whitespaces)),
                  (1...196).contains(channel),
                  let bssid = normalizedBSSID(bssidField.trimmingCharacters(in: .whitespaces)) else {
                throw WiFiSurveyError.malformedRow(line: index + 1, reason: "ESP32 扫描字段无效")
            }
            let ssid = ssidField.trimmingCharacters(in: .whitespaces)
            guard ssid.utf8.count <= 128, !ssid.contains("\u{FFFD}"),
                  !ssid.unicodeScalars.contains(where: { $0.value < 32 }) else {
                throw WiFiSurveyError.malformedRow(line: index + 1, reason: "网络名称含无效字符或过长")
            }
            let point = WiFiAccessPoint(ssid: ssid, bssid: bssid, channel: channel,
                                        rssi: rssi, security: "未记录")
            let identity = point.id
            if let existing = positions[identity] {
                if point.rssi > points[existing].rssi { points[existing] = point }
            } else {
                guard points.count < maxAccessPoints else { throw WiFiSurveyError.tooManyNetworks }
                positions[identity] = points.count
                points.append(point)
            }
        }
        return WiFiSurvey(accessPoints: points, source: .marauderScanLog)
    }

    private static func splitOnce(_ value: String, at marker: String) -> (String, String)? {
        guard let range = value.range(of: marker) else { return nil }
        return (String(value[..<range.lowerBound]), String(value[range.upperBound...]))
    }

    private static func normalizedBSSID(_ value: String) -> String? {
        let octets = value.split(separator: ":", omittingEmptySubsequences: false)
        guard octets.count == 6, octets.allSatisfy({ octet in
            octet.utf8.count == 2 && octet.utf8.allSatisfy { byte in
                (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 70) || (byte >= 97 && byte <= 102)
            }
        }) else { return nil }
        return value.uppercased()
    }

    /// One CSV record only: quoted fields may contain commas and doubled quotes, not newlines.
    private static func parseCSVRow(_ line: String, lineNumber: Int) throws -> [String] {
        enum State: Equatable { case plain, quoted, afterQuote }
        var state = State.plain
        var fields: [String] = []
        var field = ""
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            switch state {
            case .plain:
                if character == "," {
                    fields.append(field); field = ""
                } else if character == "\"" {
                    guard field.isEmpty else {
                        throw WiFiSurveyError.malformedRow(line: lineNumber, reason: "引号只能位于字段开头")
                    }
                    state = .quoted
                } else {
                    field.append(character)
                }
            case .quoted:
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\""); index += 1
                    } else {
                        state = .afterQuote
                    }
                } else {
                    field.append(character)
                }
            case .afterQuote:
                guard character == "," else {
                    throw WiFiSurveyError.malformedRow(line: lineNumber, reason: "结束引号后只能接逗号")
                }
                fields.append(field); field = ""; state = .plain
            }
            index += 1
        }
        guard state != .quoted else {
            throw WiFiSurveyError.malformedRow(line: lineNumber, reason: "引号未闭合")
        }
        fields.append(field)
        return fields
    }
}
