import Foundation
import XCTest
import FlipperCore

final class InstalledAppDiscoveryTests: XCTestCase {
    private func file(_ parent: String, _ name: String, directory: Bool = false) throws -> DeviceFile {
        try DeviceFile(parent: parent, message: PBMessage(PBMessage.uint(1, directory ? 1 : 0) + PBMessage.string(2, name)))
    }

    func testNestedAppsAreDiscoveredOnceAndKeepTheirActualLaunchPaths() async throws {
        let tree = [
            "/ext/apps": [try file("/ext/apps", "GPIO", directory: true), try file("/ext/apps", "root.fap")],
            "/ext/apps/GPIO": [try file("/ext/apps/GPIO", "GPS", directory: true), try file("/ext/apps/GPIO", "GPS", directory: true)],
            "/ext/apps/GPIO/GPS": [try file("/ext/apps/GPIO/GPS", "gps_tool.fap"), try file("/ext/apps/GPIO/GPS", "readme.txt")],
        ]
        var requested: [String] = []
        let apps = try await InstalledAppDiscovery.collect { path in
            requested.append(path)
            return tree[path] ?? []
        }
        XCTAssertEqual(requested, ["/ext/apps", "/ext/apps/GPIO", "/ext/apps/GPIO/GPS"])
        XCTAssertEqual(Set(apps.map(\.launchName)), ["/ext/apps/root.fap", "/ext/apps/GPIO/GPS/gps_tool.fap"])
        XCTAssertTrue(apps.allSatisfy(\.isInstalledApp))
    }

    func testRemoteResponseCannotRedirectTraversal() async throws {
        let misplaced = try file("/ext/elsewhere", "escape", directory: true)
        var requests = 0
        do {
            _ = try await InstalledAppDiscovery.collect { _ in requests += 1; return [misplaced] }
            XCTFail("must reject a response outside the requested parent")
        } catch { XCTAssertEqual(error as? RPCError, .malformed) }
        XCTAssertEqual(requests, 1)
        for name in ["line\nname", "tab\tname", "del\u{7f}name"] {
            let invalid = try file("/ext/apps", name, directory: true)
            do {
                _ = try await InstalledAppDiscovery.collect { _ in [invalid] }
                XCTFail(name)
            } catch { XCTAssertEqual(error as? RPCError, .malformed) }
        }
    }

    func testDepthAndAppCountLimitsFailInsteadOfReturningAPartialList() async throws {
        var requests = 0
        do {
            _ = try await InstalledAppDiscovery.collect { path in
                requests += 1
                return [try self.file(path, "next", directory: true)]
            }
            XCTFail("must reject the fifth folder level")
        } catch { XCTAssertTrue(error.localizedDescription.contains("4 层")) }
        XCTAssertEqual(requests, 5)

        let files = try (0...InstalledAppDiscovery.maximumApps).map { try file("/ext/apps", "app\($0).fap") }
        do {
            _ = try await InstalledAppDiscovery.collect { _ in files }
            XCTFail("must reject more than 600 apps")
        } catch { XCTAssertEqual(error as? RPCError, .tooLarge) }
    }

    func testCancellationAndDirectoryErrorsPropagate() async throws {
        let task = Task {
            try await InstalledAppDiscovery.collect { _ in
                try await Task.sleep(for: .seconds(30))
                return []
            }
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("cancelled traversal must not finish") }
        catch { XCTAssertTrue(error is CancellationError) }
        do {
            _ = try await InstalledAppDiscovery.collect { _ in throw RPCError.remote(9) }
            XCTFail("must retain remote permission failure")
        } catch { XCTAssertEqual(error as? RPCError, .remote(9)) }
    }
}
