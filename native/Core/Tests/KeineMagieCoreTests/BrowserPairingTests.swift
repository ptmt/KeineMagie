import Foundation
import Testing
@testable import KeineMagieCore
@Test func browserPairingRequiresSeparateInspectionAndDecision() throws {
 let api = APIClient(endpoint: try ServerEndpoint("https://example.com"), token: "native-session")
 let inspect = try api.browserPairingRequest(code: "ABCD-EFGH")
 #expect(inspect.url?.path == "/v1/auth/browser/inspect")
 #expect(inspect.value(forHTTPHeaderField: "Authorization") == "Bearer native-session")
 #expect(inspect.httpBody == Data("{\"user_code\":\"ABCD-EFGH\"}".utf8))
 let deny = try api.browserApprovalRequest(approval: "random-approval", approve: false)
 #expect(deny.url?.path == "/v1/auth/browser/approve")
 let body = try JSONSerialization.jsonObject(with: deny.httpBody!) as! [String:Any]
 #expect(body["approve"] as? Bool == false)
 #expect(body["approval_token"] as? String == "random-approval")
 #expect(throws: (any Error).self) { try api.browserPairingRequest(code: "bad") }
}
