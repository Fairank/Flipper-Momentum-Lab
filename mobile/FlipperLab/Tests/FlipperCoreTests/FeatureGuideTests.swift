import XCTest
@testable import FlipperCore

final class FeatureGuideTests: XCTestCase {
    func testPackagedChineseGuideIsCompleteAndHasStableIdentifiers() throws {
        let guides = try FeatureGuide.load()
        XCTAssertEqual(Set(guides.map(\.id)), Set([
            "device.connection", "library.records", "infrared.workbench", "device.chinese_help",
            "subghz.analysis", "nfc_rfid.records", "gpio.serial_logs", "expansion.diagnostics",
        ]))
        XCTAssertEqual(guides.count, 8)
        for guide in guides {
            XCTAssertFalse(guide.title.isEmpty, guide.id)
            XCTAssertFalse(guide.steps.isEmpty, guide.id)
            XCTAssertFalse(guide.requires.isEmpty, guide.id)
            XCTAssertFalse(guide.limits.isEmpty, guide.id)
            XCTAssertFalse(guide.phoneRole.isEmpty, guide.id)
            XCTAssertFalse(guide.flipperRole.isEmpty, guide.id)
        }
    }
}
