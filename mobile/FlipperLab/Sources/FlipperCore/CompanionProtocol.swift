import Foundation

/// Bounds for the pinned companion GPS/network messages (flipper.proto tags 76–90). Host, URL, data, path
/// and frequency limits follow network.h, gps.h and the .options files; header size and timeouts are
/// companion policy. This file only validates and encodes DTOs; it performs no I/O.
public enum CompanionLimits {
    public static let maxHostBytes = 255
    public static let maxURLBytes = 2048
    public static let maxHeaderBytes = 8192
    public static let maxDataBytes = 512
    /// PB_Storage.*.path max_length.
    public static let maxPathBytes = 255
    /// Longest textual IPv6 address.
    public static let maxResolvedIPBytes = 45
    public static let defaultTimeoutMilliseconds: UInt32 = 30_000
    public static let timeoutMilliseconds: ClosedRange<UInt32> = 1_000...120_000
    public static let gpsUpdatesPerSecond: ClosedRange<UInt32> = 1...10
}

/// PB_Network.Protocol.
public enum CompanionSocketProtocol: UInt32, Sendable, CaseIterable {
    case tcp = 0, udp = 1
}

/// PB_Network.HttpMethod.
public enum CompanionHTTPMethod: UInt32, Sendable, CaseIterable {
    case get = 0, post = 1, put = 2, patch = 3, delete = 4, head = 5

    public var name: String {
        switch self {
        case .get: return "GET"
        case .post: return "POST"
        case .put: return "PUT"
        case .patch: return "PATCH"
        case .delete: return "DELETE"
        case .head: return "HEAD"
        }
    }
}

/// PB_Network.ConnectionState.
public enum CompanionConnectionState: UInt32, Sendable, CaseIterable {
    case disconnected = 0, connecting = 1, connected = 2, error = 3
}

/// PB_Network.ErrorCode.
public enum CompanionNetworkErrorCode: UInt32, Sendable, CaseIterable {
    case noError = 0, dnsFailed = 1, timeout = 2, connectionRefused = 3, networkUnreachable = 4
    case hostUnreachable = 5, invalidConnection = 6, notConnected = 7, sendFailed = 8, receiveFailed = 9
    case maxConnections = 10, invalidProtocol = 11, internalError = 12, tlsFailed = 13, invalidURL = 14
    case fileError = 15
}

/// PB.CommandStatus codes a gps_location frame carries when the companion has no fix to give.
public enum CompanionGPSStatus: UInt32, Sendable, CaseIterable {
    case notSupported = 60, noPermission = 61, disabled = 62, unknown = 63
}

// MARK: - Requests from the firmware

/// A companion request sent by the firmware. Frames must carry command ID 0, status OK and no has_next;
/// payloads must match the pinned schema exactly, so unknown, repeated or mistyped fields are malformed.
public enum CompanionRequest: Sendable, Equatable {
    case connect(CompanionConnectRequest)
    case send(CompanionSendRequest)
    case close(CompanionCloseRequest)
    case startGPSStream(CompanionGPSStreamRequest)
    case stopGPSStream
    case requestGPSLocation
    case http(CompanionHTTPRequest)
    case openWebSocket(CompanionWebSocketRequest)

    public static let tags: Set<Int> = [76, 78, 81, 84, 85, 86, 88, 90]

    /// RPCEnvelope keeps only the last content field. Where the raw message is available,
    /// `init(message:)` also rejects duplicate oneof members.
    public init(_ envelope: RPCEnvelope) throws {
        guard envelope.commandID == 0, envelope.status == 0, !envelope.hasNext else { throw RPCError.malformed }
        self = try Self.parse(tag: envelope.tag, payload: envelope.payload)
    }

    /// One unframed PB.Main message, as RPCFrameDecoder hands it to RPCEnvelope.
    public init(message: Data) throws {
        let main = try CompanionWire(message)
        guard try main.uint32(1) == 0, try main.uint32(2) == 0, try main.uint32(3) == 0,
              main.integers.keys.allSatisfy({ $0 <= 3 }), main.blobs.count == 1,
              let content = main.blobs.first, content.key >= 4 else { throw RPCError.malformed }
        self = try Self.parse(tag: content.key, payload: content.value)
    }

    /// Connection or request ID of a network request; nil for GPS requests.
    public var connectionID: UInt32? {
        switch self {
        case .connect(let request): return request.connectionID
        case .send(let request): return request.connectionID
        case .close(let request): return request.connectionID
        case .http(let request): return request.requestID
        case .openWebSocket(let request): return request.connectionID
        case .startGPSStream, .stopGPSStream, .requestGPSLocation: return nil
        }
    }

    /// Reads only the ID of a network request frame, so a rejected request can still be answered with
    /// an error response. Zero is a valid proto3 ID, including when the field is omitted.
    public static func replyID(for envelope: RPCEnvelope) -> UInt32? {
        let field: Int
        switch envelope.tag {
        case 76: field = 5
        case 78, 81, 88, 90: field = 1
        default: return nil
        }
        guard let message = try? PBMessage(envelope.payload),
              let id = UInt32(exactly: message.uint(field)) else { return nil }
        return id
    }

    private static func parse(tag: Int, payload: Data) throws -> CompanionRequest {
        switch tag {
        case 76: return try .connect(CompanionConnectRequest(payload: payload))
        case 78: return try .send(CompanionSendRequest(payload: payload))
        case 81: return try .close(CompanionCloseRequest(payload: payload))
        case 84: return try .startGPSStream(CompanionGPSStreamRequest(payload: payload))
        case 85, 86:
            // StreamStopRequest and LocationRequest have no fields.
            guard payload.isEmpty else { throw RPCError.malformed }
            return tag == 85 ? .stopGPSStream : .requestGPSLocation
        case 88: return try .http(CompanionHTTPRequest(payload: payload))
        case 90: return try .openWebSocket(CompanionWebSocketRequest(payload: payload))
        default: throw RPCError.malformed
        }
    }
}

/// PB_Network.ConnectRequest (tag 76).
public struct CompanionConnectRequest: Sendable, Equatable {
    public let connectionID: UInt32
    public let host: String
    public let port: UInt16
    public let transport: CompanionSocketProtocol
    /// 0 on the wire selects the default; other values are clamped to `CompanionLimits.timeoutMilliseconds`.
    public let timeoutMilliseconds: UInt32

    init(payload: Data) throws {
        let wire = try CompanionWire(payload, fields: 1...5)
        let port = try wire.uint32(2)
        guard (1...65_535).contains(port),
              let transport = try CompanionSocketProtocol(rawValue: wire.uint32(3)) else { throw RPCError.malformed }
        connectionID = try wire.uint32(5)
        host = try CompanionText.host(wire.bytes(1, limit: CompanionLimits.maxHostBytes))
        self.port = UInt16(port)
        self.transport = transport
        timeoutMilliseconds = try CompanionText.timeout(wire.uint32(4))
    }
}

/// PB_Network.SendRequest (tag 78). Like network_websocket_send(), the payload is 1...512 bytes.
public struct CompanionSendRequest: Sendable, Equatable {
    public let connectionID: UInt32
    public let data: Data
    /// WebSocket frame type; raw sockets ignore it.
    public let isBinary: Bool

    init(payload: Data) throws {
        let wire = try CompanionWire(payload, fields: 1...3)
        let data = try wire.bytes(2, limit: CompanionLimits.maxDataBytes)
        guard !data.isEmpty else { throw RPCError.malformed }
        connectionID = try wire.uint32(1)
        self.data = data
        isBinary = try wire.bool(3)
    }
}

/// PB_Network.CloseRequest (tag 81).
public struct CompanionCloseRequest: Sendable, Equatable {
    public let connectionID: UInt32

    init(payload: Data) throws {
        connectionID = try CompanionWire(payload, fields: 1...1).uint32(1)
    }
}

/// PB_Gps.StreamStartRequest (tag 84).
public struct CompanionGPSStreamRequest: Sendable, Equatable {
    public let updatesPerSecond: UInt8

    init(payload: Data) throws {
        let frequency = try CompanionWire(payload, fields: 1...1).uint32(1)
        guard CompanionLimits.gpsUpdatesPerSecond.contains(frequency) else { throw RPCError.malformed }
        updatesPerSecond = UInt8(frequency)
    }
}

/// PB_Network.HttpRequest (tag 88).
public struct CompanionHTTPRequest: Sendable, Equatable {
    public let requestID: UInt32
    public let method: CompanionHTTPMethod
    public let url: URL
    public let headers: [CompanionHTTPHeader]
    public let body: Data
    /// SD file uploaded as the body; never set together with `body`.
    public let sendPath: String?
    /// SD file for the response body; nil means the body returns as ReceiveData chunks.
    public let savePath: String?
    public let timeoutMilliseconds: UInt32
    public let includeResponseHeaders: Bool

    init(payload: Data) throws {
        let wire = try CompanionWire(payload, fields: 1...9)
        guard let method = try CompanionHTTPMethod(rawValue: wire.uint32(2)) else { throw RPCError.malformed }
        let body = try wire.bytes(5, limit: CompanionLimits.maxDataBytes)
        let sendPath = try CompanionText.path(wire.bytes(6, limit: CompanionLimits.maxPathBytes))
        guard body.isEmpty || sendPath == nil else { throw RPCError.malformed }
        requestID = try wire.uint32(1)
        self.method = method
        url = try CompanionText.url(wire.bytes(3, limit: CompanionLimits.maxURLBytes), schemes: ["http", "https"])
        headers = try CompanionText.headers(wire.bytes(4, limit: CompanionLimits.maxHeaderBytes))
        self.body = body
        self.sendPath = sendPath
        savePath = try CompanionText.path(wire.bytes(7, limit: CompanionLimits.maxPathBytes))
        timeoutMilliseconds = try CompanionText.timeout(wire.uint32(8))
        includeResponseHeaders = try wire.bool(9)
    }
}

/// PB_Network.WebSocketOpenRequest (tag 90). The reply is a ConnectResponse.
public struct CompanionWebSocketRequest: Sendable, Equatable {
    public let connectionID: UInt32
    public let url: URL
    public let headers: [CompanionHTTPHeader]
    public let timeoutMilliseconds: UInt32

    init(payload: Data) throws {
        let wire = try CompanionWire(payload, fields: 1...4)
        connectionID = try wire.uint32(1)
        url = try CompanionText.url(wire.bytes(2, limit: CompanionLimits.maxURLBytes), schemes: ["ws", "wss"])
        headers = try CompanionText.headers(wire.bytes(3, limit: CompanionLimits.maxHeaderBytes))
        timeoutMilliseconds = try CompanionText.timeout(wire.uint32(4))
    }
}

/// One "Name: Value" header row. Names are RFC 9110 tokens and values allow no controls except tab,
/// so CR, LF and NUL cannot inject rows. Surrounding spaces and tabs are not part of the value.
public struct CompanionHTTPHeader: Sendable, Equatable {
    public let name: String
    public let value: String

    public init(name: String, value: String) throws {
        let bytes = Self.trimmed(Array(value.utf8))
        guard !name.isEmpty, name.utf8.allSatisfy({ Self.tokenBytes.contains($0) }),
              bytes.allSatisfy({ $0 == 0x09 || ($0 >= 0x20 && $0 != 0x7f) }) else { throw RPCError.malformed }
        let text = String(decoding: bytes, as: UTF8.self)
        // C1 controls are two bytes in UTF-8, so the byte check above cannot see them.
        guard !text.unicodeScalars.contains(where: { (0x80...0x9f).contains($0.value) }) else {
            throw RPCError.malformed
        }
        self.name = name
        self.value = text
    }

    init(row: ArraySlice<UInt8>) throws {
        guard let colon = row.firstIndex(of: UInt8(ascii: ":")) else { throw RPCError.malformed }
        try self.init(name: String(decoding: row[..<colon], as: UTF8.self),
                      value: String(decoding: row[(colon + 1)...], as: UTF8.self))
    }

    private static let tokenBytes = Set("!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)

    private static func trimmed(_ bytes: [UInt8]) -> ArraySlice<UInt8> {
        var slice = bytes[...]
        while let first = slice.first, first == 0x20 || first == 0x09 { slice.removeFirst() }
        while let last = slice.last, last == 0x20 || last == 0x09 { slice.removeLast() }
        return slice
    }
}

// MARK: - Location

/// A fix in PB_Gps.Location units. The schema has no presence bits: heading, speed and satellites
/// are 0 when unavailable, which a receiver cannot tell apart from a real zero reading.
public struct CompanionLocation: Sendable, Equatable {
    public let latitudeE7: Int32
    public let longitudeE7: Int32
    public let headingCentidegrees: UInt32
    public let speedMillimetersPerSecond: UInt32
    public let altitudeCentimeters: Int32
    public let accuracyMillimeters: UInt32
    public let satellites: UInt8

    /// Degrees, meters and meters per second as a location service reports them. Invalid coordinates,
    /// non-finite values and negative accuracy are rejected; negative speed or course means unavailable.
    /// `satellites` stays 0 unless a real count is known (the firmware decodes it as uint8).
    public init(latitude: Double, longitude: Double, altitude: Double, speed: Double, course: Double,
                horizontalAccuracy: Double, satellites: UInt8 = 0) throws {
        guard [latitude, longitude, altitude, speed, course, horizontalAccuracy].allSatisfy({ $0.isFinite }),
              (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude),
              horizontalAccuracy >= 0 else { throw RPCError.malformed }
        latitudeE7 = Int32((latitude * 1e7).rounded())
        longitudeE7 = Int32((longitude * 1e7).rounded())
        altitudeCentimeters = Int32(Self.clamped(altitude * 100, to: Double(Int32.min)...Double(Int32.max)))
        speedMillimetersPerSecond = speed < 0 ? 0 : UInt32(Self.clamped(speed * 1000, to: 0...Double(UInt32.max)))
        headingCentidegrees = course < 0 ? 0 : UInt32(Self.clamped(course * 100, to: 0...36_000))
        accuracyMillimeters = UInt32(Self.clamped(horizontalAccuracy * 1000, to: 0...Double(UInt32.max)))
        self.satellites = satellites
    }

    private static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value.rounded(), range.lowerBound), range.upperBound)
    }
}

// MARK: - Replies to the firmware

/// Complete length-delimited reply frames (command ID 0; zero-valued fields omitted as in proto3).
/// Inputs are range-checked instead of truncated and throw RPCError when the schema cannot carry them.
public enum CompanionResponse {
    /// ConnectResponse (tag 77), which also answers a WebSocket open request.
    public static func connect(connectionID: UInt32, state: CompanionConnectionState,
                               error: CompanionNetworkErrorCode = .noError, resolvedIP: String? = nil) throws -> Data {
        var payload = try stateFields(connectionID, state, error)
        if let resolvedIP, !resolvedIP.isEmpty {
            guard resolvedIP.utf8.count <= CompanionLimits.maxResolvedIPBytes,
                  CompanionText.isIPv4(resolvedIP) || CompanionText.isIPv6(resolvedIP) else { throw RPCError.malformed }
            payload += PBMessage.string(4, resolvedIP)
        }
        return RPCEnvelope.encode(id: 0, tag: 77, payload: payload)
    }

    /// SendResponse (tag 79).
    public static func send(connectionID: UInt32, bytesSent: Int,
                            error: CompanionNetworkErrorCode = .noError) throws -> Data {
        guard (0...CompanionLimits.maxDataBytes).contains(bytesSent) else { throw RPCError.malformed }
        var payload = try id(connectionID)
        payload += field(2, UInt64(bytesSent))
        payload += field(3, UInt64(error.rawValue))
        return RPCEnvelope.encode(id: 0, tag: 79, payload: payload)
    }

    /// ReceiveData (tag 80): one chunk of at most 512 bytes.
    public static func received(connectionID: UInt32, data: Data, binary: Bool = false) throws -> Data {
        guard data.count <= CompanionLimits.maxDataBytes else { throw RPCError.tooLarge }
        var payload = try id(connectionID)
        if !data.isEmpty { payload += PBMessage.bytes(2, data) }
        payload += field(3, binary ? 1 : 0)
        return RPCEnvelope.encode(id: 0, tag: 80, payload: payload)
    }

    /// CloseResponse (tag 82).
    public static func close(connectionID: UInt32, error: CompanionNetworkErrorCode = .noError) throws -> Data {
        var payload = try id(connectionID)
        payload += field(2, UInt64(error.rawValue))
        return RPCEnvelope.encode(id: 0, tag: 82, payload: payload)
    }

    /// StateChanged (tag 83).
    public static func stateChanged(connectionID: UInt32, state: CompanionConnectionState,
                                    error: CompanionNetworkErrorCode = .noError) throws -> Data {
        try RPCEnvelope.encode(id: 0, tag: 83, payload: stateFields(connectionID, state, error))
    }

    /// Location (tag 87) with command status OK.
    public static func location(_ location: CompanionLocation) -> Data {
        var payload = field(1, UInt64(zigzag(location.latitudeE7)))
        payload += field(2, UInt64(zigzag(location.longitudeE7)))
        payload += field(3, UInt64(location.headingCentidegrees))
        payload += field(4, UInt64(location.speedMillimetersPerSecond))
        payload += field(5, UInt64(zigzag(location.altitudeCentimeters)))
        payload += field(6, UInt64(location.accuracyMillimeters))
        payload += field(7, UInt64(location.satellites))
        return RPCEnvelope.encode(id: 0, tag: 87, payload: payload)
    }

    /// Location (tag 87) with no fields and command status 60...63, which the firmware maps to GpsStatus.
    public static func locationUnavailable(_ status: CompanionGPSStatus) -> Data {
        RPCEnvelope.encode(id: 0, tag: 87, status: status.rawValue)
    }

    /// HttpResponse (tag 89). Status 0 means no HTTP response was received and requires an error code.
    public static func http(requestID: UInt32, statusCode: Int, error: CompanionNetworkErrorCode = .noError,
                            headers: [CompanionHTTPHeader] = [], bodySize: Int = 0,
                            savedToFile: Bool = false) throws -> Data {
        guard (statusCode == 0 ? error != .noError : (100...599).contains(statusCode)),
              !savedToFile || error == .noError,
              let size = UInt32(exactly: bodySize) else { throw RPCError.malformed }
        let text = headers.map { "\($0.name): \($0.value)\r\n" }.joined()
        guard text.utf8.count <= CompanionLimits.maxHeaderBytes else { throw RPCError.tooLarge }
        var payload = try id(requestID)
        payload += field(2, UInt64(statusCode))
        payload += field(3, UInt64(error.rawValue))
        if !text.isEmpty { payload += PBMessage.string(4, text) }
        payload += field(5, UInt64(size))
        payload += field(6, savedToFile ? 1 : 0)
        return RPCEnvelope.encode(id: 0, tag: 89, payload: payload)
    }

    /// sint32 wire value.
    static func zigzag(_ value: Int32) -> UInt32 {
        UInt32(bitPattern: (value << 1) ^ (value >> 31))
    }

    private static func id(_ connectionID: UInt32) throws -> Data {
        return PBMessage.uint(1, UInt64(connectionID))
    }

    private static func field(_ number: Int, _ value: UInt64) -> Data {
        value == 0 ? Data() : PBMessage.uint(number, value)
    }

    /// ConnectResponse and StateChanged share connection_id, state and error as fields 1–3.
    private static func stateFields(_ connectionID: UInt32, _ state: CompanionConnectionState,
                                    _ error: CompanionNetworkErrorCode) throws -> Data {
        switch state {
        case .connecting, .connected: guard error == .noError else { throw RPCError.malformed }
        case .error: guard error != .noError else { throw RPCError.malformed }
        case .disconnected: break
        }
        var payload = try id(connectionID)
        payload += field(2, UInt64(state.rawValue))
        payload += field(3, UInt64(error.rawValue))
        return payload
    }
}

// MARK: - Validation

/// One companion message read strictly. The schema only uses varint and length-delimited fields, so
/// other wire types, a repeated field number or a number outside `fields` is malformed.
private struct CompanionWire {
    var integers: [Int: UInt64] = [:]
    var blobs: [Int: Data] = [:]

    init(_ data: Data, fields allowed: ClosedRange<Int> = 1...0x1fff_ffff) throws {
        guard data.count <= 65_536 else { throw RPCError.tooLarge }
        let input = Array(data)
        var offset = 0
        while offset < input.count {
            let key = try PBMessage.readVarint(input, offset: &offset)
            guard key >> 3 <= UInt64(allowed.upperBound), allowed.contains(Int(key >> 3)) else {
                throw RPCError.malformed
            }
            let number = Int(key >> 3)
            guard integers[number] == nil, blobs[number] == nil else { throw RPCError.malformed }
            switch key & 7 {
            case 0:
                integers[number] = try PBMessage.readVarint(input, offset: &offset)
            case 2:
                let count = try PBMessage.readVarint(input, offset: &offset)
                guard count <= UInt64(input.count - offset) else { throw RPCError.malformed }
                blobs[number] = Data(input[offset..<(offset + Int(count))])
                offset += Int(count)
            default:
                throw RPCError.malformed
            }
        }
    }

    func uint32(_ number: Int) throws -> UInt32 {
        guard blobs[number] == nil, let value = UInt32(exactly: integers[number] ?? 0) else {
            throw RPCError.malformed
        }
        return value
    }

    func bool(_ number: Int) throws -> Bool {
        let value = try uint32(number)
        guard value <= 1 else { throw RPCError.malformed }
        return value == 1
    }

    func bytes(_ number: Int, limit: Int) throws -> Data {
        guard integers[number] == nil else { throw RPCError.malformed }
        let value = blobs[number] ?? Data()
        guard value.count <= limit else { throw RPCError.tooLarge }
        return value
    }
}

private enum CompanionText {
    static let hexBytes = Set("0123456789ABCDEFabcdef".utf8)
    static let hostBytes = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._".utf8)
    /// RFC 3986 characters except '#': no spaces, controls, backslashes, double quotes, braces or non-ASCII.
    static let urlBytes = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~%!$&'()*+,;=:@/?[]".utf8)

    static func utf8(_ data: Data) throws -> String {
        let text = String(decoding: data, as: UTF8.self)
        guard text.utf8.elementsEqual(data) else { throw RPCError.malformed }
        return text
    }

    /// Controls, format characters (such as bidi overrides) and line separators are never printable here.
    static func isPrintable(_ scalar: Unicode.Scalar, allowSpace: Bool) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator: return false
        case .spaceSeparator: return allowSpace
        default: return true
        }
    }

    static func host(_ data: Data) throws -> String {
        let host = try utf8(data)
        guard !host.isEmpty, host.unicodeScalars.allSatisfy({ isPrintable($0, allowSpace: false) }) else {
            throw RPCError.malformed
        }
        return host
    }

    /// Empty means unset; otherwise an absolute /ext path whose components are real names.
    static func path(_ data: Data) throws -> String? {
        guard !data.isEmpty else { return nil }
        let path = try utf8(data)
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0].isEmpty, parts[1] == "ext", !path.contains("\\"),
              !parts.dropFirst().contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              path.unicodeScalars.allSatisfy({ isPrintable($0, allowSpace: true) }) else { throw RPCError.malformed }
        return path
    }

    static func timeout(_ milliseconds: UInt32) -> UInt32 {
        guard milliseconds != 0 else { return CompanionLimits.defaultTimeoutMilliseconds }
        let range = CompanionLimits.timeoutMilliseconds
        return min(max(milliseconds, range.lowerBound), range.upperBound)
    }

    /// Rows end with CRLF or LF; the final terminator is optional and empty rows are rejected.
    static func headers(_ data: Data) throws -> [CompanionHTTPHeader] {
        _ = try utf8(data)
        let bytes = Array(data)
        var rows: [CompanionHTTPHeader] = []
        var start = 0
        while start < bytes.count {
            let newline = bytes[start...].firstIndex(of: UInt8(ascii: "\n"))
            var row = bytes[start..<(newline ?? bytes.count)]
            if newline != nil, row.last == UInt8(ascii: "\r") { row = row.dropLast() }
            try rows.append(CompanionHTTPHeader(row: row))
            start = (newline ?? bytes.count) + 1
        }
        return rows
    }

    /// Absolute ASCII URL with a listed scheme, no userinfo or fragment, valid percent escapes, a DNS-style
    /// or bracketed IPv6 host and an optional port 1...65535.
    static func url(_ data: Data, schemes: Set<String>) throws -> URL {
        let bytes = Array(data)
        guard bytes.allSatisfy({ urlBytes.contains($0) }),
              let colon = bytes.firstIndex(of: UInt8(ascii: ":")),
              schemes.contains(String(decoding: bytes[..<colon], as: UTF8.self).lowercased()),
              bytes[(colon + 1)...].starts(with: [UInt8(ascii: "/"), UInt8(ascii: "/")]) else {
            throw RPCError.malformed
        }
        for index in bytes.indices where bytes[index] == UInt8(ascii: "%") {
            guard index + 2 < bytes.count, hexBytes.contains(bytes[index + 1]), hexBytes.contains(bytes[index + 2]) else {
                throw RPCError.malformed
            }
        }
        let start = colon + 3
        let end = bytes[start...].firstIndex(where: { $0 == UInt8(ascii: "/") || $0 == UInt8(ascii: "?") }) ?? bytes.count
        guard isAuthority(bytes[start..<end]),
              !bytes[end...].contains(where: { $0 == UInt8(ascii: "[") || $0 == UInt8(ascii: "]") }),
              let url = URL(string: String(decoding: bytes, as: UTF8.self)) else { throw RPCError.malformed }
        return url
    }

    private static func isAuthority(_ authority: ArraySlice<UInt8>) -> Bool {
        var host = authority
        var port: ArraySlice<UInt8>?
        if authority.first == UInt8(ascii: "[") {
            guard let close = authority.firstIndex(of: UInt8(ascii: "]")) else { return false }
            host = authority[(authority.startIndex + 1)..<close]
            let rest = authority[(close + 1)...]
            if !rest.isEmpty {
                guard rest.first == UInt8(ascii: ":") else { return false }
                port = rest.dropFirst()
            }
            guard isIPv6(String(decoding: host, as: UTF8.self)) else { return false }
        } else {
            if let colon = authority.firstIndex(of: UInt8(ascii: ":")) {
                host = authority[..<colon]
                port = authority[(colon + 1)...]
            }
            let name = String(decoding: host, as: UTF8.self)
            guard !host.isEmpty, host.allSatisfy({ hostBytes.contains($0) }),
                  !name.hasPrefix("."), !name.contains("..") else { return false }
        }
        guard let port else { return true }
        let digits = Array(port)
        guard (1...5).contains(digits.count), digits.allSatisfy({ (0x30...0x39).contains($0) }) else { return false }
        return (1...65_535).contains(digits.reduce(0) { $0 * 10 + Int($1 - 0x30) })
    }

    static func isIPv4<S: StringProtocol>(_ text: S) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            let digits = Array(part.utf8)
            guard (1...3).contains(digits.count), digits.allSatisfy({ (0x30...0x39).contains($0) }),
                  digits.count == 1 || digits[0] != 0x30 else { return false }
            return digits.reduce(0) { $0 * 10 + Int($1 - 0x30) } <= 255
        }
    }

    /// Up to eight 1–4 digit hex groups with at most one "::" and an optional trailing IPv4 part.
    /// Zone IDs are not accepted.
    static func isIPv6(_ text: String) -> Bool {
        guard text.utf8.allSatisfy({ hexBytes.contains($0) || $0 == UInt8(ascii: ":") || $0 == UInt8(ascii: ".") }) else {
            return false
        }
        let halves = text.components(separatedBy: "::")
        guard halves.count <= 2 else { return false }
        var groups = 0
        for (index, half) in halves.enumerated() where !half.isEmpty {
            let parts = half.split(separator: ":", omittingEmptySubsequences: false)
            for (position, part) in parts.enumerated() {
                if index == halves.count - 1, position == parts.count - 1, part.contains(".") {
                    guard isIPv4(part) else { return false }
                    groups += 2
                } else {
                    guard (1...4).contains(part.count), !part.contains(".") else { return false }
                    groups += 1
                }
            }
        }
        return halves.count == 2 ? groups <= 7 : groups == 8
    }
}
