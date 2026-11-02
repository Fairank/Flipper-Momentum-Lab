import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import FlipperCore

/// Real RFC 6455 traffic through URLSession, confined to IPv4 loopback.
/// The fixture uses ephemeral ports, bounded I/O and no timing sleeps or ATS exceptions.
final class CompanionWebSocketLoopbackTests: XCTestCase {
    @MainActor
    func testHandshakeTextBinaryAndPeerClose() async throws {
        let server = try WebSocketLoopbackFixture()
        let finished = expectation(description: "server finished and released its sockets")
        let disconnected = expectation(description: "one graceful terminal callback")
        disconnected.assertForOverFulfill = true
        let text = Data("手机与 Flipper 🐬".utf8)
        let binary = Data((0..<512).map { UInt8($0 % 256) })
        let clientSent = DispatchSemaphore(value: 0)
        server.start(finished: finished) { wire in
            try wire.upgrade(path: "/companion", header: "X-Flipper-Test: local")
            try wire.requireFrame(opcode: 1, payload: text)
            try wire.requireFrame(opcode: 2, payload: binary)
            // Peer closure must not race either send's completion callback on the main actor.
            try wire.waitForSignal(clientSent)
            try wire.sendFrame(opcode: 1, payload: text)
            try wire.sendFrame(opcode: 2, payload: binary)
            try wire.sendFrame(opcode: 8, payload: Data([0x03, 0xE8]))
            try wire.requireNormalCloseOrEOF()
        }
        let net = CompanionNetworking()
        defer { net.cancelAll(); server.stop(); clientSent.signal() }
        var chunks: [(UInt32, Data, Bool)] = []
        var states: [(UInt32, CompanionTransportState, CompanionTransportError?)] = []
        net.onData = { id, data, binary in chunks.append((id, data, binary)) }
        net.onState = { id, state, error in
            states.append((id, state, error))
            disconnected.fulfill()
        }
        try await net.openWebSocket(id: 41, url: server.url(path: "/companion"),
                                    headers: ["X-Flipper-Test": "local"], timeout: 5)
        XCTAssertEqual(net.activeIDs, [41])
        let sentText = try await net.send(id: 41, data: text, binary: false)
        let sentBinary = try await net.send(id: 41, data: binary, binary: true)
        XCTAssertEqual(sentText, text.count)
        XCTAssertEqual(sentBinary, binary.count)
        clientSent.signal()
        await fulfillment(of: [disconnected, finished], timeout: 10)
        try server.checkResult()
        XCTAssertEqual(chunks.count, 2)
        if chunks.count == 2 {
            XCTAssertEqual(chunks[0].0, 41)
            XCTAssertEqual(chunks[0].1, text)
            XCTAssertFalse(chunks[0].2)
            XCTAssertEqual(chunks[1].0, 41)
            XCTAssertEqual(chunks[1].1, binary)
            XCTAssertTrue(chunks[1].2)
        }
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states.first?.0, 41)
        XCTAssertEqual(states.first?.1, .disconnected)
        XCTAssertNil(states.first?.2)
        XCTAssertTrue(net.activeIDs.isEmpty)
    }

    @MainActor
    func testExplicitCloseIsSilentAndReleasesID() async throws {
        let server = try WebSocketLoopbackFixture()
        let finished = expectation(description: "local close reached server and sockets were released")
        server.start(finished: finished) { wire in
            try wire.upgrade(path: "/close")
            try wire.requireNormalCloseOrEOF(reply: true)
        }
        let net = CompanionNetworking()
        defer { net.cancelAll(); server.stop() }
        var callbackCount = 0
        net.onData = { _, _, _ in callbackCount += 1 }
        net.onState = { _, _, _ in callbackCount += 1 }
        try await net.openWebSocket(id: 42, url: server.url(path: "/close"), headers: [:], timeout: 5)
        XCTAssertEqual(net.activeIDs, [42])
        net.close(id: 42)
        XCTAssertTrue(net.activeIDs.isEmpty)
        do {
            _ = try await net.send(id: 42, data: Data([1]), binary: true)
            XCTFail("A closed ID must not accept another message")
        } catch {
            XCTAssertEqual(error as? CompanionTransportError, .invalidConnection)
        }
        await fulfillment(of: [finished], timeout: 10)
        try server.checkResult()
        XCTAssertEqual(callbackCount, 0)
        XCTAssertTrue(net.activeIDs.isEmpty)
    }

    @MainActor
    func testCancellationAfterRequestBeforeUpgradeIsSilent() async throws {
        let server = try WebSocketLoopbackFixture()
        let requestReceived = expectation(description: "complete opening HTTP request received")
        let finished = expectation(description: "cancelled peer reached EOF and sockets were released")
        server.start(finished: finished) { wire in
            _ = try wire.readUpgradeRequest(path: "/cancel")
            requestReceived.fulfill()
            // The fixture never sends 101. Cancellation is synchronized to the actual request.
            try wire.requireEOF()
        }
        let net = CompanionNetworking()
        defer { net.cancelAll(); server.stop() }
        var callbackCount = 0
        net.onData = { _, _, _ in callbackCount += 1 }
        net.onState = { _, _, _ in callbackCount += 1 }
        let opening = Task {
            try await net.openWebSocket(id: 43, url: server.url(path: "/cancel"), headers: [:], timeout: 5)
        }
        await fulfillment(of: [requestReceived], timeout: 5)
        opening.cancel()
        do {
            try await opening.value
            XCTFail("Cancelling an unfinished handshake must throw")
        } catch {
            XCTAssertTrue(error is CancellationError, "Unexpected opening error: \(error)")
        }
        await fulfillment(of: [finished], timeout: 10)
        try server.checkResult()
        XCTAssertEqual(callbackCount, 0)
        XCTAssertTrue(net.activeIDs.isEmpty)
    }
}

private enum WebSocketFixtureError: Error {
    case system(String, Int32), timeout, stopped, peerClosed, invalid(String), unfinished
}

/// Descriptor ownership and completion state are protected by one lock. Teardown only shuts
/// descriptors down; the worker closes them under the same lock before fulfilling completion.
private final class WebSocketLoopbackFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var listener: Int32?
    private var peer: Int32?
    private var stopped = false
    private var result: Result<Void, Error>?
    private let port: UInt16

    init() throws {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw WebSocketFixtureError.system("socket", errno) }
        do {
            try WebSocketFixtureWire.configure(fd)
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = 0
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bound == 0 else { throw WebSocketFixtureError.system("bind", errno) }
            guard Darwin.listen(fd, 1) == 0 else { throw WebSocketFixtureError.system("listen", errno) }
            var size = socklen_t(MemoryLayout<sockaddr_in>.size)
            let named = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.getsockname(fd, $0, &size) }
            }
            guard named == 0 else { throw WebSocketFixtureError.system("getsockname", errno) }
            port = UInt16(bigEndian: address.sin_port)
            listener = fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    func url(path: String) -> URL { URL(string: "ws://127.0.0.1:\(port)\(path)")! }

    func start(finished: XCTestExpectation, script: @escaping @Sendable (WebSocketFixtureWire) throws -> Void) {
        DispatchQueue(label: "FlipperCoreTests.WebSocketLoopback").async { [self] in
            let outcome: Result<Void, Error>
            do {
                lock.lock()
                let fd = listener!
                lock.unlock()
                let wire = WebSocketFixtureWire(fd: fd, cancelled: { [self] in isStopped })
                let accepted = try wire.acceptPeer()
                lock.lock()
                peer = accepted
                let wasStopped = stopped
                lock.unlock()
                guard !wasStopped else { throw WebSocketFixtureError.stopped }
                try WebSocketFixtureWire.configure(accepted)
                try script(WebSocketFixtureWire(fd: accepted, cancelled: { [self] in isStopped }))
                outcome = .success(())
            } catch {
                outcome = .failure(error)
            }
            lock.lock()
            if let peer { Darwin.close(peer) }
            if let listener { Darwin.close(listener) }
            peer = nil
            listener = nil
            result = outcome
            lock.unlock()
            finished.fulfill()
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        if let peer { Darwin.shutdown(peer, SHUT_RDWR) }
        lock.unlock()
    }

    func checkResult() throws {
        lock.lock()
        let completed = result
        lock.unlock()
        guard let completed else { throw WebSocketFixtureError.unfinished }
        try completed.get()
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    deinit {
        if let peer { Darwin.close(peer) }
        if let listener { Darwin.close(listener) }
    }
}

/// Only the fixture worker calls wire methods. One absolute deadline bounds each script;
/// short poll intervals let failed-test teardown cancel it without closing a reused descriptor.
private final class WebSocketFixtureWire {
    private let fd: Int32
    private let cancelled: @Sendable () -> Bool
    private let deadline = DispatchTime.now().uptimeNanoseconds + 8_000_000_000

    init(fd: Int32, cancelled: @escaping @Sendable () -> Bool) {
        self.fd = fd
        self.cancelled = cancelled
    }

    static func configure(_ fd: Int32) throws {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw WebSocketFixtureError.system("fcntl", errno)
        }
        var enabled: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw WebSocketFixtureError.system("SO_NOSIGPIPE", errno)
        }
    }

    func acceptPeer() throws -> Int32 {
        while true {
            try ready(Int16(POLLIN))
            let accepted = Darwin.accept(fd, nil, nil)
            if accepted >= 0 { return accepted }
            guard errno == EINTR || errno == EAGAIN else { throw WebSocketFixtureError.system("accept", errno) }
        }
    }

    func waitForSignal(_ signal: DispatchSemaphore) throws {
        while true {
            guard !cancelled() else { throw WebSocketFixtureError.stopped }
            guard DispatchTime.now().uptimeNanoseconds < deadline else { throw WebSocketFixtureError.timeout }
            if signal.wait(timeout: .now() + .milliseconds(50)) == .success {
                guard !cancelled() else { throw WebSocketFixtureError.stopped }
                return
            }
        }
    }

    func readUpgradeRequest(path: String, header: String? = nil) throws -> String {
        var bytes = Data()
        let terminator = Data([13, 10, 13, 10])
        while !bytes.suffix(4).elementsEqual(terminator) {
            guard bytes.count < 8192 else { throw WebSocketFixtureError.invalid("HTTP header exceeds fixture limit") }
            bytes.append(try readExactly(1))
        }
        guard let text = String(data: bytes, encoding: .utf8) else {
            throw WebSocketFixtureError.invalid("HTTP header is not UTF-8")
        }
        let lines = text.components(separatedBy: "\r\n")
        guard lines.first == "GET \(path) HTTP/1.1",
              lines.contains(where: { $0.lowercased() == "upgrade: websocket" }),
              lines.contains(where: { $0.lowercased() == "sec-websocket-version: 13" }),
              lines.contains(where: {
                  $0.lowercased().hasPrefix("connection:") &&
                      $0.dropFirst("connection:".count).split(separator: ",").contains(where: {
                          $0.trimmingCharacters(in: .whitespaces).lowercased() == "upgrade"
                      })
              }),
              header.map({ expected in lines.contains(where: { $0.caseInsensitiveCompare(expected) == .orderedSame }) }) ?? true else {
            throw WebSocketFixtureError.invalid("Unexpected opening request")
        }
        guard let keyLine = lines.first(where: { $0.lowercased().hasPrefix("sec-websocket-key:") }) else {
            throw WebSocketFixtureError.invalid("Missing WebSocket key")
        }
        let key = String(keyLine.dropFirst("sec-websocket-key:".count)).trimmingCharacters(in: .whitespaces)
        guard Data(base64Encoded: key)?.count == 16 else { throw WebSocketFixtureError.invalid("Invalid WebSocket key") }
        return key
    }

    func upgrade(path: String, header: String? = nil) throws {
        let key = try readUpgradeRequest(path: path, header: header)
        let digest = Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))
        let accept = Data(digest).base64EncodedString()
        try write(Data(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n" +
                        "Connection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n").utf8))
    }

    func requireFrame(opcode: UInt8, payload: Data) throws {
        let actual = try readFrame()
        guard actual.0 == opcode, actual.1 == payload else {
            throw WebSocketFixtureError.invalid("Unexpected message opcode or payload")
        }
    }

    func requireNormalCloseOrEOF(reply: Bool = false) throws {
        do {
            let frame = try readFrame()
            guard frame.0 == 8, frame.1.count >= 2, frame.1.prefix(2).elementsEqual([0x03, 0xE8]) else {
                throw WebSocketFixtureError.invalid("Expected normal WebSocket close")
            }
            if reply { try sendFrame(opcode: 8, payload: frame.1) }
        } catch WebSocketFixtureError.peerClosed {
            // URLSession may finish cancellation by closing TCP before its close frame is sent.
        }
    }

    func requireEOF() throws {
        do {
            _ = try readExactly(1)
            throw WebSocketFixtureError.invalid("Cancelled handshake sent unexpected data")
        } catch WebSocketFixtureError.peerClosed { }
    }

    func sendFrame(opcode: UInt8, payload: Data) throws {
        guard payload.count <= 512 else { throw WebSocketFixtureError.invalid("Fixture frame exceeds 512 bytes") }
        var frame = Data([0x80 | opcode])
        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        } else {
            frame.append(contentsOf: [126, UInt8(payload.count >> 8), UInt8(payload.count & 255)])
        }
        frame.append(payload)
        try write(frame)
    }

    private func readFrame() throws -> (UInt8, Data) {
        while true {
            let header = Array(try readExactly(2))
            guard header[0] & 0xF0 == 0x80, header[1] & 0x80 != 0 else {
                throw WebSocketFixtureError.invalid("Expected final, unextended, masked client frame")
            }
            let opcode = header[0] & 0x0F
            let lengthTag = header[1] & 0x7F
            guard lengthTag != 127 else { throw WebSocketFixtureError.invalid("64-bit client frame exceeds fixture limit") }
            var length = Int(lengthTag)
            if length == 126 {
                let extended = Array(try readExactly(2))
                length = Int(extended[0]) << 8 | Int(extended[1])
            }
            guard length <= 512, opcode < 8 || length <= 125 else {
                throw WebSocketFixtureError.invalid("Unsupported or oversized client frame")
            }
            let mask = Array(try readExactly(4))
            let encoded = Array(try readExactly(length))
            let payload = Data(encoded.enumerated().map { $0.element ^ mask[$0.offset % 4] })
            if opcode == 9 {
                try sendFrame(opcode: 10, payload: payload)
                continue
            }
            return (opcode, payload)
        }
    }

    private func ready(_ events: Int16) throws {
        while true {
            guard !cancelled() else { throw WebSocketFixtureError.stopped }
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw WebSocketFixtureError.timeout }
            let remaining = Int32(max(1, min(50, (deadline - now) / 1_000_000)))
            var item = pollfd(fd: fd, events: events, revents: 0)
            let count = Darwin.poll(&item, 1, remaining)
            if count > 0 {
                guard item.revents & Int16(POLLNVAL) == 0 else { throw WebSocketFixtureError.invalid("Closed fixture descriptor") }
                return // recv/send reports EOF and other socket errors, including POLLHUP.
            }
            guard count == 0 || errno == EINTR else { throw WebSocketFixtureError.system("poll", errno) }
        }
    }

    private func readExactly(_ count: Int) throws -> Data {
        var bytes = Data()
        while bytes.count < count {
            try ready(Int16(POLLIN))
            var buffer = [UInt8](repeating: 0, count: count - bytes.count)
            let received = buffer.withUnsafeMutableBytes { Darwin.recv(fd, $0.baseAddress, $0.count, 0) }
            if received == 0 { throw WebSocketFixtureError.peerClosed }
            if received > 0 { bytes.append(contentsOf: buffer.prefix(received)); continue }
            guard errno == EINTR || errno == EAGAIN else { throw WebSocketFixtureError.system("recv", errno) }
        }
        return bytes
    }

    private func write(_ bytes: Data) throws {
        var offset = 0
        while offset < bytes.count {
            try ready(Int16(POLLOUT))
            let sent = bytes.withUnsafeBytes {
                Darwin.send(fd, $0.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
            }
            if sent > 0 { offset += sent; continue }
            guard sent < 0, errno == EINTR || errno == EAGAIN else { throw WebSocketFixtureError.system("send", errno) }
        }
    }
}
