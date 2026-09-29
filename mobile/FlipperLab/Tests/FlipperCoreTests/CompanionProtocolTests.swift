import XCTest
@testable import FlipperCore

// Wire vectors are derived by hand from assets/protobuf/{flipper,network,gps}.proto: key = field << 3 | wire
// type, base-128 varints, sint32 zigzag, and zero-valued proto3 fields omitted as nanopb does. They are not
// produced by the Swift encoder under test. Replies keep RPCEnvelope.encode's explicit command_id 0 (08 00).
final class CompanionProtocolTests: XCTestCase {
    // MARK: - Firmware request vectors

    func testConnectVectorsFromPingExample() throws {
        // network_connect(network, 0x51, "one.one.one.one", 80, NetworkProtocolTcp, 3000)
        var tcpFrame: [UInt8] = [0x1b, 0xe2, 0x04, 0x18, 0x0a, 0x0f]
        tcpFrame += Array("one.one.one.one".utf8)
        tcpFrame += [0x10, 0x50, 0x20, 0xb8, 0x17, 0x28, 0x51]
        guard case .connect(let tcpRequest) = try parse(tcpFrame) else { return XCTFail("expected connect") }
        XCTAssertEqual(tcpRequest.connectionID, 0x51)
        XCTAssertEqual(tcpRequest.host, "one.one.one.one")
        XCTAssertEqual(tcpRequest.port, 80)
        XCTAssertEqual(tcpRequest.transport, .tcp)
        XCTAssertEqual(tcpRequest.timeoutMilliseconds, 3000)

        // network_connect(network, 0x51, "1.1.1.1", 53, NetworkProtocolUdp, 3000)
        var udpFrame: [UInt8] = [0x15, 0xe2, 0x04, 0x12, 0x0a, 0x07]
        udpFrame += Array("1.1.1.1".utf8)
        udpFrame += [0x10, 0x35, 0x18, 0x01, 0x20, 0xb8, 0x17, 0x28, 0x51]
        guard case .connect(let udpRequest) = try parse(udpFrame) else { return XCTFail("expected connect") }
        XCTAssertEqual(udpRequest.connectionID, 0x51)
        XCTAssertEqual(udpRequest.host, "1.1.1.1")
        XCTAssertEqual(udpRequest.port, 53)
        XCTAssertEqual(udpRequest.transport, .udp)
    }

    func testSendCloseAndGPSVectors() throws {
        // network_websocket_send(network, 21, {0x00, 0xff, 0x80}, 3, true)
        let sendFrame: [UInt8] = [0x0c, 0xf2, 0x04, 0x09, 0x08, 0x15, 0x12, 0x03, 0x00, 0xff, 0x80, 0x18, 0x01]
        guard case .send(let sent) = try parse(sendFrame) else { return XCTFail("expected send") }
        XCTAssertEqual(sent.connectionID, 21)
        XCTAssertEqual(sent.data, Data([0x00, 0xff, 0x80]))
        XCTAssertTrue(sent.isBinary)

        guard case .close(let closed) = try parse([0x05, 0x8a, 0x05, 0x02, 0x08, 0x15]) else {
            return XCTFail("expected close")
        }
        XCTAssertEqual(closed.connectionID, 21)

        guard case .startGPSStream(let stream) = try parse([0x05, 0xa2, 0x05, 0x02, 0x08, 0x0a]) else {
            return XCTFail("expected stream start")
        }
        XCTAssertEqual(stream.updatesPerSecond, 10)
        XCTAssertEqual(try parse([0x03, 0xaa, 0x05, 0x00]), .stopGPSStream)
        XCTAssertEqual(try parse([0x03, 0xb2, 0x05, 0x00]), .requestGPSLocation)
    }

    func testHTTPAndWebSocketVectors() throws {
        // Like network.c's GET (1000 ms timeout), but saving under /ext.
        var getFrame: [UInt8] = [0x31, 0xc2, 0x05, 0x2e, 0x08, 0x01, 0x1a, 0x14]
        getFrame += Array("https://example.com/".utf8)
        getFrame += [0x3a, 0x11]
        getFrame += Array("/ext/response.txt".utf8)
        getFrame += [0x40, 0xe8, 0x07]
        guard case .http(let download) = try parse(getFrame) else { return XCTFail("expected HTTP") }
        XCTAssertEqual(download.requestID, 1)
        XCTAssertEqual(download.method, .get)
        XCTAssertEqual(download.url.absoluteString, "https://example.com/")
        XCTAssertEqual(download.headers, [])
        XCTAssertEqual(download.body, Data())
        XCTAssertNil(download.sendPath)
        XCTAssertEqual(download.savePath, "/ext/response.txt")
        XCTAssertEqual(download.timeoutMilliseconds, 1000)
        XCTAssertFalse(download.includeResponseHeaders)

        var postFrame: [UInt8] = [0x4d, 0xc2, 0x05, 0x4a, 0x08, 0x0c, 0x10, 0x01, 0x1a, 0x19]
        postFrame += Array("https://example.com/a?b=c".utf8)
        postFrame += [0x22, 0x23]
        postFrame += Array("Content-Type: text/plain\r\nX-Id: 7\r\n".utf8)
        postFrame += [0x2a, 0x02, 0x68, 0x69, 0x48, 0x01]
        guard case .http(let upload) = try parse(postFrame) else { return XCTFail("expected HTTP") }
        let expected = try [CompanionHTTPHeader(name: "Content-Type", value: "text/plain"),
                            CompanionHTTPHeader(name: "X-Id", value: "7")]
        XCTAssertEqual(upload.requestID, 12)
        XCTAssertEqual(upload.method, .post)
        XCTAssertEqual(upload.url.absoluteString, "https://example.com/a?b=c")
        XCTAssertEqual(upload.headers, expected)
        XCTAssertEqual(upload.body, Data("hi".utf8))
        XCTAssertEqual(upload.timeoutMilliseconds, 30_000)
        XCTAssertTrue(upload.includeResponseHeaders)

        // websocket.c: network_websocket_open(network, 21, "wss://echo.websocket.org", NULL, 15000)
        var openFrame: [UInt8] = [0x22, 0xd2, 0x05, 0x1f, 0x08, 0x15, 0x12, 0x18]
        openFrame += Array("wss://echo.websocket.org".utf8)
        openFrame += [0x20, 0x98, 0x75]
        guard case .openWebSocket(let socket) = try parse(openFrame) else { return XCTFail("expected WebSocket") }
        XCTAssertEqual(socket.connectionID, 21)
        XCTAssertEqual(socket.url.absoluteString, "wss://echo.websocket.org")
        XCTAssertEqual(socket.headers, [])
        XCTAssertEqual(socket.timeoutMilliseconds, 15_000)
    }

    // MARK: - Envelope and wire rules

    func testStatusIsEncodedOnlyWhenNonzero() throws {
        XCTAssertEqual(RPCEnvelope.encode(id: 1, tag: 32), Data([5, 8, 1, 0x82, 2, 0]))
        XCTAssertEqual(RPCEnvelope.encode(id: 0, tag: 87, status: 61), Data([7, 8, 0, 16, 61, 0xba, 5, 0]))
        XCTAssertEqual(RPCEnvelope.encode(id: 5, tag: 4, hasNext: true, status: 2), Data([8, 8, 5, 16, 2, 24, 1, 34, 0]))
        let frame = try envelope(87, Data(), status: 61)
        XCTAssertEqual(frame.status, 61)
        XCTAssertEqual(frame.tag, 87)
    }

    func testOnlyUnsolicitedCompanionRequestsAreAccepted() throws {
        let closePayload = PBMessage.uint(1, 21)
        XCTAssertEqual(try request(81, closePayload).connectionID, 21)
        XCTAssertThrowsError(try request(81, closePayload, id: 5))
        XCTAssertThrowsError(try request(81, closePayload, hasNext: true))
        XCTAssertThrowsError(try request(81, closePayload, status: 1))
        for tag in [4, 58, 77, 79, 80, 82, 83, 87, 89, 100] {
            XCTAssertThrowsError(try request(tag, Data()), "tag \(tag)")
        }
        XCTAssertEqual(CompanionRequest.tags, [76, 78, 81, 84, 85, 86, 88, 90])
    }

    func testStrictMessageRejectsDuplicateOneofAndMistypedFields() throws {
        XCTAssertEqual(try CompanionRequest(message: Data([0x8a, 0x05, 0x02, 0x08, 0x15])).connectionID, 21)
        let explicitDefaults: [UInt8] = [0x08, 0x00, 0x10, 0x00, 0x18, 0x00, 0x8a, 0x05, 0x02, 0x08, 0x15]
        XCTAssertEqual(try CompanionRequest(message: Data(explicitDefaults)).connectionID, 21)
        let rejected: [[UInt8]] = [
            [],
            [0x08, 0x00],                                                  // no content
            [0x8a, 0x05, 0x02, 0x08, 0x15, 0xaa, 0x05, 0x00],              // two oneof members
            [0x8a, 0x05, 0x02, 0x08, 0x15, 0x8a, 0x05, 0x02, 0x08, 0x16],  // one member twice
            [0x88, 0x05, 0x01],                                            // content as a varint
            [0x0a, 0x00, 0x8a, 0x05, 0x02, 0x08, 0x15],                    // command_id as bytes
            [0x08, 0x00, 0x08, 0x00, 0x8a, 0x05, 0x02, 0x08, 0x15],        // command_id repeated
            [0x08, 0x01, 0x8a, 0x05, 0x02, 0x08, 0x15],                    // command_id 1
            [0x10, 0x01, 0x8a, 0x05, 0x02, 0x08, 0x15],                    // command_status ERROR
            [0x18, 0x01, 0x8a, 0x05, 0x02, 0x08, 0x15],                    // has_next
            [0x0d, 0x00, 0x00, 0x00, 0x00, 0x8a, 0x05, 0x02, 0x08, 0x15],  // fixed32 field
            [0x8a, 0x05, 0x03, 0x08, 0x15],                                // length past the end
            [0xba, 0x05, 0x00],                                            // gps_location is a reply
        ]
        for message in rejected {
            XCTAssertThrowsError(try CompanionRequest(message: Data(message)), "\(message)")
        }
    }

    func testPayloadWireRules() throws {
        let rejected: [(tag: Int, payload: [UInt8])] = [
            (81, [0x08, 0x15, 0x08, 0x16]),                                // repeated field
            (81, [0x0a, 0x01, 0x15]),                                      // varint field sent as bytes
            (81, [0x0d, 0x15, 0x00, 0x00, 0x00]),                          // fixed32
            (81, [0x09, 0x15, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),  // fixed64
            (81, [0x0b]),                                                  // group
            (81, [0x08, 0x15, 0x10, 0x01]),                                // field 2 is not in CloseRequest
            (81, [0x08, 0x95]),                                            // truncated varint
            (81, [0x08, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f]),  // beyond 64 bits
            (84, [0x08, 0x01, 0x08, 0x02]),                                // repeated frequency
            (78, [0x08, 0x15, 0x12, 0x05, 0x00]),                          // bytes past the end
            (78, [0x08, 0x15, 0x10, 0x01]),                                // bytes field sent as varint
            (76, [0x0a, 0x01, 0x61, 0x10, 0x50, 0x28, 0x01, 0x30, 0x01]),  // unknown field 6
            (85, [0x08, 0x01]),                                            // StreamStopRequest has no fields
            (86, [0x08, 0x00]),                                            // LocationRequest has no fields
        ]
        for (tag, payload) in rejected {
            XCTAssertThrowsError(try request(tag, Data(payload)), "tag \(tag): \(payload)")
        }
        // The same connect payload without field 6 is valid.
        XCTAssertEqual(try request(76, Data([0x0a, 0x01, 0x61, 0x10, 0x50, 0x28, 0x01])).connectionID, 1)
    }

    func testUInt32FieldsRejectOutOfRangeInsteadOfTruncating() throws {
        // 2^32 + 21 would truncate to connection 21.
        XCTAssertThrowsError(try request(81, Data([0x08, 0x95, 0x80, 0x80, 0x80, 0x10])))
        XCTAssertEqual(try request(81, PBMessage.uint(1, 0)).connectionID, 0)
        XCTAssertEqual(try request(81, Data()).connectionID, 0)
        XCTAssertThrowsError(try connect(timeout: 1 << 32))
        XCTAssertThrowsError(try connect(port: (1 << 32) + 80))
        XCTAssertThrowsError(try connect(transport: UInt64.max))  // enum value -1
        XCTAssertThrowsError(try request(84, PBMessage.uint(1, (1 << 32) + 1)))
        XCTAssertThrowsError(try http(id: (1 << 32) + 3))
        XCTAssertThrowsError(try http(method: (1 << 32) + 1))
        XCTAssertThrowsError(try http(includeHeaders: (1 << 32) + 1))
    }

    // MARK: - Request field rules

    func testConnectFieldRules() throws {
        let valid = try connect()
        XCTAssertEqual(valid.host, "example.com")
        XCTAssertEqual(valid.port, 443)
        XCTAssertEqual(valid.transport, .tcp)
        XCTAssertEqual(valid.timeoutMilliseconds, 30_000)
        XCTAssertEqual(try connect(host: String(repeating: "a", count: 255)).host.utf8.count, 255)
        XCTAssertEqual(try connect(host: "例子.测试").host, "例子.测试")
        XCTAssertThrowsError(try connect(host: String(repeating: "a", count: 256))) {
            XCTAssertEqual($0 as? RPCError, .tooLarge)
        }
        let hosts = ["", "exa mple.com", "example.com\t", "a\u{0}b", "a\u{7f}b", "a\u{85}b", "a\u{a0}b", "a\u{200b}b",
                     "a\u{2028}b"]
        for host in hosts {
            XCTAssertThrowsError(try connect(host: host), host.debugDescription)
        }
        var invalidUTF8 = PBMessage.bytes(1, Data([0x61, 0xff]))
        invalidUTF8 += PBMessage.uint(2, 80)
        invalidUTF8 += PBMessage.uint(5, 1)
        XCTAssertThrowsError(try request(76, invalidUTF8))
        XCTAssertEqual(try connect(port: 1).port, 1)
        XCTAssertEqual(try connect(port: 65_535).port, 65_535)
        XCTAssertThrowsError(try connect(port: 0))
        XCTAssertThrowsError(try connect(port: 65_536))
        XCTAssertEqual(try connect(transport: 1).transport, .udp)
        XCTAssertThrowsError(try connect(transport: 2))
        XCTAssertEqual(try connect(id: 0).connectionID, 0)
        let timeouts: [(wire: UInt64, effective: UInt32)] = [
            (0, 30_000), (1, 1_000), (999, 1_000), (1_000, 1_000), (45_000, 45_000),
            (120_000, 120_000), (120_001, 120_000), (UInt64(UInt32.max), 120_000),
        ]
        for (wire, effective) in timeouts {
            XCTAssertEqual(try connect(timeout: wire).timeoutMilliseconds, effective, "\(wire)")
        }
    }

    func testSendRules() throws {
        func send(_ data: Data, binary: UInt64 = 0, id: UInt64 = 21) throws -> CompanionSendRequest {
            var payload = PBMessage.uint(1, id)
            payload += PBMessage.bytes(2, data)
            payload += PBMessage.uint(3, binary)
            guard case .send(let parsed) = try request(78, payload) else { throw RPCError.malformed }
            return parsed
        }
        XCTAssertEqual(try send(Data(repeating: 7, count: 512)).data.count, 512)
        XCTAssertFalse(try send(Data([1])).isBinary)
        XCTAssertThrowsError(try send(Data(repeating: 7, count: 513))) { XCTAssertEqual($0 as? RPCError, .tooLarge) }
        XCTAssertThrowsError(try send(Data()))
        XCTAssertThrowsError(try send(Data([1]), binary: 2))
        XCTAssertEqual(try send(Data([1]), id: 0).connectionID, 0)
    }

    func testGPSRequestRules() throws {
        for frequency: UInt64 in [1, 10] {
            guard case .startGPSStream(let stream) = try request(84, PBMessage.uint(1, frequency)) else {
                return XCTFail("expected stream start")
            }
            XCTAssertEqual(UInt64(stream.updatesPerSecond), frequency)
        }
        XCTAssertThrowsError(try request(84, Data()))
        XCTAssertThrowsError(try request(84, PBMessage.uint(1, 0)))
        XCTAssertThrowsError(try request(84, PBMessage.uint(1, 11)))
        XCTAssertEqual(try request(85, Data()), .stopGPSStream)
        XCTAssertEqual(try request(86, Data()), .requestGPSLocation)
        XCTAssertNil(try request(86, Data()).connectionID)
    }

    func testHTTPURLRules() throws {
        let accepted: [String] = [
            "https://example.com/", "http://example.com", "HTTPS://Example.COM/Path", "http://10.0.0.2:8080/api?x=1&y=%20z",
            "http://[::1]:8080/", "http://[2001:db8::1]/", "https://example.com?q=1", "https://example.com./users/@me",
            "http://localhost:65535/", "https://example.com/" + String(repeating: "a", count: 2028),
        ]
        for url in accepted {
            XCTAssertNoThrow(try http(url: url), url)
        }
        XCTAssertEqual(try http(url: "http://[::1]:8080/").url.port, 8080)
        let rejected: [String] = [
            "", "ftp://example.com/", "wss://example.com/", "javascript:alert(1)", "https:example.com", "https:///path",
            "https://user@example.com/", "https://user:pw@example.com/", "https://example.com/#top",
            "https://example.com/a b", "https://example.com/a\\b", "https://exa\\mple.com/", "https://example.com:0/",
            "https://example.com:65536/", "https://example.com:/", "https://example.com:8a/", "https://example.com/%zz",
            "https://example.com/%4", "https://例子.测试/", "https://[::1/", "https://[fe80::1%25en0]/", "https://[::1]x/",
            "https://[1.2.3.4]/", "http://example.com/a[b]", "https://.example.com/", "https://a..b/",
            "https://example.com/\u{7f}", "https://example.com/\r\nHost: x",
        ]
        for url in rejected {
            XCTAssertThrowsError(try http(url: url), url.debugDescription)
        }
        XCTAssertThrowsError(try http(url: "https://example.com/" + String(repeating: "a", count: 2029))) {
            XCTAssertEqual($0 as? RPCError, .tooLarge)
        }
    }

    func testWebSocketRules() throws {
        XCTAssertEqual(try webSocket("ws://192.168.1.2:8765/socket?room=1").url.port, 8765)
        XCTAssertNoThrow(try webSocket("WSS://example.com/"))
        XCTAssertEqual(try webSocket("wss://example.com/", headers: "Sec-WebSocket-Protocol: chat").headers.map(\.name),
                       ["Sec-WebSocket-Protocol"])
        XCTAssertEqual(try webSocket("wss://example.com/", timeout: 500_000).timeoutMilliseconds, 120_000)
        for url in ["https://example.com/", "http://example.com/", "wss://example.com/#x", "wss://u@example.com/", "ws://"] {
            XCTAssertThrowsError(try webSocket(url), url)
        }
        XCTAssertThrowsError(try webSocket("wss://example.com/", headers: "A: b\r\n\r\nGET / HTTP/1.1"))
    }

    func testHeaderRows() throws {
        let single = try CompanionHTTPHeader(name: "A", value: "b")
        XCTAssertEqual(try http(headers: "A: b").headers, [single])
        let rows = try http(headers: "Accept: */*\r\nX-Token: abc\r\n").headers
        XCTAssertEqual(rows.map(\.name), ["Accept", "X-Token"])
        XCTAssertEqual(rows.map(\.value), ["*/*", "abc"])
        XCTAssertEqual(try http(headers: "A:b\nC: \t d \t\n").headers.map(\.value), ["b", "d"])
        XCTAssertEqual(try http(headers: "X-Empty:").headers.map(\.value), [""])
        XCTAssertEqual(try http(headers: "X-Name: 中文").headers.map(\.value), ["中文"])
        XCTAssertEqual(try http(headers: "X: " + String(repeating: "a", count: 8189)).headers.count, 1)
        let rejected: [String] = [
            "A: b\r\n\r\nC: d", "A: b\n\n", "\r\nA: b", "A: b\rC: d", "A: b\r", "Bad Name: x", ": x", "NoColon",
            " A: b", "A: b\n c", "A: b\u{0}c", "A: b\u{7f}", "A: \u{85}", "Ä: b", "A: b\r\nInjected",
        ]
        for headers in rejected {
            XCTAssertThrowsError(try http(headers: headers), headers.debugDescription)
        }
        XCTAssertThrowsError(try http(headers: "X: " + String(repeating: "a", count: 8190))) {
            XCTAssertEqual($0 as? RPCError, .tooLarge)
        }
        // An overlong UTF-8 newline (C0 8A) must not pass as text.
        var payload = PBMessage.uint(1, 3)
        payload += PBMessage.string(3, "https://example.com/")
        payload += PBMessage.bytes(4, Data([0x41, 0x3a, 0x20, 0xc0, 0x8a]))
        XCTAssertThrowsError(try request(88, payload))
        XCTAssertThrowsError(try CompanionHTTPHeader(name: "X", value: "a\r\nInjected: 1"))
        XCTAssertEqual(try CompanionHTTPHeader(name: "X", value: " \tv\t ").value, "v")
    }

    func testSDPathRules() throws {
        XCTAssertNil(try http().savePath)
        let accepted: [String] = ["/ext/response.txt", "/ext/apps_data/net/a b.txt", "/ext/中文.txt", "/ext/.hidden",
                                  "/ext/" + String(repeating: "a", count: 250)]
        for path in accepted {
            XCTAssertEqual(try http(savePath: path).savePath, path)
            XCTAssertEqual(try http(sendPath: path).sendPath, path)
        }
        // "/data/..." is APP_DATA_PATH, which the firmware resolves per calling app; network.c uses it.
        let rejected: [String] = [
            "/data/networktest_response.txt", "/ext", "/ext/", "/ext//a", "/ext/./a", "/ext/../int/a", "/ext/a/..",
            "ext/a", "/ext/a\\b", "/ext/a\u{0}b", "/ext/a\nb", "/int/a", "/EXT/a", "/ext/a\u{202e}txt.exe", "/any/ext/a",
        ]
        for path in rejected {
            XCTAssertThrowsError(try http(savePath: path), path.debugDescription)
            XCTAssertThrowsError(try http(sendPath: path), path.debugDescription)
        }
        XCTAssertThrowsError(try http(savePath: "/ext/" + String(repeating: "a", count: 251))) {
            XCTAssertEqual($0 as? RPCError, .tooLarge)
        }
    }

    func testHTTPBodyMethodAndFlags() throws {
        XCTAssertEqual(try http(method: 5).method, .head)
        XCTAssertEqual(try http(body: Data(repeating: 1, count: 512)).body.count, 512)
        XCTAssertThrowsError(try http(body: Data(repeating: 1, count: 513))) { XCTAssertEqual($0 as? RPCError, .tooLarge) }
        XCTAssertThrowsError(try http(method: 6))
        XCTAssertEqual(try http(id: 0).requestID, 0)
        XCTAssertThrowsError(try http(includeHeaders: 2))
        XCTAssertTrue(try http(includeHeaders: 1).includeResponseHeaders)
        XCTAssertEqual(try http(sendPath: "/ext/body.bin").sendPath, "/ext/body.bin")
        XCTAssertThrowsError(try http(body: Data([1]), sendPath: "/ext/body.bin"))
        XCTAssertEqual(try http(timeout: 200_000).timeoutMilliseconds, 120_000)
        XCTAssertEqual(CompanionHTTPMethod.allCases.map(\.name), ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"])
    }

    func testReplyIDSurvivesRejectedPayloads() throws {
        var badHost = PBMessage.string(1, "bad host")
        badHost += PBMessage.uint(2, 80)
        badHost += PBMessage.uint(5, 9)
        let rejectedConnect = try envelope(76, badHost)
        XCTAssertThrowsError(try CompanionRequest(rejectedConnect))
        XCTAssertEqual(CompanionRequest.replyID(for: rejectedConnect), 9)

        var badURL = PBMessage.uint(1, 12)
        badURL += PBMessage.string(3, "https://example.com/#x")
        let rejectedHTTP = try envelope(88, badURL)
        XCTAssertThrowsError(try CompanionRequest(rejectedHTTP))
        XCTAssertEqual(CompanionRequest.replyID(for: rejectedHTTP), 12)

        XCTAssertEqual(try CompanionRequest.replyID(for: envelope(78, PBMessage.uint(1, 21))), 21)
        XCTAssertNil(try CompanionRequest.replyID(for: envelope(84, PBMessage.uint(1, 11))))
        XCTAssertEqual(try CompanionRequest.replyID(for: envelope(81, Data())), 0)
        XCTAssertNil(try CompanionRequest.replyID(for: envelope(81, PBMessage.uint(1, 1 << 32))))
        XCTAssertNil(try CompanionRequest.replyID(for: envelope(81, Data([0x08]))))
    }

    // MARK: - Replies

    func testNetworkReplyVectors() throws {
        XCTAssertEqual(try CompanionResponse.connect(connectionID: 0x51, state: .connected, resolvedIP: "1.1.1.1"),
                       Data([0x12, 0x08, 0x00, 0xea, 0x04, 0x0d, 0x08, 0x51, 0x10, 0x02, 0x22, 0x07,
                             0x31, 0x2e, 0x31, 0x2e, 0x31, 0x2e, 0x31]))
        XCTAssertEqual(try CompanionResponse.connect(connectionID: 21, state: .error, error: .tlsFailed),
                       Data([0x0b, 0x08, 0x00, 0xea, 0x04, 0x06, 0x08, 0x15, 0x10, 0x03, 0x18, 0x0d]))
        XCTAssertEqual(try CompanionResponse.send(connectionID: 21, bytesSent: 3),
                       Data([0x09, 0x08, 0x00, 0xfa, 0x04, 0x04, 0x08, 0x15, 0x10, 0x03]))
        XCTAssertEqual(try CompanionResponse.received(connectionID: 21, data: Data([0x00, 0xff]), binary: true),
                       Data([0x0d, 0x08, 0x00, 0x82, 0x05, 0x08, 0x08, 0x15, 0x12, 0x02, 0x00, 0xff, 0x18, 0x01]))
        XCTAssertEqual(try CompanionResponse.close(connectionID: 21),
                       Data([0x07, 0x08, 0x00, 0x92, 0x05, 0x02, 0x08, 0x15]))
        XCTAssertEqual(try CompanionResponse.close(connectionID: 21, error: .notConnected),
                       Data([0x09, 0x08, 0x00, 0x92, 0x05, 0x04, 0x08, 0x15, 0x10, 0x07]))
        XCTAssertEqual(try CompanionResponse.stateChanged(connectionID: 21, state: .disconnected, error: .receiveFailed),
                       Data([0x09, 0x08, 0x00, 0x9a, 0x05, 0x04, 0x08, 0x15, 0x18, 0x09]))
        var okFrame: [UInt8] = [0x2a, 0x08, 0x00, 0xca, 0x05, 0x25, 0x08, 0x01, 0x10, 0xc8, 0x01, 0x22, 0x19]
        okFrame += Array("Content-Type: text/html\r\n".utf8)
        okFrame += [0x28, 0xe8, 0x09, 0x30, 0x01]
        let html = try CompanionHTTPHeader(name: "Content-Type", value: "text/html")
        XCTAssertEqual(try CompanionResponse.http(requestID: 1, statusCode: 200, headers: [html], bodySize: 1256,
                                                  savedToFile: true), Data(okFrame))
        XCTAssertEqual(try CompanionResponse.http(requestID: 12, statusCode: 0, error: .dnsFailed),
                       Data([0x09, 0x08, 0x00, 0xca, 0x05, 0x04, 0x08, 0x0c, 0x18, 0x01]))
    }

    func testLocationVectorsAndZigzag() throws {
        let fix = try location(latitude: -33.8688, longitude: 151.2093, altitude: -12.34, speed: 1.234, course: 12.34,
                               accuracy: 1.234)
        XCTAssertEqual(fix.latitudeE7, -338_688_000)
        XCTAssertEqual(fix.longitudeE7, 1_512_093_000)
        XCTAssertEqual(fix.altitudeCentimeters, -1234)
        XCTAssertEqual(fix.speedMillimetersPerSecond, 1234)
        XCTAssertEqual(fix.headingCentidegrees, 1234)
        XCTAssertEqual(fix.accuracyMillimeters, 1234)
        XCTAssertEqual(fix.satellites, 0)
        XCTAssertEqual(CompanionResponse.location(fix), Data([
            0x1d, 0x08, 0x00, 0xba, 0x05, 0x18,
            0x08, 0xff, 0xdf, 0xff, 0xc2, 0x02,  // latitude, zigzag 677375999
            0x10, 0x90, 0xd5, 0x85, 0xa2, 0x0b,  // longitude, zigzag 3024186000
            0x18, 0xd2, 0x09, 0x20, 0xd2, 0x09,  // heading and speed 1234
            0x28, 0xa3, 0x13,                    // altitude, zigzag 2467
            0x30, 0xd2, 0x09,                    // accuracy 1234; satellites 0 is omitted
        ]))
        XCTAssertEqual(try CompanionResponse.location(location(accuracy: 0)), Data([5, 8, 0, 0xba, 5, 0]))
        XCTAssertEqual(try CompanionResponse.location(location(satellites: 7)).suffix(2), Data([0x38, 0x07]))
        let pairs: [(Int32, UInt32)] = [
            (0, 0), (-1, 1), (1, 2), (-2, 3), (.max, 4_294_967_294), (.min, 4_294_967_295),
            (-338_688_000, 677_375_999), (1_512_093_000, 3_024_186_000), (-1234, 2467),
        ]
        for (value, encoded) in pairs {
            XCTAssertEqual(CompanionResponse.zigzag(value), encoded, "\(value)")
            XCTAssertEqual(signed(UInt64(encoded)), value)
        }
        for status in CompanionGPSStatus.allCases {
            XCTAssertEqual(CompanionResponse.locationUnavailable(status),
                           Data([7, 8, 0, 16, UInt8(status.rawValue), 0xba, 5, 0]))
        }
    }

    func testLocationLimitsAndRoundTrip() throws {
        let north = try location(latitude: 90, longitude: -180, altitude: 1e12, speed: -1, course: -1, accuracy: 5e6)
        XCTAssertEqual(north.latitudeE7, 900_000_000)
        XCTAssertEqual(north.longitudeE7, -1_800_000_000)
        XCTAssertEqual(north.altitudeCentimeters, .max)
        XCTAssertEqual(north.speedMillimetersPerSecond, 0)
        XCTAssertEqual(north.headingCentidegrees, 0)
        XCTAssertEqual(north.accuracyMillimeters, .max)

        let south = try location(latitude: -90, longitude: 180, altitude: -1e12, speed: 1e10, course: 400, accuracy: 0,
                                 satellites: 12)
        XCTAssertEqual(south.latitudeE7, -900_000_000)
        XCTAssertEqual(south.longitudeE7, 1_800_000_000)
        XCTAssertEqual(south.altitudeCentimeters, .min)
        XCTAssertEqual(south.speedMillimetersPerSecond, .max)
        XCTAssertEqual(south.headingCentidegrees, 36_000)
        XCTAssertEqual(south.accuracyMillimeters, 0)
        XCTAssertEqual(south.satellites, 12)

        let tiny = try location(latitude: 6e-8, longitude: -6e-8, altitude: 0.004, speed: 0.0004, course: 359.996,
                                accuracy: 0.0004, satellites: 255)
        XCTAssertEqual(tiny.latitudeE7, 1)
        XCTAssertEqual(tiny.longitudeE7, -1)
        XCTAssertEqual(tiny.altitudeCentimeters, 0)
        XCTAssertEqual(tiny.speedMillimetersPerSecond, 0)
        XCTAssertEqual(tiny.headingCentidegrees, 36_000)
        XCTAssertEqual(tiny.accuracyMillimeters, 0)

        for sample in [north, south, tiny] {
            let (frame, fields) = try decode(CompanionResponse.location(sample))
            XCTAssertEqual(frame.tag, 87)
            XCTAssertEqual(frame.commandID, 0)
            XCTAssertEqual(frame.status, 0)
            XCTAssertFalse(frame.hasNext)
            XCTAssertEqual(signed(fields.uint(1)), sample.latitudeE7)
            XCTAssertEqual(signed(fields.uint(2)), sample.longitudeE7)
            XCTAssertEqual(fields.uint(3), UInt64(sample.headingCentidegrees))
            XCTAssertEqual(fields.uint(4), UInt64(sample.speedMillimetersPerSecond))
            XCTAssertEqual(signed(fields.uint(5)), sample.altitudeCentimeters)
            XCTAssertEqual(fields.uint(6), UInt64(sample.accuracyMillimeters))
            XCTAssertEqual(fields.uint(7), UInt64(sample.satellites))
        }

        XCTAssertThrowsError(try location(latitude: 90.000_000_1))
        XCTAssertThrowsError(try location(latitude: -90.5))
        XCTAssertThrowsError(try location(longitude: 180.1))
        XCTAssertThrowsError(try location(longitude: -181))
        XCTAssertThrowsError(try location(latitude: -180, longitude: -180))  // CoreLocation's invalid coordinate
        XCTAssertThrowsError(try location(latitude: .nan))
        XCTAssertThrowsError(try location(longitude: .infinity))
        XCTAssertThrowsError(try location(altitude: -Double.infinity))
        XCTAssertThrowsError(try location(speed: .nan))
        XCTAssertThrowsError(try location(course: .infinity))
        XCTAssertThrowsError(try location(accuracy: -1))
        XCTAssertThrowsError(try location(accuracy: .nan))
    }

    func testReplyInputsAreRangeChecked() throws {
        XCTAssertNoThrow(try CompanionResponse.connect(connectionID: 0, state: .connected))
        XCTAssertThrowsError(try CompanionResponse.connect(connectionID: 1, state: .connected, error: .timeout))
        XCTAssertThrowsError(try CompanionResponse.connect(connectionID: 1, state: .error))
        XCTAssertThrowsError(try CompanionResponse.stateChanged(connectionID: 1, state: .connecting, error: .sendFailed))
        XCTAssertNoThrow(try CompanionResponse.connect(connectionID: 1, state: .disconnected, error: .dnsFailed))
        XCTAssertEqual(try CompanionResponse.connect(connectionID: 1, state: .connected, resolvedIP: ""),
                       try CompanionResponse.connect(connectionID: 1, state: .connected))
        for ip in ["1.1.1.1", "::1", "::", "2001:db8::1", "::ffff:192.0.2.1", "1:2:3:4:5:6:7:8", "FE80::1"] {
            XCTAssertNoThrow(try CompanionResponse.connect(connectionID: 1, state: .connected, resolvedIP: ip), ip)
        }
        let invalidIPs: [String] = [
            "256.1.1.1", "01.1.1.1", "1.1.1", "1.1.1.1.1", "fe80::1%en0", "example.com", " 1.1.1.1", "1:2:3:4:5:6:7:8:9",
            "1::2::3", ":1", "1:", "12345::1", "1.2.3.4::", "::ffff:1.2.3.4:1", String(repeating: "1", count: 46),
        ]
        for ip in invalidIPs {
            XCTAssertThrowsError(try CompanionResponse.connect(connectionID: 1, state: .connected, resolvedIP: ip), ip)
        }
        XCTAssertNoThrow(try CompanionResponse.send(connectionID: 1, bytesSent: 512))
        XCTAssertNoThrow(try CompanionResponse.send(connectionID: 1, bytesSent: 0, error: .sendFailed))
        XCTAssertThrowsError(try CompanionResponse.send(connectionID: 1, bytesSent: 513))
        XCTAssertThrowsError(try CompanionResponse.send(connectionID: 1, bytesSent: -1))
        XCTAssertThrowsError(try CompanionResponse.received(connectionID: 1, data: Data(count: 513))) {
            XCTAssertEqual($0 as? RPCError, .tooLarge)
        }
        XCTAssertEqual(try CompanionResponse.received(connectionID: 1, data: Data()), Data([7, 8, 0, 0x82, 5, 2, 8, 1]))
        XCTAssertNoThrow(try CompanionResponse.close(connectionID: 0))
        for status in [-1, 99, 600] {
            XCTAssertThrowsError(try CompanionResponse.http(requestID: 1, statusCode: status), "\(status)")
        }
        XCTAssertThrowsError(try CompanionResponse.http(requestID: 1, statusCode: 0))
        XCTAssertNoThrow(try CompanionResponse.http(requestID: 0, statusCode: 200))
        XCTAssertThrowsError(try CompanionResponse.http(requestID: 1, statusCode: 200, bodySize: -1))
        XCTAssertThrowsError(try CompanionResponse.http(requestID: 1, statusCode: 200, bodySize: Int(UInt32.max) + 1))
        XCTAssertNoThrow(try CompanionResponse.http(requestID: 1, statusCode: 200, bodySize: Int(UInt32.max)))
        XCTAssertThrowsError(try CompanionResponse.http(requestID: 1, statusCode: 200, error: .fileError, savedToFile: true))
        XCTAssertNoThrow(try CompanionResponse.http(requestID: 1, statusCode: 200, error: .fileError))
        let fits = try CompanionHTTPHeader(name: "X", value: String(repeating: "a", count: 8187))
        XCTAssertNoThrow(try CompanionResponse.http(requestID: 1, statusCode: 200, headers: [fits]))
        let tooLong = try CompanionHTTPHeader(name: "X", value: String(repeating: "a", count: 8188))
        XCTAssertThrowsError(try CompanionResponse.http(requestID: 1, statusCode: 200, headers: [tooLong])) {
            XCTAssertEqual($0 as? RPCError, .tooLarge)
        }
    }

    func testRepliesDecodeWithTheExistingFrameDecoder() throws {
        let chunk = Data((0..<512).map { UInt8(truncatingIfNeeded: $0) })
        let header = try CompanionHTTPHeader(name: "A", value: "b")
        let replies = try [
            CompanionResponse.connect(connectionID: 7, state: .connected, resolvedIP: "2001:db8::1"),
            CompanionResponse.received(connectionID: 7, data: chunk),
            CompanionResponse.http(requestID: 9, statusCode: 404, headers: [header], bodySize: 70_000),
        ]
        var stream = Data()
        for reply in replies { stream.append(reply) }
        var decoder = RPCFrameDecoder()
        let frames = try decoder.append(stream)
        XCTAssertEqual(frames.map(\.tag), [77, 80, 89])
        XCTAssertTrue(frames.allSatisfy { $0.commandID == 0 && $0.status == 0 && !$0.hasNext })
        let connected = try PBMessage(frames[0].payload)
        XCTAssertEqual(connected.uint(1), 7)
        XCTAssertEqual(connected.uint(2), 2)
        XCTAssertEqual(try connected.string(4), "2001:db8::1")
        let received = try PBMessage(frames[1].payload)
        XCTAssertEqual(received.bytes(2), chunk)
        XCTAssertEqual(received.uint(3), 0)
        let response = try PBMessage(frames[2].payload)
        XCTAssertEqual(response.uint(1), 9)
        XCTAssertEqual(response.uint(2), 404)
        XCTAssertEqual(try response.string(4), "A: b\r\n")
        XCTAssertEqual(response.uint(5), 70_000)
        XCTAssertEqual(response.uint(6), 0)
    }

    func testEnumCodesMatchPinnedSchema() {
        XCTAssertEqual(CompanionNetworkErrorCode.allCases.map(\.rawValue), Array(UInt32(0)...15))
        XCTAssertEqual(CompanionNetworkErrorCode.invalidURL.rawValue, 14)
        XCTAssertEqual(CompanionNetworkErrorCode.fileError.rawValue, 15)
        XCTAssertEqual(CompanionConnectionState.allCases.map(\.rawValue), [0, 1, 2, 3])
        XCTAssertEqual(CompanionSocketProtocol.allCases.map(\.rawValue), [0, 1])
        XCTAssertEqual(CompanionHTTPMethod.allCases.map(\.rawValue), Array(UInt32(0)...5))
        XCTAssertEqual(CompanionGPSStatus.allCases.map(\.rawValue), [60, 61, 62, 63])
    }

    // MARK: - Helpers

    /// Parses a firmware frame across every transport split and through the strict message entry point.
    private func parse(_ frame: [UInt8], file: StaticString = #filePath, line: UInt = #line) throws -> CompanionRequest {
        let bytes = Data(frame)
        var parsed: [CompanionRequest] = []
        for split in 0...bytes.count {
            var decoder = RPCFrameDecoder()
            let frames = try decoder.append(bytes.prefix(split)) + decoder.append(bytes.dropFirst(split))
            XCTAssertEqual(frames.count, 1, file: file, line: line)
            try parsed.append(CompanionRequest(XCTUnwrap(frames.first)))
        }
        let prefix = try XCTUnwrap(frame.firstIndex(where: { $0 < 0x80 })) + 1
        try parsed.append(CompanionRequest(message: Data(frame.dropFirst(prefix))))
        XCTAssertTrue(parsed.allSatisfy({ $0 == parsed[0] }), file: file, line: line)
        return parsed[0]
    }

    private func envelope(_ tag: Int, _ payload: Data, id: UInt32 = 0, hasNext: Bool = false,
                          status: UInt32 = 0) throws -> RPCEnvelope {
        var decoder = RPCFrameDecoder()
        let frames = try decoder.append(RPCEnvelope.encode(id: id, tag: tag, payload: payload, hasNext: hasNext,
                                                           status: status))
        XCTAssertEqual(frames.count, 1)
        return try XCTUnwrap(frames.first)
    }

    private func request(_ tag: Int, _ payload: Data, id: UInt32 = 0, hasNext: Bool = false,
                         status: UInt32 = 0) throws -> CompanionRequest {
        try CompanionRequest(envelope(tag, payload, id: id, hasNext: hasNext, status: status))
    }

    private func connect(host: String = "example.com", port: UInt64 = 443, transport: UInt64 = 0,
                         timeout: UInt64 = 0, id: UInt64 = 7) throws -> CompanionConnectRequest {
        var payload = PBMessage.string(1, host)
        payload += PBMessage.uint(2, port)
        payload += PBMessage.uint(3, transport)
        payload += PBMessage.uint(4, timeout)
        payload += PBMessage.uint(5, id)
        guard case .connect(let parsed) = try request(76, payload) else { throw RPCError.malformed }
        return parsed
    }

    private func http(id: UInt64 = 3, method: UInt64 = 0, url: String = "https://example.com/", headers: String = "",
                      body: Data = Data(), sendPath: String = "", savePath: String = "", timeout: UInt64 = 0,
                      includeHeaders: UInt64 = 0) throws -> CompanionHTTPRequest {
        var payload = PBMessage.uint(1, id)
        payload += PBMessage.uint(2, method)
        payload += PBMessage.string(3, url)
        if !headers.isEmpty { payload += PBMessage.string(4, headers) }
        if !body.isEmpty { payload += PBMessage.bytes(5, body) }
        if !sendPath.isEmpty { payload += PBMessage.string(6, sendPath) }
        if !savePath.isEmpty { payload += PBMessage.string(7, savePath) }
        payload += PBMessage.uint(8, timeout)
        payload += PBMessage.uint(9, includeHeaders)
        guard case .http(let parsed) = try request(88, payload) else { throw RPCError.malformed }
        return parsed
    }

    private func webSocket(_ url: String, headers: String = "", timeout: UInt64 = 0) throws -> CompanionWebSocketRequest {
        var payload = PBMessage.uint(1, 21)
        payload += PBMessage.string(2, url)
        if !headers.isEmpty { payload += PBMessage.string(3, headers) }
        payload += PBMessage.uint(4, timeout)
        guard case .openWebSocket(let parsed) = try request(90, payload) else { throw RPCError.malformed }
        return parsed
    }

    private func location(latitude: Double = 0, longitude: Double = 0, altitude: Double = 0, speed: Double = 0,
                          course: Double = 0, accuracy: Double = 1, satellites: UInt8 = 0) throws -> CompanionLocation {
        try CompanionLocation(latitude: latitude, longitude: longitude, altitude: altitude, speed: speed,
                              course: course, horizontalAccuracy: accuracy, satellites: satellites)
    }

    private func decode(_ frame: Data) throws -> (frame: RPCEnvelope, fields: PBMessage) {
        var decoder = RPCFrameDecoder()
        let frames = try decoder.append(frame)
        XCTAssertEqual(frames.count, 1)
        let decoded = try XCTUnwrap(frames.first)
        let fields = try PBMessage(decoded.payload)
        return (decoded, fields)
    }

    /// sint32 zigzag decoding, written independently of CompanionResponse.zigzag.
    private func signed(_ value: UInt64) -> Int32 {
        Int32(truncatingIfNeeded: Int64(value >> 1) ^ -Int64(value & 1))
    }
}
