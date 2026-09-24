import XCTest

final class FlipperLabUITests: XCTestCase {
    @MainActor
    func testExampleRecordAnalysis() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-ui-testing-fixtures"]
        app.launch()
        XCTAssertTrue(app.navigationBars["设备"].waitForExistence(timeout: 15))
        app.tabBars.buttons["资料库"].tap()
        let record = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "示例：客厅遥控")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        capture(app, name: "08-示例资料库")
        record.tap()
        XCTAssertTrue(app.staticTexts["分析结果"].waitForExistence(timeout: 10))
        capture(app, name: "09-示例记录分析")
        for _ in 0..<10 {
            if app.staticTexts["包络时序"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["包络时序"].isHittable)
        capture(app, name: "10-示例脉冲图")
    }

    @MainActor
    func testOfflineNavigationAndChineseGuide() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.navigationBars["设备"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["搜索附近的 Flipper"].exists)
        capture(app, name: "01-设备")

        app.tabBars.buttons["资料库"].tap()
        XCTAssertTrue(app.navigationBars["中文资料库"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["导入文件"].waitForExistence(timeout: 5))
        capture(app, name: "02-资料库")

        app.tabBars.buttons["工具"].tap()
        capture(app, name: "03-工具")
        app.buttons["比较两次记录"].tap()
        XCTAssertTrue(app.navigationBars["比较记录"].waitForExistence(timeout: 5))
        capture(app, name: "04-比较记录")

        app.tabBars.buttons["任务"].tap()
        XCTAssertTrue(app.navigationBars["任务"].waitForExistence(timeout: 5))
        capture(app, name: "05-任务")

        app.tabBars.buttons["指南"].tap()
        let guide = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "设备连接")).firstMatch
        XCTAssertTrue(guide.waitForExistence(timeout: 10))
        capture(app, name: "06-指南")
        guide.tap()
        XCTAssertTrue(app.navigationBars["设备连接"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["操作步骤"].exists)
        capture(app, name: "07-中文连接指南")
    }

    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
