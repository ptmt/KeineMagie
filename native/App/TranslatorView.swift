import SwiftUI
import UIKit
import KeineMagieCore

/// The signed-in landing screen is the real personal translator, not account setup.
struct TranslatorView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var inputFocused: Bool
    @State private var restoreInputFocus = false
    @Binding var showPending: Bool
    @ScaledMetric(relativeTo: .body) private var editorHeight = 112

    var body: some View {
        @Bindable var model = model
        List {

            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    TextEditor(text: $model.draft)
                        .focused($inputFocused)
                        .frame(height: editorHeight)
                        // Reserve a separate trailing lane, including while empty.
                        .padding(.trailing, 44)
                        .accessibilityLabel("Text zum Übersetzen")
                        .accessibilityIdentifier("translator-input")
                }
                    .padding(8)
                    .overlay(alignment: .topLeading) {
                        if model.draft.isEmpty {
                            Text("Text zum Übersetzen")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 13).padding(.vertical, 16)
                                .padding(.trailing, 44)
                                .allowsHitTesting(false)
                                .accessibilityIdentifier("translator-placeholder")
                                .accessibilityHidden(true)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if !model.draft.isEmpty {
                            Button {
                                model.draft = ""
                                inputFocused = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("translation.clear")
                            .accessibilityIdentifier("translator-clear")

                            .padding(8)
                        }
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("translator-input-container")
                TranslationShortcutsView()
                Button {
                    model.beginTranslation()
                } label: {
                    ZStack {
                        Text("outbox.quiet.sending").hidden().accessibilityHidden(true)
                        HStack(spacing: 8) {
                            if model.translationSubmitPending { TranslationPendingGlyph() }
                            Text(LocalizedStringKey(model.translationSubmitPending ? "outbox.quiet.sending" : "Übersetzen"))
                        }
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("translator-submit")
                    .disabled(model.translationSubmitPending || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.draft.unicodeScalars.count > 8000)
                if model.outboxStorageError { Text("outbox.storage").foregroundStyle(.red).accessibilityIdentifier("outbox-storage-error") }
                if let error = model.translatorError { ErrorNotice(text: error) }

            }.frame(maxWidth: 700).frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
            // One stable output footprint; retain the last result throughout submission.
            TranslationResultView(text: model.result?.translation ?? "", pending: model.translationPending)
                .listRowSeparator(.hidden)
            Section {
                // Initial/cache hydration and refresh are quiet. Only a completed load
                // can claim emptiness; saved rows remain visible through refresh/error.
                // No delayed task means no late spinner on navigation or owner changes.
                if model.historyLoadError == nil && model.history.isEmpty && model.historyPhase == .loaded { Text("Noch keine Übersetzungen.").foregroundStyle(.secondary) }
                ForEach(model.history) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text(verbatim: item.text).font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            if item.favorite {
                                Image(systemName: "star.fill").foregroundStyle(.yellow)
                                    .accessibilityLabel("history.favorite")
                                    .accessibilityIdentifier("history-star-\(item.id)")
                            }
                            if model.historyBusy(item.id) {
                                ProgressView().accessibilityLabel("history.updating")
                            }
                        }
                        Text(verbatim: item.translation).textSelection(.enabled)
                        Button { UIPasteboard.general.string = item.translation } label: {
                            Label("translation.copy", systemImage: "doc.on.doc").labelStyle(.iconOnly).frame(width: 44, height: 44)
                        }.buttonStyle(.borderless).accessibilityIdentifier("history-copy-\(item.id)")
                        if let error = model.historyErrors[item.id] { ErrorNotice(text: error) }
                    }.frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("history-row-\(item.id)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // Red styling without SwiftUI's destructive-role optimistic row removal:
                            // the row must remain present until the server acknowledges deletion.
                            Button { model.deleteHistory(item) } label: {
                                Label("history.delete", systemImage: "trash")
                            }.tint(.red).accessibilityIdentifier("history-delete-\(item.id)")
                                .disabled(!model.session.canWrite || model.historyBusy(item.id))
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button { model.toggleHistoryFavorite(item) } label: {
                                Label(LocalizedStringKey(item.favorite ? "history.unfavorite" : "history.addFavorite"), systemImage: item.favorite ? "star.slash" : "star")
                            }.tint(.orange)
                                .accessibilityIdentifier("history-favorite-\(item.id)")
                                .disabled(!model.session.canWrite || model.historyBusy(item.id))
                        }
                }
                // Dataset failure belongs after existing rows, never above them
                // or duplicated in the translation form. Retry remains available.
                if let error = model.historyLoadError {
                    Text(error).foregroundStyle(.secondary).accessibilityIdentifier("history-load-error")
                    Button("podcast.retry") { Task { await model.refreshTranslator() } }
                        .accessibilityIdentifier("history-retry")
                }
            } header: { Text("Dein Verlauf").font(.headline).textCase(nil) }
        }

        .listStyle(.plain)
        .onChange(of: model.translationPending) { _, pending in
            if pending { UIAccessibility.post(notification: .announcement, argument: AppL10n.text("outbox.quiet.sending")) }
        }
        .onChange(of: showPending) { _, presented in
            if presented { restoreInputFocus = inputFocused; inputFocused = false }
            else if restoreInputFocus { inputFocused = true; restoreInputFocus = false }
        }
        // Let the final result/history controls scroll clear of floating tabs.
        .safeAreaPadding(.bottom, 24)
        .environment(\.layoutDirection, .leftToRight)
        .scrollDismissesKeyboard(.interactively)
        .task { model.loadTranslationOutbox(); model.loadShortcuts() }
    }
}

struct PendingTranslationsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    private var items: [TranslationOutbox.Item] {
        model.outbox.items.filter { ![.completed, .cancelled].contains($0.state) }
    }
    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text(verbatim: item.text).lineLimit(3).textSelection(.enabled)
                            Spacer(minLength: 8)
                            if item.state != .sending {
                                Menu {
                                    if item.state == .queued {
                                        Button("outbox.stopWaiting", role: .destructive) { model.removeTranslation(item.id) }
                                    }
                                    Button("outbox.deleteLocal", role: .destructive) { model.removeTranslation(item.id, delete: true) }
                                } label: {
                                    Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
                                }.accessibilityLabel("outbox.actions")
                                    .accessibilityIdentifier("translation-actions")
                            }
                        }
                        Text(LocalizedStringKey(item.state == .sending ? "outbox.quiet.sending" : item.state == .queued ? "outbox.quiet.saved" : "outbox.quiet.failed"))
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let notice = model.translationCheckNotices[item.id] {
                            Text(LocalizedStringKey(notice)).font(.footnote).foregroundStyle(.secondary)
                        }
                        if item.state == .needsDecision || item.failure == .server {
                            Button("outbox.check") { Task { await model.checkTranslation(item.id) } }
                                .disabled(model.checkingTranslations.contains(item.id))
                                .accessibilityIdentifier("translation-check")
                        } else if item.state != .sending {
                            if item.failure == .provider {
                                NavigationLink("chatgpt.connect") { ChatGPTConnectionView() }
                            }
                            Button("outbox.send") { Task { await model.retryTranslation(item.id) } }
                                .accessibilityIdentifier("translation-send")
                        }
                    }.padding(.vertical, 4)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("pending-item-" + item.id.uuidString)
                }
                if items.isEmpty { Text("outbox.nonePending").foregroundStyle(.secondary) }
            }
            .navigationTitle("outbox.pending")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("outbox.done") { dismiss() }.accessibilityIdentifier("pending-done")
                }
            }
        }.presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }
}

private struct TranslationPendingGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if reduceMotion { Image(systemName: "hourglass") }
            else { ProgressView().controlSize(.small) }
        }.accessibilityHidden(true)
    }
}

private struct TranslationPendingPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let empty: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    if empty {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(0..<3) { index in
                                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                                    .frame(width: max(0, geometry.size.width - 32) * [1.0, 0.85, 0.62][index], height: 12)
                            }
                        }.padding(16).padding(.trailing, 52)
                    }
                    if !reduceMotion {
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        LinearGradient(colors: [.clear, .primary.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geometry.size.width)
                            .offset(x: geometry.size.width * (phase * 2 - 1))
                    }
                }.clipped()
            }
        }.clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear {
            #if targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["KM_SIMULATOR_SESSION_FIXTURE"] != nil {
                print("TRANSLATE_MOTION reduce=\(reduceMotion) system=\(UIAccessibility.isReduceMotionEnabled)")
            }
            #endif
        }
    }
}

private struct TranslationResultView: View {
    let text: String
    var pending = false
    @State private var copied = false
    @State private var confirmationID = UUID()
    @State private var pasteboardCheck = ""

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(verbatim: text).font(.title3).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("translation-result-text")
            // Reserve the lane even when there is no copyable output.
            Group {
                if !text.isEmpty {
                Button {
                    UIPasteboard.general.string = text
                    copied = true; confirmationID = UUID()
                    #if targetEnvironment(simulator)
                    if ProcessInfo.processInfo.environment["KM_SIMULATOR_SESSION_FIXTURE"] == "translation-copy" {
                        pasteboardCheck = UIPasteboard.general.string == SimulatorSessionFixture.copyTranslation ? "pasteboard-exact" : "pasteboard-mismatch"
                    }
                    #endif
                } label: {
                    Label(copied ? "translation.copied" : "translation.copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(pending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("translation-copy")
                .accessibilityValue(Text(verbatim: pasteboardCheck))
                } else {
                    Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                }
            }
        }
        // Preserve the previous 44 + 8 + 70 footprint through empty/pending states.
        .frame(minHeight: 122, alignment: .topLeading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            if pending { TranslationPendingPanel(empty: text.isEmpty).allowsHitTesting(false).accessibilityHidden(true) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("translation-output")
        .accessibilityValue(Text(verbatim: pending ? AppL10n.text("outbox.quiet.sending") : ""))
        .task(id: confirmationID) {
            guard copied else { return }
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled else { return }
            copied = false
        }
        .onChange(of: text) { copied = false; confirmationID = UUID(); pasteboardCheck = "" }
    }
}
