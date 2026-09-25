import Foundation

/// Keys and event values are fixed by the pinned assets/protobuf/gui.proto.
public enum RemoteKey: Int, Sendable, CaseIterable {
    case up = 0, down = 1, right = 2, left = 3, ok = 4, back = 5
}

/// The GUI RPC sends u8g2's 128 × 64, vertically packed framebuffer.
public struct RemoteScreenFrame: Sendable, Equatable {
    public static let width = 128
    public static let height = 64
    public static let byteCount = width * height / 8
    public let bitmap: Data
    public let orientation: UInt64
    public let foreground: UInt64
    public let background: UInt64

    public init(payload: Data) throws {
        let message = try PBMessage(payload)
        guard let bitmap = message.bytes(1), bitmap.count == Self.byteCount,
              message.uint(2) <= 3,
              message.uint(3) <= UInt32.max,
              message.uint(4) <= UInt32.max else { throw RPCError.malformed }
        self.bitmap = bitmap
        orientation = message.uint(2)
        foreground = message.uint(4)
        background = message.uint(3)
    }

    /// Bytes are RGBA, one pixel per channel quartet, for a platform image provider.
    public func rgbaPixels() -> Data {
        let ink = Self.color(foreground, fallback: (0, 0, 0))
        let paper = Self.color(background, fallback: (255, 130, 0))
        let bytes = [UInt8](bitmap)
        var output = Data(count: Self.width * Self.height * 4)
        output.withUnsafeMutableBytes { rawBuffer in
            let rgba = rawBuffer.bindMemory(to: UInt8.self)
            for y in 0..<Self.height {
                let tileRow = (y / 8) * Self.width
                let bit = UInt8(1 << (y % 8))
                for x in 0..<Self.width {
                    let on = bytes[tileRow + x] & bit != 0
                    let color = on ? ink : paper
                    let offset = (y * Self.width + x) * 4
                    rgba[offset] = color.0
                    rgba[offset + 1] = color.1
                    rgba[offset + 2] = color.2
                    rgba[offset + 3] = 255
                }
            }
        }
        return output
    }

    private static func color(_ value: UInt64, fallback: (UInt8, UInt8, UInt8)) -> (UInt8, UInt8, UInt8) {
        // ScreenFrameColor packs a one-byte mode and three RGB bytes in this firmware.
        guard value & 0xff == 1 else { return fallback }
        return (UInt8((value >> 8) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 24) & 0xff))
    }
}
