import SwiftUI
import KeineMagieCore

/// Voluntary discussion: presenting, reading and typing never request AI work.
struct TranslationDiscussionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @FocusState private var composerFocused: Bool
    @State private var expanded: Set<String> = []

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let record = model.discussionRecord {
                        DisclosureGroup {
                            Text(verbatim: model.draft).foregroundStyle(.secondary)
                            Text(verbatim: model.displayedTranslation)
                        } label: {
                            Text(verbatim: model.displayedTranslation).lineLimit(2).foregroundStyle(.secondary)
                        }.font(.subheadline).accessibilityIdentifier("followup-context")
                        ForEach(record.followups) { turn in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(verbatim: turn.question)
                                    .padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                Text(verbatim: turn.answer).textSelection(.enabled)
                                    .accessibilityIdentifier("followup-answer")
                                if let translation = turn.revisedText {
                                    let source = turn.proposalSource(original: record.text)
                                    let paired = source != model.draft
                                    DisclosureGroup(isExpanded: Binding(get: { expanded.contains(turn.id) }, set: { if $0 { composerFocused = false; expanded.insert(turn.id) } else { expanded.remove(turn.id) } })) {
                                        VStack(alignment: .leading, spacing: 8) {
                                            if paired {
                                                Text("followup.source").font(.caption).foregroundStyle(.secondary)
                                                Text(verbatim: source).textSelection(.enabled).accessibilityIdentifier("followup-proposed-source")
                                            }
                                            Text("followup.translation").font(.caption).foregroundStyle(.secondary)
                                            Text(verbatim: translation).textSelection(.enabled)
                                            if model.appliedProposalID == turn.id {
                                                Label("followup.applied", systemImage: "checkmark").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("followup-applied")
                                            } else {
                                                Button(LocalizedStringKey(paired ? "followup.useBoth" : "followup.use")) {
                                                    model.applyTranslationProposal(turn)
                                                }.frame(minHeight: 44).buttonStyle(.borderless)
                                                    .disabled(model.followupPending || !model.session.canWrite)
                                                    .accessibilityIdentifier("followup-apply")
                                            }
                                        }.padding(.top, 8)
                                    } label: { Text("followup.proposal").font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("followup-proposal") }
                                }
                            }
                        }
                        if model.followupPending { ProgressView().controlSize(.small).accessibilityLabel("followup.sending").accessibilityIdentifier("followup-pending") }
                    }
                }.padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    if let error = model.followupError {
                        Text(LocalizedStringKey(error)).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("followup-error")
                    }
                    if !model.session.canWrite { Text("followup.readonly").font(.footnote).foregroundStyle(.secondary) }
                    if (model.discussionRecord?.followups.count ?? 0) >= 6 {
                        Text("followup.limit").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        HStack(alignment: .bottom, spacing: 8) {
                            TextField("followup.prompt", text: $model.followupQuestion, axis: .vertical)
                                .lineLimit(1...5).focused($composerFocused)
                                .padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                                .accessibilityIdentifier("followup-question")
                            Button {
                                model.beginTranslationFollowup(locale: locale.language.languageCode?.identifier ?? "en")
                            } label: {
                                Image(systemName: model.followupPending ? "ellipsis" : "arrow.up.circle.fill")
                                    .font(.title2).frame(width: 44, height: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("followup.send").accessibilityIdentifier("followup-send")
                                .disabled(!model.session.canWrite || model.followupPending || model.followupQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.followupQuestion.unicodeScalars.count > 2000 || model.draft.unicodeScalars.count > 8000 || model.displayedTranslation.unicodeScalars.count > 8000)
                        }
                        if model.followupQuestion.unicodeScalars.count >= 1800 {
                            Text(verbatim: "\(model.followupQuestion.unicodeScalars.count) / 2,000").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.padding(.horizontal).padding(.vertical, 8).background(.bar)
            }
            .navigationTitle("followup.title").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("outbox.done") { model.closeTranslationDiscussion(); dismiss() }.accessibilityIdentifier("followup-done")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await model.loadTranslationDiscussions()
            if model.session.canWrite { composerFocused = true }
        }
    }
}
