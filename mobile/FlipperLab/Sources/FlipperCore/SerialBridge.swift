import Foundation

/// Versioned application-data transport for Lab Bridge. It carries serial bytes, not Wi-Fi frames.
public enum SerialBridge {
    public static let maxChunk = 512
    public static let baudRates: [UInt32] = [9600, 19200, 38400, 57600, 115200, 230400]
    public enum Operation: UInt8, Sendable { case hello = 0, open = 1, read = 2, write = 3, close = 4 }

    public static func request(_ operation: Operation, sequence: UInt16, payload: Data = Data()) throws -> Data {
        guard payload.count <= maxChunk else { throw RPCError.tooLarge }
        switch operation {
        case .hello, .read, .close:
            guard payload.isEmpty else { throw RPCError.malformed }
        case .open:
            guard payload.count == 5, payload.first! <= 1 else { throw RPCError.malformed }
            guard baudRates.contains(read32(Array(payload), 1)) else { throw RPCError.malformed }
        case .write:
            guard !payload.isEmpty else { throw RPCError.malformed }
        }
        return Data([0x46, 0x4c, 0x42, 1, UInt8(sequence & 255), UInt8(sequence >> 8), operation.rawValue]) + payload
    }

    public static func configuration(port: UInt8, baud: UInt32) throws -> Data {
        guard port <= 1, baudRates.contains(baud) else { throw RPCError.malformed }
        return Data([port, UInt8(baud & 255), UInt8((baud >> 8) & 255), UInt8((baud >> 16) & 255), UInt8(baud >> 24)])
    }

    public struct Reply: Sendable {
        public let sequence: UInt16
        public let operation: Operation
        public let droppedBytes: UInt32
        public let payload: Data
        public init(_ data: Data) throws {
            let bytes = Array(data)
            guard bytes.count >= 12, bytes.count <= maxChunk + 12,
                  Array(bytes.prefix(4)) == [0x46, 0x4c, 0x42, 1],
                  let operation = Operation(rawValue: bytes[6]) else { throw RPCError.malformed }
            sequence = UInt16(bytes[4]) | UInt16(bytes[5]) << 8
            self.operation = operation
            switch bytes[7] {
            case 0: break
            case 1: throw RPCError.message("串口参数无效，请检查端口和波特率。")
            case 2: throw RPCError.message("串口被其他应用占用，请先关闭它。")
            case 3: throw RPCError.message("串口尚未打开。")
            default: throw RPCError.message("扩展板通信返回了未知错误。")
            }
            droppedBytes = SerialBridge.read32(bytes, 8)
            payload = Data(bytes.dropFirst(12))
        }
    }

    private static func read32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
    }
}

/// A bounded raw capture. Local truncation and the bridge's overflow counter are separate.
public struct SerialCapture: Sendable {
    public private(set) var data = Data()
    public private(set) var receivedBytes: UInt64 = 0
    public private(set) var trimmedBytes: UInt64 = 0
    public private(set) var deviceDroppedBytes: UInt32 = 0
    public static let capacity = 64 * 1024
    public init() {}
    public mutating func append(_ reply: SerialBridge.Reply) {
        receivedBytes += UInt64(reply.payload.count)
        deviceDroppedBytes = reply.droppedBytes
        data.append(reply.payload)
        if data.count > Self.capacity {
            let excess = data.count - Self.capacity
            data.removeFirst(excess)
            trimmedBytes += UInt64(excess)
        }
    }
    public var displayText: String {
        String(decoding: data.suffix(8192), as: UTF8.self)
            .unicodeScalars.map { ($0.value < 32 && $0 != "\n" && $0 != "\r" && $0 != "\t") ? "·" : String($0) }.joined()
    }
}
