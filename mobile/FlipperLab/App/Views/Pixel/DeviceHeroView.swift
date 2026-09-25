import SwiftUI

/// What the LCD draws beside the dolphin.
enum LCDOverlay: Equatable {
    case empty
    case arcs(Int)
    case sleep
}

/// Orange backlit screen: a 64 × 32 grid of `px`-point cells inside a 6 pt bezel — the only
/// framed object left in the app. Hidden from VoiceOver; its state is real text beside it.
struct LCDScreen: View {
    let dolphin: PixelBitmap
    let decoration: LCDOverlay
    let lines: [String]
    let px: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            LabColor.brandOrange
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

/// 设备 status header (UI_APPLE_DESIGN.md §4): the compact LCD companion (px 2, 128 × 64 pt)
/// beside the status title, then one explanation; stacked at accessibility text sizes. The
/// LCD only receives real connection values — never record content. The group carries
/// `device.hero`; its status title carries `device.status`.
@MainActor struct DeviceStatusHeader: View {
    let state: FlipperDevice.State
    let deviceName: String
    let protocolVersion: String
    let explanation: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var eyesClosed = false
    @State private var arcFrame = 3

    var body: some View {
        let motion: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.2)
        VStack(alignment: .leading, spacing: 12) {
            AdaptiveStack(verticalAlignment: .center, spacing: 16) {
                LCDScreen(dolphin: dolphin, decoration: decoration, lines: lcdLines, px: 2)
                statusText
                    .animation(motion, value: state)
            }
            Text(explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(motion, value: state)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("device.hero")
        .task(id: MotionKey(state: state, reduceMotion: reduceMotion)) {
            await runMotion()
        }
    }

    private var statusText: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                statusSymbol
                Text(state.rawValue)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("device.status")
            }
            .font(.title2.weight(.semibold))
            if state == .ready {
                Text(verbatim: "\(deviceName) · 协议 \(protocolVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    /// A spinner while the device is working, a check once ready; the title says the rest.
    @ViewBuilder private var statusSymbol: some View {
        switch state {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        case .scanning, .connecting, .discovering, .negotiating:
            ProgressView()
                .accessibilityHidden(true)
        case .idle, .unavailable:
            EmptyView()
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
