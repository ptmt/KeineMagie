import Foundation
import Testing
import KeineMagieCore
@testable import Lifecycle

@Test @MainActor func activityOwnerOfflineAndUnauthorized() async throws {
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 defer { try? FileManager.default.removeItem(at:root) }
 let gate=CoachGate();let model=try await gate.model(root)
 gate.bodyOverride = #"{"version":1,"time_zone":"UTC","days":[],"sources":{},"undated":0}"#
 #expect(await model.loadActivity(start:"2026-11-16",timeZone:"UTC") != nil)
 gate.hold=true
 let stale=Task {await model.loadActivity(start:"2026-11-16",timeZone:"UTC")}
 while gate.replies.isEmpty {await Task.yield()}
 gate.owner="other-owner";await model.session.restore()
 gate.replies.removeFirst().resume()
 #expect(await stale.value == nil)
 gate.hold=false;gate.status=401
 #expect(await model.loadActivity(start:"2026-11-16",timeZone:"UTC") == nil)
 #expect(!model.session.canWrite)
 let before=gate.calls.count
 #expect(await model.loadActivity(start:"2026-11-16",timeZone:"UTC") == nil)
 #expect(gate.calls.count == before)
 #expect(gate.calls.allSatisfy{$0 == "GET"})
}
