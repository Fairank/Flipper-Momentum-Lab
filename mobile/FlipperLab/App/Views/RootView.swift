import SwiftUI
import FlipperCore

@MainActor struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            NavigationStack { DeviceView(model: model) }
                .tabItem { Label("设备", systemImage: "antenna.radiowaves.left.and.right") }
            NavigationStack { ToolsView(model: model) }
                .tabItem { Label("工具", systemImage: "waveform.path") }
            NavigationStack { LibraryView(model: model) }
                .tabItem { Label("资料库", systemImage: "square.stack.3d.up") }
            NavigationStack { TasksView(model: model) }
                .tabItem { Label("任务", systemImage: "checklist") }
            NavigationStack { GuidesView(model: model) }
                .tabItem { Label("指南", systemImage: "book.closed") }
        }
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .alert("操作提示", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

@MainActor struct DeviceView: View {
    let model: AppModel
    var body: some View {
        List {
            Section {
                Label(model.device.state.rawValue, systemImage: model.device.ready ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                    .font(.headline).foregroundStyle(model.device.ready ? .green : .secondary)
                Text(model.device.deviceName)
                if model.device.ready {
                    LabeledContent("协议版本", value: model.device.protocolVersion)
                    NavigationLink("浏览设备文件") { DeviceFilesView(model: model, path: "/ext") }
                }
                if let error = model.device.lastError { Text(error).foregroundStyle(.red) }
                if model.device.state == .idle || model.device.state == .scanning || model.device.state == .unavailable {
                    Button("搜索附近的 Flipper", systemImage: "magnifyingglass") { model.device.scan() }
                        .disabled(model.busy || model.device.state == .scanning)
                }
                if model.device.state != .idle && model.device.state != .unavailable {
                    Button("断开 / 停止搜索", role: .destructive) { model.device.disconnect() }
                }
            } header: { Text("我的 Flipper") }
            if !model.device.ready {
                Section("附近设备") {
                    if model.device.nearby.isEmpty {
                        Text(model.device.state == .scanning ? "正在搜索，请将设备放在手机旁。" : "搜索后在这里选择设备。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.device.nearby) { device in
                        Button { model.device.connect(device) } label: {
                            HStack {
                                Label(device.name, systemImage: "dot.radiowaves.left.and.right")
                                Spacer()
                                Text("\(device.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(model.busy || (model.device.state != .scanning && model.device.state != .idle))
                    }
                }
                Section("首次连接") {
                    Text("1. 在 Flipper 设置中开启蓝牙。\n2. 允许本应用使用 iPhone 蓝牙。\n3. 选择设备，在 iPhone 输入 Flipper 屏幕上的配对码。\n4. 等待“设备已就绪”后操作。")
                    Text("传输和分析时请保持应用在前台。模拟器无法验证真实蓝牙连接。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !model.device.info.isEmpty {
                Section("设备报告的信息") {
                    ForEach(model.device.info.keys.sorted(), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key).font(.caption).foregroundStyle(.secondary)
                            Text(model.device.info[key] ?? "").textSelection(.enabled)
                        }
                    }
                }
            }
        }.navigationTitle("设备")
    }
}

@MainActor struct DeviceFilesView: View {
    let model: AppModel
    let path: String
    @State private var files: [DeviceFile] = []
    @State private var loading = false
    @State private var failure: String?
    @State private var revision = 0
    var body: some View {
        List {
            Section {
                Text(path).font(.caption).textSelection(.enabled)
                Text("选择文件导入手机；支持红外、Sub-GHz、NFC、RFID、iButton 和文本日志，单个文件最多 2 MiB。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if loading { ProgressView("读取目录…") }
            if let failure { Text(failure).foregroundStyle(.red) }
            if !loading && failure == nil && files.isEmpty { Text("此目录为空。") }
            ForEach(files) { file in
                if file.isDirectory {
                    NavigationLink { DeviceFilesView(model: model, path: file.path) } label: {
                        Label(file.name, systemImage: "folder")
                    }.disabled(model.busy)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(file.name).lineLimit(3)
                        HStack {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: file.size), countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("导入") { model.importDeviceFile(file) }.buttonStyle(.bordered)
                                .disabled(model.busy || !model.device.ready || file.size > 2 * 1024 * 1024)
                        }
                    }
                }
            }
        }
        .navigationTitle(path == "/ext" ? "设备文件" : (path as NSString).lastPathComponent)
        .toolbar { Button("刷新", systemImage: "arrow.clockwise") { revision += 1 }.disabled(model.busy || !model.device.ready) }
        .task(id: "\(path):\(revision)") {
            loading = true; failure = nil
            defer { loading = false }
            do {
                let result = try await model.directory(path)
                try Task.checkCancellation(); files = result
            } catch {
                if !Task.isCancelled { failure = error.localizedDescription }
            }
        }
    }
}

@MainActor struct TasksView: View {
    let model: AppModel
    var body: some View {
        List {
            if model.busy {
                Section {
                    ProgressView("正在处理…")
                    Button("取消当前任务", role: .destructive) { model.cancelTask() }
                    Text("取消设备操作会断开连接；已写入设备的部分文件可能保留。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if model.tasks.isEmpty { ContentUnavailableView("还没有任务", systemImage: "checklist", description: Text("导入、保存或执行后的结果会显示在这里。")) }
            ForEach(model.tasks) { task in
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(task.title).font(.headline); Spacer(); Text(task.state.rawValue).font(.caption) }
                    Text(task.detail).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(task.startedAt, format: .dateTime.hour().minute().second()).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section { Text("显示本次打开应用期间最近 100 项任务。设备确认执行后，仍需观察实际家电或硬件的响应。")
                    .font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("任务")
    }
}

@MainActor struct GuidesView: View {
    let model: AppModel
    @State private var search = ""
    var body: some View {
        List {
            if model.guides.isEmpty {
                ContentUnavailableView("指南尚未加载", systemImage: "book.closed")
                Button("重新加载") { Task { await model.load() } }.disabled(model.busy)
            }
            ForEach(model.guides.filter { search.isEmpty || ($0.title + $0.summary).localizedCaseInsensitiveContains(search) }) { guide in
                NavigationLink { GuideDetail(guide: guide) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(guide.title).font(.headline)
                        Text(guide.summary).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("功能指南").searchable(text: $search, prompt: "搜索功能")
    }
}

@MainActor struct GuideDetail: View {
    let guide: FeatureGuide
    var body: some View {
        List {
            Section("用途") { Text(guide.summary) }
            Section("准备事项") { ForEach(Array(guide.requires.enumerated()), id: \.offset) { _, text in Text(text) } }
            Section("操作步骤") { ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, text in Text("\(index + 1). \(text)") } }
            Section("手机负责") { Text(guide.phoneRole) }
            Section("Flipper 负责") { Text(guide.flipperRole); Text(guide.deviceHelp) }
            Section("怎样理解结果") { Text(guide.result) }
            Section("适用范围") { Text(guide.limits) }
        }.navigationTitle(guide.title).navigationBarTitleDisplayMode(.inline)
    }
}
