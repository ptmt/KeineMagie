import Foundation
import XCTest
@testable import KeineMagieCore

@MainActor private final class PlaybackFixture {
    var record = try! JSONDecoder().decode(DictationRecord.self,from:DictationPolicyTests.wire)
    var actions: [DictationPlaybackRequest] = []
    var plays = 0; var stops = 0; var allowed = true
    var completion: ((Bool) -> Void)?
    var errors: [Error] = []
    var sleepGate: CheckedContinuation<Void,Error>?
    lazy var controller = DictationPlaybackController(
        read: { self.record }, refresh: { self.record },
        send: { request in
            self.actions.append(request)
            let old=self.record.playback!
            let active = ["release","progress","resume","start"].contains(request.action) ? DictationListen(id:request.id,client:request.client,step:request.step,fence:old.revision+1,offset:request.offset,leaseUntil: request.action == "release" ? 0 : 2000000000000,done:false) : nil
            return DictationPlayback(revision:old.revision+1,wholeStarts:old.wholeStarts,cursor:request.action == "ended" && request.step > 0 ? old.cursor+1 : old.cursor,finalUsed:old.finalUsed,active:active,listens:nil)
        }, audio: { _ in Data([0]) }, publish: { self.record.playback=$0 },
        play: { _,_,finish in self.plays += 1;self.completion=finish },
        stop: { self.stops += 1; return 0.7 }, authorized: {self.allowed}, failed: {self.errors.append($0)},
        pause: { try await withCheckedThrowingContinuation {self.sleepGate=$0} })
}
final class DictationPlaybackControllerTests: XCTestCase {
    @MainActor func testLate401RevokesSameOwnerAfterAttemptNavigationButNotReplacementOwner() async throws {
        let f=PlaybackFixture()
        var gate:CheckedContinuation<DictationRecord,Error>?
        var sameOwner=true;var selected=true;var failures=0
        let controller=DictationPlaybackController(read:{f.record},refresh:{try await withCheckedThrowingContinuation {gate=$0}},send:{_ in f.record.playback!},audio:{_ in Data()},publish:{_ in XCTFail("late publication")},play:{_,_,_ in XCTFail("late play")},stop:{0},authorized:{selected},failed:{_ in failures += 1},ownerCurrent:{sameOwner})
        let task=Task {await controller.play()}
        while gate == nil {await Task.yield()}
        selected=false;await controller.interrupt();gate?.resume(throwing:APIError.http(401));await task.value
        XCTAssertEqual(failures,1)
        selected=true;gate=nil
        let next=Task {await controller.play()}
        while gate == nil {await Task.yield()}
        sameOwner=false;selected=false;await controller.interrupt();gate?.resume(throwing:APIError.http(401));await next.value
        XCTAssertEqual(failures,1)
    }
    @MainActor func testInterruptedContinueUsesSameReservationAndDoesNotEnd() async throws {
        let f=PlaybackFixture()
        await f.controller.play()
        XCTAssertEqual(f.actions.map(\.action),["resume"])
        XCTAssertEqual(f.plays,1)
        let stale=f.completion
        await f.controller.interrupt()
        stale?(true)
        await Task.yield()
        XCTAssertEqual(f.actions.map(\.action),["resume","release"])
        await f.controller.play()
        XCTAssertEqual(f.actions.map(\.action),["resume","release","resume"])
        XCTAssertEqual(Set(f.actions.map(\.id)),["listen"])
        XCTAssertEqual(f.record.playback?.wholeStarts,1)
    }
    @MainActor func testDecodeFailureNeverCompletesAndRevokedOwnerCannotResume() async throws {
        let f=PlaybackFixture()
        await f.controller.play()
        f.completion?(false)
        for _ in 0..<30 {await Task.yield()}
        XCTAssertFalse(f.actions.contains {$0.action == "ended"})
        f.allowed=false
        await f.controller.play()
        XCTAssertEqual(f.plays,1)
    }
    @MainActor func testContinuousSequenceUsesRealThreeSecondPauseAndStopsOnBackground() async throws {
        var record=try JSONDecoder().decode(DictationRecord.self,from:DictationPolicyTests.wire)
        var object=try JSONSerialization.jsonObject(with:DictationPolicyTests.wire) as! [String:Any]
        object["mode"]="sentences"
        object["plan"]=[["kind":"whole","asset":0],["kind":"sentence","asset":1],["kind":"chunk","asset":2],["kind":"final","asset":0]]
        record=try JSONDecoder().decode(DictationRecord.self,from:JSONSerialization.data(withJSONObject:object))
        record.playback=DictationPlayback(revision:1,wholeStarts:0,cursor:1,finalUsed:false,active:nil,listens:nil)
        var plays=0;var completion:((Bool)->Void)?
        let controller=DictationPlaybackController(read:{record},refresh:{record},send:{request in
            let old=record.playback!
            let active=request.action == "ended" ? nil : DictationListen(id:request.id,client:request.client,step:request.step,fence:old.revision+1,offset:0,leaseUntil:2000000000000,done:false)
            return DictationPlayback(revision:old.revision+1,wholeStarts:0,cursor:request.action == "ended" ? old.cursor+1 : old.cursor,finalUsed:false,active:active,listens:nil)
        },audio:{_ in Data()},publish:{record.playback=$0},play:{_,_,done in plays += 1;completion=done},stop:{0},authorized:{true},failed:{_ in XCTFail("unexpected failure")})
        await controller.play();completion?(true)
        for _ in 0..<30 {await Task.yield()}
        XCTAssertTrue(controller.waiting)
        try await Task.sleep(for:.milliseconds(2800));XCTAssertEqual(plays,1)
        try await Task.sleep(for:.milliseconds(400));XCTAssertEqual(plays,2)
        completion?(true)
        for _ in 0..<30 {await Task.yield()}
        XCTAssertFalse(controller.waiting);XCTAssertEqual(record.playback?.cursor,3)
        await controller.interrupt()
        XCTAssertFalse(record.checked)
    }
    @MainActor func testExpiredLeaseStopsMediaWithoutEndedOrAnotherStart() async throws {
        let f=PlaybackFixture()
        // Expiry is tested with a controlled server lease and the real deadline task.
        var plays=0;var stops=0;var errors=0;var actions:[String]=[]
        var ledger=f.record.playback!
        let controller=DictationPlaybackController(read:{f.record},refresh:{f.record},send:{request in
            actions.append(request.action)
            ledger=DictationPlayback(revision:ledger.revision+1,wholeStarts:1,cursor:1,finalUsed:false,active:DictationListen(id:request.id,client:request.client,step:0,fence:ledger.revision+1,offset:0,leaseUntil:Int64(Date().timeIntervalSince1970*1000)+350,done:false),listens:nil)
            return ledger
        },audio:{_ in Data()},publish:{f.record.playback=$0},play:{_,_,_ in plays += 1},stop:{stops += 1;return 0},authorized:{true},failed:{_ in errors += 1})
        await controller.play();XCTAssertEqual(plays,1)
        for _ in 0..<100 {if errors > 0 {break};try await Task.sleep(for:.milliseconds(20))}
        XCTAssertFalse(controller.playing);XCTAssertEqual(errors,1)
        XCTAssertEqual(actions,["resume","release"]);XCTAssertGreaterThan(stops,0)
    }
    @MainActor func testSentenceChainWaitsThreeSecondsAndFinalIsExplicit() async throws {
        let f=PlaybackFixture()
        f.record.mode="sentences"
        f.record.playback=DictationPlayback(revision:1,wholeStarts:0,cursor:1,finalUsed:false,active:nil,listens:nil)
        await f.controller.play()
        f.completion?(true)
        for _ in 0..<30 {await Task.yield()}
        XCTAssertEqual(f.record.playback?.cursor,2)
        XCTAssertFalse(f.controller.waiting)
        XCTAssertEqual(f.plays,1) // Final whole never autoplays.
        await f.controller.play()
        XCTAssertEqual(f.plays,2)
        await f.controller.interrupt()
    }
}
