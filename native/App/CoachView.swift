import SwiftUI
import KeineMagieCore

struct CoachView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @FocusState private var composerFocused: Bool
    var body: some View {
        @Bindable var model = model
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if !model.session.canWrite { Text("Offline. Showing saved history").font(.footnote).foregroundStyle(.secondary) }
                    if model.coach?.turns.isEmpty != false {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("coach.welcome")
                            Text("coach.scope").font(.caption).foregroundStyle(.secondary)
                            Button("coach.practice") { model.sendCoach("message", text: AppL10n.text("coach.practice")) }
                                .disabled(!model.session.canWrite || model.coachBusy)
                                .accessibilityIdentifier("coach-practice")
                        }.padding().background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
                    }
                    ForEach(model.coach?.turns ?? []) { turn in
                        HStack { Spacer(minLength: 32); Text(turn.text).padding(14).foregroundStyle(.white).background(Color(white: 0.2), in: RoundedRectangle(cornerRadius: 18)) }
                        CoachTurnView(turn: turn)
                            .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .bottom)))
                    }
                    if model.coachBusy {
                        HStack {
                            ProgressView().accessibilityLabel("coach.pending")
                            if let id = model.coachPendingID { Button("coach.cancel") { model.sendCoach("cancel", turnID: id) } }
                        }.padding(12)
                    }
                    if let error = model.coachError { Text(error).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("coach-error") }
                    Color.clear.frame(height: 1).id("coach-bottom")
                }.padding(.horizontal).padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("coach.message", text: $model.coachDraft, axis: .vertical)
                        .lineLimit(1...5).focused($composerFocused)
                        .padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("coach-composer")
                    Button {
                        model.sendCoach("message", text: model.coachDraft)
                        composerFocused = false
                    } label: { Image(systemName: "arrow.up.circle.fill").font(.title).frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("coach.send").accessibilityIdentifier("coach-send")
                        .disabled(!model.session.canWrite || model.coachBusy || model.coachDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.coachDraft.unicodeScalars.count > 2000)
                }.padding(.horizontal).padding(.vertical, 8).background(.bar)
            }
            .onChange(of: model.coach?.turns.count) { old, new in
                if let old, let new, new > old {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { proxy.scrollTo("coach-bottom", anchor: .bottom) }
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.coachBusy)
        }
        .task(id: "\(model.session.generation)-\(model.session.canWrite)") { await model.loadCoach() }
        .refreshable { await model.loadCoach() }

    }
}

private struct CoachTurnView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let turn: CoachTurn
    @State private var answer = ""
    @State private var sourceOpen = false
    private var writable: Bool { model.session.canWrite && !model.coachBusy }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message = turn.message { Text(message).textSelection(.enabled) }
            if turn.state == "pending" {
                Text("coach.pending").font(.footnote)
                Button("coach.cancel") { model.sendCoach("cancel", turnID: turn.id) }.disabled(!model.session.canWrite)
            } else if turn.state == "failed" || turn.state == "canceled" {
                Text(LocalizedStringKey("coach." + turn.state)).font(.footnote)
            }
            if let kind = turn.kind, kind != "clarification", let prompt = turn.prompt {
                VStack(alignment: .leading, spacing: 12) {
                    Text(LocalizedStringKey("coach.target." + (turn.target ?? "grammar"))).font(.caption).foregroundStyle(.secondary)
                    Text(prompt).font(.title3).textSelection(.enabled)
                    if let attempt = turn.attempt {
                        Text(attempt.answer).italic()
                        Text(LocalizedStringKey("coach." + (attempt.excluded ? "excluded" : attempt.outcome))).font(.headline)
                            .accessibilityIdentifier("coach-feedback")
                        if attempt.assisted { Text("coach.assisted").font(.caption).foregroundStyle(.secondary) }
                        Menu("coach.review") {
                            Button("coach.count.correct") { model.sendCoach("review", text: "correct", turnID: turn.id) }
                            Button("coach.count.wrong") { model.sendCoach("review", text: "wrong", turnID: turn.id) }
                            Button("coach.exclude") { model.sendCoach("review", text: "excluded", turnID: turn.id) }
                        }.disabled(!writable)
                    } else {
                        TextField("coach.answer", text: $answer, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("coach-answer-" + turn.id)
                        ViewThatFits(in: .horizontal) {
                            HStack { answerButtons }
                            VStack(alignment: .leading) { answerButtons }
                        }
                    }
                }.padding(14).background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            }
            if let quote = turn.quote {
                DisclosureGroup(isExpanded: $sourceOpen) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(quote).textSelection(.enabled)
                        if let explanation = turn.explanation { Text(explanation).font(.callout) }
                        if let source = turn.sourceID, let target = CoachSourceTarget(source) {
                            NavigationLink { CoachSourceView(target: target, generation: model.session.generation) } label: { Text("coach.openSource") }
                                .accessibilityIdentifier("coach-source-" + turn.id)
                        }
                    }.padding(.vertical, 8)
                } label: { Text("coach.source") }
            } else if turn.sourceID != nil {
                Button("coach.source") { model.sendCoach("reveal", turnID: turn.id); sourceOpen = true }.disabled(!writable)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
            .padding(.trailing, 24)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: sourceOpen)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: turn.attempt?.outcome)
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
            Button("coach.reset") { confirmReset = true }.disabled(!model.session.canWrite || model.coachBusy)
        }
        .confirmationDialog("coach.reset.confirm", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("coach.reset", role: .destructive) { model.sendCoach("reset") }
        }
        .task { await model.loadCoach() }
    }
}
