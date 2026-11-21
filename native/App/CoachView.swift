import SwiftUI
import KeineMagieCore

// Explicit opaque text and surfaces: secondary labels/placeholders stay readable
// independently of system material opacity and background blending.
private enum CoachPalette {
    static let secondary = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.78, alpha: 1) : UIColor(white: 0.32, alpha: 1) })
    static let surface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.15, alpha: 1) : UIColor(white: 0.94, alpha: 1) })
    static let success = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.125, green: 0.208, blue: 0.161, alpha: 1) : UIColor(red: 0.929, green: 0.965, blue: 0.937, alpha: 1) })
    static let unanswered = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.161, green: 0.145, blue: 0.149, alpha: 1) : UIColor(red: 0.973, green: 0.953, blue: 0.953, alpha: 1) })
}

private struct CoachReduceMotionOverride: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var coachReduceMotionOverride: Bool {
        get { self[CoachReduceMotionOverride.self] }
        set { self[CoachReduceMotionOverride.self] = newValue }
    }
}

struct CoachView: View {
    var isSelected = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var nearBottom = true
    @State private var showEarlier = 0
    @State private var historyNow = Date()
    @State private var followQuickReply = false
    @State private var visibleTurns: Set<String> = []
    @State private var hydrated = false
    @State private var followedSendRevision = 0
    @State private var contentHeight: CGFloat = 0
    @State private var presented = false
    @State private var viewport = CGRect.zero
    @State private var focusedAnswerID: String?
    @State private var pinnedTurnID: String?
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
                VStack(alignment: .leading, spacing: 12) {
                    if model.coach?.turns.contains(where: { $0.isVisible && !$0.isRecent(now: historyNow) }) == true {
                        Button {
                            let count = model.coach?.turns.filter { $0.isVisible && !$0.isRecent(now: historyNow) }.count ?? 0
                            showEarlier = showEarlier < count ? showEarlier + 50 : 0
                        } label: {
                            HStack(spacing: 12) {
                                Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5)
                                Label("coach.earlier", systemImage: "chevron.up").fixedSize()
                                Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5)
                            }
                            .frame(minHeight: 44).contentShape(Rectangle())
                        }
                            .buttonStyle(.plain).foregroundStyle(CoachPalette.secondary)
                            .font(.footnote).accessibilityIdentifier("coach-earlier")
                    }
                    if !model.session.canWrite { Text("Offline. Showing saved history").font(.footnote).foregroundStyle(.secondary) }
                    if model.coach?.turns.filter(\.isVisible).isEmpty != false {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("coach.welcome")

                        }.padding().background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
                    }
                    ForEach(CoachTurn.historyWindow(model.coach?.turns ?? [], now: historyNow, earlierLimit: showEarlier, pinnedID: pinnedTurnID)) { turn in
                        if !turn.text.isEmpty { HStack { Spacer(minLength: 32); Text(turn.text).padding(14).foregroundStyle(.white).background(Color(white: 0.2), in: RoundedRectangle(cornerRadius: 18)) } }
                        CoachTurnView(turn: turn, focusedAnswerID: $focusedAnswerID)
                            .id(turn.id)
                            .transition(reduceMotion || !hydrated ? .identity : .opacity.combined(with: .move(edge: .bottom)))
                            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                                let visible = frame.intersection(viewport).height >= min(frame.height, viewport.height) * 0.6 && viewport.height > 0
                                if visible { visibleTurns.insert(turn.id) } else { visibleTurns.remove(turn.id) }
                                if visible && nearBottom && presented && scenePhase == .active { Task { await model.seeCoach(turn) } }
                            }
                    }
                    if model.coachBusy && !(model.coach?.turns.contains { $0.state == "pending" || $0.attempt?.assessmentState == "pending" } ?? false) {
                        CoachCheckingView(reduceMotion: reduceMotion)
                    }
                    if let error = model.coachError { Text(error).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("coach-error") }
                    Color.clear.frame(height: 1).id("coach-bottom")
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                            nearBottom = viewport.height > 0 && frame.maxY <= viewport.maxY + 80
                        }
                }.padding(.horizontal).padding(.vertical, 16)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }

            }
            .scrollDismissesKeyboard(.interactively)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                let shrank = frame.height < viewport.height
                viewport = frame
                if shrank, let focusedAnswerID {
                    proxy.scrollTo("coach-answer-bottom-" + focusedAnswerID, anchor: .bottom)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                // Native focus scrolling settles after the viewport resize. Keep
                // the complete answer action row visible, not only the caret.
                if let focusedAnswerID { proxy.scrollTo("coach-answer-bottom-" + focusedAnswerID, anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    historyControls(proxy: proxy)
                    VStack(spacing: 0) {
                        HStack(alignment: .bottom, spacing: 4) {
                            if !dynamicTypeSize.isAccessibilitySize { actionsMenu }
                            TextField("coach.message", text: $model.coachDraft, prompt: Text("coach.message").foregroundStyle(CoachPalette.secondary), axis: .vertical)
                                .lineLimit(1...5).focused($composerFocused)
                                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 8 : 0).padding(.vertical, 12)
                                .accessibilityIdentifier("coach-composer")
                                .accessibilityLabel("coach.message")
                                .accessibilitySortPriority(1)
                            if !dynamicTypeSize.isAccessibilitySize { sendButton }
                        }
                        if dynamicTypeSize.isAccessibilitySize {
                            HStack { actionsMenu; Spacer(minLength: 0); sendButton }
                        }
                    }.padding(.horizontal, 4).background(CoachPalette.surface, in: RoundedRectangle(cornerRadius: 24))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("coach-composer-container")
                }.padding(.horizontal).padding(.vertical, 8).background(.bar)
            }
            .task(id: "\(scrollRevision)-\(model.coachOwnSendRevision)-\(model.coachLoaded)-\(viewport.height > 0)-\(contentHeight > 0)") {
                guard model.coachLoaded, viewport.height > 0, contentHeight > 0 else { return }
                let initial = !hydrated
                let shouldFollow = initial || nearBottom || followQuickReply || followedSendRevision != model.coachOwnSendRevision
                guard shouldFollow else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                hydrated = true
                followedSendRevision = model.coachOwnSendRevision
                proxy.scrollTo("coach-bottom", anchor: .bottom)
                if !model.coachBusy { followQuickReply = false }
            }
            .onChange(of: scenePhase) { _, phase in
                model.coachForeground = presented && phase == .active
                if phase == .active && presented && model.session.canWrite { model.sendCoach("entry") }
                if phase == .active && nearBottom && presented { for turn in model.coach?.turns ?? [] where visibleTurns.contains(turn.id) { Task { await model.seeCoach(turn) } } }
            }
        }
        .onChange(of: nearBottom) { _, near in
            if near && scenePhase == .active && presented { for turn in model.coach?.turns ?? [] where visibleTurns.contains(turn.id) { Task { await model.seeCoach(turn) } } }
        }
        .onChange(of: model.coachBusy) { _, busy in
            if busy { pinnedTurnID = model.coach?.turns.last(where: { $0.isVisible && $0.kind != "clarification" && $0.kind != nil })?.id }
            if !busy && scenePhase == .active && nearBottom && presented { for turn in model.coach?.turns ?? [] where visibleTurns.contains(turn.id) { Task { await model.seeCoach(turn) } } }
        }
        .onAppear { presented = isSelected; model.coachForeground = isSelected && scenePhase == .active }
        .onChange(of: isSelected) { _, selected in
            presented = selected; model.coachForeground = selected && scenePhase == .active
            if selected { historyNow = Date() } else { visibleTurns.removeAll() }
        }
        .onDisappear { presented = false; model.coachForeground = false; visibleTurns.removeAll() }
        .onChange(of: model.session.generation) { _, _ in showEarlier = 0; hydrated = false; historyNow = Date(); visibleTurns.removeAll(); focusedAnswerID = nil; pinnedTurnID = nil }
        .animation(reduceMotion || !hydrated ? nil : .easeOut(duration: 0.2), value: model.coach?.turns.map(\.id))
        .task(id: "\(model.session.generation)-\(model.session.canWrite)-\(isSelected)") { guard isSelected else { return }; await model.loadCoach(); if !Task.isCancelled && model.session.canWrite && scenePhase == .active && presented { model.sendCoach("entry") } }
        .refreshable { await Task { await model.loadCoach() }.value }

    }
    private var scrollRevision: String {
        "\(model.coach?.turns.filter(\.isVisible).map { "\($0.id):\($0.state):\($0.messageVersion ?? ""):\($0.attempt?.id ?? ""):\($0.attempt?.assessmentState ?? "")" }.joined(separator: "|") ?? "")"
    }
    private var pendingID: String? {
        model.coachPendingID ?? model.coach?.turns.last(where: { $0.attempt?.assessmentState == "pending" })?.attempt?.id ?? model.coach?.turns.last(where: { $0.state == "pending" })?.id
    }
    @ViewBuilder private var sendButton: some View {
        if let pendingID {
            Button { model.sendCoach("cancel", turnID: pendingID) } label: {
                Image(systemName: "stop.circle.fill").font(.system(size: 28)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("coach.stop").accessibilityIdentifier("coach-stop")
            .disabled(!model.session.canWrite || (model.coachBusy && model.coachPendingID == nil))
        } else {
            Button {
                followQuickReply = true
                model.sendCoach("message", text: model.coachDraft)
                composerFocused = false
            } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 28)).frame(width: 44, height: 44) }
                .accessibilityLabel("coach.send").accessibilityIdentifier("coach-send")
                .disabled(!model.session.canWrite || model.coachBusy || model.coachDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.coachDraft.unicodeScalars.count > 2000)
        }
    }
    private var actionsMenu: some View {
        Menu {
            ForEach(Array((model.coach?.quickActions ?? []).enumerated()), id: \.offset) { _, action in
                Button {
                    followQuickReply = action.action != "reveal"
                    model.sendCoach(action.action, text: action.action == "reveal" ? "source" : AppL10n.text("coach.quick." + action.action), turnID: action.turnID, preserveDraft: true)
                } label: {
                    Label(LocalizedStringKey(action.action == "progress" ? "coach.menu.progress" : "coach.quick." + action.action), systemImage: actionSymbol(action.action))
                }
                .disabled(!model.session.canWrite || model.coachBusy)
                .accessibilityIdentifier("coach-" + action.action)
            }
        } label: {
            Image(systemName: "plus").font(.system(size: 22, weight: .medium))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("coach.actions").accessibilityIdentifier("coach-actions")
        .accessibilityValue(motionContract)
        // Keep commands discoverable while busy/offline; only their execution is disabled.
        .disabled(model.coach?.quickActions.isEmpty != false)
    }
    private func actionSymbol(_ action: String) -> String {
        switch action {
        case "reveal": "lightbulb"
        case "progress": "chart.bar"
        case "explain": "text.bubble"
        case "practice", "more": "pencil"
        default: "text.bubble"
        }
    }
    private func historyControls(proxy: ScrollViewProxy) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout())
        return layout {
            if let active = model.coach?.turns.last(where: { $0.isVisible && $0.kind != nil && !["clarification", "nudge"].contains($0.kind ?? "") }), active.attempt == nil, !active.isRecent(now: historyNow), !CoachTurn.historyWindow(model.coach?.turns ?? [], now: historyNow, earlierLimit: showEarlier, pinnedID: pinnedTurnID).contains(where: { $0.id == active.id }) {
                Button("coach.awaiting") {
                    let older = (model.coach?.turns ?? []).filter { $0.isVisible && !$0.isRecent(now: historyNow) }
                    let index = older.firstIndex(where: { $0.id == active.id }) ?? 0
                    showEarlier = ((older.count - index - 1) / 50 + 1) * 50
                    Task { await Task.yield(); proxy.scrollTo(active.id, anchor: .center) }
                }.font(.footnote).frame(minHeight: 44).accessibilityIdentifier("coach-active-earlier")
            }
            if !nearBottom {
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Button { proxy.scrollTo("coach-bottom", anchor: .bottom) } label: { Image(systemName: "arrow.down.circle").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("coach.latest").accessibilityIdentifier("coach-latest")
            }
        }
    }
}

private struct CoachCheckingView: View {
    let reduceMotion: Bool
    var body: some View {
        Text(verbatim: "•••")
            .font(.title3.weight(.semibold)).tracking(4)
            .foregroundStyle(CoachPalette.secondary)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(CoachPalette.surface, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityLabel("coach.working")
            .accessibilityIdentifier("coach-typing")
    }
}

private struct CoachAssistantBubble: ViewModifier {
    var unread = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    func body(content: Content) -> some View {
        content.padding(14)
            .background(CoachPalette.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .leading) {
                if unread { RoundedRectangle(cornerRadius: 2).fill(.primary.opacity(0.65)).frame(width: 3).padding(.vertical, 12) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? 0 : 24)
    }
}

private struct CoachTurnView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.coachReduceMotionOverride) private var reduceMotionOverride
    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }
    let turn: CoachTurn
    @Binding var focusedAnswerID: String?
    @FocusState private var answerFocused: Bool
    @State private var answer = ""
    @State private var confirmRecheck = false
    private var writable: Bool { model.session.canWrite && !model.coachBusy }
    private var masked: Bool { turn.masksAnswer(latestID: model.coach?.turns.last(where: \.isVisible)?.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let kind = turn.kind, !["clarification", "nudge"].contains(kind), let prompt = turn.prompt {
                VStack(alignment: .leading, spacing: 12) {
                    Text(highlightedPrompt(prompt)).font(.body).textSelection(.enabled)
                        .accessibilityIdentifier("coach-prompt-" + turn.id)
                        .accessibilityValue(turn.kind == "context_translation" ? turn.targetText ?? "" : "")
                    if let message = turn.message, turn.showsInstruction {
                        Text(message).font(.footnote).foregroundStyle(CoachPalette.secondary).textSelection(.enabled)
                    }
                    if masked {
                        Button("coach.showAnswer") { model.sendCoach("reveal", text: "answer", turnID: turn.id) }.disabled(!writable)
                    } else if turn.attempt == nil {
                        TextField("coach.answer", text: $answer, prompt: Text("coach.answer").foregroundStyle(CoachPalette.secondary), axis: .vertical).font(.title3).lineLimit(2...4)
                            .focused($answerFocused)
                            .onChange(of: answerFocused) { _, focused in
                                if focused { focusedAnswerID = turn.id }
                                else if focusedAnswerID == turn.id { focusedAnswerID = nil }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 2).frame(minHeight: 44)
                            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                            .accessibilityIdentifier("coach-answer-" + turn.id)
                            .accessibilityLabel("coach.answer")
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 32) { checkButton; Spacer(minLength: 0); skipButton }
                            VStack(alignment: .leading, spacing: 8) { checkButton; HStack { Spacer(); skipButton } }
                        }
                        Color.clear.frame(height: 1).id("coach-answer-bottom-" + turn.id)
                    }
                    if turn.attempt == nil, (turn.sourceReveals ?? 0) > 0, let quote = turn.quote {
                        Text("coach.hint").font(.caption)
                        Text(quote).textSelection(.enabled)
                        if let explanation = turn.explanation { Text(explanation).font(.callout) }
                    }
                }.modifier(CoachAssistantBubble(unread: turn.isUnread))
            } else if let message = turn.message, !message.isEmpty {
                Text(message).textSelection(.enabled).modifier(CoachAssistantBubble(unread: turn.isUnread))
            }
            if let attempt = turn.attempt, !masked {
                if !attempt.answer.isEmpty {
                    HStack {
                        Spacer(minLength: 32)
                        Text(attempt.answer).textSelection(.enabled)
                            .padding(14).foregroundStyle(.white)
                            .background(Color(white: 0.2), in: RoundedRectangle(cornerRadius: 18))
                            .accessibilityIdentifier("coach-submitted-" + turn.id)
                    }
                }
                if attempt.assessmentState == "pending", model.coachError == nil {
                    CoachCheckingView(reduceMotion: reduceMotion)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        if attempt.assessmentState != "pending" {
                            Text(LocalizedStringKey(attempt.feedbackKey)).font(.callout.weight(.semibold))
                                .accessibilityIdentifier("coach-feedback")
                        }
                        if let assessment = attempt.assessment, !assessment.correctedAnswer.isEmpty {
                            Text(assessment.correctedAnswer).textSelection(.enabled)
                                .accessibilityIdentifier("coach-correction")
                        }
                        if let explanation = attempt.assessment?.explanation ?? turn.explanation,
                           attempt.assessmentState == nil || attempt.assessmentState == "completed" {
                            Text(explanation).font(.callout).textSelection(.enabled)
                                .accessibilityIdentifier("coach-explanation")
                        }
                        if attempt.assisted { Text("coach.assisted").font(.caption).foregroundStyle(CoachPalette.secondary) }
                        if attempt.canRecheck {
                            Menu { Button("coach.assessment.recheck") { confirmRecheck = true } } label: {
                                Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
                            }.accessibilityLabel("coach.assessment.recheck").disabled(!writable)
                        }
                    }.modifier(CoachAssistantBubble())
                }
            }
            if turn.state == "pending" { CoachCheckingView(reduceMotion: reduceMotion) }
            else if turn.state == "failed" || turn.state == "canceled" {
                Text(LocalizedStringKey("coach." + turn.state)).font(.footnote).modifier(CoachAssistantBubble())
            }
        }
        .confirmationDialog("coach.assessment.confirm", isPresented: $confirmRecheck, titleVisibility: .visible) {
            Button("coach.assessment.recheck") { model.sendCoach("recheck", turnID: turn.id) }
        }
    }
    private func highlightedPrompt(_ prompt: String) -> AttributedString {
        var text = AttributedString(prompt)
        if turn.kind == "context_translation", let target = turn.targetText, !target.isEmpty, let range = text.range(of: target) {
            text[range].font = .body.bold()
            text[range].underlineStyle = .single
        }
        return text
    }
    private var checkButton: some View {
        Button { model.sendCoach("answer", text: answer, turnID: turn.id) } label: {
            Text("coach.check").font(.body.weight(.medium)).fixedSize().padding(.horizontal, 16).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
            .buttonStyle(.plain)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .background(Color.primary.opacity(writable && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1 : 0.25), in: Capsule())
            .disabled(!writable || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || answer.unicodeScalars.count > 300)
            .accessibilityIdentifier("coach-check-" + turn.id)
    }
    private var skipButton: some View {
        Button { model.sendCoach("skip", turnID: turn.id) } label: {
            Text("coach.skip").fixedSize().frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(CoachPalette.secondary).disabled(!writable)
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
