import SwiftUI
import FlipperCore

/// A phone-side Chinese catalogue. Filters never create launch paths or infer installation.
@MainActor struct FunctionsView: View {
    let model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var search = ""
    @State private var source: FunctionCatalogSource = .all
    @State private var category: FunctionCatalogCategory?
    @State private var installed: [FlipperFunction] = []
    @State private var installedState: InstalledState = .idle
    @State private var loadedAt: Date?
    @State private var catalogueSession: UUID?
    @State private var loadID: UUID?
    @State private var installedTask: Task<Void, Never>?
    @State private var selectedFunction: FlipperFunction?
    @State private var lastLaunchID: UUID?
    @State private var blockedActionMessage: String?

    private enum InstalledState: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    private var device: FlipperDevice { model.device }

    private var isCataloguePreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui-testing-app-catalog")
        #else
        false
        #endif
    }

    private var displayedInstalled: [FlipperFunction] {
        #if DEBUG
        if isCataloguePreview {
            // Display-only fixtures never enter the device's launch whitelist.
            return [
                "/ext/apps/Tools/clock.fap",
                "/ext/apps/Tools/flipnote.fap",
                "/ext/apps/Tools/calculator.fap",
                "/ext/apps/Games/bounce.fap",
                "/ext/apps/Games/sudoku.fap",
                "/ext/apps/Media/music_player.fap",
                "/ext/apps/Tools/gps_rpc.fap",
                "/ext/apps/GPIO/Sensors/weather.fap",
            ].compactMap(FlipperFunction.installed(path:))
        }
        #endif
        return installed
    }

    private var query: FunctionCatalogQuery {
        FunctionCatalogQuery(source: source, category: category, search: search)
    }

    private var allFunctions: [FlipperFunction] {
        FlipperFunction.builtIns + displayedInstalled
    }

    private var visibleFunctions: [FlipperFunction] { query.filter(allFunctions) }

    private var visibleCategories: [FunctionCatalogCategory] {
        FunctionCatalogCategory.allCases.filter { $0 != .other || count(in: $0) > 0 }
    }

    private func count(in category: FunctionCatalogCategory) -> Int {
        allFunctions.filter {
            query.includes($0, ignoringCategory: true)
                && FunctionCatalogCategory.category(of: $0) == category
        }.count
    }

    private var categoryColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8),
              count: dynamicTypeSize.isAccessibilitySize ? 2 : 3)
    }

    private var showsNFCWorkbench: Bool {
        source != .installed && (category == nil || category == .wireless)
            && query.matches(text: "NFC 离线工作台 MIFARE Classic 认证样本 字典分析 手机工作台")
    }

    private var showsSerialBridge: Bool {
        source != .installed && (category == nil || category == .expansion)
            && query.matches(text: "扩展板实时数据 串口 ESP32 CC1101 NRF24 AIO 模块 手机工作台")
    }

    /// Blocked rows remain discoverable. open() never sends a request while blocked.
    private var blockReason: String? {
        if isCataloguePreview { return "应用目录预览不会向 Flipper 发送命令。" }
        if !device.ready { return "需要先在“设备”页连接 Flipper。" }
        if installedState == .loading { return "正在读取设备应用，请稍候。" }
        if model.busy { return "有任务正在进行，详情见“任务”页。" }
        return nil
    }

    var body: some View {
        List {
            statusSection
            filtersSection
            if showsNFCWorkbench || showsSerialBridge {
                workbenchSection
            }
            if !visibleFunctions.isEmpty {
                Section {
                    ForEach(visibleFunctions) { function in
                        functionRow(function)
                    }
                } header: {
                    SectionHeader(category?.title ?? "设备功能",
                                  count: "\(visibleFunctions.count) 项")
                }
            } else if !showsNFCWorkbench && !showsSerialBridge,
                      installedState != .loading {
                noResultsSection
            }
            if source != .common {
                installedSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("功能")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "搜索功能或设备应用")
        .refreshable { await readInstalled() }
        .onAppear {
            synchronizeSession()
            loadIfIdle()
        }
        .onChange(of: device.ready) { _, _ in
            synchronizeSession()
            loadIfIdle()
        }
        .onChange(of: device.companionSession) { _, _ in
            synchronizeSession()
            loadIfIdle()
        }
        .onChange(of: model.busy) { _, isBusy in
            if !isBusy { loadIfIdle() }
        }
        .sheet(item: $selectedFunction) { function in
            FunctionDetailsSheet(function: function, badge: badge(for: function),
                                 blockReason: blockReason) {
                open(function)
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

    // MARK: Filters and workbenches

    private var filtersSection: some View {
        Section {
            Picker("应用来源", selection: $source) {
                ForEach(FunctionCatalogSource.allCases, id: \.self) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("functions.source")
            LazyVGrid(columns: categoryColumns, spacing: 8) {
                ForEach(visibleCategories) { item in
                    CatalogCategoryTile(title: item.title, symbol: item.symbol,
                                        count: count(in: item), isSelected: category == item) {
                        category = category == item ? nil : item
                    }
                    .accessibilityIdentifier("functions.category." + item.rawValue)
                }
            }
            .padding(.vertical, 4)
            if let category {
                HStack {
                    Text("已选：\(category.title)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("清除分类", systemImage: "xmark.circle") {
                        self.category = nil
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("functions.clearCategory")
                }
            }
        }
    }

    private var workbenchSection: some View {
        Section {
            if showsNFCWorkbench {
                NavigationLink { NFCWorkbenchView() } label: {
                    workbenchLabel("NFC 离线工作台", symbol: "wave.3.right",
                                   summary: "在手机上分析认证样本并整理字典。")
                }
                .accessibilityIdentifier("functions.nfcWorkbench")
            }
            if showsSerialBridge {
                NavigationLink { SerialBridgeView(model: model) } label: {
                    workbenchLabel("扩展板实时数据", symbol: "cable.connector",
                                   summary: "查看已接入扩展板的串口数据。")
                }
                .accessibilityIdentifier("functions.serialBridge")
            }
        } header: {
            SectionHeader("手机工作台")
        }
    }

    private func workbenchLabel(_ title: String, symbol: String, summary: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SymbolTile(systemName: symbol)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(summary).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private var noResultsSection: some View {
        Section {
            ContentUnavailableView {
                Label(search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      ? "暂无可显示应用" : "没有匹配的功能",
                      systemImage: "magnifyingglass")
            } description: {
                Text(source == .installed && search.isEmpty
                     ? "连接 Flipper 并读取应用目录，或切换到常用功能。"
                     : "试试其他关键词，或清除当前分类。")
            }
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("functions.noResults")
        }
    }

    // MARK: Real connection and launch status

    private var statusSection: some View {
        Section {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        compactLCD
                        connectionText
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        compactLCD
                        connectionText
                    }
                }
            }
            .padding(.vertical, 4)
            if device.ready, let reason = blockReason {
                ReasonNote(reason)
            }
            if let task = lastLaunch {
                launchResultRow(task)
            }
        }
    }

    private var compactLCD: some View {
        LCDScreen(dolphin: PixelSprites.dolphinOpen, decoration: .empty,
                  lines: [isCataloguePreview ? "PREVIEW" : device.ready ? "READY" : "NO LINK"],
                  px: 1.25)
    }

    private var connectionText: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(isCataloguePreview ? "应用目录预览" : device.state.rawValue)
                    .font(.headline)
                    .accessibilityIdentifier("functions.status")
                if isConnecting && !isCataloguePreview {
                    ProgressView().accessibilityHidden(true)
                }
            }
            Text(isCataloguePreview ? "预览不向设备发送命令"
                 : device.ready ? device.deviceName
                 : isConnecting ? "连接准备中，请稍候"
                 : "连接后可在设备上打开功能")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isConnecting: Bool {
        switch device.state {
        case .scanning, .connecting, .discovering, .negotiating, .reconnecting: return true
        case .idle, .ready, .unavailable: return false
        }
    }

    private var lastLaunch: TaskEntry? {
        guard let lastLaunchID else { return nil }
        return model.tasks.first { $0.id == lastLaunchID }
    }

    private func launchResultRow(_ task: TaskEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: Self.symbolName(for: task.state))
                .font(.headline)
                .foregroundStyle(Self.symbolColor(for: task.state))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: task.title).font(.subheadline)
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

    // MARK: Independent launch and details controls

    private func badge(for function: FlipperFunction) -> String {
        isCataloguePreview ? "预览" : function.isInstalledApp ? "已安装" : "常用"
    }

    private func functionRow(_ function: FlipperFunction) -> some View {
        HStack(spacing: 8) {
            Button { open(function) } label: {
                CatalogAppRow(function: function, badge: badge(for: function))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rowDescription(function))
            .accessibilityHint(blockReason ?? "在 Flipper 上打开此应用")
            .accessibilityIdentifier((function.isInstalledApp
                                      ? "functions.app." : "functions.builtin.") + function.id)

            Button { selectedFunction = function } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(LabColor.accent)
            .accessibilityLabel(function.title + "的功能介绍")
            .accessibilityIdentifier("functions.details." + function.id)
        }
        .accessibilityElement(children: .contain)
    }

    private func rowDescription(_ function: FlipperFunction) -> String {
        "\(function.title)，\(function.isInstalledApp ? "设备应用" : "常用功能")，\(function.summary)"
    }

    /// perform() inserts this task synchronously. A rejected request never becomes a launch.
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

    // MARK: Session-bound directory reads

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
            SectionHeader("应用目录", count: isCataloguePreview
                          ? "\(displayedInstalled.count) 项预览"
                          : installedState == .loaded ? "\(installed.count) 项" : nil)
        }
    }

    @ViewBuilder private var installedStatus: some View {
        if isCataloguePreview {
            Text("仅展示预览目录，未读取设备。").foregroundStyle(.secondary)
        } else if !device.ready {
            Text("连接后读取设备 SD 卡上的应用。").foregroundStyle(.secondary)
        } else {
            switch installedState {
            case .idle:
                Text("尚未读取应用目录。").foregroundStyle(.secondary)
            case .loading:
                BusyRow("正在读取设备应用…")
            case .failed(let message):
                ErrorRow(title: "无法读取设备应用", message: message)
            case .loaded:
                if installed.isEmpty {
                    Text("SD 卡上尚未找到已安装应用。").foregroundStyle(.secondary)
                } else if let loadedAt {
                    Text("目录更新于 \(loadedAt, format: .dateTime.hour().minute())")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Invalidate display ownership, not RPC: replaced device sessions terminate their
    /// own exchanges. A tab switch never cancels a directory read.
    private func synchronizeSession() {
        let session = device.companionSession
        if catalogueSession != session {
            resetInstalled()
            catalogueSession = session
        }
        if !device.ready { resetInstalled() }
    }

    private func resetInstalled() {
        loadID = nil
        installedTask = nil
        installed = []
        loadedAt = nil
        installedState = .idle
    }

    private func loadIfIdle() {
        guard installedState == .idle else { return }
        loadInstalled()
    }

    private func loadInstalled() {
        Task { await readInstalled() }
    }

    /// The unstructured read survives refreshable/view cancellation. Refresh still awaits
    /// completion; only the current ready session and load ID may publish a result.
    private func readInstalled() async {
        guard !isCataloguePreview else { return }
        if let installedTask {
            await installedTask.value
            return
        }
        guard device.ready, !model.busy, installedState != .loading else { return }
        let session = device.companionSession
        if catalogueSession != session {
            resetInstalled()
            catalogueSession = session
        }
        let id = UUID()
        loadID = id
        installedState = .loading
        let task = Task { @MainActor in
            defer {
                if loadID == id {
                    installedTask = nil
                    loadID = nil
                }
            }
            do {
                let apps = try await model.installedDeviceApps()
                try Task.checkCancellation()
                guard loadID == id, catalogueSession == session,
                      device.companionSession == session, device.ready else { return }
                installed = apps
                loadedAt = Date()
                installedState = .loaded
            } catch {
                guard loadID == id, catalogueSession == session,
                      device.companionSession == session, device.ready else { return }
                installed = []
                loadedAt = nil
                let cancelled = Task.isCancelled || error is CancellationError
                    || (error as? RPCError) == .cancelled
                installedState = cancelled ? .idle : .failed(PhoneErrorDescription.describe(error))
            }
        }
        installedTask = task
        await task.value
    }
}

/// Secondary information stays in a sheet; raw paths never appear in the main catalogue.
@MainActor private struct FunctionDetailsSheet: View {
    let function: FlipperFunction
    let badge: String
    let blockReason: String?
    let onOpen: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CatalogAppRow(function: function, badge: badge)
                }
                Section("功能介绍") {
                    Text(function.summary)
                }
                Section {
                    Text(function.requirement)
                    if let blockReason { ReasonNote(blockReason) }
                } header: {
                    SectionHeader("使用条件")
                }
                Section {
                    Button {
                        onOpen()
                        dismiss()
                    } label: {
                        Label("在 Flipper 上打开", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(blockReason != nil)
                    .accessibilityIdentifier("functions.details.open")
                }
                Section {
                    DisclosureGroup(function.isInstalledApp ? "文件位置" : "设备启动名称") {
                        Text(verbatim: function.launchName)
                            .font(LabFont.mono)
                            .textSelection(.enabled)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(function.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
