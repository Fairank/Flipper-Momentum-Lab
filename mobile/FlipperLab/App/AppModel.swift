import Foundation
import Observation
import FlipperCore

struct TaskEntry: Identifiable {
    let id: UUID
    let title: String
    let startedAt: Date
    var detail: String
    var state: State
    enum State: String { case running = "进行中", completed = "已完成", failed = "失败", cancelled = "已取消" }
}

@MainActor @Observable
final class AppModel {
    let device = FlipperDevice()
    private(set) var records: [CaptureRecord] = []
    private(set) var guides: [FeatureGuide] = []
    private(set) var tasks: [TaskEntry] = []
    private(set) var busy = false
    private(set) var libraryReady = false
    var error: String?
    @ObservationIgnored private let store: RecordStore
    @ObservationIgnored private var running: Task<Void, Never>?

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-fixtures") {
            store = RecordStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("UITest-" + UUID().uuidString))
            return
        }
        #endif
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        store = RecordStore(directory: documents.appendingPathComponent("Library", isDirectory: true))
    }

    func load() async {
        guard !libraryReady, !busy else { return }
        busy = true; defer { busy = false }
        do {
            guides = try FeatureGuide.load()
            records = try await store.load()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-fixtures") {
                records = PreviewRecords.samples
            }
            #endif
            libraryReady = true
        } catch { self.error = "资料库加载失败，原文件已保留：" + error.localizedDescription }
    }

    private func perform(_ title: String, action: @escaping @MainActor () async throws -> String) {
        guard !busy else { error = RPCError.busy.localizedDescription; return }
        busy = true; error = nil
        let id = UUID()
        tasks.insert(TaskEntry(id: id, title: title, startedAt: Date(), detail: "正在处理", state: .running), at: 0)
        if tasks.count > 100 { tasks.removeLast(tasks.count - 100) }
        running = Task {
            defer { busy = false; running = nil }
            do {
                let detail = try await action()
                try Task.checkCancellation()
                updateTask(id, state: .completed, detail: detail)
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError || (error as? RPCError) == .cancelled
                updateTask(id, state: cancelled ? .cancelled : .failed, detail: error.localizedDescription)
                if !cancelled { self.error = error.localizedDescription }
            }
        }
    }
    private func updateTask(_ id: UUID, state: TaskEntry.State, detail: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].state = state; tasks[index].detail = detail
    }
    func cancelTask() { running?.cancel(); device.cancelOperation() }

    func directory(_ path: String) async throws -> [DeviceFile] {
        guard !busy else { throw RPCError.busy }
        busy = true; defer { busy = false }
        return try await device.listFiles(path)
    }
    func importDeviceFile(_ file: DeviceFile) {
        perform("从 Flipper 导入 \(file.name)") {
            guard !file.isDirectory, file.size <= 2 * 1024 * 1024 else { throw RPCError.tooLarge }
            let data = try await self.device.readFile(file.path)
            try await self.importData(data, name: file.name, path: file.path)
            return "原始内容已导入，可在资料库分析与编辑中文名称。"
        }
    }
    func importFile(_ url: URL) {
        perform("导入 \(url.lastPathComponent)") {
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize, size <= 2 * 1024 * 1024 else { throw RPCError.tooLarge }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            try await self.importData(data, name: url.lastPathComponent, path: nil)
            return "记录已保存。原文件保持不变。"
        }
    }
    private func importData(_ data: Data, name: String, path: String?) async throws {
        guard libraryReady else { throw RPCError.message("资料库尚未成功加载，暂时不能写入。") }
        guard data.count <= 2 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { throw RPCError.malformed }
        let ext = (name as NSString).pathExtension
        let kind = try await Task.detached(priority: .userInitiated) {
            let kind = try RecordAnalyzer.detectKind(text: text, fileExtension: ext)
            _ = try RecordAnalyzer.analyze(text, kind: kind)
            return kind
        }.value
        try Task.checkCancellation()
        let record = CaptureRecord(name: (name as NSString).deletingPathExtension, kind: kind, sourcePath: path, rawText: text)
        let updated = [record] + records
        try await store.save(updated)
        records = updated
    }
    func saveRecord(_ record: CaptureRecord) {
        perform("保存中文名称与备注") {
            guard self.libraryReady, let index = self.records.firstIndex(where: { $0.id == record.id }) else { throw RPCError.message("未找到该记录。") }
            var updated = self.records; updated[index] = record
            try await self.store.save(updated); self.records = updated
            return "名称、标签和备注已保存，原始采集数据保持不变。"
        }
    }
    func deleteRecord(_ id: UUID) {
        perform("删除手机记录") {
            guard self.libraryReady else { throw RPCError.message("资料库尚未准备好。") }
            let updated = self.records.filter { $0.id != id }
            try await self.store.save(updated); self.records = updated
            return "手机资料库中的记录已删除，设备上的文件不受影响。"
        }
    }
    func upload(_ record: CaptureRecord) {
        perform("上传 \(record.name)") {
            guard self.libraryReady, let index = self.records.firstIndex(where: { $0.id == record.id }) else { throw RPCError.message("资料库记录不存在。") }
            let path = try await self.device.upload(record)
            var updated = self.records; updated[index].sourcePath = path
            try await self.store.save(updated); self.records = updated
            return "已上传并读回核对：\(path)"
        }
    }
    func sendInfrared(_ record: CaptureRecord, index: Int) {
        perform("执行红外按钮") {
            try await self.device.sendInfrared(record, buttonIndex: index)
            return "设备已确认执行；请检查实际家电响应。"
        }
    }
}
