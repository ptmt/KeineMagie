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
    @MainActor func testLateStopAcknowledgmentPreservesNewerPersistedStop() async throws {
        let store=DictationDraftStore();var disk=Data();store.persist={disk=$0}
        let original=PlaybackFixture().record;try store.accept(original)
        var remote=original;var offline=false;var gate:CheckedContinuation<Void,Never>?
        var responses:[String:DictationPlayback]=[:];var plays=0;var requests:[DictationPlaybackRequest]=[]
        func make(_ journal:DictationDraftStore) -> DictationPlaybackController {
            DictationPlaybackController(read:{journal.record(original.id)},refresh:{remote},send:{request in
                requests.append(request)
                if offline {throw URLError(.notConnectedToInternet)}
                if let response=responses[request.id],request.action == "stop" {return response}
                let old=remote.playback!
                let active=["start","resume"].contains(request.action) ? DictationListen(id:request.id,client:request.client,step:0,fence:old.revision+1,offset:0,leaseUntil:2000000000000,done:false) : nil
                let response=DictationPlayback(revision:old.revision+1,wholeStarts:old.wholeStarts,cursor:1,finalUsed:false,active:active,listens:nil)
                remote.playback=response
                if request.action == "stop" {
                    responses[request.id]=response
                    await withCheckedContinuation {gate=$0}
                }
                return response
            },audio:{_ in Data()},publish:{try journal.acceptPlayback(id:original.id,policy:1,ledger:$0)},
            play:{_,_,_ in plays += 1},stop:{0},authorized:{true},failed:{_ in},
            readStop:{journal.playbackStop(id:original.id)},saveStop:{try journal.setPlaybackStop(id:original.id,intent:$0)})
        }
        let retained=make(store);await retained.play()
        let firstStop=retained.stop()
        while gate == nil {await Task.yield()}
        let firstID=try XCTUnwrap(store.playbackStop(id:original.id)?.id)
        await retained.suspend().value
        let replacement=make(store);await replacement.play()
        XCTAssertTrue(replacement.playing);XCTAssertNil(store.playbackStop(id:original.id))
        offline=true;await replacement.stop().value
        let second=try XCTUnwrap(store.playbackStop(id:original.id))
        XCTAssertNotEqual(second.id,firstID)
        let persistedBefore=disk;let requestsBefore=requests.count
        gate?.resume();await firstStop.value
        XCTAssertEqual(store.playbackStop(id:original.id)?.id,second.id,"Late S1 must not clear S2")
        XCTAssertEqual(disk,persistedBefore,"Late S1 must not write the journal")
        let cold=DictationDraftStore();try cold.restore(disk)
        XCTAssertEqual(cold.playbackStop(id:original.id)?.id,second.id)
        XCTAssertEqual(plays,2);XCTAssertFalse(retained.playing)
        await retained.play();await retained.stop().value
        XCTAssertFalse(retained.playing)
        XCTAssertEqual(store.playbackStop(id:original.id)?.id,second.id)
        XCTAssertEqual(disk,persistedBefore)
        XCTAssertEqual(requests.count,requestsBefore,"Stale controller must not retry S1 or resume")
        let relaunched=make(cold);await relaunched.play()
        XCTAssertFalse(relaunched.playing);XCTAssertEqual(plays,2)
        XCTAssertEqual(requests.last?.id,second.id,"Cold Play must retry S2 before admission")
    }

    @MainActor func testLateTrackedAcknowledgmentDoesNotOverwriteNewerStopIntent() async throws {
        let store=DictationDraftStore();var disk=Data();store.persist={disk=$0}
        var original=PlaybackFixture().record;original.mode="sentences"
        original.playback=DictationPlayback(revision:1,wholeStarts:1,cursor:1,finalUsed:false,active:nil,listens:nil)
        try store.accept(original)
        var remote=original;var gate:CheckedContinuation<Void,Never>?
        var completion:((Bool)->Void)?;var requests:[DictationPlaybackRequest]=[];var plays=0
        let controller=DictationPlaybackController(read:{store.record(original.id)},refresh:{remote},send:{request in
            requests.append(request)
            let old=remote.playback!
            let active=request.action == "start" ? DictationListen(id:request.id,client:request.client,step:1,fence:old.revision+1,offset:0,leaseUntil:2000000000000,done:false) : nil
            let response=DictationPlayback(revision:old.revision+1,wholeStarts:1,cursor:2,finalUsed:false,active:active,listens:nil)
            remote.playback=response
            if request.action == "ended" {await withCheckedContinuation {gate=$0}}
            return response
        },audio:{_ in Data()},publish:{try store.acceptPlayback(id:original.id,policy:1,ledger:$0)},
        play:{_,_,done in plays += 1;completion=done},stop:{0},authorized:{true},failed:{_ in},
        readStop:{store.playbackStop(id:original.id)},saveStop:{try store.setPlaybackStop(id:original.id,intent:$0)})
        await controller.play();completion?(true)
        while gate == nil {await Task.yield()}
        let pending=controller.stop()
        let firstID=try XCTUnwrap(store.playbackStop(id:original.id)?.id)
        var newer=DictationStopIntent(client:"replacement")
        newer.request=DictationPlaybackRequest(id:newer.id,client:newer.client,action:"stop",step:0,fence:4)
        try store.setPlaybackStop(id:original.id,intent:newer)
        XCTAssertNotEqual(newer.id,firstID)
        gate?.resume();await pending.value
        XCTAssertEqual(store.playbackStop(id:original.id)?.id,newer.id,"Tracked S1 acknowledgment must not overwrite S2")
        XCTAssertEqual(store.playbackStop(id:original.id)?.request?.id,newer.id)
        XCTAssertEqual(store.playbackStop(id:original.id)?.request?.fence,4)
        let cold=DictationDraftStore();try cold.restore(disk)
        XCTAssertEqual(cold.playbackStop(id:original.id)?.id,newer.id)
        XCTAssertEqual(requests.map(\.action),["start","ended"],"Stale controller must not send another Stop")
        XCTAssertFalse(controller.playing);XCTAssertEqual(plays,1)
    }

    @MainActor func testOfflineGapStopColdRestartDoesNotResetNewerReleasedForeignReservation() async throws {
        let store=DictationDraftStore();var disk=Data();store.persist={disk=$0}
        var object=try JSONSerialization.jsonObject(with:DictationPolicyTests.wire) as! [String:Any]
        object["mode"]="sentences"
        object["plan"]=[["kind":"whole","asset":0],["kind":"sentence","asset":1],
                        ["kind":"repeat","asset":1],["kind":"final","asset":0]]
        var original=try JSONDecoder().decode(DictationRecord.self,from:JSONSerialization.data(withJSONObject:object))
        original.playback=DictationPlayback(revision:7,wholeStarts:1,cursor:2,finalUsed:false,active:nil,listens:nil)
        try store.accept(original)
        var remote=original;var offline=true;var requests:[DictationPlaybackRequest]=[];var failures=0
        func make(_ journal:DictationDraftStore) -> DictationPlaybackController {
            DictationPlaybackController(read:{journal.record(original.id)},refresh:{
                if offline {throw URLError(.notConnectedToInternet)}
                return remote
            },send:{request in
                requests.append(request)
                if offline {throw URLError(.notConnectedToInternet)}
                let old=remote.playback!
                guard request.action == "stop",request.fence == old.revision else {throw APIError.http(409)}
                remote.playback=DictationPlayback(revision:old.revision+1,wholeStarts:old.wholeStarts,cursor:1,finalUsed:old.finalUsed,active:nil,listens:old.listens)
                return remote.playback!
            },audio:{_ in Data()},publish:{try journal.acceptPlayback(id:original.id,policy:1,ledger:$0)},
            play:{_,_,_ in XCTFail("Conflicting Stop must not play")},stop:{0},authorized:{true},failed:{_ in failures += 1},
            readStop:{journal.playbackStop(id:original.id)},saveStop:{try journal.setPlaybackStop(id:original.id,intent:$0)})
        }
        let controller=make(store)
        await controller.stop().value
        XCTAssertEqual(store.playbackStop(id:original.id)?.request?.fence,7,"Persist the observed gap revision before offline I/O")
        XCTAssertNil(store.playbackStop(id:original.id)?.admission)
        let cold=DictationDraftStore();try cold.restore(disk);cold.persist={disk=$0}
        let foreign=DictationListen(id:"foreign",client:"other-client",step:2,fence:9,offset:1.25,leaseUntil:0,done:false)
        let newer=DictationPlayback(revision:9,wholeStarts:2,cursor:2,finalUsed:true,active:foreign,listens:[foreign])
        remote.playback=newer;offline=false;requests=[]
        let relaunched=make(cold)
        await relaunched.play()
        XCTAssertEqual(requests.map(\.action),["stop"])
        XCTAssertEqual(requests.first?.fence,7,"Retry must not adopt the foreign generation")
        XCTAssertEqual(remote.playback,newer,"Released foreign reservation, offset, cursor and quota must survive")
        XCTAssertNotNil(cold.playbackStop(id:original.id))
        XCTAssertFalse(relaunched.playing)
        XCTAssertEqual(failures,2)
    }

    @MainActor func testStopAdvancesOnlyToHeldEndedAcknowledgment() async throws {
        let f=PlaybackFixture();f.record.mode="sentences"
        f.record.playback=DictationPlayback(revision:1,wholeStarts:1,cursor:1,finalUsed:false,active:nil,listens:nil)
        var remote=f.record;var disk:DictationStopIntent?;var gate:CheckedContinuation<Void,Never>?
        var completion:((Bool)->Void)?;var requests:[DictationPlaybackRequest]=[]
        let controller=DictationPlaybackController(read:{f.record},refresh:{remote},send:{request in
            requests.append(request)
            let old=remote.playback!
            if request.action == "stop",request.fence != old.revision {throw APIError.http(409)}
            let active=request.action == "start" ? DictationListen(id:request.id,client:request.client,step:1,fence:old.revision+1,offset:0,leaseUntil:2000000000000,done:false) : nil
            remote.playback=DictationPlayback(revision:old.revision+1,wholeStarts:old.wholeStarts,cursor:request.action == "ended" ? 2 : 1,finalUsed:false,active:active,listens:nil)
            let response=remote.playback!
            if request.action == "ended" {await withCheckedContinuation {gate=$0}}
            return response
        },audio:{_ in Data()},publish:{f.record.playback=$0},play:{_,_,done in completion=done},stop:{0},authorized:{true},failed:{_ in XCTFail("Unexpected failure")},readStop:{disk},saveStop:{disk=$0})
        await controller.play();completion?(true)
        while gate == nil {await Task.yield()}
        let stop=controller.stop()
        XCTAssertEqual(disk?.request?.fence,2,"Persist before waiting for the tracked acknowledgment")
        gate?.resume();await stop.value
        XCTAssertEqual(requests.map(\.action),["start","ended","stop"])
        XCTAssertEqual(requests.last?.fence,3)
        XCTAssertNil(disk)
        XCTAssertEqual(f.record.playback?.cursor,1)
    }

    @MainActor func testModeCancellationWaitsForPendingExplicitReset() async throws {
        let f=PlaybackFixture();var actions:[String]=[];var gate:CheckedContinuation<Void,Never>?
        let controller=DictationPlaybackController(read:{f.record},refresh:{f.record},send:{request in
            actions.append(request.action)
            let old=f.record.playback!
            if request.action == "stop" {await withCheckedContinuation {gate=$0}}
            let active=["resume","start","release"].contains(request.action) ? DictationListen(id:request.id,client:request.client,step:0,fence:old.revision+1,offset:0,leaseUntil:2000000000000,done:false) : nil
            return DictationPlayback(revision:old.revision+1,wholeStarts:1,cursor:1,finalUsed:false,active:active,listens:nil)
        },audio:{_ in Data([0])},publish:{f.record.playback=$0},play:{_,_,_ in},stop:{0},authorized:{true},failed:{_ in})
        await controller.play();let stop=controller.stop()
        while gate == nil {await Task.yield()}
        let mode=Task {try await controller.cancel()}
        for _ in 0..<40 {await Task.yield()}
        XCTAssertEqual(actions,["resume","stop"],"Mode/Check cancellation must not race a pending reset with another resume/cancel")
        gate?.resume();await stop.value;try await mode.value
        XCTAssertNil(f.record.playback?.active)
    }
    @MainActor func testOfflineStopColdRelaunchResetsBeforeNextStart() async throws {
        let store=DictationDraftStore();var disk=Data();store.persist={disk=$0}
        let original=PlaybackFixture().record;try store.accept(original)
        var remote=original;var offline=false;var position=1.5;var starts:[Double]=[];var actions:[String]=[]
        func make(_ journal:DictationDraftStore) -> DictationPlaybackController {
            DictationPlaybackController(read:{journal.record(original.id)},refresh:{remote},send:{request in
                actions.append(request.action)
                if offline {throw URLError(.notConnectedToInternet)}
                let old=remote.playback!
                let active=request.action == "start" || request.action == "resume" ? DictationListen(id:request.id,client:request.client,step:0,fence:old.revision+1,offset:request.action == "resume" ? 1.5 : 0,leaseUntil:2000000000000,done:false) : nil
                remote.playback=DictationPlayback(revision:old.revision+1,wholeStarts:old.wholeStarts+(request.action == "start" ? 1 : 0),cursor:1,finalUsed:false,active:active,listens:nil)
                return remote.playback!
            },audio:{_ in Data([0])},publish:{try journal.acceptPlayback(id:original.id,policy:1,ledger:$0)},play:{_,offset,_ in starts.append(offset)},stop:{position=0;return 1.5},authorized:{true},failed:{_ in},readStop:{journal.playbackStop(id:original.id)},saveStop:{try journal.setPlaybackStop(id:original.id,intent:$0)},position:{position},duration:{_ in 2})
        }
        let controller=make(store);await controller.play()
        offline=true;await controller.stop().value
        XCTAssertEqual(position,0);XCTAssertNotNil(store.playbackStop(id:original.id))
        let cold=DictationDraftStore();try cold.restore(disk);cold.persist={disk=$0}
        let relaunched=make(cold);await relaunched.loadTiming()
        XCTAssertEqual(relaunched.timing.elapsed,0,"Cold Stop must never restore stale media offset")
        let before=starts.count
        await relaunched.play();XCTAssertEqual(starts.count,before,"Offline reset cannot resume media")
        offline=false;actions=[];await relaunched.play()
        XCTAssertEqual(actions,["stop","start"])
        XCTAssertEqual(starts.last,0);XCTAssertNil(cold.playbackStop(id:original.id))
        await relaunched.stop().value
    }

    @MainActor func testStopWhileAdmissionIsHeldNeverPlaysLate() async throws {
        let f=PlaybackFixture();var remote=f.record
        var gate:CheckedContinuation<Void,Never>?;var actions:[String]=[];var plays=0
        let controller=DictationPlaybackController(read:{f.record},refresh:{remote},send:{request in
            actions.append(request.action)
            let old=remote.playback!
            if request.action == "stop",request.fence != old.revision {throw APIError.http(409)}
            let active=request.action == "start" || request.action == "resume" ? DictationListen(id:request.id,client:request.client,step:0,fence:old.revision+1,offset:0,leaseUntil:2000000000000,done:false) : nil
            remote.playback=DictationPlayback(revision:old.revision+1,wholeStarts:1,cursor:1,finalUsed:false,active:active,listens:nil)
            let response=remote.playback!
            if active != nil {await withCheckedContinuation {gate=$0}}
            return response
        },audio:{_ in Data([0])},publish:{f.record.playback=$0},play:{_,_,_ in plays += 1},stop:{0},authorized:{true},failed:{_ in XCTFail("unexpected failure")})
        let start=Task {await controller.play()}
        while gate == nil {await Task.yield()}
        let stop=controller.stop()
        gate?.resume();gate=nil
        await start.value;await stop.value
        XCTAssertEqual(plays,0);XCTAssertEqual(actions.last,"stop")
        XCTAssertNil(f.record.playback?.active)
        XCTAssertEqual(f.record.playback?.wholeStarts,1)
    }
    @MainActor func testStopIntentSurvivesColdJournalAndOwnerResetPurges() throws {
        let store=DictationDraftStore();var disk=Data();store.persist={disk=$0}
        let record=PlaybackFixture().record
        try store.accept(record)
        let intent=DictationStopIntent(client:"owner-client")
        try store.setPlaybackStop(id:record.id,intent:intent)
        let cold=DictationDraftStore();try cold.restore(disk)
        XCTAssertEqual(cold.playbackStop(id:record.id)?.id,intent.id)
        XCTAssertEqual(cold.record(record.id)?.draft,record.draft)
        cold.reset();XCTAssertNil(cold.playbackStop(id:record.id))
    }
    @MainActor func testExplicitStopImmediatelyResetsTimingAndNeverEnds() async throws {
        let f = PlaybackFixture()
        await f.controller.loadTiming(); await f.controller.play()
        f.mediaPosition = 1.25
        let oldCompletion = f.completion
        let stopped = f.controller.stop()
        XCTAssertFalse(f.controller.playing)
        XCTAssertEqual(f.controller.timing.elapsed, 0)
        await stopped.value
        oldCompletion?(true)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(f.actions.last?.action, "stop")
        XCTAssertFalse(f.actions.contains { $0.action == "ended" })
        XCTAssertNil(f.record.playback?.active)
    }
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
    @MainActor func testReplacedAttemptReleasesLateAdmissionWithoutStartingOrEndingMedia() async throws {
        let f = PlaybackFixture()
        var admission: CheckedContinuation<DictationPlayback, Never>?
        var request: DictationPlaybackRequest?
        var commands: [String] = []
        let controller = DictationPlaybackController(read:{f.record},refresh:{f.record},send:{ command in
            commands.append(command.action)
            if command.action == "resume" {
                request = command
                return await withCheckedContinuation { admission = $0 }
            }
            return DictationPlayback(revision:4,wholeStarts:1,cursor:1,finalUsed:false,
                active:DictationListen(id:command.id,client:command.client,step:0,fence:4,offset:command.offset,leaseUntil:0,done:false),listens:nil)
        },audio:{_ in XCTFail("Replaced admission must never load media");return Data()},publish:{f.record.playback=$0},
           play:{_,_,_ in XCTFail("Replaced admission must never play")},stop:{0},authorized:{true},failed:{_ in XCTFail("Unexpected failure")})
        let start = Task { await controller.play() }
        while admission == nil { await Task.yield() }
        await controller.suspend().value
        let command = try XCTUnwrap(request)
        admission?.resume(returning:DictationPlayback(revision:3,wholeStarts:1,cursor:1,finalUsed:false,
            active:DictationListen(id:command.id,client:command.client,step:0,fence:3,offset:0.5,leaseUntil:2000000000000,done:false),listens:nil))
        await start.value
        XCTAssertEqual(commands,["resume","release"])
        XCTAssertEqual(f.record.playback?.active?.leaseUntil,0)
        XCTAssertEqual(f.record.playback?.wholeStarts,1)
        XCTAssertFalse(controller.playing)
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
