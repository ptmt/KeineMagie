import Foundation
import XCTest
@testable import KeineMagieCore

final class DictationManualIntegrationTests: XCTestCase {
    @MainActor func testNewAttemptsOptIntoManualPacingWithoutChangingStoredAttempts() throws {
        let store=DictationDraftStore()
        try store.editAdd(title:"Test",original:"Die Katze schläft.")
        let body=try JSONSerialization.jsonObject(with:store.pendingCreate()) as! [String:Any]
        XCTAssertEqual(body["playback_policy_version"] as? Int,2)
        let attempt=try JSONSerialization.jsonObject(with:store.pendingAttempt(source:"old")) as! [String:Any]
        XCTAssertEqual(attempt["playback_policy_version"] as? Int,2)
    }
    func testManualTimingContainsOnlyCurrentFragmentAndConfiguredRepeatGaps() throws {
        var record=try JSONDecoder().decode(DictationRecord.self,from:Self.wire)
        record.playback=DictationPlayback(revision:1,wholeStarts:1,cursor:1,finalUsed:false,active:nil,listens:nil)
        XCTAssertEqual(record.timingSteps,[1,2],"Manual writing waits are not timed audio")
        XCTAssertEqual(DictationTimingTrack(assets:[1,1],gapSeconds:8).snapshot(durations:[1:2],index:0,position:0).duration,12)
    }
    @MainActor func testPacingMutationSurvivesColdRestoreWithExactBody() throws {
        let store=DictationDraftStore();var disk=Data();store.persist={disk=$0}
        try store.accept(JSONDecoder().decode(DictationRecord.self,from:Self.wire))
        let body=try store.pendingPacing(id:"manual",repeats:3,gapSeconds:8)
        let cold=DictationDraftStore();try cold.restore(disk)
        XCTAssertEqual(try cold.pendingPacing(id:"manual",repeats:2,gapSeconds:3),body)
    }
    static let wire = Data(#"{"id":"manual","title":"Manual","language":"de","created":"now","mode":"sentences","step":0,"replays":0,"draft":"Heute","revision":0,"checked":false,"assisted":false,"playback_policy_version":2,"pacing":{"repeats":2,"gap_seconds":8},"playback":{"revision":0,"cursor":0,"whole_starts":0,"final_used":false},"plan":[{"kind":"whole","asset":0},{"kind":"sentence","asset":1},{"kind":"sentence_repeat","asset":1},{"kind":"sentence","asset":2},{"kind":"sentence_repeat","asset":2},{"kind":"final","asset":0}],"ready":[0,1,2]}"#.utf8)
    @MainActor func testIntroductionAndFragmentRequireExplicitNextButRepeatsUseConfiguredGap() async throws {
        var record = try JSONDecoder().decode(DictationRecord.self, from: Self.wire)
        var completion: ((Bool)->Void)?; var commands: [DictationPlaybackRequest] = []; var gaps: [Double] = []
        let controller = DictationPlaybackController(read:{record},refresh:{record},send:{request in
            commands.append(request)
            let old = record.playback!
            let active = request.action == "start" ? DictationListen(id:request.id,client:request.client,step:request.step,fence:old.revision+1,offset:0,leaseUntil:2000000000000,done:false) : nil
            return DictationPlayback(revision:old.revision+1,wholeStarts:old.wholeStarts,cursor:request.action == "ended" ? request.step+1 : old.cursor,finalUsed:false,active:active,listens:nil)
        },audio:{_ in Data()},publish:{record.playback=$0},play:{_,_,end in completion=end},stop:{0},authorized:{true},failed:{XCTFail("\($0)")},resumePause:{gaps.append($0)})
        await controller.play()
        XCTAssertTrue(controller.playing, "Policy 2 must admit its actual introduction")
        XCTAssertEqual(commands.first?.step,0)
        completion?(true)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertFalse(controller.playing); XCTAssertFalse(controller.waiting)
        XCTAssertEqual(commands.filter{$0.action == "start"}.count,1,"Introduction must not auto-next")
        await controller.play() // explicit Next
        completion?(true)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(gaps,[8]); XCTAssertEqual(commands.last?.step,2)
        completion?(true)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertFalse(controller.playing); XCTAssertFalse(controller.waiting)
        XCTAssertEqual(commands.filter{$0.action == "start"}.count,3,"Fragment completion must wait for Next")
        let encoded = try JSONSerialization.jsonObject(with:JSONEncoder().encode(try XCTUnwrap(commands.first))) as! [String:Any]
        XCTAssertEqual(encoded["policy_version"] as? Int,2)
        XCTAssertEqual(encoded["intent"] as? String,"planned")
        await controller.suspend().value
    }
}
