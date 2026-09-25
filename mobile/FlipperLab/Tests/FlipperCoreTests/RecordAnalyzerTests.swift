import XCTest
import FlipperCore

final class RecordAnalyzerTests: XCTestCase {
    // MARK: - 样例（取自 documentation/file_formats 中的示例）

    private static let infraredRemote = """
        Filetype: IR signals file
        Version: 1
        #
        name: Power
        type: parsed
        protocol: NECext
        address: EE 87 00 00
        command: 5D A0 00 00
        #
        name: Vol_up
        type: raw
        frequency: 38000
        duty_cycle: 0.330000
        data: 504 3432 502 483 500 484 510 502 502 482 501 485 509 1452 504 1458 509 1452 504 481 501 474 509 3420 503
        #
        name: Mute
        type: parsed
        protocol: SIRC
        address: 01 00 00 00
        command: 15 00 00 00

        """

    private static let subGhzRaw = """
        Filetype: Flipper SubGhz RAW File
        Version: 1
        Frequency: 433920000
        Preset: FuriHalSubGhzPresetOok650Async
        Protocol: RAW
        RAW_Data: 29262 361 -68 2635 -66 24113 -66 11
        RAW_Data: -424 205 -412 159 -412 381 -240 181
        RAW_Data: -1448 361 -17056 131 -134 233 -1462 131 -166 953 -100

        """

    private static let subGhzKey = """
        Filetype: Flipper SubGhz Key File
        Version: 1
        Frequency: 433920000
        Preset: FuriHalSubGhzPresetOok650Async
        Protocol: Princeton
        Bit: 24
        Key: 00 00 00 00 00 95 D5 D4
        TE: 400

        """

    private static let nfcUltralight = """
        Filetype: Flipper NFC device
        Version: 4
        # Device type can be ISO14443-3A, ISO14443-3B, ISO14443-4A, NTAG/Ultralight, Mifare Classic, Mifare DESFire
        Device type: NTAG/Ultralight
        # UID is common for all formats
        UID: 04 85 90 54 12 98 23
        # ISO14443-3A specific data
        ATQA: 00 44
        SAK: 00
        # NTAG/Ultralight specific data
        Data format version: 2
        NTAG/Ultralight type: NTAG216
        Signature: 1B 84 EB 70 BD 4C BD 1B 1D E4 98 0B 18 58 BD 7C 72 85 B4 E4 7B 38 8E 96 CF 88 6B EE A3 43 AD 90
        Mifare version: 00 04 04 02 01 00 13 03
        Counter 0: 0
        Tearing 0: 00
        Pages total: 4
        Pages read: 4
        Page 0: 04 85 92 9B
        Page 1: 8A A0 61 81
        Page 2: CA 48 0F 00
        Page 3: E1 10 6D 00
        Failed authentication attempts: 0

        """

    private static let nfcClassic = """
        Filetype: Flipper NFC device
        Version: 4
        Device type: Mifare Classic
        UID: BA E2 7C 9D
        ATQA: 00 02
        SAK: 18
        Mifare Classic type: 1K
        Data format version: 2
        # Mifare Classic blocks, '??' means unknown data
        Block 0: BA E2 7C 9D B9 18 02 00 46 44 53 37 30 56 30 31
        Block 1: ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ??
        Block 2: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
        Block 3: FF FF FF FF FF FF FF 07 80 69 FF FF FF FF FF FF

        """

    private static let rfidKey = """
        Filetype: Flipper RFID key
        Version: 1
        Key type: EM4100
        Data: 01 23 45 67 89

        """

    private static let iButtonKey = """
        Filetype: Flipper iButton key
        Version: 2
        Protocol: DS1992
        Rom Data: 08 DE AD BE EF FA CE 4E
        Sram Data: 4E 65 76 65 72 47 6F 6E 6E 61 47 69 76 65 59 6F 75 55 70 4E 65 76 65 72 47 6F 6E 6E 61 4C 65 74 59 6F 75 44 6F 77 6E 4E 65 76 65 72 47 6F 6E 6E 61 52 75 6E 41 72 6F 75 6E 64 41 6E 64 44 65 73 65 72 74 59 6F 75 4E 65 76 65 72 47 6F 6E 6E 61 4D 61 6B 65 59 6F 75 43 72 79 4E 65 76 65 72 47 6F 6E 6E 61 53 61 79 47 6F 6F 64 62 79 65 4E 65 76 65 72 47 6F 6E 6E 61 54 65 6C 6C 41 4C 69 65

        """

    // MARK: - 辅助

    private func irFile(_ buttons: [String], fileType: String = "IR signals file") -> String {
        "Filetype: \(fileType)\nVersion: 1\n" + buttons.map { "#\n\($0)\n" }.joined()
    }

    private func rawButton(_ name: String, frequency: String = "38000", dutyCycle: String = "0.330000",
                           data: String = "9024 4512 579 552 579") -> String {
        "name: \(name)\ntype: raw\nfrequency: \(frequency)\nduty_cycle: \(dutyCycle)\ndata: \(data)"
    }

    private func parsedButton(_ name: String, protocolName: String = "NEC", address: String = "04 00 00 00",
                              command: String = "08 00 00 00") -> String {
        "name: \(name)\ntype: parsed\nprotocol: \(protocolName)\naddress: \(address)\ncommand: \(command)"
    }

    /// 带标准 RAW 文件头（Frequency 在第 3 行，Preset 在第 4 行）的 Sub-GHz 文本。
    private func subFile(_ body: String) -> String {
        "Filetype: Flipper SubGhz RAW File\nVersion: 1\nFrequency: 433920000\nPreset: FuriHalSubGhzPresetOok650Async\n"
            + body
    }

    private func fact(_ report: AnalysisReport, _ title: String) -> String? {
        report.facts.first { $0.title == title }?.value
    }

    private func expectError(_ expression: @autoclosure () throws -> Any,
                             file: StaticString = #filePath, line: UInt = #line,
                             where matches: (RecordAnalysisError) -> Bool) {
        do {
            _ = try expression()
            XCTFail("预期抛出错误，但解析成功", file: file, line: line)
        } catch let error as RecordAnalysisError {
            XCTAssertTrue(matches(error), "错误类型不符：\(error)", file: file, line: line)
        } catch {
            XCTFail("抛出了非 RecordAnalysisError：\(error)", file: file, line: line)
        }
    }

    // MARK: - 类型识别与基础校验

    func testDetectKindUsesHeaderForEverySupportedFormat() throws {
        let cases: [(text: String, fileExtension: String, expected: RecordKind)] = [
            (Self.infraredRemote, "ir", .infrared),
            (Self.subGhzRaw, "sub", .subGHz),
            (Self.subGhzKey, "sub", .subGHz),
            (Self.nfcUltralight, "nfc", .nfc),
            (Self.rfidKey, "rfid", .rfid),
            (Self.iButtonKey, "ibtn", .iButton),
            // 扩展名未被识别时以文件头为准；扩展名忽略大小写与前导点。
            (Self.infraredRemote, "bak", .infrared),
            (Self.subGhzRaw, "", .subGHz),
            (Self.nfcUltralight, ".NFC", .nfc),
            (Self.rfidKey, "backup.RFID", .rfid),
        ]
        for item in cases {
            XCTAssertEqual(try RecordAnalyzer.detectKind(text: item.text, fileExtension: item.fileExtension),
                           item.expected, "扩展名：\(item.fileExtension)")
        }
    }

    func testRecognizedExtensionContradictingHeaderIsAnError() {
        for fileExtension in ["sub", "nfc", "rfid", "ibtn", "txt", "log"] {
            expectError(try RecordAnalyzer.detectKind(text: Self.infraredRemote, fileExtension: fileExtension)) {
                $0 == .extensionMismatch(fileExtension: fileExtension, headerKind: .infrared)
            }
        }
        expectError(try RecordAnalyzer.detectKind(text: Self.subGhzRaw, fileExtension: "ir")) {
            $0 == .extensionMismatch(fileExtension: "ir", headerKind: .subGHz)
        }
    }

    func testHeaderlessTextIsOnlyAcceptedAsSerialLog() throws {
        let log = "boot ok\n[I][Main] ready\n"
        XCTAssertEqual(try RecordAnalyzer.detectKind(text: log, fileExtension: "txt"), .serial)
        XCTAssertEqual(try RecordAnalyzer.detectKind(text: log, fileExtension: "LOG"), .serial)
        expectError(try RecordAnalyzer.detectKind(text: log, fileExtension: "ir")) { $0 == .missingHeader(expected: .infrared) }
        expectError(try RecordAnalyzer.detectKind(text: log, fileExtension: "sub")) { $0 == .missingHeader(expected: .subGHz) }
        expectError(try RecordAnalyzer.detectKind(text: log, fileExtension: "bin")) { $0 == .unrecognizedFormat(fileExtension: "bin") }
        expectError(try RecordAnalyzer.detectKind(text: log, fileExtension: "")) { $0 == .unrecognizedFormat(fileExtension: "") }
        // 小写的 filetype 不是 Flipper 文件头
        expectError(try RecordAnalyzer.detectKind(text: "filetype: IR signals file\nVersion: 1\n", fileExtension: "ir")) {
            $0 == .missingHeader(expected: .infrared)
        }
    }

    func testRejectsEmptyBinaryAndInvalidText() {
        for text in ["", "   \n\t\r\n", "\u{FEFF}\n"] {
            expectError(try RecordAnalyzer.detectKind(text: text, fileExtension: "txt")) { $0 == .emptyInput }
        }
        expectError(try RecordAnalyzer.detectKind(text: "ok\nbad\u{0}byte", fileExtension: "txt")) { $0 == .binaryContent(line: 2) }
        expectError(try RecordAnalyzer.analyze("ok\n\u{1}\u{2}\u{3}", kind: .serial)) { $0 == .binaryContent(line: 2) }
        expectError(try RecordAnalyzer.analyze("abc\u{FFFD}def\n", kind: .serial)) { $0 == .invalidUTF8 }
        // 串口日志允许终端颜色控制符，Flipper 文件不允许。
        XCTAssertNoThrow(try RecordAnalyzer.analyze("\u{1B}[31mred\u{1B}[0m\n", kind: .serial))
        let coloured = Self.infraredRemote.replacingOccurrences(of: "name: Mute", with: "name: \u{1B}[1mMute")
        expectError(try RecordAnalyzer.analyze(coloured, kind: .infrared)) { $0 == .binaryContent(line: 16) }
    }

    func testDecodeTextRejectsInvalidBytesAndKeepsOriginalText() throws {
        expectError(try RecordAnalyzer.decodeText(Data([0x61, 0xFF, 0x62]))) { $0 == .invalidUTF8 }
        expectError(try RecordAnalyzer.decodeText(Data([0x61, 0x00]))) { $0 == .binaryContent(line: 1) }
        expectError(try RecordAnalyzer.decodeText(Data(count: 2 * 1024 * 1024 + 1))) {
            $0 == .inputTooLarge(byteCount: 2 * 1024 * 1024 + 1, limit: 2 * 1024 * 1024)
        }
        let original = "\u{FEFF}Filetype: IR signals file\r\nVersion: 1\r\n# Cafe\u{301}\r\n"
        let decoded = try RecordAnalyzer.decodeText(Data(original.utf8))
        XCTAssertEqual(Array(decoded.utf8), Array(original.utf8))
        XCTAssertEqual(try RecordAnalyzer.detectKind(text: decoded, fileExtension: "ir"), .infrared)
    }

    func testInputLimitIsTwoMebibytesOfUTF8() throws {
        let limit = 2 * 1024 * 1024
        let atLimit = String(repeating: "a", count: limit)
        XCTAssertEqual(try RecordAnalyzer.detectKind(text: atLimit, fileExtension: "log"), .serial)
        XCTAssertEqual(fact(try RecordAnalyzer.analyze(atLimit, kind: .serial), "行数"), "1")
        expectError(try RecordAnalyzer.detectKind(text: atLimit + "a", fileExtension: "log")) {
            $0 == .inputTooLarge(byteCount: limit + 1, limit: limit)
        }
        // 按 UTF-8 字节而不是字符计数：每个汉字 3 字节。
        let chinese = String(repeating: "串", count: limit / 3 + 1)
        expectError(try RecordAnalyzer.analyze(chinese, kind: .serial)) {
            $0 == .inputTooLarge(byteCount: (limit / 3 + 1) * 3, limit: limit)
        }
    }

    func testRejectsUnsupportedHeadersAndVersions() throws {
        expectError(try RecordAnalyzer.detectKind(text: "Filetype: Flipper SubGhz Setting File\nVersion: 1\n",
                                                  fileExtension: "txt")) {
            $0 == .unsupportedFileType("Flipper SubGhz Setting File")
        }
        expectError(try RecordAnalyzer.detectKind(text: "Filetype: IR signals file\nVersion: 2\n", fileExtension: "ir")) {
            $0 == .unsupportedVersion(fileType: "IR signals file", version: "2")
        }
        expectError(try RecordAnalyzer.detectKind(text: "Filetype: IR signals file\nVersion: 99999999999999999999999\n",
                                                  fileExtension: "ir")) {
            $0 == .unsupportedVersion(fileType: "IR signals file", version: "99999999999999999999999")
        }
        expectError(try RecordAnalyzer.detectKind(text: "Filetype: IR signals file\nname: Power\n", fileExtension: "ir")) {
            $0 == .missingVersion
        }
        expectError(try RecordAnalyzer.detectKind(text: "Filetype:IR signals file\nVersion: 1\n", fileExtension: "ir")) {
            if case .malformedLine(1, _) = $0 { return true }
            return false
        }
        // NFC：版本 1 已被固件弃用；版本 2~4 可读取。
        let nfcVersion1 = Self.nfcUltralight.replacingOccurrences(of: "Version: 4", with: "Version: 1")
        expectError(try RecordAnalyzer.detectKind(text: nfcVersion1, fileExtension: "nfc")) {
            $0 == .unsupportedVersion(fileType: "Flipper NFC device", version: "1")
        }
        let nfcVersion3 = Self.nfcUltralight.replacingOccurrences(of: "Version: 4", with: "Version: 3")
        XCTAssertEqual(try RecordAnalyzer.detectKind(text: nfcVersion3, fileExtension: "nfc"), .nfc)
    }

    func testAnalyzeRejectsKindThatContradictsHeader() {
        expectError(try RecordAnalyzer.analyze(Self.infraredRemote, kind: .subGHz)) {
            $0 == .kindMismatch(requested: .subGHz, detected: .infrared)
        }
        expectError(try RecordAnalyzer.analyze(Self.rfidKey, kind: .serial)) {
            $0 == .kindMismatch(requested: .serial, detected: .rfid)
        }
        expectError(try RecordAnalyzer.analyze("plain text\n", kind: .nfc)) { $0 == .missingHeader(expected: .nfc) }
    }

    // MARK: - 红外

    func testInfraredButtonsFollowFileOrderWithSignedRawEnvelope() throws {
        let report = try RecordAnalyzer.analyze(Self.infraredRemote, kind: .infrared)
        XCTAssertEqual(report.buttons, ["Power", "Vol_up", "Mute"])
        XCTAssertEqual(fact(report, "按钮数量"), "3")
        XCTAssertEqual(fact(report, "协议解析按钮"), "2")
        XCTAssertEqual(fact(report, "原始信号按钮"), "1")
        // 逐按钮详情的序号同样对应文件顺序。
        let detailTitles = report.facts.map(\.title).filter { $0.hasPrefix("按钮 ") }
        XCTAssertEqual(detailTitles, ["按钮 1 · Power", "按钮 2 · Vol_up", "按钮 3 · Mute"])

        // 原始时长按文件顺序转为带符号序列：发射为正、间隔为负。
        let timings = "504 3432 502 483 500 484 510 502 502 482 501 485 509 1452 504 1458 509 1452 504 481 501 474 509 3420 503"
            .split(separator: " ").compactMap { Double(String($0)) }
        XCTAssertEqual(timings.count, 25)
        let signed = timings.enumerated().map { $0.offset % 2 == 0 ? $0.element : -$0.element }
        XCTAssertEqual(report.pulseDurations, signed)

        // CRLF 换行和 UTF-8 BOM 不影响结果。
        let crlf = try RecordAnalyzer.analyze(Self.infraredRemote.replacingOccurrences(of: "\n", with: "\r\n"),
                                              kind: .infrared)
        let bom = try RecordAnalyzer.analyze("\u{FEFF}" + Self.infraredRemote, kind: .infrared)
        XCTAssertEqual(crlf, report)
        XCTAssertEqual(bom, report)
    }

    func testRawInfraredCarrierIsReportedAsFileMetadata() throws {
        let report = try RecordAnalyzer.analyze(Self.infraredRemote, kind: .infrared)
        let carrier = try XCTUnwrap(report.facts.first { $0.value == "38000 Hz" })
        XCTAssertTrue(carrier.title.contains("文件"), carrier.title)
        let texts = report.facts.map(\.title) + report.facts.map(\.value) + report.notes
        XCTAssertFalse(texts.contains { $0.contains("测得") || $0.contains("实测") })

        // 超出固件发射范围的频率仍是有效文件，但会提示设备会限制频率。
        let lowCarrier = try RecordAnalyzer.analyze(irFile([rawButton("Low", frequency: "5000")]), kind: .infrared)
        XCTAssertEqual(lowCarrier.facts.first { $0.value == "5000 Hz" }?.title, carrier.title)
        XCTAssertTrue(lowCarrier.notes.contains { $0.contains("10 kHz–1 MHz") })
    }

    func testRemoteRequiresUniqueNamesButLibraryMayRepeatThem() throws {
        let buttons = [parsedButton("Power"), rawButton("Power"), parsedButton("Mute")]
        let library = try RecordAnalyzer.analyze(irFile(buttons, fileType: "IR library file"), kind: .infrared)
        XCTAssertEqual(library.buttons, ["Power", "Power", "Mute"])
        expectError(try RecordAnalyzer.analyze(irFile(buttons), kind: .infrared)) {
            $0 == .duplicateButtonName(name: "Power", line: 10, firstLine: 4)
        }
        // 名称区分大小写与空格，与固件的精确比较一致。
        let distinct = try RecordAnalyzer.analyze(irFile([parsedButton("Power"), parsedButton("power")]), kind: .infrared)
        XCTAssertEqual(distinct.buttons, ["Power", "power"])
    }

    func testInvalidRawInfraredValuesAreRejectedWithoutTrapping() {
        let cases: [(field: String, button: String)] = [
            ("duty_cycle", rawButton("A", dutyCycle: "1.5")),
            ("duty_cycle", rawButton("A", dutyCycle: "0")),
            ("duty_cycle", rawButton("A", dutyCycle: "-0.33")),
            ("duty_cycle", rawButton("A", dutyCycle: "nan")),
            ("duty_cycle", rawButton("A", dutyCycle: "inf")),
            ("duty_cycle", rawButton("A", dutyCycle: "1e999")),
            ("duty_cycle", rawButton("A", dutyCycle: "0x1p-2")),
            ("duty_cycle", rawButton("A", dutyCycle: "0.33 0.5")),
            ("frequency", rawButton("A", frequency: "0")),
            ("frequency", rawButton("A", frequency: "-38000")),
            ("frequency", rawButton("A", frequency: "38kHz")),
            ("frequency", rawButton("A", frequency: "4294967296")),
            ("frequency", rawButton("A", frequency: "99999999999999999999999")),
            ("data", rawButton("A", data: "9000 0 560")),
            ("data", rawButton("A", data: "9000 -4500 560")),
            ("data", rawButton("A", data: "9000 4500.5")),
            ("data", rawButton("A", data: "9000 99999999999999999999999")),
            ("data", rawButton("A", data: "")),
        ]
        for item in cases {
            expectError(try RecordAnalyzer.analyze(irFile([item.button]), kind: .infrared)) {
                $0.isInvalidField && $0.field == item.field
            }
        }
    }

    func testParsedInfraredPayloadMustMatchFirmwareLimits() throws {
        let cases: [(field: String, button: String)] = [
            ("address", parsedButton("A", address: "EE 87 00")),
            ("address", parsedButton("A", address: "EE 87 00 0G")),
            ("address", parsedButton("A", address: "EE8700 00")),
            ("command", parsedButton("A", command: "08 00 00 00 00")),
            // NEC 地址只有 8 位；RC5 命令只有 6 位。
            ("address", parsedButton("A", protocolName: "NEC", address: "00 01 00 00")),
            ("command", parsedButton("A", protocolName: "RC5", address: "01 00 00 00", command: "40 00 00 00")),
            // 协议名称区分大小写。
            ("protocol", parsedButton("A", protocolName: "necext")),
            ("protocol", parsedButton("A", protocolName: "Unknown")),
        ]
        for item in cases {
            expectError(try RecordAnalyzer.analyze(irFile([item.button]), kind: .infrared)) {
                $0.isInvalidField && $0.field == item.field
            }
        }
        // 位宽之内的最大值可以通过。
        let widest = [
            parsedButton("A", protocolName: "NECext", address: "FF FF 00 00", command: "FF FF 00 00"),
            parsedButton("B", protocolName: "Kaseikyo", address: "FF FF FF 03", command: "FF 03 00 00"),
        ]
        XCTAssertEqual(try RecordAnalyzer.analyze(irFile(widest), kind: .infrared).buttons, ["A", "B"])
    }

    func testInfraredStructureFollowsFirmwareReadOrder() throws {
        expectError(try RecordAnalyzer.analyze(
            irFile(["name: A\nprotocol: NEC\naddress: 04 00 00 00\ncommand: 08 00 00 00"]), kind: .infrared)) {
            $0 == .missingField(field: "type", line: 4)
        }
        expectError(try RecordAnalyzer.analyze(
            irFile(["name: A\ntype: raw\nduty_cycle: 0.33\nfrequency: 38000\ndata: 100"]), kind: .infrared)) {
            $0 == .unexpectedField(field: "duty_cycle", line: 6)
        }
        expectError(try RecordAnalyzer.analyze(irFile([parsedButton("A") + "\nrepeat: false"]), kind: .infrared)) {
            $0 == .unexpectedField(field: "repeat", line: 9)
        }
        expectError(try RecordAnalyzer.analyze("Filetype: IR signals file\nVersion: 1\nfrequency: 38000\n", kind: .infrared)) {
            $0 == .unexpectedField(field: "frequency", line: 3)
        }
        expectError(try RecordAnalyzer.analyze(
            irFile(["name: A\ntype: raw\nfrequency: 38000\nduty_cycle: 0.33"]), kind: .infrared)) {
            $0 == .missingField(field: "data", line: 4)
        }
        expectError(try RecordAnalyzer.analyze(irFile(["name: A\ntype: parsed\nprotocol: NEC", parsedButton("B")]),
                                               kind: .infrared)) {
            $0 == .missingField(field: "address", line: 4)
        }
        expectError(try RecordAnalyzer.analyze(irFile(["name: A\ntype: RAW\nfrequency: 38000"]), kind: .infrared)) {
            $0.isInvalidField && $0.field == "type"
        }
        for badName in ["", "   ", "电源"] {
            expectError(try RecordAnalyzer.analyze(irFile([rawButton(badName)]), kind: .infrared)) {
                $0.isInvalidField && $0.field == "name"
            }
        }
        expectError(try RecordAnalyzer.analyze(irFile(["name: A\ntype parsed"]), kind: .infrared)) {
            if case .malformedLine(5, _) = $0 { return true }
            return false
        }
        expectError(try RecordAnalyzer.analyze(irFile(["name : A"]), kind: .infrared)) {
            if case .malformedLine(4, _) = $0 { return true }
            return false
        }
        // 只有文件头的遥控器文件是有效的空遥控器。
        let empty = try RecordAnalyzer.analyze("Filetype: IR signals file\nVersion: 1\n", kind: .infrared)
        XCTAssertEqual(empty.buttons, [])
        XCTAssertEqual(fact(empty, "按钮数量"), "0")
    }

    func testRawInfraredTimingLimitAndBoundedPlot() throws {
        let timings = (0..<1024).map { 100 + $0 }
        let data = timings.map { String($0) }.joined(separator: " ")
        let report = try RecordAnalyzer.analyze(irFile([rawButton("Long", data: data)]), kind: .infrared)
        XCTAssertEqual(fact(report, "原始时长总数"), "1024 个")
        XCTAssertEqual(report.pulseDurations.count, 512)
        // 缩减后的每个点都是带符号的原始值，顺序不变，且保留了绝对值最大的时长。
        let signed = Set(timings.enumerated().map { Double($0.offset % 2 == 0 ? $0.element : -$0.element) })
        XCTAssertTrue(report.pulseDurations.allSatisfy { signed.contains($0) })
        let magnitudes = report.pulseDurations.map { abs($0) }
        XCTAssertEqual(magnitudes, magnitudes.sorted())
        XCTAssertEqual(report.pulseDurations.last, -1123)

        expectError(try RecordAnalyzer.analyze(irFile([rawButton("TooLong", data: data + " 5")]), kind: .infrared)) {
            $0.isInvalidField && $0.field == "data"
        }
    }

    // MARK: - Sub-GHz

    func testSubGhzMultilineRawDataIsCountedInFileOrder() throws {
        let report = try RecordAnalyzer.analyze(Self.subGhzRaw, kind: .subGHz)
        let expected: [Double] = [
            29262, 361, -68, 2635, -66, 24113, -66, 11,
            -424, 205, -412, 159, -412, 381, -240, 181,
            -1448, 361, -17056, 131, -134, 233, -1462, 131, -166, 953, -100,
        ]
        XCTAssertEqual(report.pulseDurations, expected)
        XCTAssertEqual(fact(report, "RAW_Data 行数"), "3")
        XCTAssertEqual(fact(report, "样本数"), "27（正值 14，负值 13）")
        XCTAssertEqual(fact(report, "频率（文件字段）"), "433.92 MHz（433920000 Hz）")
        XCTAssertEqual(report.buttons, [])
        let crlf = try RecordAnalyzer.analyze(Self.subGhzRaw.replacingOccurrences(of: "\n", with: "\r\n"), kind: .subGHz)
        XCTAssertEqual(crlf.pulseDurations, expected)
    }

    func testSubGhzRawRejectsZeroMalformedAndOutOfRangeSamples() throws {
        for bad in ["0", "-0", "12a", "1.5", "--5", "0x10", "2147483648", "-2147483649", "99999999999999999999999"] {
            expectError(try RecordAnalyzer.analyze(subFile("Protocol: RAW\nRAW_Data: 100 -200 \(bad) 300\n"), kind: .subGHz)) {
                $0.isInvalidField && $0.field == "RAW_Data"
            }
        }
        expectError(try RecordAnalyzer.analyze(subFile("Protocol: RAW\nRAW_Data: 100 -200\nRAW_Data:\n"), kind: .subGHz)) {
            $0.isInvalidField && $0.field == "RAW_Data"
        }
        // 32 位有符号整数的边界值可以接受；相邻同号的值不是错误。
        let edges = try RecordAnalyzer.analyze(subFile("Protocol: RAW\nRAW_Data: 2147483647 -2147483648 5 7\n"),
                                               kind: .subGHz)
        XCTAssertEqual(edges.pulseDurations, [2_147_483_647, -2_147_483_648, 5, 7])
    }

    func testSubGhzRequiresHeaderFieldsAndPositiveFrequency() {
        let head = "Filetype: Flipper SubGhz RAW File\nVersion: 1\n"
        let rest = "Preset: FuriHalSubGhzPresetOok650Async\nProtocol: RAW\nRAW_Data: 100 -100\n"
        expectError(try RecordAnalyzer.analyze(head + rest, kind: .subGHz)) {
            $0 == .missingField(field: "Frequency", line: nil)
        }
        for frequency in ["0", "-433920000", "433.92", "99999999999999999999999"] {
            expectError(try RecordAnalyzer.analyze(head + "Frequency: \(frequency)\n" + rest, kind: .subGHz)) {
                $0.isInvalidField && $0.field == "Frequency"
            }
        }
        expectError(try RecordAnalyzer.analyze(head + "Frequency: 433920000\nFrequency: 315000000\n" + rest, kind: .subGHz)) {
            $0.isInvalidField && $0.field == "Frequency"
        }
        expectError(try RecordAnalyzer.analyze(head + "Frequency: 433920000\nProtocol: RAW\nRAW_Data: 1 -1\n", kind: .subGHz)) {
            $0 == .missingField(field: "Preset", line: nil)
        }
        expectError(try RecordAnalyzer.analyze(subFile("Protocol: RAW\n"), kind: .subGHz)) {
            $0 == .missingField(field: "RAW_Data", line: 5)
        }
        expectError(try RecordAnalyzer.analyze(
            "Filetype: Flipper SubGhz RAW File\nVersion: 2\nFrequency: 433920000\n", kind: .subGHz)) {
            $0 == .unsupportedVersion(fileType: "Flipper SubGhz RAW File", version: "2")
        }
    }

    func testSubGhzSampleCountIsBounded() {
        let limit = 1_000_000
        let text = subFile("Protocol: RAW\nRAW_Data: " + String(repeating: "1 ", count: limit + 1) + "\n")
        // 确认触发的是样本数上限，而不是 2 MiB 的文件大小上限。
        XCTAssertLessThan(text.utf8.count, 2 * 1024 * 1024)
        expectError(try RecordAnalyzer.analyze(text, kind: .subGHz)) {
            if case .limitExceeded(_, limit) = $0 { return true }
            return false
        }
    }

    func testSubGhzReportsRepeatedAdjacentPulsePairsAsObservations() throws {
        let preamble = String(repeating: "350 -1050 ", count: 20)
        let tail = String(repeating: "1050 -350 ", count: 5)
        let report = try RecordAnalyzer.analyze(subFile("Protocol: RAW\nRAW_Data: \(preamble)\(tail)\n"), kind: .subGHz)
        XCTAssertEqual(fact(report, "高低电平对")?.hasPrefix("25 对"), true)
        let first = try XCTUnwrap(fact(report, "常见脉冲对 1"))
        XCTAssertTrue(first.contains("350") && first.contains("1050") && first.contains("20 次"), first)
        let second = try XCTUnwrap(fact(report, "常见脉冲对 2"))
        XCTAssertTrue(second.contains("5 次"), second)
        let run = try XCTUnwrap(fact(report, "最长连续重复"))
        XCTAssertTrue(run.contains("连续 20 次") && run.contains("第 1 个样本"), run)
        XCTAssertTrue(report.notes.contains { $0.contains("不代表协议识别") })
    }

    func testSubGhzPlotIsBoundedWhileStatisticsCoverAllSamples() throws {
        let values = (0..<2000).map { $0 % 2 == 0 ? 100 + $0 : -(100 + $0) }
        let lines = stride(from: 0, to: values.count, by: 500).map { start in
            "RAW_Data: " + values[start..<Swift.min(start + 500, values.count)].map { String($0) }.joined(separator: " ")
        }
        let report = try RecordAnalyzer.analyze(subFile("Protocol: RAW\n" + lines.joined(separator: "\n") + "\n"),
                                                kind: .subGHz)
        XCTAssertEqual(report.pulseDurations.count, 512)
        XCTAssertEqual(fact(report, "样本数"), "2000（正值 1000，负值 1000）")
        XCTAssertEqual(fact(report, "RAW_Data 行数"), "4")
        let allowed = Set(values.map { Double($0) })
        XCTAssertTrue(report.pulseDurations.allSatisfy { allowed.contains($0) })
        let magnitudes = report.pulseDurations.map { abs($0) }
        XCTAssertEqual(magnitudes, magnitudes.sorted())
        XCTAssertEqual(report.pulseDurations.last, -2099)
    }

    func testSubGhzKeyFileSummarisesFieldsWithoutPulseData() throws {
        let report = try RecordAnalyzer.analyze(Self.subGhzKey, kind: .subGHz)
        XCTAssertEqual(report.pulseDurations, [])
        XCTAssertEqual(fact(report, "协议（文件字段）"), "Princeton")
        XCTAssertEqual(fact(report, "位长（文件字段）"), "24 位")
        XCTAssertEqual(fact(report, "TE（文件字段）"), "400 µs")
        XCTAssertEqual(fact(report, "Key 数据长度"), "8 字节")

        let custom = Self.subGhzKey.replacingOccurrences(
            of: "Preset: FuriHalSubGhzPresetOok650Async",
            with: "Preset: FuriHalSubGhzPresetCustom\nCustom_preset_module: CC1101\nCustom_preset_data: 02 0D 03")
        expectError(try RecordAnalyzer.analyze(custom, kind: .subGHz)) {
            $0.isInvalidField && $0.field == "Custom_preset_data"
        }
        let badKey = Self.subGhzKey.replacingOccurrences(of: "Key: 00 00 00 00 00 95 D5 D4", with: "Key: 0x95D5D4")
        expectError(try RecordAnalyzer.analyze(badKey, kind: .subGHz)) { $0.isInvalidField && $0.field == "Key" }
    }

    // MARK: - NFC、低频 RFID、iButton

    func testNfcSummaryReportsHeaderFieldsAndDataSizes() throws {
        let ultralight = try RecordAnalyzer.analyze(Self.nfcUltralight, kind: .nfc)
        XCTAssertEqual(fact(ultralight, "设备类型"), "NTAG/Ultralight")
        XCTAssertEqual(fact(ultralight, "NTAG/Ultralight type"), "NTAG216")
        XCTAssertEqual(fact(ultralight, "UID 长度"), "7 字节")
        XCTAssertEqual(fact(ultralight, "页数据"), "4 页，共 16 字节")
        XCTAssertEqual(ultralight.pulseDurations, [])

        let classic = try RecordAnalyzer.analyze(Self.nfcClassic, kind: .nfc)
        XCTAssertEqual(fact(classic, "块数据"), "4 块，共 64 字节")
        XCTAssertEqual(fact(classic, "标记为未知的字节"), "16 字节（文件中写作 ??）")
    }

    func testNfcRequiresDeviceTypeAndWellFormedData() {
        let noUID = Self.nfcUltralight.replacingOccurrences(of: "UID: 04 85 90 54 12 98 23\n", with: "")
        expectError(try RecordAnalyzer.analyze(noUID, kind: .nfc)) { $0 == .missingField(field: "UID", line: nil) }
        let noType = Self.nfcUltralight.replacingOccurrences(of: "Device type: NTAG/Ultralight\n", with: "")
        expectError(try RecordAnalyzer.analyze(noType, kind: .nfc)) { $0 == .missingField(field: "Device type", line: nil) }
        let badUID = Self.nfcUltralight.replacingOccurrences(of: "UID: 04 85 90 54 12 98 23", with: "UID: 04 85 9")
        expectError(try RecordAnalyzer.analyze(badUID, kind: .nfc)) { $0.isInvalidField && $0.field == "UID" }
        let badPage = Self.nfcUltralight.replacingOccurrences(of: "Page 2: CA 48 0F 00", with: "Page 2: CA 48 0F ZZ")
        expectError(try RecordAnalyzer.analyze(badPage, kind: .nfc)) { $0.isInvalidField && $0.field == "Page 2" }
    }

    func testRfidAndIButtonSummaries() throws {
        let rfid = try RecordAnalyzer.analyze(Self.rfidKey, kind: .rfid)
        XCTAssertEqual(fact(rfid, "协议类型"), "EM4100")
        XCTAssertEqual(fact(rfid, "数据长度"), "5 字节")
        let badRfid = Self.rfidKey.replacingOccurrences(of: "Data: 01 23 45 67 89", with: "Data: 01 23 45 6")
        expectError(try RecordAnalyzer.analyze(badRfid, kind: .rfid)) { $0.isInvalidField && $0.field == "Data" }

        let iButton = try RecordAnalyzer.analyze(Self.iButtonKey, kind: .iButton)
        XCTAssertEqual(fact(iButton, "协议"), "DS1992")
        XCTAssertEqual(fact(iButton, "Rom Data 长度"), "8 字节")
        XCTAssertEqual(fact(iButton, "Sram Data 长度"), "128 字节")

        let legacy = try RecordAnalyzer.analyze(
            "Filetype: Flipper iButton key\nVersion: 1\nKey type: Cyfral\nData: A6 D2\n", kind: .iButton)
        XCTAssertEqual(fact(legacy, "类型"), "Cyfral")
        XCTAssertEqual(fact(legacy, "Data 长度"), "2 字节")
        expectError(try RecordAnalyzer.analyze("Filetype: Flipper iButton key\nVersion: 2\nProtocol: DS1990\n",
                                               kind: .iButton)) {
            $0 == .missingField(field: "Rom Data 或 Data", line: nil)
        }
    }

    // MARK: - 串口日志

    func testSerialLogCountsLinesAndSimpleSeverityMatches() throws {
        let log = "1234 \u{1B}[31m[E][BtSrv] radio stack failed\u{1B}[0m\r\n"
            + "1300 [W][Storage] SD card slow\r\n"
            + "boot ok\r\n"
            + "\r\n"
            + "ERROR: spi timeout\r\n"
            + "Warning: low battery\r\n"
            + "最后一行没有换行"
        XCTAssertEqual(try RecordAnalyzer.detectKind(text: log, fileExtension: "log"), .serial)
        let report = try RecordAnalyzer.analyze(log, kind: .serial)
        XCTAssertEqual(fact(report, "行数"), "7")
        XCTAssertEqual(fact(report, "非空行"), "6")
        XCTAssertEqual(fact(report, "错误行（关键词）"), "2")
        XCTAssertEqual(fact(report, "警告行（关键词）"), "2")
        XCTAssertEqual(fact(report, "文本大小"), "\(log.utf8.count) 字节")
        XCTAssertEqual(report.buttons, [])
        XCTAssertEqual(report.pulseDurations, [])
    }

    func testPassiveWiFiSurveyImportsAsItsOwnRecordKind() throws {
        let scan = """
        # Flipper Lab WiFi Survey v1
        ssid,bssid,channel,rssi,security
        Home,02:11:22:33:44:55,6,-54,WPA2
        "Office, Guest",02:11:22:33:44:66,11,-71,WPA3
        """
        for ext in ["wscan", "csv", "txt"] {
            XCTAssertEqual(try RecordAnalyzer.detectKind(text: scan, fileExtension: ext), .wifiSurvey)
        }
        let report = try RecordAnalyzer.analyze(scan, kind: .wifiSurvey)
        XCTAssertEqual(fact(report, "扫描到的接入点"), "2")
        XCTAssertEqual(fact(report, "不同网络名称"), "2")
        XCTAssertEqual(fact(report, "涉及信道"), "2")
        XCTAssertTrue(report.notes.contains { $0.contains("不能直接换算距离") })
        XCTAssertThrowsError(try RecordAnalyzer.analyze(scan, kind: .serial))
    }

    func testSavedESP32APLogIsRecognizedWithoutConvertingFile() throws {
        let log = """
        > #scanap
        Starting AP scan. Stop with stopscan
        RSSI: -57 Ch: 3 BSSID: 50:ff:20:84:d6:0f ESSID: Home
        Beacon: 11 18 1 17464
        """
        XCTAssertEqual(try RecordAnalyzer.detectKind(text: log, fileExtension: "log"), .wifiSurvey)
        let report = try RecordAnalyzer.analyze(log, kind: .wifiSurvey)
        XCTAssertEqual(fact(report, "记录来源"), "ESP32 扫描日志")
        XCTAssertEqual(fact(report, "扫描到的接入点"), "1")
        XCTAssertTrue(report.notes.contains { $0.contains("未记录") })
        XCTAssertThrowsError(try RecordAnalyzer.analyze(log, kind: .serial))
        let failedScan = "Starting AP scan. Stop with stopscan\nFailed to deinit Wi-Fi driver\n"
        XCTAssertEqual(try RecordAnalyzer.detectKind(text: failedScan, fileExtension: "log"), .serial)
    }

    // MARK: - 错误说明

    func testEveryErrorHasChineseDescription() {
        let errors: [RecordAnalysisError] = [
            .emptyInput,
            .inputTooLarge(byteCount: 3_000_000, limit: 2_097_152),
            .invalidUTF8,
            .binaryContent(line: 3),
            .unrecognizedFormat(fileExtension: ""),
            .unrecognizedFormat(fileExtension: "bin"),
            .missingHeader(expected: .infrared),
            .unsupportedFileType("Flipper SubGhz Setting File"),
            .missingVersion,
            .unsupportedVersion(fileType: "IR signals file", version: "9"),
            .extensionMismatch(fileExtension: "sub", headerKind: .infrared),
            .kindMismatch(requested: .nfc, detected: .rfid),
            .malformedLine(line: 1, reason: "缺少冒号"),
            .missingField(field: "UID", line: nil),
            .missingField(field: "type", line: 4),
            .invalidField(field: "data", line: 9, reason: "不是正整数"),
            .unexpectedField(field: "repeat", line: 12),
            .duplicateButtonName(name: "Power", line: 10, firstLine: 4),
            .limitExceeded(item: "RAW_Data 样本总数", limit: 1_000_000),
        ]
        for error in errors {
            let description = error.errorDescription ?? ""
            XCTAssertTrue(description.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }, "\(error)")
            XCTAssertFalse(description.contains("Optional("), description)
        }
    }
}

private extension RecordAnalysisError {
    /// 字段相关错误中的字段名。
    var field: String? {
        switch self {
        case let .missingField(field, _), let .invalidField(field, _, _), let .unexpectedField(field, _):
            return field
        default:
            return nil
        }
    }

    var isInvalidField: Bool {
        if case .invalidField = self { return true }
        return false
    }
}
