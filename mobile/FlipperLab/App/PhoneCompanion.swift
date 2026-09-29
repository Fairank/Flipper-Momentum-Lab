import Foundation
import Observation
import CoreLocation
import FlipperCore

/// One foreground BLE session. Location and internet are separately opted into;
/// callbacks and suspended operations may never cross a session or toggle change.
@MainActor @Observable
final class PhoneCompanion {
    private(set) var connected = false
    private(set) var locationEnabled = false
    private(set) var networkEnabled = false
    private(set) var locationStatus = "定位共享已关闭"
    private(set) var networkStatus = "网络共享已关闭"
    private(set) var lastEndpoint: String?
    private(set) var receivedBytes = 0
    private(set) var sentBytes = 0
    private(set) var connectionCount = 0
    @ObservationIgnored private weak var device: FlipperDevice?
    @ObservationIgnored private let location = PhoneLocationProvider()
    @ObservationIgnored private let network = CompanionNetworking()
    @ObservationIgnored private var networkEpoch = UUID()
    @ObservationIgnored private var locationEpoch = UUID()
    @ObservationIgnored private var operations: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var occupied: [UInt32: UUID] = [:]
    @ObservationIgnored private var connections: Set<UInt32> = []
    @ObservationIgnored private var opening: Set<UInt32> = []
    @ObservationIgnored private var httpDeliveries: Set<UInt32> = []
    @ObservationIgnored private var stateEvents: [UInt32: (CompanionConnectionState, CompanionNetworkErrorCode)] = [:]
    @ObservationIgnored private var stateDelivery: Task<Void, Never>?
    @ObservationIgnored private var stateSendingID: UInt32?
    @ObservationIgnored private var gpsRequests: [UUID: Task<Void, Never>] = [:]

    func attach(_ device: FlipperDevice) { self.device = device }
    func beginSession() {
        connected = true
        setLocationEnabled(false)
        setNetworkEnabled(false)
    }

    func endSession() {
        suspendSharing()
        connected = false
    }

    func suspendSharing() {
        setLocationEnabled(false)
        setNetworkEnabled(false)
    }

    func setLocationEnabled(_ enabled: Bool) {
        locationEpoch = UUID()
        for task in gpsRequests.values { task.cancel() }
        gpsRequests.removeAll()
        locationEnabled = enabled && connected && device?.ready == true
        let epoch = locationEpoch
        let session = device?.companionSession
        location.onStatus = { [weak self] text in
            guard let self, self.locationEpoch == epoch else { return }
            self.locationStatus = text
        }
        location.onLocation = { [weak self] fix, status in
            guard let self, let device = self.device, let session,
                  self.locationEpoch == epoch, device.companionSession == session else { return }
            let frame: Data
            if let fix, status == 0, self.locationEnabled {
                do {
                    let value = try CompanionLocation(latitude: fix.coordinate.latitude,
                        longitude: fix.coordinate.longitude, altitude: fix.altitude,
                        speed: fix.speed, course: fix.course, horizontalAccuracy: fix.horizontalAccuracy)
                    frame = CompanionResponse.location(value)
                    self.locationStatus = "正在共享定位 · 精度约 \(Int(min(fix.horizontalAccuracy.rounded(), 999_999))) 米"
                } catch { frame = CompanionResponse.locationUnavailable(.unknown) }
            } else {
                frame = CompanionResponse.locationUnavailable(CompanionGPSStatus(rawValue: status) ?? .unknown)
            }
            try? await device.sendCompanion(frame, session: session)
        }
        location.setSharing(locationEnabled)
        if !locationEnabled { device?.discardCompanion(tags: [87]) }
    }

    func setNetworkEnabled(_ enabled: Bool) {
        networkEpoch = UUID()
        for task in operations.values { task.cancel() }
        operations.removeAll(); occupied.removeAll(); connections.removeAll()
        opening.removeAll(); httpDeliveries.removeAll(); stateSendingID = nil
        stateEvents.removeAll(); stateDelivery?.cancel(); stateDelivery = nil
        network.onData = nil; network.onState = nil
        network.cancelAll()
        connectionCount = 0
        networkEnabled = enabled && connected && device?.ready == true
        networkStatus = networkEnabled ? "网络共享已就绪，等待设备请求" : "网络共享已关闭"
        device?.discardCompanion(tags: [77, 79, 80, 82, 83, 89])
        guard networkEnabled, let session = device?.companionSession else { return }
        receivedBytes = 0; sentBytes = 0; lastEndpoint = nil
        let epoch = networkEpoch
        network.onData = { [weak self] id, data, binary in
            guard let self, self.networkEnabled, self.networkEpoch == epoch,
                  let device = self.device, device.companionSession == session else { return }
            do {
                // A full BLE queue must not let incoming bytes overtake the
                // response announcing this channel. The transport awaits us.
                while self.opening.contains(id) {
                    try self.check(epoch: epoch, session: session)
                    try await Task.sleep(for: .milliseconds(20))
                }
                try self.check(epoch: epoch, session: session)
                try await device.sendCompanion(CompanionResponse.received(connectionID: id, data: data, binary: binary), session: session)
                guard self.networkEpoch == epoch else { return }
                self.receivedBytes += data.count
            } catch {
                if self.networkEpoch == epoch, !Task.isCancelled { self.networkStatus = "蓝牙数据传输未完成，连接已关闭" }
                // The transport still owns the exact channel object; it closes
                // that object, never a new operation that happens to reuse id.
                throw error
            }
        }
        network.onState = { [weak self] id, state, error in
            guard let self, self.networkEnabled, self.networkEpoch == epoch else { return }
            if state == .connected { return } // open request has its own ConnectResponse
            self.connections.remove(id); self.connectionCount = self.connections.count
            let code = error.map(Self.networkError) ?? .noError
            self.stateEvents[id] = (state == .error ? .error : .disconnected, code)
            self.deliverStateEvents(epoch: epoch, session: session)
        }
    }

    private func deliverStateEvents(epoch: UUID, session: UUID) {
        guard stateDelivery == nil else { return }
        stateDelivery = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.networkEpoch == epoch, let (id, state) = self.stateEvents.first {
                if self.opening.contains(id) {
                    try? await Task.sleep(for: .milliseconds(20))
                    continue
                }
                self.stateEvents.removeValue(forKey: id)
                self.stateSendingID = id
                if let frame = try? CompanionResponse.stateChanged(connectionID: id, state: state.0, error: state.1) {
                    try? await self.device?.sendCompanion(frame, session: session)
                }
            }
            if self.networkEpoch == epoch { self.stateDelivery = nil; self.stateSendingID = nil }
        }
    }

    func accept(_ request: CompanionRequest) throws {
        guard connected, let device, device.ready else { throw RPCError.disconnected }
        let session = device.companionSession
        switch request {
        case .requestGPSLocation, .startGPSStream:
            guard gpsRequests.count < 4 else { throw RPCError.busy }
            let id = UUID(), epoch = locationEpoch
            gpsRequests[id] = Task { [weak self] in
                guard let self, self.locationEpoch == epoch, !Task.isCancelled else { return }
                defer { self.gpsRequests.removeValue(forKey: id) }
                switch request {
                case .requestGPSLocation: await self.location.requestOnce()
                case .startGPSStream(let value): await self.location.startStream(frequency: UInt32(value.updatesPerSecond))
                default: break
                }
            }
        case .stopGPSStream:
            // Invalidate a pending stream-start check while retaining any
            // independent one-shot location request.
            location.stopStream()
        default:
            guard let id = request.connectionID, operations.count < 16 else { throw RPCError.busy }
            let token = UUID(), epoch = networkEpoch
            if case .close = request, let active = occupied.removeValue(forKey: id) {
                operations[active]?.cancel()
            }
            let duplicate = occupied[id] != nil
            if !duplicate { occupied[id] = token }
            operations[token] = Task { [weak self] in
                guard let self, self.networkEpoch == epoch, !Task.isCancelled else { return }
                defer {
                    self.operations.removeValue(forKey: token)
                    if self.occupied[id] == token { self.occupied.removeValue(forKey: id) }
                }
                do {
                    if !self.networkEnabled {
                        try await device.sendCompanion(self.failure(request, error: .notConnected), session: session)
                    } else if duplicate {
                        try await device.sendCompanion(self.failure(request, error: .invalidConnection), session: session)
                    } else {
                        try await self.perform(request, epoch: epoch, session: session)
                    }
                } catch {
                    guard !Task.isCancelled, self.networkEpoch == epoch else { return }
                    let code = Self.networkError(error)
                    self.networkStatus = Self.errorDescription(code)
                    if let frame = try? self.failure(request, error: code) {
                        try? await device.sendCompanion(frame, session: session)
                    }
                }
            }
        }
    }

    private func perform(_ request: CompanionRequest, epoch: UUID, session: UUID) async throws {
        guard let device else { throw RPCError.disconnected }
        let reply: Data
        switch request {
        case .connect(let value):
            try admitChannel(value.connectionID)
            opening.insert(value.connectionID)
            defer { if networkEpoch == epoch { opening.remove(value.connectionID) } }
            lastEndpoint = "\(value.host):\(value.port)"
            let ip = try await network.openSocket(id: value.connectionID, host: value.host, port: value.port,
                udp: value.transport == .udp, timeout: Double(value.timeoutMilliseconds) / 1000)
            try await announceOpen(id: value.connectionID, resolvedIP: ip, epoch: epoch, session: session)
            return
        case .openWebSocket(let value):
            try admitChannel(value.connectionID)
            opening.insert(value.connectionID)
            defer { if networkEpoch == epoch { opening.remove(value.connectionID) } }
            lastEndpoint = value.url.host
            try await network.openWebSocket(id: value.connectionID, url: value.url,
                headers: Self.headers(value.headers), timeout: Double(value.timeoutMilliseconds) / 1000)
            try await announceOpen(id: value.connectionID, epoch: epoch, session: session)
            return
        case .send(let value):
            let count = try await network.send(id: value.connectionID, data: value.data, binary: value.isBinary)
            try check(epoch: epoch, session: session)
            sentBytes += count
            reply = try CompanionResponse.send(connectionID: value.connectionID, bytesSent: count)
        case .close(let value):
            network.close(id: value.connectionID)
            connections.remove(value.connectionID); connectionCount = connections.count
            reply = try CompanionResponse.close(connectionID: value.connectionID)
        case .http(let value):
            guard httpDeliveries.count < 2 else { throw CompanionTransportError.limit }
            httpDeliveries.insert(value.requestID)
            defer { if networkEpoch == epoch { httpDeliveries.remove(value.requestID) } }
            lastEndpoint = value.url.host
            var body = value.body
            do {
                if let path = value.savePath { try CompanionStorage.validate(path) }
                if let path = value.sendPath { body = try await device.readCompanionFile(path, session: session) }
            } catch {
                try check(epoch: epoch, session: session)
                try await device.sendCompanion(failure(request, error: .fileError), session: session)
                return
            }
            try check(epoch: epoch, session: session)
            let result = try await network.http(method: value.method.name, url: value.url,
                headers: Self.headers(value.headers), body: body, timeout: Double(value.timeoutMilliseconds) / 1000,
                requestID: value.requestID)
            try check(epoch: epoch, session: session)
            sentBytes += body.count
            if let path = value.savePath {
                do { try await device.writeCompanionFile(result.body, path: path, session: session) }
                catch {
                    try check(epoch: epoch, session: session)
                    try await device.sendCompanion(failure(request, error: .fileError), session: session)
                    return
                }
                receivedBytes += result.body.count
            } else {
                for offset in stride(from: 0, to: result.body.count, by: CompanionLimits.maxDataBytes) {
                    try check(epoch: epoch, session: session)
                    let data = Data(result.body[offset..<min(offset + CompanionLimits.maxDataBytes, result.body.count)])
                    try await device.sendCompanion(CompanionResponse.received(connectionID: value.requestID, data: data), session: session)
                    receivedBytes += data.count
                }
            }
            var responseHeaders: [CompanionHTTPHeader] = []
            if value.includeResponseHeaders {
                responseHeaders = try result.headers.sorted { $0.key < $1.key }.map { try CompanionHTTPHeader(name: $0.key, value: $0.value) }
            }
            reply = try CompanionResponse.http(requestID: value.requestID, statusCode: result.status,
                headers: responseHeaders, bodySize: result.body.count, savedToFile: value.savePath != nil)
            try check(epoch: epoch, session: session)
            try await device.sendCompanion(reply, session: session)
            networkStatus = "共享中 · 请求已完成"
            return
        default: return
        }
        try check(epoch: epoch, session: session)
        try await device.sendCompanion(reply, session: session)
        networkStatus = "共享中 · 请求已完成"
    }

    private func announceOpen(id: UInt32, resolvedIP: String = "", epoch: UUID, session: UUID) async throws {
        do {
            try check(epoch: epoch, session: session)
            // A peer may have closed as soon as the transport finished opening.
            if stateEvents[id] == nil { connections.insert(id) }
            connectionCount = connections.count
            let frame = try CompanionResponse.connect(connectionID: id, state: .connected, resolvedIP: resolvedIP)
            try await device?.sendCompanion(frame, session: session)
            try check(epoch: epoch, session: session)
            networkStatus = "共享中 · 连接已建立"
        } catch {
            // Only an open that actually succeeded owns cleanup. A rejected
            // duplicate ID must never close the pre-existing channel. Explicit
            // close/toggle cancellation already disposed of its own channel.
            if !Task.isCancelled, networkEpoch == epoch, device?.companionSession == session {
                network.close(id: id)
                connections.remove(id); connectionCount = connections.count
            }
            throw error
        }
    }

    private func admitChannel(_ id: UInt32) throws {
        // Bound queued terminal events while BLE is slow. Never reuse an ID
        // until its old terminal event has been queued in the same ordered lane.
        guard stateEvents.count < 8 else { throw CompanionTransportError.limit }
        guard !connections.contains(id), stateEvents[id] == nil, stateSendingID != id else { throw CompanionTransportError.invalidConnection }
    }

    private func check(epoch: UUID, session: UUID) throws {
        try Task.checkCancellation()
        guard networkEnabled, networkEpoch == epoch, device?.companionSession == session else { throw RPCError.cancelled }
    }

    private func failure(_ request: CompanionRequest, error: CompanionNetworkErrorCode) throws -> Data {
        switch request {
        case .connect(let value): return try CompanionResponse.connect(connectionID: value.connectionID, state: .error, error: error)
        case .openWebSocket(let value): return try CompanionResponse.connect(connectionID: value.connectionID, state: .error, error: error)
        case .send(let value): return try CompanionResponse.send(connectionID: value.connectionID, bytesSent: 0, error: error)
        case .close(let value): return try CompanionResponse.close(connectionID: value.connectionID, error: error)
        case .http(let value): return try CompanionResponse.http(requestID: value.requestID, statusCode: 0, error: error)
        default: return CompanionResponse.locationUnavailable(.unknown)
        }
    }

    private static func headers(_ values: [CompanionHTTPHeader]) -> [String: String] {
        // Names are case-insensitive; explicit duplicate rows are combined.
        Dictionary(values.map { ($0.name.lowercased(), $0.value) }, uniquingKeysWith: { $0 + ", " + $1 })
    }

    private static func networkError(_ error: Error) -> CompanionNetworkErrorCode {
        guard let value = error as? CompanionTransportError else { return .internalError }
        switch value {
        case .dns: return .dnsFailed
        case .timeout: return .timeout
        case .refused: return .connectionRefused
        case .unreachable: return .networkUnreachable
        case .invalidConnection: return .invalidConnection
        case .notConnected: return .notConnected
        case .send: return .sendFailed
        case .receive: return .receiveFailed
        case .limit: return .maxConnections
        case .invalidProtocol: return .invalidProtocol
        case .tls: return .tlsFailed
        case .invalidURL: return .invalidURL
        case .internalFailure: return .internalError
        }
    }

    private static func errorDescription(_ error: CompanionNetworkErrorCode) -> String {
        switch error {
        case .noError: return "请求已完成"
        case .dnsFailed: return "无法解析服务器地址"
        case .timeout: return "网络请求超时"
        case .connectionRefused: return "服务器拒绝连接"
        case .networkUnreachable, .hostUnreachable: return "无法连接网络或服务器"
        case .invalidConnection, .notConnected: return "连接不可用或标识重复"
        case .sendFailed: return "网络发送失败"
        case .receiveFailed: return "网络接收失败"
        case .maxConnections: return "连接数或数据大小超过限制"
        case .invalidProtocol: return "暂不支持此网络协议"
        case .tlsFailed: return "服务器安全连接验证失败"
        case .invalidURL: return "服务器地址无效"
        case .fileError: return "SD 卡文件传输失败"
        case .internalError: return "请求未完成，请重试"
        }
    }
}
