import XCTest
@testable import FlipperCore

final class RPCWireTests: XCTestCase {
    func testKnownDeviceInfoRequestVector() {
        XCTAssertEqual(RPCEnvelope.encode(id: 1, tag: 32), Data([5, 8, 1, 0x82, 2, 0]))
    }
    func testEveryPossibleChunkBoundaryAndMultipleFrames() throws {
        let bytes = RPCEnvelope.encode(id: 17, tag: 33, payload: PBMessage.string(1, "name") + PBMessage.string(2, "海豚"))
        for split in 0...bytes.count {
            var decoder = RPCFrameDecoder()
            let results = try decoder.append(bytes.prefix(split)) + decoder.append(bytes.dropFirst(split))
            XCTAssertEqual(results.count, 1)
            XCTAssertEqual(results.first?.commandID, 17)
            let payload = try PBMessage(XCTUnwrap(results.first?.payload))
            XCTAssertEqual(try payload.string(2), "海豚")
        }
        var decoder = RPCFrameDecoder()
        XCTAssertEqual(try decoder.append(bytes + bytes).count, 2)
    }
    func testRejectsOversizedTruncatedAndOverflowFrames() throws {
        var decoder = RPCFrameDecoder()
        XCTAssertThrowsError(try decoder.append(PBMessage.varint(65_537)))
        XCTAssertEqual(try decoder.append(Data([5, 8])).count, 0)
        decoder.reset()
        XCTAssertEqual(try decoder.append(RPCEnvelope.encode(id: 1, tag: 4)).count, 1)
        XCTAssertThrowsError(try PBMessage(Data([8] + Array(repeating: 0xff, count: 10))))
        XCTAssertThrowsError(try PBMessage(Data([10, 5, 1])))
        XCTAssertThrowsError(try PBMessage(Data([0])))
        XCTAssertThrowsError(try PBMessage(Data([11])))
    }
    func testUnknownFixedFieldsAndRepeatedEntries() throws {
        let bytes = Data([0x0d, 1, 2, 3, 4]) + PBMessage.bytes(2, Data([1])) + PBMessage.bytes(2, Data([2]))
        let message = try PBMessage(bytes)
        XCTAssertEqual(message.blobs(2), [Data([1]), Data([2])])
    }
    func testDirectoryNamesCannotChangePath() throws {
        let file = try DeviceFile(parent: "/ext", message: PBMessage(PBMessage.string(2, "遥控.ir")))
        XCTAssertEqual(file.path, "/ext/遥控.ir")
        for name in ["..", "a/b", "a\\b", "x\0y", ""] {
            XCTAssertThrowsError(try DeviceFile(parent: "/ext", message: PBMessage(PBMessage.string(2, name))))
        }
    }
    func testMalformedInputsAreBounded() {
        for count in 1...128 {
            var decoder = RPCFrameDecoder()
            _ = try? decoder.append(Data(repeating: 0xff, count: count))
        }
    }
}
