import XCTest
import FlipperCore

final class RecordStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlipperCoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let directory, FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    // MARK: - 辅助

    private func record(_ name: String, rawText: String = "boot ok\n") -> CaptureRecord {
        CaptureRecord(name: name, kind: .serial, rawText: rawText)
    }

    /// 目录中的全部文件，按名称排序。
    private func storeFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func expectStoreError(_ operation: () async throws -> Void,
                                  file: StaticString = #filePath, line: UInt = #line,
                                  where matches: (RecordStoreError) -> Bool) async {
        do {
            try await operation()
            XCTFail("预期操作失败，但没有抛出错误", file: file, line: line)
        } catch let error as RecordStoreError {
            XCTAssertTrue(matches(error), "错误类型不符：\(error)", file: file, line: line)
        } catch {
            XCTFail("抛出了非 RecordStoreError：\(error)", file: file, line: line)
        }
    }

    // MARK: - 读写

    func testMissingStoreLoadsAsEmptyWithoutCreatingFiles() async throws {
        let records = try await RecordStore(directory: directory).load()
        XCTAssertEqual(records, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testRoundTripPreservesEveryFieldAndExactRawText() async throws {
        // 组合字符（未规范化）、BOM、CRLF 与行尾空格都必须原样保留。
        let raw = "\u{FEFF}Filetype: IR signals file\r\nVersion: 1\r\n# Cafe\u{301} 🎛️ 客厅\r\nname: Power \r\n"
        let records = [
            CaptureRecord(name: "../../客厅电视", kind: .infrared,
                          createdAt: Date(timeIntervalSinceReferenceDate: 780_000_000.123_456_7),
                          sourcePath: "/ext/infrared/TV.ir", tags: ["客厅", "tv/remote"],
                          notes: "第一行\n第二行", rawText: raw),
            CaptureRecord(name: "日志", kind: .serial, rawText: "boot ok\n"),
        ]
        try await RecordStore(directory: directory).save(records)
        let loaded = try await RecordStore(directory: directory).load()
        XCTAssertEqual(loaded, records)
        XCTAssertEqual(loaded.map { Array($0.rawText.unicodeScalars) }, records.map { Array($0.rawText.unicodeScalars) })
        // 文件名固定，记录名称不会变成路径。
        XCTAssertEqual(try storeFiles().count, 1)
    }

    func testFileIsVersionedJsonEnvelope() async throws {
        try await RecordStore(directory: directory).save([record("A"), record("B")])
        let url = try XCTUnwrap(storeFiles().first)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual((object["records"] as? [Any])?.count, 2)
    }

    func testLimitsAreInclusive() async throws {
        let store = RecordStore(directory: directory)
        try await store.save((0..<1000).map { record("R\($0)") })
        let count = try await store.load().count
        XCTAssertEqual(count, 1000)

        let largest = record("Max", rawText: String(repeating: "a", count: 2 * 1024 * 1024))
        try await store.save([largest])
        let loaded = try await store.load()
        XCTAssertEqual(loaded, [largest])
    }

    // MARK: - 保存失败时保留原文件

    func testRejectedSavesLeavePreviousPrimaryUntouched() async throws {
        let store = RecordStore(directory: directory)
        let original = [record("A"), record("B")]
        try await store.save(original)
        let url = try XCTUnwrap(storeFiles().first)
        let before = try Data(contentsOf: url)

        let tooMany = (0...1000).map { record("R\($0)") }
        await expectStoreError({ try await store.save(tooMany) }) {
            $0 == .tooManyRecords(count: 1001, limit: 1000)
        }

        let first = record("C")
        let sameID = CaptureRecord(id: first.id, name: "D", kind: .nfc, rawText: "other")
        await expectStoreError({ try await store.save([first, sameID]) }) { $0 == .duplicateRecordID(first.id) }

        let oversized = record("Big", rawText: String(repeating: "a", count: 2 * 1024 * 1024 + 1))
        await expectStoreError({ try await store.save([oversized]) }) {
            $0 == .recordTooLarge(id: oversized.id, byteCount: 2 * 1024 * 1024 + 1, limit: 2 * 1024 * 1024)
        }

        let wordy = CaptureRecord(name: "N", kind: .serial, notes: String(repeating: "注", count: 30_000), rawText: "x")
        await expectStoreError({ try await store.save([wordy]) }) {
            if case .metadataTooLarge(wordy.id, _, _) = $0 { return true }
            return false
        }

        // 每条记录都在单条上限之内，但编码后合计超过 32 MiB。
        let maximal = String(repeating: "a", count: 2 * 1024 * 1024)
        let bulky = (0..<16).map { record("M\($0)", rawText: maximal) }
        await expectStoreError({ try await store.save(bulky) }) {
            if case let .storeTooLarge(byteCount, limit) = $0 { return byteCount > limit && limit == 32 * 1024 * 1024 }
            return false
        }

        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(try storeFiles().count, 1)
        let loaded = try await store.load()
        XCTAssertEqual(loaded, original)
    }

    // MARK: - 损坏文件

    func testCorruptPrimaryIsReportedInsteadOfLoadingEmpty() async throws {
        try await RecordStore(directory: directory).save([record("A")])
        let url = try XCTUnwrap(storeFiles().first)
        let valid = try Data(contentsOf: url)
        let corruptContents = [
            Data(),
            Data("{ not json".utf8),
            Data("[]".utf8),
            valid.prefix(valid.count / 2),
            Data("{\"format\":\"SomethingElse\",\"schemaVersion\":1,\"records\":[]}".utf8),
        ]
        for contents in corruptContents {
            try contents.write(to: url)
            let store = RecordStore(directory: directory)
            await expectStoreError({ _ = try await store.load() }) {
                if case .corruptStore = $0 { return true }
                return false
            }
        }
    }

    func testOversizedPrimaryIsReportedWithoutLoading() async throws {
        try await RecordStore(directory: directory).save([record("A")])
        let url = try XCTUnwrap(storeFiles().first)
        try Data(count: 32 * 1024 * 1024 + 1).write(to: url)
        let store = RecordStore(directory: directory)
        await expectStoreError({ _ = try await store.load() }) {
            if case .corruptStore = $0 { return true }
            return false
        }
    }

    func testNewerSchemaVersionIsReportedAndPreservedOnSave() async throws {
        try await RecordStore(directory: directory).save([record("A")])
        let url = try XCTUnwrap(storeFiles().first)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["schemaVersion"] = 2
        let newer = try JSONSerialization.data(withJSONObject: object)
        try newer.write(to: url)

        let store = RecordStore(directory: directory)
        await expectStoreError({ _ = try await store.load() }) { $0 == .unsupportedSchemaVersion(2) }

        // 保存新数据时，无法读取的旧文件改名保留，不会被覆盖或删除。
        let replacement = [record("B")]
        try await store.save(replacement)
        let loaded = try await store.load()
        XCTAssertEqual(loaded, replacement)
        let others = try storeFiles().filter { $0.lastPathComponent != url.lastPathComponent }
        XCTAssertEqual(others.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(others.first)), newer)
    }

    func testSavingWithoutPriorLoadDoesNotOverwriteCorruptPrimary() async throws {
        try await RecordStore(directory: directory).save([record("A")])
        let url = try XCTUnwrap(storeFiles().first)
        let garbage = Data("definitely not a record store".utf8)
        try garbage.write(to: url)

        let replacement = [record("B")]
        try await RecordStore(directory: directory).save(replacement)
        let loaded = try await RecordStore(directory: directory).load()
        XCTAssertEqual(loaded, replacement)
        let others = try storeFiles().filter { $0.lastPathComponent != url.lastPathComponent }
        XCTAssertEqual(others.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(others.first)), garbage)
    }

    // MARK: - 其他

    func testRejectsDirectoryThatIsNotLocal() async throws {
        let store = RecordStore(directory: try XCTUnwrap(URL(string: "https://example.com/records")))
        await expectStoreError({ _ = try await store.load() }) {
            if case .invalidDirectory = $0 { return true }
            return false
        }
        await expectStoreError({ try await store.save([]) }) {
            if case .invalidDirectory = $0 { return true }
            return false
        }
    }

    func testEveryErrorHasChineseDescription() {
        let id = UUID()
        let errors: [RecordStoreError] = [
            .invalidDirectory("https://example.com"),
            .tooManyRecords(count: 1001, limit: 1000),
            .duplicateRecordID(id),
            .recordTooLarge(id: id, byteCount: 2_097_153, limit: 2_097_152),
            .metadataTooLarge(id: id, byteCount: 90_000, limit: 65_536),
            .storeTooLarge(byteCount: 40_000_000, limit: 33_554_432),
            .corruptStore(reason: "文件为空"),
            .unsupportedSchemaVersion(2),
            .readFailed(reason: "权限不足"),
            .writeFailed(reason: "磁盘已满"),
        ]
        for error in errors {
            let description = error.errorDescription ?? ""
            XCTAssertTrue(description.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }, "\(error)")
            XCTAssertFalse(description.contains("Optional("), description)
        }
    }
}
