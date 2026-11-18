import SwiftUI
import AVFoundation
import KeineMagieCore

struct DictationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var textSize
    @Binding var showAdd: Bool
    @Binding var showSettings: Bool
    @Binding var path: [String]
    let isSelected: Bool
    private struct PhotoPresentation: Identifiable {
        let id = UUID()
        let context: DictationPhotoInsertion
    }
    @State private var photo: PhotoPresentation?
    @State private var items: [DictationRecord] = []
    @State private var record: DictationRecord?
    @State private var busy = false
    @State private var loaded = false
    @State private var historyConfirmed = false
    @State private var loadedGeneration: Int?
    @State private var error: String?
    @State private var title = ""
    @State private var original = ""
    @Environment(DictationPlaybackCoordinator.self) private var playbackSession
    private var player: DictationPlayer { playbackSession.player }
    @State private var task: Task<Void, Never>?
    @State private var saveTask: Task<Void, Never>?
    @State private var epoch = 0
    private var saving: Bool { saveFence.isSaving }
    @State private var saveFence = DictationSaveFence()
    @State private var draftVersion = 0
    @State private var confirmDelete = false
    @State private var confirmReveal = false
    @State private var originalVisible: String?
    private var preparing: Bool { playbackSession.preparing }
    private var policyPlayer: DictationPlaybackController? { playbackSession.controller }
    @AccessibilityFocusState private var menuAXFocused: Bool
    @FocusState private var menuFocused: Bool
    @FocusState private var draftFocused: Bool
    private var mediaRevision: String {
        guard let value = model.dictationDrafts.record(record?.id ?? "") else { return "" }
        return "\(value.id)-\(value.playback?.revision ?? -1)-\(value.ready)-\(value.step)"
    }
    var body: some View {
        // Each tab owns its navigation stack; RootView resets all of them on owner change.
        NavigationStack(path: $path) {
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
                        Button { if let cached = model.dictationDrafts.record(item.id) { record = cached; path = [cached.id] }; perform { api, current in let value = try await api.dictation(id: item.id); if current() { try accept(value) } } } label: {
                            VStack(alignment: .leading) { Text(item.title); Text(AppL10n.text(item.checked ? "Checked" : "In progress")).font(.caption).foregroundStyle(.secondary) }
                        }.accessibilityIdentifier("dictation-row").disabled(busy || saving)
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
                .navigationTitle("feature.dictation")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add text", systemImage: "plus") { showAdd = true }
                            .accessibilityIdentifier("dictation-add").disabled(!model.session.canWrite)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Einstellungen", systemImage: "gearshape") { showSettings = true }
                            .accessibilityIdentifier("main-settings")
                    }
                }
                .navigationDestination(for: String.self) { id in
                    if let value = record, value.id == id {
                        practice(value)
                            .navigationTitle(value.title)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar(.visible, for: .navigationBar)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) { attemptMenu(value) }
                            }
                    }
                }
        }
        .onChange(of: path) { old, next in
            if let id = next.last, record?.id != id { record = model.dictationDrafts.record(id) }
            if !old.isEmpty && next.isEmpty {
                draftFocused = false
                photo = nil
                // Back/swipe-back never waits on the network; the local draft was
                // persisted on every keystroke. Show locally created attempts even
                // when a previous save is still in flight, then refresh if possible.
                items = model.dictationDrafts.records.sorted { $0.created == $1.created ? $0.id < $1.id : $0.created > $1.created }
                save { load() }
            }
        }
        .onChange(of: isSelected) { _, selected in if !selected { photo=nil; save() } }
        .task(id: model.session.generation) {
            guard loadedGeneration != model.session.generation else { return }
            loadedGeneration = model.session.generation
            let destination = path.last
            clear(); load()
            if let destination, let saved = model.dictationDrafts.record(destination) { record = saved; path = [destination] }
        }
        .onChange(of: phase) { _, next in if next != .active { save() } }
        .onChange(of: record?.id) { _, id in
            photo = nil
            if let record { playbackSession.select(record, model:model) };originalVisible=nil
            path = id.map { [$0] } ?? []
        }
        .onDisappear { photo=nil;save() }
        .onChange(of: playbackSession.openRequest) { _, _ in
            guard let value = playbackSession.record else { return }
            // Reuse the existing destination if already open: no fetch, create, or focus reset.
            if record?.id != value.id { record = value }
            if path != [value.id] { path = [value.id] }
        }
        .onChange(of: mediaRevision) { _, _ in
            guard let latest = model.dictationDrafts.record(record?.id ?? "") else { return }
            record?.playback = latest.playback
            record?.ready = latest.ready
            record?.step = latest.step
        }
        .onChange(of: record?.checked) { _, checked in if checked == true { photo=nil } }
        .sheet(item: $photo) { presentation in
            DictationCameraSheet(ownerID: String(presentation.context.generation), attemptID: presentation.context.attempt,
                onInsert: { text, replace in
                    guard photo?.id == presentation.id, isSelected, path.last == presentation.context.attempt,
                          let current = record, !current.checked, !busy,
                          model.dictationDrafts.record(current.id) != nil,
                          model.dictationDrafts.conflict(current.id) == nil,
                          let next = presentation.context.applying(text, replacing: replace, to: current.draft,
                              generation: model.session.generation, attempt: current.id) else { return false }
                    editDraft(next)
                    photo = nil
                    return true
                }, onCancel: { if photo?.id == presentation.id { photo=nil } })
        }
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
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Mode", selection: Binding(get:{record?.mode ?? "whole"},set:{ mode in transition(mode == "whole" ? .whole : .sentences) })) {
                    Text("Whole text").tag("whole"); Text("By sentences").tag("sentences")
                }.pickerStyle(.segmented).disabled(value.checked || busy || saving || policyPlayer?.busy == true).accessibilityIdentifier("dictation-mode")
                DictationRules(record:value)
                if value.segment != nil && !playbackSession.cached(value) && !preparing {
                    HStack {
                        Button("Prepare audio", systemImage:"waveform") { playbackSession.activate() }
                            .frame(minHeight:44).accessibilityIdentifier("dictation-prepare")
                            .disabled(busy || saving || playbackSession.disabled)
                        Spacer()
                        DictationAudioInformation()
                    }
                }
                if let failure = playbackSession.error { Text(failure).font(.footnote).foregroundStyle(.secondary) }
                if value.assisted { Text("With hint · assisted").font(.caption) }
                if value.segment != nil {
                    if value.playbackPolicyVersion == 1 {
                        Text(AppL10n.text("dictation.listens").replacingOccurrences(of:"{n}",with:String(value.playback?.wholeStarts ?? 0)).replacingOccurrences(of:"{total}",with:"4")).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("dictation-starts")
                        if value.mode == "sentences" {Text(AppL10n.text("dictation.policy.step").replacingOccurrences(of:"{n}",with:String(value.policyStep)).replacingOccurrences(of:"{total}",with:String(max(1,value.plan.count-1)))).font(.caption).foregroundStyle(.secondary)}
                    }
                    if value.playbackPolicyVersion == 1 && (value.playback?.wholeStarts ?? 0) >= 4 {Text("dictation.limit").font(.footnote).foregroundStyle(.secondary)}
                    if value.playbackPolicyVersion == nil && !value.checked && value.mode == "sentences" && value.step < value.plan.count - 1 { Button("Next") { transition(.next) }.disabled(busy || saving).accessibilityIdentifier("dictation-next") }
                }
                if !value.checked {
                    HStack {
                        Button {
                            draftFocused = false
                            cancelTransport()
                            photo = PhotoPresentation(context: DictationPhotoInsertion(generation: model.session.generation, attempt: value.id))
                        } label: { Image(systemName:"camera").font(.system(size:22)).frame(width:44,height:44).contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("dictation.camera.title", tableName:"DictationCamera"))
                            .accessibilityIdentifier("dictation-camera")
                            .disabled(busy || model.dictationDrafts.conflict(value.id) != nil)
                        Spacer()
                        Button("Check") { action("check") }.buttonStyle(.borderedProminent).controlSize(.large).tint(.primary).foregroundStyle(Color(uiColor:.systemBackground)).frame(minHeight:44).disabled(value.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || busy || saving).accessibilityIdentifier("dictation-check")
                    }.dynamicTypeSize(...DynamicTypeSize.xxxLarge).id("dictation-draft-header")
                }
                TextField("", text: Binding(get:{record?.draft ?? ""},set:{ draft in
                    editDraft(draft)
                }),axis:.vertical).lineLimit(6...14).focused($draftFocused).autocorrectionDisabled().textInputAutocapitalization(.never).padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(.quaternary,lineWidth:1)).disabled(value.checked || (busy && !preparing)).accessibilityLabel("What you heard").accessibilityIdentifier("dictation-draft").id("dictation-draft-field")
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            // Keep the compact 44pt action header and full-size editable lines together
            // above the transport, rather than scrolling Check behind system navigation.
            if draftFocused && textSize.isAccessibilitySize {
                proxy.scrollTo("dictation-draft-header", anchor: .top)
            }
        }
        }
    }
    private func attemptMenu(_ value: DictationRecord) -> some View {
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
    private func editDraft(_ draft: String) {
        record?.draft = String(draft.prefix(2400))
        if let record {
            do { try model.dictationDrafts.update(record) }
            catch { self.error = AppL10n.text("Not saved. Retry before leaving.") }
        }
        draftVersion += 1
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            if !Task.isCancelled { save() }
        }
    }
    private func policyController(_ value: DictationRecord) -> DictationPlaybackController? {
        playbackSession.select(value, model:model)
        return playbackSession.controller
    }
    private func cancelTransport() { playbackSession.interrupt();task?.cancel();task=nil;epoch += 1;busy=false }
    private func transition(_ event: DictationEvent) {
        if let value=record,value.playbackPolicyVersion == 1,event == .whole || event == .sentences {
            let controller=policyController(value)
            perform {_,current in
                try await controller?.cancel()
                guard current() else {return}
                record?.transition(event)
                if let record {try model.dictationDrafts.update(record)}
            }
        } else {player.stop(resetTiming:event != .ended);record?.transition(event);if let record {do {try model.dictationDrafts.update(record)} catch {self.error=AppL10n.text("Not saved. Retry before leaving.")}};save()}
    }
    private func clear() { originalVisible=nil;epoch += 1;saveFence.reset();task?.cancel();saveTask?.cancel();path=[];items=[];record=nil;title="";original="";error=nil;busy=false;loaded=false;historyConfirmed=false;showAdd=false }
    private func saveAddForm() { do { try model.dictationDrafts.editAdd(title:title,original:original) } catch { self.error=AppL10n.text("Not saved. Retry before leaving.") } }
    private func accept(_ value: DictationRecord) throws { try model.dictationDrafts.accept(value);record = model.dictationDrafts.record(value.id);path=[value.id] }
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
        Task { @MainActor in
            defer { saveFence.finish(ticket) }
            do {
                guard saveFence.isCurrent(ticket),model.session.generation==generation,record?.id==value.id else{return}
                try await model.dictationDrafts.flushRecoveringDeletion(id:value.id) { id,body in try await api.dictation(id:id,method:"PUT",body:body) }
                guard let updated=model.dictationDrafts.record(value.id) else { return }
                guard saveFence.isCurrent(ticket),model.session.generation==generation,record?.id==value.id else{return}
                record?.revision=updated.revision
                if version==draftVersion { _=saveFence.finish(ticket);completion() }
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
