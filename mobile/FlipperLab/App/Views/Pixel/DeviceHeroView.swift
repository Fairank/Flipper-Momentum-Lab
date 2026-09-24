import SwiftUI

/// What the LCD draws beside the dolphin.
enum LCDOverlay: Equatable {
    case empty
    case arcs(Int)
    case sleep
}

/// Orange backlit screen: a 64 × 32 grid of `px`-point cells inside a 6 pt bezel (§4.3).
struct LCDScreen: View {
    let dolphin: PixelBitmap
    let decoration: LCDOverlay
    let lines: [String]
    let px: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            LabColor.orange
            PixelBitmapView(bitmap: dolphin, unit: px, color: LabColor.lcdInk)
                .offset(x: px, y: 12 * px)
            overlayArt
            tokens
        }
        .frame(width: 64 * px, height: 32 * px)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .padding(6)
        .background(LabColor.lcdInk, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder private var overlayArt: some View {
        switch decoration {
        case .empty:
            EmptyView()
        case .arcs(let count):
            ZStack(alignment: .topLeading) {
                ForEach(0..<min(max(count, 0), PixelSprites.arcs.count), id: \.self) { index in
                    PixelBitmapView(bitmap: PixelSprites.arcs[index], unit: px, color: LabColor.lcdInk)
                }
            }
            .offset(x: 35 * px, y: 16 * px)
        case .sleep:
            PixelBitmapView(bitmap: PixelSprites.sleep, unit: px, color: LabColor.lcdInk)
                .offset(x: 30 * px, y: 8 * px)
        }
    }

    /// ASCII tokens only, top-right with a two-cell margin.
    private var tokens: some View {
        VStack(alignment: .trailing, spacing: px) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .font(LabFont.lcd(px))
        .foregroundStyle(LabColor.lcdInk)
        .padding(.top, 2 * px)
        .padding(.trailing, 2 * px)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

/// Decorative direction pad: 88 pt ring, square direction marks, orange centre.
struct DPadView: View {
    var body: some View {
        ZStack {
            Circle().fill(LabColor.surface)
            Circle().strokeBorder(LabColor.strongLine, lineWidth: 2)
            mark.offset(y: -29)
            mark.offset(x: 29)
            mark.offset(y: 29)
            mark.offset(x: -29)
            Circle()
                .fill(LabColor.orange)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(LabColor.strongLine, lineWidth: 1.5))
        }
        .frame(width: 88, height: 88)
        .accessibilityHidden(true)
    }

    private var mark: some View {
        Rectangle().fill(LabColor.ink).frame(width: 8, height: 8)
    }
}

/// Decorative back key, 28 × 28.
struct BackKeyView: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        shape
            .fill(LabColor.surface)
            .overlay(shape.strokeBorder(LabColor.strongLine, lineWidth: 1.5))
            .overlay(Rectangle().fill(LabColor.orange).frame(width: 6, height: 6))
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }
}

/// Abstract front of the companion device (not an official render): LCD with the original
/// pixel dolphin, D-pad and back key. It only receives real connection values — never
/// record content — and the whole card is one accessibility element; the status is also
/// written as real text beneath it.
@MainActor struct DeviceHeroView: View {
    let state: FlipperDevice.State
    let deviceName: String
    let protocolVersion: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var eyesClosed = false
    @State private var arcFrame = 3

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        VStack(spacing: 0) {
            // Largest whole-point cell size that fits: 4 on Pro Max widths, 3 on 6.1-inch phones.
            ViewThatFits(in: .horizontal) {
                face(px: 4)
                face(px: 3)
                face(px: 2)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            LabColor.orange
                .frame(height: 6)
        }
        .background(LabColor.surfaceAlt)
        .clipShape(shape)
        .overlay(shape.strokeBorder(LabColor.strongLine, lineWidth: 1.5))
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("device.hero")
        .task(id: MotionKey(state: state, reduceMotion: reduceMotion)) {
            await runMotion()
        }
    }

    /// Accessibility text sizes drop the decorative controls and give the LCD the full width.
    @ViewBuilder private func face(px: CGFloat) -> some View {
        let screen = LCDScreen(dolphin: dolphin, decoration: decoration, lines: lcdLines, px: px)
        if dynamicTypeSize.isAccessibilitySize {
            screen
        } else {
            HStack(spacing: 0) {
                screen
                Spacer(minLength: 16)
                VStack(alignment: .trailing, spacing: 12) {
                    DPadView()
                    BackKeyView()
                }
                .frame(width: 88)
            }
        }
    }

    private var dolphin: PixelBitmap {
        (state == .unavailable || eyesClosed) ? PixelSprites.dolphinClosed : PixelSprites.dolphinOpen
    }

    private var decoration: LCDOverlay {
        switch state {
        case .scanning: return .arcs(reduceMotion ? 3 : arcFrame)
        case .connecting, .discovering, .negotiating: return .arcs(3)
        case .unavailable: return .sleep
        case .idle, .ready: return .empty
        }
    }

    private var lcdLines: [String] {
        switch state {
        case .idle: return ["NO LINK"]
        case .scanning: return ["SCAN"]
        case .connecting: return ["PAIR"]
        case .discovering: return ["SETUP"]
        case .negotiating: return ["CHECK"]
        case .unavailable: return ["NO BT"]
        case .ready: return readyLines
        }
    }

    /// Real device name and RPC version; a line with non-ASCII characters is not drawn on the LCD.
    private var readyLines: [String] {
        let name = deviceName.count > 13 ? String(deviceName.prefix(12)) + "~" : deviceName
        let lines = [name, "RPC " + protocolVersion].filter { line in
            !line.isEmpty && line.allSatisfy(\.isASCII)
        }
        return lines.isEmpty ? ["READY"] : lines
    }

    private var accessibilityDescription: String {
        var text = "Flipper 设备示意图，状态：\(state.rawValue)"
        if state == .ready {
            text += "，\(deviceName)，协议版本 \(protocolVersion)"
        }
        return text
    }

    private struct MotionKey: Equatable {
        let state: FlipperDevice.State
        let reduceMotion: Bool
    }

    /// Scanning arcs cycle every 350 ms; idle and ready blink for 120 ms every 5 s.
    /// Reduce Motion shows static art. The task is cancelled whenever the state changes.
    private func runMotion() async {
        eyesClosed = false
        arcFrame = 3
        guard !reduceMotion else { return }
        switch state {
        case .scanning:
            var frame = 0
            while !Task.isCancelled {
                arcFrame = frame
                try? await Task.sleep(for: .milliseconds(350))
                frame = (frame + 1) % 4
            }
        case .idle, .ready:
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                eyesClosed = true
                try? await Task.sleep(for: .milliseconds(120))
                eyesClosed = false
            }
        case .connecting, .discovering, .negotiating, .unavailable:
            break
        }
    }
}
