import Foundation

public enum NFCComparisonAddress: Equatable, Sendable {
    case field(String)
    case page(Int)
    case block(Int)

    public var title: String {
        switch self {
        case let .field(name): return "字段 · \(name)"
        case let .page(index): return "页 \(index)"
        case let .block(index): return "块 \(index)"
        }
    }
}

public struct NFCComparisonDifference: Equatable, Sendable {
    public let address: NFCComparisonAddress
    /// nil means an absent field, whereas a literal ?? means an unknown byte.
    public let left: String?
    public let right: String?
    /// Zero-based byte positions, available for numbered storage records.
    public let changedByteOffsets: [Int]
}

public struct NFCComparisonReport: Equatable, Sendable {
    public let differences: [NFCComparisonDifference]
    public let totalDifferenceCount: Int
    public let leftUnknownByteCount: Int
    public let rightUnknownByteCount: Int
    public var limited: Bool { totalDifferenceCount > differences.count }
}

struct NFCComparisonField {
    let key: String
    let value: String
    let line: Int
    let bytes: [UInt8?]?
    let number: Int64?
}

struct NFCComparisonSource {
    let version: UInt32
    let fields: [NFCComparisonField]
}

/// Compare saved files by address, never by physical line position. Validates
/// both entire inputs before producing a bounded report. No card/RF operation.
public enum NFCRecordComparison {
    public static let maxStorageRows = 4096
    public static let maxReportedDifferences = 200
    private static let ultralightTypes: Set<String> = [
        "NTAG/Ultralight", "NTAG213", "NTAG215", "NTAG216",
        "Mifare Ultralight", "Mifare Ultralight 11", "Mifare Ultralight 21",
        "Mifare Ultralight C", "Mifare Ultralight Origin",
    ]
    static let supportedTypes = Set([
        "UID", "ISO14443-3A", "ISO14443-3B", "ISO14443-4A", "ISO14443-4B",
        "NTAG/Ultralight", "Mifare Classic", "ST25TB",
    ]).union(ultralightTypes)

    private struct Document {
        var fields: [String: String]
        var pages: [Int: [UInt8?]]
        var blocks: [Int: [UInt8?]]
        var unknownBytes: Int
    }

    public static func compare(_ left: String, _ right: String) throws -> NFCComparisonReport {
        let a = try parse(RecordAnalyzer.nfcComparisonSource(left))
        let b = try parse(RecordAnalyzer.nfcComparisonSource(right))
        var differences: [NFCComparisonDifference] = []
        var total = 0
        func add(_ address: NFCComparisonAddress, _ x: String?, _ y: String?, _ offsets: [Int] = []) {
            guard x != y else { return }
            total += 1
            if differences.count < maxReportedDifferences {
                differences.append(NFCComparisonDifference(address: address, left: x, right: y, changedByteOffsets: offsets))
            }
        }
        for key in Set(a.fields.keys).union(b.fields.keys).sorted() {
            add(.field(key), a.fields[key], b.fields[key])
        }
        func storage(_ x: [Int: [UInt8?]], _ y: [Int: [UInt8?]], page: Bool) {
            for index in Set(x.keys).union(y.keys).sorted() {
                let first = x[index], second = y[index]
                let count = max(first?.count ?? 0, second?.count ?? 0)
                let changed = (0..<count).filter { offset in
                    // A missing record/byte must remain different from an unknown byte.
                    guard let first, let second, offset < first.count, offset < second.count else { return true }
                    return first[offset] != second[offset]
                }
                add(page ? .page(index) : .block(index), first.map(hex), second.map(hex), changed)
            }
        }
        storage(a.pages, b.pages, page: true)
        storage(a.blocks, b.blocks, page: false)
        return NFCComparisonReport(differences: differences, totalDifferenceCount: total,
            leftUnknownByteCount: a.unknownBytes, rightUnknownByteCount: b.unknownBytes)
    }

    private static func hex(_ bytes: [UInt8?]) -> String {
        bytes.map { $0.map { String(format: "%02X", $0) } ?? "??" }.joined(separator: " ")
    }

    private static func parse(_ source: NFCComparisonSource) throws -> Document {
        var entries: [String: NFCComparisonField] = [:]
        var result = Document(fields: ["Version": String(source.version)], pages: [:], blocks: [:], unknownBytes: 0)
        var storageLines: [String: Int] = [:]
        for entry in source.fields {
            guard entries[entry.key] == nil else { throw invalid(entry, "字段重复") }
            entries[entry.key] = entry
        }
        let type = try text("Device type", entries)
        guard supportedTypes.contains(type) else { throw invalid(entries["Device type"]!, "此类型尚不支持结构化比较") }
        let isUltralight = ultralightTypes.contains(type)
        guard let uid = entries["UID"], let uidBytes = uid.bytes, !uidBytes.isEmpty, !uidBytes.contains(nil) else {
            throw RecordAnalysisError.invalidField(field: "UID", line: entries["UID"]?.line ?? 1, reason: "应为已知的两位十六进制字节")
        }
        let uidLengths = type == "ST25TB" ? [8] : (type.hasSuffix("B") ? [4] : [4, 7, 10])
        guard uidLengths.contains(uidBytes.count) else { throw invalid(uid, "UID 长度不符合设备类型") }

        for entry in source.fields {
            let isPage = entry.key.hasPrefix("Page ")
            let isBlock = entry.key.hasPrefix("Block ")
            if isPage || isBlock {
                let raw = entry.key.dropFirst(isPage ? 5 : 6)
                guard !raw.isEmpty, raw.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                      let index = Int(raw), index < maxStorageRows else {
                    throw invalid(entry, "存储编号应为 0…\(maxStorageRows - 1) 的十进制整数")
                }
                let key = "\(isPage ? "P" : "B")\(index)"
                guard storageLines[key] == nil else { throw invalid(entry, "重复的存储编号 \(index)") }
                storageLines[key] = entry.line
                guard storageLines.count <= maxStorageRows else {
                    throw RecordAnalysisError.limitExceeded(item: "NFC 存储行数量", limit: maxStorageRows)
                }
                let width = isPage ? 4 : (type == "ST25TB" ? 4 : 16)
                guard (isPage && isUltralight) || (!isPage && (type == "Mifare Classic" || type == "ST25TB")) else {
                    throw invalid(entry, "此设备类型不使用这种存储行")
                }
                guard let bytes = entry.bytes, bytes.count == width else {
                    throw invalid(entry, "应有 \(width) 个两位十六进制字节；未知字节写作 ??")
                }
                // Classic explicitly saves unread data as ??; Ultralight and
                // ST25TB save concrete bytes. Do not invent unknown page data.
                if type != "Mifare Classic", bytes.contains(nil) { throw invalid(entry, "此格式的存储行不接受未知字节") }
                if isPage { result.pages[index] = bytes } else { result.blocks[index] = bytes }
                result.unknownBytes += bytes.filter { $0 == nil }.count
            } else {
                if entry.key == "Filetype" || entry.key == "Version" { throw invalid(entry, "文件头字段不能再次出现") }
                if numericKeys.contains(entry.key) || entry.key.hasPrefix("Counter ") {
                    guard let value = entry.number, value <= Int64(UInt32.max) else { throw invalid(entry, "应为非负的 32 位十进制整数") }
                    result.fields[entry.key] = String(value)
                } else if entry.key == "Key A map" || entry.key == "Key B map" {
                    let value = entry.value.trimmingCharacters(in: .whitespaces)
                    guard value.utf8.count == 16, value.utf8.allSatisfy({ byte in
                        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
                    }) else { throw invalid(entry, "旧版密钥位图应为 16 位连续十六进制字符") }
                    result.fields[entry.key] = value.uppercased()
                } else if let width = fixedHexWidths[entry.key] ?? (entry.key.hasPrefix("Tearing ") ? 1 : nil) {
                    guard let bytes = entry.bytes, bytes.count == width, !bytes.contains(nil) else {
                        throw invalid(entry, "应有 \(width) 个已知的两位十六进制字节")
                    }
                    result.fields[entry.key] = hex(bytes)
                } else if entry.key == "ATS" || entry.key == "T1...Tk" {
                    guard let bytes = entry.bytes, !bytes.isEmpty, bytes.count <= 255, !bytes.contains(nil) else {
                        throw invalid(entry, "应有 1…255 个已知的两位十六进制字节")
                    }
                    result.fields[entry.key] = hex(bytes)
                } else if let bytes = entry.bytes, !bytes.isEmpty {
                    result.fields[entry.key] = hex(bytes)
                    result.unknownBytes += bytes.filter { $0 == nil }.count
                } else {
                    result.fields[entry.key] = entry.value.trimmingCharacters(in: .whitespaces)
                }
            }
        }
        if isUltralight {
            let count = try number("Pages total", entries)
            guard count <= 510 else { throw invalid(entries["Pages total"]!, "页总数超过固件上限 510") }
            if entries["Pages read"] != nil, try number("Pages read", entries) > count {
                throw invalid(entries["Pages read"]!, "已读页数超过页总数")
            }
            try requireComplete(result.pages, count: count, name: "Page")
        } else if type == "Mifare Classic" {
            let card = try text("Mifare Classic type", entries)
            guard let count = ["MINI": 20, "1K": 64, "2K": 128, "4K": 256][card] else {
                throw invalid(entries["Mifare Classic type"]!, "未知的 Classic 容量")
            }
            try requireComplete(result.blocks, count: count, name: "Block")
        } else if type == "ST25TB" {
            let card = try text("ST25TB Type", entries)
            guard let count = ["512AT": 16, "512AC": 16, "X512": 16, "2K": 64, "4K": 128, "X4K": 128][card] else {
                throw invalid(entries["ST25TB Type"]!, "未知的 ST25TB 容量")
            }
            try requireComplete(result.blocks, count: count, name: "Block")
            guard let otp = entries["System OTP Block"], let bytes = otp.bytes, bytes.count == 4, !bytes.contains(nil) else {
                throw RecordAnalysisError.invalidField(field: "System OTP Block", line: entries["System OTP Block"]?.line ?? 1, reason: "应有 4 个已知十六进制字节")
            }
        }
        return result
    }

    private static let numericKeys: Set<String> = ["Data format version", "Pages total", "Pages read", "Failed authentication attempts"]
    private static let fixedHexWidths = ["ATQA": 2, "SAK": 1, "T0": 1,
        "TA(1)": 1, "TB(1)": 1, "TC(1)": 1, "Application data": 4, "Protocol info": 3,
        "Signature": 32, "AES signature": 48, "Mifare version": 8, "System OTP Block": 4]
    private static func invalid(_ entry: NFCComparisonField, _ reason: String) -> RecordAnalysisError {
        .invalidField(field: entry.key, line: entry.line, reason: reason)
    }
    private static func text(_ key: String, _ entries: [String: NFCComparisonField]) throws -> String {
        guard let entry = entries[key] else { throw RecordAnalysisError.missingField(field: key, line: nil) }
        let value = entry.value.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { throw invalid(entry, "值为空") }
        return value
    }
    private static func number(_ key: String, _ entries: [String: NFCComparisonField]) throws -> Int {
        guard let entry = entries[key] else { throw RecordAnalysisError.missingField(field: key, line: nil) }
        guard let value = entry.number, value <= Int64(maxStorageRows), let count = Int(exactly: value) else {
            throw invalid(entry, "应为 0…\(maxStorageRows) 的十进制整数")
        }
        return count
    }
    private static func requireComplete(_ rows: [Int: [UInt8?]], count: Int, name: String) throws {
        for index in 0..<count where rows[index] == nil {
            throw RecordAnalysisError.missingField(field: "\(name) \(index)（存储数据截断）", line: nil)
        }
        guard rows.count == count else {
            throw RecordAnalysisError.invalidField(field: name, line: 1, reason: "存储编号超出声明容量")
        }
    }
}
