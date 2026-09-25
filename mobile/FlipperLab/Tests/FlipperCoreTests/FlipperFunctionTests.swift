import XCTest
@testable import FlipperCore

final class FlipperFunctionTests: XCTestCase {
    func testInstalledAppPathMustStayInsideDeviceAppsDirectory() {
        let app = FlipperFunction.installed(path: "/ext/apps/Tools/my_tool.fap")
        XCTAssertEqual(app?.title, "my tool")
        XCTAssertEqual(app?.category, "Tools")
        XCTAssertEqual(app?.launchName, "/ext/apps/Tools/my_tool.fap")
        XCTAssertTrue(app?.isInstalledApp == true)

        for path in [
            "/ext/infrared/remote.ir", "/ext/apps/../danger.fap", "/ext/apps/Tools/../../danger.fap",
            "/ext/apps/Tools/evil\\thing.fap", "/ext/apps/Tools/evil\0thing.fap",
            "/ext/apps/Tools/notes.txt", "/ext/apps/Tools/.fap", "/ext/apps//empty.fap",
            "/ext/apps/Tools/nested/app.fap",
        ] {
            XCTAssertNil(FlipperFunction.installed(path: path), path)
        }
    }

    func testBuiltInLaunchNamesAreUnique() {
        let functions = FlipperFunction.builtIns
        XCTAssertEqual(Set(functions.map(\.id)).count, functions.count)
        XCTAssertEqual(Set(functions.map(\.launchName)).count, functions.count)
        XCTAssertTrue(functions.contains { $0.launchName == "Infrared" })
        XCTAssertTrue(functions.contains { $0.launchName == "Apps" })
    }
}
