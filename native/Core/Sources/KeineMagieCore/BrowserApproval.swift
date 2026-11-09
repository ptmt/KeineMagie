public struct BrowserApproval: Decodable, Sendable {
 public let approvalToken: String
 public let userCode: String
 public let origin: String
 public let expiresAt: String
 enum CodingKeys: String, CodingKey { case approvalToken = "approval_token", userCode = "user_code", origin, expiresAt = "expires_at" }
}
