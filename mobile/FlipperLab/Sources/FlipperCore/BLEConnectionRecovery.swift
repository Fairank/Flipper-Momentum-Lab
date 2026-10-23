import Foundation

/// Reconnect the transport after a previously ready link drops. Never retry an RPC action.
/// Pairing failures on the first connection are not retried; manual cancellation disarms it.
public struct BLEConnectionRecovery: Sendable {
    public static let delays = [1, 3, 6]
    public private(set) var attempt = 0
    private var armed = false

    public init() {}

    public mutating func becameReady() { armed = true; attempt = 0 }
    public mutating func cancel() { armed = false; attempt = 0 }

    public mutating func nextDelay(bluetoothAvailable: Bool) -> Int? {
        guard armed, bluetoothAvailable, attempt < Self.delays.count else {
            cancel(); return nil
        }
        let delay = Self.delays[attempt]
        attempt += 1
        return delay
    }
}
