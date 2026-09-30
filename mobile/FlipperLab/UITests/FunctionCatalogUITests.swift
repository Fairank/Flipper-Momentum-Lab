import XCTest
import UIKit

/// These checks exercise Chinese presentation while disconnected. The DEBUG catalogue
/// contains display-only examples; it never makes the simulator a connected Flipper.
final class FunctionCatalogUITests: XCTestCase {
    private let chineseLocale = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]

    @MainActor
    func testOfflineSearchFindsDeviceFunctionAndPhoneWorkbench() throws {
        continueAfterFailure = false
        let app = launch(["-ui-testing-light"])
        openFunctions(in: app)
        replaceSearch(with: "NFC", in: app)

        let workbench = app.buttons["functions.nfcWorkbench"]
        XCTAssertTrue(scrollUntilHittable(workbench, in: app))
        XCTAssertFalse(app.buttons["functions.builtin.infrared"].exists)
        let nfc = app.buttons["functions.builtin.nfc"]
        let details = app.buttons["functions.details.nfc"]
        XCTAssertTrue(scrollUntilHittable(details, in: app))
        XCTAssertTrue(nfc.exists)
        XCTAssertTrue(nfc.label.contains("NFC 卡片"))
        details.tap()

        let sheet = app.navigationBars["NFC 卡片"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollUntilHittable(app.staticTexts["使用条件"], in: app))
        XCTAssertTrue(app.staticTexts["将卡片贴近 Flipper 的 NFC 区域。"].exists)
        XCTAssertTrue(app.staticTexts["需要先在“设备”页连接 Flipper。"].exists)
        let open = app.buttons["functions.details.open"]
        XCTAssertTrue(scrollUntilHittable(open, in: app))
        XCTAssertFalse(open.isEnabled)
        capture(app, name: "29-功能搜索与中文详情")
        sheet.buttons["完成"].tap()

        XCTAssertTrue(scrollUntilHittable(nfc, in: app))
        nfc.tap()
        assertBlocked("需要先在“设备”页连接 Flipper。", in: app)

        replaceSearch(with: "", in: app)
        XCTAssertTrue(scrollUntilHittable(app.buttons["functions.builtin.infrared"], in: app))
        replaceSearch(with: "zz_no_function_987654", in: app)
        let noResults = app.descendants(matching: .any)
            .matching(identifier: "functions.noResults").firstMatch
        XCTAssertTrue(scrollUntilHittable(noResults, in: app))
        XCTAssertTrue(app.staticTexts["没有匹配的功能"].exists)
        XCTAssertFalse(app.buttons["functions.builtin.nfc"].exists)
        XCTAssertFalse(app.buttons["functions.nfcWorkbench"].exists)
        replaceSearch(with: "", in: app)
        XCTAssertTrue(scrollUntilHittable(app.buttons["functions.builtin.infrared"], in: app))
        XCTAssertFalse(noResults.exists)
    }

    @MainActor
    func testPreviewInstalledGamesHaveChineseDetailsAndCannotLaunch() throws {
        continueAfterFailure = false
        let app = launch(["-ui-testing-light", "-ui-testing-app-catalog"])
        openFunctions(in: app)
        XCTAssertEqual(app.staticTexts["functions.status"].label, "应用目录预览")
        capture(app, name: "28-中文应用目录预览")
        let source = app.segmentedControls["functions.source"]
        XCTAssertTrue(scrollUntilHittable(source, in: app))
        source.buttons["已安装"].tap()
        XCTAssertTrue(source.buttons["已安装"].isSelected)
        let games = app.buttons["functions.category.games"]
        XCTAssertTrue(scrollUntilHittable(games, in: app))
        games.tap()
        XCTAssertTrue(games.isSelected)

        let bounce = app.buttons["functions.app./ext/apps/Games/bounce.fap"]
        let sudoku = app.buttons["functions.app./ext/apps/Games/sudoku.fap"]
        XCTAssertTrue(scrollUntilHittable(bounce, in: app))
        XCTAssertTrue(scrollUntilHittable(sudoku, in: app))
        XCTAssertTrue(bounce.label.contains("弹跳球"))
        XCTAssertTrue(sudoku.label.contains("数独"))
        XCTAssertFalse(app.buttons["functions.builtin.nfc"].exists)
        XCTAssertFalse(app.buttons["functions.app./ext/apps/Tools/clock.fap"].exists)
        let visibleApps = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "functions.app."))
        XCTAssertEqual(Set(visibleApps.allElementsBoundByIndex.map(\.identifier)),
                       Set(["functions.app./ext/apps/Games/bounce.fap", "functions.app./ext/apps/Games/sudoku.fap"]))
        capture(app, name: "28b-已安装游戏分类预览")

        let details = app.buttons["functions.details./ext/apps/Games/bounce.fap"]
        XCTAssertTrue(scrollUntilHittable(details, in: app, direction: .down))
        details.tap()
        let sheet = app.navigationBars["弹跳球"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let introduction = app.staticTexts["滚动与跳跃，收集圆环并到达关卡出口。"].firstMatch
        XCTAssertTrue(introduction.exists)
        XCTAssertTrue(scrollUntilHittable(app.staticTexts["使用条件"], in: app))
        XCTAssertTrue(app.staticTexts["应用目录样例，尚未读取设备；此处不会启动设备应用。"].exists)
        XCTAssertTrue(app.staticTexts["应用目录预览不会向 Flipper 发送命令。"].exists)
        let open = app.buttons["functions.details.open"]
        XCTAssertTrue(scrollUntilHittable(open, in: app))
        XCTAssertFalse(open.isEnabled)
        capture(app, name: "30-应用分类预览与中文介绍")
        sheet.buttons["完成"].tap()

        XCTAssertTrue(scrollUntilHittable(bounce, in: app, direction: .down))
        bounce.tap()
        assertBlocked("应用目录预览不会向 Flipper 发送命令。", in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "functions.lastLaunch").firstMatch.exists,
                       "A preview must not create a device launch task")
    }

    @MainActor
    func testDarkAccessibilityCategoriesAndWorkbenchRemainOperable() throws {
        continueAfterFailure = false
        let app = launch(["-ui-testing-dark", "-ui-testing-large-text"])
        openFunctions(in: app)
        let luminance = try XCTUnwrap(pageBackgroundLuminance(of: app))
        XCTAssertLessThan(luminance, 0.3)

        let source = app.segmentedControls["functions.source"]
        XCTAssertTrue(scrollUntilHittable(source, in: app))
        source.buttons["常用"].tap()
        XCTAssertTrue(source.buttons["常用"].isSelected)
        let tools = app.buttons["functions.category.tools"]
        XCTAssertTrue(scrollUntilHittable(tools, in: app))
        XCTAssertGreaterThanOrEqual(tools.frame.width, 44)
        XCTAssertGreaterThanOrEqual(tools.frame.height, 44)
        tools.tap()
        XCTAssertTrue(tools.isSelected)
        XCTAssertFalse(app.buttons["functions.nfcWorkbench"].exists)
        let clear = app.buttons["functions.clearCategory"]
        XCTAssertTrue(scrollUntilHittable(clear, in: app))
        XCTAssertGreaterThanOrEqual(clear.frame.height, 44)
        capture(app, name: "31-深色大字-功能分类")
        clear.tap()
        XCTAssertFalse(clear.exists)

        replaceSearch(with: "NFC", in: app)
        let workbench = app.buttons["functions.nfcWorkbench"]
        XCTAssertTrue(scrollUntilHittable(workbench, in: app))
        workbench.tap()
        XCTAssertTrue(app.navigationBars["NFC 离线工作台"].waitForExistence(timeout: 5))
        let example = app.buttons["nfc.loadExample"]
        XCTAssertTrue(scrollUntilHittable(example, in: app))
        XCTAssertTrue(example.isEnabled)
    }

    // MARK: - Helpers

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = chineseLocale + arguments
        app.launch()
        return app
    }

    @MainActor
    private func openFunctions(in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["设备"].waitForExistence(timeout: 15))
        app.tabBars.buttons["功能"].tap()
        XCTAssertTrue(app.navigationBars["功能"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    private func replaceSearch(with query: String, in app: XCUIApplication) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(scrollUntilHittable(field, in: app, direction: .down))
        field.tap()
        let current = (field.value as? String) ?? ""
        if !current.isEmpty && current != "搜索功能或设备应用" {
            // Use UISearchTextField's native clear control instead of assuming that a
            // tap placed the insertion point at the end of an existing query.
            let clear = field.buttons.firstMatch
            XCTAssertTrue(clear.waitForExistence(timeout: 2))
            clear.tap()
        }
        if query.isEmpty {
            // An empty UISearchTextField disables its Search key. End native search
            // explicitly so later list drags cannot land on the remaining keyboard.
            let cancel = app.buttons["取消"].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 3))
            cancel.tap()
            XCTAssertFalse(app.keyboards.firstMatch.exists)
        } else {
            field.typeText(query + "\n")
        }
    }

    @MainActor
    private func assertBlocked(_ reason: String, in app: XCUIApplication) {
        let alert = app.alerts["暂时无法打开"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts[reason].exists)
        alert.buttons["知道了"].tap()
    }

    private enum ScrollDirection { case up, down }

    /// Fixed, momentum-free drags are bounded. Reverse drags return to earlier lazy rows;
    /// tests never restart the app or weaken an assertion if a control cannot be reached.
    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication,
                                    direction: ScrollDirection = .up, maxDrags: Int = 14) -> Bool {
        for _ in 0..<maxDrags {
            if element.exists && element.isHittable { return true }
            let startY: CGFloat = direction == .up ? 0.72 : 0.42
            let endY: CGFloat = direction == .up ? 0.42 : 0.72
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
            start.press(forDuration: 0.05, thenDragTo: end,
                        withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        return element.exists && element.isHittable
    }

    /// Match the original suite's real screenshot measurement for the dark grouped page.
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

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
