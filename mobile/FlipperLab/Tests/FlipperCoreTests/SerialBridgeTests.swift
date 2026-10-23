import XCTest
@testable import FlipperCore

final class SerialBridgeTests: XCTestCase {
    private func reply(_ operation: SerialBridge.Operation = .read, sequence: UInt16 = 0x1234,
                       status: UInt8 = 0, dropped: UInt32 = 0, payload: Data = Data()) -> Data {
        Data([0x46, 0x4c, 0x42, 1, UInt8(sequence & 255), UInt8(sequence >> 8), operation.rawValue, status,
              UInt8(dropped & 255), UInt8((dropped >> 8) & 255), UInt8((dropped >> 16) & 255), UInt8(dropped >> 24)]) + payload
    }

    func testWireBytesAgreeWithFirmware() throws {
        XCTAssertEqual(try SerialBridge.request(.hello, sequence: 0x1234), Data([70,76,66,1,52,18,0]))
        XCTAssertEqual(try SerialBridge.request(.open, sequence: 1,
            payload: SerialBridge.configuration(port: 1, baud: 115200)),
            Data([70,76,66,1,1,0,1,1,0,194,1,0]))
        let parsed = try SerialBridge.Reply(reply(dropped: 0x87654321, payload: Data([0, 0xff, 10])))
        XCTAssertEqual(parsed.sequence, 0x1234)
        XCTAssertEqual(parsed.operation, .read)
        XCTAssertEqual(parsed.droppedBytes, 0x87654321)
        XCTAssertEqual(parsed.payload, Data([0, 0xff, 10]))
    }

    func testInvalidRequestsCannotReachDevice() throws {
        for operation: SerialBridge.Operation in [.hello, .read, .close] {
            XCTAssertThrowsError(try SerialBridge.request(operation, sequence: 0, payload: Data([0])))
        }
        XCTAssertThrowsError(try SerialBridge.request(.write, sequence: 0))
        XCTAssertThrowsError(try SerialBridge.request(.write, sequence: 0, payload: Data(repeating: 0, count: 513)))
        XCTAssertNoThrow(try SerialBridge.request(.write, sequence: .max, payload: Data(repeating: 0, count: 512)))
        XCTAssertThrowsError(try SerialBridge.configuration(port: 2, baud: 115200))
        XCTAssertThrowsError(try SerialBridge.configuration(port: 0, baud: 0))
        for rate in SerialBridge.baudRates {
            for port: UInt8 in [0, 1] {
                XCTAssertNoThrow(try SerialBridge.request(.open, sequence: 0, payload: SerialBridge.configuration(port: port, baud: rate)))
            }
        }
    }

    func testTruncatedInvalidAndErrorReplies() throws {
        let valid = reply()
        for length in 0..<12 { XCTAssertThrowsError(try SerialBridge.Reply(valid.prefix(length))) }
        for index in 0..<4 {
            var malformed = valid; malformed[index] ^= 255
            XCTAssertThrowsError(try SerialBridge.Reply(malformed))
        }
        var badOperation = valid; badOperation[6] = 255
        XCTAssertThrowsError(try SerialBridge.Reply(badOperation))
        for status: UInt8 in [1, 2, 3, 255] {
            XCTAssertThrowsError(try SerialBridge.Reply(reply(status: status)))
        }
        XCTAssertThrowsError(try SerialBridge.Reply(reply(payload: Data(repeating: 0, count: 513))))
        XCTAssertNoThrow(try SerialBridge.Reply(reply(payload: Data(repeating: 0, count: 512))))
    }

    func testBoundedCaptureRetainsRawBytesAndReportsEveryLoss() throws {
        var capture = SerialCapture()
        for i in 0..<140 {
            let packet = reply(dropped: UInt32(i), payload: Data(repeating: UInt8(i), count: 512))
            capture.append(try SerialBridge.Reply(packet))
        }
        XCTAssertEqual(capture.receivedBytes, 140 * 512)
        XCTAssertEqual(capture.data.count, SerialCapture.capacity)
        XCTAssertEqual(capture.trimmedBytes, 12 * 512)
        XCTAssertEqual(capture.deviceDroppedBytes, 139)
        XCTAssertEqual(capture.data.first, 12)
        XCTAssertEqual(capture.data.last, 139)
        capture.append(try SerialBridge.Reply(reply(dropped: .max)))
        XCTAssertEqual(capture.deviceDroppedBytes, .max)
        XCTAssertEqual(capture.receivedBytes, 140 * 512)
    }

    func testDisplayDoesNotChangeExportedBinary() throws {
        var capture = SerialCapture()
        let bytes = Data([0, 0xff, 0x1b, 10]) + Data("中文\r\t".utf8)
        capture.append(try SerialBridge.Reply(reply(payload: bytes)))
        XCTAssertEqual(capture.data, bytes)
        XCTAssertEqual(capture.displayText, "·�·\n中文\r\t")
    }
}
