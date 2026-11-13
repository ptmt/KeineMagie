import SwiftUI
import UIKit
import KeineMagieCore

/// The signed-in landing screen is the real personal translator, not account setup.
struct TranslatorView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var inputFocused: Bool
    @ScaledMetric(relativeTo: .body) private var editorHeight = 112

    var body: some View {
        @Bindable var model = model
        List {

            VStack(alignment: .leading, spacing: 12) {
                Picker("Richtung", selection: $model.direction) {
                    ForEach(TranslationDirection.allCases, id: \.self) { direction in
                        Text(verbatim: direction.compactTitle).tag(direction)
                            .accessibilityLabel(Text(LocalizedStringKey("direction." + direction.rawValue)))
                    }
                }.pickerStyle(.segmented).accessibilityIdentifier("translator-direction")
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
                    inputFocused = false
                    Task { await model.translate() }
                } label: {
                    Text("Übersetzen").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("translator-submit")
                    .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.draft.unicodeScalars.count > 8000)
                if model.session.canWrite && model.provider == nil {
                    if model.refreshing || model.historyPhase == .idle {
                        // Quiet status while checking; no spinner competing with saved history.
                        Text("Verbindung prüfen")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        Button("Verbindung prüfen") { Task { await model.refreshTranslator() } }
                    }
                } else if model.session.canWrite && model.provider?.connected != true {
                    NavigationLink { ChatGPTConnectionView() } label: {
                        Label("chatgpt.connect", systemImage: "link.badge.plus")
                            .font(.callout)
                    }
                }
                if model.outboxStorageError { Text("outbox.storage").foregroundStyle(.red).accessibilityIdentifier("outbox-storage-error") }
                if let error = model.translatorError { ErrorNotice(text: error) }

            }.frame(maxWidth: 700).frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
            if !model.outbox.items.isEmpty {
                Section("outbox.title") {
                    Text("outbox.foreground").font(.caption).foregroundStyle(.secondary)
                    ForEach(model.outbox.items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: item.text).lineLimit(3).textSelection(.enabled)
                            Text(LocalizedStringKey("outbox.state." + item.state.rawValue)).font(.caption)
                            if let failure = item.failure {
                                Text(LocalizedStringKey("outbox.error." + failure.rawValue)).font(.caption).foregroundStyle(.secondary)
                            }
                            HStack {
                                if [.failed, .needsDecision, .queued].contains(item.state) {
                                    Button("outbox.retry") { Task { await model.retryTranslation(item.id) } }.buttonStyle(.borderless)
                                }
                                if item.failure == .provider {
                                    NavigationLink("chatgpt.connect") { ChatGPTConnectionView() }
                                }
                                if [.queued, .sending, .failed, .needsDecision].contains(item.state) {
                                    Button("outbox.cancel") { model.removeTranslation(item.id) }.buttonStyle(.borderless)
                                }
                                Button("history.delete", role: .destructive) { model.removeTranslation(item.id, delete: true) }.buttonStyle(.borderless)
                            }
                        }.accessibilityIdentifier("outbox-item-" + item.id.uuidString)
                    }
                }
            }
            if let result = model.result {
                TranslationResultView(text: result.translation)
                    .listRowSeparator(.hidden)
            }
            Section {
                // Initial/cache hydration and refresh are quiet. Only a completed load
                // can claim emptiness; saved rows remain visible through refresh/error.
                // No delayed task means no late spinner on navigation or owner changes.
                if let error = model.historyLoadError {
                    Text(error).foregroundStyle(.secondary)
                    Button("podcast.retry") { Task { await model.refreshTranslator() } }
                } else if model.history.isEmpty && model.historyPhase == .loaded { Text("Noch keine Übersetzungen.").foregroundStyle(.secondary) }
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
            } header: { Text("Dein Verlauf").font(.headline).textCase(nil) }
        }

        .listStyle(.plain)
        .environment(\.layoutDirection, .leftToRight)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { ChatGPTConnectionView() } label: {
                    Image(systemName: "person.crop.circle")
                }.accessibilityLabel("Konto")
            }
        }
        .task { model.loadTranslationOutbox(); model.loadShortcuts() }
    }
}

private struct TranslationResultView: View {
    let text: String
    @State private var copied = false
    @State private var confirmationID = UUID()
    @State private var pasteboardCheck = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer(minLength: 0)
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
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("translation-copy")
                .accessibilityValue(Text(verbatim: pasteboardCheck))
            }
            Text(verbatim: text).font(.title3).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .task(id: confirmationID) {
            guard copied else { return }
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled else { return }
            copied = false
        }
        .onChange(of: text) { copied = false; confirmationID = UUID(); pasteboardCheck = "" }
    }
}
