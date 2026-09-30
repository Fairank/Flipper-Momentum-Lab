import XCTest
import FlipperCore

final class NFCRecordComparisonTests: XCTestCase {
    // MARK: - 合成夹具

    /// 合成的 Mifare Classic 文件各行。这只是为比较逻辑编写的合成夹具，不是从实体卡或硬件抓取的数据；
    /// 测试只比较内存中的文本，不读卡，也不涉及射频。
    /// 每块 16 个字节：首字节是块号，其余是 `fill`，所以各块互不相同；`rows` 按块号替换冒号之后的字节。
    private func classicLines(type: String, blocks: Int, fill: String = "AA",
                              rows: [Int: String] = [:]) -> [String] {
        var lines = [
            "Filetype: Flipper NFC device",
            "Version: 4",
            "Device type: Mifare Classic",
            "UID: BA E2 7C 9D",
            "ATQA: 00 02",
            "SAK: 18",
            "Mifare Classic type: \(type)",
            "Data format version: 2",
        ]
        for index in 0..<blocks {
            let bytes = [String(format: "%02X", index)] + Array(repeating: fill, count: 15)
            lines.append("Block \(index): " + (rows[index] ?? bytes.joined(separator: " ")))
        }
        return lines
    }

    /// 合成的完整 MINI 文件（20 块）：全文 28 行，块 N 在第 9 + N 行。
    private func miniLines(rows: [Int: String] = [:]) -> [String] {
        classicLines(type: "MINI", blocks: 20, rows: rows)
    }

    /// 以 LF 换行、末尾带换行的文件文本。
    private func text(_ lines: [String]) -> String {
        lines.joined(separator: "\n") + "\n"
    }

    // MARK: - 辅助

    private func assertNoDifferences(_ report: NFCComparisonReport, unknownBytes: Int = 0,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(report.differences.map(\.address), [], file: file, line: line)
        XCTAssertEqual(report.totalDifferenceCount, 0, file: file, line: line)
        XCTAssertFalse(report.limited, file: file, line: line)
        XCTAssertEqual(report.leftUnknownByteCount, unknownBytes, file: file, line: line)
        XCTAssertEqual(report.rightUnknownByteCount, unknownBytes, file: file, line: line)
    }

    /// 报告恰好只有一处差异，地址、两侧取值与字节偏移都与预期一致。
    private func assertSingleDifference(_ report: NFCComparisonReport, _ address: NFCComparisonAddress,
                                        left: String, right: String, offsets: [Int] = [],
                                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(report.totalDifferenceCount, 1, file: file, line: line)
        XCTAssertFalse(report.limited, file: file, line: line)
        XCTAssertEqual(report.differences.map(\.address), [address], file: file, line: line)
        XCTAssertEqual(report.differences.first?.left, left, file: file, line: line)
        XCTAssertEqual(report.differences.first?.right, right, file: file, line: line)
        XCTAssertEqual(report.differences.first?.changedByteOffsets, offsets, file: file, line: line)
    }

    /// 无效文件放在任意一侧都必须被拒绝；`matches` 确认拒绝的原因指向预期的位置。
    /// 另一侧默认是有效的 MINI 夹具。
    private func expectRejected(_ invalid: [String], against valid: [String]? = nil,
                                file: StaticString = #filePath, line: UInt = #line,
                                where matches: (RecordAnalysisError) -> Bool) {
        let invalidText = text(invalid)
        let validText = text(valid ?? miniLines())
        for (left, right) in [(invalidText, validText), (validText, invalidText)] {
            do {
                _ = try NFCRecordComparison.compare(left, right)
                XCTFail("预期抛出错误，但比较成功", file: file, line: line)
            } catch let error as RecordAnalysisError {
                XCTAssertTrue(matches(error), "错误不符：\(error)", file: file, line: line)
            } catch {
                XCTFail("抛出了非 RecordAnalysisError：\(error)", file: file, line: line)
            }
        }
    }

    /// 拒绝的原因必须是指向给定字段与行号的 invalidField（原因文字不参与比较）。
    private func expectInvalidField(_ invalid: [String], against valid: [String]? = nil,
                                    field: String, atLine fieldLine: Int,
                                    file: StaticString = #filePath, line: UInt = #line) {
        expectRejected(invalid, against: valid, file: file, line: line) {
            if case .invalidField(field, fieldLine, _) = $0 { return true }
            return false
        }
    }

    // MARK: - 等价写法与差异定位

    func testLineOrderCommentsLineEndingsAndHexSpellingAreNotDifferences() throws {
        let lines = miniLines()
        // 类型名是区分大小写的文本，保持原样；其余各行的取值是十六进制字节或十进制数。
        let typeLines: Set = ["Device type: Mifare Classic", "Mifare Classic type: MINI"]
        // 文件头两行留在原位，其后各行倒序；注释里那行内容不同的 Block 7 不是数据。
        var rewritten = Array(lines.prefix(2))
        rewritten += ["# Mifare Classic blocks, '??' means unknown data",
                      "# Block 7: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF"]
        for line in lines.dropFirst(2).reversed() {
            guard !typeLines.contains(line) else {
                rewritten.append(line)
                continue
            }
            // 小写十六进制；冒号后用制表符，字节之间混用空格与制表符，行尾留一个空格。
            let parts = line.components(separatedBy: ": ")
            rewritten.append(parts[0] + ":\t" + parts[1].lowercased().replacingOccurrences(of: " ", with: " \t") + " ")
        }
        // UTF-8 BOM 开头，CRLF 换行。
        let other = "\u{FEFF}" + rewritten.joined(separator: "\r\n") + "\r\n"
        XCTAssertTrue(other.contains("Block 7:\t07 \taa \taa"), "夹具没有按预期改写")

        assertNoDifferences(try NFCRecordComparison.compare(text(lines), other))
        assertNoDifferences(try NFCRecordComparison.compare(other, text(lines)))
    }

    func testSingleChangedByteIsReportedAtItsBlockAndOffset() throws {
        // 块 7 的第 5 个字节（从 0 起的偏移 4）由 AA 改为 BB。
        let changedRow = "07 AA AA AA BB AA AA AA AA AA AA AA AA AA AA AA"
        let report = try NFCRecordComparison.compare(text(miniLines()), text(miniLines(rows: [7: changedRow])))
        assertSingleDifference(report, .block(7), left: "07 AA AA AA AA AA AA AA AA AA AA AA AA AA AA AA",
                               right: changedRow, offsets: [4])
        XCTAssertEqual(report.leftUnknownByteCount, 0)
        XCTAssertEqual(report.rightUnknownByteCount, 0)
    }

    func testUnknownBytesDifferFromZeroAndAreCountedPerSide() throws {
        // 块 6：一侧有 3 个未读出的字节（??）；另一侧把偏移 2 和 15 写成 00，偏移 10 仍是 ??。
        let unreadRow = "06 AA ?? AA AA AA AA AA AA AA ?? AA AA AA AA ??"
        let zeroedRow = "06 AA 00 AA AA AA AA AA AA AA ?? AA AA AA AA 00"
        let unread = text(miniLines(rows: [6: unreadRow]))
        let zeroed = text(miniLines(rows: [6: zeroedRow]))

        // ?? 不等于 00；两侧同为 ?? 的偏移 10 不在变化之列。
        let report = try NFCRecordComparison.compare(unread, zeroed)
        assertSingleDifference(report, .block(6), left: unreadRow, right: zeroedRow, offsets: [2, 15])
        XCTAssertEqual(report.leftUnknownByteCount, 3)
        XCTAssertEqual(report.rightUnknownByteCount, 1)

        // 左右对调后，未知字节数跟随各自一侧。
        let swapped = try NFCRecordComparison.compare(zeroed, unread)
        assertSingleDifference(swapped, .block(6), left: zeroedRow, right: unreadRow, offsets: [2, 15])
        XCTAssertEqual(swapped.leftUnknownByteCount, 1)
        XCTAssertEqual(swapped.rightUnknownByteCount, 3)

        // 两侧同为 ?? 时没有差异，未知字节照常计数。
        assertNoDifferences(try NFCRecordComparison.compare(unread, unread), unknownBytes: 3)
    }

    // MARK: - 无效文件

    func testDuplicateBlockNumberAndDuplicateUIDAreRejected() {
        let lines = miniLines()
        // 追加在第 29 行的“Block 01”与第 10 行的“Block 1”是同一个块号；内容不同，无法判断以哪一行为准。
        expectInvalidField(lines + ["Block 01: 01 BB BB BB BB BB BB BB BB BB BB BB BB BB BB BB"],
                           field: "Block 01", atLine: 29)
        expectInvalidField(lines + ["UID: 11 22 33 44"], field: "UID", atLine: 29)
    }

    func testTruncatedMalformedAndOutOfRangeBlocksAreRejected() {
        let lines = miniLines()
        // 删除最后一块：MINI 应有 20 块，Block 19 缺失。
        expectRejected(Array(lines.dropLast())) {
            if case let .missingField(field, _) = $0 { return field.hasPrefix("Block 19") }
            return false
        }
        // 块 3（第 12 行）：16 个字节变成 15 个；含有非十六进制的 GG。
        expectInvalidField(miniLines(rows: [3: "03 AA AA AA AA AA AA AA AA AA AA AA AA AA AA"]),
                           field: "Block 3", atLine: 12)
        expectInvalidField(miniLines(rows: [3: "03 AA AA AA GG AA AA AA AA AA AA AA AA AA AA AA"]),
                           field: "Block 3", atLine: 12)
        // 追加在第 29 行的块：负编号，以及超出 64 位整数范围的巨大编号。
        let row = "00 AA AA AA AA AA AA AA AA AA AA AA AA AA AA AA"
        expectInvalidField(lines + ["Block -1: \(row)"], field: "Block -1", atLine: 29)
        expectInvalidField(lines + ["Block 99999999999999999999999999: \(row)"],
                           field: "Block 99999999999999999999999999", atLine: 29)
    }

    func testReportListsOnly200DifferencesButCountsAndValidatesAll256Blocks() throws {
        // 完整的 4K（256 块）：两侧每一块的后 15 个字节都不同。
        let left = classicLines(type: "4K", blocks: 256)
        let right = classicLines(type: "4K", blocks: 256, fill: "BB")
        let report = try NFCRecordComparison.compare(text(left), text(right))
        XCTAssertEqual(NFCRecordComparison.maxReportedDifferences, 200)
        XCTAssertEqual(report.totalDifferenceCount, 256)
        XCTAssertEqual(report.differences.count, 200)
        XCTAssertTrue(report.limited)
        // 报告只列出块号最小的 200 处，每一项仍带完整的取值与偏移。
        XCTAssertEqual(report.differences.map(\.address), (0..<200).map { NFCComparisonAddress.block($0) })
        XCTAssertTrue(report.differences.allSatisfy { $0.changedByteOffsets == Array(1...15) })
        XCTAssertEqual(report.differences.last?.left, "C7 AA AA AA AA AA AA AA AA AA AA AA AA AA AA AA")
        XCTAssertEqual(report.differences.last?.right, "C7 BB BB BB BB BB BB BB BB BB BB BB BB BB BB BB")

        // 最后一块（第 264 行）含非法的 GG：此前的差异早已填满报告，仍必须报错，而不是提前返回。
        let invalid = classicLines(type: "4K", blocks: 256, fill: "BB",
                                   rows: [255: "FF BB BB BB BB BB BB BB BB BB BB BB BB BB BB GG"])
        expectInvalidField(invalid, against: left, field: "Block 255", atLine: 264)
    }

    // MARK: - 其他类型与旧版格式

    func testISO4AMetadataComparesByFieldAndFeliCaIsExplicitlyUnsupported() throws {
        // 合法的 ISO14443-4A 元数据：4 字节 UID 与 T0/TA(1)/TB(1)/TC(1)，没有 ATS 行、历史字节和存储行。
        func iso(uid: String) -> String {
            text([
                "Filetype: Flipper NFC device",
                "Version: 4",
                "Device type: ISO14443-4A",
                "UID: \(uid)",
                "ATQA: 00 04",
                "SAK: 20",
                "T0: 78",
                "TA(1): 80",
                "TB(1): 70",
                "TC(1): 02",
            ])
        }
        let card = iso(uid: "BA E2 7C 9D")
        assertNoDifferences(try NFCRecordComparison.compare(card, card))

        let report = try NFCRecordComparison.compare(card, iso(uid: "11 22 33 44"))
        assertSingleDifference(report, .field("UID"), left: "BA E2 7C 9D", right: "11 22 33 44")

        // FeliCa 的 Block 行是 2 个状态字节加 16 个数据字节：应在第 3 行明确报告类型不受支持，
        // 而不是套用 Classic 的 16 字节规则去指责 Block 0。
        let felica = [
            "Filetype: Flipper NFC device",
            "Version: 4",
            "Device type: FeliCa",
            "UID: 01 2E 3D 12 34 56 78 9A",
            "Data format version: 1",
            "Manufacture id: 01 2E 3D 12 34 56 78 9A",
            "Manufacture parameter: 00 F1 00 00 00 01 43 00",
            "Blocks total: 1",
            "Blocks read: 1",
            "Block 0: 00 00 DE AD BE EF 00 00 00 00 00 00 00 00 00 00 00 00",
        ]
        expectRejected(felica) {
            if case let .invalidField(field, line, reason) = $0 {
                return field == "Device type" && line == 3 && reason.contains("不支持")
            }
            return false
        }
    }

    func testLegacyKeyMapsIgnoreLetterCaseAndRepeatedHeaderFieldIsRejected() throws {
        // 旧版数据格式的完整 MINI：没有 Data format version 行，密钥位图写成 16 位连续十六进制（全文 29 行）。
        func legacy(keyA: String, keyB: String) -> [String] {
            miniLines().flatMap { line -> [String] in
                line == "Data format version: 2" ? ["Key A map: \(keyA)", "Key B map: \(keyB)"] : [line]
            }
        }
        let upper = legacy(keyA: "000000000000001F", keyB: "000000000000001B")
        let lower = legacy(keyA: "000000000000001f", keyB: "000000000000001b")
        assertNoDifferences(try NFCRecordComparison.compare(text(upper), text(lower)))

        // 只有大小写不同不算差异；位图的值确实不同时仍要列出。
        let other = legacy(keyA: "000000000000001f", keyB: "000000000000000B")
        let report = try NFCRecordComparison.compare(text(upper), text(other))
        assertSingleDifference(report, .field("Key B map"), left: "000000000000001B", right: "000000000000000B")

        // 在末尾（第 30 行）再写一次文件头字段 Version。
        expectInvalidField(upper + ["Version: 4"], field: "Version", atLine: 30)
    }
}
