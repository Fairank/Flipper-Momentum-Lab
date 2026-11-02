import Foundation

/// Network applications may exchange their own SD data, never internal storage,
/// firmware resources, settings or arbitrary files in the phone's sandbox.
public enum CompanionStorage {
    public static let maximumBytes = 2 * 1024 * 1024

    public static func validate(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard path.hasPrefix("/ext/apps_data/"), path.utf8.count <= 240,
              parts.count >= 5, parts[0].isEmpty,
              parts.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !path.contains("\\"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw RPCError.message("网络文件传输仅支持 SD 卡 apps_data 下的应用目录。")
        }
    }
}
