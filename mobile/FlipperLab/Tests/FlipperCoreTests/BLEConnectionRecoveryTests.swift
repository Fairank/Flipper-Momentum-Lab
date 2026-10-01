import XCTest
@testable import FlipperCore

final class BLEConnectionRecoveryTests: XCTestCase {
    func testInitialConnectionDoesNotRetryWithoutAReadySession() {
        var recovery = BLEConnectionRecovery()
        XCTAssertNil(recovery.nextDelay(bluetoothAvailable: true))
        XCTAssertNil(recovery.nextDelay(bluetoothAvailable: false))
        XCTAssertNil(recovery.nextDelay(bluetoothAvailable: true))
        XCTAssertEqual(recovery.attempt, 0)
    }

    func testBackoffIsFiniteAndExhaustionCannotRearmItself() {
        var recovery = BLEConnectionRecovery()
        recovery.becameReady()
        for (index, expectedDelay) in [1, 3, 6].enumerated() {
            XCTAssertEqual(recovery.nextDelay(bluetoothAvailable: true), expectedDelay)
            XCTAssertEqual(recovery.attempt, index + 1)
        }
        XCTAssertNil(recovery.nextDelay(bluetoothAvailable: true))
        XCTAssertEqual(recovery.attempt, 0)
        for _ in 0..<5 {
            XCTAssertNil(recovery.nextDelay(bluetoothAvailable: true))
        }
    }

    func testManualCancellationDisarmsEveryRetryPhase() {
        for issuedRetries in 0...3 {
            var recovery = BLEConnectionRecovery()
            recovery.becameReady()
            for delay in [1, 3, 6].prefix(issuedRetries) {
                XCTAssertEqual(recovery.nextDelay(bluetoothAvailable: true), delay)
            }
            recovery.cancel()
            XCTAssertEqual(recovery.attempt, 0, "Cancelled after \(issuedRetries) retries")
            XCTAssertNil(recovery.nextDelay(bluetoothAvailable: true))
            recovery.cancel()
            XCTAssertNil(recovery.nextDelay(bluetoothAvailable: true))
        }
    }

    func testBluetoothOffDisarmsAndPoweringOnCannotRestartRetries() {
        for issuedRetries in 0...3 {
            var recovery = BLEConnectionRecovery()
            recovery.becameReady()
            for delay in [1, 3, 6].prefix(issuedRetries) {
                XCTAssertEqual(recovery.nextDelay(bluetoothAvailable: true), delay)
            }
            XCTAssertNil(recovery.nextDelay(bluetoothAvailable: false))
            XCTAssertEqual(recovery.attempt, 0)
            XCTAssertNil(recovery.nextDelay(bluetoothAvailable: true))
            XCTAssertNil(recovery.nextDelay(bluetoothAvailable: true))
        }
    }

    func testBecomingReadyStartsANewBudgetDuringRetriesAndAfterExhaustion() {
        for issuedRetries in 0...4 {
            var recovery = BLEConnectionRecovery()
            recovery.becameReady()
            for delay in [1, 3, 6].prefix(issuedRetries) {
                XCTAssertEqual(recovery.nextDelay(bluetoothAvailable: true), delay)
            }
            if issuedRetries == 4 {
                XCTAssertNil(recovery.nextDelay(bluetoothAvailable: true))
            }
            recovery.becameReady()
            XCTAssertEqual(recovery.attempt, 0)
            for (index, delay) in [1, 3, 6].enumerated() {
                XCTAssertEqual(recovery.nextDelay(bluetoothAvailable: true), delay)
                XCTAssertEqual(recovery.attempt, index + 1)
            }
            XCTAssertNil(recovery.nextDelay(bluetoothAvailable: true))
        }
    }

    func testOnlyBecomingReadyRearmsAfterCancellationOrBluetoothLoss() {
        for cancelledManually in [true, false] {
            var recovery = BLEConnectionRecovery()
            recovery.becameReady()
            XCTAssertEqual(recovery.nextDelay(bluetoothAvailable: true), 1)
            if cancelledManually {
                recovery.cancel()
            } else {
                XCTAssertNil(recovery.nextDelay(bluetoothAvailable: false))
            }
            XCTAssertNil(recovery.nextDelay(bluetoothAvailable: true))
            recovery.becameReady()
            XCTAssertEqual(recovery.attempt, 0)
            XCTAssertEqual(recovery.nextDelay(bluetoothAvailable: true), 1)
        }
    }
}
