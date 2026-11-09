import Foundation

public struct ProviderStatus: Decodable, Sendable {
    public let connected: Bool
    public let status: String
    public let message: String
    public let selectedModel: String?
    public let models: [ProviderModel]?
    enum CodingKeys: String, CodingKey { case connected, status, message, models; case selectedModel = "selected_model" }
}
public struct ProviderModel: Decodable, Sendable {
    public let slug: String
    public let displayName: String
    enum CodingKeys: String, CodingKey { case slug; case displayName = "display_name" }
}
public struct ProviderBootstrap: Decodable, Sendable {
    public let bootstrapToken: String
    public let expiresIn: Int
    public let message: String
    enum CodingKeys: String, CodingKey { case message; case bootstrapToken = "bootstrap_token"; case expiresIn = "expires_in" }
}
