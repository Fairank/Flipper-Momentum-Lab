import Foundation
import Network

/// Terminal state of a channel that finished opening. An open call's own return or throw answers
/// the connect request, so `onState` only ever reports `.disconnected` or `.error`.
public enum CompanionTransportState: Sendable, Equatable {
    case connected, disconnected, error
}

/// Transport failures, grouped like the firmware's `PB_Network.ErrorCode`.
public enum CompanionTransportError: Error, LocalizedError, Equatable, Sendable {
    case dns, timeout, refused, unreachable, invalidConnection, notConnected
    case send, receive, limit, invalidProtocol, internalFailure, tls, invalidURL

    public var errorDescription: String? {
        switch self {
        case .dns: return "无法解析服务器地址。"
        case .timeout: return "网络操作超时，连接已关闭。"
        case .refused: return "服务器拒绝了连接。"
        case .unreachable: return "当前网络无法到达服务器。"
        case .invalidConnection: return "连接编号无效或已被占用。"
        case .notConnected: return "连接尚未建立或已经关闭。"
        case .send: return "发送数据失败。"
        case .receive: return "接收数据失败。"
        case .limit: return "超过了连接数量或数据大小限制。"
        case .invalidProtocol: return "请求使用了不支持的协议、方法或请求头。"
        case .internalFailure: return "手机端网络组件发生内部错误。"
        case .tls: return "安全连接失败，请检查证书或改用 HTTPS。"
        case .invalidURL: return "网址或主机地址无效。"
        }
    }
}

public struct CompanionHTTPResult: Sendable, Equatable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

/// Phone-side transport for the firmware's companion network proxy (`PB_Network`).
///
/// Every operation belongs to a client ID that is unique across sockets, WebSockets and HTTP.
/// Transport callbacks carry the object that produced them, so a closed operation never reaches a
/// newer one that reuses its ID. `onData` and `onState` run on the main actor. A channel reads its
/// next chunk only after `onData` returns, so each channel holds at most one pending chunk.
/// `close(id:)`, `cancelAll()` and cancelling an awaiting task are silent: the waiting call throws
/// `CancellationError` and no callback follows for that operation.
@MainActor
public final class CompanionNetworking {
    public var onData: ((UInt32, Data, Bool) async throws -> Void)?
    public var onState: ((UInt32, CompanionTransportState, CompanionTransportError?) -> Void)?

    private let configuration: URLSessionConfiguration
    private let queue = DispatchQueue(label: "FlipperLab.CompanionNetworking", qos: .userInitiated)
    private var sessionBox: SessionBox?
    private var entries: [UInt32: Entry] = [:]

    public init(httpConfiguration: URLSessionConfiguration = .ephemeral) {
        configuration = CompanionNetworkPolicy.hardened(httpConfiguration)
    }

    /// IDs that currently own an operation.
    var activeIDs: [UInt32] { entries.keys.sorted() }

    /// Closes one operation silently. Unknown IDs are ignored.
    public func close(id: UInt32) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        Self.stop(entry)
    }

    /// Closes every operation and invalidates the URL session. The adapter stays usable.
    public func cancelAll() {
        let all = Array(entries.values)
        entries.removeAll()
        for entry in all { Self.stop(entry) }
        sessionBox?.session.invalidateAndCancel()
        sessionBox = nil
    }

    /// Sends one socket payload or one WebSocket message and returns the bytes handed to the transport.
    public func send(id: UInt32, data: Data, binary: Bool) async throws -> Int {
        try Task.checkCancellation()
        switch entries[id] {
        case .socket(let channel)?:
            return try await send(data, on: channel)
        case .webSocket(let channel)?:
            return try await send(data, binary: binary, on: channel)
        case .http?, nil:
            throw CompanionTransportError.invalidConnection
        }
    }

    // MARK: Sockets

    /// Opens a TCP stream or a connected UDP flow and returns the peer address when known.
    public func openSocket(id: UInt32, host: String, port: UInt16, udp: Bool,
                           timeout: TimeInterval) async throws -> String? {
        try Task.checkCancellation()
        guard port != 0, let endpoint = CompanionNetworkPolicy.socketHost(host),
              let remotePort = NWEndpoint.Port(rawValue: port) else { throw CompanionTransportError.invalidURL }
        try admit(id, channel: true)
        let connection = NWConnection(host: endpoint, port: remotePort, using: CompanionNetworkPolicy.parameters(udp: udp))
        let channel = SocketChannel(id: id, udp: udp, connection: connection)
        entries[id] = .socket(channel)
        let limit = CompanionNetworkPolicy.timeout(timeout)
        let peer = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String?, Error>) in
                channel.opening = continuation
                channel.deadline = Task { @MainActor [weak self, weak channel] in
                    try? await Task.sleep(for: .seconds(limit))
                    guard !Task.isCancelled, let self, let channel else { return }
                    self.failOpening(channel, CompanionTransportError.timeout)
                }
                connection.stateUpdateHandler = { @Sendable [weak self, weak channel, weak connection] state in
                    guard let self, let channel else { return }
                    let update = LinkUpdate(state, peer: CompanionNetworkPolicy.peerAddress(connection?.currentPath?.remoteEndpoint))
                    Task { @MainActor in self.linkChanged(update, on: channel) }
                }
                connection.start(queue: queue)
            }
        } onCancel: {
            Task { @MainActor [weak self, weak channel] in
                guard let self, let channel else { return }
                self.failOpening(channel, CancellationError())
            }
        }
        try confirmOpen(channel)
        return peer
    }

    private func linkChanged(_ update: LinkUpdate, on channel: SocketChannel) {
        guard isCurrent(channel.id, channel) else { return }
        switch update {
        case .pending:
            break
        case .ready(let peer):
            guard channel.phase == .opening, let opening = channel.opening else { return }
            channel.opening = nil
            channel.deadline?.cancel()
            channel.deadline = nil
            channel.phase = .established
            opening.resume(returning: peer)
        case .failed(let error):
            // `.waiting` lands here too: Network.framework would retry it, the adapter never does.
            let stage: CompanionNetworkPolicy.Stage = channel.phase == .open ? .receive : .connect
            fail(channel, CompanionNetworkPolicy.transportError(error, stage: stage))
        case .cancelled:
            fail(channel, .internalFailure)
        }
    }

    private func fail(_ channel: SocketChannel, _ error: CompanionTransportError) {
        switch channel.phase {
        case .opening: failOpening(channel, error)
        case .established: channel.earlyFailure = channel.earlyFailure ?? error
        case .open: terminate(channel, .error, error)
        }
    }

    private func failOpening(_ channel: SocketChannel, _ error: Error) {
        guard isCurrent(channel.id, channel), channel.opening != nil else { return }
        entries[channel.id] = nil
        channel.shutdown(failing: error)
    }

    /// Runs in the opener's task right after it resumed, so no callback for this channel can
    /// precede the open call's answer.
    private func confirmOpen(_ channel: SocketChannel) throws {
        guard isCurrent(channel.id, channel) else { throw CancellationError() }
        if let failure = channel.earlyFailure {
            entries[channel.id] = nil
            channel.shutdown(failing: failure)
            throw failure
        }
        channel.phase = .open
        receiveNext(channel)
    }

    private func terminate(_ channel: SocketChannel, _ state: CompanionTransportState, _ error: CompanionTransportError?) {
        guard isCurrent(channel.id, channel) else { return }
        if channel.delivering {
            channel.terminal = channel.terminal ?? (state, error)
            return
        }
        entries[channel.id] = nil
        channel.shutdown(failing: CompanionTransportError.send)
        onState?(channel.id, state, error)
    }

    private func receiveNext(_ channel: SocketChannel) {
        guard isCurrent(channel.id, channel), channel.phase == .open, !channel.receiving else { return }
        channel.receiving = true
        let completion: @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void = {
            [weak self, weak channel] data, context, isComplete, error in
            guard let self, let channel else { return }
            let inbound = CompanionNetworkPolicy.SocketInbound(
                data: data, isComplete: isComplete, hasContext: context != nil, error: error)
            Task { @MainActor in
                guard self.isCurrent(channel.id, channel) else { return }
                channel.delivery = Task { @MainActor in
                    await self.received(inbound, on: channel)
                    channel.delivery = nil
                }
            }
        }
        if channel.udp {
            channel.connection.receiveMessage(completion: completion)
        } else {
            channel.connection.receive(minimumIncompleteLength: 1, maximumLength: CompanionNetworkPolicy.maxChunk,
                                       completion: completion)
        }
    }

    private func received(_ inbound: CompanionNetworkPolicy.SocketInbound, on channel: SocketChannel) async {
        guard isCurrent(channel.id, channel), channel.phase == .open else { return }
        channel.receiving = false
        // The callback may close this channel or cancel everything; each step below re-checks.
        switch CompanionNetworkPolicy.outcome(of: inbound, udp: channel.udp) {
        case .deliver(let data):
            guard await deliver(data, on: channel) else { return }
            receiveNext(channel)
        case .deliverThenClose(let data):
            guard await deliver(data, on: channel) else { return }
            terminate(channel, .disconnected, nil)
        case .close:
            terminate(channel, .disconnected, nil)
        case .skip:
            receiveNext(channel)
        case .fail(let error):
            terminate(channel, .error, error)
        }
    }

    private func deliver(_ data: Data, on channel: SocketChannel) async -> Bool {
        channel.delivering = true
        do { try await onData?(channel.id, data, false) }
        catch {
            channel.delivering = false
            terminate(channel, .error, .receive)
            return false
        }
        channel.delivering = false
        if let terminal = channel.terminal {
            terminate(channel, terminal.0, terminal.1)
            return false
        }
        return isCurrent(channel.id, channel) && !Task.isCancelled
    }

    private func send(_ data: Data, on channel: SocketChannel) async throws -> Int {
        guard channel.phase == .open else { throw CompanionTransportError.notConnected }
        guard channel.sending == nil else { throw CompanionTransportError.send }
        guard data.count <= CompanionNetworkPolicy.maxChunk else { throw CompanionTransportError.limit }
        if data.isEmpty && !channel.udp { return 0 }
        channel.sendSerial &+= 1
        let serial = channel.sendSerial
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
                channel.sending = continuation
                channel.connection.send(content: data, completion: .contentProcessed { @Sendable [weak self, weak channel] error in
                    guard let self, let channel else { return }
                    Task { @MainActor in self.sent(data.count, serial: serial, error: error, on: channel) }
                })
            }
        } onCancel: {
            Task { @MainActor [weak self, weak channel] in
                guard let self, let channel else { return }
                self.abandonSend(serial, on: channel)
            }
        }
    }

    private func sent(_ count: Int, serial: UInt64, error: NWError?, on channel: SocketChannel) {
        guard isCurrent(channel.id, channel), channel.sendSerial == serial, let sending = channel.sending else { return }
        channel.sending = nil
        if let error {
            sending.resume(throwing: CompanionNetworkPolicy.transportError(error, stage: .send))
        } else {
            sending.resume(returning: count)
        }
    }

    /// A send whose caller went away leaves the stream position unknown, so the channel closes.
    private func abandonSend(_ serial: UInt64, on channel: SocketChannel) {
        guard isCurrent(channel.id, channel), channel.sendSerial == serial, channel.sending != nil else { return }
        entries[channel.id] = nil
        channel.shutdown(failing: CancellationError())
    }

    // MARK: WebSockets

    /// Opens a WebSocket and returns only after the server accepted the handshake (`didOpen`).
    public func openWebSocket(id: UInt32, url: URL, headers: [String: String], timeout: TimeInterval) async throws {
        try Task.checkCancellation()
        let target = try CompanionNetworkPolicy.checkedURL(url, schemes: CompanionNetworkPolicy.webSocketSchemes)
        let fields = try CompanionNetworkPolicy.headerFields(headers, forbidden: CompanionNetworkPolicy.forbiddenWebSocketHeaders)
        try admit(id, channel: true)
        let limit = CompanionNetworkPolicy.timeout(timeout)
        let request = CompanionNetworkPolicy.request(url: target, method: "GET", headers: fields, authorization: nil,
                                                     body: nil, timeout: CompanionNetworkPolicy.webSocketIdleTimeout)
        let box = activeSession()
        let task = box.session.webSocketTask(with: request)
        task.maximumMessageSize = CompanionNetworkPolicy.maxChunk
        let channel = WebSocketChannel(id: id, task: task)
        entries[id] = .webSocket(channel)
        box.bridge.register(task, WebSocketRoute { [weak self, weak channel] event in
            guard let self, let channel else { return }
            Task { @MainActor in self.webSocketEvent(event, on: channel) }
        })
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                channel.opening = continuation
                channel.deadline = Task { @MainActor [weak self, weak channel] in
                    try? await Task.sleep(for: .seconds(limit))
                    guard !Task.isCancelled, let self, let channel else { return }
                    self.failOpening(channel, CompanionTransportError.timeout)
                }
                task.resume()
            }
        } onCancel: {
            Task { @MainActor [weak self, weak channel] in
                guard let self, let channel else { return }
                self.failOpening(channel, CancellationError())
            }
        }
        try confirmOpen(channel)
    }

    private func webSocketEvent(_ event: WebSocketEvent, on channel: WebSocketChannel) {
        guard isCurrent(channel.id, channel) else { return }
        switch event {
        case .opened:
            guard channel.phase == .opening, let opening = channel.opening else { return }
            channel.opening = nil
            channel.deadline?.cancel()
            channel.deadline = nil
            channel.phase = .established
            opening.resume()
        case .closed:
            // An outstanding receive drains buffered messages first and then reports the close.
            guard channel.phase != .open || !channel.receiving else { return }
            end(channel, graceful: true, error: .notConnected)
        case .completed(let error, let failure):
            let stage: CompanionNetworkPolicy.Stage = channel.phase == .open ? .receive : .connect
            let graceful = failure == nil && (error == nil || channel.task.closeCode != .invalid)
            end(channel, graceful: graceful,
                error: failure ?? error.map { CompanionNetworkPolicy.transportError($0, stage: stage) } ?? .notConnected)
        }
    }

    /// Ends a WebSocket according to its phase. Before the open call returns, the end is its answer.
    private func end(_ channel: WebSocketChannel, graceful: Bool, error: CompanionTransportError) {
        switch channel.phase {
        case .opening:
            failOpening(channel, graceful ? CompanionTransportError.notConnected : error)
        case .established:
            channel.earlyFailure = channel.earlyFailure ?? (graceful ? .notConnected : error)
        case .open:
            if graceful { terminate(channel, .disconnected, nil) } else { terminate(channel, .error, error) }
        }
    }

    private func failOpening(_ channel: WebSocketChannel, _ error: Error) {
        guard isCurrent(channel.id, channel), channel.opening != nil else { return }
        entries[channel.id] = nil
        channel.shutdown(failing: error)
    }

    private func confirmOpen(_ channel: WebSocketChannel) throws {
        guard isCurrent(channel.id, channel) else { throw CancellationError() }
        if let failure = channel.earlyFailure {
            entries[channel.id] = nil
            channel.shutdown(failing: failure)
            throw failure
        }
        channel.phase = .open
        receiveNext(channel)
    }

    private func terminate(_ channel: WebSocketChannel, _ state: CompanionTransportState, _ error: CompanionTransportError?,
                           code: URLSessionWebSocketTask.CloseCode = .normalClosure) {
        guard isCurrent(channel.id, channel) else { return }
        if channel.delivering {
            channel.terminal = channel.terminal ?? (state, error)
            return
        }
        entries[channel.id] = nil
        channel.shutdown(failing: CompanionTransportError.send, code: code)
        onState?(channel.id, state, error)
    }

    private func receiveNext(_ channel: WebSocketChannel) {
        guard isCurrent(channel.id, channel), channel.phase == .open, !channel.receiving else { return }
        channel.receiving = true
        channel.task.receive { @Sendable [weak self, weak channel] result in
            guard let self, let channel else { return }
            let inbound = WebSocketInbound(result)
            Task { @MainActor in
                guard self.isCurrent(channel.id, channel) else { return }
                channel.delivery = Task { @MainActor in
                    await self.received(inbound, on: channel)
                    channel.delivery = nil
                }
            }
        }
    }

    private func received(_ inbound: WebSocketInbound, on channel: WebSocketChannel) async {
        guard isCurrent(channel.id, channel), channel.phase == .open else { return }
        channel.receiving = false
        switch inbound {
        case .message(let data, let binary):
            // `maximumMessageSize` already fails larger messages; this also bounds text by UTF-8 bytes.
            guard data.count <= CompanionNetworkPolicy.maxChunk else {
                terminate(channel, .error, .limit, code: .messageTooBig)
                return
            }
            channel.delivering = true
            do { try await onData?(channel.id, data, binary) }
            catch {
                channel.delivering = false
                terminate(channel, .error, .receive)
                return
            }
            channel.delivering = false
            if let terminal = channel.terminal {
                terminate(channel, terminal.0, terminal.1)
                return
            }
            receiveNext(channel)
        case .unsupported:
            terminate(channel, .error, .invalidProtocol, code: .unsupportedData)
        case .failure(let error):
            if channel.task.closeCode != .invalid {
                terminate(channel, .disconnected, nil)
            } else {
                terminate(channel, .error, CompanionNetworkPolicy.transportError(error, stage: .receive))
            }
        }
    }

    private func send(_ data: Data, binary: Bool, on channel: WebSocketChannel) async throws -> Int {
        guard channel.phase == .open else { throw CompanionTransportError.notConnected }
        guard channel.sending == nil else { throw CompanionTransportError.send }
        guard data.count <= CompanionNetworkPolicy.maxChunk else { throw CompanionTransportError.limit }
        let message: URLSessionWebSocketTask.Message
        if binary {
            message = .data(data)
        } else {
            guard let text = CompanionNetworkPolicy.text(data) else { throw CompanionTransportError.invalidProtocol }
            message = .string(text)
        }
        channel.sendSerial &+= 1
        let serial = channel.sendSerial
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
                channel.sending = continuation
                channel.task.send(message) { @Sendable [weak self, weak channel] error in
                    guard let self, let channel else { return }
                    Task { @MainActor in self.sent(data.count, serial: serial, error: error, on: channel) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self, weak channel] in
                guard let self, let channel else { return }
                self.abandonSend(serial, on: channel)
            }
        }
    }

    private func sent(_ count: Int, serial: UInt64, error: Error?, on channel: WebSocketChannel) {
        guard isCurrent(channel.id, channel), channel.sendSerial == serial, let sending = channel.sending else { return }
        channel.sending = nil
        if let error {
            sending.resume(throwing: CompanionNetworkPolicy.transportError(error, stage: .send))
        } else {
            sending.resume(returning: count)
        }
    }

    private func abandonSend(_ serial: UInt64, on channel: WebSocketChannel) {
        guard isCurrent(channel.id, channel), channel.sendSerial == serial, channel.sending != nil else { return }
        entries[channel.id] = nil
        channel.shutdown(failing: CancellationError())
    }

    // MARK: HTTP

    /// Performs one request with a bounded body. Every redirect hop is revalidated before it is followed.
    public func http(method: String, url: URL, headers: [String: String], body: Data,
                     timeout: TimeInterval, requestID: UInt32) async throws -> CompanionHTTPResult {
        try Task.checkCancellation()
        let verb = try CompanionNetworkPolicy.httpMethod(method)
        let target = try CompanionNetworkPolicy.checkedURL(url, schemes: CompanionNetworkPolicy.httpSchemes)
        var fields = try CompanionNetworkPolicy.headerFields(headers, forbidden: CompanionNetworkPolicy.forbiddenHTTPHeaders)
        guard body.count <= CompanionNetworkPolicy.maxBodyBytes else { throw CompanionTransportError.limit }
        guard body.isEmpty || (verb != "GET" && verb != "HEAD") else { throw CompanionTransportError.invalidProtocol }
        try admit(requestID, channel: false)
        let limit = CompanionNetworkPolicy.timeout(timeout)
        let authorization = fields.first { $0.lowercasedName == "authorization" }?.value
        fields.removeAll { $0.lowercasedName == "authorization" }
        let request = CompanionNetworkPolicy.request(url: target, method: verb, headers: fields, authorization: authorization,
                                                     body: body.isEmpty ? nil : body, timeout: limit)
        let box = activeSession()
        let task = box.session.dataTask(with: request)
        let exchange = HTTPExchange(id: requestID, task: task)
        entries[requestID] = .http(exchange)
        box.bridge.register(task, HTTPRoute(url: target, request: request, method: verb, headers: fields,
                                            authorization: authorization, body: body) { [weak self, weak exchange] outcome in
            guard let self, let exchange else { return }
            Task { @MainActor in self.finish(exchange, outcome.mapError { $0 as Error }) }
        })
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CompanionHTTPResult, Error>) in
                exchange.continuation = continuation
                exchange.deadline = Task { @MainActor [weak self, weak exchange] in
                    try? await Task.sleep(for: .seconds(limit))
                    guard !Task.isCancelled, let self, let exchange else { return }
                    self.finish(exchange, .failure(CompanionTransportError.timeout))
                }
                task.resume()
            }
        } onCancel: {
            Task { @MainActor [weak self, weak exchange] in
                guard let self, let exchange else { return }
                self.finish(exchange, .failure(CancellationError()))
            }
        }
    }

    private func finish(_ exchange: HTTPExchange, _ outcome: Result<CompanionHTTPResult, Error>) {
        guard isCurrent(exchange.id, exchange), exchange.continuation != nil else { return }
        entries[exchange.id] = nil
        exchange.shutdown(with: outcome)
    }

    // MARK: Shared

    private func admit(_ id: UInt32, channel: Bool) throws {
        guard entries[id] == nil else { throw CompanionTransportError.invalidConnection }
        let channels = entries.values.filter(\.isChannel).count
        let full = channel ? channels >= CompanionNetworkPolicy.maxChannels
                           : entries.count - channels >= CompanionNetworkPolicy.maxRequests
        if full { throw CompanionTransportError.limit }
    }

    private func isCurrent(_ id: UInt32, _ object: AnyObject) -> Bool {
        entries[id]?.object === object
    }

    private func activeSession() -> SessionBox {
        if let sessionBox { return sessionBox }
        let box = SessionBox(configuration: configuration)
        sessionBox = box
        return box
    }

    private static func stop(_ entry: Entry) {
        switch entry {
        case .socket(let channel): channel.shutdown(failing: CancellationError())
        case .webSocket(let channel): channel.shutdown(failing: CancellationError())
        case .http(let exchange): exchange.shutdown(with: .failure(CancellationError()))
        }
    }
}

// MARK: - Operations

private enum ChannelPhase {
    /// The transport is opening and the open call is suspended.
    case opening
    /// The transport opened and the open call is resuming; failures are held for its answer.
    case established
    /// The open call returned; data and state callbacks may run.
    case open
}

private enum Entry {
    case socket(SocketChannel)
    case webSocket(WebSocketChannel)
    case http(HTTPExchange)

    var object: AnyObject {
        switch self {
        case .socket(let channel): return channel
        case .webSocket(let channel): return channel
        case .http(let exchange): return exchange
        }
    }

    var isChannel: Bool {
        if case .http = self { return false }
        return true
    }
}

/// Cancels a transport when its owner goes away, e.g. if the adapter is dropped without `cancelAll()`.
/// Kept outside the main-actor classes because a deinit may run on any thread.
private final class CancelOnRelease {
    private let cancel: @Sendable () -> Void
    init(_ cancel: @escaping @Sendable () -> Void) { self.cancel = cancel }
    deinit { cancel() }
}

@MainActor
private final class SocketChannel {
    let id: UInt32
    let udp: Bool
    let connection: NWConnection
    var phase = ChannelPhase.opening
    var opening: CheckedContinuation<String?, Error>?
    var sending: CheckedContinuation<Int, Error>?
    var sendSerial: UInt64 = 0
    var receiving = false
    var delivering = false
    var delivery: Task<Void, Never>?
    var terminal: (CompanionTransportState, CompanionTransportError?)?
    var earlyFailure: CompanionTransportError?
    var deadline: Task<Void, Never>?
    private let cleanup: CancelOnRelease

    init(id: UInt32, udp: Bool, connection: NWConnection) {
        self.id = id
        self.udp = udp
        self.connection = connection
        cleanup = CancelOnRelease { connection.cancel() }
    }

    /// Cancels the connection and fails any call still waiting on it.
    func shutdown(failing error: Error) {
        delivery?.cancel(); delivery = nil
        deadline?.cancel()
        deadline = nil
        connection.cancel()
        let waiting = (opening, sending)
        opening = nil
        sending = nil
        waiting.0?.resume(throwing: error)
        waiting.1?.resume(throwing: error)
    }
}

@MainActor
private final class WebSocketChannel {
    let id: UInt32
    let task: URLSessionWebSocketTask
    var phase = ChannelPhase.opening
    var opening: CheckedContinuation<Void, Error>?
    var sending: CheckedContinuation<Int, Error>?
    var sendSerial: UInt64 = 0
    var receiving = false
    var delivering = false
    var delivery: Task<Void, Never>?
    var terminal: (CompanionTransportState, CompanionTransportError?)?
    var earlyFailure: CompanionTransportError?
    var deadline: Task<Void, Never>?
    private let cleanup: CancelOnRelease

    init(id: UInt32, task: URLSessionWebSocketTask) {
        self.id = id
        self.task = task
        cleanup = CancelOnRelease { task.cancel() }
    }

    func shutdown(failing error: Error, code: URLSessionWebSocketTask.CloseCode = .normalClosure) {
        delivery?.cancel(); delivery = nil
        deadline?.cancel()
        deadline = nil
        task.cancel(with: code, reason: nil)
        let waiting = (opening, sending)
        opening = nil
        sending = nil
        waiting.0?.resume(throwing: error)
        waiting.1?.resume(throwing: error)
    }
}

@MainActor
private final class HTTPExchange {
    let id: UInt32
    let task: URLSessionDataTask
    var continuation: CheckedContinuation<CompanionHTTPResult, Error>?
    var deadline: Task<Void, Never>?
    private let cleanup: CancelOnRelease

    init(id: UInt32, task: URLSessionDataTask) {
        self.id = id
        self.task = task
        cleanup = CancelOnRelease { task.cancel() }
    }

    func shutdown(with outcome: Result<CompanionHTTPResult, Error>) {
        deadline?.cancel()
        deadline = nil
        if case .failure = outcome { task.cancel() }
        let waiting = continuation
        continuation = nil
        waiting?.resume(with: outcome)
    }
}

private enum LinkUpdate: Sendable {
    case pending
    case ready(peer: String?)
    case failed(NWError)
    case cancelled

    init(_ state: NWConnection.State, peer: @autoclosure () -> String?) {
        switch state {
        case .ready: self = .ready(peer: peer())
        case .waiting(let error), .failed(let error): self = .failed(error)
        case .cancelled: self = .cancelled
        case .setup, .preparing: self = .pending
        @unknown default: self = .pending
        }
    }
}

private enum WebSocketEvent: Sendable {
    case opened
    case closed
    /// The task finished: the transport error, and any failure the delegate recorded first.
    case completed(Error?, CompanionTransportError?)
}

private enum WebSocketInbound: Sendable {
    case message(Data, binary: Bool)
    case unsupported
    case failure(Error)

    init(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        switch result {
        case .success(.data(let data)): self = .message(data, binary: true)
        case .success(.string(let text)): self = .message(Data(text.utf8), binary: false)
        case .success: self = .unsupported
        case .failure(let error): self = .failure(error)
        }
    }
}

// MARK: - URLSession

private final class SessionBox {
    let session: URLSession
    let bridge: SessionBridge

    init(configuration: URLSessionConfiguration) {
        let bridge = SessionBridge()
        let queue = OperationQueue()
        queue.name = "FlipperLab.CompanionNetworking.URLSession"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        self.bridge = bridge
        session = URLSession(configuration: configuration, delegate: bridge, delegateQueue: queue)
    }

    deinit { session.invalidateAndCancel() }
}

/// Session delegate. Routes are registered on the main actor before `resume()` and afterwards used
/// only on the session's serial delegate queue.
private final class SessionBridge: NSObject, URLSessionDataDelegate, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [Int: AnyObject] = [:]

    func register(_ task: URLSessionTask, _ route: AnyObject) {
        lock.lock()
        routes[task.taskIdentifier] = route
        lock.unlock()
    }

    private func lookup(_ task: URLSessionTask, remove: Bool = false) -> AnyObject? {
        lock.lock()
        defer { lock.unlock() }
        return remove ? routes.removeValue(forKey: task.taskIdentifier) : routes[task.taskIdentifier]
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        lock.lock()
        routes.removeAll()
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // System trust evaluation only. No stored, ambient or custom credential is ever offered.
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.rejectProtectionSpace, nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let route = lookup(task)
        if let http = route as? HTTPRoute, let next = http.redirect(after: response, proposed: request) {
            completionHandler(next)
            return
        }
        // A refused hop fails the task; WebSocket handshakes never follow redirects.
        (route as? WebSocketRoute)?.reject(.invalidProtocol)
        task.cancel()
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let route = lookup(dataTask) as? HTTPRoute, route.accept(response) else {
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Stop at the first byte past the limit instead of draining the rest of the body.
        guard let route = lookup(dataTask) as? HTTPRoute, route.append(data) else {
            dataTask.cancel()
            return
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse,
                    completionHandler: @escaping (CachedURLResponse?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol negotiated: String?) {
        (lookup(webSocketTask) as? WebSocketRoute)?.notify(.opened)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        (lookup(webSocketTask) as? WebSocketRoute)?.notify(.closed)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let route = lookup(task, remove: true) else { return }
        if let http = route as? HTTPRoute {
            http.complete(error)
        } else if let socket = route as? WebSocketRoute {
            socket.complete(error)
        }
    }
}

/// One HTTP request's delegate state, confined to the session's serial delegate queue.
private final class HTTPRoute: @unchecked Sendable {
    private let request: URLRequest
    private let headers: [CompanionNetworkPolicy.HeaderField]
    private let authorization: String?
    private let body: Data
    private let completion: @Sendable (Result<CompanionHTTPResult, CompanionTransportError>) -> Void
    private var chain: CompanionRedirect
    private var response: (status: Int, headers: [String: String])?
    private var received = Data()
    private var failure: CompanionTransportError?

    init(url: URL, request: URLRequest, method: String, headers: [CompanionNetworkPolicy.HeaderField],
         authorization: String?, body: Data,
         completion: @escaping @Sendable (Result<CompanionHTTPResult, CompanionTransportError>) -> Void) {
        self.request = request
        self.headers = headers
        self.authorization = authorization
        self.body = body
        self.completion = completion
        chain = CompanionRedirect(url: url, method: method)
    }

    /// Returns false to cancel. Checks the declared length and headers before any body byte arrives.
    func accept(_ response: URLResponse) -> Bool {
        guard failure == nil else { return false }
        guard self.response == nil, let http = response as? HTTPURLResponse else { return fail(.invalidProtocol) }
        if chain.method != "HEAD" && http.expectedContentLength > Int64(CompanionNetworkPolicy.maxBodyBytes) {
            return fail(.limit)
        }
        do {
            let headers = try CompanionNetworkPolicy.responseHeaders(http)
            self.response = (http.statusCode, headers)
            return true
        } catch {
            return fail(error as? CompanionTransportError ?? .receive)
        }
    }

    /// Returns false to cancel as soon as the body would pass the limit.
    func append(_ data: Data) -> Bool {
        guard failure == nil else { return false }
        guard received.count + data.count <= CompanionNetworkPolicy.maxBodyBytes else { return fail(.limit) }
        received.append(data)
        return true
    }

    /// The next hop rebuilt from the app's own headers, or nil after recording why it was refused.
    func redirect(after response: HTTPURLResponse, proposed: URLRequest) -> URLRequest? {
        guard failure == nil else { return nil }
        do {
            chain = try chain.following(status: response.statusCode, to: proposed.url)
        } catch {
            _ = fail(error as? CompanionTransportError ?? .invalidURL)
            return nil
        }
        let kept = chain.keepsBody ? headers : headers.filter { !CompanionNetworkPolicy.bodyHeaders.contains($0.lowercasedName) }
        return CompanionNetworkPolicy.request(url: chain.url, method: chain.method, headers: kept,
                                              authorization: chain.keepsAuthorization ? authorization : nil,
                                              body: chain.keepsBody && !body.isEmpty ? body : nil,
                                              timeout: request.timeoutInterval)
    }

    func complete(_ error: Error?) {
        let outcome: Result<CompanionHTTPResult, CompanionTransportError>
        if let failure {
            outcome = .failure(failure)
        } else if let error {
            outcome = .failure(CompanionNetworkPolicy.transportError(error, stage: response == nil ? .connect : .receive))
        } else if let response {
            outcome = .success(CompanionHTTPResult(status: response.status, headers: response.headers, body: received))
        } else {
            outcome = .failure(.receive)
        }
        received = Data()
        completion(outcome)
    }

    private func fail(_ error: CompanionTransportError) -> Bool {
        failure = failure ?? error
        received = Data()
        return false
    }
}

/// One WebSocket task's delegate state, confined to the session's serial delegate queue.
private final class WebSocketRoute: @unchecked Sendable {
    private let events: @Sendable (WebSocketEvent) -> Void
    private var failure: CompanionTransportError?

    init(_ events: @escaping @Sendable (WebSocketEvent) -> Void) {
        self.events = events
    }

    func notify(_ event: WebSocketEvent) { events(event) }
    func reject(_ error: CompanionTransportError) { failure = failure ?? error }
    func complete(_ error: Error?) { events(.completed(error, failure)) }
}

// MARK: - Rules

/// Limits, validation and error mapping. Pure and nonisolated, so the delegate queue and tests share them.
enum CompanionNetworkPolicy {
    static let maxChannels = 4
    static let maxRequests = 2
    static let maxChunk = 512
    static let maxBodyBytes = 2 * 1024 * 1024
    static let maxHeaderBytes = 8192
    static let maxRedirects = 5
    /// Mirrors the firmware's `NETWORK_MAX_URL_LENGTH` and `NETWORK_MAX_HOST_LENGTH`.
    static let maxURLBytes = 2048
    static let maxHostBytes = 255
    /// The firmware sends 0 for "default".
    static let defaultTimeout: TimeInterval = 30
    static let maxTimeout: TimeInterval = 300
    /// URLSession may apply a request's timeout as an idle timer, so an open WebSocket gets a long
    /// one. The handshake deadline is enforced separately.
    static let webSocketIdleTimeout: TimeInterval = 3600

    static let httpSchemes: Set<String> = ["http", "https"]
    static let webSocketSchemes: Set<String> = ["ws", "wss"]
    static let httpMethods: Set<String> = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"]
    /// Lowercased names that URLSession owns or that would carry ambient state between requests.
    static let forbiddenHTTPHeaders: Set<String> = [
        "connection", "content-length", "cookie", "cookie2", "expect", "host", "keep-alive",
        "proxy-authorization", "proxy-connection", "te", "trailer", "transfer-encoding", "upgrade",
    ]
    static let forbiddenWebSocketHeaders = forbiddenHTTPHeaders.union([
        "sec-websocket-accept", "sec-websocket-extensions", "sec-websocket-key", "sec-websocket-version",
    ])
    /// Fetch's request-body header names, dropped when a redirect turns the request into a GET.
    static let bodyHeaders: Set<String> = ["content-encoding", "content-language", "content-location", "content-type"]

    enum Stage { case connect, send, receive }

    struct HeaderField: Equatable, Sendable {
        let name: String
        let value: String
        var lowercasedName: String { name.lowercased() }
    }

    /// One Network.framework receive completion.
    struct SocketInbound: Sendable {
        var data: Data?
        var isComplete: Bool
        var hasContext: Bool
        var error: NWError?
    }

    enum SocketOutcome: Equatable {
        case deliver(Data)
        case deliverThenClose(Data)
        case close
        case skip
        case fail(CompanionTransportError)
    }

    private static let hostScalars = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._:%")
    private static let tokenScalars = CharacterSet(
        charactersIn: "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    /// A copy of the caller's configuration without cookies, credentials, cache, extra headers,
    /// proxies or connectivity waiting. Background configurations fall back to ephemeral.
    static func hardened(_ source: URLSessionConfiguration) -> URLSessionConfiguration {
        let base = source.identifier == nil ? source : URLSessionConfiguration.ephemeral
        let configuration = base.copy() as! URLSessionConfiguration
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpAdditionalHeaders = nil
        configuration.connectionProxyDictionary = [:]
        configuration.waitsForConnectivity = false
        return configuration
    }

    static func timeout(_ requested: TimeInterval) -> TimeInterval {
        requested > 0 ? min(requested, maxTimeout) : defaultTimeout
    }

    static func parameters(udp: Bool) -> NWParameters {
        let parameters: NWParameters
        if udp {
            parameters = NWParameters(dtls: nil, udp: NWProtocolUDP.Options())
        } else {
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            parameters = NWParameters(tls: nil, tcp: tcp)
        }
        parameters.preferNoProxies = true
        return parameters
    }

    /// An IP literal (IPv6 optionally in brackets) or an ASCII host name; nothing else.
    static func socketHost(_ host: String) -> NWEndpoint.Host? {
        var name = Substring(host)
        let bracketed = name.hasPrefix("[") && name.hasSuffix("]")
        if bracketed { name = name.dropFirst().dropLast() }
        guard !name.isEmpty, name.utf8.count <= maxHostBytes,
              name.unicodeScalars.allSatisfy({ hostScalars.contains($0) }) else { return nil }
        let text = String(name)
        if !bracketed, let address = IPv4Address(text) { return .ipv4(address) }
        if let address = IPv6Address(text) { return .ipv6(address) }
        guard !bracketed, !text.contains(":"), !text.contains("%"),
              !text.hasPrefix("-"), !text.hasPrefix(".") else { return nil }
        return .name(text, nil)
    }

    /// Rejects other schemes, user info, fragments (unless dropped), port 0, control characters and long URLs.
    static func checkedURL(_ url: URL, schemes: Set<String>, maxBytes: Int = CompanionNetworkPolicy.maxURLBytes,
                           dropFragment: Bool = false) throws -> URL {
        guard var parts = URLComponents(url: url.absoluteURL, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), schemes.contains(scheme),
              let host = parts.host, !host.isEmpty,
              host.unicodeScalars.allSatisfy({ hostScalars.contains($0) || $0 == "[" || $0 == "]" }),
              parts.user == nil, parts.password == nil,
              parts.port.map({ (1...65_535).contains($0) }) ?? true
        else { throw CompanionTransportError.invalidURL }
        if parts.fragment != nil {
            guard dropFragment else { throw CompanionTransportError.invalidURL }
            parts.fragment = nil
        }
        parts.scheme = scheme
        guard let checked = parts.url, checked.absoluteString.utf8.count <= maxBytes,
              checked.absoluteString.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) })
        else { throw CompanionTransportError.invalidURL }
        return checked
    }

    static func httpMethod(_ method: String) throws -> String {
        guard httpMethods.contains(method) else { throw CompanionTransportError.invalidProtocol }
        return method
    }

    /// Token names, values without control characters, no reserved or repeated names, and at most
    /// `maxHeaderBytes` counted as UTF-8 `Name: Value\r\n` lines.
    static func headerFields(_ headers: [String: String], forbidden: Set<String>) throws -> [HeaderField] {
        var seen = Set<String>()
        var total = 0
        var fields: [HeaderField] = []
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            let key = name.lowercased()
            guard isToken(name), isFieldValue(value), !forbidden.contains(key), seen.insert(key).inserted else {
                throw CompanionTransportError.invalidProtocol
            }
            total += name.utf8.count + value.utf8.count + 4
            guard total <= maxHeaderBytes else { throw CompanionTransportError.limit }
            fields.append(HeaderField(name: name, value: value))
        }
        return fields
    }

    /// Response headers under the same size rule, so they can be relayed as `Name: Value\r\n` lines.
    static func responseHeaders(_ response: HTTPURLResponse) throws -> [String: String] {
        var headers: [String: String] = [:]
        var total = 0
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String, let text = value as? String,
                  isToken(name), isFieldValue(text) else { throw CompanionTransportError.receive }
            total += name.utf8.count + text.utf8.count + 4
            guard total <= maxHeaderBytes else { throw CompanionTransportError.limit }
            headers[name] = text
        }
        return headers
    }

    static func request(url: URL, method: String, headers: [HeaderField], authorization: String?,
                        body: Data?, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        for field in headers { request.setValue(field.value, forHTTPHeaderField: field.name) }
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        request.httpBody = body
        return request
    }

    /// The payload as text only if it is valid UTF-8 that round-trips byte for byte.
    static func text(_ data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        return text.utf8.elementsEqual(data) ? text : nil
    }

    /// Classifies one receive completion. Streams keep chunk order; datagrams are never split.
    static func outcome(of inbound: SocketInbound, udp: Bool) -> SocketOutcome {
        if let error = inbound.error { return .fail(transportError(error, stage: .receive)) }
        let data = inbound.data ?? Data()
        if udp {
            // A zero-length datagram arrives complete, with a context but possibly no content.
            guard inbound.isComplete, inbound.data != nil || inbound.hasContext else { return .fail(.receive) }
            return data.count <= maxChunk ? .deliver(data) : .skip
        }
        guard data.count <= maxChunk else { return .fail(.receive) }
        if inbound.isComplete { return data.isEmpty ? .close : .deliverThenClose(data) }
        return data.isEmpty ? .fail(.receive) : .deliver(data)
    }

    static func peerAddress(_ endpoint: NWEndpoint?) -> String? {
        guard case .hostPort(let host, _)? = endpoint else { return nil }
        switch host {
        case .ipv4(let address): return presentation(address.rawValue, family: AF_INET)
        case .ipv6(let address): return presentation(address.rawValue, family: AF_INET6)
        default: return nil
        }
    }

    private static func presentation(_ raw: Data, family: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let converted = raw.withUnsafeBytes { bytes -> Bool in
            guard let base = bytes.baseAddress else { return false }
            return inet_ntop(family, base, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil
        }
        guard converted, let end = buffer.firstIndex(of: 0) else { return nil }
        return String(decoding: buffer[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func transportError(_ error: Error, stage: Stage) -> CompanionTransportError {
        if let error = error as? CompanionTransportError { return error }
        if let error = error as? NWError { return transportError(error, stage: stage) }
        let nsError = error as NSError
        switch nsError.domain {
        case NSURLErrorDomain: return urlError(nsError.code, stage: stage)
        case NSPOSIXErrorDomain: return posixError(Int32(truncatingIfNeeded: nsError.code), stage: stage)
        default: return fallback(stage)
        }
    }

    static func transportError(_ error: NWError, stage: Stage) -> CompanionTransportError {
        switch error {
        case .dns: return .dns
        case .tls: return .tls
        case .posix(let code): return posixError(code.rawValue, stage: stage)
        @unknown default: return fallback(stage)
        }
    }

    private static func posixError(_ code: Int32, stage: Stage) -> CompanionTransportError {
        switch code {
        case ECONNREFUSED: return .refused
        case ETIMEDOUT: return .timeout
        case ENETDOWN, ENETUNREACH, EHOSTDOWN, EHOSTUNREACH, EADDRNOTAVAIL: return .unreachable
        case EMSGSIZE: return .limit
        case ECONNRESET, ECONNABORTED: return stage == .connect ? .refused : fallback(stage)
        default: return fallback(stage)
        }
    }

    private static func urlError(_ code: Int, stage: Stage) -> CompanionTransportError {
        switch code {
        case NSURLErrorTimedOut: return .timeout
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return .dns
        case NSURLErrorCannotConnectToHost: return .refused
        case NSURLErrorNotConnectedToInternet, NSURLErrorInternationalRoamingOff, NSURLErrorCallIsActive,
             NSURLErrorDataNotAllowed: return .unreachable
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired, NSURLErrorAppTransportSecurityRequiresSecureConnection: return .tls
        case NSURLErrorBadURL, NSURLErrorUnsupportedURL, NSURLErrorRedirectToNonExistentLocation: return .invalidURL
        case NSURLErrorHTTPTooManyRedirects, NSURLErrorDataLengthExceedsMaximum: return .limit
        case NSURLErrorBadServerResponse, NSURLErrorCannotParseResponse:
            return stage == .connect ? .invalidProtocol : .receive
        default: return fallback(stage)
        }
    }

    private static func fallback(_ stage: Stage) -> CompanionTransportError {
        switch stage {
        case .connect: return .internalFailure
        case .send: return .send
        case .receive: return .receive
        }
    }

    private static func isToken(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { tokenScalars.contains($0) }
    }

    private static func isFieldValue(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            scalar == "\t" || (scalar.value >= 0x20 && scalar.value != 0x7F && !(0x80...0x9F).contains(scalar.value))
        }
    }
}

/// Redirect state of one HTTP request. Each hop is revalidated; credentials never return once a hop
/// leaves the original origin.
struct CompanionRedirect: Equatable {
    private(set) var url: URL
    private(set) var method: String
    private(set) var hops = 0
    private(set) var keepsAuthorization = true
    private(set) var keepsBody = true

    init(url: URL, method: String) {
        self.url = url
        self.method = method
    }

    func following(status: Int, to target: URL?) throws -> CompanionRedirect {
        guard hops < CompanionNetworkPolicy.maxRedirects else { throw CompanionTransportError.limit }
        guard let target else { throw CompanionTransportError.invalidURL }
        var next = self
        // A Location header is bounded by the header budget, not by the firmware's URL field.
        next.url = try CompanionNetworkPolicy.checkedURL(target, schemes: CompanionNetworkPolicy.httpSchemes,
                                                         maxBytes: CompanionNetworkPolicy.maxHeaderBytes, dropFragment: true)
        next.hops += 1
        let sameOrigin = Self.origin(of: url).map { $0 == Self.origin(of: next.url) } ?? false
        next.keepsAuthorization = keepsAuthorization && sameOrigin
        // Fetch: 301/302 turn POST into GET; 303 turns everything except GET/HEAD into GET.
        if ((status == 301 || status == 302) && method == "POST") || (status == 303 && method != "GET" && method != "HEAD") {
            next.method = "GET"
            next.keepsBody = false
        }
        return next
    }

    static func origin(of url: URL) -> String? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased() else { return nil }
        return "\(scheme)://\(host):\(parts.port ?? (scheme == "https" ? 443 : 80))"
    }
}
