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

    public var canContinue: Bool { pendingGap || ledger?.active != nil }

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
        if !playing && !waiting && !timingCompleted && !pendingGap {
            configureTiming(record)
        }
        let assets = Set(record.timingSteps.map { record.plan[$0].asset })
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
        timingTrack = DictationTimingTrack(assets: timingSteps.map { record.plan[$0].asset })
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
                position: @escaping () -> Double = {0},
                duration: @escaping (Data) -> Double? = {_ in nil},
                pause: @escaping @MainActor () async throws -> Void = {try await Task.sleep(for:.seconds(3))},
                timingNow: @escaping () -> Double = {ProcessInfo.processInfo.systemUptime},
                resumePause: @escaping @MainActor (Double) async throws -> Void = {try await Task.sleep(for: .seconds($0))},
                now: @escaping () -> Int64 = {Int64(Date().timeIntervalSince1970 * 1000)}) {
        self.read=read;self.refresh=refresh;self.send=send;self.audio=audio;self.publish=publish
        self.startMedia=play;self.stopMedia=stop;self.authorized=authorized;self.failed=failed
        self.ownerCurrent=ownerCurrent ?? authorized
        self.position=position;self.measureDuration=duration;self.pause=pause;self.now=now
        self.timingNow=timingNow;self.resumePause=resumePause
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
            do {value=try await send(DictationPlaybackRequest(id:latest.id,client:client,action:action,step:latest.step,fence:latest.fence,offset:offset))}
            catch {if case APIError.http(401)=error,ownerCurrent() {failed(error)};throw error}
            try apply(value)
            if owned?.id == latest.id {owned=value.active}
            return value
        }
        tail=task
        return try await task.value
    }
    public func play() async {
        guard !busy,!playing,!waiting,authorized(),let initial=read(),initial.playbackPolicyVersion == 1,!initial.checked else {return}
        busy=true;epoch += 1;let ticket=epoch
        defer {if ticket == epoch {busy=false}}
        do {
            if pendingGap {
                waiting = true; gapBegan = timingNow() - frozenGap
                try await resumePause(max(0, 3 - frozenGap))
                guard current(ticket) else { return }
                waiting = false; pendingGap = false; gapBegan = nil; frozenGap = 3
            }
            _ = try? await tail?.value
            guard current(ticket) else {return}
            let fresh=try await refresh()
            guard current(ticket),fresh.id == initial.id,fresh.playbackPolicyVersion == 1,!fresh.checked,let value=fresh.playback else {return}
            try apply(value)
            var selection=initial;selection.playback=value
            guard !selection.policyExhausted,let segment=selection.segment else {throw APIError.http(409)}
            let request: DictationPlaybackRequest
            if let active=value.active {
                request=DictationPlaybackRequest(id:active.id,client:client,action:"resume",step:active.step,fence:active.fence)
            } else {
                request=DictationPlaybackRequest(id:UUID().uuidString,client:client,action:"start",step:selection.policyStep,fence:0)
            }
            let admitted=try await send(request)
            guard current(ticket) else {return} // GET resolves uncertain admission on Continue.
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
            playing=true
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
            frozenGap = min(3, max(0, timingNow() - began)); pendingGap = true
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
    /// Explicit mode change / Check cancels the reservation without refunding starts.
    public func cancel() async throws {
        await interrupt()
        timingCompleted=false; pendingGap=false; frozenGap=0; timingSteps=[]; timingTrack=DictationTimingTrack(assets: [])
        guard authorized() else {throw CancellationError()}
        let fresh:DictationRecord
        do {fresh=try await refresh()}
        catch {if case APIError.http(401)=error,ownerCurrent() {failed(error)};throw error}
        if let value=fresh.playback {try apply(value)}
        if let active=ledger?.active {
            let resumed=try await command("resume",stamp:active,offset:active.offset)
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
            guard active.step > 0,let record=read(),let value=ledger,value.cursor < record.plan.count-1 else {
                timingCompleted = true; return
            }
            waiting=true;frozenGap=0;gapBegan=timingNow()
            gap=Task { @MainActor [weak self] in
                guard let self else {return}
                do {try await self.pause()} catch {return}
                guard self.current(ticket) else {return}
                self.waiting=false;self.gapBegan=nil;self.frozenGap=3;await self.play()
            }
        } catch {if current(ticket) {await interrupt();failed(error)}}
    }
}
