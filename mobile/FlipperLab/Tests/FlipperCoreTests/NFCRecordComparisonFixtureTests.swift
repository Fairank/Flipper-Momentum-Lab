import Foundation
import XCTest
import FlipperCore

/// Uses seven tracked public dumps and two explicitly synthetic protocol fixtures.
/// No live card read or ignored external application tree is required.
final class NFCRecordComparisonFixtureTests: XCTestCase {
    private struct Sample {
        let path: String
        let storageKey: String?
        let address: NFCComparisonAddress?
    }

    private static let unitSamples = "applications/debug/unit_tests/resources/unit_tests/nfc/"
    private static let syntheticSamples = "mobile/FlipperLab/Tests/Fixtures/NFCComparison/"
    private static let samples: [Sample] = [
        Sample(path: "applications/main/nfc/resources/nfc/RickRoll.nfc", storageKey: "Page 10", address: .page(10)),
        Sample(path: unitSamples + "Ntag213_locked.nfc", storageKey: "Page 10", address: .page(10)),
        Sample(path: unitSamples + "Ntag215.nfc", storageKey: "Page 10", address: .page(10)),
        Sample(path: unitSamples + "Ntag216.nfc", storageKey: "Page 10", address: .page(10)),
        Sample(path: unitSamples + "Ultralight_11.nfc", storageKey: "Page 10", address: .page(10)),
        Sample(path: unitSamples + "Ultralight_21.nfc", storageKey: "Page 10", address: .page(10)),
        Sample(path: unitSamples + "Ultralight_C.nfc", storageKey: "Page 10", address: .page(10)),
        Sample(path: syntheticSamples + "st25tb-512at.nfc",
               storageKey: "Block 9", address: .block(9)),
        Sample(path: syntheticSamples + "iso14443-4a.nfc", storageKey: nil, address: nil),
    ]

    func testCompleteFixturesIgnoreBodyOrderAndHexPresentation() throws {
        for sample in Self.samples {
            let original = try source(sample)
            let lines = original.components(separatedBy: "\n")
            let header = Array(lines.prefix(2))
            let body = lines.dropFirst(2).reversed().map { line -> String in
                let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard pieces.count == 2 else { return line }
                let tokens = pieces[1].split(whereSeparator: \.isWhitespace)
                guard !tokens.isEmpty, tokens.allSatisfy({ $0.count == 2 && UInt8($0, radix: 16) != nil }) else {
                    return line
                }
                return String(pieces[0]) + ": " + tokens.map { $0.lowercased() }.joined(separator: "\t")
            }
            let reordered = (header + body).joined(separator: "\n")
            let report = try NFCRecordComparison.compare(original, reordered)
            XCTAssertEqual(report.totalDifferenceCount, 0, sample.path)
            XCTAssertTrue(report.differences.isEmpty, sample.path)
            XCTAssertFalse(report.limited, sample.path)
            XCTAssertEqual(report.leftUnknownByteCount, 0, sample.path)
            XCTAssertEqual(report.rightUnknownByteCount, 0, sample.path)
        }
    }

    func testOneStorageByteChangeHasTheExactAddressAndOffset() throws {
        for sample in Self.samples where sample.storageKey != nil {
            let original = try source(sample)
            let key = try XCTUnwrap(sample.storageKey)
            let changed = try changingByte(in: original, key: key, offset: 2)
            let report = try NFCRecordComparison.compare(original, changed.text)
            XCTAssertEqual(report.totalDifferenceCount, 1, sample.path)
            let difference = try XCTUnwrap(report.differences.first)
            XCTAssertEqual(report.differences.count, 1, sample.path)
            XCTAssertEqual(difference.address, try XCTUnwrap(sample.address), sample.path)
            XCTAssertEqual(difference.changedByteOffsets, [2], sample.path)
            XCTAssertEqual(difference.left, changed.before, sample.path)
            XCTAssertEqual(difference.right, changed.after, sample.path)
            XCTAssertFalse(report.limited, sample.path)
        }
    }

    func testRemovingTheLastSavedStorageRowIsRejectedAsTruncated() throws {
        for sample in Self.samples where sample.storageKey != nil {
            let original = try source(sample)
            var lines = original.components(separatedBy: "\n")
            let row = try XCTUnwrap(lines.lastIndex(where: { $0.hasPrefix("Page ") || $0.hasPrefix("Block ") }))
            let key = String(try XCTUnwrap(lines[row].split(separator: ":", maxSplits: 1).first))
            lines.remove(at: row)
            let truncated = lines.joined(separator: "\n")
            XCTAssertThrowsError(try NFCRecordComparison.compare(original, truncated), sample.path) { error in
                XCTAssertNotNil(error as? RecordAnalysisError, sample.path)
                XCTAssertTrue(error.localizedDescription.contains(key), "\(sample.path): \(error)")
            }
        }
    }

    func testSyntheticISO4AHeaderWithoutAnATSFieldComparesByFieldName() throws {
        let sample = try XCTUnwrap(Self.samples.last)
        let original = try source(sample)
        XCTAssertFalse(original.components(separatedBy: "\n").contains { $0.hasPrefix("ATS:") })
        let changed = try changingByte(in: original, key: "T0", offset: 0)
        let report = try NFCRecordComparison.compare(original, changed.text)
        XCTAssertEqual(report.totalDifferenceCount, 1)
        let difference = try XCTUnwrap(report.differences.first)
        XCTAssertEqual(difference.address, .field("T0"))
        XCTAssertTrue(difference.changedByteOffsets.isEmpty)
        XCTAssertEqual(difference.left, "78")
        XCTAssertEqual(difference.right, "79")
    }

    func testPublicDumpReportCapDoesNotHideAnInvalidLateStorageRow() throws {
        let sample = try XCTUnwrap(Self.samples.first)
        let original = try source(sample)
        let keys = original.components(separatedBy: "\n").filter { $0.hasPrefix("Page ") }
            .map { String($0.split(separator: ":", maxSplits: 1)[0]) }
        XCTAssertEqual(keys.count, 231, "This public file should exercise more than the 200-result display cap")
        var changed = original
        for key in keys.prefix(201) {
            changed = try changingByte(in: changed, key: key, offset: 0).text
        }
        let report = try NFCRecordComparison.compare(original, changed)
        XCTAssertEqual(report.totalDifferenceCount, 201)
        XCTAssertEqual(report.differences.count, 200)
        XCTAssertTrue(report.limited)

        let lateKey = try XCTUnwrap(keys.last)
        var lines = changed.components(separatedBy: "\n")
        let row = try XCTUnwrap(lines.firstIndex(where: { $0.hasPrefix(lateKey + ":") }))
        lines[row] = lateKey + ": 00 00 00 ZZ"
        XCTAssertThrowsError(try NFCRecordComparison.compare(original, lines.joined(separator: "\n"))) { error in
            XCTAssertNotNil(error as? RecordAnalysisError)
            XCTAssertTrue(error.localizedDescription.contains(lateKey), "\(error)")
        }
    }

    func testFixtureMetadataRejectsMalformedBytesWithoutRequiringOptionalATSFields() throws {
        let iso4a = try source(try XCTUnwrap(Self.samples.last))
        let ntag = try source(Self.samples[1])
        let signatureLine = try XCTUnwrap(ntag.components(separatedBy: "\n").first { $0.hasPrefix("Signature:") })
        let signature = signatureLine.dropFirst("Signature:".count).split(whereSeparator: \.isWhitespace)
        XCTAssertEqual(signature.count, 32)
        let cases: [(source: String, key: String, value: String)] = [
            (iso4a, "ATQA", "GG FF"),
            (iso4a, "SAK", "20 00"),
            (iso4a, "T0", "ZZ"),
            (iso4a, "T0", "??"),
            (ntag, "Signature", signature.dropLast().joined(separator: " ")),
        ]
        for fixture in cases {
            var lines = fixture.source.components(separatedBy: "\n")
            let row = try XCTUnwrap(lines.firstIndex { $0.hasPrefix(fixture.key + ":") })
            lines[row] = fixture.key + ": " + fixture.value
            XCTAssertThrowsError(try NFCRecordComparison.compare(fixture.source, lines.joined(separator: "\n")), fixture.key) { error in
                guard case let RecordAnalysisError.invalidField(field, _, _) = error else {
                    return XCTFail("Expected invalid metadata field \(fixture.key), received \(error)")
                }
                XCTAssertEqual(field, fixture.key)
            }
        }

        // The synthetic ISO4A fixture has no ATS line. Firmware also omits
        // optional ATS component fields when no component is saved.
        let optionalKeys = ["T0", "TA(1)", "TB(1)", "TC(1)", "T1...Tk", "ATS"]
        let withoutOptionalATS = iso4a.components(separatedBy: "\n").filter { line in
            !optionalKeys.contains { line.hasPrefix($0 + ":") }
        }.joined(separator: "\n")
        let report = try NFCRecordComparison.compare(withoutOptionalATS, withoutOptionalATS)
        XCTAssertEqual(report.totalDifferenceCount, 0)
        XCTAssertTrue(report.differences.isEmpty)
    }

    private func source(_ sample: Sample) throws -> String {
        var repository = URL(fileURLWithPath: #filePath)
        // File -> FlipperCoreTests -> Tests -> FlipperLab -> mobile -> repository.
        for _ in 0..<5 { repository.deleteLastPathComponent() }
        let url = repository.appendingPathComponent(sample.path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func changingByte(in text: String, key: String, offset: Int) throws -> (text: String, before: String, after: String) {
        var lines = text.components(separatedBy: "\n")
        let row = try XCTUnwrap(lines.firstIndex(where: { $0.hasPrefix(key + ":") }), "Missing fixture field \(key)")
        let value = lines[row].dropFirst(key.count + 1)
        let tokens = value.split(whereSeparator: \.isWhitespace)
        var bytes = try tokens.map { try XCTUnwrap(UInt8($0, radix: 16), "Fixture contains a non-byte token") }
        XCTAssertGreaterThan(bytes.count, offset)
        guard bytes.indices.contains(offset) else { throw NSError(domain: "NFCFixtureTests", code: 1) }
        let before = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        bytes[offset] ^= 1
        let after = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        lines[row] = key + ": " + after
        return (lines.joined(separator: "\n"), before, after)
    }
}
