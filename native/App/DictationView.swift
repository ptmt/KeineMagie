import SwiftUI
import AVFoundation
import KeineMagieCore

@MainActor @Observable final class DictationPlayer: NSObject, AVAudioPlayerDelegate {
    var playing = false
    var rate: Float = 1 {didSet {player?.rate=rate}}
    var finished: ((Bool) -> Void)?
    var position: Double {player?.currentTime ?? 0}
    private var player: AVAudioPlayer?
    private var generation = 0
    func play(_ data: Data, offset: Double = 0) throws {
        stop()
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)
        let next = try AVAudioPlayer(data: data)
        next.enableRate = true; next.rate = rate; next.delegate = self
        next.currentTime=min(max(0,offset),max(0,next.duration-0.01))
        guard next.prepareToPlay(), next.play() else { throw APIError.invalidResponse }
        player = next; playing = true
    }
    func pause() { player?.pause(); playing = false }
    func stop() { generation += 1; finished = nil; player?.stop(); player = nil; playing = false; try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let completedPlayer = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == completedPlayer else { return }
            self.playing = false
            self.finished?(flag)
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let failedPlayer=ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self,let current=self.player,ObjectIdentifier(current)==failedPlayer else {return}
            self.playing=false;self.finished?(false)
        }
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
    @State private var historyConfirmed = false
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
    @State private var confirmReveal = false
    @State private var originalVisible: String?
    @State private var preparing = false
    @State private var policyPlayer: DictationPlaybackController?
    @AccessibilityFocusState private var menuAXFocused: Bool
    @FocusState private var menuFocused: Bool
    var body: some View {
        Group {
            if let value = record { practice(value) }
            else {
                List {
                    if !loaded { ProgressView() }
                    if model.session.canWrite && historyConfirmed && loaded && !busy && error == nil && items.isEmpty && model.dictationDrafts.records.isEmpty && model.dictationDrafts.recoveries.isEmpty && model.dictationDrafts.addForm.title.isEmpty && model.dictationDrafts.addForm.original.isEmpty && model.dictationDrafts.addForm.pending == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No dictations yet.")
                            Text("dictation.onboarding").font(.callout)
                            Button("Add text") { showAdd = true }
                                .buttonStyle(.borderedProminent).frame(minHeight: 44)
                                .accessibilityIdentifier("dictation-empty-create")
                        }.foregroundStyle(.secondary)
                    }
                    if model.session.canWrite && (!model.dictationDrafts.addForm.title.isEmpty || !model.dictationDrafts.addForm.original.isEmpty || model.dictationDrafts.addForm.pending != nil) {
                        Button {
                            title = model.dictationDrafts.addForm.title
                            original = model.dictationDrafts.addForm.original
                            showAdd = true
                        } label: {
                            VStack(alignment: .leading) {
                                if !model.dictationDrafts.addForm.title.isEmpty { Text(model.dictationDrafts.addForm.title) }
                                Text(AppL10n.text("In progress")).font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("dictation-resume-create")
                    }

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
                }.refreshable { load(); await task?.value }
            }
        }
        .task(id: model.session.generation) { clear(); load() }
        .onChange(of: phase) { _, next in if next != .active { cancelTransport();save() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in cancelTransport() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in cancelTransport() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)) { _ in cancelTransport() }
        .onChange(of: record?.id) { _, _ in _=policyPlayer?.suspend();policyPlayer=nil;player.stop();originalVisible=nil }
        .onDisappear { cancelTransport();player.stop();save() }
        .confirmationDialog("Showing the original counts as help for this attempt. Continue?", isPresented:$confirmReveal,titleVisibility:.visible) {
            Button("Show original") {action("reveal")}
            Button("Cancel",role:.cancel) {menuAXFocused=true;menuFocused=true}
        }
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
                Button { cancelTransport();save { record = nil; load() } } label: {Label("History",systemImage:"chevron.left").frame(minHeight:44)}.buttonStyle(.plain).foregroundStyle(.secondary)
                HStack(alignment:.firstTextBaseline) {
                    Text(value.title).font(.headline).frame(maxWidth:.infinity,alignment:.leading)
                    Menu {
                    Button("New attempt") { save { perform { api,current in
                        let body = try model.dictationDrafts.pendingAttempt(source:value.id)
                        let next = try await api.dictation(id:value.id,action:"attempts",method:"POST",body:body)
                        guard current() else { return };try model.dictationDrafts.finishAttempt(source:value.id,value:next);record = model.dictationDrafts.record(next.id)
                    } } }.disabled(busy || saving || !model.session.canWrite)
                    Button("Delete attempt",role:.destructive) { confirmDelete = true }.disabled(busy || saving || !model.session.canWrite)
                    if !(value.text != nil && (value.assisted || originalVisible == value.id)) {
                        Button("Show original") {
                            if value.checked {originalVisible=value.id;menuAXFocused=true;menuFocused=true}
                            else {confirmReveal = true}
                        }.disabled(busy || saving).accessibilityIdentifier("dictation-reveal")
                    }
                    } label: {Label("More options", systemImage: "ellipsis").labelStyle(.iconOnly).frame(width:44,height:44)}
                    .accessibilityIdentifier("dictation-menu").accessibilityFocused($menuAXFocused).focused($menuFocused)
                }
                Picker("Mode", selection: Binding(get:{record?.mode ?? "whole"},set:{ mode in transition(mode == "whole" ? .whole : .sentences) })) {
                    Text("Whole text").tag("whole"); Text("By sentences").tag("sentences")
                }.pickerStyle(.segmented).disabled(value.checked || busy || saving || policyPlayer?.busy == true).accessibilityIdentifier("dictation-mode")
                DictationRules(record:value)
                if value.assisted { Text("With hint · assisted").font(.caption) }
                if let segment = value.segment {
                    if value.playbackPolicyVersion == 1 {
                        Text(AppL10n.text("dictation.listens").replacingOccurrences(of:"{n}",with:String(value.playback?.wholeStarts ?? 0)).replacingOccurrences(of:"{total}",with:"4")).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("dictation-starts")
                        if value.mode == "sentences" {Text(AppL10n.text("dictation.policy.step").replacingOccurrences(of:"{n}",with:String(value.policyStep)).replacingOccurrences(of:"{total}",with:String(max(1,value.plan.count-1)))).font(.caption).foregroundStyle(.secondary)}
                    }
                    playback(value,segment)
                    if value.playbackPolicyVersion == 1 && (value.playback?.wholeStarts ?? 0) >= 4 {Text("dictation.limit").font(.footnote).foregroundStyle(.secondary)}
                    if value.playbackPolicyVersion == nil && !value.checked && value.mode == "sentences" && value.step < value.plan.count - 1 { Button("Next") { transition(.next) }.disabled(busy || saving).accessibilityIdentifier("dictation-next") }
                }
                if !value.checked {
                    HStack { Spacer(); Button("Check") { action("check") }.buttonStyle(.borderedProminent).tint(.primary).foregroundStyle(Color(uiColor:.systemBackground)).frame(minHeight:44).disabled(value.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || busy || saving).accessibilityIdentifier("dictation-check") }
                }
                TextField("", text: Binding(get:{record?.draft ?? ""},set:{ draft in
                    record?.draft = String(draft.prefix(2400));if let record { do { try model.dictationDrafts.update(record) } catch { self.error = AppL10n.text("Not saved. Retry before leaving.") } };draftVersion += 1;saveTask?.cancel();saveTask = Task { try? await Task.sleep(for:.milliseconds(700));if !Task.isCancelled { save() } }
                }),axis:.vertical).lineLimit(6...14).autocorrectionDisabled().textInputAutocapitalization(.never).padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(.quaternary,lineWidth:1)).disabled(value.checked || (busy && !preparing)).accessibilityLabel("What you heard").accessibilityIdentifier("dictation-draft")
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
                if let text = value.text, value.assisted || originalVisible == value.id { Text("Original").font(.headline); Text(text).textSelection(.enabled).accessibilityIdentifier("dictation-revealed") }
                if value.checked {
                    Text("Exact text comparison, not a language-level assessment.").font(.caption)
                    if value.differences?.isEmpty != false { Text("Matches the original.") }
                    ForEach(Array((value.differences ?? []).enumerated()), id: \.offset) { _, d in Text(verbatim: "\(AppL10n.text(d.kind)): \(d.original.isEmpty ? "—" : d.original) → \(d.written.isEmpty ? "—" : d.written)").font(.callout) }
                }
                if busy && !preparing { ProgressView() }
                if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            }.padding()
        }.scrollDismissesKeyboard(.interactively)
    }
    private func playback(_ value: DictationRecord, _ segment: DictationSegment) -> some View {
        let policy=value.playbackPolicyVersion == 1
        let assets=policy ? value.policyAssets : [segment.asset]
        let cached=assets.allSatisfy {value.ready.contains($0)}
        let label=preparing ? "Preparing audio…" : !cached ? "Prepare audio" : policyPlayer?.waiting == true ? "dictation.pause" : player.playing ? "dictation.listening" : policy && value.playback?.active != nil ? "dictation.resume" : segment.kind == "final" ? "Optional final reading" : "Play"
        return DictationAudioToolbar(label:label,identifier:cached ? "dictation-play" : "dictation-prepare",
            disabled:busy || saving || player.playing || !model.session.canWrite || (policy && (value.checked || value.policyExhausted || policyPlayer?.busy == true || policyPlayer?.waiting == true || player.playing)) || (value.playbackPolicyVersion != nil && !policy),
            preparing:preparing,primary:value.draft.isEmpty && !value.checked,rate:$player.rate,
            activate:{
                if !cached {
                    perform { api,current in
                        preparing=true
                        defer {if current() {preparing=false}}
                        for asset in assets where !value.ready.contains(asset) {
                            guard current() else {return}
                            _ = try await api.dictationAudio(id:value.id,index:asset,prepare:true)
                            guard current() else {return}
                            record?.ready.append(asset)
                            if let record {try model.dictationDrafts.update(record)}
                        }
                        save()
                    }
                } else if policy {
                    let controller=policyController(value)
                    Task {await controller?.play()}
                } else if player.playing {player.pause()}
                else {
                    perform {api,current in
                        let data=try await api.dictationAudio(id:value.id,index:segment.asset,prepare:false)
                        guard current(),phase == .active else {return}
                        try player.play(data)
                        player.finished={success in if current(),success {transition(.ended)}}
                    }
                }
            },cancel:{cancelTransport();save()})
    }

    private func policyController(_ value:DictationRecord) -> DictationPlaybackController? {
        if let policyPlayer {return policyPlayer}
        guard let api=try? model.podcastAPI() else {return nil}
        let generation=model.session.generation,id=value.id
        let controller=DictationPlaybackController(
            read:{record?.id == id ? record : nil},refresh:{try await api.dictation(id:id)},
            send:{try await api.dictationPlayback(id:id,command:$0)},
            audio:{try await api.dictationAudio(id:id,index:$0,prepare:false)},
            publish:{ledger in
                guard record?.id == id,model.session.generation == generation else {throw CancellationError()}
                try model.dictationDrafts.acceptPlayback(id:id,policy:1,ledger:ledger)
                record?.playback=ledger
            },play:{data,offset,completion in
                guard phase == .active else {throw CancellationError()}
                try player.play(data,offset:offset);player.finished=completion
            },stop:{let offset=player.position;player.stop();return offset},
            authorized:{model.session.generation == generation && model.session.canWrite && record?.id == id},
            failed:{failure in
                guard model.session.generation == generation else {return}
                if case APIError.http(401)=failure {model.session.rejectUnauthorized();model.resetSessionContent();clear()}
                else if case APIError.http(404)=failure {
                    if let asset=record?.segment?.asset {record?.ready.removeAll {$0 == asset}}
                    if let record {try? model.dictationDrafts.update(record)}
                    error=AppL10n.text("Saved audio unavailable. Prepare it again.")
                } else if case APIError.http(409)=failure {error=AppL10n.text("dictation.playback.conflict")}
                else {error=AppL10n.text("dictation.continue")}
            },ownerCurrent:{model.session.generation == generation},position:{player.position})
        policyPlayer=controller
        return controller
    }
    private func cancelTransport() { _=policyPlayer?.suspend();task?.cancel();task=nil;epoch += 1;busy=false;preparing=false;player.pause() }
    private func transition(_ event: DictationEvent) {
        if let value=record,value.playbackPolicyVersion == 1,event == .whole || event == .sentences {
            let controller=policyController(value)
            perform {_,current in
                try await controller?.cancel()
                guard current() else {return}
                record?.transition(event)
                if let record {try model.dictationDrafts.update(record)}
            }
        } else {player.stop();record?.transition(event);if let record {do {try model.dictationDrafts.update(record)} catch {self.error=AppL10n.text("Not saved. Retry before leaving.")}};save()}
    }
    private func clear() { _=policyPlayer?.suspend();policyPlayer=nil;originalVisible=nil;preparing=false;epoch += 1;saveFence.reset();task?.cancel();saveTask?.cancel();player.stop();items=[];record=nil;title="";original="";error=nil;busy=false;saving=false;loaded=false;historyConfirmed=false;showAdd=false }
    private func saveAddForm() { do { try model.dictationDrafts.editAdd(title:title,original:original) } catch { self.error=AppL10n.text("Not saved. Retry before leaving.") } }
    private func accept(_ value: DictationRecord) throws { try model.dictationDrafts.accept(value);record = model.dictationDrafts.record(value.id) }
    private func load() {
        do { try model.hydrateDictations();title=model.dictationDrafts.addForm.title;original=model.dictationDrafts.addForm.original;items = model.dictationDrafts.records;loaded = true } catch { self.error = AppL10n.text("Not saved. Retry before leaving.");return }
        perform { api, current in let value = try await api.dictations().items; if current() { try model.dictationDrafts.reconcile(value);items = value; loaded = true;historyConfirmed = true;if let selected=record,model.dictationDrafts.record(selected.id)==nil {player.stop();record=nil} } }
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
        guard let value=record else{return}
        let controller=value.playbackPolicyVersion == 1 ? policyController(value) : nil
        guard model.dictationDrafts.conflict(value.id)==nil else {self.error=AppL10n.text("Draft conflict");return}
        perform { api, current in
            if let controller {try await controller.cancel()} else {player.stop()}
            guard current() else {return}
            try model.dictationDrafts.update(value)
            try await model.dictationDrafts.flush(id:value.id) { id,body in try await api.dictation(id:id,method:"PUT",body:body) }
            guard current() else { return }; record = model.dictationDrafts.record(value.id)
            let checked = try await api.dictation(id:value.id,action:action,method:"POST",body:JSONEncoder().encode(["revision":record?.revision ?? value.revision]))
            if current() { try accept(checked);if action == "reveal" {originalVisible=value.id;menuAXFocused=true;menuFocused=true} }
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
            defer { if epoch==current {busy=false;if record != nil {save()} } }
            guard !Task.isCancelled,generation == model.session.generation,current == epoch,model.session.canWrite else{return}
            do { try await operation(api, { !Task.isCancelled && generation == model.session.generation && current == epoch && model.session.canWrite }) }
            catch {
                if case APIError.http(401) = error,generation==model.session.generation {model.session.rejectUnauthorized();model.resetSessionContent();clear()}
                else if epoch==current && generation==model.session.generation && model.session.canWrite && !Task.isCancelled {
                if case APIError.http(409) = error,let id=record?.id { await resolveConflict(id:id,api:api,current:{ epoch==current && generation==model.session.generation }) }
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
