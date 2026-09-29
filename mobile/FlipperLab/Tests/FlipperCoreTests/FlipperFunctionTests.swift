import XCTest
@testable import FlipperCore

final class FlipperFunctionTests: XCTestCase {
    func testInstalledAppPathMustStayInsideDeviceAppsDirectory() {
        let app = FlipperFunction.installed(path: "/ext/apps/Tools/my_tool.fap")
        XCTAssertEqual(app?.title, "my tool")
        XCTAssertEqual(app?.category, "工具")
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

    func testChineseInstalledToolsKeepTheirVerifiedLaunchPaths() {
        let path = "/ext/apps/Tools/clock.fap"
        let app = FlipperFunction.installed(path: path)
        XCTAssertEqual(app?.title, "床头时钟")
        XCTAssertEqual(app?.category, "工具")
        XCTAssertEqual(app?.launchName, path)
        XCTAssertEqual(app?.id, path)
        XCTAssertTrue(app?.isInstalledApp == true)
        // Same filename elsewhere is a different app; do not borrow its description.
        XCTAssertEqual(FlipperFunction.installed(path: "/ext/apps/Other/clock.fap")?.title, "clock")
        XCTAssertEqual(FlipperFunction.installed(path: "/ext/apps/Tools/calendar.fap")?.title, "日历")
        XCTAssertEqual(FlipperFunction.installed(path: "/ext/apps/Tools/gps_rpc.fap")?.title, "手机 GPS")
        XCTAssertEqual(FlipperFunction.installed(path: "/ext/apps/Tools/example_network.fap")?.launchName, "/ext/apps/Tools/example_network.fap")
        XCTAssertEqual(FlipperFunction.installed(path: "/ext/apps/Games/chess_clock.fap")?.category, "游戏")
        XCTAssertEqual(FlipperFunction.installed(path: "/ext/apps/Infrared/pause_timer.fap")?.title, "红外暂停定时器")
    }
}
