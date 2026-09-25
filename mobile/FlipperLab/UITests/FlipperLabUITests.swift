import XCTest
import UIKit

/// Offline UI checks. The simulator has no Bluetooth, so these tests never reach a connected
/// state and never trigger hardware actions. Example records load only with the DEBUG
/// `-ui-testing-fixtures` argument. Elements are found by stable accessibility identifiers;
/// the locked Chinese copy is then asserted on their labels. Pages are native lists that build
/// rows lazily, so rows below the fold are revealed with bounded drags before they are checked.
final class FlipperLabUITests: XCTestCase {
    private let chineseLocale = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]

    @MainActor
    func testExampleRecordAnalysis() throws {
        continueAfterFailure = false
        let app = launch(["-ui-testing-fixtures", "-ui-testing-light"])
        XCTAssertTrue(app.navigationBars["设备"].waitForExistence(timeout: 15))

        app.tabBars.buttons["资料库"].tap()
        let record = buttonContaining("示例：客厅遥控", in: app)
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        XCTAssertTrue(buttonContaining("示例：设备启动日志", in: app).exists)
        captureWithLightToolbarIcon(app, name: "08-示例资料库", icon: moreMenu("library.more", in: app))

        record.tap()
        XCTAssertTrue(app.staticTexts["分析结果"].waitForExistence(timeout: 10))
        // Facts replace the progress row only after the off-main analysis finishes.
        XCTAssertTrue(app.staticTexts["文件类型"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["按钮数量"].exists)
        // The native toolbar may finish its transition after the analysis rows appear.
        // Verify the actual orange icon is painted before taking the first detail screenshot.
        let recordMore = moreMenu("record.more", in: app)
        captureWithLightToolbarIcon(app, name: "09-示例记录分析", icon: recordMore)

        // The chart row is built only when it scrolls near the screen, then measured whole.
        let chart = app.descendants(matching: .any).matching(identifier: "record.pulseChart").firstMatch
        XCTAssertTrue(reveal([app.staticTexts["包络时序"], chart], in: app))
        XCTAssertTrue(scrollFullyIntoView(chart, in: app))
        capture(app, name: "10-示例脉冲图")

        // Offline, the single-shot infrared key is disabled and its reason sits beside it.
        let key = app.buttons["record.irKey.0"]
        XCTAssertTrue(scrollUntilHittable([key], in: app))
        XCTAssertEqual(key.label, "1. Power")
        XCTAssertFalse(key.isEnabled)
        XCTAssertTrue(element(labeled: "先在“设备”页连接 Flipper。", in: app).exists)
        capture(app, name: "11-示例红外按键")

        // Export, compare and delete live in the record's 更多 menu; delete still asks first.
        moreMenu("record.more", in: app).tap()
        XCTAssertTrue(menuItem("record.export", title: "导出原始文件", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(menuItem("record.compare", title: "与其他记录比较", in: app).exists)
        let delete = menuItem("record.delete", title: "删除记录", in: app)
        XCTAssertTrue(delete.exists)
        delete.tap()
        XCTAssertTrue(element(labeled: "删除此手机记录？设备上的文件会保留。", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testOfflineNavigationAndChineseGuide() throws {
        continueAfterFailure = false
        let app = launch(["-ui-testing-light"])
        XCTAssertTrue(app.navigationBars["设备"].waitForExistence(timeout: 15))
        // Five destinations: 设备 · 功能 · 资料库 · 任务 · 指南.
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        let scan = app.buttons["device.scan"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        XCTAssertEqual(scan.label, "搜索附近的 Flipper")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "device.hero").firstMatch.exists)
        // No Bluetooth on the simulator: let the honest offline status settle, then check it.
        _ = element(labeled: "蓝牙不可用", in: app).waitForExistence(timeout: 5)
        let status = app.staticTexts["device.status"]
        XCTAssertTrue(status.exists)
        XCTAssertTrue(["蓝牙不可用", "尚未连接"].contains(status.label), "Unexpected offline status: \(status.label)")
        if status.label == "蓝牙不可用" {
            // Stated once, as the status title (the LCD token is hidden art), not again as a note.
            // 打开 iPhone 设置 is the action; search stays visible but disabled.
            let mentions = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "蓝牙不可用"))
            XCTAssertEqual(mentions.count, 1)
            XCTAssertTrue(app.buttons["device.openSettings"].exists)
            XCTAssertFalse(scan.isEnabled)
        }
        // Regression: forcing a dark tab scheme over iOS 26's light glass made every icon white.
        let darkFraction = try XCTUnwrap(darkPixelFraction(of: app.tabBars.buttons["资料库"]))
        XCTAssertGreaterThan(darkFraction, 0.02, "Unselected tab icon and text must stay legible on light glass")
        capture(app, name: "01-设备")

        app.tabBars.buttons["功能"].tap()
        XCTAssertTrue(app.navigationBars["功能"].waitForExistence(timeout: 5))
        XCTAssertTrue(buttonContaining("红外遥控", in: app).exists)
        capture(app, name: "01b-功能中心离线预览")

        app.tabBars.buttons["资料库"].tap()
        XCTAssertTrue(app.navigationBars["资料库"].waitForExistence(timeout: 5))
        XCTAssertTrue(button(labeled: "导入文件", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(buttonContaining("示例：", in: app).exists, "A normal launch must not show example records")
        let emptyImport = app.buttons["library.emptyImport"]
        XCTAssertTrue(emptyImport.waitForExistence(timeout: 5))
        // Regression: an unavailable-view action stretched into a tall icon-only capsule.
        XCTAssertGreaterThan(emptyImport.frame.width, emptyImport.frame.height * 2,
                             "The empty-library action should remain a readable horizontal button")
        XCTAssertLessThan(emptyImport.frame.height, app.frame.height * 0.2)
        captureWithLightToolbarIcon(app, name: "02-资料库", icon: moreMenu("library.more", in: app))

        // 比较 and 从 Flipper 导入 live in the library's 更多 menu; offline, device import is
        // disabled and its subtitle gives the reason.
        moreMenu("library.more", in: app).tap()
        let compare = menuItem("library.compare", title: "比较两次记录", in: app)
        XCTAssertTrue(compare.waitForExistence(timeout: 5))
        XCTAssertTrue(compare.label.hasPrefix("比较两次记录"))
        let deviceImport = menuItem("library.importDevice", title: "从 Flipper 导入", in: app)
        XCTAssertTrue(deviceImport.exists)
        XCTAssertFalse(deviceImport.isEnabled)
        capture(app, name: "03-资料库菜单")
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
        XCTAssertTrue(app.staticTexts["操作步骤"].waitForExistence(timeout: 5))
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
        XCTAssertLessThan(luminance, 0.3, "Dark appearance should draw the dark grouped page background")
        capture(app, name: "12-深色大字-设备")

        app.tabBars.buttons["资料库"].tap()
        XCTAssertTrue(app.navigationBars["资料库"].waitForExistence(timeout: 5))
        let record = buttonContaining("示例：客厅遥控", in: app)
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        XCTAssertTrue(scrollUntilHittable([record], in: app))
        capture(app, name: "13-深色大字-资料库")
        record.tap()
        // At accessibility sizes the analysis may start below the fold, where rows are not built yet.
        XCTAssertTrue(reveal([app.staticTexts["分析结果"]], in: app))
        XCTAssertTrue(reveal([app.staticTexts["文件类型"]], in: app))
        capture(app, name: "14-深色大字-记录")

        // 与其他记录比较 in the record's menu opens 比较记录 with this record already chosen as A.
        moreMenu("record.more", in: app).tap()
        let compare = menuItem("record.compare", title: "与其他记录比较", in: app)
        XCTAssertTrue(compare.waitForExistence(timeout: 5))
        compare.tap()
        XCTAssertTrue(app.navigationBars["比较记录"].waitForExistence(timeout: 5))
        let slotA = app.descendants(matching: .any).matching(identifier: "compare.pickerA").firstMatch
        XCTAssertTrue(slotA.waitForExistence(timeout: 5))
        let chosen = (slotA.value as? String) ?? ""
        XCTAssertTrue(chosen.contains("示例：客厅遥控") || slotA.label.contains("示例：客厅遥控"),
                      "Record A should be pre-filled, got \(slotA.label) / \(chosen)")
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
        XCTAssertTrue(reveal([steps], in: app))
        capture(app, name: "17-深色大字-指南")
    }

    // MARK: - Helpers

    @MainActor
    private func scrollFullyIntoView(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<10 {
            let frame = element.frame
            let top = app.navigationBars.firstMatch.frame.maxY + 8
            let bottom = app.tabBars.firstMatch.frame.minY - 12
            if frame.minY >= top && frame.maxY <= bottom { return true }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: frame.maxY > bottom ? 0.50 : 0.80))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        return false
    }

    @MainActor
    private func darkPixelFraction(of element: XCUIElement, threshold: Double = 80) -> Double? {
        guard let image = element.screenshot().image.cgImage else { return nil }
        return darkPixelFraction(in: image, threshold: threshold)
    }

    private func darkPixelFraction(in image: CGImage, threshold: Double) -> Double? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var darkCount = 0
        for index in stride(from: 0, to: rgba.count, by: 4) {
            let red: Double = 0.2126 * Double(rgba[index])
            let green: Double = 0.7152 * Double(rgba[index + 1])
            let blue: Double = 0.0722 * Double(rgba[index + 2])
            if red + green + blue < threshold { darkCount += 1 }
        }
        return Double(darkCount) / Double(width * height)
    }

    /// Inspect the exact full-screen image that becomes the attachment. An element screenshot
    /// followed by a separate app screenshot can observe different native-toolbar frames.
    /// Cropping is only for measurement: the unmodified full-screen image is saved.
    @MainActor
    private func captureWithLightToolbarIcon(_ app: XCUIApplication, name: String, icon: XCUIElement) {
        XCTAssertTrue(icon.waitForExistence(timeout: 5))
        for _ in 0..<5 {
            guard icon.isHittable else { continue }
            let frame = icon.frame
            let appFrame = app.frame
            let screenshot = app.screenshot()
            guard let full = screenshot.image.cgImage, appFrame.width > 0, appFrame.height > 0 else { continue }
            let scaleX = CGFloat(full.width) / appFrame.width
            let scaleY = CGFloat(full.height) / appFrame.height
            let bounds = CGRect(x: (frame.minX - appFrame.minX) * scaleX,
                                y: (frame.minY - appFrame.minY) * scaleY,
                                width: frame.width * scaleX, height: frame.height * scaleY).integral
                .intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))
            guard !bounds.isEmpty, let region = full.cropping(to: bounds) else { continue }
            if let fraction = darkPixelFraction(in: region, threshold: 180), fraction > 0.02 {
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
                return
            }
        }
        capture(app, name: name + "-toolbar-failure")
        XCTFail("The saved full-screen image must show the toolbar icon")
    }

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

    /// The toolbar 更多 menu, by identifier or by its visible title.
    @MainActor
    private func moreMenu(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", identifier, "更多")).firstMatch
    }

    /// An open menu's item, by identifier or by title prefix: UIKit may fold a subtitle into the label.
    @MainActor
    private func menuItem(_ identifier: String, title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@", identifier, title)).firstMatch
    }

    /// One fixed, momentum-free drag that moves the page content up by 30 % of the screen.
    @MainActor
    private func dragUp(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    /// Drags the page in fixed, momentum-free steps until every element is on screen and hittable.
    @MainActor
    private func scrollUntilHittable(_ elements: [XCUIElement], in app: XCUIApplication, maxDrags: Int = 14) -> Bool {
        for _ in 0..<maxDrags {
            if elements.allSatisfy({ $0.exists && $0.isHittable }) { return true }
            dragUp(in: app)
        }
        return elements.allSatisfy { $0.exists && $0.isHittable }
    }

    /// Lists build rows lazily and some content arrives asynchronously: waits briefly for the
    /// elements, then drags in bounded steps until every one exists and is hittable.
    @MainActor
    private func reveal(_ elements: [XCUIElement], in app: XCUIApplication, maxDrags: Int = 14) -> Bool {
        for _ in 0..<maxDrags {
            if elements.allSatisfy({ $0.waitForExistence(timeout: 1) && $0.isHittable }) { return true }
            dragUp(in: app)
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
