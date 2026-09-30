import XCTest
@testable import FlipperCore

final class FunctionCatalogTests: XCTestCase {
    private let commonIDs = ["infrared", "nfc", "gpio", "power", "clock"]
    private let installedPaths = [
        "/ext/apps/Tools/clock.fap",
        "/ext/apps/Games/bounce.fap",
        "/ext/apps/Tools/my_tool.fap",
        "/ext/apps/Games/my_tool.fap",
        "/ext/apps/GPIO/GPS/gps_tool.fap",
        "/ext/apps/Other/clock.fap",
        "/ext/apps/root.fap",
        "/ext/apps/NFC/nfc_helper.fap",
        "/ext/apps/Tools/Games/nested_tool.fap",
    ]

    private func builtIn(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> FlipperFunction {
        try XCTUnwrap(FlipperFunction.builtIns.first { $0.id == id }, file: file, line: line)
    }

    private func installed(_ path: String, file: StaticString = #filePath, line: UInt = #line) throws -> FlipperFunction {
        try XCTUnwrap(FlipperFunction.installed(path: path), file: file, line: line)
    }

    /// Display data only: these factories do not discover an app or connect a device.
    private func fixtures() throws -> [FlipperFunction] {
        let common = try commonIDs.map { try builtIn($0) }
        let apps = try installedPaths.map { try installed($0) }
        return common + apps
    }

    func testSourcesKeepTheirActualInputEntriesAndOrder() throws {
        let entries = try fixtures()
        XCTAssertEqual(FunctionCatalogQuery().filter(entries).map(\.id), commonIDs + installedPaths)
        XCTAssertEqual(FunctionCatalogQuery(source: .common).filter(entries).map(\.id), commonIDs)
        XCTAssertEqual(FunctionCatalogQuery(source: .installed).filter(entries).map(\.id), installedPaths)
        XCTAssertTrue(FunctionCatalogQuery().filter([]).isEmpty)
    }

    func testInstalledFilterDoesNotInferAppsFromTheChineseMetadataTable() throws {
        // Metadata for clock.fap exists, but only the supplied discovery result may appear.
        let common = try commonIDs.map { try builtIn($0) }
        XCTAssertTrue(FunctionCatalogQuery(source: .installed).filter(common).isEmpty)
        let discovered = try installed("/ext/apps/Games/bounce.fap")
        XCTAssertEqual(FunctionCatalogQuery(source: .installed).filter(common + [discovered]).map(\.launchName),
                       ["/ext/apps/Games/bounce.fap"])
    }

    func testSourceCategoryAndKeywordAreCombined() throws {
        let entries = try fixtures()
        let installedGame = FunctionCatalogQuery(source: .installed, category: .games, search: "my tool")
        XCTAssertEqual(installedGame.filter(entries).map(\.id), ["/ext/apps/Games/my_tool.fap"])
        let commonNFC = FunctionCatalogQuery(source: .common, category: .wireless, search: "NFC")
        XCTAssertEqual(commonNFC.filter(entries).map(\.id), ["nfc"])
        let power = FunctionCatalogQuery(category: .system, search: "电源")
        XCTAssertEqual(power.filter(entries).map(\.id), ["power"])
    }

    func testChineseTitlesAndCatalogueCategoryAliasesAreSearchable() throws {
        let entries = try fixtures()
        XCTAssertEqual(FunctionCatalogQuery(search: "弹跳球").filter(entries).map(\.id),
                       ["/ext/apps/Games/bounce.fap"])
        XCTAssertEqual(FunctionCatalogQuery(search: "实用工具").filter(entries).map(\.id), [
            "/ext/apps/Tools/clock.fap", "/ext/apps/Tools/my_tool.fap", "/ext/apps/Tools/Games/nested_tool.fap",
        ])
        XCTAssertEqual(FunctionCatalogQuery(search: "无线识别").filter(entries).map(\.id),
                       ["infrared", "nfc", "/ext/apps/NFC/nfc_helper.fap"])
    }

    func testEnglishRPCNamesAndFilenamesMatchChineseDisplayEntries() throws {
        let entries = try fixtures()
        XCTAssertEqual(FunctionCatalogQuery(search: "iNfRaReD").filter(entries).map(\.id), ["infrared"])
        XCTAssertEqual(FunctionCatalogQuery(search: "CLOCK.FAP").filter(entries).map(\.id),
                       ["/ext/apps/Tools/clock.fap", "/ext/apps/Other/clock.fap"])
        let clock = try installed("/ext/apps/Tools/clock.fap")
        XCTAssertEqual(clock.title, "床头时钟")
        XCTAssertTrue(FunctionCatalogQuery(search: "CLOCK.FAP").includes(clock))
    }

    func testMultipleTermsMatchInEitherOrderAndAllAreRequired() throws {
        let entries = try fixtures()
        let expected = ["/ext/apps/Tools/clock.fap"]
        XCTAssertEqual(FunctionCatalogQuery(search: "\tCLOCK.FAP \n 工具  ").filter(entries).map(\.id), expected)
        XCTAssertEqual(FunctionCatalogQuery(search: " 工具\t clock.fap\r\n").filter(entries).map(\.id), expected)
        XCTAssertTrue(FunctionCatalogQuery(search: "clock.fap 不存在的关键词").filter(entries).isEmpty)
    }

    func testWhitespaceOnlyQueryIsAnEmptySearch() throws {
        let entries = try fixtures()
        let whitespace = " \t\n\r\u{00A0}\u{2003}\u{3000}"
        XCTAssertEqual(FunctionCatalogQuery(search: whitespace).filter(entries).map(\.id), entries.map(\.id))
        XCTAssertTrue(FunctionCatalogQuery(search: whitespace).matches(text: ""))
        XCTAssertTrue(FunctionCatalogQuery(search: "").matches(text: "NFC 离线工作台"))
    }

    func testCategoryUsesTheValidatedRootFolderAndBuiltInIdentity() throws {
        XCTAssertEqual(FunctionCatalogCategory.category(of: try builtIn("gpio")), .expansion)
        XCTAssertEqual(FunctionCatalogCategory.category(of: try builtIn("expansion")), .expansion)
        for (path, category) in [
            ("/ext/apps/root.fap", FunctionCatalogCategory.other),
            ("/ext/apps/UnknownFolder/Games/tool.fap", .other),
            ("/ext/apps/Tools/Games/tool.fap", .tools),
            ("/ext/apps/Games/Tools/tool.fap", .games),
            ("/ext/apps/GPIO/GPS/gps_tool.fap", .expansion),
            ("/ext/apps/NFC/reader.fap", .wireless),
            ("/ext/apps/Media/player.fap", .media),
            ("/ext/apps/Settings/helper.fap", .system),
        ] {
            let function = try installed(path)
            XCTAssertEqual(FunctionCatalogCategory.category(of: function), category, path)
            XCTAssertEqual(function.launchName, path)
        }
    }

    func testSameDisplayTitleFromDifferentFoldersRemainsTwoApps() throws {
        let matches = FunctionCatalogQuery(source: .installed, search: "my tool").filter(try fixtures())
        XCTAssertEqual(matches.map(\.title), ["my tool", "my tool"])
        XCTAssertEqual(matches.map(\.id), ["/ext/apps/Tools/my_tool.fap", "/ext/apps/Games/my_tool.fap"])
        XCTAssertEqual(Set(matches.map(\.id)).count, 2)
        XCTAssertEqual(matches.map(\.launchName), matches.map(\.id))
    }

    func testFilteringPreservesExactIDsAndLaunchNames() throws {
        var entries = try fixtures()
        entries.append(try installed("/ext/apps/Tools/MixedCase.FAP"))
        let originalIDs = entries.map(\.id)
        let originalPaths = entries.map(\.launchName)
        let originals = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let categories: [FunctionCatalogCategory?] = [nil] + FunctionCatalogCategory.allCases.map { Optional($0) }
        for source in FunctionCatalogSource.allCases {
            for category in categories {
                for search in ["", "NFC", "工具 clock.fap", "MixedCase.FAP"] {
                    for result in FunctionCatalogQuery(source: source, category: category, search: search).filter(entries) {
                        let original = try XCTUnwrap(originals[result.id])
                        XCTAssertEqual(result.id, original.id)
                        XCTAssertEqual(result.launchName, original.launchName)
                        XCTAssertEqual(result.title, original.title)
                        XCTAssertEqual(result.isInstalledApp, original.isInstalledApp)
                    }
                }
            }
        }
        XCTAssertEqual(entries.map(\.id), originalIDs)
        XCTAssertEqual(entries.map(\.launchName), originalPaths)
        XCTAssertEqual(FunctionCatalogQuery(search: "mixedcase.fap").filter(entries).map(\.launchName),
                       ["/ext/apps/Tools/MixedCase.FAP"])
    }

    func testIgnoringCategoryForCountsStillAppliesSourceAndSearch() throws {
        let entries = try fixtures()
        for (source, expectedID) in [(FunctionCatalogSource.common, "nfc"),
                                     (.installed, "/ext/apps/NFC/nfc_helper.fap")] {
            let query = FunctionCatalogQuery(source: source, category: .games, search: "NFC")
            XCTAssertTrue(query.filter(entries).isEmpty)
            XCTAssertEqual(entries.filter { query.includes($0, ignoringCategory: true) }.map(\.id), [expectedID])
            XCTAssertFalse(query.includes(try installed("/ext/apps/Tools/clock.fap"), ignoringCategory: true))
        }
        let allInstalled = FunctionCatalogQuery(source: .installed, category: .games)
        XCTAssertEqual(entries.filter { allInstalled.includes($0, ignoringCategory: true) }.count, installedPaths.count)
        XCTAssertFalse(allInstalled.includes(try builtIn("nfc"), ignoringCategory: true))
    }

    func testPhoneWorkbenchDescriptionsUseTextSearchWithoutAnRPCIdentity() {
        let nfc = "NFC 离线工作台：在 iPhone 上分析公开样本，管理增强字典。"
        let serial = "扩展板实时数据：接收串口输出并导出记录。"
        let nfcQuery = FunctionCatalogQuery(search: "  NfC\n离线  ")
        XCTAssertTrue(nfcQuery.matches(text: nfc))
        XCTAssertFalse(nfcQuery.matches(text: serial))
        XCTAssertTrue(FunctionCatalogQuery(search: "实时 扩展板").matches(text: serial))
        XCTAssertFalse(FunctionCatalogQuery(search: "NFC 实时").matches(text: nfc))
    }
}
