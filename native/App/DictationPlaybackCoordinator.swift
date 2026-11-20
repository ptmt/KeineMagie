import SwiftUI
import AVFoundation
import KeineMagieCore

/// One owner-scoped transport, owned by MainTabsView, never a practice destination.
/// Tab navigation has no transport lifecycle meaning. Only explicit replacement,
/// OS interruption/background, or owner revocation interrupts the current lease.
@MainActor @Observable final class DictationPlaybackCoordinator {
    let player = DictationPlayer()
    private(set) var controller: DictationPlaybackController?
    private(set) var attemptID: String?
    private(set) var preparing = false
    private(set) var busy = false
    private(set) var error: String?
    var openRequest = 0
    private weak var model: AppModel?
    private var ownerGeneration: Int?
    private var operation = 0
    private var work: Task<Void, Never>?

    var record: DictationRecord? {
        guard let model, model.session.generation == ownerGeneration,
              model.session.phase == .signedIn, let attemptID else { return nil }
        return model.dictationDrafts.record(attemptID)
    }
    var visible: Bool {
        guard let record, record.segment != nil else { return false }
        return preparing || cached(record)
    }
    var ticking: Bool { player.playing || controller?.waiting == true }
    var canStop: Bool { !preparing && (player.playing || busy || controller?.busy == true || controller?.waiting == true) }
    var status: String {
        if player.playing { return "dictation.player.playing" }
        if preparing || busy || controller?.busy == true { return "dictation.player.loading" }
        if controller?.waiting == true { return "dictation.player.gap" }
        if controller?.explicitlyStopped == true { return "dictation.player.stopped" }
        return "dictation.player.ready"
    }
    func stop() {
        operation += 1; work?.cancel(); work=nil
        if let controller { _ = controller.stop() }
        player.stop(resetTiming:true);busy=false;preparing=false
    }
    var disabled: Bool {
        guard let value = record else { return true }
        return model?.session.canWrite != true || busy || player.playing || controller?.busy == true || controller?.waiting == true ||
            (value.supportsPlaybackPolicy && (value.checked || value.policyExhausted)) ||
            (value.playbackPolicyVersion != nil && !value.supportsPlaybackPolicy)
    }
    var label: String {
        guard let value = record else { return "Play" }
        if preparing { return "Preparing audio…" }
        if value.needsManualNext { return "Next" }
        if !cached(value) { return "Prepare audio" }
        if controller?.waiting == true { return "dictation.pause" }
        if player.playing { return "dictation.listening" }
        if controller?.explicitlyStopped != true && value.supportsPlaybackPolicy && (value.playback?.active != nil || controller?.canContinue == true) { return "dictation.resume" }
        return value.segment?.kind == "final" ? "Optional final reading" : "Play"
    }
    var timing: DictationTimingSnapshot? {
        guard let value = record, let segment = value.segment else { return nil }
        if value.supportsPlaybackPolicy { return controller?.timing }
        return DictationTimingTrack(assets:[segment.asset]).snapshot(
            durations:player.duration.map { [segment.asset:$0] } ?? [:], index:0, position:player.position)
    }
    func cached(_ value: DictationRecord) -> Bool {
        let assets = value.supportsPlaybackPolicy ? value.policyAssets : value.segment.map { [$0.asset] } ?? []
        return !assets.isEmpty && assets.allSatisfy { value.ready.contains($0) }
    }
    func select(_ value: DictationRecord, model: AppModel) {
        if ownerGeneration != model.session.generation { reset() }
        self.model = model; ownerGeneration = model.session.generation
        guard attemptID != value.id else { return }
        // suspend stops synchronously; its retained controller finishes the old
        // interrupted release against its own ID even after selection changes.
        interrupt()
        controller = nil; player.stop(resetTiming:true)
        attemptID = value.id; error = nil
        if value.supportsPlaybackPolicy { controller = makeController(value, model:model) }
    }
    func loadTiming() async { await controller?.loadTiming() }
    func requestOpen() { guard record != nil else { return }; openRequest += 1 }
    func interrupt() {
        operation += 1; work?.cancel(); work = nil
        _ = controller?.suspend()
        player.stop(); busy = false; preparing = false
    }
    func reset() {
        interrupt(); controller = nil; player.stop(resetTiming:true)
        attemptID = nil; ownerGeneration = nil; model = nil; error = nil
    }
    func activate() {
        guard !disabled, let value = record, let model, let api = try? model.podcastAPI() else { return }
        if cached(value), value.supportsPlaybackPolicy {
            let controller = controller
            Task { await controller?.play() }
            return
        }
        let generation = model.session.generation, id = value.id
        operation += 1; let ticket = operation
        let prepare = !cached(value)
        busy = true; preparing = prepare; error = nil
        work = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.operation == ticket { self.busy = false; self.preparing = false } }
            let current = { self.operation == ticket && model.session.generation == generation && model.session.canWrite && self.attemptID == id && !Task.isCancelled }
            do {
                if prepare {
                    let assets = value.supportsPlaybackPolicy ? value.policyAssets : value.segment.map { [$0.asset] } ?? []
                    for asset in assets where !value.ready.contains(asset) {
                        guard current() else { return }
                        _ = try await api.dictationAudio(id:id,index:asset,prepare:true)
                        guard current(), var latest = model.dictationDrafts.record(id) else { return }
                        if !latest.ready.contains(asset) { latest.ready.append(asset) }
                        try model.dictationDrafts.update(latest)
                    }
                    if current() { await self.controller?.loadTiming() }
                } else if let segment = value.segment {
                    let data = try await api.dictationAudio(id:id,index:segment.asset,prepare:false)
                    guard current() else { return }
                    try self.player.play(data)
                    self.player.finished = { [weak self] success in
                        guard let self, current(), success, var latest = model.dictationDrafts.record(id) else { return }
                        latest.transition(.ended); try? model.dictationDrafts.update(latest)
                        self.player.finished = nil
                    }
                }
            } catch { self.failed(error, model:model, generation:generation, id:id) }
        }
    }
    private func failed(_ failure: Error, model: AppModel, generation: Int, id: String) {
        guard model.session.generation == generation else { return }
        if case APIError.http(401) = failure {
            model.session.rejectUnauthorized(); model.resetSessionContent(); reset()
        } else if attemptID == id {
            if case APIError.http(404) = failure {
                if var latest = model.dictationDrafts.record(id), let asset = latest.segment?.asset {
                    latest.ready.removeAll { $0 == asset }; try? model.dictationDrafts.update(latest)
                }
                error = AppL10n.text("Saved audio unavailable. Prepare it again.")
            } else if case APIError.http(409) = failure { error = AppL10n.text("dictation.playback.conflict") }
            else if !(failure is CancellationError) { error = AppL10n.text(controller?.explicitlyStopped == true ? "dictation.player.resetPending" : "dictation.continue") }
        }
    }
    private func makeController(_ value: DictationRecord, model: AppModel) -> DictationPlaybackController? {
        guard let api = try? model.podcastAPI() else { return nil }
        let generation = model.session.generation, id = value.id
        let player = player, owner = model.session.user?.id
        return DictationPlaybackController(
            read:{ [weak model] in model?.dictationDrafts.record(id) },
            refresh:{ try await api.dictation(id:id) },
            send:{ try await api.dictationPlayback(id:id,command:$0,owner:owner) },
            audio:{ try await api.dictationAudio(id:id,index:$0,prepare:false) },
            publish:{ [weak model] ledger in
                guard let model, model.session.generation == generation, model.session.canWrite else { throw CancellationError() }
                try model.dictationDrafts.acceptPlayback(id:id,policy:value.playbackPolicyVersion ?? 1,ledger:ledger)
            }, play:{ [weak self] data, offset, completion in
                guard let self, self.attemptID == id, self.record != nil else { throw CancellationError() }
                try player.play(data,offset:offset); player.finished = completion
            }, stop:{ let offset = player.position; player.stop(); return offset },
            authorized:{ [weak self, weak model] in self?.ownerGeneration == generation && model?.session.generation == generation && model?.session.canWrite == true && model?.dictationDrafts.record(id) != nil },
            failed:{ [weak self, weak model] failure in
                guard let model else { return }; self?.failed(failure,model:model,generation:generation,id:id)
            }, ownerCurrent:{ [weak model] in model?.session.generation == generation },
            readStop:{ [weak model] in model?.dictationDrafts.playbackStop(id:id) },
            saveStop:{ [weak model] intent in
                guard let model, model.session.generation == generation else { throw CancellationError() }
                try model.dictationDrafts.setPlaybackStop(id:id,intent:intent)
            },
            position:{ player.position }, duration:{ (try? AVAudioPlayer(data:$0))?.duration })
    }
}
