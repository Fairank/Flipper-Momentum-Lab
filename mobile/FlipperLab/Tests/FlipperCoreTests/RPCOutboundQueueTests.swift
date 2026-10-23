import XCTest
@testable import FlipperCore

final class RPCOutboundQueueTests: XCTestCase {
    func testDisablingSharingDropsOnlyUnstartedRepliesOfThatCapability() throws {
        var queue = RPCOutboundQueue()
        let fix = RPCEnvelope.encode(id: 0, tag: 87, payload: Data(repeating: 1, count: 200))
        let network = RPCEnvelope.encode(id: 0, tag: 80)
        try queue.append(fix + fix + network, lane: .companion)
        var wire = queue.next(maximumBytes: 1)!.data
        queue.discardCompanion(tags: [87])
        while let part = queue.next(maximumBytes: 486) { wire += part.data }
        var decoder = RPCFrameDecoder()
        XCTAssertEqual(try decoder.append(wire).map(\.tag), [87, 80])
        XCTAssertTrue(queue.isEmpty)
        queue.discardCompanion(tags: [87, 80])
        XCTAssertTrue(queue.isEmpty)
    }

    func testMaximumFileAndPathFitWhileReservingRoomForCompanionReplies() throws {
        var queue = RPCOutboundQueue()
        var frames = Data()
        let path = "/ext/apps_data/a/" + String(repeating: "x", count: 223)
        XCTAssertEqual(path.utf8.count, 240)
        for offset in stride(from: 0, to: CompanionStorage.maximumBytes, by: 512) {
            frames += RPCEnvelope.encode(id: 1, tag: 11,
                payload: PBMessage.string(1, path) + PBMessage.bytes(2, PBMessage.bytes(4, Data(count: 512))),
                hasNext: offset + 512 < CompanionStorage.maximumBytes)
        }
        try queue.append(frames, lane: .command)
        try queue.append(RPCEnvelope.encode(id: 0, tag: 80, payload: Data(count: 16_000)), lane: .companion)
        XCTAssertLessThan(queue.commandBytes + queue.companionBytes, RPCOutboundQueue.totalLimit)
    }

    func testRepliesCannotSplitAnAlreadyStartedCommandFrame() throws {
        var queue = RPCOutboundQueue()
        let first = RPCEnvelope.encode(id: 1, tag: 11, payload: Data(repeating: 0x5a, count: 600))
        let second = RPCEnvelope.encode(id: 1, tag: 11, payload: Data(repeating: 0x33, count: 300))
        try queue.append(first + second, lane: .command)
        var wire = queue.next(maximumBytes: 1)!.data // fragment even the length prefix
        try queue.append(RPCEnvelope.encode(id: 0, tag: 87), lane: .companion)
        while let part = queue.next(maximumBytes: 47) { wire += part.data }
        var decoder = RPCFrameDecoder()
        let frames = try decoder.append(wire)
        XCTAssertEqual(frames.map(\.tag), [11, 87, 11])
        XCTAssertEqual(frames.map(\.payload.count), [600, 0, 300])
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.companionBytes, 0)
        XCTAssertEqual(queue.commandBytes, 0)
    }

    func testCompanionTrafficIsBoundedAndCannotStarveCommand() throws {
        var queue = RPCOutboundQueue()
        try queue.append(RPCEnvelope.encode(id: 7, tag: 9), lane: .command)
        for _ in 0..<10 { try queue.append(RPCEnvelope.encode(id: 0, tag: 80), lane: .companion) }
        var wire = Data()
        while let part = queue.next(maximumBytes: 486) { wire += part.data }
        var decoder = RPCFrameDecoder()
        let frames = try decoder.append(wire)
        XCTAssertEqual(frames[4].commandID, 7)
        XCTAssertEqual(frames.count, 11)
        XCTAssertTrue(queue.isEmpty)
        try queue.append(RPCEnvelope.encode(id: 0, tag: 80, payload: Data(repeating: 1, count: 16_000)), lane: .companion)
        let before = queue.companionBytes
        XCTAssertThrowsError(try queue.append(RPCEnvelope.encode(id: 0, tag: 80, payload: Data(repeating: 2, count: 512)), lane: .companion))
        XCTAssertEqual(queue.companionBytes, before)
        queue.reset()
        XCTAssertTrue(queue.isEmpty)
    }

    func testInvalidBatchDoesNotPartiallyEnqueueAndResetDropsOldSession() throws {
        var queue = RPCOutboundQueue()
        let valid = RPCEnvelope.encode(id: 12, tag: 7)
        XCTAssertThrowsError(try queue.append(valid + Data([0x81]), lane: .command))
        XCTAssertTrue(queue.isEmpty)
        try queue.append(valid, lane: .command)
        XCTAssertNil(queue.next(maximumBytes: 0))
        XCTAssertEqual(queue.commandBytes, valid.count)
        _ = queue.next(maximumBytes: 1)
        queue.reset()
        XCTAssertNil(queue.next(maximumBytes: 486))
        try queue.append(RPCEnvelope.encode(id: 13, tag: 9), lane: .command)
        var decoder = RPCFrameDecoder()
        XCTAssertEqual(try decoder.append(queue.next(maximumBytes: 486)!.data).first?.commandID, 13)
    }
}
