import XCTest
import UIKit

/// Offline UI checks. The simulator has no Bluetooth, so these tests never reach a connected
/// state and never trigger hardware actions. Example records load only with the DEBUG
/// `-ui-testing-fixtures` argument. Elements are found by stable accessibility identifiers;
/// the locked Chinese copy is then asserted on their labels.
final class FlipperLabUITests: XCTestCase {
    private let chineseLocale = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]

    @MainActor
    func testExampleRecordAnalysis() throws {
        continueAfterFailure = false
        let app = launch(["-ui-testing-fixtures"])
        XCTAssertTrue(app.navigationBars["设备"].waitForExistence(timeout: 15))

        app.tabBars.buttons["资料库"].tap()
        let record = buttonContaining("示例：客厅遥控", in: app)
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        XCTAssertTrue(buttonContaining("示例：设备启动日志", in: app).exists)
        capture(app, name: "08-示例资料库")

        record.tap()
        XCTAssertTrue(app.staticTexts["分析结果"].waitForExistence(timeout: 10))
        // Facts replace the progress placeholder only after the off-main analysis finishes.
        XCTAssertTrue(app.staticTexts["文件类型"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["按钮数量"].exists)
        capture(app, name: "09-示例记录分析")

        let chart = app.descendants(matching: .any).matching(identifier: "record.pulseChart").firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        XCTAssertTrue(scrollUntilHittable([app.staticTexts["包络时序"], chart], in: app))
        capture(app, name: "10-示例脉冲图")

        // Offline, the single-shot infrared key is disabled and its reason sits beside it.
        let key = app.buttons["record.irKey.0"]
        XCTAssertTrue(scrollUntilHittable([key], in: app))
        XCTAssertEqual(key.label, "1. Power")
        XCTAssertFalse(key.isEnabled)
        XCTAssertTrue(element(labeled: "先在“设备”页连接 Flipper。", in: app).exists)
        capture(app, name: "11-示例红外按键")
    }

    @MainActor
    func testOfflineNavigationAndChineseGuide() throws {
        continueAfterFailure = false
        let app = launch()
        XCTAssertTrue(app.navigationBars["设备"].waitForExistence(timeout: 15))
        let scan = app.buttons["device.scan"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        XCTAssertEqual(scan.label, "搜索附近的 Flipper")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "device.hero").firstMatch.exists)
        // No Bluetooth on the simulator: let the honest offline status settle, then check it.
        _ = element(labeled: "蓝牙不可用", in: app).waitForExistence(timeout: 5)
        let status = app.staticTexts["device.status"]
        XCTAssertTrue(status.exists)
        XCTAssertTrue(["蓝牙不可用", "尚未连接"].contains(status.label), "Unexpected offline status: \(status.label)")
        capture(app, name: "01-设备")

        app.tabBars.buttons["资料库"].tap()
        XCTAssertTrue(app.navigationBars["中文资料库"].waitForExistence(timeout: 5))
        XCTAssertTrue(button(labeled: "导入文件", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(buttonContaining("示例：", in: app).exists, "A normal launch must not show example records")
        capture(app, name: "02-资料库")

        app.tabBars.buttons["工具"].tap()
        XCTAssertTrue(app.navigationBars["工具"].waitForExistence(timeout: 5))
        let compare = app.buttons["tools.compare"]
        XCTAssertTrue(compare.waitForExistence(timeout: 5))
        XCTAssertEqual(compare.label, "比较两次记录")
        capture(app, name: "03-工具")
        compare.tap()
        XCTAssertTrue(app.navigationBars["比较记录"].waitForExistence(timeout: 5))
        capture(app, name: "04-比较记录")

        app.tabBars.buttons["任务"].tap()
        XCTAssertTrue(app.navigationBars["任务"].waitForExistence(timeout: 5))
        capture(app, name: "05-任务")

        app.tabBars.buttons["指南"].tap()
        let guide = app.buttons["guides.row.device.connection"]
        XCTAssertTrue(guide.waitForExistence(timeout: 10))
        XCTAssertTrue(guide.label.contains("设备连接"))
        capture(app, name: "06-指南")
        guide.tap()
        XCTAssertTrue(app.navigationBars["设备连接"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["操作步骤"].exists)
        capture(app, name: "07-中文连接指南")
    }

    @MainActor
    func testDarkAppearanceAndAccessibilityTextNavigation() throws {
        continueAfterFailure = false
        let app = launch(["-ui-testing-fixtures", "-ui-testing-dark", "-ui-testing-large-text"])
        XCTAssertTrue(app.navigationBars["设备"].waitForExistence(timeout: 15))
        let scan = app.buttons["device.scan"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        XCTAssertEqual(scan.label, "搜索附近的 Flipper")
        // Accessibility text must enlarge the main action (wrapping, not shrinking, its label).
        XCTAssertGreaterThanOrEqual(scan.frame.height, 60)
        _ = element(labeled: "蓝牙不可用", in: app).waitForExistence(timeout: 5)
        let luminance = try XCTUnwrap(pageBackgroundLuminance(of: app))
        XCTAssertLessThan(luminance, 0.3, "Dark appearance should draw the warm-black page background")
        capture(app, name: "12-深色大字-设备")

        app.tabBars.buttons["资料库"].tap()
        XCTAssertTrue(app.navigationBars["中文资料库"].waitForExistence(timeout: 5))
        let record = buttonContaining("示例：客厅遥控", in: app)
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        XCTAssertTrue(scrollUntilHittable([record], in: app))
        capture(app, name: "13-深色大字-资料库")
        record.tap()
        XCTAssertTrue(app.staticTexts["分析结果"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["文件类型"].waitForExistence(timeout: 10))
        capture(app, name: "14-深色大字-记录")

        app.tabBars.buttons["工具"].tap()
        XCTAssertTrue(app.navigationBars["工具"].waitForExistence(timeout: 5))
        let compare = app.buttons["tools.compare"]
        XCTAssertTrue(compare.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollUntilHittable([compare], in: app))
        compare.tap()
        XCTAssertTrue(app.navigationBars["比较记录"].waitForExistence(timeout: 5))
        capture(app, name: "15-深色大字-比较记录")

        app.tabBars.buttons["任务"].tap()
        XCTAssertTrue(app.navigationBars["任务"].waitForExistence(timeout: 5))
        capture(app, name: "16-深色大字-任务")

        app.tabBars.buttons["指南"].tap()
        let guide = app.buttons["guides.row.device.connection"]
        XCTAssertTrue(guide.waitForExistence(timeout: 10))
        XCTAssertTrue(scrollUntilHittable([guide], in: app))
        guide.tap()
        XCTAssertTrue(app.navigationBars["设备连接"].waitForExistence(timeout: 5))
        let steps = app.staticTexts["操作步骤"]
        XCTAssertTrue(steps.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollUntilHittable([steps], in: app))
        capture(app, name: "17-深色大字-指南")
    }

    // MARK: - Helpers

    @MainActor
    private func launch(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = chineseLocale + extraArguments
        app.launch()
        return app
    }

    @MainActor
    private func button(labeled label: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    private func buttonContaining(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func element(labeled label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Drags the page in fixed, momentum-free steps until every element is on screen and hittable.
    @MainActor
    private func scrollUntilHittable(_ elements: [XCUIElement], in app: XCUIApplication, maxDrags: Int = 14) -> Bool {
        for _ in 0..<maxDrags {
            if elements.allSatisfy({ $0.exists && $0.isHittable }) { return true }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        return elements.allSatisfy { $0.exists && $0.isHittable }
    }

    /// Luminance of the page background in the left margin, sampled from a real screenshot.
    @MainActor
    private func pageBackgroundLuminance(of app: XCUIApplication) -> CGFloat? {
        guard let image = app.screenshot().image.cgImage else { return nil }
        let x = Int(CGFloat(image.width) * 0.015)
        let y = Int(CGFloat(image.height) * 0.6)
        guard let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return (0.2126 * CGFloat(rgba[0]) + 0.7152 * CGFloat(rgba[1]) + 0.0722 * CGFloat(rgba[2])) / 255
    }

    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
