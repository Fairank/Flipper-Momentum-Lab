import SwiftUI
import FlipperCore

/// 功能: the phone's own Chinese index of Flipper applications, built with the same tokens as
/// the other tabs (UI_APPLE_DESIGN.md §3). A tap sends one App.Start request over Bluetooth
/// and everything after that happens on the device; nothing here mirrors or imitates the
/// Flipper screen. Built-in entries come from `FlipperFunction.builtIns`; installed `.fap`
/// files are read from `/ext/apps` on the first visit while connected and afterwards only when
/// the user asks. Every row is disabled with a stated reason while the device is not ready or
/// a task is running, tapping a row explains why it cannot open yet; no request is sent.
@MainActor struct FunctionsView: View {
    let model: AppModel
    @State private var search = ""
    @State private var installed: [FlipperFunction] = []
    @State private var installedState: InstalledState = .idle
    @State private var loadedAt: Date?
    @State private var lastLaunchID: UUID?
    @State private var blockedActionMessage: String?

    private enum InstalledState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private struct FunctionGroup: Identifiable {
        let category: String
        let functions: [FlipperFunction]
        var id: String { category }
    }

    private var device: FlipperDevice { model.device }

    /// Why no device request may start right now; nil when a tap can go ahead.
    private var blockReason: String? {
        if !device.ready { return "需要先在“设备”页连接 Flipper。" }
        if installedState == .loading { return "正在读取设备应用，请稍候。" }
        if model.busy { return "有任务正在进行，详情见“任务”页。" }
        return nil
    }

    var body: some View {
        let builtIns = Self.groups(FlipperFunction.builtIns.filter { matches($0) }, sortCategories: false)
        let apps = Self.groups(installed.filter { matches($0) }, sortCategories: true)
        List {
            statusSection
            if !search.isEmpty, builtIns.isEmpty, apps.isEmpty {
                Section {
                    ContentUnavailableView.search(text: search)
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(builtIns) { group in
                Section {
                    ForEach(group.functions) { function in
                        functionRow(function)
                    }
                } header: {
                    SectionHeader("常用功能 · " + group.category, count: "\(group.functions.count) 项")
                }
            }
            installedSection
            ForEach(apps) { group in
                Section {
                    ForEach(group.functions) { function in
                        functionRow(function)
                    }
                } header: {
                    SectionHeader("设备应用 · " + group.category, count: "\(group.functions.count) 项")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("功能")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "搜索功能或设备应用")
        .onAppear {
            // First visit while connected: read the list once. Later visits keep what was read;
            // a failure waits for the user to tap 刷新设备应用.
            if installedState == .idle { loadInstalled() }
        }
        .onChange(of: device.ready) { _, isReady in
            // A new connection may be a different Flipper: forget the old list instead of
            // offering entries the device would refuse to launch.
            if !isReady {
                installed = []
                loadedAt = nil
                installedState = .idle
            }
        }
        .alert("暂时无法打开", isPresented: Binding(
            get: { blockedActionMessage != nil },
            set: { if !$0 { blockedActionMessage = nil } }
        )) {
            Button("知道了") { blockedActionMessage = nil }
        } message: {
            Text(blockedActionMessage ?? "")
        }
    }

    // MARK: Connection status

    /// Real connection state in words, then the outcome of the last launch request. The pixel
    /// arcs are decoration only; the title beside them carries the meaning.
    private var statusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    SignalMark(color: device.ready ? LabColor.brandOrange : Color.secondary)
                    Text(device.state.rawValue)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("functions.status")
                    if isConnecting {
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                }
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if device.ready, let reason = blockReason {
                    ReasonNote(reason)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .contain)
            if let task = lastLaunch {
                launchResultRow(task)
            }
        }
    }

    private var isConnecting: Bool {
        switch device.state {
        case .scanning, .connecting, .discovering, .negotiating: return true
        case .idle, .ready, .unavailable: return false
        }
    }

    /// Offline states explain what to do; the ready state explains what a tap does.
    private var explanation: String {
        switch device.state {
        case .idle: return "先在“设备”页搜索并连接 Flipper，再回到这里点选要在设备上打开的功能。"
        case .scanning: return "正在搜索附近设备，请在“设备”页选择要连接的 Flipper。"
        case .connecting: return "正在配对与连接，请留意 iPhone 弹出的配对码窗口。"
        case .discovering, .negotiating: return "正在准备通信并检查设备，完成后即可点选功能。"
        case .ready: return "已连接 \(device.deviceName)。点选条目会通过蓝牙让 Flipper 打开对应应用，之后的操作在设备屏幕上继续。"
        case .unavailable: return device.lastError ?? "请开启 iPhone 蓝牙。"
        }
    }

    /// The task entry created by the last tap on this page, as long as 任务 still lists it.
    private var lastLaunch: TaskEntry? {
        guard let lastLaunchID else { return nil }
        return model.tasks.first { $0.id == lastLaunchID }
    }

    /// State symbol in its semantic colour, the model's own title, then state and detail.
    private func launchResultRow(_ task: TaskEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: Self.symbolName(for: task.state))
                .font(.headline)
                .foregroundStyle(Self.symbolColor(for: task.state))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: task.title)
                    .font(.subheadline)
                Text(verbatim: task.state.rawValue + " · " + task.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("functions.lastLaunch")
    }

    private static func symbolName(for state: TaskEntry.State) -> String {
        switch state {
        case .running: return "hourglass"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "minus.circle"
        }
    }

    private static func symbolColor(for state: TaskEntry.State) -> Color {
        switch state {
        case .running: return LabColor.brandOrange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }

    // MARK: Rows

    /// The whole row is the button; a ready device launches immediately. Offline taps explain
    /// the requirement while keeping the catalogue legible and discoverable.
    private func functionRow(_ function: FlipperFunction) -> some View {
        Button { open(function) } label: {
            FunctionRow(function: function)
        }
        .accessibilityLabel(rowDescription(function))
        .accessibilityHint(blockReason ?? (function.isInstalledApp ? "在 Flipper 上打开此应用" : "在 Flipper 上打开此功能"))
        .accessibilityIdentifier((function.isInstalledApp ? "functions.app." : "functions.builtin.") + function.id)
    }

    private func rowDescription(_ function: FlipperFunction) -> String {
        if function.isInstalledApp {
            return "\(function.title)，设备应用，\(function.category)"
        }
        return "\(function.title)，\(function.summary)使用条件：\(function.requirement)"
    }

    /// `perform` inserts the task entry synchronously, so the newest entry is ours; when the
    /// model is busy it inserts nothing and raises the shared alert instead.
    private func open(_ function: FlipperFunction) {
        if let reason = blockReason {
            blockedActionMessage = reason
            return
        }
        let previous = model.tasks.first?.id
        model.openOnFlipper(function)
        if let current = model.tasks.first?.id, current != previous {
            lastLaunchID = current
        }
    }

    private func matches(_ function: FlipperFunction) -> Bool {
        search.isEmpty || [function.title, function.summary, function.category, function.launchName]
            .joined(separator: " ")
            .localizedCaseInsensitiveContains(search)
    }

    /// Built-ins keep the catalogue's category order; device folders sort by name.
    private static func groups(_ functions: [FlipperFunction], sortCategories: Bool) -> [FunctionGroup] {
        var order: [String] = []
        var buckets: [String: [FlipperFunction]] = [:]
        for function in functions {
            if buckets[function.category] == nil { order.append(function.category) }
            buckets[function.category, default: []].append(function)
        }
        if sortCategories {
            order.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        return order.map { FunctionGroup(category: $0, functions: buckets[$0] ?? []) }
    }

    // MARK: Installed apps

    /// The refresh action and the section's own state; category sections follow it.
    private var installedSection: some View {
        Section {
            Button { loadInstalled() } label: {
                Label("刷新设备应用", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .disabled(blockReason != nil)
            .accessibilityIdentifier("functions.refresh")
            installedStatus
        } header: {
            SectionHeader("设备已安装应用", count: installedState == .loaded ? "共 \(installed.count) 项" : nil)
        } footer: {
            Text("列表来自设备 SD 卡；未提供中文名称的应用显示原始文件名。")
        }
    }

    @ViewBuilder private var installedStatus: some View {
        if !device.ready {
            Text("连接 Flipper 后可以读取设备上的应用列表。")
                .foregroundStyle(.secondary)
        } else {
            switch installedState {
            case .idle:
                Text("尚未读取，点“刷新设备应用”从设备获取列表。")
                    .foregroundStyle(.secondary)
            case .loading:
                BusyRow("正在读取设备应用…")
            case .failed(let message):
                ErrorRow(title: "无法读取设备应用", message: message)
            case .loaded:
                if installed.isEmpty {
                    Text("设备 SD 卡上尚未找到其他已安装应用。")
                        .foregroundStyle(.secondary)
                } else if let loadedAt {
                    Text("已读取 \(installed.count) 个应用，\(loadedAt, format: .dateTime.hour().minute())。")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// One request at a time, only while ready and not busy. The task is deliberately not tied
    /// to the view's lifetime: cancelling a device request closes the Bluetooth connection, so a
    /// tab switch in the middle of reading must not do that.
    private func loadInstalled() {
        guard blockReason == nil else { return }
        installedState = .loading
        Task {
            do {
                let apps = try await model.installedDeviceApps()
                installed = apps
                loadedAt = Date()
                installedState = .loaded
            } catch {
                installed = []
                loadedAt = nil
                // A dropped connection already resets this section; only a failure while
                // still connected is worth showing here.
                installedState = device.ready ? .failed(error.localizedDescription) : .idle
            }
        }
    }
}

/// Function row: symbol tile, Chinese title with the name the Flipper menu shows, then the
/// summary and the key condition. Installed apps show their device path instead, because the
/// title is only the file name and nothing about the app is known. The row remains readable
/// offline; the reason is stated at the top, on tap, and in the accessibility hint.
private struct FunctionRow: View {
    let function: FlipperFunction

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SymbolTile(systemName: function.symbol)
            VStack(alignment: .leading, spacing: 4) {
                if function.isInstalledApp {
                    Text(verbatim: function.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(verbatim: function.launchName)
                        .font(LabFont.mono)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                } else {
                    AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: function.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(verbatim: function.launchName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text(verbatim: function.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(verbatim: function.requirement)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.up.right.square")
                .font(.body)
                .foregroundStyle(LabColor.accent)
                .accessibilityHidden(true)
        }
        .multilineTextAlignment(.leading)
        .padding(.vertical, 4)
        .frame(minHeight: 44)
    }
}

/// The one pixel element of this page: the three signal arcs from the LCD sprites, drawn at a
/// whole-point cell size that scales with the headline. Hidden from VoiceOver; the status title
/// beside it says the same thing in words.
private struct SignalMark: View {
    let color: Color
    @ScaledMetric(relativeTo: .headline) private var unit: CGFloat = 3

    var body: some View {
        let cell = max(2, unit.rounded())
        ZStack(alignment: .topLeading) {
            ForEach(0..<PixelSprites.arcs.count, id: \.self) { index in
                PixelBitmapView(bitmap: PixelSprites.arcs[index], unit: cell, color: color)
            }
        }
        .accessibilityHidden(true)
    }
}
