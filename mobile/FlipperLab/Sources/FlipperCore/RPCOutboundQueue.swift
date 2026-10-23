import Foundation

/// Multiplex at protobuf frame boundaries, never inside a frame or BLE write.
/// Companion replies can pass a large file transfer without starving its frames.
public struct RPCOutboundQueue: Sendable {
    public enum Lane: Sendable, Equatable { case command, companion }
    public struct Chunk: Sendable {
        public let data: Data
        public let lane: Lane
    }
    private struct Frames: Sendable {
        var values: [Data?] = []
        var head = 0
        var bytes = 0
        mutating func append(_ frames: [Data]) {
            values.append(contentsOf: frames.map(Optional.some))
            bytes += frames.reduce(0) { $0 + $1.count }
        }
        mutating func pop() -> Data? {
            guard head < values.count, let value = values[head] else { return nil }
            values[head] = nil
            head += 1
            bytes -= value.count
            if head == values.count { values.removeAll(keepingCapacity: false); head = 0 }
            else if head >= 512 { values.removeFirst(head); head = 0 }
            return value
        }
        mutating func discard(tags: Set<Int>) {
            values = values[head...].compactMap { value -> Data? in
                guard let value else { return nil }
                var decoder = RPCFrameDecoder()
                guard let frame = try? decoder.append(value).first else { return nil }
                return tags.contains(frame.tag) ? nil : value
            }.map(Optional.some)
            head = 0
            bytes = values.reduce(0) { $0 + ($1?.count ?? 0) }
        }
    }
    private var commands = Frames()
    private var companions = Frames()
    private var current: Data?
    private var currentLane: Lane = .command
    private var offset = 0
    private var consecutiveCompanions = 0
    // A 2 MiB storage transfer repeats a path of up to 240 bytes per 512-byte
    // frame. Account for that framing overhead as well as the companion lane.
    public static let totalLimit = 4 * 1024 * 1024
    public static let companionLimit = 16 * 1024

    public init() {}
    public var commandBytes: Int {
        commands.bytes + (currentLane == .command ? (current?.count ?? 0) - offset : 0)
    }
    public var companionBytes: Int {
        companions.bytes + (currentLane == .companion ? (current?.count ?? 0) - offset : 0)
    }
    public var isEmpty: Bool { commandBytes + companionBytes == 0 }

    public mutating func reset() { self = Self() }

    /// A partially transmitted frame must finish to preserve RPC framing. Drop
    /// all not-yet-started replies for a capability the user has just disabled.
    public mutating func discardCompanion(tags: Set<Int>) { companions.discard(tags: tags) }

    public mutating func append(_ bytes: Data, lane: Lane) throws {
        guard !bytes.isEmpty else { throw RPCError.malformed }
        guard bytes.count <= Self.totalLimit - commandBytes - companionBytes else { throw RPCError.tooLarge }
        if lane == .companion {
            guard bytes.count <= Self.companionLimit - companionBytes else { throw RPCError.busy }
        }
        // Validate the entire batch first: a rejected suffix must not enqueue its prefix.
        let input = Array(bytes)
        var start = 0
        var frames: [Data] = []
        while start < input.count {
            let frameStart = start
            let length = try PBMessage.readVarint(input, offset: &start)
            guard length > 0, length <= 65_536, start - frameStart <= 5,
                  length <= UInt64(input.count - start), frames.count < 16_384 else {
                throw RPCError.malformed
            }
            start += Int(length)
            frames.append(Data(input[frameStart..<start]))
        }
        switch lane {
        case .command: commands.append(frames)
        case .companion: companions.append(frames)
        }
    }

    public mutating func next(maximumBytes: Int) -> Chunk? {
        guard maximumBytes > 0 else { return nil }
        if current == nil {
            if companions.bytes > 0 && (commands.bytes == 0 || consecutiveCompanions < 4) {
                current = companions.pop(); currentLane = .companion
                consecutiveCompanions = min(consecutiveCompanions + 1, 4)
            } else {
                current = commands.pop(); currentLane = .command
                consecutiveCompanions = 0
            }
            offset = 0
        }
        guard let frame = current else { return nil }
        let end = offset + min(maximumBytes, frame.count - offset)
        let result = Chunk(data: Data(frame[offset..<end]), lane: currentLane)
        offset = end
        if end == frame.count { current = nil; offset = 0 }
        return result
    }
}
