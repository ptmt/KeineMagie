import Foundation
import Observation

/// Owner/attempt-scoped media admission. No synthesis, grading, or draft writes.
/// A stopped/failed player releases a lease, never reports a successful ending.
@MainActor @Observable public final class DictationPlaybackController {
    public private(set) var busy = false
    public private(set) var waiting = false
    public private(set) var playing = false
    private let read: () -> DictationRecord?
    private let refresh: @MainActor () async throws -> DictationRecord
    private let send: @MainActor (DictationPlaybackRequest) async throws -> DictationPlayback
    private let audio: (Int) async throws -> Data
    private let publish: (DictationPlayback) throws -> Void
    private let startMedia: (Data, Double, @escaping (Bool) -> Void) throws -> Void
    private let stopMedia: () -> Double
    private let authorized: () -> Bool
    private let ownerCurrent: () -> Bool
    private let failed: (Error) -> Void
    private let pause: @MainActor () async throws -> Void
    private let now: () -> Int64
    private let client = UUID().uuidString
    private var epoch = 0
    private var lastStopEpoch = -1
    // Metadata survives admission, but never an interruption/mode/owner boundary.
    private var timingEpoch = 0
    private var owned: DictationListen?
    private var ledger: DictationPlayback?
    private var tail: Task<DictationPlayback, Error>?
    private var heartbeat: Task<Void,Never>?
    private var expiry: Task<Void,Never>?
    private var gap: Task<Void,Never>?
    private var audioCache: [Int: Data] = [:]
    public private(set) var durations: [Int: Double] = [:]
    private let measureDuration: (Data) -> Double?
    private var timingSteps: [Int] = []
    private var timingTrack = DictationTimingTrack(assets: [])
    private var timingIndex = 0
    private var stoppedPosition: Double = 0
    private var gapBegan: Double?
    private var frozenGap: Double = 0
    private var pendingGap = false
    private let timingNow: () -> Double
    private let resumePause: @MainActor (Double) async throws -> Void
    private var timingCompleted = false
    private let position: () -> Double
    private let readStop: (() -> DictationStopIntent?)?
    private let saveStop: (DictationStopIntent?) throws -> Void
    private var localStop: DictationStopIntent?
    private var admission: Task<DictationPlayback, Error>?
    private var admissionRequest: DictationPlaybackRequest?
    private var resetTask: Task<Void, Never>?
    public private(set) var explicitlyStopped = false
    private var stopIntent: DictationStopIntent? { localStop ?? readStop?() }

    public var canContinue: Bool { !explicitlyStopped && (pendingGap || ledger?.active != nil) }

    public var timing: DictationTimingSnapshot {
        timingTrack.snapshot(durations: durations, index: timingIndex,
            position: playing ? position() : stoppedPosition,
            gapElapsed: gapBegan.map { max(0, timingNow() - $0) } ?? frozenGap,
            completed: timingCompleted)
    }

    /// GET existing bytes only; no admission or synthesis. Late owners cannot publish.
    public func loadTiming() async {
        guard authorized(), let record = read() else { return }
        let ticket = timingEpoch
        if !playing && !waiting && !timingCompleted && !pendingGap && !explicitlyStopped {
            configureTiming(record)
        }
        let assets = Set((explicitlyStopped ? timingSteps : record.timingSteps).map { record.plan[$0].asset })
        for asset in assets where record.ready.contains(asset) && audioCache[asset] == nil {
            do {
                let data = try await audio(asset)
                guard ticket == timingEpoch, authorized(), !Task.isCancelled else { return }
                cache(data, asset: asset)
            } catch {
                if case APIError.http(401) = error, ownerCurrent() { failed(error) }
                // Other unavailable bytes leave duration unknown. Play reports errors.
            }
        }
    }
    private func cache(_ data: Data, asset: Int) {
        audioCache[asset] = data
        if let duration = measureDuration(data), duration.isFinite, duration > 0 { durations[asset] = duration }
    }
    private func configureTiming(_ record: DictationRecord) {
        timingSteps = record.timingSteps
        timingTrack = DictationTimingTrack(assets: timingSteps.map { record.plan[$0].asset },gapSeconds:record.repeatGap)
        timingIndex = timingSteps.firstIndex(of: record.policyStep) ?? 0
        stoppedPosition = record.playback?.active?.offset ?? 0
        gapBegan = nil; frozenGap = 0; pendingGap = false; timingCompleted = false
    }

    public init(read: @escaping () -> DictationRecord?, refresh: @escaping @MainActor () async throws -> DictationRecord,
                send: @escaping @MainActor (DictationPlaybackRequest) async throws -> DictationPlayback,
                audio: @escaping (Int) async throws -> Data, publish: @escaping (DictationPlayback) throws -> Void,
                play: @escaping (Data, Double, @escaping (Bool) -> Void) throws -> Void,
                stop: @escaping () -> Double, authorized: @escaping () -> Bool, failed: @escaping (Error) -> Void,
                ownerCurrent: (() -> Bool)? = nil,
                readStop: (() -> DictationStopIntent?)? = nil,
                saveStop: @escaping (DictationStopIntent?) throws -> Void = {_ in},
                position: @escaping () -> Double = {0},
                duration: @escaping (Data) -> Double? = {_ in nil},
                pause: @escaping @MainActor () async throws -> Void = {try await Task.sleep(for:.seconds(3))},
                timingNow: @escaping () -> Double = {ProcessInfo.processInfo.systemUptime},
                resumePause: @escaping @MainActor (Double) async throws -> Void = {try await Task.sleep(for: .seconds($0))},
                now: @escaping () -> Int64 = {Int64(Date().timeIntervalSince1970 * 1000)}) {
        self.read=read;self.refresh=refresh;self.send=send;self.audio=audio;self.publish=publish
        self.startMedia=play;self.stopMedia=stop;self.authorized=authorized;self.failed=failed
        self.ownerCurrent=ownerCurrent ?? authorized
        self.readStop=readStop;self.saveStop=saveStop
        self.explicitlyStopped=readStop?() != nil
        self.position=position;self.measureDuration=duration;self.pause=pause;self.now=now
        self.timingNow=timingNow;self.resumePause=resumePause
        if explicitlyStopped { resetToBeginning() }
    }
    private func current(_ ticket: Int) -> Bool {ticket == epoch && authorized() && !Task.isCancelled}
    private func clearTimers() {heartbeat?.cancel();expiry?.cancel();gap?.cancel();heartbeat=nil;expiry=nil;gap=nil;waiting=false}
    private func apply(_ value: DictationPlayback) throws {
        guard authorized() else {throw CancellationError()}
        if value.revision >= (ledger?.revision ?? -1) {ledger=value;try publish(value)}
    }
    /// Serializes fence-changing callbacks. A release queued behind a heartbeat
    /// uses its acknowledged fence, never the stale fence captured by the OS event.
    private func command(_ action: String, stamp: DictationListen, offset: Double) async throws -> DictationPlayback {
        let previous=tail
        let task=Task { @MainActor [self] in
            _ = try? await previous?.value
            guard authorized() else {throw CancellationError()}
            let active=ledger?.active
            let latest=active?.id == stamp.id ? active! : stamp
            let value: DictationPlayback
            do {value=try await send(DictationPlaybackRequest(id:latest.id,client:client,action:action,step:latest.step,fence:latest.fence,offset:offset,policyVersion:read()?.playbackPolicyVersion,reason:action == "release" ? "interrupted" : nil))}
            catch {if case APIError.http(401)=error,ownerCurrent() {failed(error)};throw error}
            try apply(value)
            if owned?.id == latest.id {owned=value.active}
            return value
        }
        tail=task
        return try await task.value
    }
    public func play() async {
        guard !busy,!playing,!waiting,authorized(),let initial=read(),initial.supportsPlaybackPolicy,!initial.checked else {return}
        busy=true;epoch += 1;let ticket=epoch
        defer {if ticket == epoch {busy=false}}
        do {
            await resetTask?.value
            guard current(ticket) else { return }
            if stopIntent != nil { try await finishStop() }
            guard current(ticket) else { return }
            if pendingGap {
                waiting = true; gapBegan = timingNow() - frozenGap
                try await resumePause(max(0, (read()?.repeatGap ?? 3) - frozenGap))
                guard current(ticket) else { return }
                waiting = false; pendingGap = false; gapBegan = nil; frozenGap = read()?.repeatGap ?? 3
            }
            _ = try? await tail?.value
            guard current(ticket) else {return}
            let fresh=try await refresh()
            guard current(ticket),fresh.id == initial.id,fresh.supportsPlaybackPolicy,!fresh.checked,let value=fresh.playback else {return}
            try apply(value)
            if explicitlyStopped {
                guard value.active == nil, initial.mode == "whole" || value.cursor == (fresh.playbackPolicyVersion == 2 ? 0 : 1) else { throw APIError.http(409) }
                explicitlyStopped=false
            }
            var selection=initial;selection.playback=value
            guard !selection.policyExhausted,let segment=selection.segment else {throw APIError.http(409)}
            let request: DictationPlaybackRequest
            if let active=value.active {
                request=DictationPlaybackRequest(id:active.id,client:client,action:"resume",step:active.step,fence:active.fence,policyVersion:fresh.playbackPolicyVersion)
            } else {
                request=DictationPlaybackRequest(id:UUID().uuidString,client:client,action:"start",step:selection.policyStep,fence:0,policyVersion:fresh.playbackPolicyVersion,intent:fresh.playbackPolicyVersion == 2 ? "planned" : nil)
            }
            let requestTask = Task { @MainActor in try await send(request) }
            admission = requestTask;admissionRequest=request
            let admitted=try await requestTask.value
            if admissionRequest?.id == request.id { admission = nil;admissionRequest=nil }
            guard current(ticket) else {
                // A replacement/background boundary may happen while admission is
                // in flight. Release the acknowledged reservation without playing,
                // refunding, or ending it. Never disturb a newer resume operation.
                if authorized(), ticket > lastStopEpoch, !busy, !playing, !waiting,
                   let active = admitted.active, active.id == request.id, active.client == client {
                    try apply(admitted)
                    _ = try await command("release", stamp: active, offset: active.offset)
                }
                return
            }
            try apply(admitted)
            guard let active=admitted.active,active.id == request.id,active.client == client else {throw APIError.invalidResponse}
            owned=active
            if timingSteps.contains(active.step), !timingCompleted {
                timingIndex = timingSteps.firstIndex(of: active.step) ?? 0
                stoppedPosition = active.offset; gapBegan = nil; frozenGap = 0
            } else { configureTiming(selection) }
            watch(ticket)
            let data: Data
            if let cached = audioCache[segment.asset] { data = cached }
            else { data = try await audio(segment.asset) }
            guard current(ticket),owned?.id == active.id,active.leaseUntil > now() else {return}
            cache(data, asset: segment.asset)
            try startMedia(data,active.offset) { [weak self] success in
                guard let self,self.current(ticket),self.playing else {return}
                self.playing=false
                Task { @MainActor in await self.completed(success,ticket:ticket) }
            }
            explicitlyStopped=false;playing=true
        } catch {
            // A late same-owner 401 still revokes identity, even after interruption.
            if case APIError.http(401)=error, ownerCurrent() {failed(error)}
            else if current(ticket) {await interrupt();failed(error)}
        }
    }
    private func watch(_ ticket:Int) {
        armExpiry(ticket)
        heartbeat=Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {try await Task.sleep(for:.seconds(4))} catch {return}
                guard let self,self.current(ticket),let active=self.owned else {return}
                do {_ = try await self.command("progress",stamp:active,offset:self.position());if self.current(ticket) {self.armExpiry(ticket)}}
                catch {if self.current(ticket) {await self.interrupt();self.failed(error)};return}
            }
        }
    }
    private func armExpiry(_ ticket:Int) {
        expiry?.cancel()
        let milliseconds=max(0,(ledger?.active?.leaseUntil ?? 0)-now()-250)
        expiry=Task { @MainActor [weak self] in
            do {try await Task.sleep(for:.milliseconds(milliseconds))} catch {return}
            guard let self,self.current(ticket) else {return}
            await self.interrupt();self.failed(APIError.http(409))
        }
    }
    /// Call synchronously on background/OS interruption, then await best-effort release.
    public func suspend() -> Task<Void,Never> {
        if playing { stoppedPosition = position() }
        // Freeze the gap clock. Continue waits only its remaining real seconds
        // before admitting the next sentence; background time never advances it.
        if let began = gapBegan {
            frozenGap = min(read()?.repeatGap ?? 3, max(0, timingNow() - began)); pendingGap = true
        }
        gapBegan = nil
        epoch += 1;timingEpoch += 1;clearTimers();busy=false;playing=false
        let offset=stopMedia(),active=owned;owned=nil
        return Task { @MainActor [self] in
            guard let active,authorized() else {return}
            do {_ = try await command("release",stamp:active,offset:offset)}
            catch {if case APIError.http(401)=error,authorized() {failed(error)}}
        }
    }
    public func interrupt() async {await suspend().value}

    /// User Stop is distinct from OS interruption. Silence and invalidate callbacks
    /// synchronously, then persist the reset intent before attempting any network I/O.
    public func stop() -> Task<Void, Never> {
        epoch += 1; lastStopEpoch=epoch; timingEpoch += 1; clearTimers(); busy=false; playing=false
        // An error-triggered interruption clears `owned`, but the last
        // acknowledged ledger still identifies our uncertain heartbeat.
        let acknowledgedOwned = ledger?.active.flatMap { $0.client == client ? $0.id : nil }
        let stoppedAdmission=admissionRequest?.id ?? owned?.id ?? acknowledgedOwned
        _ = stopMedia(); owned=nil
        explicitlyStopped=true; resetToBeginning()
        if let resetTask { return resetTask }
        let newIntent = stopIntent == nil
        if newIntent {
            var intent=DictationStopIntent(client:client,admission:stoppedAdmission)
            if let revision=[ledger?.revision,read()?.playback?.revision].compactMap({$0}).max() {
                intent.request=DictationPlaybackRequest(id:intent.id,client:intent.client,action:"stop",step:0,fence:revision,admission:intent.admission,policyVersion:read()?.playbackPolicyVersion)
            }
            localStop=intent
        }
        do {
            if !newIntent, let intent=stopIntent { try requireCurrentStop(intent) }
            try saveStop(stopIntent)
        }
        catch { failed(error); return Task {} }
        let pendingAdmission=admission, pendingCommand=tail, pendingIntent=stopIntent
        let task=Task { @MainActor [self] in
            let admitted = try? await pendingAdmission?.value
            let commanded = try? await pendingCommand?.value
            guard authorized() else { resetTask=nil; return }
            do {
                guard var intent=pendingIntent else { throw CancellationError() }
                try requireCurrentStop(intent)
                // Only acknowledgments of operations captured at Stop may advance
                // its target. A refresh or a retry cannot adopt a foreign revision.
                if newIntent, let revision=[admitted?.revision,commanded?.revision].compactMap({$0}).max(),
                   revision > (intent.request?.fence ?? -1) {
                    intent.request=DictationPlaybackRequest(id:intent.id,client:intent.client,action:"stop",step:0,fence:revision,admission:intent.admission,policyVersion:read()?.playbackPolicyVersion)
                    localStop=intent;try saveStop(intent)
                }
                try await finishStop()
            }
            catch { if ownerCurrent() { failed(error) } }
            resetTask=nil
        }
        resetTask=task
        return task
    }
    private func resetToBeginning() {
        stoppedPosition=0;timingIndex=0
        pendingGap=false;gapBegan=nil;frozenGap=0;timingCompleted=false
        if let record=read() {
            timingSteps = record.playbackPolicyVersion == 2 ? [0] : (record.mode == "whole" ? Array(record.plan.indices.prefix(1)) : Array(record.plan.indices.dropFirst().dropLast()))
            timingTrack = DictationTimingTrack(assets:timingSteps.map {record.plan[$0].asset})
        }
    }
    private func requireCurrentStop(_ intent: DictationStopIntent) throws {
        // A replacement controller may have consumed this operation or persisted
        // a newer Stop. Never let this controller rewrite or acknowledge that intent.
        if let readStop, readStop()?.id != intent.id { throw CancellationError() }
    }
    private func finishStop() async throws {
        guard authorized(), let intent=stopIntent else { return }
        // Retry the exact persisted operation. An intent without an observed fence
        // cannot safely acquire one from a newer ledger (including after relaunch).
        guard let request=intent.request else { throw APIError.invalidResponse }
        try requireCurrentStop(intent)
        try saveStop(intent) // retry a previously failed persistence barrier too
        let value=try await send(request)
        guard authorized() else { throw CancellationError() }
        try requireCurrentStop(intent)
        try apply(value)
        try saveStop(nil);localStop=nil
    }
    /// Explicit mode change / Check cancels the reservation without refunding starts.
    public func cancel() async throws {
        let suspension=suspend(), ticket=epoch
        busy=true
        defer { if ticket == epoch { busy=false } }
        await suspension.value
        await resetTask?.value
        guard current(ticket) else { throw CancellationError() }
        if stopIntent != nil { try await finishStop() }
        guard current(ticket) else { throw CancellationError() }
        timingCompleted=false; pendingGap=false; frozenGap=0; timingSteps=[]; timingTrack=DictationTimingTrack(assets: [])
        let fresh:DictationRecord
        do {fresh=try await refresh()}
        catch {if case APIError.http(401)=error,ownerCurrent() {failed(error)};throw error}
        guard current(ticket) else { throw CancellationError() }
        if let value=fresh.playback {try apply(value)}
        if let active=ledger?.active {
            let resumed=try await command("resume",stamp:active,offset:active.offset)
            guard current(ticket) else { throw CancellationError() }
            if let latest=resumed.active {_ = try await command("cancel",stamp:latest,offset:latest.offset)}
        }
    }
    private func completed(_ success:Bool,ticket:Int) async {
        guard current(ticket),let active=owned else {return}
        if !success {await interrupt();failed(APIError.invalidResponse);return}
        if timingTrack.assets.indices.contains(timingIndex) {
            stoppedPosition = durations[timingTrack.assets[timingIndex]] ?? position()
        }
        clearTimers();busy=true
        do {
            _ = try await command("ended",stamp:active,offset:position())
            guard current(ticket) else {return}
            owned=nil;busy=false
            guard let record=read(),let value=ledger else { return }
            let repeats = record.playbackPolicyVersion == 2 && active.intent != "extra" && value.cursor == active.step+1 && record.plan.indices.contains(value.cursor) && record.plan[value.cursor].kind == "sentence_repeat" && record.plan[value.cursor].asset == record.plan[active.step].asset
            guard repeats || (record.playbackPolicyVersion == 1 && active.step > 0 && value.cursor < record.plan.count-1) else {
                timingCompleted = true; return
            }
            waiting=true;frozenGap=0;gapBegan=timingNow()
            gap=Task { @MainActor [weak self] in
                guard let self else {return}
                do { if record.playbackPolicyVersion == 2 { try await self.resumePause(record.repeatGap) } else { try await self.pause() } } catch {return}
                guard self.current(ticket) else {return}
                self.waiting=false;self.gapBegan=nil;self.frozenGap=record.repeatGap;await self.play()
            }
        } catch {if current(ticket) {await interrupt();failed(error)}}
    }
}
