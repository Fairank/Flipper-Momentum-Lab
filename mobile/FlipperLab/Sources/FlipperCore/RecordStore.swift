import Foundation

/// 资料库读写错误；`errorDescription` 为面向用户的中文说明。
public enum RecordStoreError: Error, Equatable, Sendable {
    /// 目录不是本机文件 URL。
    case invalidDirectory(String)
    case tooManyRecords(count: Int, limit: Int)
    case duplicateRecordID(UUID)
    /// 单条记录的原始文本超过上限。
    case recordTooLarge(id: UUID, byteCount: Int, limit: Int)
    /// 单条记录的名称、备注、标签与来源路径合计超过上限。
    case metadataTooLarge(id: UUID, byteCount: Int, limit: Int)
    /// 编码后的资料库超过文件上限。
    case storeTooLarge(byteCount: Int, limit: Int)
    /// 主文件存在，但内容为空、无法解析、超出上限或不满足资料库约束。
    case corruptStore(reason: String)
    case unsupportedSchemaVersion(Int)
    case readFailed(reason: String)
    case writeFailed(reason: String)
}

extension RecordStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidDirectory(location):
            return "资料库目录必须是本机文件路径：\(location)"
        case let .tooManyRecords(count, limit):
            return "共有 \(count) 条记录，超过上限 \(limit) 条，未保存；原有资料库保持不变。"
        case let .duplicateRecordID(id):
            return "记录 ID \(id.uuidString) 重复，未保存；原有资料库保持不变。"
        case let .recordTooLarge(id, byteCount, limit):
            return "记录 \(id.uuidString) 的原始文本为 \(RecordStore.describeBytes(byteCount))，超过单条上限 \(RecordStore.describeBytes(limit))，未保存。"
        case let .metadataTooLarge(id, byteCount, limit):
            return "记录 \(id.uuidString) 的名称、备注、标签和来源路径合计 \(RecordStore.describeBytes(byteCount))，超过上限 \(RecordStore.describeBytes(limit))，未保存。"
        case let .storeTooLarge(byteCount, limit):
            return "资料库编码后为 \(RecordStore.describeBytes(byteCount))，超过文件上限 \(RecordStore.describeBytes(limit))，未保存；原有资料库保持不变。"
        case let .corruptStore(reason):
            return "资料库文件已损坏或无法识别：\(reason)。原文件没有被修改。"
        case let .unsupportedSchemaVersion(version):
            return "资料库文件的数据版本为 \(version)，当前应用只支持版本 \(RecordStore.schemaVersion)。原文件没有被修改。"
        case let .readFailed(reason):
            return "无法读取资料库文件：\(reason)。"
        case let .writeFailed(reason):
            return "无法保存资料库：\(reason)。原有资料库保持不变。"
        }
    }
}

/// 采集记录资料库：在给定目录中用一个 JSON 文件保存全部记录。
///
/// 文件为信封格式 `{"format": …, "schemaVersion": 1, "records": […]}`，文件名固定，
/// 不根据记录名称生成路径，只读写给定目录内的文件，不执行任何删除操作。
/// 保存时先完成校验与编码，再以原子写入替换主文件；任一步失败，原主文件保持不变。
/// 主文件不存在时读取结果为空；文件损坏或版本不受支持时抛出错误，不会当作空资料库。
/// 若要覆盖一个无法读取的主文件，会先把它改名保留在同一目录中。
public actor RecordStore {
    public static let schemaVersion = 1
    public static let maxRecordCount = 1000
    /// 单条记录原始文本的上限，与 `RecordAnalyzer.maxInputBytes` 一致。
    public static let maxRawTextBytes = 2 * 1024 * 1024
    /// 单条记录名称、备注、标签与来源路径合计的上限。
    public static let maxMetadataBytes = 64 * 1024
    /// 编码后整个资料库文件的上限。
    public static let maxFileBytes = 32 * 1024 * 1024

    static let fileName = "capture-records.json"
    static let formatIdentifier = "FlipperLab.CaptureRecords"

    private let directory: URL
    private let fileURL: URL
    /// 本实例已确认主文件不存在或可以正常读取；否则保存前会先检查，避免覆盖无法读取的数据。
    private var primaryIsKnownReadable = false

    public init(directory: URL) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent(RecordStore.fileName, isDirectory: false)
    }

    public func load() throws -> [CaptureRecord] {
        try requireFileDirectory()
        guard let data = try Self.readPrimary(at: fileURL) else {
            primaryIsKnownReadable = true
            return []
        }
        do {
            let records = try Self.decode(data)
            primaryIsKnownReadable = true
            return records
        } catch {
            primaryIsKnownReadable = false
            throw error
        }
    }

    public func save(_ records: [CaptureRecord]) throws {
        try requireFileDirectory()
        if let problem = Self.violation(in: records) { throw problem }
        let data = try Self.encode(records)
        guard data.count <= Self.maxFileBytes else {
            throw RecordStoreError.storeTooLarge(byteCount: data.count, limit: Self.maxFileBytes)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw RecordStoreError.writeFailed(reason: "无法创建资料库目录（\(error.localizedDescription)）")
        }
        if !primaryIsKnownReadable {
            try setAsideUnreadablePrimary()
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw RecordStoreError.writeFailed(reason: error.localizedDescription)
        }
        primaryIsKnownReadable = true
    }

    private func requireFileDirectory() throws {
        guard directory.isFileURL else { throw RecordStoreError.invalidDirectory(directory.absoluteString) }
    }

    /// 覆盖前确认现有主文件可读。损坏、版本不受支持或超限的文件改名保留；
    /// 无法确认内容（读取失败）时取消保存。
    private func setAsideUnreadablePrimary() throws {
        do {
            if let data = try Self.readPrimary(at: fileURL) {
                _ = try Self.decode(data)
            }
            return
        } catch RecordStoreError.readFailed(let reason) {
            throw RecordStoreError.writeFailed(reason: "无法确认现有资料库文件的内容（\(reason)），为避免覆盖已取消保存")
        } catch {
            // 继续：把无法读取的文件改名保留，再写入新的主文件。
        }
        let stamp = Int64(Date().timeIntervalSince1970)
        let suffix = UUID().uuidString.prefix(8)
        let preservedURL = directory.appendingPathComponent(
            "capture-records.unreadable-\(stamp)-\(suffix).json", isDirectory: false)
        do {
            try FileManager.default.moveItem(at: fileURL, to: preservedURL)
        } catch {
            throw RecordStoreError.writeFailed(reason: "无法保留现有的损坏文件（\(error.localizedDescription)）")
        }
    }
}

// MARK: - 编码、解码与约束检查

extension RecordStore {
    struct Envelope: Codable {
        let format: String
        let schemaVersion: Int
        let records: [CaptureRecord]

        enum CodingKeys: String, CodingKey {
            case format, schemaVersion, records
        }

        init(records: [CaptureRecord]) {
            format = RecordStore.formatIdentifier
            schemaVersion = RecordStore.schemaVersion
            self.records = records
        }

        /// 先核对格式标识与版本，再解码记录，以便区分“不是资料库”“版本不受支持”和“内容损坏”。
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let format = try container.decode(String.self, forKey: .format)
            guard format == RecordStore.formatIdentifier else {
                throw RecordStoreError.corruptStore(reason: "格式标识“\(format.prefix(64))”不是 FlipperLab 资料库")
            }
            let version = try container.decode(Int.self, forKey: .schemaVersion)
            guard version == RecordStore.schemaVersion else {
                throw RecordStoreError.unsupportedSchemaVersion(version)
            }
            self.format = format
            self.schemaVersion = version
            self.records = try container.decode([CaptureRecord].self, forKey: .records)
        }
    }

    /// 读取主文件；不存在时返回 nil。最多读取上限加 1 个字节，超限视为损坏。
    static func readPrimary(at url: URL) throws -> Data? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        guard !isDirectory.boolValue else {
            throw RecordStoreError.readFailed(reason: "资料库文件的位置被一个目录占用")
        }
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: maxFileBytes + 1) ?? Data()
        } catch {
            throw RecordStoreError.readFailed(reason: error.localizedDescription)
        }
        guard data.count <= maxFileBytes else {
            throw RecordStoreError.corruptStore(reason: "文件超过 \(describeBytes(maxFileBytes)) 上限")
        }
        return data
    }

    static func decode(_ data: Data) throws -> [CaptureRecord] {
        guard !data.isEmpty else { throw RecordStoreError.corruptStore(reason: "文件为空") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch let error as RecordStoreError {
            throw error
        } catch {
            throw RecordStoreError.corruptStore(reason: describeDecodingFailure(error))
        }
        if let problem = violation(in: envelope.records) {
            throw RecordStoreError.corruptStore(reason: constraintSummary(problem))
        }
        return envelope.records
    }

    static func encode(_ records: [CaptureRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // 按 Date 自身的参考时间秒数保存，读回后与原值完全相等。
        encoder.dateEncodingStrategy = .deferredToDate
        do {
            return try encoder.encode(Envelope(records: records))
        } catch {
            throw RecordStoreError.writeFailed(reason: "记录无法编码为 JSON（例如创建时间不是有效数值）")
        }
    }

    /// 返回第一处违反数量、大小或 ID 唯一性约束的问题；全部满足时返回 nil。
    static func violation(in records: [CaptureRecord]) -> RecordStoreError? {
        guard records.count <= maxRecordCount else {
            return .tooManyRecords(count: records.count, limit: maxRecordCount)
        }
        var identifiers = Set<UUID>()
        for record in records {
            guard identifiers.insert(record.id).inserted else { return .duplicateRecordID(record.id) }
            let rawBytes = record.rawText.utf8.count
            guard rawBytes <= maxRawTextBytes else {
                return .recordTooLarge(id: record.id, byteCount: rawBytes, limit: maxRawTextBytes)
            }
            let metadataBytes = record.tags.reduce(
                record.name.utf8.count + record.notes.utf8.count + (record.sourcePath?.utf8.count ?? 0)
            ) { $0 + $1.utf8.count + 1 }
            guard metadataBytes <= maxMetadataBytes else {
                return .metadataTooLarge(id: record.id, byteCount: metadataBytes, limit: maxMetadataBytes)
            }
        }
        return nil
    }

    static func constraintSummary(_ problem: RecordStoreError) -> String {
        switch problem {
        case let .tooManyRecords(count, limit):
            return "记录数量 \(count) 超过上限 \(limit)"
        case let .duplicateRecordID(id):
            return "记录 ID \(id.uuidString) 重复"
        case let .recordTooLarge(id, _, limit):
            return "记录 \(id.uuidString) 的原始文本超过 \(describeBytes(limit))"
        case let .metadataTooLarge(id, _, limit):
            return "记录 \(id.uuidString) 的附加信息超过 \(describeBytes(limit))"
        default:
            return "内容不满足资料库约束"
        }
    }

    static func describeDecodingFailure(_ error: any Error) -> String {
        guard let decodingError = error as? DecodingError else { return "JSON 无法解析" }
        if case let .keyNotFound(key, context) = decodingError {
            return "缺少字段“\(codingPath(context.codingPath + [key]))”"
        }
        if case let .typeMismatch(_, context) = decodingError {
            return "字段“\(codingPath(context.codingPath))”的类型不正确"
        }
        if case let .valueNotFound(_, context) = decodingError {
            return "字段“\(codingPath(context.codingPath))”缺少值"
        }
        if case let .dataCorrupted(context) = decodingError, !context.codingPath.isEmpty {
            return "字段“\(codingPath(context.codingPath))”的数据无效"
        }
        return "不是有效的 JSON"
    }

    static func codingPath(_ keys: [any CodingKey]) -> String {
        keys.map { key in key.intValue.map { "[\($0)]" } ?? key.stringValue }.joined(separator: ".")
    }

    static func describeBytes(_ count: Int) -> String {
        if count >= 1024 * 1024, count % (1024 * 1024) == 0 { return "\(count / (1024 * 1024)) MiB" }
        if count >= 1024, count % 1024 == 0 { return "\(count / 1024) KiB" }
        return "\(count) 字节"
    }
}
