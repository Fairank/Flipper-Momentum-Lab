import XCTest
@testable import FlipperCore

final class RemoteScreenTests: XCTestCase {
    func testPinnedGuiFrameDecodesTileLayoutAndCustomColors() throws {
        var bytes = Data(repeating: 0, count: RemoteScreenFrame.byteCount)
        bytes[0] = 0b0000_0001       // (0, 0)
        bytes[7] = 0b0000_0100       // (7, 2)
        bytes[128] = 0b0000_0001     // (0, 8)
        let payload = PBMessage.bytes(1, bytes)
            + PBMessage.uint(2, 0)
            + PBMessage.uint(3, 1 | (255 << 8) | (130 << 16))
            + PBMessage.uint(4, 1)
        let frame = try RemoteScreenFrame(payload: payload)
        let pixels = [UInt8](frame.rgbaPixels())
        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let start = (y * RemoteScreenFrame.width + x) * 4
            return Array(pixels[start..<(start + 4)])
        }
        XCTAssertEqual(pixel(0, 0), [0, 0, 0, 255])
        XCTAssertEqual(pixel(7, 2), [0, 0, 0, 255])
        XCTAssertEqual(pixel(0, 8), [0, 0, 0, 255])
        XCTAssertEqual(pixel(1, 0), [255, 130, 0, 255])
        XCTAssertEqual(pixel(0, 1), [255, 130, 0, 255])
    }

    func testRejectsFramesWithWrongLengthOrOrientation() {
        let tooShort = PBMessage.bytes(1, Data(repeating: 0, count: 1023))
        XCTAssertThrowsError(try RemoteScreenFrame(payload: tooShort))
        let invalidOrientation = PBMessage.bytes(1, Data(repeating: 0, count: 1024))
            + PBMessage.uint(2, 4)
        XCTAssertThrowsError(try RemoteScreenFrame(payload: invalidOrientation))
    }

    func testScreenFrameCanArriveBetweenRepliesWithoutBreakingFraming() throws {
        let screen = RPCEnvelope.encode(id: 0, tag: 22,
            payload: PBMessage.bytes(1, Data(repeating: 0, count: 1024)))
        let reply = RPCEnvelope.encode(id: 9, tag: 4)
        var decoder = RPCFrameDecoder()
        var values: [RPCEnvelope] = []
        let stream = screen + reply
        for byte in stream { values += try decoder.append(Data([byte])) }
        XCTAssertEqual(values.map(\.tag), [22, 4])
        XCTAssertEqual(values.map(\.commandID), [0, 9])
    }

    func testPinnedGuiInputLongEventVector() throws {
        let payload = PBMessage.uint(1, UInt64(RemoteKey.back.rawValue)) + PBMessage.uint(2, 3)
        let bytes = RPCEnvelope.encode(id: 7, tag: 23, payload: payload)
        XCTAssertEqual(bytes, Data([9, 8, 7, 0xba, 1, 4, 8, 5, 16, 3]))
        var decoder = RPCFrameDecoder()
        let request = try XCTUnwrap(decoder.append(bytes).first)
        XCTAssertEqual(request.tag, 23)
        let input = try PBMessage(request.payload)
        XCTAssertEqual(input.uint(1), 5)
        XCTAssertEqual(input.uint(2), 3)
    }
}
