import XCTest

final class FlipperLabUITests: XCTestCase {
    @MainActor
    func testOfflineNavigationAndChineseGuide() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.navigationBars["设备"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["搜索附近的 Flipper"].exists)

        app.tabBars.buttons["资料库"].tap()
        XCTAssertTrue(app.navigationBars["中文资料库"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["导入文件"].waitForExistence(timeout: 5))

        app.tabBars.buttons["工具"].tap()
        app.buttons["比较两次记录"].tap()
        XCTAssertTrue(app.navigationBars["比较记录"].waitForExistence(timeout: 5))

        app.tabBars.buttons["任务"].tap()
        XCTAssertTrue(app.navigationBars["任务"].waitForExistence(timeout: 5))

        app.tabBars.buttons["指南"].tap()
        let guide = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "设备连接")).firstMatch
        XCTAssertTrue(guide.waitForExistence(timeout: 10))
        guide.tap()
        XCTAssertTrue(app.navigationBars["设备连接"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["操作步骤"].exists)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "中文连接指南"
        image.lifetime = .keepAlways
        add(image)
    }
}
