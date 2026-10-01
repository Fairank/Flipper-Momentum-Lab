import XCTest
@testable import FlipperCore

final class CompanionStorageTests: XCTestCase {
    func testAppDataPathsAndTraversal() throws {
        try CompanionStorage.validate("/ext/apps_data/network/测试.txt")
        try CompanionStorage.validate("/ext/apps_data/network/sub/file.bin")
        for path in ["/int/settings", "/data/file", "/ext/file", "/ext/apps_data/a",
                     "/ext/apps_data/../a/b", "/ext/apps_data/a/./b", "/ext/apps_data//a/b",
                     "/ext/apps_data/a/", "/ext/apps_data/a/b\u{0}", "/ext/apps_data/a/\\b",
                     "/ext/apps_data/a/" + String(repeating: "中", count: 100)] {
            XCTAssertThrowsError(try CompanionStorage.validate(path), path)
        }
    }
}
