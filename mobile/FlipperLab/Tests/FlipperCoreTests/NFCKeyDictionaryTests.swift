import XCTest
import FlipperCore

final class NFCKeyDictionaryTests: XCTestCase {
    /// Excerpt of the firmware's bundled mf_classic_dict.nfc: comment blocks around well-known default keys.
    private static let flipperDictionary = """
        # Key dictionary from https://github.com/RfidResearchGroup/proxmark3/blob/master/client/dictionaries/mfc_default_keys.dic
        #
        # Mifare Default Keys
        #   -- Iceman Fork Version --
        #
        # Default key
        FFFFFFFFFFFF
        #
        # Blank key
        000000000000
        #
        # NFC Forum MADkey
        A0A1A2A3A4A5
        #
        # MAD access key A (reversed)
        A5A4A3A2A1A0
        #
        # MAD access key B
        89ECA97F8C2A
        #
        # Mifare 1k EV1 (S50) hidden blocks, Signature data
        # 16 A
        5C8FF9990DA2
        #
        # 17 A
        75CCB59C9BED

        """

    private static let flipperKeys = [
        "FFFFFFFFFFFF", "000000000000", "A0A1A2A3A4A5", "A5A4A3A2A1A0",
        "89ECA97F8C2A", "5C8FF9990DA2", "75CCB59C9BED",
    ]

    // MARK: - Helpers

    /// `value` as 12 uppercase hex digits, so distinct values give distinct keys.
    private func key(_ value: Int) -> String {
        let hex = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: 12 - hex.count) + hex
    }

    /// One key per line for every value in `values`, with a final newline.
    private func text(_ values: Range<Int>) -> String {
        values.map { key($0) }.joined(separator: "\n") + "\n"
    }

    private func expectError(_ expression: @autoclosure () throws -> Any,
                             file: StaticString = #filePath, line: UInt = #line,
                             where matches: (NFCKeyDictionaryError) -> Bool) {
        do {
            _ = try expression()
            XCTFail("预期抛出错误，但解析成功", file: file, line: line)
        } catch let error as NFCKeyDictionaryError {
            XCTAssertTrue(matches(error), "错误类型不符：\(error)", file: file, line: line)
        } catch {
            XCTFail("抛出了非 NFCKeyDictionaryError：\(error)", file: file, line: line)
        }
    }

    // MARK: - Parsing

    func testParsesTypicalFlipperDictionaryInFileOrder() throws {
        let dictionary = try NFCKeyDictionary(text: Self.flipperDictionary)
        XCTAssertEqual(dictionary.keys, Self.flipperKeys)
        XCTAssertEqual(dictionary.text, Self.flipperKeys.joined(separator: "\n") + "\n")
    }

    func testAcceptsBOMLineEndingsSurroundingWhitespaceAndByteSeparators() throws {
        let text = "\u{FEFF}# header\r\n\r\n  ffffffffffff  \r\n\tA0 a1 A2 a3 A4 a5\r\n89:ec:a9:7f:8c:2a\r\n"
            + "   # indented comment\r\n000000000000"
        let dictionary = try NFCKeyDictionary(text: text)
        XCTAssertEqual(dictionary.keys, ["FFFFFFFFFFFF", "A0A1A2A3A4A5", "89ECA97F8C2A", "000000000000"])
        // Lone CR line endings, and a last line without a newline.
        XCTAssertEqual(try NFCKeyDictionary(text: "FFFFFFFFFFFF\r000000000000").keys,
                       ["FFFFFFFFFFFF", "000000000000"])
        // The same content with LF, CRLF or CR endings gives the same dictionary.
        let lf = Self.flipperDictionary
        XCTAssertEqual(try NFCKeyDictionary(text: lf.replacingOccurrences(of: "\n", with: "\r\n")),
                       try NFCKeyDictionary(text: lf))
        XCTAssertEqual(try NFCKeyDictionary(text: lf.replacingOccurrences(of: "\n", with: "\r")),
                       try NFCKeyDictionary(text: lf))
    }

    func testDeduplicatesAcrossLetterCaseAndSeparatorStyles() throws {
        let text = """
            ffffffffffff
            FF FF FF FF FF FF
            FF:FF:FF:FF:FF:FF
            a0a1a2a3a4a5
            FFFFFFFFFFFF
            A0A1A2A3A4A5

            """
        XCTAssertEqual(try NFCKeyDictionary(text: text).keys, ["FFFFFFFFFFFF", "A0A1A2A3A4A5"])
    }

    func testCanonicalTextRoundTrips() throws {
        let source = Self.flipperDictionary + "d0:1a:fe:eb:89:0a\r\n4b 79 1b ea 7b cc\r\n"
        let dictionary = try NFCKeyDictionary(text: source)
        let text = dictionary.text
        XCTAssertEqual(text, (Self.flipperKeys + ["D01AFEEB890A", "4B791BEA7BCC"]).joined(separator: "\n") + "\n")
        XCTAssertTrue(text.hasSuffix("\n"))
        XCTAssertFalse(text.hasSuffix("\n\n"))
        // Every output line is what the firmware's keys_dict reader expects: exactly 12 uppercase hex digits.
        for line in text.split(separator: "\n") {
            XCTAssertEqual(line.count, 12, String(line))
            XCTAssertTrue(line.allSatisfy { $0.isHexDigit && !$0.isLowercase }, String(line))
        }
        let reparsed = try NFCKeyDictionary(text: text)
        XCTAssertEqual(reparsed, dictionary)
        XCTAssertEqual(reparsed.text, text)
    }

    // MARK: - Malformed lines

    func testWrongKeyWidthIsReportedWithLineNumber() {
        expectError(try NFCKeyDictionary(text: "\u{FEFF}# comment\r\n\r\nFFFFFFFFFFFF\r\nFFFFFFFFFFF\r\n")) {
            $0 == .invalidKeyLength(line: 4, digitCount: 11)
        }
        expectError(try NFCKeyDictionary(text: "FFFFFFFFFFFF\n# c\nFFFFFFFFFFFFF\n")) {
            $0 == .invalidKeyLength(line: 3, digitCount: 13)
        }
        // Two keys on one line, too many byte groups, separators without digits, and an 8-byte key.
        expectError(try NFCKeyDictionary(text: "FFFFFFFFFFFF FFFFFFFFFFFF\n")) {
            $0 == .invalidKeyLength(line: 1, digitCount: 24)
        }
        expectError(try NFCKeyDictionary(text: "FF FF FF FF FF FF FF\n")) {
            $0 == .invalidKeyLength(line: 1, digitCount: 14)
        }
        expectError(try NFCKeyDictionary(text: "FFFFFFFFFFFF\n:\n")) {
            $0 == .invalidKeyLength(line: 2, digitCount: 0)
        }
        expectError(try NFCKeyDictionary(text: "0123456789ABCDEF\n")) {
            $0 == .invalidKeyLength(line: 1, digitCount: 16)
        }
        // Valid keys earlier in the file never make a malformed line skippable.
        let appendedLine = Self.flipperDictionary.filter { $0 == "\n" }.count + 1
        expectError(try NFCKeyDictionary(text: Self.flipperDictionary + "FFFFFFFFFFF\n")) {
            $0 == .invalidKeyLength(line: appendedLine, digitCount: 11)
        }
    }

    func testInvalidCharactersAndInlineCommentsAreRejected() {
        let cases: [(text: String, character: String)] = [
            ("FFFFFFFFFFFG", "G"),
            ("FFFFFFFFFFFF # default key", "#"),
            ("0xFFFFFFFFFFFF", "x"),
            ("FF-FF-FF-FF-FF-FF", "-"),
            ("FF\tFF\tFF\tFF\tFF\tFF", "U+0009"),
            ("FFFFFFFFFFFF\u{FEFF}", "U+FEFF"),
            ("FFFFFFFFFFFF\u{00A0}", "U+00A0"),
            ("FFFFFFFFFFFF\u{0}", "U+0000"),
            ("密钥 FFFFFFFFFFFF", "密"),
            ("FFFFFFFFFFFF；", "；"),
        ]
        for item in cases {
            expectError(try NFCKeyDictionary(text: "000000000000\n" + item.text + "\n")) {
                $0 == .invalidCharacter(line: 2, character: item.character)
            }
        }
        let inline = NFCKeyDictionaryError.invalidCharacter(line: 2, character: "#").errorDescription ?? ""
        XCTAssertTrue(inline.contains("注释"), inline)
    }

    func testAmbiguousSeparatorsAreRejected() {
        let cases = [
            "FFF FFF FFF FFF",
            "FFFF FFFF FFFF",
            "FFFFFF FFFFFF",
            "FF  FF FF FF FF FF",
            "FF::FF:FF:FF:FF:FF",
            "FF:FF FF:FF FF:FF",
            "F FF FF FF FF FF F",
            ":FF:FF:FF:FF:FF:FF",
            "FF:FF:FF:FF:FF:FF:",
            "FFFFFFFFFFF F",
        ]
        for text in cases {
            expectError(try NFCKeyDictionary(text: "# keys\n" + text + "\n")) { $0 == .invalidSeparators(line: 2) }
        }
    }

    func testEmptyInputIsAnError() {
        let empties = ["", "\n", "\r\n\r\n", "   \t\n", "\u{FEFF}", "# only comments\n#\n",
                       "\u{FEFF}# comment\r\n   # another\r\n"]
        for text in empties {
            expectError(try NFCKeyDictionary(text: text)) { $0 == .emptyDictionary }
        }
        expectError(try NFCKeyDictionary.merge([])) { $0 == .emptyDictionary }
    }

    // MARK: - Limits

    func testInputLimitIsTwoMebibytesOfUTF8() throws {
        let limit = NFCKeyDictionary.maxBytes
        XCTAssertEqual(limit, 2 * 1024 * 1024)
        let head = "FFFFFFFFFFFF\n#"
        let atLimit = head + String(repeating: "x", count: limit - head.utf8.count - 1) + "\n"
        XCTAssertEqual(atLimit.utf8.count, limit)
        XCTAssertEqual(try NFCKeyDictionary(text: atLimit).keys, ["FFFFFFFFFFFF"])
        expectError(try NFCKeyDictionary(text: atLimit + "\n")) {
            $0 == .inputTooLarge(byteCount: limit + 1, limit: limit)
        }
        // Counted in UTF-8 bytes, not characters: each CJK character is 3 bytes.
        let chinese = head + String(repeating: "钥", count: limit / 3)
        XCTAssertLessThan(chinese.count, limit)
        expectError(try NFCKeyDictionary(text: chinese)) {
            $0 == .inputTooLarge(byteCount: chinese.utf8.count, limit: limit)
        }
    }

    func testKeyLimitIsInclusiveAndCountsDistinctKeysOnly() throws {
        let limit = NFCKeyDictionary.maxKeys
        XCTAssertEqual(limit, 100_000)
        let full = text(0..<limit)
        // The key limit, not the byte limit, is what stops one more key.
        XCTAssertLessThan(full.utf8.count, NFCKeyDictionary.maxBytes)
        let dictionary = try NFCKeyDictionary(text: full)
        XCTAssertEqual(dictionary.keys.count, limit)
        XCTAssertEqual(dictionary.keys.first, "000000000000")
        XCTAssertEqual(dictionary.keys.last, key(limit - 1))
        // Repeated keys after the limit are not new keys.
        let duplicates = full + "000000000000\n" + key(limit - 1).lowercased() + "\n00 00 00 00 00 01\n"
        XCTAssertEqual(try NFCKeyDictionary(text: duplicates).keys.count, limit)
        expectError(try NFCKeyDictionary(text: full + key(limit) + "\n")) { $0 == .tooManyKeys(limit: limit) }
    }

    // MARK: - Merging

    func testMergeKeepsFirstSeenOrderAndDropsDuplicates() throws {
        let first = try NFCKeyDictionary(text: "FFFFFFFFFFFF\nA0A1A2A3A4A5\n")
        let second = try NFCKeyDictionary(text: "a0:a1:a2:a3:a4:a5\n000000000000\nFF FF FF FF FF FF\n")
        XCTAssertEqual(try NFCKeyDictionary.merge([first, second]).keys,
                       ["FFFFFFFFFFFF", "A0A1A2A3A4A5", "000000000000"])
        XCTAssertEqual(try NFCKeyDictionary.merge([second, first]).keys,
                       ["A0A1A2A3A4A5", "000000000000", "FFFFFFFFFFFF"])
        XCTAssertEqual(try NFCKeyDictionary.merge([first]), first)
        XCTAssertEqual(try NFCKeyDictionary.merge([first, first, first]), first)
        XCTAssertEqual(try NFCKeyDictionary.merge([first, second]).text, "FFFFFFFFFFFF\nA0A1A2A3A4A5\n000000000000\n")
    }

    func testMergeEnforcesKeyLimitAndStaysParseable() throws {
        let limit = NFCKeyDictionary.maxKeys
        let half = limit / 2
        let lower = try NFCKeyDictionary(text: text(0..<half))
        let upper = try NFCKeyDictionary(text: text(half..<limit))
        let overlapping = try NFCKeyDictionary(text: text((half - 10)..<limit))
        let extra = try NFCKeyDictionary(text: key(limit) + "\n")

        let merged = try NFCKeyDictionary.merge([lower, upper])
        XCTAssertEqual(merged.keys.count, limit)
        XCTAssertEqual(try NFCKeyDictionary.merge([lower, overlapping]).keys.count, limit)
        XCTAssertEqual(try NFCKeyDictionary.merge([lower, overlapping, upper]), merged)
        expectError(try NFCKeyDictionary.merge([lower, upper, extra])) { $0 == .tooManyKeys(limit: limit) }
        expectError(try NFCKeyDictionary.merge([extra, lower, upper])) { $0 == .tooManyKeys(limit: limit) }

        // The largest allowed result stays well inside the input limit and parses back unchanged.
        XCTAssertEqual(merged.text.utf8.count, limit * 13)
        XCTAssertLessThanOrEqual(merged.text.utf8.count, NFCKeyDictionary.maxBytes)
        XCTAssertEqual(try NFCKeyDictionary(text: merged.text), merged)
    }

    // MARK: - Errors

    func testEveryErrorHasChineseDescriptionWithLineNumber() {
        let errors: [NFCKeyDictionaryError] = [
            .inputTooLarge(byteCount: 2_097_153, limit: 2_097_152),
            .emptyDictionary,
            .invalidCharacter(line: 3, character: "G"),
            .invalidCharacter(line: 3, character: "#"),
            .invalidCharacter(line: 3, character: "U+0009"),
            .invalidKeyLength(line: 4, digitCount: 0),
            .invalidKeyLength(line: 4, digitCount: 11),
            .invalidKeyLength(line: 4, digitCount: 24),
            .invalidSeparators(line: 5),
            .tooManyKeys(limit: 100_000),
        ]
        for error in errors {
            let description = error.errorDescription ?? ""
            XCTAssertTrue(description.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }, "\(error)")
            XCTAssertFalse(description.contains("Optional("), description)
            XCTAssertEqual(error.localizedDescription, description)
        }
        let lineErrors: [(NFCKeyDictionaryError, Int)] = [
            (.invalidCharacter(line: 3, character: "G"), 3),
            (.invalidKeyLength(line: 4, digitCount: 11), 4),
            (.invalidSeparators(line: 5), 5),
        ]
        for (error, line) in lineErrors {
            XCTAssertTrue((error.errorDescription ?? "").contains("第 \(line) 行"), "\(error)")
        }
        let multiple = NFCKeyDictionaryError.invalidKeyLength(line: 4, digitCount: 24).errorDescription ?? ""
        XCTAssertTrue(multiple.contains("多个密钥"), multiple)
    }
}
