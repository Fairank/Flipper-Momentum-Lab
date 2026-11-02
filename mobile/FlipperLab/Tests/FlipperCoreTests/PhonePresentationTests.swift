import Foundation
import XCTest
@testable import FlipperCore

final class PhonePresentationTests: XCTestCase {
    func testKnownDeviceLabelsDoNotRewriteReportKeys() {
        let report = ["hardware_model": "Flipper Zero", "firmware_commit": "cafe1234",
                      "future_firmware_key": "unchanged"]
        let original = report
        XCTAssertEqual(DeviceInfoLabel.title(for: "hardware_model"), "设备型号")
        XCTAssertEqual(DeviceInfoLabel.title(for: "firmware_commit"), "固件提交")
        XCTAssertEqual(DeviceInfoLabel.title(for: "radio_stack_major"), "蓝牙协议栈主版本")
        XCTAssertEqual(DeviceInfoLabel.title(for: "future_firmware_key"), "future_firmware_key")
        XCTAssertEqual(DeviceInfoLabel.title(for: ""), "")
        for (key, value) in report { _ = DeviceInfoLabel.value(for: value, key: key) }
        XCTAssertEqual(report, original)
    }

    func testOnlyKnownBooleanAndModeValuesAreTranslated() {
        XCTAssertEqual(DeviceInfoLabel.value(for: "true", key: "firmware_commit_dirty"), "是")
        XCTAssertEqual(DeviceInfoLabel.value(for: "false", key: "firmware_commit_dirty"), "否")
        XCTAssertEqual(DeviceInfoLabel.value(for: "true", key: "enclave_valid"), "是")
        XCTAssertEqual(DeviceInfoLabel.value(for: "false", key: "enclave_valid"), "否")
        XCTAssertEqual(DeviceInfoLabel.value(for: "true", key: "radio_alive"), "可用")
        XCTAssertEqual(DeviceInfoLabel.value(for: "false", key: "radio_alive"), "不可用")
        XCTAssertEqual(DeviceInfoLabel.value(for: "Stack", key: "radio_mode"), "蓝牙协议栈")
        XCTAssertEqual(DeviceInfoLabel.value(for: "FUS", key: "radio_mode"), "固件升级服务（FUS）")
        for (key, value) in [("future_boolean", "true"), ("radio_mode", "stack"),
                             ("firmware_commit_dirty", " true"), ("radio_alive", "1")] {
            XCTAssertEqual(DeviceInfoLabel.value(for: value, key: key), value)
        }
    }

    func testOpaqueDeviceDataRemainsExact() {
        for (key, value) in [("firmware_commit", "deadBEEF0123"), ("firmware_version", "v1.2.3-dev"),
                             ("hardware_name", "true"), ("firmware_branch", "Stack"),
                             ("radio_ble_mac", "0011AaBBccFF"),
                             ("firmware_origin_git", "https://example.com/fork?tag=true")] {
            XCTAssertEqual(DeviceInfoLabel.value(for: value, key: key), value)
        }
    }

    func testChineseLocalizedErrorsArePreserved() {
        XCTAssertEqual(PhoneErrorDescription.describe(RPCError.busy), RPCError.busy.errorDescription)
        XCTAssertEqual(PhoneErrorDescription.describe(DisplayError(description: "保存失败：路径无效。")),
                       "保存失败：路径无效。")
        XCTAssertEqual(PhoneErrorDescription.describe(DisplayError(description: "𠮷字错误")), "𠮷字错误")
    }

    func testNonChineseLocalizedErrorsUseFallback() {
        for text in ["The operation failed.", "Échec de l’opération.", "エラー"] {
            let error = DisplayError(description: text)
            let original = error as NSError
            XCTAssertEqual(PhoneErrorDescription.describe(error),
                           "操作未完成（\(original.domain) / \(original.code)）。")
        }
        let error = DisplayError(description: nil)
        let original = error as NSError
        XCTAssertEqual(PhoneErrorDescription.describe(error),
                       "操作未完成（\(original.domain) / \(original.code)）。")
    }

    func testBluetoothAndNetworkErrorsKeepOriginalDiagnostics() {
        for (domain, code, expected) in [
            ("CBErrorDomain", 7, "蓝牙通信失败，请检查连接后重试。（错误 7）"),
            ("CBATTErrorDomain", 13, "设备蓝牙请求失败，请检查连接后重试。（错误 13）"),
            (NSURLErrorDomain, -1009, "网络请求失败，请检查网络后重试。（错误 -1009）"),
            ("FutureTransportDomain", 42, "操作未完成（FutureTransportDomain / 42）。"),
        ] {
            let original = NSError(domain: domain, code: code,
                                   userInfo: [NSLocalizedDescriptionKey: "Remote failure", "device": "Flipper-7"])
            let identity = ObjectIdentifier(original)
            XCTAssertEqual(PhoneErrorDescription.describe(original), expected)
            XCTAssertEqual(ObjectIdentifier(original), identity)
            XCTAssertEqual(original.domain, domain)
            XCTAssertEqual(original.code, code)
            XCTAssertEqual(original.userInfo[NSLocalizedDescriptionKey] as? String, "Remote failure")
            XCTAssertEqual(original.userInfo["device"] as? String, "Flipper-7")
        }
    }

    func testVerifiedInstalledTitlesKeepLaunchIdentity() {
        for (path, title) in [("/ext/apps/Tools/calculator.fap", "计算器"),
                              ("/ext/apps/Media/music_player.fap", "音乐播放器"),
                              ("/ext/apps/Media/wav_player.fap", "WAV 播放器")] {
            let function = FlipperFunction.installed(path: path)
            XCTAssertEqual(function?.title, title)
            XCTAssertEqual(function?.id, path)
            XCTAssertEqual(function?.launchName, path)
        }
    }

    func testBuiltInChineseTitlesKeepRPCNames() {
        for (id, title, launchName) in [
            ("subghz", "Sub-GHz 无线", "Sub-GHz"), ("nfc", "NFC 卡片", "NFC"),
            ("lfrfid", "低频 RFID", "125 kHz RFID"), ("ibutton", "iButton 接触钥匙", "iButton"),
            ("gpio", "GPIO 扩展接口", "GPIO"), ("bad_kb", "键盘脚本", "Bad KB"),
            ("lab", "设备功能指南", "Flipper Lab"),
        ] {
            let function = FlipperFunction.builtIns.first { $0.id == id }
            XCTAssertEqual(function?.title, title)
            XCTAssertEqual(function?.launchName, launchName)
        }
    }

    func testCategoryDisplayAndNestedLaunchIdentityAreIndependent() {
        XCTAssertEqual(FlipperFunction.displayCategory(for: "GPIO/GPS"), "扩展接口 / GPS 定位")
        XCTAssertEqual(FlipperFunction.displayCategory(for: "USB"), "USB 工具")
        XCTAssertEqual(FlipperFunction.displayCategory(for: "UnknownFolder"), "其他应用")
        XCTAssertEqual(FlipperFunction.displayCategory(for: "GPIO/UnknownFolder"), "扩展接口 / 其他应用")
        let path = "/ext/apps/GPIO/GPS/my_receiver.fap"
        let function = FlipperFunction.installed(path: path)
        XCTAssertEqual(function?.category, "扩展接口 / GPS 定位")
        XCTAssertEqual(function?.title, "my receiver")
        XCTAssertEqual(function?.id, path)
        XCTAssertEqual(function?.launchName, path)
    }
}

private struct DisplayError: LocalizedError {
    let description: String?
    var errorDescription: String? { description }
}
