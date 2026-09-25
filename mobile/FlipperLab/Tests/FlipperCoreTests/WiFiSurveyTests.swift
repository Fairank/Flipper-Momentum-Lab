import Foundation
import XCTest
import FlipperCore

final class WiFiSurveyTests: XCTestCase {
    private let header = "# Flipper Lab WiFi Survey v1\nssid,bssid,channel,rssi,security\n"

    func testParsesQuotedNamesHiddenNetworksAndChannelStatistics() throws {
        let text = header
            + "\"Cafe, \"\"North\"\"\",02:11:22:33:44:55,6,-54,WPA2\n"
            + ",02:11:22:33:44:66,11,-71,OPEN\n"
            + "Cafe,02:11:22:33:44:77,6,-45,WPA3\n"
        let survey = try WiFiSurvey.parse(text)
        XCTAssertEqual(survey.accessPoints.count, 3)
        XCTAssertEqual(survey.accessPoints[0].ssid, "Cafe, \"North\"")
        XCTAssertEqual(survey.accessPoints[0].bssid, "02:11:22:33:44:55")
        XCTAssertEqual(survey.accessPoints[1].ssid, "")
        XCTAssertEqual(survey.uniqueSSIDCount, 2)
        XCTAssertEqual(survey.channelCounts, [6: 2, 11: 1])
        XCTAssertEqual(survey.strongestFirst.map(\.rssi), [-45, -54, -71])
    }

    func testCRLFAndUppercaseBSSIDNormalization() throws {
        let text = (header + "Home,aa:bb:cc:dd:ee:ff,1,-80,WPA2\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        let survey = try WiFiSurvey.parse(text)
        XCTAssertEqual(survey.accessPoints[0].bssid, "AA:BB:CC:DD:EE:FF")
    }

    func testRejectsMalformedRowsAndDuplicateBSSIDChannel() throws {
        let invalid = [
            "Home,not-a-mac,6,-54,WPA2\n",
            "Home,02:11:22:33:44:55,0,-54,WPA2\n",
            "Home,02:11:22:33:44:55,6,-128,WPA2\n",
            "Home,02:11:22:33:44:55,6,-54\n",
            "Ho\"me,02:11:22:33:44:55,6,-54,WPA2\n",
            "\"Home,02:11:22:33:44:55,6,-54,WPA2\n",
        ]
        for row in invalid {
            XCTAssertThrowsError(try WiFiSurvey.parse(header + row), row)
        }
        let sameTwice = header
            + "Home,02:11:22:33:44:55,6,-54,WPA2\n"
            + "Home,02:11:22:33:44:55,6,-55,WPA2\n"
        XCTAssertThrowsError(try WiFiSurvey.parse(sameTwice)) {
            XCTAssertEqual($0 as? WiFiSurveyError, .duplicateNetwork(line: 4))
        }
    }

    func testLimitsAndRequiredHeader() throws {
        XCTAssertThrowsError(try WiFiSurvey.parse("ssid,bssid,channel,rssi,security\n")) {
            XCTAssertEqual($0 as? WiFiSurveyError, .invalidHeader)
        }
        XCTAssertThrowsError(try WiFiSurvey.parse("# Flipper Lab WiFi Survey v1\nwrong\n")) {
            XCTAssertEqual($0 as? WiFiSurveyError, .invalidColumns)
        }
        XCTAssertThrowsError(try WiFiSurvey.parse(String(repeating: "x", count: WiFiSurvey.maxBytes + 1))) {
            XCTAssertEqual($0 as? WiFiSurveyError, .tooLarge)
        }
        let rows = (0...WiFiSurvey.maxAccessPoints).map { index in
            String(format: "N,02:00:00:00:%02X:%02X,1,-50,WPA2", index / 256, index % 256)
        }
        XCTAssertThrowsError(try WiFiSurvey.parse(header + rows.joined(separator: "\n"))) {
            XCTAssertEqual($0 as? WiFiSurveyError, .tooManyNetworks)
        }
    }
}
