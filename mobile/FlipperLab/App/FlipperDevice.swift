import Foundation
import CoreBluetooth
import Observation
import FlipperCore

struct NearbyDevice: Identifiable { let id: UUID; let name: String; let rssi: Int }

@MainActor @Observable
final class FlipperDevice: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum State: String {
        case idle = "尚未连接", scanning = "正在搜索", connecting = "正在配对与连接"
        case discovering = "正在准备通信", negotiating = "正在检查设备", ready = "设备已就绪"
        case unavailable = "蓝牙不可用"
        case reconnecting = "正在恢复连接"
    }
    private(set) var state: State = .idle
    private(set) var nearby: [NearbyDevice] = []
    private(set) var info: [String: String] = [:]
    private(set) var deviceName = "Flipper Zero"
    private(set) var lastError: String?
    private(set) var transferredBytes = 0
    private(set) var protocolVersion = "未检查"
    var ready: Bool { state == .ready }
    let companion = PhoneCompanion()
    var companionSession: UUID { generation }

    // serial_profile.c ORs the 0x3080 advertisement with hardware color (0...3).
    // Scan for every firmware-advertised variant, including spoofed colors.
    private static let advertisedServices = ["3080", "3081", "3082", "3083"].map { CBUUID(string: $0) }
    // UUIDs are reversed from the little-endian arrays in serial_service_uuid.inc.
    private static let service = CBUUID(string: "8FE5B3D5-2E7F-4A98-2A48-7ACC60FE0000")
    private static let tx = CBUUID(string: "19ED82AE-ED21-4C9D-4145-228E61FE0000")
    private static let rx = CBUUID(string: "19ED82AE-ED21-4C9D-4145-228E62FE0000")
    private static let flow = CBUUID(string: "19ED82AE-ED21-4C9D-4145-228E63FE0000")
    private static let status = CBUUID(string: "19ED82AE-ED21-4C9D-4145-228E64FE0000")

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var characteristics: [CBUUID: CBCharacteristic] = [:]
    @ObservationIgnored private var subscriptions: Set<CBUUID> = []
    @ObservationIgnored private var decoder = RPCFrameDecoder()
    @ObservationIgnored private var credits: Int?
    @ObservationIgnored private var outbound = RPCOutboundQueue()
    private var hasUnsentBytes: Bool { outbound.commandBytes > 0 }
    @ObservationIgnored private var writeInFlight = false
    @ObservationIgnored private var writeLane: RPCOutboundQueue.Lane = .command
    @ObservationIgnored private var nextID: UInt32 = 0
    @ObservationIgnored private var pendingID: UInt32?
    @ObservationIgnored private var response: [RPCEnvelope] = []
    @ObservationIgnored private var responseBytes = 0
    @ObservationIgnored private var responseComplete = false
    @ObservationIgnored private var responseError: RPCError?
    @ObservationIgnored private var continuation: CheckedContinuation<[RPCEnvelope], Error>?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var deadline: Task<Void, Never>?
    @ObservationIgnored private var connectionTimer: Task<Void, Never>?
    @ObservationIgnored private var handshake: Task<Void, Never>?
    private var generation = UUID()
    @ObservationIgnored private var appReady = false
    @ObservationIgnored private var installedAppPaths: Set<String> = []
    @ObservationIgnored private var bridgeActive = false
    @ObservationIgnored private var bridgeSequence: UInt16 = 0
    @ObservationIgnored private var bridgeReply: Data?
    @ObservationIgnored private var recovery = BLEConnectionRecovery()
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var isForeground = true
    private(set) var reconnectAttempt = 0

    override init() {
        super.init()
        companion.attach(self)
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func scan() {
        guard central.state == .poweredOn else { updateBluetoothState(); return }
        guard peripheral == nil else { return }
        reconnectTask?.cancel(); reconnectTask = nil; recovery.cancel(); reconnectAttempt = 0
        nearby = []; peripherals = [:]; lastError = nil; state = .scanning
        // Firmware advertises a color-dependent 16-bit UUID, not its 128-bit serial service.
        central.scanForPeripherals(withServices: Self.advertisedServices, options: nil)
        connectionTimer?.cancel()
        connectionTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.state == .scanning else { return }
            self.central.stopScan(); self.state = .idle
        }
    }

    func connect(_ device: NearbyDevice) {
        guard peripheral == nil, let selected = peripherals[device.id] else { return }
        reconnectTask?.cancel(); reconnectTask = nil; recovery.cancel(); reconnectAttempt = 0
        deviceName = device.name
        connectPeripheral(selected)
    }

    private func connectPeripheral(_ selected: CBPeripheral) {
        central.stopScan(); lastError = nil; state = .connecting
        peripheral = selected; selected.delegate = self
        central.connect(selected, options: nil)
        connectionTimer?.cancel()
        connectionTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled, let self, !self.ready else { return }
            self.fail(RPCError.message("配对或通信准备超时，请检查设备上的配对提示。"))
        }
    }

    func disconnect() { close(error: RPCError.disconnected) }
    func cancelOperation() { close(error: RPCError.cancelled) }
    func clearError() { lastError = nil }

    /// Backgrounding stops pending reconnects; existing ready links may remain connected.
    func setForeground(_ active: Bool) {
        isForeground = active
        if active {
            if ready { recovery.becameReady() }
        } else {
            recovery.cancel()
            if state == .reconnecting || reconnectAttempt > 0 { close(error: RPCError.disconnected) }
        }
    }

    private func close(error: Error, keepingRecovery: Bool = false) {
        reconnectTask?.cancel(); reconnectTask = nil
        if !keepingRecovery { recovery.cancel(); reconnectAttempt = 0 }
        generation = UUID(); handshake?.cancel(); handshake = nil
        companion.endSession()
        connectionTimer?.cancel(); connectionTimer = nil
        central.stopScan()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        peripheral = nil; characteristics = [:]; subscriptions = []; credits = nil
        outbound.reset(); writeInFlight = false; decoder.reset(); appReady = false
        installedAppPaths = []
        bridgeActive = false; bridgeReply = nil
        finish(.failure(error)); info = [:]; protocolVersion = "未检查"
        state = central.state == .poweredOn ? .idle : .unavailable
    }
    private func fail(_ error: Error) { lastError = PhoneErrorDescription.describe(error); close(error: error) }

    private func recover(_ target: CBPeripheral, error: Error) {
        guard isForeground else { fail(error); return }
        guard let delay = recovery.nextDelay(bluetoothAvailable: central.state == .poweredOn) else {
            fail(error); return
        }
        // Fail the old continuation and discard its bytes/decoder/whitelist before reconnecting.
        // No operation (including App.Start or a write) is carried into the replacement session.
        close(error: error, keepingRecovery: true)
        reconnectAttempt = recovery.attempt
        state = .reconnecting
        lastError = "连接已中断，正在尝试恢复（\(reconnectAttempt)/\(BLEConnectionRecovery.delays.count)）。原任务不会自动重发。"
        let session = generation
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.generation == session,
                  self.state == .reconnecting, self.central.state == .poweredOn else { return }
            self.reconnectTask = nil
            self.connectPeripheral(target)
        }
    }

    private func requireSession(_ session: UUID) throws {
        try Task.checkCancellation()
        guard ready, generation == session else { throw RPCError.disconnected }
    }
    private func finish(_ result: Result<[RPCEnvelope], Error>) {
        timer?.cancel(); timer = nil
        deadline?.cancel(); deadline = nil
        let waiting = continuation
        continuation = nil; pendingID = nil; response = []; responseBytes = 0; responseComplete = false; responseError = nil
        waiting?.resume(with: result)
    }

    private func refreshTimeout() {
        guard let id = pendingID else { return }
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled, let self, self.pendingID == id else { return }
            self.fail(RPCError.timeout)
        }
    }

    private func request(tag: Int, payload: Data = Data(), session: UUID? = nil) async throws -> [RPCEnvelope] {
        try await exchange(session: session) { id in RPCEnvelope.encode(id: id, tag: tag, payload: payload) }
    }
    private func exchange(session: UUID? = nil, frames: (UInt32) -> Data) async throws -> [RPCEnvelope] {
        guard peripheral != nil, state == .ready || state == .negotiating else { throw RPCError.disconnected }
        if let session, generation != session { throw RPCError.disconnected }
        let startedSession = generation
        guard continuation == nil, !hasUnsentBytes, !(writeInFlight && writeLane == .command) else { throw RPCError.busy }
        try Task.checkCancellation()
        nextID = nextID == UInt32.max ? 1 : nextID + 1
        let id = nextID
        let bytes = frames(id)
        guard bytes.count <= RPCOutboundQueue.totalLimit else { throw RPCError.tooLarge }
        try outbound.append(bytes, lane: .command)
        let rows: [RPCEnvelope] = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation; pendingID = id
                response = []; responseBytes = 0; responseComplete = false; responseError = nil; transferredBytes = 0
                refreshTimeout()
                deadline = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(600))
                    guard !Task.isCancelled, let self, self.pendingID == id else { return }
                    self.fail(RPCError.timeout)
                }
                pump()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.pendingID == id else { return }
                self.close(error: RPCError.cancelled)
            }
        }
        guard generation == startedSession else { throw RPCError.disconnected }
        return rows
    }

    private func pump() {
        guard !writeInFlight, !outbound.isEmpty, let capacity = credits, capacity > 0,
              let peripheral, let rx = characteristics[Self.rx] else { return }
        let size = min(capacity, 486, peripheral.maximumWriteValueLength(for: .withResponse))
        guard size > 0 else { fail(RPCError.malformed); return }
        guard let chunk = outbound.next(maximumBytes: size) else { return }
        credits = capacity - chunk.data.count; writeInFlight = true; writeLane = chunk.lane
        peripheral.writeValue(chunk.data, for: rx, type: .withResponse)
        if chunk.lane == .command { transferredBytes += chunk.data.count }
    }

    /// Bounded backpressure: callers await space instead of building an unbounded
    /// stream of location/network tasks. A stale session may never enqueue bytes.
    func sendCompanion(_ frame: Data, session: UUID) async throws {
        guard frame.count <= RPCOutboundQueue.companionLimit else { throw RPCError.tooLarge }
        let until = ContinuousClock.now.advanced(by: .seconds(45))
        while true {
            try Task.checkCancellation()
            guard ready, generation == session else { throw RPCError.disconnected }
            if outbound.companionBytes + frame.count <= RPCOutboundQueue.companionLimit,
               outbound.commandBytes + outbound.companionBytes + frame.count <= RPCOutboundQueue.totalLimit {
                try outbound.append(frame, lane: .companion)
                pump()
                return
            }
            guard ContinuousClock.now < until else { throw RPCError.timeout }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func accept(_ envelope: RPCEnvelope) throws {
        if CompanionRequest.tags.contains(envelope.tag) {
            guard ready else { throw RPCError.malformed }
            try companion.accept(CompanionRequest(envelope))
            return
        }
        if envelope.tag == 58 { appReady = try PBMessage(envelope.payload).uint(1) == 1; return }
        if envelope.tag == 65, bridgeActive {
            guard let data = try PBMessage(envelope.payload).bytes(1), data.count <= SerialBridge.maxChunk + 12 else {
                throw RPCError.malformed
            }
            // Application data is unsolicited; the inner sequence correlates it with our request.
            guard data.count >= 6, (UInt16(data[4]) | UInt16(data[5]) << 8) == bridgeSequence else { return }
            guard bridgeReply == nil else { throw RPCError.malformed }
            bridgeReply = data
            return
        }
        guard envelope.commandID == pendingID else { return }
        refreshTimeout()
        // Stop queued continuation frames on a device error, rather than completing
        // the request while old writes can still mutate the device's storage state.
        guard envelope.status == 0 else {
            if hasUnsentBytes { fail(RPCError.remote(envelope.status)) }
            else {
                responseError = .remote(envelope.status); responseComplete = true
                completeIfDrained()
            }
            return
        }
        guard response.count < 8192, responseBytes + envelope.payload.count <= 2_200_000 else { throw RPCError.tooLarge }
        response.append(envelope); responseBytes += envelope.payload.count
        if !envelope.hasNext { responseComplete = true; completeIfDrained() }
    }

    func discardCompanion(tags: Set<Int>) { outbound.discardCompanion(tags: tags) }

    private func completeIfDrained() {
        if responseComplete, !hasUnsentBytes, !(writeInFlight && writeLane == .command) {
            if let responseError { finish(.failure(responseError)) }
            else { finish(.success(response)) }
        }
    }

    private func beginHandshakeIfReady() {
        guard state == .discovering, credits != nil,
              subscriptions.contains(Self.tx), subscriptions.contains(Self.flow) else { return }
        state = .negotiating
        let session = generation
        handshake = Task {
            do {
                let version = try await request(tag: 39)
                try Task.checkCancellation()
                guard let first = version.first, first.tag == 40 else { throw RPCError.malformed }
                let value = try PBMessage(first.payload)
                guard value.uint(1) == 0, value.uint(2) >= 25 else { throw RPCError.message("需要 RPC 0.25 或更新的兼容固件，请先更新设备。") }
                protocolVersion = "\(value.uint(1)).\(value.uint(2))"
                let rows = try await request(tag: 32)
                try Task.checkCancellation()
                for row in rows {
                    guard row.tag == 33 else { throw RPCError.malformed }
                    let value = try PBMessage(row.payload)
                    if let key = try value.string(1), let text = try value.string(2) { info[key] = text }
                }
                try Task.checkCancellation()
                guard peripheral != nil, generation == session else { return }
                state = .ready; connectionTimer?.cancel(); connectionTimer = nil
                if isForeground { recovery.becameReady() } else { recovery.cancel() }
                reconnectAttempt = 0
                companion.beginSession()
                handshake = nil
            } catch {
                // A cancelled old handshake must not tear down a newer connection.
                if generation == session { fail(error) }
            }
        }
    }

    func listFiles(_ path: String) async throws -> [DeviceFile] {
        guard ready else { throw RPCError.disconnected }
        let session = generation
        try validate(path)
        let rows = try await request(tag: 7, payload: PBMessage.string(1, path), session: session)
        try requireSession(session)
        var files: [DeviceFile] = []
        for row in rows {
            guard row.tag == 8 else { throw RPCError.malformed }
            for data in try PBMessage(row.payload).blobs(1) {
                guard files.count < 4096 else { throw RPCError.tooLarge }
                files.append(try DeviceFile(parent: path, message: PBMessage(data)))
            }
        }
        return files.sorted { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func listInstalledApps() async throws -> [FlipperFunction] {
        guard ready else { throw RPCError.disconnected }
        let session = generation
        installedAppPaths = []
        let result = try await InstalledAppDiscovery.collect { path in
            guard self.ready, self.generation == session else { throw RPCError.disconnected }
            let files: [DeviceFile]
            do { files = try await self.listFiles(path) }
            catch RPCError.remote(7) where path == InstalledAppDiscovery.root { return [] }
            guard self.ready, self.generation == session else { throw RPCError.disconnected }
            return files
        }
        try Task.checkCancellation()
        guard ready, generation == session else { throw RPCError.disconnected }
        installedAppPaths = Set(result.map(\.launchName))
        return result
    }

    func launch(_ feature: FlipperFunction) async throws {
        guard ready else { throw RPCError.disconnected }
        let session = generation
        let known = FlipperFunction.builtIns.contains {
            $0.id == feature.id && $0.launchName == feature.launchName
        }
        guard known || (feature.isInstalledApp && installedAppPaths.contains(feature.launchName)) else {
            throw RPCError.message("请先刷新设备应用列表，再选择设备上确实安装的应用。")
        }
        do {
            let rows = try await request(tag: 16, payload: PBMessage.string(1, feature.launchName), session: session)
            guard rows.count == 1, rows[0].tag == 4 else { throw RPCError.malformed }
        } catch RPCError.remote(15) {
            throw RPCError.message("设备未安装这个应用，或当前固件不支持直接打开。")
        } catch RPCError.remote(16) {
            throw RPCError.message("Flipper 无法启动该应用，请检查 SD 卡、应用版本和设备提示。")
        }
    }

    func readFile(_ path: String, session: UUID? = nil) async throws -> Data {
        guard ready else { throw RPCError.disconnected }
        let expected = session ?? generation
        try requireSession(expected)
        try validate(path)
        let rows = try await request(tag: 9, payload: PBMessage.string(1, path), session: expected)
        var bytes = Data()
        for row in rows {
            guard row.tag == 10, let blob = try PBMessage(row.payload).bytes(1) else { throw RPCError.malformed }
            guard let part = try PBMessage(blob).bytes(4) else { continue }
            guard bytes.count + part.count <= 2 * 1024 * 1024 else { throw RPCError.tooLarge }
            bytes.append(part)
        }
        return bytes
    }

    func upload(_ record: CaptureRecord) async throws -> String {
        guard ready else { throw RPCError.disconnected }
        let session = generation
        guard let directory = record.kind.deviceDirectory else { throw RPCError.message("串口日志仅保存在手机，不能作为设备应用文件上传。") }
        let data = Data(record.rawText.utf8)
        guard !data.isEmpty, data.count <= 2 * 1024 * 1024 else { throw RPCError.tooLarge }
        _ = try await Task.detached(priority: .userInitiated) {
            try RecordAnalyzer.analyze(record.rawText, kind: record.kind)
        }.value
        try requireSession(session)
        let path = directory + "/Lab_" + UUID().uuidString + "." + record.kind.fileExtension
        do { _ = try await request(tag: 13, payload: PBMessage.string(1, directory), session: session) }
        catch RPCError.remote(6) { /* Existing directory is expected. */ }
        _ = try await exchange(session: session) { id in
            var bytes = Data()
            for offset in stride(from: 0, to: data.count, by: 256) {
                let end = min(offset + 256, data.count)
                let file = PBMessage.bytes(4, Data(data[offset..<end]))
                bytes.append(RPCEnvelope.encode(id: id, tag: 11,
                    payload: PBMessage.string(1, path) + PBMessage.bytes(2, file), hasNext: end < data.count))
            }
            return bytes
        }
        guard try await readFile(path, session: session) == data else { throw RPCError.message("上传后的内容校验失败，请重新导入检查。") }
        return path
    }

    private func waitForCompanionStorage(session: UUID) async throws {
        let until = ContinuousClock.now.advanced(by: .seconds(45))
        while continuation != nil || hasUnsentBytes || (writeInFlight && writeLane == .command) {
            try Task.checkCancellation()
            guard ready, generation == session else { throw RPCError.disconnected }
            guard ContinuousClock.now < until else { throw RPCError.busy }
            try await Task.sleep(for: .milliseconds(25))
        }
        try Task.checkCancellation()
        guard ready, generation == session else { throw RPCError.disconnected }
    }

    func readCompanionFile(_ path: String, session: UUID) async throws -> Data {
        try CompanionStorage.validate(path)
        try await waitForCompanionStorage(session: session)
        let data = try await readFile(path, session: session)
        try Task.checkCancellation()
        guard generation == session else { throw RPCError.disconnected }
        return data
    }

    func writeCompanionFile(_ data: Data, path: String, session: UUID) async throws {
        try CompanionStorage.validate(path)
        guard data.count <= CompanionStorage.maximumBytes else { throw RPCError.tooLarge }
        let parts = path.split(separator: "/")
        // Firmware resolves /data relative to its calling application before
        // issuing the request. Each missing application subdirectory is created.
        for count in 2..<parts.count {
            let directory = "/" + parts.prefix(count).joined(separator: "/")
            try await waitForCompanionStorage(session: session)
            do { _ = try await request(tag: 13, payload: PBMessage.string(1, directory), session: session) }
            catch RPCError.remote(6) { /* Directory already exists. */ }
        }
        try await waitForCompanionStorage(session: session)
        _ = try await exchange(session: session) { id in
            var frames = Data()
            // 512 is the pinned storage protocol's maximum chunk. Include one
            // empty final frame to create a genuine zero-byte response file.
            for offset in stride(from: 0, to: max(data.count, 1), by: 512) {
                let end = min(offset + 512, data.count)
                let part = data.isEmpty ? Data() : Data(data[offset..<end])
                frames += RPCEnvelope.encode(id: id, tag: 11,
                    payload: PBMessage.string(1, path) + PBMessage.bytes(2, PBMessage.bytes(4, part)),
                    hasNext: end < data.count)
            }
            return frames
        }
        let actual = try await readCompanionFile(path, session: session)
        guard actual == data else { throw RPCError.message("网络文件写入后的校验失败。") }
    }

    func sendInfrared(_ record: CaptureRecord, buttonIndex: Int) async throws {
        guard ready else { throw RPCError.disconnected }
        let session = generation
        guard record.kind == .infrared, let path = record.sourcePath,
              path.hasPrefix("/ext/infrared/") else { throw RPCError.message("请先将此红外记录上传至当前设备。") }
        let analysis = try await Task.detached(priority: .userInitiated) {
            try RecordAnalyzer.analyze(record.rawText, kind: .infrared)
        }.value
        try requireSession(session)
        guard analysis.buttons.indices.contains(buttonIndex) else { throw RPCError.malformed }
        guard try await readFile(path, session: session) == Data(record.rawText.utf8) else {
            throw RPCError.message("设备文件与手机记录不同，请重新导入或上传后再操作。")
        }
        appReady = false
        _ = try await request(tag: 16, payload: PBMessage.string(1, "Infrared") + PBMessage.string(2, "RPC"), session: session)
        do {
            for _ in 0..<100 {
                try requireSession(session)
                if appReady { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard appReady else { throw RPCError.timeout }
            _ = try await request(tag: 48, payload: PBMessage.string(1, path), session: session)
            _ = try await request(tag: 75, payload: PBMessage.uint(2, UInt64(buttonIndex)), session: session)
            _ = try await request(tag: 47, session: session)
        } catch {
            // The firmware closes the RPC scene and stops output when this connection closes.
            if generation == session { fail(error) }
            throw error
        }
    }

    func startSerialBridge(port: UInt8, baud: UInt32) async throws {
        guard ready, !bridgeActive else { throw RPCError.busy }
        let session = generation
        let configuration = try SerialBridge.configuration(port: port, baud: baud)
        appReady = false
        _ = try await request(tag: 16, payload: PBMessage.string(1, "Lab Bridge") + PBMessage.string(2, "RPC"), session: session)
        do {
            for _ in 0..<100 {
                try requireSession(session)
                if appReady { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard appReady else { throw RPCError.message("Lab Bridge 没有就绪，请安装本项目的新固件。") }
            bridgeActive = true
            let hello = try await serialBridgeRequest(.hello, session: session)
            guard String(data: hello.payload, encoding: .utf8) == "FlipperLab.Serial/1" else {
                throw RPCError.message("串口桥版本不兼容。")
            }
            _ = try await serialBridgeRequest(.open, payload: configuration, session: session)
        } catch {
            if generation == session { fail(error) }
            throw error
        }
    }

    func readSerialBridge(session: UUID? = nil) async throws -> SerialBridge.Reply {
        try await serialBridgeRequest(.read, session: session)
    }

    func stopSerialBridge(session: UUID? = nil) async throws {
        guard bridgeActive else { return }
        let expected = session ?? generation
        try requireSession(expected)
        _ = try await serialBridgeRequest(.close, session: expected)
        _ = try await request(tag: 47, session: expected)
        bridgeActive = false; bridgeReply = nil
    }

    private func serialBridgeRequest(_ operation: SerialBridge.Operation, payload: Data = Data(), session: UUID? = nil) async throws -> SerialBridge.Reply {
        let expected = session ?? generation
        try requireSession(expected)
        guard bridgeActive, appReady else { throw RPCError.message("扩展板串口会话已结束。") }
        bridgeSequence &+= 1
        bridgeReply = nil
        let packet = try SerialBridge.request(operation, sequence: bridgeSequence, payload: payload)
        let result = try await request(tag: 65, payload: PBMessage.bytes(1, packet), session: expected)
        guard result.count == 1, result[0].tag == 4, let data = bridgeReply else { throw RPCError.malformed }
        let reply = try SerialBridge.Reply(data)
        guard reply.sequence == bridgeSequence, reply.operation == operation else { throw RPCError.malformed }
        return reply
    }

    private func validate(_ path: String) throws {
        guard path == "/ext" || path.hasPrefix("/ext/"), path.utf8.count <= 240,
              !path.contains("\0"), !path.contains("\\"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains("..") else { throw RPCError.malformed }
    }

    private func updateBluetoothState() {
        guard central.state == .poweredOn else {
            switch central.state {
            case .unauthorized: lastError = "请在 iPhone 设置中允许本应用使用蓝牙。"
            case .poweredOff: lastError = "请在 iPhone 设置中开启蓝牙。"
            case .unsupported: lastError = "当前设备不支持蓝牙连接。"
            case .resetting: lastError = "蓝牙正在重置，请稍后重试。"
            default: lastError = "正在检查蓝牙状态，请稍后重试。"
            }
            close(error: RPCError.disconnected); return
        }
        if state == .unavailable { state = .idle; lastError = nil }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) { updateBluetoothState() }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard state == .scanning else { return }
        let device = NearbyDevice(id: peripheral.identifier,
            name: (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "Flipper",
            rssi: RSSI.intValue)
        if let index = nearby.firstIndex(where: { $0.id == device.id }) {
            peripherals[device.id] = peripheral; nearby[index] = device
        } else if nearby.count < 100 { peripherals[device.id] = peripheral; nearby.append(device) }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { central.cancelPeripheralConnection(peripheral); return }
        guard state == .connecting else { return }
        state = .discovering; peripheral.discoverServices([Self.service])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral, state == .connecting else { return }
        recover(peripheral, error: error ?? RPCError.disconnected)
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        recover(peripheral, error: error ?? RPCError.disconnected)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === self.peripheral, state == .discovering else { return }
        if let error { fail(error); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else {
            fail(RPCError.message("此设备没有兼容的 Flipper 串口服务。")); return
        }
        peripheral.discoverCharacteristics([Self.tx, Self.rx, Self.flow, Self.status], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === self.peripheral, state == .discovering else { return }
        if let error { fail(error); return }
        for item in service.characteristics ?? [] { characteristics[item.uuid] = item }
        guard let tx = characteristics[Self.tx], let flow = characteristics[Self.flow],
              let rx = characteristics[Self.rx], rx.properties.contains(.write) else { fail(RPCError.malformed); return }
        peripheral.setNotifyValue(true, for: tx); peripheral.setNotifyValue(true, for: flow)
        peripheral.readValue(for: flow)
        if let status = characteristics[Self.status] { peripheral.setNotifyValue(true, for: status) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristics[characteristic.uuid] === characteristic else { return }
        if let error { fail(error); return }
        if characteristic.isNotifying { subscriptions.insert(characteristic.uuid) }
        else { subscriptions.remove(characteristic.uuid) }
        beginHandshakeIfReady()
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristics[characteristic.uuid] === characteristic else { return }
        if let error { fail(error); return }
        guard let value = characteristic.value else { return }
        do {
            if characteristic.uuid == Self.flow {
                guard value.count == 4 else { throw RPCError.malformed }
                let capacity = value.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                guard capacity <= 65_536 else { throw RPCError.tooLarge }
                credits = Int(capacity); pump(); beginHandshakeIfReady()
            } else if characteristic.uuid == Self.tx {
                if !value.isEmpty { refreshTimeout() }
                for envelope in try decoder.append(value) { try accept(envelope) }
            } else if characteristic.uuid == Self.status, value.first == 0, state == .ready {
                throw RPCError.message("设备关闭了通信会话，请重新连接。")
            }
        } catch { fail(error) }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristic.uuid == Self.rx,
              characteristics[Self.rx] === characteristic, writeInFlight else { return }
        if let error { fail(error); return }
        refreshTimeout()
        writeInFlight = false; pump(); completeIfDrained()
    }
}
