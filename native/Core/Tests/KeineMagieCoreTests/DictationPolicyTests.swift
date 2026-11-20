import Foundation
import XCTest
@testable import KeineMagieCore

private actor AudioGateForPolicy {
    var continuation:CheckedContinuation<Void,Never>?
    func wait() async {await withCheckedContinuation {continuation=$0}}
    func ready() -> Bool {continuation != nil}
    func release() {continuation?.resume();continuation=nil}
}
final class DictationPolicyTests: XCTestCase {
    static let wire = Data(#"{"id":"policy","title":"Synthetic","language":"de","created":"now","mode":"whole","step":0,"replays":0,"draft":"","revision":1,"checked":false,"assisted":false,"plan":[{"kind":"whole","asset":0},{"kind":"sentence","asset":1},{"kind":"final","asset":0}],"ready":[0,1],"playback_policy_version":1,"playback":{"revision":2,"whole_starts":1,"cursor":1,"final_used":false,"active":{"id":"listen","client":"client","step":0,"fence":2,"offset":0.5,"lease_until":2000000000000,"done":false}}}"#.utf8)
    @MainActor func testLedgerRefreshMergesThroughDirtyDraftAndColdRestore() throws {
        let store = DictationDraftStore()
        var snapshot = Data()
        store.persist = { snapshot = $0 }
        var server = try JSONDecoder().decode(DictationRecord.self, from: Self.wire)
        try store.accept(server)
        try store.edit(id:server.id,draft:"offline typing")
        server.playback = try JSONDecoder().decode(DictationPlayback.self, from: Data(#"{"revision":4,"whole_starts":3,"cursor":2,"final_used":false}"#.utf8))
        try store.accept(server)
        let cold = DictationDraftStore(); try cold.restore(snapshot)
        XCTAssertEqual(cold.record(server.id)?.draft,"offline typing")
        XCTAssertEqual(cold.record(server.id)?.playback?.wholeStarts,3)
        server.playback = try JSONDecoder().decode(DictationPlayback.self, from: Data(#"{"revision":1,"whole_starts":0,"cursor":1,"final_used":false}"#.utf8))
        try store.accept(server)
        XCTAssertEqual(store.record(server.id)?.playback?.wholeStarts,3)
    }
    @MainActor func testCleanRefreshAndStaleUIUpdateCannotRewindLedger() throws {
        let store = DictationDraftStore()
        let newer = try JSONDecoder().decode(DictationRecord.self,from:Self.wire)
        try store.accept(newer)
        var stale = newer; stale.playback=nil; stale.playbackPolicyVersion=nil
        try store.accept(stale)
        XCTAssertEqual(store.record(newer.id)?.playback?.wholeStarts,1)
        try store.update(stale)
        XCTAssertEqual(store.record(newer.id)?.playbackPolicyVersion,1)
        var local = newer
        local.transition(.ended);local.transition(.sentences)
        XCTAssertEqual(local.replays,0)
        XCTAssertEqual(local.segment?.kind,"whole") // Interrupted whole stays selected until cancellation.
    }
    @MainActor func testUseServerConflictCannotRewindPlaybackLedger() throws {
        let store=DictationDraftStore();var saved=Data();store.persist={saved=$0}
        let original=try JSONDecoder().decode(DictationRecord.self,from:Self.wire)
        try store.accept(original)
        try store.markConflict(id:original.id,server:original)
        let latest=try JSONDecoder().decode(DictationPlayback.self,from:Data(#"{"revision":9,"whole_starts":4,"cursor":2,"final_used":true}"#.utf8))
        try store.acceptPlayback(id:original.id,policy:1,ledger:latest)
        try store.useServer(original.id)
        let cold=DictationDraftStore();try cold.restore(saved)
        XCTAssertEqual(cold.record(original.id)?.playback?.wholeStarts,4)
        XCTAssertEqual(cold.record(original.id)?.playback?.revision,9)
        XCTAssertTrue(cold.record(original.id)?.policyExhausted == true)
    }
    func testPlaybackRequestUsesExistingAuthenticatedRouteAndShortLeaseTimeout() throws {
        let api=PodcastAPI(endpoint:try ServerEndpoint("https://example.com"),token:"fixture")
        let request=try api.dictationRequest(id:"policy",action:"playback",method:"POST",body:Data("{}".utf8))
        XCTAssertEqual(request.url?.path,"/v1/learning/dictations/policy/playback")
        XCTAssertEqual(request.timeoutInterval,8)
        XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer fixture")
    }
    func testRevokedAudioIsNotHiddenByCancellation() async throws {
        let gate=AudioGateForPolicy()
        let api=PodcastAPI(endpoint:try ServerEndpoint("https://example.com"),token:"fixture",transport:{_ in await gate.wait();return AuthResponse(data:Data(),status:401)})
        let task=Task {try await api.dictationAudio(id:"policy",index:0,prepare:false)}
        while !(await gate.ready()) {await Task.yield()}
        task.cancel();await gate.release()
        do {_ = try await task.value;XCTFail("revoked audio returned")}
        catch APIError.http(401) {} catch {XCTFail("401 hidden: \(error)")}
    }
    func testPolicySurvivesDecodeEncodeInsteadOfOldClientDroppingIt() throws {
        let record = try JSONDecoder().decode(DictationRecord.self, from: Self.wire)
        let data = try JSONEncoder().encode(record)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String:Any])
        XCTAssertEqual(object["playback_policy_version"] as? Int, 1)
        XCTAssertEqual((object["playback"] as? [String:Any])?["whole_starts"] as? Int, 1)
    }
    @MainActor func testNewCreateAndAttemptOptInButPersistedLegacyRetryIsUnchanged() throws {
        let store = DictationDraftStore()
        try store.editAdd(title:"Test", original:"Hallo.")
        let body = try store.pendingCreate()
        XCTAssertEqual((try JSONSerialization.jsonObject(with: body) as? [String:Any])?["playback_policy_version"] as? Int, 2)
        let attempt = try store.pendingAttempt(source:"policy")
        XCTAssertEqual((try JSONSerialization.jsonObject(with: attempt) as? [String:Any])?["playback_policy_version"] as? Int, 2)
        let legacy = Data(#"{"entries":{},"add":{"title":"Test","original":"Hallo.","id":"old","pending":"eyJpZCI6Im9sZCJ9"},"attempts":{"old":"eyJpZCI6Im9sZCJ9"},"recovered":{},"conflicts":{}}"#.utf8)
        try store.restore(legacy)
        XCTAssertEqual(try store.pendingCreate(), Data(#"{"id":"old"}"#.utf8))
        XCTAssertEqual(try store.pendingAttempt(source:"old"), Data(#"{"id":"old"}"#.utf8))
    }
}
