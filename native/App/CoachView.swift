import SwiftUI
import KeineMagieCore

private struct CoachReduceMotionOverride: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var coachReduceMotionOverride: Bool {
        get { self[CoachReduceMotionOverride.self] }
        set { self[CoachReduceMotionOverride.self] = newValue }
    }
}

struct CoachView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var nearBottom = true
    @State private var followQuickReply = false
    @State private var visibleTurns: Set<String> = []
    @State private var hydrated = false
    @State private var presented = false
    @State private var viewport = CGRect.zero
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.coachReduceMotionOverride) private var reduceMotionOverride
    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }

    @FocusState private var composerFocused: Bool
    private var motionContract: String {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["KM_SIMULATOR_SESSION_FIXTURE"] == "coach-arrival" {
            return "\(reduceMotion ? "static" : "animated");system=\(UIAccessibility.isReduceMotionEnabled);injected=\(ProcessInfo.processInfo.environment["KM_SIMULATOR_COACH_REDUCE_MOTION"] == "1")"
        }
        #endif
        return ""
    }
    var body: some View {
        @Bindable var model = model
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !model.session.canWrite { Text("Offline. Showing saved history").font(.footnote).foregroundStyle(.secondary) }
                    if model.coach?.turns.isEmpty != false {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("coach.welcome")
                            Text("coach.scope").font(.caption).foregroundStyle(.secondary)

                        }.padding().background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
                    }
                    ForEach(model.coach?.turns ?? []) { turn in
                        if !turn.text.isEmpty { HStack { Spacer(minLength: 32); Text(turn.text).padding(14).foregroundStyle(.white).background(Color(white: 0.2), in: RoundedRectangle(cornerRadius: 18)) } }
                        CoachTurnView(turn: turn)
                            .id(turn.id)
                            .transition(reduceMotion || !hydrated ? .identity : .opacity.combined(with: .move(edge: .bottom)))
                            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                                let visible = frame.intersection(viewport).height >= min(frame.height, viewport.height) * 0.6 && viewport.height > 0
                                if visible { visibleTurns.insert(turn.id) } else { visibleTurns.remove(turn.id) }
                                if visible && nearBottom && presented && scenePhase == .active { Task { await model.seeCoach(turn) } }
                            }
                    }
                    if model.coachBusy && !(model.coach?.turns.contains { $0.attempt?.assessmentState == "pending" } ?? false) {
                        HStack {
                            ProgressView().accessibilityLabel("coach.pending")
                            if let id = model.coachPendingID { Button("coach.cancel") { model.sendCoach("cancel", turnID: id) } }
                        }.padding(12)
                    }
                    if let error = model.coachError { Text(error).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("coach-error") }
                    Color.clear.frame(height: 1).id("coach-bottom")
                }.padding(.horizontal).padding(.vertical, 16)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { nearBottom = viewport.height > 0 && $0.maxY <= viewport.maxY + 80 }
            }
            .scrollDismissesKeyboard(.interactively)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { viewport = $0 }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    quickControls(proxy: proxy)
                    HStack(alignment: .bottom, spacing: 12) {
                    TextField("coach.message", text: $model.coachDraft, axis: .vertical)
                        .lineLimit(1...5).focused($composerFocused)
                        .padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("coach-composer")
                        .accessibilityLabel("coach.message")
                        .accessibilitySortPriority(1)
                    Button {
                        model.sendCoach("message", text: model.coachDraft)
                        composerFocused = false
                    } label: { Image(systemName: "arrow.up.circle.fill").font(.title).frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("coach.send").accessibilityIdentifier("coach-send")
                        .disabled(!model.session.canWrite || model.coachBusy || model.coachDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.coachDraft.unicodeScalars.count > 2000)
                    }.accessibilityElement(children: .contain)
                }.padding(.horizontal).padding(.vertical, 8).background(.bar)
            }
            .onChange(of: model.coach?.turns.count) { old, new in
                if hydrated, let old, let new, new > old, nearBottom || followQuickReply {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { proxy.scrollTo("coach-bottom", anchor: .bottom) }
                    followQuickReply = false
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.coachBusy)
            .onChange(of: model.coach?.turns.map(\.id)) { old, new in
                if new != nil { hydrated = true }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && nearBottom && presented { for turn in model.coach?.turns ?? [] where visibleTurns.contains(turn.id) { Task { await model.seeCoach(turn) } } }
            }
        }
        .onChange(of: nearBottom) { _, near in
            if near && scenePhase == .active && presented { for turn in model.coach?.turns ?? [] where visibleTurns.contains(turn.id) { Task { await model.seeCoach(turn) } } }
        }
        .onChange(of: model.coachBusy) { _, busy in
            if !busy { followQuickReply = false }
            if !busy && scenePhase == .active && nearBottom && presented { for turn in model.coach?.turns ?? [] where visibleTurns.contains(turn.id) { Task { await model.seeCoach(turn) } } }
        }
        .onAppear { presented = true }
        .onDisappear { presented = false; visibleTurns.removeAll() }
        .animation(reduceMotion || !hydrated ? nil : .easeOut(duration: 0.2), value: model.coach?.turns.map(\.id))
        .task(id: "\(model.session.generation)-\(model.session.canWrite)") { await model.loadCoach(); if !Task.isCancelled && scenePhase == .active && presented { model.sendCoach("entry") } }
        .refreshable { await Task { await model.loadCoach() }.value }

    }
    private func quickControls(proxy: ScrollViewProxy) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout())
        return layout {
            ForEach(Array((model.coach?.quickActions ?? []).prefix(3).enumerated()), id: \.offset) { _, action in
                Button(LocalizedStringKey("coach.quick." + action.action)) {
                    followQuickReply = action.action != "reveal"
                    model.sendCoach(action.action, text: action.action == "reveal" ? "source" : AppL10n.text("coach.quick." + action.action), turnID: action.turnID, preserveDraft: true)
                }
                .font(.subheadline).frame(minHeight: 44)
                .disabled(!model.session.canWrite || model.coachBusy)
                .accessibilityIdentifier("coach-" + action.action).accessibilityValue(motionContract)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            if model.coach?.turns.contains(where: \.isUnread) == true {
                Button { proxy.scrollTo("coach-bottom", anchor: .bottom) } label: { Image(systemName: "arrow.down.circle").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("coach.newMessages")
            }
        }
    }
}

private struct CoachTurnView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.coachReduceMotionOverride) private var reduceMotionOverride
    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }
    let turn: CoachTurn
    @State private var answer = ""
    @State private var sourceOpen = false
    @State private var confirmRecheck = false
    private var writable: Bool { model.session.canWrite && !model.coachBusy }
    private var masked: Bool { turn.masksAnswer(latestID: model.coach?.turns.last?.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message = turn.message, turn.showsInstruction { Text(message).textSelection(.enabled) }
            if turn.state == "pending" {
                Text("coach.pending").font(.footnote)
                Button("coach.cancel") { model.sendCoach("cancel", turnID: turn.id) }.disabled(!model.session.canWrite)
            } else if turn.state == "failed" || turn.state == "canceled" {
                Text(LocalizedStringKey("coach." + turn.state)).font(.footnote)
            }
            if let kind = turn.kind, !["clarification", "nudge"].contains(kind), let prompt = turn.prompt {
                VStack(alignment: .leading, spacing: 12) {
                    Text(prompt).font(.title3).textSelection(.enabled)
                    if masked {
                        Button("coach.showAnswer") { model.sendCoach("reveal", text: "answer", turnID: turn.id) }.disabled(!writable)
                    } else if let attempt = turn.attempt {
                        Text(attempt.answer).italic()
                        Text(LocalizedStringKey(attempt.feedbackKey)).font(attempt.outcome == "ambiguous" ? .callout : .headline)
                            .accessibilityIdentifier("coach-feedback")
                        if attempt.assessmentState == "pending" {
                            Button("coach.cancel") { model.sendCoach("cancel", turnID: attempt.id) }.disabled(!model.session.canWrite)
                        }
                        if attempt.canRecheck {
                            Menu { Button("coach.assessment.recheck") { confirmRecheck = true } } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("coach.assessment.recheck").disabled(!writable)
                        }
                        if let assessment = attempt.assessment, assessment.verdict != "correct", !assessment.correctedAnswer.isEmpty {
                            Text(assessment.correctedAnswer).textSelection(.enabled)
                        }
                        if attempt.assisted { Text("coach.assisted").font(.caption).foregroundStyle(.secondary) }

                    } else {
                        TextField("coach.answer", text: $answer, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("coach-answer-" + turn.id)
                            .accessibilityLabel("coach.answer")
                        ViewThatFits(in: .horizontal) {
                            HStack { answerButtons }
                            VStack(alignment: .leading) { answerButtons }
                        }
                    }
                }
            }
            if let explanation = turn.explanation, turn.attempt != nil, !masked, turn.attempt?.assessmentState == nil || turn.attempt?.assessmentState == "completed" {
                Text(explanation).font(.callout).textSelection(.enabled)
                    .accessibilityIdentifier("coach-explanation")
            }
            if let quote = turn.quote, (turn.sourceReveals ?? 0) > 0 {
                DisclosureGroup(isExpanded: Binding(get: { sourceOpen }, set: { open in
                    if open && !sourceOpen { model.sendCoach("reveal", text: "source", turnID: turn.id) }; sourceOpen = open
                })) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(quote).textSelection(.enabled)
                        if let explanation = turn.explanation, turn.attempt == nil { Text(explanation).font(.callout) }
                        if let source = turn.sourceID, let target = CoachSourceTarget(source) {
                            NavigationLink { CoachSourceView(target: target, generation: model.session.generation) } label: { Text(LocalizedStringKey(source.hasPrefix("translation:") ? "coach.savedTranslation" : "coach.savedPassage")) }
                                .accessibilityIdentifier("coach-source-" + turn.id)
                        }
                    }.padding(.vertical, 8)
                } label: { Text(LocalizedStringKey(turn.attempt == nil ? "coach.hint" : "coach.source")) }
            } else if turn.sourceID != nil && (turn.attempt != nil || !(model.coach?.quickActions.contains { $0.action == "reveal" && $0.turnID == turn.id } ?? false)) {
                Button(LocalizedStringKey(turn.attempt == nil ? "coach.hint" : "coach.source")) { model.sendCoach("reveal", text: "source", turnID: turn.id); sourceOpen = true }.disabled(!writable)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .leading) { if turn.isUnread { RoundedRectangle(cornerRadius: 2).fill(.primary.opacity(0.65)).frame(width: 3).padding(.vertical, 12) } }
            .padding(.trailing, 24)
            .onChange(of: turn.sourceReveals) { old, new in if turn.attempt == nil, (new ?? 0) > (old ?? 0) { sourceOpen = true } }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: sourceOpen)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: turn.attempt?.outcome)
            .confirmationDialog("coach.assessment.confirm", isPresented: $confirmRecheck, titleVisibility: .visible) {
                Button("coach.assessment.recheck") { model.sendCoach("recheck", turnID: turn.id) }
            }
    }
    @ViewBuilder private var answerButtons: some View {
        Button("coach.check") { model.sendCoach("answer", text: answer, turnID: turn.id) }
            .buttonStyle(.borderedProminent).tint(.primary)
            .disabled(!writable || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || answer.unicodeScalars.count > 300)
            .accessibilityIdentifier("coach-check-" + turn.id)
        Button("coach.skip") { model.sendCoach("skip", turnID: turn.id) }.disabled(!writable)
    }
}

private struct CoachSourceView: View {
    @Environment(AppModel.self) private var model
    let target: CoachSourceTarget
    let generation: Int
    var body: some View {
        Group {
            if generation == model.session.generation, model.session.phase == .signedIn {
                switch target {
                case .translation(let id):
                    if let record = model.history.first(where: { $0.id == id }) {
                        ScrollView { VStack(alignment: .leading, spacing: 20) {
                            Text(record.text).textSelection(.enabled)
                            Text(record.translation).textSelection(.enabled).font(.title3)
                        }.padding() }.navigationTitle("coach.openSource")
                    } else { Text("coach.sourceMissing").padding() }
                case .passage(let id, let index):
                    if let job = model.podcasts.jobs.first(where: { $0.id == id }), job.segments.indices.contains(index) {
                        EpisodeReaderView(job: job, initialSegment: index)
                    } else { Text("coach.sourceMissing").padding() }
                }
            } else { Text("coach.signin") }
        }
    }
}

struct CoachObservationsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false
    var body: some View {
        Section("coach.skills") {
            if model.coach?.observations.isEmpty != false { Text("coach.separate").font(.footnote).foregroundStyle(.secondary) }
            else { Text("episode.self.assessment").font(.footnote).foregroundStyle(.secondary) }
            ForEach(model.coach?.observations ?? []) { item in
                VStack(alignment: .leading, spacing: 5) {
                    Text(LocalizedStringKey("coach.target." + item.target)).font(.headline)
                    Text(item.language).font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: "\(AppL10n.text("coach.answers")): \(item.count) · \(AppL10n.text("coach.examples")): \(item.distinctExamples)")
                    Text(verbatim: "\(AppL10n.text("coach.correct")): \(item.correct) · \(AppL10n.text("coach.wrong")): \(item.needsPractice)")
                    Text(verbatim: "\(AppL10n.text("coach.assisted")): \(item.assisted) · \(AppL10n.text("coach.limited"))").font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach((model.coach?.turns ?? []).filter { $0.attempt != nil }) { turn in
                VStack(alignment: .leading, spacing: 6) {
                    Text(turn.prompt ?? "").font(.callout)
                    Text(turn.attempt?.answer ?? "").italic()
                    Menu("coach.review") {
                        Button("coach.count.correct") { model.sendCoach("review", text: "correct", turnID: turn.id) }
                        Button("coach.count.wrong") { model.sendCoach("review", text: "wrong", turnID: turn.id) }
                        Button("coach.exclude") { model.sendCoach("review", text: "excluded", turnID: turn.id) }
                    }.disabled(!model.session.canWrite || model.coachBusy || (turn.attempt?.assessmentState != nil && turn.attempt?.assessmentState != "completed"))
                }
            }
            Button("coach.reset") { confirmReset = true }.disabled(!model.session.canWrite || model.coachBusy)
        }
        .confirmationDialog("coach.reset.confirm", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("coach.reset", role: .destructive) { model.sendCoach("reset") }
        }
        .task { await model.loadCoach() }
    }
}
