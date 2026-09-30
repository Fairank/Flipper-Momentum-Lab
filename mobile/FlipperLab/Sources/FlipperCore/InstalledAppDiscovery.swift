import Foundation

/// Sequential discovery matches the BLE RPC lane, which allows one request at
/// a time. Never return a partial list labelled as complete when a bound fails.
public enum InstalledAppDiscovery {
    public static let root = "/ext/apps"
    public static let maximumDirectories = 128
    public static let maximumEntries = 12_000
    public static let maximumApps = 600
    public static let maximumFolderDepth = 4

    public static func collect(listDirectory: (String) async throws -> [DeviceFile]) async throws -> [FlipperFunction] {
        var directories = [root]
        var visited: Set<String> = [root]
        var apps: [String: FlipperFunction] = [:]
        var entries = 0
        var position = 0
        while position < directories.count {
            try Task.checkCancellation()
            let directory = directories[position]
            position += 1
            let files = try await listDirectory(directory)
            try Task.checkCancellation()
            for file in files {
                entries += 1
                guard entries <= maximumEntries else { throw RPCError.tooLarge }
                // Do not trust an arbitrary remote response to redirect traversal.
                guard file.path == directory + "/" + file.name,
                      !file.name.isEmpty, file.name != ".", file.name != "..",
                      !file.name.contains("/"), !file.name.contains("\\"),
                      !file.name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
                      file.path.utf8.count <= 240 else { throw RPCError.malformed }
                if file.isDirectory {
                    let depth = file.path.split(separator: "/").count - 2
                    guard depth <= maximumFolderDepth else {
                        throw RPCError.message("设备应用目录超过 4 层，尚未完成完整读取。")
                    }
                    if visited.insert(file.path).inserted {
                        guard directories.count < maximumDirectories else { throw RPCError.tooLarge }
                        directories.append(file.path)
                    }
                } else if let app = FlipperFunction.installed(path: file.path) {
                    apps[app.id] = app
                    guard apps.count <= maximumApps else { throw RPCError.tooLarge }
                }
            }
        }
        return apps.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
