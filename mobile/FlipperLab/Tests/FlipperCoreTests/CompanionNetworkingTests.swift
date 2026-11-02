import Foundation
import Network
import XCTest
@testable import FlipperCore

/// HTTP runs against an in-process URLProtocol; sockets only talk to a loopback listener.
/// Nothing here contacts an external host.
final class CompanionNetworkingTests: XCTestCase {
    private typealias Policy = CompanionNetworkPolicy

    // MARK: Rules

    func testTimeoutsDefaultAndClamp() {
        XCTAssertEqual(Policy.timeout(0), Policy.defaultTimeout)
        XCTAssertEqual(Policy.timeout(-1), Policy.defaultTimeout)
        XCTAssertEqual(Policy.timeout(.nan), Policy.defaultTimeout)
        XCTAssertEqual(Policy.timeout(2.5), 2.5)
        XCTAssertEqual(Policy.timeout(.infinity), Policy.maxTimeout)
        XCTAssertEqual(Policy.timeout(86_400), Policy.maxTimeout)
    }

    func testURLsAreStrictAboutSchemesCredentialsAndFragments() throws {
        let http = Policy.httpSchemes
        XCTAssertEqual(try Policy.checkedURL(makeURL("HTTPS://api.example.test:8443/a?b=c"), schemes: http).absoluteString,
                       "https://api.example.test:8443/a?b=c")
        XCTAssertEqual(try Policy.checkedURL(makeURL("wss://api.example.test/socket"), schemes: Policy.webSocketSchemes).scheme,
                       "wss")
        XCTAssertEqual(try Policy.checkedURL(makeURL("https://api.example.test/a#top"), schemes: http, dropFragment: true)
                        .absoluteString, "https://api.example.test/a")
        let rejected = [
            "ftp://api.example.test/", "file:///etc/hosts", "wss://api.example.test/",
            "https://user:pw@api.example.test/", "https://user@api.example.test/", "https://api.example.test/#frag",
            "https://api.example.test:0/", "https://api.example.test/" + String(repeating: "a", count: 2048),
        ]
        for text in rejected {
            XCTAssertThrowsError(try Policy.checkedURL(makeURL(text), schemes: http), text) {
                XCTAssertEqual($0 as? CompanionTransportError, .invalidURL, text)
            }
        }
        XCTAssertThrowsError(try Policy.checkedURL(makeURL("https://api.example.test/"), schemes: Policy.webSocketSchemes))
    }

    func testHeadersRejectInjectionReservedNamesAndOversize() throws {
        let fields = try Policy.headerFields(["X-B": "2", "Accept": "text/plain", "Authorization": "Bearer t"],
                                             forbidden: Policy.forbiddenHTTPHeaders)
        XCTAssertEqual(fields.map(\.name), ["Accept", "Authorization", "X-B"])
        let malformed: [[String: String]] = [
            ["X-A": "1\r\nInjected: yes"], ["X-A": "1\nx"], ["X-A": "\u{0}"], ["X-A": "a\u{7F}"], ["X-A": "\u{85}"],
            ["X A": "1"], ["X:A": "1"], ["": "1"], ["Ünï": "1"], ["X-A": "1", "x-a": "2"],
        ]
        for headers in malformed {
            XCTAssertThrowsError(try Policy.headerFields(headers, forbidden: []), "\(headers)") {
                XCTAssertEqual($0 as? CompanionTransportError, .invalidProtocol)
            }
        }
        for reserved in ["Content-Length", "host", "Connection", "Cookie", "Transfer-Encoding", "Proxy-Authorization"] {
            XCTAssertThrowsError(try Policy.headerFields([reserved: "x"], forbidden: Policy.forbiddenHTTPHeaders), reserved)
        }
        XCTAssertThrowsError(try Policy.headerFields(["Sec-WebSocket-Key": "x"], forbidden: Policy.forbiddenWebSocketHeaders))
        XCTAssertNoThrow(try Policy.headerFields(["Sec-WebSocket-Protocol": "chat", "Authorization": "Bearer t"],
                                                 forbidden: Policy.forbiddenWebSocketHeaders))
        // "X-Big: " + value + "\r\n" is 9 bytes plus the value, counted in UTF-8.
        XCTAssertNoThrow(try Policy.headerFields(["X-Big": String(repeating: "v", count: 8183)], forbidden: []))
        XCTAssertThrowsError(try Policy.headerFields(["X-Big": String(repeating: "v", count: 8184)], forbidden: [])) {
            XCTAssertEqual($0 as? CompanionTransportError, .limit)
        }
        XCTAssertNoThrow(try Policy.headerFields(["X-Big": String(repeating: "中", count: 2727)], forbidden: []))
        XCTAssertThrowsError(try Policy.headerFields(["X-Big": String(repeating: "中", count: 2728)], forbidden: [])) {
            XCTAssertEqual($0 as? CompanionTransportError, .limit)
        }
    }

    func testOnlyFirmwareMethodsAreAccepted() throws {
        for method in ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"] {
            XCTAssertEqual(try Policy.httpMethod(method), method)
        }
        for method in ["get", "TRACE", "CONNECT", "OPTIONS", "", "GET "] {
            XCTAssertThrowsError(try Policy.httpMethod(method), method)
        }
    }

    func testSocketHostsAreAddressesOrPlainNames() throws {
        let loopback = try XCTUnwrap(IPv4Address("127.0.0.1"))
        let loopback6 = try XCTUnwrap(IPv6Address("::1"))
        XCTAssertEqual(Policy.socketHost("127.0.0.1"), .ipv4(loopback))
        XCTAssertEqual(Policy.socketHost("::1"), .ipv6(loopback6))
        XCTAssertEqual(Policy.socketHost("[::1]"), .ipv6(loopback6))
        XCTAssertEqual(Policy.socketHost("pool.ntp.org"), .name("pool.ntp.org", nil))
        let rejected = [
            "", " ", "a b", "a/b", "user@host", "host\r\n", "-lead", ".lead", "[example.test]", "[127.0.0.1]",
            "1:2:3", "a%b", "例え.jp", String(repeating: "a", count: 256),
        ]
        for host in rejected {
            XCTAssertNil(Policy.socketHost(host), host)
        }
    }

    func testTextFramesMustBeExactUTF8() {
        XCTAssertEqual(Policy.text(Data("海豚 ok".utf8)), "海豚 ok")
        XCTAssertEqual(Policy.text(Data()), "")
        XCTAssertEqual(Policy.text(Data([0xEF, 0xBB, 0xBF, 0x41])), "\u{FEFF}A")
        for invalid: [UInt8] in [[0xC3], [0xC0, 0x80], [0xED, 0xA0, 0x80], [0xFF], [0x41, 0x80]] {
            XCTAssertNil(Policy.text(Data(invalid)), "\(invalid)")
        }
    }

    func testStreamChunksStayOrderedAndDatagramsStayWhole() {
        typealias Inbound = Policy.SocketInbound
        let three = Data([1, 2, 3])
        let full = Data(repeating: 7, count: 512)
        let over = Data(repeating: 7, count: 513)
        func tcp(_ inbound: Inbound) -> Policy.SocketOutcome { Policy.outcome(of: inbound, udp: false) }
        func udp(_ inbound: Inbound) -> Policy.SocketOutcome { Policy.outcome(of: inbound, udp: true) }

        XCTAssertEqual(tcp(Inbound(data: full, isComplete: false, hasContext: true, error: nil)), .deliver(full))
        XCTAssertEqual(tcp(Inbound(data: three, isComplete: true, hasContext: true, error: nil)), .deliverThenClose(three))
        XCTAssertEqual(tcp(Inbound(data: nil, isComplete: true, hasContext: true, error: nil)), .close)
        XCTAssertEqual(tcp(Inbound(data: over, isComplete: false, hasContext: true, error: nil)), .fail(.receive))
        XCTAssertEqual(tcp(Inbound(data: Data(), isComplete: false, hasContext: false, error: nil)), .fail(.receive))
        XCTAssertEqual(tcp(Inbound(data: nil, isComplete: false, hasContext: false, error: .posix(.ECONNRESET))),
                       .fail(.receive))

        XCTAssertEqual(udp(Inbound(data: nil, isComplete: true, hasContext: true, error: nil)), .deliver(Data()))
        XCTAssertEqual(udp(Inbound(data: Data(), isComplete: true, hasContext: true, error: nil)), .deliver(Data()))
        XCTAssertEqual(udp(Inbound(data: full, isComplete: true, hasContext: true, error: nil)), .deliver(full))
        XCTAssertEqual(udp(Inbound(data: over, isComplete: true, hasContext: true, error: nil)), .skip)
        XCTAssertEqual(udp(Inbound(data: three, isComplete: false, hasContext: true, error: nil)), .fail(.receive))
        XCTAssertEqual(udp(Inbound(data: nil, isComplete: true, hasContext: false, error: nil)), .fail(.receive))
        XCTAssertEqual(udp(Inbound(data: nil, isComplete: false, hasContext: false, error: .posix(.ECONNREFUSED))),
                       .fail(.refused))
    }

    func testRedirectPolicyRevalidatesEveryHop() throws {
        var chain = CompanionRedirect(url: makeURL("https://api.example.test/start"), method: "POST")
        chain = try chain.following(status: 307, to: makeURL("https://api.example.test/next#frag"))
        XCTAssertEqual(chain.url.absoluteString, "https://api.example.test/next")
        XCTAssertEqual(chain.method, "POST")
        XCTAssertTrue(chain.keepsBody)
        XCTAssertTrue(chain.keepsAuthorization)
        chain = try chain.following(status: 302, to: makeURL("https://API.example.test:443/login"))
        XCTAssertEqual(chain.method, "GET")
        XCTAssertFalse(chain.keepsBody)
        XCTAssertTrue(chain.keepsAuthorization, "same origin: case and the default port do not matter")
        chain = try chain.following(status: 301, to: makeURL("https://cdn.example.test/file"))
        XCTAssertFalse(chain.keepsAuthorization)
        chain = try chain.following(status: 308, to: makeURL("https://api.example.test/back"))
        XCTAssertFalse(chain.keepsAuthorization, "credentials never come back after leaving the origin")
        chain = try chain.following(status: 302, to: makeURL("https://api.example.test/5"))
        XCTAssertEqual(chain.hops, 5)
        XCTAssertThrowsError(try chain.following(status: 302, to: makeURL("https://api.example.test/6"))) {
            XCTAssertEqual($0 as? CompanionTransportError, .limit)
        }
    }

    func testRedirectPolicyRejectsUnsafeTargets() throws {
        let plain = CompanionRedirect(url: makeURL("https://api.example.test/"), method: "GET")
        let targets = [
            "ftp://api.example.test/", "file:///etc/hosts", "javascript:alert(1)", "wss://api.example.test/",
            "https://u:p@api.example.test/", "https://u@api.example.test/",
        ]
        for target in targets {
            XCTAssertThrowsError(try plain.following(status: 302, to: makeURL(target)), target) {
                XCTAssertEqual($0 as? CompanionTransportError, .invalidURL, target)
            }
        }
        XCTAssertThrowsError(try plain.following(status: 302, to: nil))
        XCTAssertFalse(try plain.following(status: 302, to: makeURL("http://api.example.test/")).keepsAuthorization,
                       "an https to http downgrade is a different origin")
        XCTAssertFalse(try plain.following(status: 302, to: makeURL("https://api.example.test:8443/")).keepsAuthorization)
        let put = CompanionRedirect(url: makeURL("https://api.example.test/"), method: "PUT")
        XCTAssertEqual(try put.following(status: 302, to: makeURL("https://api.example.test/x")).method, "PUT")
        XCTAssertEqual(try put.following(status: 303, to: makeURL("https://api.example.test/x")).method, "GET")
        let head = CompanionRedirect(url: makeURL("https://api.example.test/"), method: "HEAD")
        XCTAssertEqual(try head.following(status: 303, to: makeURL("https://api.example.test/x")).method, "HEAD")
    }

    func testTransportErrorsMapToFirmwareFamilies() {
        XCTAssertEqual(Policy.transportError(NWError.dns(-65554), stage: .connect), .dns)
        XCTAssertEqual(Policy.transportError(NWError.tls(-9807), stage: .connect), .tls)
        XCTAssertEqual(Policy.transportError(NWError.posix(.ECONNREFUSED), stage: .connect), .refused)
        XCTAssertEqual(Policy.transportError(NWError.posix(.ETIMEDOUT), stage: .connect), .timeout)
        XCTAssertEqual(Policy.transportError(NWError.posix(.ENETUNREACH), stage: .connect), .unreachable)
        XCTAssertEqual(Policy.transportError(NWError.posix(.EHOSTUNREACH), stage: .receive), .unreachable)
        XCTAssertEqual(Policy.transportError(NWError.posix(.EMSGSIZE), stage: .send), .limit)
        XCTAssertEqual(Policy.transportError(NWError.posix(.ECONNRESET), stage: .connect), .refused)
        XCTAssertEqual(Policy.transportError(NWError.posix(.ECONNRESET), stage: .receive), .receive)
        XCTAssertEqual(Policy.transportError(NWError.posix(.EPIPE), stage: .send), .send)
        XCTAssertEqual(Policy.transportError(URLError(.timedOut), stage: .connect), .timeout)
        XCTAssertEqual(Policy.transportError(URLError(.cannotFindHost), stage: .connect), .dns)
        XCTAssertEqual(Policy.transportError(URLError(.cannotConnectToHost), stage: .connect), .refused)
        XCTAssertEqual(Policy.transportError(URLError(.notConnectedToInternet), stage: .connect), .unreachable)
        XCTAssertEqual(Policy.transportError(URLError(.serverCertificateUntrusted), stage: .connect), .tls)
        XCTAssertEqual(Policy.transportError(URLError(.appTransportSecurityRequiresSecureConnection), stage: .connect), .tls)
        XCTAssertEqual(Policy.transportError(URLError(.unsupportedURL), stage: .connect), .invalidURL)
        XCTAssertEqual(Policy.transportError(URLError(.badServerResponse), stage: .connect), .invalidProtocol)
        XCTAssertEqual(Policy.transportError(URLError(.networkConnectionLost), stage: .receive), .receive)
        XCTAssertEqual(Policy.transportError(NSError(domain: NSPOSIXErrorDomain, code: Int(EMSGSIZE)), stage: .receive), .limit)
        XCTAssertEqual(Policy.transportError(CompanionTransportError.tls, stage: .receive), .tls)
    }

    func testPeerAddressesUsePresentationFormat() throws {
        let v4 = try XCTUnwrap(IPv4Address("192.0.2.7"))
        let v6 = try XCTUnwrap(IPv6Address("2001:db8::1"))
        XCTAssertEqual(Policy.peerAddress(.hostPort(host: .ipv4(v4), port: 80)), "192.0.2.7")
        XCTAssertEqual(Policy.peerAddress(.hostPort(host: .ipv6(v6), port: 443)), "2001:db8::1")
        XCTAssertNil(Policy.peerAddress(.hostPort(host: .name("example.test", nil), port: 80)))
        XCTAssertNil(Policy.peerAddress(nil))
    }

    func testInjectedConfigurationLosesSharedState() {
        let source = URLSessionConfiguration.default
        source.httpCookieStorage = .shared
        source.httpShouldSetCookies = true
        source.urlCredentialStorage = .shared
        source.urlCache = .shared
        source.requestCachePolicy = .returnCacheDataElseLoad
        source.httpAdditionalHeaders = ["Cookie": "a=b"]
        source.waitsForConnectivity = true
        source.protocolClasses = [StubProtocol.self]
        let hardened = Policy.hardened(source)
        XCTAssertNil(hardened.httpCookieStorage)
        XCTAssertFalse(hardened.httpShouldSetCookies)
        XCTAssertEqual(hardened.httpCookieAcceptPolicy, .never)
        XCTAssertNil(hardened.urlCredentialStorage)
        XCTAssertNil(hardened.urlCache)
        XCTAssertEqual(hardened.requestCachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
        XCTAssertNil(hardened.httpAdditionalHeaders)
        XCTAssertFalse(hardened.waitsForConnectivity)
        XCTAssertNotNil(hardened.connectionProxyDictionary)
        XCTAssertEqual(hardened.protocolClasses?.first.map { $0 == StubProtocol.self }, true)
        XCTAssertNotNil(source.httpCookieStorage, "the caller's configuration is copied, not modified")
        XCTAssertNil(Policy.hardened(.background(withIdentifier: "FlipperCoreTests.companion")).identifier)
    }

    // MARK: HTTP through a local URLProtocol

    @MainActor
    func testHTTPReturnsBoundedResultWithoutAmbientState() async throws {
        StubProtocol.install { _ in
            .respond(status: 201, headers: ["Content-Type": "text/plain", "X-Reply": "ok", "Set-Cookie": "a=b"],
                     body: Data("hello".utf8))
        }
        let net = stubbedNetworking()
        let result = try await net.http(method: "POST", url: makeURL("https://api.example.test/items"),
                                        headers: ["Authorization": "Bearer t", "Content-Type": "application/json"],
                                        body: Data("{}".utf8), timeout: 5, requestID: 9)
        XCTAssertEqual(result.status, 201)
        XCTAssertEqual(result.body, Data("hello".utf8))
        XCTAssertEqual(result.headers["X-Reply"], "ok")
        let first = try XCTUnwrap(StubProtocol.seen.first)
        XCTAssertEqual(first.method, "POST")
        XCTAssertEqual(first.body, Data("{}".utf8))
        XCTAssertEqual(first.headers["Authorization"], "Bearer t")
        XCTAssertTrue(net.activeIDs.isEmpty)

        // The same ID is free again; no cookie from the first reply is replayed.
        _ = try await net.http(method: "GET", url: makeURL("https://api.example.test/items"), headers: [:],
                               body: Data(), timeout: 5, requestID: 9)
        XCTAssertEqual(StubProtocol.seen.count, 2)
        XCTAssertNil(StubProtocol.seen.last?.headers["Cookie"])
        net.cancelAll()
    }

    @MainActor
    func testHTTPRejectsDeclaredOversizeButAllowsLargeHEAD() async throws {
        let declared = String(Policy.maxBodyBytes + 1)
        StubProtocol.install { request in
            .respond(status: 200, headers: ["Content-Length": declared],
                     body: request.httpMethod == "HEAD" ? Data() : Data("x".utf8))
        }
        let net = stubbedNetworking()
        await assertThrows(.limit) {
            try await net.http(method: "GET", url: makeURL("https://api.example.test/big"), headers: [:],
                               body: Data(), timeout: 5, requestID: 1)
        }
        let head = try await net.http(method: "HEAD", url: makeURL("https://api.example.test/big"), headers: [:],
                                      body: Data(), timeout: 5, requestID: 1)
        XCTAssertEqual(head.status, 200)
        XCTAssertTrue(head.body.isEmpty)
        XCTAssertEqual(head.headers["Content-Length"], declared)
        XCTAssertTrue(net.activeIDs.isEmpty)
        net.cancelAll()
    }

    @MainActor
    func testHTTPStreamingCapCancelsTheTransferEarly() async throws {
        StubProtocol.install { _ in .stream(chunk: 64 * 1024, total: 64 * 1024 * 1024) }
        let net = stubbedNetworking()
        await assertThrows(.limit) {
            try await net.http(method: "GET", url: makeURL("https://api.example.test/stream"), headers: [:],
                               body: Data(), timeout: 30, requestID: 1)
        }
        try await waitUntil { StubProtocol.stops >= 1 }
        XCTAssertGreaterThan(StubProtocol.streamed, Policy.maxBodyBytes)
        XCTAssertLessThan(StubProtocol.streamed, 16 * 1024 * 1024, "the body must not be drained before the cap applies")
        XCTAssertTrue(net.activeIDs.isEmpty)
        net.cancelAll()
    }

    @MainActor
    func testHTTPTimeoutCancelsTheTask() async throws {
        StubProtocol.install { _ in .hang }
        let net = stubbedNetworking()
        let started = Date()
        await assertThrows(.timeout) {
            try await net.http(method: "GET", url: makeURL("https://api.example.test/slow"), headers: [:],
                               body: Data(), timeout: 0.3, requestID: 1)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        try await waitUntil { StubProtocol.stops >= 1 }
        XCTAssertTrue(net.activeIDs.isEmpty)
        net.cancelAll()
    }

    @MainActor
    func testCancellingTheAwaitingTaskCancelsTheRequestAndFreesItsID() async throws {
        StubProtocol.install { request in
            request.url?.path == "/slow" ? .hang : .respond(status: 200, headers: [:], body: Data("new".utf8))
        }
        let net = stubbedNetworking()
        let slow = Task {
            try await net.http(method: "GET", url: makeURL("https://api.example.test/slow"), headers: [:],
                               body: Data(), timeout: 30, requestID: 3)
        }
        try await waitUntil { StubProtocol.seen.count == 1 }
        slow.cancel()
        await assertCancelled(slow)
        try await waitUntil { StubProtocol.stops >= 1 }
        XCTAssertTrue(net.activeIDs.isEmpty)
        let fresh = try await net.http(method: "GET", url: makeURL("https://api.example.test/fast"), headers: [:],
                                       body: Data(), timeout: 5, requestID: 3)
        XCTAssertEqual(fresh.body, Data("new".utf8))
        net.cancelAll()
    }

    @MainActor
    func testRedirectsKeepAuthorizationOnlyOnTheOriginalOrigin() async throws {
        StubProtocol.install { request in
            switch (request.url?.host ?? "", request.url?.path ?? "") {
            case ("a.example.test", "/start"): return .redirect(status: 302, location: "/same")
            case ("a.example.test", "/same"): return .redirect(status: 307, location: "https://b.example.test/other")
            case ("b.example.test", "/other"): return .redirect(status: 302, location: "https://a.example.test/final")
            default: return .respond(status: 200, headers: [:], body: Data("done".utf8))
            }
        }
        let net = stubbedNetworking()
        let result = try await net.http(method: "GET", url: makeURL("https://a.example.test/start"),
                                        headers: ["Authorization": "Bearer secret", "X-Trace": "1"],
                                        body: Data(), timeout: 5, requestID: 1)
        XCTAssertEqual(result.status, 200)
        XCTAssertEqual(result.body, Data("done".utf8))
        let seen = StubProtocol.seen
        XCTAssertEqual(seen.map(\.url.absoluteString), [
            "https://a.example.test/start", "https://a.example.test/same",
            "https://b.example.test/other", "https://a.example.test/final",
        ])
        XCTAssertEqual(seen.map { $0.headers["Authorization"] }, ["Bearer secret", "Bearer secret", nil, nil])
        XCTAssertEqual(seen.map { $0.headers["X-Trace"] }, ["1", "1", "1", "1"])
        XCTAssertTrue(seen.allSatisfy { $0.headers["Cookie"] == nil })
        net.cancelAll()
    }

    @MainActor
    func testRedirectMethodRulesFollowFetch() async throws {
        StubProtocol.install { request in
            switch request.url?.path ?? "" {
            case "/see-other": return .redirect(status: 303, location: "/result")
            case "/temporary": return .redirect(status: 307, location: "/result")
            default: return .respond(status: 200, headers: [:], body: Data("ok".utf8))
            }
        }
        let net = stubbedNetworking()
        let body = Data(#"{"a":1}"#.utf8)
        let headers = ["Content-Type": "application/json", "Authorization": "Bearer t"]
        _ = try await net.http(method: "POST", url: makeURL("https://a.example.test/see-other"), headers: headers,
                               body: body, timeout: 5, requestID: 1)
        let seeOther = StubProtocol.seen
        XCTAssertEqual(seeOther.map(\.method), ["POST", "GET"])
        XCTAssertEqual(seeOther.map(\.body), [body, Data()])
        XCTAssertNil(seeOther.last?.headers["Content-Type"])
        XCTAssertEqual(seeOther.last?.headers["Authorization"], "Bearer t")

        _ = try await net.http(method: "POST", url: makeURL("https://a.example.test/temporary"), headers: headers,
                               body: body, timeout: 5, requestID: 1)
        let temporary = Array(StubProtocol.seen.suffix(2))
        XCTAssertEqual(temporary.map(\.method), ["POST", "POST"])
        XCTAssertEqual(temporary.map(\.body), [body, body])
        XCTAssertEqual(temporary.last?.headers["Content-Type"], "application/json")
        net.cancelAll()
    }

    @MainActor
    func testRedirectChainsAreCappedAndRevalidated() async throws {
        StubProtocol.install { request in
            let path = request.url?.path ?? ""
            switch path {
            case "/ftp": return .redirect(status: 302, location: "ftp://a.example.test/file")
            case "/userinfo": return .redirect(status: 302, location: "https://user:pw@a.example.test/")
            default:
                guard path.hasPrefix("/hop/"), let remaining = Int(path.dropFirst(5)), remaining > 0 else {
                    return .respond(status: 200, headers: [:], body: Data("end".utf8))
                }
                return .redirect(status: 302, location: "/hop/\(remaining - 1)")
            }
        }
        let net = stubbedNetworking()
        let five = try await net.http(method: "GET", url: makeURL("https://a.example.test/hop/5"), headers: [:],
                                      body: Data(), timeout: 5, requestID: 1)
        XCTAssertEqual(five.body, Data("end".utf8))
        XCTAssertEqual(StubProtocol.seen.count, 6)
        await assertThrows(.limit) {
            try await net.http(method: "GET", url: makeURL("https://a.example.test/hop/6"), headers: [:],
                               body: Data(), timeout: 5, requestID: 1)
        }
        await assertThrows(.invalidURL) {
            try await net.http(method: "GET", url: makeURL("https://a.example.test/ftp"), headers: [:],
                               body: Data(), timeout: 2, requestID: 1)
        }
        await assertThrows(.invalidURL) {
            try await net.http(method: "GET", url: makeURL("https://a.example.test/userinfo"), headers: [:],
                               body: Data(), timeout: 2, requestID: 1)
        }
        XCTAssertTrue(net.activeIDs.isEmpty)
        net.cancelAll()
    }

    @MainActor
    func testInvalidRequestsFailBeforeAnyTransportStarts() async throws {
        StubProtocol.install { _ in .respond(status: 200, headers: [:], body: Data()) }
        let net = stubbedNetworking()
        let site = makeURL("https://api.example.test/")
        let socket = makeURL("wss://api.example.test/")
        await assertThrows(.invalidURL) { try await net.openSocket(id: 1, host: "bad host", port: 80, udp: false, timeout: 1) }
        await assertThrows(.invalidURL) { try await net.openSocket(id: 1, host: "example.test", port: 0, udp: true, timeout: 1) }
        await assertThrows(.invalidURL) { try await net.openWebSocket(id: 1, url: site, headers: [:], timeout: 1) }
        await assertThrows(.invalidURL) {
            try await net.openWebSocket(id: 1, url: makeURL("wss://u:p@api.example.test/"), headers: [:], timeout: 1)
        }
        await assertThrows(.invalidProtocol) {
            try await net.openWebSocket(id: 1, url: socket, headers: ["Sec-WebSocket-Key": "x"], timeout: 1)
        }
        await assertThrows(.invalidURL) {
            try await net.http(method: "GET", url: socket, headers: [:], body: Data(), timeout: 1, requestID: 1)
        }
        await assertThrows(.invalidProtocol) {
            try await net.http(method: "TRACE", url: site, headers: [:], body: Data(), timeout: 1, requestID: 1)
        }
        await assertThrows(.invalidProtocol) {
            try await net.http(method: "GET", url: site, headers: ["Cookie": "a=b"], body: Data(), timeout: 1, requestID: 1)
        }
        await assertThrows(.invalidProtocol) {
            try await net.http(method: "POST", url: site, headers: ["X-A": "1\r\nHost: evil.test"], body: Data(),
                               timeout: 1, requestID: 1)
        }
        await assertThrows(.invalidProtocol) {
            try await net.http(method: "GET", url: site, headers: [:], body: Data([1]), timeout: 1, requestID: 1)
        }
        await assertThrows(.limit) {
            try await net.http(method: "POST", url: site, headers: [:], body: Data(count: Policy.maxBodyBytes + 1),
                               timeout: 1, requestID: 1)
        }
        await assertThrows(.limit) {
            try await net.http(method: "GET", url: site, headers: ["X-Big": String(repeating: "v", count: 9000)],
                               body: Data(), timeout: 1, requestID: 1)
        }
        await assertThrows(.invalidConnection) { try await net.send(id: 1, data: Data([1]), binary: true) }
        XCTAssertTrue(StubProtocol.seen.isEmpty)
        XCTAssertTrue(net.activeIDs.isEmpty)

        let exact = try await net.http(method: "PUT", url: site, headers: [:], body: Data(count: Policy.maxBodyBytes),
                                       timeout: 5, requestID: 1)
        XCTAssertEqual(exact.status, 200)
        XCTAssertEqual(StubProtocol.seen.first?.body.count, Policy.maxBodyBytes)
        net.cancelAll()
    }

    @MainActor
    func testIDsAreUniqueAcrossOperationsAndHTTPIsBounded() async throws {
        StubProtocol.install { _ in .hang }
        let net = stubbedNetworking()
        let first = Task {
            try await net.http(method: "GET", url: makeURL("https://a.example.test/1"), headers: [:], body: Data(),
                               timeout: 30, requestID: 1)
        }
        let second = Task {
            try await net.http(method: "GET", url: makeURL("https://a.example.test/2"), headers: [:], body: Data(),
                               timeout: 30, requestID: 2)
        }
        try await waitUntil { net.activeIDs == [1, 2] }
        await assertThrows(.limit) {
            try await net.http(method: "GET", url: makeURL("https://a.example.test/3"), headers: [:], body: Data(),
                               timeout: 30, requestID: 3)
        }
        await assertThrows(.invalidConnection) {
            try await net.http(method: "GET", url: makeURL("https://a.example.test/1"), headers: [:], body: Data(),
                               timeout: 30, requestID: 1)
        }
        // Admission fails before any socket or task exists.
        await assertThrows(.invalidConnection) {
            try await net.openSocket(id: 2, host: "127.0.0.1", port: 9, udp: true, timeout: 1)
        }
        await assertThrows(.invalidConnection) {
            try await net.openWebSocket(id: 1, url: makeURL("wss://a.example.test/ws"), headers: [:], timeout: 1)
        }
        await assertThrows(.invalidConnection) { try await net.send(id: 1, data: Data([1]), binary: true) }
        await assertThrows(.invalidConnection) { try await net.send(id: 77, data: Data([1]), binary: true) }

        net.close(id: 1)
        await assertCancelled(first)
        net.cancelAll()
        await assertCancelled(second)
        XCTAssertTrue(net.activeIDs.isEmpty)

        // cancelAll() invalidated the session; the next request gets a fresh one.
        StubProtocol.install { _ in .respond(status: 200, headers: [:], body: Data("again".utf8)) }
        let again = try await net.http(method: "GET", url: makeURL("https://a.example.test/1"), headers: [:],
                                       body: Data(), timeout: 5, requestID: 1)
        XCTAssertEqual(again.body, Data("again".utf8))
        net.cancelAll()
    }

    // MARK: Sockets on loopback

    @MainActor
    func testAsyncDeliveryBackpressuresAndCloseCancelsTheWaitingConsumer() async throws {
        let server = try await LoopbackServer.start(udp: false) { connection, _ in
            LoopbackServer.flood(connection, byte: 0xAA)
        }
        defer { server.stop() }
        let net = CompanionNetworking()
        var calls = 0
        var cancelled = false
        net.onData = { _, data, _ in
            XCTAssertLessThanOrEqual(data.count, 512)
            calls += 1
            do { try await Task.sleep(for: .seconds(60)) }
            catch { cancelled = true; throw error }
        }
        _ = try await net.openSocket(id: 0, host: "127.0.0.1", port: server.port, udp: false, timeout: 5)
        try await waitUntil { calls == 1 }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(calls, 1, "a slow BLE consumer must hold off the next receive")
        net.close(id: 0)
        try await waitUntil { cancelled }
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(net.activeIDs.isEmpty)
        net.cancelAll()
    }

    @MainActor
    func testChannelLimitCoversSocketsAndWebSockets() async throws {
        StubProtocol.install { _ in .respond(status: 204, headers: [:], body: Data()) }
        let net = stubbedNetworking()
        // Connected UDP flows to loopback become ready without sending a packet.
        for id: UInt32 in 1...4 {
            _ = try await net.openSocket(id: id, host: "127.0.0.1", port: 9, udp: true, timeout: 5)
        }
        await assertThrows(.limit) { try await net.openSocket(id: 5, host: "127.0.0.1", port: 9, udp: true, timeout: 5) }
        await assertThrows(.limit) {
            try await net.openWebSocket(id: 6, url: makeURL("wss://a.example.test/ws"), headers: [:], timeout: 5)
        }
        let http = try await net.http(method: "GET", url: makeURL("https://a.example.test/"), headers: [:], body: Data(),
                                      timeout: 5, requestID: 7)
        XCTAssertEqual(http.status, 204, "HTTP has its own budget")
        net.close(id: 2)
        _ = try await net.openSocket(id: 2, host: "127.0.0.1", port: 9, udp: true, timeout: 5)
        XCTAssertEqual(net.activeIDs, [1, 2, 3, 4])
        net.cancelAll()
        XCTAssertTrue(net.activeIDs.isEmpty)
    }

    @MainActor
    func testRefusedTCPConnectFailsWithoutRetry() async throws {
        let server = try await LoopbackServer.start(udp: false) { _, _ in }
        let closedPort = server.port
        server.stop()
        try await Task.sleep(for: .milliseconds(100))
        let net = CompanionNetworking()
        let started = Date()
        await assertThrows(.refused) {
            try await net.openSocket(id: 1, host: "127.0.0.1", port: closedPort, udp: false, timeout: 10)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "a refused connect must not wait for a path change")
        XCTAssertTrue(net.activeIDs.isEmpty)
    }

    @MainActor
    func testTCPStreamArrivesInBoundedChunksAndPeerCloseIsReportedOnce() async throws {
        let payload = Data((0..<1500).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        let server = try await LoopbackServer.start(udp: false) { connection, _ in
            connection.send(content: payload, contentContext: .finalMessage, isComplete: true,
                            completion: .contentProcessed { _ in })
        }
        defer { server.stop() }
        let net = CompanionNetworking()
        let recorder = Recorder(net)
        let peer = try await net.openSocket(id: 11, host: "127.0.0.1", port: server.port, udp: false, timeout: 5)
        XCTAssertEqual(peer, "127.0.0.1")
        try await waitUntil { !recorder.events.isEmpty }
        XCTAssertEqual(recorder.bytes(for: 11), payload)
        XCTAssertGreaterThanOrEqual(recorder.chunks.count, 3)
        XCTAssertTrue(recorder.chunks.allSatisfy { $0.id == 11 && !$0.data.isEmpty && $0.data.count <= 512 && !$0.binary })
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(recorder.events, [Recorder.Event(id: 11, state: .disconnected, error: nil)])
        XCTAssertTrue(net.activeIDs.isEmpty)
    }

    @MainActor
    func testTCPSendsAreBoundedAndOneAtATime() async throws {
        let server = try await LoopbackServer.start(udp: false) { connection, _ in LoopbackServer.echo(connection) }
        defer { server.stop() }
        let net = CompanionNetworking()
        let recorder = Recorder(net)
        _ = try await net.openSocket(id: 12, host: "127.0.0.1", port: server.port, udp: false, timeout: 5)
        await assertThrows(.limit) { try await net.send(id: 12, data: Data(count: 513), binary: false) }
        let empty = try await net.send(id: 12, data: Data(), binary: false)
        XCTAssertEqual(empty, 0)

        // Both calls reach the adapter before the first send completes; exactly one may be in flight.
        let first = Task { try await net.send(id: 12, data: Data("ab".utf8), binary: false) }
        let second = Task { try await net.send(id: 12, data: Data("cd".utf8), binary: false) }
        let outcomes = [await first.result, await second.result]
        XCTAssertEqual(outcomes.compactMap { try? $0.get() }, [2])
        XCTAssertEqual(outcomes.compactMap { outcome -> CompanionTransportError? in
            guard case .failure(let error) = outcome else { return nil }
            return error as? CompanionTransportError
        }, [.send])
        try await waitUntil { recorder.bytes(for: 12).count == 2 }

        let full = try await net.send(id: 12, data: Data(repeating: 0x41, count: 512), binary: false)
        XCTAssertEqual(full, 512)
        try await waitUntil { recorder.bytes(for: 12).count == 514 }
        XCTAssertTrue(recorder.chunks.allSatisfy { $0.data.count <= 512 })

        net.close(id: 12)
        await assertThrows(.invalidConnection) { try await net.send(id: 12, data: Data([1]), binary: false) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(recorder.events.isEmpty, "a local close is silent")
    }

    @MainActor
    func testNoDataAfterCloseAndAReusedIDNeverSeesOldTraffic() async throws {
        let server = try await LoopbackServer.start(udp: false) { connection, index in
            if index == 1 {
                LoopbackServer.flood(connection, byte: 0xAA)
            } else {
                connection.send(content: Data(repeating: 0xBB, count: 700), contentContext: .finalMessage,
                                isComplete: true, completion: .contentProcessed { _ in })
            }
        }
        defer { server.stop() }
        let net = CompanionNetworking()
        let recorder = Recorder(net)
        // Close from inside the first data callback, as a firmware close request racing traffic would.
        recorder.afterData = { [unowned recorder, weak net] id in
            if recorder.chunks.count == 1 { net?.close(id: id) }
        }
        _ = try await net.openSocket(id: 7, host: "127.0.0.1", port: server.port, udp: false, timeout: 5)
        try await waitUntil { !recorder.chunks.isEmpty }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(recorder.chunks.count, 1, "nothing may follow a close, not even a chunk already in flight")
        XCTAssertEqual(recorder.chunks.first?.data.allSatisfy { $0 == 0xAA }, true)
        XCTAssertTrue(net.activeIDs.isEmpty)

        _ = try await net.openSocket(id: 7, host: "127.0.0.1", port: server.port, udp: false, timeout: 5)
        try await waitUntil { !recorder.events.isEmpty }
        let reopened = recorder.chunks.dropFirst().reduce(into: Data()) { $0.append($1.data) }
        XCTAssertEqual(reopened, Data(repeating: 0xBB, count: 700))
        XCTAssertEqual(recorder.events, [Recorder.Event(id: 7, state: .disconnected, error: nil)])
    }

    @MainActor
    func testUDPDatagramsStayWholeAndOversizeOnesAreDropped() async throws {
        let replies = [Data("abc".utf8), Data(repeating: 0x42, count: 512), Data(repeating: 0x43, count: 513), Data("z".utf8)]
        let server = try await LoopbackServer.start(udp: true) { connection, _ in
            connection.receiveMessage { data, _, _, error in
                guard error == nil, data == Data("hi".utf8) else { return }
                for reply in replies { connection.send(content: reply, completion: .contentProcessed { _ in }) }
            }
        }
        defer { server.stop() }
        let net = CompanionNetworking()
        let recorder = Recorder(net)
        _ = try await net.openSocket(id: 31, host: "127.0.0.1", port: server.port, udp: true, timeout: 5)
        await assertThrows(.limit) { try await net.send(id: 31, data: Data(count: 513), binary: true) }
        let sent = try await net.send(id: 31, data: Data("hi".utf8), binary: true)
        XCTAssertEqual(sent, 2)
        try await waitUntil { recorder.chunks.last?.data == Data("z".utf8) }
        XCTAssertEqual(recorder.chunks.map(\.data), [replies[0], replies[1], replies[3]])
        XCTAssertTrue(recorder.events.isEmpty)
        net.cancelAll()
    }

    // MARK: Helpers

    @MainActor
    private func stubbedNetworking() -> CompanionNetworking {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return CompanionNetworking(httpConfiguration: configuration)
    }

    @MainActor
    private func assertThrows<T>(_ expected: CompanionTransportError, file: StaticString = #filePath, line: UInt = #line,
                                 _ body: () async throws -> T) async {
        do {
            _ = try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? CompanionTransportError, expected, "\(error)", file: file, line: line)
        }
    }

    @MainActor
    private func assertCancelled<T>(_ task: Task<T, Error>, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await task.value
            XCTFail("expected cancellation", file: file, line: line)
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)", file: file, line: line)
        }
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("condition not met in time", file: file, line: line) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private func makeURL(_ string: String) -> URL {
    URL(string: string)!
}

/// Records adapter callbacks in order.
@MainActor
private final class Recorder {
    struct Chunk: Equatable {
        let id: UInt32
        let data: Data
        let binary: Bool
    }

    struct Event: Equatable {
        let id: UInt32
        let state: CompanionTransportState
        let error: CompanionTransportError?
    }

    private(set) var chunks: [Chunk] = []
    private(set) var events: [Event] = []
    var afterData: ((UInt32) -> Void)?

    init(_ net: CompanionNetworking) {
        net.onData = { [weak self] id, data, binary in
            guard let self else { return }
            self.chunks.append(Chunk(id: id, data: data, binary: binary))
            self.afterData?(id)
        }
        net.onState = { [weak self] id, state, error in
            self?.events.append(Event(id: id, state: state, error: error))
        }
    }

    func bytes(for id: UInt32) -> Data {
        chunks.filter { $0.id == id }.reduce(into: Data()) { $0.append($1.data) }
    }
}

/// Answers every request in process; requests never reach a network.
private final class StubProtocol: URLProtocol {
    enum Reply {
        case respond(status: Int, headers: [String: String], body: Data)
        case redirect(status: Int, location: String)
        /// A 200 without Content-Length whose body keeps coming until the task stops it.
        case stream(chunk: Int, total: Int)
        case hang
    }

    struct Seen {
        let url: URL
        let method: String
        let headers: [String: String]
        let body: Data
    }

    private static let lock = NSLock()
    private static var generation = 0
    private static var router: (URLRequest) -> Reply = { _ in .hang }
    private static var seenRequests: [Seen] = []
    private static var stopCount = 0
    private static var streamedBytes = 0

    /// Starts a scenario. Late callbacks from an earlier scenario are not counted.
    static func install(_ router: @escaping (URLRequest) -> Reply) {
        locked {
            generation += 1
            self.router = router
            seenRequests = []
            stopCount = 0
            streamedBytes = 0
        }
    }

    static var seen: [Seen] { locked { seenRequests } }
    static var stops: Int { locked { stopCount } }
    static var streamed: Int { locked { streamedBytes } }

    private static func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private var scenario = -1
    private var sent = 0
    private var timer: Timer?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        guard let url = request.url, let client else { return }
        let seen = Seen(url: url, method: request.httpMethod ?? "GET", headers: request.allHTTPHeaderFields ?? [:],
                        body: StubProtocol.body(of: request))
        let (scenario, reply) = StubProtocol.locked { () -> (Int, Reply) in
            StubProtocol.seenRequests.append(seen)
            return (StubProtocol.generation, StubProtocol.router(request))
        }
        self.scenario = scenario
        switch reply {
        case .respond(let status, let headers, let body):
            client.urlProtocol(self, didReceive: StubProtocol.response(url, status, headers), cacheStoragePolicy: .notAllowed)
            if !body.isEmpty { client.urlProtocol(self, didLoad: body) }
            client.urlProtocolDidFinishLoading(self)
        case .redirect(let status, let location):
            let target = URL(string: location, relativeTo: url)!.absoluteURL
            client.urlProtocol(self, wasRedirectedTo: URLRequest(url: target),
                               redirectResponse: StubProtocol.response(url, status, ["Location": location]))
        case .stream(let chunk, let total):
            client.urlProtocol(self, didReceive: StubProtocol.response(url, 200, [:]), cacheStoragePolicy: .notAllowed)
            let payload = Data(repeating: 0x5A, count: chunk)
            // Delivered from the loading thread's run loop, one chunk per tick, until stopLoading().
            let timer = Timer(timeInterval: 0.002, repeats: true) { [weak self] timer in
                guard let self, let client = self.client else { return timer.invalidate() }
                guard self.sent < total else {
                    timer.invalidate()
                    return client.urlProtocolDidFinishLoading(self)
                }
                self.sent += chunk
                let scenario = self.scenario
                StubProtocol.locked {
                    if StubProtocol.generation == scenario { StubProtocol.streamedBytes += chunk }
                }
                client.urlProtocol(self, didLoad: payload)
            }
            self.timer = timer
            RunLoop.current.add(timer, forMode: .common)
        case .hang:
            break
        }
    }

    override func stopLoading() {
        timer?.invalidate()
        timer = nil
        let scenario = self.scenario
        StubProtocol.locked {
            if StubProtocol.generation == scenario { StubProtocol.stopCount += 1 }
        }
    }

    private static func response(_ url: URL, _ status: Int, _ headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// A listener bound to the loopback interface only.
private final class LoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "FlipperCoreTests.LoopbackServer")
    private var accepted: [NWConnection] = []
    private(set) var port: UInt16 = 0

    private init(listener: NWListener) {
        self.listener = listener
    }

    /// Starts listening; `onConnection` gets each accepted flow and its 1-based index.
    static func start(udp: Bool, onConnection: @escaping @Sendable (NWConnection, Int) -> Void) async throws -> LoopbackServer {
        let parameters = udp ? NWParameters(dtls: nil, udp: NWProtocolUDP.Options())
                             : NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        parameters.requiredInterfaceType = .loopback
        let server = LoopbackServer(listener: try NWListener(using: parameters, on: .any))
        let once = Once()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            server.listener.stateUpdateHandler = { state in
                switch state {
                case .ready: once.run { continuation.resume() }
                case .failed(let error), .waiting(let error): once.run { continuation.resume(throwing: error) }
                case .cancelled: once.run { continuation.resume(throwing: CancellationError()) }
                default: break
                }
            }
            server.listener.newConnectionHandler = { connection in
                server.accepted.append(connection)
                connection.start(queue: server.queue)
                onConnection(connection, server.accepted.count)
            }
            server.listener.start(queue: server.queue)
        }
        server.port = server.listener.port?.rawValue ?? 0
        return server
    }

    func stop() {
        listener.cancel()
        queue.sync { accepted.forEach { $0.cancel() } }
    }

    /// Echoes everything back until the peer goes away.
    static func echo(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
            if let data, !data.isEmpty { connection.send(content: data, completion: .contentProcessed { _ in }) }
            if error == nil && !isComplete { LoopbackServer.echo(connection) }
        }
    }

    /// Writes `byte` until the connection fails; sends pace themselves on the socket buffer.
    static func flood(_ connection: NWConnection, byte: UInt8) {
        connection.send(content: Data(repeating: byte, count: 4096), completion: .contentProcessed { error in
            if error == nil { LoopbackServer.flood(connection, byte: byte) }
        })
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}
