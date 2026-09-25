import SwiftUI
import UIKit
import FlipperCore

/// 远程操作: the connected Flipper's real 128 × 64 screen and its six keys as grouped sections
/// (UI_APPLE_DESIGN.md §3–4). The screen stream starts when the page appears and stops when it
/// leaves. The only picture ever drawn is `FlipperDevice.remoteImage`, a frame the connected
/// device sent after the stream started; every other state shows a neutral grey placeholder,
/// never a drawn, cached or sample screen. One tap sends one press / short / release sequence,
/// or press / long / release when the deliberate one-shot long mode is enabled. There is no
/// continuous hold or auto-repeat, and the next key waits until the previous one returns.
@MainActor struct RemoteControlView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var starting = false
    @State private var failure: String?
    @State private var keyFailure: String?
    @State private var pressing: RemoteKey?
    @State private var longPressNext = false
    @State private var session: Task<Void, Never>?
    @State private var keyTask: Task<Void, Never>?

    private var device: FlipperDevice { model.device }

    /// Reading order for the single-column keypad at accessibility text sizes.
    private static let keyOrder: [RemoteKey] = [.up, .down, .left, .right, .ok, .back]

    /// One state at a time, in priority order: a lost connection, a failed start, the start in
    /// flight, then whether the device has sent a frame yet.
    private enum Status: Equatable {
        case disconnected, failed(String), connecting, waitingFrame, live
    }

    private var status: Status {
        if !device.ready { return .disconnected }
        if let failure { return .failed(failure) }
        if starting || !device.remoteActive { return .connecting }
        return device.remoteImage == nil ? .waitingFrame : .live
    }

    private var failureMessage: String? {
        if case .failed(let message) = status { return message }
        return nil
    }

    /// Keys need a running stream, a free RPC channel and no key still in flight.
    private var keysEnabled: Bool {
        (status == .waitingFrame || status == .live) && !model.busy && pressing == nil
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    screen
                    statusRow
                }
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            } footer: {
                Text("画面由已连接的 Flipper 实时发送；未连接或尚未收到画面时，这里不会显示任何模拟内容。离开本页会停止屏幕传输。")
            }
            if let failureMessage {
                Section {
                    ErrorRow(title: "无法开启屏幕传输", message: failureMessage) {
                        Button("重试") { retry() }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.large)
                            .disabled(starting)
                            .accessibilityIdentifier("remote.retry")
                    }
                }
            }
            if status == .disconnected {
                disconnectedSection
            }
            keysSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("远程操作")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { beginSession() }
        .onDisappear { endSession() }
    }

    // MARK: Screen — only a frame the connected device sent, otherwise a neutral placeholder

    private var screen: some View {
        Group {
            if status == .live, let image = device.remoteImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .aspectRatio(2, contentMode: .fit)
                    .accessibilityLabel("Flipper 屏幕画面，来自已连接的 \(device.deviceName)")
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier("remote.screen")
            } else {
                placeholder
            }
        }
        .frame(maxWidth: 512)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .padding(6)
        .background(LabColor.lcdInk, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Same footprint as a frame so the page does not jump when the first one arrives. Grey
    /// system fill with a short caption: recognisably not a device screen. Hidden from
    /// VoiceOver because the rows below state the same in real text.
    private var placeholder: some View {
        Color(uiColor: .systemGray5)
            .aspectRatio(2, contentMode: .fit)
            .overlay {
                VStack(spacing: 8) {
                    if status == .connecting || status == .waitingFrame {
                        ProgressView()
                    } else {
                        Image(systemName: placeholderSymbol)
                            .font(.title2)
                    }
                    Text(placeholderCaption)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding(12)
            }
            .accessibilityHidden(true)
    }

    private var placeholderSymbol: String {
        status == .disconnected ? "antenna.radiowaves.left.and.right.slash" : "xmark.circle"
    }

    private var placeholderCaption: String {
        switch status {
        case .connecting: return "正在开启屏幕传输"
        case .waitingFrame: return "等待设备画面"
        case .failed: return "屏幕传输未开启"
        case .disconnected: return "设备已断开"
        case .live: return ""
        }
    }

    /// The state in real text under the screen. Failure and disconnection have their own
    /// sections with an action, so this row stays empty for them instead of repeating.
    @ViewBuilder private var statusRow: some View {
        switch status {
        case .connecting:
            BusyRow("正在开启屏幕传输…")
                .accessibilityIdentifier("remote.status")
        case .waitingFrame:
            BusyRow("传输已开启，等待设备发送画面…")
                .accessibilityIdentifier("remote.status")
        case .live:
            Label {
                Text(verbatim: "画面来自已连接的 \(device.deviceName)")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("remote.status")
        case .failed, .disconnected:
            EmptyView()
        }
    }

    private var disconnectedSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("设备已断开", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("屏幕传输已停止。请返回“设备”页重新连接后再操作。")
                Button("返回设备页") { dismiss() }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .accessibilityIdentifier("remote.back")
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Keys — one tap, one event sequence; nothing repeats

    @ViewBuilder private var keysSection: some View {
        let disabled = !keysEnabled
        Section {
            if model.busy {
                ReasonNote("有任务正在进行，详情见“任务”页。")
            }
            Toggle("下一键发送长按事件", isOn: $longPressNext)
                .disabled(disabled)
                .accessibilityHint("仅对下一次远程按键生效，不会持续按住")
                .accessibilityIdentifier("remote.longPressNext")
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    ForEach(Self.keyOrder, id: \.self) { key in
                        keyButton(key, disabled: disabled)
                    }
                }
                .padding(.vertical, 4)
            } else {
                // Laid out like the device: D-pad with 确认 in the centre, 返回 to the lower right.
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        blank
                        keyButton(.up, disabled: disabled)
                        blank
                    }
                    GridRow {
                        keyButton(.left, disabled: disabled)
                        keyButton(.ok, disabled: disabled)
                        keyButton(.right, disabled: disabled)
                    }
                    GridRow {
                        blank
                        keyButton(.down, disabled: disabled)
                        keyButton(.back, disabled: disabled)
                    }
                }
                .padding(.vertical, 4)
            }
            if let keyFailure {
                ErrorRow(title: "按键未执行", message: keyFailure) {
                    Button("知道了") { self.keyFailure = nil }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .accessibilityIdentifier("remote.keyError.dismiss")
                }
            }
        } header: {
            SectionHeader("远程按键 · 单次发送")
        } footer: {
            Text("与 Flipper 的实体按键对应。默认轻点；可预先选择下一键发送一次长按事件。不会持续按住或自动连按，上一次按键返回前不会发送下一次。")
        }
    }

    private var blank: some View {
        Color.clear
            .gridCellUnsizedAxes([.horizontal, .vertical])
    }

    /// 确认 is the orange key, the rest are `.bordered`. A plain `Button` fires once per tap and
    /// system repeat is switched off explicitly.
    @ViewBuilder private func keyButton(_ key: RemoteKey, disabled: Bool) -> some View {
        let button = Button { press(key) } label: {
            KeyCap(key: key, prominent: key == .ok)
        }
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .buttonRepeatBehavior(.disabled)
        .disabled(disabled)
        .accessibilityLabel(key.labSpokenName)
        .accessibilityHint("向 Flipper 发送一次按键")
        .accessibilityIdentifier("remote.key.\(key.labIdentifier)")
        if key == .ok {
            button
                .buttonStyle(.borderedProminent)
                .tint(LabColor.brandOrange)
        } else {
            button
                .buttonStyle(.bordered)
        }
    }

    // MARK: Session — start on appear, stop on leave, never cancel an in-flight request

    /// Waits for the previous visit's stop (if still in flight) so the two never race on the
    /// single RPC channel, then starts the stream.
    private func beginSession() {
        guard session == nil else { return }
        let previousStop = RemoteSession.closing
        session = Task { @MainActor in
            await previousStop?.value
            await start()
        }
    }

    /// Cancelling a pending RPC closes the whole BLE connection, so the start and any key
    /// sequence are awaited rather than cancelled; stop is sent once the channel is quiet.
    private func endSession() {
        let pendingStart = session
        let pendingKey = keyTask
        let previousStop = RemoteSession.closing
        let device = self.device
        session = nil
        RemoteSession.closing = Task { @MainActor in
            await previousStop?.value
            await pendingStart?.value
            await pendingKey?.value
            try? await device.stopRemoteScreen()
        }
    }

    private func start() async {
        guard device.ready else { return }
        starting = true
        failure = nil
        defer { starting = false }
        do {
            try await device.startRemoteScreen()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func retry() {
        guard !starting else { return }
        session = Task { @MainActor in
            await start()
        }
    }

    /// One key at a time: a tap while a key is in flight is ignored, never queued.
    private func press(_ key: RemoteKey) {
        guard keysEnabled else { return }
        let longPress = longPressNext
        longPressNext = false
        pressing = key
        keyFailure = nil
        keyTask = Task { @MainActor in
            defer { pressing = nil }
            do {
                try await device.sendRemoteKey(key, longPress: longPress)
                UIAccessibility.post(notification: .announcement, argument: "已发送\(key.labSpokenName)")
            } catch {
                keyFailure = error.localizedDescription
            }
        }
    }
}

/// The stop request of the previous visit may still be in flight when the page is opened
/// again; the next start waits for it instead of racing on the single RPC channel.
@MainActor private enum RemoteSession {
    static var closing: Task<Void, Never>?
}

/// Key face: symbol over the Chinese name, at least 56 pt tall so the hit area is well above
/// 44 pt. Enabled text on the orange 确认 key is #1C1917 (UI_APPLE_DESIGN.md §3); the other
/// keys keep the system label colour and the system's own dimming when disabled.
private struct KeyCap: View {
    let key: RemoteKey
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        if prominent && isEnabled {
            face.foregroundStyle(LabColor.lcdInk)
        } else {
            face
        }
    }

    private var face: some View {
        VStack(spacing: 4) {
            Image(systemName: key.labSymbolName)
                .font(.title3.weight(.semibold))
                .accessibilityHidden(true)
            Text(key.labTitle)
                .font(.footnote.weight(.medium))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
    }
}

private extension RemoteKey {
    var labTitle: String {
        switch self {
        case .up: return "上"
        case .down: return "下"
        case .left: return "左"
        case .right: return "右"
        case .ok: return "确认"
        case .back: return "返回"
        }
    }

    var labSpokenName: String {
        switch self {
        case .up: return "上方向键"
        case .down: return "下方向键"
        case .left: return "左方向键"
        case .right: return "右方向键"
        case .ok: return "确认键"
        case .back: return "返回键"
        }
    }

    var labSymbolName: String {
        switch self {
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        case .ok: return "circle.circle"
        case .back: return "arrow.uturn.backward"
        }
    }

    var labIdentifier: String {
        switch self {
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        case .ok: return "ok"
        case .back: return "back"
        }
    }
}
