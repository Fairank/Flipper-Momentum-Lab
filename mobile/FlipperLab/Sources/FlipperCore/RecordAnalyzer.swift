import Foundation

// MARK: - 错误

/// 记录识别与分析错误；`errorDescription` 为面向用户的中文说明。
public enum RecordAnalysisError: Error, Equatable, Sendable {
    /// 没有内容，或只有空白字符。
    case emptyInput
    /// UTF-8 字节数超过上限。
    case inputTooLarge(byteCount: Int, limit: Int)
    /// 含无法解码的字节，或解码时产生的替换字符 U+FFFD。
    case invalidUTF8
    /// 含二进制数据或不允许的控制字符；`line` 从 1 开始。
    case binaryContent(line: Int)
    /// 没有 Flipper 文件头，扩展名也不是支持的串口日志类型。
    case unrecognizedFormat(fileExtension: String)
    /// 需要 Flipper 文件头（`Filetype`/`Version`），但文件没有。
    case missingHeader(expected: RecordKind)
    case unsupportedFileType(String)
    case missingVersion
    case unsupportedVersion(fileType: String, version: String)
    /// 已识别的扩展名与文件头声明的类型冲突。
    case extensionMismatch(fileExtension: String, headerKind: RecordKind)
    /// 文件头声明的类型与要求分析的类型冲突。
    case kindMismatch(requested: RecordKind, detected: RecordKind)
    case malformedLine(line: Int, reason: String)
    /// 缺少必需字段；`line` 为相关位置（如所属按钮的 `name` 行）。
    case missingField(field: String, line: Int?)
    case invalidField(field: String, line: Int, reason: String)
    /// 字段不受支持，或不在固件读取顺序要求的位置。
    case unexpectedField(field: String, line: Int)
    case duplicateButtonName(name: String, line: Int, firstLine: Int)
    case limitExceeded(item: String, limit: Int)
}

extension RecordAnalysisError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "文件内容为空，没有可分析的数据。"
        case let .inputTooLarge(byteCount, limit):
            return "文件大小为 \(RecordAnalyzer.TextFormat.bytes(byteCount))，超过上限 \(RecordAnalyzer.TextFormat.bytes(limit))。"
        case .invalidUTF8:
            return "文件不是有效的 UTF-8 文本：含无法解码的字节或替换字符（U+FFFD）。"
        case let .binaryContent(line):
            return "第 \(line) 行含二进制数据或不允许的控制字符，无法作为文本记录分析。"
        case let .unrecognizedFormat(fileExtension):
            let shown = fileExtension.isEmpty ? "（无扩展名）" : "“.\(fileExtension)”"
            return "无法识别文件类型：没有 Flipper 文件头或 Wi-Fi 扫描标记，扩展名\(shown)也不是支持的日志类型（.txt、.log）。"
        case let .missingHeader(expected):
            return "缺少 Flipper 文件头（第一条有效内容应为“Filetype: …”），无法按“\(expected.title)”解析。"
        case let .unsupportedFileType(fileType):
            return "不支持的 Flipper 文件类型“\(fileType)”。"
        case .missingVersion:
            return "文件头缺少“Version: …”行（应紧跟在 Filetype 之后）。"
        case let .unsupportedVersion(fileType, version):
            return "“\(fileType)”的格式版本“\(version)”无效或不受支持。"
        case let .extensionMismatch(fileExtension, headerKind):
            return "扩展名“.\(fileExtension)”与文件头声明的“\(headerKind.title)”不一致，已停止解析，以免按错误的类型处理。"
        case let .kindMismatch(requested, detected):
            return "文件头表明这是“\(detected.title)”，与要求的“\(requested.title)”不一致。"
        case let .malformedLine(line, reason):
            return "第 \(line) 行格式错误：\(reason)。"
        case let .missingField(field, line):
            if let line {
                return "缺少必需字段“\(field)”（相关位置：第 \(line) 行）。"
            }
            return "缺少必需字段“\(field)”。"
        case let .invalidField(field, line, reason):
            return "第 \(line) 行的字段“\(field)”无效：\(reason)。"
        case let .unexpectedField(field, line):
            return "第 \(line) 行出现不支持或位置不正确的字段“\(field)”。"
        case let .duplicateButtonName(name, line, firstLine):
            return "第 \(line) 行的按钮名称“\(name)”与第 \(firstLine) 行重复；遥控器文件中的按钮名称必须唯一。"
        case let .limitExceeded(item, limit):
            return "\(item)超过上限 \(limit)。"
        }
    }
}

// MARK: - 分析入口

/// Flipper 记录文本的类型识别与离线分析（仅依赖 Foundation）。
///
/// 解析在 UTF-8 字节上进行：输入不超过 2 MiB，统计排序至多 O(n log n)；
/// 数值溢出、NaN、无穷大都以错误返回，不会触发运行时陷阱。
/// 报告只描述文件内容与时长统计，不做协议识别、解码或安全判断。
public enum RecordAnalyzer {
    /// 可分析文本的最大 UTF-8 字节数（2 MiB）。读取文件前可据此限制读取量。
    public static let maxInputBytes = 2 * 1024 * 1024
    /// `AnalysisReport.pulseDurations` 最多包含的点数。
    public static let maxPlotPoints = 512
    /// 单个红外原始信号的时长数量上限，与固件 `MAX_TIMINGS_AMOUNT` 一致。
    public static let maxInfraredTimings = 1024
    /// Sub-GHz 文件中全部 `RAW_Data` 样本的数量上限。
    public static let maxSubGhzSamples = 1_000_000

    /// 把文件字节解码为文本：先限制大小，再拒绝无效 UTF-8、空内容与二进制数据。
    /// 返回的字符串与原始字节一一对应（保留 BOM 与换行符），不做规范化。
    public static func decodeText(_ data: Data) throws -> String {
        guard data.count <= maxInputBytes else {
            throw RecordAnalysisError.inputTooLarge(byteCount: data.count, limit: maxInputBytes)
        }
        // 无效字节会被解码为 U+FFFD，随后由 TextInput 统一拒绝。
        let text = String(decoding: data, as: UTF8.self)
        _ = try TextInput(text)
        return text
    }

    /// 识别记录类型。文件头优先；已识别的扩展名与文件头冲突时报错，不做改判。
    /// 没有 Flipper 文件头时接受 `.txt`/`.log` 日志或带专用标记的 Wi-Fi 扫描文件。
    public static func detectKind(text: String, fileExtension: String) throws -> RecordKind {
        let input = try TextInput(text)
        let normalized = normalizedExtension(fileExtension)
        let extensionKind = kind(forExtension: normalized)
        if isWiFiSurvey(text) {
            guard ["wscan", "csv", "txt", "log"].contains(normalized) else {
                throw RecordAnalysisError.extensionMismatch(fileExtension: TextFormat.display(normalized), headerKind: .wifiSurvey)
            }
            _ = try WiFiSurvey.parse(text)
            return .wifiSurvey
        }
        if let found = try readHeader(input) {
            if let extensionKind, extensionKind != found.header.kind {
                throw RecordAnalysisError.extensionMismatch(
                    fileExtension: TextFormat.display(normalized), headerKind: found.header.kind)
            }
            try input.requireNoTerminalControls()
            return found.header.kind
        }
        switch extensionKind {
        case .some(.serial):
            return .serial
        case .some(.wifiSurvey):
            _ = try WiFiSurvey.parse(text)
            return .wifiSurvey
        case .some(let expected):
            throw RecordAnalysisError.missingHeader(expected: expected)
        case .none:
            throw RecordAnalysisError.unrecognizedFormat(fileExtension: TextFormat.display(normalized))
        }
    }

    /// 校验并分析文本。`kind` 必须与文件头一致；串口日志不能带 Flipper 文件头。
    public static func analyze(_ text: String, kind: RecordKind) throws -> AnalysisReport {
        let input = try TextInput(text)
        if kind == .wifiSurvey {
            return try analyzeWiFiSurvey(WiFiSurvey.parse(text))
        }
        if isWiFiSurvey(text) {
            throw RecordAnalysisError.kindMismatch(requested: kind, detected: .wifiSurvey)
        }
        guard let found = try readHeader(input) else {
            guard kind == .serial else { throw RecordAnalysisError.missingHeader(expected: kind) }
            return analyzeSerial(input)
        }
        guard found.header.kind == kind else {
            throw RecordAnalysisError.kindMismatch(requested: kind, detected: found.header.kind)
        }
        try input.requireNoTerminalControls()
        let document = try FlipperDocument(input: input, header: found.header, cursor: found.cursor)
        switch kind {
        case .infrared: return try analyzeInfrared(document)
        case .subGHz: return try analyzeSubGhz(document)
        case .nfc: return try analyzeNfc(document)
        case .rfid: return try analyzeRfid(document)
        case .iButton: return try analyzeIButton(document)
        case .serial: throw RecordAnalysisError.kindMismatch(requested: .serial, detected: found.header.kind)
        case .wifiSurvey: throw RecordAnalysisError.kindMismatch(requested: .wifiSurvey, detected: found.header.kind)
        }
    }

    private static func isWiFiSurvey(_ text: String) -> Bool {
        guard let first = text.split(whereSeparator: \.isNewline)
            .first(where: { !String($0).trimmingCharacters(in: .whitespaces).isEmpty }) else { return false }
        return String(first).trimmingCharacters(in: .whitespaces) == "# Flipper Lab WiFi Survey v1"
    }

    private static func analyzeWiFiSurvey(_ survey: WiFiSurvey) -> AnalysisReport {
        let points = survey.accessPoints
        let channelCounts = Dictionary(grouping: points, by: \.channel)
        let distribution = channelCounts.keys.sorted().map { "\($0): \(channelCounts[$0]?.count ?? 0)" }.joined(separator: " · ")
        var facts = [
            AnalysisFact("扫描到的接入点", "\(points.count)"),
            AnalysisFact("不同网络名称", "\(survey.uniqueSSIDCount)"),
            AnalysisFact("涉及信道", "\(channelCounts.count)"),
            AnalysisFact("信道分布", distribution.isEmpty ? "无" : distribution),
        ]
        if let strongest = points.max(by: { $0.rssi < $1.rssi }) {
            facts.append(AnalysisFact("最强接收信号", "\(strongest.ssid.isEmpty ? "隐藏网络" : strongest.ssid) · \(strongest.rssi) dBm"))
        }
        return AnalysisReport(facts: facts, notes: [
            "这是已保存的被动扫描记录；RSSI 只表示当时收到的信号强度，不能直接换算距离。",
            "分析不会连接网络、猜测密码或向扩展板发送无线操作。",
        ])
    }
}

// MARK: - 输入检查与文件头

extension RecordAnalyzer {
    /// 通过基础检查的文本：UTF-8 字节，以及跳过 BOM 后的起点。
    fileprivate struct TextInput {
        let bytes: [UInt8]
        let start: Int
        /// BEL、BS、FF、ESC、DEL 首次出现的行；串口日志允许（终端颜色等），Flipper 文件不允许。
        let terminalControlLine: Int?

        init(_ text: String) throws {
            let byteCount = text.utf8.count
            guard byteCount <= RecordAnalyzer.maxInputBytes else {
                throw RecordAnalysisError.inputTooLarge(byteCount: byteCount, limit: RecordAnalyzer.maxInputBytes)
            }
            let bytes = Array(text.utf8)
            let start = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
            var line = 1
            var hasContent = false
            var controlLine: Int?
            var index = start
            while index < bytes.count {
                switch bytes[index] {
                case 0x0A:
                    line += 1
                case 0x09, 0x0D, 0x20:
                    break
                case 0x07, 0x08, 0x0C, 0x1B, 0x7F:
                    if controlLine == nil { controlLine = line }
                case 0x00...0x1F:
                    throw RecordAnalysisError.binaryContent(line: line)
                case 0xEF where index + 2 < bytes.count && bytes[index + 1] == 0xBF && bytes[index + 2] == 0xBD:
                    throw RecordAnalysisError.invalidUTF8
                default:
                    hasContent = true
                }
                index += 1
            }
            guard hasContent else { throw RecordAnalysisError.emptyInput }
            self.bytes = bytes
            self.start = start
            self.terminalControlLine = controlLine
        }

        func requireNoTerminalControls() throws {
            if let line = terminalControlLine { throw RecordAnalysisError.binaryContent(line: line) }
        }
    }

    fileprivate struct FileTypeSpec: Sendable {
        let name: String
        let kind: RecordKind
        let versions: [UInt32]
    }

    fileprivate struct FileHeader {
        let fileType: String
        let kind: RecordKind
        let version: UInt32
    }

    /// 与本仓库固件读取文件时检查的 Filetype 与版本一致。
    fileprivate static let fileTypes: [FileTypeSpec] = [
        FileTypeSpec(name: "IR signals file", kind: .infrared, versions: [1]),
        FileTypeSpec(name: "IR library file", kind: .infrared, versions: [1]),
        FileTypeSpec(name: "Flipper SubGhz Key File", kind: .subGHz, versions: [1]),
        FileTypeSpec(name: "Flipper SubGhz RAW File", kind: .subGHz, versions: [1]),
        FileTypeSpec(name: "Flipper NFC device", kind: .nfc, versions: [2, 3, 4]),
        FileTypeSpec(name: "Flipper RFID key", kind: .rfid, versions: [1]),
        FileTypeSpec(name: "Flipper iButton key", kind: .iButton, versions: [1, 2]),
    ]

    /// 接受“ir”“.IR”或完整文件名，取最后一个点之后的部分并转为小写。
    fileprivate static func normalizedExtension(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let dot = value.lastIndex(of: ".") {
            value = String(value[value.index(after: dot)...])
        }
        return value
    }

    fileprivate static func kind(forExtension fileExtension: String) -> RecordKind? {
        if fileExtension == "log" { return .serial }
        if fileExtension == "csv" { return .wifiSurvey }
        return RecordKind.allCases.first { $0.fileExtension == fileExtension }
    }

    /// 第一条有效内容（跳过空行和 # 注释）以“Filetype:”开头时按 Flipper 文件处理，
    /// 并要求紧接着的有效内容是受支持的 Version；否则返回 nil。
    fileprivate static func readHeader(_ input: TextInput) throws -> (header: FileHeader, cursor: LineCursor)? {
        var cursor = LineCursor(input)
        guard let first = cursor.nextContentLine(), FF.line(first, in: input.bytes, hasPrefix: FF.filetypePrefix) else {
            return nil
        }
        let typeEntry = try FF.entry(first, input.bytes)
        let fileType = FF.text(input.bytes, typeEntry)
        guard let spec = fileTypes.first(where: { $0.name == fileType }) else {
            throw RecordAnalysisError.unsupportedFileType(TextFormat.display(fileType))
        }
        guard let versionLine = cursor.nextContentLine() else { throw RecordAnalysisError.missingVersion }
        let versionEntry = try FF.entry(versionLine, input.bytes)
        guard versionEntry.key == "Version" else { throw RecordAnalysisError.missingVersion }
        let tokens = FF.tokens(input.bytes, versionEntry)
        guard tokens.count == 1,
              let value = FF.integer(input.bytes, tokens[0], allowNegative: false),
              let version = UInt32(exactly: value),
              spec.versions.contains(version) else {
            throw RecordAnalysisError.unsupportedVersion(
                fileType: spec.name, version: TextFormat.display(FF.text(input.bytes, versionEntry)))
        }
        return (FileHeader(fileType: spec.name, kind: spec.kind, version: version), cursor)
    }
}

// MARK: - Flipper 文件格式（逐行“键: 值”）

extension RecordAnalyzer {
    /// 一行的字节范围，不含换行符和行尾的 \r。
    fileprivate struct SourceLine {
        let number: Int
        let start: Int
        let end: Int
    }

    fileprivate struct LineCursor {
        private let bytes: [UInt8]
        private var position: Int
        private var number = 1

        init(_ input: TextInput) {
            bytes = input.bytes
            position = input.start
        }

        mutating func next() -> SourceLine? {
            guard position < bytes.count else { return nil }
            let start = position
            var end = start
            while end < bytes.count, bytes[end] != 0x0A { end += 1 }
            position = end + 1
            var contentEnd = end
            if contentEnd > start, bytes[contentEnd - 1] == 0x0D { contentEnd -= 1 }
            defer { number += 1 }
            return SourceLine(number: number, start: start, end: contentEnd)
        }

        /// 下一条有效内容：跳过空白行与行首为 # 的注释行（与固件相同，只有行首的 # 表示注释）。
        mutating func nextContentLine() -> SourceLine? {
            while let line = next() {
                if !FF.isBlank(line, bytes), bytes[line.start] != UInt8(ascii: "#") { return line }
            }
            return nil
        }
    }

    fileprivate struct Entry {
        let line: Int
        let key: String
        let valueStart: Int
        let valueEnd: Int
    }

    /// 文件头之后的全部字段，保持文件顺序。
    fileprivate struct FlipperDocument {
        let header: FileHeader
        let bytes: [UInt8]
        let entries: [Entry]

        init(input: TextInput, header: FileHeader, cursor: LineCursor) throws {
            var cursor = cursor
            var entries: [Entry] = []
            while let line = cursor.nextContentLine() {
                entries.append(try FF.entry(line, input.bytes))
            }
            self.header = header
            self.bytes = input.bytes
            self.entries = entries
        }

        func text(_ entry: Entry) -> String { FF.text(bytes, entry) }

        func tokens(_ entry: Entry) -> [Range<Int>] { FF.tokens(bytes, entry) }

        func hexBytes(_ entry: Entry, allowUnknown: Bool = false) -> [UInt8?]? {
            FF.hexBytes(bytes, entry, allowUnknown: allowUnknown)
        }

        /// 单个 0...UInt32.max 的十进制整数（允许前导 +，与固件 strint 一致）。
        func unsignedValue(_ entry: Entry) -> Int64? {
            let parts = tokens(entry)
            guard parts.count == 1,
                  let value = FF.integer(bytes, parts[0], allowNegative: false),
                  value <= Int64(UInt32.max) else { return nil }
            return value
        }
    }

    /// 与固件 flipper_format_stream.c 对齐的解析规则：键为行首到第一个冒号，
    /// 冒号后跟一个空格再接值；数组值以空格或制表符分隔。
    fileprivate enum FF {
        static let filetypePrefix = Array("Filetype:".utf8)

        static func isSpace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0D
        }

        static func isBlank(_ line: SourceLine, _ bytes: [UInt8]) -> Bool {
            var index = line.start
            while index < line.end {
                if !isSpace(bytes[index]) { return false }
                index += 1
            }
            return true
        }

        static func line(_ line: SourceLine, in bytes: [UInt8], hasPrefix prefix: [UInt8]) -> Bool {
            guard line.end - line.start >= prefix.count else { return false }
            for offset in 0..<prefix.count where bytes[line.start + offset] != prefix[offset] {
                return false
            }
            return true
        }

        static func entry(_ line: SourceLine, _ bytes: [UInt8]) throws -> Entry {
            var colon = line.start
            while colon < line.end, bytes[colon] != UInt8(ascii: ":") { colon += 1 }
            guard colon < line.end else {
                throw RecordAnalysisError.malformedLine(line: line.number, reason: "不是“键: 值”格式（缺少冒号）")
            }
            guard colon > line.start, !isSpace(bytes[line.start]), !isSpace(bytes[colon - 1]) else {
                throw RecordAnalysisError.malformedLine(line: line.number, reason: "冒号前的字段名为空，或首尾带有空格")
            }
            var valueStart = colon + 1
            if valueStart < line.end {
                guard bytes[valueStart] == UInt8(ascii: " ") || bytes[valueStart] == UInt8(ascii: "\t") else {
                    throw RecordAnalysisError.malformedLine(line: line.number, reason: "冒号后应有一个空格")
                }
                valueStart += 1
            }
            let key = String(decoding: bytes[line.start..<colon], as: UTF8.self)
            return Entry(line: line.number, key: key, valueStart: valueStart, valueEnd: line.end)
        }

        static func text(_ bytes: [UInt8], _ entry: Entry) -> String {
            String(decoding: bytes[entry.valueStart..<entry.valueEnd], as: UTF8.self)
        }

        static func forEachToken(_ bytes: [UInt8], _ start: Int, _ end: Int,
                                 _ body: (Range<Int>) throws -> Void) rethrows {
            var index = start
            while index < end {
                if isSpace(bytes[index]) {
                    index += 1
                    continue
                }
                let tokenStart = index
                while index < end, !isSpace(bytes[index]) { index += 1 }
                try body(tokenStart..<index)
            }
        }

        static func tokens(_ bytes: [UInt8], _ entry: Entry) -> [Range<Int>] {
            var result: [Range<Int>] = []
            forEachToken(bytes, entry.valueStart, entry.valueEnd) { result.append($0) }
            return result
        }

        /// 十进制整数，可带 + 号（`allowNegative` 时也可带 - 号）。
        /// 含其他字符、超过 19 位数字或超出 Int64 时返回 nil。
        static func integer(_ bytes: [UInt8], _ range: Range<Int>, allowNegative: Bool) -> Int64? {
            var index = range.lowerBound
            var negative = false
            if index < range.upperBound, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                negative = bytes[index] == UInt8(ascii: "-")
                index += 1
            }
            if negative && !allowNegative { return nil }
            let digitCount = range.upperBound - index
            guard digitCount > 0, digitCount <= 19 else { return nil }
            var value: Int64 = 0
            while index < range.upperBound {
                let digit = bytes[index] &- UInt8(ascii: "0")
                guard digit <= 9 else { return nil }
                let (shifted, overflowA) = value.multipliedReportingOverflow(by: 10)
                let (sum, overflowB) = shifted.addingReportingOverflow(Int64(digit))
                guard !overflowA, !overflowB else { return nil }
                value = sum
                index += 1
            }
            return negative ? -value : value
        }

        /// 十进制小数（可带符号与指数）。拒绝 nan、inf、十六进制等写法，结果必须有限。
        static func decimal(_ bytes: [UInt8], _ range: Range<Int>) -> Double? {
            guard range.count <= 64 else { return nil }
            let end = range.upperBound
            var index = range.lowerBound
            func skipDigits() -> Int {
                var count = 0
                while index < end, bytes[index] >= UInt8(ascii: "0"), bytes[index] <= UInt8(ascii: "9") {
                    index += 1
                    count += 1
                }
                return count
            }
            if index < end, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
            var mantissaDigits = skipDigits()
            if index < end, bytes[index] == UInt8(ascii: ".") {
                index += 1
                mantissaDigits += skipDigits()
            }
            guard mantissaDigits > 0 else { return nil }
            if index < end, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                index += 1
                if index < end, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
                guard skipDigits() > 0 else { return nil }
            }
            guard index == end,
                  let value = Double(String(decoding: bytes[range], as: UTF8.self)),
                  value.isFinite else { return nil }
            return value
        }

        static func hexDigit(_ byte: UInt8) -> UInt8? {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
            case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
            case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
            default: return nil
            }
        }

        /// 以空格分隔的两位十六进制字节；`allowUnknown` 时“??”记为 nil（NFC 未读出的数据）。
        /// 任一记号不合法时返回 nil。
        static func hexBytes(_ bytes: [UInt8], _ entry: Entry, allowUnknown: Bool) -> [UInt8?]? {
            var result: [UInt8?] = []
            var valid = true
            forEachToken(bytes, entry.valueStart, entry.valueEnd) { token in
                guard valid else { return }
                guard token.count == 2 else {
                    valid = false
                    return
                }
                let first = bytes[token.lowerBound]
                let second = bytes[token.lowerBound + 1]
                if allowUnknown, first == UInt8(ascii: "?"), second == UInt8(ascii: "?") {
                    result.append(nil)
                } else if let high = hexDigit(first), let low = hexDigit(second) {
                    result.append(high << 4 | low)
                } else {
                    valid = false
                }
            }
            return valid ? result : nil
        }

        /// 错误信息中引用的记号片段（最多 24 字节，控制字符替换为 ?）。
        static func snippet(_ bytes: [UInt8], _ range: Range<Int>) -> String {
            let end = min(range.upperBound, range.lowerBound + 24)
            let text = TextFormat.display(String(decoding: bytes[range.lowerBound..<end], as: UTF8.self))
            return end < range.upperBound ? text + "…" : text
        }
    }
}

// MARK: - 红外

extension RecordAnalyzer {
    fileprivate struct InfraredProtocolSpec: Sendable {
        let name: String
        let addressBits: Int
        let commandBits: Int
    }

    fileprivate struct InfraredButton {
        enum Signal {
            case parsed(protocolName: String, address: [UInt8], command: [UInt8])
            case raw(frequency: Int64, dutyCycle: Double, timings: [Int64], total: Int64)
        }

        let name: String
        let signal: Signal
    }

    /// 协议名称与地址/命令位宽取自本仓库固件 lib/infrared/encoder_decoder（名称区分大小写）。
    fileprivate static let infraredProtocols: [InfraredProtocolSpec] = [
        InfraredProtocolSpec(name: "NEC", addressBits: 8, commandBits: 8),
        InfraredProtocolSpec(name: "NECext", addressBits: 16, commandBits: 16),
        InfraredProtocolSpec(name: "NEC42", addressBits: 13, commandBits: 8),
        InfraredProtocolSpec(name: "NEC42ext", addressBits: 26, commandBits: 16),
        InfraredProtocolSpec(name: "Samsung32", addressBits: 8, commandBits: 8),
        InfraredProtocolSpec(name: "RC6", addressBits: 8, commandBits: 8),
        InfraredProtocolSpec(name: "RC5", addressBits: 5, commandBits: 6),
        InfraredProtocolSpec(name: "RC5X", addressBits: 5, commandBits: 7),
        InfraredProtocolSpec(name: "SIRC", addressBits: 5, commandBits: 7),
        InfraredProtocolSpec(name: "SIRC15", addressBits: 8, commandBits: 7),
        InfraredProtocolSpec(name: "SIRC20", addressBits: 13, commandBits: 7),
        InfraredProtocolSpec(name: "Kaseikyo", addressBits: 26, commandBits: 10),
        InfraredProtocolSpec(name: "RCA", addressBits: 4, commandBits: 8),
        InfraredProtocolSpec(name: "Pioneer", addressBits: 8, commandBits: 8),
    ]
    /// 固件发射时允许的载波频率（furi_hal_infrared.h），超出时设备会限制到边界值。
    fileprivate static let infraredCarrierRange: ClosedRange<Int64> = 10_000...1_000_000
    /// 逐个列出按钮详情的上限；按钮列表本身始终完整。
    fileprivate static let maxButtonFacts = 100

    fileprivate static func analyzeInfrared(_ document: FlipperDocument) throws -> AnalysisReport {
        let isLibrary = document.header.fileType == "IR library file"
        let entries = document.entries
        var buttons: [InfraredButton] = []
        var firstLineByName: [String: Int] = [:]
        var index = 0
        while index < entries.count {
            let nameEntry = entries[index]
            guard nameEntry.key == "name" else {
                throw RecordAnalysisError.unexpectedField(field: TextFormat.display(nameEntry.key), line: nameEntry.line)
            }
            let name = document.text(nameEntry)
            try validateButtonName(name, line: nameEntry.line)
            if let firstLine = firstLineByName[name] {
                // 通用遥控库按品牌重复使用 Power 等名称；遥控器文件可按名称调用按钮，必须唯一。
                if !isLibrary {
                    throw RecordAnalysisError.duplicateButtonName(
                        name: TextFormat.display(name), line: nameEntry.line, firstLine: firstLine)
                }
            } else {
                firstLineByName[name] = nameEntry.line
            }
            index += 1

            guard index < entries.count, entries[index].key == "type" else {
                throw RecordAnalysisError.missingField(field: "type", line: nameEntry.line)
            }
            let typeEntry = entries[index]
            index += 1
            let signal: InfraredButton.Signal
            switch document.text(typeEntry) {
            case "parsed":
                let fields = try buttonFields(["protocol", "address", "command"], of: nameEntry, in: entries, at: &index)
                signal = try parsedSignal(protocolEntry: fields[0], addressEntry: fields[1], commandEntry: fields[2],
                                          in: document)
            case "raw":
                let fields = try buttonFields(["frequency", "duty_cycle", "data"], of: nameEntry, in: entries, at: &index)
                signal = try rawSignal(frequencyEntry: fields[0], dutyEntry: fields[1], dataEntry: fields[2],
                                       in: document)
            default:
                throw RecordAnalysisError.invalidField(
                    field: "type", line: typeEntry.line,
                    reason: "应为 parsed 或 raw，实际为“\(TextFormat.display(document.text(typeEntry)))”")
            }
            buttons.append(InfraredButton(name: name, signal: signal))
        }
        return infraredReport(buttons, header: document.header, isLibrary: isLibrary)
    }

    /// 按固件的读取顺序取出按钮字段。固件逐个向后查找键，顺序不同会读到其他按钮的值。
    fileprivate static func buttonFields(_ keys: [String], of nameEntry: Entry, in entries: [Entry],
                                         at index: inout Int) throws -> [Entry] {
        var fields: [Entry] = []
        for key in keys {
            guard index < entries.count, entries[index].key != "name" else {
                throw RecordAnalysisError.missingField(field: key, line: nameEntry.line)
            }
            let entry = entries[index]
            guard entry.key == key else {
                throw RecordAnalysisError.unexpectedField(field: TextFormat.display(entry.key), line: entry.line)
            }
            fields.append(entry)
            index += 1
        }
        return fields
    }

    fileprivate static func validateButtonName(_ name: String, line: Int) throws {
        guard name.utf8.contains(where: { $0 != UInt8(ascii: " ") && $0 != UInt8(ascii: "\t") }) else {
            throw RecordAnalysisError.invalidField(field: "name", line: line, reason: "按钮名称为空")
        }
        guard name.utf8.allSatisfy({ $0 >= 0x20 && $0 <= 0x7E }) else {
            throw RecordAnalysisError.invalidField(
                field: "name", line: line, reason: "按钮名称只能包含可打印 ASCII 字符（Flipper 红外文件格式要求）")
        }
    }

    fileprivate static func parsedSignal(protocolEntry: Entry, addressEntry: Entry, commandEntry: Entry,
                                         in document: FlipperDocument) throws -> InfraredButton.Signal {
        let name = document.text(protocolEntry)
        guard let spec = infraredProtocols.first(where: { $0.name == name }) else {
            throw RecordAnalysisError.invalidField(
                field: "protocol", line: protocolEntry.line,
                reason: "不支持的协议“\(TextFormat.display(name))”（名称区分大小写）")
        }
        let address = try infraredPayload(addressEntry, field: "address", label: "地址", bits: spec.addressBits,
                                          protocolName: spec.name, in: document)
        let command = try infraredPayload(commandEntry, field: "command", label: "命令", bits: spec.commandBits,
                                          protocolName: spec.name, in: document)
        return .parsed(protocolName: spec.name, address: address, command: command)
    }

    /// address/command 固定为 4 个字节；按固件的读取方式（小端）组成 32 位值后检查协议位宽。
    fileprivate static func infraredPayload(_ entry: Entry, field: String, label: String, bits: Int,
                                            protocolName: String, in document: FlipperDocument) throws -> [UInt8] {
        guard let parsed = document.hexBytes(entry) else {
            throw RecordAnalysisError.invalidField(
                field: field, line: entry.line, reason: "应为以空格分隔的两位十六进制字节，例如“EE 87 00 00”")
        }
        let values = parsed.compactMap { $0 }
        guard values.count == 4 else {
            throw RecordAnalysisError.invalidField(
                field: field, line: entry.line, reason: "应为 4 个字节，实际为 \(values.count) 个")
        }
        let value = UInt32(values[0]) | UInt32(values[1]) << 8 | UInt32(values[2]) << 16 | UInt32(values[3]) << 24
        let maximum: UInt32 = bits >= 32 ? .max : (1 << UInt32(bits)) - 1
        guard value <= maximum else {
            throw RecordAnalysisError.invalidField(
                field: field, line: entry.line,
                reason: "\(protocolName) 的\(label)只有 \(bits) 位，最大为 0x\(String(maximum, radix: 16, uppercase: true))")
        }
        return values
    }

    fileprivate static func rawSignal(frequencyEntry: Entry, dutyEntry: Entry, dataEntry: Entry,
                                      in document: FlipperDocument) throws -> InfraredButton.Signal {
        guard let frequency = document.unsignedValue(frequencyEntry), frequency > 0 else {
            throw RecordAnalysisError.invalidField(
                field: "frequency", line: frequencyEntry.line,
                reason: "应为正整数（单位 Hz），实际为“\(TextFormat.display(document.text(frequencyEntry)))”")
        }
        let dutyTokens = document.tokens(dutyEntry)
        guard dutyTokens.count == 1, let dutyCycle = FF.decimal(document.bytes, dutyTokens[0]),
              dutyCycle > 0, dutyCycle <= 1 else {
            throw RecordAnalysisError.invalidField(
                field: "duty_cycle", line: dutyEntry.line,
                reason: "应为大于 0 且不超过 1 的十进制小数，实际为“\(TextFormat.display(document.text(dutyEntry)))”")
        }
        let bytes = document.bytes
        var timings: [Int64] = []
        var total: Int64 = 0
        try FF.forEachToken(bytes, dataEntry.valueStart, dataEntry.valueEnd) { token in
            guard timings.count < maxInfraredTimings else {
                throw RecordAnalysisError.invalidField(
                    field: "data", line: dataEntry.line, reason: "时长数量超过固件上限 \(maxInfraredTimings) 个")
            }
            guard let value = FF.integer(bytes, token, allowNegative: false), value > 0,
                  value <= Int64(UInt32.max) else {
                throw RecordAnalysisError.invalidField(
                    field: "data", line: dataEntry.line,
                    reason: "第 \(timings.count + 1) 个时长“\(FF.snippet(bytes, token))”不是正整数（单位 µs）")
            }
            timings.append(value)
            total += value  // 至多 1024 个 UInt32，总和远小于 Int64 上限
        }
        guard !timings.isEmpty else {
            throw RecordAnalysisError.invalidField(field: "data", line: dataEntry.line, reason: "没有时长数据")
        }
        return .raw(frequency: frequency, dutyCycle: dutyCycle, timings: timings, total: total)
    }

    fileprivate static func infraredReport(_ buttons: [InfraredButton], header: FileHeader,
                                           isLibrary: Bool) -> AnalysisReport {
        var facts = [
            AnalysisFact("文件类型", isLibrary ? "IR library file（通用遥控库）" : "IR signals file（遥控器）"),
            AnalysisFact("格式版本", "\(header.version)"),
            AnalysisFact("按钮数量", "\(buttons.count)"),
        ]
        var notes: [String] = []
        var protocolOrder: [String] = []
        var protocolCounts: [String: Int] = [:]
        var frequencies: [Int64] = []
        var seenFrequencies: Set<Int64> = []
        var dutyCycles: [Double] = []
        var seenDutyCycles: Set<Double> = []
        var magnitudes: [UInt64] = []
        var rawCount = 0
        var outOfRangeCount = 0
        var firstRaw: (position: Int, name: String, timings: [Int64])?

        for (position, button) in buttons.enumerated() {
            switch button.signal {
            case let .parsed(protocolName, _, _):
                if protocolCounts[protocolName] == nil { protocolOrder.append(protocolName) }
                protocolCounts[protocolName, default: 0] += 1
            case let .raw(frequency, dutyCycle, timings, _):
                rawCount += 1
                if seenFrequencies.insert(frequency).inserted { frequencies.append(frequency) }
                if seenDutyCycles.insert(dutyCycle).inserted { dutyCycles.append(dutyCycle) }
                if !infraredCarrierRange.contains(frequency) { outOfRangeCount += 1 }
                magnitudes.append(contentsOf: timings.map { $0.magnitude })
                if firstRaw == nil { firstRaw = (position, button.name, timings) }
            }
        }

        facts.append(AnalysisFact("协议解析按钮", "\(buttons.count - rawCount)"))
        facts.append(AnalysisFact("原始信号按钮", "\(rawCount)"))
        if !protocolOrder.isEmpty {
            let distribution = protocolOrder.map { name in "\(name) ×\(protocolCounts[name] ?? 0)" }
            facts.append(AnalysisFact("协议分布", TextFormat.list(distribution, limit: 8)))
        }
        if rawCount > 0 {
            magnitudes.sort()
            let median = DurationStatistics.mergedMedian(magnitudes, [])
            facts.append(AnalysisFact("原始时长总数", "\(magnitudes.count) 个"))
            facts.append(AnalysisFact(
                "原始时长范围",
                "最短 \(magnitudes.first ?? 0) µs · 中位 \(TextFormat.decimal(median, digits: 1)) µs · 最长 \(magnitudes.last ?? 0) µs"))
            facts.append(AnalysisFact("载波频率（文件字段）", TextFormat.list(frequencies.map { "\($0) Hz" }, limit: 6)))
            facts.append(AnalysisFact("占空比（文件字段）",
                                      TextFormat.list(dutyCycles.map { TextFormat.decimal($0, digits: 4) }, limit: 6)))
            notes.append("原始信号记录的是解调后的包络，依次为发射（亮）与间隔（灭）的持续时间，单位 µs。载波频率和占空比来自文件字段，不是测量得到的载波。")
            if outOfRangeCount > 0 {
                notes.append("有 \(outOfRangeCount) 个原始按钮的载波频率超出固件发射范围 10 kHz–1 MHz，设备会将其限制到范围边界后发射。")
            }
        }

        for (position, button) in buttons.prefix(maxButtonFacts).enumerated() {
            facts.append(AnalysisFact("按钮 \(position + 1) · \(TextFormat.display(button.name))",
                                      buttonSummary(button.signal)))
        }
        if buttons.count > maxButtonFacts {
            notes.append("共 \(buttons.count) 个按钮，逐项详情只列出前 \(maxButtonFacts) 个；按钮列表完整保留文件顺序。")
        }
        if buttons.isEmpty {
            notes.append("文件中没有按钮。")
        }
        if isLibrary {
            notes.append("通用遥控库允许同名按钮（通常每个品牌一组）；红外应用不会把库文件当作普通遥控器打开。")
        }

        var plot: [Double] = []
        if let firstRaw {
            let signed = firstRaw.timings.enumerated().map { $0.offset % 2 == 0 ? $0.element : -$0.element }
            plot = plotPoints(signed)
            notes.append("波形数据取自第 \(firstRaw.position + 1) 个按钮“\(TextFormat.display(firstRaw.name))”：正值为发射，负值为间隔。")
            if signed.count > maxPlotPoints { notes.append(reductionNote(signed.count)) }
        }
        return AnalysisReport(facts: facts, notes: notes, buttons: buttons.map(\.name), pulseDurations: plot)
    }

    fileprivate static func buttonSummary(_ signal: InfraredButton.Signal) -> String {
        switch signal {
        case let .parsed(protocolName, address, command):
            return "协议解析 · \(protocolName) · 地址 \(TextFormat.hex(address)) · 命令 \(TextFormat.hex(command))"
        case let .raw(frequency, dutyCycle, timings, total):
            return "原始 · \(timings.count) 个时长 · 包络 \(TextFormat.microseconds(Double(total))) · 文件载波 \(frequency) Hz · 占空比 \(TextFormat.decimal(dutyCycle, digits: 4))"
        }
    }
}

// MARK: - Sub-GHz

extension RecordAnalyzer {
    /// 在文件中只能出现一次的字段；RAW_Data、Data_RAW 等可重复。
    fileprivate static let subGhzSingleFields: Set<String> = [
        "Frequency", "Preset", "Custom_preset_module", "Custom_preset_data", "Protocol", "Bit", "TE", "Key",
    ]

    fileprivate static func analyzeSubGhz(_ document: FlipperDocument) throws -> AnalysisReport {
        var single: [String: Entry] = [:]
        var rawLines: [Entry] = []
        var binaryBlocks: [Entry] = []
        var otherFields: [String] = []
        var seenOther: Set<String> = []
        for entry in document.entries {
            if entry.key == "RAW_Data" {
                rawLines.append(entry)
            } else if entry.key == "Data_RAW" {
                binaryBlocks.append(entry)
            } else if subGhzSingleFields.contains(entry.key) {
                if let first = single[entry.key] { throw duplicateField(entry, firstLine: first.line) }
                single[entry.key] = entry
            } else if seenOther.insert(entry.key).inserted {
                otherFields.append(entry.key)
            }
        }

        guard let frequencyEntry = single["Frequency"] else {
            throw RecordAnalysisError.missingField(field: "Frequency", line: nil)
        }
        guard let frequency = document.unsignedValue(frequencyEntry), frequency > 0 else {
            throw RecordAnalysisError.invalidField(
                field: "Frequency", line: frequencyEntry.line,
                reason: "应为正整数（单位 Hz），实际为“\(TextFormat.display(document.text(frequencyEntry)))”")
        }
        let preset = try requiredText("Preset", in: single, document: document)
        let protocolName = try requiredText("Protocol", in: single, document: document)

        var facts = [
            AnalysisFact("文件类型", document.header.fileType),
            AnalysisFact("格式版本", "\(document.header.version)"),
            AnalysisFact("频率（文件字段）", TextFormat.frequency(frequency)),
            AnalysisFact("预设", TextFormat.display(preset.value)),
        ]
        var notes: [String] = []
        var plot: [Double] = []

        if preset.value == "FuriHalSubGhzPresetCustom" {
            let module = try requiredText("Custom_preset_module", in: single, document: document, near: preset.line)
            guard let dataEntry = single["Custom_preset_data"] else {
                throw RecordAnalysisError.missingField(field: "Custom_preset_data", line: preset.line)
            }
            guard let data = document.hexBytes(dataEntry), !data.isEmpty, data.count % 2 == 0 else {
                throw RecordAnalysisError.invalidField(
                    field: "Custom_preset_data", line: dataEntry.line, reason: "应为偶数个以空格分隔的两位十六进制字节")
            }
            facts.append(AnalysisFact("自定义预设", "\(TextFormat.display(module.value)) · \(data.count) 字节配置"))
        }
        facts.append(AnalysisFact("协议（文件字段）", TextFormat.display(protocolName.value)))

        let isRawFile = document.header.fileType == "Flipper SubGhz RAW File"
        if protocolName.value == "RAW" {
            guard !rawLines.isEmpty else {
                throw RecordAnalysisError.missingField(field: "RAW_Data", line: protocolName.line)
            }
            if !isRawFile { notes.append("文件头为 Key File，但协议字段为 RAW，已按 RAW 数据分析。") }
            let parsed = try rawSamples(rawLines, in: document)
            guard let statistics = DurationStatistics(parsed.samples) else {
                throw RecordAnalysisError.missingField(field: "RAW_Data", line: protocolName.line)
            }
            facts.append(AnalysisFact("RAW_Data 行数", "\(rawLines.count)"))
            facts += statistics.facts
            facts += pulsePairs(parsed.samples).facts
            notes.append("RAW 数据按接收顺序记录电平持续时间：正值为高电平，负值为低电平，单位 µs。")
            notes.append("脉冲对按约 ±10% 的时长容差归类。以上统计与重复模式只是时长观察，不代表协议识别、解码或解密结果。")
            if statistics.overOneSecond > 0 {
                notes.append("有 \(statistics.overOneSecond) 个时长超过 1 秒；按本仓库固件源码，回放时这类值会被替换为 ±100 µs。")
            }
            if parsed.longLines > 0 {
                notes.append("有 \(parsed.longLines) 行 RAW_Data 超过 512 个值；Flipper 自己保存的文件每行不超过 512 个。")
            }
            plot = plotPoints(parsed.samples)
            if parsed.samples.count > maxPlotPoints { notes.append(reductionNote(parsed.samples.count)) }
        } else {
            if let first = rawLines.first {
                throw RecordAnalysisError.unexpectedField(field: "RAW_Data", line: first.line)
            }
            if isRawFile { notes.append("文件头为 RAW File，但协议字段不是 RAW，已按 Key 文件字段汇总。") }
            if let entry = single["Bit"] {
                guard let bits = document.unsignedValue(entry) else {
                    throw RecordAnalysisError.invalidField(field: "Bit", line: entry.line, reason: "应为非负整数")
                }
                facts.append(AnalysisFact("位长（文件字段）", "\(bits) 位"))
            }
            if let entry = single["TE"] {
                guard let te = document.unsignedValue(entry) else {
                    throw RecordAnalysisError.invalidField(field: "TE", line: entry.line, reason: "应为非负整数（单位 µs）")
                }
                facts.append(AnalysisFact("TE（文件字段）", "\(te) µs"))
            }
            if let entry = single["Key"] {
                guard let key = document.hexBytes(entry), !key.isEmpty else {
                    throw RecordAnalysisError.invalidField(
                        field: "Key", line: entry.line, reason: "应为以空格分隔的两位十六进制字节")
                }
                facts.append(AnalysisFact("Key 数据长度", "\(key.count) 字节"))
            }
            if !binaryBlocks.isEmpty {
                var total = 0
                for block in binaryBlocks {
                    guard let data = document.hexBytes(block), !data.isEmpty else {
                        throw RecordAnalysisError.invalidField(
                            field: "Data_RAW", line: block.line, reason: "应为以空格分隔的两位十六进制字节")
                    }
                    total += data.count
                }
                facts.append(AnalysisFact("Data_RAW 数据块", "\(binaryBlocks.count) 个，共 \(total) 字节"))
            }
            notes.append("Key 文件的字段由接收时的协议解码器写入；这里只列出字段与数据长度，不做协议识别、解码或解密。")
        }
        if !otherFields.isEmpty {
            facts.append(AnalysisFact("其他字段", TextFormat.list(otherFields, limit: 12)))
        }
        return AnalysisReport(facts: facts, notes: notes, pulseDurations: plot)
    }

    fileprivate static func duplicateField(_ entry: Entry, firstLine: Int) -> RecordAnalysisError {
        .invalidField(field: TextFormat.display(entry.key), line: entry.line,
                      reason: "字段重复（首次出现在第 \(firstLine) 行）")
    }

    /// 必填文本字段：值不能为空白，返回原值（不修剪，按固件的精确比较使用）。
    fileprivate static func requiredText(_ key: String, in fields: [String: Entry], document: FlipperDocument,
                                         near line: Int? = nil) throws -> (value: String, line: Int) {
        guard let entry = fields[key] else { throw RecordAnalysisError.missingField(field: key, line: line) }
        let value = document.text(entry)
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw RecordAnalysisError.invalidField(field: key, line: entry.line, reason: "值为空")
        }
        return (value, entry.line)
    }

    /// 解析全部 RAW_Data 行：每个值必须是非零的 32 位有符号整数，总数受 `maxSubGhzSamples` 限制。
    fileprivate static func rawSamples(_ lines: [Entry],
                                       in document: FlipperDocument) throws -> (samples: [Int64], longLines: Int) {
        let bytes = document.bytes
        var samples: [Int64] = []
        var longLines = 0
        for entry in lines {
            var valuesOnLine = 0
            try FF.forEachToken(bytes, entry.valueStart, entry.valueEnd) { token in
                guard let value = FF.integer(bytes, token, allowNegative: true),
                      value >= Int64(Int32.min), value <= Int64(Int32.max) else {
                    throw RecordAnalysisError.invalidField(
                        field: "RAW_Data", line: entry.line,
                        reason: "“\(FF.snippet(bytes, token))”不是 32 位有符号整数")
                }
                guard value != 0 else {
                    throw RecordAnalysisError.invalidField(field: "RAW_Data", line: entry.line, reason: "时长不能为 0")
                }
                guard samples.count < maxSubGhzSamples else {
                    throw RecordAnalysisError.limitExceeded(item: "RAW_Data 样本总数", limit: maxSubGhzSamples)
                }
                samples.append(value)
                valuesOnLine += 1
            }
            guard valuesOnLine > 0 else {
                throw RecordAnalysisError.invalidField(field: "RAW_Data", line: entry.line, reason: "该行没有时长数据")
            }
            if valuesOnLine > 512 { longLines += 1 }
        }
        return (samples, longLines)
    }
}

// MARK: - 时长统计与重复脉冲对

extension RecordAnalyzer {
    /// 带符号时长序列的统计，覆盖全部已接受的样本。
    fileprivate struct DurationStatistics {
        let count: Int
        let positiveCount: Int
        let negativeCount: Int
        let total: UInt64
        let minimum: UInt64
        let maximum: UInt64
        let median: Double
        let mean: Double
        let positiveMedian: Double?
        let negativeMedian: Double?
        let sameSignNeighbours: Int
        let overOneSecond: Int

        init?(_ samples: [Int64]) {
            guard !samples.isEmpty else { return nil }
            var positives: [UInt64] = []
            var negatives: [UInt64] = []
            var sum: UInt64 = 0
            var sameSign = 0
            var longCount = 0
            var previous: Int64 = 0
            for value in samples {
                let magnitude = value.magnitude
                // 样本数与单个时长都有上限（≤ 1e6 × 2^31），不会溢出；仍用饱和加法杜绝陷阱。
                let (next, overflow) = sum.addingReportingOverflow(magnitude)
                sum = overflow ? .max : next
                if value > 0 { positives.append(magnitude) } else { negatives.append(magnitude) }
                if magnitude > 1_000_000 { longCount += 1 }
                if previous != 0, (previous > 0) == (value > 0) { sameSign += 1 }
                previous = value
            }
            positives.sort()
            negatives.sort()
            count = samples.count
            positiveCount = positives.count
            negativeCount = negatives.count
            total = sum
            minimum = Swift.min(positives.first ?? .max, negatives.first ?? .max)
            maximum = Swift.max(positives.last ?? 0, negatives.last ?? 0)
            median = DurationStatistics.mergedMedian(positives, negatives)
            mean = Double(sum) / Double(samples.count)
            positiveMedian = positives.isEmpty ? nil : DurationStatistics.mergedMedian(positives, [])
            negativeMedian = negatives.isEmpty ? nil : DurationStatistics.mergedMedian(negatives, [])
            sameSignNeighbours = sameSign
            overOneSecond = longCount
        }

        var facts: [AnalysisFact] {
            var result = [
                AnalysisFact("样本数", "\(count)（正值 \(positiveCount)，负值 \(negativeCount)）"),
                AnalysisFact("总时长", TextFormat.microseconds(Double(total))),
                AnalysisFact("时长统计",
                             "最短 \(minimum) µs · 中位 \(TextFormat.decimal(median, digits: 1)) µs · 平均 \(TextFormat.decimal(mean, digits: 1)) µs · 最长 \(maximum) µs"),
            ]
            if let positiveMedian {
                result.append(AnalysisFact("正值中位数", "\(TextFormat.decimal(positiveMedian, digits: 1)) µs"))
            }
            if let negativeMedian {
                result.append(AnalysisFact("负值中位数", "\(TextFormat.decimal(negativeMedian, digits: 1)) µs"))
            }
            result.append(AnalysisFact("相邻同号样本", "\(sameSignNeighbours) 处"))
            return result
        }

        /// 两个已排序数组合并后的中位数，不另行分配合并数组。
        static func mergedMedian(_ first: [UInt64], _ second: [UInt64]) -> Double {
            let size = first.count + second.count
            guard size > 0 else { return 0 }
            if size % 2 == 1 { return Double(mergedElement(at: size / 2, first, second)) }
            let lower = Double(mergedElement(at: size / 2 - 1, first, second))
            let upper = Double(mergedElement(at: size / 2, first, second))
            return (lower + upper) / 2
        }

        /// 合并顺序中的第 k 个元素（从 0 开始，k 小于两数组总长）；线性扫描，不排序。
        static func mergedElement(at k: Int, _ first: [UInt64], _ second: [UInt64]) -> UInt64 {
            var i = 0
            var j = 0
            var remaining = k
            while true {
                if i == first.count { return second[j + remaining] }
                if j == second.count { return first[i + remaining] }
                let takeFirst = first[i] <= second[j]
                if remaining == 0 { return takeFirst ? first[i] : second[j] }
                if takeFirst { i += 1 } else { j += 1 }
                remaining -= 1
            }
        }
    }

    /// “正值后紧跟负值”的高低电平对，按对数分箱（相邻箱约差 20%）归类后统计。
    fileprivate struct PulsePairSummary {
        struct Pattern {
            let high: Double
            let low: Double
            let count: Int

            var label: String {
                "高 ≈\(TextFormat.decimal(high, digits: 0)) µs / 低 ≈\(TextFormat.decimal(low, digits: 0)) µs"
            }
        }

        struct Run {
            let pattern: Pattern
            let length: Int
            let startSample: Int
        }

        let pairCount: Int
        let common: [Pattern]
        let longestRun: Run?

        var facts: [AnalysisFact] {
            var result = [AnalysisFact("高低电平对", "\(pairCount) 对（正值后紧跟负值）")]
            for (rank, pattern) in common.enumerated() {
                let share = pairCount > 0 ? Double(pattern.count) * 100 / Double(pairCount) : 0
                result.append(AnalysisFact(
                    "常见脉冲对 \(rank + 1)",
                    "\(pattern.label)：\(pattern.count) 次（占 \(TextFormat.decimal(share, digits: 1))%）"))
            }
            if let longestRun {
                result.append(AnalysisFact(
                    "最长连续重复",
                    "\(longestRun.pattern.label) 连续 \(longestRun.length) 次（从第 \(longestRun.startSample + 1) 个样本开始）"))
            }
            return result
        }
    }

    fileprivate static let pairBinCount = 128
    fileprivate static let pairBinBase = log(1.2)

    /// 时长 1 µs…2^31 µs 映射到 0…118 号箱，箱内相差不超过约 ±10%。
    fileprivate static func pairBin(_ magnitude: UInt64) -> Int {
        let bin = Int((log(Double(Swift.max(magnitude, 1))) / pairBinBase).rounded())
        return Swift.min(Swift.max(bin, 0), pairBinCount - 1)
    }

    fileprivate static func pulsePairs(_ samples: [Int64]) -> PulsePairSummary {
        let slots = pairBinCount * pairBinCount
        var counts = [Int](repeating: 0, count: slots)
        var highSums = [UInt64](repeating: 0, count: slots)
        var lowSums = [UInt64](repeating: 0, count: slots)
        var pairCount = 0
        var runKey = -1
        var runLength = 0
        var runStart = 0
        var previousPairEnd = -1
        var bestKey = -1
        var bestLength = 0
        var bestStart = 0
        var index = 0
        while index + 1 < samples.count {
            let high = samples[index]
            let low = samples[index + 1]
            guard high > 0, low < 0 else {
                index += 1
                continue
            }
            let key = pairBin(high.magnitude) * pairBinCount + pairBin(low.magnitude)
            counts[key] += 1
            highSums[key] &+= high.magnitude
            lowSums[key] &+= low.magnitude
            pairCount += 1
            if key == runKey, index == previousPairEnd {
                runLength += 1
            } else {
                runKey = key
                runLength = 1
                runStart = index
            }
            if runLength > bestLength {
                bestKey = key
                bestLength = runLength
                bestStart = runStart
            }
            previousPairEnd = index + 2
            index += 2
        }

        func pattern(_ key: Int) -> PulsePairSummary.Pattern {
            let count = Double(counts[key])
            return PulsePairSummary.Pattern(high: Double(highSums[key]) / count, low: Double(lowSums[key]) / count,
                                            count: counts[key])
        }
        let ranked = counts.indices
            .filter { counts[$0] >= 2 }
            .sorted { counts[$0] != counts[$1] ? counts[$0] > counts[$1] : $0 < $1 }
            .prefix(3)
            .map { pattern($0) }
        let run: PulsePairSummary.Run? = bestLength >= 2
            ? PulsePairSummary.Run(pattern: pattern(bestKey), length: bestLength, startSample: bestStart)
            : nil
        return PulsePairSummary(pairCount: pairCount, common: Array(ranked), longestRun: run)
    }
}

// MARK: - NFC、低频 RFID、iButton

extension RecordAnalyzer {
    /// 本仓库固件 lib/nfc/protocols 中的设备类型名称（格式版本 4）。
    fileprivate static let nfcDeviceTypes: Set<String> = [
        "ISO14443-3A", "ISO14443-3B", "ISO14443-4A", "ISO14443-4B", "ISO15693-3", "FeliCa",
        "NTAG/Ultralight", "Mifare Classic", "Mifare Plus", "Mifare DESFire", "SLIX", "ST25TB",
        "EMV", "Type 4 Tag", "NTAG4xx",
    ]
    /// 本仓库固件 lib/lfrfid/protocols 中的协议名称（小写，比较时忽略大小写）。
    fileprivate static let rfidKeyTypes: Set<String> = [
        "em4100", "em4100/32", "em4100/16", "h10301", "idteck", "indala26", "indala224", "ioproxxsf",
        "awid", "fdx-a", "fdx-b", "hidprox", "hidext", "pyramid", "viking", "jablotron", "paradox",
        "pac/stanley", "keri", "gallagher", "gproxii", "electra", "instafob", "nexwatch", "noralsy", "radio key",
    ]
    /// documentation/file_formats/iButtonFileFormat.md 列出的协议（版本 2）与类型（版本 1）。
    fileprivate static let iButtonProtocols: Set<String> = [
        "DS1990", "DS1992", "DS1996", "DS1971", "DS1420", "DSGeneric", "Cyfral", "Metakom",
    ]
    fileprivate static let iButtonLegacyTypes: Set<String> = ["Cyfral", "Dallas", "Metakom"]
    fileprivate static let iButtonDataFields = ["Rom Data", "Sram Data", "Eeprom Data", "Data"]
    fileprivate static let dataOnlyNote = "摘要只统计文件中的字段与数据大小，不对卡片或钥匙的安全性、用途作任何判断。"

    fileprivate static func analyzeNfc(_ document: FlipperDocument) throws -> AnalysisReport {
        var deviceTypeEntry: Entry?
        var uidEntry: Entry?
        var uidLength = 0
        var pages = 0
        var pageBytes = 0
        var blocks = 0
        var blockBytes = 0
        var unknownBytes = 0
        var hexFields = 0
        var hexByteTotal = 0
        var typeFacts: [AnalysisFact] = []
        for entry in document.entries {
            switch entry.key {
            case "Device type":
                if let first = deviceTypeEntry { throw duplicateField(entry, firstLine: first.line) }
                deviceTypeEntry = entry
            case "UID":
                if let first = uidEntry { throw duplicateField(entry, firstLine: first.line) }
                guard let uid = document.hexBytes(entry), !uid.isEmpty else {
                    throw RecordAnalysisError.invalidField(
                        field: "UID", line: entry.line, reason: "应为以空格分隔的两位十六进制字节")
                }
                uidEntry = entry
                uidLength = uid.count
                hexFields += 1
                hexByteTotal += uid.count
            default:
                let isPage = hasNumberedKey(entry.key, prefix: "Page ")
                let isBlock = !isPage && hasNumberedKey(entry.key, prefix: "Block ")
                if isPage || isBlock {
                    guard let data = document.hexBytes(entry, allowUnknown: true), !data.isEmpty else {
                        throw RecordAnalysisError.invalidField(
                            field: TextFormat.display(entry.key), line: entry.line,
                            reason: "应为以空格分隔的两位十六进制字节，未知字节写作 ??")
                    }
                    if isPage {
                        pages += 1
                        pageBytes += data.count
                    } else {
                        blocks += 1
                        blockBytes += data.count
                    }
                    unknownBytes += data.reduce(0) { $0 + ($1 == nil ? 1 : 0) }
                    hexFields += 1
                    hexByteTotal += data.count
                } else if entry.key.hasSuffix(" type") {
                    if typeFacts.count < 4 {
                        typeFacts.append(AnalysisFact(TextFormat.display(entry.key), TextFormat.display(document.text(entry))))
                    }
                } else if let data = document.hexBytes(entry, allowUnknown: true), !data.isEmpty {
                    unknownBytes += data.reduce(0) { $0 + ($1 == nil ? 1 : 0) }
                    hexFields += 1
                    hexByteTotal += data.count
                }
            }
        }
        guard let deviceType = deviceTypeEntry.map({ document.text($0) }) else {
            throw RecordAnalysisError.missingField(field: "Device type", line: nil)
        }
        if deviceType.trimmingCharacters(in: .whitespaces).isEmpty, let entry = deviceTypeEntry {
            throw RecordAnalysisError.invalidField(field: "Device type", line: entry.line, reason: "值为空")
        }
        guard uidEntry != nil else { throw RecordAnalysisError.missingField(field: "UID", line: nil) }

        let version = document.header.version
        var facts = [
            AnalysisFact("文件类型", document.header.fileType),
            AnalysisFact("格式版本", version < 4 ? "\(version)（旧版格式）" : "\(version)"),
            AnalysisFact("设备类型", TextFormat.display(deviceType)),
        ]
        facts += typeFacts
        facts.append(AnalysisFact("UID 长度", "\(uidLength) 字节"))
        if pages > 0 { facts.append(AnalysisFact("页数据", "\(pages) 页，共 \(pageBytes) 字节")) }
        if blocks > 0 { facts.append(AnalysisFact("块数据", "\(blocks) 块，共 \(blockBytes) 字节")) }
        if unknownBytes > 0 { facts.append(AnalysisFact("标记为未知的字节", "\(unknownBytes) 字节（文件中写作 ??）")) }
        facts.append(AnalysisFact("字段数量", "\(document.entries.count)"))
        facts.append(AnalysisFact("十六进制数据", "\(hexFields) 个字段，共 \(hexByteTotal) 字节"))

        var notes = [dataOnlyNote]
        if version < 4 {
            notes.append("格式版本 \(version) 是旧版格式；本仓库固件可读取版本 2 及以上的 NFC 文件。")
        } else if !nfcDeviceTypes.contains(deviceType) {
            notes.append("设备类型“\(TextFormat.display(deviceType))”不在本仓库固件的 NFC 协议列表中，设备可能无法打开此文件。")
        }
        return AnalysisReport(facts: facts, notes: notes)
    }

    /// 形如“Page 12”“Block 0”的键：固定前缀加十进制编号。
    fileprivate static func hasNumberedKey(_ key: String, prefix: String) -> Bool {
        guard key.hasPrefix(prefix) else { return false }
        let number = key.utf8.dropFirst(prefix.utf8.count)
        return !number.isEmpty && number.allSatisfy { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }
    }

    fileprivate static func analyzeRfid(_ document: FlipperDocument) throws -> AnalysisReport {
        var fields: [String: Entry] = [:]
        var otherFields: [String] = []
        var seenOther: Set<String> = []
        for entry in document.entries {
            if entry.key == "Key type" || entry.key == "Data" {
                if let first = fields[entry.key] { throw duplicateField(entry, firstLine: first.line) }
                fields[entry.key] = entry
            } else if seenOther.insert(entry.key).inserted {
                otherFields.append(entry.key)
            }
        }
        let keyType = try requiredText("Key type", in: fields, document: document)
        guard let dataEntry = fields["Data"] else { throw RecordAnalysisError.missingField(field: "Data", line: nil) }
        guard let data = document.hexBytes(dataEntry), !data.isEmpty else {
            throw RecordAnalysisError.invalidField(
                field: "Data", line: dataEntry.line, reason: "应为以空格分隔的两位十六进制字节")
        }
        var facts = [
            AnalysisFact("文件类型", document.header.fileType),
            AnalysisFact("格式版本", "\(document.header.version)"),
            AnalysisFact("协议类型", TextFormat.display(keyType.value)),
            AnalysisFact("数据长度", "\(data.count) 字节"),
        ]
        if !otherFields.isEmpty { facts.append(AnalysisFact("其他字段", TextFormat.list(otherFields, limit: 12))) }
        var notes = [dataOnlyNote]
        if !rfidKeyTypes.contains(keyType.value.lowercased()) {
            notes.append("协议类型“\(TextFormat.display(keyType.value))”不在本仓库固件的低频 RFID 协议列表中。")
        }
        return AnalysisReport(facts: facts, notes: notes)
    }

    fileprivate static func analyzeIButton(_ document: FlipperDocument) throws -> AnalysisReport {
        let legacy = document.header.version == 1
        let typeKey = legacy ? "Key type" : "Protocol"
        let dataKeys = legacy ? ["Data"] : iButtonDataFields
        var typeEntry: Entry?
        var dataLines: [String: Int] = [:]
        var dataFacts: [AnalysisFact] = []
        var otherFields: [String] = []
        var seenOther: Set<String> = []
        for entry in document.entries {
            if entry.key == typeKey {
                if let first = typeEntry { throw duplicateField(entry, firstLine: first.line) }
                typeEntry = entry
            } else if dataKeys.contains(entry.key) {
                if let firstLine = dataLines[entry.key] { throw duplicateField(entry, firstLine: firstLine) }
                guard let data = document.hexBytes(entry), !data.isEmpty else {
                    throw RecordAnalysisError.invalidField(
                        field: entry.key, line: entry.line, reason: "应为以空格分隔的两位十六进制字节")
                }
                dataLines[entry.key] = entry.line
                dataFacts.append(AnalysisFact("\(entry.key) 长度", "\(data.count) 字节"))
            } else if seenOther.insert(entry.key).inserted {
                otherFields.append(entry.key)
            }
        }
        guard let protocolEntry = typeEntry else { throw RecordAnalysisError.missingField(field: typeKey, line: nil) }
        let protocolName = try requiredText(typeKey, in: [typeKey: protocolEntry], document: document)
        guard !dataFacts.isEmpty else {
            throw RecordAnalysisError.missingField(field: legacy ? "Data" : "Rom Data 或 Data", line: nil)
        }
        var facts = [
            AnalysisFact("文件类型", document.header.fileType),
            AnalysisFact("格式版本", legacy ? "1（旧版格式）" : "\(document.header.version)"),
            AnalysisFact(legacy ? "类型" : "协议", TextFormat.display(protocolName.value)),
        ]
        facts += dataFacts
        if !otherFields.isEmpty { facts.append(AnalysisFact("其他字段", TextFormat.list(otherFields, limit: 12))) }
        var notes = [dataOnlyNote]
        if legacy { notes.append("格式版本 1 是旧版格式，固件保存时会转换为版本 2。") }
        if !(legacy ? iButtonLegacyTypes : iButtonProtocols).contains(protocolName.value) {
            notes.append("“\(TextFormat.display(protocolName.value))”不在 iButton 文件格式文档列出的类型中。")
        }
        return AnalysisReport(facts: facts, notes: notes)
    }
}

// MARK: - 串口日志

extension RecordAnalyzer {
    fileprivate struct LogMarker: Sendable {
        let pattern: [UInt8]
        let ignoresCase: Bool

        init(_ text: String, ignoresCase: Bool = false) {
            pattern = Array((ignoresCase ? text.lowercased() : text).utf8)
            self.ignoresCase = ignoresCase
        }
    }

    /// Flipper 日志行形如“1234 [E][Tag] …”（级别字母前可能有 ANSI 颜色代码）。
    fileprivate static let errorMarkers = [
        LogMarker("[E]"), LogMarker("error", ignoresCase: true), LogMarker("错误"), LogMarker("失败"),
    ]
    fileprivate static let warningMarkers = [
        LogMarker("[W]"), LogMarker("warn", ignoresCase: true), LogMarker("警告"),
    ]

    fileprivate static func analyzeSerial(_ input: TextInput) -> AnalysisReport {
        let bytes = input.bytes
        var cursor = LineCursor(input)
        var lineCount = 0
        var nonEmptyLines = 0
        var errorLines = 0
        var warningLines = 0
        var longestLine = 0
        while let current = cursor.next() {
            lineCount += 1
            longestLine = Swift.max(longestLine, current.end - current.start)
            guard !FF.isBlank(current, bytes) else { continue }
            nonEmptyLines += 1
            if errorMarkers.contains(where: { lineContains(current, bytes, $0) }) {
                errorLines += 1
            } else if warningMarkers.contains(where: { lineContains(current, bytes, $0) }) {
                warningLines += 1
            }
        }
        let facts = [
            AnalysisFact("行数", "\(lineCount)"),
            AnalysisFact("非空行", "\(nonEmptyLines)"),
            AnalysisFact("错误行（关键词）", "\(errorLines)"),
            AnalysisFact("警告行（关键词）", "\(warningLines)"),
            AnalysisFact("文本大小", TextFormat.bytes(bytes.count)),
            AnalysisFact("最长一行", TextFormat.bytes(longestLine)),
        ]
        var notes = [
            "错误与警告按行做简单关键词匹配：含 [E]、error、错误或失败的行记为错误，其余含 [W]、warn 或警告的行记为警告。结果仅供筛选，可能误报或漏报。",
        ]
        if input.terminalControlLine != nil {
            notes.append("日志含终端控制字符（例如 ANSI 颜色代码），统计按原文进行。")
        }
        return AnalysisReport(facts: facts, notes: notes)
    }

    fileprivate static func lineContains(_ line: SourceLine, _ bytes: [UInt8], _ marker: LogMarker) -> Bool {
        let pattern = marker.pattern
        guard !pattern.isEmpty, line.end - line.start >= pattern.count else { return false }
        let lastStart = line.end - pattern.count
        var start = line.start
        while start <= lastStart {
            var offset = 0
            while offset < pattern.count {
                var byte = bytes[start + offset]
                if marker.ignoresCase, byte >= UInt8(ascii: "A"), byte <= UInt8(ascii: "Z") { byte += 0x20 }
                if byte != pattern[offset] { break }
                offset += 1
            }
            if offset == pattern.count { return true }
            start += 1
        }
        return false
    }
}

// MARK: - 图表数据与文本格式

extension RecordAnalyzer {
    /// 把带符号时长序列缩减为最多 `maxPlotPoints` 个点：按顺序等分成若干段，
    /// 每段保留绝对值最大的原始值（含符号）。只用于绘图，统计不受影响。
    fileprivate static func plotPoints(_ values: [Int64]) -> [Double] {
        let limit = maxPlotPoints
        guard values.count > limit else { return values.map { Double($0) } }
        var points: [Double] = []
        points.reserveCapacity(limit)
        for bucket in 0..<limit {
            let lower = bucket * values.count / limit
            let upper = (bucket + 1) * values.count / limit
            var best = values[lower]
            var index = lower + 1
            while index < upper {
                if values[index].magnitude > best.magnitude { best = values[index] }
                index += 1
            }
            points.append(Double(best))
        }
        return points
    }

    fileprivate static func reductionNote(_ count: Int) -> String {
        "图表数据共 \(count) 个时长，按顺序分成 \(maxPlotPoints) 段、每段显示绝对值最大的一个；统计数字基于全部数据。"
    }

    fileprivate enum TextFormat {
        static let hexDigits = Array("0123456789ABCDEF".utf8)

        static func bytes(_ count: Int) -> String {
            if count < 1024 { return "\(count) 字节" }
            if count < 1024 * 1024 { return "\(count) 字节（约 \(decimal(Double(count) / 1024, digits: 1)) KiB）" }
            return "\(count) 字节（约 \(decimal(Double(count) / 1_048_576, digits: 2)) MiB）"
        }

        /// 固定小数位后去掉末尾的 0，使用与区域设置无关的“.”作小数点。
        static func decimal(_ value: Double, digits: Int) -> String {
            guard value.isFinite else { return "—" }
            var text = String(format: "%.\(digits)f", value)
            if text.contains(".") {
                while text.hasSuffix("0") { text.removeLast() }
                if text.hasSuffix(".") { text.removeLast() }
            }
            return text
        }

        static func microseconds(_ value: Double) -> String {
            if value < 1000 { return "\(decimal(value, digits: 1)) µs" }
            if value < 1_000_000 { return "\(decimal(value / 1000, digits: 2)) ms" }
            return "\(decimal(value / 1_000_000, digits: 3)) s"
        }

        static func frequency(_ hertz: Int64) -> String {
            if hertz >= 1_000_000 { return "\(decimal(Double(hertz) / 1_000_000, digits: 3)) MHz（\(hertz) Hz）" }
            if hertz >= 1000 { return "\(decimal(Double(hertz) / 1000, digits: 3)) kHz（\(hertz) Hz）" }
            return "\(hertz) Hz"
        }

        static func hex(_ values: [UInt8]) -> String {
            var output: [UInt8] = []
            output.reserveCapacity(values.count * 3)
            for (index, value) in values.enumerated() {
                if index > 0 { output.append(UInt8(ascii: " ")) }
                output.append(hexDigits[Int(value >> 4)])
                output.append(hexDigits[Int(value & 0x0F)])
            }
            return String(decoding: output, as: UTF8.self)
        }

        /// 引用文件内容时使用：控制字符替换为 ?，超长时截断。
        static func display(_ value: String, limit: Int = 48) -> String {
            var output = String.UnicodeScalarView()
            var count = 0
            for scalar in value.unicodeScalars {
                if count == limit {
                    output.append("…")
                    break
                }
                output.append(scalar.value < 0x20 || scalar.value == 0x7F ? "?" : scalar)
                count += 1
            }
            return String(output)
        }

        static func list(_ items: [String], limit: Int) -> String {
            let shown = items.prefix(limit).map { display($0) }.joined(separator: "、")
            return items.count > limit ? "\(shown) 等 \(items.count) 项" : shown
        }
    }
}
