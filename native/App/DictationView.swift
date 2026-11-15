import SwiftUI
import AVFoundation
import KeineMagieCore

@MainActor @Observable final class DictationPlayer: NSObject, AVAudioPlayerDelegate {
    var playing = false
    var rate: Float = 1
    var finished: (() -> Void)?
    private var player: AVAudioPlayer?
    private var generation = 0
    func play(_ data: Data) throws {
        stop()
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)
        let next = try AVAudioPlayer(data: data)
        next.enableRate = true; next.rate = rate; next.delegate = self
        guard next.prepareToPlay(), next.play() else { throw APIError.invalidResponse }
        player = next; playing = true
    }
    func pause() { player?.pause(); playing = false }
    func stop() { generation += 1; finished = nil; player?.stop(); player = nil; playing = false; try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in guard let self, self.player === player else { return }; self.playing = false; if flag { self.finished?() } }
    }
}

struct DictationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    @Binding var showAdd: Bool
    @State private var items: [DictationRecord] = []
    @State private var record: DictationRecord?
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var title = ""
    @State private var original = ""
    @State private var player = DictationPlayer()
    @State private var task: Task<Void, Never>?
    @State private var saveTask: Task<Void, Never>?
    @State private var epoch = 0
    @State private var saving = false
    @State private var saveFence = DictationSaveFence()
    @State private var draftVersion = 0
    @State private var confirmDelete = false
    var body: some View {
        Group {
            if let value = record { practice(value) }
            else {
                List {
                    if !loaded { ProgressView() }
                    if loaded && items.isEmpty { Text("No dictations yet.").foregroundStyle(.secondary) }
                    ForEach(items) { item in
                        Button { if let cached = model.dictationDrafts.record(item.id) { record = cached }; perform { api, current in let value = try await api.dictation(id: item.id); if current() { try accept(value) } } } label: {
                            VStack(alignment: .leading) { Text(item.title); Text(AppL10n.text(item.checked ? "Checked" : "In progress")).font(.caption).foregroundStyle(.secondary) }
                        }.accessibilityIdentifier("dictation-row")
                    }
                    ForEach(model.dictationDrafts.recoveries) { recovery in
                        VStack(alignment: .leading) {
                            Text(recovery.title).font(.headline)
                            Text("Deleted on another device · draft saved locally").font(.caption)
                            ShareLink("Export draft", item: recovery.draft)
                        }.accessibilityIdentifier("dictation-recovery")
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                    Button("Refresh") { load() }.disabled(busy)
                }.refreshable { load() }
            }
        }
        .task(id: model.session.generation) { clear(); load() }
        .onChange(of: phase) { _, next in if next != .active { cancelTransport();save() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in cancelTransport() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in cancelTransport() }
        .onDisappear { cancelTransport();player.stop();save() }
        .confirmationDialog("Delete this attempt and its draft?", isPresented: $confirmDelete) {
            Button("Delete attempt", role: .destructive) {
                guard let value = record else { return }
                save { perform { api, current in
                    guard let latest = record else { return }
                    try await api.deleteDictation(id:value.id,revision:latest.revision)
                    guard current() else { return }
                    try model.dictationDrafts.remove(value.id); record = nil
                    items.removeAll { $0.id == value.id }
                } }
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    TextField("Title", text: Binding(get:{title},set:{title=$0;saveAddForm()})).disabled(model.dictationDrafts.addForm.pending != nil).accessibilityIdentifier("dictation-title")
                    Picker("Text language", selection: .constant("de")) { Text(verbatim: "Deutsch").tag("de") }
                    TextEditor(text: Binding(get:{original},set:{original=$0;saveAddForm()})).disabled(model.dictationDrafts.addForm.pending != nil).frame(minHeight: 180).accessibilityIdentifier("dictation-original")
                    Text("German · up to 1800 characters / 300 words. Computer-generated voice.").font(.footnote)
                    if let error { Text(error).font(.footnote) }
                }.navigationTitle("Add text").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showAdd = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("Save") {
                            perform { api, current in
                                let body = try model.dictationDrafts.pendingCreate()
                                let value: DictationRecord
                                do { value = try await api.dictation(method:"POST",body:body) }
                                catch APIError.http(400) {
                                    if current() { try model.dictationDrafts.rejectCreate();self.error = AppL10n.text("Use German text up to 1800 characters / 300 words and a title up to 80 characters.") }
                                    return
                                }
                                guard current() else { return }
                                try model.dictationDrafts.finishCreate(value); record = model.dictationDrafts.record(value.id); title = ""; original = ""; showAdd = false
                            }
                        }.disabled(busy || title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || original.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || original.unicodeScalars.count > 1800).accessibilityIdentifier("dictation-create") }
                    }
            }
        }
    }
    private func practice(_ value: DictationRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button("History") { player.stop(); save { record = nil; load() } }
                Text(value.title).font(.headline)
                HStack {
                    Button("New attempt") { save { perform { api,current in
                        let body = try model.dictationDrafts.pendingAttempt(source:value.id)
                        let next = try await api.dictation(id:value.id,action:"attempts",method:"POST",body:body)
                        guard current() else { return };try model.dictationDrafts.finishAttempt(source:value.id,value:next);record = model.dictationDrafts.record(next.id)
                    } } }.disabled(busy || saving || !model.session.canWrite)
                    Button("Delete attempt") { confirmDelete = true }.disabled(busy || saving || !model.session.canWrite)
                }
                Picker("Mode", selection: Binding(get:{record?.mode ?? "whole"},set:{ mode in transition(mode == "whole" ? .whole : .sentences) })) {
                    Text("Whole text").tag("whole"); Text("By sentences").tag("sentences")
                }.pickerStyle(.segmented).disabled(value.checked || busy || saving).accessibilityIdentifier("dictation-mode")
                if value.assisted { Text("With hint · assisted").font(.caption) }
                if let segment = value.segment {
                    Text(AppL10n.text(stage(segment.kind))).font(.callout)
                    Text(value.mode == "whole" ? AppL10n.text("readings").replacingOccurrences(of:"{n}",with:String(value.replays)) : AppL10n.text("step").replacingOccurrences(of:"{n}",with:String(value.step+1)).replacingOccurrences(of:"{total}",with:String(value.plan.count))).font(.caption).foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack { playback(value, segment) }
                        VStack(alignment: .leading) { playback(value, segment) }
                    }
                    Picker("Speed", selection: $player.rate) { Text(verbatim: "0.75×").tag(Float(0.75));Text(verbatim: "1×").tag(Float(1));Text(verbatim: "1.25×").tag(Float(1.25)) }.pickerStyle(.segmented).accessibilityIdentifier("dictation-speed")
                    if !value.checked && value.mode == "sentences" && value.step < value.plan.count - 1 { Button("Next") { transition(.next) }.disabled(busy || saving).accessibilityIdentifier("dictation-next") }
                }
                TextField("What you heard", text: Binding(get:{record?.draft ?? ""},set:{ draft in
                    record?.draft = String(draft.prefix(2400));if let record { do { try model.dictationDrafts.update(record) } catch { self.error = AppL10n.text("Not saved. Retry before leaving.") } };draftVersion += 1;saveTask?.cancel();saveTask = Task { try? await Task.sleep(for:.milliseconds(700));if !Task.isCancelled { save() } }
                }),axis:.vertical).lineLimit(6...14).autocorrectionDisabled().textInputAutocapitalization(.never).padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius:8)).disabled(value.checked || busy).accessibilityIdentifier("dictation-draft")
                if !value.checked {
                    HStack { Button("Check") { action("check") }.disabled(value.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || busy || saving).accessibilityIdentifier("dictation-check")
                        Button("Show original · mark assisted") { action("reveal") }.disabled(busy || saving) }
                }
                if let server = model.dictationDrafts.conflict(value.id) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Draft conflict").font(.headline)
                        Text("Your draft").font(.caption); Text(value.draft).textSelection(.enabled)
                        Text("Server draft").font(.caption); Text(server.draft).textSelection(.enabled)
                        ShareLink("Export draft", item: value.draft)
                        HStack {
                            Button("Rebase my draft") { do { try model.dictationDrafts.rebase(value.id);record=model.dictationDrafts.record(value.id);save() } catch { self.error=AppL10n.text("Not saved. Retry before leaving.") } }.disabled(server.checked)
                            Button("Use server draft") { do { try model.dictationDrafts.useServer(value.id);record=model.dictationDrafts.record(value.id) } catch { self.error=AppL10n.text("Not saved. Retry before leaving.") } }
                        }
                    }.accessibilityIdentifier("dictation-conflict")
                }
                if let text = value.text { Text("Original").font(.headline); Text(text).textSelection(.enabled).accessibilityIdentifier("dictation-revealed") }
                if value.checked {
                    Text("Exact text comparison, not a language-level assessment.").font(.caption)
                    if value.differences?.isEmpty != false { Text("Matches the original.") }
                    ForEach(Array((value.differences ?? []).enumerated()), id: \.offset) { _, d in Text(verbatim: "\(AppL10n.text(d.kind)): \(d.original.isEmpty ? "—" : d.original) → \(d.written.isEmpty ? "—" : d.written)").font(.callout) }
                }
                if busy { HStack { ProgressView(); Button("Cancel") { cancelTransport();player.stop() } } }
                if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            }.padding()
        }.scrollDismissesKeyboard(.interactively)
    }
    @ViewBuilder private func playback(_ value: DictationRecord, _ segment: DictationSegment) -> some View {
        Text("dictation.paid.notice").font(.caption).foregroundStyle(.secondary)
        Button("Prepare audio") { perform { api, current in
            _ = try await api.dictationAudio(id:value.id,index:segment.asset,prepare:true)
            guard current() else { return }
            record?.ready.append(segment.asset)
        } }.disabled(busy || value.ready.contains(segment.asset)).accessibilityIdentifier("dictation-prepare")
        Button("Play / repeat") { perform { api, current in
            let data = try await api.dictationAudio(id:value.id,index:segment.asset,prepare:false)
            try Task.checkCancellation()
            guard current(), phase == .active, model.session.canWrite else { return }
            try player.play(data)
            player.finished = { if current() { transition(.ended) } }
        } }.disabled(busy || !value.ready.contains(segment.asset)).accessibilityIdentifier("dictation-play")
        Button("Pause") { player.pause() }.accessibilityIdentifier("dictation-pause")
    }
    private func cancelTransport() { task?.cancel();task=nil;epoch += 1;busy=false;player.pause() }
    private func stage(_ kind: String) -> String { ["whole":"Listen to the whole text","sentence":"Listen to the sentence","chunk":"Listen to this part","sentence_repeat":"Listen to the sentence again","final":"Optional final reading"][kind] ?? "Listen" }
    private func transition(_ event: DictationEvent) { player.stop();record?.transition(event);if let record { do { try model.dictationDrafts.update(record) } catch { self.error = AppL10n.text("Not saved. Retry before leaving.") } };save() }
    private func clear() { epoch += 1;saveFence.reset();task?.cancel();saveTask?.cancel();player.stop();items=[];record=nil;title="";original="";error=nil;busy=false;saving=false;loaded=false;showAdd=false }
    private func saveAddForm() { do { try model.dictationDrafts.editAdd(title:title,original:original) } catch { self.error=AppL10n.text("Not saved. Retry before leaving.") } }
    private func accept(_ value: DictationRecord) throws { try model.dictationDrafts.accept(value);record = model.dictationDrafts.record(value.id) }
    private func load() {
        do { try model.hydrateDictations();title=model.dictationDrafts.addForm.title;original=model.dictationDrafts.addForm.original;items = model.dictationDrafts.records;loaded = true } catch { self.error = AppL10n.text("Not saved. Retry before leaving.");return }
        perform { api, current in let value = try await api.dictations().items; if current() { try model.dictationDrafts.reconcile(value);items = value; loaded = true;if let selected=record,model.dictationDrafts.record(selected.id)==nil {player.stop();record=nil} } }
    }
    private func save(_ completion: @escaping @MainActor () -> Void = {}) {
        guard !saving, !busy else { return }
        guard let value=record,!value.checked else { completion();return }
        do { try model.dictationDrafts.update(value) } catch { self.error=AppL10n.text("Not saved. Retry before leaving.");return }
        guard model.session.canWrite, let api=try? model.podcastAPI() else { completion();return }
        guard let ticket=saveFence.begin() else { return }
        let generation=model.session.generation, version=draftVersion
        saving=true
        Task { @MainActor in
            defer { if saveFence.finish(ticket) {saving=false} }
            do {
                guard saveFence.isCurrent(ticket),model.session.generation==generation,record?.id==value.id else{return}
                try await model.dictationDrafts.flushRecoveringDeletion(id:value.id) { id,body in try await api.dictation(id:id,method:"PUT",body:body) }
                guard let updated=model.dictationDrafts.record(value.id) else { return }
                guard saveFence.isCurrent(ticket),model.session.generation==generation,record?.id==value.id else{return}
                record?.revision=updated.revision
                if version==draftVersion { _=saveFence.finish(ticket);saving=false;completion() }
                else { Task { @MainActor in await Task.yield();save(completion) } }
            } catch { if saveFence.isCurrent(ticket) && generation==model.session.generation && model.session.canWrite {
                if case APIError.http(401) = error { model.session.rejectUnauthorized();model.resetSessionContent();clear() }
                else if case APIError.http(404) = error {
                    record=nil;items.removeAll { $0.id==value.id }
                }
                else if case APIError.http(409) = error { await resolveConflict(id:value.id,api:api,current:{ saveFence.isCurrent(ticket) && model.session.generation==generation }) }
                else { self.error=AppL10n.text("Not saved. Retry before leaving.") }
            } }
        }
    }
    private func action(_ action: String) {
        player.stop();guard let value=record else{return}
        guard model.dictationDrafts.conflict(value.id)==nil else {self.error=AppL10n.text("Draft conflict");return}
        perform { api, current in
            try model.dictationDrafts.update(value)
            try await model.dictationDrafts.flush(id:value.id) { id,body in try await api.dictation(id:id,method:"PUT",body:body) }
            guard current() else { return }; record = model.dictationDrafts.record(value.id)
            let checked = try await api.dictation(id:value.id,action:action,method:"POST",body:JSONEncoder().encode(["revision":record?.revision ?? value.revision]))
            if current() { try accept(checked) }
        }
    }
    private func resolveConflict(id:String,api:PodcastAPI,current: @escaping @MainActor () -> Bool) async {
        do {
            let server=try await api.dictation(id:id)
            guard current() else { return }
            try model.dictationDrafts.markConflict(id:id,server:server)
            self.error=AppL10n.text("Draft conflict")
        } catch {
            guard current() else { return }
            if case APIError.http(401) = error {
                model.session.rejectUnauthorized();model.resetSessionContent();clear()
            } else if case APIError.http(404) = error {
                do { try model.dictationDrafts.reconcileDeleted(id);if current() {record=nil;items.removeAll { $0.id==id }} }
                catch { self.error=AppL10n.text("Not saved. Retry before leaving.") }
            } else { self.error=AppL10n.text("conflict") }
        }
    }
    private func perform(_ operation: @escaping @MainActor (PodcastAPI, @escaping @MainActor () -> Bool) async throws -> Void) {
        guard !busy,!saving,model.session.canWrite,let api=try? model.podcastAPI() else{return}
        let generation=model.session.generation,current=epoch
        busy=true;error=nil
        task=Task { @MainActor in
            defer { if epoch==current {busy=false} }
            guard !Task.isCancelled,generation == model.session.generation,current == epoch,model.session.canWrite else{return}
            do { try await operation(api, { !Task.isCancelled && generation == model.session.generation && current == epoch && model.session.canWrite }) }
            catch { if epoch==current && generation==model.session.generation && model.session.canWrite && !Task.isCancelled {
                if case APIError.http(401) = error { model.session.rejectUnauthorized();model.resetSessionContent();clear() }
                else if case APIError.http(409) = error,let id=record?.id { await resolveConflict(id:id,api:api,current:{ epoch==current && generation==model.session.generation }) }
                else if case APIError.http(404) = error,let id=record?.id {
                    do {try model.dictationDrafts.reconcileDeleted(id);record=nil;items.removeAll{$0.id==id}}
                    catch {self.error=AppL10n.text("Not saved. Retry before leaving.")}
                }
                else { self.error = AppL10n.text("Could not complete. Check your connection or speech-engine availability, then retry.") }
            } }
            if generation != model.session.generation && epoch == current { clear() }
        }
    }
}
