import Foundation

public enum RPCError: Error, LocalizedError, Equatable, Sendable {
    case malformed, tooLarge, disconnected, busy, timeout, cancelled
    case remote(UInt32)
    case message(String)
    public var errorDescription: String? {
        switch self {
        case .malformed: return "设备返回的数据格式不正确。请断开后重新连接。"
        case .tooLarge: return "数据超过本次操作的大小限制。"
        case .disconnected: return "设备尚未准备完成，或连接已经断开。"
        case .busy: return "上一项设备操作尚未完成。"
        case .timeout: return "设备响应超时，连接已关闭以避免重复执行。"
        case .cancelled: return "操作已取消。"
        case .remote(let code):
            switch code {
            case 3: return "当前固件不支持此功能。"
            case 4, 17: return "Flipper 正忙，请先退出设备上的当前应用。"
            case 5: return "设备存储尚未准备好，请检查 SD 卡。"
            case 6: return "设备上已存在同名文件。"
            case 7: return "设备上的文件不存在。"
            case 9: return "设备拒绝访问该文件。"
            case 21: return "设备应用尚未启动，或不支持远程控制。"
            default: return "设备操作失败（错误码 \(code)）。"
            }
        case .message(let text): return text
        }
    }
}

/// The subset of the protobuf wire format used by the pinned Flipper RPC schema.
/// Unknown fixed-width fields are skipped; groups are rejected. No schema dependency is upgraded.
public struct PBMessage: Sendable {
    public enum Value: Sendable { case integer(UInt64), data(Data) }
    public let fields: [(number: Int, value: Value)]

    public init(_ data: Data) throws {
        guard data.count <= 65_536 else { throw RPCError.tooLarge }
        let input = Array(data)
        var offset = 0
        var values: [(number: Int, value: Value)] = []
        while offset < input.count {
            guard values.count < 4096 else { throw RPCError.tooLarge }
            let key = try Self.readVarint(input, offset: &offset)
            let number = key >> 3
            guard number > 0, number <= 0x1fff_ffff else { throw RPCError.malformed }
            switch key & 7 {
            case 0: values.append((Int(number), .integer(try Self.readVarint(input, offset: &offset))))
            case 2:
                let count = try Self.readVarint(input, offset: &offset)
                guard count <= UInt64(input.count - offset) else { throw RPCError.malformed }
                let end = offset + Int(count)
                values.append((Int(number), .data(Data(input[offset..<end]))))
                offset = end
            case 1, 5:
                let size = key & 7 == 1 ? 8 : 4
                guard input.count - offset >= size else { throw RPCError.malformed }
                offset += size
            default: throw RPCError.malformed
            }
        }
        fields = values
    }

    public func uint(_ number: Int) -> UInt64 {
        for field in fields.reversed() where field.number == number {
            if case .integer(let value) = field.value { return value }
        }
        return 0
    }
    public func bytes(_ number: Int) -> Data? { blobs(number).last }
    public func blobs(_ number: Int) -> [Data] {
        fields.compactMap { field in
            guard field.number == number, case .data(let data) = field.value else { return nil }
            return data
        }
    }
    public func string(_ number: Int) throws -> String? {
        guard let data = bytes(number) else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { throw RPCError.malformed }
        return text
    }

    static func readVarint(_ data: [UInt8], offset: inout Int) throws -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<10 {
            guard offset < data.count else { throw RPCError.malformed }
            let byte = data[offset]
            offset += 1
            if index == 9 && byte > 1 { throw RPCError.malformed }
            value |= UInt64(byte & 0x7f) << (index * 7)
            if byte & 0x80 == 0 { return value }
        }
        throw RPCError.malformed
    }
    public static func varint(_ value: UInt64) -> Data {
        var value = value
        var output = Data()
        repeat {
            let byte = UInt8(value & 0x7f)
            value >>= 7
            output.append(value == 0 ? byte : byte | 0x80)
        } while value != 0
        return output
    }
    public static func uint(_ number: Int, _ value: UInt64) -> Data {
        precondition((1...0x1fff_ffff).contains(number))
        return varint(UInt64(number) << 3) + varint(value)
    }
    public static func bytes(_ number: Int, _ value: Data) -> Data {
        precondition((1...0x1fff_ffff).contains(number))
        return varint((UInt64(number) << 3) | 2) + varint(UInt64(value.count)) + value
    }
    public static func string(_ number: Int, _ value: String) -> Data { bytes(number, Data(value.utf8)) }
}

public struct RPCEnvelope: Sendable {
    public let commandID: UInt32
    public let status: UInt32
    public let hasNext: Bool
    public let tag: Int
    public let payload: Data

    public init(_ data: Data) throws {
        let message = try PBMessage(data)
        guard let id = UInt32(exactly: message.uint(1)),
              let status = UInt32(exactly: message.uint(2)) else { throw RPCError.malformed }
        guard let body = message.fields.last(where: { field in
            guard field.number >= 4 else { return false }
            if case .data = field.value { return true }
            return false
        }), case .data(let payload) = body.value else { throw RPCError.malformed }
        self.commandID = id; self.status = status; hasNext = message.uint(3) != 0
        tag = body.number; self.payload = payload
    }
    public static func encode(id: UInt32, tag: Int, payload: Data = Data(), hasNext: Bool = false) -> Data {
        let body = PBMessage.uint(1, UInt64(id)) +
            (hasNext ? PBMessage.uint(3, 1) : Data()) + PBMessage.bytes(tag, payload)
        return PBMessage.varint(UInt64(body.count)) + body
    }
}

/// Length-delimited frames can span arbitrary BLE indications, including the length prefix.
public struct RPCFrameDecoder: Sendable {
    private var pending: [UInt8] = []
    public init() {}
    public mutating func reset() { pending.removeAll(keepingCapacity: false) }
    public mutating func append(_ chunk: Data) throws -> [RPCEnvelope] {
        guard pending.count + chunk.count <= 131_072 else { reset(); throw RPCError.tooLarge }
        pending.append(contentsOf: chunk)
        var frames: [RPCEnvelope] = []
        var start = 0
        do {
            while start < pending.count {
                var offset = start
                var length: UInt64 = 0
                var complete = false
                for index in 0..<5 {
                    if offset == pending.count { break }
                    let byte = pending[offset]; offset += 1
                    length |= UInt64(byte & 0x7f) << (index * 7)
                    if byte & 0x80 == 0 { complete = true; break }
                    if index == 4 { throw RPCError.malformed }
                }
                if !complete { break }
                guard length > 0, length <= 65_536 else { throw RPCError.tooLarge }
                guard UInt64(pending.count - offset) >= length else { break }
                let end = offset + Int(length)
                frames.append(try RPCEnvelope(Data(pending[offset..<end])))
                start = end
            }
            if start > 0 { pending.removeFirst(start) }
            return frames
        } catch {
            reset()
            throw error
        }
    }
}

public struct DeviceFile: Identifiable, Sendable, Equatable {
    public let path: String
    public let name: String
    public let size: UInt64
    public let isDirectory: Bool
    public var id: String { path }
    public init(parent: String, message: PBMessage) throws {
        guard let name = try message.string(2), !name.isEmpty,
              name != ".", name != "..", !name.contains("/"), !name.contains("\\"),
              !name.contains("\0"), name.utf8.count <= 254,
              message.uint(1) <= 1 else { throw RPCError.malformed }
        self.name = name; size = message.uint(3); isDirectory = message.uint(1) == 1
        path = (parent == "/" ? "" : parent) + "/" + name
    }
}
