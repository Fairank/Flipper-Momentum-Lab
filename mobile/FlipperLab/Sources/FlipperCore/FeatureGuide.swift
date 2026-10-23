import Foundation

public struct FeatureGuide: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let deviceHelp: String
    public let requires: [String]
    public let steps: [String]
    public let phoneRole: String
    public let flipperRole: String
    public let result: String
    public let limits: String
    public static func load() throws -> [FeatureGuide] {
        struct Catalog: Decodable { let features: [FeatureGuide] }
        guard let url = Bundle.module.url(forResource: "FeatureCatalog", withExtension: "json") else {
            throw RPCError.message("离线指南资源缺失。")
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Catalog.self, from: Data(contentsOf: url)).features
    }
}
