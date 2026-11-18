import Foundation
import XCTest
@testable import KeineMagieCore

@MainActor private final class PlaybackFixture {
    var record = try! JSONDecoder().decode(DictationRecord.self,from:DictationPolicyTests.wire)
    var actions: [DictationPlaybackRequest] = []
    var plays = 0; var stops = 0; var allowed = true
    var completion: ((Bool) -> Void)?
    var errors: [Error] = []
    var clock: Int64 = 1000
    var mediaPosition: Double = 0
    var sleepGate: CheckedContinuation<Void,Error>?
    var resumeGate: CheckedContinuation<Void,Error>?
    var resumedPauses: [Double] = []
    var holdRefresh = false
    var refreshGate: CheckedContinuation<DictationRecord, Error>?
    lazy var controller = DictationPlaybackController(
        read: { self.record }, refresh: {
            if self.holdRefresh { return try await withCheckedThrowingContinuation { self.refreshGate = $0 } }
            return self.record
        },
        send: { request in
            self.actions.append(request)
            let old=self.record.playback!
            let active = ["release","progress","resume","start"].contains(request.action) ? DictationListen(id:request.id,client:request.client,step:request.step,fence:old.revision+1,offset:request.offset,leaseUntil: request.action == "release" ? 0 : 2000000000000,done:false) : nil
            return DictationPlayback(revision:old.revision+1,wholeStarts:old.wholeStarts,cursor:request.action == "ended" && request.step > 0 ? old.cursor+1 : old.cursor,finalUsed:old.finalUsed,active:active,listens:nil)
        }, audio: { _ in Data([0]) }, publish: { self.record.playback=$0 },
        play: { _,_,finish in self.plays += 1;self.completion=finish },
        stop: { self.stops += 1; return 0.7 }, authorized: {self.allowed}, failed: {self.errors.append($0)},
        position: { self.mediaPosition }, duration: { _ in 2 },
        pause: { try await withCheckedThrowingContinuation {self.sleepGate=$0} },
        timingNow: { Double(self.clock) / 1000 },
        resumePause: { seconds in
            self.resumedPauses.append(seconds)
            try await withCheckedThrowingContinuation { self.resumeGate = $0 }
        }, now: { self.clock })
}
final class DictationPlaybackControllerTests: XCTestCase {
    @MainActor func testRealCachedDurationsEndPersistsAndFinalStartsFresh() async throws {
        let f = PlaybackFixture()
        await f.controller.loadTiming()
        XCTAssertEqual(f.controller.timing.duration, 2)
        XCTAssertEqual(f.actions.count, 0, "Timing GET must never admit a start")
        await f.controller.play()
        f.mediaPosition = 1.25
        XCTAssertEqual(f.controller.timing.elapsed, 1.25)
        f.completion?(true)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(f.controller.timing.remaining, 0)
        await f.controller.interrupt()
        XCTAssertEqual(f.controller.timing.elapsed, 2, "Natural completion survives tab/background stop")
        await f.controller.play()
        XCTAssertEqual(f.controller.timing.duration, 2)
        await f.controller.interrupt()
    }

    @MainActor func testGapClockFreezesOnCancellationAndRejectsLateGapCompletion() async throws {
        let f = PlaybackFixture()
        var object = try JSONSerialization.jsonObject(with: DictationPolicyTests.wire) as! [String: Any]
        object["mode"] = "sentences"
        object["plan"] = [["kind":"whole","asset":0], ["kind":"sentence","asset":1],
                          ["kind":"repeat","asset":1], ["kind":"final","asset":0]]
        object["ready"] = [0, 1]
        f.record = try JSONDecoder().decode(DictationRecord.self, from: JSONSerialization.data(withJSONObject: object))
        f.record.playback = DictationPlayback(revision: 1, wholeStarts: 1, cursor: 1, finalUsed: false, active: nil, listens: nil)
        await f.controller.loadTiming()
        XCTAssertEqual(f.controller.timing.duration, 7)
        await f.controller.play()
        f.mediaPosition = 2
        f.completion?(true)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertTrue(f.controller.waiting)
        f.clock += 1500
        XCTAssertEqual(f.controller.timing.elapsed, 3.5)
        await f.controller.interrupt()
        f.clock += 10000
        XCTAssertEqual(f.controller.timing.elapsed, 3.5)
        f.sleepGate?.resume(); f.sleepGate = nil
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(f.plays, 1)
        XCTAssertEqual(f.record.playback?.wholeStarts, 1)
        await f.controller.loadTiming()
        XCTAssertEqual(f.controller.timing.elapsed, 3.5)
        let resume = Task { await f.controller.play() }
        while f.resumeGate == nil { await Task.yield() }
        XCTAssertEqual(f.resumedPauses, [1.5])
        XCTAssertEqual(f.plays, 1, "No media/admission before remaining real gap")
        f.clock += 1500
        f.mediaPosition = 0
        f.holdRefresh = true
        f.resumeGate?.resume(); f.resumeGate = nil
        while f.refreshGate == nil { await Task.yield() }
        XCTAssertEqual(f.controller.timing.elapsed, 5, "Completed resumed gap must remain counted while admission is pending")
        f.holdRefresh = false; f.refreshGate?.resume(returning: f.record); f.refreshGate = nil
        await resume.value
        XCTAssertEqual(f.plays, 2)
        XCTAssertEqual(f.controller.timing.elapsed, 5)
        f.mediaPosition = 2; f.completion?(true)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertFalse(f.controller.waiting)
        XCTAssertEqual(f.controller.timing.elapsed, 7)
        XCTAssertEqual(f.plays, 2, "Final reading is never automatic")
        await f.controller.play()
        XCTAssertEqual(f.controller.timing.duration, 2, "Explicit final has its own whole track")
        await f.controller.interrupt()
    }

    @MainActor func testCancelledTimingDownloadCannotPublishDurationOrAdmitPlayback() async throws {
        let f = PlaybackFixture()
        var gate: CheckedContinuation<Data, Error>?
        let controller = DictationPlaybackController(read: {f.record}, refresh: {f.record},
            send: {_ in XCTFail("Timing must not admit playback"); return f.record.playback!},
            audio: {_ in try await withCheckedThrowingContinuation {gate = $0}},
            publish: {_ in XCTFail("Timing must not mutate ledger")}, play: {_,_,_ in XCTFail("Late play")},
            stop: {0}, authorized: {f.allowed}, failed: {_ in XCTFail("Unexpected error")}, duration: {_ in 5})
        let download = Task {await controller.loadTiming()}
        while gate == nil {await Task.yield()}
        await controller.interrupt()
        gate?.resume(returning: Data([0]))
        await download.value
        XCTAssertTrue(controller.durations.isEmpty)
        XCTAssertNil(controller.timing.duration)
    }

    @MainActor func testTimingDownloadSurvivesPlaybackAdmission() async throws {
        let f = PlaybackFixture()
        var object = try JSONSerialization.jsonObject(with: DictationPolicyTests.wire) as! [String: Any]
        object["mode"] = "sentences"
        object["plan"] = [["kind":"whole","asset":0], ["kind":"sentence","asset":1], ["kind":"sentence","asset":2], ["kind":"final","asset":0]]
        object["ready"] = [1,2]
        f.record = try JSONDecoder().decode(DictationRecord.self, from: JSONSerialization.data(withJSONObject: object))
        f.record.playback = DictationPlayback(revision:1,wholeStarts:1,cursor:1,finalUsed:false,active:nil,listens:nil)
        var first = true
        var gate: CheckedContinuation<Data, Error>?
        let controller = DictationPlaybackController(read:{f.record},refresh:{f.record},send:{ request in
            DictationPlayback(revision:2,wholeStarts:1,cursor:1,finalUsed:false,
                active:DictationListen(id:request.id,client:request.client,step:1,fence:2,offset:0,leaseUntil:2000000000000,done:false),listens:nil)
        },audio:{ _ in
            if first { first=false; return try await withCheckedThrowingContinuation {gate=$0} }
            return Data([0])
        },publish:{f.record.playback=$0},play:{_,_,_ in},stop:{0},authorized:{f.allowed},failed:{_ in XCTFail("unexpected")},duration:{_ in 2})
        let metadata = Task {await controller.loadTiming()}
        while gate == nil {await Task.yield()}
        await controller.play()
        gate?.resume(returning:Data([0])); await metadata.value
        XCTAssertEqual(controller.durations[2],2)
        XCTAssertEqual(controller.timing.duration,7)
        await controller.interrupt()
    }

    @MainActor func testCompletedGapRemainsCountedDuringNextAdmission() async throws {
        let f = PlaybackFixture()
        var object = try JSONSerialization.jsonObject(with: DictationPolicyTests.wire) as! [String: Any]
        object["mode"] = "sentences"
        object["plan"] = [["kind":"whole","asset":0], ["kind":"sentence","asset":1], ["kind":"repeat","asset":1], ["kind":"final","asset":0]]
        object["ready"] = [0,1]
        f.record = try JSONDecoder().decode(DictationRecord.self, from: JSONSerialization.data(withJSONObject: object))
        f.record.playback = DictationPlayback(revision:1,wholeStarts:1,cursor:1,finalUsed:false,active:nil,listens:nil)
        await f.controller.loadTiming(); await f.controller.play()
        f.mediaPosition=2;f.completion?(true)
        while f.sleepGate == nil {await Task.yield()}
        f.clock += 3000
        XCTAssertEqual(f.controller.timing.elapsed,5)
        f.holdRefresh=true;f.sleepGate?.resume();f.sleepGate=nil
        while f.refreshGate == nil {await Task.yield()}
        XCTAssertEqual(f.controller.timing.elapsed,5,"Elapsed must not jump backward across a completed gap")
        XCTAssertEqual(f.controller.timing.remaining,2)
        f.mediaPosition=0;f.holdRefresh=false;f.refreshGate?.resume(returning:f.record);f.refreshGate=nil
        while f.plays < 2 {await Task.yield()}
        await f.controller.interrupt()
    }

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
